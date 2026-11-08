-- Cancelling a ride or an order now says why (bucks_30).
-- Rider: cancel_task. Driver hands a ride back: release_task. Buyer / shop: cancel_order, update_order_status, respond_order take an optional reason.
-- Reasons are optional on the server so older app builds keep working; the new app asks for them. The shop is told when a buyer cancels.

alter table public.tasks add column if not exists cancel_reason text;
alter table public.tasks add column if not exists cancel_note text;
alter table public.tasks add column if not exists cancelled_by text;
alter table public.tasks add column if not exists cancel_after text;
alter table public.tasks drop constraint if exists tasks_cancelled_by_check;
alter table public.tasks add constraint tasks_cancelled_by_check check (cancelled_by is null or cancelled_by in ('RIDER', 'DRIVER', 'SYSTEM'));
alter table public.task_events add column if not exists reason text;
alter table public.orders add column if not exists cancel_reason text;

-- ---------- reasons ----------
create or replace function public.cancel_reason_ok(p_who text, p_code text) returns boolean language sql immutable as $$
  select case p_who
    when 'RIDER' then p_code in ('TOO_LONG', 'DRIVER_FAR', 'DRIVER_ASKED', 'PLANS_CHANGED', 'BOOKED_BY_MISTAKE', 'WRONG_ADDRESS', 'OTHER')
    when 'DRIVER' then p_code in ('RIDER_NO_SHOW', 'RIDER_UNREACHABLE', 'RIDER_ASKED', 'TOO_FAR', 'VEHICLE_ISSUE', 'UNSAFE', 'OTHER')
    when 'BUYER' then p_code in ('CHANGED_MIND', 'ORDERED_BY_MISTAKE', 'WRONG_ADDRESS', 'TOO_SLOW', 'FOUND_BETTER', 'OTHER')
    when 'SHOP' then p_code in ('OUT_OF_STOCK', 'CANT_DELIVER', 'CUSTOMER_UNREACHABLE', 'CUSTOMER_ASKED', 'CLOSED', 'OTHER')
    when 'SHOP_REJECT' then p_code in ('OUT_OF_STOCK', 'CLOSED', 'TOO_FAR', 'CANT_DELIVER', 'OTHER')
    else false end
$$;

create or replace function public.cancel_reason_label(p_code text) returns text language sql immutable as $$
  select case p_code
    when 'TOO_LONG' then 'Taking too long' when 'DRIVER_FAR' then 'Driver is too far' when 'DRIVER_ASKED' then 'Driver asked to cancel'
    when 'PLANS_CHANGED' then 'Plans changed' when 'BOOKED_BY_MISTAKE' then 'Booked by mistake' when 'WRONG_ADDRESS' then 'Wrong address'
    when 'RIDER_NO_SHOW' then 'Customer not at pickup' when 'RIDER_UNREACHABLE' then 'Customer not reachable' when 'RIDER_ASKED' then 'Customer asked to cancel'
    when 'TOO_FAR' then 'Too far' when 'VEHICLE_ISSUE' then 'Vehicle problem' when 'UNSAFE' then 'Felt unsafe'
    when 'CHANGED_MIND' then 'Changed their mind' when 'ORDERED_BY_MISTAKE' then 'Ordered by mistake' when 'TOO_SLOW' then 'Taking too long' when 'FOUND_BETTER' then 'Found it elsewhere'
    when 'OUT_OF_STOCK' then 'Out of stock' when 'CANT_DELIVER' then 'Can''t deliver there' when 'CUSTOMER_UNREACHABLE' then 'Customer not reachable'
    when 'CUSTOMER_ASKED' then 'Customer asked to cancel' when 'CLOSED' then 'Shop is closed'
    when 'OTHER' then 'Other reason' else null end
$$;

