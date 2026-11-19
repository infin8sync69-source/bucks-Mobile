-- The demand loop (supabase/migrations/demand_loop.sql): "Tell me when one joins", the matching job, and demand by area for staff.
-- One "ok" or "FAIL" line per check.
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
set search_path = public, extensions;   -- PostGIS (geometry, st_x, st_y) lives in extensions
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
-- The 30-minute job, as cron runs it: nobody signed in.
create or replace function pg_temp.job() returns int language sql as $$ select set_config('request.jwt.claims', '', false); select public.wanted_match() $$;

set role authenticated;
select pg_temp.as_phone('wl_me', '9000000801'); select (public.ensure_profile('Meera Searcher', '9000000801')).id is not null;
select pg_temp.as_phone('wl_teen', '9000000802'); select (public.ensure_profile('Tanvi Teen', '9000000802')).id is not null;
select pg_temp.as_phone('wl_shop', '9000000803'); select (public.ensure_profile('Lakshmi Owner', '9000000803')).id is not null;
select pg_temp.as_phone('wl_blocked', '9000000804'); select (public.ensure_profile('Bad Owner', '9000000804')).id is not null;
select pg_temp.as_phone('wl_far', '9000000805'); select (public.ensure_profile('Far Owner', '9000000805')).id is not null;
select pg_temp.as_phone('wl_staff', '9000000806'); select (public.ensure_profile('Sam Staff', '9000000806')).id is not null;
reset role;
insert into profile_safety (profile_id, birth_date, age_band) values (pg_temp.pid('wl_teen'), current_date - interval '15 years', 'TEEN') on conflict (profile_id) do nothing;
insert into staff (profile_id) values (pg_temp.pid('wl_staff')) on conflict do nothing;
insert into localities (name, district, state, pincode, lat, lng) values ('Gonikoppal', 'Kodagu', 'Karnataka', '571213', 12.181, 75.919) on conflict do nothing;
set role authenticated;

\echo '== asking'
select pg_temp.as_phone('wl_me', '9000000801');
create temp table wl_ids as select public.want_notify('tailor', 12.1817, 75.9147, 10000) tailor;
select pg_temp.check('a request is stored', (select tailor is not null from wl_ids));
select pg_temp.check('asking again keeps the one request (phone numbers are taken out first)',
  public.want_notify('Tailor 98765 43210', 12.1830, 75.9150, 10000) = (select tailor from wl_ids));
select pg_temp.check('my requests show the area by name', (select q = 'tailor' and area = 'Gonikoppal, Kodagu' and notified_at is null from my_wanted() where id = (select tailor from wl_ids)));
select pg_temp.fails('nothing to look for is refused', $$select want_notify('  ', 12.18, 75.91)$$, 'say what you are looking for');
select pg_temp.fails('no location is refused', $$select want_notify('tailor', null, null)$$, 'a location is needed');
select pg_temp.check('the table is not readable from the app', not has_table_privilege('authenticated', 'public.wanted', 'select'));
select pg_temp.check('the job cannot be called from the app', not has_function_privilege('authenticated', 'public.wanted_match(integer)', 'execute'));
select pg_temp.as_phone('wl_teen', '9000000802');
select pg_temp.check('a teen can ask too (it is their own request, not tracking)', public.want_notify('maths tutor', 12.1817, 75.9147) is not null);
select pg_temp.as_phone('wl_nobody', '9000000899');
select pg_temp.fails('nobody signed in: refused', $$select want_notify('tailor', 12.18, 75.91)$$, 'sign in first');
reset role;
select pg_temp.check('only the cell is kept, never the exact point', (select cell = '12.18,75.92' and abs(st_y(at_point::geometry) - 12.18) < 1e-9
  and abs(st_x(at_point::geometry) - 75.92) < 1e-9 and q = 'tailor' from wanted where id = (select tailor from wl_ids)));

