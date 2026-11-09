\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

set role authenticated;
select pg_temp.as_user('ana'); select (public.ensure_profile('Ana', '+34600000001')).id is not null;
select pg_temp.as_user('kid'); select (public.ensure_profile('Kid', '+34600000002')).id is not null;

\echo '== 1. 13 and over: adults get ADULT, 13 to 17 TEEN with private defaults; under 13 is refused and nothing is stored'
select pg_temp.as_user('ana');
select pg_temp.check('adult', set_birth_date((current_date - interval '30 years')::date) = 'ADULT');
select pg_temp.check('same date again is fine', set_birth_date((current_date - interval '30 years')::date) = 'ADULT');
select pg_temp.check('my_safety', (select age_band = 'ADULT' and birth_date_set from my_safety()));
select pg_temp.as_user('teen'); select (public.ensure_profile('Teen', '+34600000003')).id is not null;
select pg_temp.check('15 is a teen', set_birth_date((current_date - interval '15 years')::date) = 'TEEN');
select pg_temp.check('teen: only syncs can message', (select who_can_message = 'SYNCED' and moments_audience = 'SYNCED' from user_settings where profile_id = me()));
select pg_temp.as_user('kid');
select '12 -> ' || pg_temp.expect_fail(format('select set_birth_date(%L)', (current_date - interval '12 years')::date), 'not eligible');
select pg_temp.check('nothing stored for an under-13', (select not birth_date_set from my_safety()));

\echo '== 2. Terms version'
select pg_temp.as_user('ana');
select record_terms('2026-11-09');
reset role; select pg_temp.check('terms recorded', (select terms_version = '2026-11-09' and terms_accepted_at is not null from profiles where id = me())); set role authenticated;

\echo '== 3. Country and language on the profile'
select set_my_locale('es', 'es');
reset role; select pg_temp.check('country and language saved', (select country = 'ES' and language = 'es' from profiles where id = me())); set role authenticated;
select set_my_locale(null, 'pt-BR');
reset role; select pg_temp.check('null keeps the country', (select country = 'ES' and language = 'pt-BR' from profiles where id = me())); set role authenticated;
select 'bad country -> ' || pg_temp.expect_fail($$select set_my_locale('Spain', 'es')$$, 'check');

\echo '== 4. Signed out: refused'
select set_config('request.jwt.claims', '{}', false);
select 'signed out -> ' || pg_temp.expect_fail($$select record_terms('x')$$, 'not signed in');
