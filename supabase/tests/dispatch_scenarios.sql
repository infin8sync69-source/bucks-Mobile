\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- These flows are walked in milliseconds and without moving anyone: switch off hardening_dispatch.sql's clock and distance checks, as
-- device-test projects do (supabase/README.md, "Dispatch settings"). hardening_dispatch_scenarios.sql tests those checks themselves.
update public.settings set value = 0 where key in ('min_trip_seconds', 'arrive_radius_m', 'complete_radius_m', 'presence_max_speed_mps');
-- Dispatch scenarios: ride request -> claim -> PIN -> complete -> paid, plus the views/functions the app uses to follow a task.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.pin_refused(t uuid) returns text language plpgsql as $$
declare st text;
begin st := (public.advance_task(t, 'IN_PROGRESS', '0000')).status;
  return case when st = 'ARRIVED' then 'ok, refused (the trip stays ARRIVED)' else 'FAIL (a wrong PIN moved the trip to ' || st || ')' end;
exception when others then return case when sqlerrm ilike '%PIN%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

set role authenticated;
select pg_temp.as_user('kavya');  select (public.ensure_profile('Kavya (customer)', '9000000021')).id is not null;
select pg_temp.as_user('suresh'); select (public.ensure_profile('Suresh (auto driver)', '9000000022')).id is not null;
select pg_temp.as_user('ravi');   select (public.ensure_profile('Ravi (bike rider)', '9000000023')).id is not null;
select pg_temp.as_user('nobody'); select (public.ensure_profile('Someone else', '9000000024')).id is not null;
select pg_temp.as_user('meera');  select (public.ensure_profile('Meera (second customer)', '9000000025')).id is not null;

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
select pg_temp.as_user('kavya');
select 'map shows the plate''s last 4 only: ' || plate from online_drivers_near(12.9250, 77.5938);
select 'map radius is capped at 10 km (Whitefield, huge radius): ' || count(*) from online_drivers_near(12.9855, 77.7363, 2147483647);
select 'riders read presence rows directly: ' || count(*) from driver_presence;
-- The presence trigger stamps updated_at with the server clock, so ageing a row needs triggers off (superuser only).
reset role; set session_replication_role = replica; update driver_presence set updated_at = now() - interval '6 minutes'; set session_replication_role = origin; set role authenticated;
select 'stale presence hidden: ' || count(*) from online_drivers_near(12.9250, 77.5938);
\echo '-- the app''s 60-second heartbeat (a PostgREST upsert without updated_at) brings a driver standing still back'
select pg_temp.as_user('suresh');
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'AUTO', true, geo(12.9260, 77.5940) from vehicles where plate = 'KA01AB0001'
  on conflict (profile_id) do update set vehicle_id = excluded.vehicle_id, kind = excluded.kind, online = excluded.online, location = excluded.location;
