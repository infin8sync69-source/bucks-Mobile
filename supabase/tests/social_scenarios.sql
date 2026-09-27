\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('priya'); select (public.ensure_profile('Priya', '9000000011')).id is not null;
select pg_temp.as_user('arun');  select (public.ensure_profile('Arun', '9000000012')).id is not null;
select pg_temp.as_user('meera'); select (public.ensure_profile('Meera', '9000000013')).id is not null;
select pg_temp.as_user('troll'); select (public.ensure_profile('Troll', '9000000014')).id is not null;
reset role; update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('priya', 'arun', 'meera', 'troll'); set role authenticated;

\echo '== 1. Messaging needs a sync by default; sync by Bucks ID; then chat works'
select pg_temp.as_user('arun');
select 'DM a stranger -> ' || pg_temp.expect_fail(format('select start_direct(%L)', pg_temp.pid('priya')), 'synced');
select 'sync request: ' || request_sync((select id from profiles where short_code = (select short_code from profiles where auth_uid = 'priya')));
select pg_temp.as_user('priya');
select 'Priya syncs back (auto-accepts): ' || request_sync(pg_temp.pid('arun'));
select set_config('t.conv', start_direct(pg_temp.pid('arun'))::text, false) is not null;
select 'same chat reused: ' || (start_direct(pg_temp.pid('arun'))::text = current_setting('t.conv'));
insert into messages (conversation_id, sender_id, body) values (current_setting('t.conv')::uuid, me(), 'Hi Arun, still coming at 6?');
insert into messages (conversation_id, sender_id, body, attachment) values (current_setting('t.conv')::uuid, me(), '', '{"path": "x/menu.pdf", "name": "menu.pdf", "mime": "application/pdf", "size": 120000}');
select pg_temp.as_user('arun');
select 'Arun inbox: ' || other_name || ' | "' || last_body || '" | unread ' || unread from inbox();
select 'Arun reads messages: ' || count(*) from messages where conversation_id = current_setting('t.conv')::uuid;
select mark_read(current_setting('t.conv')::uuid);
select 'unread after reading: ' || unread from inbox();
insert into messages (conversation_id, sender_id, body) values (current_setting('t.conv')::uuid, me(), 'Yes, see you!');
select pg_temp.as_user('priya'); select 'Priya sees "seen": ' || (seen_up_to(current_setting('t.conv')::uuid) is not null);
select pg_temp.as_user('meera');
select 'outsider reads the chat: ' || count(*) from messages where conversation_id = current_setting('t.conv')::uuid;
select 'outsider posts into it -> ' || pg_temp.expect_fail(format($$insert into messages (conversation_id, sender_id, body) values (%L, me(), 'hi')$$, current_setting('t.conv')), 'row-level security');

\echo '== 2. Edit and delete a message; read receipts can be turned off'
select pg_temp.as_user('arun');
update messages set body = 'Yes, see you at 6!' where sender_id = me(); select 'edited: ' || (edited_at is not null) from messages where sender_id = me();
update messages set deleted_at = now() where sender_id = me(); select 'deleted shows as: "' || body || '"' from messages where sender_id = me();
insert into user_settings (profile_id, read_receipts) values (me(), false);
select pg_temp.as_user('priya'); select 'Priya sees "seen" after Arun turns receipts off: ' || coalesce(seen_up_to(current_setting('t.conv')::uuid)::text, 'no');

\echo '== 3. File sharing: chat files only for members'
reset role; insert into storage.objects (bucket_id, name) values ('chat', current_setting('t.conv') || '/menu.pdf'); set role authenticated;
select pg_temp.as_user('arun');  select 'member sees chat file: ' || count(*) from storage.objects where bucket_id = 'chat';
select pg_temp.as_user('meera'); select 'outsider sees chat file: ' || count(*) from storage.objects where bucket_id = 'chat';
select 'outsider uploads into the chat -> ' || pg_temp.expect_fail(format($$insert into storage.objects (bucket_id, name) values ('chat', %L)$$, current_setting('t.conv') || '/x.jpg'), 'row-level security');

