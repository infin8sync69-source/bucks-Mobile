\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
-- Look-ups by name run as the database owner, so a test user can name a row they are not allowed to read.
create or replace function pg_temp.job(t text) returns uuid language sql security definer as $$ select id from public.jobs where title = t $$;
create or replace function pg_temp.app(t text, u text) returns uuid language sql security definer as $$ select a.id from public.applications a join public.jobs j on j.id = a.job_id join public.profiles p on p.id = a.applicant_id where j.title = t and p.auth_uid = u $$;

set role authenticated;
select pg_temp.as_user('asha');  select (public.ensure_profile('Asha (shop owner)', '9000000021')).id is not null;
select pg_temp.as_user('bala');  select (public.ensure_profile('Bala (admin)', '9000000022')).id is not null;
select pg_temp.as_user('ravi');  select (public.ensure_profile('Ravi (driver)', '9000000023')).id is not null;
select pg_temp.as_user('meera'); select (public.ensure_profile('Meera', '9000000024')).id is not null;
select pg_temp.as_user('sam');   select (public.ensure_profile('Sam (stranger)', '9000000025')).id is not null;

\echo '== 1. Asha opens a shop (made LIVE by the database); Ravi has a skill profile, Meera has none'
select pg_temp.as_user('asha');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Asha Stores', 'Grocery', 'JP Nagar', geo(12.9063, 77.5857));
reset role; update listings set status = 'LIVE' where title = 'Asha Stores'; set role authenticated;
select pg_temp.as_user('ravi');
insert into listings (kind, owner_id, title, category, area, location) values ('SKILL', me(), 'Delivery driver', 'Driver', 'JP Nagar', geo(12.9070, 77.5860));
select pg_temp.as_user('asha');
select 'invite Bala as admin: ' || (invite((select id from listings where title = 'Asha Stores'), null, (select short_code from profiles where auth_uid = 'bala'), 'ADMIN') is not null);
select pg_temp.as_user('bala'); select respond_invite((select id from invites where invitee_id = me() and status = 'PENDING'), true);
select 'Bala role: ' || listing_role((select id from listings where title = 'Asha Stores'));

\echo '== 2. Post: owner and admin can post jobs; an outsider cannot'
select pg_temp.as_user('asha');
insert into jobs (listing_id, created_by, title, description, pay, job_type) select id, me(), 'Delivery rider', 'Morning deliveries in JP Nagar, own bike', 'Rs 15,000/month', 'FULL_TIME' from listings where title = 'Asha Stores';
select pg_temp.as_user('bala');
insert into jobs (listing_id, created_by, title, pay, job_type) select id, me(), 'Weekend billing help', 'Rs 500/day', 'PART_TIME' from listings where title = 'Asha Stores';
select pg_temp.as_user('ravi');
select 'outsider posts a job -> ' || pg_temp.expect_fail(format($$insert into jobs (listing_id, created_by, title) values (%L, me(), 'Fake job')$$, (select id from listings where title = 'Asha Stores')), 'row-level security');

\echo '== 3. Near: jobs of live listings show with distance, nearest first; nothing far away'
select pg_temp.as_user('ravi');
select 'near JP Nagar: ' || string_agg(title || ' @ ' || listing_title || ' (' || area || ', ' || round(distance_m) || ' m, ' || job_type || ')', ' / ' order by created_at) from jobs_near(12.9070, 77.5860);
select 'from Noida: ' || count(*) from jobs_near(28.5355, 77.3910);
select 'within 100 m: ' || count(*) from jobs_near(12.9070, 77.5860, 100);
select pg_temp.as_user('sam');
select 'Sam''s pending skill listing does not create jobs: ' || count(*) from jobs_near(12.9070, 77.5860) where listing_title <> 'Asha Stores';

\echo '== 4. Apply: with your own skill profile only, never to your own listing, once per job'
select pg_temp.as_user('ravi');
insert into applications (job_id, applicant_id, skill_listing_ids, note) values (pg_temp.job('Delivery rider'), me(), array[(select id from listings where title = 'Delivery driver')], 'I know every lane in JP Nagar.');
select 'Ravi applied: ' || status from applications where applicant_id = me();
select 'apply twice -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id) values (%L, me())$$, pg_temp.job('Delivery rider')), 'duplicate');
select pg_temp.as_user('meera');
select 'apply with Ravi''s skill profile -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id, skill_listing_ids) values (%L, me(), array[%L::uuid])$$, pg_temp.job('Delivery rider'), (select id from listings where title = 'Delivery driver')), 'own skill profiles');
select 'apply as someone else -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id) values (%L, %L)$$, pg_temp.job('Delivery rider'), pg_temp.pid('ravi')), 'row-level security');
insert into applications (job_id, applicant_id, note) values (pg_temp.job('Delivery rider'), me(), 'Available from next week.');
select 'Meera applied without a skill profile: ' || status from applications where applicant_id = me();
select pg_temp.as_user('bala');
select 'admin applies to own listing -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id) values (%L, me())$$, pg_temp.job('Delivery rider')), 'own listing');

