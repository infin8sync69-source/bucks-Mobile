\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.code(u text) returns text language sql as $$ select short_code from public.profiles where auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('shop');   select (public.ensure_profile('Asha', '9000000021')).id is not null;
select pg_temp.as_user('helper'); select (public.ensure_profile('Bala', '9000000022')).id is not null;
select pg_temp.as_user('driver'); select (public.ensure_profile('Ravi', '9000000023')).id is not null;
select pg_temp.as_user('other');  select (public.ensure_profile('Meena', '9000000024')).id is not null;

\echo '== 1. A listing invite shows the listing name and inviter to the invitee, who cannot see the pending listing itself'
select pg_temp.as_user('shop');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Asha Stores', 'Grocery', 'JP Nagar', geo(12.9063, 77.5857));
select 'invite sent: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('helper'), 'STORE_RIDER') is not null);
select 'invite yourself -> ' || pg_temp.expect_fail(format('select invite(%L, null, %L, %L)', (select id from listings where title = 'Asha Stores'), pg_temp.code('shop'), 'ADMIN'), 'already own');
select 'unknown Bucks ID -> ' || pg_temp.expect_fail(format('select invite(%L, null, %L, %L)', (select id from listings where title = 'Asha Stores'), 'ZZZZZZZZ', 'ADMIN'), 'no one has');
select pg_temp.as_user('helper');
select 'helper reads the pending listing directly: ' || count(*) || ' rows' from listings where title = 'Asha Stores';
select 'helper my_invites: ' || title || ' (' || kind || ') as ' || role || ' from ' || inviter_name from my_invites();
select pg_temp.as_user('other');
select 'someone else my_invites: ' || count(*) from my_invites();
select pg_temp.as_user('helper');
select respond_invite((select id from my_invites()), true);
select 'after accepting: ' || count(*) || ' pending, role now ' || coalesce(listing_role((select id from listings where title = 'Asha Stores')), '-') from my_invites();
select 'store rider deletes the listing: ' || count(*) from (select 1) x where false; delete from listings where title = 'Asha Stores';
reset role; select 'listing still there: ' || count(*) from listings where title = 'Asha Stores'; set role authenticated;

