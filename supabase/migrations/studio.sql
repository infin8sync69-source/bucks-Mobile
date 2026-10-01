-- Studio: the professional space (hamburger menu), on top of schema.sql and the other migrations.
--
-- 1. Assets: a fourth listing kind for things people sell, rent or lease (houses, flats, plots, shops, offices, vehicles,
--    equipment). details carries mode (SELL / RENT / LEASE / PG), price and price_unit; property types belong to the
--    Properties service, so they need its documents (owner ID) before they go live, like every other listing.
-- 2. Galleries: listings.gallery holds up to 20 photos with captions (a shop's photos, a worker's portfolio, a flat's rooms).
--    Every photo must sit in that listing's own folder of the listing-media bucket, so nobody can point a gallery at an
--    outside tracker or someone else's files.
-- 3. Products and services get a description, up to 8 photos, a stock count (null = not counted) and free-form details
--    (duration, pricing model). place_order checks and takes stock; a rejected, expired or cancelled order puts it back.
--    Stock at 0 marks the item out of stock.
-- 4. Bucks ID card: profiles.id_issued_at starts a one-year validity. renew_bucks_id() renews it in the last 30 days or
--    after it lapsed; nobody can set the date directly.
set search_path = public, extensions;

-- ---------- 1. assets ----------
alter table public.listings drop constraint if exists listings_kind_check;
alter table public.listings add constraint listings_kind_check check (kind in ('BUSINESS', 'SKILL', 'DRIVER', 'ASSET'));
alter table public.listings drop constraint if exists listings_asset_details;
alter table public.listings add constraint listings_asset_details check (
  kind <> 'ASSET' or (
    coalesce(details->>'mode', '') in ('SELL', 'RENT', 'LEASE', 'PG')
    and case when jsonb_typeof(details->'price') = 'number' then (details->>'price')::numeric >= 0 else false end
    and coalesce(details->>'price_unit', 'TOTAL') in ('TOTAL', 'MONTH', 'YEAR', 'DAY')));

-- Which asset types are property (the Properties service and its documents); vehicles, equipment and the rest have none.
create or replace function public.asset_service(c text) returns text language sql immutable set search_path = public, extensions as $$
  select case when lower(coalesce(c, '')) in ('house', 'flat', 'villa', 'plot / land', 'shop', 'office', 'warehouse', 'pg / room', 'commercial space')
              then 'PROPERTIES' end
$$;

-- listing_service_rules from services.sql, plus assets.
create or replace function public.listing_service_rules() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.kind = 'SKILL' then new.service := 'GIGS';
  elsif new.kind = 'DRIVER' then new.service := null;
  elsif new.kind = 'ASSET' then new.service := public.asset_service(new.category);
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

-- ---------- 2. galleries ----------
-- Photos are public URLs of listing-media/<listing id>/<file>; captions up to 200 characters.
create or replace function public.media_urls_ok(g jsonb, lid uuid, max_n int) returns boolean language sql immutable set search_path = public, extensions as $$
  select jsonb_typeof(g) = 'array' and jsonb_array_length(g) <= max_n and not exists (
    select 1 from jsonb_array_elements(g) e
    where jsonb_typeof(e) <> 'object'
       or coalesce(e->>'url', '') !~ ('^https://[^/]+/storage/v1/object/public/listing-media/' || lid::text || '/[^/]+$')
       or length(coalesce(e->>'caption', '')) > 200)
$$;
alter table public.listings add column if not exists gallery jsonb not null default '[]';
alter table public.listings drop constraint if exists listings_gallery_ok;
alter table public.listings add constraint listings_gallery_ok check (public.media_urls_ok(gallery, id, 20));

-- ---------- 3. products and services ----------
alter table public.items add column if not exists description text not null default '';
alter table public.items add column if not exists stock int;
alter table public.items add column if not exists photos jsonb not null default '[]';
alter table public.items add column if not exists details jsonb not null default '{}';
alter table public.items drop constraint if exists items_stock_ok;
alter table public.items add constraint items_stock_ok check (stock is null or stock >= 0);
alter table public.items drop constraint if exists items_description_ok;
alter table public.items add constraint items_description_ok check (length(description) <= 1000);
alter table public.items drop constraint if exists items_photos_ok;
alter table public.items add constraint items_photos_ok check (public.media_urls_ok(photos, listing_id, 8));
alter table public.items drop constraint if exists items_details_ok;
alter table public.items add constraint items_details_ok check (jsonb_typeof(details) = 'object');

-- Stock at 0 is out of stock; stock coming back from 0 is back in stock. The owner's own switch wins otherwise.
create or replace function public.item_stock_rules() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.stock = 0 then new.in_stock := false;
  elsif tg_op = 'UPDATE' and old.stock = 0 and new.stock > 0 and not new.in_stock and not old.in_stock then new.in_stock := true;
  end if;
  return new;
end $$;
drop trigger if exists item_stock on public.items;
create trigger item_stock before insert or update on public.items for each row execute function public.item_stock_rules();

-- place_order from commerce.sql, plus stock: an order can't take more than is left, and placing it takes the stock.
create or replace function public.place_order(p_listing uuid, p_lines jsonb, p_lat double precision, p_lng double precision, p_drop_label text, p_payment text, p_mode text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare l listings; lines jsonb := '[]'; sub int := 0; line jsonb; it items; q int; km numeric; fee int := 0; oid uuid;
begin
  select * into l from listings where id = p_listing and kind = 'BUSINESS' and status = 'LIVE';
  if not found then raise exception 'this shop is not taking orders'; end if;
  if not l.online then raise exception 'this shop is closed right now'; end if;   -- switched off by the owner (MyListings "closed")
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into it from items where id = (line->>'item_id')::uuid and listing_id = p_listing and in_stock for update;
    if not found then raise exception 'an item is no longer available'; end if;
    q := greatest(1, (line->>'qty')::int);
    if it.stock is not null and q > it.stock then raise exception 'only % left of %', it.stock, it.name; end if;
    if it.stock is not null then update items set stock = stock - q where id = it.id; end if;
    lines := lines || jsonb_build_object('item_id', it.id, 'name', it.name, 'price', it.price, 'qty', q);
    sub := sub + it.price * q;
  end loop;
  if p_payment = 'COD' and p_mode <> 'STORE_RIDER' then raise exception 'cash on delivery is only with the store''s own riders'; end if;
  if p_mode = 'STORE_RIDER' and not exists (select 1 from listing_members m where m.listing_id = p_listing and m.role = 'STORE_RIDER') then
    raise exception 'this shop has no riders of its own; choose a Bucks rider or pick it up';
  end if;
  if p_payment = 'COD' and lower(coalesce(l.details->>'cod', '')) <> 'true' then raise exception 'this shop does not take cash on delivery'; end if;
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

-- An order that won't be delivered (rejected, timed out, cancelled) gives its stock back.
create or replace function public.order_stock_back() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare line jsonb;
begin
  if new.status in ('REJECTED', 'CANCELLED') and old.status not in ('REJECTED', 'CANCELLED') then
    for line in select * from jsonb_array_elements(new.lines) loop
      update items set stock = stock + greatest(1, (line->>'qty')::int) where id = (line->>'item_id')::uuid and stock is not null;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists order_stock on public.orders;
create trigger order_stock after update of status on public.orders for each row execute function public.order_stock_back();

-- ---------- 4. Bucks ID card ----------
alter table public.profiles add column if not exists id_issued_at timestamptz not null default now();
grant select (id_issued_at) on public.profiles to authenticated;

-- guard_profile from schema.sql, plus the card date.
create or replace function public.guard_profile() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.trust_up <> old.trust_up or new.trust_down <> old.trust_down or new.status <> old.status
     or new.auth_uid <> old.auth_uid or new.short_code <> old.short_code or new.created_at <> old.created_at
     or new.id_issued_at <> old.id_issued_at) then
    raise exception 'trust, status and ids are managed by Bucks';
  end if;
  return new;
end $$;

-- A year from issue. Renewing is open in the last 30 days and after it lapsed; the new year starts today.
create or replace function public.renew_bucks_id() returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare t timestamptz; p profiles;
begin
  select * into p from profiles where id = me();
  if not found then raise exception 'not signed in'; end if;
  if p.id_issued_at + interval '1 year' - interval '30 days' > now() then
    raise exception 'your Bucks ID is valid until %; you can renew it in its last 30 days', to_char(p.id_issued_at + interval '1 year', 'DD Mon YYYY');
  end if;
  update profiles set id_issued_at = now() where id = p.id returning id_issued_at into t;
  return t;
end $$;

-- ---------- grants ----------
revoke execute on function public.item_stock_rules(), public.order_stock_back() from authenticated, anon, public;
revoke execute on function public.renew_bucks_id() from anon, public;
grant execute on function public.renew_bucks_id() to authenticated;
