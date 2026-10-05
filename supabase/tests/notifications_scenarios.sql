\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Notification scenarios: who gets told what, and that nobody can read, write or fake anyone else's.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.code(u text) returns text language sql as $$ select short_code from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.n(u text, k text) returns bigint language sql as $$ select count(*) from public.notifications where profile_id = pg_temp.pid(u) and kind = k $$;

set role authenticated;
select pg_temp.as_user('owner');  select (public.ensure_profile('Asha (owner)', '9000000071')).id is not null;
select pg_temp.as_user('admin');  select (public.ensure_profile('Bala (admin)', '9000000072')).id is not null;
select pg_temp.as_user('buyer');  select (public.ensure_profile('Ravi (buyer)', '9000000073')).id is not null;
select pg_temp.as_user('friend'); select (public.ensure_profile('Meena (friend)', '9000000074')).id is not null;

\echo '== 1. Sync: a request tells the other person, an acceptance tells the requester'
select pg_temp.as_user('buyer');
select request_sync((select id from profiles where short_code = pg_temp.code('friend')));
select pg_temp.as_user('friend');
select pg_temp.check(pg_temp.n('friend', 'SYNC_REQUEST') = 1, 'the addressee is told about the request');
select pg_temp.check((select title from notifications where kind = 'SYNC_REQUEST') = 'Ravi (buyer) wants to sync with you', 'it names who asked');
select pg_temp.check((select route from notifications where kind = 'SYNC_REQUEST') = 'sync', 'and opens Sync');
select pg_temp.check(pg_temp.n('buyer', 'SYNC_REQUEST') = 0, 'the requester is not told about their own request');
update syncs set status = 'ACCEPTED' where addressee_id = me();
select pg_temp.as_user('buyer');
select pg_temp.check(pg_temp.n('buyer', 'SYNC_ACCEPTED') = 1, 'the requester is told it was accepted');

\echo '== 2. Invites: the invitee is told what they were invited to'
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Asha Bakery', 'Bakery', 'JP Nagar', geo(12.9, 77.6), '{}');
select 'invite sent: ' || (invite((select id from listings where title = 'Asha Bakery'), null, pg_temp.code('admin'), 'ADMIN') is not null);
select pg_temp.as_user('admin');
select pg_temp.check((select title from notifications where kind = 'INVITE') = 'Asha (owner) invited you to help run Asha Bakery', 'the invite names who and what');
select respond_invite((select id from invites where invitee_id = me() and status = 'PENDING'), true);

