-- Bucks: Supabase (Postgres) schema.
-- Run once in Supabase > SQL Editor. Safe to re-run: every object is created "if not exists" or replaced.
--
-- Identity: users sign in with Firebase (phone OTP). Supabase trusts the Firebase token
-- (Authentication > Third-party auth > Firebase), so auth.jwt()->>'sub' is the Firebase uid.
-- Every person, listing, vehicle, order and task gets a UUIDv7 id; people also get an
-- 8-character Bucks ID (short_code) that is easy to read out, type or scan as a QR.
--
-- Everything writes through row-level security. Actions with rules (placing an order,
-- accepting it, claiming a task, recommending someone, accepting an invite) go through
-- security-definer functions so the rules can't be bypassed from the app.

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;
set search_path = public, extensions;

-- ---------- helpers ----------

-- RFC 9562 UUIDv7: 48-bit millisecond timestamp + random. Sorts by creation time, indexes well.
create or replace function public.uuid_v7() returns uuid language plpgsql volatile set search_path = public, extensions as $$
declare b bytea;
begin
  b := substring(int8send((extract(epoch from clock_timestamp()) * 1000)::bigint) from 3) || extensions.gen_random_bytes(10);
  b := set_byte(b, 6, (get_byte(b, 6) & 15) | 112);   -- version 7
  b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);   -- RFC 4122 variant
  return encode(b, 'hex')::uuid;
end $$;

-- 8-character Crockford base32 code (no I, L, O, U): readable aloud, ~1 trillion combinations.
create or replace function public.new_short_code() returns text language plpgsql volatile set search_path = public, extensions as $$
declare alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; r bytea := extensions.gen_random_bytes(8); c text := '';
begin
  for i in 0..7 loop c := c || substr(alphabet, (get_byte(r, i) % 32) + 1, 1); end loop;
  return c;
end $$;

create or replace function public.geo(lat double precision, lng double precision) returns geography
language sql immutable set search_path = public, extensions as $$ select st_setsrid(st_makepoint(lng, lat), 4326)::geography $$;

-- Tunables in one place (community cap, radii, timeouts).
create table if not exists public.settings (key text primary key, value numeric not null);
insert into public.settings values
  ('min_recommendations', 7),          -- recommendations needed before a listing goes live
  ('recommend_radius_m', 3000),        -- recommenders must be local to the listing
  ('recommender_min_account_days', 14),
  ('delivery_radius_m', 3000),         -- bikes rung for a delivery
  ('ride_radius_m', 5000),
  ('order_accept_minutes', 5),
  ('delivery_base_fee', 20), ('delivery_fee_per_km', 8)
on conflict (key) do nothing;
create or replace function public.setting(k text) returns numeric language sql stable set search_path = public, extensions as $$ select value from public.settings where key = k $$;

-- ---------- people ----------

create table if not exists public.profiles (
  id          uuid primary key default public.uuid_v7(),
  auth_uid    text unique not null,                       -- Firebase uid today; any auth later
  short_code  text unique not null default public.new_short_code(),
  name        text not null default '',
  bio         text not null default '',
  area        text not null default '',
  photo_url   text,
  home        geography(point, 4326),                     -- where they live/work; used for "local" recommendations
  trust_up    int not null default 0,
  trust_down  int not null default 0,
  status      text not null default 'ACTIVE' check (status in ('ACTIVE', 'BANNED')),
  created_at  timestamptz not null default now()
);
-- Phone and payment QR are private: only the person, and counterparties of an active trip/order, can read them.
create table if not exists public.profile_private (
  profile_id  uuid primary key references public.profiles on delete cascade,
  phone       text,
  upi_uri     text                                        -- decoded from the payment QR the person uploads
);

-- Current person's profile id, from the signed-in token.
create or replace function public.me() returns uuid language sql stable security definer set search_path = public, extensions as $$
  select id from public.profiles where auth_uid = auth.jwt()->>'sub' and status = 'ACTIVE'
$$;

