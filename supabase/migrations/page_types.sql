-- Page types (bucks_32): a business, NGO, school or association is still kind = BUSINESS, but now carries a page type that decides
-- what its catalogue is (Products, Services, Programs, Events), what its primary button does, which Home tile it belongs to and
-- which documents make sense. Products and orders exist only on the two shop types. See docs/ORG_PROFILES_PLAN.md.
--
-- The app keeps the same registry in ui/PageTypes.kt (fallback when offline); this table is what the triggers enforce.

create table if not exists public.listing_types (
  key text primary key,
  group_key text not null check (group_key in ('SHOPS', 'LOCAL_SERVICES', 'COMPANIES', 'COMMUNITY', 'INSTITUTIONS')),
  group_label text not null,
  label text not null,
  blurb text not null default '',
  kind text not null default 'BUSINESS',
  /** Service row the page lives under. Shop types derive it from the category instead (restaurant -> FOOD). */
  default_service text not null references public.service_rules(key),
  tabs text[] not null,
  catalogue_label text,                    -- "Products", "Services", "Programs", "Events"; null = no catalogue tab
  item_kinds text[] not null default '{}', -- which items.kind values the catalogue holds
  cta text not null check (cta in ('CART', 'BOOK', 'QUOTE', 'ENQUIRE', 'VOLUNTEER', 'JOIN', 'DIRECTIONS', 'HIRE')),
  cta_label text not null,
  reviews boolean not null default true,
  docs text[] not null default '{}',       -- doc types that make sense for this type (filters the Documents screen)
  sort int not null default 0,
  active boolean not null default true
);
alter table public.listing_types enable row level security;
drop policy if exists listing_types_read on public.listing_types;
create policy listing_types_read on public.listing_types for select using (true);
grant select on public.listing_types to authenticated;
revoke all on public.listing_types from anon;

-- ---------- new Home tiles ----------
insert into public.service_rules (key, label, sort, mode, supply, listing_kind, vehicle_kind, radius_m, min_supply, min_online, delivery, supply_noun) values
  ('LOCAL_SERVICES', 'Local services', 12, 'AUTO', 'LISTINGS', 'BUSINESS', null, 5000, 1, 0, false, 'service providers'),
  ('BIZ_PRO', 'Companies', 13, 'AUTO', 'LISTINGS', 'BUSINESS', null, 25000, 1, 0, false, 'companies and firms'),
  ('COMMUNITY', 'NGOs and groups', 14, 'AUTO', 'LISTINGS', 'BUSINESS', null, 10000, 1, 0, false, 'NGOs and community groups'),
  ('INSTITUTIONS', 'Institutions', 15, 'AUTO', 'LISTINGS', 'BUSINESS', null, 10000, 1, 0, false, 'schools, colleges and institutions')
on conflict (key) do update set label = excluded.label, sort = excluded.sort, radius_m = excluded.radius_m, supply_noun = excluded.supply_noun;

-- Documents an organisation may show Bucks; none are required, so an empty staff table never blocks a page from going live.
insert into public.doc_types (key, label, public_number, asks_number, has_expiry, number_regex, hint) values
  ('NGO_REG', 'NGO / trust / society registration', true, true, false, null, 'Registration certificate from the charity commissioner, registrar of societies or the Companies Act (section 8).'),
  ('AFFILIATION', 'Board or university affiliation', true, true, true, null, 'CBSE, ICSE, state board or university affiliation letter. The number is shown on your page.'),
  ('UDYAM', 'Udyam (MSME) registration', true, true, false, '^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$', 'Udyam registration number, if you have one.')
