\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Services scenarios: service unlock rules around a customer, "notify me", listing documents (public vs private),
-- the two go-live gates (recommendations + documents), staff review, expiry hold and recovery, search by service.
-- Every check prints "ok, ..." or "FAIL ...".
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.shop() returns uuid language sql as $$ select id from public.listings where title = 'Meghana Biryani' $$;

set role authenticated;
select pg_temp.as_user('owner');    select (public.ensure_profile('Meghana (owner)', '9000000041')).id is not null;
select pg_temp.as_user('buyer');    select (public.ensure_profile('Ravi (customer)', '9000000042')).id is not null;
select pg_temp.as_user('staff1');   select (public.ensure_profile('Bucks staff', '9000000043')).id is not null;
select pg_temp.as_user('stranger'); select (public.ensure_profile('Kiran (nobody)', '9000000044')).id is not null;
select pg_temp.as_user('driver');   select (public.ensure_profile('Imran (cab driver)', '9000000045')).id is not null;
do $$ declare i int; begin for i in 1..7 loop
  perform set_config('request.jwt.claims', format('{"sub":"n%s"}', i), false); perform public.ensure_profile(format('Neighbour %s', i), format('90000001%s', lpad(i::text, 2, '0')));
end loop; end $$;
reset role; insert into staff (profile_id) values (pg_temp.pid('staff1')); set role authenticated;

\echo '== 1. The catalogue: eleven services, readable by everyone signed in'
select pg_temp.as_user('stranger');
select pg_temp.check((select count(*) from service_rules) = 11, 'eleven services: ' || (select string_agg(label, ', ' order by sort) from service_rules));

\echo '== 2. A listing belongs to one service: skills are Gigs, a business follows its choice or its category'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Meghana Biryani', 'Restaurant', 'Jayanagar', geo(12.9250, 77.5938), '{}');
insert into listings (kind, owner_id, title, category, area, location, service) values ('BUSINESS', me(), 'Fresh Cuts', 'Chicken', 'Jayanagar', geo(12.9252, 77.5940), 'MEAT');
insert into listings (kind, owner_id, title, category, area, location, service) values ('SKILL', me(), 'Meghana tutoring', 'Tutor', 'Jayanagar', geo(12.9252, 77.5940), 'FOOD');
select pg_temp.check((select service from listings where title = 'Meghana Biryani') = 'FOOD', 'restaurant category -> FOOD');
select pg_temp.check((select service from listings where title = 'Fresh Cuts') = 'MEAT', 'chosen service kept -> MEAT');
select pg_temp.check((select service from listings where title = 'Meghana tutoring') = 'GIGS', 'a skill is always GIGS');

\echo '== 3. What the team sees: every document the service asks for; strangers see nothing'
select string_agg(doc_type || (case when required then '*' else '' end) || '=' || status, ', ') from listing_compliance(pg_temp.shop());
select pg_temp.as_user('stranger');
select pg_temp.check((select count(*) from listing_compliance(pg_temp.shop())) = 0, 'stranger gets no compliance rows');

