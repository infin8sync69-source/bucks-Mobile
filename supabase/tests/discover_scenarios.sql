\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.lid(t text) returns uuid language sql security definer as $$ select id from public.listings where title = t $$;

set role authenticated;
select pg_temp.as_user('asha');   select (public.ensure_profile('Asha', '9000000021')).id is not null;
select pg_temp.as_user('chetan'); select (public.ensure_profile('Chetan', '9000000022')).id is not null;
select pg_temp.as_user('ravi');   select (public.ensure_profile('Ravi', '9000000023')).id is not null;

\echo '== 1. A live shop and a pending pro: listing_points follows listing visibility'
select pg_temp.as_user('asha');
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Asha Stores', 'Grocery', 'Rice, dal, oil and daily needs', 'Jayanagar', geo(12.9250, 77.5938), '{"hours": "7am to 9pm", "free_delivery": true, "delivery_radius_km": 3}');
insert into listings (kind, owner_id, title, category, area, location, details)
  values ('SKILL', me(), 'Asha Tailoring', 'Tailor', 'Jayanagar', geo(12.9260, 77.5940), '{"rate": "₹300 per piece"}');
insert into items (listing_id, name, price, mrp, unit, group_name) values (pg_temp.lid('Asha Stores'), 'Sugar', 45, 50, '1 kg', 'Staples');
insert into items (listing_id, name, price, unit, group_name, in_stock) values (pg_temp.lid('Asha Stores'), 'Sunflower oil', 140, '1 L', 'Staples', false);
insert into items (listing_id, kind, name, price, unit) values (pg_temp.lid('Asha Tailoring'), 'SERVICE', 'Blouse stitching', 350, 'per piece');
reset role; update listings set status = 'LIVE' where title = 'Asha Stores'; set role authenticated;
select pg_temp.as_user('chetan');
select 'Chetan sees points for: ' || string_agg(l.title, ', ') from listing_points p join listings l on l.id = p.id;
select 'Asha Stores at ' || round(lat::numeric, 4) || ', ' || round(lng::numeric, 4) from listing_points where id = pg_temp.lid('Asha Stores');
select 'Chetan reads the pending pro''s point: ' || count(*) from listing_points where id = pg_temp.lid('Asha Tailoring');
select pg_temp.as_user('asha');
select 'owner sees points for: ' || string_agg(l.title, ', ' order by l.title) from listing_points p join listings l on l.id = p.id;

\echo '== 2. Search: browse everything nearby, match an item, filter by kind and radius'
select pg_temp.as_user('chetan');
select 'browse nearby: ' || string_agg(title || ' (' || round(distance_m) || ' m, ' || kind || ')', ', ') from search_listings('', 12.9250, 77.5938);
select 'sugar -> ' || title || ', matched "' || matched_item || '", from ₹' || min_price from search_listings('sugar', 12.9250, 77.5938);
select 'out-of-stock oil is not the min price: ' || (min_price = 45) from search_listings('', 12.9250, 77.5938) where title = 'Asha Stores';
select 'drivers only: ' || count(*) from search_listings('', 12.9250, 77.5938, 10000, array['DRIVER']);
select 'shops only: ' || count(*) from search_listings('', 12.9250, 77.5938, 10000, array['BUSINESS']);
select 'from Whitefield within 3 km: ' || count(*) from search_listings('', 12.9855, 77.7363, 3000);
select 'from Whitefield within 25 km: ' || count(*) from search_listings('', 12.9855, 77.7363, 25000);

