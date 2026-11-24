\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

set role authenticated;
select pg_temp.as_user('ap'); select (public.ensure_profile('Pinned Priya', '9000000601')).id is not null;
\echo '== A saved address keeps a drop point; only a real one, only for its owner'
insert into addresses (profile_id, label, name, phone, line1, city, state, pincode, lat, lng)
  values (me(), 'Home', 'Priya', '9876500001', '7 Temple Road', 'Mysuru', 'Karnataka', '570001', 12.30, 76.65);
select pg_temp.check('pinned', (select lat = 12.30 and lng = 76.65 from addresses where label = 'Home'));
select 'half a pin -> ' || pg_temp.expect_fail($$update addresses set lng = null where label = 'Home'$$, 'addresses_pin_shape');
select 'outside India -> ' || pg_temp.expect_fail($$update addresses set lat = 51.5, lng = -0.1 where label = 'Home'$$, 'addresses_pin_shape');
update addresses set lat = null, lng = null where label = 'Home';
select pg_temp.check('unpinned is fine', (select lat is null and lng is null from addresses where label = 'Home'));
select pg_temp.as_user('ax'); select (public.ensure_profile('Other Om', '9000000602')).id is not null;
select pg_temp.check('nobody else sees it', (select count(*) from addresses where label = 'Home') = 0);
