\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Dispatch scenarios: ride request -> claim -> PIN -> complete -> paid, plus the views/functions the app uses to follow a task.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('kavya');  select (public.ensure_profile('Kavya (customer)', '9000000021')).id is not null;
select pg_temp.as_user('suresh'); select (public.ensure_profile('Suresh (auto driver)', '9000000022')).id is not null;
select pg_temp.as_user('ravi');   select (public.ensure_profile('Ravi (bike rider)', '9000000023')).id is not null;
select pg_temp.as_user('nobody'); select (public.ensure_profile('Someone else', '9000000024')).id is not null;

\echo '== 1. Driver registers an auto, uploads a UPI QR, goes online; the map sees him with vehicle and trust'
select pg_temp.as_user('suresh');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01AB0001');
insert into listings (kind, owner_id, title, category, area, location) values ('DRIVER', me(), 'Suresh Auto', 'Auto', 'Jayanagar', geo(12.9250, 77.5938));
reset role; update vehicles set status = 'ACTIVE'; update listings set status = 'LIVE', trust_up = 12, trust_down = 1 where title = 'Suresh Auto'; set role authenticated;
update profile_private set upi_uri = 'upi://pay?pa=suresh@okaxis&pn=Suresh%20Kumar' where profile_id = me();
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'AUTO', true, geo(12.9260, 77.5940) from vehicles where plate = 'KA01AB0001';
select pg_temp.as_user('kavya');
select 'map sees: ' || name || ' ' || kind || ' ' || model || ' ' || plate || ' at ' || round(lat::numeric, 4) || ',' || round(lng::numeric, 4) || ' trust +' || up || '/-' || down from online_drivers_near(12.9250, 77.5938);
select 'far away (Whitefield) sees: ' || count(*) from online_drivers_near(12.9855, 77.7363);
select pg_temp.as_user('suresh'); select 'driver does not see himself: ' || count(*) from online_drivers_near(12.9250, 77.5938);
reset role; update driver_presence set updated_at = now() - interval '6 minutes'; set role authenticated;
select pg_temp.as_user('kavya'); select 'stale presence hidden: ' || count(*) from online_drivers_near(12.9250, 77.5938);
reset role; update driver_presence set updated_at = now(); set role authenticated;

\echo '== 2. Customer requests an auto; tasks_geo gives coordinates; my_open_task finds it'
select pg_temp.as_user('kavya');
select set_config('t.task', (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.2, 106)).id::text, false) is not null;
select 'tasks_geo: pickup ' || round(pickup_lat::numeric, 4) || ',' || round(pickup_lng::numeric, 4) || ' -> drop ' || round(drop_lat::numeric, 4) || ',' || round(drop_lng::numeric, 4) || ', driver ' || coalesce(driver_lat::text, 'none') || ', items ' || coalesce(order_items::text, 'n/a') from tasks_geo where id = current_setting('t.task')::uuid;
select 'my_open_task (customer): ' || status || ' ' || pickup_label || ' -> ' || drop_label from my_open_task();
select pg_temp.as_user('nobody'); select 'outsider sees the task: ' || count(*) from tasks_geo where id = current_setting('t.task')::uuid;
select 'outsider my_open_task: ' || count(*) from my_open_task();

\echo '== 3. Driver is rung, claims it, position flows through tasks_geo, customer sees the driver'
select pg_temp.as_user('suresh');
select 'rung for: ' || type || ' ' || pickup_label || ' Rs ' || fare from open_tasks_near(12.9260, 77.5940);
select 'driver reads pickup via tasks_geo while ringing: ' || round(pickup_lat::numeric, 3) from tasks_geo where id = current_setting('t.task')::uuid;
select 'claim: ' || claim_task(current_setting('t.task')::uuid);
select 'claim twice: ' || claim_task(current_setting('t.task')::uuid);
select 'my_open_task (driver): ' || status from my_open_task();
select update_location(12.9255, 77.5939);
select pg_temp.as_user('kavya');
select 'customer sees driver at ' || round(driver_lat::numeric, 4) || ',' || round(driver_lng::numeric, 4) || ' status ' || status from tasks_geo where id = current_setting('t.task')::uuid;
select 'task_driver: ' || name || ' ' || model || ' ' || plate || ' +' || up || ' listing ' || (listing_id is not null) from task_driver(current_setting('t.task')::uuid);
select 'contact: phone ' || phone || ', upi ' || upi_uri from contact_for_task(current_setting('t.task')::uuid);
select pg_temp.as_user('nobody'); select 'outsider task_driver: ' || count(*) from task_driver(current_setting('t.task')::uuid);

