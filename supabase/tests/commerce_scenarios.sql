\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- These flows are walked in milliseconds and without moving anyone: switch off hardening_dispatch.sql's clock and distance checks, as
-- device-test projects do (supabase/README.md, "Dispatch settings"). hardening_dispatch_scenarios.sql tests those checks themselves.
update public.settings set value = 0 where key in ('min_trip_seconds', 'arrive_radius_m', 'complete_radius_m', 'presence_max_speed_mps');
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.shop() returns uuid language sql as $$ select id from public.listings where title = 'Lakshmi Stores' $$;

set role authenticated;
select pg_temp.as_user('owner');   select (public.ensure_profile('Lakshmi (owner)', '9000000021')).id is not null;
select pg_temp.as_user('admin');   select (public.ensure_profile('Suresh (admin)', '9000000022')).id is not null;
select pg_temp.as_user('rider');   select (public.ensure_profile('Manju (store rider)', '9000000023')).id is not null;
select pg_temp.as_user('buyer');   select (public.ensure_profile('Deepa (buyer)', '9000000024')).id is not null;
select pg_temp.as_user('stranger'); select (public.ensure_profile('Kiran (nobody)', '9000000025')).id is not null;
select pg_temp.as_user('owner');
update profile_private set upi_uri = 'upi://pay?pa=lakshmi@okaxis&pn=Lakshmi%20Stores&cu=INR' where profile_id = me();
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Lakshmi Stores', 'Grocery', 'Rice, dal, oil', 'Jayanagar', geo(12.9250, 77.5938), '{"cod": true, "free_delivery": false}');
insert into items (listing_id, name, price, unit) values (pg_temp.shop(), 'Sona masoori rice', 62, '1 kg'), (pg_temp.shop(), 'Toor dal', 140, '1 kg');
select 'invite admin: ' || (invite(pg_temp.shop(), null, (select short_code from profiles where auth_uid = 'admin'), 'ADMIN') is not null);
select 'invite store rider: ' || (invite(pg_temp.shop(), null, (select short_code from profiles where auth_uid = 'rider'), 'STORE_RIDER') is not null);
select pg_temp.as_user('admin'); select respond_invite((select id from invites where invitee_id = me() and status = 'PENDING'), true);
select pg_temp.as_user('rider'); select respond_invite((select id from invites where invitee_id = me() and status = 'PENDING'), true);
reset role; update listings set status = 'LIVE', online = true where id = pg_temp.shop(); set role authenticated;

\echo '== 1. Cart screen: anyone can see the shop has store riders (so "Store''s own rider" and cash on delivery can be offered)'
select pg_temp.as_user('buyer');
select 'store riders visible to buyer: ' || count(*) from listing_members where listing_id = pg_temp.shop() and role = 'STORE_RIDER';

