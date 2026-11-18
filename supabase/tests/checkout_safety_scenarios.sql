\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- checkout_safety.sql: a retried checkout answers the first order instead of placing a second one.
create or replace function pg_temp.said(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok: ' else 'FAIL: ' end || what $$;
create or replace function pg_temp.fails(sql text) returns boolean language plpgsql as $$ begin execute sql; return false; exception when others then return true; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.shop() returns uuid language sql security definer as $$ select id from public.listings where title = 'Retry Stores' $$;
create or replace function pg_temp.rice() returns uuid language sql security definer as $$ select id from public.items where name = 'Retry rice' $$;
create or replace function pg_temp.lines(q int) returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('item_id', pg_temp.rice(), 'qty', q)) $$;
create or replace function pg_temp.addr() returns jsonb language sql as $$
  select jsonb_build_object('name', 'Uma R', 'phone', '9876543210', 'line1', '12 MG Road', 'line2', '', 'city', 'Mysuru', 'state', 'Karnataka', 'pincode', '570001') $$;

set role authenticated;
select pg_temp.as_user('cs_owner'); select (public.ensure_profile('Retry (owner)', '9000000061')).id is not null;
select pg_temp.as_user('cs_buyer'); select (public.ensure_profile('Retry (buyer)', '9000000062')).id is not null;
select pg_temp.as_user('cs_other'); select (public.ensure_profile('Retry (other buyer)', '9000000063')).id is not null;
select pg_temp.as_user('cs_owner');
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Retry Stores', 'Grocery', 'Rice', 'Jayanagar', geo(12.9250, 77.5938), '{"ships_india": true, "ship_fee": 50}');
insert into items (listing_id, name, price, unit, stock) values (pg_temp.shop(), 'Retry rice', 60, '1 kg', 20);
reset role; update listings set status = 'LIVE', online = true where id = pg_temp.shop(); set role authenticated;

\echo '== 1. Local order: the same request id twice is one order'
select pg_temp.as_user('cs_buyer');
select set_config('t.a1', place_order_once('11111111-1111-4111-8111-111111111111', pg_temp.shop(), pg_temp.lines(2), 12.9300, 77.6000, 'Home', 'UPI', 'PICKUP')::text, false) is not null;
select set_config('t.a2', place_order_once('11111111-1111-4111-8111-111111111111', pg_temp.shop(), pg_temp.lines(2), 12.9300, 77.6000, 'Home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.said(current_setting('t.a1') = current_setting('t.a2'), 'the retry answers the first order''s id');
select pg_temp.said((select count(*) from orders where buyer_id = me()) = 1, 'only one order exists');
select pg_temp.said((select stock from items where id = pg_temp.rice()) = 18, 'stock went down once (20 -> 18)');
select pg_temp.said((select client_ref from orders where id = current_setting('t.a1')::uuid) = '11111111-1111-4111-8111-111111111111', 'the order keeps its request id');

\echo '== 2. A new request id is a new order'
select set_config('t.a3', place_order_once('22222222-2222-4222-8222-222222222222', pg_temp.shop(), pg_temp.lines(1), 12.9300, 77.6000, 'Home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.said(current_setting('t.a3') <> current_setting('t.a1'), 'a different id places a second order');
select pg_temp.said((select stock from items where id = pg_temp.rice()) = 17, 'and takes its own stock (18 -> 17)');

\echo '== 3. Shipped order: the same rule'
select set_config('t.s1', place_order_ship_once('33333333-3333-4333-8333-333333333333', pg_temp.shop(), pg_temp.lines(1), pg_temp.addr(), 'UPI')::text, false) is not null;
select set_config('t.s2', place_order_ship_once('33333333-3333-4333-8333-333333333333', pg_temp.shop(), pg_temp.lines(1), pg_temp.addr(), 'UPI')::text, false) is not null;
select pg_temp.said(current_setting('t.s1') = current_setting('t.s2'), 'a retried shipped order answers the first one');
select pg_temp.said((select count(*) from orders where buyer_id = me()) = 3, 'three orders in all, not four');

\echo '== 4. The id belongs to its buyer; a refused order leaves nothing behind; old calls still work'
select pg_temp.as_user('cs_other');
select set_config('t.b1', place_order_once('11111111-1111-4111-8111-111111111111', pg_temp.shop(), pg_temp.lines(1), 12.9300, 77.6000, 'Office', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.said(current_setting('t.b1') <> current_setting('t.a1'), 'another buyer using the same id gets their own order, not the first buyer''s');
select pg_temp.said((select count(*) from orders where id = current_setting('t.a1')::uuid) = 0, 'and still cannot read the first buyer''s order');
select pg_temp.said(pg_temp.fails(format($$select place_order_once('44444444-4444-4444-8444-444444444444', %L, %L::jsonb, 12.93, 77.60, 'Office', 'UPI', 'PICKUP')$$, pg_temp.shop(), pg_temp.lines(99))), 'an order for more than the stock is refused');
select pg_temp.said((select count(*) from orders where client_ref = '44444444-4444-4444-8444-444444444444') = 0, 'and its id is free to use again');
select set_config('t.b2', place_order(pg_temp.shop(), pg_temp.lines(1), 12.9300, 77.6000, 'Office', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.said((select client_ref from orders where id = current_setting('t.b2')::uuid) is null, 'place_order without an id still works and stores none');
select pg_temp.said(pg_temp.fails(format($$select place_order_once(null, %L, %L::jsonb, 12.93, 77.60, 'Office', 'UPI', 'PICKUP')$$, pg_temp.shop(), pg_temp.lines(1))), 'a missing id is refused');
select set_config('request.jwt.claims', '', false) is not null;
select pg_temp.said(pg_temp.fails(format($$select place_order_once('55555555-5555-4555-8555-555555555555', %L, %L::jsonb, 12.93, 77.60, 'Office', 'UPI', 'PICKUP')$$, pg_temp.shop(), pg_temp.lines(1))), 'signed out: refused');