\echo '== 5. Counts: managers see every application, applicants only their own'
select pg_temp.as_user('asha');
select 'Asha sees: ' || title || ' ' || applications || ' applications, ' || new_applications || ' new' from jobs_with_counts where listing_id = (select id from listings where title = 'Asha Stores') order by created_at;
select 'Asha reads applicants: ' || string_agg(p.name, ', ' order by a.created_at) from applications a join profiles p on p.id = a.applicant_id where a.job_id = pg_temp.job('Delivery rider');
select pg_temp.as_user('ravi');
select 'Ravi sees count: ' || applications from jobs_with_counts where id = pg_temp.job('Delivery rider');
select 'Ravi reads applications: ' || count(*) from applications where job_id = pg_temp.job('Delivery rider');
select pg_temp.as_user('sam');
select 'Sam reads applications: ' || count(*) from applications where job_id = pg_temp.job('Delivery rider');

\echo '== 6. Decide: shortlist -> hire by the admin; applicants cannot promote themselves; notes are frozen'
select pg_temp.as_user('ravi');
select 'Ravi hires himself -> ' || pg_temp.expect_fail(format($$update applications set status = 'HIRED' where id = %L$$, pg_temp.app('Delivery rider', 'ravi')), 'can only withdraw');
select pg_temp.as_user('bala');
update applications set status = 'SHORTLISTED' where id = pg_temp.app('Delivery rider', 'ravi');
select 'Bala edits Ravi''s note -> ' || pg_temp.expect_fail(format($$update applications set note = 'x' where id = %L$$, pg_temp.app('Delivery rider', 'ravi')), 'cannot be changed');
select 'Bala withdraws for Ravi -> ' || pg_temp.expect_fail(format($$update applications set status = 'WITHDRAWN' where id = %L$$, pg_temp.app('Delivery rider', 'ravi')), 'only the applicant');
select pg_temp.as_user('ravi');
select 'Ravi sees: ' || status || ' for ' || job_title || ' at ' || listing_title from my_applications();
select pg_temp.as_user('bala');
update applications set status = 'HIRED' where id = pg_temp.app('Delivery rider', 'ravi');
update applications set status = 'REJECTED' where id = pg_temp.app('Delivery rider', 'meera');
select 'after decisions: ' || string_agg(p.name || '=' || a.status, ', ' order by a.created_at) from applications a join profiles p on p.id = a.applicant_id where a.job_id = pg_temp.job('Delivery rider');
select 'hiring does not close the job: ' || open from jobs where id = pg_temp.job('Delivery rider');
select pg_temp.as_user('sam');
update applications set status = 'HIRED' where id = pg_temp.app('Delivery rider', 'meera');
reset role; select 'Meera''s status after Sam''s attempt (row hidden from him): ' || status from applications where id = pg_temp.app('Delivery rider', 'meera'); set role authenticated;

\echo '== 6b. Message: a manager can open a chat with an applicant on default settings; nobody else gets a way in'
reset role; select 'Ravi''s setting (default): ' || who_can_message from settings_of(pg_temp.pid('ravi')); set role authenticated;
select pg_temp.as_user('bala');
select 'plain start_direct still follows his setting -> ' || pg_temp.expect_fail(format($$select start_direct(%L)$$, pg_temp.pid('ravi')), 'synced with');
create temp table chat_ids (who text, id uuid); grant all on chat_ids to authenticated;
insert into chat_ids select 'bala-ravi', start_applicant_chat(pg_temp.app('Delivery rider', 'ravi'));
select 'Bala opens a chat with Ravi: ' || (id is not null) from chat_ids where who = 'bala-ravi';
select 'opening again reuses it: ' || (start_applicant_chat(pg_temp.app('Delivery rider', 'ravi')) = id) from chat_ids where who = 'bala-ravi';
insert into messages (conversation_id, sender_id, body) select id, me(), 'Can you start on Monday at 7?' from chat_ids where who = 'bala-ravi';
select 'a rejected applicant can still be reached: ' || (start_applicant_chat(pg_temp.app('Delivery rider', 'meera')) is not null);
select pg_temp.as_user('ravi');
select 'Ravi has it in his inbox: ' || kind || ' with ' || other_name || ': ' || last_body || ' (' || unread || ' unread)' from inbox() where conversation_id = (select id from chat_ids where who = 'bala-ravi');
insert into messages (conversation_id, sender_id, body) select id, me(), 'Yes, see you then.' from chat_ids where who = 'bala-ravi';
select 'Ravi uses it on his own application -> ' || pg_temp.expect_fail(format($$select start_applicant_chat(%L)$$, pg_temp.app('Delivery rider', 'ravi')), 'not available');
select 'applying opens no reverse channel into Asha''s DMs -> ' || pg_temp.expect_fail(format($$select start_direct(%L)$$, pg_temp.pid('asha')), 'synced with');
select pg_temp.as_user('sam');
select 'Sam uses it on Meera''s application -> ' || pg_temp.expect_fail(format($$select start_applicant_chat(%L)$$, pg_temp.app('Delivery rider', 'meera')), 'not available');
select 'Sam with a made-up id -> ' || pg_temp.expect_fail($$select start_applicant_chat(gen_random_uuid())$$, 'not available');
select pg_temp.as_user('meera');
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('asha'));
select pg_temp.as_user('asha');
select 'Meera blocked Asha -> ' || pg_temp.expect_fail(format($$select start_applicant_chat(%L)$$, pg_temp.app('Delivery rider', 'meera')), 'cannot message');
select pg_temp.as_user('meera');
delete from blocks where blocker_id = me() and blocked_id = pg_temp.pid('asha');
reset role; select 'anon cannot call it: ' || not has_function_privilege('anon', 'public.start_applicant_chat(uuid)', 'execute'); set role authenticated;