-- "Sync": a two-way connection between people (replaces follow).
create table if not exists public.syncs (
  requester_id uuid not null references public.profiles on delete cascade,
  addressee_id uuid not null references public.profiles on delete cascade,
  status       text not null default 'PENDING' check (status in ('PENDING', 'ACCEPTED')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

-- ---------- listings: every public profile (business, skill, driver) ----------

create table if not exists public.listings (
  id          uuid primary key default public.uuid_v7(),
  kind        text not null check (kind in ('BUSINESS', 'SKILL', 'DRIVER')),
  owner_id    uuid not null references public.profiles on delete cascade,
  title       text not null,
  category    text not null default '',
  description text not null default '',
  photo_url   text,
  area        text not null default '',
  location    geography(point, 4326),
  details     jsonb not null default '{}',                -- kind-specific: hours, free_delivery, level, rate, languages...
  status      text not null default 'PENDING' check (status in ('PENDING', 'LIVE', 'SUSPENDED')),
  online      boolean not null default false,
  trust_up    int not null default 0,
  trust_down  int not null default 0,
  search      tsvector generated always as (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(category, '') || ' ' || coalesce(description, ''))) stored,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists listings_search_idx on public.listings using gin (search);
create index if not exists listings_title_trgm on public.listings using gin (title extensions.gin_trgm_ops);
create index if not exists listings_location_idx on public.listings using gist (location);
create unique index if not exists one_driver_profile on public.listings (owner_id) where kind = 'DRIVER';

-- Who runs a listing. OWNER: everything. ADMIN: operate on the owner's behalf. STORE_RIDER: the store's own delivery riders.
create table if not exists public.listing_members (
  listing_id  uuid not null references public.listings on delete cascade,
  profile_id  uuid not null references public.profiles on delete cascade,
  role        text not null check (role in ('OWNER', 'ADMIN', 'STORE_RIDER')),
  created_at  timestamptz not null default now(),
  primary key (listing_id, profile_id)
);
create or replace function public.listing_role(l uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select role from public.listing_members where listing_id = l and profile_id = public.me()
$$;
create or replace function public.can_manage_listing(l uuid) returns boolean language sql stable set search_path = public, extensions as $$
  select coalesce(public.listing_role(l) in ('OWNER', 'ADMIN'), false)
$$;
-- The creator becomes OWNER automatically.
create or replace function public.listing_add_owner() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin insert into public.listing_members values (new.id, new.owner_id, 'OWNER') on conflict do nothing; return new; end $$;
drop trigger if exists listing_owner on public.listings;
create trigger listing_owner after insert on public.listings for each row execute function public.listing_add_owner();

-- Products (businesses) and services (skills), one table.
create table if not exists public.items (
  id          uuid primary key default public.uuid_v7(),
  listing_id  uuid not null references public.listings on delete cascade,
  kind        text not null default 'PRODUCT' check (kind in ('PRODUCT', 'SERVICE')),
  name        text not null,
  price       int not null check (price >= 0),           -- rupees
  mrp         int,
  unit        text not null default '',                   -- "1 kg", "per hour", "per visit"
  group_name  text not null default '',                   -- menu section / aisle
  photo_url   text,
  in_stock    boolean not null default true,
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists items_listing_idx on public.items (listing_id);
create index if not exists items_name_trgm on public.items using gin (name extensions.gin_trgm_ops);

-- People sync with listings they like (shows their posts in the feed).
create table if not exists public.listing_syncs (
  profile_id  uuid not null references public.profiles on delete cascade,
  listing_id  uuid not null references public.listings on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (profile_id, listing_id)
);

-- ---------- vehicles: internal records, managed by owner and admins (drivers) ----------

create table if not exists public.vehicles (
  id          uuid primary key default public.uuid_v7(),
  owner_id    uuid not null references public.profiles on delete cascade,
  kind        text not null check (kind in ('BIKE', 'AUTO', 'CAB')),
  model       text not null default '',
  plate       text not null unique,
  docs        jsonb not null default '[]',               -- storage paths of RC, insurance, permit
  status      text not null default 'PENDING' check (status in ('PENDING', 'ACTIVE', 'SUSPENDED')),
  created_at  timestamptz not null default now()
);
create table if not exists public.vehicle_members (
  vehicle_id  uuid not null references public.vehicles on delete cascade,
  profile_id  uuid not null references public.profiles on delete cascade,
  role        text not null check (role in ('OWNER', 'ADMIN')),
  primary key (vehicle_id, profile_id)
);
create or replace function public.vehicle_role(v uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select role from public.vehicle_members where vehicle_id = v and profile_id = public.me()
$$;
create or replace function public.vehicle_add_owner() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin insert into public.vehicle_members values (new.id, new.owner_id, 'OWNER') on conflict do nothing; return new; end $$;
drop trigger if exists vehicle_owner on public.vehicles;
create trigger vehicle_owner after insert on public.vehicles for each row execute function public.vehicle_add_owner();

-- Admin invites for listings and vehicles, sent to a Bucks ID.
create table if not exists public.invites (
  id          uuid primary key default public.uuid_v7(),
  listing_id  uuid references public.listings on delete cascade,
  vehicle_id  uuid references public.vehicles on delete cascade,
  inviter_id  uuid not null references public.profiles,
  invitee_id  uuid not null references public.profiles on delete cascade,
  role        text not null check (role in ('ADMIN', 'STORE_RIDER')),
  status      text not null default 'PENDING' check (status in ('PENDING', 'ACCEPTED', 'DECLINED', 'REVOKED')),
  created_at  timestamptz not null default now(),
  check ((listing_id is null) <> (vehicle_id is null))
);

-- ---------- community cap: local recommendations ----------

create table if not exists public.recommendations (
  listing_id     uuid not null references public.listings on delete cascade,
  recommender_id uuid not null references public.profiles on delete cascade,
  at_location    geography(point, 4326) not null,
  created_at     timestamptz not null default now(),
  primary key (listing_id, recommender_id)
);
-- Short-lived tokens the listing owner shows as a QR; scanning one in person is the only way to recommend.
create table if not exists public.recommend_tokens (
  token       text primary key,
  listing_id  uuid not null references public.listings on delete cascade,
  expires_at  timestamptz not null
);

-- ---------- presence, tasks (rides and deliveries), orders ----------

-- Where online drivers are. Riders and the dispatcher read it; each driver writes their own row.
create table if not exists public.driver_presence (
  profile_id  uuid primary key references public.profiles on delete cascade,
  vehicle_id  uuid not null references public.vehicles on delete cascade,
  kind        text not null,
  online      boolean not null default false,
  location    geography(point, 4326),
  updated_at  timestamptz not null default now()
);
create index if not exists presence_location_idx on public.driver_presence using gist (location);

create table if not exists public.orders (
  id            uuid primary key default public.uuid_v7(),
  listing_id    uuid not null references public.listings,
  buyer_id      uuid not null references public.profiles,
  lines         jsonb not null,                           -- [{item_id, name, price, qty}] priced by the server
  subtotal      int not null,
  delivery_fee  int not null default 0,
  fee_paid_by   text not null default 'BUYER' check (fee_paid_by in ('BUYER', 'VENDOR')),
  delivery_mode text not null default 'MARKETPLACE' check (delivery_mode in ('MARKETPLACE', 'STORE_RIDER', 'PICKUP')),
  payment       text not null default 'UPI' check (payment in ('UPI', 'COD')),
  drop_location geography(point, 4326),
  drop_label    text not null default '',
  status        text not null default 'PLACED' check (status in ('PLACED', 'ACCEPTED', 'REJECTED', 'READY', 'PICKED_UP', 'DELIVERED', 'CANCELLED')),
  accept_by     timestamptz not null,
  created_at    timestamptz not null default now()
);

create table if not exists public.tasks (
  id            uuid primary key default public.uuid_v7(),
  type          text not null check (type in ('RIDE', 'DELIVERY')),
  requester_id  uuid not null references public.profiles,
  order_id      uuid references public.orders on delete cascade,
  vehicle_kind  text not null,
  pickup        geography(point, 4326) not null,
  pickup_label  text not null default '',
  drop_at       geography(point, 4326) not null,
  drop_label    text not null default '',
  km            numeric not null default 0,
  fare          int not null default 0,
  pin           text not null default lpad((floor(random() * 10000))::int::text, 4, '0'),
  only_riders   uuid[],                                   -- store riders only (cash on delivery); null = marketplace
  status        text not null default 'SEARCHING' check (status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'PAID', 'NO_DRIVER', 'CANCELLED')),
  driver_id     uuid references public.profiles,
  vehicle_id    uuid references public.vehicles,
  driver_location geography(point, 4326),
  paid_with     text,
  created_at    timestamptz not null default now()
);
create index if not exists tasks_open_idx on public.tasks (status, vehicle_kind) where status = 'SEARCHING';
create index if not exists tasks_pickup_idx on public.tasks using gist (pickup);

-- Every accept, reject and completion, per driver and vehicle: feeds the owner's dashboard.
create table if not exists public.task_events (
  id          bigint generated always as identity primary key,
  task_id     uuid not null references public.tasks on delete cascade,
  driver_id   uuid not null references public.profiles,
  vehicle_id  uuid not null references public.vehicles,
  event       text not null check (event in ('ACCEPTED', 'REJECTED', 'MISSED', 'COMPLETED', 'CANCELLED')),
  km          numeric not null default 0,
  fare        int not null default 0,
  at          timestamptz not null default now()
);

-- Reviews are only accepted against a completed task or delivered order (enforced in review()).
create table if not exists public.reviews (
  id          uuid primary key default public.uuid_v7(),
  listing_id  uuid not null references public.listings on delete cascade,
  author_id   uuid not null references public.profiles,
  task_id     uuid references public.tasks,
  order_id    uuid references public.orders,
  vote        smallint not null check (vote in (-1, 1)),
  comment     text not null check (length(comment) > 0),
  created_at  timestamptz not null default now(),
  unique (listing_id, author_id, task_id, order_id)
);

-- ---------- jobs ----------

create table if not exists public.jobs (
  id          uuid primary key default public.uuid_v7(),
  listing_id  uuid not null references public.listings on delete cascade,
  title       text not null,
  description text not null default '',
  pay         text not null default '',
  job_type    text not null default 'FULL_TIME' check (job_type in ('FULL_TIME', 'PART_TIME', 'GIG')),
  open        boolean not null default true,
  created_by  uuid not null references public.profiles,
  created_at  timestamptz not null default now()
);
create table if not exists public.applications (
  id          uuid primary key default public.uuid_v7(),
  job_id      uuid not null references public.jobs on delete cascade,
  applicant_id uuid not null references public.profiles on delete cascade,
  skill_listing_ids uuid[] not null default '{}',        -- the applicant's skill profiles they apply with
  note        text not null default '',
  status      text not null default 'APPLIED' check (status in ('APPLIED', 'SHORTLISTED', 'REJECTED', 'HIRED', 'WITHDRAWN')),
  created_at  timestamptz not null default now(),
  unique (job_id, applicant_id)
);

-- ---------- row-level security ----------

alter table public.settings enable row level security;
alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.syncs enable row level security;
alter table public.listings enable row level security;
alter table public.listing_members enable row level security;
alter table public.items enable row level security;
alter table public.listing_syncs enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_members enable row level security;
alter table public.invites enable row level security;
alter table public.recommendations enable row level security;
alter table public.recommend_tokens enable row level security;
alter table public.driver_presence enable row level security;
alter table public.orders enable row level security;
alter table public.tasks enable row level security;
alter table public.task_events enable row level security;
alter table public.reviews enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy settings_read on public.settings for select to authenticated using (true);

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated with check (auth_uid = auth.jwt()->>'sub');
create policy profiles_update on public.profiles for update to authenticated using (id = public.me()) with check (id = public.me());
-- Trust, status and identity fields only change through Bucks' own functions.
create or replace function public.guard_profile() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.trust_up <> old.trust_up or new.trust_down <> old.trust_down or new.status <> old.status
     or new.auth_uid <> old.auth_uid or new.short_code <> old.short_code or new.created_at <> old.created_at) then
    raise exception 'trust, status and ids are managed by Bucks';
  end if;
  return new;
end $$;
drop trigger if exists profile_guard on public.profiles;
create trigger profile_guard before update on public.profiles for each row execute function public.guard_profile();
create policy private_self on public.profile_private for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());

create policy syncs_read on public.syncs for select to authenticated using (public.me() in (requester_id, addressee_id));
create policy syncs_request on public.syncs for insert to authenticated with check (requester_id = public.me() and status = 'PENDING');
create policy syncs_accept on public.syncs for update to authenticated using (addressee_id = public.me()) with check (addressee_id = public.me());
create policy syncs_delete on public.syncs for delete to authenticated using (public.me() in (requester_id, addressee_id));

-- Live listings are public; pending ones are visible to their members (and via the recommend QR flow).
create policy listings_read on public.listings for select to authenticated using (status = 'LIVE' or public.listing_role(id) is not null);
create policy listings_insert on public.listings for insert to authenticated with check (owner_id = public.me() and status = 'PENDING' and trust_up = 0 and trust_down = 0);
create policy listings_update on public.listings for update to authenticated using (public.can_manage_listing(id))
  with check (public.can_manage_listing(id));
create policy listings_delete on public.listings for delete to authenticated using (public.listing_role(id) = 'OWNER');
-- Status and trust only change through the server functions below.
create or replace function public.guard_listing() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.status <> old.status or new.trust_up <> old.trust_up or new.trust_down <> old.trust_down or new.owner_id <> old.owner_id or new.kind <> old.kind) then
    raise exception 'status, trust, owner and kind are managed by Bucks';
  end if;
  new.updated_at := now(); return new;
end $$;
drop trigger if exists listing_guard on public.listings;
create trigger listing_guard before update on public.listings for each row execute function public.guard_listing();

create policy members_read on public.listing_members for select to authenticated using (true);
create policy members_remove on public.listing_members for delete to authenticated
  using ((public.listing_role(listing_id) = 'OWNER' and role <> 'OWNER') or (profile_id = public.me() and role <> 'OWNER'));

create policy items_read on public.items for select to authenticated using (exists (select 1 from public.listings l where l.id = listing_id));
create policy items_write on public.items for all to authenticated using (public.can_manage_listing(listing_id)) with check (public.can_manage_listing(listing_id));


create policy lsync_read on public.listing_syncs for select to authenticated using (true);
create policy lsync_self on public.listing_syncs for insert to authenticated with check (profile_id = public.me());
create policy lsync_delete on public.listing_syncs for delete to authenticated using (profile_id = public.me());

create policy vehicles_read on public.vehicles for select to authenticated using (public.vehicle_role(id) is not null);
create policy vehicles_insert on public.vehicles for insert to authenticated with check (owner_id = public.me() and status = 'PENDING');
create policy vehicles_update on public.vehicles for update to authenticated using (public.vehicle_role(id) = 'OWNER') with check (public.vehicle_role(id) = 'OWNER');
create policy vehicles_delete on public.vehicles for delete to authenticated using (public.vehicle_role(id) = 'OWNER');
create or replace function public.guard_vehicle() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.status <> old.status or new.owner_id <> old.owner_id) then raise exception 'vehicle status is managed by Bucks'; end if;
  return new;
