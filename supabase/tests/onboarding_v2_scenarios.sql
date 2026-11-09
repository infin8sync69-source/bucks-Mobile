\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when cond then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;

set role authenticated;
select pg_temp.as_user('ana'); select (public.ensure_profile('Ana', '+34600000001')).id is not null;

\echo '== 1. 18+ confirmation with the terms version sets the ADULT band, no birth date needed'
select confirm_adult('2026-11-09');
select pg_temp.check('band is ADULT', (select age_band = 'ADULT' and not birth_date_set from my_safety()));
select pg_temp.check('terms recorded', (select terms_version = '2026-11-09' and terms_accepted_at is not null from profile_safety where profile_id = me()));
select confirm_adult('2026-12-01');
select pg_temp.check('accepting newer terms updates the version', (select terms_version = '2026-12-01' from profile_safety where profile_id = me()));

\echo '== 2. Country and language on the profile'
select set_my_locale('es', 'es');
select pg_temp.check('country and language saved', (select country = 'ES' and language = 'es' from profiles where id = me()));
select set_my_locale(null, 'pt-BR');
select pg_temp.check('null keeps the country', (select country = 'ES' and language = 'pt-BR' from profiles where id = me()));
select 'bad country -> ' || pg_temp.expect_fail($$select set_my_locale('Spain', 'es')$$, 'check');

\echo '== 3. Signed out: refused'
select set_config('request.jwt.claims', '{}', false);
select 'signed out -> ' || pg_temp.expect_fail($$select confirm_adult('x')$$, 'not signed in');