\echo '== 7. Withdraw: a hired or shortlisted applicant may withdraw, a declined one may not, and only once'
select pg_temp.as_user('meera');
select 'Meera withdraws after being declined -> ' || pg_temp.expect_fail(format($$update applications set status = 'WITHDRAWN' where id = %L$$, pg_temp.app('Delivery rider', 'meera')), 'already declined');
select pg_temp.as_user('ravi');
update applications set status = 'WITHDRAWN' where id = pg_temp.app('Delivery rider', 'ravi');
select 'Ravi withdrew: ' || status from applications where id = pg_temp.app('Delivery rider', 'ravi');
select 'withdraw again -> ' || pg_temp.expect_fail(format($$update applications set status = 'WITHDRAWN' where id = %L$$, pg_temp.app('Delivery rider', 'ravi')), 'already withdrawn');
select 'apply again -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id) values (%L, me())$$, pg_temp.job('Delivery rider')), 'duplicate');
select pg_temp.as_user('bala');
select 'Bala re-hires after withdrawal -> ' || pg_temp.expect_fail(format($$update applications set status = 'HIRED' where id = %L$$, pg_temp.app('Delivery rider', 'ravi')), 'withdrew');
select 'Bala opens a chat from the withdrawn application -> ' || pg_temp.expect_fail(format($$select start_applicant_chat(%L)$$, pg_temp.app('Delivery rider', 'ravi')), 'withdrew');
select 'withdrawn ones drop out of the count: ' || applications || ' (new ' || new_applications || ')' from jobs_with_counts where id = pg_temp.job('Delivery rider');

\echo '== 8. Close: no new applications, gone from nearby, but applicants keep the job on their list'
select pg_temp.as_user('asha');
update jobs set open = false where id = pg_temp.job('Delivery rider');
select pg_temp.as_user('sam');
select 'Sam applies to a closed job -> ' || pg_temp.expect_fail(format($$insert into applications (job_id, applicant_id) values (%L, me())$$, pg_temp.job('Delivery rider')), 'closed');
select 'nearby after closing: ' || string_agg(title, ', ') from jobs_near(12.9070, 77.5860);
select 'Sam opens the closed job page: ' || count(*) from job_page(pg_temp.job('Delivery rider'));
select pg_temp.as_user('meera');
select 'Meera reads the closed job row directly: ' || count(*) from jobs where id = pg_temp.job('Delivery rider');
select 'Meera''s job page still works: ' || title || ' at ' || listing_title || ', open=' || open from job_page(pg_temp.job('Delivery rider'));
select 'Meera''s list: ' || string_agg(job_title || ' (' || status || ', open=' || job_open || ')', ', ') from my_applications();
select pg_temp.as_user('bala');
select 'Bala lists open and closed: ' || string_agg(title || ' open=' || open, ', ' order by created_at) from jobs_with_counts where listing_id = (select id from listings where title = 'Asha Stores');
select 'Bala closes the other job and reopens it: ' || (select open from jobs where id = pg_temp.job('Weekend billing help'));
update jobs set open = false where id = pg_temp.job('Weekend billing help'); update jobs set open = true where id = pg_temp.job('Weekend billing help');
select 'reopened: ' || open from jobs where id = pg_temp.job('Weekend billing help');
select set_config('request.jwt.claims', '', false) is not null;
select 'signed-out job page: ' || count(*) from job_page(pg_temp.job('Weekend billing help'));
