-- Dispatch: rides and deliveries on Supabase (see docs/FEATURE_CONTRACT.md, feature "dispatch").
-- Adds what the app needs on top of schema.sql: task rows with plain coordinates, online drivers for the map,
-- the counterpart's vehicle for a task, and "my open task" so a killed app returns to its trip. It also tightens
-- schema.sql's dispatch rules: the customer's PIN is readable by the customer only, a hand-back rings again for the
-- full window, presence is stamped and typed by the server, one review per trip or order and never of your own
-- listing, and account deletion on the server.
-- Safe to re-run. Apply after schema.sql (and manage.sql); re-applying schema.sql re-grants the whole tasks table and
-- restores its versions of the functions below, so this migration always runs after it.
set search_path = public, extensions;

-- ---------- tasks with lat/lng (PostgREST returns geography as EWKB hex, which the app cannot read) ----------
-- Delivery tasks also carry how many items the order has; the rider may not read orders, so a definer helper counts them.
create or replace function public.order_item_count(o uuid) returns int
language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select sum(greatest(1, coalesce((l->>'qty')::int, 1)))::int from public.orders x, jsonb_array_elements(x.lines) l where x.id = o), 0)
$$;

-- What the rider takes from the buyer at the door for a delivery. MARKETPLACE: the fee when the buyer pays it, else 0 (the
-- shop pays the rider at pick-up). STORE_RIDER: the whole COD bill (goods, plus the fee when the buyer pays it), 0 for UPI.
-- The task's fare stays the rider's delivery fee (their earnings); this is only the amount to collect. Readable by the buyer,
-- the shop's managers and the rider holding the task; null for anyone else (a ringing rider sees it once they claim).
create or replace function public.order_collect(o uuid) returns int
language sql stable security definer set search_path = public, extensions as $$
  select case
    when x.delivery_mode = 'MARKETPLACE' then case when x.fee_paid_by = 'BUYER' then x.delivery_fee else 0 end
    when x.delivery_mode = 'STORE_RIDER' and x.payment = 'COD' then x.subtotal + case when x.fee_paid_by = 'BUYER' then x.delivery_fee else 0 end
    else 0 end
  from public.orders x where x.id = o
    and (x.buyer_id = public.me() or public.can_manage_listing(x.listing_id)
         or exists (select 1 from public.tasks t where t.order_id = x.id and t.driver_id = public.me()))
$$;

-- ---------- when a task's status last changed ----------
-- Ringing (open_tasks_near), "my open task" and the buyer's "no rider yet" are timed from here, not from created_at:
-- a task a driver handed back starts searching again now, and a finished trip is counted from when it finished.
alter table public.tasks add column if not exists status_at timestamptz;
update public.tasks set status_at = created_at where status_at is null;
alter table public.tasks alter column status_at set default now();
alter table public.tasks alter column status_at set not null;
create or replace function public.task_status_at() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then new.status_at := now(); end if;
  return new;
end $$;
drop trigger if exists task_status_at on public.tasks;
create trigger task_status_at before insert or update of status on public.tasks for each row execute function public.task_status_at();

-- ---------- the customer's PIN is for the customer only ----------
-- The PIN proves the driver met the customer (IN_PROGRESS needs it; for a delivery it marks the order picked up), so the
-- driver must never read it. The API may read every column of tasks except pin (so select=* on the table is refused,
-- and realtime leaves pin out); the requester gets it through tasks_geo, which asks this helper.
create or replace function public.task_pin(p_task uuid) returns text
language sql stable security definer set search_path = public, extensions as $$
  select t.pin from public.tasks t where t.id = p_task and t.requester_id = public.me()
$$;

drop view if exists public.tasks_geo cascade;
create view public.tasks_geo with (security_invoker = true) as
  select t.id, t.type, t.requester_id, t.order_id, t.vehicle_kind, t.pickup, t.pickup_label, t.drop_at, t.drop_label, t.km, t.fare,
         case when t.requester_id = public.me() then coalesce(public.task_pin(t.id), '') else '' end as pin,
         t.only_riders, t.status, t.driver_id, t.vehicle_id, t.driver_location, t.paid_with, t.created_at, t.status_at,
         st_y(t.pickup::geometry)          as pickup_lat, st_x(t.pickup::geometry)          as pickup_lng,
         st_y(t.drop_at::geometry)         as drop_lat,   st_x(t.drop_at::geometry)         as drop_lng,
         st_y(t.driver_location::geometry) as driver_lat, st_x(t.driver_location::geometry) as driver_lng,
         case when t.order_id is null then null else public.order_item_count(t.order_id) end as order_items,
         case when t.order_id is null then null else public.order_collect(t.order_id) end as collect
  from public.tasks t;
