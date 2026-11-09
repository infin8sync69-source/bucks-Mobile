-- Security hardening (audit, November 2026). Every rule is tunable in public.settings (0 switches it off), so the older scenario
-- suites can run with them relaxed (supabase/tests/run_all.sh) and security_hardening_scenarios.sql tests them switched on.
--
--   1. Drivers on the map: online_drivers_near returns positions snapped to a ~300 m grid, no name or plate, and an id that is a
--      per-caller, per-hour pseudonym (enough to draw and animate pins, useless for following one driver). Rate-limited per caller.
--      Dispatch (can_claim, ringing, task_driver after a match) keeps using exact positions.
--   2. Skill and driver pages: listings.location is stored snapped to a ~500 m grid for SKILL and DRIVER (often someone's home);
--      the exact point the owner sent is kept in listing_exact_location (owner only). Every RPC that measures distance to a listing
--      (search_listings, suggest_listings, jobs_near, recommend) therefore only ever sees the grid point. BUSINESS and ASSET stay exact.
--   3. Recommendations: a recommend QR token works once (one recommender), an account whose home moved more than 500 m can't
--      recommend for N days, and a page takes at most N recommendations an hour.
--   4. Rate limits: one per-person hourly counter (rate_events) for posts, comments, Moments, messages, sync requests, reports,
--      feedback posts, new pages and ride requests. Deleting or cancelling doesn't give the count back. Writes with no caller (cron,
--      triggers run by the system) are never limited.
--   5. profiles.auth_uid (the Firebase id) is no longer readable by other people. search_people and suggest_people already respect
--      discoverable = false; the profiles table itself stays readable so names show in chats, feeds and reviews.
--   6. Reports keep a snapshot of what was reported, so an edit or delete by the author can't remove the evidence.
--   7. Ride fares: the trip length the app sends is accepted down to 1.2x the straight-line distance (was 0.8x).

insert into public.settings (key, value) values
  ('rate_limits_on', 1),
  ('rate_posts_per_hour', 30), ('rate_comments_per_hour', 120), ('rate_moments_per_hour', 30), ('rate_messages_per_hour', 600),
  ('rate_syncs_per_hour', 60), ('rate_reports_per_hour', 30), ('rate_feedback_per_hour', 10), ('rate_listings_per_hour', 10),
  ('rate_rides_per_hour', 15), ('rate_drivers_map_per_hour', 720),
  ('recommend_per_listing_per_hour', 10), ('recommend_home_cooldown_days', 7),
  ('listing_blur_m', 500), ('drivers_map_blur_m', 300),
  ('ride_min_km_factor', 1.2)
on conflict (key) do nothing;

-- ---------- 4. the shared rate limiter ----------

create table if not exists public.rate_events (
  profile_id uuid not null references public.profiles on delete cascade,
  bucket     text not null,
  at         timestamptz not null default now()
);
create index if not exists rate_events_lookup on public.rate_events (profile_id, bucket, at);
alter table public.rate_events enable row level security;
revoke all on public.rate_events from anon, authenticated;

-- Counts one [bucket] action for the caller and refuses it past settings.rate_<bucket>_per_hour. No caller, the master switch off,
-- or no cap set: allowed and not counted.
create or replace function public.rate_hit(p_bucket text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); cap numeric := setting('rate_' || p_bucket || '_per_hour'); n int;
begin
  if my is null or coalesce(setting('rate_limits_on'), 1) < 1 or cap is null or cap <= 0 then return; end if;
  select count(*) into n from rate_events where profile_id = my and bucket = p_bucket and at > now() - interval '1 hour';
  if n >= cap then
    raise exception 'slow down: you have reached the limit for this in the last hour; try again later' using errcode = 'P0001';
  end if;
  insert into rate_events (profile_id, bucket) values (my, p_bucket);
  if random() < 0.02 then delete from rate_events where profile_id = my and at < now() - interval '1 day'; end if;
end $$;

