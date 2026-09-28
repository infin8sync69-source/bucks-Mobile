-- Services: which services a customer can use where they stand, and the documents a listing needs to go live.
-- Design and the reasoning behind every number: docs/SERVICES_UNLOCK.md. Safe to re-run; apply after the other migrations
-- (it redefines recommend() and search_listings()).
--
--   service_rules          one row per tile in the Services menu: what supply unlocks it, within what radius, how many
--   services_near(lat,lng) each service's state for a customer at that point: SOON / LOCKED / QUIET / OPEN, with the counts
--   service_interest       "Notify me when Food opens here" (the demand side; shown to suppliers as "42 people want this")
--   listings.service       which service a listing belongs to (FOOD, GROCERY, ... ; GIGS for skills, none for drivers)
--   doc_types, service_doc_rules, listing_documents
--                          the documents each service needs, the uploads, and their review by Bucks staff
--   listing_compliance()   what the listing's team sees: each document, required or not, and its status
--   listing_badges()       what everyone sees: verified documents only, with the number only where the law wants it public
-- A listing goes LIVE when it has the community's recommendations AND every required document verified.
set search_path = public, extensions;

-- ---------- the catalogue of services ----------
create table if not exists public.service_rules (
  key          text primary key,
  label        text not null,
  sort         int not null,
  -- AUTO: unlocks by the supply rule below. ON: always unlocked (pilot override). OFF: "coming soon" (not built or paused).
  mode         text not null default 'AUTO' check (mode in ('AUTO', 'ON', 'OFF')),
  -- What counts as supply: LIVE listings of this service, checked vehicles of a kind active nearby, or open jobs.
  supply       text not null check (supply in ('LISTINGS', 'VEHICLES', 'JOBS')),
  listing_kind text check (listing_kind in ('BUSINESS', 'SKILL')),
  vehicle_kind text check (vehicle_kind in ('BIKE', 'AUTO', 'CAB')),
  -- Counted around the customer; the same distance the service is actually served from.
  radius_m     int not null check (radius_m between 500 and 50000),
  min_supply   int not null check (min_supply >= 0),
  -- 0 = no "open now" check (scheduled services such as gigs, jobs, properties).
  min_online   int not null default 0 check (min_online >= 0),
  -- Orders here are delivered by riders; with no bike online nearby the service shows "pickup only right now".
  delivery     boolean not null default false,
  supply_noun  text not null,
  updated_at   timestamptz not null default now()
);
alter table public.service_rules enable row level security;
drop policy if exists service_rules_read on public.service_rules;
create policy service_rules_read on public.service_rules for select to authenticated using (true);
revoke all on public.service_rules from anon, authenticated;
grant select on public.service_rules to authenticated;

-- Launch defaults. "on conflict do nothing": numbers tuned later in the dashboard survive a re-run of this file.
insert into public.service_rules (key, label, sort, mode, supply, listing_kind, vehicle_kind, radius_m, min_supply, min_online, delivery, supply_noun) values
  ('TAXI',       'Taxi',       1,  'AUTO', 'VEHICLES', null,       'CAB',  5000,  3,  1, false, 'cabs'),
  ('AUTO',       'Auto',       2,  'AUTO', 'VEHICLES', null,       'AUTO', 5000,  3,  1, false, 'autos'),
  ('PARCEL',     'Parcel',     3,  'OFF',  'VEHICLES', null,       'BIKE', 3000,  4,  2, false, 'riders'),
  ('FOOD',       'Food',       4,  'AUTO', 'LISTINGS', 'BUSINESS', null,   5000,  10, 3, true,  'restaurants'),
  ('GROCERY',    'Grocery',    5,  'AUTO', 'LISTINGS', 'BUSINESS', null,   3000,  5,  1, true,  'grocery stores'),
  ('VEGETABLES', 'Vegetables', 6,  'AUTO', 'LISTINGS', 'BUSINESS', null,   3000,  3,  1, true,  'vegetable and fruit sellers'),
  ('MEAT',       'Meat',       7,  'AUTO', 'LISTINGS', 'BUSINESS', null,   3000,  2,  1, true,  'meat and fish shops'),
  ('SHOPPING',   'Shopping',   8,  'AUTO', 'LISTINGS', 'BUSINESS', null,   5000,  5,  1, true,  'shops'),
  ('GIGS',       'Gigs',       9,  'AUTO', 'LISTINGS', 'SKILL',    null,   5000,  8,  0, false, 'skilled people'),
  ('JOBS',       'Jobs',       10, 'AUTO', 'JOBS',     null,       null,   10000, 5,  0, false, 'open jobs'),
  ('PROPERTIES', 'Properties', 11, 'AUTO', 'LISTINGS', 'BUSINESS', null,   10000, 10, 0, false, 'property listings')
