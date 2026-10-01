\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Contact links: private notes about a synced person.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.code(u text) returns text language sql as $$ select short_code from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;

set role authenticated;
select pg_temp.as_user('a'); select (public.ensure_profile('Asha', '9000000081')).id is not null;
select pg_temp.as_user('b'); select (public.ensure_profile('Bala', '9000000082')).id is not null;
select pg_temp.as_user('c'); select (public.ensure_profile('Chitra', '9000000083')).id is not null;
select pg_temp.as_user('a'); select request_sync((select id from profiles where short_code = pg_temp.code('b')));
select pg_temp.as_user('b'); update syncs set status = 'ACCEPTED' where addressee_id = me();

\echo '== 1. Attach details to a synced person'
select pg_temp.as_user('a');
insert into contact_links (owner_id, profile_id, phones, emails, org, title, address, note)
  values (me(), pg_temp.pid('b'), '["+91 98450 12345"]', '["bala@example.com"]', 'Bala Electricals', 'Owner', 'JP Nagar 2nd Phase', 'Met at the market');
select pg_temp.check((select org from contact_links where profile_id = pg_temp.pid('b')) = 'Bala Electricals', 'the owner reads it back');
select pg_temp.check((select phones->>0 from contact_links) = '+91 98450 12345', 'with the number');
update contact_links set note = 'Cousin of Ravi', org = 'Bala Power' where profile_id = pg_temp.pid('b');
select pg_temp.check((select note from contact_links) = 'Cousin of Ravi', 'and can edit it');
select pg_temp.check((select updated_at > now() - interval '1 minute' from contact_links), 'edits are timestamped');

\echo '== 2. Private: nobody else sees it, edits it or deletes it'
select pg_temp.as_user('b');
select pg_temp.check((select count(*) from contact_links) = 0, 'the person it is about can''t see it');
with d as (delete from contact_links returning 1) select pg_temp.check((select count(*) from d) = 0, 'or delete it');
select pg_temp.as_user('c');
select pg_temp.check((select count(*) from contact_links) = 0, 'a stranger can''t see it');

\echo '== 3. Rules'
select pg_temp.as_user('a');
select 'not synced -> ' || pg_temp.expect_fail(format($$insert into contact_links (owner_id, profile_id) values (me(), %L)$$, pg_temp.pid('c')), 'synced with');
select 'about yourself -> ' || pg_temp.expect_fail($$insert into contact_links (owner_id, profile_id) values (me(), me())$$, 'synced with');
select 'for someone else -> ' || pg_temp.expect_fail(format($$insert into contact_links (owner_id, profile_id) values (%L, %L)$$, pg_temp.pid('c'), pg_temp.pid('b')), 'synced with');
select '6 numbers -> ' || pg_temp.expect_fail($$update contact_links set phones = '["1","2","3","4","5","6"]'$$, 'contact_links');
select 'a number that is not text -> ' || pg_temp.expect_fail($$update contact_links set phones = '[123]'$$, 'contact_links');
select 'long note -> ' || pg_temp.expect_fail($$update contact_links set note = repeat('x', 501)$$, 'contact_links');
select 'move it to another person -> ' || pg_temp.expect_fail(format($$update contact_links set profile_id = %L$$, pg_temp.pid('c')), 'permission denied');

\echo '== 4. After an unsync the notes stay; after the person deletes their account they go'
select pg_temp.as_user('b'); delete from syncs where addressee_id = me() or requester_id = me();
select pg_temp.as_user('a');
select pg_temp.check((select count(*) from contact_links) = 1, 'unsyncing does not erase your notes');
with u as (update contact_links set note = 'Still mine' returning 1) select pg_temp.check((select count(*) from u) = 1, 'you can still edit them after an unsync');
reset role; select set_config('request.jwt.claims', '{}', false); delete from profiles where auth_uid = 'b'; set role authenticated; select pg_temp.as_user('a');
select pg_temp.check((select count(*) from contact_links) = 0, 'deleting their account removes what you attached to it');