-- ---------- rider cancels a ride ----------
create or replace function public.cancel_task(p_task uuid, p_reason text default null, p_note text default '') returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  select * into t from tasks where id = p_task for update;
  if not found or t.requester_id is distinct from me() then raise exception 'ride not found'; end if;
  if t.order_id is not null then raise exception 'this delivery belongs to an order; cancel the order instead'; end if;
  if t.status not in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER') then raise exception 'this ride can no longer be cancelled (it is %)', lower(replace(t.status, '_', ' ')); end if;
  if p_reason is not null and not cancel_reason_ok('RIDER', p_reason) then raise exception 'unknown reason'; end if;
  if t.status in ('MATCHED', 'ARRIVED') and p_reason is null then raise exception 'choose why you are cancelling'; end if;
  if char_length(coalesce(p_note, '')) > 200 then raise exception 'keep the note under 200 characters'; end if;
  update tasks set status = 'CANCELLED', cancel_reason = p_reason, cancel_note = nullif(trim(coalesce(p_note, '')), ''), cancelled_by = 'RIDER', cancel_after = t.status
   where id = p_task returning * into t;
  return t;
end $$;

-- ---------- driver hands a ride back ----------
create or replace function public.release_task(p_task uuid, p_reason text, p_note text default '') returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  select * into t from tasks where id = p_task for update;
  if not found or t.driver_id is distinct from me() then raise exception 'ride not found'; end if;
  if t.status not in ('MATCHED', 'ARRIVED') then raise exception 'it can only be handed back before the trip starts (it is %)', lower(replace(t.status, '_', ' ')); end if;
  if p_reason is null or not cancel_reason_ok('DRIVER', p_reason) then raise exception 'choose why you are handing it back'; end if;
  insert into task_events (task_id, driver_id, vehicle_id, event, reason) values (t.id, me(), t.vehicle_id, 'CANCELLED', p_reason);
  update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where id = p_task returning * into t;
  t.pin := '';
  return t;
end $$;

-- ---------- how often I cancel after someone accepted (shown as a gentle nudge) ----------
create or replace function public.my_cancel_stats() returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'rider_day', (select count(*) from tasks where requester_id = me() and cancelled_by = 'RIDER' and cancel_after in ('MATCHED', 'ARRIVED') and status_at > now() - interval '1 day'),
    'rider_week', (select count(*) from tasks where requester_id = me() and cancelled_by = 'RIDER' and cancel_after in ('MATCHED', 'ARRIVED') and status_at > now() - interval '7 days'),
    'driver_day', (select count(*) from task_events where driver_id = me() and event = 'CANCELLED' and at > now() - interval '1 day'),
    'driver_week', (select count(*) from task_events where driver_id = me() and event = 'CANCELLED' and at > now() - interval '7 days'))
$$;

-- ---------- orders ----------
alter function public.cancel_order(uuid) rename to cancel_order_old;   -- kept (not dropped) as a rollback; revoked below
create or replace function public.cancel_order(p_order uuid, p_reason text default null) returns void language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or o.buyer_id is distinct from me() then raise exception 'order not found'; end if;
  if o.status <> 'PLACED' then raise exception 'this order is already %; it can only be cancelled before the shop accepts', lower(o.status); end if;
  if p_reason is not null and not cancel_reason_ok('BUYER', p_reason) then raise exception 'unknown reason'; end if;
  update orders set status = 'CANCELLED', cancelled_by = 'BUYER', cancel_reason = p_reason where id = p_order;
end $$;

alter function public.update_order_status(uuid, text) rename to update_order_status_old;
create or replace function public.update_order_status(p_order uuid, p_status text, p_reason text default null) returns void language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if p_status = 'READY' and o.status = 'ACCEPTED' then null;
  elsif p_status = 'DELIVERED' and o.delivery_mode = 'PICKUP' and o.status in ('ACCEPTED', 'READY') then null;
  elsif p_status = 'DELIVERED' then raise exception 'delivery orders are completed by the rider';
  elsif p_status = 'CANCELLED' and o.status in ('ACCEPTED', 'READY') then
    if p_reason is not null and not cancel_reason_ok('SHOP', p_reason) then raise exception 'unknown reason'; end if;
    if exists (select 1 from tasks t where t.order_id = o.id and t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'PAID')) then
      raise exception 'a rider already has this order, so it can''t be cancelled now';
    end if;
    update tasks set status = 'CANCELLED', cancelled_by = 'SYSTEM', cancel_reason = 'ORDER_CANCELLED' where order_id = o.id and status in ('SEARCHING', 'NO_DRIVER');
  else raise exception 'cannot go from % to %', lower(o.status), lower(p_status); end if;
  update orders set status = p_status, cancelled_by = case when p_status = 'CANCELLED' then 'SHOP' else cancelled_by end,
                    cancel_reason = case when p_status = 'CANCELLED' then p_reason else cancel_reason end where id = p_order;