select 'heartbeat refreshed updated_at: ' || (updated_at > now() - interval '1 minute') from driver_presence where profile_id = me();
select pg_temp.as_user('kavya'); select 'driver back on the map: ' || count(*) from online_drivers_near(12.9250, 77.5938);

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
select 'driver reads the PIN via tasks_geo: ''' || pin || '''' from tasks_geo where id = current_setting('t.task')::uuid;
select 'driver reads the PIN from tasks -> ' || pg_temp.expect_fail(format($$select pin from tasks where id = %L$$, current_setting('t.task')), 'permission denied');
select 'driver reads the PIN via my_open_task: ''' || pin || '''' from my_open_task();
\echo '-- one trip at a time: a busy driver cannot claim a second request (from another customer: one open ride per customer, too)'
select pg_temp.as_user('meera');
select set_config('t.busy', (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 81)).id::text, false) is not null;
select pg_temp.as_user('suresh');
select 'second ring shows no PIN: ''' || pin || '''' from open_tasks_near(12.9260, 77.5940) where id = current_setting('t.busy')::uuid;
select 'busy driver claims another -> ' || pg_temp.expect_fail(format($$select claim_task(%L)$$, current_setting('t.busy')), 'current trip');
select pg_temp.as_user('meera'); select 'customer cancels it: ' || (advance_task(current_setting('t.busy')::uuid, 'CANCELLED')).status;
select pg_temp.as_user('suresh');
select update_location(12.9255, 77.5939);
select pg_temp.as_user('kavya');
select 'customer sees driver at ' || round(driver_lat::numeric, 4) || ',' || round(driver_lng::numeric, 4) || ' status ' || status from tasks_geo where id = current_setting('t.task')::uuid;
select 'task_driver: ' || name || ' ' || model || ' ' || plate || ' +' || up || ' listing ' || (listing_id is not null) from task_driver(current_setting('t.task')::uuid);
select 'contact: phone ' || phone || ', upi ' || upi_uri from contact_for_task(current_setting('t.task')::uuid);
select pg_temp.as_user('nobody'); select 'outsider task_driver: ' || count(*) from task_driver(current_setting('t.task')::uuid);

\echo '== 4. Arrived -> PIN -> complete -> customer pays; the task is no longer open'
select pg_temp.as_user('suresh');
select set_config('t.arr', row_to_json(advance_task(current_setting('t.task')::uuid, 'ARRIVED'))::text, false) is not null;
select 'arrived: ' || (current_setting('t.arr')::json->>'status') || ', PIN in the row the driver gets back: ''' || (current_setting('t.arr')::json->>'pin') || '''';
-- A wrong PIN is refused; since hardening_dispatch.sql it is counted (5 tries) instead of raising, so the trip simply stays ARRIVED.
select 'wrong PIN -> ' || pg_temp.pin_refused(current_setting('t.task')::uuid);
select pg_temp.as_user('kavya'); select set_config('t.pin', pin, false) is not null from tasks_geo where id = current_setting('t.task')::uuid;
select pg_temp.as_user('suresh');
select 'started with the customer''s PIN: ' || (advance_task(current_setting('t.task')::uuid, 'IN_PROGRESS', current_setting('t.pin'))).status;
select 'driver hands back mid-trip -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'SEARCHING')$$, current_setting('t.task')), 'cannot go');
select 'completed: ' || (advance_task(current_setting('t.task')::uuid, 'COMPLETED')).status;
select 'driver my_open_task after completing (no stale trip on every launch): ' || count(*) from my_open_task();
select 'driver marks paid -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'PAID', null, 'Cash')$$, current_setting('t.task')), 'cannot go');
select pg_temp.as_user('kavya');
select 'still open before paying: ' || status from my_open_task();
reset role; update tasks set status_at = now() - interval '25 hours' where id = current_setting('t.task')::uuid; set role authenticated;
select 'unpaid ride a day later is not open any more: ' || count(*) from my_open_task();
select 'contact a day later: ' || count(*) from contact_for_task(current_setting('t.task')::uuid);
reset role; update tasks set status_at = now() where id = current_setting('t.task')::uuid; set role authenticated;
select 'paid: ' || (advance_task(current_setting('t.task')::uuid, 'PAID', null, 'UPI')).status;
select 'paid with: ' || paid_with from tasks_geo where id = current_setting('t.task')::uuid;
select 'open tasks after paying: ' || count(*) from my_open_task();
select review((select listing_id from task_driver(current_setting('t.task')::uuid)), current_setting('t.task')::uuid, null, 1, 'Safe driving, on time');
select 'driver listing trust now +' || trust_up from listings where title = 'Suresh Auto';
select 'review the same trip again -> ' || pg_temp.expect_fail(format($$select review(%L, %L, null, 1, 'again')$$, (select listing_id from task_driver(current_setting('t.task')::uuid)), current_setting('t.task')), 'already reviewed');
reset role;
select 'a duplicate row is refused by the table too -> ' || pg_temp.expect_fail(format($$insert into reviews (listing_id, author_id, task_id, vote, comment) select listing_id, author_id, task_id, 1, 'x' from reviews where task_id = %L$$, current_setting('t.task')), 'duplicate key');
set role authenticated;
select 'driver listing trust still +' || trust_up from listings where title = 'Suresh Auto';

\echo '== 4b. A driver cannot take his own request, nor review his own listing'
select pg_temp.as_user('suresh');
select set_config('t.own', (request_ride('AUTO', 12.9260, 77.5940, 'Jayanagar', 12.9757, 77.6063, 'MG Road', 7.2, 106)).id::text, false) is not null;
select 'rung for his own request: ' || count(*) from open_tasks_near(12.9260, 77.5940) where id = current_setting('t.own')::uuid;
select 'claims his own request: ' || claim_task(current_setting('t.own')::uuid);
select 'cancel: ' || (advance_task(current_setting('t.own')::uuid, 'CANCELLED')).status;
-- A trip where he was both customer and driver (possible before claim_task refused it) still can't feed his own trust.
reset role;
insert into tasks (type, requester_id, driver_id, vehicle_kind, pickup, drop_at, km, fare, status)
  values ('RIDE', pg_temp.pid('suresh'), pg_temp.pid('suresh'), 'AUTO', geo(12.9260, 77.5940), geo(12.9757, 77.6063), 7.2, 106, 'PAID') returning set_config('t.self', id::text, false) is not null;
set role authenticated;
select 'reviews his own listing from that trip -> ' || pg_temp.expect_fail(format($$select review(%L, %L, null, 1, 'great')$$, (select id from listings where title = 'Suresh Auto'), current_setting('t.self')), 'your own listing');

\echo '== 4c. A driver hands a trip back after 3 minutes: it rings again for the full window'
select pg_temp.as_user('kavya');
select set_config('t.back', (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar', 12.9757, 77.6063, 'MG Road', 7.2, 106)).id::text, false) is not null;
select pg_temp.as_user('suresh'); select 'claim: ' || claim_task(current_setting('t.back')::uuid);
reset role; update tasks set created_at = now() - interval '5 minutes', status_at = now() - interval '4 minutes' where id = current_setting('t.back')::uuid; set role authenticated;
select 'hand back: ' || (advance_task(current_setting('t.back')::uuid, 'SEARCHING')).status;
select 'rings again after the hand-back: ' || count(*) from open_tasks_near(12.9260, 77.5940) where id = current_setting('t.back')::uuid;
select pg_temp.as_user('kavya');
select 'customer''s my_open_task after the hand-back: ' || status from my_open_task();
select 'cancel: ' || (advance_task(current_setting('t.back')::uuid, 'CANCELLED')).status;

\echo '== 5. Cancel while searching; a stale SEARCHING task is not "open" any more'
select set_config('t.task2', (request_ride('CAB', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 112)).id::text, false) is not null;
select 'cancel: ' || (advance_task(current_setting('t.task2')::uuid, 'CANCELLED')).status;
select 'open after cancel: ' || count(*) from my_open_task();
select set_config('t.task3', (request_ride('CAB', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 112)).id::text, false) is not null;
select 'fresh SEARCHING is open: ' || count(*) from my_open_task();
reset role; update tasks set created_at = now() - interval '4 minutes', status_at = now() - interval '4 minutes' where id = current_setting('t.task3')::uuid; set role authenticated;
select 'stale SEARCHING is not: ' || count(*) from my_open_task();
select 'no driver: ' || (advance_task(current_setting('t.task3')::uuid, 'NO_DRIVER')).status;

\echo '== 6. Delivery task shows the item count to the bike rider; the buyer follows it'
select pg_temp.as_user('nobody');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Kavya Stores', 'Grocery', 'Jayanagar', geo(12.9240, 77.5930));
reset role; update listings set status = 'LIVE', online = true where title = 'Kavya Stores'; set role authenticated;
insert into items (listing_id, name, price, unit) select id, 'Sugar 1kg', 48, '1 kg' from listings where title = 'Kavya Stores';
select pg_temp.as_user('kavya');
select set_config('t.order', place_order((select id from listings where title = 'Kavya Stores'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Sugar 1kg'), 'qty', 3)), 12.9300, 77.5900, 'Kavya home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('nobody'); select respond_order(current_setting('t.order')::uuid, true);
select pg_temp.as_user('ravi');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'BIKE', 'Honda Activa', 'KA05CD0002');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA05CD0002'; set role authenticated;   -- only checked vehicles may go online (manage.sql)
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'BIKE', true, geo(12.9245, 77.5935) from vehicles where plate = 'KA05CD0002';
select 'bike rung for: ' || type || ' from ' || pickup_label || ' to ' || drop_label || ', PIN ''' || pin || '''' from open_tasks_near(12.9245, 77.5935);
select 'rider sees ' || order_items || ' items, shop at ' || round(pickup_lat::numeric, 4) || ',' || round(pickup_lng::numeric, 4) || ', PIN ''' || pin || '''' from tasks_geo where order_id = current_setting('t.order')::uuid;
\echo '-- a bike cannot go online as an auto: presence kind comes from the vehicle'
update driver_presence set kind = 'AUTO' where profile_id = me();
select 'bike presence after claiming AUTO: ' || kind from driver_presence where profile_id = me();
select pg_temp.as_user('suresh'); select 'auto driver rung for the delivery: ' || count(*) from open_tasks_near(12.9245, 77.5935);
select pg_temp.as_user('ravi'); select 'claim delivery: ' || claim_task((select id from tasks_geo where order_id = current_setting('t.order')::uuid));
select pg_temp.as_user('kavya');
select 'buyer follows: ' || status || ' rider ' || (select name from task_driver(t.id)) || ' on ' || (select plate from task_driver(t.id)) || ', PIN ' || length(pin) || ' digits' from tasks_geo t where order_id = current_setting('t.order')::uuid;
select 'buyer my_open_task is the delivery: ' || type from my_open_task();

\echo '== 7. Deleting an account: presence, phone and UPI link go, open requests are cancelled, the profile is anonymised'
select pg_temp.as_user('leaving'); select (public.ensure_profile('Leaving User', '9000000025')).id is not null;
select set_config('t.leaver', me()::text, false) is not null;
update profile_private set upi_uri = 'upi://pay?pa=leaving@okaxis' where profile_id = me();
insert into vehicles (owner_id, kind, model, plate) values (me(), 'CAB', 'Dzire', 'KA09EF0003');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA09EF0003'; set role authenticated;
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'CAB', true, geo(12.9250, 77.5940) from vehicles where plate = 'KA09EF0003';
select set_config('t.gone', (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar', 12.9352, 77.6245, 'Koramangala', 5.1, 81)).id::text, false) is not null;
insert into posts (author_id, body, visibility) values (me(), 'Selling my old cycle', 'PUBLIC');
insert into moments (author_id, media_path, caption, audience) values (me(), me()::text || '/m.jpg', 'Sunset', 'SYNCED');
select set_config('t.leaverchat', start_listing_chat((select id from listings where title = 'Kavya Stores'))::text, false) is not null;
insert into messages (conversation_id, sender_id, body) values (current_setting('t.leaverchat')::uuid, me(), 'Is the sugar in stock?');
select delete_my_account();
select 'signed-in calls afterwards -> ' || pg_temp.expect_fail($$select delete_my_account()$$, 'not signed in');
reset role;
select 'profile: status ' || status || ', name ''' || name || ''', sign-in kept: ' || (auth_uid = 'leaving') from profiles where id = current_setting('t.leaver')::uuid;
select 'phone and UPI rows left: ' || count(*) from profile_private where profile_id = current_setting('t.leaver')::uuid;
select 'presence rows left: ' || count(*) from driver_presence where profile_id = current_setting('t.leaver')::uuid;
select 'open request: ' || status from tasks where id = current_setting('t.gone')::uuid;
select 'posts and moments left: ' || (select count(*) from posts where author_id = current_setting('t.leaver')::uuid) || ' / ' || (select count(*) from moments where author_id = current_setting('t.leaver')::uuid);
select 'messages kept for the shop but blanked: ' || count(*) || ', with text ' || count(*) filter (where body <> '') from messages where sender_id = current_setting('t.leaver')::uuid;
select 'chats still joined: ' || count(*) from conversation_members where profile_id = current_setting('t.leaver')::uuid;
set role authenticated;
select pg_temp.as_user('kavya'); select 'map sees the deleted driver: ' || count(*) from online_drivers_near(12.9250, 77.5940) where name = 'Leaving User';
select pg_temp.as_user('leaving'); select 'signing up again with the same number starts a new profile: ' || ((public.ensure_profile('New Me', '9000000025')).id <> current_setting('t.leaver')::uuid);