on conflict (key) do nothing;
insert into public.service_doc_rules (service, doc_type, required) values
  ('LOCAL_SERVICES', 'OWNER_ID', false), ('LOCAL_SERVICES', 'GSTIN', false), ('LOCAL_SERVICES', 'TRADE_LICENCE', false), ('LOCAL_SERVICES', 'SHOP_EST', false),
  ('BIZ_PRO', 'OWNER_ID', false), ('BIZ_PRO', 'GSTIN', false), ('BIZ_PRO', 'UDYAM', false),
  ('COMMUNITY', 'OWNER_ID', false), ('COMMUNITY', 'NGO_REG', false),
  ('INSTITUTIONS', 'OWNER_ID', false), ('INSTITUTIONS', 'NGO_REG', false), ('INSTITUTIONS', 'AFFILIATION', false)
on conflict do nothing;

-- ---------- the 14 types ----------
insert into public.listing_types (key, group_key, group_label, label, blurb, default_service, tabs, catalogue_label, item_kinds, cta, cta_label, reviews, docs, sort) values
  ('RETAIL_SHOP',   'SHOPS', 'Shops', 'Shop', 'Restaurant, grocery, store. Products with prices, orders and delivery nearby.', 'SHOPPING',
     '{products,feed,about,jobs,reviews}', 'Products', '{PRODUCT}', 'CART', 'Add to cart', true, '{OWNER_ID,GSTIN,FSSAI,SHOP_EST,TRADE_LICENCE}', 1),
  ('D2C_STORE',     'SHOPS', 'Shops', 'Online store', 'Ships across India by courier. Products, orders, tracking.', 'SHOPPING',
     '{products,about,feed,reviews}', 'Products', '{PRODUCT}', 'CART', 'Add to cart', true, '{OWNER_ID,GSTIN,UDYAM}', 2),
  ('LOCAL_SERVICE', 'LOCAL_SERVICES', 'Local services', 'Local service', 'Salon, clinic, repair, coaching, gym. Services with prices; people book.', 'LOCAL_SERVICES',
     '{services,photos,about,feed,reviews}', 'Services', '{SERVICE}', 'BOOK', 'Book', true, '{OWNER_ID,GSTIN,TRADE_LICENCE,SHOP_EST}', 3),
  ('IT_COMPANY',    'COMPANIES', 'Companies', 'IT company', 'Software, apps, design, digital marketing. Services from a price or on quote.', 'BIZ_PRO',
     '{services,photos,about,team,jobs,reviews,feed}', 'Services', '{SERVICE}', 'QUOTE', 'Get a quote', true, '{OWNER_ID,GSTIN,UDYAM}', 4),
  ('COLLECTIVE',    'COMPANIES', 'Companies', 'Freelancer collective', 'A few pros working together. People, then services.', 'BIZ_PRO',
     '{team,services,photos,about,reviews,feed}', 'Services', '{SERVICE}', 'HIRE', 'Hire us', true, '{OWNER_ID,GSTIN}', 5),
  ('PRO_FIRM',      'COMPANIES', 'Companies', 'Professional firm', 'Accounting, legal, architecture, consulting.', 'BIZ_PRO',
     '{services,about,team,reviews,feed}', 'Services', '{SERVICE}', 'ENQUIRE', 'Enquire', true, '{OWNER_ID,GSTIN,UDYAM}', 6),
  ('MANUFACTURER',  'COMPANIES', 'Companies', 'Manufacturer / wholesaler', 'A catalogue with per-unit prices; buyers ask for a quote, no cart.', 'BIZ_PRO',
     '{services,about,jobs,reviews,feed}', 'Catalogue', '{SERVICE}', 'QUOTE', 'Get a quote', true, '{OWNER_ID,GSTIN,UDYAM}', 7),
  ('NGO_CHARITY',   'COMMUNITY', 'NGOs and groups', 'NGO / charity', 'Programs people can join or support. Volunteers, team, updates.', 'COMMUNITY',
     '{about,programs,jobs,team,feed,reviews}', 'Programs', '{PROGRAM}', 'VOLUNTEER', 'Volunteer', true, '{OWNER_ID,NGO_REG}', 8),
  ('COMMUNITY_GROUP','COMMUNITY', 'NGOs and groups', 'Community group', 'Neighbours doing things together. Events and updates.', 'COMMUNITY',
     '{about,events,feed,team}', 'Events', '{EVENT,SERVICE}', 'JOIN', 'Join', false, '{OWNER_ID}', 9),
  ('SCHOOL_COLLEGE','INSTITUTIONS', 'Institutions', 'School / college', 'Courses and classes, admissions, campus, staff openings.', 'INSTITUTIONS',
     '{about,programs,photos,team,jobs,feed,reviews}', 'Programs', '{PROGRAM}', 'ENQUIRE', 'Admission enquiry', true, '{OWNER_ID,NGO_REG,AFFILIATION}', 10),
  ('HOSPITAL',      'INSTITUTIONS', 'Institutions', 'Hospital', 'Departments and services; people book a visit.', 'INSTITUTIONS',
     '{about,services,team,feed,reviews}', 'Services', '{SERVICE}', 'BOOK', 'Book a visit', true, '{OWNER_ID,GSTIN}', 11),
  ('WORSHIP_PLACE', 'INSTITUTIONS', 'Institutions', 'Place of worship', 'Timings, events and updates. No reviews.', 'INSTITUTIONS',
     '{about,events,photos,feed}', 'Events', '{EVENT}', 'DIRECTIONS', 'Directions', false, '{OWNER_ID,NGO_REG}', 12),
  ('ASSOCIATION',   'INSTITUTIONS', 'Institutions', 'Association / society', 'Residents, alumni, trade or welfare association. Members, events, notices.', 'INSTITUTIONS',
     '{about,events,team,jobs,feed}', 'Events', '{EVENT,SERVICE}', 'JOIN', 'Join', false, '{OWNER_ID,NGO_REG}', 13)
