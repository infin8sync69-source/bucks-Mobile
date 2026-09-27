\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
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
reset role; update listings set status = 'LIVE' where id = pg_temp.shop(); set role authenticated;

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
