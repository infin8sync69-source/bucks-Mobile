-- Hardening for dispatch, rides, delivery, orders and reviews (audit items D1-D9).
-- Apply LAST for this area: after schema.sql, dispatch.sql, commerce.sql, studio.sql, services.sql and the rest, because it
-- redefines their latest versions of the functions below. Safe to re-run. Tests: supabase/tests/hardening_dispatch_scenarios.sql.
--
-- What changes for a phone that has not updated yet (nothing here changes an RPC signature or a returned column):
--  * a wrong PIN no longer raises: advance_task returns the task unchanged and counts the attempt (the old app then shows
--    "PIN matched" for a moment; the server still refuses COMPLETED from ARRIVED). Needs the new app for the right message.
--  * arriving and completing need a fresh location near the pick-up / drop; claiming needs to be online with a fresh, verified
--    vehicle near the pick-up. An old app with working GPS is unaffected; without it the server explains what is missing.
--  * request_ride ignores the app's km and fare, and place_order / review / update_location refuse abuse with plain messages.
--  * a position that moves faster than a car can drive is ignored (movement allowance in presence_clamp / update_location), and
--    driver_presence rows can no longer be deleted from the app (the app never did; delete-and-reinsert was the way round both that
--    and the hand-back cap).
set search_path = public, extensions;

-- ---------- settings (0 switches a geometric check off) ----------
insert into public.settings (key, value) values
  ('arrive_radius_m', 800), ('complete_radius_m', 2000), ('min_trip_seconds', 60), ('claim_fresh_seconds', 180), ('ring_window_seconds', 180),
  ('fare_base', 20), ('fare_bike_per_km', 8), ('fare_auto_per_km', 12), ('fare_cab_per_km', 18),
  ('presence_max_speed_mps', 40), ('presence_slack_m', 300)
on conflict (key) do nothing;

-- A setting with a fallback, so a deleted row never turns a check off by accident.
create or replace function public.dispatch_cfg(k text, d numeric) returns numeric language sql stable set search_path = public, extensions as $$
  select coalesce((select value from public.settings where key = k), d)
$$;

-- ---------- columns ----------
alter table public.tasks add column if not exists pin_attempts smallint not null default 0;
alter table public.tasks add column if not exists started_at timestamptz;      -- IN_PROGRESS reached
alter table public.tasks add column if not exists completed_at timestamptz;    -- COMPLETED reached
alter table public.orders add column if not exists accepted_at timestamptz;
alter table public.orders add column if not exists delivered_at timestamptz;
alter table public.driver_presence add column if not exists located_at timestamptz;   -- last accepted position change: the 2-second throttle and the movement allowance both start from it
alter table public.driver_presence add column if not exists move_credit_m double precision;   -- movement allowance in metres, see presence_clamp
alter table public.tasks drop constraint if exists tasks_pin_attempts_ok;
alter table public.tasks add constraint tasks_pin_attempts_ok check (pin_attempts between 0 and 5);
-- tasks.pin is withheld from the API (dispatch.sql), so the new column needs its own grant: the requester and the driver of a task read it.
grant select (pin_attempts) on public.tasks to authenticated;

-- 4-digit PIN from pgcrypto (random() is predictable and seeded per session).
create or replace function public.new_pin() returns text language plpgsql volatile set search_path = public, extensions as $$
declare b bytea := extensions.gen_random_bytes(4);
begin
  return lpad(((get_byte(b, 0)::bigint * 16777216 + get_byte(b, 1) * 65536 + get_byte(b, 2) * 256 + get_byte(b, 3)) % 10000)::text, 4, '0');
end $$;
alter table public.tasks alter column pin set default public.new_pin();

-- ---------- who may claim a SEARCHING task ----------
-- The calling driver, as their presence row stands now: online, a fresh position, an ACTIVE vehicle of the task's kind, the pick-up
-- inside the ring radius (measured from the presence position, never from what the app says), the request inside the ring window
-- (timed from when it last started searching, so a hand-back rings again).
-- One predicate for claim_task, open_tasks_near and the tasks read policy, so listing a request shows only what could be claimed.
create or replace function public.can_claim(p_type text, p_kind text, p_pickup geography, p_requester uuid, p_only uuid[], p_status_at timestamptz) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from public.driver_presence p
    join public.vehicles v on v.id = p.vehicle_id and v.status = 'ACTIVE'
    where p.profile_id = public.me() and p.online and p.location is not null
      and p.updated_at > now() - make_interval(secs => public.dispatch_cfg('claim_fresh_seconds', 180)::double precision)
      and v.kind = p_kind and p_requester <> p.profile_id
      and (p_only is null or p.profile_id = any(p_only))
      and p_status_at > now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision)
      and st_dwithin(p_pickup, p.location, (case when p_type = 'DELIVERY' then public.dispatch_cfg('delivery_radius_m', 3000) else public.dispatch_cfg('ride_radius_m', 5000) end)::double precision))
$$;

drop policy if exists tasks_read on public.tasks;
create policy tasks_read on public.tasks for select to authenticated using (
  requester_id = public.me() or driver_id = public.me()
  or (status = 'SEARCHING' and public.can_claim(type, vehicle_kind, pickup, requester_id, only_riders, status_at)));

