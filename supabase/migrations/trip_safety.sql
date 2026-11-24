-- Trip safety (2026-11-13): trusted contacts, SOS, live trip links and ride alerts. Safe to re-run. See docs/SAFETY.md.
--
--   trusted_contacts  up to 5 people (name + Indian mobile) per account. SOS and "Share trip" text them from the phone's own SMS app.
--   trip_shares       an unguessable token per trip. The page docs/trip/ (GitHub Pages) reads it through the Edge Function "trip"
--                     (service role, trip_share_view), so a contact without Bucks can follow the trip live. Location stops at the drop.
--   sos_events        raise_sos(): during a ride or delivery (rider or driver) or any time. Pushes every staff member at once
--                     (functions/notify), and staff see the open ones in sos_queue(). The phone also dials 112 itself.
--   ride_alerts       ride_watch() (pg_cron, every minute) looks at rides in progress: stopped for long, off the route, or the
--                     driver's phone silent. The rider gets "Are you OK?" (push + in-app card). Unanswered for 5 minutes: an SOS is
--                     raised for them automatically.

-- ---------- settings ----------
insert into public.settings (key, value) values
  ('ride_stop_alert_minutes', 8),     -- no movement for this long while a ride is in progress
  ('ride_silent_alert_minutes', 6),   -- the driver's phone sent no location for this long
  ('ride_offroute_m', 3000),          -- further from the drop than the pickup was, by this much
  ('ride_alert_escalate_minutes', 5)  -- "Are you OK?" not answered in this time: automatic SOS
on conflict (key) do nothing;

-- ---------- trusted contacts ----------
create table if not exists public.trusted_contacts (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles on delete cascade,
  name        text not null check (length(btrim(name)) between 1 and 60),
  phone       text not null check (phone ~ '^\+91[6-9][0-9]{9}$'),
  created_at  timestamptz not null default now(),
  unique (profile_id, phone)
);
alter table public.trusted_contacts enable row level security;
drop policy if exists trusted_contacts_own on public.trusted_contacts;
create policy trusted_contacts_own on public.trusted_contacts for select to authenticated using (profile_id = (select me()));
revoke all on public.trusted_contacts from public, anon;   -- signed-out callers get nothing (Supabase grants anon by default)
revoke insert, update, delete on public.trusted_contacts from authenticated;
grant select on public.trusted_contacts to authenticated;

create or replace function public.add_trusted_contact(p_name text, p_phone text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); ph text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'); rid uuid;
begin
  if my is null then raise exception 'not signed in'; end if;
  if ph ~ '^[6-9][0-9]{9}$' then ph := '+91' || ph; elsif ph ~ '^91[6-9][0-9]{9}$' then ph := '+' || ph; elsif ph ~ '^0[6-9][0-9]{9}$' then ph := '+91' || substr(ph, 2); end if;
  if ph !~ '^\+91[6-9][0-9]{9}$' then raise exception 'enter a 10-digit Indian mobile number'; end if;
  if ph = (select phone from profile_private where profile_id = my) then raise exception 'add someone other than yourself'; end if;
  if length(btrim(coalesce(p_name, ''))) = 0 then raise exception 'enter their name'; end if;
  if (select count(*) from trusted_contacts where profile_id = my) >= 5 and not exists (select 1 from trusted_contacts where profile_id = my and phone = ph) then
    raise exception 'you can have 5 trusted contacts; remove one first';
  end if;
  insert into trusted_contacts (profile_id, name, phone) values (my, left(btrim(p_name), 60), ph)
  on conflict (profile_id, phone) do update set name = excluded.name
  returning id into rid;
  return rid;
end $$;

create or replace function public.remove_trusted_contact(p_id uuid) returns void
language sql security definer set search_path = public, extensions as $$
  delete from trusted_contacts where id = p_id and profile_id = me()
$$;

