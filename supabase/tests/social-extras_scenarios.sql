\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('gpriya'); select (public.ensure_profile('Priya', '9000000021')).id is not null;
select pg_temp.as_user('garun');  select (public.ensure_profile('Arun', '9000000022')).id is not null;
select pg_temp.as_user('gmeera'); select (public.ensure_profile('Meera', '9000000023')).id is not null;
select pg_temp.as_user('gravi');  select (public.ensure_profile('Ravi', '9000000024')).id is not null;
reset role; update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('gpriya', 'garun', 'gmeera', 'gravi'); set role authenticated;

\echo '== 1. A group takes only synced people at creation'
select pg_temp.as_user('gpriya'); select request_sync(pg_temp.pid('garun')) is not null;
select pg_temp.as_user('garun');  select 'Arun syncs back: ' || request_sync(pg_temp.pid('gpriya'));
select pg_temp.as_user('gpriya');
select set_config('t.grp', create_group('Street cricket', array[pg_temp.pid('garun'), pg_temp.pid('gmeera')])::text, false) is not null;
select 'members after create (Meera not synced, so left out): ' || count(*) from conversation_members where conversation_id = current_setting('t.grp')::uuid;
select 'Priya is admin: ' || role from conversation_members where conversation_id = current_setting('t.grp')::uuid and profile_id = me();
select 'inbox shows kind/title: ' || kind || ' / ' || title from inbox() where conversation_id = current_setting('t.grp')::uuid;
select 'conversation row readable by a member: ' || count(*) from conversations where id = current_setting('t.grp')::uuid;

\echo '== 2. Sender names: messages from two people in the group'
insert into messages (conversation_id, sender_id, body) values (current_setting('t.grp')::uuid, me(), 'Match at 6 on Sunday?');
select pg_temp.as_user('garun');
insert into messages (conversation_id, sender_id, body) values (current_setting('t.grp')::uuid, me(), 'Count me in');
select 'distinct senders: ' || count(distinct sender_id) from messages where conversation_id = current_setting('t.grp')::uuid;

\echo '== 3. Adding people later: synced only, no strangers, no duplicates, members only'
select pg_temp.as_user('garun'); select request_sync(pg_temp.pid('gmeera')) is not null;
select pg_temp.as_user('gmeera'); select 'Meera syncs with Arun: ' || request_sync(pg_temp.pid('garun'));
select 'outsider adds herself -> ' || pg_temp.expect_fail(format('select add_group_members(%L, array[%L]::uuid[])', current_setting('t.grp'), pg_temp.pid('gmeera')), 'not in this group');
select pg_temp.as_user('gpriya');
select 'Priya adds Meera (not synced with Priya): ' || add_group_members(current_setting('t.grp')::uuid, array[pg_temp.pid('gmeera')]);
select pg_temp.as_user('garun');
select 'Arun (member, synced with Meera) adds Meera: ' || add_group_members(current_setting('t.grp')::uuid, array[pg_temp.pid('gmeera')]);
select 'adding again: ' || add_group_members(current_setting('t.grp')::uuid, array[pg_temp.pid('gmeera'), pg_temp.pid('gravi')]);
select 'members now: ' || count(*) from conversation_members where conversation_id = current_setting('t.grp')::uuid;
select pg_temp.as_user('gmeera');
select 'Meera reads the history: ' || count(*) from messages where conversation_id = current_setting('t.grp')::uuid;
select 'Meera sees every member: ' || count(*) from conversation_members where conversation_id = current_setting('t.grp')::uuid;

\echo '== 4. Rename: any member may rename a group, nobody renames a direct chat'
select pg_temp.as_user('gmeera');
update conversations set title = 'Sunday cricket' where id = current_setting('t.grp')::uuid;
select 'renamed by a member: ' || title from conversations where id = current_setting('t.grp')::uuid;
select pg_temp.as_user('gpriya');
select set_config('t.dm', start_direct(pg_temp.pid('garun'))::text, false) is not null;
update conversations set title = 'Hacked' where id = current_setting('t.dm')::uuid;
select 'direct chat title after a rename attempt: ' || coalesce(title, '(none)') from conversations where id = current_setting('t.dm')::uuid;