\echo '== 2. Vehicle invite shows model and plate; only the owner can change documents; admins can drive it'
select pg_temp.as_user('driver');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01AB1111');
update vehicles set docs = '[{"kind": "RC", "path": "x/rc.jpg"}]' where plate = 'KA01AB1111';
select 'owner docs: ' || docs::text from vehicles where plate = 'KA01AB1111';
select 'owner sets ACTIVE -> ' || pg_temp.expect_fail($$update vehicles set status = 'ACTIVE' where plate = 'KA01AB1111'$$, 'managed by Bucks');
select 'store rider on a vehicle -> ' || pg_temp.expect_fail(format('select invite(null, %L, %L, %L)', (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('helper'), 'STORE_RIDER'), 'only have admins');
select 'vehicle invite sent: ' || (invite(null, (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('helper'), 'ADMIN') is not null);
select pg_temp.as_user('helper');
select 'helper my_invites: ' || title || ' (' || kind || ') as ' || role || ' from ' || inviter_name from my_invites();
select respond_invite((select id from my_invites()), true);
select 'helper sees the vehicle: ' || count(*) || ', role ' || vehicle_role(id) from vehicles where plate = 'KA01AB1111' group by id;
select 'helper sees vehicle members: ' || count(*) from vehicle_members where vehicle_id = (select id from vehicles where plate = 'KA01AB1111');
update vehicles set docs = '[]' where plate = 'KA01AB1111';
select 'docs after admin attempt: ' || docs::text from vehicles where plate = 'KA01AB1111';
select 'admin invites someone -> ' || pg_temp.expect_fail(format('select invite(null, %L, %L, %L)', (select id from vehicles where plate = 'KA01AB1111'), pg_temp.code('other'), 'ADMIN'), 'only the owner');
select 'admin leaves: ' || count(*) from (select 1) x where false; delete from vehicle_members where vehicle_id = (select id from vehicles where plate = 'KA01AB1111') and profile_id = me();
select 'helper sees the vehicle after leaving: ' || count(*) from vehicles where plate = 'KA01AB1111';

\echo '== 3. Declined and revoked invites disappear; the owner sees pending invites they sent'
select pg_temp.as_user('shop');
select 'invite Ravi as admin: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('driver'), 'ADMIN') is not null);
select 'invite Meena as admin: ' || (invite((select id from listings where title = 'Asha Stores'), null, pg_temp.code('other'), 'ADMIN') is not null);
select 'owner pending invites sent: ' || count(*) from invites where status = 'PENDING' and inviter_id = me();
update invites set status = 'REVOKED' where invitee_id = pg_temp.pid('other') and status = 'PENDING';
select 'owner sets ACCEPTED directly -> ' || pg_temp.expect_fail(format($$update invites set status = 'ACCEPTED' where invitee_id = %L$$, pg_temp.pid('driver')), 'row-level security');
select pg_temp.as_user('other');
select 'Meena after revoke: ' || count(*) from my_invites();
select pg_temp.as_user('driver');
select 'Ravi sees: ' || title || ' as ' || role from my_invites();
select respond_invite((select id from my_invites()), false);
select 'Ravi after declining: ' || count(*) || ' pending, role ' || coalesce(listing_role((select id from listings where title = 'Asha Stores')), 'none') from my_invites();
select 'respond twice -> ' || pg_temp.expect_fail(format('select respond_invite(%L, true)', (select id from invites where invitee_id = pg_temp.pid('driver'))), 'not found');

\echo '== 4. Recommendation counts are readable for the owner''s own pending listing; tokens are not'
select pg_temp.as_user('shop');
select 'token: ' || (recommend_token((select id from listings where title = 'Asha Stores')) is not null);
select 'count: ' || count(*) from recommendations where listing_id = (select id from listings where title = 'Asha Stores');
select 'read tokens -> ' || pg_temp.expect_fail('select count(*) from recommend_tokens', 'permission denied');

\echo '== 5. Recommendation rows (who, and where they stood) are visible to the team and the recommender only'
reset role;
insert into recommendations (listing_id, recommender_id, at_location) values ((select id from listings where title = 'Asha Stores'), pg_temp.pid('other'), geo(12.9063, 77.5857));
set role authenticated;
select pg_temp.as_user('shop');   select 'owner sees: ' || count(*) from recommendations;
select pg_temp.as_user('helper'); select 'store rider sees: ' || count(*) from recommendations;
select pg_temp.as_user('other');  select 'recommender sees own: ' || count(*) from recommendations;
select pg_temp.as_user('driver'); select 'stranger sees: ' || count(*) from recommendations;

\echo '== 6. Home positions are private: the API reads every profile column except home'
select pg_temp.as_user('other');
select 'stranger reads homes -> ' || pg_temp.expect_fail('select home from profiles', 'permission denied');
select 'select * -> ' || pg_temp.expect_fail('select * from profiles', 'permission denied');
select 'named columns work: ' || name || ' ' || short_code || ' (' || trust_up || ')' from profiles where id = pg_temp.pid('shop');
update profiles set home = geo(12.9065, 77.5860), area = 'JP Nagar' where id = me();
reset role; select 'own home saved: ' || extensions.st_astext(home::extensions.geometry) from profiles where auth_uid = 'other'; set role authenticated;

\echo '== 7. Changing a checked vehicle''s type, plate or documents restarts the check; other edits do not'
reset role; update vehicles set status = 'ACTIVE', docs = '[{"kind": "RC", "path": "x/rc.jpg"}, {"kind": "INSURANCE", "path": "x/ins.pdf"}]' where plate = 'KA01AB1111'; set role authenticated;
select pg_temp.as_user('driver');
update vehicles set model = 'Bajaj RE Compact' where plate = 'KA01AB1111';
select 'model edit: ' || status from vehicles where plate = 'KA01AB1111';
update vehicles set docs = '[{"path": "x/ins.pdf", "kind": "INSURANCE"}, {"path": "x/rc.jpg", "kind": "RC"}]' where plate = 'KA01AB1111';
select 'same documents, other order: ' || status from vehicles where plate = 'KA01AB1111';
update vehicles set docs = '[{"kind": "RC", "path": "x/rc2.jpg"}, {"kind": "INSURANCE", "path": "x/ins.pdf"}]' where plate = 'KA01AB1111';
select 'new RC photo: ' || status from vehicles where plate = 'KA01AB1111';
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01AB1111'; set role authenticated;
update vehicles set plate = 'KA01AB2222' where plate = 'KA01AB1111';
select 'new plate: ' || status from vehicles where plate = 'KA01AB2222';
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01AB2222'; set role authenticated;
update vehicles set kind = 'CAB' where plate = 'KA01AB2222';
select 'auto became a cab: ' || status from vehicles where plate = 'KA01AB2222';
select 'owner sets ACTIVE back -> ' || pg_temp.expect_fail($$update vehicles set status = 'ACTIVE' where plate = 'KA01AB2222'$$, 'managed by Bucks');

\echo '== 8. Only a checked vehicle can go online; going offline is always allowed'
select 'pending vehicle online -> ' || pg_temp.expect_fail($$insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, kind, true, geo(12.9250, 77.5938) from vehicles where plate = 'KA01AB2222'$$, 'row-level security');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01AB2222'; set role authenticated;
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, kind, true, geo(12.9250, 77.5938) from vehicles where plate = 'KA01AB2222';
select 'active vehicle online: ' || count(*) from driver_presence where profile_id = me() and online;
reset role; update vehicles set status = 'SUSPENDED' where plate = 'KA01AB2222'; set role authenticated;
update driver_presence set online = false where profile_id = me();
select 'suspended vehicle goes offline: ' || count(*) from driver_presence where profile_id = me() and not online;
select 'suspended vehicle back online -> ' || pg_temp.expect_fail($$update driver_presence set online = true where profile_id = me()$$, 'row-level security');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01AB2222'; set role authenticated;

\echo '== 9. A vehicle that has taken trips can be removed; the trips stay with the driver'
reset role;
insert into tasks (type, requester_id, vehicle_kind, pickup, drop_at, status, driver_id, vehicle_id)
  values ('RIDE', pg_temp.pid('other'), 'CAB', geo(12.9250, 77.5938), geo(12.9757, 77.6063), 'COMPLETED', pg_temp.pid('driver'), (select id from vehicles where plate = 'KA01AB2222'));
insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) select id, driver_id, vehicle_id, 'COMPLETED', 7.2, 106 from tasks where driver_id = pg_temp.pid('driver');
set role authenticated;
select pg_temp.as_user('driver');
select 'dashboard before: ' || completed || ' trip, ₹' || earnings from vehicle_stats where plate = 'KA01AB2222';
delete from vehicles where plate = 'KA01AB2222';
select 'vehicle gone: ' || count(*) from vehicles where plate = 'KA01AB2222';
select 'driver still sees the trip: ' || count(*) || ', event ' || (select event from task_events where driver_id = me()) from tasks where driver_id = me();
reset role;
select 'trip records kept, vehicle cleared: ' || count(*) || ' task(s), vehicle ' || coalesce(max(vehicle_id::text), 'none') from tasks where driver_id = pg_temp.pid('driver');
select 'presence row gone with it: ' || count(*) from driver_presence where profile_id = pg_temp.pid('driver');
set role authenticated;

\echo '== 10. Deleting a business: outright when it never sold; hidden but kept for the buyers'' history once it has; never with open orders'
select pg_temp.as_user('shop');
insert into listings (kind, owner_id, title, category, area, location) values ('SKILL', me(), 'Asha Tailoring', 'Tailor', 'JP Nagar', geo(12.9063, 77.5857));
select delete_listing((select id from listings where title = 'Asha Tailoring'));
reset role; select 'skill with no orders is gone: ' || count(*) from listings where title = 'Asha Tailoring';
update listings set status = 'LIVE', online = true where title = 'Asha Stores'; set role authenticated;
insert into items (listing_id, name, price, unit) select id, 'Sugar', 45, '1 kg' from listings where title = 'Asha Stores';
select pg_temp.as_user('other');
select set_config('t.order', place_order((select id from listings where title = 'Asha Stores'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Sugar'), 'qty', 2)), 12.9070, 77.5860, 'Home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.as_user('helper');
select 'store rider deletes -> ' || pg_temp.expect_fail(format('select delete_listing(%L)', (select id from listings where title = 'Asha Stores')), 'only the owner');
select pg_temp.as_user('shop');
select 'open order -> ' || pg_temp.expect_fail(format('select delete_listing(%L)', (select id from listings where title = 'Asha Stores')), 'orders in progress');
select respond_order(current_setting('t.order')::uuid, false);
select set_config('t.listing', id::text, false) is not null from listings where title = 'Asha Stores';
select delete_listing(current_setting('t.listing')::uuid);
select 'owner no longer sees it: ' || count(*) || ' listing, role ' || coalesce(listing_role(current_setting('t.listing')::uuid), 'none') from listings where title = 'Asha Stores';
select pg_temp.as_user('helper'); select 'store rider no longer sees it: ' || count(*) || ' listing, role ' || coalesce(listing_role(current_setting('t.listing')::uuid), 'none') from listings where title = 'Asha Stores';
select pg_temp.as_user('other');  select 'buyer keeps the order: ' || status || ' at ' || (select count(*) from listings where title = 'Asha Stores') || ' visible listing' from orders where id = current_setting('t.order')::uuid;
reset role;
select 'kept as: ' || status || ', online ' || online || ', ' || (select count(*) from items where listing_id = l.id) || ' items, ' || (select count(*) from listing_members where listing_id = l.id) || ' members, ' || (select count(*) from recommendations where listing_id = l.id) || ' recommendations' from listings l where title = 'Asha Stores';
select 'hidden from search: ' || count(*) from search_listings('Asha', 12.9063, 77.5857, 10000);