-- ---------- live trip links ----------
create table if not exists public.trip_shares (
  token       text primary key,
  task_id     uuid not null references public.tasks on delete cascade,
  created_by  uuid not null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index if not exists trip_shares_task on public.trip_shares (task_id);
alter table public.trip_shares enable row level security;
revoke all on public.trip_shares from public, anon, authenticated;

-- The link for my current trip (as the rider or the driver); the same link again while it is valid.
create or replace function public.trip_share_link(p_task uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); t tasks; tok text;
begin
  if my is null then raise exception 'not signed in'; end if;
  select * into t from tasks where id = p_task;
  if not found or my not in (t.requester_id, coalesce(t.driver_id, '00000000-0000-0000-0000-000000000000'::uuid)) then raise exception 'not your trip'; end if;
  if t.status not in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS') then raise exception 'this trip has ended'; end if;
  select token into tok from trip_shares where task_id = p_task and created_by = my and expires_at > now() order by created_at desc limit 1;
  if tok is not null then return tok; end if;
  tok := translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
  insert into trip_shares (token, task_id, created_by, expires_at) values (tok, p_task, my, now() + interval '12 hours');
  return tok;
end $$;

-- What the trip page shows. Called only by the Edge Function "trip" (service role). Live location only while the trip is on.
create or replace function public.trip_share_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s trip_shares; t tasks; v vehicles; drv profiles; req profiles; live boolean; sos boolean;
begin
  select * into s from trip_shares where token = p_token and expires_at > now();
  if not found then return null; end if;
  select * into t from tasks where id = s.task_id;
  if not found then return null; end if;
  select * into v from vehicles where id = t.vehicle_id;
  select * into drv from profiles where id = t.driver_id;
  select * into req from profiles where id = t.requester_id;
  live := t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS');
  sos := exists (select 1 from sos_events e where e.task_id = t.id and e.status = 'OPEN');
  return jsonb_build_object(
    'status', t.status, 'type', t.type, 'updated_at', t.status_at,
    'rider', split_part(coalesce(req.name, ''), ' ', 1),
    'driver', case when t.driver_id is not null then drv.name end,
    'vehicle', case when v.id is not null then jsonb_build_object('kind', v.kind, 'model', v.model, 'plate', v.plate) end,
    'pickup', jsonb_build_object('label', t.pickup_label, 'lat', st_y(t.pickup::geometry), 'lng', st_x(t.pickup::geometry)),
    'drop', jsonb_build_object('label', t.drop_label, 'lat', st_y(t.drop_at::geometry), 'lng', st_x(t.drop_at::geometry)),
    'driver_at', case when live and t.driver_location is not null then jsonb_build_object('lat', st_y(t.driver_location::geometry), 'lng', st_x(t.driver_location::geometry),
                      'at', (select coalesce(p.located_at, p.updated_at) from driver_presence p where p.profile_id = t.driver_id)) end,
    'started_at', t.started_at, 'completed_at', t.completed_at, 'sos', sos);
end $$;
revoke execute on function public.trip_share_view(text) from public, anon, authenticated;

-- ---------- SOS ----------
create table if not exists public.sos_events (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles,
  task_id     uuid references public.tasks on delete set null,
  role        text not null check (role in ('RIDER', 'DRIVER', 'NONE', 'AUTO')),
  location    geography(Point, 4326),
  share_token text,
  status      text not null default 'OPEN' check (status in ('OPEN', 'CLOSED')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  closed_by   uuid,
  closed_at   timestamptz,
  note        text
);
create index if not exists sos_events_open on public.sos_events (created_at desc) where status = 'OPEN';
alter table public.sos_events enable row level security;
drop policy if exists sos_events_own on public.sos_events;
create policy sos_events_own on public.sos_events for select to authenticated using (profile_id = (select me()) or (select is_staff()));
revoke all on public.sos_events from public, anon;   -- signed-out callers get nothing (Supabase grants anon by default)
revoke insert, update, delete on public.sos_events from authenticated;
grant select on public.sos_events to authenticated;

-- Raises an SOS (never refused for a signed-in person). A second press within 10 minutes updates the same one with the new location.
-- Returns what the phone needs to alert people: the trip link, my trusted contacts and a ready message.
create or replace function public.raise_sos(p_task uuid default null, p_lat double precision default null, p_lng double precision default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); t tasks; r text := 'NONE'; here geography; sid uuid; tok text; v vehicles; drv text; msg text;
begin
  if my is null then raise exception 'not signed in'; end if;
  here := case when p_lat between -90 and 90 and p_lng between -180 and 180 then geo(p_lat, p_lng) end;
  if p_task is not null then
    select * into t from tasks where id = p_task;
    if found and my = t.requester_id then r := 'RIDER'; elsif found and my = t.driver_id then r := 'DRIVER'; else t := null; end if;
  end if;
  if t.id is not null and t.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS') then tok := trip_share_link(t.id); end if;
  select id into sid from sos_events where profile_id = my and status = 'OPEN' and created_at > now() - interval '10 minutes'
    and task_id is not distinct from t.id order by created_at desc limit 1;
  if sid is not null then
    update sos_events set location = coalesce(here, location), share_token = coalesce(tok, share_token), updated_at = now() where id = sid;
  else
    insert into sos_events (profile_id, task_id, role, location, share_token) values (my, t.id, r, here, tok) returning id into sid;
    insert into notifications (profile_id, kind, title, body, route)
      select s.profile_id, 'SOS', 'SOS: ' || coalesce(nullif((select name from profiles where id = my), ''), 'a Bucks user'),
             case r when 'RIDER' then 'A rider pressed SOS during a trip.' when 'DRIVER' then 'A driver pressed SOS during a trip.' else 'Someone pressed SOS.' end
             || ' Open the SOS queue and call them now.', ''
      from staff s;
  end if;
  if t.id is not null then
    select * into v from vehicles where id = t.vehicle_id;
    select name into drv from profiles where id = case when r = 'RIDER' then t.driver_id else t.requester_id end;
  end if;
  msg := 'SOS from ' || coalesce(nullif(split_part((select name from profiles where id = my), ' ', 1), ''), 'me') || ' on Bucks. I need help.'
      || case when r = 'RIDER' and v.id is not null then ' I''m in ' || coalesce(v.model, 'a vehicle') || ' ' || coalesce(v.plate, '') || coalesce(' with ' || drv, '') || '.'
              when r = 'DRIVER' then coalesce(' My passenger is ' || drv || '.', '') else '' end
      || case when here is not null then ' My location: https://maps.google.com/?q=' || round(p_lat::numeric, 6) || ',' || round(p_lng::numeric, 6) else '' end
      || case when tok is not null then ' Live trip: https://infin8sync69-source.github.io/bucks-Mobile/trip/#' || tok else '' end
      || ' If you can''t reach me, call 112.';
  return jsonb_build_object('sos_id', sid, 'share_token', tok, 'message', msg,
    'contacts', coalesce((select jsonb_agg(jsonb_build_object('name', c.name, 'phone', c.phone) order by c.created_at) from trusted_contacts c where c.profile_id = my), '[]'));
end $$;

create or replace function public.cancel_sos(p_sos uuid) returns void
language sql security definer set search_path = public, extensions as $$
  update sos_events set status = 'CLOSED', closed_by = me(), closed_at = now(), note = coalesce(note, 'Cancelled by the person who raised it')
   where id = p_sos and profile_id = me() and status = 'OPEN'
$$;

-- Staff: open SOS alerts, newest first, with everything needed to act (call them, the other person, the vehicle, where).
create or replace function public.sos_queue(lim integer default 50) returns table (
  id uuid, created_at timestamptz, updated_at timestamptz, role text, name text, phone text, lat double precision, lng double precision,
  task_id uuid, task_status text, other_name text, other_phone text, vehicle text, trip_link text)
language plpgsql stable security definer set search_path = public, extensions as $$
#variable_conflict use_column
begin
  if not is_staff() then raise exception 'staff only'; end if;
  return query
  select e.id, e.created_at, e.updated_at, e.role, p.name, pp.phone,
         st_y(coalesce(e.location, t.driver_location)::geometry), st_x(coalesce(e.location, t.driver_location)::geometry),
         t.id, t.status, o.name, op.phone,
         case when v.id is not null then concat_ws(' ', v.kind, v.model, v.plate) end,
         case when e.share_token is not null then 'https://infin8sync69-source.github.io/bucks-Mobile/trip/#' || e.share_token end
  from sos_events e
  join profiles p on p.id = e.profile_id
  left join profile_private pp on pp.profile_id = e.profile_id
  left join tasks t on t.id = e.task_id
  left join profiles o on o.id = case when e.profile_id = t.requester_id then t.driver_id else t.requester_id end
  left join profile_private op on op.profile_id = o.id
  left join vehicles v on v.id = t.vehicle_id
  where e.status = 'OPEN'
  order by e.created_at desc
  limit greatest(1, least(coalesce(lim, 50), 200));
end $$;

create or replace function public.close_sos(p_sos uuid, p_note text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  update sos_events set status = 'CLOSED', closed_by = me(), closed_at = now(), note = left(btrim(coalesce(p_note, '')), 500) where id = p_sos;
end $$;

-- ---------- ride alerts ----------
create table if not exists public.ride_alerts (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks on delete cascade,
  rider_id    uuid not null,
  kind        text not null check (kind in ('STOPPED', 'OFF_ROUTE', 'SILENT')),
  created_at  timestamptz not null default now(),
  answered_at timestamptz,
  answer      text check (answer in ('OK', 'SOS')),
  escalated   boolean not null default false,
  unique (task_id, kind)
);
alter table public.ride_alerts enable row level security;
drop policy if exists ride_alerts_own on public.ride_alerts;
create policy ride_alerts_own on public.ride_alerts for select to authenticated using (rider_id = (select me()));
revoke all on public.ride_alerts from public, anon;   -- signed-out callers get nothing (Supabase grants anon by default)
revoke insert, update, delete on public.ride_alerts from authenticated;
grant select on public.ride_alerts to authenticated;

-- Unanswered alerts for my ride (the in-ride screen polls this).
create or replace function public.my_ride_alerts(p_task uuid) returns setof public.ride_alerts
language sql stable security definer set search_path = public, extensions as $$
  select * from ride_alerts where task_id = p_task and rider_id = me() and answered_at is null order by created_at
$$;

-- "I'm OK" answers every open alert for the trip; "SOS" raises one.
create or replace function public.answer_ride_alert(p_task uuid, p_ok boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  update ride_alerts set answered_at = now(), answer = case when p_ok then 'OK' else 'SOS' end
   where task_id = p_task and rider_id = me() and answered_at is null;
  if not p_ok then perform raise_sos(p_task, null, null); end if;
end $$;

-- Every minute (pg_cron). Only rides with passengers; deliveries carry goods.
create or replace function public.ride_watch() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int := 0; k int; stop_m numeric := coalesce(setting('ride_stop_alert_minutes'), 8); silent_m numeric := coalesce(setting('ride_silent_alert_minutes'), 6);
        off_m numeric := coalesce(setting('ride_offroute_m'), 3000); esc_m numeric := coalesce(setting('ride_alert_escalate_minutes'), 5); a record;
begin
  -- Stopped: the phone keeps reporting, but the position has not changed (presence_clamp freezes located_at while still).
  if stop_m > 0 then
    insert into ride_alerts (task_id, rider_id, kind)
    select t.id, t.requester_id, 'STOPPED' from tasks t join driver_presence p on p.profile_id = t.driver_id
     where t.type = 'RIDE' and t.status = 'IN_PROGRESS' and t.started_at < now() - make_interval(mins => stop_m::int)
       and p.updated_at > now() - interval '2 minutes' and coalesce(p.located_at, p.updated_at) < now() - make_interval(mins => stop_m::int)
    on conflict (task_id, kind) do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  -- Silent: the driver's phone stopped sending its location.
  if silent_m > 0 then
    insert into ride_alerts (task_id, rider_id, kind)
    select t.id, t.requester_id, 'SILENT' from tasks t left join driver_presence p on p.profile_id = t.driver_id
     where t.type = 'RIDE' and t.status = 'IN_PROGRESS' and t.started_at < now() - make_interval(mins => silent_m::int)
       and coalesce(p.updated_at, t.started_at) < now() - make_interval(mins => silent_m::int)
    on conflict (task_id, kind) do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  -- Off route: further from the drop than the pickup ever was, by a margin.
  if off_m > 0 then
    insert into ride_alerts (task_id, rider_id, kind)
    select t.id, t.requester_id, 'OFF_ROUTE' from tasks t
     where t.type = 'RIDE' and t.status = 'IN_PROGRESS' and t.driver_location is not null
       and st_distance(t.driver_location, t.drop_at) > st_distance(t.pickup, t.drop_at) + off_m
    on conflict (task_id, kind) do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  -- Nobody answered "Are you OK?": raise an SOS on the rider's behalf (staff are pushed at once).
  if esc_m > 0 then
    for a in select x.id, x.task_id, x.rider_id from ride_alerts x join tasks t on t.id = x.task_id
              where x.answered_at is null and not x.escalated and x.created_at < now() - make_interval(mins => esc_m::int) and t.status = 'IN_PROGRESS' loop
      insert into sos_events (profile_id, task_id, role, location, share_token)
      select a.rider_id, a.task_id, 'AUTO', t.driver_location, (select token from trip_shares s where s.task_id = a.task_id order by created_at desc limit 1)
        from tasks t where t.id = a.task_id
        and not exists (select 1 from sos_events e where e.task_id = a.task_id and e.status = 'OPEN');
      insert into notifications (profile_id, kind, title, body, route)
        select s.profile_id, 'SOS', 'Automatic SOS: a rider did not answer', 'A ride stopped, went off route or went silent, and the rider did not answer "Are you OK?". Open the SOS queue.', '' from staff s;
      update ride_alerts set escalated = true where id = a.id;
    end loop;
  end if;
  -- In-app notification for each new alert (the push comes from the ride_alerts trigger).
  insert into notifications (profile_id, kind, title, body, route)
    select x.rider_id, 'RIDE_CHECK', 'Are you OK?', case x.kind when 'STOPPED' then 'Your ride has stopped for a while.' when 'OFF_ROUTE' then 'Your ride looks off its route.' else 'We lost your driver''s location.' end
           || ' Open Bucks and tap I''m OK, or SOS.', ''
      from ride_alerts x where x.created_at > now() - interval '70 seconds' and x.answered_at is null
       and not exists (select 1 from notifications nn where nn.profile_id = x.rider_id and nn.kind = 'RIDE_CHECK' and nn.created_at > x.created_at - interval '1 second');
  return n;
end $$;
revoke execute on function public.ride_watch() from public, anon, authenticated;

-- ---------- pushes (functions/notify handles sos_events and ride_alerts) ----------
drop trigger if exists push_sos_events on public.sos_events;
create trigger push_sos_events after insert on public.sos_events for each row execute function public.push_notify();
drop trigger if exists push_ride_alerts on public.ride_alerts;
create trigger push_ride_alerts after insert on public.ride_alerts for each row execute function public.push_notify();

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('bucks-ride-watch', '* * * * *', 'select public.ride_watch()');
  end if;
end $$;

-- ---------- grants ----------
revoke execute on function public.add_trusted_contact(text, text), public.remove_trusted_contact(uuid), public.trip_share_link(uuid),
  public.raise_sos(uuid, double precision, double precision), public.cancel_sos(uuid), public.sos_queue(integer), public.close_sos(uuid, text),
  public.my_ride_alerts(uuid), public.answer_ride_alert(uuid, boolean) from public, anon;
grant execute on function public.add_trusted_contact(text, text), public.remove_trusted_contact(uuid), public.trip_share_link(uuid),
  public.raise_sos(uuid, double precision, double precision), public.cancel_sos(uuid), public.sos_queue(integer), public.close_sos(uuid, text),
  public.my_ride_alerts(uuid), public.answer_ride_alert(uuid, boolean) to authenticated;

-- Deleting an account removes its trusted contacts (cascade) and closes its open SOS alerts.
create or replace function public.sos_close_on_delete() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'DELETED' and old.status is distinct from 'DELETED' then
    update sos_events set status = 'CLOSED', closed_at = now(), note = coalesce(note, 'Account deleted') where profile_id = new.id and status = 'OPEN';
    delete from trusted_contacts where profile_id = new.id;
  end if;
  return new;
end $$;
revoke execute on function public.sos_close_on_delete() from public, anon, authenticated;
drop trigger if exists profile_sos_cleanup on public.profiles;
create trigger profile_sos_cleanup after update of status on public.profiles for each row execute function public.sos_close_on_delete();