\echo '== 3. Sync with a listing: only for yourself; the count is public; nobody can remove yours'
select pg_temp.as_user('chetan');
insert into listing_syncs (profile_id, listing_id) values (me(), pg_temp.lid('Asha Stores'));
select 'forge a sync for Ravi -> ' || pg_temp.expect_fail(format($$insert into listing_syncs (profile_id, listing_id) values (%L, %L)$$, pg_temp.pid('ravi'), pg_temp.lid('Asha Stores')), 'row-level security');
select 'sync twice -> ' || pg_temp.expect_fail(format($$insert into listing_syncs (profile_id, listing_id) values (me(), %L)$$, pg_temp.lid('Asha Stores')), 'duplicate');
select pg_temp.as_user('ravi');
select 'Ravi sees sync count: ' || count(*) from listing_syncs where listing_id = pg_temp.lid('Asha Stores');
delete from listing_syncs where profile_id = pg_temp.pid('chetan');
select 'still synced after Ravi tried to remove it: ' || count(*) from listing_syncs where profile_id = pg_temp.pid('chetan');
select pg_temp.as_user('chetan');
delete from listing_syncs where profile_id = me() and listing_id = pg_temp.lid('Asha Stores');
select 'Chetan unsynced: ' || count(*) from listing_syncs where profile_id = me();
insert into listing_syncs (profile_id, listing_id) values (me(), pg_temp.lid('Asha Stores'));

\echo '== 4. listing_counts: recommendations, syncs, members, open jobs; nothing for a listing I cannot see'
select pg_temp.as_user('asha');
insert into jobs (listing_id, title, pay, job_type, created_by) values (pg_temp.lid('Asha Stores'), 'Delivery rider', '₹15,000 a month', 'FULL_TIME', me());
insert into jobs (listing_id, title, created_by, open) values (pg_temp.lid('Asha Stores'), 'Old closed job', me(), false);
select pg_temp.as_user('chetan');
select 'Asha Stores: recs ' || recommendations || ', syncs ' || syncs || ', members ' || members || ', open jobs ' || open_jobs from listing_counts(pg_temp.lid('Asha Stores'));
select 'pending pro for Chetan: ' || count(*) || ' rows' from listing_counts(pg_temp.lid('Asha Tailoring'));
select pg_temp.as_user('asha');
select 'pending pro for its owner: members ' || members from listing_counts(pg_temp.lid('Asha Tailoring'));
select 'no such listing: ' || count(*) || ' rows' from listing_counts('00000000-0000-0000-0000-000000000000');

\echo '== 5. Profile reads: items with mrp and stock, reviews list, members'
select pg_temp.as_user('chetan');
select 'products: ' || string_agg(name || ' ₹' || price || coalesce(' (mrp ' || mrp || ')', '') || ' ' || unit || case when in_stock then '' else ' [out of stock]' end, ', ' order by sort, name) from items where listing_id = pg_temp.lid('Asha Stores');
select 'pending pro''s services visible to Chetan: ' || count(*) from items where listing_id = pg_temp.lid('Asha Tailoring');
select 'members of Asha Stores: ' || string_agg(role, ', ') from listing_members where listing_id = pg_temp.lid('Asha Stores');
select 'reviews of Asha Stores: ' || count(*) from reviews where listing_id = pg_temp.lid('Asha Stores');

\echo '== 6. Message a shop: the listing chat, a first line from a service request, owner sees it'
select pg_temp.as_user('chetan');
select set_config('t.conv', start_listing_chat(pg_temp.lid('Asha Stores'))::text, false) is not null;
insert into messages (conversation_id, sender_id, body) values (current_setting('t.conv')::uuid, me(), 'Hi, I''d like to request: Blouse stitching (₹350 per piece). When are you free?');
select 'same chat reused: ' || (start_listing_chat(pg_temp.lid('Asha Stores'))::text = current_setting('t.conv'));
select pg_temp.as_user('asha');
select 'Asha inbox: ' || kind || ' "' || title || '" | "' || last_body || '"' from inbox();
select 'owner chats with own listing -> ' || pg_temp.expect_fail(format('select start_listing_chat(%L)', pg_temp.lid('Asha Stores')), 'own listing');
select pg_temp.as_user('chetan');
select 'chat with a pending listing -> ' || pg_temp.expect_fail(format('select start_listing_chat(%L)', pg_temp.lid('Asha Tailoring')), 'not available');