\echo '== 5. Remove and leave'
select pg_temp.as_user('gmeera');
select 'non-admin removes Arun -> ' || pg_temp.expect_fail(format('select remove_group_member(%L, %L)', current_setting('t.grp'), pg_temp.pid('garun')), 'admin');
select pg_temp.as_user('gpriya');
select 'admin removes self -> ' || pg_temp.expect_fail(format('select remove_group_member(%L, %L)', current_setting('t.grp'), pg_temp.pid('gpriya')), 'leave');
select remove_group_member(current_setting('t.grp')::uuid, pg_temp.pid('gmeera'));
select 'after removing Meera: ' || count(*) from conversation_members where conversation_id = current_setting('t.grp')::uuid;
select pg_temp.as_user('gmeera');
select 'Meera reads after removal: ' || count(*) from messages where conversation_id = current_setting('t.grp')::uuid;
select 'Meera posts after removal -> ' || pg_temp.expect_fail(format($$insert into messages (conversation_id, sender_id, body) values (%L, me(), 'still here?')$$, current_setting('t.grp')), 'row-level security');
select pg_temp.as_user('garun');
delete from conversation_members where conversation_id = current_setting('t.grp')::uuid and profile_id = me();
select 'Arun left; his inbox rows for the group: ' || count(*) from inbox() where conversation_id = current_setting('t.grp')::uuid;
with x as (delete from conversation_members where conversation_id = current_setting('t.grp')::uuid and profile_id = pg_temp.pid('gpriya') returning 1) select 'Arun deletes someone else''s row: ' || count(*) from x;
select pg_temp.as_user('gpriya');
select 'Priya still in: ' || count(*) from conversation_members where conversation_id = current_setting('t.grp')::uuid and profile_id = me();
select 'remove on a direct chat -> ' || pg_temp.expect_fail(format('select remove_group_member(%L, %L)', current_setting('t.dm'), pg_temp.pid('garun')), 'only groups');
select 'add to a direct chat -> ' || pg_temp.expect_fail(format('select add_group_members(%L, array[%L]::uuid[])', current_setting('t.dm'), pg_temp.pid('garun')), 'only groups');

\echo '== 6. Muted moments: hidden from the tray, back after unmute, list is mine only'
select pg_temp.as_user('garun');
insert into moments (author_id, media_path, media_type, caption, audience) values (me(), pg_temp.pid('garun') || '/clip.mp4', 'VIDEO', 'Nets practice', 'SYNCED');
select pg_temp.as_user('gpriya');
select 'Priya tray: ' || string_agg(author_name, ', ') from moments_tray(12.9063, 77.5857) where not is_me;
insert into moment_mutes (profile_id, muted_id) values (me(), pg_temp.pid('garun'));
select 'after mute: ' || coalesce(string_agg(author_name, ', '), '(nobody)') from moments_tray(12.9063, 77.5857) where not is_me;
select 'my mutes: ' || count(*) from moment_mutes;
select pg_temp.as_user('gmeera'); select 'Meera sees Priya''s mutes: ' || count(*) from moment_mutes;
select pg_temp.as_user('gpriya');
delete from moment_mutes where profile_id = me() and muted_id = pg_temp.pid('garun');
select 'after unmute: ' || string_agg(author_name || ' (' || moments || ' moment)', ', ') from moments_tray(12.9063, 77.5857) where not is_me;
select 'video moment kept its type: ' || media_type from moments_of(pg_temp.pid('garun'), 12.9063, 77.5857);

\echo '== 7. Members change only their own read/mute/archive state, never their role'
select pg_temp.as_user('gpriya');
select set_config('t.grp2', create_group('Tea stall', array[pg_temp.pid('garun')])::text, false) is not null;
select pg_temp.as_user('garun');
select 'member makes himself admin -> ' || pg_temp.expect_fail(format($$update conversation_members set role = 'ADMIN' where conversation_id = %L and profile_id = me()$$, current_setting('t.grp2')), 'not allowed');
select 'member moves his row to another chat -> ' || pg_temp.expect_fail(format($$update conversation_members set conversation_id = %L where conversation_id = %L and profile_id = me()$$, current_setting('t.dm'), current_setting('t.grp2')), 'not allowed');
select 'Arun is still: ' || role from conversation_members where conversation_id = current_setting('t.grp2')::uuid and profile_id = me();
with x as (update conversation_members set muted_until = '2999-01-01', archived = true where conversation_id = current_setting('t.grp2')::uuid and profile_id = me() returning 1) select 'mute and archive still work: ' || count(*) from x;
select 'marking read still works: ' || (mark_read(current_setting('t.grp2')::uuid) is null);
select 'so he cannot remove the creator -> ' || pg_temp.expect_fail(format('select remove_group_member(%L, %L)', current_setting('t.grp2'), pg_temp.pid('gpriya')), 'admin');
select pg_temp.as_user('gpriya');
select 'Priya still in and admin: ' || role from conversation_members where conversation_id = current_setting('t.grp2')::uuid and profile_id = me();

