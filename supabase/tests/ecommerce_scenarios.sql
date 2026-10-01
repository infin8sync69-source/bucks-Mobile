\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Scenarios for shipping and local delivery (migrations/ecommerce.sql, migrations/product_feedback.sql) as they stand after the two hardening
-- files, which redefine place_order, place_order_ship, contact_for_order, search_listings and can_see_post. Every printed line starts with
-- "ok" or "FAIL". Run in a throw-away copy of a database built with apply_all.sh (see supabase/README.md).
-- Locations (Bengaluru): shop S 12.9250,77.5938; near N 12.9300,77.6000 (0.9 km); far F 13.2000,77.7000 (31 km). Mumbai M 19.0760,72.8777.

create or replace function pg_temp.as_user(u text) returns setof text language plpgsql as $$ begin perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false); return; end $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when coalesce(ok, false) then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.eq(actual text, want text, what text) returns text language sql as $$
  select case when actual is not distinct from want then 'ok, ' || what else 'FAIL ' || what || ' (got: ' || left(coalesce(actual, '<null>'), 90) || ', want: ' || left(coalesce(want, '<null>'), 90) || ')' end $$;
create or replace function pg_temp.q(sql text) returns text language plpgsql as $$ declare r text; begin execute sql into r; return coalesce(r, '<null>'); exception when others then return 'ERR: ' || sqlerrm; end $$;
create or replace function pg_temp.blocked(sql text, want text) returns boolean language plpgsql as $$ begin execute sql; return false; exception when others then return sqlerrm ilike '%' || want || '%'; end $$;
create or replace function pg_temp.pid(u text) returns uuid language sql security definer as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.sq(sql text) returns text language plpgsql security definer as $$ declare r text; begin execute sql into r; return coalesce(r, '<null>'); exception when others then return 'ERR: ' || sqlerrm; end $$;
create or replace function pg_temp.mkuser(p_u text) returns uuid language plpgsql security definer as $$
declare pr uuid;
begin
  insert into public.profiles (auth_uid, name) values (p_u, initcap(p_u)) returning id into pr;
  insert into public.profile_private (profile_id, phone) values (pr, '98' || lpad((abs(hashtext(p_u)) % 100000000)::text, 8, '0'));
  return pr;
end $$;
create or replace function pg_temp.mkshop(p_owner text, p_title text, p_details jsonb) returns uuid language plpgsql security definer as $$
declare lid uuid;
begin
  insert into public.listings (kind, owner_id, title, category, area, location, details)
    values ('BUSINESS', pg_temp.pid(p_owner), p_title, 'Grocery', 'Jayanagar', public.geo(12.9250, 77.5938), p_details) returning id into lid;
  update public.listings set status = 'LIVE', online = true where id = lid;
  insert into public.items (listing_id, name, price, unit) values (lid, 'Rice', 62, '1 kg'), (lid, 'Saree', 900, '1 piece');
  return lid;
end $$;
create or replace function pg_temp.item(p_shop uuid, p_name text) returns uuid language sql security definer as $$ select id from public.items where listing_id = p_shop and name = p_name $$;
create or replace function pg_temp.line(p_item uuid, p_qty int) returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty)) $$;
create or replace function pg_temp.addr(p_pincode text default '560041') returns jsonb language sql as $$
  select jsonb_build_object('name', 'Uma R', 'phone', '9876543210', 'line1', '12 MG Road', 'line2', '', 'city', 'Mysuru', 'state', 'Karnataka', 'pincode', p_pincode) $$;

-- ---------- fixtures ----------
select pg_temp.mkuser('sol') is not null as fixture \gset
select pg_temp.mkuser('tia') is not null as fixture \gset
select pg_temp.mkuser('uma') is not null as fixture \gset
select pg_temp.mkuser('vic') is not null as fixture \gset
select pg_temp.mkshop('sol', 'Sol Silks', '{"ships_india": true, "ship_fee": 50, "free_ship_above": 1500, "cod": true, "delivery_radius_km": 3}') as ship_shop \gset
select pg_temp.mkshop('tia', 'Tia Grocers', '{"cod": false}') as local_shop \gset

