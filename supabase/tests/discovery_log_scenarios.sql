-- Search logging and the learning loop (supabase/migrations/discovery_log.sql): who is logged and who never is, what is kept,
-- forgetting, the nightly roll-up and mining, and the staff review. One "ok" or "FAIL" line per check.
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.as_phone(u text, ph text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'phone_number', ph)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.fails(label text, stmt text, needle text) returns text language plpgsql as $$
begin
  execute stmt;
  return 'FAIL ' || label || ' (no error)';
exception when others then
  return case when position(needle in sqlerrm) > 0 then 'ok ' || label else 'FAIL ' || label || ': ' || sqlerrm end;
end $$;
-- One event list in the shape the apps send.
create or replace function pg_temp.q(id text, q text, n int, surface text default 'SEARCH') returns jsonb language sql as $$
  select jsonb_build_object('t', 'QUERY', 'id', id, 'surface', surface, 'q', q, 'lat', 12.1817, 'lng', 75.9147, 'radius_m', 10000, 'n', n, 'ms', 120, 'app', 'test')
$$;

set role authenticated;
select pg_temp.as_phone('dl_a', '9000000701'); select (public.ensure_profile('Asha Adult', '9000000701')).id is not null;
select set_birth_date((current_date - interval '30 years')::date) = 'ADULT';
select pg_temp.as_phone('dl_b', '9000000702'); select (public.ensure_profile('Bala Staff', '9000000702')).id is not null;
select set_birth_date((current_date - interval '40 years')::date) = 'ADULT';
select pg_temp.as_phone('dl_c', '9000000703'); select (public.ensure_profile('Chitra Adult', '9000000703')).id is not null;
select set_birth_date((current_date - interval '22 years')::date) = 'ADULT';
select pg_temp.as_phone('dl_teen', '9000000704'); select (public.ensure_profile('Tara Teen', '9000000704')).id is not null;
select pg_temp.as_phone('dl_new', '9000000705'); select (public.ensure_profile('Uma Unknown', '9000000705')).id is not null;
select pg_temp.as_phone('dl_owner', '9000000706'); select (public.ensure_profile('Omar Owner', '9000000706')).id is not null;
select set_birth_date((current_date - interval '35 years')::date) = 'ADULT';
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Omar Stores', 'Grocery', 'Gonikoppal', geo(12.18, 75.91));
reset role;
insert into profile_safety (profile_id, birth_date, age_band) values (pg_temp.pid('dl_teen'), current_date - interval '15 years', 'TEEN') on conflict (profile_id) do nothing;
update listings set status = 'LIVE' where title = 'Omar Stores';
insert into staff (profile_id) values (pg_temp.pid('dl_b')) on conflict do nothing;
create temp table dl_ids as select (select id from listings where title = 'Omar Stores') shop;
grant select on dl_ids to authenticated;
set role authenticated;

\echo '== who is logged'
select pg_temp.as_phone('dl_a', '9000000701');
select pg_temp.check('an adult: the search, its impressions and the open are kept; malformed events are skipped', log_discovery(jsonb_build_array(
  pg_temp.q('a0000000-0000-4000-8000-000000000001', 'plumber 98765 43210', 3),
  jsonb_build_object('t', 'IMPRESSION', 'query_id', 'a0000000-0000-4000-8000-000000000001', 'subject_type', 'LISTING', 'ids', jsonb_build_array((select shop from dl_ids))),
  jsonb_build_object('t', 'OPEN', 'query_id', 'a0000000-0000-4000-8000-000000000001', 'subject_type', 'LISTING', 'subject_id', (select shop from dl_ids), 'position', 0),
  jsonb_build_object('t', 'BOGUS'), jsonb_build_object('t', 'OPEN', 'subject_id', 'not-a-uuid'), '"a string"'::jsonb)) = 3);