end $$;

alter function public.respond_order(uuid, boolean) rename to respond_order_old;
create or replace function public.respond_order(p_order uuid, p_accept boolean, p_reason text default null) returns void language plpgsql security definer set search_path = public, extensions as $$
declare o orders; l listings; riders uuid[];
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if o.status <> 'PLACED' then raise exception 'this order is already %', lower(o.status); end if;
  if o.accept_by < now() then update orders set status = 'REJECTED' where id = p_order; raise exception 'too late: the order timed out'; end if;
  if not p_accept then
    if p_reason is not null and not cancel_reason_ok('SHOP_REJECT', p_reason) then raise exception 'unknown reason'; end if;
    update orders set status = 'REJECTED', cancel_reason = p_reason where id = p_order; return;
  end if;
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

-- Notifications: the buyer hears the reason; the shop hears when a buyer cancels (it used to hear nothing).
create or replace function public.note_order() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare shop text; verb text; why text;
begin
  select title into shop from listings where id = new.listing_id;
  if tg_op = 'INSERT' then
    perform push_note_team(new.listing_id, 'ORDER_NEW', 'New order · ₹' || new.subtotal, pname(new.buyer_id) || ' ordered from ' || coalesce(shop, 'your shop') || case when new.delivery_mode = 'SHIP' then '. Accept it and ship it.' else '. Accept it in time.' end, 'orders-for/' || new.listing_id);
  elsif new.status is distinct from old.status then
    why := cancel_reason_label(new.cancel_reason);
    verb := case new.status when 'ACCEPTED' then 'was accepted' when 'REJECTED' then 'was declined' when 'READY' then 'is ready' when 'PICKED_UP' then 'is on its way'
                            when 'SHIPPED' then 'has shipped' when 'DELIVERED' then 'was delivered' when 'CANCELLED' then case when new.cancelled_by = 'BUYER' then null else 'was cancelled by the shop' end end;
    if verb is not null then perform push_note(new.buyer_id, 'ORDER_UPDATE', 'Your order from ' || coalesce(shop, 'the shop') || ' ' || verb,
        case when new.status = 'SHIPPED' then trim(new.carrier || ' ' || new.tracking_no)
             when new.status in ('REJECTED', 'CANCELLED') and why is not null then 'Reason: ' || why || '. Tap to see the details.'
             else 'Tap to see the details.' end, 'cloud-order/' || new.id); end if;
    if new.status = 'CANCELLED' and new.cancelled_by = 'BUYER' then
      perform push_note_team(new.listing_id, 'ORDER_UPDATE', 'Order cancelled', pname(new.buyer_id) || ' cancelled before you accepted' || case when why is not null then ' (' || lower(why) || ')' else '' end || '.', 'orders-for/' || new.listing_id);
    end if;
    if new.status = 'DELIVERED' and new.delivery_mode = 'SHIP' then perform push_note_team(new.listing_id, 'ORDER_UPDATE', 'Delivered', pname(new.buyer_id) || ' received their order.', 'orders-for/' || new.listing_id); end if;
  end if;
  return null;
end $$;

-- ---------- grants ----------
revoke execute on function public.cancel_task(uuid, text, text), public.release_task(uuid, text, text), public.my_cancel_stats(),
  public.cancel_order(uuid, text), public.update_order_status(uuid, text, text), public.respond_order(uuid, boolean, text),
  public.cancel_order_old(uuid), public.update_order_status_old(uuid, text), public.respond_order_old(uuid, boolean) from anon, public, authenticated;
grant execute on function public.cancel_task(uuid, text, text), public.release_task(uuid, text, text), public.my_cancel_stats(),
  public.cancel_order(uuid, text), public.update_order_status(uuid, text, text), public.respond_order(uuid, boolean, text) to authenticated;
