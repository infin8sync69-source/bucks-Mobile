-- guardian_gate.sql: a minor can't post, message or order until a guardian agrees; vehicles are for adults only.
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;

set role authenticated;
select pg_temp.as_user('ga'); select (public.ensure_profile('Gita Adult', '9000000901')).id is not null; select set_birth_date('1990-05-05') = 'ADULT';
select pg_temp.as_user('gt'); select (public.ensure_profile('Gopal Teen', '9000000902')).id is not null; select set_birth_date((current_date - interval '15 years')::date) = 'TEEN';

\echo '== 1. A teen without consent is held at the guardian step'
select pg_temp.as_user('gt');
select 'post -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, visibility) values (me(), 'Hi all', 'PUBLIC')$$, 'parent or guardian');
select 'moment -> ' || pg_temp.expect_fail($$insert into moments (author_id, media_path) values (me(), 'gt/1.jpg')$$, 'parent or guardian');
select 'vehicle -> ' || pg_temp.expect_fail($$insert into vehicles (owner_id, kind, plate) values (me(), 'BIKE', 'KA01GT0001')$$, '18 or over');

\echo '== 2. After consent the teen can post, but still can''t add a vehicle'
select record_guardian_consent('Ravi Kumar', '+91 98450 00003', 'PARENT');
insert into posts (author_id, body, visibility) values (me(), 'Hi all', 'PUBLIC');
select pg_temp.check('teen post saved after consent', exists (select 1 from posts where body = 'Hi all'));
select 'vehicle after consent -> ' || pg_temp.expect_fail($$insert into vehicles (owner_id, kind, plate) values (me(), 'BIKE', 'KA01GT0002')$$, '18 or over');

\echo '== 3. Adults are never gated'
select pg_temp.as_user('ga');
insert into posts (author_id, body, visibility) values (me(), 'Adult hello', 'PUBLIC');
insert into vehicles (owner_id, kind, plate) values (me(), 'AUTO', 'KA01GA0001');
select pg_temp.check('adult post and vehicle saved', exists (select 1 from posts where body = 'Adult hello') and exists (select 1 from vehicles where plate = 'KA01GA0001'));
