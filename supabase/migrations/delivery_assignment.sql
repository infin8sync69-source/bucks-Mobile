-- Delivery assignment, the shop's view of its deliveries, vehicle review, and search without blocked owners.
--
-- 1. A shop that accepts an order chooses who delivers it: auto (as before: its store riders for a cash order, every Bucks bike nearby
--    otherwise) or one of its own store riders, who gets the request alone for delivery_exclusive_seconds (60) before it widens to the
--    auto set. respond_order gains p_rider; reassign_delivery rings again or sends another rider while nobody has taken it.
-- 2. The shop sees where its delivery stands (order_delivery: ringing, who's on the way, picked up, nobody took it) and the pickup PIN to
--    hand over with the parcel, and lists its riders with who's online now (store_riders).
-- 3. Bucks staff approve or reject vehicles (vehicles_to_review, review_vehicle): nothing could make a vehicle ACTIVE before, so no
--    driver could go online.
-- 4. search_listings leaves out pages whose owner and I have blocked each other (latest before this: hardening_platform.sql).
-- push.sql's tasks trigger now also fires when only_riders changes, so the notify function can ring the riders a request widens to.
-- Safe to run more than once. Apply after hardening_platform.sql, review_fixes.sql and pro_profile.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

insert into public.settings (key, value) values ('delivery_exclusive_seconds', 60) on conflict (key) do nothing;

alter table public.tasks add column if not exists preferred_rider uuid references public.profiles on delete set null;
alter table public.tasks add column if not exists exclusive_until timestamptz;
-- tasks has column grants (everything but pin, dispatch.sql): the new columns are granted on their own.
grant select (preferred_rider, exclusive_until) on public.tasks to authenticated;

-- ---------- 1. who delivers ----------
-- The riders a shop's delivery goes to when nobody in particular is chosen: its store riders for a STORE_RIDER (cash) order, every
-- Bucks bike nearby (null) otherwise.
create or replace function public.delivery_pool(o public.orders) returns uuid[] language sql stable security definer set search_path = public, extensions as $$
  select case when o.delivery_mode = 'STORE_RIDER'
    then (select array_agg(m.profile_id) from public.listing_members m where m.listing_id = o.listing_id and m.role = 'STORE_RIDER') end
$$;

-- A store rider of the order's shop, or an error the owner can act on.
create or replace function public.check_store_rider(o public.orders, p_rider uuid) returns void language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.listing_members m where m.listing_id = o.listing_id and m.profile_id = p_rider and m.role = 'STORE_RIDER') then
    raise exception 'choose one of your store riders, or let Bucks pick a rider';
  end if;
end $$;

