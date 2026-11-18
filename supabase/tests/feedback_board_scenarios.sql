\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;

set role authenticated;
select pg_temp.as_user('fa'); select (public.ensure_profile('Farah', '9000000201')).id is not null; select set_birth_date('1995-05-05') = 'ADULT';
select pg_temp.as_user('fb'); select (public.ensure_profile('Gopal', '9000000202')).id is not null; select set_birth_date('1990-01-01') = 'ADULT';
select pg_temp.as_user('ft'); select (public.ensure_profile('Tanvi', '9000000203')).id is not null; select set_birth_date((current_date - interval '15 years')::date) = 'TEEN';
reset role; insert into staff (profile_id) select id from profiles where auth_uid = 'fb'; set role authenticated;

\echo '== 1. Post, auto-vote, others vote, sort by top'
select pg_temp.as_user('fa');
select set_config('t.a', feedback_post('Dark mode for Moments', 'The viewer is too bright at night', 'idea')::text, false) is not null;
select pg_temp.check('author vote counted', (select votes = 1 and voted and is_mine from feedback_list() where id = current_setting('t.a')::uuid));
select 'direct insert -> ' || pg_temp.expect_fail($$insert into feedback_posts (author_id, title) values (me(), 'sneaky')$$, 'permission denied');
select 'too short -> ' || pg_temp.expect_fail($$select feedback_post('hi')$$, 'check constraint');
select pg_temp.as_user('ft');
select set_config('t.t', feedback_post('Stickers in chat', '', 'IDEA')::text, false) is not null;
select pg_temp.check('vote up', feedback_vote(current_setting('t.a')::uuid, true) = 2);
select pg_temp.check('vote twice is one vote', feedback_vote(current_setting('t.a')::uuid, true) = 2);
select pg_temp.check('top first', (select id from feedback_list('TOP') limit 1) = current_setting('t.a')::uuid);
select pg_temp.check('new first', (select id from feedback_list('NEW') limit 1) = current_setting('t.t')::uuid);
select pg_temp.check('unvote', feedback_vote(current_setting('t.a')::uuid, false) = 1);

\echo '== 2. Minors are anonymous on the board'
select pg_temp.as_user('fa');
select pg_temp.check('teen shown as Bucks member', (select author_name = 'Bucks member' from feedback_list() where id = current_setting('t.t')::uuid));
select pg_temp.check('adult shown by name', (select author_name = 'Farah' from feedback_list() where id = current_setting('t.a')::uuid));

\echo '== 3. Staff status; only own posts deletable; declined hidden by default'
select 'non-staff status -> ' || pg_temp.expect_fail(format($$select feedback_set_status(%L, 'DONE')$$, current_setting('t.a')), 'staff only');
select 'delete someone else''s -> ' || pg_temp.expect_fail(format($$select feedback_delete(%L)$$, current_setting('t.t')), 'only delete your own');
select pg_temp.as_user('fb');
select feedback_set_status(current_setting('t.a')::uuid, 'planned', 'Coming in 1.1');
select pg_temp.check('status and note visible', (select status = 'PLANNED' and staff_note = 'Coming in 1.1' from feedback_list() where id = current_setting('t.a')::uuid));
select feedback_set_status(current_setting('t.t')::uuid, 'DECLINED', 'Not for now');
select pg_temp.check('declined hidden from the default board', not exists (select 1 from feedback_list() where id = current_setting('t.t')::uuid));
select pg_temp.check('declined filter shows it', exists (select 1 from feedback_list('NEW', 'DECLINED') where id = current_setting('t.t')::uuid));

\echo '== 4. Rate limit and account deletion'
select pg_temp.as_user('fa');
select feedback_post('Idea number two', '', 'IDEA'); select feedback_post('Idea number three', '', 'IDEA'); select feedback_post('Idea number four', '', 'BUG'); select feedback_post('Idea number five', '', 'OTHER');
select 'sixth today -> ' || pg_temp.expect_fail($$select feedback_post('Idea number six')$$, '5 ideas a day');
select delete_my_account();
reset role;
select pg_temp.check('my feedback posts gone', not exists (select 1 from feedback_posts f join profiles p on p.id = f.author_id where p.auth_uid like 'deleted:%'));