-- BEFORE INSERT trigger; TG_ARGV[0] is the bucket. Ride requests only count rides the caller asks for (deliveries a shop creates don't).
create or replace function public.rate_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare j jsonb;
begin
  -- Fields read through jsonb: PL/pgSQL resolves new.<field> even in a branch that doesn't run, and only tasks has these columns.
  if tg_table_name = 'tasks' then
    j := to_jsonb(new);
    if j->>'type' is distinct from 'RIDE' or (j->>'requester_id')::uuid is distinct from me() then return new; end if;
  end if;
  perform rate_hit(tg_argv[0]);
  return new;
end $$;

revoke execute on function public.rate_hit(text), public.rate_guard() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values ('posts', 'posts'), ('post_comments', 'comments'), ('moments', 'moments'), ('messages', 'messages'),
                                 ('syncs', 'syncs'), ('reports', 'reports'), ('feedback_posts', 'feedback'), ('listings', 'listings'),
                                 ('tasks', 'rides')) v(t, b) loop
    if to_regclass('public.' || r.t) is not null then
      execute format('drop trigger if exists a2_rate_limit on public.%I', r.t);
      execute format('create trigger a2_rate_limit before insert on public.%I for each row execute function public.rate_guard(%L)', r.t, r.b);
    end if;
  end loop;
end $$;

-- ---------- 1. drivers on the map ----------

create or replace function public.online_drivers_near(p_lat double precision, p_lng double precision, radius_m integer default 5000)
returns table (profile_id uuid, kind text, lat double precision, lng double precision, name text, model text, plate text, up integer, down integer)
language plpgsql volatile security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare blur double precision := coalesce(setting('drivers_map_blur_m'), 300) / 111320.0; my uuid := me();
begin
  perform rate_hit('drivers_map');
  return query
  select case when blur > 0 then md5(p.profile_id::text || coalesce(my::text, '') || to_char(date_trunc('hour', now()), 'YYYYMMDDHH24'))::uuid else p.profile_id end,
         p.kind,
         case when blur > 0 then st_y(st_snaptogrid(p.location::geometry, blur)) else st_y(p.location::geometry) end,
         case when blur > 0 then st_x(st_snaptogrid(p.location::geometry, blur)) else st_x(p.location::geometry) end,
         case when blur > 0 then '' else pr.name end,
         v.model,
         case when blur > 0 then '' else '••' || right(v.plate, 4) end,
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0)
  from driver_presence p
  join profiles pr on pr.id = p.profile_id and pr.status = 'ACTIVE'
  join vehicles v on v.id = p.vehicle_id and v.status = 'ACTIVE'
  left join listings l on l.owner_id = p.profile_id and l.kind = 'DRIVER'
  where p.online and p.location is not null
    and p.updated_at > now() - make_interval(secs => dispatch_cfg('claim_fresh_seconds', 180)::double precision)
    and p.profile_id is distinct from my
    and st_dwithin(p.location, geo(p_lat, p_lng), least(greatest(coalesce(radius_m, 5000), 0), 10000))
  order by st_distance(p.location, geo(p_lat, p_lng))
  limit 30;
end $$;

-- ---------- 2. skill and driver pages: a grid point, not the home ----------

create table if not exists public.listing_exact_location (
  -- Deferred: the copy is written by a BEFORE INSERT trigger, before the listing row itself exists.
  listing_id uuid primary key references public.listings on delete cascade deferrable initially deferred,
  location   geography(Point, 4326) not null,
  updated_at timestamptz not null default now()
);
alter table public.listing_exact_location enable row level security;
drop policy if exists listing_exact_location_owner on public.listing_exact_location;
create policy listing_exact_location_owner on public.listing_exact_location for select to authenticated
  using (public.can_manage_listing(listing_id) or (select public.is_staff()));
revoke all on public.listing_exact_location from anon, authenticated;
grant select on public.listing_exact_location to authenticated;