on conflict (key) do nothing;

-- ---------- which service a listing belongs to ----------
alter table public.listings add column if not exists service text references public.service_rules (key);
-- Set by Bucks when a live listing is taken down for an expired or missing document; cleared when it is fixed.
alter table public.listings add column if not exists compliance_hold boolean not null default false;
create index if not exists listings_service_live_idx on public.listings (service) where status = 'LIVE';

-- The shop's own category decides the service when the app does not say (older app versions, imports).
create or replace function public.service_for_category(c text) returns text language sql immutable set search_path = public, extensions as $$
  select case
    when lower(c) in ('restaurant', 'bakery', 'cafe', 'sweets', 'cloud kitchen', 'tiffin', 'food') then 'FOOD'
    when lower(c) in ('grocery', 'supermarket', 'dairy', 'kirana') then 'GROCERY'
    when lower(c) in ('vegetables', 'fruits', 'vegetables and fruits') then 'VEGETABLES'
    when lower(c) in ('meat', 'chicken', 'mutton', 'fish', 'eggs', 'meat and fish') then 'MEAT'
    when lower(c) in ('real estate agent', 'property owner', 'builder', 'properties') then 'PROPERTIES'
    else 'SHOPPING' end
$$;

-- Skills are always Gigs and drivers have no service tile of their own. A business picks one of the business services.
-- A LIVE listing cannot move to another service from the app: the new service may need documents it never showed.
create or replace function public.listing_service_rules() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.kind = 'SKILL' then new.service := 'GIGS';
  elsif new.kind = 'DRIVER' then new.service := null;
  elsif new.service is null or new.service not in (select key from public.service_rules where supply = 'LISTINGS' and listing_kind = 'BUSINESS') then
    new.service := public.service_for_category(new.category);
  end if;
  if tg_op = 'UPDATE' and current_user = 'authenticated' then
    if new.service is distinct from old.service and old.status <> 'PENDING' then
      raise exception 'a live listing cannot move to another service; ask Bucks support to move it';
    end if;
    if new.compliance_hold <> old.compliance_hold then raise exception 'status, trust, owner and kind are managed by Bucks'; end if;
  end if;
  return new;
end $$;
drop trigger if exists listing_service on public.listings;
create trigger listing_service before insert or update on public.listings for each row execute function public.listing_service_rules();
update public.listings set service = case kind when 'SKILL' then 'GIGS' when 'DRIVER' then null else public.service_for_category(category) end where service is null and kind <> 'DRIVER';

-- ---------- demand: "notify me when it opens here" ----------
create table if not exists public.service_interest (
  profile_id uuid not null references public.profiles on delete cascade,
  service    text not null references public.service_rules on delete cascade,
  location   geography(point, 4326) not null,
  created_at timestamptz not null default now(),
  primary key (profile_id, service)
);
create index if not exists service_interest_service_idx on public.service_interest (service);
create index if not exists service_interest_location_idx on public.service_interest using gist (location);
alter table public.service_interest enable row level security;
drop policy if exists interest_self on public.service_interest;
create policy interest_self on public.service_interest for select to authenticated using (profile_id = public.me());
revoke all on public.service_interest from anon, authenticated;
grant select on public.service_interest to authenticated;

-- Returns true when I am now on the list for this service, false when I just left it.
create or replace function public.toggle_service_interest(p_service text, lat double precision, lng double precision) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from service_rules where key = p_service) then raise exception 'unknown service'; end if;
  delete from service_interest where profile_id = me() and service = p_service;
  if found then return false; end if;
  insert into service_interest (profile_id, service, location) values (me(), p_service, geo(lat, lng));
  return true;