on conflict (key) do update set group_key = excluded.group_key, group_label = excluded.group_label, label = excluded.label, blurb = excluded.blurb,
  default_service = excluded.default_service, tabs = excluded.tabs, catalogue_label = excluded.catalogue_label, item_kinds = excluded.item_kinds,
  cta = excluded.cta, cta_label = excluded.cta_label, reviews = excluded.reviews, docs = excluded.docs, sort = excluded.sort;

-- ---------- columns and constraints ----------
alter table public.listings add column if not exists type_key text references public.listing_types(key);
create index if not exists listings_type_idx on public.listings (type_key) where status = 'LIVE';

alter table public.items drop constraint if exists items_kind_check;
alter table public.items add constraint items_kind_check check (kind in ('PRODUCT', 'SERVICE', 'PROGRAM', 'EVENT'));
alter table public.jobs drop constraint if exists jobs_job_type_check;
alter table public.jobs add constraint jobs_job_type_check check (job_type in ('FULL_TIME', 'PART_TIME', 'GIG', 'VOLUNTEER'));

-- ---------- triggers ----------
-- The service follows the type: shops keep the category-derived service (restaurant -> FOOD), everything else takes the type's row.
create or replace function public.listing_service_rules() returns trigger language plpgsql set search_path = public, extensions as $$
declare t listing_types;
begin
  if new.kind = 'SKILL' then new.service := 'GIGS';
  elsif new.kind = 'DRIVER' then new.service := null;
  elsif new.kind = 'ASSET' then new.service := public.asset_service(new.category);
  else
    -- Every business has a page type: older app builds that send none get a shop, by whether it ships.
    if new.type_key is null then new.type_key := case when lower(coalesce(new.details->>'ships_india', '')) = 'true' then 'D2C_STORE' else 'RETAIL_SHOP' end; end if;
    select * into t from public.listing_types where key = new.type_key;
    if t.group_key = 'SHOPS' then
      if new.service is null or new.service not in (select key from public.service_rules where supply = 'LISTINGS' and listing_kind = 'BUSINESS' and key not in ('LOCAL_SERVICES', 'BIZ_PRO', 'COMMUNITY', 'INSTITUTIONS')) then
        new.service := public.service_for_category(new.category);
      end if;
    else new.service := t.default_service; end if;
  end if;
  if tg_op = 'UPDATE' and current_user = 'authenticated' then
    if new.service is distinct from old.service and old.status <> 'PENDING' and coalesce(setting('pilot_skip_checks'), 0) <> 1 then
      raise exception 'a live listing cannot move to another service; ask Bucks support to move it';
    end if;
    if new.compliance_hold <> old.compliance_hold then raise exception 'status, trust, owner and kind are managed by Bucks'; end if;
  end if;
  return new;