\echo '== the job: only a page in range that answers it, never across a block'
select pg_temp.check('nothing to find yet: no notification', pg_temp.job() = 0);
set role authenticated;
select pg_temp.as_phone('wl_shop', '9000000803');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Hill Top Bakery', 'Bakery', 'Gonikoppal', geo(12.183, 75.912));
select pg_temp.as_phone('wl_far', '9000000805');
insert into listings (kind, owner_id, title, category, area, location, details) values ('BUSINESS', me(), 'Pune Tailors Online', 'Tailor', 'Pune', geo(18.54, 73.82), '{"ships_india": true}');
select pg_temp.as_phone('wl_blocked', '9000000804');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Blocked Tailors', 'Tailor', 'Gonikoppal', geo(12.184, 75.913));
select pg_temp.as_phone('wl_me', '9000000801');
insert into blocks (blocker_id, blocked_id) values (me(), pg_temp.pid('wl_blocked'));
reset role;
update listings set status = 'LIVE' where title in ('Hill Top Bakery', 'Pune Tailors Online', 'Blocked Tailors');
select pg_temp.check('a bakery, a far tailor that ships and a blocked owner''s tailor: still no notification', pg_temp.job() = 0
  and not exists (select 1 from notifications where profile_id = pg_temp.pid('wl_me') and kind = 'WANTED_FOUND'));
set role authenticated;
select pg_temp.as_phone('wl_shop', '9000000803');
insert into listings (kind, owner_id, title, category, area, location) values ('BUSINESS', me(), 'Lakshmi Tailors', 'Tailor', 'Gonikoppal', geo(12.185, 75.916));
reset role;
update listings set status = 'LIVE' where title = 'Lakshmi Tailors';
select pg_temp.check('a tailor joins nearby: one notification', pg_temp.job() = 1);
select pg_temp.check('it names the page, says what was asked and opens the page', (select count(*) = 1 and bool_and(title = 'Lakshmi Tailors is on Bucks' and position('"tailor"' in body) > 0
  and route = 'l/' || (select id from listings where title = 'Lakshmi Tailors')) from notifications where profile_id = pg_temp.pid('wl_me') and kind = 'WANTED_FOUND'));
select pg_temp.check('the request closes on the page found', (select notified_at is not null and found_listing = (select id from listings where title = 'Lakshmi Tailors') from wanted where id = (select tailor from wl_ids)));
select pg_temp.check('the next run does not tell them again', pg_temp.job() = 0
  and (select count(*) = 1 from notifications where profile_id = pg_temp.pid('wl_me') and kind = 'WANTED_FOUND'));
set role authenticated;
select pg_temp.as_phone('wl_me', '9000000801');
select pg_temp.check('my requests show what was found', (select found_title = 'Lakshmi Tailors' from my_wanted() where id = (select tailor from wl_ids)));

\echo '== cancelling, and the limit'
create temp table wl_more as select public.want_notify('carpenter', 12.1817, 75.9147) carpenter, public.want_notify('plumber', 12.1817, 75.9147) plumber;
select pg_temp.check('cancelling a request', cancel_wanted((select plumber from wl_more)));
select pg_temp.check('a cancelled request is gone from my list', not exists (select 1 from my_wanted() where id = (select plumber from wl_more)));
select pg_temp.as_phone('wl_shop', '9000000803');
select pg_temp.check('someone else cannot cancel mine', not cancel_wanted((select carpenter from wl_more)));
select pg_temp.as_phone('wl_me', '9000000801');
reset role; update settings set value = 1 where key = 'wanted_max_open'; set role authenticated;
select pg_temp.as_phone('wl_me', '9000000801');
select pg_temp.fails('past the limit of open requests', $$select want_notify('mason', 12.1817, 75.9147)$$, 'already waiting');
reset role; update settings set value = 20 where key = 'wanted_max_open'; set role authenticated;

\echo '== staff see demand by area, never who'
select pg_temp.as_phone('wl_me', '9000000801');
select pg_temp.fails('the demand report is staff only', 'select demand_report(30)', 'staff only');
select pg_temp.as_phone('wl_staff', '9000000806');
select pg_temp.check('waiting: carpenter near Gonikoppal, by one person', (select demand_report(30)->'waiting' @> '[{"q": "carpenter", "area": "Gonikoppal, Kodagu", "people": 1}]'));
select pg_temp.check('found: the tailor, with the page', (select demand_report(30)->'found' @> '[{"q": "tailor", "page": "Lakshmi Tailors"}]'));
select pg_temp.check('the report names no one', position('Meera' in demand_report(30)::text) = 0 and position((select pg_temp.pid('wl_me'))::text in demand_report(30)::text) = 0);

\echo '== forgetting'
reset role;
update profiles set status = 'DELETED' where id = pg_temp.pid('wl_me');
select pg_temp.check('a deleted account takes its requests with it', not exists (select 1 from wanted where profile_id = pg_temp.pid('wl_me')));