end $$;

-- ---------- each service's state for a customer standing at (lat, lng) ----------
-- SOON:   switched off by Bucks (mode OFF): not built yet, or paused.
-- LOCKED: fewer than min_supply verified providers within radius_m. The app shows "3 of 10 restaurants near you".
-- QUIET:  unlocked, but fewer than min_online of them are online right now ("no autos online nearby right now").
-- OPEN:   usable now.
-- Supply only counts what already passed the community cap and document checks (LIVE listings, ACTIVE vehicles), so a
-- service does not flicker: it locks again only if providers are suspended or leave. Online counts change by the minute,
-- which is why they decide QUIET/OPEN and never LOCKED. delivery_now: a Bucks rider is online close enough to deliver.
create or replace function public.services_near(lat double precision, lng double precision)
returns table (key text, label text, mode text, state text, supply int, min_supply int, online int, min_online int, supply_noun text,
               radius_m int, delivery boolean, delivery_now boolean, interested int, mine boolean)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g),
  counted as (
    select r.*,
      (case r.supply
        when 'LISTINGS' then (select count(*) from listings l, here where l.status = 'LIVE' and l.service = r.key and l.location is not null and st_dwithin(l.location, here.g, r.radius_m))
        -- a vehicle "serves here" when it went online nearby in the last two weeks; vehicles have no home address
        when 'VEHICLES' then (select count(distinct p.vehicle_id) from driver_presence p join vehicles v on v.id = p.vehicle_id and v.status = 'ACTIVE', here
                               where p.kind = r.vehicle_kind and p.location is not null and p.updated_at > now() - interval '14 days' and st_dwithin(p.location, here.g, r.radius_m))
        else (select count(*) from jobs j join listings l on l.id = j.listing_id, here where j.open and l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, here.g, r.radius_m))
      end)::int as supply_n,
      (case r.supply
        when 'LISTINGS' then (select count(*) from listings l, here where l.status = 'LIVE' and l.online and l.service = r.key and l.location is not null and st_dwithin(l.location, here.g, r.radius_m))
        when 'VEHICLES' then (select count(*) from driver_presence p, here where p.online and p.kind = r.vehicle_kind and p.location is not null and p.updated_at > now() - interval '5 minutes' and st_dwithin(p.location, here.g, r.radius_m))
        else 0
      end)::int as online_n
    from service_rules r),
  riders as (
    select count(*)::int n from driver_presence p, here
    where p.online and p.kind = 'BIKE' and p.location is not null and p.updated_at > now() - interval '5 minutes' and st_dwithin(p.location, here.g, public.setting('delivery_radius_m')))
  select c.key, c.label, c.mode,
         case when c.mode = 'OFF' then 'SOON'
              when c.mode = 'AUTO' and c.supply_n < c.min_supply then 'LOCKED'
              when c.min_online > 0 and c.online_n < c.min_online then 'QUIET'
              else 'OPEN' end,
         c.supply_n, c.min_supply, c.online_n, c.min_online, c.supply_noun, c.radius_m, c.delivery, (select n from riders) > 0,
         (select count(*)::int from service_interest i, here where i.service = c.key and st_dwithin(i.location, here.g, c.radius_m)),
         exists (select 1 from service_interest i where i.service = c.key and i.profile_id = public.me())
  from counted c
  order by c.sort
$$;

-- ---------- documents ----------
create table if not exists public.doc_types (
  key           text primary key,
  label         text not null,
  -- Law or trust wants the number shown to customers (FSSAI, GSTIN, RERA). The file itself is never public.
  public_number boolean not null default false,
  -- The app asks for the document number. Off for identity documents: Bucks does not keep ID numbers.
  asks_number   boolean not null default true,
  has_expiry    boolean not null default false,
  -- Checked on submit when set (upper-cased first).
  number_regex  text,
  hint          text not null default ''
);
alter table public.doc_types enable row level security;
drop policy if exists doc_types_read on public.doc_types;
create policy doc_types_read on public.doc_types for select to authenticated using (true);
revoke all on public.doc_types from anon, authenticated;
grant select on public.doc_types to authenticated;

