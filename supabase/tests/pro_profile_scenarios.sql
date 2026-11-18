\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;

set role authenticated;
select pg_temp.as_user('pa'); select (public.ensure_profile('Asha Rao', '9000000301')).id is not null; select set_birth_date('1992-03-03') = 'ADULT';
select pg_temp.as_user('pb'); select (public.ensure_profile('Bala', '9000000302')).id is not null; select set_birth_date('1988-08-08') = 'ADULT';
select pg_temp.as_user('pc'); select (public.ensure_profile('Chitra', '9000000303')).id is not null; select set_birth_date('1990-01-01') = 'ADULT';
select pg_temp.as_user('pt'); select (public.ensure_profile('Teen', '9000000304')).id is not null; select set_birth_date((current_date - interval '16 years')::date) = 'TEEN';

\echo '== 1. An adult builds a Pro profile; every section saves'
select pg_temp.as_user('pa');
insert into pro_profiles (profile_id, headline, summary, open_to, years_experience, job_types, work_radius_km, languages)
  values (me(), 'Electrician · 6 years', 'Wiring, panels and solar for homes and shops.', array['WORK', 'GIGS'], 6, array['FULL_TIME', 'GIG'], 15, array['Kannada', 'Hindi']);
insert into pro_experience (profile_id, title, org, start_month, end_month, description) values (me(), 'Senior electrician', 'Sri Power Works', '2021-06-01', null, 'Site lead');
insert into pro_experience (profile_id, title, org, start_month, end_month) values (me(), 'Electrician', 'City Electricals', '2018-01-01', '2021-05-01');
insert into pro_education (profile_id, course, institute, start_year, end_year) values (me(), 'ITI Electrician', 'Govt ITI Bengaluru', 2016, 2018);
insert into pro_skills (profile_id, name, level, years) values (me(), 'House wiring', 'EXPERT', 6), (me(), 'Solar panels', 'INTERMEDIATE', 2);
insert into pro_certifications (profile_id, name, issuer, issued_on) values (me(), 'Wireman licence', 'KPTCL', '2019-02-01');
insert into pro_cvs (profile_id, path, file_name, mime, size_bytes, is_primary) values (me(), me()::text || '/cv-a1.pdf', 'Asha CV.pdf', 'application/pdf', 120000, true);
select pg_temp.check('the profile and its sections read back', (select count(*) from pro_experience) = 2 and (select count(*) from pro_skills) = 2 and (select count(*) from pro_cvs) = 1);
select 'same skill twice -> ' || pg_temp.expect_fail($$insert into pro_skills (profile_id, name) values (me(), ' house WIRING ')$$, 'duplicate');
select 'end before start -> ' || pg_temp.expect_fail($$insert into pro_experience (profile_id, title, start_month, end_month) values (me(), 'x', '2020-05-01', '2019-01-01')$$, 'check constraint');
select 'a CV outside my folder -> ' || pg_temp.expect_fail(format($$insert into pro_cvs (profile_id, path, file_name, mime, size_bytes) values (me(), %L, 'x.pdf', 'application/pdf', 10)$$, pg_temp.pid('pb')::text || '/cv-x.pdf'), 'check constraint');
select 'a second primary CV -> ' || pg_temp.expect_fail($$insert into pro_cvs (profile_id, path, file_name, mime, size_bytes, is_primary) values (me(), me()::text || '/cv-b.pdf', 'b.pdf', 'application/pdf', 10, true)$$, 'duplicate');
select 'an app file as a CV -> ' || pg_temp.expect_fail($$insert into pro_cvs (profile_id, path, file_name, mime, size_bytes) values (me(), me()::text || '/cv-c.apk', 'c.apk', 'application/vnd.android.package-archive', 10)$$, 'check constraint');
select 'writing into someone else''s profile -> ' || pg_temp.expect_fail(format($$insert into pro_skills (profile_id, name) values (%L, 'x')$$, pg_temp.pid('pb')), 'row-level security');

