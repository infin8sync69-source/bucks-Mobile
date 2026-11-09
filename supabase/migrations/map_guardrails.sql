-- Phase 0 of the "Recommended here" map (reports/Map feed for Gen Z India.md): the guardrails that must exist before any post is
-- shown as a pin. Nothing here draws a map; it decides which posts may ever appear on one, and where.
--   1. Consent: a post goes on the map only while its author has said yes ("Show my posts on the map"), separately from posting.
--      Saying no later removes every past pin at once (the check is made at read time, not copied).
--   2. Never raw GPS: a pin sits on a public place, never on where the phone was. A post tagged to a live Bucks page uses that page's
--      point; otherwise it snaps to the nearest India Post locality centre (within 10 km) and waits 45 minutes before it can show.
--   3. No minors: posts by anyone under 18 (or whose age Bucks doesn't know) never go on the map (DPDP Act s.9(3)).
--   4. Takedown: the author can remove any post from the map; anyone can report "this shows my home or me", which takes it off the
--      map at once until staff look; staff can hide a post from the map.
--   5. Kill switches: one for the whole map (setting map_enabled) and one per district (map_kill_zones), for orders or unrest.
--   6. One author can't fill a map: at most 3 of their posts per place show (map_pins applies it).
-- map_pins is the only way to read the map; it returns places, never authors.
--   7. Posts stop keeping the phone's exact GPS: the server snaps first, then stores the point rounded to about 1 km (0.01 degree),
--      which is all the feed's "near me" needs. Existing posts are snapped and rounded once, at the end of this file.
-- Safe to run more than once. Apply after places.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

insert into public.settings (key, value) values ('map_enabled', 1) on conflict (key) do nothing;

-- ---------- 1. consent ----------
create table if not exists public.map_consent (
  profile_id uuid primary key references public.profiles on delete cascade,
  allowed    boolean not null default false,
  changed_at timestamptz not null default now()
);
alter table public.map_consent enable row level security;
drop policy if exists map_consent_own on public.map_consent;
create policy map_consent_own on public.map_consent for select to authenticated using (profile_id = public.me());
revoke all on public.map_consent from public, anon;
grant select on public.map_consent to authenticated;

-- Yes or no to "Show my posts on the map". Minors can't say yes.
create or replace function public.set_map_consent(p_allowed boolean) returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'sign in first'; end if;
  if p_allowed and age_band_of(me()) <> 'ADULT' then raise exception 'posts show on the map only for people 18 and over'; end if;
  insert into map_consent (profile_id, allowed, changed_at) values (me(), coalesce(p_allowed, false), now())
    on conflict (profile_id) do update set allowed = excluded.allowed, changed_at = now();
  return coalesce(p_allowed, false);
end $$;

-- ---------- 2. where a post may go: a public place, decided by the server ----------
alter table public.posts add column if not exists place_listing uuid references public.listings on delete set null;  -- "I'm at ..." tag
alter table public.posts add column if not exists map_point geography(point, 4326);   -- the place, never the phone
alter table public.posts add column if not exists map_place text;                     -- LISTING or LOCALITY
alter table public.posts add column if not exists map_place_id text;                  -- listing id or locality id
alter table public.posts add column if not exists map_district text;
alter table public.posts add column if not exists map_after timestamptz;              -- earliest time it may show
alter table public.posts add column if not exists map_off_by text check (map_off_by in ('AUTHOR', 'REPORT', 'STAFF'));
create index if not exists posts_map_point_idx on public.posts using gist (map_point) where map_point is not null;
-- The map columns are the server's: post_map_place recomputes or keeps them on every write, whatever a client sends.

create table if not exists public.map_kill_zones (
  district   text not null,
  state      text not null default '',
  reason     text not null default '',
  created_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  primary key (district, state)
);
alter table public.map_kill_zones enable row level security;
revoke all on public.map_kill_zones from public, anon, authenticated;

-- The nearest locality to a point (within 10 km): its id, district and state.
create or replace function public.nearest_locality(at geography) returns public.localities language sql stable security definer set search_path = public, extensions as $$
  select x.* from localities x
  where x.lat between st_y(at::geometry) - 0.1 and st_y(at::geometry) + 0.1 and x.lng between st_x(at::geometry) - 0.1 and st_x(at::geometry) + 0.1
    and st_dwithin(geo(x.lat, x.lng), at, 10000)
  order by st_distance(geo(x.lat, x.lng), at) limit 1
$$;

create or replace function public.post_map_place() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare l listings; x localities; staff_write boolean := current_setting('bucks.map_write', true) = 'on';
begin
  -- Only Bucks' own functions (which set bucks.map_write) change map_off_by; anything a client sends for these columns is ignored.
  if tg_op = 'UPDATE' then
    if not staff_write then new.map_off_by := old.map_off_by; end if;
    if new.place_listing is not distinct from old.place_listing and new.listing_id is not distinct from old.listing_id
       and new.location is not distinct from old.location and current_setting('bucks.map_backfill', true) is distinct from 'on' then
      new.map_point := old.map_point; new.map_place := old.map_place; new.map_place_id := old.map_place_id;
      new.map_district := old.map_district; new.map_after := old.map_after;
      return new;
    end if;
  elsif not staff_write then new.map_off_by := null;
  end if;
  new.map_point := null; new.map_place := null; new.map_place_id := null; new.map_district := null; new.map_after := null;
  -- A live page: the post tagged to one, or posted as one.
  select * into l from listings where id = coalesce(new.place_listing, new.listing_id) and status = 'LIVE' and location is not null;
  if found then
    x := nearest_locality(l.location);
    new.map_point := l.location; new.map_place := 'LISTING'; new.map_place_id := l.id::text;
    new.map_district := x.district; new.map_after := new.created_at;
  elsif new.location is not null then
    x := nearest_locality(new.location);
    if x.id is not null then
      new.map_point := geo(x.lat, x.lng); new.map_place := 'LOCALITY'; new.map_place_id := x.id::text;
      new.map_district := x.district; new.map_after := new.created_at + interval '45 minutes';
    end if;
  end if;
  -- Never keep where the phone was: the feed's "near me" only needs about a kilometre (0.01 degree).
  if new.location is not null then
    new.location := geo(round(st_y(new.location::geometry)::numeric, 2)::double precision, round(st_x(new.location::geometry)::numeric, 2)::double precision);
  end if;
  return new;
end $$;
drop trigger if exists post_map_place on public.posts;
create trigger post_map_place before insert or update on public.posts for each row execute function public.post_map_place();
revoke execute on function public.post_map_place() from public, anon, authenticated;
revoke execute on function public.nearest_locality(geography) from public, anon, authenticated;

-- ---------- 3 + 5. may this post be on the map now ----------
create or replace function public.post_on_map(p public.posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.map_point is not null and p.map_off_by is null and p.deleted_at is null and p.visibility in ('PUBLIC', 'LOCAL')
     and p.map_after <= now()
     and coalesce((select value from settings where key = 'map_enabled'), 1) = 1
     and age_band_of(p.author_id) = 'ADULT'
     and exists (select 1 from map_consent c where c.profile_id = p.author_id and c.allowed)
     and exists (select 1 from profiles a where a.id = p.author_id and a.status = 'ACTIVE')
     and not exists (select 1 from map_kill_zones k where k.district = p.map_district)
$$;
revoke execute on function public.post_on_map(public.posts) from public, anon, authenticated;

-- ---------- 4. taking a post off the map ----------
-- The author: this one post, or (p_back) put it back.
create or replace function public.set_post_on_map(p_post uuid, p_on boolean) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform set_config('bucks.map_write', 'on', true);
  update posts set map_off_by = case when p_on then null else 'AUTHOR' end
   where id = p_post and author_id = me() and (map_off_by is null or map_off_by = 'AUTHOR');
  if not found then raise exception 'post not found, or taken off the map by Bucks'; end if;
end $$;

-- Anyone who can see it: "this shows my home or me". Off the map now, and a report for staff.
create or replace function public.report_map_location(p_post uuid, p_detail text default '') returns void language plpgsql security definer set search_path = public, extensions as $$
declare p posts;
begin
  if me() is null then raise exception 'sign in first'; end if;
  select * into p from posts where id = p_post;
  if not found or not can_see_post(p) then raise exception 'post not found'; end if;
  perform set_config('bucks.map_write', 'on', true);
  update posts set map_off_by = 'REPORT' where id = p_post and map_off_by is distinct from 'STAFF';
  insert into reports (reporter_id, target_kind, target_id, target_owner, reason, detail)
  values (me(), 'POST', p_post, p.author_id, 'OTHER', left('MAP LOCATION: ' || coalesce(p_detail, ''), 500));
end $$;

-- Staff: hide, or put back after a review.
create or replace function public.staff_post_map(p_post uuid, p_on boolean) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  perform set_config('bucks.map_write', 'on', true);
  update posts set map_off_by = case when p_on then null else 'STAFF' end where id = p_post;
  if not found then raise exception 'post not found'; end if;
end $$;

-- Staff: stop or restart the map in a district (the district name as India Post spells it).
create or replace function public.staff_map_district(p_district text, p_off boolean, p_reason text default '') returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  if p_off then insert into map_kill_zones (district, reason, created_by) values (btrim(p_district), coalesce(p_reason, ''), me()) on conflict (district, state) do update set reason = excluded.reason;
  else delete from map_kill_zones where district = btrim(p_district); end if;
end $$;

-- ---------- my posts and the map ----------
-- What I've agreed to and which of my posts are (or would be) on the map, for the settings page.
create or replace function public.my_map_posts() returns table (id uuid, body text, place text, on_map boolean, off_by text, shows_from timestamptz, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, left(p.body, 120),
         case p.map_place when 'LISTING' then (select title from listings where id = p.map_place_id::uuid)
                          when 'LOCALITY' then (select name || ', ' || district from localities where id = p.map_place_id::bigint) end,
         post_on_map(p), p.map_off_by, p.map_after, p.created_at
  from posts p where p.author_id = me() and p.deleted_at is null and p.map_point is not null
  order by p.created_at desc limit 100
$$;

-- ---------- 6. the only read: places with counts, never authors ----------
-- Pins in a box (south, west, north, east): one per place, with how many posts and recommend / not-recommend votes count.
-- Each author counts at most 3 posts per place. Phase 1 adds ranking modes and the For you hand-off on top of this.
create or replace function public.map_pins(s double precision, w double precision, n double precision, e double precision, lim int default 200)
returns table (place text, place_id text, name text, lat double precision, lng double precision, posts int, up int, down int, latest timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  with ok as (
    select p.*, row_number() over (partition by p.map_place_id, p.author_id order by p.up - p.down desc, p.created_at desc) k
    from posts p
    where p.map_point is not null and st_intersects(p.map_point, st_makeenvelope(w, s, e, n, 4326)::geography)
      and post_on_map(p) and not blocked_between(me(), p.author_id)
  )
  select ok.map_place, ok.map_place_id,
         coalesce(max(l.title), max(x.name)),
         st_y(min(ok.map_point::geometry)), st_x(min(ok.map_point::geometry)),
         count(*)::int, sum(ok.up)::int, sum(ok.down)::int, max(ok.created_at)
  from ok left join listings l on ok.map_place = 'LISTING' and l.id::text = ok.map_place_id
          left join localities x on ok.map_place = 'LOCALITY' and x.id::text = ok.map_place_id
  where ok.k <= 3 and me() is not null
  group by ok.map_place, ok.map_place_id
  order by sum(ok.up) - sum(ok.down) desc, max(ok.created_at) desc
  limit greatest(1, least(coalesce(lim, 200), 500))
$$;

-- ---------- grants ----------
revoke all on function public.set_map_consent(boolean), public.set_post_on_map(uuid, boolean), public.report_map_location(uuid, text),
  public.staff_post_map(uuid, boolean), public.staff_map_district(text, boolean, text), public.my_map_posts(),
  public.map_pins(double precision, double precision, double precision, double precision, int) from public, anon;
grant execute on function public.set_map_consent(boolean), public.set_post_on_map(uuid, boolean), public.report_map_location(uuid, text),
  public.staff_post_map(uuid, boolean), public.staff_map_district(text, boolean, text), public.my_map_posts(),
  public.map_pins(double precision, double precision, double precision, double precision, int) to authenticated;

-- ---------- 7. existing posts: snap to a place, then round the stored point (one-time; a rerun changes nothing) ----------
select set_config('bucks.map_backfill', 'on', true);
update public.posts set location = location where location is not null and map_point is null;
select set_config('bucks.map_backfill', 'off', true);