end $$;

-- The type must fit the kind and may only change while the page is pending (or during the pilot).
create or replace function public.listing_type_guard() returns trigger language plpgsql set search_path = public, extensions as $$
declare t listing_types;
begin
  if new.type_key is null then return new; end if;
  select * into t from public.listing_types where key = new.type_key and active;
  if not found then raise exception 'unknown page type'; end if;
  if t.kind <> new.kind then raise exception 'that page type is for a %', lower(t.kind); end if;
  if tg_op = 'UPDATE' and current_user = 'authenticated' and new.type_key is distinct from old.type_key and old.type_key is not null
     and old.status <> 'PENDING' and coalesce(setting('pilot_skip_checks'), 0) <> 1 then
    raise exception 'the page type is fixed once the page is live; ask Bucks support to change it';
  end if;
  return new;
end $$;
drop trigger if exists listing_type_guard on public.listings;
-- Runs before listing_service_rules (alphabetical order of trigger names: "listing_service_rules" > "listing_a_type_guard").
create trigger listing_a_type_guard before insert or update on public.listings for each row execute function public.listing_type_guard();

-- Items must match the page's catalogue: a product on an NGO page, or a program on a shop, is refused.
create or replace function public.items_kind_guard() returns trigger language plpgsql set search_path = public, extensions as $$
declare kinds text[];
begin
  select t.item_kinds into kinds from public.listings l join public.listing_types t on t.key = l.type_key where l.id = new.listing_id;
  if kinds is not null and not (new.kind = any(kinds)) then
    raise exception 'this page lists %, not %', lower(array_to_string(kinds, ' or ')) || 's', lower(new.kind) || 's';
  end if;
  return new;
end $$;
drop trigger if exists items_kind_guard on public.items;
create trigger items_kind_guard before insert or update of kind, listing_id on public.items for each row execute function public.items_kind_guard();

-- Orders exist only where the catalogue holds products.
create or replace function public.orders_module_guard() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.listings l join public.listing_types t on t.key = l.type_key where l.id = new.listing_id and 'PRODUCT' = any(t.item_kinds)) then
    raise exception 'this page does not sell products';
  end if;
  return new;
end $$;
drop trigger if exists orders_module_guard on public.orders;
create trigger orders_module_guard before insert on public.orders for each row execute function public.orders_module_guard();

-- ---------- backfill ----------
update public.listings set type_key = case
    when details->>'org_type' in ('NGO') then 'NGO_CHARITY'
    when details->>'org_type' = 'COMMUNITY' then 'COMMUNITY_GROUP'
    when details->>'org_type' in ('SCHOOL', 'COLLEGE') then 'SCHOOL_COLLEGE'
    when details->>'org_type' = 'ASSOCIATION' then 'ASSOCIATION'
    when details->>'org_type' in ('IT_SERVICES', 'IT_PRODUCT') then 'IT_COMPANY'
    when details->>'org_type' = 'SERVICE' then 'LOCAL_SERVICE'
    when lower(coalesce(details->>'ships_india', '')) = 'true' then 'D2C_STORE'
    else 'RETAIL_SHOP' end
  where kind = 'BUSINESS' and type_key is null;