-- A shop's own rider reads only the orders they carry (not the buyers and addresses of the rest); owners and admins read the shop's
-- orders; buyers read their own. Bucks riders on a marketplace delivery still read no order (task_driver and tasks_geo carry what they need).
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select to authenticated using (
  buyer_id = public.me() or coalesce(public.listing_role(listing_id), '') in ('OWNER', 'ADMIN')
  or (public.listing_role(listing_id) = 'STORE_RIDER' and exists (select 1 from public.tasks t where t.order_id = orders.id and t.driver_id = public.me())));

-- ---------- ringing: the request list of an online driver, nearest first ----------
-- lat and lng are still accepted (old apps send them) but no longer decide anything: the server uses the presence position.
create or replace function public.open_tasks_near(lat double precision, lng double precision) returns setof public.tasks
language sql stable security definer set search_path = public, extensions as $$
  select m.*
  from public.tasks t
  join public.driver_presence p on p.profile_id = public.me()
  cross join lateral jsonb_populate_record(t, jsonb_build_object('pin', '')) m
  where t.status = 'SEARCHING' and public.can_claim(t.type, t.vehicle_kind, t.pickup, t.requester_id, t.only_riders, t.status_at)
  order by st_distance(t.pickup, p.location)
$$;

-- ---------- claiming ----------
-- false = not claimable (taken, too far, stale, not eligible). Raises only when the driver themself is not ready.
-- The presence row is locked for the whole call, so two claims by one driver cannot both pass "one trip at a time" or the hand-back cap.
-- The cap is checked here as well as at hand-back, and it counts CANCELLED events however they came about (the driver's own hand-back,
-- or expire_tasks handing back a trip whose driver went silent): claiming is what reveals the requester's phone, so this is the limit
-- on how many phones one driver account can read an hour (3), whatever they do with the trip afterwards.
create or replace function public.claim_task(p_task uuid) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := public.me(); p driver_presence; v vehicles; t tasks; k int;
begin
  select * into p from driver_presence where profile_id = my for update;
  if not found or not p.online then raise exception 'go online first'; end if;
  select * into v from vehicles where id = p.vehicle_id;
  if not found or v.status <> 'ACTIVE' then raise exception 'vehicle not verified'; end if;
  if exists (select 1 from tasks x where x.driver_id = my and x.id <> p_task and x.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')) then
    raise exception 'finish your current trip before taking another';
  end if;
  select count(*) into k from task_events where driver_id = my and event = 'CANCELLED' and at > now() - interval '1 hour';
  if k >= 3 then raise exception 'you have handed back % trips in the last hour; try again later', k; end if;
  update tasks set status = 'MATCHED', driver_id = my, vehicle_id = v.id, driver_location = p.location
   where id = p_task and status = 'SEARCHING' and public.can_claim(type, vehicle_kind, pickup, requester_id, only_riders, status_at)
  returning * into t;
  if not found then return false; end if;
  insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, my, v.id, 'ACCEPTED', t.km, t.fare);
  return true;
end $$;

