\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
-- Near Hindupur (a tier 3 town).
create or replace function pg_temp.hits(q text) returns setof text language sql as $$ select source || ':' || name from public.search_places(q, 13.83, 77.49) $$;

insert into localities (name, district, state, pincode, lat, lng) values
  ('Peddakotla', 'Anantapur', 'Andhra Pradesh', '515631', 14.5689, 77.85624),
  ('Kotnur', 'Anantapur', 'Andhra Pradesh', '515201', 13.85, 77.50),
  ('Kotnuru', 'Nellore', 'Andhra Pradesh', '524001', 14.40, 79.90),
  ('Hindupur Bazar', 'Anantapur', 'Andhra Pradesh', '515201', 13.829, 77.491);
set role authenticated;
select pg_temp.as_user('pa'); select (public.ensure_profile('Pin Pavan', '9000000701')).id is not null;
select pg_temp.as_user('pb'); select (public.ensure_profile('Blocked Bala', '9000000702')).id is not null;
select pg_temp.as_user('pa');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Kotnur Kirana', 'Grocery', 'Kotnur', geo(13.851, 77.501));
reset role; update listings set status = 'LIVE' where title = 'Kotnur Kirana'; set role authenticated;

\echo '== India Post localities: by pincode, by name (nearest first), with small typos'
select pg_temp.check('pincode lists its localities', (select count(*) from search_places('515201', 13.83, 77.49) where source = 'POST') = 2);
select pg_temp.check('by name, the nearest Kotnur first', (select name from search_places('kotnur', 13.83, 77.49) where source = 'POST' limit 1) = 'Kotnur');
select pg_temp.check('a typo still finds it', 'POST:Hindupur Bazar' in (select pg_temp.hits('hindupr bazar')));
select pg_temp.check('a typo doesn''t bring look-alikes from far away', 'POST:Kotnuru' not in (select pg_temp.hits('kotnru')) and 'POST:Kotnur' in (select pg_temp.hits('kotnru')));
select pg_temp.check('the detail names the district, state and pincode', (select detail from search_places('peddakotla', 13.83, 77.49) limit 1) = 'Anantapur, Andhra Pradesh 515631');

\echo '== Bucks first: live pages and the areas they are in'
select pg_temp.check('the shop comes before the post office', (select source from search_places('kotnur', 13.83, 77.49) limit 1) = 'BUCKS');
select pg_temp.check('its area is a place too', 'AREA:Kotnur' in (select pg_temp.hits('kotnur')));

\echo '== Dropping a pin'
select pg_temp.check('added', public.add_place('Sai Baba Temple Ward 12', 13.831, 77.492, 'Hindupur') is not null);
select pg_temp.check('the same name nearby is the same place', public.add_place('sai baba temple ward 12', 13.8311, 77.4921) = public.add_place('Sai Baba Temple Ward 12', 13.831, 77.492));
select pg_temp.check('found by the next person', 'PEOPLE:Sai Baba Temple Ward 12' in (select pg_temp.hits('sai baba')));
select 'outside India -> ' || pg_temp.expect_fail($$select public.add_place('Somewhere', 51.5, -0.1)$$, 'in India');
select 'no name -> ' || pg_temp.expect_fail($$select public.add_place(' ', 13.8, 77.4)$$, 'give the place a name');
select pg_temp.as_user('pb');
insert into blocks (blocker_id, blocked_id) values (me(), (select id from profiles where auth_uid = 'pa'));
select pg_temp.check('not shown across a block', 'PEOPLE:Sai Baba Temple Ward 12' not in (select pg_temp.hits('sai baba')));
select pg_temp.check('a stranger can''t hide it', (select pg_temp.expect_fail($$select public.hide_place(gen_random_uuid())$$, 'staff only') like 'ok%'));

\echo '== Only through the functions'
select pg_temp.check('localities not readable directly', not has_table_privilege('authenticated', 'public.localities', 'select'));
select pg_temp.check('user places not readable directly', not has_table_privilege('authenticated', 'public.user_places', 'select'));
