-- ============================================================================
-- Bucks: dispatch offer log and the density gate (swarm Phase 0, docs/ai/reports/Swarm intelligence for Bucks.md)
-- Until now the list of drivers rung for a request went straight into push notifications and was lost, so nothing about
-- dispatch could be measured, audited for fairness or tuned. This records one row per driver rung (who, when, how far,
-- which ~2 km area cell, never coordinates) and stamps each row's outcome as the task moves on.
-- It changes no behaviour: dispatch_mode_for() always answers BROADCAST, every new setting defaults to 0 or off, and
-- drivers_to_ring, claim_task, can_claim and expire_tasks are untouched. Waves and batching (Phases 2-3) build on this.
-- Idempotent; safe to re-run.
-- ============================================================================

insert into public.settings (key, value) values
  ('swarm_enabled', 0),          -- master switch for any non-broadcast dispatch (Phase 2+); 0 = today's broadcast
  ('area_cell_deg', 0.05),       -- area cell size in degrees: 0.05 (~5 km) for rural Kodagu, 0.02 (~2 km) for towns and cities
  ('offer_log_days', 180)        -- how long offer rows are kept (purged daily below)
on conflict (key) do nothing;

-- A coarse area cell for a point: "row:col" of a grid of area_cell_deg degrees. Used instead of coordinates in logs and
-- heat maps, so no row stores where a driver was.
create or replace function public.area_cell(p geography) returns text
language sql stable set search_path = public, extensions as $$
  select floor(st_y(p::geometry) / d)::bigint || ':' || floor(st_x(p::geometry) / d)::bigint
  from (select coalesce(nullif(public.setting('area_cell_deg'), 0), 0.05) d) s
$$;

create table if not exists public.dispatch_offers (
  id          uuid primary key default public.uuid_v7(),
  task_id     uuid not null references public.tasks on delete cascade,
  driver_id   uuid not null references public.profiles on delete cascade,
  mode        text not null default 'BROADCAST' check (mode in ('BROADCAST', 'WAVE', 'BATCH', 'RECOVERY')),
  wave        smallint not null default 0,
  rank        smallint,                       -- position in drivers_to_ring's nearest-first order
  dist_m      integer,                        -- straight-line pickup distance when rung
  cell        text,                           -- area_cell of the pickup, never lat/lng
  visible_at  timestamptz not null default now(),
  outcome     text check (outcome in ('ACCEPTED', 'LOST_RACE', 'EXPIRED', 'CANCELLED', 'RERUNG')),
  outcome_at  timestamptz
);
create index if not exists dispatch_offers_task on public.dispatch_offers (task_id, visible_at);
create index if not exists dispatch_offers_driver on public.dispatch_offers (driver_id, visible_at desc);
create index if not exists dispatch_offers_cell on public.dispatch_offers (cell, visible_at desc);

alter table public.dispatch_offers enable row level security;
drop policy if exists dispatch_offers_read on public.dispatch_offers;
-- A driver sees the offers made to them (why they were or were not offered a ride); staff see all. Nobody writes directly.
create policy dispatch_offers_read on public.dispatch_offers for select to authenticated
  using (driver_id = public.me() or public.is_staff());
revoke all on public.dispatch_offers from anon, authenticated;
grant select on public.dispatch_offers to authenticated;

alter table public.tasks add column if not exists dispatch_mode text not null default 'BROADCAST';

-- Called by the notify Edge Function right after drivers_to_ring, with the ids it is about to ring, in that order.
-- Earlier unanswered offers for the same task are closed as RERUNG first, so each ring round reads on its own.
create or replace function public.log_offers(p_task uuid, p_drivers uuid[]) returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare t public.tasks; n integer;
begin
  select * into t from tasks where id = p_task;
  if t.id is null or t.status <> 'SEARCHING' or coalesce(array_length(p_drivers, 1), 0) = 0 then return 0; end if;
  update dispatch_offers set outcome = 'RERUNG', outcome_at = now() where task_id = p_task and outcome is null;
  insert into dispatch_offers (task_id, driver_id, mode, rank, dist_m, cell)
  select p_task, d.id, t.dispatch_mode, d.ord::smallint, round(st_distance(t.pickup, p.location))::integer, area_cell(t.pickup)
  from unnest(p_drivers) with ordinality as d(id, ord)
  left join driver_presence p on p.profile_id = d.id;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.log_offers(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.log_offers(uuid, uuid[]) to service_role;

-- Stamps outcomes as a task moves on. AFTER trigger, so it sees the committed status and never blocks a transition.
create or replace function public.dispatch_offers_outcome() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = old.status then return null; end if;
  if new.status = 'MATCHED' and new.driver_id is not null then
    update dispatch_offers set outcome = case when driver_id = new.driver_id then 'ACCEPTED' else 'LOST_RACE' end, outcome_at = now()
     where task_id = new.id and outcome is null;
  elsif new.status = 'NO_DRIVER' then
    update dispatch_offers set outcome = 'EXPIRED', outcome_at = now() where task_id = new.id and outcome is null;
  elsif new.status = 'CANCELLED' then
    update dispatch_offers set outcome = 'CANCELLED', outcome_at = now() where task_id = new.id and outcome is null;
  end if;
  return null;
end $$;
drop trigger if exists dispatch_offers_outcome on public.tasks;
create trigger dispatch_offers_outcome after update of status on public.tasks
  for each row execute function public.dispatch_offers_outcome();
revoke execute on function public.dispatch_offers_outcome() from public, anon, authenticated;

-- The density gate. Phase 0: always BROADCAST. Later phases read swarm_enabled, the eligible count and the 7-day median
-- from dispatch_offers before choosing WAVE or BATCH; until then this is the one place that decision will live.
create or replace function public.dispatch_mode_for(p_task uuid) returns text
language sql stable security definer set search_path = public, extensions as $$
  select 'BROADCAST'::text
$$;
revoke execute on function public.dispatch_mode_for(uuid) from public, anon, authenticated;
grant execute on function public.dispatch_mode_for(uuid) to service_role;

-- Offer rows are operational data, not a permanent record: keep offer_log_days, purge daily at 03:20 IST.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge_dispatch_offers', '50 21 * * *',
      $q$delete from public.dispatch_offers where visible_at < now() - make_interval(days => coalesce(public.setting('offer_log_days'), 180)::int)$q$);
  end if;
end $$;