\echo '== 4. Arrived -> PIN -> complete -> customer pays; the task is no longer open'
select pg_temp.as_user('suresh');
select 'arrived: ' || (advance_task(current_setting('t.task')::uuid, 'ARRIVED')).status;
select 'wrong PIN -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'IN_PROGRESS', '0000')$$, current_setting('t.task')), 'PIN');
select pg_temp.as_user('kavya'); select set_config('t.pin', pin, false) is not null from tasks_geo where id = current_setting('t.task')::uuid;
select pg_temp.as_user('suresh');
select 'started with the customer''s PIN: ' || (advance_task(current_setting('t.task')::uuid, 'IN_PROGRESS', current_setting('t.pin'))).status;
select 'driver hands back mid-trip -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'SEARCHING')$$, current_setting('t.task')), 'cannot go');
select 'completed: ' || (advance_task(current_setting('t.task')::uuid, 'COMPLETED')).status;
select 'driver marks paid -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'PAID', null, 'Cash')$$, current_setting('t.task')), 'cannot go');
select pg_temp.as_user('kavya');
select 'still open before paying: ' || status from my_open_task();
select 'paid: ' || (advance_task(current_setting('t.task')::uuid, 'PAID', null, 'UPI')).status;
select 'paid with: ' || paid_with from tasks_geo where id = current_setting('t.task')::uuid;
select 'open tasks after paying: ' || count(*) from my_open_task();
select review((select listing_id from task_driver(current_setting('t.task')::uuid)), current_setting('t.task')::uuid, null, 1, 'Safe driving, on time');
select 'driver listing trust now +' || trust_up from listings where title = 'Suresh Auto';

\echo '== 5. Cancel while searching; a stale SEARCHING task is not "open" any more'
select set_config('t.task2', (request_ride('CAB', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 112)).id::text, false) is not null;
select 'cancel: ' || (advance_task(current_setting('t.task2')::uuid, 'CANCELLED')).status;
select 'open after cancel: ' || count(*) from my_open_task();
select set_config('t.task3', (request_ride('CAB', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 112)).id::text, false) is not null;
select 'fresh SEARCHING is open: ' || count(*) from my_open_task();
reset role; update tasks set created_at = now() - interval '4 minutes' where id = current_setting('t.task3')::uuid; set role authenticated;
select 'stale SEARCHING is not: ' || count(*) from my_open_task();
select 'no driver: ' || (advance_task(current_setting('t.task3')::uuid, 'NO_DRIVER')).status;

\echo '== 6. Delivery task shows the item count to the bike rider; the buyer follows it'
select pg_temp.as_user('nobody');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Kavya Stores', 'Grocery', 'Jayanagar', geo(12.9240, 77.5930));
reset role; update listings set status = 'LIVE' where title = 'Kavya Stores'; set role authenticated;
insert into items (listing_id, name, price, unit) select id, 'Sugar 1kg', 48, '1 kg' from listings where title = 'Kavya Stores';
select pg_temp.as_user('kavya');
select set_config('t.order', place_order((select id from listings where title = 'Kavya Stores'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Sugar 1kg'), 'qty', 3)), 12.9300, 77.5900, 'Kavya home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('nobody'); select respond_order(current_setting('t.order')::uuid, true);
select pg_temp.as_user('ravi');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'BIKE', 'Honda Activa', 'KA05CD0002');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA05CD0002'; set role authenticated;   -- only checked vehicles may go online (manage.sql)
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'BIKE', true, geo(12.9245, 77.5935) from vehicles where plate = 'KA05CD0002';
select 'bike rung for: ' || type || ' from ' || pickup_label || ' to ' || drop_label from open_tasks_near(12.9245, 77.5935);
select 'rider sees ' || order_items || ' items, shop at ' || round(pickup_lat::numeric, 4) || ',' || round(pickup_lng::numeric, 4) from tasks_geo where order_id = current_setting('t.order')::uuid;
select pg_temp.as_user('suresh'); select 'auto driver rung for the delivery: ' || count(*) from open_tasks_near(12.9245, 77.5935);
select pg_temp.as_user('ravi'); select 'claim delivery: ' || claim_task((select id from tasks_geo where order_id = current_setting('t.order')::uuid));
select pg_temp.as_user('kavya');
select 'buyer follows: ' || status || ' rider ' || (select name from task_driver(t.id)) || ' on ' || (select plate from task_driver(t.id)) || ', PIN ' || length(pin) || ' digits' from tasks_geo t where order_id = current_setting('t.order')::uuid;
select 'buyer my_open_task is the delivery: ' || type from my_open_task();
