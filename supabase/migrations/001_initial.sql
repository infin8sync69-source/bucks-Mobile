-- bucks P2P Ride-Hailing — Initial Schema
-- Run once on a fresh Supabase project

-- ────────────────────────────────────────────
-- Extensions
-- ────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists "pg_trgm"; -- fast text search on addresses

-- ────────────────────────────────────────────
-- Tables
-- ────────────────────────────────────────────

-- Universal profile (Clerk manages auth; we store app-level data here)
create table public.users (
  id          uuid primary key default uuid_generate_v4(),
  clerk_id    text unique not null,
  phone       text not null,
  name        text not null,
  title       text,
  avatar_url  text,
  created_at  timestamptz not null default now()
);

-- Vehicles listed by users
create table public.vehicles (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references public.users(id) on delete cascade,
  type         text not null check (type in ('car', 'auto', 'bike')),
  license_plate text not null,
  listing_mode text not null,
  doc_url      text,
  verified     boolean not null default false,
  status       text not null default 'offline'
               check (status in ('offline', 'online', 'in_progress')),
  created_at   timestamptz not null default now()
);

-- Live driver positions (Realtime enabled below)
-- Rows are upserted every 3s; stale rows cleaned via cron/pg_cron
create table public.driver_locations (
  user_id    uuid primary key references public.users(id) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  updated_at timestamptz not null default now()
);

-- Rides — the core P2P transaction
create table public.rides (
  id              uuid primary key default uuid_generate_v4(),
  customer_id     uuid not null references public.users(id),
  driver_id       uuid references public.users(id),
  vehicle_id      uuid references public.vehicles(id),
  vehicle_type    text not null,
  pickup_lat      double precision not null,
  pickup_lng      double precision not null,
  pickup_address  text not null,
  drop_lat        double precision not null,
  drop_lng        double precision not null,
  drop_address    text not null,
  fare            integer not null,           -- in rupees, no decimals
  pin_code        char(4) not null,
  status          text not null default 'searching'
                  check (status in ('searching','accepted','pickup','active','done','cancelled')),
  cancel_reason   text,
  customer_rating smallint check (customer_rating between 1 and 5),
  driver_rating   smallint check (driver_rating between 1 and 5),
  tip_amount      integer not null default 0,
  created_at      timestamptz not null default now()
);

-- ────────────────────────────────────────────
-- Indexes
-- ────────────────────────────────────────────

-- Partial index: only active searching rides (small hot set)
create index idx_rides_searching on public.rides(status, vehicle_type)
  where status = 'searching';

create index idx_rides_customer   on public.rides(customer_id);
create index idx_rides_driver     on public.rides(driver_id);
create index idx_vehicles_user    on public.vehicles(user_id);
create index idx_vehicles_online  on public.vehicles(status)
  where status = 'online';

-- ────────────────────────────────────────────
-- Row-Level Security (RLS)
-- ────────────────────────────────────────────

alter table public.users           enable row level security;
alter table public.vehicles        enable row level security;
alter table public.driver_locations enable row level security;
alter table public.rides           enable row level security;

-- Users: own-row access only
create policy "users_self_all" on public.users
  for all using (clerk_id = (auth.jwt() ->> 'sub'));

-- Vehicles: owner full access; anyone can read online vehicles (for nearby display)
create policy "vehicles_owner_all" on public.vehicles
  for all using (user_id = auth.uid());

create policy "vehicles_online_read" on public.vehicles
  for select using (status = 'online');

-- Driver locations: anyone can read (live map); only owner can write
create policy "driver_loc_read"   on public.driver_locations for select using (true);
create policy "driver_loc_insert" on public.driver_locations for insert with check (user_id = auth.uid());
create policy "driver_loc_update" on public.driver_locations for update using (user_id = auth.uid());

-- Rides: customer and matched driver can see their rides
create policy "rides_customer_all" on public.rides
  for all using (customer_id = auth.uid());

create policy "rides_driver_read" on public.rides
  for select using (driver_id = auth.uid() or status = 'searching');

-- *** P2P race-condition claim: first UPDATE wins; subsequent attempts rejected by USING ***
create policy "rides_claim" on public.rides
  for update
  using  (status = 'searching' and driver_id is null)
  with check (driver_id = auth.uid());

create policy "rides_driver_update" on public.rides
  for update using (driver_id = auth.uid());

-- ────────────────────────────────────────────
-- Realtime
-- ────────────────────────────────────────────
alter publication supabase_realtime add table public.rides;
alter publication supabase_realtime add table public.driver_locations;

-- ────────────────────────────────────────────
-- Stale location cleanup (run via pg_cron every minute)
-- Schedule: select cron.schedule('expire-driver-locs', '* * * * *', 'select expire_driver_locations()');
-- ────────────────────────────────────────────
create or replace function expire_driver_locations()
returns void language sql security definer as $$
  delete from public.driver_locations
  where updated_at < now() - interval '30 seconds';
$$;