end $$;
drop trigger if exists vehicle_guard on public.vehicles;
create trigger vehicle_guard before update on public.vehicles for each row execute function public.guard_vehicle();
create policy vmembers_read on public.vehicle_members for select to authenticated using (public.vehicle_role(vehicle_id) is not null);
create policy vmembers_remove on public.vehicle_members for delete to authenticated
  using ((public.vehicle_role(vehicle_id) = 'OWNER' and role <> 'OWNER') or (profile_id = public.me() and role <> 'OWNER'));

create policy invites_read on public.invites for select to authenticated using (public.me() in (inviter_id, invitee_id));
create policy invites_revoke on public.invites for update to authenticated using (inviter_id = public.me()) with check (inviter_id = public.me() and status = 'REVOKED');

create policy recs_read on public.recommendations for select to authenticated using (true);

create policy presence_read on public.driver_presence for select to authenticated using (online);
create policy presence_self on public.driver_presence for all to authenticated using (profile_id = public.me())
  with check (profile_id = public.me() and public.vehicle_role(vehicle_id) is not null);

create policy orders_read on public.orders for select to authenticated using (buyer_id = public.me() or public.listing_role(listing_id) is not null);

-- Open tasks are visible to online drivers of the right vehicle (or to the store's riders); after that only to the two parties.
create policy tasks_read on public.tasks for select to authenticated using (
  requester_id = public.me() or driver_id = public.me()
  or (status = 'SEARCHING' and (only_riders is null or public.me() = any(only_riders))
      and exists (select 1 from public.driver_presence p where p.profile_id = public.me() and p.online and p.kind = vehicle_kind)));

create policy events_read on public.task_events for select to authenticated using (driver_id = public.me() or public.vehicle_role(vehicle_id) = 'OWNER');
create policy reviews_read on public.reviews for select to authenticated using (true);

create policy jobs_read on public.jobs for select to authenticated using (open or public.listing_role(listing_id) is not null);
create policy jobs_write on public.jobs for all to authenticated using (public.can_manage_listing(listing_id)) with check (public.can_manage_listing(listing_id) and created_by = public.me());
create policy apps_read on public.applications for select to authenticated
  using (applicant_id = public.me() or exists (select 1 from public.jobs j where j.id = job_id and public.can_manage_listing(j.listing_id)));
create policy apps_apply on public.applications for insert to authenticated
  with check (applicant_id = public.me() and status = 'APPLIED' and exists (select 1 from public.jobs j where j.id = job_id and j.open));
create policy apps_update on public.applications for update to authenticated
  using (applicant_id = public.me() or exists (select 1 from public.jobs j where j.id = job_id and public.can_manage_listing(j.listing_id)))
  with check ((applicant_id = public.me() and status = 'WITHDRAWN') or exists (select 1 from public.jobs j where j.id = job_id and public.can_manage_listing(j.listing_id)));

-- ---------- functions the app calls ----------

-- First sign-in: create (or return) my profile.
create or replace function public.ensure_profile(p_name text, p_phone text default null) returns public.profiles
language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles; uid text := auth.jwt()->>'sub';
begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into p from profiles where auth_uid = uid;
  if not found then
    loop
      begin insert into profiles (auth_uid, name) values (uid, coalesce(p_name, '')) returning * into p; exit;
      exception when unique_violation then if exists (select 1 from profiles where auth_uid = uid) then select * into p from profiles where auth_uid = uid; exit; end if; end;  -- short_code clash: retry
    end loop;
  end if;
  insert into profile_private (profile_id, phone) values (p.id, p_phone) on conflict (profile_id) do update set phone = coalesce(excluded.phone, profile_private.phone);
  return p;
end $$;

-- Search live listings (and their items) near a point. Empty query = everything nearby.
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null, lim int default 40)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int,
               details jsonb, distance_m double precision, matched_item text, min_price int)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         (select i.name from items i where i.listing_id = l.id and term.t is not null and i.name ilike '%' || term.t || '%' order by i.price limit 1) as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock) as min_price
  from listings l, here, term
  where l.status = 'LIVE'
    and (kinds is null or l.kind = any(kinds))
    and l.location is not null and st_dwithin(l.location, here.g, radius_m)
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit lim
$$;