select pg_temp.check('a retried batch is not counted twice', log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000001', 'plumber', 3))) = 0);
select pg_temp.check('people search keeps no text', log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000002', 'Chitra', 1, 'PEOPLE'))) = 1);
select pg_temp.fails('more than 200 events in one call is refused',
  format('select log_discovery(%L::jsonb)', (select jsonb_agg(pg_temp.q(gen_random_uuid()::text, 'x', 0)) from generate_series(1, 201))), 'at most 200');

select pg_temp.as_phone('dl_teen', '9000000704');
select pg_temp.check('a person under 18: nothing is kept', log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000003', 'tutor', 2))) = 0);
select pg_temp.as_phone('dl_new', '9000000705');
select pg_temp.check('a person whose age is not known: nothing is kept', log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000004', 'tutor', 2))) = 0);
select pg_temp.as_phone('dl_owner', '9000000706');
select pg_temp.check('an owner opening their own page is left out', log_discovery(jsonb_build_array(
  jsonb_build_object('t', 'OPEN', 'query_id', 'a0000000-0000-4000-8000-000000000005', 'subject_type', 'LISTING', 'subject_id', (select shop from dl_ids)))) = 0);
select pg_temp.as_phone('dl_x', '9000000799');
select pg_temp.check('nobody signed in: nothing is kept', log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000006', 'tutor', 2))) = 0);

\echo '== what is kept, and who can read it'
reset role;
select pg_temp.check('the query: phone number masked, normalised words, a 2 km cell and never coordinates',
  (select q = 'plumber #' and q_norm = 'plumber' and cell = '12.18,75.92' and n_results = 3 and app = 'test'
   from discovery_queries where id = 'a0000000-0000-4000-8000-000000000001'));
select pg_temp.check('people search: the name typed is not stored', (select q is null and q_norm is null from discovery_queries where id = 'a0000000-0000-4000-8000-000000000002'));
select pg_temp.check('nothing from the teen, the unknown age or the owner', not exists (select 1 from discovery_queries where viewer in (pg_temp.pid('dl_teen'), pg_temp.pid('dl_new')))
  and not exists (select 1 from discovery_events where viewer = pg_temp.pid('dl_owner')));
select pg_temp.check('no coordinate column exists', not exists (select 1 from information_schema.columns where table_schema = 'public'
  and table_name in ('discovery_queries', 'discovery_events', 'query_stats_daily') and column_name in ('lat', 'lng', 'location', 'home')));
select pg_temp.check('the apps cannot read or write the tables', not has_table_privilege('authenticated', 'public.discovery_queries', 'select')
  and not has_table_privilege('authenticated', 'public.discovery_events', 'select, insert') and not has_table_privilege('authenticated', 'public.query_stats_daily', 'select')
  and not has_table_privilege('authenticated', 'public.lexicon_candidates', 'select'));
select pg_temp.check('the nightly jobs cannot be called from the app', not has_function_privilege('authenticated', 'public.discovery_daily()', 'execute')
  and not has_function_privilege('authenticated', 'public.discovery_mine(integer)', 'execute') and not has_function_privilege('authenticated', 'public.discovery_rollup(date)', 'execute'));

\echo '== the staff review'
set role authenticated;
select pg_temp.as_phone('dl_a', '9000000701');
select pg_temp.fails('the report is staff only', 'select discovery_report(7)', 'staff only');
select pg_temp.fails('accepting a word is staff only', $$select lexicon_accept('x', 'y', 'SAME')$$, 'staff only');
select pg_temp.as_phone('dl_b', '9000000702');
select pg_temp.check('staff get the report', (select discovery_report(7) ? 'searches' and discovery_report(7) ? 'candidates' and discovery_report(7)->'lexicon' ? 'live'));
select pg_temp.check('"Did they help?": a ↑ after contact is kept as the outcome of its search', log_discovery(jsonb_build_array(
  jsonb_build_object('t', 'VOTE', 'query_id', 'a0000000-0000-4000-8000-000000000009', 'subject_type', 'LISTING', 'subject_id', (select shop from dl_ids), 'detail', 'up'),
  jsonb_build_object('t', 'VOTE', 'subject_type', 'LISTING', 'subject_id', (select shop from dl_ids), 'detail', 'sideways'))) = 2);
select pg_temp.check('the report counts outcomes', (select (discovery_report(7)->'outcomes'->>'up')::int = 1 and (discovery_report(7)->'outcomes'->>'from_search')::int = 1));
reset role;
select pg_temp.check('a vote keeps only up or down, nothing else', (select array_agg(detail order by detail nulls last) = array['UP', null]
  from discovery_events where kind = 'VOTE' and viewer = pg_temp.pid('dl_b')));
set role authenticated;

\echo '== forgetting'
select pg_temp.as_phone('dl_a', '9000000701');
select pg_temp.check('switching analytics off deletes the person''s rows', discovery_forget_me() = 4);
reset role;
select pg_temp.check('nothing of theirs is left', not exists (select 1 from discovery_queries where viewer = pg_temp.pid('dl_a'))
  and not exists (select 1 from discovery_events where viewer = pg_temp.pid('dl_a')));
set role authenticated;
select pg_temp.as_phone('dl_c', '9000000703');
select log_discovery(jsonb_build_array(pg_temp.q('a0000000-0000-4000-8000-000000000007', 'bakery', 2))) = 1;
reset role;
update profiles set status = 'DELETED' where id = pg_temp.pid('dl_c');
select pg_temp.check('a deleted account takes its rows with it', not exists (select 1 from discovery_queries where viewer = pg_temp.pid('dl_c')));
update profiles set status = 'ACTIVE' where id = pg_temp.pid('dl_c');

\echo '== the nightly roll-up: steps of typing are not searches'
-- yesterday noon, India time; Asha types plum → plumb → plumber and opens one, Bala searches plumber, Asha searches tailor and finds nothing
create temp table dl_t as select ((now() at time zone 'Asia/Kolkata')::date - 1 + time '12:00') at time zone 'Asia/Kolkata' t0;
insert into discovery_queries (id, at, viewer, surface, q, q_norm, cell, n_results)
select v.id::uuid, (select t0 from dl_t) + v.s * interval '1 second', pg_temp.pid(v.who), 'SEARCH', v.q, btrim(search_norm(v.q)), '12.18,75.92', v.n
from (values ('b0000000-0000-4000-8000-000000000001', 0, 'dl_a', 'plum', 2), ('b0000000-0000-4000-8000-000000000002', 3, 'dl_a', 'plumb', 1),
             ('b0000000-0000-4000-8000-000000000003', 6, 'dl_a', 'plumber', 1), ('b0000000-0000-4000-8000-000000000004', 600, 'dl_b', 'plumber', 1),
             ('b0000000-0000-4000-8000-000000000005', 900, 'dl_a', 'tailor', 0)) v(id, s, who, q, n);
insert into discovery_events (query_id, at, viewer, kind, subject_type, subject_id, position)
values ('b0000000-0000-4000-8000-000000000003', (select t0 from dl_t) + interval '8 seconds', pg_temp.pid('dl_a'), 'OPEN', 'LISTING', (select shop from dl_ids), 0);
select discovery_rollup((now() at time zone 'Asia/Kolkata')::date - 1) >= 2;
select pg_temp.check('plumber: 2 searches by 2 people, 1 opened', (select searches = 2 and searchers = 2 and opens = 1 from query_stats_daily
  where day = (now() at time zone 'Asia/Kolkata')::date - 1 and q_norm = 'plumber'));
select pg_temp.check('tailor: a zero-result search', (select searches = 1 and zero_results = 1 from query_stats_daily where day = (now() at time zone 'Asia/Kolkata')::date - 1 and q_norm = 'tailor'));
select pg_temp.check('plum and plumb were steps of typing, not searches', not exists (select 1 from query_stats_daily where q_norm in ('plum', 'plumb')));

\echo '== mining: rephrasings, words that keep finding nothing, feedback'
-- Asha and Bala each search darjee (nothing), then "tailor shop" 20 s later and open it; both search kolhapuri chappal (nothing);
-- Chitra searches jhadu (nothing), then broom (opened), and taps "Not what I wanted" on jhadu; somebody searches a person's name.
insert into discovery_queries (id, at, viewer, surface, q, q_norm, cell, n_results)
select v.id::uuid, now() - interval '2 hours' + v.s * interval '1 second', pg_temp.pid(v.who), 'SEARCH', v.q, btrim(search_norm(v.q)), '12.18,75.92', v.n
from (values ('c0000000-0000-4000-8000-000000000001', 0, 'dl_a', 'darjee', 0), ('c0000000-0000-4000-8000-000000000002', 20, 'dl_a', 'tailor shop', 1),
             ('c0000000-0000-4000-8000-000000000003', 300, 'dl_b', 'darjee', 0), ('c0000000-0000-4000-8000-000000000004', 320, 'dl_b', 'tailor shop', 1),
             ('c0000000-0000-4000-8000-000000000005', 600, 'dl_a', 'kolhapuri chappal', 0), ('c0000000-0000-4000-8000-000000000006', 900, 'dl_b', 'kolhapuri chappal', 0),
             ('c0000000-0000-4000-8000-000000000007', 1200, 'dl_c', 'jhadu', 0), ('c0000000-0000-4000-8000-000000000008', 1215, 'dl_c', 'broom', 1),
             ('c0000000-0000-4000-8000-000000000009', 1500, 'dl_a', 'Chitra Adult', 0), ('c0000000-0000-4000-8000-000000000010', 1800, 'dl_b', 'Chitra Adult', 0)) v(id, s, who, q, n);
insert into discovery_events (query_id, at, viewer, kind, subject_type, subject_id, position, detail)
values ('c0000000-0000-4000-8000-000000000002', now() - interval '2 hours' + interval '25 seconds', pg_temp.pid('dl_a'), 'OPEN', 'LISTING', (select shop from dl_ids), 0, null),
       ('c0000000-0000-4000-8000-000000000004', now() - interval '2 hours' + interval '325 seconds', pg_temp.pid('dl_b'), 'OPEN', 'LISTING', (select shop from dl_ids), 0, null),
       ('c0000000-0000-4000-8000-000000000008', now() - interval '2 hours' + interval '1220 seconds', pg_temp.pid('dl_c'), 'OPEN', 'LISTING', (select shop from dl_ids), 0, null),
       ('c0000000-0000-4000-8000-000000000007', now() - interval '2 hours' + interval '1230 seconds', pg_temp.pid('dl_c'), 'FEEDBACK', null, null, null, 'WRONG_RESULTS');
select discovery_mine(30) >= 3;
select pg_temp.check('a rephrasing by 2 people becomes a candidate', exists (select 1 from lexicon_candidates where term = 'darjee' and means = 'tailor shop' and source = 'REFORMULATION' and searchers = 2));
select pg_temp.check('a phrase 2 people keep finding nothing for becomes a candidate', exists (select 1 from lexicon_candidates where term = 'kolhapuri chappal' and means = '' and searchers = 2));
select pg_temp.check('one person''s rephrasing does not (one person cannot plant a word)', not exists (select 1 from lexicon_candidates where term = 'jhadu' and means = 'broom'));
select pg_temp.check('"Not what I wanted" is enough on its own', exists (select 1 from lexicon_candidates where term = 'jhadu' and means = '' and source = 'FEEDBACK'));
select pg_temp.check('a person''s name never enters the queue', not exists (select 1 from lexicon_candidates where term = 'chitra adult'));
select pg_temp.check('a word the lexicon already knows is not proposed', not exists (select 1 from lexicon_candidates where term in ('tailor', 'tailor shop', 'plumber')));

\echo '== the review closes the loop'
set role authenticated;
select pg_temp.as_phone('dl_b', '9000000702');
select lexicon_accept('darjee', 'tailor', 'SAME', 'hi-Latn', 'golden case added');
select pg_temp.check('an accepted word is live at once, with who reviewed it', exists (select 1 from search_parse('darjee') t, jsonb_array_elements_text(t->'terms'->0->'direct') f where f = ' tailor '));
select pg_temp.check('its candidates leave the queue', not (discovery_report(7)->'candidates' @> '[{"term": "darjee"}]'));
select pg_temp.check('rejecting a candidate', lexicon_reject('kolhapuri chappal') = 1);
select pg_temp.check('the export carries the learned word for git', position('darjee' in lexicon_export()) > 0);
reset role;
select pg_temp.check('accepted with who reviewed it', exists (select 1 from search_lexicon where term = 'darjee' and source = 'mined' and reviewed_by = 'Bala Staff' and status = 'live'));
select discovery_mine(30) >= 0;
select pg_temp.check('a rejected candidate is never proposed again', (select status = 'rejected' from lexicon_candidates where term = 'kolhapuri chappal' and means = ''));

\echo '== retention'
insert into discovery_queries (id, at, viewer, surface, q, q_norm, n_results)
values ('d0000000-0000-4000-8000-000000000001', now() - interval '100 days', pg_temp.pid('dl_b'), 'SEARCH', 'old', 'old', 1);
select discovery_purge() >= 1;
select pg_temp.check('raw rows older than 90 days are purged', not exists (select 1 from discovery_queries where id = 'd0000000-0000-4000-8000-000000000001'));
select pg_temp.check('the nightly job runs end to end', (select discovery_daily() ?& array['rolled_up', 'candidates', 'purged']));
