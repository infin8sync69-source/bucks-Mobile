\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.found(q text, title text) returns boolean language sql as $$ select exists (select 1 from public.search_listings(q, 12.9250, 77.5938) s where s.title = found.title) $$;

set role authenticated;
select pg_temp.as_user('qo'); select (public.ensure_profile('Owner Qadir', '9000000501')).id is not null;
select pg_temp.as_user('qs'); select (public.ensure_profile('Searcher Sita', '9000000502')).id is not null;
select pg_temp.as_user('qo');
insert into listings (kind, owner_id, title, category, area, location) values
  ('BUSINESS', me(), 'Lakshmi Kirana', 'Grocery', 'Jayanagar', geo(12.9251, 77.5939)),
  ('SKILL', me(), 'Raju Repairs', 'Electrician', 'Jayanagar', geo(12.9252, 77.5940)),
  ('SKILL', me(), 'Fast Pipes', 'Plumber', 'Jayanagar', geo(12.9253, 77.5941));
insert into items (listing_id, name, price, unit, in_stock) values
  ((select id from listings where title = 'Lakshmi Kirana'), 'Rice, Basmati', 120, '1 kg', true),
  ((select id from listings where title = 'Lakshmi Kirana'), 'Sona Masoori Rice', 60, '1 kg', true),
  ((select id from listings where title = 'Lakshmi Kirana'), 'AA Battery', 20, '1', true);
reset role; update listings set status = 'LIVE' where owner_id = (select id from profiles where auth_uid = 'qo'); set role authenticated;

select pg_temp.as_user('qs');
\echo '== Plurals, typos and everyday words'
select pg_temp.check('plural: plumbers', pg_temp.found('plumbers', 'Fast Pipes'));
select pg_temp.check('plural: batteries', pg_temp.found('batteries', 'Lakshmi Kirana'));
select pg_temp.check('typo: electrecian', pg_temp.found('electrecian', 'Raju Repairs'));
select pg_temp.check('typo: plumbr', pg_temp.found('plumbr', 'Fast Pipes'));
select pg_temp.check('vernacular: bijli wala', pg_temp.found('bijli wala', 'Raju Repairs'));
select pg_temp.check('vernacular: kirana store finds grocery', pg_temp.found('kirana', 'Lakshmi Kirana'));
select pg_temp.check('vernacular: nal wala', pg_temp.found('nal wala', 'Fast Pipes'));
select pg_temp.check('nothing for nonsense', not pg_temp.found('zzqxv', 'Lakshmi Kirana') and not pg_temp.found('zzqxv', 'Fast Pipes'));
select pg_temp.check('a plumber search doesn''t bring the grocer', not pg_temp.found('plumber', 'Lakshmi Kirana'));

\echo '== Products: every word in any order, with that product''s own price'
select pg_temp.check('basmati rice matches "Rice, Basmati"', (select matched_item = 'Rice, Basmati' and matched_price = 120 from search_listings('basmati rice', 12.9250, 77.5938) where title = 'Lakshmi Kirana'));
select pg_temp.check('rice: the cheapest rice and its price', (select matched_item = 'Sona Masoori Rice' and matched_price = 60 and min_price = 20 from search_listings('rice', 12.9250, 77.5938) where title = 'Lakshmi Kirana'));
select pg_temp.check('empty search: no matched product', (select bool_and(matched_item is null and matched_price is null) from search_listings('', 12.9250, 77.5938)));

\echo '== Only through the function'
select pg_temp.check('the word list isn''t readable directly', not has_table_privilege('authenticated', 'public.search_synonyms', 'select'));

\echo '== Call: only when the owner turns it on, never across a block'
select pg_temp.check('off by default: no number', public.listing_phone((select id from listings where title = 'Fast Pipes')) is null);
reset role; update listings set details = details || '{"show_phone": true}' where title = 'Fast Pipes'; set role authenticated;
select pg_temp.check('on: the owner''s verified number', public.listing_phone((select id from listings where title = 'Fast Pipes')) like '%9000000501');
insert into blocks (blocker_id, blocked_id) values (me(), (select id from profiles where auth_uid = 'qo'));
select pg_temp.check('blocked: no number', public.listing_phone((select id from listings where title = 'Fast Pipes')) is null);