\echo '== 3. Orders: the shop team is told of a new order, the buyer of each change'
reset role; select set_config('request.jwt.claims', '{}', false); update listings set status = 'LIVE', online = true where title = 'Asha Bakery'; set role authenticated;
select pg_temp.as_user('owner'); select pg_temp.check(pg_temp.n('owner', 'LISTING_LIVE') = 1, 'the owner is told the listing is live');
select pg_temp.as_user('admin'); select pg_temp.check(pg_temp.n('admin', 'LISTING_LIVE') = 1, 'so is the admin');
select pg_temp.as_user('owner');
insert into items (listing_id, name, price, unit) values ((select id from listings where title = 'Asha Bakery'), 'Bun', 20, '1 piece');
select pg_temp.as_user('buyer');
select set_config('t.o1', place_order((select id from listings where title = 'Asha Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Bun'), 'qty', 3)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')::text, false) is not null;
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.n('owner', 'ORDER_NEW') = 1, 'the owner is told of the new order');
select pg_temp.check((select title from notifications where kind = 'ORDER_NEW') = 'New order · ₹60', 'with the amount');
select pg_temp.check((select route from notifications where kind = 'ORDER_NEW') = 'orders-for/' || (select id from listings where title = 'Asha Bakery'), 'and opens the shop''s orders');
select pg_temp.as_user('admin'); select pg_temp.check(pg_temp.n('admin', 'ORDER_NEW') = 1, 'the admin is told too');
select pg_temp.as_user('buyer'); select pg_temp.check(pg_temp.n('buyer', 'ORDER_NEW') = 0, 'the buyer is not told about their own order');
select pg_temp.as_user('owner'); select respond_order(current_setting('t.o1')::uuid, true);
select pg_temp.as_user('buyer');
select pg_temp.check((select title from notifications where kind = 'ORDER_UPDATE' order by created_at desc limit 1) = 'Your order from Asha Bakery was accepted', 'the buyer is told it was accepted');
select pg_temp.as_user('owner'); select update_order_status(current_setting('t.o1')::uuid, 'READY');
select pg_temp.as_user('buyer');
select pg_temp.check(pg_temp.n('buyer', 'ORDER_UPDATE') = 2, 'and again when it is ready');
select set_config('t.o2', place_order((select id from listings where title = 'Asha Bakery'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Bun'), 'qty', 1)), 12.93, 77.60, 'home', 'UPI', 'PICKUP')::text, false) is not null;
select cancel_order(current_setting('t.o2')::uuid);
select pg_temp.check(pg_temp.n('buyer', 'ORDER_UPDATE') = 2, 'cancelling your own order does not notify you');
select pg_temp.as_user('owner'); select pg_temp.check(pg_temp.n('owner', 'ORDER_NEW') = 2, 'the shop was told of the second order');

\echo '== 4. Recommendations, going live, documents and reviews reach the right people'
reset role; select set_config('request.jwt.claims', '{}', false);
insert into recommendations (listing_id, recommender_id, at_location) values ((select id from listings where title = 'Asha Bakery'), pg_temp.pid('friend'), geo(12.9, 77.6));
insert into reviews (listing_id, author_id, order_id, vote, comment) values ((select id from listings where title = 'Asha Bakery'), pg_temp.pid('buyer'), current_setting('t.o1')::uuid, 1, 'Fresh buns, quick pickup');
set role authenticated;
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.n('owner', 'RECOMMENDED') = 1, 'the owner is told about a recommendation');
select pg_temp.check((select body from notifications where kind = 'RECOMMENDED') like '1 of %', 'with the count so far');
select pg_temp.check(pg_temp.n('owner', 'REVIEW') = 1 and (select body from notifications where kind = 'REVIEW') = 'Fresh buns, quick pickup', 'and about a review, with its comment');
select pg_temp.as_user('friend'); select pg_temp.check(pg_temp.n('friend', 'RECOMMENDED') = 0, 'the recommender is not told');
select pg_temp.as_user('owner');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Asha Sweets', 'Sweets', 'JP Nagar', geo(12.9, 77.6), '{}');
reset role; select set_config('request.jwt.claims', '{}', false);
insert into listing_documents (listing_id, doc_type, path, number, uploaded_by) values ((select id from listings where title = 'Asha Sweets'), 'OWNER_ID', pg_temp.pid('owner')::text || '/id.jpg', '', pg_temp.pid('owner'));
update listing_documents set status = 'REJECTED', note = 'Photo is blurry' where listing_id = (select id from listings where title = 'Asha Sweets');
update listings set status = 'LIVE' where title = 'Asha Sweets';
update listings set status = 'SUSPENDED', compliance_hold = true where title = 'Asha Sweets';
set role authenticated; select pg_temp.as_user('owner');
select pg_temp.check((select body from notifications where kind = 'DOCUMENT_REJECTED') = 'Asha Sweets: Photo is blurry', 'a rejected document tells the uploader why');
select pg_temp.check((select route from notifications where kind = 'DOCUMENT_REJECTED') like 'listing-docs/%', 'and opens its documents');
select pg_temp.check((select body from notifications where kind = 'LISTING_PAUSED') like 'A document expired%', 'a paused listing says why');

\echo '== 5. Reading: only my own, mark read, delete, and nothing can be faked'
select pg_temp.as_user('buyer');
select pg_temp.check(not exists (select 1 from notifications where profile_id <> pg_temp.pid('buyer')), 'buyer sees only their own notifications');
select pg_temp.check((select count(*) from notifications where read_at is null) = (select count(*) from notifications), 'all of buyer''s are unread to start');
select 'mark one read: ' || mark_notifications_read(array[(select id from notifications order by created_at limit 1)]);
select pg_temp.check((select count(*) from notifications where read_at is not null) = 1, 'exactly one is read');
select 'mark all read: ' || mark_notifications_read();
select pg_temp.check(not exists (select 1 from notifications where read_at is null), 'now none are unread');
select pg_temp.as_user('owner'); select pg_temp.check((select count(*) from notifications where read_at is null) > 0, 'the owner''s were not touched by the buyer marking read');
select pg_temp.as_user('buyer');
select 'insert a fake -> ' || pg_temp.expect_fail(format($$insert into notifications (profile_id, kind, title) values (%L, 'FAKE', 'You won')$$, pg_temp.pid('buyer')), 'permission denied');
select 'edit one -> ' || pg_temp.expect_fail($$update notifications set title = 'x'$$, 'permission denied');
select 'call push_note -> ' || pg_temp.expect_fail(format($$select public.push_note(%L, 'X', 'x', '', null)$$, pg_temp.pid('owner')), 'permission denied');
with d as (delete from notifications where id = (select id from notifications limit 1) returning 1) select 'delete one -> ' || count(*) from d;
select pg_temp.as_user('friend');
with d as (delete from notifications where profile_id = pg_temp.pid('owner') returning 1) select pg_temp.check((select count(*) from d) = 0, 'a stranger can''t delete someone else''s');
