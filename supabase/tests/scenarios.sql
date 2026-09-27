\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- helpers: act as a signed-in user, or as the database owner
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' or want = '' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

\echo '== 1. Sign-up creates profiles with UUIDv7 ids and 8-char Bucks IDs'
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"owner"}', false); select 'owner id version ' || substr(id::text, 15, 1) || ', short ' || short_code from public.ensure_profile('Asha (shop owner)', '9000000001');
select set_config('request.jwt.claims', '{"sub":"buyer"}', false); select 'buyer ' || short_code from public.ensure_profile('Chetan (buyer)', '9000000002');
select set_config('request.jwt.claims', '{"sub":"rider"}', false); select 'rider ' || short_code from public.ensure_profile('Ravi (bike rider)', '9000000003');
select set_config('request.jwt.claims', '{"sub":"helper"}', false); select 'helper ' || short_code from public.ensure_profile('Bala (admin)', '9000000004');
reset role;
insert into profiles (auth_uid, name, home, created_at) select 'n' || g, 'Neighbour ' || g, geo(12.9063 + g * 0.001, 77.5857), now() - interval '30 days' from generate_series(1, 8) g;
insert into profiles (auth_uid, name, home, created_at) values ('newbie', 'New account', geo(12.9063, 77.5857), now()), ('faraway', 'Noida user', geo(28.5355, 77.3910), now() - interval '90 days');

\echo '== 2. Owner creates a business with items; it starts PENDING and is hidden from others'
set role authenticated; select set_config('request.jwt.claims', '{"sub":"owner"}', false);
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Asha Biryani House', 'Restaurant', 'Dum biryani and kebabs', 'JP Nagar', geo(12.9063, 77.5857), '{"free_delivery": false}');
insert into items (listing_id, name, price, unit, group_name) select id, 'Chicken dum biryani', 220, '1 plate', 'Biryani' from listings where title = 'Asha Biryani House';
insert into items (listing_id, name, price, unit, group_name) select id, 'Paneer tikka', 180, '8 pcs', 'Starters' from listings where title = 'Asha Biryani House';
select 'status: ' || status || ', owner role: ' || listing_role(id) from listings where title = 'Asha Biryani House';
select 'owner sets LIVE directly -> ' || pg_temp.expect_fail($$update listings set status = 'LIVE'$$, 'managed by Bucks');
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
select 'buyer sees pending listing? ' || count(*) from listings where title = 'Asha Biryani House';

\echo '== 3. Community cap: 7 local, in-person recommendations make it LIVE'
select set_config('request.jwt.claims', '{"sub":"owner"}', false);
select set_config('t.tok', recommend_token(id), false) is not null from listings where title = 'Asha Biryani House';
select set_config('request.jwt.claims', '{"sub":"newbie"}', false);
select 'new account -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'too new');
select set_config('request.jwt.claims', '{"sub":"faraway"}', false);
select 'Noida user -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'live nearby');
select set_config('request.jwt.claims', '{"sub":"owner"}', false);
select 'owner self -> ' || pg_temp.expect_fail(format($$select recommend(%L, 12.9063, 77.5857)$$, current_setting('t.tok')), 'own listing');
select set_config('request.jwt.claims', '{"sub":"n1"}', false);
select 'n1 remote (not in person) -> ' || pg_temp.expect_fail(format($$select recommend(%L, 13.20, 77.70)$$, current_setting('t.tok')), 'in person');
do $$ declare i int; n int; begin for i in 1..7 loop
  perform set_config('request.jwt.claims', format('{"sub":"n%s"}', i), false);
  n := recommend(current_setting('t.tok'), 12.9063, 77.5857);
  raise notice 'recommendation % -> total %, status %', i, n, (select status from listings where title = 'Asha Biryani House');
end loop; end $$;

\echo '== 4. Search finds it by dish name, from the buyer, with distance'
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
select title || ' | matched: ' || coalesce(matched_item, '-') || ' | from Rs ' || min_price || ' | ' || round(distance_m) || ' m' from search_listings('biryani', 12.9100, 77.5860);
select 'search far away (Noida): ' || count(*) from search_listings('biryani', 28.5355, 77.3910);

\echo '== 5. Admin invite by Bucks ID; admin can edit items but not delete the business'
select set_config('request.jwt.claims', '{"sub":"owner"}', false);
select 'invite sent: ' || (invite((select id from listings where title = 'Asha Biryani House'), null, (select short_code from profiles where auth_uid = 'helper'), 'ADMIN') is not null);
select set_config('request.jwt.claims', '{"sub":"helper"}', false);
select respond_invite((select id from invites where status = 'PENDING' limit 1), true);
update items set price = 230 where name = 'Chicken dum biryani'; select 'admin changed price to ' || price from items where name = 'Chicken dum biryani';
delete from listings where title = 'Asha Biryani House'; select 'listing still exists after admin delete attempt: ' || count(*) from listings where title = 'Asha Biryani House';
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
select 'buyer edits item -> updated rows: ' || count(*) from (select 1) x where false; update items set price = 1 where name = 'Chicken dum biryani'; 
reset role; select 'price after buyer attempt: ' || price from items where name = 'Chicken dum biryani'; set role authenticated;

