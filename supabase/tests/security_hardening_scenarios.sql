\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.expect_ok(sql text, label text) returns text language plpgsql as $$
begin execute sql; return 'ok ' || label; exception when others then return 'FAIL ' || label || ': ' || sqlerrm; end $$;
create or replace function pg_temp.try(sql text) returns text language plpgsql as $$ begin execute sql; return 'tried'; exception when others then return 'tried'; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql security definer as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;

-- run_all.sh relaxes these rules for the older suites; this suite tests them, so back to the migration's values.
update public.settings set value = 1 where key = 'rate_limits_on';
update public.settings set value = 7 where key = 'recommend_home_cooldown_days';
update public.settings set value = 500 where key = 'listing_blur_m';
update public.settings set value = 300 where key = 'drivers_map_blur_m';
update public.settings set value = 1.2 where key = 'ride_min_km_factor';
update public.settings set value = 0 where key = 'recommender_min_account_days';
revoke select (auth_uid) on public.profiles from authenticated;

set role authenticated;
select pg_temp.as_user('owner');  select (public.ensure_profile('Asha', '9000000301')).id is not null;
select pg_temp.as_user('poster'); select (public.ensure_profile('Priya', '9000000302')).id is not null;
select pg_temp.as_user('driver'); select (public.ensure_profile('Dinesh', '9000000303')).id is not null;
select pg_temp.as_user('rec1');   select (public.ensure_profile('Ravi', '9000000304')).id is not null;
select pg_temp.as_user('rec2');   select (public.ensure_profile('Rekha', '9000000305')).id is not null;
select pg_temp.as_user('rec3');   select (public.ensure_profile('Rohan', '9000000306')).id is not null;
reset role;
update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('owner', 'poster', 'driver', 'rec1', 'rec2', 'rec3');
set role authenticated;

\echo '== 1. Rate limits: per person per hour, deleting does not give the count back, system writes pass'
reset role; update public.settings set value = 2 where key = 'rate_posts_per_hour'; set role authenticated;
select pg_temp.as_user('poster');
select pg_temp.expect_ok($$insert into posts (author_id, body, visibility) values (me(), 'one', 'PUBLIC')$$, 'first post');
select pg_temp.expect_ok($$insert into posts (author_id, body, visibility) values (me(), 'two', 'PUBLIC')$$, 'second post');
select 'third post -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, visibility) values (me(), 'three', 'PUBLIC')$$, 'slow down');
reset role; delete from posts where body = 'two'; set role authenticated;
select 'after deleting one -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, visibility) values (me(), 'four', 'PUBLIC')$$, 'slow down');
reset role;
select set_config('request.jwt.claims', '{}', false);
select pg_temp.expect_ok(format($$insert into posts (author_id, body, visibility) values (%L, 'system', 'PUBLIC')$$, pg_temp.pid('poster')), 'a write with no caller is never limited');
update public.settings set value = 30 where key = 'rate_posts_per_hour';
set role authenticated;

\echo '== 2. Ride requests: request then cancel cannot loop'
reset role; update public.settings set value = 1 where key = 'rate_rides_per_hour'; set role authenticated;
select pg_temp.as_user('rec3');
select pg_temp.expect_ok($$select request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 7.5, 111)$$, 'first ride request');
reset role; update tasks set status = 'CANCELLED' where requester_id = pg_temp.pid('rec3'); set role authenticated;
select 'second request in the hour -> ' || pg_temp.expect_fail($$select request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 7.5, 111)$$, 'slow down');
reset role; update public.settings set value = 15 where key = 'rate_rides_per_hour'; set role authenticated;

\echo '== 3. Fare floor: a trip length under 1.2x the straight line is replaced by 1.3x'
select pg_temp.as_user('rec2');
select pg_temp.check('short p_km not trusted', (select km > 6 from request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 4.0, 60)));
reset role; update tasks set status = 'CANCELLED' where requester_id = pg_temp.pid('rec2'); delete from rate_events; set role authenticated;
select pg_temp.check('a plausible road distance is kept', (select km = 7.5 from request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 7.5, 111)));
reset role; update tasks set status = 'CANCELLED' where requester_id = pg_temp.pid('rec2'); set role authenticated;

