\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
set search_path = public, extensions;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.check(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok ' || label else 'FAIL ' || label end $$;
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
-- Everything in a box around Hindupur.
create or replace function pg_temp.pins() returns table (name text, posts int) language sql as $$ select name, posts from public.map_pins(13.5, 77.2, 14.2, 77.8) $$;
create or replace function pg_temp.post(b text) returns public.posts language sql security definer as $$ select * from public.posts where body = b $$;

insert into localities (name, district, state, pincode, lat, lng) values
  ('Hindupur', 'Anantapur', 'Andhra Pradesh', '515201', 13.829, 77.491),
  ('Kotnur', 'Anantapur', 'Andhra Pradesh', '515202', 13.85, 77.50);
set role authenticated;
select pg_temp.as_user('ma'); select (public.ensure_profile('Map Meena', '9000000801')).id is not null; select set_birth_date('1994-04-04') = 'ADULT';
select pg_temp.as_user('mt'); select (public.ensure_profile('Teen Tara', '9000000802')).id is not null; select set_birth_date((current_date - interval '16 years')::date) = 'TEEN';
select pg_temp.as_user('mv'); select (public.ensure_profile('Viewer Vik', '9000000803')).id is not null; select set_birth_date('1990-01-01') = 'ADULT';
select pg_temp.as_user('ms'); select (public.ensure_profile('Staff Sita', '9000000804')).id is not null;
reset role; insert into staff (profile_id) select id from profiles where auth_uid = 'ms'; set role authenticated;

\echo '== Never raw GPS: the post snaps to a locality centre'
select pg_temp.as_user('ma');
insert into posts (author_id, body, visibility, area, location) values (me(), 'Best masala dosa at the corner', 'PUBLIC', 'Hindupur', geo(13.83137, 77.49261));
select pg_temp.check('snapped to the Hindupur locality centre', (select map_place = 'LOCALITY' and st_y(map_point::geometry) = 13.829 and map_district = 'Anantapur' from pg_temp.post('Best masala dosa at the corner')));
select pg_temp.check('the phone''s exact point isn''t kept', (select abs(st_y(location::geometry) - 13.83137) > 1e-6 from pg_temp.post('Best masala dosa at the corner')));
select pg_temp.check('a client can''t move its pin', (with u as (update posts set map_point = geo(13.9, 77.6), map_off_by = null where body = 'Best masala dosa at the corner' returning 1) select count(*) = 1 from u)
  and (select st_y(map_point::geometry) = 13.829 from pg_temp.post('Best masala dosa at the corner')));

\echo '== Consent first, and a delay for locality pins'
reset role; update posts set map_after = now() - interval '1 minute' where body = 'Best masala dosa at the corner'; set role authenticated;
select pg_temp.as_user('mv');
select pg_temp.check('not on the map before the author agrees', (select count(*) from pg_temp.pins()) = 0);
select pg_temp.as_user('ma'); select set_map_consent(true);
select pg_temp.as_user('mv');
select pg_temp.check('on the map once they agree: a place, its votes, no author', (select count(*) = 1 and bool_and(name = 'Hindupur' and posts = 1) from pg_temp.pins()));
insert into posts (author_id, body, visibility, location) values ((select id from profiles where auth_uid = 'mv'), 'Fresh post just now', 'PUBLIC', geo(13.851, 77.501));
select pg_temp.check('a fresh locality post waits', (select map_after > now() + interval '40 minutes' from pg_temp.post('Fresh post just now')));
select pg_temp.as_user('ma'); select set_map_consent(false);
select pg_temp.as_user('mv');
select pg_temp.check('saying no removes past pins at once', (select count(*) from pg_temp.pins()) = 0);
select pg_temp.as_user('ma'); select set_map_consent(true);

\echo '== No minors on the map'
select pg_temp.as_user('mt');
select 'a teen agreeing -> ' || pg_temp.expect_fail($$select set_map_consent(true)$$, '18 and over');
insert into posts (author_id, body, visibility, location) values (me(), 'Our college fest', 'PUBLIC', geo(13.83, 77.49));
reset role; update posts set map_after = now() - interval '1 minute' where body = 'Our college fest';
insert into map_consent (profile_id, allowed) select id, true from profiles where auth_uid = 'mt' on conflict (profile_id) do update set allowed = true; set role authenticated;
select pg_temp.as_user('mv');
select pg_temp.check('a teen''s post stays off even with a consent row', (select coalesce(sum(posts), 0) from pg_temp.pins()) = 1);

\echo '== Taking a post off the map'
select pg_temp.as_user('mv');
select report_map_location((select id from posts where body = 'Best masala dosa at the corner'), 'that is my house');
select pg_temp.check('a "shows my home" report takes it off at once', (select count(*) from pg_temp.pins()) = 0);
select pg_temp.check('and files a report for staff', exists (select 1 from reports where detail like 'MAP LOCATION:%'));
select pg_temp.as_user('ma');
select 'the author can''t undo a report -> ' || pg_temp.expect_fail($$select set_post_on_map((select id from posts where body = 'Best masala dosa at the corner'), true)$$, 'taken off the map by Bucks');
select pg_temp.as_user('ms'); select staff_post_map((select id from posts where body = 'Best masala dosa at the corner'), true);
select pg_temp.as_user('mv');
select pg_temp.check('staff put it back after review', (select count(*) from pg_temp.pins()) = 1);
select pg_temp.as_user('ma'); select set_post_on_map((select id from posts where body = 'Best masala dosa at the corner'), false);
select pg_temp.as_user('mv');
select pg_temp.check('the author removes one post', (select count(*) from pg_temp.pins()) = 0);
select pg_temp.as_user('ma'); select set_post_on_map((select id from posts where body = 'Best masala dosa at the corner'), true);
select pg_temp.check('the author sees it on their page', (select bool_and(on_map) and count(*) = 1 from my_map_posts()));

\echo '== Kill switches'
select pg_temp.as_user('mv');
select 'a non-staff kill -> ' || pg_temp.expect_fail($$select staff_map_district('Anantapur', true)$$, 'staff only');
select pg_temp.as_user('ms'); select staff_map_district('Anantapur', true, 'test');
select pg_temp.as_user('mv');
select pg_temp.check('a district switched off shows nothing', (select count(*) from pg_temp.pins()) = 0);
select pg_temp.as_user('ms'); select staff_map_district('Anantapur', false);
reset role; update settings set value = 0 where key = 'map_enabled'; set role authenticated;
select pg_temp.as_user('mv');
select pg_temp.check('the whole map switched off shows nothing', (select count(*) from pg_temp.pins()) = 0);
reset role; update settings set value = 1 where key = 'map_enabled'; set role authenticated;

\echo '== One author can''t fill a place'
select pg_temp.as_user('ma');
insert into posts (author_id, body, visibility, location) select me(), 'Spam ' || g, 'PUBLIC', geo(13.83, 77.49) from generate_series(1, 6) g;
reset role; update posts set map_after = now() - interval '1 minute' where body like 'Spam %'; set role authenticated;
select pg_temp.as_user('mv');
select pg_temp.check('at most 3 of their posts count per place', (select posts from pg_temp.pins() where name = 'Hindupur') = 3);

\echo '== Only through the functions'
select pg_temp.check('the consent table is mine only', (select count(*) from map_consent) = 0);
select pg_temp.check('kill zones not readable', not has_table_privilege('authenticated', 'public.map_kill_zones', 'select'));