\echo '== 4. Blocking ends the sync and stops messages'
select pg_temp.as_user('troll');
select request_sync(pg_temp.pid('meera'));
select pg_temp.as_user('meera');
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('troll'));
select pg_temp.as_user('troll');
select 'blocked user syncs again -> ' || pg_temp.expect_fail(format('select request_sync(%L)', pg_temp.pid('meera')), 'cannot sync');
select 'blocked user DMs -> ' || pg_temp.expect_fail(format('select start_direct(%L)', pg_temp.pid('meera')), 'cannot message');
select pg_temp.as_user('meera');
insert into user_settings (profile_id, who_can_message) values (me(), 'EVERYONE');
select pg_temp.as_user('troll');
select 'still blocked even though Meera allows everyone -> ' || pg_temp.expect_fail(format('select start_direct(%L)', pg_temp.pid('meera')), 'cannot message');

\echo '== 5. Feed: local, synced-only and public posts; votes and comments are counted by the database'
select pg_temp.as_user('priya');
insert into posts (author_id, body, visibility, location, area) values (me(), 'Any good tailor near JP Nagar?', 'LOCAL', geo(12.9063, 77.5857), 'JP Nagar');
insert into posts (author_id, body, visibility) values (me(), 'Just for my synced people', 'SYNCED');
select pg_temp.as_user('arun');
select 'Arun (synced, nearby) feed: ' || string_agg(body, ' / ' order by created_at) from feed(12.9063, 77.5857);
insert into post_votes values ((select id from posts where body like 'Any good tailor%'), me(), 1);
insert into post_comments (post_id, author_id, body) values ((select id from posts where body like 'Any good tailor%'), me(), 'Try Raju Tailors, 9th cross');
select 'counts: up ' || up || ', comments ' || comments from posts where body like 'Any good tailor%';
select 'forge counts -> ' || pg_temp.expect_fail($$insert into posts (author_id, body, up) values (me(), 'fake', 999)$$, 'row-level security');
select pg_temp.as_user('meera');
select 'Meera (nearby, not synced) feed: ' || string_agg(body, ' / ') from feed(12.9063, 77.5857);
select 'Meera far away (Delhi): ' || count(*) from feed(28.61, 77.20);

\echo '== 6. Moments: 24 hours, audience, tray with unseen, viewers, reply goes to chat'
select pg_temp.as_user('priya');
insert into moments (author_id, media_path, caption, audience) values (me(), pg_temp.pid('priya') || '/sunset.jpg', 'Sunset at Lalbagh', 'SYNCED');
insert into moments (author_id, media_path, caption, audience, location) values (me(), pg_temp.pid('priya') || '/market.jpg', 'Sunday market', 'LOCAL', geo(12.9063, 77.5857));
select 'post a 3-day moment -> ' || pg_temp.expect_fail(format($$insert into moments (author_id, media_path, expires_at) values (me(), 'x', now() + interval '3 days')$$), 'row-level security');
select pg_temp.as_user('arun');
select 'Arun tray: ' || author_name || ' ' || moments || ' moments, ' || unseen || ' unseen' from moments_tray(12.9063, 77.5857) where not is_me;
select view_moment((select id from moments where caption = 'Sunset at Lalbagh'), '🔥');
select 'after viewing one: unseen ' || unseen from moments_tray(12.9063, 77.5857) where not is_me;
select 'reply lands in chat: ' || (reply_to_moment((select id from moments where caption = 'Sunset at Lalbagh'), 'Beautiful!') = current_setting('t.conv')::uuid);
select pg_temp.as_user('meera');
select 'Meera nearby sees only the LOCAL moment: ' || string_agg(caption, ', ') from moments_of(pg_temp.pid('priya'), 12.9063, 77.5857);
select pg_temp.as_user('priya');
select 'Priya sees viewers: ' || name || ' reacted ' || coalesce(reaction, '-') from moment_viewers((select id from moments where caption = 'Sunset at Lalbagh'));
reset role; update moments set expires_at = now() - interval '2 hours'; set role authenticated;
select pg_temp.as_user('arun'); select 'tray after 24h: ' || count(*) from moments_tray(12.9063, 77.5857) where not is_me;
reset role; select 'expired moments cleaned: ' || expire_moments(); set role authenticated;

\echo '== 7. Suggestions: people you may know'
select pg_temp.as_user('meera');
select 'Meera suggestions: ' || string_agg(name || ' (' || mutual || ' mutual)', ', ') from suggest_people(12.9063, 77.5857);
select pg_temp.as_user('arun'); insert into user_settings (profile_id) values (me()) on conflict (profile_id) do update set discoverable = false;
select pg_temp.as_user('meera');
select 'after Arun hides himself: ' || string_agg(name, ', ') from suggest_people(12.9063, 77.5857);
