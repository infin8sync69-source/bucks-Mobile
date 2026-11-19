-- The demand loop (docs/DISCOVERY_ALGORITHMS.md §4.6 and §13.7): a search that finds nothing becomes a reason to find a provider.
--
-- 1. "Tell me when one joins": want_notify stores what the person searched for and the ~2 km cell they searched around (never their
--    exact position). Every 30 minutes wanted_match runs each open request through search_listings, and when a live page in range
--    answers it, the person gets one notification (kind WANTED_FOUND, opening the page) and the request closes. A request is checked
--    for 90 days. People see and cancel their own requests (my_wanted, cancel_wanted); the rows go with the account.
-- 2. Demand by area, for staff (demand_report): what people are waiting for, what keeps finding nothing, and what was found, by area
--    (the nearest India Post locality), so recruiting goes where people already search. Counts only, never who.
-- Safe to run more than once. Apply after discovery_log.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

insert into public.settings (key, value) values
  ('wanted_days', 90),          -- a request is matched for this long
  ('wanted_max_open', 20),      -- open requests per person
  ('rate_wanted_per_hour', 30)  -- want_notify calls per person per hour
on conflict (key) do nothing;

create table if not exists public.wanted (
  id            uuid primary key default public.uuid_v7(),
  profile_id    uuid not null references public.profiles on delete cascade,
  q             text not null check (length(q) between 1 and 100),
  q_norm        text not null check (length(q_norm) between 1 and 200),
  cell          text not null check (length(cell) <= 24),          -- '12.18,75.92'
  at_point      geography(point, 4326) not null,                   -- the cell's centre, never where the person stood
  radius_m      int not null check (radius_m between 1000 and 50000),
  created_at    timestamptz not null default now(),
  checked_at    timestamptz,
  found_listing uuid references public.listings on delete set null,
  notified_at   timestamptz,
  cancelled_at  timestamptz
);
create unique index if not exists wanted_one_open on public.wanted (profile_id, q_norm, cell) where notified_at is null and cancelled_at is null;
create index if not exists wanted_open on public.wanted (checked_at nulls first) where notified_at is null and cancelled_at is null;
create index if not exists wanted_profile on public.wanted (profile_id, created_at desc);
alter table public.wanted enable row level security;   -- read and written through the functions below
revoke all on public.wanted from public, anon, authenticated;

-- Area names for the cells: the nearest locality within about 5 km. A plain (lat, lng) index keeps the box lookup cheap.
create index if not exists localities_lat_lng on public.localities (lat, lng);
create or replace function public.demand_area(p_cell text) returns text language sql stable security definer set search_path = public, extensions as $$
  with c as (select split_part(p_cell, ',', 1)::double precision la, split_part(p_cell, ',', 2)::double precision lo where p_cell ~ '^-?\d+\.\d+,-?\d+\.\d+$')
  select coalesce((select l.name || case when l.district <> '' then ', ' || l.district else '' end
                   from localities l, c where l.lat between c.la - 0.05 and c.la + 0.05 and l.lng between c.lo - 0.05 and c.lo + 0.05
                   order by (l.lat - c.la) ^ 2 + (l.lng - c.lo) ^ 2 limit 1), p_cell)
$$;

-- ---------- the person's side ----------
-- Ask to be told when a page that answers q goes live within radius_m of (lat, lng). Returns the request's id; asking again for the
-- same words in the same area keeps the one request.
create or replace function public.want_notify(q text, lat double precision, lng double precision, radius_m int default 10000) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  my uuid := me(); t text := nullif(btrim(left(discovery_mask(q), 100)), ''); k text; c text := discovery_cell(lat, lng); rid uuid;
begin
  if my is null then raise exception 'sign in first' using errcode = '42501'; end if;
  k := nullif(btrim(search_norm(t)), '');
  if t is null or k is null then raise exception 'say what you are looking for' using errcode = 'P0001'; end if;
  if c is null then raise exception 'a location is needed' using errcode = 'P0001'; end if;
  select id into rid from wanted where profile_id = my and q_norm = k and cell = c and notified_at is null and cancelled_at is null;
  if rid is not null then return rid; end if;
  perform rate_hit('wanted');
  if (select count(*) from wanted where profile_id = my and notified_at is null and cancelled_at is null
        and created_at > now() - make_interval(days => coalesce(setting('wanted_days'), 90)::int)) >= coalesce(setting('wanted_max_open'), 20) then
    raise exception 'you are already waiting for % searches; remove one first', coalesce(setting('wanted_max_open'), 20)::int using errcode = 'P0001';
  end if;
  insert into wanted (profile_id, q, q_norm, cell, at_point, radius_m)
  values (my, t, k, c, geo(split_part(c, ',', 1)::double precision, split_part(c, ',', 2)::double precision),
          least(greatest(coalesce(radius_m, 10000), 1000), 50000))
  returning id into rid;
  return rid;
end $$;

-- My requests: waiting, or found in the last 90 days.
create or replace function public.my_wanted()
returns table (id uuid, q text, area text, radius_m int, created_at timestamptz, notified_at timestamptz, found_listing uuid, found_title text)
language sql stable security definer set search_path = public, extensions as $$
  select w.id, w.q, demand_area(w.cell), w.radius_m, w.created_at, w.notified_at, w.found_listing, l.title
  from wanted w left join listings l on l.id = w.found_listing and l.status = 'LIVE'
  where w.profile_id = me() and w.cancelled_at is null
    and ((w.notified_at is null and w.created_at > now() - make_interval(days => coalesce(setting('wanted_days'), 90)::int))
         or w.notified_at > now() - interval '90 days')
  order by w.notified_at is null desc, w.created_at desc
