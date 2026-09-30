-- ============================================================================
-- Bucks: e-commerce (ship anywhere in India) and direct recommendations (bucks_29)
--  1. A store can ship: details.ships_india = true, with details.ship_fee, details.free_ship_above, details.dispatch_days.
--     Such a store shows up in search for everybody, not only nearby.
--  2. Orders can be delivery_mode SHIP: the buyer gives an address (kept in the address book), the store accepts (24 hours), ships it with a
--     carrier and tracking number (or delivers it itself), and either side marks it delivered. No Bucks rider is involved.
--  3. Local delivery (Bucks rider or the store's rider) only inside the store's delivery radius; farther away the buyer ships or picks up.
--  4. Anyone can recommend / not recommend any live listing with a comment (rate_listing); it is a review, so it shows on the Reviews tab
--     and counts in the trust numbers. One per person per listing, editable and removable. Order and trip reviews stay as they were.
-- ============================================================================

-- ---------- orders ----------
alter table public.orders drop constraint if exists orders_delivery_mode_check;
alter table public.orders add constraint orders_delivery_mode_check check (delivery_mode in ('MARKETPLACE', 'STORE_RIDER', 'PICKUP', 'SHIP'));
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in ('PLACED', 'ACCEPTED', 'REJECTED', 'READY', 'PICKED_UP', 'SHIPPED', 'DELIVERED', 'CANCELLED'));
alter table public.orders add column if not exists ship_to jsonb;
alter table public.orders add column if not exists carrier text not null default '';
alter table public.orders add column if not exists tracking_no text not null default '';
alter table public.orders add column if not exists tracking_url text not null default '';
alter table public.orders add column if not exists shipped_at timestamptz;
alter table public.orders add column if not exists delivered_at timestamptz;
alter table public.orders drop constraint if exists orders_ship_to_ok;
alter table public.orders add constraint orders_ship_to_ok check (delivery_mode <> 'SHIP' or (ship_to is not null and jsonb_typeof(ship_to) = 'object'));

-- ---------- address book ----------
create table if not exists public.addresses (
  id         uuid primary key default public.uuid_v7(),
  profile_id uuid not null references public.profiles on delete cascade,
  label      text not null default '' check (length(label) <= 30),
  name       text not null check (length(btrim(name)) between 1 and 80),
  phone      text not null check (phone ~ '^[6-9][0-9]{9}$'),
  line1      text not null check (length(btrim(line1)) between 3 and 150),
  line2      text not null default '' check (length(line2) <= 150),
  city       text not null check (length(btrim(city)) between 1 and 60),
  state      text not null check (length(btrim(state)) between 1 and 60),
  pincode    text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists addresses_owner on public.addresses (profile_id, created_at desc);
alter table public.addresses enable row level security;
drop policy if exists addresses_own on public.addresses;
create policy addresses_own on public.addresses for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me());
revoke all on public.addresses from anon;
create or replace function public.address_guard() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' and (select count(*) from public.addresses where profile_id = new.profile_id) >= 10 then raise exception 'you can save up to 10 addresses'; end if;
  if new.is_default then update public.addresses set is_default = false where profile_id = new.profile_id and id <> new.id and is_default; end if;
  return new;
end $$;
drop trigger if exists address_guard on public.addresses;
create trigger address_guard before insert or update on public.addresses for each row execute function public.address_guard();
revoke execute on function public.address_guard() from authenticated, anon, public;

