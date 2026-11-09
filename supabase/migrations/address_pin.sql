-- A saved address can carry its drop point (docs/CORE_FLOWS.md §4): pinned once while standing there, it lets a local order be
-- delivered home from anywhere, with the fee worked out from that point, instead of only to where the phone is now.
-- Courier shipping keeps using the written address; the pin is only for Bucks and store riders.
-- Safe to run more than once. Apply after ecommerce.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

alter table public.addresses add column if not exists lat double precision;
alter table public.addresses add column if not exists lng double precision;
alter table public.addresses drop constraint if exists addresses_pin_shape;
-- Both or neither, and inside India (the only place Bucks delivers).
alter table public.addresses add constraint addresses_pin_shape check (
  (lat is null and lng is null) or (lat is not null and lng is not null and lat between 6 and 38 and lng between 68 and 98));