\echo '== 4. Submitting documents: checked on the server'
select 'stranger submits -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'FSSAI', 'x/f.pdf', '12345678901234', current_date + 300)$$, pg_temp.shop()), 'listing not found');
select pg_temp.as_user('owner');
select 'file in someone else''s folder -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'FSSAI', %L, '12345678901234', current_date + 300)$$, pg_temp.shop(), pg_temp.pid('buyer')::text || '/f.pdf'), 'upload the file first');
select 'FSSAI with 12 digits -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'FSSAI', %L, '123456789012', current_date + 300)$$, pg_temp.shop(), me()::text || '/f.pdf'), 'valid');
select 'FSSAI without expiry -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'FSSAI', %L, '12345678901234', null)$$, pg_temp.shop(), me()::text || '/f.pdf'), 'expires');
select 'already expired -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'FSSAI', %L, '12345678901234', current_date - 1)$$, pg_temp.shop(), me()::text || '/f.pdf'), 'already expired');
select 'RERA on a restaurant -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'RERA', %L, 'PRM/KA/1', current_date + 300)$$, pg_temp.shop(), me()::text || '/f.pdf'), 'not needed for Food');
select 'bad GSTIN -> ' || pg_temp.expect_fail(format($$select submit_document(%L, 'GSTIN', %L, '29ABCDE1234F1Z', null)$$, pg_temp.shop(), me()::text || '/g.pdf'), 'valid');
select (submit_document(pg_temp.shop(), 'FSSAI', me()::text || '/fssai.pdf', '1234 5678 9012 34', current_date + 300)).status;
select (submit_document(pg_temp.shop(), 'OWNER_ID', me()::text || '/pan.jpg', 'ABCDE1234F', null)).status;
select pg_temp.check((select number from listing_documents where doc_type = 'OWNER_ID') = '', 'ID number is not kept');
select pg_temp.check((select number from listing_documents where doc_type = 'FSSAI') = '12345678901234', 'FSSAI number stored without spaces');
select 'owner writes the table directly -> ' || pg_temp.expect_fail(format($$update listing_documents set status = 'VERIFIED' where listing_id = %L$$, pg_temp.shop()), 'permission denied');

\echo '== 5. Go-live needs both gates: 7 recommendations and verified documents'
reset role;
insert into recommendations (listing_id, recommender_id, at_location) select pg_temp.shop(), id, geo(12.9250, 77.5938) from profiles where auth_uid like 'n_';
select pg_temp.check(try_go_live(pg_temp.shop()) = 'PENDING', 'seven recommendations but documents unchecked -> still PENDING');
set role authenticated;
select pg_temp.as_user('owner');
select 'owner reviews own document -> ' || pg_temp.expect_fail(format($$select review_document(%L, true)$$, (select id from listing_documents where doc_type = 'FSSAI')), 'only Bucks staff');
select pg_temp.as_user('staff1');
select pg_temp.check((select count(*) from documents_to_review()) = 2, 'staff queue has both documents');
select 'reject without a reason -> ' || pg_temp.expect_fail(format($$select review_document(%L, false, '')$$, (select id from listing_documents where doc_type = 'OWNER_ID')), 'say why');
select pg_temp.check(review_document((select id from listing_documents where doc_type = 'FSSAI'), true) = 'PENDING', 'FSSAI verified, ID still pending -> PENDING');
select pg_temp.check(review_document((select id from listing_documents where doc_type = 'OWNER_ID'), true) = 'LIVE', 'ID verified too -> LIVE');
select pg_temp.as_user('stranger');
select pg_temp.check((select count(*) from documents_to_review()) = 0, 'not staff: empty queue');

\echo '== 6. Public vs private: customers get badges, the FSSAI number, never files or the ID'
select pg_temp.as_user('buyer');
select pg_temp.check((select count(*) from listing_documents) = 0, 'buyer reads no document rows');
select 'badges: ' || string_agg(label || coalesce(nullif(' #' || number, ' #'), ''), ', ') from listing_badges(pg_temp.shop());
select pg_temp.check((select number from listing_badges(pg_temp.shop()) where doc_type = 'OWNER_ID') = '', 'ID badge shows no number');
select pg_temp.check(not exists (select 1 from listing_badges(pg_temp.shop()) where doc_type = 'OWNER_ID' and number <> ''), 'no private number leaks');
select pg_temp.as_user('owner');
select pg_temp.check((select count(*) from listing_documents where listing_id = pg_temp.shop()) = 2, 'owner reads own two documents');
select 'remove a verified required document -> ' || pg_temp.expect_fail(format($$select delete_document(%L, 'FSSAI')$$, pg_temp.shop()), 'required');
select (submit_document(pg_temp.shop(), 'GSTIN', me()::text || '/gst.pdf', '29ABCDE1234F1Z5', null)).status;
select delete_document(pg_temp.shop(), 'GSTIN');
select pg_temp.check(not exists (select 1 from listing_documents where doc_type = 'GSTIN'), 'optional document removed');

