\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.shop() returns uuid language sql as $$ select id from public.listings where title = 'Annapurna Stores' $$;
create or replace function pg_temp.task(o text) returns public.tasks language sql security definer as $$ select * from public.tasks where order_id = current_setting(o)::uuid order by created_at desc limit 1 $$;

set role authenticated;
select pg_temp.as_user('do');  select (public.ensure_profile('Owner Anu', '9000000401')).id is not null;
select pg_temp.as_user('dr');  select (public.ensure_profile('Ravi Rider', '9000000402')).id is not null;
select pg_temp.as_user('db');  select (public.ensure_profile('Buyer Bina', '9000000403')).id is not null;
select pg_temp.as_user('dx');  select (public.ensure_profile('Stranger Xan', '9000000404')).id is not null;
select pg_temp.as_user('ds');  select (public.ensure_profile('Staff Sam', '9000000405')).id is not null;
select pg_temp.as_user('do');
insert into listings (kind, owner_id, title, category, area, location, details)
  values ('BUSINESS', me(), 'Annapurna Stores', 'Grocery', 'Jayanagar', geo(12.9250, 77.5938), '{"cod": true}');
insert into items (listing_id, name, price, unit) values (pg_temp.shop(), 'Rice', 60, '1 kg');
select invite(pg_temp.shop(), null, (select short_code from profiles where auth_uid = 'dr'), 'STORE_RIDER') is not null;
select pg_temp.as_user('dr'); select respond_invite((select id from invites where invitee_id = me() and status = 'PENDING'), true);
reset role;
update listings set status = 'LIVE', online = true where id = pg_temp.shop();
insert into staff (profile_id) select id from profiles where auth_uid = 'ds';
set role authenticated;

