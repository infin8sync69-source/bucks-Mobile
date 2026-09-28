\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Studio scenarios: assets (sell / rent / lease) and their service, galleries that only take the listing's own photos,
-- products with description, photos and stock (orders take stock, rejected / cancelled orders give it back),
-- and the one-year Bucks ID card. Every check prints "ok, ..." or "FAIL ...".
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.lid(t text) returns uuid language sql as $$ select id from public.listings where title = t $$;
create or replace function pg_temp.url(l uuid, f text) returns text language sql as $$ select format('https://lboxctryrktwdsvywfqp.supabase.co/storage/v1/object/public/listing-media/%s/%s', l, f) $$;

set role authenticated;
select pg_temp.as_user('owner');    select (public.ensure_profile('Asha (owner)', '9000000051')).id is not null;
select pg_temp.as_user('buyer');    select (public.ensure_profile('Ravi (buyer)', '9000000052')).id is not null;
select pg_temp.as_user('stranger'); select (public.ensure_profile('Kiran (nobody)', '9000000053')).id is not null;

\echo '== 1. Assets: a fourth kind with a mode and a price; property types land in Properties, the rest in no service'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('ASSET', me(), '2BHK in 4th Block', 'Flat', 'Sunny, 2nd floor', 'Jayanagar', geo(12.925, 77.594), '{"mode": "RENT", "price": 28000, "price_unit": "MONTH", "deposit": 150000}');
insert into listings (kind, owner_id, title, category, area, location, details)
  values ('ASSET', me(), 'Activa 2019', 'Vehicle', 'Jayanagar', geo(12.925, 77.594), '{"mode": "SELL", "price": 42000}');
select pg_temp.check((select service from listings where id = pg_temp.lid('2BHK in 4th Block')) = 'PROPERTIES', 'a flat for rent is in Properties');
select pg_temp.check((select service from listings where id = pg_temp.lid('Activa 2019')) is null, 'a scooter for sale has no service');
select pg_temp.check((select status from listings where id = pg_temp.lid('2BHK in 4th Block')) = 'PENDING', 'a new asset starts PENDING like every listing');
select 'no mode -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title, category, details) values ('ASSET', me(), 'x', 'House', '{"price": 1}')$$, 'listings_asset_details');
select 'barter -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title, category, details) values ('ASSET', me(), 'x', 'House', '{"mode": "SWAP", "price": 1}')$$, 'listings_asset_details');
select 'price as text -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title, category, details) values ('ASSET', me(), 'x', 'House', '{"mode": "SELL", "price": "lots"}')$$, 'listings_asset_details');
select 'negative price -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title, category, details) values ('ASSET', me(), 'x', 'House', '{"mode": "SELL", "price": -5}')$$, 'listings_asset_details');
select 'unknown kind -> ' || pg_temp.expect_fail($$insert into listings (kind, owner_id, title) values ('THING', me(), 'x')$$, 'listings_kind_check');
select pg_temp.check(exists (select 1 from listing_compliance(pg_temp.lid('2BHK in 4th Block')) where doc_type = 'OWNER_ID' and required), 'a property asset needs the owner''s ID checked before it goes live');
select pg_temp.check(not exists (select 1 from listing_compliance(pg_temp.lid('Activa 2019'))), 'a scooter needs no service documents');
update listings set category = 'House' where id = pg_temp.lid('Activa 2019');
select pg_temp.check((select service from listings where id = pg_temp.lid('Activa 2019')) = 'PROPERTIES', 'changing a pending asset to a house moves it to Properties');
update listings set category = 'Vehicle' where id = pg_temp.lid('Activa 2019');
reset role; update listings set status = 'LIVE' where id = pg_temp.lid('2BHK in 4th Block'); set role authenticated;
select pg_temp.as_user('owner');
select 'live flat turned into a scooter -> ' || pg_temp.expect_fail(format($$update listings set category = 'Vehicle' where id = %L$$, pg_temp.lid('2BHK in 4th Block')), 'cannot move to another service');
select pg_temp.as_user('buyer');
select pg_temp.check((select details->>'mode' || ' ' || (details->>'price') from listings where id = pg_temp.lid('2BHK in 4th Block')) = 'RENT 28000', 'buyers see mode and price of a live asset');
select pg_temp.check((select count(*) from search_listings('flat', 12.925, 77.594, 5000, null, 40, array['PROPERTIES'])) = 1, 'search under Properties finds the flat');

