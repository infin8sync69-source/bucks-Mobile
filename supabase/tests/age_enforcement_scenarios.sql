\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.expect_ok(sql text, label text) returns text language plpgsql as $$
begin execute sql; return 'ok ' || label; exception when others then return 'FAIL ' || label || ': ' || sqlerrm; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;

-- run_all.sh switches the age rules off for the older suites; this suite tests them, so on again.
update public.settings set value = 1 where key = 'enforce_age';

set role authenticated;
select pg_temp.as_user('nodob'); select (public.ensure_profile('Nadia', '9000000201')).id is not null;
select pg_temp.as_user('adult'); select (public.ensure_profile('Arun', '9000000202')).id is not null;
select pg_temp.as_user('teen');  select (public.ensure_profile('Tanvi', '9000000203')).id is not null;
reset role;
update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('nodob', 'adult', 'teen');
set role authenticated;

\echo '== 1. No date of birth: nothing can be published, ordered or booked'
select pg_temp.as_user('nodob');
select 'post -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, visibility) values (me(), 'hello', 'PUBLIC')$$, 'date of birth');
select 'vehicle -> ' || pg_temp.expect_fail($$insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01AE0001')$$, 'date of birth');
select 'ride -> ' || pg_temp.expect_fail($$select request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 7.5, 111)$$, 'date of birth');

\echo '== 2. Adult: allowed once the date of birth is set'
select pg_temp.as_user('adult');
select set_birth_date((current_date - interval '30 years')::date) = 'ADULT';
select pg_temp.expect_ok($$insert into posts (author_id, body, visibility) values (me(), 'hello from an adult', 'PUBLIC')$$, 'adult posts');
select pg_temp.expect_ok($$insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01AE0002')$$, 'adult adds a vehicle');

\echo '== 3. Teen without guardian consent: blocked; with consent: social allowed, adult-only things still refused'
select pg_temp.as_user('teen');
select set_birth_date((current_date - interval '15 years')::date) = 'TEEN';
select 'teen post before consent -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, visibility) values (me(), 'hi', 'SYNCED')$$, 'guardian');
select record_guardian_consent('Ravi Kumar', '+91 98450 00000', 'parent');
select pg_temp.expect_ok($$insert into posts (author_id, body, visibility) values (me(), 'hi after consent', 'SYNCED')$$, 'teen posts after consent');
select 'teen vehicle -> ' || pg_temp.expect_fail($$insert into vehicles (owner_id, kind, model, plate) values (me(), 'BIKE', 'Activa', 'KA01AE0003')$$, '18 and over');
select 'teen ride -> ' || pg_temp.expect_fail($$select request_ride('AUTO', 12.9250, 77.5938, 'A', 12.9757, 77.6063, 'B', 7.5, 111)$$, '18 and over');
select 'teen business page -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title, category) values ('BUSINESS', me(), 'Tanvi Tiffins', 'FOOD')$$, '18 and over');

\echo '== 4. Switch off: everything passes again (emergency kill switch)'
reset role;
update public.settings set value = 0 where key = 'enforce_age';
set role authenticated;
select pg_temp.as_user('nodob');
select pg_temp.expect_ok($$insert into posts (author_id, body, visibility) values (me(), 'switch off', 'PUBLIC')$$, 'kill switch lets a post through');