-- respond_order from cancellation.sql, plus p_rider: one of the shop's store riders to ring first and alone.
drop function if exists public.respond_order(uuid, boolean, text);
create or replace function public.respond_order(p_order uuid, p_accept boolean, p_reason text default null, p_rider uuid default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare o orders; l listings; riders uuid[];
begin
  select * into o from orders where id = p_order for update;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if o.status <> 'PLACED' then raise exception 'this order is already %', lower(o.status); end if;
  if o.accept_by < now() then raise exception 'too late: the order timed out'; end if;
  if not p_accept then
    if p_reason is not null and not cancel_reason_ok('SHOP_REJECT', p_reason) then raise exception 'unknown reason'; end if;
    update orders set status = 'REJECTED', cancel_reason = p_reason where id = p_order; return;
  end if;
  if p_rider is not null and o.delivery_mode in ('PICKUP', 'SHIP') then raise exception 'this order isn''t delivered by a rider'; end if;
  if p_rider is not null then perform check_store_rider(o, p_rider); end if;
  riders := delivery_pool(o);
  if o.delivery_mode = 'STORE_RIDER' and riders is null then raise exception 'you have no store riders left to deliver this; add one under Team or reject the order'; end if;
  update orders set status = 'ACCEPTED' where id = p_order;
  if o.delivery_mode in ('PICKUP', 'SHIP') then return; end if;
  select * into l from listings where id = o.listing_id;
  insert into tasks (type, requester_id, order_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare, only_riders, preferred_rider, exclusive_until)
  values ('DELIVERY', o.buyer_id, o.id, 'BIKE', l.location, l.title, o.drop_location, o.drop_label,
          round((st_distance(l.location, o.drop_location) / 1000.0 * 1.3)::numeric, 1), o.delivery_fee,
          case when p_rider is not null then array[p_rider] else riders end, p_rider,
          case when p_rider is not null then now() + make_interval(secs => dispatch_cfg('delivery_exclusive_seconds', 60)::double precision) end);
end $$;

-- While nobody has taken the delivery (still ringing, or nobody took it in time): ring again, or send one of the shop's riders.
create or replace function public.reassign_delivery(p_order uuid, p_rider uuid default null) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare o orders; t tasks; riders uuid[];
begin
  select * into o from orders where id = p_order;
  if not found or not can_manage_listing(o.listing_id) then raise exception 'order not found'; end if;
  if o.status not in ('ACCEPTED', 'READY') or o.delivery_mode in ('PICKUP', 'SHIP') then raise exception 'this order isn''t waiting for a rider'; end if;
  select * into t from tasks where order_id = o.id and type = 'DELIVERY' order by created_at desc limit 1 for update;
  if not found then raise exception 'this order has no delivery to reassign'; end if;
  if t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS') then raise exception 'a rider already has it'; end if;
  if t.status not in ('SEARCHING', 'NO_DRIVER') then raise exception 'this delivery is %', lower(t.status); end if;
  if p_rider is not null then perform check_store_rider(o, p_rider); end if;
  riders := delivery_pool(o);
  if p_rider is null and o.delivery_mode = 'STORE_RIDER' and riders is null then raise exception 'you have no store riders; add one under Team'; end if;
  update tasks set status = 'SEARCHING', status_at = now(), driver_id = null, vehicle_id = null, driver_location = null,
         only_riders = case when p_rider is not null then array[p_rider] else riders end, preferred_rider = p_rider,
         exclusive_until = case when p_rider is not null then now() + make_interval(secs => dispatch_cfg('delivery_exclusive_seconds', 60)::double precision) end
   where id = t.id;
  return 'SEARCHING';
end $$;

-- expire_tasks from hardening_dispatch.sql, plus first: a request a chosen rider didn't take in their window widens to the shop's
-- usual riders (status_at restarts, so they get the full ring window).
create or replace function public.expire_tasks() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int := 0; k int;
begin
  update tasks x set only_riders = public.delivery_pool(o), exclusive_until = null, status_at = now()
    from orders o
   where o.id = x.order_id and x.status = 'SEARCHING' and x.exclusive_until is not null and x.exclusive_until < now();
  get diagnostics k = row_count; n := n + k;
  update tasks set status = 'NO_DRIVER' where status = 'SEARCHING'
    and status_at < now() - make_interval(secs => public.dispatch_cfg('ring_window_seconds', 180)::double precision);
  get diagnostics k = row_count; n := n + k;
  with stale as (
    select t.id, t.driver_id, t.vehicle_id from tasks t
    where t.status in ('MATCHED', 'ARRIVED')
      and not exists (select 1 from driver_presence p where p.profile_id = t.driver_id and p.updated_at > now() - interval '10 minutes')
    for update of t skip locked
  ), ev as (
    insert into task_events (task_id, driver_id, vehicle_id, event) select id, driver_id, vehicle_id, 'CANCELLED' from stale where driver_id is not null returning 1
  )
  update tasks x set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null, pin = public.new_pin(), pin_attempts = 0
    from stale s where x.id = s.id;
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;

-- Ring the riders a request widens to (or a reassigned rider): the notify function rings on this, not only on a status change.
drop trigger if exists push_tasks on public.tasks;
create trigger push_tasks after insert or update of status, only_riders on public.tasks for each row execute function public.push_notify();

-- ---------- 2. the shop's view ----------
-- The latest delivery of an order, for its shop's owners and admins: where it stands, who has it, and the pickup PIN to hand over.
-- The rider's phone only when they're one of the shop's own riders.
create or replace function public.order_delivery(p_order uuid)
returns table (task_id uuid, status text, rider_id uuid, rider_name text, rider_phone text, vehicle_plate text, preferred_rider uuid, exclusive_until timestamptz,
               status_at timestamptz, pin text, only_store_riders boolean)
language sql stable security definer set search_path = public, extensions as $$
  select t.id, t.status, t.driver_id, coalesce(nullif(p.name, ''), case when t.driver_id is not null then 'Your rider' end),
         case when exists (select 1 from listing_members m where m.listing_id = o.listing_id and m.profile_id = t.driver_id and m.role = 'STORE_RIDER')
              then (select pp.phone from profile_private pp where pp.profile_id = t.driver_id) end,
         v.plate, t.preferred_rider, t.exclusive_until, t.status_at, t.pin, t.only_riders is not null
  from orders o join tasks t on t.order_id = o.id and t.type = 'DELIVERY'
  left join profiles p on p.id = t.driver_id left join vehicles v on v.id = t.vehicle_id
  where o.id = p_order and can_manage_listing(o.listing_id)
  order by t.created_at desc limit 1
$$;

-- A shop's store riders, online ones first: online means a fresh position with an ACTIVE bike right now.
create or replace function public.store_riders(p_listing uuid)
returns table (profile_id uuid, name text, photo_url text, online boolean, has_bike boolean)
language sql stable security definer set search_path = public, extensions as $$
  select m.profile_id, coalesce(nullif(p.name, ''), 'Rider'), p.photo_url,
         exists (select 1 from driver_presence d join vehicles v on v.id = d.vehicle_id and v.status = 'ACTIVE' and v.kind = 'BIKE'
                 where d.profile_id = m.profile_id and d.online and d.updated_at > now() - interval '5 minutes') as online,
         exists (select 1 from vehicles v left join vehicle_members vm on vm.vehicle_id = v.id
                 where v.kind = 'BIKE' and v.status = 'ACTIVE' and (v.owner_id = m.profile_id or vm.profile_id = m.profile_id)) as has_bike
  from listing_members m join profiles p on p.id = m.profile_id
  where m.listing_id = p_listing and m.role = 'STORE_RIDER' and p.status = 'ACTIVE' and can_manage_listing(p_listing)
  order by 4 desc, 5 desc, 2
$$;

-- ---------- 3. vehicle review ----------
create or replace function public.vehicles_to_review(lim int default 50)
returns table (id uuid, owner_id uuid, owner_name text, kind text, model text, plate text, docs jsonb, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select v.id, v.owner_id, coalesce(nullif(p.name, ''), 'Owner'), v.kind, v.model, v.plate, v.docs, v.created_at
  from vehicles v join profiles p on p.id = v.owner_id
  where is_staff() and v.status = 'PENDING' and p.status = 'ACTIVE'
  order by v.created_at
  limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- Staff approve (ACTIVE: the vehicle can go online) or reject (SUSPENDED, with a note the owner reads). The owner is told either way.
-- Changing the plate, type or documents later sends it back to PENDING (guard_vehicle), so it comes back here.
create or replace function public.review_vehicle(p_vehicle uuid, p_approve boolean, p_note text default '') returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v vehicles; note text := left(btrim(coalesce(p_note, '')), 300);
begin
  if not is_staff() then raise exception 'staff only'; end if;
  if p_approve is null then raise exception 'approve or reject'; end if;
  select * into v from vehicles where id = p_vehicle for update;
  if not found then raise exception 'vehicle not found'; end if;
  if not p_approve and note = '' then raise exception 'say what the owner needs to fix'; end if;
  update vehicles set status = case when p_approve then 'ACTIVE' else 'SUSPENDED' end where id = p_vehicle;
  perform push_note(v.owner_id, 'VEHICLE_REVIEW',
    case when p_approve then 'Your ' || v.plate || ' is approved' else 'Your ' || v.plate || ' needs attention' end,
    case when p_approve then case when v.kind = 'BIKE' then 'Go online to take deliveries.' else 'Go online to take rides.' end else note end,
    'my/vehicles');
end $$;

-- ---------- 4. search without blocked owners ----------
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null,
                                                  lim int default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int,
               details jsonb, distance_m double precision, matched_item text, min_price int, type_key text, group_key text, owner_id uuid, owner_name text)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         (select i.name from items i where i.listing_id = l.id and term.t is not null and i.name ilike '%' || term.t || '%' order by i.price limit 1) as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock and i.price > 0) as min_price,
         l.type_key, t.group_key, l.owner_id, coalesce(nullif(o.name, ''), 'Bucks member')
  from listings l left join listing_types t on t.key = l.type_key join profiles o on o.id = l.owner_id, here, term
  where l.status = 'LIVE'
    and not public.blocked_between(public.me(), l.owner_id)
    and (kinds is null or l.kind = any(kinds))
    and (services is null or l.service = any(services))
    and ((l.location is not null and st_dwithin(l.location, here.g, least(greatest(coalesce(radius_m, 10000), 0), 50000)))
         or (l.kind = 'BUSINESS' and lower(coalesce(l.details->>'ships_india', '')) = 'true'))
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or coalesce(t.label, '') ilike '%' || term.t || '%' or o.name ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit greatest(1, least(coalesce(lim, 40), 100))
$$;

-- ---------- grants ----------
revoke execute on function public.respond_order(uuid, boolean, text, uuid), public.reassign_delivery(uuid, uuid), public.order_delivery(uuid),
  public.store_riders(uuid), public.vehicles_to_review(int), public.review_vehicle(uuid, boolean, text),
  public.search_listings(text, double precision, double precision, int, text[], int, text[]) from public, anon;
grant execute on function public.respond_order(uuid, boolean, text, uuid), public.reassign_delivery(uuid, uuid), public.order_delivery(uuid),
  public.store_riders(uuid), public.vehicles_to_review(int), public.review_vehicle(uuid, boolean, text),
  public.search_listings(text, double precision, double precision, int, text[], int, text[]) to authenticated;
revoke execute on function public.delivery_pool(public.orders), public.check_store_rider(public.orders, uuid), public.expire_tasks() from public, anon, authenticated;