\echo '== 2. Galleries: up to 20 photos from the listing''s own folder, with captions'
select pg_temp.as_user('owner');
update listings set gallery = jsonb_build_array(jsonb_build_object('url', pg_temp.url(pg_temp.lid('2BHK in 4th Block'), 'hall.jpg'), 'caption', 'Hall'),
                                                jsonb_build_object('url', pg_temp.url(pg_temp.lid('2BHK in 4th Block'), 'kitchen.jpg')))
  where id = pg_temp.lid('2BHK in 4th Block');
select pg_temp.check(jsonb_array_length((select gallery from listings where id = pg_temp.lid('2BHK in 4th Block'))) = 2, 'owner saves two photos');
select 'photo from another listing''s folder -> ' || pg_temp.expect_fail(format($$update listings set gallery = jsonb_build_array(jsonb_build_object('url', %L)) where id = %L$$,
  pg_temp.url(pg_temp.lid('Activa 2019'), 'a.jpg'), pg_temp.lid('2BHK in 4th Block')), 'listings_gallery_ok');
select 'outside link -> ' || pg_temp.expect_fail(format($$update listings set gallery = '[{"url": "https://tracker.example/p.gif"}]' where id = %L$$, pg_temp.lid('2BHK in 4th Block')), 'listings_gallery_ok');
select 'path tricks -> ' || pg_temp.expect_fail(format($$update listings set gallery = jsonb_build_array(jsonb_build_object('url', %L)) where id = %L$$,
  pg_temp.url(pg_temp.lid('2BHK in 4th Block'), '../x/a.jpg'), pg_temp.lid('2BHK in 4th Block')), 'listings_gallery_ok');
select '21 photos -> ' || pg_temp.expect_fail(format($$update listings set gallery = (select jsonb_agg(jsonb_build_object('url', %L)) from generate_series(1, 21)) where id = %L$$,
  pg_temp.url(pg_temp.lid('2BHK in 4th Block'), 'a.jpg'), pg_temp.lid('2BHK in 4th Block')), 'listings_gallery_ok');
select 'long caption -> ' || pg_temp.expect_fail(format($$update listings set gallery = jsonb_build_array(jsonb_build_object('url', %L, 'caption', repeat('x', 201))) where id = %L$$,
  pg_temp.url(pg_temp.lid('2BHK in 4th Block'), 'a.jpg'), pg_temp.lid('2BHK in 4th Block')), 'listings_gallery_ok');
select pg_temp.as_user('stranger');
with x as (update listings set gallery = '[]' where id = pg_temp.lid('2BHK in 4th Block') returning 1) select pg_temp.check(count(*) = 0, 'a stranger can''t change the gallery') from x;
select pg_temp.check(jsonb_array_length((select gallery from listings where id = pg_temp.lid('2BHK in 4th Block'))) = 2, 'a stranger sees the live gallery');

\echo '== 3. Products: description, photos, stock; stock at 0 is out of stock'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Asha Bakery', 'Bakery', 'Jayanagar', geo(12.925, 77.594), '{"cod": false}');
insert into items (listing_id, name, price, unit, description, stock, photos, details)
  values (pg_temp.lid('Asha Bakery'), 'Plum cake', 450, '1 kg', 'Rum-soaked, baked on Fridays', 3,
          jsonb_build_array(jsonb_build_object('url', pg_temp.url(pg_temp.lid('Asha Bakery'), 'cake.jpg'))), '{"veg": false}'),
         (pg_temp.lid('Asha Bakery'), 'Bun', 20, '1 piece', '', null, '[]', '{}');
select pg_temp.check((select description from items where name = 'Plum cake') = 'Rum-soaked, baked on Fridays', 'product keeps its description');
select 'photo from elsewhere -> ' || pg_temp.expect_fail(format($$update items set photos = jsonb_build_array(jsonb_build_object('url', %L)) where name = 'Bun'$$, pg_temp.url(pg_temp.lid('Activa 2019'), 'a.jpg')), 'items_photos_ok');
select '9 photos -> ' || pg_temp.expect_fail(format($$update items set photos = (select jsonb_agg(jsonb_build_object('url', %L)) from generate_series(1, 9)) where name = 'Bun'$$, pg_temp.url(pg_temp.lid('Asha Bakery'), 'b.jpg')), 'items_photos_ok');
select 'negative stock -> ' || pg_temp.expect_fail($$update items set stock = -1 where name = 'Bun'$$, 'items_stock_ok');
update items set stock = 0 where name = 'Bun';
select pg_temp.check(not (select in_stock from items where name = 'Bun'), 'stock 0 switches the bun out of stock');
update items set stock = 10 where name = 'Bun';
select pg_temp.check((select in_stock from items where name = 'Bun'), 'stock back from 0 switches it back in stock');
update items set stock = null where name = 'Bun';
select pg_temp.check((select in_stock from items where name = 'Bun'), 'not counting stock leaves it in stock');
select pg_temp.as_user('stranger');
select 'stranger adds a product -> ' || pg_temp.expect_fail(format($$insert into items (listing_id, name, price) values (%L, 'Fake', 1)$$, pg_temp.lid('Asha Bakery')), 'row-level security');

