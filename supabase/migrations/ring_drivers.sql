-- ============================================================================
-- Bucks: who should be rung for a new request (bucks_26)
-- Until now a driver only found out about a request while the app was open and polling (open_tasks_near), silently.
-- The notify function now pushes every online driver in range the moment a request starts searching; this is the
-- lookup it uses. Same rules as open_tasks_near: online, same vehicle kind, inside the ride/delivery radius, not the
-- requester, and on the request's only_riders list when it has one. Also drops drivers whose presence went stale (no
-- heartbeat for 5 minutes), so a phone that lost signal is not rung.
-- Service role only: it lists other people's ids.
-- ============================================================================
create or replace function public.drivers_to_ring(p_task uuid) returns setof uuid
language sql stable security definer set search_path = public, extensions as $$
  select p.profile_id
  from public.tasks t
  join public.driver_presence p on p.online and p.kind = t.vehicle_kind and p.location is not null
  where t.id = p_task and t.status = 'SEARCHING'
    and p.profile_id <> t.requester_id
    and (t.only_riders is null or p.profile_id = any(t.only_riders))
    and p.updated_at > now() - interval '5 minutes'
    and st_dwithin(t.pickup, p.location, case when t.type = 'DELIVERY' then public.setting('delivery_radius_m') else public.setting('ride_radius_m') end)
  order by st_distance(t.pickup, p.location)
  limit 20
$$;
revoke execute on function public.drivers_to_ring(uuid) from public, anon, authenticated;
grant execute on function public.drivers_to_ring(uuid) to service_role;