\echo '== 2. Marketplace order: buyer sees the owner''s phone + UPI; owner/admin see the buyer''s phone only; others see nothing'
select set_config('t.o1', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Sona masoori rice'), 'qty', 5)), 12.9300, 77.6000, 'Deepa home, 4th block', 'UPI', 'MARKETPLACE')::text, false) is not null;
select 'order: subtotal Rs ' || subtotal || ', delivery Rs ' || delivery_fee || ' paid by ' || fee_paid_by || ', ' || status from orders where id = current_setting('t.o1')::uuid;
select 'buyer contact -> ' || coalesce(phone, '-') || ' | ' || coalesce(upi_uri, '-') || ' | ' || name from contact_for_order(current_setting('t.o1')::uuid);
select pg_temp.as_user('owner');  select 'owner contact -> ' || coalesce(phone, '-') || ' | upi ' || coalesce(upi_uri, '-') || ' | ' || name from contact_for_order(current_setting('t.o1')::uuid);
select pg_temp.as_user('admin');  select 'admin contact -> ' || coalesce(phone, '-') || ' | ' || name from contact_for_order(current_setting('t.o1')::uuid);
select pg_temp.as_user('rider');  select 'store rider rows: ' || count(*) from contact_for_order(current_setting('t.o1')::uuid);
select pg_temp.as_user('stranger'); select 'stranger rows: ' || count(*) from contact_for_order(current_setting('t.o1')::uuid);
reset role; select 'signed-out rows: ' || count(*) from contact_for_order(current_setting('t.o1')::uuid); set role authenticated;

\echo '== 3. Cancel: only the buyer, only while PLACED; contact closes after that'
select pg_temp.as_user('stranger'); select 'stranger cancels -> ' || pg_temp.expect_fail(format('select cancel_order(%L)', current_setting('t.o1')), 'not found');
select pg_temp.as_user('owner');    select 'owner cancels -> ' || pg_temp.expect_fail(format('select cancel_order(%L)', current_setting('t.o1')), 'not found');
select pg_temp.as_user('buyer');    select cancel_order(current_setting('t.o1')::uuid);
select 'status: ' || status from orders where id = current_setting('t.o1')::uuid;
select 'cancel twice -> ' || pg_temp.expect_fail(format('select cancel_order(%L)', current_setting('t.o1')), 'already cancelled');
select 'contact after cancel rows: ' || count(*) from contact_for_order(current_setting('t.o1')::uuid);
with x as (update orders set status = 'PLACED' where id = current_setting('t.o1')::uuid returning 1) select 'buyer tries a direct update -> rows changed: ' || count(*) from x;

\echo '== 4. Accepted order cannot be cancelled; the buyer can follow the delivery task; contact stays open through DELIVERED'
select set_config('t.o2', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 2)), 12.9300, 77.6000, 'Deepa home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('admin'); select respond_order(current_setting('t.o2')::uuid, true);
select pg_temp.as_user('buyer');
select 'cancel after accept -> ' || pg_temp.expect_fail(format('select cancel_order(%L)', current_setting('t.o2')), 'already accepted');
select 'buyer sees delivery task: ' || type || ' ' || status || ' to ' || drop_label || ', Rs ' || fare from tasks where order_id = current_setting('t.o2')::uuid;
select pg_temp.as_user('stranger'); select 'stranger sees the task: ' || count(*) from tasks where order_id = current_setting('t.o2')::uuid;
select pg_temp.as_user('admin');
select update_order_status(current_setting('t.o2')::uuid, 'READY'); select 'admin marks READY: ' || status from orders where id = current_setting('t.o2')::uuid;
select 'admin marks a delivery order DELIVERED -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'DELIVERED')$$, current_setting('t.o2')), 'completed by the rider');
reset role; update orders set status = 'DELIVERED' where id = current_setting('t.o2')::uuid; set role authenticated;
select pg_temp.as_user('buyer');
select 'buyer contact at DELIVERED -> upi ' || coalesce(upi_uri, '-') from contact_for_order(current_setting('t.o2')::uuid);

\echo '== 5. Pick-up order: no delivery fee; vendor marks READY then DELIVERED when the buyer collects; buyer can then review'
select set_config('t.o3', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Sona masoori rice'), 'qty', 1)), 12.9300, 77.6000, '', 'UPI', 'PICKUP')::text, false) is not null;
select 'pickup order: delivery Rs ' || delivery_fee || ', mode ' || delivery_mode from orders where id = current_setting('t.o3')::uuid;
select 'buyer marks own order -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'READY')$$, current_setting('t.o3')), 'not found');
select pg_temp.as_user('owner');
select 'ready before accepting -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'READY')$$, current_setting('t.o3')), 'cannot go from placed');
select respond_order(current_setting('t.o3')::uuid, true);
select update_order_status(current_setting('t.o3')::uuid, 'READY'); select 'after READY: ' || status from orders where id = current_setting('t.o3')::uuid;
select 'no task for a pick-up order: ' || count(*) from tasks where order_id = current_setting('t.o3')::uuid;
select update_order_status(current_setting('t.o3')::uuid, 'DELIVERED'); select 'after hand-over: ' || status from orders where id = current_setting('t.o3')::uuid;
select pg_temp.as_user('buyer');
select review(pg_temp.shop(), null, current_setting('t.o3')::uuid, 1, 'Fresh rice, packed quickly');
select 'shop trust after review: +' || trust_up from listings where id = pg_temp.shop();

\echo '== 6. Store rider + cash on delivery: the task rings only that store''s riders'
select set_config('t.o4', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.9300, 77.6000, 'Deepa home', 'COD', 'STORE_RIDER')::text, false) is not null;
select pg_temp.as_user('owner'); select respond_order(current_setting('t.o4')::uuid, true);
select pg_temp.as_user('buyer');
select 'task only for store riders: ' || (pg_temp.pid('rider') = any(only_riders)) || ', payment ' || (select payment from orders where id = current_setting('t.o4')::uuid) from tasks where order_id = current_setting('t.o4')::uuid;