-- Invite someone by Bucks ID to help run a listing (ADMIN, STORE_RIDER) or drive a vehicle (ADMIN).
create or replace function public.invite(p_listing uuid, p_vehicle uuid, p_short_code text, p_role text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare invitee uuid; inv uuid;
begin
  if p_listing is not null and coalesce(listing_role(p_listing), '') <> 'OWNER' then raise exception 'only the owner can invite'; end if;
  if p_vehicle is not null and coalesce(vehicle_role(p_vehicle), '') <> 'OWNER' then raise exception 'only the owner can invite'; end if;
  if p_vehicle is not null and p_role <> 'ADMIN' then raise exception 'vehicles only have admins'; end if;
  select id into invitee from profiles where short_code = upper(trim(p_short_code)) and status = 'ACTIVE';
  if invitee is null then raise exception 'no one has that Bucks ID'; end if;
  if invitee = me() then raise exception 'you already own this'; end if;
  insert into invites (listing_id, vehicle_id, inviter_id, invitee_id, role) values (p_listing, p_vehicle, me(), invitee, p_role) returning id into inv;
  return inv;
end $$;

create or replace function public.respond_invite(p_invite uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare i invites;
begin
  select * into i from invites where id = p_invite and invitee_id = me() and status = 'PENDING' for update;
  if not found then raise exception 'invite not found'; end if;
  update invites set status = case when p_accept then 'ACCEPTED' else 'DECLINED' end where id = p_invite;
  if p_accept and i.listing_id is not null then insert into listing_members values (i.listing_id, i.invitee_id, i.role) on conflict (listing_id, profile_id) do update set role = excluded.role; end if;
  if p_accept and i.vehicle_id is not null then insert into vehicle_members values (i.vehicle_id, i.invitee_id, 'ADMIN') on conflict do nothing; end if;
end $$;

-- Owner shows this as a QR; valid for 2 minutes.
create or replace function public.recommend_token(p_listing uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(extensions.gen_random_bytes(12), 'hex');
begin
  if not can_manage_listing(p_listing) then raise exception 'not your listing'; end if;
  delete from recommend_tokens where expires_at < now();
  insert into recommend_tokens values (t, p_listing, now() + interval '2 minutes');
  return t;
end $$;

-- Scanning the QR in person. Recommender must be local (their home and where they stand), and an established account.
-- Returns how many local recommendations the listing now has; it goes LIVE at the threshold.
create or replace function public.recommend(p_token text, lat double precision, lng double precision) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare tok recommend_tokens; l listings; me_p profiles; here geography := geo(lat, lng); n int;
begin
  select * into tok from recommend_tokens where token = p_token and expires_at > now();
  if not found then raise exception 'this code has expired, ask them to show a new one'; end if;
  select * into l from listings where id = tok.listing_id;
  select * into me_p from profiles where id = me();
  if me_p.id is null then raise exception 'not signed in'; end if;
  if listing_role(l.id) is not null then raise exception 'you cannot recommend your own listing'; end if;
  if me_p.created_at > now() - make_interval(days => setting('recommender_min_account_days')::int) then raise exception 'your account is too new to recommend'; end if;
  if me_p.home is null or l.location is null or not st_dwithin(me_p.home, l.location, setting('recommend_radius_m')) then raise exception 'only people who live nearby can recommend'; end if;
  if not st_dwithin(here, l.location, setting('recommend_radius_m')) then raise exception 'recommend in person, near where they work'; end if;
  insert into recommendations values (l.id, me_p.id, here) on conflict do nothing;
  select count(*) into n from recommendations where listing_id = l.id;
  if n >= setting('min_recommendations') and l.status = 'PENDING' then update listings set status = 'LIVE' where id = l.id; end if;
  return n;
end $$;

-- Buyer places an order; prices come from the items table, never from the app.
create or replace function public.place_order(p_listing uuid, p_lines jsonb, p_lat double precision, p_lng double precision, p_drop_label text, p_payment text, p_mode text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare l listings; lines jsonb := '[]'; sub int := 0; line jsonb; it items; km numeric; fee int := 0; oid uuid;
begin
  select * into l from listings where id = p_listing and kind = 'BUSINESS' and status = 'LIVE';
  if not found then raise exception 'this shop is not taking orders'; end if;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into it from items where id = (line->>'item_id')::uuid and listing_id = p_listing and in_stock;
    if not found then raise exception 'an item is no longer available'; end if;
    lines := lines || jsonb_build_object('item_id', it.id, 'name', it.name, 'price', it.price, 'qty', greatest(1, (line->>'qty')::int));
    sub := sub + it.price * greatest(1, (line->>'qty')::int);
  end loop;
  if p_payment = 'COD' and p_mode <> 'STORE_RIDER' then raise exception 'cash on delivery is only with the store''s own riders'; end if;
  if p_mode <> 'PICKUP' then
    km := round((st_distance(l.location, geo(p_lat, p_lng)) / 1000.0 * 1.3)::numeric, 1);   -- road ~1.3x straight line
    fee := (setting('delivery_base_fee') + setting('delivery_fee_per_km') * km)::int;
  end if;
  insert into orders (listing_id, buyer_id, lines, subtotal, delivery_fee, fee_paid_by, delivery_mode, payment, drop_location, drop_label, accept_by)
  values (p_listing, me(), lines, sub, fee, case when coalesce((l.details->>'free_delivery')::boolean, false) then 'VENDOR' else 'BUYER' end,
          p_mode, p_payment, geo(p_lat, p_lng), coalesce(p_drop_label, ''), now() + make_interval(mins => setting('order_accept_minutes')::int))
  returning id into oid;
  return oid;
end $$;

-- Vendor (owner or admin) accepts or rejects within 5 minutes. Accepting a delivery order creates a bike delivery task:
-- marketplace orders ring online bikes within 3 km; store-rider orders ring only that store's riders.
create or replace function public.respond_order(p_order uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders; l listings; riders uuid[];
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if o.status <> 'PLACED' then raise exception 'this order is already %', lower(o.status); end if;
  if o.accept_by < now() then update orders set status = 'REJECTED' where id = p_order; raise exception 'too late: the order timed out'; end if;
  if not p_accept then update orders set status = 'REJECTED' where id = p_order; return; end if;
  update orders set status = 'ACCEPTED' where id = p_order;
  if o.delivery_mode = 'PICKUP' then return; end if;
  select * into l from listings where id = o.listing_id;
  if o.delivery_mode = 'STORE_RIDER' then select array_agg(profile_id) into riders from listing_members where listing_id = l.id and role = 'STORE_RIDER'; end if;
  insert into tasks (type, requester_id, order_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare, only_riders)
  values ('DELIVERY', o.buyer_id, o.id, 'BIKE', l.location, l.title, o.drop_location, o.drop_label,
          round((st_distance(l.location, o.drop_location) / 1000.0 * 1.3)::numeric, 1), o.delivery_fee, riders);
end $$;

-- Orders nobody accepted in time are rejected (schedule with pg_cron, see SUPABASE_SETUP.md).
create or replace function public.expire_orders() returns int language sql security definer set search_path = public, extensions as $$
  with x as (update orders set status = 'REJECTED' where status = 'PLACED' and accept_by < now() returning 1) select count(*)::int from x
$$;

-- Rider books a passenger ride (auto or cab only).
create or replace function public.request_ride(p_kind text, p_lat double precision, p_lng double precision, p_pickup_label text,
                                               d_lat double precision, d_lng double precision, p_drop_label text, p_km numeric, p_fare int)
returns public.tasks language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  if p_kind not in ('AUTO', 'CAB') then raise exception 'bikes carry goods only'; end if;
  insert into tasks (type, requester_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare)
  values ('RIDE', me(), p_kind, geo(p_lat, p_lng), p_pickup_label, geo(d_lat, d_lng), p_drop_label, p_km, p_fare) returning * into t;
  return t;
end $$;

-- Open tasks this online driver should be rung for, nearest first.
create or replace function public.open_tasks_near(lat double precision, lng double precision) returns setof public.tasks
language sql stable security definer set search_path = public, extensions as $$
  select t.* from tasks t join driver_presence p on p.profile_id = me() and p.online and p.kind = t.vehicle_kind
  where t.status = 'SEARCHING' and t.requester_id <> me()
    and (t.only_riders is null or me() = any(t.only_riders))
    and st_dwithin(t.pickup, geo(lat, lng), case when t.type = 'DELIVERY' then setting('delivery_radius_m') else setting('ride_radius_m') end)
    and t.created_at > now() - interval '3 minutes'
  order by st_distance(t.pickup, geo(lat, lng))
$$;

-- First driver to claim wins. Logged for the vehicle owner's dashboard.
create or replace function public.claim_task(p_task uuid) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare p driver_presence; t tasks;
begin
  select * into p from driver_presence where profile_id = me() and online;
  if not found then raise exception 'go online first'; end if;
  update tasks set status = 'MATCHED', driver_id = me(), vehicle_id = p.vehicle_id, driver_location = p.location
   where id = p_task and status = 'SEARCHING' and vehicle_kind = p.kind and (only_riders is null or me() = any(only_riders))
  returning * into t;
  if not found then return false; end if;
  insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, me(), p.vehicle_id, 'ACCEPTED', t.km, t.fare);
  return true;
end $$;

-- Driver declined or let it ring out: counts in the owner's stats.
create or replace function public.pass_task(p_task uuid, p_missed boolean default false) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare p driver_presence;
begin
  select * into p from driver_presence where profile_id = me();
  if found then insert into task_events (task_id, driver_id, vehicle_id, event) values (p_task, me(), p.vehicle_id, case when p_missed then 'MISSED' else 'REJECTED' end); end if;
end $$;

-- Moves a task along. Driver: ARRIVED -> IN_PROGRESS (needs the requester's PIN) -> COMPLETED; or hand it back.
-- Requester: CANCELLED (before pick-up), PAID. Delivery completion also marks the order delivered.
create or replace function public.advance_task(p_task uuid, p_status text, p_pin text default null, p_paid_with text default null) returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  select * into t from tasks where id = p_task for update;
  if not found then raise exception 'task not found'; end if;
  if t.driver_id = me() then
    if p_status = 'ARRIVED' and t.status = 'MATCHED' then null;
    elsif p_status = 'IN_PROGRESS' and t.status = 'ARRIVED' then if p_pin is distinct from t.pin then raise exception 'that PIN does not match'; end if;
    elsif p_status = 'COMPLETED' and t.status = 'IN_PROGRESS' then
      insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, me(), t.vehicle_id, 'COMPLETED', t.km, t.fare);
      if t.order_id is not null then update orders set status = 'DELIVERED' where id = t.order_id; end if;
    elsif p_status = 'SEARCHING' and t.status in ('MATCHED', 'ARRIVED') then
      insert into task_events (task_id, driver_id, vehicle_id, event) values (t.id, me(), t.vehicle_id, 'CANCELLED');
      update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where id = p_task returning * into t; return t;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
    if p_status = 'IN_PROGRESS' and t.order_id is not null then update orders set status = 'PICKED_UP' where id = t.order_id; end if;
  elsif t.requester_id = me() then
    if p_status = 'CANCELLED' and t.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER') then null;
    elsif p_status = 'NO_DRIVER' and t.status = 'SEARCHING' then null;
    elsif p_status = 'PAID' and t.status = 'COMPLETED' then null;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
  else raise exception 'not your task'; end if;
  update tasks set status = p_status, paid_with = coalesce(p_paid_with, paid_with) where id = p_task returning * into t;
  return t;
end $$;

-- Driver's live position during a trip.
create or replace function public.update_location(lat double precision, lng double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  update driver_presence set location = geo(lat, lng), updated_at = now() where profile_id = me();
  update tasks set driver_location = geo(lat, lng) where driver_id = me() and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS');
end $$;

-- Counterparty's phone and payment link, only while a trip or order is active between us.
create or replace function public.contact_for_task(p_task uuid) returns table (phone text, upi_uri text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone, pp.upi_uri from tasks t join profile_private pp on pp.profile_id = case when t.requester_id = me() then t.driver_id else t.requester_id end
  where t.id = p_task and me() in (t.requester_id, t.driver_id) and t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED')
$$;

-- Reviews only from someone who completed a task with, or received an order from, that listing.
create or replace function public.review(p_listing uuid, p_task uuid, p_order uuid, p_vote int, p_comment text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l listings; ok boolean := false;
begin
  select * into l from listings where id = p_listing;
  if p_task is not null then
    select exists (select 1 from tasks t where t.id = p_task and t.requester_id = me() and t.status in ('COMPLETED', 'PAID') and l.kind = 'DRIVER' and l.owner_id = t.driver_id) into ok;
  elsif p_order is not null then
    select exists (select 1 from orders o where o.id = p_order and o.buyer_id = me() and o.status = 'DELIVERED' and o.listing_id = p_listing) into ok;
  end if;
  if not ok then raise exception 'you can review after a completed trip or order'; end if;
  insert into reviews (listing_id, author_id, task_id, order_id, vote, comment) values (p_listing, me(), p_task, p_order, p_vote, trim(p_comment));
  update listings set trust_up = trust_up + (p_vote > 0)::int, trust_down = trust_down + (p_vote < 0)::int where id = p_listing;
end $$;

-- Vehicle owner's dashboard: per vehicle, last 30 days.
create or replace view public.vehicle_stats with (security_invoker = true) as
  select v.id as vehicle_id, v.plate, v.model, v.kind,
         count(*) filter (where e.event = 'ACCEPTED')  as accepted,
         count(*) filter (where e.event in ('REJECTED', 'MISSED')) as rejected,
         count(*) filter (where e.event = 'COMPLETED') as completed,
         coalesce(sum(e.km) filter (where e.event = 'COMPLETED'), 0)   as km,
         coalesce(sum(e.fare) filter (where e.event = 'COMPLETED'), 0) as earnings
  from public.vehicles v left join public.task_events e on e.vehicle_id = v.id and e.at > now() - interval '30 days'
  group by v.id;

-- =====================================================================
-- Social: settings, blocking, messaging, files, feed, moments, suggestions
-- =====================================================================

-- Per-person settings. Privacy fields are enforced by the database; the rest the app reads.
create table if not exists public.user_settings (
  profile_id        uuid primary key references public.profiles on delete cascade,
  who_can_message   text not null default 'SYNCED'   check (who_can_message in ('EVERYONE', 'SYNCED', 'NOBODY')),
  who_can_sync      text not null default 'EVERYONE' check (who_can_sync in ('EVERYONE', 'NOBODY')),
  moments_audience  text not null default 'SYNCED'   check (moments_audience in ('SYNCED', 'LOCAL', 'CLOSE')),
  read_receipts     boolean not null default true,    -- off: others don't see "seen", and you don't see theirs
  show_online       boolean not null default true,
  discoverable      boolean not null default true,    -- appear in people suggestions
  notify            jsonb not null default '{"messages": true, "sync_requests": true, "moments": true, "comments": true, "orders": true, "tasks": true, "offers": false}',
  quiet_hours       jsonb,                            -- {"from": "22:00", "to": "07:00"}
  app               jsonb not null default '{}',      -- theme, text size, language, data saver, media auto-download...
  updated_at        timestamptz not null default now()
);
create or replace function public.settings_of(p uuid) returns public.user_settings language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select s from user_settings s where s.profile_id = p), row(p, 'SYNCED', 'EVERYONE', 'SYNCED', true, true, true, '{}'::jsonb, null, '{}'::jsonb, now())::user_settings)
$$;

-- Close friends list for moments shared with "CLOSE".
create table if not exists public.close_friends (
  profile_id uuid not null references public.profiles on delete cascade,
  friend_id  uuid not null references public.profiles on delete cascade,
  primary key (profile_id, friend_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles on delete cascade,
  blocked_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create or replace function public.blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from blocks where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a))
$$;
create or replace function public.synced(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from syncs where status = 'ACCEPTED' and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a)))
$$;

-- Sync requests respect the addressee's setting and blocks.
create or replace function public.request_sync(p_other uuid) returns text language plpgsql security definer set search_path = public, extensions as $$
declare other_setting text;
begin
  if p_other = me() then raise exception 'that is you'; end if;
  if blocked_between(me(), p_other) then raise exception 'you cannot sync with this person'; end if;
  if exists (select 1 from syncs where requester_id = p_other and addressee_id = me() and status = 'PENDING') then
    update syncs set status = 'ACCEPTED' where requester_id = p_other and addressee_id = me(); return 'ACCEPTED';   -- they asked first
  end if;
  select who_can_sync into other_setting from settings_of(p_other);
  if other_setting = 'NOBODY' then raise exception 'this person is not accepting sync requests'; end if;
  insert into syncs (requester_id, addressee_id) values (me(), p_other) on conflict do nothing;
  return 'PENDING';
end $$;

-- ---------- messaging ----------

create table if not exists public.conversations (
  id              uuid primary key default public.uuid_v7(),
  kind            text not null default 'DIRECT' check (kind in ('DIRECT', 'GROUP', 'LISTING')),
  title           text,                                 -- groups
  listing_id      uuid references public.listings on delete cascade,  -- customer <-> business/pro inbox
  direct_key      text unique,                          -- sorted pair of profile ids, so a DM is never duplicated
  created_by      uuid not null references public.profiles,
  last_message_at timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations on delete cascade,
  profile_id      uuid not null references public.profiles on delete cascade,
  role            text not null default 'MEMBER' check (role in ('MEMBER', 'ADMIN')),
  last_read_at    timestamptz not null default 'epoch',
  muted_until     timestamptz,
  archived        boolean not null default false,
  primary key (conversation_id, profile_id)
);
create index if not exists conv_members_profile_idx on public.conversation_members (profile_id);
create table if not exists public.messages (
  id              uuid primary key default public.uuid_v7(),
  conversation_id uuid not null references public.conversations on delete cascade,
  sender_id       uuid not null references public.profiles,
  body            text not null default '',
  attachment      jsonb,                                -- {"path","name","mime","size","width","height"} in the "chat" bucket
  reply_to        uuid references public.messages,
  moment_id       uuid,                                 -- a reply to someone's moment
  created_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz,
  check (deleted_at is not null or length(body) > 0 or attachment is not null)
);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at desc);

create or replace function public.is_member(c uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from conversation_members where conversation_id = c and profile_id = public.me())
$$;

-- Open (or reuse) a one-to-one chat, following the other person's "who can message me" setting:
-- EVERYONE = anyone; SYNCED = people they're synced with; NOBODY = no new chats.
-- A driver and rider on an active trip can always message each other. Blocks always win.
create or replace function public.start_direct(p_other uuid) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare k text; c uuid; allowed boolean;
begin
  if p_other = me() then raise exception 'that is you'; end if;
  if blocked_between(me(), p_other) then raise exception 'you cannot message this person'; end if;
  k := least(me()::text, p_other::text) || ':' || greatest(me()::text, p_other::text);
  select id into c from conversations where direct_key = k;
  if c is not null then return c; end if;
  allowed := case (select who_can_message from settings_of(p_other)) when 'EVERYONE' then true when 'SYNCED' then synced(me(), p_other) else false end
          or exists (select 1 from tasks t where t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED') and
                     ((t.requester_id = me() and t.driver_id = p_other) or (t.requester_id = p_other and t.driver_id = me())));
  if not allowed then raise exception 'this person only takes messages from people they have synced with'; end if;
  insert into conversations (kind, direct_key, created_by) values ('DIRECT', k, me()) returning id into c;
  insert into conversation_members (conversation_id, profile_id) values (c, me()), (c, p_other);
  return c;
end $$;

-- Message a business or pro: everyone who runs the listing (owner and admins) shares one inbox with the customer.
create or replace function public.start_listing_chat(p_listing uuid) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare c uuid; l listings;
begin
  select * into l from listings where id = p_listing and status = 'LIVE';
  if not found then raise exception 'not available'; end if;
  if listing_role(p_listing) is not null then raise exception 'this is your own listing'; end if;
  select cm.conversation_id into c from conversations cv join conversation_members cm on cm.conversation_id = cv.id
   where cv.kind = 'LISTING' and cv.listing_id = p_listing and cv.created_by = me() and cm.profile_id = me() limit 1;
  if c is not null then return c; end if;
  insert into conversations (kind, listing_id, created_by, title) values ('LISTING', p_listing, me(), l.title) returning id into c;
  insert into conversation_members (conversation_id, profile_id) values (c, me());
  insert into conversation_members (conversation_id, profile_id, role)
    select c, profile_id, 'ADMIN' from listing_members where listing_id = p_listing and role in ('OWNER', 'ADMIN') on conflict do nothing;
  return c;
end $$;

create or replace function public.create_group(p_title text, p_members uuid[]) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare c uuid; m uuid;
begin
  insert into conversations (kind, title, created_by) values ('GROUP', p_title, me()) returning id into c;
  insert into conversation_members (conversation_id, profile_id, role) values (c, me(), 'ADMIN');
  foreach m in array coalesce(p_members, '{}') loop
    if m <> me() and synced(me(), m) and not blocked_between(me(), m) then insert into conversation_members values (c, m) on conflict do nothing; end if;
  end loop;
  return c;
end $$;

create or replace function public.touch_conversation() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update conversations set last_message_at = new.created_at where id = new.conversation_id;
  update conversation_members set last_read_at = new.created_at where conversation_id = new.conversation_id and profile_id = new.sender_id;
  return new;
end $$;
drop trigger if exists message_touch on public.messages;
create trigger message_touch after insert on public.messages for each row execute function public.touch_conversation();

-- Senders can edit their text or delete ("This message was deleted"); nothing else about a message changes.
create or replace function public.guard_message() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.sender_id <> old.sender_id or new.conversation_id <> old.conversation_id or new.created_at <> old.created_at) then raise exception 'not allowed'; end if;
  if new.deleted_at is not null then new.body := ''; new.attachment := null; end if;
  if new.body <> old.body then new.edited_at := now(); end if;
  return new;
end $$;
drop trigger if exists message_guard on public.messages;
create trigger message_guard before update on public.messages for each row execute function public.guard_message();

-- Inbox: one row per conversation with the other person (or group/listing title), last message and unread count.
create or replace function public.inbox() returns table (conversation_id uuid, kind text, title text, other_id uuid, other_name text, other_code text,
  last_body text, last_at timestamptz, unread int, muted boolean, archived boolean)
language sql stable security definer set search_path = public, extensions as $$
  select c.id, c.kind,
         coalesce(c.title, op.name), op.id, op.name, op.short_code,
         (select case when m.deleted_at is not null then 'Message deleted' when m.body = '' then coalesce(m.attachment->>'name', 'Attachment') else m.body end
            from messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*)::int from messages m where m.conversation_id = c.id and m.sender_id <> me() and m.created_at > mine.last_read_at),
         coalesce(mine.muted_until > now(), false), mine.archived
  from conversation_members mine join conversations c on c.id = mine.conversation_id
  left join lateral (select p.* from conversation_members o join profiles p on p.id = o.profile_id
                      where o.conversation_id = c.id and o.profile_id <> me() and c.kind = 'DIRECT' limit 1) op on true
  where mine.profile_id = me()
  order by c.last_message_at desc