insert into public.doc_types (key, label, public_number, asks_number, has_expiry, number_regex, hint) values
  ('OWNER_ID',         'Owner''s photo ID',                          false, false, false, null,
     'PAN card, voter ID, passport or driving licence. Please do not upload Aadhaar; if it is all you have, use the masked Aadhaar from the UIDAI site.'),
  ('FSSAI',            'FSSAI licence or registration',               true,  true,  true,  '^[0-9]{14}$',
     'The 14-digit number on your FSSAI certificate. Food businesses must show it to customers.'),
  ('GSTIN',            'GST registration',                            true,  true,  false, '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
     'Only if you are registered for GST. The 15-character GSTIN is shown on your profile.'),
  ('SHOP_EST',         'Shop and establishment registration',         false, true,  false, null, 'From your state labour department.'),
  ('TRADE_LICENCE',    'Municipal trade licence',                     false, true,  true,  null, 'From your city corporation (BBMP in Bengaluru). Meat shops need one.'),
  ('RERA',             'RERA registration',                           true,  true,  true,  null,
     'Agents and new projects registered with the state RERA. The number is shown on every property you list.'),
  ('PROPERTY_PROOF',   'Ownership proof',                             false, false, false, null, 'Sale deed, khata or the latest property tax receipt. Only Bucks sees it.'),
  ('AUTHORITY_LETTER', 'Owner''s authorisation',                      false, false, false, null, 'If you list a property for someone else: their signed letter allowing you to.'),
  ('SKILL_CERT',       'Trade licence or certificate',                false, true,  true,  null, 'For example an electrical wireman licence or a training certificate.'),
  ('POLICE_CERT',      'Police clearance certificate',                false, false, true,  null, 'Earns a "Background checked" badge. Recommended for work inside homes.')
on conflict (key) do nothing;

create table if not exists public.service_doc_rules (
  service  text not null references public.service_rules on delete cascade,
  doc_type text not null references public.doc_types on delete cascade,
  required boolean not null,
  primary key (service, doc_type)
);
create index if not exists service_doc_rules_type_idx on public.service_doc_rules (doc_type);
alter table public.service_doc_rules enable row level security;
drop policy if exists service_doc_rules_read on public.service_doc_rules;
create policy service_doc_rules_read on public.service_doc_rules for select to authenticated using (true);
revoke all on public.service_doc_rules from anon, authenticated;
grant select on public.service_doc_rules to authenticated;

insert into public.service_doc_rules (service, doc_type, required) values
  ('FOOD', 'OWNER_ID', true), ('FOOD', 'FSSAI', true), ('FOOD', 'GSTIN', false), ('FOOD', 'TRADE_LICENCE', false), ('FOOD', 'SHOP_EST', false),
  ('GROCERY', 'OWNER_ID', true), ('GROCERY', 'FSSAI', true), ('GROCERY', 'GSTIN', false), ('GROCERY', 'SHOP_EST', false),
  ('VEGETABLES', 'OWNER_ID', true), ('VEGETABLES', 'FSSAI', true), ('VEGETABLES', 'GSTIN', false),
  ('MEAT', 'OWNER_ID', true), ('MEAT', 'FSSAI', true), ('MEAT', 'TRADE_LICENCE', true), ('MEAT', 'GSTIN', false),
  ('SHOPPING', 'OWNER_ID', true), ('SHOPPING', 'GSTIN', false), ('SHOPPING', 'SHOP_EST', false), ('SHOPPING', 'TRADE_LICENCE', false),
  ('GIGS', 'OWNER_ID', true), ('GIGS', 'SKILL_CERT', false), ('GIGS', 'POLICE_CERT', false),
  ('PROPERTIES', 'OWNER_ID', true), ('PROPERTIES', 'RERA', false), ('PROPERTIES', 'PROPERTY_PROOF', false), ('PROPERTIES', 'AUTHORITY_LETTER', false)
on conflict (service, doc_type) do nothing;

-- Bucks staff review documents. Added by hand in the dashboard: insert into staff (profile_id) values ('<profile id>').
create table if not exists public.staff (
  profile_id uuid primary key references public.profiles on delete cascade,
  added_at   timestamptz not null default now()
);
alter table public.staff enable row level security;
revoke all on public.staff from anon, authenticated;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.staff where profile_id = public.me())
$$;