set role authenticated;

-- ---------- place_order: local delivery only inside the shop's radius ----------
select pg_temp.as_user('uma');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 13.2000, 77.7000, 'Far away', 'UPI', 'MARKETPLACE')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1)), 'ship it to an address instead'),
  'a shop that ships says to ship when the drop is outside its radius');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 13.2000, 77.7000, 'Far away', 'UPI', 'MARKETPLACE')$$, :'local_shop', pg_temp.line(pg_temp.item(:'local_shop', 'Rice'), 1)), 'or pick it up'),
  'a local-only shop offers pick-up when the drop is outside its radius');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.9300, 77.6000, 'Near', 'UPI', 'SHIP')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1)), 'place_order_ship'),
  'place_order sends SHIP to place_order_ship');
select pg_temp.check(pg_temp.q(format($$select place_order(%L, %L::jsonb, 12.9300, 77.6000, 'Near', 'UPI', 'MARKETPLACE')$$, :'local_shop', pg_temp.line(pg_temp.item(:'local_shop', 'Rice'), 1))) !~ '^ERR',
  'a delivery inside the radius is placed');
select pg_temp.check(pg_temp.q(format($$select place_order(%L, %L::jsonb, 13.2000, 77.7000, 'Far away', 'UPI', 'PICKUP')$$, :'local_shop', pg_temp.line(pg_temp.item(:'local_shop', 'Rice'), 1))) !~ '^ERR',
  'pick-up is placed from anywhere');

-- ---------- place_order_ship: the address, the limits ----------
select pg_temp.as_user('vic');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, %L::jsonb, 'UPI')$$, :'local_shop', pg_temp.line(pg_temp.item(:'local_shop', 'Rice'), 1), pg_temp.addr()), 'does not ship'),
  'a shop that does not ship refuses a shipped order');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1), pg_temp.addr('0123')), '6-digit pincode'),
  'a bad pincode is refused');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, 'null'::jsonb, 'UPI')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1)), 'delivery address'),
  'a missing address is refused');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 100), pg_temp.addr()), 'between 1 and 99'),
  'quantity 100 is refused (hardening limit)');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, (select jsonb_agg(jsonb_build_object('item_id', %L::uuid, 'qty', 1)) from generate_series(1, 31)), %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.item(:'ship_shop', 'Rice'), pg_temp.addr()), 'too many items'),
  '31 lines are refused (hardening limit)');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, '[]'::jsonb, %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.addr()), 'cart is empty'),
  'an empty cart is refused');
select place_order_ship(:'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1), pg_temp.addr(), 'UPI') as ship1 \gset
select pg_temp.eq(pg_temp.sq(format($$select delivery_fee || ' ' || delivery_mode || ' ' || status || ' ' || drop_label from orders where id = %L$$, :'ship1')), '50 SHIP PLACED Mysuru, Karnataka 560041',
  'a shipped order carries the flat fee and the address city');
select place_order_ship(:'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Saree'), 2), pg_temp.addr(), 'COD') as ship2 \gset
select pg_temp.eq(pg_temp.sq(format($$select delivery_fee::text from orders where id = %L$$, :'ship2')), '0', 'shipping is free above the shop''s line');
select place_order_ship(:'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1), pg_temp.addr(), 'UPI') as ship3 \gset
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1), pg_temp.addr()), 'orders waiting'),
  'a fourth waiting order is refused (hardening limit applies to shipped orders too)');
select pg_temp.as_user('sol');
select pg_temp.check(pg_temp.blocked(format($$select place_order_ship(%L, %L::jsonb, %L::jsonb, 'UPI')$$, :'ship_shop', pg_temp.line(pg_temp.item(:'ship_shop', 'Rice'), 1), pg_temp.addr()), 'own shop'),
  'an owner cannot ship-order from their own shop');