$$;

-- Mark read. Read receipts: the other side's last_read_at is only exposed if both have receipts on.
create or replace function public.mark_read(p_conv uuid) returns void language sql security definer set search_path = public, extensions as $$
  update conversation_members set last_read_at = now() where conversation_id = p_conv and profile_id = me()
$$;
create or replace function public.seen_up_to(p_conv uuid) returns timestamptz language sql stable security definer set search_path = public, extensions as $$
  select case when (select read_receipts from settings_of(me())) then
    (select min(o.last_read_at) from conversation_members o where o.conversation_id = p_conv and o.profile_id <> me() and (select read_receipts from settings_of(o.profile_id)))
  end where is_member(p_conv)
$$;

-- ---------- feed ----------

create table if not exists public.posts (
  id          uuid primary key default public.uuid_v7(),
  author_id   uuid not null references public.profiles on delete cascade,
  listing_id  uuid references public.listings on delete cascade,     -- posted as a business / pro profile
  body        text not null default '',
  media       jsonb not null default '[]',                          -- [{"path","mime","width","height"}] in the "posts" bucket
  visibility  text not null default 'LOCAL' check (visibility in ('PUBLIC', 'LOCAL', 'SYNCED')),
  location    geography(point, 4326),
  area        text not null default '',
  up          int not null default 0,
  down        int not null default 0,
  comments    int not null default 0,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  check (length(body) > 0 or media <> '[]'::jsonb)
);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_location_idx on public.posts using gist (location);
create table if not exists public.post_votes (
  post_id    uuid not null references public.posts on delete cascade,
  profile_id uuid not null references public.profiles on delete cascade,
  vote       smallint not null check (vote in (-1, 1)),
  primary key (post_id, profile_id)
);
create table if not exists public.post_comments (
  id         uuid primary key default public.uuid_v7(),
  post_id    uuid not null references public.posts on delete cascade,
  author_id  uuid not null references public.profiles on delete cascade,
  body       text not null check (length(body) > 0),
  created_at timestamptz not null default now()
);
create or replace function public.can_see_post(p public.posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.deleted_at is null and not blocked_between(me(), p.author_id) and
         (p.author_id = me() or p.visibility in ('PUBLIC', 'LOCAL') or (p.visibility = 'SYNCED' and synced(me(), p.author_id)))
$$;
-- Counters kept by the database, so they can't be forged.
create or replace function public.post_counts() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare pid uuid := coalesce(new.post_id, old.post_id);
begin
  update posts set up = (select count(*) from post_votes where post_id = pid and vote = 1),
                   down = (select count(*) from post_votes where post_id = pid and vote = -1),
                   comments = (select count(*) from post_comments where post_id = pid) where id = pid;
  return null;
end $$;
drop trigger if exists post_votes_count on public.post_votes;
create trigger post_votes_count after insert or update or delete on public.post_votes for each row execute function public.post_counts();
drop trigger if exists post_comments_count on public.post_comments;
create trigger post_comments_count after insert or delete on public.post_comments for each row execute function public.post_counts();

-- Feed: my synced people and listings, plus local posts within radius; newest first, lightly boosted by votes.
create or replace function public.feed(lat double precision, lng double precision, radius_m int default 5000, before timestamptz default now(), lim int default 30)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.author_id, a.name, a.short_code, p.listing_id, l.title, p.body, p.media, p.visibility, p.area, p.up, p.down, p.comments,
         (select v.vote from post_votes v where v.post_id = p.id and v.profile_id = me()), p.created_at, synced(me(), p.author_id)
  from posts p join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
  where p.created_at < before and can_see_post(p)
    and (p.author_id = me() or synced(me(), p.author_id)
         or (p.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = p.listing_id))
         or p.visibility = 'PUBLIC'
         or (p.visibility = 'LOCAL' and p.location is not null and st_dwithin(p.location, geo(lat, lng), radius_m)))
  order by p.created_at desc
  limit lim