$$;

create or replace function public.cancel_wanted(p_id uuid) returns boolean
language sql security definer set search_path = public, extensions as $$
  with x as (update wanted set cancelled_at = now() where id = p_id and profile_id = me() and cancelled_at is null and notified_at is null returning 1)
  select exists (select 1 from x)
$$;

-- An account that is deleted takes its requests with it.
create or replace function public.wanted_forget() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from wanted where profile_id = new.id;
  return new;
end $$;
drop trigger if exists wanted_forget on public.profiles;
create trigger wanted_forget after update of status on public.profiles
  for each row when (new.status = 'DELETED' and old.status is distinct from 'DELETED') execute function public.wanted_forget();

-- ---------- the job: every 30 minutes ----------
-- Checks the open requests that were checked longest ago (at most p_limit of them), with the same search people use, from the cell's
-- centre and within the radius they searched. A page counts only in range (a shop that ships India-wide from far away doesn't), never
-- the person's own page, never across a block. One notification, then the request closes. Old rows are purged here too.
create or replace function public.wanted_match(p_limit int default 200) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare w record; hit_id uuid; hit_title text; n int := 0; keep_days int := coalesce(setting('wanted_days'), 90)::int;
begin
  for w in
    select * from wanted
    where notified_at is null and cancelled_at is null and created_at > now() - make_interval(days => keep_days)
    order by checked_at nulls first, created_at
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
    for update skip locked
  loop
    update wanted set checked_at = now() where id = w.id;
    select s.id, s.title into hit_id, hit_title
    from search_listings(w.q, st_y(w.at_point::geometry), st_x(w.at_point::geometry), w.radius_m, null, 10) s
    where s.distance_m is not null and s.distance_m <= w.radius_m and s.owner_id <> w.profile_id and not blocked_between(w.profile_id, s.owner_id)
    limit 1;
    if hit_id is not null then
      update wanted set notified_at = now(), found_listing = hit_id where id = w.id;
      perform push_note(w.profile_id, 'WANTED_FOUND', left(hit_title, 90) || ' is on Bucks',
                        'You asked to hear when "' || left(w.q, 60) || '" joins near you. Tap to see it.', 'l/' || hit_id);
      n := n + 1;
    end if;
  end loop;
  delete from wanted where created_at < now() - make_interval(days => keep_days + 90) or (notified_at is not null and notified_at < now() - interval '90 days')
                          or (cancelled_at is not null and cancelled_at < now() - interval '30 days');
  return n;
end $$;

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('bucks-wanted-match', '*/30 * * * *', 'select public.wanted_match()');
  end if;
end $$;

-- ---------- staff: where people search and find nothing ----------
-- What people are waiting for (requests), what keeps finding nothing (logged searches of adults with usage statistics on), and what
-- was found in the last p_days, by area. Counts only, never who.
create or replace function public.demand_report(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare d int := least(greatest(coalesce(p_days, 30), 1), 90); r jsonb;
begin
  if not is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  select jsonb_build_object(
    'days', d,
    'waiting', (select coalesce(jsonb_agg(x order by x.people desc, x.since), '[]') from (
        select q_norm q, demand_area(cell) area, count(distinct profile_id) people, min(created_at)::date since
        from wanted where notified_at is null and cancelled_at is null and created_at > now() - make_interval(days => coalesce(setting('wanted_days'), 90)::int)
        group by q_norm, cell order by count(distinct profile_id) desc, min(created_at) limit 50) x),
    'nothing_found', (select coalesce(jsonb_agg(x order by x.people desc, x.searches desc), '[]') from (
        select s.q_norm q, demand_area(s.cell) area, count(*) searches, count(distinct s.viewer) people
        from discovery_settled(now() - make_interval(days => d), now()) s
        where s.surface = 'SEARCH' and s.n_results = 0 and s.cell <> '' and discovery_safe_text(s.q_norm)
        group by s.q_norm, s.cell order by count(distinct s.viewer) desc, count(*) desc limit 50) x),
    'found', (select coalesce(jsonb_agg(x order by x.found desc), '[]') from (
        select w.q_norm q, demand_area(w.cell) area, l.title page, w.notified_at::date found,
               extract(day from w.notified_at - w.created_at)::int days_waited
        from wanted w left join listings l on l.id = w.found_listing
        where w.notified_at > now() - make_interval(days => d) order by w.notified_at desc limit 50) x))
  into r;
  return r;
end $$;

-- ---------- grants ----------
revoke all on function public.want_notify(text, double precision, double precision, int), public.my_wanted(), public.cancel_wanted(uuid),
                       public.demand_report(int) from public, anon;
grant execute on function public.want_notify(text, double precision, double precision, int), public.my_wanted(), public.cancel_wanted(uuid),
                          public.demand_report(int) to authenticated;   -- demand_report checks is_staff()
revoke all on function public.wanted_match(int), public.wanted_forget(), public.demand_area(text) from public, anon, authenticated;
