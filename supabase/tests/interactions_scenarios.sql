\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.n(u text, k text) returns bigint language sql as $$ select count(*) from public.notifications where profile_id = pg_temp.pid(u) and kind = k $$;

set role authenticated;
select pg_temp.as_user('author'); select (public.ensure_profile('Asha', '9000000091')).id is not null;
select pg_temp.as_user('fan');    select (public.ensure_profile('Bala', '9000000092')).id is not null;
select pg_temp.as_user('other');  select (public.ensure_profile('Chitra', '9000000093')).id is not null;
select pg_temp.as_user('author');
insert into posts (author_id, body, visibility, area) values (me(), 'Fresh stock today', 'PUBLIC', 'JP Nagar');
select set_config('t.post', (select id::text from posts limit 1), false);

\echo '== 1. Comments'
select pg_temp.as_user('fan');
insert into post_comments (post_id, author_id, body) values (current_setting('t.post')::uuid, me(), 'Do you deliver?');
select pg_temp.as_user('author');
select pg_temp.check(pg_temp.n('author', 'COMMENT') = 1, 'the author is told about a comment');
select pg_temp.check((select title from notifications where kind = 'COMMENT') = 'Bala commented on your post', 'naming who');
select pg_temp.check((select body from notifications where kind = 'COMMENT') = 'Do you deliver?', 'with the comment');
select pg_temp.check((select route from notifications where kind = 'COMMENT') = 'post/' || current_setting('t.post'), 'and opens the post');
insert into post_comments (post_id, author_id, body) values (current_setting('t.post')::uuid, me(), 'Yes, within 3 km');
select pg_temp.check(pg_temp.n('author', 'COMMENT') = 1, 'the author is not told about their own reply');
select pg_temp.as_user('fan'); select pg_temp.check(pg_temp.n('fan', 'COMMENT_THREAD') = 1, 'the earlier commenter is told about the reply');
select pg_temp.as_user('other');
insert into post_comments (post_id, author_id, body) values (current_setting('t.post')::uuid, me(), 'Nice!');
select pg_temp.as_user('author'); select pg_temp.check(pg_temp.n('author', 'COMMENT') = 2, 'a third person''s comment reaches the author');
select pg_temp.as_user('fan'); select pg_temp.check(pg_temp.n('fan', 'COMMENT_THREAD') = 2, 'and the earlier commenter');
select pg_temp.as_user('other'); select pg_temp.check(pg_temp.n('other', 'COMMENT_THREAD') = 0, 'but not the commenter themselves');

\echo '== 2. Likes'
select pg_temp.as_user('fan');
insert into post_votes (post_id, profile_id, vote) values (current_setting('t.post')::uuid, me(), 1);
select pg_temp.as_user('author'); select pg_temp.check(pg_temp.n('author', 'POST_LIKE') = 1, 'the author is told about a like');
select pg_temp.as_user('fan'); delete from post_votes where profile_id = me(); insert into post_votes (post_id, profile_id, vote) values (current_setting('t.post')::uuid, me(), 1);
select pg_temp.as_user('author'); select pg_temp.check(pg_temp.n('author', 'POST_LIKE') = 1, 'liking again the same day does not repeat');
select pg_temp.as_user('other'); insert into post_votes (post_id, profile_id, vote) values (current_setting('t.post')::uuid, me(), -1);
select pg_temp.as_user('author'); select pg_temp.check(pg_temp.n('author', 'POST_LIKE') = 1, 'a down-vote says nothing');
select pg_temp.as_user('author'); insert into post_votes (post_id, profile_id, vote) values (current_setting('t.post')::uuid, me(), 1);
select pg_temp.check(pg_temp.n('author', 'POST_LIKE') = 1, 'liking your own post says nothing');

\echo '== 3. Moment reactions'
select pg_temp.as_user('author');
insert into moments (author_id, media_path, media_type, audience, expires_at) values (me(), me()::text || '/m.jpg', 'IMAGE', 'SYNCED', now() + interval '23 hours');
reset role; select set_config('request.jwt.claims', '{}', false);
insert into moment_views (moment_id, viewer_id) values ((select id from moments limit 1), pg_temp.pid('fan'));
select pg_temp.check(pg_temp.n('author', 'MOMENT_REACTION') = 0, 'a plain view is not a notification');
update moment_views set reaction = '❤️' where viewer_id = pg_temp.pid('fan');
select pg_temp.check(pg_temp.n('author', 'MOMENT_REACTION') = 1, 'a reaction is');
select pg_temp.check((select title from notifications where kind = 'MOMENT_REACTION') = 'Bala reacted ❤️ to your moment', 'naming who and what');
update moment_views set reaction = '❤️' where viewer_id = pg_temp.pid('fan');
select pg_temp.check(pg_temp.n('author', 'MOMENT_REACTION') = 1, 'the same reaction twice is not repeated');