-- ---------- contact_for_order: the buyer after acceptance, the shop from PLACED; SHIPPED counts as live ----------
select pg_temp.as_user('vic');
select pg_temp.eq(pg_temp.q(format($$select count(*)::text from contact_for_order(%L)$$, :'ship1')), '0', 'the buyer gets no shop phone before the shop accepts');
select pg_temp.as_user('sol');
select pg_temp.eq(pg_temp.q(format($$select count(*)::text from contact_for_order(%L)$$, :'ship1')), '1', 'the shop sees the buyer from PLACED');
select pg_temp.check(pg_temp.q(format($$select respond_order(%L, true)$$, :'ship1')) !~ '^ERR', 'the shop accepts a shipped order');
select pg_temp.eq(pg_temp.sq(format($$select count(*)::text from tasks where order_id = %L$$, :'ship1')), '0', 'accepting a shipped order rings no rider');
select pg_temp.check(pg_temp.blocked(format($$select ship_order(%L, 'DTDC', '', 'ftp://x')$$, :'ship1'), 'http'), 'a tracking link must be http(s)');
select pg_temp.check(pg_temp.q(format($$select ship_order(%L, 'DTDC', 'D123', 'https://dtdc.in/t/D123')$$, :'ship1')) !~ '^ERR', 'the shop ships it');
select pg_temp.eq(pg_temp.q(format($$select count(*)::text from contact_for_order(%L)$$, :'ship1')), '1', 'the shop still reaches the buyer while SHIPPED');
select pg_temp.as_user('vic');
select pg_temp.eq(pg_temp.q(format($$select count(*)::text from contact_for_order(%L)$$, :'ship1')), '1', 'the buyer reaches the shop while SHIPPED');
select pg_temp.eq(pg_temp.q(format($$select status || ' ' || carrier || ' ' || tracking_no from orders where id = %L$$, :'ship1')), 'SHIPPED DTDC D123', 'the buyer sees the carrier and tracking number');
select pg_temp.check(pg_temp.q(format($$select mark_delivered(%L)$$, :'ship1')) !~ '^ERR', 'the buyer marks it delivered');
select pg_temp.eq(pg_temp.q(format($$select status from orders where id = %L$$, :'ship1')), 'DELIVERED', 'the order is DELIVERED');
select pg_temp.eq(pg_temp.sq(format($$select (delivered_at is not null)::text from orders where id = %L$$, :'ship1')), 'true', 'delivered_at is stamped');

-- ---------- search_listings: a store that ships is found from anywhere ----------
select pg_temp.as_user('uma');
select pg_temp.eq(pg_temp.q(format($$select string_agg(title, ',' order by title) from search_listings('', 19.0760, 72.8777, 10000, array['BUSINESS'])$$)), 'Sol Silks',
  'from Mumbai, only the store that ships shows up');
select pg_temp.eq(pg_temp.q(format($$select string_agg(title, ',' order by title) from search_listings('', 12.9300, 77.6000, 10000, array['BUSINESS'])$$)), 'Sol Silks,Tia Grocers',
  'nearby, both stores show up');

-- ---------- can_see_post: a store's posts reach the people who synced with the store ----------
select pg_temp.as_user('sol');
insert into posts (author_id, listing_id, body, visibility) values (pg_temp.pid('sol'), :'ship_shop', 'New silks in', 'SYNCED');
select pg_temp.as_user('uma');
select pg_temp.eq(pg_temp.q($$select count(*)::text from posts where body = 'New silks in'$$), '0', 'a store''s synced-only post is hidden from a stranger');
insert into listing_syncs (profile_id, listing_id) values (pg_temp.pid('uma'), :'ship_shop');
select pg_temp.eq(pg_temp.q($$select count(*)::text from posts where body = 'New silks in'$$), '1', 'after syncing with the store, its post shows in the Feed');

-- ---------- rate_listing: a direct recommendation ----------
select pg_temp.check(pg_temp.q(format($$select rate_listing(%L, 1, 'Lovely silks')$$, :'ship_shop')) !~ '^ERR', 'anyone can recommend a live store with a comment');
select pg_temp.eq(pg_temp.sq(format($$select trust_up::text from listings where id = %L$$, :'ship_shop')), '1', 'the recommendation counts in the trust numbers');

reset role;
