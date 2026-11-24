-- ============================================================================
-- Bucks: swarm Phase 1, signals and recovery (docs/ai/reports/Swarm intelligence for Bucks.md, "Phases open only when
-- measured density says so"). Apply after swarm_core.sql.
--
--   A3 demand field   area_signals: decayed per-cell counters (REQUEST, UNFILLED, COMPLETED, INTEREST, SUPPLY_ONLINE), lazy decay,
--                     area cells only (never coordinates, never user ids), never shown below signal_k_min events in 7 days, nothing
--                     from accounts that are not known adults. Drivers read it through recent_requests_near() (the "recent requests" card).
--   A4 recovery       recovery_offers: a ride that ended NO_DRIVER, or an order a shop turned down (OUT_OF_STOCK, CLOSED...), gets a
--                     recovery row; the app shows "Try again / Try a cab / Notify me" or "Similar shops nearby". It only proposes:
--                     nothing here creates a task or an order. A choice is recorded only from the person's own tap (recovery_choice).
--   Queues            pgmq recovery_q and nudge_q, sent in the same transaction as the business write (a transactional outbox);
--                     the swarm-worker Edge Function reads them with a visibility timeout and moves poison messages to agent_dead.
--   Learning          intent_feedback: opt-in, adults only, utterance redacted (phones, UPI ids, PINs), rate-limited per account.
--   Metrics           swarm_metrics_daily: nightly rollup per area cell (zone) and day (IST).
--
-- Every new switch defaults to 0 (off): demand_field_enabled, recovery_enabled, intent_feedback_enabled. With them off the only writes
-- are recovery_offers rows (measurement, like Phase 0's offer log) and the nightly rollup. A queue or worker failure never blocks a
-- ride, an order or a status change: enqueueing swallows its own errors.
-- Works without pgmq / pg_cron / pg_net (the CI database has none of them): those parts are skipped.
-- Idempotent; safe to re-run.
-- ============================================================================

insert into public.settings (key, value) values
  ('demand_field_enabled', 0),        -- A3: write area_signals and answer recent_requests_near
  ('recovery_enabled', 0),            -- A4: enqueue recovery_q / nudge_q, send recovery pushes, accept "Notify me"
  ('intent_feedback_enabled', 0),     -- accept intent_feedback rows (the app also asks the person first)
  ('signal_tau_s', 10800),            -- decay time constant of area_signals in seconds (3 h for rural Kodagu; 3600 for towns)
  ('signal_k_min', 3),                -- a cell shows nothing until it has this many events in 7 days
  ('recovery_alert_minutes', 120),    -- how long a "Notify me when a driver is online" request lasts
  ('swarm_dead_after', 5),            -- a queue message read more than this many times goes to agent_dead
  ('rate_intent_feedback_per_hour', 30)
on conflict (key) do nothing;

-- ---------- pgmq: install when available (Supabase has 1.5.1), create the two queues ----------
do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pgmq') and not exists (select 1 from pg_extension where extname = 'pgmq') then
    create extension pgmq;
  end if;
  if exists (select 1 from pg_extension where extname = 'pgmq') then
    if not exists (select 1 from pgmq.meta where queue_name = 'recovery_q') then perform pgmq.create('recovery_q'); end if;
    if not exists (select 1 from pgmq.meta where queue_name = 'nudge_q') then perform pgmq.create('nudge_q'); end if;
  end if;
end $$;

-- The swarm-worker Edge Function (same project as notify_url()).
create or replace function public.swarm_worker_url() returns text language sql immutable set search_path = public, extensions as $$
  select replace(public.notify_url(), '/functions/v1/notify', '/functions/v1/swarm-worker')
$$;
revoke execute on function public.swarm_worker_url() from public, anon, authenticated;

-- Asks the worker to drain the queues now. pg_net queues the request and sends it only after the transaction commits, so a rolled-back
-- write never wakes the worker. No-op when recovery is off, pg_net is missing or there is no shared secret yet.
create or replace function public.swarm_kick() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare secret text;
begin
  if coalesce(setting('recovery_enabled'), 0) < 1 or to_regproc('net.http_post') is null then return; end if;
  select value into secret from push_config where key = 'webhook_secret';
  if coalesce(secret, '') = '' then return; end if;
  perform net.http_post(url := swarm_worker_url(), body := '{"drain":true}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-bucks-secret', secret), timeout_milliseconds := 5000);
exception when others then
  raise warning 'swarm_kick: %', sqlerrm;
end $$;
revoke execute on function public.swarm_kick() from public, anon, authenticated;

-- Sends one message in the caller's transaction (the business write and its message commit or roll back together).
-- Never raises: a missing extension or a queue error must not stop a ride or an order.
create or replace function public.swarm_enqueue(p_queue text, p_msg jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(setting('recovery_enabled'), 0) < 1 or to_regnamespace('pgmq') is null then return; end if;
  perform pgmq.send(p_queue, p_msg);
  perform swarm_kick();
exception when others then
  raise warning 'swarm_enqueue(%): %', p_queue, sqlerrm;
end $$;
revoke execute on function public.swarm_enqueue(text, jsonb) from public, anon, authenticated;

-- ---------- area cells: the 3 x 3 block around a cell ----------
create or replace function public.area_cell_at(lat double precision, lng double precision) returns text
language sql stable set search_path = public, extensions as $$
  select floor(lat / d)::bigint || ':' || floor(lng / d)::bigint
  from (select coalesce(nullif(public.setting('area_cell_deg'), 0), 0.05) d) s
$$;
create or replace function public.area_block(p_cell text) returns text[]
language sql immutable set search_path = public, extensions as $$
  select coalesce(array_agg((split_part(p_cell, ':', 1)::bigint + dr) || ':' || (split_part(p_cell, ':', 2)::bigint + dc)), '{}')
  from generate_series(-1, 1) dr, generate_series(-1, 1) dc
  where p_cell ~ '^-?\d+:-?\d+$'
$$;

-- Only known adults feed the field and the metrics (DPDP Act s.9(3): no behavioural monitoring of children). An unknown age counts
-- as not an adult, the same rule map_guardrails.sql uses.
create or replace function public.swarm_counts(p uuid) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select p is not null and age_band_of(p) = 'ADULT'
$$;
revoke execute on function public.swarm_counts(uuid) from public, anon, authenticated;

-- ============================================================================
-- A3: the demand field
-- ============================================================================
create table if not exists public.area_signals (
  cell        text not null,
  signal      text not null check (signal in ('REQUEST', 'UNFILLED', 'COMPLETED', 'INTEREST', 'SUPPLY_ONLINE')),
  service     text not null default 'RIDE',
  score       double precision not null default 0,   -- decayed to updated_at; read through area_heat()
  updated_at  timestamptz not null default now(),
  primary key (cell, signal, service)
);
-- Hourly event counts per cell, kept 8 days: the k-threshold (events in 7 days) and "in the last 3 hours" read these.
create table if not exists public.area_signal_hours (
  cell     text not null,
  signal   text not null,
  service  text not null,
  hour     timestamptz not null,
  n        integer not null default 0,
  primary key (cell, signal, service, hour)
);
alter table public.area_signals enable row level security;
alter table public.area_signal_hours enable row level security;
revoke all on public.area_signals, public.area_signal_hours from public, anon, authenticated;
drop policy if exists area_signals_staff on public.area_signals;
create policy area_signals_staff on public.area_signals for select to authenticated using (public.is_staff());
grant select on public.area_signals to authenticated;

-- score(t) = score(t0) * exp(-(t - t0) / tau) + w, applied at write time; a read applies the same decay, so no cron evaporates it.
create or replace function public.bump_signal(p_cell text, p_signal text, p_service text, p_w double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare tau double precision := coalesce(nullif(setting('signal_tau_s'), 0), 10800);
begin
  if coalesce(setting('demand_field_enabled'), 0) < 1 or p_cell is null then return; end if;
  insert into area_signals as a (cell, signal, service, score, updated_at) values (p_cell, p_signal, p_service, p_w, now())
  on conflict (cell, signal, service) do update
    set score = a.score * exp(-greatest(extract(epoch from now() - a.updated_at), 0) / tau) + p_w, updated_at = now();
  insert into area_signal_hours as h (cell, signal, service, hour, n) values (p_cell, p_signal, p_service, date_trunc('hour', now()), 1)
  on conflict (cell, signal, service, hour) do update set n = h.n + 1;
exception when others then
  raise warning 'bump_signal: %', sqlerrm;   -- the field is best effort; never block the write that fed it
end $$;
revoke execute on function public.bump_signal(text, text, text, double precision) from public, anon, authenticated;

-- Events of a cell in the last p_hours.
create or replace function public.area_events(p_cell text, p_signal text, p_service text, p_hours int) returns integer
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(sum(n), 0)::int from area_signal_hours
   where cell = p_cell and signal = p_signal and service = p_service and hour > now() - make_interval(hours => p_hours)
$$;
revoke execute on function public.area_events(text, text, text, int) from public, anon, authenticated;

-- A cell's heat, decayed to now; nothing for a cell under the k-threshold (all signals of that service over 7 days).
create or replace function public.area_heat(p_cell text, p_service text default 'RIDE')
returns table (signal text, heat double precision)
language sql stable security definer set search_path = public, extensions as $$
  select a.signal, a.score * exp(-greatest(extract(epoch from now() - a.updated_at), 0) / coalesce(nullif(setting('signal_tau_s'), 0), 10800))
    from area_signals a
   where a.cell = p_cell and a.service = p_service
     and (select coalesce(sum(n), 0) from area_signal_hours h where h.cell = p_cell and h.service = p_service and h.hour > now() - interval '7 days')
         >= coalesce(setting('signal_k_min'), 3)
$$;
revoke execute on function public.area_heat(text, text) from public, anon, authenticated;
grant execute on function public.area_heat(text, text) to service_role;

-- Field keeper triggers. Task service is RIDE or DELIVERY; supply follows the vehicle (bikes carry goods only).
create or replace function public.signal_from_task() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c text;
begin
  if coalesce(setting('demand_field_enabled'), 0) < 1 or not swarm_counts(new.requester_id) or new.pickup is null then return null; end if;
  c := area_cell(new.pickup);
  if tg_op = 'INSERT' then
    perform bump_signal(c, 'REQUEST', new.type, 1);
  elsif new.status is distinct from old.status then
    if new.status = 'NO_DRIVER'
       or (new.status = 'CANCELLED' and old.status = 'SEARCHING' and new.cancelled_by = 'RIDER' and new.cancel_reason = 'TOO_LONG') then
      perform bump_signal(c, 'UNFILLED', new.type, 3);
    elsif new.status = 'COMPLETED' then
      perform bump_signal(c, 'COMPLETED', new.type, 1);
    end if;
  end if;
  return null;
end $$;
revoke execute on function public.signal_from_task() from public, anon, authenticated;
drop trigger if exists signal_from_task on public.tasks;
create trigger signal_from_task after insert or update of status on public.tasks for each row execute function public.signal_from_task();

create or replace function public.signal_from_interest() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(setting('demand_field_enabled'), 0) < 1 or not swarm_counts(new.profile_id) or new.location is null then return null; end if;
  perform bump_signal(area_cell(new.location), 'INTEREST', new.service, 0.5);
  return null;
end $$;
revoke execute on function public.signal_from_interest() from public, anon, authenticated;
drop trigger if exists signal_from_interest on public.service_interest;
create trigger signal_from_interest after insert on public.service_interest for each row execute function public.signal_from_interest();

-- ============================================================================
-- A4: recovery
-- ============================================================================
create table if not exists public.recovery_offers (
  id            uuid primary key default public.uuid_v7(),
  subject_kind  text not null check (subject_kind in ('TASK', 'ORDER')),
  subject_id    uuid not null,
  profile_id    uuid not null references public.profiles on delete cascade,   -- the rider or buyer it is for
  service       text not null,                -- RIDE / DELIVERY, or the order's listing service
  vehicle_kind  text,                          -- rides: the kind that found nobody
  reason        text not null,                 -- NO_DRIVER, REJECTED, OUT_OF_STOCK, CLOSED...
  cell          text,                          -- area_cell of the pickup or drop, never coordinates
  shown_at      timestamptz not null default now(),
  notified_at   timestamptz,                   -- when swarm-worker pushed it (recovery_enabled)
  choice        text check (choice in ('TRY_AGAIN', 'TRY_CAB', 'NOTIFY_ME', 'SIMILAR_SHOPS', 'DISMISS')),
  chosen_at     timestamptz,                   -- set only by recovery_choice(), i.e. the person's own tap
  followup_id   uuid,                          -- the task or order the person then booked themselves
  followup_at   timestamptz,
  unique (subject_kind, subject_id)
);
create index if not exists recovery_offers_profile on public.recovery_offers (profile_id, shown_at desc);
create index if not exists recovery_offers_shown on public.recovery_offers (shown_at);
alter table public.recovery_offers enable row level security;
drop policy if exists recovery_offers_read on public.recovery_offers;
create policy recovery_offers_read on public.recovery_offers for select to authenticated
  using (profile_id = public.me() or public.is_staff());
revoke all on public.recovery_offers from anon, authenticated;
grant select on public.recovery_offers to authenticated;

-- "Notify me when a driver is online": one per person and vehicle kind, for recovery_alert_minutes. Deleted once sent or expired.
create table if not exists public.recovery_alerts (
  profile_id    uuid not null references public.profiles on delete cascade,
  vehicle_kind  text not null,
  cell          text not null,
  until         timestamptz not null,
  primary key (profile_id, vehicle_kind)
);
create index if not exists recovery_alerts_cell on public.recovery_alerts (cell, vehicle_kind);
alter table public.recovery_alerts enable row level security;
drop policy if exists recovery_alerts_read on public.recovery_alerts;
create policy recovery_alerts_read on public.recovery_alerts for select to authenticated using (profile_id = public.me());
revoke all on public.recovery_alerts from anon, authenticated;
grant select on public.recovery_alerts to authenticated;

-- Agent audit trail (Phase 1 subset of agent_runs / agent_events) and the dead-letter table pgmq lacks.
create table if not exists public.agent_events (
  id            uuid primary key default public.uuid_v7(),
  agent         text not null,                 -- 'A4_recovery', 'A4_alert', 'swarm-worker'
  subject_kind  text,
  subject_id    uuid,
  kind          text not null,                 -- PROPOSED, NOTIFIED, SKIPPED, DEAD
  detail        jsonb not null default '{}',
  created_at    timestamptz not null default now()
);
create index if not exists agent_events_subject on public.agent_events (subject_kind, subject_id);
create index if not exists agent_events_at on public.agent_events (created_at);
create table if not exists public.agent_dead (
  id          uuid primary key default public.uuid_v7(),
  queue       text not null,
  msg_id      bigint not null,
  read_ct     integer not null,
  message     jsonb not null,
  error       text,
  created_at  timestamptz not null default now()
);
alter table public.agent_events enable row level security;
alter table public.agent_dead enable row level security;
drop policy if exists agent_events_staff on public.agent_events;
create policy agent_events_staff on public.agent_events for select to authenticated using (public.is_staff());
drop policy if exists agent_dead_staff on public.agent_dead;
create policy agent_dead_staff on public.agent_dead for select to authenticated using (public.is_staff());
revoke all on public.agent_events, public.agent_dead from anon, authenticated;
grant select on public.agent_events, public.agent_dead to authenticated;

-- A ride that found nobody, or an order a shop turned down: record the recovery offer (always: it is the denominator of recovery
-- conversion) and, with recovery on, enqueue it for the worker's push. AFTER trigger: it sees the committed status, blocks nothing.
create or replace function public.recovery_from_task() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare oid uuid;
begin
  if new.status is not distinct from old.status or new.status <> 'NO_DRIVER' or new.type <> 'RIDE' then return null; end if;
  insert into recovery_offers (subject_kind, subject_id, profile_id, service, vehicle_kind, reason, cell)
  values ('TASK', new.id, new.requester_id, new.type, new.vehicle_kind, 'NO_DRIVER', case when new.pickup is null then null else area_cell(new.pickup) end)
  on conflict (subject_kind, subject_id) do nothing returning id into oid;
  if oid is not null then perform swarm_enqueue('recovery_q', jsonb_build_object('kind', 'RIDE_NO_DRIVER', 'offer', oid, 'task', new.id)); end if;
  return null;
end $$;
revoke execute on function public.recovery_from_task() from public, anon, authenticated;
drop trigger if exists recovery_from_task on public.tasks;
create trigger recovery_from_task after update of status on public.tasks for each row execute function public.recovery_from_task();

create or replace function public.recovery_from_order() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare oid uuid; svc text; loc geography;
begin
  if new.status is not distinct from old.status then return null; end if;
  -- Turned down by the shop (any reason), or cancelled by the shop for a reason another shop could fix.
  if not (new.status = 'REJECTED'
          or (new.status = 'CANCELLED' and new.cancelled_by = 'SHOP' and coalesce(new.cancel_reason, '') in ('OUT_OF_STOCK', 'CLOSED', 'CANT_DELIVER', 'TOO_FAR'))) then
    return null;
  end if;
  select service, location into svc, loc from listings where id = new.listing_id;
  insert into recovery_offers (subject_kind, subject_id, profile_id, service, reason, cell)
  values ('ORDER', new.id, new.buyer_id, coalesce(svc, 'SHOP'), coalesce(new.cancel_reason, new.status),
          case when coalesce(new.drop_location, loc) is null then null else area_cell(coalesce(new.drop_location, loc)) end)
  on conflict (subject_kind, subject_id) do nothing returning id into oid;
  if oid is not null then perform swarm_enqueue('recovery_q', jsonb_build_object('kind', 'ORDER_LOST', 'offer', oid, 'order', new.id)); end if;
  return null;
end $$;
revoke execute on function public.recovery_from_order() from public, anon, authenticated;
drop trigger if exists recovery_from_order on public.orders;
create trigger recovery_from_order after update of status on public.orders for each row execute function public.recovery_from_order();

-- The person's tap on the recovery card. The only way a choice is recorded; it books nothing (the app then runs today's booking flow
-- with its confirm sheet). Returns false when there is no recovery offer of theirs for that subject.
create or replace function public.recovery_choice(p_kind text, p_subject uuid, p_choice text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  if p_choice not in ('TRY_AGAIN', 'TRY_CAB', 'NOTIFY_ME', 'SIMILAR_SHOPS', 'DISMISS') then raise exception 'unknown choice'; end if;
  update recovery_offers set choice = p_choice, chosen_at = now()
   where subject_kind = p_kind and subject_id = p_subject and profile_id = me();
  return found;
end $$;
revoke execute on function public.recovery_choice(text, uuid, text) from public, anon;
grant execute on function public.recovery_choice(text, uuid, text) to authenticated;

-- Follow-ups: the task or order the person booked themselves after tapping a recovery choice (30 min for rides, 2 h for orders).
-- Attribution only; it is what "recovery conversion" counts.
create or replace function public.recovery_followup() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_table_name = 'tasks' then
    update recovery_offers set followup_id = new.id, followup_at = now()
     where id = (select id from recovery_offers where subject_kind = 'TASK' and profile_id = new.requester_id and followup_id is null
                   and choice in ('TRY_AGAIN', 'TRY_CAB', 'NOTIFY_ME') and shown_at > now() - interval '3 hours'
                   and coalesce(chosen_at, shown_at) > now() - interval '30 minutes' and subject_id <> new.id
                 order by shown_at desc limit 1);
  else
    update recovery_offers set followup_id = new.id, followup_at = now()
     where id = (select id from recovery_offers where subject_kind = 'ORDER' and profile_id = new.buyer_id and followup_id is null
                   and choice = 'SIMILAR_SHOPS' and chosen_at > now() - interval '2 hours'
                 order by shown_at desc limit 1);
  end if;
  return null;
exception when others then
  raise warning 'recovery_followup: %', sqlerrm;
  return null;
end $$;
revoke execute on function public.recovery_followup() from public, anon, authenticated;
drop trigger if exists recovery_followup on public.tasks;
create trigger recovery_followup after insert on public.tasks for each row execute function public.recovery_followup();
drop trigger if exists recovery_followup on public.orders;
create trigger recovery_followup after insert on public.orders for each row execute function public.recovery_followup();

-- "Notify me when a driver is online". False when recovery is switched off (the app says it can't do that yet).
create or replace function public.notify_me_when_driver_online(p_kind text, lat double precision, lng double precision) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  if p_kind not in ('AUTO', 'CAB', 'BIKE') then raise exception 'unknown vehicle kind'; end if;
  if coalesce(setting('recovery_enabled'), 0) < 1 then return false; end if;
  insert into recovery_alerts (profile_id, vehicle_kind, cell, until)
  values (me(), p_kind, area_cell_at(lat, lng), now() + make_interval(mins => coalesce(setting('recovery_alert_minutes'), 120)::int))
  on conflict (profile_id, vehicle_kind) do update set cell = excluded.cell, until = excluded.until;
  return true;
end $$;
revoke execute on function public.notify_me_when_driver_online(text, double precision, double precision) from public, anon;
grant execute on function public.notify_me_when_driver_online(text, double precision, double precision) to authenticated;

-- A driver coming online: SUPPLY_ONLINE for the field, and a nudge_q message for each live "Notify me" in the 3 x 3 block around them.
create or replace function public.swarm_from_presence() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c text; a record;
begin
  if not new.online or new.location is null or (tg_op = 'UPDATE' and old.online) then return null; end if;
  c := area_cell(new.location);
  if swarm_counts(new.profile_id) then
    perform bump_signal(c, 'SUPPLY_ONLINE', case when new.kind = 'BIKE' then 'DELIVERY' else 'RIDE' end, 1);
  end if;
  if coalesce(setting('recovery_enabled'), 0) >= 1 then
    for a in select profile_id, vehicle_kind from recovery_alerts
              where vehicle_kind = new.kind and until > now() and cell = any (area_block(c)) and profile_id <> new.profile_id loop
      perform swarm_enqueue('nudge_q', jsonb_build_object('kind', 'DRIVER_ONLINE', 'profile', a.profile_id, 'vehicle_kind', a.vehicle_kind));
    end loop;
  end if;
  return null;
exception when others then
  raise warning 'swarm_from_presence: %', sqlerrm;
  return null;
end $$;
revoke execute on function public.swarm_from_presence() from public, anon, authenticated;
drop trigger if exists swarm_from_presence on public.driver_presence;
create trigger swarm_from_presence after insert or update of online on public.driver_presence for each row execute function public.swarm_from_presence();

-- "Similar shops nearby" for an order a shop turned down: up to 3 other shops within 10 km of the drop (or the shop) that list the
-- rejected lines' items, best match first. Read-only, the buyer only. SECURITY INVOKER so search_listings applies the caller's own
-- visibility rules (blocked people, hidden pages, the content screen). The buyer opens a shop and orders through today's cart.
create or replace function public.order_alternatives(p_order uuid)
returns table (listing_id uuid, title text, photo_url text, area text, distance_m double precision, matched_items text[], min_price integer)
language plpgsql stable security invoker set search_path = public, extensions as $$
declare o record; loc geography; lat double precision; lng double precision;
begin
  select x.id, x.listing_id, x.buyer_id, x.status, x.lines, x.drop_location into o from orders x where x.id = p_order;
  if o.id is null or o.buyer_id is distinct from me() then raise exception 'order not found'; end if;
  if o.status not in ('REJECTED', 'CANCELLED') then return; end if;
  loc := coalesce(o.drop_location, (select l.location from listings l where l.id = o.listing_id));
  if loc is null then return; end if;
  lat := st_y(loc::geometry); lng := st_x(loc::geometry);
  return query
    with names as (
      select distinct trim(e ->> 'name') as nm from jsonb_array_elements(coalesce(o.lines, '[]'::jsonb)) e
       where length(trim(coalesce(e ->> 'name', ''))) >= 2 limit 5
    ), hits as (
      select s.id, s.title, s.photo_url, s.area, s.distance_m, n.nm, coalesce(s.matched_price, s.min_price) as price
        from names n, lateral search_listings(n.nm, lat, lng, 10000, null, 10, null) s
       where s.id <> o.listing_id and s.matched_item is not null
    )
    select h.id, min(h.title), min(h.photo_url), min(h.area), min(h.distance_m), array_agg(distinct h.nm), min(h.price)
      from hits h group by h.id
     order by count(distinct h.nm) desc, min(h.distance_m) asc
     limit 3;
end $$;
revoke execute on function public.order_alternatives(uuid) from public, anon;
grant execute on function public.order_alternatives(uuid) to authenticated;

-- A driver's "recent requests nearby" card: the 3 x 3 block of area cells around them, cells under the k-threshold left out, counts
-- under the threshold not shown. No row when the field is off, the caller is not a driver or there is nothing to say.
create or replace function public.recent_requests_near(lat double precision, lng double precision)
returns table (requests_3h integer, requests_7d integer, unfilled_7d integer, drivers_online integer)
language plpgsql stable security definer set search_path = public, extensions as $$
declare k int := coalesce(setting('signal_k_min'), 3)::int; blk text[]; cells text[]; r3 int; r7 int; u7 int; d int;
begin
  if coalesce(setting('demand_field_enabled'), 0) < 1 or me() is null then return; end if;
  if not exists (select 1 from driver_presence where profile_id = me()) then return; end if;
  blk := area_block(area_cell_at(lat, lng));
  select coalesce(array_agg(cell), '{}') into cells from (
    select cell from area_signal_hours where cell = any (blk) and hour > now() - interval '7 days' and signal in ('REQUEST', 'UNFILLED')
     group by cell having sum(n) >= k) s;
  if cardinality(cells) = 0 then return; end if;
  select coalesce(sum(n) filter (where signal = 'REQUEST' and hour > now() - interval '3 hours'), 0),
         coalesce(sum(n) filter (where signal = 'REQUEST'), 0),
         coalesce(sum(n) filter (where signal = 'UNFILLED'), 0)
    into r3, r7, u7
    from area_signal_hours where cell = any (cells) and hour > now() - interval '7 days';
  select count(*) into d from driver_presence p
   where p.online and p.location is not null and p.updated_at > now() - interval '15 minutes' and area_cell(p.location) = any (blk);
  return query select case when r3 >= k then r3 end, r7, case when u7 >= k then u7 else 0 end, d;
end $$;
revoke execute on function public.recent_requests_near(double precision, double precision) from public, anon;
grant execute on function public.recent_requests_near(double precision, double precision) to authenticated;

-- ============================================================================
-- swarm-worker RPCs (service_role only). One message, one step, one transaction.
-- ============================================================================
create or replace function public.swarm_read(p_queue text, p_vt integer default 60, p_n integer default 10)
returns table (msg_id bigint, read_ct integer, message jsonb)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_queue not in ('recovery_q', 'nudge_q') then raise exception 'unknown queue'; end if;
  if to_regnamespace('pgmq') is null then return; end if;
  return query select m.msg_id, m.read_ct, m.message from pgmq.read(p_queue, greatest(p_vt, 10), least(greatest(p_n, 1), 50)) m;
end $$;

create or replace function public.swarm_archive(p_queue text, p_msg_id bigint) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_queue not in ('recovery_q', 'nudge_q') then raise exception 'unknown queue'; end if;
  return pgmq.archive(p_queue, p_msg_id);
end $$;

-- Poison message: keep it in agent_dead, take it off the queue, tell staff in their notifications.
create or replace function public.swarm_dead_letter(p_queue text, p_msg_id bigint, p_read_ct integer, p_message jsonb, p_error text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare s record;
begin
  if p_queue not in ('recovery_q', 'nudge_q') then raise exception 'unknown queue'; end if;
  insert into agent_dead (queue, msg_id, read_ct, message, error) values (p_queue, p_msg_id, p_read_ct, coalesce(p_message, '{}'), left(p_error, 1000));
  insert into agent_events (agent, kind, detail) values ('swarm-worker', 'DEAD', jsonb_build_object('queue', p_queue, 'msg_id', p_msg_id, 'error', left(p_error, 300)));
  perform pgmq.archive(p_queue, p_msg_id);
  for s in select profile_id from staff loop
    insert into notifications (profile_id, kind, title, body, route)
    values (s.profile_id, 'SWARM_DEAD', 'A swarm message failed', left(p_queue || ' #' || p_msg_id || ': ' || coalesce(p_error, ''), 240), null);
  end loop;
end $$;

-- What to do with one message. Returns {notes:[...]} for the worker to push (it honours notification settings and quiet hours) or
-- {skip:"why"}. Writes the in-app notification and the audit row here, in this transaction. Never creates a task or an order.
create or replace function public.swarm_step(p_queue text, p_message jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r recovery_offers; t tasks; o orders; shop text; n int; who uuid; vk text; title text; body text; route text;
begin
  if coalesce(setting('recovery_enabled'), 0) < 1 then return jsonb_build_object('skip', 'recovery_enabled is 0'); end if;
  case p_message ->> 'kind'
  when 'RIDE_NO_DRIVER' then
    select * into r from recovery_offers where id = (p_message ->> 'offer')::uuid;
    select * into t from tasks where id = (p_message ->> 'task')::uuid;
    if r.id is null or t.id is null then return jsonb_build_object('skip', 'gone'); end if;
    if r.notified_at is not null then return jsonb_build_object('skip', 'already notified'); end if;
    -- Already sorted: they booked again or tapped a choice in the app.
    if r.choice is not null or exists (select 1 from tasks x where x.requester_id = t.requester_id and x.created_at > t.created_at) then
      insert into agent_events (agent, subject_kind, subject_id, kind, detail) values ('A4_recovery', 'TASK', t.id, 'SKIPPED', '{"why":"already acted"}');
      return jsonb_build_object('skip', 'already acted');
    end if;
    title := 'No driver took your ride';
    body := 'Open Bucks to try again, try a cab, or be told when a driver is online nearby.';
    route := '';
    who := t.requester_id;
    update recovery_offers set notified_at = now() where id = r.id;
    insert into notifications (profile_id, kind, title, body, route) values (who, 'RECOVERY', title, body, nullif(route, ''));
    insert into agent_events (agent, subject_kind, subject_id, kind, detail) values ('A4_recovery', 'TASK', t.id, 'PROPOSED', '{"choices":["TRY_AGAIN","TRY_CAB","NOTIFY_ME"]}');
    return jsonb_build_object('notes', jsonb_build_array(jsonb_build_object('to', who, 'key', 'my_trips', 'type', 'tasks', 'title', title, 'body', body, 'route', route, 'tag', 'recovery-' || t.id)));
  when 'ORDER_LOST' then
    select * into r from recovery_offers where id = (p_message ->> 'offer')::uuid;
    select * into o from orders where id = (p_message ->> 'order')::uuid;
    if r.id is null or o.id is null then return jsonb_build_object('skip', 'gone'); end if;
    if r.notified_at is not null then return jsonb_build_object('skip', 'already notified'); end if;
    -- Is there anything to suggest? Another live shop within 10 km listing one of the items in stock.
    select count(distinct i.listing_id) into n
      from jsonb_array_elements(coalesce(o.lines, '[]'::jsonb)) e
      join items i on i.in_stock and i.name ilike '%' || trim(e ->> 'name') || '%' and length(trim(coalesce(e ->> 'name', ''))) >= 2
      join listings l on l.id = i.listing_id and l.status = 'LIVE' and l.id <> o.listing_id and not l.compliance_hold
     where st_dwithin(l.location, coalesce(o.drop_location, (select x.location from listings x where x.id = o.listing_id)), 10000);
    if coalesce(n, 0) = 0 then
      insert into agent_events (agent, subject_kind, subject_id, kind, detail) values ('A4_recovery', 'ORDER', o.id, 'SKIPPED', '{"why":"no similar shop"}');
      return jsonb_build_object('skip', 'no similar shop');
    end if;
    select l.title into shop from listings l where l.id = o.listing_id;
    title := 'Similar shops nearby';
    body := coalesce(shop, 'The shop') || ' couldn''t take your order. ' || least(n, 3) || case when n = 1 then ' shop nearby has' else ' shops nearby have' end || ' the same items.';
    route := 'similar-shops/' || o.id;
    who := o.buyer_id;
    update recovery_offers set notified_at = now() where id = r.id;
    insert into notifications (profile_id, kind, title, body, route) values (who, 'RECOVERY', title, body, route);
    insert into agent_events (agent, subject_kind, subject_id, kind, detail) values ('A4_recovery', 'ORDER', o.id, 'PROPOSED', jsonb_build_object('shops', least(n, 3)));
    return jsonb_build_object('notes', jsonb_build_array(jsonb_build_object('to', who, 'key', 'my_orders', 'type', 'orders', 'title', title, 'body', body, 'route', route, 'tag', 'recovery-' || o.id)));
  when 'DRIVER_ONLINE' then
    who := (p_message ->> 'profile')::uuid; vk := p_message ->> 'vehicle_kind';
    delete from recovery_alerts where profile_id = who and vehicle_kind = vk and until > now();
    if not found then return jsonb_build_object('skip', 'alert gone'); end if;
    title := 'A driver is online near you';
    body := 'Open Bucks to book your ride now.';
    insert into notifications (profile_id, kind, title, body, route) values (who, 'RECOVERY', title, body, 'home');
    insert into agent_events (agent, subject_kind, subject_id, kind, detail) values ('A4_alert', 'PROFILE', who, 'NOTIFIED', jsonb_build_object('vehicle_kind', vk));
    return jsonb_build_object('notes', jsonb_build_array(jsonb_build_object('to', who, 'key', 'my_trips', 'type', 'tasks', 'title', title, 'body', body, 'route', 'home', 'tag', 'driver-online-' || vk)));
  else
    raise exception 'unknown message kind %', coalesce(p_message ->> 'kind', 'null');
  end case;
end $$;

revoke execute on function public.swarm_read(text, integer, integer), public.swarm_archive(text, bigint),
  public.swarm_dead_letter(text, bigint, integer, jsonb, text), public.swarm_step(text, jsonb) from public, anon, authenticated;
grant execute on function public.swarm_read(text, integer, integer), public.swarm_archive(text, bigint),
  public.swarm_dead_letter(text, bigint, integer, jsonb, text), public.swarm_step(text, jsonb) to service_role;

-- ============================================================================
-- intent_feedback: opt-in, adults only, redacted, rate-limited
-- ============================================================================
-- Strips what must never be stored with an utterance: UPI ids and e-mail addresses, Indian phone numbers, any long digit run
-- (account or card numbers), and 4-6 digit numbers (PINs, OTPs; a 6-digit postcode goes too). Prices of up to 3 digits stay.
create or replace function public.redact_pii(p text) returns text
language sql immutable set search_path = public, extensions as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
    '[A-Za-z0-9._-]{2,}@[A-Za-z][A-Za-z0-9.-]{1,}', '[upi]', 'g'),
    '(\+?91[ -]?)?[6-9][0-9]{4}[ -]?[0-9]{5}', '[phone]', 'g'),
    '[0-9][0-9 -]{6,}[0-9]', '[number]', 'g'),
    '\m[0-9]{4,6}\M', '[pin]', 'g')
$$;

create table if not exists public.intent_feedback_optin (
  profile_id  uuid primary key references public.profiles on delete cascade,
  opted_at    timestamptz not null default now()
);
alter table public.intent_feedback_optin enable row level security;
drop policy if exists intent_feedback_optin_self on public.intent_feedback_optin;
create policy intent_feedback_optin_self on public.intent_feedback_optin for select to authenticated using (profile_id = public.me());
revoke all on public.intent_feedback_optin from anon, authenticated;
grant select on public.intent_feedback_optin to authenticated;

-- Turn "Help improve Bucks's understanding" on or off. Adults only; turning it off also deletes what was collected.
create or replace function public.set_intent_feedback_optin(p_on boolean) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  if p_on then
    if age_band_of(me()) <> 'ADULT' then raise exception 'only for people 18 and over'; end if;
    insert into intent_feedback_optin (profile_id) values (me()) on conflict do nothing;
    return true;
  end if;
  delete from intent_feedback_optin where profile_id = me();
  delete from intent_feedback where profile_id = me();
  return false;
end $$;

create table if not exists public.intent_feedback (
  id             uuid primary key default public.uuid_v7(),
  profile_id     uuid not null default public.me() references public.profiles on delete cascade,
  locale         text not null check (length(locale) between 2 and 16),
  tier           smallint not null check (tier between 0 and 2),
  utterance      text not null,                       -- redacted by the trigger below
  predicted      jsonb not null default '{}',          -- the tool call the tier proposed
  final_action   jsonb not null default '{}',          -- what the person actually did
  corrected      boolean not null default false,
  app_version    text check (length(app_version) <= 32),
  model_version  text check (length(model_version) <= 64),
  created_at     timestamptz not null default now()
);
create index if not exists intent_feedback_at on public.intent_feedback (created_at);
alter table public.intent_feedback enable row level security;
drop policy if exists intent_feedback_insert_own on public.intent_feedback;
create policy intent_feedback_insert_own on public.intent_feedback for insert to authenticated with check (profile_id = public.me());
drop policy if exists intent_feedback_staff on public.intent_feedback;
create policy intent_feedback_staff on public.intent_feedback for select to authenticated using (public.is_staff());
revoke all on public.intent_feedback from anon, authenticated;
grant insert (locale, tier, utterance, predicted, final_action, corrected, app_version, model_version) on public.intent_feedback to authenticated;
grant select on public.intent_feedback to authenticated;

create or replace function public.intent_feedback_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(setting('intent_feedback_enabled'), 0) < 1 then raise exception 'intent feedback is not being collected'; end if;
  new.profile_id := me();
  if new.profile_id is null then raise exception 'not signed in'; end if;
  if age_band_of(new.profile_id) <> 'ADULT' then raise exception 'only for people 18 and over'; end if;
  if not exists (select 1 from intent_feedback_optin where profile_id = new.profile_id) then raise exception 'turn on Help improve Bucks first'; end if;
  perform rate_hit('intent_feedback');
  new.utterance := left(redact_pii(left(new.utterance, 500)), 500);
  new.created_at := now();
  return new;
end $$;
revoke execute on function public.intent_feedback_guard() from public, anon, authenticated;
drop trigger if exists intent_feedback_guard on public.intent_feedback;
create trigger intent_feedback_guard before insert on public.intent_feedback for each row execute function public.intent_feedback_guard();
revoke execute on function public.set_intent_feedback_optin(boolean) from public, anon;
grant execute on function public.set_intent_feedback_optin(boolean) to authenticated;

-- ============================================================================
-- swarm_metrics_daily: per area cell (zone) and day in IST; zone 'ALL' is the whole project. Staff read it.
-- ============================================================================
create table if not exists public.swarm_metrics_daily (
  zone                  text not null,
  day                   date not null,
  service               text not null,
  requests              integer not null default 0,
  unfilled              integer not null default 0,     -- NO_DRIVER, or cancelled while searching for TOO_LONG
  unfilled_rate         numeric,
  accept_p50_s          numeric,                        -- request to first accept
  accept_p95_s          numeric,
  offers                integer not null default 0,
  offers_per_accept     numeric,
  lost_race_rate        numeric,
  trips_completed       integer not null default 0,
  trips_gini            numeric,                        -- fairness of completed trips across the drivers who drove that day
  recovery_shown        integer not null default 0,
  recovery_tapped       integer not null default 0,     -- a choice from the person's own tap
  recovery_converted    integer not null default 0,     -- then booked again themselves (followup)
  recovery_untapped_followups integer not null default 0, -- booked again without tapping the card (manual rebook)
  computed_at           timestamptz not null default now(),
  primary key (zone, day, service)
);
alter table public.swarm_metrics_daily enable row level security;
drop policy if exists swarm_metrics_staff on public.swarm_metrics_daily;
create policy swarm_metrics_staff on public.swarm_metrics_daily for select to authenticated using (public.is_staff());
revoke all on public.swarm_metrics_daily from anon, authenticated;
grant select on public.swarm_metrics_daily to authenticated;

create or replace function public.rollup_swarm_metrics(p_day date default ((now() at time zone 'Asia/Kolkata')::date - 1)) returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare n int; t0 timestamptz := (p_day::timestamp at time zone 'Asia/Kolkata'); t1 timestamptz := ((p_day + 1)::timestamp at time zone 'Asia/Kolkata');
begin
  delete from swarm_metrics_daily where day = p_day;
  with t as (
    select x.id, x.type as service, x.status, x.driver_id, x.cancel_reason, x.cancelled_by, x.created_at,
           case when x.pickup is null then '?' else area_cell(x.pickup) end as cell
      from tasks x where x.created_at >= t0 and x.created_at < t1 and swarm_counts(x.requester_id)
  ), z as (select cell as zone, * from t union all select 'ALL', * from t),
  acc as (
    select d.task_id, min(d.outcome_at) filter (where d.outcome = 'ACCEPTED') as accepted_at, count(*) as offers,
           count(*) filter (where d.outcome = 'LOST_RACE') as lost, count(*) filter (where d.outcome = 'ACCEPTED') as won
      from dispatch_offers d where d.task_id in (select id from t) group by d.task_id
  ), trips as (
    select zone, service, driver_id, count(*) as k from z where status in ('COMPLETED', 'PAID') and driver_id is not null group by 1, 2, 3
  ), gini as (
    select zone, service, case when count(*) < 2 or sum(k) = 0 then null
             else round((2.0 * sum(rk * k) / (count(*) * sum(k)) - (count(*) + 1.0) / count(*))::numeric, 3) end as g
      from (select zone, service, k, row_number() over (partition by zone, service order by k) as rk from trips) s group by 1, 2
  ), rec as (
    select coalesce(r.cell, '?') as cell, r.service, r.shown_at, r.choice, r.followup_id,
           exists (select 1 from tasks f where f.requester_id = r.profile_id and r.subject_kind = 'TASK' and f.created_at > r.shown_at
                     and f.created_at < r.shown_at + interval '30 minutes' and f.id <> r.subject_id)
           or exists (select 1 from orders f where f.buyer_id = r.profile_id and r.subject_kind = 'ORDER' and f.created_at > r.shown_at
                     and f.created_at < r.shown_at + interval '2 hours') as rebooked
      from recovery_offers r where r.shown_at >= t0 and r.shown_at < t1 and swarm_counts(r.profile_id)
  ), recz as (select cell as zone, * from rec union all select 'ALL', * from rec),
  m as (
    select z.zone, z.service, count(*)::int as requests,
           count(*) filter (where z.status = 'NO_DRIVER' or (z.status = 'CANCELLED' and z.cancelled_by = 'RIDER' and z.cancel_reason = 'TOO_LONG'))::int as unfilled,
           percentile_cont(0.5) within group (order by extract(epoch from a.accepted_at - z.created_at)) as p50,
           percentile_cont(0.95) within group (order by extract(epoch from a.accepted_at - z.created_at)) as p95,
           coalesce(sum(a.offers), 0)::int as offers, sum(a.won) as won, sum(a.lost) as lost,
           count(*) filter (where z.status in ('COMPLETED', 'PAID'))::int as done
      from z left join acc a on a.task_id = z.id group by 1, 2
  ), keys as (select zone, service from m union select zone, service from recz)
  insert into swarm_metrics_daily (zone, day, service, requests, unfilled, unfilled_rate, accept_p50_s, accept_p95_s, offers, offers_per_accept,
                                   lost_race_rate, trips_completed, trips_gini, recovery_shown, recovery_tapped, recovery_converted, recovery_untapped_followups)
  select k.zone, p_day, k.service, coalesce(m.requests, 0), coalesce(m.unfilled, 0),
         case when m.requests > 0 then round(m.unfilled::numeric / m.requests, 3) end,
         round(m.p50::numeric, 1), round(m.p95::numeric, 1), coalesce(m.offers, 0),
         case when m.won > 0 then round(m.offers::numeric / m.won, 2) end,
         case when m.offers > 0 then round(m.lost::numeric / m.offers, 3) end,
         coalesce(m.done, 0), g.g,
         (select count(*) from recz r where r.zone = k.zone and r.service = k.service)::int,
         (select count(*) from recz r where r.zone = k.zone and r.service = k.service and r.choice is not null and r.choice <> 'DISMISS')::int,
         (select count(*) from recz r where r.zone = k.zone and r.service = k.service and r.followup_id is not null)::int,
         (select count(*) from recz r where r.zone = k.zone and r.service = k.service and r.choice is null and r.rebooked)::int
    from keys k left join m on m.zone = k.zone and m.service = k.service left join gini g on g.zone = k.zone and g.service = k.service;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.rollup_swarm_metrics(date) from public, anon, authenticated;
grant execute on function public.rollup_swarm_metrics(date) to service_role;

-- ---------- schedules (pg_cron on Supabase; skipped elsewhere) ----------
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Nightly metrics at 03:40 IST, purges at 03:25 IST, and a once-a-minute backstop kick for the worker (a no-op while recovery is off).
    perform cron.schedule('swarm_metrics_daily', '10 22 * * *', $q$select public.rollup_swarm_metrics()$q$);
    perform cron.schedule('purge_swarm_phase1', '55 21 * * *', $q$
      delete from public.area_signal_hours where hour < now() - interval '8 days';
      delete from public.area_signals where updated_at < now() - interval '30 days';
      delete from public.recovery_alerts where until < now();
      delete from public.recovery_offers where shown_at < now() - make_interval(days => coalesce(public.setting('offer_log_days'), 180)::int);
      delete from public.agent_events where created_at < now() - interval '90 days';
      delete from public.intent_feedback where created_at < now() - interval '365 days'$q$);
    perform cron.schedule('swarm_worker_kick', '* * * * *', $q$
      select public.swarm_kick() where coalesce(public.setting('recovery_enabled'), 0) >= 1
        and to_regnamespace('pgmq') is not null
        and exists (select 1 from pgmq.metrics_all() where queue_name in ('recovery_q', 'nudge_q') and queue_length > 0)$q$);
  end if;
end $$;