\echo '== 1. Accept and choose the shop''s own rider: rung alone for a minute'
select pg_temp.as_user('db');
select set_config('t.o1', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Rice'), 'qty', 2)), 12.9300, 77.6000, 'Bina home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('do');
select 'a stranger as the rider -> ' || pg_temp.expect_fail(format($$select respond_order(%L, true, null, %L)$$, current_setting('t.o1'), pg_temp.pid('dx')), 'choose one of your store riders');
select pg_temp.check('the order is still waiting after a refused rider', (select status from orders where id = current_setting('t.o1')::uuid) = 'PLACED');
select respond_order(current_setting('t.o1')::uuid, true, null, pg_temp.pid('dr'));
select pg_temp.check('only the chosen rider is rung', (pg_temp.task('t.o1')).only_riders = array[pg_temp.pid('dr')] and (pg_temp.task('t.o1')).preferred_rider = pg_temp.pid('dr'));
select pg_temp.check('for a short window', (pg_temp.task('t.o1')).exclusive_until between now() + interval '30 seconds' and now() + interval '2 minutes');

\echo '== 2. The shop sees where its delivery stands, and its riders; nobody else does'
select pg_temp.check('the owner sees it ringing, with the pickup PIN', (select status = 'SEARCHING' and length(pin) = 4 from order_delivery(current_setting('t.o1')::uuid)));
select pg_temp.check('the owner lists the store rider', (select count(*) from store_riders(pg_temp.shop())) = 1);
select pg_temp.as_user('dx');
select pg_temp.check('a stranger sees no delivery', (select count(*) from order_delivery(current_setting('t.o1')::uuid)) = 0);
select pg_temp.check('nor the shop''s riders', (select count(*) from store_riders(pg_temp.shop())) = 0);
select pg_temp.as_user('db');
select pg_temp.check('the buyer doesn''t get the shop''s view either', (select count(*) from order_delivery(current_setting('t.o1')::uuid)) = 0);

\echo '== 3. The window ends: the request widens to the usual riders (Bucks bikes nearby for a marketplace order)'
reset role;
update tasks set exclusive_until = now() - interval '1 second' where order_id = current_setting('t.o1')::uuid;
select expire_tasks() >= 1;
select pg_temp.check('widened to every nearby bike', (pg_temp.task('t.o1')).only_riders is null and (pg_temp.task('t.o1')).exclusive_until is null and (pg_temp.task('t.o1')).status = 'SEARCHING');
set role authenticated;

\echo '== 4. Nobody took it: the shop rings again or sends its rider; never once a rider has it'
reset role; update tasks set status = 'NO_DRIVER' where order_id = current_setting('t.o1')::uuid; set role authenticated;
select pg_temp.as_user('dx');
select 'a stranger reassigns -> ' || pg_temp.expect_fail(format($$select reassign_delivery(%L, null)$$, current_setting('t.o1')), 'order not found');
select pg_temp.as_user('do');
select reassign_delivery(current_setting('t.o1')::uuid, pg_temp.pid('dr')) = 'SEARCHING';
select pg_temp.check('sent to the shop''s rider', (pg_temp.task('t.o1')).status = 'SEARCHING' and (pg_temp.task('t.o1')).only_riders = array[pg_temp.pid('dr')]);
select reassign_delivery(current_setting('t.o1')::uuid, null) = 'SEARCHING';
select pg_temp.check('ring again: back to every nearby bike', (pg_temp.task('t.o1')).only_riders is null and (pg_temp.task('t.o1')).preferred_rider is null);
reset role; update tasks set status = 'MATCHED', driver_id = pg_temp.pid('dr') where order_id = current_setting('t.o1')::uuid; set role authenticated;
select 'once a rider has it -> ' || pg_temp.expect_fail(format($$select reassign_delivery(%L, null)$$, current_setting('t.o1')), 'already has it');
select pg_temp.check('the owner sees who has it, and their phone (a store rider)', (select rider_name = 'Ravi Rider' and rider_phone is not null from order_delivery(current_setting('t.o1')::uuid)));

\echo '== 5. Cash orders stay with the shop''s riders; accepting without choosing still works'
select pg_temp.as_user('db');
select set_config('t.o2', place_order(pg_temp.shop(), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Rice'), 'qty', 1)), 12.9300, 77.6000, 'Bina home', 'COD', 'STORE_RIDER')::text, false) is not null;
select pg_temp.as_user('do'); select respond_order(current_setting('t.o2')::uuid, true);
select pg_temp.check('auto: the shop''s riders, no window', (pg_temp.task('t.o2')).only_riders = array[pg_temp.pid('dr')] and (pg_temp.task('t.o2')).exclusive_until is null);

\echo '== 6. Vehicle review: staff approve, the owner can go online; others can''t decide'
reset role; insert into vehicles (owner_id, kind, model, plate, docs) values (pg_temp.pid('dr'), 'BIKE', 'Splendor', 'KA05XY1234', '[{"kind": "RC", "path": "x/rc.pdf"}]')
  returning set_config('t.v', id::text, false) is not null; set role authenticated;
select pg_temp.as_user('dx');
select pg_temp.check('a non-staff person sees no queue', (select count(*) from vehicles_to_review()) = 0);
select 'a non-staff person approves -> ' || pg_temp.expect_fail($$select review_vehicle(current_setting('t.v')::uuid, true)$$, 'staff only');
select pg_temp.as_user('ds');
select pg_temp.check('staff see the pending bike', (select count(*) from vehicles_to_review() where plate = 'KA05XY1234') = 1);
select 'a rejection without a note -> ' || pg_temp.expect_fail($$select review_vehicle(current_setting('t.v')::uuid, false, '')$$, 'what the owner needs to fix');
select review_vehicle(current_setting('t.v')::uuid, true);
reset role;
select pg_temp.check('approved: ACTIVE', (select status from vehicles where plate = 'KA05XY1234') = 'ACTIVE');
select pg_temp.check('and the owner is told', exists (select 1 from notifications where profile_id = pg_temp.pid('dr') and kind = 'VEHICLE_REVIEW'));
set role authenticated;

\echo '== 7. Search leaves out pages whose owner and I blocked each other'
select pg_temp.as_user('dx');
select pg_temp.check('found before a block', (select count(*) from search_listings('Annapurna', 12.9250, 77.5938)) = 1);
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('do'));
select pg_temp.check('gone after it', (select count(*) from search_listings('Annapurna', 12.9250, 77.5938)) = 0);