$$;

-- ---------- moments (24-hour stories) ----------

create table if not exists public.moments (
  id          uuid primary key default public.uuid_v7(),
  author_id   uuid not null references public.profiles on delete cascade,
  listing_id  uuid references public.listings on delete cascade,     -- a shop or pro can post moments too
  media_path  text not null,                                        -- in the "moments" bucket
  media_type  text not null default 'IMAGE' check (media_type in ('IMAGE', 'VIDEO')),
  caption     text not null default '',
  audience    text not null default 'SYNCED' check (audience in ('SYNCED', 'LOCAL', 'CLOSE')),
  location    geography(point, 4326),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);
create index if not exists moments_live_idx on public.moments (expires_at);
create table if not exists public.moment_views (
  moment_id  uuid not null references public.moments on delete cascade,
  viewer_id  uuid not null references public.profiles on delete cascade,
  reaction   text,                                                  -- an emoji, optional
  viewed_at  timestamptz not null default now(),
  primary key (moment_id, viewer_id)
);
-- People whose moments I've chosen to hide from my tray.
create table if not exists public.moment_mutes (
  profile_id uuid not null references public.profiles on delete cascade,
  muted_id   uuid not null references public.profiles on delete cascade,
  primary key (profile_id, muted_id)
);
create or replace function public.can_see_moment(m public.moments, lat double precision default null, lng double precision default null) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select m.expires_at > now() and not blocked_between(me(), m.author_id) and (
    m.author_id = me()
    or (m.audience = 'SYNCED' and synced(me(), m.author_id))
    or (m.audience = 'CLOSE' and exists (select 1 from close_friends c where c.profile_id = m.author_id and c.friend_id = me()))
    or (m.audience = 'LOCAL' and (synced(me(), m.author_id) or (lat is not null and m.location is not null and st_dwithin(m.location, geo(lat, lng), 5000)))))
