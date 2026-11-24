\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- content_screen.sql: screened goods never reach another user (search, store page, posts, orders); halal look-alikes stay visible;
-- the owner sees their own listing as before; the term list is not readable from the app.
create or replace function pg_temp.as_phone(u text, ph text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'phone_number', ph)::text, false) $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.found(q text, title text) returns boolean language sql as $$ select exists (select 1 from public.search_listings(q, 12.9250, 77.5938) s where s.title = found.title) $$;
create or replace function pg_temp.lid(t text) returns uuid language sql as $$ select id from public.listings where title = t $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

set role authenticated;
select pg_temp.as_phone('so', '9000000601'); select (public.ensure_profile('Owner Salim', '9000000601')).id is not null;
select pg_temp.as_phone('sb', '9000000602'); select (public.ensure_profile('Buyer Bindu', '9000000602')).id is not null;
select pg_temp.as_user('so');
insert into listings (kind, owner_id, title, category, description, area, location) values
  ('BUSINESS', me(), 'Coorg Pandi Point', 'Restaurant', 'Pork fry and pandi curry', 'Gonikoppal', geo(12.9251, 77.5939)),
  ('BUSINESS', me(), 'Spirits Corner', 'Wine shop', 'Beer, whisky and rum', 'Gonikoppal', geo(12.9252, 77.5940)),
  ('BUSINESS', me(), 'Green Leaf Corner', 'General store', 'Ganja and weed available', 'Gonikoppal', geo(12.9253, 77.5941)),
  ('BUSINESS', me(), 'Halal Chicken Centre', 'Meat shop', 'Fresh halal chicken. 100% halal, no pork.', 'Gonikoppal', geo(12.9254, 77.5942)),
  ('BUSINESS', me(), 'Burger Hub', 'Restaurant', 'Burgers and shakes', 'Gonikoppal', geo(12.9255, 77.5943)),
  ('BUSINESS', me(), 'Lakshmi Kirana', 'Grocery', 'Daily needs', 'Gonikoppal', geo(12.9256, 77.5944)),
  ('BUSINESS', me(), 'Silk House', 'Clothing', 'Sarees and kurtis', 'Gonikoppal', geo(12.9257, 77.5945));
insert into items (listing_id, name, price, unit, in_stock) values
  (pg_temp.lid('Coorg Pandi Point'), 'Pandi curry', 320, 'plate', true),
  (pg_temp.lid('Halal Chicken Centre'), 'Halal chicken curry cut', 240, '1 kg', true),
  (pg_temp.lid('Burger Hub'), 'Chicken hamburger', 150, '1', true),
  (pg_temp.lid('Lakshmi Kirana'), 'Basmati rice', 120, '1 kg', true),
  (pg_temp.lid('Lakshmi Kirana'), 'Kingfisher beer', 180, '650 ml', true),
  (pg_temp.lid('Lakshmi Kirana'), 'Weed killer', 450, '1 l', true),
  (pg_temp.lid('Silk House'), 'Wine red silk saree', 2400, '1', true);
insert into posts (author_id, body, visibility) values (me(), 'Fresh pork fry today at the Point', 'PUBLIC'), (me(), 'Fresh halal chicken today', 'PUBLIC');
reset role; update listings set status = 'LIVE', online = true where owner_id = (select id from profiles where auth_uid = 'so'); set role authenticated;

select pg_temp.as_user('sb');
\echo '== Search: pork, alcohol and weed listings are not found by another user'
select pg_temp.check('pork listing hidden ("pork")', not pg_temp.found('pork', 'Coorg Pandi Point'));
select pg_temp.check('pork listing hidden ("pandi curry")', not pg_temp.found('pandi curry', 'Coorg Pandi Point'));
select pg_temp.check('alcohol listing hidden ("whisky")', not pg_temp.found('whisky', 'Spirits Corner'));
select pg_temp.check('alcohol listing hidden ("wine shop")', not pg_temp.found('wine shop', 'Spirits Corner'));
select pg_temp.check('weed listing hidden ("ganja")', not pg_temp.found('ganja', 'Green Leaf Corner'));
select pg_temp.check('none of them in a browse with no words',
  not exists (select 1 from search_listings('', 12.9250, 77.5938) where title in ('Coorg Pandi Point', 'Spirits Corner', 'Green Leaf Corner')));