-- One current document per listing and type; replacing it sends it back for review.
create table if not exists public.listing_documents (
  id          uuid primary key default public.uuid_v7(),
  listing_id  uuid not null references public.listings on delete cascade,
  doc_type    text not null references public.doc_types,
  path        text not null,                               -- private "docs" bucket: <uploader profile id>/<file>
  number      text not null default '',
  expires_on  date,
  status      text not null default 'PENDING' check (status in ('PENDING', 'VERIFIED', 'REJECTED', 'EXPIRED')),
  note        text not null default '',                     -- why Bucks rejected it
  uploaded_by uuid not null references public.profiles on delete cascade,
  reviewed_by uuid references public.profiles on delete set null,
  reviewed_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (listing_id, doc_type)
);
create index if not exists listing_documents_type_idx on public.listing_documents (doc_type);
create index if not exists listing_documents_uploader_idx on public.listing_documents (uploaded_by);
create index if not exists listing_documents_reviewer_idx on public.listing_documents (reviewed_by);
create index if not exists listing_documents_pending_idx on public.listing_documents (created_at) where status = 'PENDING';
alter table public.listing_documents enable row level security;
drop policy if exists listing_documents_read on public.listing_documents;
-- The listing's owner and admins, and Bucks staff. Customers see badges only (listing_badges).
create policy listing_documents_read on public.listing_documents for select to authenticated
  using (public.can_manage_listing(listing_id) or public.is_staff());
revoke all on public.listing_documents from anon, authenticated;
grant select on public.listing_documents to authenticated;

