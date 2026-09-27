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