$$;

-- The row of circles at the top of the feed: me first, then people with unseen moments, newest first.
create or replace function public.moments_tray(lat double precision, lng double precision)
returns table (author_id uuid, author_name text, author_code text, listing_title text, moments int, unseen int, latest_at timestamptz, is_me boolean)
language sql stable security definer set search_path = public, extensions as $$
  select m.author_id, a.name, a.short_code, max(l.title), count(*)::int,
         count(*) filter (where not exists (select 1 from moment_views v where v.moment_id = m.id and v.viewer_id = me()) and m.author_id <> me())::int,
         max(m.created_at), m.author_id = me()
  from moments m join profiles a on a.id = m.author_id left join listings l on l.id = m.listing_id
  where can_see_moment(m, lat, lng) and not exists (select 1 from moment_mutes x where x.profile_id = me() and x.muted_id = m.author_id)
  group by m.author_id, a.name, a.short_code
  order by (m.author_id = me()) desc, (count(*) filter (where not exists (select 1 from moment_views v where v.moment_id = m.id and v.viewer_id = me())) > 0) desc, max(m.created_at) desc
$$;
create or replace function public.moments_of(p_author uuid, lat double precision, lng double precision) returns setof public.moments
language sql stable security definer set search_path = public, extensions as $$
  select m.* from moments m where m.author_id = p_author and can_see_moment(m, lat, lng) order by m.created_at
$$;
create or replace function public.view_moment(p_moment uuid, p_reaction text default null) returns void language plpgsql security definer set search_path = public, extensions as $$
declare m moments;
begin
  select * into m from moments where id = p_moment;
  if not found or not can_see_moment(m, null, null) and m.audience <> 'LOCAL' then raise exception 'not available'; end if;
  if m.author_id = me() then return; end if;
  insert into moment_views (moment_id, viewer_id, reaction) values (p_moment, me(), p_reaction)
    on conflict (moment_id, viewer_id) do update set reaction = coalesce(excluded.reaction, moment_views.reaction);
end $$;
-- Author sees who viewed (and reacted).
create or replace function public.moment_viewers(p_moment uuid) returns table (viewer_id uuid, name text, reaction text, viewed_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select v.viewer_id, p.name, v.reaction, v.viewed_at from moment_views v join profiles p on p.id = v.viewer_id join moments m on m.id = v.moment_id
  where v.moment_id = p_moment and m.author_id = me() order by v.viewed_at desc
$$;
-- Reply to a moment: lands in a direct chat with the author.
create or replace function public.reply_to_moment(p_moment uuid, p_body text) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare m moments; c uuid;
begin
  select * into m from moments where id = p_moment;
  if not found or m.author_id = me() or not (synced(me(), m.author_id) or m.audience = 'LOCAL') then raise exception 'not available'; end if;
  c := start_direct(m.author_id);
  insert into messages (conversation_id, sender_id, body, moment_id) values (c, me(), p_body, p_moment);
  return c;
end $$;
-- Hourly cleanup of expired moments (schedule with pg_cron; media files are removed by the storage cleanup job).
create or replace function public.expire_moments() returns int language sql security definer set search_path = public, extensions as $$
  with x as (delete from moments where expires_at < now() - interval '1 hour' returning 1) select count(*)::int from x
$$;

-- ---------- suggestions ("For you") ----------

-- People you may know: friends of friends first, then active people nearby. Excludes blocked, already synced, undiscoverable.
create or replace function public.suggest_people(lat double precision, lng double precision, lim int default 20)
returns table (id uuid, name text, short_code text, area text, mutual int, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id))
  select p.id, p.name, p.short_code, p.area,
         (select count(*)::int from syncs s where s.status = 'ACCEPTED' and ((s.requester_id = p.id and s.addressee_id in (select f from mine)) or (s.addressee_id = p.id and s.requester_id in (select f from mine)))) as mutual,
         st_distance(p.home, geo(lat, lng))
  from profiles p
  where p.id <> me() and p.status = 'ACTIVE' and (select discoverable from settings_of(p.id))
    and p.id not in (select f from mine) and not blocked_between(me(), p.id)
    and not exists (select 1 from syncs s where s.requester_id = me() and s.addressee_id = p.id)
  order by mutual desc, st_distance(p.home, geo(lat, lng)) nulls last
  limit lim