-- Runs before every other listing trigger (name sorts first), so the reverify and recommendation-pruning triggers compare grid
-- points: re-saving a page from the same spot is no change.
create or replace function public.listing_blur_location() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare blur double precision := coalesce(setting('listing_blur_m'), 500) / 111320.0;
begin
  if blur <= 0 or new.kind not in ('SKILL', 'DRIVER') or new.location is null then return new; end if;
  if tg_op = 'UPDATE' and st_astext(new.location) = st_astext(old.location) then return new; end if;
  new.location := st_snaptogrid(new.location::geometry, blur)::geography;
  return new;
end $$;

create or replace function public.listing_keep_exact() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.kind in ('SKILL', 'DRIVER') and new.location is not null and coalesce(setting('listing_blur_m'), 500) > 0 then
    insert into listing_exact_location (listing_id, location) values (new.id, new.location)
    on conflict (listing_id) do update set location = excluded.location, updated_at = now();
  end if;
  return new;
end $$;
revoke execute on function public.listing_blur_location(), public.listing_keep_exact() from public, anon, authenticated;

-- The exact copy is taken from the row as the owner sent it (BEFORE, ahead of the blur), then the blur replaces it.
drop trigger if exists listing_0_exact on public.listings;
create trigger listing_0_exact before insert or update of location, kind on public.listings for each row execute function public.listing_keep_exact();
drop trigger if exists listing_1_blur on public.listings;
create trigger listing_1_blur before insert or update of location, kind on public.listings for each row execute function public.listing_blur_location();

-- Existing skill and driver pages: keep the exact point privately, then snap. Recommendations are not pruned by this one-off move.
do $$
declare blur double precision := coalesce(public.setting('listing_blur_m'), 500) / 111320.0;
begin
  if blur > 0 then
    insert into public.listing_exact_location (listing_id, location)
      select id, location from public.listings where kind in ('SKILL', 'DRIVER') and location is not null
    on conflict (listing_id) do nothing;
    alter table public.listings disable trigger listing_prune_recs;
    update public.listings set location = st_snaptogrid(location::geometry, blur)::geography
     where kind in ('SKILL', 'DRIVER') and location is not null;
    alter table public.listings enable trigger listing_prune_recs;
  end if;
end $$;

-- ---------- 3. recommendations ----------

alter table public.profiles add column if not exists home_changed_at timestamptz;

-- A home that moves more than 500 m starts the cooldown. Setting it the first time doesn't (new accounts are covered by
-- recommender_min_account_days). Nobody can set the timestamp by hand.
create or replace function public.profile_home_moved() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if old.home is not null and new.home is not null and st_distance(old.home, new.home) > 500 then
    new.home_changed_at := now();
  else
    new.home_changed_at := old.home_changed_at;
  end if;
  return new;
end $$;
revoke execute on function public.profile_home_moved() from public, anon, authenticated;
drop trigger if exists profile_home_moved on public.profiles;
create trigger profile_home_moved before update on public.profiles for each row execute function public.profile_home_moved();

create or replace function public.recommend(p_token text, lat double precision, lng double precision) returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare tok recommend_tokens; l listings; me_p profiles; here geography := geo(lat, lng); n int; added int;
  cooldown numeric := coalesce(setting('recommend_home_cooldown_days'), 7);
