-- Bucks: commerce (cart, checkout, orders, vendor inbox). Applied after schema.sql; safe to re-run.
set search_path = public, extensions;

-- Who to call and how to pay while an order is live (PLACED .. DELIVERED).
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
    and o.status in ('PLACED', 'ACCEPTED', 'READY', 'PICKED_UP', 'DELIVERED')
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
  update orders set status = 'CANCELLED' where id = p_order;
end $$;

-- Shop owner or admin moves an accepted order along: READY (packed / cooked) and, for pick-up orders only,
-- DELIVERED once the buyer collects it. Delivery orders reach PICKED_UP and DELIVERED through the rider's task.
create or replace function public.update_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if p_status = 'READY' and o.status = 'ACCEPTED' then null;
  elsif p_status = 'DELIVERED' and o.delivery_mode = 'PICKUP' and o.status in ('ACCEPTED', 'READY') then null;
  elsif p_status = 'DELIVERED' then raise exception 'delivery orders are completed by the rider';
  else raise exception 'cannot go from % to %', lower(o.status), lower(p_status); end if;
  update orders set status = p_status where id = p_order;
end $$;

revoke execute on function public.contact_for_order(uuid), public.cancel_order(uuid), public.update_order_status(uuid, text) from public, anon;
grant execute on function public.contact_for_order(uuid), public.cancel_order(uuid), public.update_order_status(uuid, text) to authenticated;