\echo '== 8. Members rename a group and change nothing else about it'
select pg_temp.as_user('garun');
select 'member sets direct_key -> ' || pg_temp.expect_fail(format($$update conversations set direct_key = 'x:y' where id = %L$$, current_setting('t.grp2')), 'permission denied');
select 'member sets created_by -> ' || pg_temp.expect_fail(format($$update conversations set created_by = me() where id = %L$$, current_setting('t.grp2')), 'permission denied');
select 'member sets last_message_at -> ' || pg_temp.expect_fail(format($$update conversations set last_message_at = '2999-01-01' where id = %L$$, current_setting('t.grp2')), 'permission denied');
select 'member sets kind -> ' || pg_temp.expect_fail(format($$update conversations set kind = 'DIRECT' where id = %L$$, current_setting('t.grp2')), 'permission denied');
update conversations set title = 'Tea at 5' where id = current_setting('t.grp2')::uuid;
select 'rename still works: ' || title || ', direct_key ' || coalesce(direct_key, '(none)') from conversations where id = current_setting('t.grp2')::uuid;
insert into messages (conversation_id, sender_id, body) values (current_setting('t.grp2')::uuid, me(), 'On my way');
select 'last_message_at follows the message: ' || (c.last_message_at = m.created_at) from conversations c join messages m on m.conversation_id = c.id where c.id = current_setting('t.grp2')::uuid;

\echo '== 9. Listing inbox: the people who run it see each customer; customers see the listing'
select pg_temp.as_user('gpriya');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Priya Stores', 'Grocery', 'Jayanagar', geo(12.9063, 77.5857));
reset role; update listings set status = 'LIVE' where title = 'Priya Stores'; set role authenticated;
select pg_temp.as_user('garun');
select set_config('t.lc1', start_listing_chat((select id from listings where title = 'Priya Stores'))::text, false) is not null;
select 'Arun (customer) inbox: ' || title || ' / other ' || coalesce(other_name, '(none)') from inbox() where conversation_id = current_setting('t.lc1')::uuid;
select pg_temp.as_user('gmeera');
select set_config('t.lc2', start_listing_chat((select id from listings where title = 'Priya Stores'))::text, false) is not null;
select pg_temp.as_user('gpriya');
select 'Priya (owner) inbox: ' || string_agg(other_name || ' about ' || title, ', ' order by other_name) from inbox() where kind = 'LISTING';
select 'owner rows carry the customer id: ' || bool_and(other_id is not null and other_code is not null) from inbox() where kind = 'LISTING';
select 'direct chat unchanged: ' || title || ' / ' || other_name from inbox() where conversation_id = current_setting('t.dm')::uuid;
select 'group has no other person: ' || coalesce(other_name, '(none)') from inbox() where conversation_id = current_setting('t.grp2')::uuid;

\echo '== 10. Nearby moments from people I am not synced with open (media readable), far away or blocked they do not'
select pg_temp.as_user('gravi');
insert into moments (author_id, media_path, media_type, caption, audience, location) values (me(), pg_temp.pid('gravi') || '/street.mp4', 'VIDEO', 'Street food', 'LOCAL', geo(12.9063, 77.5857));
reset role; insert into storage.objects (bucket_id, name) values ('moments', (select id::text from profiles where auth_uid = 'gravi') || '/street.mp4'); set role authenticated;
select pg_temp.as_user('garun');
select 'Arun tray has Ravi: ' || count(*) from moments_tray(12.9063, 77.5857) where author_id = pg_temp.pid('gravi');
select 'before opening, moment row readable: ' || count(*) from moments where author_id = pg_temp.pid('gravi');
select 'before opening, media readable: ' || count(*) from storage.objects where bucket_id = 'moments' and name like pg_temp.pid('gravi') || '/%';
select 'open_moments returns: ' || count(*) from open_moments(pg_temp.pid('gravi'), 12.9063, 77.5857);
select 'after opening, moment row readable: ' || count(*) from moments where author_id = pg_temp.pid('gravi');
select 'after opening, media readable: ' || count(*) from storage.objects where bucket_id = 'moments' and name like pg_temp.pid('gravi') || '/%';
select 'my access rows: ' || count(*) from moment_access;
select 'writing my own access row -> ' || pg_temp.expect_fail(format('insert into moment_access (viewer_id, moment_id) values (me(), %L)', (select id from moments where author_id = pg_temp.pid('gravi'))), 'denied');
select pg_temp.as_user('gmeera');
select 'Meera far away, open_moments returns: ' || count(*) from open_moments(pg_temp.pid('gravi'), 13.3000, 77.9000);
select 'Meera media readable: ' || count(*) from storage.objects where bucket_id = 'moments' and name like pg_temp.pid('gravi') || '/%';
select 'Meera sees Arun''s access rows: ' || count(*) from moment_access;
select pg_temp.as_user('gravi');
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('garun'));
select pg_temp.as_user('garun');
select 'after Ravi blocks Arun, media readable: ' || count(*) from storage.objects where bucket_id = 'moments' and name like pg_temp.pid('gravi') || '/%';
select 'and open_moments returns: ' || count(*) from open_moments(pg_temp.pid('gravi'), 12.9063, 77.5857);