\echo '== 7. A live listing cannot switch service or clear its own hold'
select 'LIVE -> GROCERY -> ' || pg_temp.expect_fail(format($$update listings set service = 'GROCERY' where id = %L$$, pg_temp.shop()), 'cannot move');
select 'clear hold -> ' || pg_temp.expect_fail(format($$update listings set compliance_hold = true where id = %L$$, pg_temp.shop()), 'managed by Bucks');
update listings set service = 'VEGETABLES' where title = 'Fresh Cuts';
select pg_temp.check((select service from listings where title = 'Fresh Cuts') = 'VEGETABLES', 'a pending listing can change service');

\echo '== 8. Services around the customer: LOCKED -> QUIET -> OPEN, SOON for switched-off ones'
select pg_temp.as_user('buyer');
select string_agg(key || '=' || state || '(' || supply || '/' || min_supply || ')', ' ') from services_near(12.9260, 77.5950);
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'FOOD') = 'LOCKED', 'Food locked with 1 of 10 restaurants');
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'PARCEL') = 'SOON', 'Parcel is switched off -> SOON');
reset role; update service_rules set min_supply = 1 where key = 'FOOD'; set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'FOOD') = 'QUIET', 'enough restaurants but none open -> QUIET');
reset role; update service_rules set min_online = 1 where key = 'FOOD'; update listings set online = true where id = pg_temp.shop(); set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'FOOD') = 'OPEN', 'one open restaurant -> OPEN');
select pg_temp.check((select state from services_near(28.5355, 77.3910) where key = 'FOOD') = 'LOCKED', 'the same service is locked in Noida');
select pg_temp.check((select supply from services_near(12.9260, 77.5950) where key = 'FOOD') = 1, 'supply counts only LIVE listings (the pending one is not counted)');
select pg_temp.check((select not delivery_now from services_near(12.9260, 77.5950) where key = 'FOOD'), 'no bike online -> pickup only');

\echo '== 9. Vehicles: checked cabs that worked here in the last two weeks unlock Taxi; online ones open it'
select pg_temp.as_user('driver');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'CAB', 'Maruti Dzire', 'KA01CB0001');
reset role;
update vehicles set status = 'ACTIVE' where plate = 'KA01CB0001';
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select pg_temp.pid('driver'), id, 'CAB', true, geo(12.9270, 77.5960) from vehicles where plate = 'KA01CB0001';
set role authenticated; select pg_temp.as_user('buyer');
select pg_temp.check((select state || ' ' || supply || '/' || min_supply || ', online ' || online from services_near(12.9260, 77.5950) where key = 'TAXI') = 'LOCKED 1/3, online 1', 'one cab of three -> LOCKED');
reset role; update service_rules set min_supply = 1 where key = 'TAXI'; set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'TAXI') = 'OPEN', 'threshold met and a cab online -> OPEN');
reset role; update driver_presence set online = false; set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'TAXI') = 'QUIET', 'cab went offline -> QUIET, not LOCKED');
reset role; set session_replication_role = replica; update driver_presence set updated_at = now() - interval '15 days'; set session_replication_role = origin; set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'TAXI') = 'LOCKED', 'not seen for two weeks -> no longer counted');
reset role; update service_rules set mode = 'ON' where key = 'AUTO'; set role authenticated;
select pg_temp.check((select state from services_near(12.9260, 77.5950) where key = 'AUTO') = 'QUIET', 'forced ON skips the supply rule but still says nobody is online');

\echo '== 10. Jobs count open jobs of live businesses'
select pg_temp.as_user('owner');
insert into jobs (listing_id, title, created_by) values (pg_temp.shop(), 'Kitchen helper', me());
select pg_temp.as_user('buyer');
select pg_temp.check((select supply from services_near(12.9260, 77.5950) where key = 'JOBS') = 1, 'one open job counted');