\echo '== 4. Orders take stock; a rejected or cancelled order gives it back'
reset role; update listings set status = 'LIVE', online = true where id = pg_temp.lid('Asha Bakery'); set role authenticated;
select pg_temp.as_user('buyer');
select 'five cakes when three are left -> ' || pg_temp.expect_fail(format($$select place_order(%L, jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 5)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')$$,
  pg_temp.lid('Asha Bakery'), (select id from items where name = 'Plum cake')), 'only 3 left of Plum cake');
select set_config('t.o1', place_order(pg_temp.lid('Asha Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Plum cake'), 'qty', 2),
  jsonb_build_object('item_id', (select id from items where name = 'Bun'), 'qty', 6)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.check((select stock from items where name = 'Plum cake') = 1, 'two cakes ordered, one left');
select pg_temp.check((select stock from items where name = 'Bun') is null, 'uncounted buns stay uncounted');
select pg_temp.as_user('owner'); select respond_order(current_setting('t.o1')::uuid, false);
select pg_temp.check((select stock from items where name = 'Plum cake') = 3, 'rejected order gives the two cakes back');
select pg_temp.as_user('buyer');
select set_config('t.o2', place_order(pg_temp.lid('Asha Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Plum cake'), 'qty', 3)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.check((select stock = 0 and not in_stock from items where name = 'Plum cake'), 'last three cakes sold: out of stock');
select 'one more cake -> ' || pg_temp.expect_fail(format($$select place_order(%L, jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 1)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')$$,
  pg_temp.lid('Asha Bakery'), (select id from items where name = 'Plum cake')), 'no longer available');
select cancel_order(current_setting('t.o2')::uuid);
select pg_temp.check((select stock = 3 and in_stock from items where name = 'Plum cake'), 'cancelled order: three cakes back and in stock');
select set_config('t.o3', place_order(pg_temp.lid('Asha Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Plum cake'), 'qty', 1)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')::text, false) is not null;
reset role; update orders set accept_by = now() - interval '1 minute' where id = current_setting('t.o3')::uuid; select expire_orders(); set role authenticated;
select pg_temp.check((select stock from items where name = 'Plum cake') = 3, 'timed-out order gives its cake back');
select pg_temp.as_user('buyer');
select 'buyer calls the stock trigger -> ' || pg_temp.expect_fail('select public.order_stock_back()', 'permission denied');

\echo '== 5. Bucks ID card: valid a year, renewable only near the end, never set by hand'
select pg_temp.as_user('owner');
select pg_temp.check((select id_issued_at > now() - interval '1 minute' from profiles where id = me()), 'a new profile''s card starts today');
select pg_temp.as_user('buyer');
select pg_temp.check((select id_issued_at is not null from profiles where auth_uid = 'owner'), 'others can read the card date (to show validity)');
select pg_temp.as_user('owner');
select 'owner backdates the card -> ' || pg_temp.expect_fail($$update profiles set id_issued_at = now() - interval '2 years' where id = me()$$, 'managed by Bucks');
select 'renew a fresh card -> ' || pg_temp.expect_fail('select renew_bucks_id()', 'you can renew it in its last 30 days');
reset role; update profiles set id_issued_at = now() - interval '13 months' where auth_uid = 'owner'; set role authenticated;
select pg_temp.as_user('owner');
select pg_temp.check(renew_bucks_id() > now() - interval '1 minute', 'a lapsed card renews for a year from today');
reset role; update profiles set id_issued_at = now() - interval '340 days' where auth_uid = 'owner'; set role authenticated;
select pg_temp.as_user('owner');
select pg_temp.check(renew_bucks_id() > now() - interval '1 minute', 'a card in its last month can renew');
reset role; set role anon; select 'signed out renews -> ' || pg_temp.expect_fail('select public.renew_bucks_id()', 'permission denied'); reset role;