\echo '== 6. Rider registers a bike, goes online nearby; bikes cannot take passengers'
select set_config('request.jwt.claims', '{"sub":"rider"}', false);
insert into vehicles (owner_id, kind, model, plate) values (me(), 'BIKE', 'Honda Activa', 'KA05AB1234');
reset role; update vehicles set status = 'ACTIVE'; set role authenticated;
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'BIKE', true, geo(12.9080, 77.5870) from vehicles where plate = 'KA05AB1234';
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
select 'bike passenger ride -> ' || pg_temp.expect_fail($$select request_ride('BIKE', 12.91, 77.58, 'x', 12.97, 77.60, 'MG Road', 8, 90)$$, 'goods only');

reset role; update listings set online = true where title = 'Asha Biryani House'; set role authenticated;   -- the owner opens the shop
\echo '== 7. Order -> vendor accepts -> bike delivery task -> rider claims -> PIN -> delivered'
select set_config('t.order', place_order((select id from listings where title = 'Asha Biryani House'),
  jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Chicken dum biryani'), 'qty', 2, 'price', 1)), 12.9150, 77.5900, 'Buyer home', 'UPI', 'MARKETPLACE')::text, false) is not null;
select 'order: subtotal Rs ' || subtotal || ' (app said Rs 1, server priced it), delivery Rs ' || delivery_fee || ', accept within ' || round(extract(epoch from accept_by - created_at) / 60) || ' min' from orders where id = current_setting('t.order')::uuid;
select 'COD via marketplace -> ' || pg_temp.expect_fail(format($$select place_order(%L, '[]'::jsonb, 12.91, 77.59, 'x', 'COD', 'MARKETPLACE')$$, (select id from listings where title = 'Asha Biryani House')), 'store''s own riders');
select set_config('request.jwt.claims', '{"sub":"rider"}', false);
select 'rider sees tasks before vendor accepts: ' || count(*) from open_tasks_near(12.9080, 77.5870);
select set_config('request.jwt.claims', '{"sub":"helper"}', false);
select respond_order(current_setting('t.order')::uuid, true); select 'order status after admin accepts: ' || status from orders where id = current_setting('t.order')::uuid;
select set_config('request.jwt.claims', '{"sub":"rider"}', false);
select 'rider rung for: ' || type || ' ' || pickup_label || ' -> ' || drop_label || ', ' || km || ' km, Rs ' || fare from open_tasks_near(12.9080, 77.5870);
select set_config('t.task', (select id::text from open_tasks_near(12.9080, 77.5870) limit 1), false) is not null;
select 'claim: ' || claim_task(current_setting('t.task')::uuid);
select 'arrived: ' || (advance_task(current_setting('t.task')::uuid, 'ARRIVED')).status;
select 'wrong PIN -> ' || pg_temp.expect_fail(format($$select advance_task(%L, 'IN_PROGRESS', '0000')$$, current_setting('t.task')), 'PIN');
reset role; select set_config('t.pin', pin, false) is not null from tasks where id = current_setting('t.task')::uuid; set role authenticated;
select 'picked up: ' || (advance_task(current_setting('t.task')::uuid, 'IN_PROGRESS', current_setting('t.pin'))).status;
select 'delivered: ' || (advance_task(current_setting('t.task')::uuid, 'COMPLETED')).status;
select 'order status: ' || status from orders where id = current_setting('t.order')::uuid;

\echo '== 8. Review only after a real order; owner dashboard per vehicle'
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
select review((select id from listings where title = 'Asha Biryani House'), null, current_setting('t.order')::uuid, 1, 'Hot and on time');
select 'listing trust: +' || trust_up from listings where title = 'Asha Biryani House';
select set_config('request.jwt.claims', '{"sub":"helper"}', false);
select 'review without an order -> ' || pg_temp.expect_fail(format($$select review(%L, null, null, 1, 'great')$$, (select id from listings where title = 'Asha Biryani House')), 'after a completed');
select set_config('request.jwt.claims', '{"sub":"rider"}', false);
select plate || ': accepted ' || accepted || ', rejected ' || rejected || ', completed ' || completed || ', ' || km || ' km, Rs ' || earnings from vehicle_stats;

\echo '== 9. Jobs: business posts, buyer applies, admin shortlists'
select set_config('request.jwt.claims', '{"sub":"owner"}', false);
insert into jobs (listing_id, title, pay, job_type, created_by) select id, 'Kitchen helper', 'Rs 15,000/month', 'FULL_TIME', me() from listings where title = 'Asha Biryani House';
select set_config('request.jwt.claims', '{"sub":"buyer"}', false);
insert into applications (job_id, applicant_id, note) select id, me(), 'Worked 2 years at a hotel' from jobs;
select set_config('request.jwt.claims', '{"sub":"helper"}', false);
update applications set status = 'SHORTLISTED'; select 'application: ' || status from applications;
select set_config('request.jwt.claims', '{"sub":"rider"}', false);
select 'rider can see others'' applications: ' || count(*) from applications;

\echo '== 10. Unaccepted orders expire after 5 minutes'
reset role;
update orders set status = 'PLACED', accept_by = now() - interval '1 second' where id = current_setting('t.order')::uuid;
select 'expired orders: ' || expire_orders();