\echo '== 7. Vendor inbox: owner and admin list every order for the shop, newest first; the buyer sees only their own'
select pg_temp.as_user('admin'); select 'admin sees ' || count(*) || ' orders for the shop' from orders where listing_id = pg_temp.shop();
select pg_temp.as_user('stranger'); select 'stranger sees ' || count(*) || ' orders' from orders where listing_id = pg_temp.shop();
select pg_temp.as_user('buyer'); select 'buyer newest first: ' || string_agg(status, ' > ' order by created_at desc) from orders where buyer_id = me();

\echo '== 8. Checks the server now makes itself: store riders must exist, cash on delivery only where the shop allows it'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Ravi Bakery', 'Bakery', 'Jayanagar', geo(12.9260, 77.5940), '{"cod": true}');
insert into items (listing_id, name, price) values ((select id from listings where title = 'Ravi Bakery'), 'Milk bread', 45);
reset role; update listings set status = 'LIVE', online = true where title = 'Ravi Bakery'; set role authenticated;
select pg_temp.as_user('buyer');
select 'store rider at a shop with none -> ' || pg_temp.expect_fail(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Deepa home', 'UPI', 'STORE_RIDER')$$, (select id from listings where title = 'Ravi Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Milk bread'), 'qty', 1))), 'no riders of its own');
select 'COD + store rider at a shop with none -> ' || pg_temp.expect_fail(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Deepa home', 'COD', 'STORE_RIDER')$$, (select id from listings where title = 'Ravi Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Milk bread'), 'qty', 1))), 'no riders of its own');
reset role; update listings set details = details || '{"cod": false}' where id = pg_temp.shop(); set role authenticated;
select pg_temp.as_user('buyer');
select 'COD where the shop turned it off -> ' || pg_temp.expect_fail(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Deepa home', 'COD', 'STORE_RIDER')$$, pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1))), 'does not take cash');
reset role; update listings set details = details || '{"cod": true}' where id = pg_temp.shop(); set role authenticated;
select pg_temp.as_user('buyer');
select set_config('t.o5', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.9300, 77.6000, 'Deepa home', 'COD', 'STORE_RIDER')::text, false) is not null;
reset role; delete from listing_members where listing_id = pg_temp.shop() and role = 'STORE_RIDER'; set role authenticated;
select pg_temp.as_user('owner');
select 'accept after the last store rider left -> ' || pg_temp.expect_fail(format('select respond_order(%L, true)', current_setting('t.o5')), 'no store riders left');
select 'order still waiting: ' || status || ', tasks: ' || (select count(*) from tasks where order_id = o.id) from orders o where id = current_setting('t.o5')::uuid;
select respond_order(current_setting('t.o5')::uuid, false); select 'shop rejects instead: ' || status from orders where id = current_setting('t.o5')::uuid;
reset role; insert into listing_members values (pg_temp.shop(), pg_temp.pid('rider'), 'STORE_RIDER'); set role authenticated;

\echo '== 9. A delivery nobody will complete can be closed by the shop (not once a rider has it); the buyer can still call about a refund'
select pg_temp.as_user('buyer');
select 'buyer cancel is recorded as: ' || cancelled_by from orders where id = current_setting('t.o1')::uuid;
select set_config('t.o6', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.9300, 77.6000, 'Deepa home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('admin');
select 'shop cancels before accepting -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'CANCELLED')$$, current_setting('t.o6')), 'cannot go from placed');
select respond_order(current_setting('t.o6')::uuid, true);
select pg_temp.as_user('buyer');
select 'buyer uses the shop''s cancel -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'CANCELLED')$$, current_setting('t.o6')), 'not found');
select pg_temp.as_user('admin');
select update_order_status(current_setting('t.o6')::uuid, 'CANCELLED');
select 'no rider came, shop closes it: ' || status || ' by ' || cancelled_by from orders where id = current_setting('t.o6')::uuid;
select pg_temp.as_user('buyer');
select 'its delivery task: ' || status from tasks where order_id = current_setting('t.o6')::uuid;
select 'buyer can still call the shop -> ' || coalesce(phone, '-') || ' | ' || name from contact_for_order(current_setting('t.o6')::uuid);
select set_config('t.o7', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.9300, 77.6000, 'Deepa home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('owner'); select respond_order(current_setting('t.o7')::uuid, true);
select pg_temp.as_user('buyer'); select 'buyer cancels the delivery task: ' || (advance_task((select id from tasks where order_id = current_setting('t.o7')::uuid), 'CANCELLED')).status;
select pg_temp.as_user('owner'); select update_order_status(current_setting('t.o7')::uuid, 'CANCELLED');
select 'after the buyer dropped the delivery: ' || status || ' by ' || cancelled_by from orders where id = current_setting('t.o7')::uuid;
select pg_temp.as_user('buyer');
select set_config('t.o8', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.9300, 77.6000, 'Deepa home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('owner'); select respond_order(current_setting('t.o8')::uuid, true);
reset role; update tasks set status = 'MATCHED', driver_id = pg_temp.pid('stranger') where order_id = current_setting('t.o8')::uuid; set role authenticated;
select pg_temp.as_user('owner');
select 'shop cancels once a rider has it -> ' || pg_temp.expect_fail(format($$select update_order_status(%L, 'CANCELLED')$$, current_setting('t.o8')), 'rider already has');
select 'order stays: ' || status from orders where id = current_setting('t.o8')::uuid;

\echo '== 10. A shop switched off (closed) takes no orders until the owner opens it again'
select pg_temp.as_user('owner'); update listings set online = false where id = pg_temp.shop();
select pg_temp.as_user('buyer');
select 'order while closed -> ' || pg_temp.expect_fail(format($$select place_order(%L, jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1)), 12.93, 77.60, 'Deepa home', 'UPI', 'PICKUP')$$, pg_temp.shop(), (select id from items where name = 'Toor dal')), 'closed right now');
select pg_temp.as_user('owner'); update listings set online = true where id = pg_temp.shop();
select pg_temp.as_user('buyer');
select 'order once open again: ' || (place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal'), 'qty', 1)), 12.93, 77.60, 'Deepa home', 'UPI', 'PICKUP') is not null);

\echo '== 11. What the rider collects at the door: the fee (buyer pays it), 0 (free delivery), the whole bill (store-rider COD); hidden from others'
select pg_temp.as_user('buyer');
select case when collect = (select delivery_fee from orders where id = current_setting('t.o2')::uuid) then 'ok, marketplace collect = fee: ' || collect else 'FAIL marketplace collect ' || coalesce(collect::text, 'null') end
  from tasks_geo where order_id = current_setting('t.o2')::uuid;
select case when collect = (select subtotal + delivery_fee from orders where id = current_setting('t.o4')::uuid) then 'ok, store-rider COD collect = whole bill: ' || collect else 'FAIL COD collect ' || coalesce(collect::text, 'null') end
  from tasks_geo where order_id = current_setting('t.o4')::uuid;
reset role; update orders set fee_paid_by = 'VENDOR' where id = current_setting('t.o2')::uuid; set role authenticated;
select case when collect = 0 then 'ok, free delivery collect = 0' else 'FAIL free delivery collect ' || coalesce(collect::text, 'null') end
  from tasks_geo where order_id = current_setting('t.o2')::uuid;
select pg_temp.as_user('stranger');
select case when public.order_collect(current_setting('t.o4')::uuid) is null then 'ok, stranger gets no amount' else 'FAIL stranger reads the COD amount' end;
select pg_temp.as_user('rider');
select case when public.order_collect(current_setting('t.o4')::uuid) is null then 'ok, ringing rider gets no amount yet' else 'FAIL unclaimed rider reads the amount' end;
reset role; update tasks set driver_id = pg_temp.pid('rider'), status = 'COMPLETED' where order_id = current_setting('t.o4')::uuid; set role authenticated;
select case when public.order_collect(current_setting('t.o4')::uuid) = (select subtotal + delivery_fee from orders where id = current_setting('t.o4')::uuid) then 'ok, rider holding the task reads the COD amount' else 'FAIL rider holding the task: ' || coalesce(public.order_collect(current_setting('t.o4')::uuid)::text, 'null') end;