\echo '== Search: halal look-alikes stay visible'
select pg_temp.check('halal chicken shop found ("chicken")', pg_temp.found('chicken', 'Halal Chicken Centre'));
select pg_temp.check('"no pork" does not screen the halal shop', pg_temp.found('halal', 'Halal Chicken Centre'));
select pg_temp.check('hamburger found with its own item', (select matched_item = 'Chicken hamburger' from search_listings('hamburger', 12.9250, 77.5938) where title = 'Burger Hub'));
select pg_temp.check('weed killer found at the grocer', (select matched_item = 'Weed killer' from search_listings('weed killer', 12.9250, 77.5938) where title = 'Lakshmi Kirana'));
select pg_temp.check('wine red saree found at the silk shop', (select matched_item = 'Wine red silk saree' from search_listings('saree', 12.9250, 77.5938) where title = 'Silk House'));

\echo '== Items: the grocer stays, its beer does not'
select pg_temp.check('grocer found for rice', pg_temp.found('rice', 'Lakshmi Kirana'));
select pg_temp.check('beer is never the matched item', not exists (select 1 from search_listings('beer', 12.9250, 77.5938) where matched_item ilike '%beer%'));
select pg_temp.check('beer price is not the "from" price', (select min_price = 120 from search_listings('', 12.9250, 77.5938) where title = 'Lakshmi Kirana'));
select pg_temp.check('store page: beer is not in the item list', not exists (select 1 from items where name = 'Kingfisher beer'));
select pg_temp.check('store page: rice and weed killer are', (select count(*) = 2 from items where listing_id = pg_temp.lid('Lakshmi Kirana')));

\echo '== Direct reads, posts and orders'
select pg_temp.check('pork shop page is not readable', not exists (select 1 from listings where title = 'Coorg Pandi Point'));
select pg_temp.check('its items are not readable', not exists (select 1 from items where name = 'Pandi curry'));
select pg_temp.check('pork post hidden, halal post visible',
  not exists (select 1 from posts where body like '%pork%') and exists (select 1 from posts where body like '%halal chicken%'));
select pg_temp.check('pork post not in explore', not exists (select 1 from explore('ALL', 'pork', 60)));
reset role;
select set_config('t.kirana', (select id from listings where title = 'Lakshmi Kirana')::text, false) is not null,
       set_config('t.beer', (select id from items where name = 'Kingfisher beer')::text, false) is not null,
       set_config('t.rice', (select id from items where name = 'Basmati rice')::text, false) is not null;
set role authenticated; select pg_temp.as_user('sb');
select pg_temp.expect_fail($$select place_order(current_setting('t.kirana')::uuid, jsonb_build_array(jsonb_build_object('item_id', current_setting('t.beer'), 'qty', 1)), 12.9256, 77.5944, '', 'UPI', 'PICKUP')$$,
                           'an item is no longer available');
select pg_temp.check('an order for rice still goes through',
  place_order(current_setting('t.kirana')::uuid, jsonb_build_array(jsonb_build_object('item_id', current_setting('t.rice'), 'qty', 1)), 12.9256, 77.5944, '', 'UPI', 'PICKUP') is not null);

\echo '== The owner sees their own'
select pg_temp.as_user('so');
select pg_temp.check('owner reads their pork listing', exists (select 1 from listings where title = 'Coorg Pandi Point'));
select pg_temp.check('owner reads their beer item', exists (select 1 from items where name = 'Kingfisher beer'));
select pg_temp.check('owner finds their own listing in search', pg_temp.found('pork', 'Coorg Pandi Point'));
select pg_temp.check('author sees their own post', exists (select 1 from posts where body like '%pork%'));

\echo '== The list is private and edits take effect at once'
select pg_temp.check('term list not readable from the app', not has_table_privilege('authenticated', 'public.content_screen_terms', 'select'));
select pg_temp.check('screened ids not readable from the app', not has_table_privilege('authenticated', 'public.content_screened', 'select'));
select pg_temp.check('matcher not callable from the app', not has_function_privilege('authenticated', 'public.screen_hit(text, text)', 'execute'));
reset role;
insert into public.content_screen_terms (term, how) values ('basmati', 'WORD');
set role authenticated; select pg_temp.as_user('sb');
select pg_temp.check('a new term hides at once', not exists (select 1 from items where name = 'Basmati rice'));
reset role; delete from public.content_screen_terms where term = 'basmati'; set role authenticated; select pg_temp.as_user('sb');
select pg_temp.check('removing it shows it again', exists (select 1 from items where name = 'Basmati rice'));
\echo '== An edit re-screens'
select pg_temp.as_user('so');
update items set name = 'Kingfisher soda' where name = 'Kingfisher beer';
select pg_temp.as_user('sb');
select pg_temp.check('renamed to a halal item: visible again', exists (select 1 from items where name = 'Kingfisher soda'));
reset role;
