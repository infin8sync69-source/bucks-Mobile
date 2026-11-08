\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;

set role authenticated;
select pg_temp.as_user('adult');  select (public.ensure_profile('Asha', '9000000101')).id is not null;
select pg_temp.as_user('adult2'); select (public.ensure_profile('Bharat', '9000000102')).id is not null;
select pg_temp.as_user('teen');   select (public.ensure_profile('Tara', '9000000103')).id is not null;
select pg_temp.as_user('teen2');  select (public.ensure_profile('Tej', '9000000104')).id is not null;
select pg_temp.as_user('kid');    select (public.ensure_profile('Kabir', '9000000105')).id is not null;
reset role;
update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('adult', 'adult2', 'teen', 'teen2', 'kid');
insert into staff (profile_id) select id from profiles where auth_uid = 'adult2';
set role authenticated;

\echo '== 1. Date of birth sets the band once; under-13s are refused while the kids band is off'
select pg_temp.as_user('adult');
select pg_temp.check('adult band', set_birth_date((current_date - interval '25 years')::date) = 'ADULT');
select pg_temp.check('same date again is fine', set_birth_date((current_date - interval '25 years')::date) = 'ADULT');
select 'changing it -> ' || pg_temp.expect_fail(format('select set_birth_date(%L)', (current_date - interval '30 years')::date), 'already set');
select 'future date -> ' || pg_temp.expect_fail(format('select set_birth_date(%L)', (current_date + 1)), 'real date');
select pg_temp.check('my_safety for an adult', (select age_band = 'ADULT' and birth_date_set and guardian_consent is null from my_safety()));
select pg_temp.as_user('teen');
select pg_temp.check('teen band', set_birth_date((current_date - interval '15 years')::date) = 'TEEN');
select pg_temp.check('teen needs consent', (select guardian_consent = false from my_safety()));
select pg_temp.as_user('teen2');
select pg_temp.check('second teen', set_birth_date((current_date - interval '16 years')::date) = 'TEEN');
select pg_temp.as_user('kid');
select 'under 13 while off -> ' || pg_temp.expect_fail(format('select set_birth_date(%L)', (current_date - interval '10 years')::date), 'too young');
select pg_temp.as_user('adult2');
select pg_temp.check('second adult', set_birth_date((current_date - interval '40 years')::date) = 'ADULT');

\echo '== 2. Nobody else can read a band or birth date, or write their own'
select pg_temp.as_user('adult');
select pg_temp.check('others see no profile_safety rows', (select count(*) from profile_safety) = 1);
select 'insert own band -> ' || pg_temp.expect_fail($$insert into profile_safety (profile_id, birth_date, age_band) values (me(), '2000-01-01', 'ADULT')$$, 'permission denied');
select pg_temp.as_user('teen');
select 'teen ages up -> ' || pg_temp.expect_fail($$update profile_safety set age_band = 'ADULT' where profile_id = me()$$, 'permission denied');

\echo '== 3. Guardian consent: only for minors'
select pg_temp.as_user('teen');
select record_guardian_consent('Ravi Kumar', '+91 98450 00000', 'parent');
select pg_temp.check('consent recorded', (select guardian_consent from my_safety()));
select pg_temp.as_user('adult');
select 'adult records consent -> ' || pg_temp.expect_fail($$select record_guardian_consent('X Y', '9845000000', 'PARENT')$$, 'only needed');

\echo '== 4. Teens: private defaults, only syncs can message, location blurred'
select pg_temp.as_user('teen');
select pg_temp.check('teen not open to messages from everyone', (select who_can_message = 'SYNCED' from settings_of(me())));
insert into user_settings (profile_id, who_can_message) values (me(), 'EVERYONE') on conflict (profile_id) do update set who_can_message = 'EVERYONE';
select pg_temp.check('teen cannot open messages to everyone', (select who_can_message = 'SYNCED' from settings_of(me())));
select pg_temp.as_user('adult');
select 'adult DMs a teen they are not synced with -> ' || pg_temp.expect_fail(format('select start_direct(%L)', pg_temp.pid('teen')), 'synced');
select pg_temp.as_user('teen');
insert into posts (author_id, body, visibility, location) values (me(), 'Hello from school', 'LOCAL', geo(12.906312, 77.585731));
reset role;
select pg_temp.check('teen post location blurred to the 2 km grid',
  (select st_equals(location::geometry, st_snaptogrid(geo(12.906312, 77.585731)::geometry, 0.02)) from posts where body = 'Hello from school'));
set role authenticated;

\echo '== 5. Suggestions: adults are not offered teens they share no sync with; teens see teens'
select pg_temp.as_user('adult');
select pg_temp.check('adult is not offered teens', not exists (select 1 from suggest_people(12.9, 77.58) where id in (pg_temp.pid('teen'), pg_temp.pid('teen2'))));
select pg_temp.as_user('teen2');
insert into user_settings (profile_id, discoverable) values (me(), true) on conflict (profile_id) do update set discoverable = true;
select pg_temp.as_user('teen');
insert into user_settings (profile_id, discoverable) values (me(), true) on conflict (profile_id) do update set discoverable = true;
select pg_temp.check('teen is offered another teen', exists (select 1 from suggest_people(12.9, 77.58) where id = pg_temp.pid('teen2')));
select pg_temp.check('teen is offered adults', exists (select 1 from suggest_people(12.9, 77.58) where id = pg_temp.pid('adult')));

