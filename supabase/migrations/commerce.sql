-- Bucks: commerce (cart, checkout, orders, vendor inbox). Applied after schema.sql; safe to re-run.
set search_path = public, extensions;

-- Who cancelled an order, so the buyer and the shop each get the right words (and the buyer who already paid knows to ask for a refund).
alter table public.orders add column if not exists cancelled_by text check (cancelled_by in ('BUYER', 'SHOP'));

-- place_order from schema.sql, plus two server-side checks the app only did on screen: "store's own rider" needs the shop to
-- have at least one STORE_RIDER member (otherwise the task would go to any bike), and cash on delivery needs details.cod = true.
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

-- respond_order from schema.sql, except that a store-rider order is never turned into a marketplace task: when the shop has no
-- STORE_RIDER left (removed after the order was placed), accepting fails and the shop can reject instead.
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
  if o.delivery_mode = 'STORE_RIDER' then
    select array_agg(profile_id) into riders from listing_members where listing_id = l.id and role = 'STORE_RIDER';
    if riders is null then raise exception 'you have no store riders left to deliver this; add one under Members or reject the order'; end if;
  end if;
  insert into tasks (type, requester_id, order_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare, only_riders)
  values ('DELIVERY', o.buyer_id, o.id, 'BIKE', l.location, l.title, o.drop_location, o.drop_label,
          round((st_distance(l.location, o.drop_location) / 1000.0 * 1.3)::numeric, 1), o.delivery_fee, riders);
end $$;

-- Who to call and how to pay while an order is live (PLACED .. DELIVERED), and after the shop cancelled an accepted order
-- (so a buyer who already paid can call about the refund).
-- Buyer: the shop owner's phone, UPI link and name. Shop owner or admin: the buyer's phone and name (no payment link).
create or replace function public.contact_for_order(p_order uuid) returns table (phone text, upi_uri text, name text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone,
         case when o.buyer_id = public.me() then pp.upi_uri else null end,
         p.name
  from orders o
  join listings l on l.id = o.listing_id
  join profiles p on p.id = case when o.buyer_id = public.me() then l.owner_id else o.buyer_id end
  left join profile_private pp on pp.profile_id = p.id
  where o.id = p_order
    and (o.status in ('PLACED', 'ACCEPTED', 'READY', 'PICKED_UP', 'DELIVERED') or (o.status = 'CANCELLED' and o.cancelled_by = 'SHOP'))
    and (o.buyer_id = public.me() or public.can_manage_listing(o.listing_id))
$$;

-- Buyer changes their mind before the shop answers. After that the shop (or its rider) is already working on it.
create or replace function public.cancel_order(p_order uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or o.buyer_id is distinct from me() then raise exception 'order not found'; end if;
  if o.status <> 'PLACED' then raise exception 'this order is already %; it can only be cancelled before the shop accepts', lower(o.status); end if;
  update orders set status = 'CANCELLED', cancelled_by = 'BUYER' where id = p_order;
end $$;

-- Shop owner or admin moves an accepted order along: READY (packed / cooked) and, for pick-up orders only,
-- DELIVERED once the buyer collects it. Delivery orders reach PICKED_UP and DELIVERED through the rider's task.
-- CANCELLED closes an accepted order nobody will complete (no rider took the delivery, the buyer cancelled the
-- delivery task, or never came to collect); not once a rider has it. An open delivery task is cancelled with it.
create or replace function public.update_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if p_status = 'READY' and o.status = 'ACCEPTED' then null;
  elsif p_status = 'DELIVERED' and o.delivery_mode = 'PICKUP' and o.status in ('ACCEPTED', 'READY') then null;
  elsif p_status = 'DELIVERED' then raise exception 'delivery orders are completed by the rider';
  elsif p_status = 'CANCELLED' and o.status in ('ACCEPTED', 'READY') then
    if exists (select 1 from tasks t where t.order_id = o.id and t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'PAID')) then
      raise exception 'a rider already has this order, so it can''t be cancelled now';
    end if;
    update tasks set status = 'CANCELLED' where order_id = o.id and status in ('SEARCHING', 'NO_DRIVER');
  else raise exception 'cannot go from % to %', lower(o.status), lower(p_status); end if;
  update orders set status = p_status, cancelled_by = case when p_status = 'CANCELLED' then 'SHOP' else cancelled_by end where id = p_order;
end $$;

revoke execute on function public.contact_for_order(uuid), public.cancel_order(uuid), public.update_order_status(uuid, text),
  public.place_order(uuid, jsonb, double precision, double precision, text, text, text), public.respond_order(uuid, boolean) from public, anon;
grant execute on function public.contact_for_order(uuid), public.cancel_order(uuid), public.update_order_status(uuid, text),
  public.place_order(uuid, jsonb, double precision, double precision, text, text, text), public.respond_order(uuid, boolean) to authenticated;