begin
  select * into tok from recommend_tokens where token = p_token and expires_at > now() for update;
  if not found then raise exception 'this code has expired, ask them to show a new one'; end if;
  select * into l from listings where id = tok.listing_id;
  select * into me_p from profiles where id = me();
  if me_p.id is null then raise exception 'not signed in'; end if;
  if listing_role(l.id) is not null then raise exception 'you cannot recommend your own listing'; end if;
  if me_p.created_at > now() - make_interval(days => setting('recommender_min_account_days')::int) then raise exception 'your account is too new to recommend'; end if;
  if cooldown > 0 and me_p.home_changed_at > now() - make_interval(days => cooldown::int) then
    raise exception 'you changed where you live recently; you can recommend again % days after the move', cooldown::int;
  end if;
  if me_p.home is null or l.location is null or not st_dwithin(me_p.home, l.location, setting('recommend_radius_m')) then raise exception 'only people who live nearby can recommend'; end if;
  if not st_dwithin(here, l.location, setting('recommend_radius_m')) then raise exception 'recommend in person, near where they work'; end if;
  if coalesce(setting('rate_limits_on'), 1) >= 1 and coalesce(setting('recommend_per_listing_per_hour'), 10) > 0
     and (select count(*) from recommendations r where r.listing_id = l.id and r.created_at > now() - interval '1 hour') >= setting('recommend_per_listing_per_hour') then
    raise exception 'this page got a lot of recommendations in the last hour; try again later';
  end if;
  insert into recommendations values (l.id, me_p.id, here) on conflict do nothing;
  get diagnostics added = row_count;
  -- One recommender per code: a code shared in a group chat can't collect a crowd.
  if added > 0 then delete from recommend_tokens where token = p_token; end if;
  select count(*) into n from recommendations where listing_id = l.id;
  perform try_go_live(l.id);
  return n;
end $$;

-- ---------- 5. the Firebase id stays private ----------

revoke select (auth_uid) on public.profiles from authenticated, anon;

-- ---------- 6. reports keep what was reported ----------

alter table public.reports add column if not exists snapshot text not null default '' check (length(snapshot) <= 2000);

create or replace function public.report_preview(p_kind text, p_target uuid) returns text
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(case upper(p_kind)
    when 'POST'     then (select body || case when jsonb_array_length(coalesce(media, '[]'::jsonb)) > 0 then ' [media: ' || media::text || ']' else '' end from posts where id = p_target)
    when 'COMMENT'  then (select body from post_comments where id = p_target)
    when 'MOMENT'   then (select caption || ' [media: ' || coalesce(media_path, '') || ']' from moments where id = p_target)
    when 'MESSAGE'  then (select body || case when attachment is not null then ' [attachment: ' || attachment::text || ']' else '' end from messages where id = p_target)
    when 'PROFILE'  then (select name || ' · ' || bio from profiles where id = p_target)
    when 'LISTING'  then (select 'Page: ' || title || ' · ' || description from listings where id = p_target)
    when 'REVIEW'   then (select 'Review of ' || l.title || ': ' || v.comment from reviews v join listings l on l.id = v.listing_id where v.id = p_target)
    when 'JOB'      then (select 'Job: ' || title || ' · ' || description from jobs where id = p_target)
    when 'FEEDBACK' then (select 'Feedback: ' || title || ' · ' || body from feedback_posts where id = p_target)
  end, '')
$$;
revoke execute on function public.report_preview(text, uuid) from public, anon, authenticated;

-- report_more_kinds.sql's version, plus the snapshot taken as the report is filed.
create or replace function public.report_content(p_kind text, p_target uuid, p_reason text, p_detail text default '') returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); owner uuid; rid uuid; k text := upper(p_kind);
begin
  if my is null then raise exception 'not signed in'; end if;
  owner := case k
    when 'POST'     then (select p.author_id from posts p where p.id = p_target and can_see_post(p))
    when 'COMMENT'  then (select c.author_id from post_comments c join posts p on p.id = c.post_id where c.id = p_target and can_see_post(p))
    when 'MOMENT'   then (select m.author_id from moments m where m.id = p_target)
    when 'MESSAGE'  then (select m.sender_id from messages m where m.id = p_target and is_member(m.conversation_id))
    when 'PROFILE'  then (select p.id from profiles p where p.id = p_target)
    when 'LISTING'  then (select l.owner_id from listings l where l.id = p_target and l.status = 'LIVE')
    when 'REVIEW'   then (select r.author_id from reviews r join listings l on l.id = r.listing_id where r.id = p_target and l.status = 'LIVE')
    when 'JOB'      then (select coalesce(j.created_by, l.owner_id) from jobs j join listings l on l.id = j.listing_id where j.id = p_target and j.open)
    when 'FEEDBACK' then (select f.author_id from feedback_posts f where f.id = p_target)
  end;
  if owner is null then raise exception 'nothing to report: it was removed or you can''t see it'; end if;
  if owner = my then raise exception 'you can''t report yourself'; end if;
  insert into reports (reporter_id, target_kind, target_id, target_owner, reason, detail, snapshot)
  values (my, k, p_target, owner, upper(p_reason), left(coalesce(btrim(p_detail), ''), 500), left(report_preview(k, p_target), 2000))
  on conflict (reporter_id, target_kind, target_id) do nothing
  returning id into rid;
  return coalesce(rid, (select id from reports where reporter_id = my and target_kind = k and target_id = p_target));