-- The driver's own position must be fresh and inside the radius (a setting; 0 = no check) for ARRIVED and COMPLETED.
create or replace function public.driver_near_check(p_point geography, p_key text, p_default numeric, p_what text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r numeric := public.dispatch_cfg(p_key, p_default); p driver_presence; d numeric;
begin
  if r <= 0 then return; end if;
  select * into p from driver_presence where profile_id = public.me();
  if not found or p.location is null or p.updated_at < now() - make_interval(secs => public.dispatch_cfg('claim_fresh_seconds', 180)::double precision) then
    raise exception 'your location is not up to date; keep the app open with location on and try again';
  end if;
  d := st_distance(p.location, p_point);
  if d > r then
    raise exception 'you are too far from % (about % away); get within % m and try again', p_what,
      case when d >= 1000 then round(d / 1000, 1)::text || ' km' else round(d)::text || ' m' end, r::int;
  end if;
end $$;

-- ---------- moving a task along ----------
-- Driver: ARRIVED (near the pick-up) -> IN_PROGRESS (the requester's PIN, 5 tries) -> COMPLETED (a minimum time, near the drop);
-- or hand it back from MATCHED / ARRIVED (3 an hour). The drop check is waived once the trip has run for max(30 min, 6 min per km).
-- A wrong PIN returns the task unchanged and counts the try: an exception would roll the counter back. A hand-back resets the counter
-- and rotates the PIN.
-- Requester: CANCELLED (before pick-up, or during the trip once the driver has been silent for over 10 minutes), NO_DRIVER, PAID.
create or replace function public.advance_task(p_task uuid, p_status text, p_pin text default null, p_paid_with text default null) returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks; my uuid := public.me(); k int;
begin
  select * into t from tasks where id = p_task for update;
  if not found then raise exception 'task not found'; end if;
  if t.driver_id = my then
    if p_status = 'ARRIVED' and t.status = 'MATCHED' then
      perform public.driver_near_check(t.pickup, 'arrive_radius_m', 800, 'the pick-up');
    elsif p_status = 'IN_PROGRESS' and t.status = 'ARRIVED' then
      if t.pin_attempts >= 5 then raise exception 'too many wrong PIN attempts; hand the trip back'; end if;
      if p_pin is distinct from t.pin then
        update tasks set pin_attempts = pin_attempts + 1 where id = t.id returning * into t;
        t.pin := '';
        return t;
      end if;
    elsif p_status = 'COMPLETED' and t.status = 'IN_PROGRESS' then
      if t.status_at > now() - make_interval(secs => public.dispatch_cfg('min_trip_seconds', 60)::double precision) then
        raise exception 'the trip has only just started; you can complete it after % seconds', public.dispatch_cfg('min_trip_seconds', 60)::int;
      end if;
      -- The geofence guards against closing a trip you did not drive. A trip whose destination changed (or whose GPS is kilometres out)
      -- would otherwise never close, and its driver could not take another, so once the trip has run for max(30 min, 6 min per km)
      -- the driver may complete it from anywhere.
      if t.status_at > now() - make_interval(mins => greatest(30, ceil(t.km * 6)::int)) then
        perform public.driver_near_check(t.drop_at, 'complete_radius_m', 2000, 'the drop');
      end if;
      insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, my, t.vehicle_id, 'COMPLETED', t.km, t.fare);
      if t.order_id is not null then update orders set status = 'DELIVERED' where id = t.order_id; end if;
    elsif p_status = 'SEARCHING' and t.status in ('MATCHED', 'ARRIVED') then
      select count(*) into k from task_events where driver_id = my and event = 'CANCELLED' and at > now() - interval '1 hour';
      if k >= 3 then raise exception 'you have handed back % trips in the last hour; keep the next one or try again later', k; end if;
      insert into task_events (task_id, driver_id, vehicle_id, event) values (t.id, my, t.vehicle_id, 'CANCELLED');
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
    if p_status = 'IN_PROGRESS' and t.order_id is not null then update orders set status = 'PICKED_UP' where id = t.order_id; end if;
  elsif t.requester_id = my then
    if p_status = 'CANCELLED' and t.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER') then null;
    elsif p_status = 'CANCELLED' and t.status = 'IN_PROGRESS'
          and not exists (select 1 from driver_presence p where p.profile_id = t.driver_id and p.updated_at > now() - interval '10 minutes') then
      insert into task_events (task_id, driver_id, vehicle_id, event) values (t.id, t.driver_id, t.vehicle_id, 'MISSED');
      if t.order_id is not null then update orders set status = 'CANCELLED', cancelled_by = 'BUYER' where id = t.order_id and status = 'PICKED_UP'; end if;
    elsif p_status = 'NO_DRIVER' and t.status = 'SEARCHING' then null;
    elsif p_status = 'PAID' and t.status = 'COMPLETED' then null;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
  else raise exception 'not your task'; end if;
  if p_status = 'SEARCHING' then
    update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null, pin = public.new_pin(), pin_attempts = 0 where id = p_task returning * into t;
  else
    update tasks set status = p_status, paid_with = case when p_status = 'PAID' then coalesce(p_paid_with, paid_with) else paid_with end where id = p_task returning * into t;
  end if;
  if t.requester_id is distinct from my then t.pin := ''; end if;
  return t;
end $$;

-- ---------- request_ride: the server decides km and fare ----------
create or replace function public.request_ride(p_kind text, p_lat double precision, p_lng double precision, p_pickup_label text,
                                               d_lat double precision, d_lng double precision, p_drop_label text, p_km numeric, p_fare int)
returns public.tasks language plpgsql security definer set search_path = public, extensions as $$
declare t tasks; my uuid := public.me(); straight numeric; km numeric; fare int;
begin
  if my is null then raise exception 'not signed in'; end if;
  if p_kind = 'BIKE' then raise exception 'bikes carry goods only'; end if;
  if p_kind is null or p_kind not in ('AUTO', 'CAB') then raise exception 'choose an auto or a cab'; end if;
  if p_lat is null or p_lng is null or d_lat is null or d_lng is null
     or not (p_lat between -90 and 90 and d_lat between -90 and 90 and p_lng between -180 and 180 and d_lng between -180 and 180) then
    raise exception 'that location is not valid';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ride:' || my::text, 0));
  update tasks set status = 'NO_DRIVER' where requester_id = my and type = 'RIDE' and order_id is null and status = 'SEARCHING'
    and status_at < now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision);
  if exists (select 1 from tasks x where x.requester_id = my and x.type = 'RIDE' and x.order_id is null and x.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS')) then
    raise exception 'you already have a ride in progress';
  end if;
  straight := (st_distance(geo(p_lat, p_lng), geo(d_lat, d_lng)) / 1000.0)::numeric;
  km := case when p_km is not null and p_km >= 0.8 * straight and p_km <= 4 * straight then round(p_km, 1) else round(1.3 * straight, 1) end;
  if km < 0.2 then raise exception 'that trip is too short'; end if;
  if km > 150 then raise exception 'that trip is too far for Bucks'; end if;
  fare := round(public.dispatch_cfg('fare_base', 20) + public.dispatch_cfg('fare_' || lower(p_kind) || '_per_km', case p_kind when 'AUTO' then 12 else 18 end) * km)::int;
  begin
    insert into tasks (type, requester_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare)
    values ('RIDE', my, p_kind, geo(p_lat, p_lng), left(coalesce(p_pickup_label, ''), 120), geo(d_lat, d_lng), left(coalesce(p_drop_label, ''), 120), km, fare) returning * into t;
  exception when unique_violation then raise exception 'you already have a ride in progress';
  end;
  return t;
end $$;

-- ---------- the driver's position ----------
-- Online drivers only (or a driver with a trip under way, whom a suspension may have taken offline); real coordinates only;
-- an update within 2 seconds of the last one is ignored. Every check on this page (claim, list, ARRIVED, COMPLETED) measures from this
-- position, so a driver who could write any position at any time would defeat them all. Each presence row therefore has a movement
-- allowance in metres (move_credit_m): it starts at presence_slack_m (300), grows by presence_max_speed_mps (40, i.e. 144 km/h) for every
-- second since the last accepted position change, and a change of D metres costs D. A position the allowance cannot pay for is ignored
-- and the old one stays (silently, so an app with a glitching fix is shown no error). A vehicle never runs out (it earns as fast as it
-- can spend); a script that writes 250 m hops in a loop, or one 31 km jump, is paid for by the allowance or refused. Waiting D / 40 seconds
-- buys a jump of D metres, so this is a speed bump, not proof of where anyone is: the claim cap in claim_task bounds the damage.
-- 0 for presence_max_speed_mps switches it off. presence_clamp below applies the same rule to direct writes to the row.
create or replace function public.update_location(lat double precision, lng double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := public.me(); p driver_presence; has_row boolean; v double precision := public.dispatch_cfg('presence_max_speed_mps', 40)::double precision;
        s double precision := public.dispatch_cfg('presence_slack_m', 300)::double precision; credit double precision;
begin
  if lat is null or lng is null or not (lat between -90 and 90 and lng between -180 and 180) then raise exception 'that location is not valid'; end if;
  select * into p from driver_presence where profile_id = my for update;
  has_row := found;
  if (not has_row or not p.online) and not exists (select 1 from tasks where driver_id = my and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')) then
    raise exception 'go online first';
  end if;
  if not has_row then return; end if;
  if p.located_at is not null and p.located_at > now() - interval '2 seconds' then return; end if;
  credit := coalesce(p.move_credit_m, s);
  if v > 0 and p.location is not null then
    credit := credit + v * greatest(extract(epoch from now() - coalesce(p.located_at, p.updated_at)), 0) - st_distance(p.location, geo(lat, lng));
    if credit < 0 then return; end if;
  end if;
  update driver_presence set location = geo(lat, lng), located_at = now(), move_credit_m = credit where profile_id = my;
  update tasks set driver_location = geo(lat, lng) where driver_id = my and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS');
end $$;

-- ---------- presence: stamped by the server ----------
-- kind comes from the vehicle while it is ACTIVE; a vehicle sent back to PENDING (after an edit) keeps the kind it was verified as.
-- Going online with an unverified vehicle stays refused by the presence policies (manage.sql), so the app's error is unchanged.
create or replace function public.presence_touch() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v vehicles;
begin
  select * into v from public.vehicles where id = new.vehicle_id;
  if found and v.status = 'ACTIVE' then new.kind := v.kind;
  else new.kind := coalesce(case when tg_op = 'UPDATE' then old.kind end, v.kind, new.kind);
  end if;
  new.updated_at := now();
  return new;
end $$;

-- Direct writes to the presence row (the app's setPresence upsert, or anything a signed-in driver sends to PostgREST) are held to the same
-- movement allowance update_location keeps. A position the allowance cannot pay for is dropped and the old one stays, the position can never
-- be cleared (a "first fix" would be free), and located_at and move_credit_m are the server's alone. A first position is taken as it comes.
-- Runs as the caller (not security definer), so the definer functions of this file, and the database owner in tests and maintenance, are
-- not held to it (update_location applies the rule itself). Keep the two in step.
create or replace function public.presence_clamp() returns trigger language plpgsql set search_path = public, extensions as $$
declare v double precision := coalesce(public.setting('presence_max_speed_mps'), 40)::double precision;
        s double precision := coalesce(public.setting('presence_slack_m'), 300)::double precision; credit double precision; d double precision;
begin
  if current_user <> 'authenticated' then return new; end if;
  if tg_op = 'INSERT' then
    new.located_at := case when new.location is not null then now() end;
    new.move_credit_m := s;
    return new;
  end if;
  new.located_at := coalesce(old.located_at, old.updated_at);   -- frozen: a refused write must not restart the clock (presence_touch bumps updated_at on every write)
  new.move_credit_m := old.move_credit_m;
  if new.location is null then new.location := old.location; return new; end if;
  if old.location is null then new.located_at := now(); new.move_credit_m := s; return new; end if;
  d := st_distance(old.location, new.location);
  if d = 0 then return new; end if;
  if v > 0 then
    credit := coalesce(old.move_credit_m, s) + v * greatest(extract(epoch from now() - new.located_at), 0) - d;
    if credit < 0 then new.location := old.location; return new; end if;
    new.move_credit_m := credit;
  end if;
  new.located_at := now();
  return new;
end $$;
drop trigger if exists presence_clamp on public.driver_presence;
create trigger presence_clamp before insert or update on public.driver_presence for each row execute function public.presence_clamp();

-- Nothing in the app deletes a presence row (going offline is an update; account deletion and vehicle removal are definer paths). Left open, a
-- driver could delete the row and insert a fresh one anywhere, which skips the speed check above, and a missing row also counted as a silent
-- driver for expire_tasks, which handed the trip back at once.
drop policy if exists presence_delete on public.driver_presence;

-- A vehicle that stops being ACTIVE (edited back to PENDING, suspended) or changes kind takes its driver offline.
create or replace function public.vehicle_offline() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update public.driver_presence set online = false where vehicle_id = new.id and online;
  return null;
end $$;
drop trigger if exists vehicle_offline on public.vehicles;
create trigger vehicle_offline after update on public.vehicles for each row
  when (new.status is distinct from old.status or new.kind is distinct from old.kind) execute function public.vehicle_offline();

-- ---------- online drivers around a point, for the map ----------
-- At most 30 drivers within 10 km, verified vehicles with a presence fresher than claim_fresh_seconds. Same columns as before
-- (the app reads every one of them).
create or replace function public.online_drivers_near(p_lat double precision, p_lng double precision, radius_m int default 5000)
returns table (profile_id uuid, kind text, lat double precision, lng double precision, name text, model text, plate text, up int, down int)
language sql stable security definer set search_path = public, extensions as $$
  select p.profile_id, p.kind, st_y(p.location::geometry), st_x(p.location::geometry), pr.name, v.model, '••' || right(v.plate, 4),
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0)
  from public.driver_presence p
  join public.profiles pr on pr.id = p.profile_id and pr.status = 'ACTIVE'
  join public.vehicles v on v.id = p.vehicle_id and v.status = 'ACTIVE'
  left join public.listings l on l.owner_id = p.profile_id and l.kind = 'DRIVER'
  where p.online and p.location is not null
    and p.updated_at > now() - make_interval(secs => public.dispatch_cfg('claim_fresh_seconds', 180)::double precision)
    and p.profile_id is distinct from public.me()
    and st_dwithin(p.location, public.geo(p_lat, p_lng), least(greatest(coalesce(radius_m, 5000), 0), 10000))
  order by st_distance(p.location, public.geo(p_lat, p_lng))
  limit 30
$$;

-- ---------- contact ----------
-- Once a trip is matched and for a day after it completes. The rider gets the driver's phone and UPI link (to pay); the driver
-- gets the rider's phone only.
create or replace function public.contact_for_task(p_task uuid) returns table (phone text, upi_uri text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone, case when t.requester_id = public.me() then pp.upi_uri end from public.tasks t
  join public.profile_private pp on pp.profile_id = case when t.requester_id = public.me() then t.driver_id else t.requester_id end
  where t.id = p_task and t.driver_id is not null and public.me() in (t.requester_id, t.driver_id)
    and (t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS') or (t.status = 'COMPLETED' and t.status_at > now() - interval '24 hours'))
$$;

-- The shop side sees the buyer from PLACED. The buyer gets the owner's phone and UPI link once the shop has accepted (or cancelled
-- an accepted order, so a buyer who paid can call about the refund).
create or replace function public.contact_for_order(p_order uuid) returns table (phone text, upi_uri text, name text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone,
         case when o.buyer_id = public.me() then pp.upi_uri else null end,
         p.name
  from orders o
  join listings l on l.id = o.listing_id
  join profiles p on p.id = case when o.buyer_id = public.me() then l.owner_id else o.buyer_id end
  left join profile_private pp on pp.profile_id = p.id
  where o.id = p_order
    and ((o.buyer_id = public.me() and (o.status in ('ACCEPTED', 'READY', 'PICKED_UP', 'DELIVERED') or (o.status = 'CANCELLED' and o.cancelled_by = 'SHOP')))
      or (public.can_manage_listing(o.listing_id) and (o.status in ('PLACED', 'ACCEPTED', 'READY', 'PICKED_UP', 'DELIVERED') or (o.status = 'CANCELLED' and o.cancelled_by = 'SHOP'))))
$$;

-- ---------- place_order: studio.sql's, plus limits ----------
create or replace function public.place_order(p_listing uuid, p_lines jsonb, p_lat double precision, p_lng double precision, p_drop_label text, p_payment text, p_mode text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare l listings; lines jsonb := '[]'; sub int := 0; line jsonb; it items; q int; km numeric; fee int := 0; oid uuid; my uuid := public.me(); drop_at geography;
begin
  if my is null then raise exception 'not signed in'; end if;
  select * into l from listings where id = p_listing and kind = 'BUSINESS' and status = 'LIVE';
  if not found then raise exception 'this shop is not taking orders'; end if;
  if not l.online then raise exception 'this shop is closed right now'; end if;   -- switched off by the owner (MyListings "closed")
  if l.owner_id = my or listing_role(p_listing) is not null then raise exception 'you cannot order from your own shop'; end if;
  if p_mode is null or p_mode not in ('MARKETPLACE', 'STORE_RIDER', 'PICKUP') then raise exception 'choose delivery or pick-up'; end if;
  if p_payment is null or p_payment not in ('UPI', 'COD') then raise exception 'choose how you will pay'; end if;
  if p_payment = 'COD' and p_mode <> 'STORE_RIDER' then raise exception 'cash on delivery is only with the store''s own riders'; end if;
  if p_mode = 'STORE_RIDER' and not exists (select 1 from listing_members m where m.listing_id = p_listing and m.role = 'STORE_RIDER') then
    raise exception 'this shop has no riders of its own; choose a Bucks rider or pick it up';
  end if;
  if p_payment = 'COD' and lower(coalesce(l.details->>'cod', '')) <> 'true' then raise exception 'this shop does not take cash on delivery'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'your cart is empty'; end if;
  if jsonb_array_length(p_lines) > 30 then raise exception 'too many items in one order (30 lines at most)'; end if;
  drop_at := case when p_lat between -90 and 90 and p_lng between -180 and 180 then geo(p_lat, p_lng) end;
  if drop_at is null and p_mode <> 'PICKUP' then raise exception 'that delivery location is not valid'; end if;
  perform pg_advisory_xact_lock(hashtextextended('order:' || my::text, 0));
  -- Only orders the shop can still answer count: an order past accept_by is dead even while expire_orders has not run (it is a cron job,
  -- and a project without pg_cron would otherwise lock the buyer out until he cancelled each one by hand).
  if (select count(*) from orders where buyer_id = my and status = 'PLACED' and accept_by > now()) >= 3 then
    raise exception 'you already have 3 orders waiting for a shop to answer; wait for them first';
  end if;
  if (select count(*) from orders where buyer_id = my and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'you have placed 10 orders in the last hour; try again later';
  end if;
  for line in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(line) <> 'object' or coalesce(line->>'item_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'an item is no longer available'; end if;
    if (line->>'qty') is null then q := 1;
    elsif (line->>'qty') ~ '^[0-9]{1,4}$' then q := (line->>'qty')::int;
    else raise exception 'quantity must be between 1 and 99'; end if;
    if q < 1 or q > 99 then raise exception 'quantity must be between 1 and 99'; end if;
    select * into it from items where id = (line->>'item_id')::uuid and listing_id = p_listing and in_stock for update;
    if not found then raise exception 'an item is no longer available'; end if;
    if it.stock is not null and q > it.stock then raise exception 'only % left of %', it.stock, it.name; end if;
    if it.stock is not null then update items set stock = stock - q where id = it.id; end if;
    lines := lines || jsonb_build_object('item_id', it.id, 'name', it.name, 'price', it.price, 'qty', q);
    sub := sub + it.price * q;
  end loop;
  if p_mode <> 'PICKUP' then
    km := round((st_distance(l.location, drop_at) / 1000.0 * 1.3)::numeric, 1);   -- road ~1.3x straight line
    fee := (setting('delivery_base_fee') + setting('delivery_fee_per_km') * km)::int;
  end if;
  insert into orders (listing_id, buyer_id, lines, subtotal, delivery_fee, fee_paid_by, delivery_mode, payment, drop_location, drop_label, accept_by)
  values (p_listing, my, lines, sub, fee, case when coalesce((l.details->>'free_delivery')::boolean, false) then 'VENDOR' else 'BUYER' end,
          p_mode, p_payment, drop_at, left(coalesce(p_drop_label, ''), 120), now() + make_interval(mins => setting('order_accept_minutes')::int))
  returning id into oid;
  return oid;
end $$;

-- ---------- reviews: dispatch.sql's, plus friction ----------
-- A ride is reviewed once it is PAID (a delivery task never is: its order is DELIVERED) and ran at least min_trip_seconds
-- (IN_PROGRESS to COMPLETED); an order once it is DELIVERED and ran at least that long (ACCEPTED to DELIVERED). Rows from before this
-- migration carry no timestamps and are not held to the minimum. At most 3 reviews per reviewer per 24 hours.
create or replace function public.review(p_listing uuid, p_task uuid, p_order uuid, p_vote int, p_comment text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l listings; ok boolean := false; t tasks; o orders; min_s double precision := public.dispatch_cfg('min_trip_seconds', 60)::double precision;
begin
  select * into l from listings where id = p_listing;
  if p_task is not null then
    select * into t from tasks x where x.id = p_task and x.requester_id = me() and x.status in ('COMPLETED', 'PAID') and l.kind = 'DRIVER' and l.owner_id = x.driver_id;
    ok := found;
  elsif p_order is not null then
    select * into o from orders x where x.id = p_order and x.buyer_id = me() and x.status = 'DELIVERED' and x.listing_id = p_listing;
    ok := found;
  end if;
  if not ok then raise exception 'you can review after a completed trip or order'; end if;
  if l.owner_id = me() or listing_role(p_listing) is not null then raise exception 'you cannot review your own listing'; end if;
  if p_task is not null and exists (select 1 from reviews r where r.author_id = me() and r.task_id = p_task) then raise exception 'you already reviewed this trip'; end if;
  if p_task is null and exists (select 1 from reviews r where r.author_id = me() and r.order_id = p_order) then raise exception 'you already reviewed this order'; end if;
  if p_task is not null then
    if t.type = 'RIDE' and t.status <> 'PAID' then raise exception 'mark the trip as paid, then review it'; end if;
    if t.started_at is not null and t.completed_at is not null and extract(epoch from t.completed_at - t.started_at) < min_s then raise exception 'that trip was too short to review'; end if;
  else
    if o.accepted_at is not null and o.delivered_at is not null and extract(epoch from o.delivered_at - o.accepted_at) < min_s then raise exception 'that order was too quick to review'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('review:' || me()::text, 0));
  if (select count(*) from reviews r where r.author_id = me() and r.created_at > now() - interval '24 hours') >= 3 then raise exception 'you can post 3 reviews a day; try again tomorrow'; end if;
  insert into reviews (listing_id, author_id, task_id, order_id, vote, comment) values (p_listing, me(), p_task, p_order, p_vote, left(trim(p_comment), 1000));
  update listings set trust_up = trust_up + (p_vote > 0)::int, trust_down = trust_down + (p_vote < 0)::int where id = p_listing;
end $$;

-- ---------- input hygiene ----------
-- Never fails an old app: labels are cut to 120 characters, the payment method is normalised (anything with "cash" in it is CASH,
-- any other text is UPI, empty stays empty), and the moments a trip or order reached are stamped for the review checks.
create or replace function public.tasks_hygiene() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.pickup_label := left(coalesce(new.pickup_label, ''), 120);
  new.drop_label := left(coalesce(new.drop_label, ''), 120);
  if new.paid_with is not null then
    new.paid_with := left(new.paid_with, 40);
    new.paid_with := case when btrim(new.paid_with) = '' then null when lower(new.paid_with) like '%cash%' then 'CASH' else 'UPI' end;
  end if;
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    if new.status = 'IN_PROGRESS' then new.started_at := now(); end if;
    if new.status = 'COMPLETED' then new.completed_at := now(); end if;
  end if;
  return new;
end $$;
drop trigger if exists tasks_hygiene on public.tasks;
create trigger tasks_hygiene before insert or update on public.tasks for each row execute function public.tasks_hygiene();

create or replace function public.orders_hygiene() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.drop_label := left(coalesce(new.drop_label, ''), 120);
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    if new.status = 'ACCEPTED' then new.accepted_at := now(); end if;
    if new.status = 'DELIVERED' then new.delivered_at := now(); end if;
  end if;
  return new;
end $$;
drop trigger if exists orders_hygiene on public.orders;
create trigger orders_hygiene before insert or update on public.orders for each row execute function public.orders_hygiene();

-- NOT VALID: rows from before this migration survive (and are fixed by the triggers above the next time they change).
alter table public.tasks drop constraint if exists tasks_labels_ok;
alter table public.tasks add constraint tasks_labels_ok check (length(pickup_label) <= 120 and length(drop_label) <= 120) not valid;
alter table public.tasks drop constraint if exists tasks_paid_with_ok;
alter table public.tasks add constraint tasks_paid_with_ok check (paid_with is null or paid_with in ('CASH', 'UPI')) not valid;
alter table public.orders drop constraint if exists orders_label_ok;
alter table public.orders add constraint orders_label_ok check (length(drop_label) <= 120) not valid;

-- ---------- timeouts ----------
-- SEARCHING requests older than ring_window_seconds become NO_DRIVER (rides and deliveries); a MATCHED or ARRIVED trip whose driver
-- has been silent for over 10 minutes goes back to SEARCHING with a new PIN and rings again. The driver gets a CANCELLED event, the
-- same as a hand-back of their own, so it counts against the 3 an hour that claim_task enforces (a driver who goes quiet after reading
-- a requester's phone is not given a fresh claim for it). Scheduled every minute where pg_cron exists.
create or replace function public.expire_tasks() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int := 0; k int;
begin
  update tasks set status = 'NO_DRIVER' where status = 'SEARCHING'
    and status_at < now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision);
  get diagnostics k = row_count; n := n + k;
  with stale as (
    select t.id, t.driver_id, t.vehicle_id from tasks t
    where t.status in ('MATCHED', 'ARRIVED')
      and not exists (select 1 from driver_presence p where p.profile_id = t.driver_id and p.updated_at > now() - interval '10 minutes')
    for update of t skip locked
  ), ev as (
    insert into task_events (task_id, driver_id, vehicle_id, event) select id, driver_id, vehicle_id, 'CANCELLED' from stale where driver_id is not null returning 1
  )
  update tasks x set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null, pin = public.new_pin(), pin_attempts = 0
    from stale s where x.id = s.id;
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;

-- ---------- staff: closing a trip that is stuck ----------
-- The rider can cancel a trip under way only once the driver has been silent for 10 minutes, and the driver can complete it only near the
-- drop (or once max(30 min, 6 min per km) have passed). When neither happens (both phones off, a dispute) a Bucks staff member closes it here:
-- COMPLETED (the trip was made: the rider can pay and review, a delivery order is DELIVERED) or CANCELLED (it was not: the driver gets a
-- MISSED event, a delivery order is CANCELLED with its stock returned). Only a trip under way: searching, matched and arrived trips
-- expire on their own (expire_tasks). Staff are the rows of the staff table (services.sql).
create or replace function public.staff_close_task(p_task uuid, p_outcome text default 'COMPLETED') returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  if not is_staff() then raise exception 'only Bucks staff can close a trip'; end if;
  if p_outcome is null or p_outcome not in ('COMPLETED', 'CANCELLED') then raise exception 'the outcome is COMPLETED or CANCELLED'; end if;
  select * into t from tasks where id = p_task for update;
  if not found then raise exception 'task not found'; end if;
  if t.status <> 'IN_PROGRESS' then raise exception 'only a trip under way can be closed here (this one is %)', t.status; end if;
  if p_outcome = 'COMPLETED' then
    insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, t.driver_id, t.vehicle_id, 'COMPLETED', t.km, t.fare);
    if t.order_id is not null then update orders set status = 'DELIVERED' where id = t.order_id and status = 'PICKED_UP'; end if;
  else
    insert into task_events (task_id, driver_id, vehicle_id, event) values (t.id, t.driver_id, t.vehicle_id, 'MISSED');
    if t.order_id is not null then update orders set status = 'CANCELLED', cancelled_by = 'BUYER' where id = t.order_id and status = 'PICKED_UP'; end if;
  end if;
  update tasks set status = p_outcome where id = t.id;
  return p_outcome;
end $$;

-- ---------- what the app reads: tasks_geo gains pin_attempts (appended, so nothing shifts) ----------
create or replace view public.tasks_geo with (security_invoker = true) as
  select t.id, t.type, t.requester_id, t.order_id, t.vehicle_kind, t.pickup, t.pickup_label, t.drop_at, t.drop_label, t.km, t.fare,
         case when t.requester_id = public.me() then coalesce(public.task_pin(t.id), '') else '' end as pin,
         t.only_riders, t.status, t.driver_id, t.vehicle_id, t.driver_location, t.paid_with, t.created_at, t.status_at,
         st_y(t.pickup::geometry)          as pickup_lat, st_x(t.pickup::geometry)          as pickup_lng,
         st_y(t.drop_at::geometry)         as drop_lat,   st_x(t.drop_at::geometry)         as drop_lng,
         st_y(t.driver_location::geometry) as driver_lat, st_x(t.driver_location::geometry) as driver_lng,
         case when t.order_id is null then null else public.order_item_count(t.order_id) end as order_items,
         case when t.order_id is null then null else public.order_collect(t.order_id) end as collect,
         t.pin_attempts
  from public.tasks t;

-- ---------- existing data ----------
-- Presence rows whose vehicle is not ACTIVE go offline. Requests that already outlived the ring window stop searching. A requester
-- left with several open rides keeps the furthest along (then the newest) so the one-open-ride index can be built.
update public.driver_presence p set online = false
  where p.online and not exists (select 1 from public.vehicles v where v.id = p.vehicle_id and v.status = 'ACTIVE');
update public.tasks set status = 'NO_DRIVER' where status = 'SEARCHING'
  and status_at < now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision);
with ranked as (
  select id, row_number() over (partition by requester_id order by case status when 'IN_PROGRESS' then 4 when 'ARRIVED' then 3 when 'MATCHED' then 2 else 1 end desc, created_at desc, id desc) as n
  from public.tasks where type = 'RIDE' and order_id is null and status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS'))
update public.tasks t set status = 'CANCELLED' from ranked r where t.id = r.id and r.n > 1;
create unique index if not exists tasks_one_open_ride on public.tasks (requester_id)
  where type = 'RIDE' and order_id is null and status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS');

-- ---------- schedule ----------
do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('bucks-expire-tasks', '* * * * *', 'select public.expire_tasks()');
  end if;
end $$;

-- ---------- grants ----------
revoke execute on function public.can_claim(text, text, geography, uuid, uuid[], timestamptz), public.claim_task(uuid), public.open_tasks_near(double precision, double precision),
  public.advance_task(uuid, text, text, text), public.staff_close_task(uuid, text),
  public.request_ride(text, double precision, double precision, text, double precision, double precision, text, numeric, integer),
  public.update_location(double precision, double precision), public.online_drivers_near(double precision, double precision, integer),
  public.contact_for_task(uuid), public.contact_for_order(uuid), public.review(uuid, uuid, uuid, integer, text),
  public.place_order(uuid, jsonb, double precision, double precision, text, text, text) from public, anon;
grant execute on function public.can_claim(text, text, geography, uuid, uuid[], timestamptz), public.claim_task(uuid), public.open_tasks_near(double precision, double precision),
  public.advance_task(uuid, text, text, text), public.staff_close_task(uuid, text),
  public.request_ride(text, double precision, double precision, text, double precision, double precision, text, numeric, integer),
  public.update_location(double precision, double precision), public.online_drivers_near(double precision, double precision, integer),
  public.contact_for_task(uuid), public.contact_for_order(uuid), public.review(uuid, uuid, uuid, integer, text),
  public.place_order(uuid, jsonb, double precision, double precision, text, text, text) to authenticated;
-- Helpers, trigger bodies and the cron job run only from inside other functions, as triggers, or as the database owner.
revoke execute on function public.dispatch_cfg(text, numeric), public.new_pin(), public.driver_near_check(geography, text, numeric, text), public.expire_tasks(),
  public.presence_touch(), public.presence_clamp(), public.vehicle_offline(), public.tasks_hygiene(), public.orders_hygiene() from public, anon, authenticated;