\echo '== 2. Others see it, minus hidden sections and the CV'
select pg_temp.as_user('pb');
select pg_temp.check('a signed-in adult sees the headline', (select headline from pro_profiles where profile_id = pg_temp.pid('pa')) = 'Electrician · 6 years');
select pg_temp.check('and the experience', (select count(*) from pro_experience where profile_id = pg_temp.pid('pa')) = 2);
select pg_temp.check('never the CV rows', (select count(*) from pro_cvs where profile_id = pg_temp.pid('pa')) = 0);
with u as (update pro_profiles set headline = 'hacked' where profile_id = pg_temp.pid('pa') returning 1)
  select case when count(*) = 0 then 'ok editing someone else''s headline changes nothing' else 'FAIL someone else''s headline was changed' end from u;
select pg_temp.as_user('pa'); update pro_profiles set hidden_sections = array['EXPERIENCE'] where profile_id = me();
select pg_temp.check('the owner still sees a hidden section', (select count(*) from pro_experience where profile_id = me()) = 2);
select pg_temp.as_user('pb');
select pg_temp.check('a hidden section disappears for others', (select count(*) from pro_experience where profile_id = pg_temp.pid('pa')) = 0);
select pg_temp.check('the other sections stay', (select count(*) from pro_skills where profile_id = pg_temp.pid('pa')) = 2);

\echo '== 3. Visibility SYNCED and ONLY_ME; blocks'
select pg_temp.as_user('pa'); update pro_profiles set visibility = 'SYNCED', hidden_sections = '{}' where profile_id = me();
select pg_temp.as_user('pb');
select pg_temp.check('not synced: hidden', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 0);
reset role; insert into syncs (requester_id, addressee_id, status) values (pg_temp.pid('pa'), pg_temp.pid('pb'), 'ACCEPTED'); set role authenticated;
select pg_temp.check('synced: visible', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 1);
select pg_temp.as_user('pc');
select pg_temp.check('another, not synced: hidden', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 0);
select pg_temp.as_user('pa'); update pro_profiles set visibility = 'EVERYONE' where profile_id = me();
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('pc'));
select pg_temp.as_user('pc');
select pg_temp.check('blocked: hidden even when public', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 0);
select pg_temp.as_user('pa'); update pro_profiles set visibility = 'ONLY_ME' where profile_id = me();
select pg_temp.as_user('pb');
select pg_temp.check('ONLY_ME: hidden from syncs too', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 0);

\echo '== 4. Adults only'
select pg_temp.as_user('pt');
select 'a teen starts a Pro profile -> ' || pg_temp.expect_fail($$insert into pro_profiles (profile_id, headline) values (me(), 'Student')$$, 'row-level security');

\echo '== 5. Limits'
select pg_temp.as_user('pb');
insert into pro_profiles (profile_id) values (me());
insert into pro_cvs (profile_id, path, file_name, mime, size_bytes) select me(), me()::text || '/cv-' || g || '.pdf', 'cv.pdf', 'application/pdf', 10 from generate_series(1, 5) g;
select 'a sixth CV -> ' || pg_temp.expect_fail($$insert into pro_cvs (profile_id, path, file_name, mime, size_bytes) values (me(), me()::text || '/cv-6.pdf', 'cv.pdf', 'application/pdf', 10)$$, 'up to 5');

\echo '== 6. Deleting the account removes the professional record'
select pg_temp.as_user('pa'); select delete_my_account();
reset role;
select pg_temp.check('nothing left of Asha''s Pro profile', (select count(*) from pro_profiles where profile_id = pg_temp.pid('pa')) = 0
  and (select count(*) from pro_experience where profile_id = (select id from profiles where name = '' and status = 'DELETED' limit 1)) = 0
  and (select count(*) from pro_cvs where path like '%/cv-a1.pdf') = 0);