end $$;

-- Staff see what was reported (the snapshot), falling back to the live content for reports filed before snapshots existed.
create or replace function public.report_queue(lim int default 50)
returns table (id uuid, target_kind text, target_id uuid, target_owner uuid, owner_name text, reason text, detail text, reporters int, created_at timestamptz, preview text)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.target_kind, r.target_id, r.target_owner, o.name, r.reason, r.detail,
         (select count(*)::int from reports x where x.target_kind = r.target_kind and x.target_id = r.target_id and x.status = 'OPEN'),
         r.created_at,
         left(coalesce(nullif(r.snapshot, ''), report_preview(r.target_kind, r.target_id)), 280)
  from reports r left join profiles o on o.id = r.target_owner
  where is_staff() and r.status = 'OPEN'
  order by (r.reason in ('CHILD_SAFETY', 'SELF_HARM')) desc, r.created_at
  limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- ---------- 7. ride fares: no shorter than 1.2x the straight line ----------

create or replace function public.request_ride(p_kind text, p_lat double precision, p_lng double precision, p_pickup_label text, d_lat double precision, d_lng double precision, p_drop_label text, p_km numeric, p_fare integer)
returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks; my uuid := public.me(); straight numeric; km numeric; fare int; floor_factor numeric := coalesce(setting('ride_min_km_factor'), 1.2);
begin
  if my is null then raise exception 'not signed in'; end if;
  if p_kind = 'BIKE' then raise exception 'bikes carry goods only'; end if;
  if p_kind is null or p_kind not in ('AUTO', 'CAB') then raise exception 'choose an auto or a cab'; end if;
  if p_lat is null or p_lng is null or d_lat is null or d_lng is null or not (p_lat between -90 and 90 and d_lat between -90 and 90 and p_lng between -180 and 180 and d_lng between -180 and 180) then raise exception 'that location is not valid'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ride:' || my::text, 0));
  update tasks set status = 'NO_DRIVER' where requester_id = my and type = 'RIDE' and order_id is null and status = 'SEARCHING' and status_at < now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision);
  if exists (select 1 from tasks x where x.requester_id = my and x.type = 'RIDE' and x.order_id is null and x.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS')) then raise exception 'you already have a ride in progress'; end if;
  straight := (st_distance(geo(p_lat, p_lng), geo(d_lat, d_lng)) / 1000.0)::numeric;
  -- The app's road distance is trusted between floor_factor and 4x the straight line; otherwise 1.3x (roads are rarely straighter).
  km := case when p_km is not null and p_km >= floor_factor * straight and p_km <= 4 * straight then round(p_km, 1) else round(1.3 * straight, 1) end;
  if km < 0.2 then raise exception 'that trip is too short'; end if;
  if km > 150 then raise exception 'that trip is too far for Bucks'; end if;
  fare := round(public.dispatch_cfg('fare_base', 20) + public.dispatch_cfg('fare_' || lower(p_kind) || '_per_km', case p_kind when 'AUTO' then 12 else 18 end) * km)::int;
  begin
    insert into tasks (type, requester_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare)
    values ('RIDE', my, p_kind, geo(p_lat, p_lng), left(coalesce(p_pickup_label, ''), 120), geo(d_lat, d_lng), left(coalesce(p_drop_label, ''), 120), km, fare)
    returning * into t;
  exception when unique_violation then raise exception 'you already have a ride in progress';
  end;
  return t;
end $$;
