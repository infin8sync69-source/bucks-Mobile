\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.code(u text) returns text language sql as $$ select short_code from public.profiles where auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('shop');   select (public.ensure_profile('Asha', '9000000021')).id is not null;
select pg_temp.as_user('helper'); select (public.ensure_profile('Bala', '9000000022')).id is not null;
select pg_temp.as_user('driver'); select (public.ensure_profile('Ravi', '9000000023')).id is not null;
select pg_temp.as_user('other');  select (public.ensure_profile('Meena', '9000000024')).id is not null;

\echo '== 1. A listing invite shows the listing name and inviter to the invitee, who cannot see the pending listing itself'
select pg_temp.as_user('shop');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Asha Stores', 'Grocery', 'JP Nagar', geo(12.9063, 77.5857));
select 'invite sent: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('helper'), 'STORE_RIDER') is not null);
select 'invite yourself -> ' || pg_temp.expect_fail(format('select invite(%L, null, %L, %L)', (select id from listings where title = 'Asha Stores'), pg_temp.code('shop'), 'ADMIN'), 'already own');
select 'unknown Bucks ID -> ' || pg_temp.expect_fail(format('select invite(%L, null, %L, %L)', (select id from listings where title = 'Asha Stores'), 'ZZZZZZZZ', 'ADMIN'), 'no one has');
select pg_temp.as_user('helper');
select 'helper reads the pending listing directly: ' || count(*) || ' rows' from listings where title = 'Asha Stores';
select 'helper my_invites: ' || title || ' (' || kind || ') as ' || role || ' from ' || inviter_name from my_invites();
select pg_temp.as_user('other');
select 'someone else my_invites: ' || count(*) from my_invites();
select pg_temp.as_user('helper');
select respond_invite((select id from my_invites()), true);
select 'after accepting: ' || count(*) || ' pending, role now ' || coalesce(listing_role((select id from listings where title = 'Asha Stores')), '-') from my_invites();
select 'store rider deletes the listing: ' || count(*) from (select 1) x where false; delete from listings where title = 'Asha Stores';
reset role; select 'listing still there: ' || count(*) from listings where title = 'Asha Stores'; set role authenticated;

\echo '== 2. Vehicle invite shows model and plate; only the owner can change documents; admins can drive it'
select pg_temp.as_user('driver');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01AB1111');
update vehicles set docs = '[{"kind": "RC", "path": "x/rc.jpg"}]' where plate = 'KA01AB1111';
select 'owner docs: ' || docs::text from vehicles where plate = 'KA01AB1111';
select 'owner sets ACTIVE -> ' || pg_temp.expect_fail($$update vehicles set status = 'ACTIVE' where plate = 'KA01AB1111'$$, 'managed by Bucks');
select 'store rider on a vehicle -> ' || pg_temp.expect_fail(format('select invite(null, %L, %L, %L)', (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('helper'), 'STORE_RIDER'), 'only have admins');
select 'vehicle invite sent: ' || (invite(null, (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('helper'), 'ADMIN') is not null);
select pg_temp.as_user('helper');
select 'helper my_invites: ' || title || ' (' || kind || ') as ' || role || ' from ' || inviter_name from my_invites();
select respond_invite((select id from my_invites()), true);
select 'helper sees the vehicle: ' || count(*) || ', role ' || vehicle_role(id) from vehicles where plate = 'KA01AB1111' group by id;
select 'helper sees vehicle members: ' || count(*) from vehicle_members where vehicle_id = (select id from vehicles where plate = 'KA01AB1111');
update vehicles set docs = '[]' where plate = 'KA01AB1111';
select 'docs after admin attempt: ' || docs::text from vehicles where plate = 'KA01AB1111';
select 'admin invites someone -> ' || pg_temp.expect_fail(format('select invite(null, %L, %L, %L)', (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('other'), 'ADMIN'), 'only the owner');
select 'admin leaves: ' || count(*) from (select 1) x where false; delete from vehicle_members where vehicle_id = (select id from vehicles where plate = 'KA01AB1111') and profile_id = me();
select 'helper sees the vehicle after leaving: ' || count(*) from vehicles where plate = 'KA01AB1111';

\echo '== 3. Declined and revoked invites disappear; the owner sees pending invites they sent'
select pg_temp.as_user('shop');
select 'invite Ravi as admin: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('driver'), 'ADMIN') is not null);
select 'invite Meena as admin: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('other'), 'ADMIN') is not null);
select 'owner pending invites sent: ' || count(*) from invites where status = 'PENDING' and inviter_id = me();
update invites set status = 'REVOKED' where invitee_id = pg_temp.pid('other') and status = 'PENDING';
select 'owner sets ACCEPTED directly -> ' || pg_temp.expect_fail(format($$update invites set status = 'ACCEPTED' where invitee_id = %L$$, pg_temp.pid('driver')), 'row-level security');
select pg_temp.as_user('other');
select 'Meena after revoke: ' || count(*) from my_invites();
select pg_temp.as_user('driver');
select 'Ravi sees: ' || title || ' as ' || role from my_invites();
select respond_invite((select id from my_invites()), false);
select 'Ravi after declining: ' || count(*) || ' pending, role ' || coalesce(listing_role((select id from listings where title = 'Asha Stores')), 'none') from my_invites();
select 'respond twice -> ' || pg_temp.expect_fail(format('select respond_invite(%L, true)', (select id from invites where invitee_id = pg_temp.pid('driver'))), 'not found');

\echo '== 4. Recommendation counts are readable for the owner''s own pending listing; tokens are not'
select pg_temp.as_user('shop');
select 'token: ' || (recommend_token((select id from listings where title = 'Asha Stores')) is not null);
select 'count: ' || count(*) from recommendations where listing_id = (select id from listings where title = 'Asha Stores');
select 'read tokens -> ' || pg_temp.expect_fail('select count(*) from recommend_tokens', 'permission denied');
