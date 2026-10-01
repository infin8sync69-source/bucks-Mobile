-- Owners can read what they own, directly.
-- The app inserts a listing (or vehicle) and asks for the new row back (INSERT ... RETURNING). The owner's membership row is
-- created by an AFTER INSERT trigger, which the read policy can't see yet inside the same statement, so the insert was
-- rejected with "new row violates row-level security policy". Reading by owner_id needs no membership row.
set search_path = public, extensions;

drop policy if exists listings_read on public.listings;
create policy listings_read on public.listings for select to authenticated
  using (status = 'LIVE' or owner_id = public.me() or public.listing_role(id) is not null);

drop policy if exists vehicles_read on public.vehicles;
create policy vehicles_read on public.vehicles for select to authenticated
  using (owner_id = public.me() or public.vehicle_role(id) is not null);