-- ---------- place_order: local delivery only inside the store's radius ----------
create or replace function public.place_order(p_listing uuid, p_lines jsonb, p_lat double precision, p_lng double precision, p_drop_label text, p_payment text, p_mode text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare l listings; lines jsonb := '[]'; sub int := 0; line jsonb; it items; q int; km numeric; fee int := 0; oid uuid; radius_m numeric; msg text;
begin
  if p_mode = 'SHIP' then raise exception 'use place_order_ship for shipped orders'; end if;
  select * into l from listings where id = p_listing and kind = 'BUSINESS' and status = 'LIVE';
  if not found then raise exception 'this shop is not taking orders'; end if;
  if not l.online then raise exception 'this shop is closed right now'; end if;
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
    radius_m := greatest(coalesce(nullif(l.details->>'delivery_radius_km', '')::numeric, 5), 1) * 1000;
    if l.location is null or st_distance(l.location, geo(p_lat, p_lng)) > radius_m then
      msg := 'this shop is too far for local delivery; ship it to an address instead' || case when lower(coalesce(l.details->>'ships_india', '')) = 'true' then '' else ' or pick it up' end;
      raise exception '%', msg;
    end if;
    km := round((st_distance(l.location, geo(p_lat, p_lng)) / 1000.0 * 1.3)::numeric, 1);
    fee := (setting('delivery_base_fee') + setting('delivery_fee_per_km') * km)::int;
  end if;
  insert into orders (listing_id, buyer_id, lines, subtotal, delivery_fee, fee_paid_by, delivery_mode, payment, drop_location, drop_label, accept_by)
  values (p_listing, me(), lines, sub, fee, case when coalesce((l.details->>'free_delivery')::boolean, false) then 'VENDOR' else 'BUYER' end,
          p_mode, p_payment, geo(p_lat, p_lng), coalesce(p_drop_label, ''), now() + make_interval(mins => setting('order_accept_minutes')::int))
  returning id into oid;
  return oid;
end $$;

-- ---------- place_order_ship: an order to an address anywhere ----------
create or replace function public.place_order_ship(p_listing uuid, p_lines jsonb, p_address jsonb, p_payment text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare l listings; lines jsonb := '[]'; sub int := 0; line jsonb; it items; q int; fee int := 0; oid uuid; free_above int; a jsonb;
begin
  if me() is null then raise exception 'sign in first'; end if;
  select * into l from listings where id = p_listing and kind = 'BUSINESS' and status = 'LIVE';
  if not found then raise exception 'this shop is not taking orders'; end if;
  if not l.online then raise exception 'this shop is closed right now'; end if;
  if lower(coalesce(l.details->>'ships_india', '')) <> 'true' then raise exception 'this shop does not ship; choose pick-up or delivery nearby'; end if;
  if listing_role(p_listing) is not null then raise exception 'you cannot order from your own shop'; end if;
  if p_payment not in ('UPI', 'COD') then raise exception 'choose UPI or cash on delivery'; end if;
  if p_payment = 'COD' and lower(coalesce(l.details->>'cod', '')) <> 'true' then raise exception 'this shop does not take cash on delivery'; end if;
  -- the address, checked and trimmed: a courier needs all of it
  a := jsonb_build_object('name', btrim(coalesce(p_address->>'name', '')), 'phone', btrim(coalesce(p_address->>'phone', '')), 'line1', btrim(coalesce(p_address->>'line1', '')),
                          'line2', btrim(coalesce(p_address->>'line2', '')), 'city', btrim(coalesce(p_address->>'city', '')), 'state', btrim(coalesce(p_address->>'state', '')), 'pincode', btrim(coalesce(p_address->>'pincode', '')));
  if length(a->>'name') not between 1 and 80 then raise exception 'enter the name of the person receiving it'; end if;
  if (a->>'phone') !~ '^[6-9][0-9]{9}$' then raise exception 'enter a 10-digit mobile number the courier can call'; end if;
  if length(a->>'line1') not between 3 and 150 then raise exception 'enter the house or flat number and street'; end if;
  if length(a->>'city') not between 1 and 60 or length(a->>'state') not between 1 and 60 then raise exception 'enter the city and state'; end if;
  if (a->>'pincode') !~ '^[1-9][0-9]{5}$' then raise exception 'enter a 6-digit pincode'; end if;
  for line in select * from jsonb_array_elements(p_lines) loop
    select * into it from items where id = (line->>'item_id')::uuid and listing_id = p_listing and in_stock for update;
    if not found then raise exception 'an item is no longer available'; end if;
    q := greatest(1, (line->>'qty')::int);
    if it.stock is not null and q > it.stock then raise exception 'only % left of %', it.stock, it.name; end if;
    if it.stock is not null then update items set stock = stock - q where id = it.id; end if;
    lines := lines || jsonb_build_object('item_id', it.id, 'name', it.name, 'price', it.price, 'qty', q);
    sub := sub + it.price * q;
  end loop;
  if jsonb_array_length(lines) = 0 then raise exception 'your cart is empty'; end if;
  fee := coalesce(nullif(l.details->>'ship_fee', '')::int, 0); free_above := coalesce(nullif(l.details->>'free_ship_above', '')::int, 0);
  if free_above > 0 and sub >= free_above then fee := 0; end if;
  insert into orders (listing_id, buyer_id, lines, subtotal, delivery_fee, fee_paid_by, delivery_mode, payment, drop_label, ship_to, accept_by)
  values (p_listing, me(), lines, sub, fee, 'BUYER', 'SHIP', p_payment, (a->>'city') || ', ' || (a->>'state') || ' ' || (a->>'pincode'), a, now() + interval '24 hours')
  returning id into oid;
  return oid;
end $$;

-- ---------- vendor: accept (no rider for shipped orders) ----------
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
  if o.delivery_mode in ('PICKUP', 'SHIP') then return; end if;
  select * into l from listings where id = o.listing_id;
  if o.delivery_mode = 'STORE_RIDER' then
    select array_agg(profile_id) into riders from listing_members where listing_id = l.id and role = 'STORE_RIDER';
    if riders is null then raise exception 'you have no store riders left to deliver this; add one under Members or reject the order'; end if;
  end if;
  insert into tasks (type, requester_id, order_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare, only_riders)
  values ('DELIVERY', o.buyer_id, o.id, 'BIKE', l.location, l.title, o.drop_location, o.drop_label,
          round((st_distance(l.location, o.drop_location) / 1000.0 * 1.3)::numeric, 1), o.delivery_fee, riders);
end $$;

-- ---------- vendor: ship, then delivered ----------
create or replace function public.ship_order(p_order uuid, p_carrier text, p_tracking text default '', p_url text default '') returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders; c text := btrim(coalesce(p_carrier, '')); t text := btrim(coalesce(p_tracking, '')); u text := btrim(coalesce(p_url, ''));
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if o.delivery_mode <> 'SHIP' then raise exception 'only shipped orders take a tracking number'; end if;
  if o.status <> 'ACCEPTED' then raise exception 'accept the order first (it is %)', lower(o.status); end if;
  if length(c) not between 1 and 60 then raise exception 'enter the carrier, or "Self delivery"'; end if;
  if length(t) > 60 then raise exception 'the tracking number is too long'; end if;
  if u <> '' and (length(u) > 300 or u !~* '^https?://[^ ]+$') then raise exception 'the tracking link must start with http:// or https://'; end if;
  update orders set status = 'SHIPPED', carrier = c, tracking_no = t, tracking_url = u, shipped_at = now() where id = p_order;
end $$;

-- The store (having delivered it itself, or on the courier's word) or the buyer (having received it) closes a shipped order.
create or replace function public.mark_delivered(p_order uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or not (o.buyer_id = me() or can_manage_listing(o.listing_id)) then raise exception 'order not found'; end if;
  if o.delivery_mode <> 'SHIP' then raise exception 'this order is completed another way'; end if;
  if o.status <> 'SHIPPED' then raise exception 'it can be marked delivered once it has shipped (it is %)', lower(o.status); end if;
  update orders set status = 'DELIVERED', delivered_at = now() where id = p_order;
end $$;

-- ---------- the buyer and the shop hear about each step ----------
create or replace function public.note_order() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare shop text; verb text;
begin
  select title into shop from listings where id = new.listing_id;
  if tg_op = 'INSERT' then
    perform push_note_team(new.listing_id, 'ORDER_NEW', 'New order · ₹' || new.subtotal, pname(new.buyer_id) || ' ordered from ' || coalesce(shop, 'your shop') || case when new.delivery_mode = 'SHIP' then '. Accept it and ship it.' else '. Accept it in time.' end, 'orders-for/' || new.listing_id);
  elsif new.status is distinct from old.status then
    verb := case new.status when 'ACCEPTED' then 'was accepted' when 'REJECTED' then 'was declined' when 'READY' then 'is ready' when 'PICKED_UP' then 'is on its way'
                            when 'SHIPPED' then 'has shipped' when 'DELIVERED' then 'was delivered' when 'CANCELLED' then case when new.cancelled_by = 'BUYER' then null else 'was cancelled by the shop' end end;
    if verb is not null then perform push_note(new.buyer_id, 'ORDER_UPDATE', 'Your order from ' || coalesce(shop, 'the shop') || ' ' || verb,
        case when new.status = 'SHIPPED' then trim(new.carrier || ' ' || new.tracking_no) else 'Tap to see the details.' end, 'cloud-order/' || new.id); end if;
    if new.status = 'DELIVERED' and new.delivery_mode = 'SHIP' then perform push_note_team(new.listing_id, 'ORDER_UPDATE', 'Delivered', pname(new.buyer_id) || ' received their order.', 'orders-for/' || new.listing_id); end if;
  end if;
  return null;
end $$;

-- ---------- search: stores that ship are found from anywhere ----------
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
    and ((l.location is not null and st_dwithin(l.location, here.g, radius_m)) or (l.kind = 'BUSINESS' and lower(coalesce(l.details->>'ships_india', '')) = 'true'))
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit lim
$$;

-- ---------- direct recommendations: up / down with a comment, on any live listing ----------
alter table public.reviews drop constraint if exists reviews_comment_check;
alter table public.reviews add constraint reviews_comment_len check (length(comment) <= 500);
create unique index if not exists reviews_direct_once on public.reviews (listing_id, author_id) where task_id is null and order_id is null;

create or replace function public.rate_listing(p_listing uuid, p_vote int, p_comment text default '') returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c text := btrim(coalesce(p_comment, '')); n int; old reviews;
begin
  if me() is null then raise exception 'sign in first'; end if;
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  if length(c) > 500 then raise exception 'keep the comment under 500 characters'; end if;
  if not exists (select 1 from listings l where l.id = p_listing and l.status = 'LIVE') then raise exception 'this profile is not live'; end if;
  if listing_role(p_listing) is not null then raise exception 'you cannot rate your own profile'; end if;
  select count(*) into n from reviews where author_id = me() and created_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'too many ratings this hour, try again later'; end if;
  select * into old from reviews where listing_id = p_listing and author_id = me() and task_id is null and order_id is null for update;
  if found then
    update reviews set vote = p_vote::smallint, comment = c, created_at = now() where id = old.id;
    update listings set trust_up = trust_up - (old.vote > 0)::int + (p_vote > 0)::int, trust_down = trust_down - (old.vote < 0)::int + (p_vote < 0)::int where id = p_listing;
  else
    insert into reviews (listing_id, author_id, vote, comment) values (p_listing, me(), p_vote::smallint, c);
    update listings set trust_up = trust_up + (p_vote > 0)::int, trust_down = trust_down + (p_vote < 0)::int where id = p_listing;
  end if;
end $$;

create or replace function public.clear_listing_rating(p_listing uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare old reviews;
begin
  select * into old from reviews where listing_id = p_listing and author_id = me() and task_id is null and order_id is null for update;
  if not found then return; end if;
  delete from reviews where id = old.id;
  update listings set trust_up = greatest(0, trust_up - (old.vote > 0)::int), trust_down = greatest(0, trust_down - (old.vote < 0)::int) where id = p_listing;
end $$;

-- the team hears about a new recommendation even when it has no comment
create or replace function public.note_review() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare ttl text;
begin
  select title into ttl from listings where id = new.listing_id;
  perform push_note_team(new.listing_id, 'REVIEW', case when new.vote > 0 then 'New recommendation for ' else 'New feedback for ' end || coalesce(ttl, 'your listing'),
                         coalesce(nullif(new.comment, ''), case when new.vote > 0 then 'Someone recommended you.' else 'Someone did not recommend you.' end), 'studio/' || new.listing_id);
  return null;
end $$;

-- ---------- grants ----------
revoke execute on function public.place_order_ship(uuid, jsonb, jsonb, text), public.ship_order(uuid, text, text, text), public.mark_delivered(uuid),
  public.rate_listing(uuid, int, text), public.clear_listing_rating(uuid) from public, anon;
grant execute on function public.place_order_ship(uuid, jsonb, jsonb, text), public.ship_order(uuid, text, text, text), public.mark_delivered(uuid),
  public.rate_listing(uuid, int, text), public.clear_listing_rating(uuid) to authenticated;

-- ---------- Services: stores that ship count as supply everywhere, so Shopping opens for people with no shop nearby ----------
create or replace function public.services_near(lat double precision, lng double precision)
returns table (key text, label text, mode text, state text, supply integer, min_supply integer, online integer, min_online integer, supply_noun text, radius_m integer, delivery boolean, delivery_now boolean, interested integer, mine boolean)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g),
  counted as (
    select r.*,
      (case r.supply
        when 'LISTINGS' then (select count(*) from listings l, here where l.status = 'LIVE' and l.service = r.key and ((l.location is not null and st_dwithin(l.location, here.g, r.radius_m)) or lower(coalesce(l.details->>'ships_india', '')) = 'true'))
        when 'VEHICLES' then (select count(distinct p.vehicle_id) from driver_presence p join vehicles v on v.id = p.vehicle_id and v.status = 'ACTIVE', here
                               where p.kind = r.vehicle_kind and p.location is not null and p.updated_at > now() - interval '14 days' and st_dwithin(p.location, here.g, r.radius_m))
        else (select count(*) from jobs j join listings l on l.id = j.listing_id, here where j.open and l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, here.g, r.radius_m))
      end)::int as supply_n,
      (case r.supply
        when 'LISTINGS' then (select count(*) from listings l, here where l.status = 'LIVE' and l.online and l.service = r.key and ((l.location is not null and st_dwithin(l.location, here.g, r.radius_m)) or lower(coalesce(l.details->>'ships_india', '')) = 'true'))
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

-- The buyer and the shop keep each other's phone (and the buyer the shop's UPI) while an order is shipped, too.
create or replace function public.contact_for_order(p_order uuid)
returns table (phone text, upi_uri text, name text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone,
         case when o.buyer_id = public.me() then pp.upi_uri else null end,
         p.name
  from orders o
  join listings l on l.id = o.listing_id
  join profiles p on p.id = case when o.buyer_id = public.me() then l.owner_id else o.buyer_id end
  left join profile_private pp on pp.profile_id = p.id
  where o.id = p_order
    and (o.status in ('PLACED', 'ACCEPTED', 'READY', 'PICKED_UP', 'SHIPPED', 'DELIVERED') or (o.status = 'CANCELLED' and o.cancelled_by = 'SHOP'))
    and (o.buyer_id = public.me() or public.can_manage_listing(o.listing_id))
$$;