\echo '== 11. Notify me: a toggle, counted around the point'
select pg_temp.check(toggle_service_interest('GROCERY', 12.9260, 77.5950), 'joined the Grocery list');
select pg_temp.check((select interested || ' ' || mine from services_near(12.9265, 77.5955) where key = 'GROCERY') = '1 true', 'counted nearby, marked as mine');
select pg_temp.as_user('stranger');
select pg_temp.check((select interested || ' ' || mine from services_near(12.9265, 77.5955) where key = 'GROCERY') = '1 false', 'others see the count, not who');
select pg_temp.check((select count(*) from service_interest) = 0, 'others cannot read the list');
select pg_temp.as_user('buyer');
select pg_temp.check(not toggle_service_interest('GROCERY', 12.9260, 77.5950), 'left the list');
select 'unknown service -> ' || pg_temp.expect_fail($$select toggle_service_interest('SPACE', 1, 1)$$, 'unknown service');

\echo '== 12. Search by service'
select pg_temp.check((select count(*) from search_listings('', 12.9260, 77.5950, 10000, null, 40, array['FOOD'])) = 1, 'Food tile finds the restaurant');
select pg_temp.check((select count(*) from search_listings('', 12.9260, 77.5950, 10000, null, 40, array['GROCERY'])) = 0, 'Grocery finds nothing');
select pg_temp.check((select count(*) from search_listings('', 12.9260, 77.5950, 10000, array['BUSINESS'])) = 1, 'old call shape still works');

\echo '== 13. Expiry: 7 days of grace, then held until a new document is verified'
reset role; update listing_documents set expires_on = current_date - 3 where doc_type = 'FSSAI'; select expire_documents(); set role authenticated;
select pg_temp.check((select status from listings where id = pg_temp.shop()) = 'LIVE', 'expired 3 days ago -> still LIVE (grace)');
select pg_temp.as_user('owner');
select pg_temp.check((select status from listing_compliance(pg_temp.shop()) where doc_type = 'FSSAI') = 'EXPIRED', 'team sees EXPIRED');
select pg_temp.as_user('buyer');
select pg_temp.check(not exists (select 1 from listing_badges(pg_temp.shop()) where doc_type = 'FSSAI'), 'expired badge no longer shown');
reset role; update listing_documents set expires_on = current_date - 9 where doc_type = 'FSSAI'; select expire_documents();
select pg_temp.check((select status || ' hold=' || compliance_hold from listings where id = pg_temp.shop()) = 'SUSPENDED hold=true', 'past grace -> SUSPENDED and held');
set role authenticated;
select pg_temp.check((select count(*) from search_listings('', 12.9260, 77.5950, 10000, null, 40, array['FOOD'])) = 0, 'held listing is out of search');
select pg_temp.as_user('owner');
select (submit_document(pg_temp.shop(), 'FSSAI', me()::text || '/fssai-2027.pdf', '12345678901234', current_date + 700)).status;
select pg_temp.as_user('staff1');
select pg_temp.check(review_document((select id from listing_documents where doc_type = 'FSSAI'), true) = 'LIVE', 'new FSSAI verified -> LIVE again');
select pg_temp.check((select not compliance_hold from listings where id = pg_temp.shop()), 'hold cleared');

\echo '== 14. Signed-out callers and account deletion'
reset role; set role anon;
select 'anon services_near -> ' || pg_temp.expect_fail($$select * from services_near(12.9, 77.5)$$, 'permission denied');
reset role; set role authenticated;
select pg_temp.as_user('buyer'); select toggle_service_interest('MEAT', 12.9260, 77.5950);
reset role; update profiles set status = 'DELETED' where auth_uid = 'buyer';
select pg_temp.check(not exists (select 1 from service_interest where profile_id = pg_temp.pid('buyer')), 'deleted account leaves no notify-me pins');