$$;

-- Listings recommended or reviewed well by people I'm synced with, near me.
create or replace function public.suggest_listings(lat double precision, lng double precision, lim int default 20)
returns table (id uuid, kind text, title text, category text, area text, synced_recommenders int, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id))
  select l.id, l.kind, l.title, l.category, l.area,
         ((select count(*) from recommendations r where r.listing_id = l.id and r.recommender_id in (select f from mine))
          + (select count(*) from reviews v where v.listing_id = l.id and v.vote = 1 and v.author_id in (select f from mine)))::int as n,
         st_distance(l.location, geo(lat, lng))
  from listings l
  where l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, geo(lat, lng), 15000)
  order by n desc, (l.trust_up - l.trust_down) desc, st_distance(l.location, geo(lat, lng))
  limit lim
$$;

-- ---------- row-level security for the social tables ----------

alter table public.user_settings enable row level security;
alter table public.close_friends enable row level security;
alter table public.blocks enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.posts enable row level security;
alter table public.post_votes enable row level security;
alter table public.post_comments enable row level security;
alter table public.moments enable row level security;
alter table public.moment_views enable row level security;
alter table public.moment_mutes enable row level security;

create policy settings_self on public.user_settings for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());
create policy close_self on public.close_friends for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());
create policy blocks_self on public.blocks for all to authenticated using (blocker_id = public.me()) with check (blocker_id = public.me());
-- Blocking also ends any sync.
create or replace function public.on_block() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin delete from syncs where (requester_id = new.blocker_id and addressee_id = new.blocked_id) or (requester_id = new.blocked_id and addressee_id = new.blocker_id); return new; end $$;
drop trigger if exists block_unsync on public.blocks;
create trigger block_unsync after insert on public.blocks for each row execute function public.on_block();

create policy conv_read on public.conversations for select to authenticated using (public.is_member(id));
create policy conv_rename on public.conversations for update to authenticated using (public.is_member(id) and kind = 'GROUP') with check (kind = 'GROUP');
create policy cm_read on public.conversation_members for select to authenticated using (public.is_member(conversation_id));
create policy cm_self on public.conversation_members for update to authenticated using (profile_id = public.me()) with check (profile_id = public.me());
create policy cm_leave on public.conversation_members for delete to authenticated using (profile_id = public.me());
create policy msg_read on public.messages for select to authenticated using (public.is_member(conversation_id));
create policy msg_send on public.messages for insert to authenticated with check (
  sender_id = public.me() and public.is_member(conversation_id)
  and not exists (select 1 from public.conversations c join public.conversation_members o on o.conversation_id = c.id
                  where c.id = messages.conversation_id and c.kind = 'DIRECT' and o.profile_id <> public.me() and public.blocked_between(public.me(), o.profile_id)));
create policy msg_edit on public.messages for update to authenticated using (sender_id = public.me()) with check (sender_id = public.me());

create policy posts_read on public.posts for select to authenticated using (public.can_see_post(posts));
create policy posts_write on public.posts for insert to authenticated
  with check (author_id = public.me() and up = 0 and down = 0 and comments = 0 and (listing_id is null or public.can_manage_listing(listing_id)));
create policy posts_edit on public.posts for update to authenticated using (author_id = public.me()) with check (author_id = public.me());
create policy posts_delete on public.posts for delete to authenticated using (author_id = public.me() or (listing_id is not null and public.can_manage_listing(listing_id)));
create policy votes_self on public.post_votes for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());
create policy comments_read on public.post_comments for select to authenticated using (exists (select 1 from public.posts p where p.id = post_id));
create policy comments_write on public.post_comments for insert to authenticated with check (author_id = public.me() and exists (select 1 from public.posts p where p.id = post_id));
create policy comments_delete on public.post_comments for delete to authenticated
  using (author_id = public.me() or exists (select 1 from public.posts p where p.id = post_id and p.author_id = public.me()));

create policy moments_read on public.moments for select to authenticated using (public.can_see_moment(moments, null, null));
create policy moments_write on public.moments for insert to authenticated with check (author_id = public.me() and (listing_id is null or public.can_manage_listing(listing_id)) and expires_at <= now() + interval '24 hours 1 minute');
create policy moments_delete on public.moments for delete to authenticated using (author_id = public.me());
create policy mviews_read on public.moment_views for select to authenticated using (viewer_id = public.me());
create policy mutes_self on public.moment_mutes for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());

-- ---------- file storage (Supabase Storage) ----------
-- Buckets: avatars and listing-media are public (profile and product photos); chat, moments, posts and docs are private.
-- Paths: chat/<conversation_id>/<file>, moments/<profile_id>/<file>, posts/<profile_id>/<file>, docs/<profile_id>/<file>,
--        listing-media/<listing_id>/<file>, avatars/<profile_id>/<file>.
do $$ begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
      ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
      ('listing-media', 'listing-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
      ('posts', 'posts', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']),
      ('moments', 'moments', false, 31457280, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']),
      ('chat', 'chat', false, 26214400, null),
      ('docs', 'docs', false, 10485760, array['image/jpeg', 'image/png', 'application/pdf'])
    on conflict (id) do nothing;

    drop policy if exists bucks_public_read on storage.objects;
    drop policy if exists bucks_own_folder on storage.objects;
    drop policy if exists bucks_listing_media on storage.objects;
    drop policy if exists bucks_chat on storage.objects;
    drop policy if exists bucks_moments_read on storage.objects;
    drop policy if exists bucks_posts_read on storage.objects;
    create policy bucks_public_read on storage.objects for select to authenticated using (bucket_id in ('avatars', 'listing-media'));
    -- Your own folder in avatars, posts, moments, docs.
    create policy bucks_own_folder on storage.objects for all to authenticated
      using (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text)
      with check (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text);
    create policy bucks_listing_media on storage.objects for all to authenticated
      using (bucket_id = 'listing-media' and public.can_manage_listing(((storage.foldername(name))[1])::uuid))
      with check (bucket_id = 'listing-media' and public.can_manage_listing(((storage.foldername(name))[1])::uuid));
    -- Chat files: any member of the conversation can upload and read.
    create policy bucks_chat on storage.objects for all to authenticated
      using (bucket_id = 'chat' and public.is_member(((storage.foldername(name))[1])::uuid))
      with check (bucket_id = 'chat' and public.is_member(((storage.foldername(name))[1])::uuid));
    -- Moment and post media: readable by whoever can see a live moment / visible post that uses the file.
    create policy bucks_moments_read on storage.objects for select to authenticated
      using (bucket_id = 'moments' and exists (select 1 from public.moments m where m.media_path = name and public.can_see_moment(m, null, null)));
    create policy bucks_posts_read on storage.objects for select to authenticated
      using (bucket_id = 'posts' and exists (select 1 from public.posts p where public.can_see_post(p) and p.media @> jsonb_build_array(jsonb_build_object('path', name))));
  end if;
end $$;

-- Supabase Realtime: stream changes on these tables to the app (row-level security still applies).
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.tasks, public.orders, public.driver_presence, public.invites, public.messages, public.conversation_members, public.moments, public.syncs; exception when duplicate_object then null; end;
  end if;
end $$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
revoke all on public.recommend_tokens from authenticated;
-- Signed-out callers get nothing: every Bucks function needs a signed-in person.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
