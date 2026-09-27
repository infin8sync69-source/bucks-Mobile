-- Discover: the universal listing profile (business / skill / driver) and cloud search.
-- Apply after schema.sql. Idempotent: every object is created "or replace".
--
-- 1. listing_points: a listing's coordinates as plain numbers. PostGIS geography reaches the app through
--    PostgREST as EWKB hex, so the app reads lat/lng from this view instead (security_invoker: the
--    listings row-level security applies, so a pending listing stays hidden from everyone but its team).
-- 2. listing_counts(): the public numbers a profile shows, in one call.

set search_path = public, extensions;

create or replace view public.listing_points with (security_invoker = true) as
  select l.id, st_y(l.location::geometry) as lat, st_x(l.location::geometry) as lng
  from public.listings l
  where l.location is not null;

grant select on public.listing_points to authenticated;

-- Recommendations from neighbours, people synced with the listing, people who run it, open jobs.
-- Returns no row for a listing I may not see (pending and not mine), the same rule as listings_read.
create or replace function public.listing_counts(p_listing uuid)
returns table (recommendations int, syncs int, members int, open_jobs int)
language sql stable security definer set search_path = public, extensions as $$
  select (select count(*) from public.recommendations r where r.listing_id = p_listing)::int,
         (select count(*) from public.listing_syncs s where s.listing_id = p_listing)::int,
         (select count(*) from public.listing_members m where m.listing_id = p_listing)::int,
         (select count(*) from public.jobs j where j.listing_id = p_listing and j.open)::int
  where exists (select 1 from public.listings l where l.id = p_listing and (l.status = 'LIVE' or public.listing_role(l.id) is not null))
$$;

revoke execute on function public.listing_counts(uuid) from public, anon;
grant execute on function public.listing_counts(uuid) to authenticated;
