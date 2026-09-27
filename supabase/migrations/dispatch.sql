-- Dispatch: rides and deliveries on Supabase (see docs/FEATURE_CONTRACT.md, feature "dispatch").
-- Adds what the app needs on top of schema.sql: task rows with plain coordinates, online drivers for the map,
-- the counterpart's vehicle for a task, and "my open task" so a killed app returns to its trip.
-- Safe to re-run.
set search_path = public, extensions;

-- ---------- tasks with lat/lng (PostgREST returns geography as EWKB hex, which the app cannot read) ----------
-- Delivery tasks also carry how many items the order has; the rider may not read orders, so a definer helper counts them.
create or replace function public.order_item_count(o uuid) returns int
language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select sum(greatest(1, coalesce((l->>'qty')::int, 1)))::int from public.orders x, jsonb_array_elements(x.lines) l where x.id = o), 0)
$$;

drop view if exists public.tasks_geo cascade;
create view public.tasks_geo with (security_invoker = true) as
  select t.*,
         st_y(t.pickup::geometry)          as pickup_lat, st_x(t.pickup::geometry)          as pickup_lng,
         st_y(t.drop_at::geometry)         as drop_lat,   st_x(t.drop_at::geometry)         as drop_lng,
         st_y(t.driver_location::geometry) as driver_lat, st_x(t.driver_location::geometry) as driver_lng,
         case when t.order_id is null then null else public.order_item_count(t.order_id) end as order_items
  from public.tasks t;
grant select on public.tasks_geo to authenticated;

-- ---------- online drivers around a point, for the map and "n riders nearby" ----------
-- Presence rows older than 5 minutes are dead apps. Trust comes from the driver's DRIVER listing when they have one.
create or replace function public.online_drivers_near(p_lat double precision, p_lng double precision, radius_m int default 5000)
returns table (profile_id uuid, kind text, lat double precision, lng double precision, name text, model text, plate text, up int, down int)
language sql stable security definer set search_path = public, extensions as $$
  select p.profile_id, p.kind, st_y(p.location::geometry), st_x(p.location::geometry), pr.name, v.model, v.plate,
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0)
  from public.driver_presence p
  join public.profiles pr on pr.id = p.profile_id and pr.status = 'ACTIVE'
  join public.vehicles v on v.id = p.vehicle_id
  left join public.listings l on l.owner_id = p.profile_id and l.kind = 'DRIVER'
  where p.online and p.location is not null and p.updated_at > now() - interval '5 minutes'
    and p.profile_id is distinct from public.me()
    and st_dwithin(p.location, public.geo(p_lat, p_lng), radius_m)
  order by st_distance(p.location, public.geo(p_lat, p_lng))
$$;

-- ---------- the driver of a task, for the requester's screen (name, vehicle, trust, listing to review) ----------
create or replace function public.task_driver(p_task uuid)
returns table (profile_id uuid, name text, kind text, model text, plate text, up int, down int, listing_id uuid)
language sql stable security definer set search_path = public, extensions as $$
  select pr.id, pr.name, coalesce(v.kind, t.vehicle_kind), coalesce(v.model, ''), coalesce(v.plate, ''),
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0), l.id
  from public.tasks t
  join public.profiles pr on pr.id = t.driver_id
  left join public.vehicles v on v.id = t.vehicle_id
  left join public.listings l on l.owner_id = t.driver_id and l.kind = 'DRIVER'
  where t.id = p_task and public.me() in (t.requester_id, t.driver_id)
$$;

-- ---------- my open task: resume a trip after the app was killed ----------
-- A SEARCHING task older than 3 minutes no longer rings anyone (open_tasks_near), so it is not "open" any more.
create or replace function public.my_open_task() returns setof public.tasks_geo
language sql stable security definer set search_path = public, extensions as $$
  select * from public.tasks_geo
  where public.me() in (requester_id, driver_id)
    and status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED')
    and (status <> 'SEARCHING' or created_at > now() - interval '3 minutes')
  order by (driver_id = public.me()) desc, created_at desc
  limit 1
$$;

-- order_item_count runs as the caller inside the security-invoker view, so authenticated needs execute on it too (it only returns a count).
revoke execute on function public.order_item_count(uuid), public.online_drivers_near(double precision, double precision, int),
  public.task_driver(uuid), public.my_open_task() from public, anon;
grant execute on function public.order_item_count(uuid), public.online_drivers_near(double precision, double precision, int),
  public.task_driver(uuid), public.my_open_task() to authenticated;