-- The trigger above recomputes service from the type; touch every business once so services follow.
update public.listings set updated_at = now() where kind = 'BUSINESS';
-- Programs for NGOs and schools; services elsewhere already match their types.
update public.items i set kind = 'PROGRAM' from public.listings l where l.id = i.listing_id and l.type_key in ('NGO_CHARITY', 'SCHOOL_COLLEGE') and i.kind <> 'PROGRAM';
update public.items i set kind = 'EVENT' from public.listings l where l.id = i.listing_id and l.type_key in ('COMMUNITY_GROUP', 'ASSOCIATION') and i.kind = 'SERVICE' and i.price = 0;
update public.jobs j set job_type = 'VOLUNTEER' from public.listings l where l.id = j.listing_id and l.type_key = 'NGO_CHARITY' and j.pay ilike '%unpaid%';

-- ---------- search returns the type (so cards can say "NGO" or "School") ----------
-- The return type changes, so the old function is renamed out of the way (kept for rollback) and a new one created.
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'search_listings')
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'search_listings_v1') then
    alter function public.search_listings(text, double precision, double precision, integer, text[], integer, text[]) rename to search_listings_v1;
    revoke execute on function public.search_listings_v1(text, double precision, double precision, integer, text[], integer, text[]) from anon, authenticated, public;
  end if;
end $$;
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null, lim int default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int, details jsonb,
               distance_m double precision, matched_item text, min_price int, type_key text, group_key text)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         (select i.name from items i where i.listing_id = l.id and term.t is not null and i.name ilike '%' || term.t || '%' order by i.price limit 1) as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock and i.price > 0) as min_price,
         l.type_key, t.group_key
  from listings l left join listing_types t on t.key = l.type_key, here, term
  where l.status = 'LIVE'
    and (kinds is null or l.kind = any(kinds))
    and (services is null or l.service = any(services))
    and ((l.location is not null and st_dwithin(l.location, here.g, radius_m)) or (l.kind = 'BUSINESS' and lower(coalesce(l.details->>'ships_india', '')) = 'true'))
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or coalesce(t.label, '') ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit lim
$$;
revoke execute on function public.search_listings(text, double precision, double precision, integer, text[], integer, text[]) from anon, public;
grant execute on function public.search_listings(text, double precision, double precision, integer, text[], integer, text[]) to authenticated;

-- ---------- every page belongs to a real person ----------
-- "By <name>" under a page title, with how far the person's identity has been checked. Phone is implicit (OTP sign-in);
-- id_checked means Bucks staff verified a photo ID on one of their pages. Face / biometric levels come later on the same line.
create or replace function public.listing_owner(p_listing uuid)
returns table (id uuid, name text, short_code text, photo_url text, area text, member_since timestamptz, id_checked boolean, pages int)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, coalesce(nullif(p.name, ''), 'Bucks member'), p.short_code, p.photo_url, p.area, p.created_at,
         exists (select 1 from listing_documents d join listings x on x.id = d.listing_id where x.owner_id = p.id and d.doc_type = 'OWNER_ID' and d.status = 'VERIFIED'),
         (select count(*)::int from listings x where x.owner_id = p.id and x.status = 'LIVE')
  from listings l join profiles p on p.id = l.owner_id
  where l.id = p_listing and (l.status = 'LIVE' or public.can_manage_listing(l.id) or l.owner_id = public.me())
$$;
revoke execute on function public.listing_owner(uuid) from anon, public;
grant execute on function public.listing_owner(uuid) to authenticated;
-- search_listings also returns owner_id and owner_name (and matches the owner's name); applied live as a rename of the previous
-- version to search_listings_v2 followed by create. The definition above is superseded by this one:
--   returns table (..., type_key text, group_key text, owner_id uuid, owner_name text)
--   ... l.type_key, t.group_key, l.owner_id, coalesce(nullif(o.name, ''), 'Bucks member')
--   from listings l left join listing_types t on t.key = l.type_key join profiles o on o.id = l.owner_id, here, term
--   ... or o.name ilike '%' || term.t || '%'