grant select on public.tasks_geo to authenticated;

-- Column privileges: everything but pin. Built from the catalogue so a column added later is readable too.
do $$ declare cols text; begin
  select string_agg(quote_ident(attname), ', ' order by attnum) into cols
    from pg_attribute where attrelid = 'public.tasks'::regclass and attnum > 0 and not attisdropped and attname <> 'pin';
  revoke select on public.tasks from authenticated, anon;
  execute format('grant select (%s) on public.tasks to authenticated', cols);
end $$;

-- ---------- ringing: open tasks for this online driver, nearest first (schema.sql's, without the PIN) ----------
-- Rings for 3 minutes from when the task started searching: created, or handed back by a driver.
create or replace function public.open_tasks_near(lat double precision, lng double precision) returns setof public.tasks
language sql stable security definer set search_path = public, extensions as $$
  select m.*
  from public.tasks t
  join public.driver_presence p on p.profile_id = public.me() and p.online and p.kind = t.vehicle_kind
  cross join lateral jsonb_populate_record(t, jsonb_build_object('pin', '')) m
  where t.status = 'SEARCHING' and t.requester_id <> public.me()
    and (t.only_riders is null or public.me() = any(t.only_riders))
    and st_dwithin(t.pickup, public.geo(lat, lng), case when t.type = 'DELIVERY' then public.setting('delivery_radius_m') else public.setting('ride_radius_m') end)
    and t.status_at > now() - interval '3 minutes'
  order by st_distance(t.pickup, public.geo(lat, lng))
$$;

-- ---------- claiming: first driver wins; never your own request, and one trip at a time ----------
create or replace function public.claim_task(p_task uuid) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare p driver_presence; t tasks;
begin
  select * into p from driver_presence where profile_id = me() and online;
  if not found then raise exception 'go online first'; end if;
  if exists (select 1 from tasks x where x.driver_id = me() and x.id <> p_task and x.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')) then
    raise exception 'finish your current trip before taking another';
  end if;
  update tasks set status = 'MATCHED', driver_id = me(), vehicle_id = p.vehicle_id, driver_location = p.location
   where id = p_task and status = 'SEARCHING' and vehicle_kind = p.kind and requester_id <> me()
     and (only_riders is null or me() = any(only_riders))
  returning * into t;
  if not found then return false; end if;
  insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, me(), p.vehicle_id, 'ACCEPTED', t.km, t.fare);
  return true;
end $$;

-- ---------- moving a task along (schema.sql's rules) ----------
-- Differences: a hand-back rings again for the full window (status_at, via the trigger), and the row handed back
-- carries the PIN only for the requester, so the driver's own calls never reveal it.
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
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
    if p_status = 'IN_PROGRESS' and t.order_id is not null then update orders set status = 'PICKED_UP' where id = t.order_id; end if;
  elsif t.requester_id = me() then
    if p_status = 'CANCELLED' and t.status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER') then null;
    elsif p_status = 'NO_DRIVER' and t.status = 'SEARCHING' then null;
    elsif p_status = 'PAID' and t.status = 'COMPLETED' then null;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
  else raise exception 'not your task'; end if;
  if p_status = 'SEARCHING' then
    update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where id = p_task returning * into t;
  else
    update tasks set status = p_status, paid_with = coalesce(p_paid_with, paid_with) where id = p_task returning * into t;
  end if;
  if t.requester_id is distinct from me() then t.pin := ''; end if;
  return t;
end $$;

-- ---------- counterparty's phone and payment link ----------
-- Only while a trip is active, and for a day after it finished (the rider pays from the UPI link); not forever.
create or replace function public.contact_for_task(p_task uuid) returns table (phone text, upi_uri text)
language sql stable security definer set search_path = public, extensions as $$
  select pp.phone, pp.upi_uri from public.tasks t
  join public.profile_private pp on pp.profile_id = case when t.requester_id = public.me() then t.driver_id else t.requester_id end
  where t.id = p_task and public.me() in (t.requester_id, t.driver_id)
    and (t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS') or (t.status = 'COMPLETED' and t.status_at > now() - interval '24 hours'))
$$;

-- ---------- reviews: one per trip or order, never of your own listing ----------
-- The table's unique (listing, author, task, order) never fires: every review leaves task or order NULL, and NULLs are
-- distinct. Earlier duplicates are removed (keeping the first) and their votes taken back off the listing's trust.
with dup as (
  select id from (select id, row_number() over (partition by author_id, task_id order by created_at, id) as n from public.reviews where task_id is not null) x where n > 1
  union
  select id from (select id, row_number() over (partition by author_id, order_id order by created_at, id) as n from public.reviews where order_id is not null) x where n > 1
), gone as (delete from public.reviews r using dup where r.id = dup.id returning r.listing_id, r.vote)
update public.listings l set trust_up = greatest(0, l.trust_up - g.up), trust_down = greatest(0, l.trust_down - g.down)
from (select listing_id, count(*) filter (where vote > 0)::int as up, count(*) filter (where vote < 0)::int as down from gone group by listing_id) g
where l.id = g.listing_id;
create unique index if not exists reviews_one_per_task on public.reviews (author_id, task_id) where task_id is not null;
create unique index if not exists reviews_one_per_order on public.reviews (author_id, order_id) where order_id is not null;

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
  if l.owner_id = me() or listing_role(p_listing) is not null then raise exception 'you cannot review your own listing'; end if;
  if p_task is not null and exists (select 1 from reviews r where r.author_id = me() and r.task_id = p_task) then raise exception 'you already reviewed this trip'; end if;
  if p_task is null and exists (select 1 from reviews r where r.author_id = me() and r.order_id = p_order) then raise exception 'you already reviewed this order'; end if;
  insert into reviews (listing_id, author_id, task_id, order_id, vote, comment) values (p_listing, me(), p_task, p_order, p_vote, trim(p_comment));
  update listings set trust_up = trust_up + (p_vote > 0)::int, trust_down = trust_down + (p_vote < 0)::int where id = p_listing;
end $$;

-- ---------- presence: stamped and typed by the server ----------
-- updated_at is the server's clock on every write (going online, the app's 60-second heartbeat, update_location), so a
-- driver waiting at a stand stays on the map. kind always comes from the vehicle, so a bike can't go online as an auto.
create or replace function public.presence_touch() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  new.kind := (select v.kind from public.vehicles v where v.id = new.vehicle_id);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists presence_touch on public.driver_presence;
create trigger presence_touch before insert or update on public.driver_presence for each row execute function public.presence_touch();
-- Riders see drivers through online_drivers_near only; the raw rows (exact positions) are each driver's own.
drop policy if exists presence_read on public.driver_presence;
create policy presence_read on public.driver_presence for select to authenticated using (profile_id = public.me());

-- ---------- online drivers around a point, for the map and "n riders nearby" ----------
-- Presence rows older than 5 minutes are dead apps. Trust comes from the driver's DRIVER listing when they have one.
-- At most 10 km and 50 drivers; the plate is shown by its last 4 characters (the matched rider gets it whole from task_driver).
create or replace function public.online_drivers_near(p_lat double precision, p_lng double precision, radius_m int default 5000)
returns table (profile_id uuid, kind text, lat double precision, lng double precision, name text, model text, plate text, up int, down int)
language sql stable security definer set search_path = public, extensions as $$
  select p.profile_id, p.kind, st_y(p.location::geometry), st_x(p.location::geometry), pr.name, v.model, '••' || right(v.plate, 4),
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0)
  from public.driver_presence p
  join public.profiles pr on pr.id = p.profile_id and pr.status = 'ACTIVE'
  join public.vehicles v on v.id = p.vehicle_id
  left join public.listings l on l.owner_id = p.profile_id and l.kind = 'DRIVER'
  where p.online and p.location is not null and p.updated_at > now() - interval '5 minutes'
    and p.profile_id is distinct from public.me()
    and st_dwithin(p.location, public.geo(p_lat, p_lng), least(greatest(coalesce(radius_m, 5000), 0), 10000))
  order by st_distance(p.location, public.geo(p_lat, p_lng))
  limit 50
$$;

-- ---------- the driver of a task, for the requester's screen (name, vehicle, trust, listing to review) ----------
create or replace function public.task_driver(p_task uuid)
returns table (profile_id uuid, name text, kind text, model text, plate text, up int, down int, listing_id uuid)
language sql stable security definer set search_path = public, extensions as $$
  select pr.id, pr.name, coalesce(v.kind, t.vehicle_kind), coalesce(v.model, ''), coalesce(v.plate, ''),
         coalesce(l.trust_up, 0), coalesce(l.trust_down, 0), l.id
  from public.tasks t
  join public.profiles pr on pr.id = t.driver_id
  left join public.vehicles v on v.id = t.vehicle_id
  left join public.listings l on l.owner_id = t.driver_id and l.kind = 'DRIVER'
  where t.id = p_task and public.me() in (t.requester_id, t.driver_id)
$$;

-- ---------- my open task: resume a trip after the app was killed ----------
-- Driver: a trip still under way. Requester: a task still searching (it rings for 3 minutes), a trip under way, or a
-- finished ride not yet marked paid, for a day (the Pay screen). A finished delivery has nothing left to do.
create or replace function public.my_open_task() returns setof public.tasks_geo
language sql stable security definer set search_path = public, extensions as $$
  select * from public.tasks_geo
  where (driver_id = public.me() and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS'))
     or (requester_id = public.me() and (status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')
                                          or (status = 'SEARCHING' and status_at > now() - interval '3 minutes')
                                          or (status = 'COMPLETED' and type = 'RIDE' and status_at > now() - interval '24 hours')))
  order by coalesce(driver_id = public.me(), false) desc, created_at desc
  limit 1
$$;

-- ---------- deleting my account ----------
-- The app calls this before removing the Firebase user. Trips, orders and reviews stay for the other party's records,
-- so the profile is anonymised rather than deleted: presence goes, open requests are cancelled and trips I was driving
-- go back to other drivers, the phone and UPI link are deleted, my listings are taken down (as delete_listing does),
-- my posts, moments, comments and votes are deleted, my messages are blanked and I leave every chat,
-- and the profile keeps no name, photo or home and no sign-in (signing up again with the same number starts afresh).
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check check (status in ('ACTIVE', 'BANNED', 'DELETED'));

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  delete from driver_presence where profile_id = my;
  update tasks set status = 'CANCELLED' where requester_id = my and status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER');
  insert into task_events (task_id, driver_id, vehicle_id, event) select id, my, vehicle_id, 'CANCELLED' from tasks where driver_id = my and status in ('MATCHED', 'ARRIVED');
  update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where driver_id = my and status in ('MATCHED', 'ARRIVED');
  delete from profile_private where profile_id = my;
  delete from syncs where my in (requester_id, addressee_id);
  update listings set status = 'DELETED', online = false where owner_id = my and status <> 'DELETED';
  -- What I said and shared goes too: posts (their votes and comments cascade), moments, my comments and votes elsewhere,
  -- my messages (blanked like "delete message", so the other side sees "Message deleted") and my place in every chat.
  delete from posts where author_id = my;
  delete from moments where author_id = my;
  delete from post_comments where author_id = my;
  delete from post_votes where profile_id = my;
  update messages set deleted_at = now() where sender_id = my and deleted_at is null;
  delete from conversation_members where profile_id = my;
  delete from close_friends where my in (profile_id, friend_id);
  delete from listing_syncs where profile_id = my;
  if to_regclass('public.device_tokens') is not null then execute 'delete from public.device_tokens where profile_id = $1' using my; end if;   -- push.sql
  update profiles set name = '', bio = '', area = '', photo_url = null, home = null, status = 'DELETED', auth_uid = 'deleted:' || id::text where id = my;
end $$;

-- order_item_count and task_pin run as the caller inside the security-invoker view, so authenticated needs execute on
-- them too (one returns a count, the other only the caller's own PIN).
revoke execute on function public.order_item_count(uuid), public.order_collect(uuid), public.task_pin(uuid), public.online_drivers_near(double precision, double precision, int),
  public.task_driver(uuid), public.my_open_task(), public.open_tasks_near(double precision, double precision), public.claim_task(uuid),
  public.advance_task(uuid, text, text, text), public.contact_for_task(uuid), public.review(uuid, uuid, uuid, int, text), public.delete_my_account() from public, anon;
grant execute on function public.order_item_count(uuid), public.order_collect(uuid), public.task_pin(uuid), public.online_drivers_near(double precision, double precision, int),
  public.task_driver(uuid), public.my_open_task(), public.open_tasks_near(double precision, double precision), public.claim_task(uuid),
  public.advance_task(uuid, text, text, text), public.contact_for_task(uuid), public.review(uuid, uuid, uuid, int, text), public.delete_my_account() to authenticated;
-- Trigger bodies run only as triggers.
revoke execute on function public.task_status_at(), public.presence_touch() from public, anon, authenticated;