\echo '== 11. Syncs: requests only through request_sync; the addressee can accept and nothing else'
select pg_temp.as_user('gsita'); select (public.ensure_profile('Sita', '9000000025')).id is not null;
insert into user_settings (profile_id, who_can_sync) values (me(), 'NOBODY') on conflict (profile_id) do update set who_can_sync = 'NOBODY';
select pg_temp.as_user('gtom');  select (public.ensure_profile('Tom', '9000000026')).id is not null;
select 'direct insert past NOBODY -> ' || pg_temp.expect_fail(format('insert into syncs (requester_id, addressee_id) values (me(), %L)', pg_temp.pid('gsita')), 'row-level security');
select 'request_sync past NOBODY -> ' || pg_temp.expect_fail(format('select request_sync(%L)', pg_temp.pid('gsita')), 'not accepting sync requests');
select pg_temp.as_user('gmeera'); select 'Meera asks Tom: ' || request_sync(pg_temp.pid('gtom'));
select pg_temp.as_user('gtom');
select 'Tom rewrites the requester to Sita -> ' || pg_temp.expect_fail(format($$update syncs set requester_id = %L, status = 'ACCEPTED' where addressee_id = me()$$, pg_temp.pid('gsita')), 'not allowed');
select 'Tom rewrites created_at -> ' || pg_temp.expect_fail($$update syncs set created_at = now() - interval '1 year' where addressee_id = me()$$, 'not allowed');
select 'Tom synced with Sita: ' || count(*) from syncs where status = 'ACCEPTED' and pg_temp.pid('gsita') in (requester_id, addressee_id);
update syncs set status = 'ACCEPTED' where requester_id = pg_temp.pid('gmeera') and addressee_id = me();
select 'Tom accepts Meera: ' || status from syncs where requester_id = pg_temp.pid('gmeera') and addressee_id = me();
select 'Tom turns it back to PENDING -> ' || pg_temp.expect_fail($$update syncs set status = 'PENDING' where addressee_id = me()$$, 'not allowed');

\echo '== 12. Posts: the author edits the text, never the listing it speaks for or its counters'
select pg_temp.as_user('gtom');
insert into posts (author_id, body, visibility) values (me(), 'Lost cat near the park', 'PUBLIC');
select set_config('t.post', (select id::text from posts where author_id = me()), false) is not null;
select 'Tom moves it onto Priya Stores -> ' || pg_temp.expect_fail(format($$update posts set listing_id = (select id from listings where title = 'Priya Stores') where id = %L$$, current_setting('t.post')), 'not allowed');
select 'Tom sets up = 9999 -> ' || pg_temp.expect_fail(format('update posts set up = 9999 where id = %L', current_setting('t.post')), 'not allowed');
select 'Tom sets comments = 50 -> ' || pg_temp.expect_fail(format('update posts set comments = 50 where id = %L', current_setting('t.post')), 'not allowed');
select 'Tom backdates it -> ' || pg_temp.expect_fail(format($$update posts set created_at = now() - interval '1 year' where id = %L$$, current_setting('t.post')), 'not allowed');
update posts set body = 'Lost cat near the park (found, thanks!)' where id = current_setting('t.post')::uuid;
select 'edit text still works: ' || body from posts where id = current_setting('t.post')::uuid;
select 'Priya Stores posts: ' || count(*) from posts where listing_id = (select id from listings where title = 'Priya Stores');
select pg_temp.as_user('gmeera');
insert into post_votes (post_id, profile_id, vote) values (current_setting('t.post')::uuid, me(), 1);
select 'a real vote still counts: up ' || up || ', down ' || down from posts where id = current_setting('t.post')::uuid;