\echo '== 6. Reports: see it to report it, once per person, staff queue and takedown'
select pg_temp.as_user('adult');
insert into posts (author_id, body, visibility) values (me(), 'Buy followers cheap!!!', 'PUBLIC');
select set_config('t.post', (select id::text from posts where body = 'Buy followers cheap!!!'), false) is not null;
select pg_temp.as_user('teen');
select pg_temp.check('report filed', report_content('post', current_setting('t.post')::uuid, 'spam', 'selling followers') is not null);
select pg_temp.check('reporting twice is one report', report_content('POST', current_setting('t.post')::uuid, 'SCAM') is not null and (select count(*) from reports) = 1);
select 'report own post -> ' || pg_temp.expect_fail(format($$select report_content('POST', (select id from posts where body = 'Hello from school'), 'SPAM')$$), 'yourself');
select 'report something invisible -> ' || pg_temp.expect_fail(format($$select report_content('POST', %L, 'SPAM')$$, gen_random_uuid()), 'nothing to report');
select 'bad reason -> ' || pg_temp.expect_fail(format($$select report_content('PROFILE', %L, 'BORING')$$, pg_temp.pid('adult')), 'check constraint');
select pg_temp.check('reporter sees own report', (select count(*) from reports) = 1);
select 'non-staff reads the queue: ' || count(*) from report_queue();
select 'non-staff acts -> ' || pg_temp.expect_fail(format($$select review_report((select id from reports limit 1), 'REMOVE')$$), 'staff only');
select pg_temp.as_user('adult');
select pg_temp.check('reported person cannot see the report', (select count(*) from reports) = 0);
select pg_temp.as_user('adult2');
select pg_temp.check('staff sees the queue with a preview', (select preview like 'Buy followers%' and reporters = 1 from report_queue() limit 1));
select review_report((select id from report_queue() limit 1), 'REMOVE');
select pg_temp.check('post taken down', (select deleted_at is not null from posts where id = current_setting('t.post')::uuid));
select pg_temp.check('queue empty after action', (select count(*) from report_queue()) = 0);
select pg_temp.as_user('teen');
select pg_temp.check('reporter sees it actioned', (select status = 'ACTIONED' and action = 'REMOVED' from reports limit 1));

\echo '== 7. Ban from a profile report'
select report_content('PROFILE', pg_temp.pid('adult'), 'HARASSMENT');
select pg_temp.as_user('adult2');
select review_report((select id from report_queue() limit 1), 'BAN');
reset role;
select pg_temp.check('reported person banned', (select status = 'BANNED' from profiles where auth_uid = 'adult'));
set role authenticated;

\echo '== 8. Deleting my account removes my band, consent and reports'
select pg_temp.as_user('teen');
select delete_my_account();
reset role;
select pg_temp.check('band gone', not exists (select 1 from profile_safety s join profiles p on p.id = s.profile_id where p.name = '' and p.auth_uid like 'deleted:%'));
select pg_temp.check('consent gone', (select count(*) from guardian_consents) = 0);
select pg_temp.check('reports I filed gone', not exists (select 1 from reports r join profiles p on p.id = r.reporter_id where p.auth_uid like 'deleted:%'));

\echo '== 9. Nobody can look up someone else''s band'
set role authenticated;
select pg_temp.as_user('adult2');
select 'age_band_of from the app -> ' || pg_temp.expect_fail(format('select age_band_of(%L)', pg_temp.pid('teen2')), 'permission denied');
select 'is_minor from the app -> ' || pg_temp.expect_fail(format('select is_minor(%L)', pg_temp.pid('teen2')), 'permission denied');

\echo '== 10. Search people: teens hidden from unconnected adults, children never shown, Bucks ID finds the person'
select pg_temp.as_user('adult2');
select pg_temp.check('adult finds no teen by name', not exists (select 1 from search_people('Tej')));
select pg_temp.check('too-short query returns nothing', not exists (select 1 from search_people('T')));
select pg_temp.as_user('teen2');
select pg_temp.check('teen finds an adult by name', exists (select 1 from search_people('bhar') where name = 'Bharat'));
select pg_temp.check('wildcards are not special', not exists (select 1 from search_people('%%')));

\echo '== 11. posts_by shows only what I may see'
select pg_temp.as_user('adult2');
insert into posts (author_id, body, visibility) values (me(), 'Public hello', 'PUBLIC'), (me(), 'Syncs only', 'SYNCED');
select pg_temp.as_user('teen2');
select pg_temp.check('stranger sees the public post only', (select array_agg(body order by body) = array['Public hello'] from posts_by(pg_temp.pid('adult2'))));