-- Staff can open the files to check them; everyone else only their own folder (schema.sql's policy).
do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "docs staff read" on storage.objects;
    create policy "docs staff read" on storage.objects for select to authenticated using (bucket_id = 'docs' and public.is_staff());
  end if;
end $$;

-- Every required document of the listing's service is verified and in date.
create or replace function public.listing_compliant(p_listing uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select not exists (
    select 1 from listings l join service_doc_rules r on r.service = l.service and r.required
    where l.id = p_listing
      and not exists (select 1 from listing_documents d where d.listing_id = l.id and d.doc_type = r.doc_type and d.status = 'VERIFIED'
                        and (d.expires_on is null or d.expires_on >= current_date)))
$$;

-- Moves a listing live when both gates are met: the community's recommendations and the documents. Also brings back a
-- listing that was held for a document once the document is verified again.
create or replace function public.try_go_live(p_listing uuid) returns text language plpgsql security definer set search_path = public, extensions as $$
declare l listings; recs int;
begin
  select * into l from listings where id = p_listing for update;
  if not found then return null; end if;
  if l.status = 'PENDING' then
    select count(*) into recs from recommendations where listing_id = l.id;
    if recs >= setting('min_recommendations') and listing_compliant(l.id) then update listings set status = 'LIVE' where id = l.id; return 'LIVE'; end if;
  elsif l.status = 'SUSPENDED' and l.compliance_hold and listing_compliant(l.id) then
    update listings set status = 'LIVE', compliance_hold = false where id = l.id; return 'LIVE';
  end if;
  return l.status;
end $$;

-- recommend() from schema.sql; the last step now goes through try_go_live, so documents count too.
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
  perform try_go_live(l.id);
  return n;
end $$;

-- The listing's team uploads (or replaces) a document. The file must already be in the uploader's own docs folder.
create or replace function public.submit_document(p_listing uuid, p_type text, p_path text, p_number text default '', p_expires date default null)
returns public.listing_documents language plpgsql security definer set search_path = public, extensions as $$
declare l listings; t doc_types; num text := upper(regexp_replace(coalesce(p_number, ''), '\s', '', 'g')); d listing_documents;
begin
  select * into l from listings where id = p_listing;
  if not found or not can_manage_listing(p_listing) then raise exception 'listing not found'; end if;
  select * into t from doc_types where key = p_type;
  if not found or not exists (select 1 from service_doc_rules where service = l.service and doc_type = p_type) then
    raise exception 'this document is not needed for %', coalesce((select label from service_rules where key = l.service), 'this listing');
  end if;
  if coalesce(p_path, '') not like me()::text || '/%' then raise exception 'upload the file first'; end if;
  if not t.asks_number then num := ''; end if;
  if t.asks_number and num = '' and t.public_number then raise exception 'add the % number', t.label; end if;
  if t.number_regex is not null and num <> '' and num !~ t.number_regex then raise exception 'that does not look like a valid % number', t.label; end if;
  if t.has_expiry and p_expires is null then raise exception 'add the date the % expires', t.label; end if;
  if p_expires is not null and p_expires < current_date then raise exception 'this % has already expired', t.label; end if;
  insert into listing_documents (listing_id, doc_type, path, number, expires_on, uploaded_by)
  values (p_listing, p_type, p_path, num, case when t.has_expiry then p_expires end, me())
  on conflict (listing_id, doc_type) do update
    set path = excluded.path, number = excluded.number, expires_on = excluded.expires_on, uploaded_by = excluded.uploaded_by,
        status = 'PENDING', note = '', reviewed_by = null, reviewed_at = null, updated_at = now()
  returning * into d;
  return d;
end $$;

-- Remove a document. A verified required one can only be replaced: removing it would leave a live listing unchecked.
create or replace function public.delete_document(p_listing uuid, p_type text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l listings; d listing_documents;
begin
  select * into l from listings where id = p_listing;
  if not found or not can_manage_listing(p_listing) then raise exception 'listing not found'; end if;
  select * into d from listing_documents where listing_id = p_listing and doc_type = p_type;
  if not found then return; end if;
  if d.status = 'VERIFIED' and exists (select 1 from service_doc_rules where service = l.service and doc_type = p_type and required) then
    raise exception 'this document is required; upload a new one to replace it';
  end if;
  delete from listing_documents where id = d.id;
end $$;

-- Staff decision on one document. A verified document may move the listing live (try_go_live).
create or replace function public.review_document(p_doc uuid, p_approve boolean, p_note text default '', p_expires date default null) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare d listing_documents;
begin
  if not is_staff() then raise exception 'only Bucks staff can review documents'; end if;
  select * into d from listing_documents where id = p_doc for update;
  if not found then raise exception 'document not found'; end if;
  if not p_approve and coalesce(trim(p_note), '') = '' then raise exception 'say why it was rejected, so they can fix it'; end if;
  update listing_documents set status = case when p_approve then 'VERIFIED' else 'REJECTED' end, note = case when p_approve then '' else trim(p_note) end,
         expires_on = coalesce(p_expires, expires_on), reviewed_by = me(), reviewed_at = now(), updated_at = now()
  where id = p_doc;
  return try_go_live(d.listing_id);
end $$;

-- For the listing's team: every document its service asks for, required first, with where each one stands.
create or replace function public.listing_compliance(p_listing uuid)
returns table (doc_type text, label text, hint text, required boolean, public_number boolean, asks_number boolean, has_expiry boolean,
               status text, number text, expires_on date, note text, path text)
language sql stable security definer set search_path = public, extensions as $$
  select t.key, t.label, t.hint, r.required, t.public_number, t.asks_number, t.has_expiry,
         coalesce(case when d.status = 'VERIFIED' and d.expires_on < current_date then 'EXPIRED' else d.status end, 'MISSING'), coalesce(d.number, ''), d.expires_on, coalesce(d.note, ''), d.path
  from listings l
  join service_doc_rules r on r.service = l.service
  join doc_types t on t.key = r.doc_type
  left join listing_documents d on d.listing_id = l.id and d.doc_type = t.key
  where l.id = p_listing and (public.can_manage_listing(l.id) or public.is_staff())
  order by r.required desc, t.label
$$;

-- For everyone: verified, in-date documents of a live listing (or of my own). The number only where it is meant to be public.
create or replace function public.listing_badges(p_listing uuid) returns table (doc_type text, label text, number text, expires_on date)
language sql stable security definer set search_path = public, extensions as $$
  select t.key, t.label, case when t.public_number then d.number else '' end, d.expires_on
  from listing_documents d join doc_types t on t.key = d.doc_type join listings l on l.id = d.listing_id
  where d.listing_id = p_listing and d.status = 'VERIFIED' and (d.expires_on is null or d.expires_on >= current_date)
    and (l.status = 'LIVE' or public.can_manage_listing(l.id))
  order by t.label
$$;

-- Staff queue: documents waiting for review, oldest first.
create or replace function public.documents_to_review(lim int default 50)
returns table (id uuid, listing_id uuid, listing_title text, service text, doc_type text, label text, number text, expires_on date, path text, uploaded_by uuid, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select d.id, d.listing_id, l.title, l.service, d.doc_type, t.label, d.number, d.expires_on, d.path, d.uploaded_by, d.updated_at
  from listing_documents d join listings l on l.id = d.listing_id join doc_types t on t.key = d.doc_type
  where public.is_staff() and d.status = 'PENDING'
  order by d.updated_at limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- Daily: documents past their date become EXPIRED; a live listing whose required document expired more than 7 days ago
-- (or is missing altogether) is held until a new one is verified (try_go_live brings it back).
create or replace function public.expire_documents() returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update listing_documents set status = 'EXPIRED', updated_at = now() where status in ('VERIFIED', 'PENDING') and expires_on < current_date;
  update listings l set status = 'SUSPENDED', compliance_hold = true, online = false
  where l.status = 'LIVE' and exists (
    select 1 from service_doc_rules r where r.service = l.service and r.required and not exists (
      select 1 from listing_documents d where d.listing_id = l.id and d.doc_type = r.doc_type
        and (d.expires_on is null or d.expires_on >= current_date - 7) and d.status <> 'REJECTED'));
end $$;

do $$ begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('bucks-expire-documents', '35 20 * * *', 'select public.expire_documents()');   -- 02:05 IST
  end if;
end $$;

-- Deleting an account (profiles.status -> DELETED) also drops its "notify me" pins and the document rows it uploaded.
-- The files in storage are removed by the app before it calls delete_my_account (storage objects cannot be removed from SQL).
create or replace function public.profile_deleted_cleanup() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'DELETED' and old.status is distinct from 'DELETED' then
    delete from service_interest where profile_id = new.id;
    delete from listing_documents where uploaded_by = new.id;
  end if;
  return new;
end $$;
drop trigger if exists profile_deleted_cleanup on public.profiles;
create trigger profile_deleted_cleanup after update of status on public.profiles for each row execute function public.profile_deleted_cleanup();

-- ---------- search by service ----------
-- search_listings from schema.sql plus a services filter (the Food / Grocery / ... tiles open search with it).
drop function if exists public.search_listings(text, double precision, double precision, int, text[], int);
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null,
                                                  lim int default 40, services text[] default null)
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
    and (services is null or l.service = any(services))
    and l.location is not null and st_dwithin(l.location, here.g, radius_m)
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit lim
$$;

-- ---------- grants ----------
revoke execute on function public.services_near(double precision, double precision), public.toggle_service_interest(text, double precision, double precision),
  public.submit_document(uuid, text, text, text, date), public.delete_document(uuid, text), public.review_document(uuid, boolean, text, date),
  public.listing_compliance(uuid), public.listing_badges(uuid), public.documents_to_review(int), public.is_staff(), public.listing_compliant(uuid),
  public.search_listings(text, double precision, double precision, int, text[], int, text[]), public.recommend(text, double precision, double precision) from public, anon;
grant execute on function public.services_near(double precision, double precision), public.toggle_service_interest(text, double precision, double precision),
  public.submit_document(uuid, text, text, text, date), public.delete_document(uuid, text), public.review_document(uuid, boolean, text, date),
  public.listing_compliance(uuid), public.listing_badges(uuid), public.documents_to_review(int), public.is_staff(),
  public.search_listings(text, double precision, double precision, int, text[], int, text[]), public.recommend(text, double precision, double precision) to authenticated;
-- Internal: only other functions, triggers and the scheduler call these.
revoke execute on function public.try_go_live(uuid), public.expire_documents(), public.listing_service_rules(), public.profile_deleted_cleanup(),
  public.listing_compliant(uuid) from public, anon, authenticated;