\echo '== 4. Drivers on the map: blurred pins, no name, plate or real id; rate-limited'
select pg_temp.as_user('driver');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01SH0001');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01SH0001'; set role authenticated;
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'AUTO', true, geo(12.92613, 77.59427) from vehicles where plate = 'KA01SH0001';
select pg_temp.as_user('poster');
select pg_temp.check('driver is shown', (select count(*) = 1 from online_drivers_near(12.9255, 77.5935, 5000)));
select pg_temp.check('no name or plate', (select name = '' and plate = '' from online_drivers_near(12.9255, 77.5935, 5000)));
reset role;
select pg_temp.check('id is a pseudonym', (select d.profile_id <> pg_temp.pid('driver') from (select * from online_drivers_near(12.9255, 77.5935, 5000)) d)) ;
set role authenticated; select pg_temp.as_user('poster');
select pg_temp.check('position is snapped, not exact', (select abs(lat - 12.92613) > 0.0001 or abs(lng - 77.59427) > 0.0001 from online_drivers_near(12.9255, 77.5935, 5000)));
reset role; update public.settings set value = 4 where key = 'rate_drivers_map_per_hour'; set role authenticated;
select 'fifth map refresh in the hour -> ' || pg_temp.expect_fail($$select * from online_drivers_near(12.9255, 77.5935, 5000)$$, 'slow down');
reset role; update public.settings set value = 720 where key = 'rate_drivers_map_per_hour'; set role authenticated;

\echo '== 5. Skill pages are stored on a ~500 m grid; the exact point is the owner''s alone; shops stay exact'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, service) values ('SKILL', me(), 'Asha tutoring', 'Tutor', 'Jayanagar', geo(12.92613, 77.59427), 'FOOD');
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Asha Biryani', 'Restaurant', 'Biryani', 'JP Nagar', geo(12.9063, 77.5857), '{}');
reset role;
select pg_temp.check('skill page location snapped', (select st_distance(location, geo(12.92613, 77.59427)) > 5 from listings where title = 'Asha tutoring'));
select pg_temp.check('exact point kept privately', (select st_distance(e.location, geo(12.92613, 77.59427)) < 1 from listing_exact_location e join listings l on l.id = e.listing_id where l.title = 'Asha tutoring'));
select pg_temp.check('shop stays exact', (select st_distance(location, geo(12.9063, 77.5857)) < 1 from listings where title = 'Asha Biryani'));
set role authenticated;
select pg_temp.as_user('owner');
select pg_temp.check('owner reads the exact point', (select count(*) = 1 from listing_exact_location));
select pg_temp.as_user('poster');
select pg_temp.check('others do not', (select count(*) = 0 from listing_exact_location));

\echo '== 6. Recommendations: one recommender per code, cooldown after moving home, per-page hourly cap'
reset role; update listings set status = 'LIVE' where title = 'Asha Biryani'; set role authenticated;
select pg_temp.as_user('owner');
select set_config('t.tok', recommend_token(id), false) is not null from listings where title = 'Asha Biryani';
select pg_temp.as_user('rec1');
select pg_temp.expect_ok(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'first recommender (home set once, no cooldown)');
select pg_temp.as_user('rec2');
select 'second person, same code -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'expired');
update profiles set home = geo(12.9300, 77.6000) where id = me();
select pg_temp.check('a home move is recorded', (select home_changed_at is not null from profiles where id = me()));
-- Clearing the stamp by hand either isn't allowed or is ignored by the trigger; either way it stays.
select pg_temp.try($$update profiles set home_changed_at = null where id = me()$$);
select pg_temp.check('the move stamp can''t be cleared by hand', (select home_changed_at is not null from profiles where id = me()));
reset role; update profiles set home = geo(12.9063, 77.5857) where auth_uid = 'rec2'; set role authenticated;
select pg_temp.as_user('owner');
select set_config('t.tok', recommend_token(id), false) is not null from listings where title = 'Asha Biryani';
select pg_temp.as_user('rec2');
select 'moved home recently -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'changed where you live');
reset role; update public.settings set value = 1 where key = 'recommend_per_listing_per_hour'; set role authenticated;
select pg_temp.as_user('rec3');
select 'page cap reached -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'last hour');

\echo '== 7. The Firebase id is private'
select pg_temp.as_user('poster');
select 'read auth_uid -> ' || pg_temp.expect_fail($$select auth_uid from profiles limit 1$$, 'permission denied');
select pg_temp.check('names still readable', (select count(*) >= 6 from (select id, name from profiles) p));

\echo '== 8. Reports keep what was reported'
select pg_temp.as_user('owner');
select report_content('POST', (select id from posts where body = 'one'), 'SPAM') is not null;
reset role; update posts set body = 'edited away' where body = 'one'; set role authenticated;
select pg_temp.check('snapshot keeps the original text', (select snapshot like 'one%' from reports where reporter_id = me()));
