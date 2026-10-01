-- Scenarios for supabase/migrations/hardening_platform.sql (audit items P1-P11, P14).
-- Every check is an exploit attempt written first: on the stack WITHOUT the migration a check prints "FAIL: ... (exploit works ...)",
-- on the stack WITH it every line prints "ok: ...". Nothing else is printed and the script always runs to the end (exit 0), because
-- each attempt is wrapped so a refused statement is reported as ok, not as a script error.
-- Run:  psql -X -q -d <db with local_auth_shim.sql + schema.sql + migrations, hardening_platform.sql last> -f supabase/tests/hardening_platform_scenarios.sql
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
\pset pager off
set search_path = public, extensions;
set client_min_messages = warning;

-- The two setters return no rows on purpose, so calling them prints nothing.
create function pg_temp.as_user(u text, phone text default null) returns setof text language plpgsql as $$
begin perform set_config('request.jwt.claims', (case when phone is null then jsonb_build_object('sub', u) else jsonb_build_object('sub', u, 'phone_number', phone) end)::text, false); return; end $$;
create function pg_temp.setv(k text, v text) returns setof text language plpgsql as $$ begin perform set_config(k, v, false); return; end $$;
create function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create function pg_temp.ok(label text, cond boolean) returns text language sql as $$ select case when coalesce(cond, false) then 'ok: ' || label else 'FAIL: ' || label end $$;
-- The statement must be refused. No error means the exploit works.
create function pg_temp.blocked(label text, stmt text, want text default '') returns text language plpgsql as $$
begin execute stmt; return 'FAIL: ' || label || ' (exploit works: no error)';
exception when others then return case when want = '' or sqlerrm ilike '%' || want || '%' then 'ok: ' || label else 'FAIL: ' || label || ' (wrong error: ' || sqlerrm || ')' end; end $$;
create function pg_temp.allowed(label text, stmt text) returns text language plpgsql as $$
begin execute stmt; return 'ok: ' || label; exception when others then return 'FAIL: ' || label || ' (' || sqlerrm || ')'; end $$;
create function pg_temp.scalar(stmt text) returns text language plpgsql as $$
declare r text; begin execute stmt into r; return coalesce(r, '<null>'); exception when others then return 'ERROR: ' || sqlerrm; end $$;
-- Rows a DML statement touched; -1 when it was refused.
create function pg_temp.rows(stmt text) returns int language plpgsql as $$
declare n int; begin execute stmt; get diagnostics n = row_count; return n; exception when others then return -1; end $$;

-- ================================================================ fixtures
\o /dev/null
set role authenticated;
select pg_temp.as_user('ann', '+919000000001'); select public.ensure_profile('Ann', '9000000001');
select pg_temp.as_user('bob', '+919000000002'); select public.ensure_profile('Bob', '9000000002');
select pg_temp.as_user('cy', '+919000000003');  select public.ensure_profile('Cy', '9000000003');
select pg_temp.as_user('dee', '+919000000004'); select public.ensure_profile('Dee', '9000000004');
select pg_temp.as_user('mal', '+919000000005'); select public.ensure_profile('Mal', '9000000005');
select pg_temp.as_user('vic', '+919000000006'); select public.ensure_profile('Vic', '9000000006');
select pg_temp.as_user('eve', '+919000000007'); select public.ensure_profile('Eve', '9000000007');
reset role;
insert into public.profiles (auth_uid, name, home, created_at) select 'n' || g, 'Neighbour ' || g, public.geo(12.9063 + g * 0.001, 77.5857), now() - interval '30 days' from generate_series(1, 8) g;
insert into public.profiles (auth_uid, name, home, created_at) select 'f' || g, 'Filler ' || g, public.geo(12.95 + (g % 10) * 0.01, 77.55 + (g / 10) * 0.01), now() - interval '40 days' from generate_series(1, 70) g;
update public.profiles set created_at = now() - interval '60 days' where auth_uid in ('ann', 'bob', 'cy', 'dee', 'mal', 'vic', 'eve');
update public.profiles set home = public.geo(12.9700, 77.6100) where auth_uid = 'vic';
-- six close candidates for the ordering check: same mutual count, same distance bucket, exact distances 111..777 m from mal's future home
insert into public.profiles (auth_uid, name, home, created_at) select 'c' || g, 'Close ' || g, public.geo(12.9100 + g * 0.001, 77.5900), now() - interval '40 days' from generate_series(1, 6) g;

-- Ann's cafe: LIVE (8 neighbours recommended it, documents verified).
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
insert into public.listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', public.me(), 'Ann Cafe', 'Cafe', 'Coffee and cake', 'JP Nagar', public.geo(12.9063, 77.5857), '{}');
select pg_temp.as_user('dee', '+919000000004');
insert into public.listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', public.me(), 'Dee Kitchen', 'Restaurant', 'Home food', 'JP Nagar', public.geo(12.9063, 77.5857), '{}');
insert into public.jobs (listing_id, title, description, pay, created_by) select id, 'Cook wanted', 'Evenings', '15000', public.me() from public.listings where title = 'Dee Kitchen';
reset role;
insert into public.listing_documents (listing_id, doc_type, path, number, expires_on, status, uploaded_by)
  select l.id, d.t, l.owner_id::text || '/doc-' || lower(d.t) || '.pdf', d.n, d.e, 'VERIFIED', l.owner_id
  from public.listings l, (values ('OWNER_ID', '', null::date), ('FSSAI', '12345678901234', current_date + 365)) d(t, n, e) where l.title = 'Ann Cafe';
insert into public.recommendations (listing_id, recommender_id, at_location)
  select l.id, p.id, public.geo(12.9063, 77.5857) from public.listings l, public.profiles p where l.title = 'Ann Cafe' and p.auth_uid ~ '^n[0-9]$';
update public.listings set status = 'LIVE' where title = 'Ann Cafe';
-- Dee's kitchen stays PENDING and has a public post.
insert into public.posts (author_id, listing_id, body, visibility) select owner_id, id, 'Grand opening of Dee Kitchen!', 'PUBLIC' from public.listings where title = 'Dee Kitchen';
select pg_temp.setv('t.dee_job', id::text) from public.jobs where title = 'Cook wanted';
select pg_temp.setv('t.ann_listing', id::text) from public.listings where title = 'Ann Cafe';
select pg_temp.setv('t.dee_listing', id::text) from public.listings where title = 'Dee Kitchen';
-- A direct chat between Ann and Bob.
with c as (insert into public.conversations (kind, direct_key, created_by) values ('DIRECT', pg_temp.pid('ann')::text || ':' || pg_temp.pid('bob')::text, pg_temp.pid('ann')) returning id)
  select pg_temp.setv('t.conv', id::text) from c;
insert into public.conversation_members (conversation_id, profile_id) select current_setting('t.conv')::uuid, x from unnest(array[pg_temp.pid('ann'), pg_temp.pid('bob')]) x;
-- and a group (blocks only silence DIRECT and LISTING chats) for the checks that need to keep posting after the P4 blocks
with c as (insert into public.conversations (kind, title, created_by) values ('GROUP', 'Test group', pg_temp.pid('ann')) returning id)
  select pg_temp.setv('t.grp', id::text) from c;
insert into public.conversation_members (conversation_id, profile_id, role) select current_setting('t.grp')::uuid, x, 'MEMBER' from unnest(array[pg_temp.pid('ann'), pg_temp.pid('cy'), pg_temp.pid('dee')]) x;
\o

-- ================================================================ P1 suggest_people is not a location oracle
create function pg_temp.p1_trilaterate() returns double precision language plpgsql as $$
declare pts double precision[] := array[12.80, 77.50, 12.80, 77.70, 13.10, 77.60];   -- lat, lng of three probe points
  lat0 double precision := 12.97; kx double precision := 111320 * cos(radians(12.97)); ky double precision := 110574;
  v uuid := pg_temp.pid('vic'); d double precision[]; px double precision[]; py double precision[];
  x double precision; y double precision; i int; k int; r double precision; dx double precision; dy double precision; jx double precision; jy double precision;
  a11 double precision; a12 double precision; a22 double precision; b1 double precision; b2 double precision; det double precision;
begin
  for k in 1..3 loop
    d[k] := (select s.distance_m from public.suggest_people(pts[2 * k - 1], pts[2 * k], 100000) s where s.id = v);
    px[k] := pts[2 * k] * kx; py[k] := pts[2 * k - 1] * ky;
    if d[k] is null then return null; end if;
  end loop;
  x := (px[1] + px[2] + px[3]) / 3; y := (py[1] + py[2] + py[3]) / 3;
  for i in 1..60 loop
    a11 := 0; a12 := 0; a22 := 0; b1 := 0; b2 := 0;
    for k in 1..3 loop
      dx := x - px[k]; dy := y - py[k]; r := greatest(sqrt(dx * dx + dy * dy), 1e-6); jx := dx / r; jy := dy / r;
      a11 := a11 + jx * jx; a12 := a12 + jx * jy; a22 := a22 + jy * jy; b1 := b1 + jx * (d[k] - r); b2 := b2 + jy * (d[k] - r);
    end loop;
    det := a11 * a22 - a12 * a12; exit when abs(det) < 1e-9;
    x := x + (a22 * b1 - a12 * b2) / det; y := y + (a11 * b2 - a12 * b1) / det;
  end loop;
  return sqrt(power(x - 77.61 * kx, 2) + power(y - 12.97 * ky, 2));
end $$;
create function pg_temp.p1_order() returns boolean language sql as $$
  select array_agg(id order by n) = (select array_agg(p.id order by md5(pg_temp.pid('mal')::text || p.id::text)) from public.profiles p where p.auth_uid ~ '^c[0-9]$')
  from (select s.id, row_number() over () n from public.suggest_people(12.9100, 77.5900, 50) s) x where x.id in (select id from public.profiles where auth_uid ~ '^c[0-9]$') $$;

set role authenticated; select pg_temp.as_user('mal', '+919000000005');
select pg_temp.ok('P1 a caller without a stored home learns no distances at all', (select count(*) filter (where distance_m is not null) = 0 from public.suggest_people(12.90, 77.60, 100)));
select pg_temp.ok(format('P1 three probes from known points cannot trilaterate a hidden home (estimate off by %s m, or no distances)', coalesce(round(e)::text, 'n/a')), coalesce(e > 1000, true)) from (select pg_temp.p1_trilaterate() e) t;
reset role; update public.profiles set home = public.geo(12.9100, 77.5900) where auth_uid = 'mal'; set role authenticated;
select pg_temp.ok(format('P1 with a home of their own the three-probe attack still finds nothing (estimate off by %s m)', coalesce(round(e)::text, 'n/a')), coalesce(e > 1000, true)) from (select pg_temp.p1_trilaterate() e) t;
select pg_temp.ok('P1 distance_m comes only in 2000 m buckets', (select count(*) > 0 and bool_and(distance_m is null or (round(distance_m)::bigint % 2000) = 0) from public.suggest_people(12.90, 77.60, 100)));
select pg_temp.ok('P1 lim is clamped to 50 (asked for 100000, 90+ people are discoverable)', (select count(*) <= 50 from public.suggest_people(12.90, 77.60, 100000)));
select pg_temp.ok('P1 the lat/lng the caller passes are not the reference point (same answer from two places)',
  (select array_agg(s::text order by s.id) from public.suggest_people(12.90, 77.50, 50) s) is not distinct from (select array_agg(s::text order by s.id) from public.suggest_people(13.20, 77.90, 50) s));
select pg_temp.ok('P1 equal-mutual, equal-bucket candidates are not ranked by exact distance (stable hash order)', pg_temp.p1_order());

-- ================================================================ P2 server-managed fields on insert
create function pg_temp.p2_profile_insert() returns setof text language plpgsql as $$
declare pid uuid; c timestamptz; tu int; sc text; ia timestamptz; st text;
begin
  begin
    insert into public.profiles (auth_uid, name, created_at, trust_up, trust_down, short_code, id_issued_at, status)
      values ('sly', 'Sly', now() - interval '90 days', 40, 0, 'AAAAAAAA', now() - interval '3 years', 'ACTIVE') returning id into pid;
  exception when others then return next case when sqlerrm ~* 'managed|not allowed|row-level|violates' then 'ok: P2 a direct profile insert with forged fields is refused (' || sqlerrm || ')' else 'FAIL: P2 profile insert failed unexpectedly: ' || sqlerrm end; return; end;
  select created_at, trust_up, short_code, id_issued_at, status into c, tu, sc, ia, st from public.profiles where id = pid;
  return next pg_temp.ok('P2 a self-inserted profile cannot backdate created_at (defeats the 14-day recommender rule)', c > now() - interval '1 minute');
  return next pg_temp.ok('P2 a self-inserted profile cannot start with forged trust', tu = 0);
  return next pg_temp.ok('P2 a self-inserted profile cannot choose its Bucks ID', sc <> 'AAAAAAAA');
  return next pg_temp.ok('P2 a self-inserted profile cannot backdate its ID card', ia > now() - interval '1 minute');
end $$;
create function pg_temp.p2_stamps() returns setof text language plpgsql as $$
declare mid uuid; pid uuid; momid uuid; c timestamptz; e timestamptz; d timestamptz;
begin
  begin
    insert into public.messages (conversation_id, sender_id, body, created_at, edited_at, deleted_at)
      values (current_setting('t.grp')::uuid, public.me(), 'stamped', now() + interval '5 years', now(), now()) returning id into mid;
    select created_at, edited_at, deleted_at into c, e, d from public.messages where id = mid;
    return next pg_temp.ok('P2 a message cannot carry a forged created_at', c < now() + interval '1 minute');
    return next pg_temp.ok('P2 a message cannot arrive already edited or deleted', e is null and d is null);
  exception when others then return next 'FAIL: P2 message insert failed unexpectedly: ' || sqlerrm; end;
  begin
    insert into public.posts (author_id, body, visibility, created_at) values (public.me(), 'stamped post', 'PUBLIC', now() + interval '5 years') returning id into pid;
    select created_at into c from public.posts where id = pid;
    return next pg_temp.ok('P2 a post cannot carry a forged created_at (pins itself to the top of the feed)', c < now() + interval '1 minute');
    insert into public.posts (author_id, body, visibility, deleted_at) values (public.me(), 'stamped deleted post', 'PUBLIC', now());   -- read back as the owner below
  exception when others then return next 'FAIL: P2 post insert failed unexpectedly: ' || sqlerrm; end;
  begin
    insert into public.moments (author_id, media_path, created_at) values (public.me(), public.me()::text || '/stamp.jpg', now() + interval '5 years') returning id into momid;
    select created_at into c from public.moments where id = momid;
    return next pg_temp.ok('P2 a moment cannot carry a forged created_at', c < now() + interval '1 minute');
  exception when others then return next 'FAIL: P2 moment insert failed unexpectedly: ' || sqlerrm; end;
end $$;

select pg_temp.as_user('sly');
select * from pg_temp.p2_profile_insert();
\o /dev/null
select pg_temp.as_user('phn', '+919777700001'); select public.ensure_profile('Phn', '5550001111');
\o
reset role;
select pg_temp.ok('P2 ensure_profile stores the phone from the verified token, ignoring the typed one', (select phone from public.profile_private where profile_id = pg_temp.pid('phn')) = '+919777700001');
set role authenticated; select pg_temp.as_user('phn', '+919777700001');
\o /dev/null
select pg_temp.rows($$update public.profile_private set phone = '5559999999' where profile_id = public.me()$$);
\o
select pg_temp.ok('P2 profile_private.phone cannot be rewritten by its owner', (select phone from public.profile_private where profile_id = public.me()) = '+919777700001');
select pg_temp.blocked('P2 upi_uri must be a upi://pay? link', $$update public.profile_private set upi_uri = 'https://evil.example/pay?x=1' where profile_id = public.me()$$);
select pg_temp.blocked('P2 upi_uri longer than 500 characters is refused', $$update public.profile_private set upi_uri = 'upi://pay?pa=' || repeat('a', 600) where profile_id = public.me()$$);
select pg_temp.allowed('P2 a real UPI link is accepted', $$update public.profile_private set upi_uri = 'UPI://PAY?pa=phn@okaxis&pn=Phn' where profile_id = public.me()$$);
select pg_temp.ok('P2 the UPI scheme is stored normalised', (select upi_uri from public.profile_private where profile_id = public.me()) = 'upi://pay?pa=phn@okaxis&pn=Phn');
select pg_temp.allowed('P2 an empty upi_uri clears it', $$update public.profile_private set upi_uri = '' where profile_id = public.me()$$);
select pg_temp.ok('P2 an empty upi_uri is stored as null', (select upi_uri is null from public.profile_private where profile_id = public.me()));
select pg_temp.as_user('ann', '+919000000001');
select * from pg_temp.p2_stamps();
reset role;
select pg_temp.ok('P2 a post cannot arrive already soft-deleted', (select deleted_at is null from public.posts where body = 'stamped deleted post'));
set role authenticated;

-- ================================================================ P3 posts and moments never store the exact GPS fix
set role authenticated; select pg_temp.as_user('bob', '+919000000002');
insert into public.posts (author_id, body, visibility, location, area) values (public.me(), 'lunch near Indiranagar', 'LOCAL', public.geo(12.934567, 77.612345), 'BTM');
insert into public.moments (author_id, media_path, audience, location, caption) values (public.me(), public.me()::text || '/local.jpg', 'LOCAL', public.geo(12.934567, 77.612345), 'p3 moment');
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P3 a stranger cannot read the exact GPS fix of a LOCAL post', (select st_distance(location, public.geo(12.934567, 77.612345)) > 1 from public.posts where body = 'lunch near Indiranagar'));
select pg_temp.ok('P3 the stored post location is on the coarse grid (about 500 m)', (select st_distance(location, public.geo(12.934567, 77.612345)) between 1 and 500 and abs(st_x(location::geometry) / 0.005 - round(st_x(location::geometry) / 0.005)) < 1e-6 from public.posts where body = 'lunch near Indiranagar'));
select pg_temp.ok('P3 feed() still finds the LOCAL post within its radius', (select count(*) = 1 from public.feed(12.9350, 77.6120, 3000) where body = 'lunch near Indiranagar'));
select pg_temp.ok('P3 feed() still respects the radius', (select count(*) = 0 from public.feed(13.2, 77.9, 3000) where body = 'lunch near Indiranagar'));
select pg_temp.ok('P3 the exact GPS fix of a moment is not readable either', (select coalesce(bool_and(st_distance(location, public.geo(12.934567, 77.612345)) > 1), false) from public.moments_of(pg_temp.pid('bob'), 12.9350, 77.6120) where caption = 'p3 moment'));
select pg_temp.ok('P3 nearby people still see the LOCAL moment in their tray', (select count(*) = 1 from public.moments_tray(12.9350, 77.6120) where author_id = pg_temp.pid('bob')));

-- ================================================================ P4 moments, interactions and invites
reset role;
insert into public.syncs (requester_id, addressee_id, status) values (pg_temp.pid('bob'), pg_temp.pid('dee'), 'ACCEPTED');
insert into public.moments (author_id, media_path, audience, location, caption, expires_at) values (pg_temp.pid('bob'), pg_temp.pid('bob')::text || '/old.jpg', 'LOCAL', public.geo(12.934567, 77.612345), 'p4 expired', now() - interval '2 hours');
insert into public.moments (author_id, media_path, audience, location, caption) values (pg_temp.pid('bob'), pg_temp.pid('bob')::text || '/fresh.jpg', 'LOCAL', public.geo(12.934567, 77.612345), 'p4 fresh');
select pg_temp.setv('t.m_old', id::text) from public.moments where caption = 'p4 expired';
select pg_temp.setv('t.m_new', id::text) from public.moments where caption = 'p4 fresh';
set role authenticated; select pg_temp.as_user('bob', '+919000000002');
\o /dev/null
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('eve'));
\o
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.blocked('P4 an expired LOCAL moment does not accept a view from a stranger', format($$select public.view_moment(%L, '🔥')$$, current_setting('t.m_old')));
select pg_temp.blocked('P4 a LOCAL moment does not accept a view from someone who never saw it (not synced, not nearby)', format($$select public.view_moment(%L, '🔥')$$, current_setting('t.m_new')));
select pg_temp.ok('P4 a nearby person who opens the author''s moments (open_moments records the access) can then view and react', (select count(*) = 1 from public.open_moments(pg_temp.pid('bob'), 12.9350, 77.6120) where caption = 'p4 fresh'));
select pg_temp.allowed('P4 the nearby viewer''s view is accepted once the moment was opened from where they stand', format($$select public.view_moment(%L, '👍')$$, current_setting('t.m_new')));
select pg_temp.as_user('eve', '+919000000007');
select pg_temp.blocked('P4 a LOCAL moment does not accept a view from someone its author blocked', format($$select public.view_moment(%L, '🔥')$$, current_setting('t.m_new')));
select pg_temp.as_user('dee', '+919000000004');
select pg_temp.blocked('P4 a reaction longer than 16 characters is refused', format($$select public.view_moment(%L, repeat('x', 5000))$$, current_setting('t.m_new')));
select pg_temp.allowed('P4 a normal reaction from a synced person still works', format($$select public.view_moment(%L, '🔥')$$, current_setting('t.m_new')));
select pg_temp.allowed('P4 the same person changes the reaction again', format($$select public.view_moment(%L, '😂')$$, current_setting('t.m_new')));
select pg_temp.allowed('P4 and again', format($$select public.view_moment(%L, '❤️')$$, current_setting('t.m_new')));
reset role;
select pg_temp.ok('P4 changing a reaction repeatedly notifies the author once, not every time', (select count(*) = 1 from public.notifications where profile_id = pg_temp.pid('bob') and kind = 'MOMENT_REACTION' and title like 'Dee reacted%'));
set role authenticated; select pg_temp.as_user('dee', '+919000000004');

-- comments: a person who blocked the new commenter is not told about the comment
reset role;
insert into public.posts (author_id, body, visibility) values (pg_temp.pid('cy'), 'p4 public post', 'PUBLIC');
select pg_temp.setv('t.p4_post', id::text) from public.posts where body = 'p4 public post';
set role authenticated; select pg_temp.as_user('bob', '+919000000002');
insert into public.post_comments (post_id, author_id, body) values (current_setting('t.p4_post')::uuid, public.me(), 'bob was here');
select pg_temp.as_user('eve', '+919000000007');
insert into public.post_comments (post_id, author_id, body) values (current_setting('t.p4_post')::uuid, public.me(), 'eve too');
reset role;
select pg_temp.ok('P4 a comment does not notify a previous commenter who blocked the new one', (select count(*) = 0 from public.notifications where profile_id = pg_temp.pid('bob') and kind = 'COMMENT_THREAD'));
-- likes: a blocked person cannot ping the post's author by voting
set role authenticated; select pg_temp.as_user('cy', '+919000000003');
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('bob'));
select pg_temp.as_user('bob', '+919000000002');
insert into public.post_votes (post_id, profile_id, vote) values (current_setting('t.p4_post')::uuid, public.me(), 1);
reset role;
select pg_temp.ok('P4 a like from someone the author blocked does not notify the author', (select count(*) = 0 from public.notifications where profile_id = pg_temp.pid('cy') and kind = 'POST_LIKE'));
-- reactions: the trigger itself refuses to notify across a block (row written under the viewer's identity)
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('bob'));
reset role;
insert into public.moments (author_id, media_path, audience, caption) values (pg_temp.pid('ann'), pg_temp.pid('ann')::text || '/x.jpg', 'SYNCED', 'p4 ann moment');
select pg_temp.as_user('bob', '+919000000002');
insert into public.moment_views (moment_id, viewer_id, reaction) select id, pg_temp.pid('bob'), '🔥' from public.moments where caption = 'p4 ann moment';
select pg_temp.ok('P4 a moment reaction from someone the author blocked does not notify the author', (select count(*) = 0 from public.notifications where profile_id = pg_temp.pid('ann') and kind = 'MOMENT_REACTION'));

-- invites: one pending invite per person per listing, and never across a block
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
select pg_temp.allowed('P4 the owner invites someone to help run the listing', format($$select public.invite(%L, null, %L, 'ADMIN')$$, current_setting('t.ann_listing'), (select short_code from public.profiles where id = pg_temp.pid('dee'))));
select pg_temp.blocked('P4 inviting the same person again while an invite is pending is refused', format($$select public.invite(%L, null, %L, 'ADMIN')$$, current_setting('t.ann_listing'), (select short_code from public.profiles where id = pg_temp.pid('dee'))));
select pg_temp.ok('P4 one pending invite per person and listing', (select count(*) = 1 from public.invites where listing_id = current_setting('t.ann_listing')::uuid and invitee_id = pg_temp.pid('dee') and status = 'PENDING'));
select pg_temp.as_user('eve', '+919000000007');
\o /dev/null
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('ann'));
\o
select pg_temp.as_user('ann', '+919000000001');
select pg_temp.blocked('P4 inviting someone who blocked you is refused', format($$select public.invite(%L, null, %L, 'ADMIN')$$, current_setting('t.ann_listing'), (select short_code from public.profiles where id = pg_temp.pid('eve'))));

-- ================================================================ P5 blocked_between is not an oracle
select pg_temp.as_user('mal', '+919000000005');
select pg_temp.ok('P5 a third party cannot ask whether two other people blocked each other', not public.blocked_between(pg_temp.pid('bob'), pg_temp.pid('eve')));
select pg_temp.as_user('bob', '+919000000002');
select pg_temp.ok('P5 the people concerned still get the real answer (policies rely on it)', public.blocked_between(pg_temp.pid('bob'), pg_temp.pid('eve')) and not public.blocked_between(pg_temp.pid('bob'), pg_temp.pid('mal')));

-- ================================================================ P6 storage
-- (a) chat: the bucket has a type allow-list and only the uploader can change or remove a file
reset role;
select pg_temp.ok('P6a the chat bucket has a mime allow-list', (select allowed_mime_types is not null from storage.buckets where id = 'chat'));
select pg_temp.ok('P6a the chat allow-list refuses apk, html, js, svg and zip', (select allowed_mime_types is not null and not (allowed_mime_types && array['application/vnd.android.package-archive', 'text/html', 'application/javascript', 'text/javascript', 'image/svg+xml', 'application/zip', 'application/octet-stream', 'application/x-msdownload']) from storage.buckets where id = 'chat'));
select pg_temp.ok('P6a the chat allow-list keeps photos, video, pdf, text and docx/xlsx/pptx',
  (select allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'application/pdf', 'text/plain',
     'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'] from storage.buckets where id = 'chat'));
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
insert into storage.objects (bucket_id, name, owner) values ('chat', current_setting('t.conv') || '/ann-file.pdf', 'ann');
select pg_temp.as_user('bob', '+919000000002');
select pg_temp.ok('P6a another member can still read the chat file', (select count(*) = 1 from storage.objects where bucket_id = 'chat' and name = current_setting('t.conv') || '/ann-file.pdf'));
select pg_temp.ok('P6a another member cannot overwrite the uploader''s chat file', pg_temp.rows(format($$update storage.objects set name = name where bucket_id = 'chat' and name = %L$$, current_setting('t.conv') || '/ann-file.pdf')) <= 0);
select pg_temp.ok('P6a another member cannot delete the uploader''s chat file', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'chat' and name = %L$$, current_setting('t.conv') || '/ann-file.pdf')) <= 0);
select pg_temp.allowed('P6a a member can upload a file of their own', format($$insert into storage.objects (bucket_id, name, owner) values ('chat', %L, 'bob')$$, current_setting('t.conv') || '/bob-file.pdf'));
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.blocked('P6a a non-member cannot upload into the chat', format($$insert into storage.objects (bucket_id, name, owner) values ('chat', %L, 'cy')$$, current_setting('t.conv') || '/cy.pdf'), 'row-level security');
select pg_temp.as_user('ann', '+919000000001');
select pg_temp.ok('P6a the uploader can delete their own chat file', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'chat' and name = %L$$, current_setting('t.conv') || '/ann-file.pdf')) = 1);

-- (b) docs: a VERIFIED listing document file cannot be overwritten or deleted while it is the evidence
insert into storage.objects (bucket_id, name, owner) values ('docs', pg_temp.pid('ann')::text || '/doc-fssai.pdf', 'ann'), ('docs', pg_temp.pid('ann')::text || '/other.pdf', 'ann');
select pg_temp.ok('P6b the owner can still read a document in their own folder', (select count(*) = 2 from storage.objects where bucket_id = 'docs'));
select pg_temp.ok('P6b a VERIFIED document file cannot be overwritten', pg_temp.rows(format($$update storage.objects set owner = 'ann' where bucket_id = 'docs' and name = %L$$, pg_temp.pid('ann')::text || '/doc-fssai.pdf')) <= 0);
select pg_temp.ok('P6b a VERIFIED document file cannot be deleted', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('ann')::text || '/doc-fssai.pdf')) <= 0);
select pg_temp.ok('P6b another file in the same folder can be deleted', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('ann')::text || '/other.pdf')) = 1);
reset role; update public.listing_documents set status = 'PENDING' where path = pg_temp.pid('ann')::text || '/doc-fssai.pdf'; set role authenticated; select pg_temp.as_user('ann', '+919000000001');
select pg_temp.ok('P6b once the document is no longer VERIFIED (replaced) its file can be deleted', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('ann')::text || '/doc-fssai.pdf')) = 1);
reset role; update public.listing_documents set status = 'VERIFIED' where listing_id = current_setting('t.ann_listing')::uuid;

-- (b2) the papers of a vehicle Bucks has approved (ACTIVE) are evidence too: their files cannot be swapped or removed behind the approval
insert into public.vehicles (owner_id, kind, model, plate, status, docs) values
  (pg_temp.pid('cy'), 'AUTO', 'Bajaj RE', 'RT06AA0001', 'ACTIVE', jsonb_build_array(
     jsonb_build_object('kind', 'RC', 'path', pg_temp.pid('cy')::text || '/vehicle-rc-abc.jpg'), jsonb_build_object('kind', 'INSURANCE', 'path', pg_temp.pid('cy')::text || '/vehicle-insurance-abc.jpg'))),
  (pg_temp.pid('cy'), 'CAB', 'Dzire', 'RT06AA0002', 'ACTIVE', jsonb_build_array(pg_temp.pid('cy')::text || '/vehicle-rc-legacy.jpg'));
insert into storage.objects (bucket_id, name, owner) select 'docs', pg_temp.pid('cy')::text || '/' || f, 'cy'
  from unnest(array['vehicle-rc-abc.jpg', 'vehicle-insurance-abc.jpg', 'vehicle-rc-legacy.jpg', 'vehicle-rc-new.jpg', 'vehicle-unlisted.jpg']) f;
set role authenticated; select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P6b2 the RC file of an ACTIVE vehicle cannot be overwritten', pg_temp.rows(format($$update storage.objects set owner = 'cy' where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-rc-abc.jpg')) <= 0);
select pg_temp.ok('P6b2 the insurance file of an ACTIVE vehicle cannot be deleted', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-insurance-abc.jpg')) <= 0);
select pg_temp.ok('P6b2 ... also when the vehicle lists its papers as bare paths', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-rc-legacy.jpg')) <= 0);
select pg_temp.ok('P6b2 a file no vehicle lists can still be deleted', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-unlisted.jpg')) = 1);
-- the app's replace flow: upload the new file, save the new list (the vehicle goes back to PENDING), then delete the old file
update public.vehicles set docs = jsonb_build_array(
  jsonb_build_object('kind', 'RC', 'path', pg_temp.pid('cy')::text || '/vehicle-rc-new.jpg'), jsonb_build_object('kind', 'INSURANCE', 'path', pg_temp.pid('cy')::text || '/vehicle-insurance-abc.jpg')) where plate = 'RT06AA0001';
select pg_temp.ok('P6b2 replacing a paper sends the vehicle back to PENDING', (select status = 'PENDING' from public.vehicles where plate = 'RT06AA0001'));
select pg_temp.ok('P6b2 ... and then the old file can be deleted (the replace flow of the app still works)', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-rc-abc.jpg')) = 1);
reset role; update public.vehicles set status = 'ACTIVE' where plate = 'RT06AA0001'; set role authenticated; select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P6b2 once Bucks approves the new papers their files are locked in turn', pg_temp.rows(format($$delete from storage.objects where bucket_id = 'docs' and name = %L$$, pg_temp.pid('cy')::text || '/vehicle-rc-new.jpg')) <= 0);
reset role;

-- (c) posts and moments: a row that names someone else's file does not open it up
insert into storage.objects (bucket_id, name, owner) values ('posts', pg_temp.pid('vic')::text || '/secret.jpg', 'vic'), ('posts', pg_temp.pid('vic')::text || '/public.jpg', 'vic'),
  ('moments', pg_temp.pid('vic')::text || '/private.jpg', 'vic'), ('moments', pg_temp.pid('mal')::text || '/mine.jpg', 'mal');
insert into public.posts (author_id, body, visibility, media) values
  (pg_temp.pid('vic'), 'vic synced-only', 'SYNCED', jsonb_build_array(jsonb_build_object('path', pg_temp.pid('vic')::text || '/secret.jpg', 'mime', 'image/jpeg'))),
  (pg_temp.pid('vic'), 'vic public', 'PUBLIC', jsonb_build_array(jsonb_build_object('path', pg_temp.pid('vic')::text || '/public.jpg', 'mime', 'image/jpeg')));
insert into public.moments (author_id, media_path, audience, caption) values (pg_temp.pid('vic'), pg_temp.pid('vic')::text || '/private.jpg', 'CLOSE', 'vic close moment');
insert into public.syncs (requester_id, addressee_id, status) values (pg_temp.pid('mal'), pg_temp.pid('cy'), 'ACCEPTED');
set role authenticated; select pg_temp.as_user('mal', '+919000000005');
insert into public.posts (author_id, body, visibility, media) values (public.me(), 'look at this', 'PUBLIC', jsonb_build_array(jsonb_build_object('path', pg_temp.pid('vic')::text || '/secret.jpg', 'mime', 'image/jpeg')));
insert into public.moments (author_id, media_path, audience, caption) values (public.me(), pg_temp.pid('vic')::text || '/private.jpg', 'SYNCED', 'mal steals a path');
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P6c a public post naming someone else''s private photo does not make that photo readable', (select count(*) = 0 from storage.objects where bucket_id = 'posts' and name = pg_temp.pid('vic')::text || '/secret.jpg'));
select pg_temp.ok('P6c a synced moment naming someone else''s private file does not make it readable', (select count(*) = 0 from storage.objects where bucket_id = 'moments' and name = pg_temp.pid('vic')::text || '/private.jpg'));
select pg_temp.ok('P6c the author''s own visible post still opens its photo to everyone who may see the post', (select count(*) = 1 from storage.objects where bucket_id = 'posts' and name = pg_temp.pid('vic')::text || '/public.jpg'));

-- ================================================================ P1 again: the moving-home attack (review finding RT-01)
-- The caller owns their own stored home, so a distance measured from it leaks whatever the rounding does not hide: moving the home along a
-- line and watching where the 2 km step flips finds the points exactly 3, 5, 7 km from the victim, and three flips locate the victim to ~13 m.
-- Both homes are now snapped to a 0.02 degree grid first. Two victim homes in one grid cell (about 0.6 km apart) must look identical to
-- any probing, and a home in the next cell must not (or the probing would prove nothing).
create function pg_temp.p1_step(la double precision, ln double precision) returns double precision language plpgsql as $$
declare s double precision;
begin
  update public.profiles set home = public.geo(la, ln) where id = public.me();
  select distance_m into s from public.suggest_people(0, 0, 50) where id = pg_temp.pid('vic');
  return coalesce(s, -1);
end $$;
create function pg_temp.p1_flip(la0 double precision, ln0 double precision, la1 double precision, ln1 double precision) returns double precision language plpgsql as $$
declare s0 double precision := pg_temp.p1_step(la0, ln0); f double precision; a double precision := 0; b double precision := 1; n int := 0;
begin
  while n < 40 loop
    f := (a + b) / 2;
    if pg_temp.p1_step(la0 + (la1 - la0) * f, ln0 + (ln1 - ln0) * f) = s0 then a := f; else b := f; end if;
    n := n + 1;
  end loop;
  return a;
end $$;
-- every answer to a 15 x 15 sweep of the caller's home over 12 km, as a hash plus the number of distinct distances seen
create function pg_temp.p1_sweep() returns text language plpgsql as $$
declare i int; j int; d double precision; r text := ''; seen double precision[] := '{}';
begin
  for i in 0..14 loop for j in 0..14 loop
    d := pg_temp.p1_step(12.90 + i * 0.008, 77.54 + j * 0.008);
    r := r || d::text || ',';
    if d >= 0 and not (d = any(seen)) then seen := seen || d; end if;
  end loop; end loop;
  return md5(r) || ':' || coalesce(array_length(seen, 1), 0);
end $$;
reset role;
set session_replication_role = replica;
insert into public.syncs (requester_id, addressee_id, status) values (pg_temp.pid('cy'), pg_temp.pid('vic'), 'ACCEPTED');   -- a mutual friend of mal and vic: vic always ranks inside the first 50
set session_replication_role = origin;
update public.profiles set home = public.geo(12.9800, 77.6200) where auth_uid = 'vic';   -- the middle of the grid cell that spans 12.97..12.99 and 77.61..77.63
set role authenticated; select pg_temp.as_user('mal', '+919000000005');
select pg_temp.p1_sweep() as sw_a \gset
select pg_temp.p1_flip(12.9716, 77.5000, 12.9716, 77.5900)::text as fl_a \gset
reset role; update public.profiles set home = public.geo(12.9840, 77.6240) where auth_uid = 'vic'; set role authenticated; select pg_temp.as_user('mal', '+919000000005');
select pg_temp.p1_sweep() as sw_b \gset
select pg_temp.p1_flip(12.9716, 77.5000, 12.9716, 77.5900)::text as fl_b \gset
reset role; update public.profiles set home = public.geo(13.0000, 77.6200) where auth_uid = 'vic'; set role authenticated; select pg_temp.as_user('mal', '+919000000005');
select pg_temp.p1_sweep() as sw_c \gset
reset role;
update public.profiles set home = public.geo(12.9700, 77.6100) where auth_uid = 'vic';
update public.profiles set home = public.geo(12.9100, 77.5900) where auth_uid = 'mal';
set session_replication_role = replica; delete from public.syncs where requester_id = pg_temp.pid('cy') and addressee_id = pg_temp.pid('vic'); set session_replication_role = origin;
set role authenticated; select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P1 the sweep sees several distance steps for the victim (so it can detect a leak)', split_part(:'sw_a', ':', 2)::int >= 3);
select pg_temp.ok('P1 moving your own home around gives the same answers for two victim homes in one grid cell (no position inside the cell)', :'sw_a' = :'sw_b');
select pg_temp.ok('P1 the point where the step flips (bisecting a line of home positions) is the same for both: it marks a grid line, not a distance from the victim', abs(:'fl_a'::float8 - :'fl_b'::float8) < 1e-9);
select pg_temp.ok('P1 a victim in the next grid cell does give other answers (the cell is what remains visible)', :'sw_a' <> :'sw_c');

-- ================================================================ P7 crash-poisoning JSON
select pg_temp.as_user('ann', '+919000000001');
select pg_temp.blocked('P7 an attachment whose path is an object is refused', format($$insert into public.messages (conversation_id, sender_id, body, attachment) values (%L, public.me(), 'x', '{"path": {"a": 1}, "name": "n", "mime": "m", "size": 1}')$$, current_setting('t.grp')));
select pg_temp.blocked('P7 an attachment that is an array is refused', format($$insert into public.messages (conversation_id, sender_id, body, attachment) values (%L, public.me(), 'x', '[1, 2]')$$, current_setting('t.grp')));
select pg_temp.blocked('P7 an attachment with a non-numeric size is refused', format($$insert into public.messages (conversation_id, sender_id, body, attachment) values (%L, public.me(), 'x', '{"path": "a/b.pdf", "name": "n", "mime": "application/pdf", "size": "big"}')$$, current_setting('t.grp')));
select pg_temp.blocked('P7 an attachment missing its mime is refused', format($$insert into public.messages (conversation_id, sender_id, body, attachment) values (%L, public.me(), 'x', '{"path": "a/b.pdf", "name": "n", "size": 3}')$$, current_setting('t.grp')));
select pg_temp.allowed('P7 a well-formed attachment is accepted', format($$insert into public.messages (conversation_id, sender_id, body, attachment) values (%L, public.me(), '', '{"path": "a/b.pdf", "name": "b.pdf", "mime": "application/pdf", "size": 120000}')$$, current_setting('t.grp')));
select pg_temp.blocked('P7 post media that is an object, not an array, is refused', $$insert into public.posts (author_id, body, media) values (public.me(), 'x', '{"path": "a", "mime": "b"}')$$);
select pg_temp.blocked('P7 post media holding a non-object is refused', $$insert into public.posts (author_id, body, media) values (public.me(), 'x', '[1, "a"]')$$);
select pg_temp.blocked('P7 post media with an array as its path is refused', $$insert into public.posts (author_id, body, media) values (public.me(), 'x', '[{"path": ["a"], "mime": "image/jpeg"}]')$$);
select pg_temp.blocked('P7 post media with an object as its mime is refused', $$insert into public.posts (author_id, body, media) values (public.me(), 'x', '[{"path": "a", "mime": {"x": 1}}]')$$);
select pg_temp.allowed('P7 well-formed post media is accepted', $$insert into public.posts (author_id, body, media) values (public.me(), 'x', '[{"path": "a/1.jpg", "mime": "image/jpeg"}]')$$);
select pg_temp.blocked('P7 a moment media path of absurd length is refused', $$insert into public.moments (author_id, media_path) values (public.me(), repeat('a', 5000))$$);

-- ================================================================ P8 hidden listings stay hidden
select pg_temp.as_user('bob', '+919000000002');
select pg_temp.ok('P8 jobs of a PENDING listing are not readable by strangers', (select count(*) = 0 from public.jobs where title = 'Cook wanted'));
select pg_temp.blocked('P8 nobody can apply to a job of a PENDING listing', format($$insert into public.applications (job_id, applicant_id, note) values (%L, public.me(), 'hire me')$$, current_setting('t.dee_job')));
select pg_temp.ok('P8 job_page hides a job of a PENDING listing', (select count(*) = 0 from public.job_page(current_setting('t.dee_job')::uuid)));
select pg_temp.ok('P8 jobs_near never lists a PENDING listing', (select count(*) = 0 from public.jobs_near(12.9063, 77.5857, 5000) where title = 'Cook wanted'));
select pg_temp.ok('P8 the feed does not carry posts of a PENDING listing', (select count(*) = 0 from public.feed(12.9063, 77.5857) where body like 'Grand opening of Dee Kitchen%'));
select pg_temp.as_user('dee', '+919000000004');
select pg_temp.ok('P8 the listing''s own team still sees its jobs', (select count(*) = 1 from public.jobs where title = 'Cook wanted'));
select pg_temp.ok('P8 the listing''s own team still sees its own post', (select count(*) = 1 from public.posts where body like 'Grand opening of Dee Kitchen%'));
select pg_temp.blocked('P8 a PENDING listing cannot post publicly as itself', format($$insert into public.posts (author_id, listing_id, body, visibility) values (public.me(), %L, 'Open now!', 'PUBLIC')$$, current_setting('t.dee_listing')));
-- a LIVE listing works normally, a suspended one cannot answer applicants
select pg_temp.as_user('ann', '+919000000001');
select pg_temp.allowed('P8 a LIVE listing can still post as itself', format($$insert into public.posts (author_id, listing_id, body, visibility) values (public.me(), %L, 'Fresh coffee today', 'PUBLIC')$$, current_setting('t.ann_listing')));
insert into public.jobs (listing_id, title, description, pay, created_by) select id, 'Barista', 'Mornings', '12000', public.me() from public.listings where title = 'Ann Cafe';
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.allowed('P8 anyone can apply to an open job of a LIVE listing', $$insert into public.applications (job_id, applicant_id, note) select id, public.me(), 'I can start Monday' from public.jobs where title = 'Barista'$$);
select pg_temp.as_user('dee', '+919000000004');
select pg_temp.allowed('P8 a second applicant applies', $$insert into public.applications (job_id, applicant_id, note) select id, public.me(), 'Weekends too' from public.jobs where title = 'Barista'$$);
reset role;
select pg_temp.setv('t.app_cy', a.id::text) from public.applications a where a.applicant_id = pg_temp.pid('cy');
select pg_temp.setv('t.app_dee', a.id::text) from public.applications a where a.applicant_id = pg_temp.pid('dee');
select pg_temp.setv('t.barista', id::text) from public.jobs where title = 'Barista';
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
select pg_temp.allowed('P8 the owner of a LIVE listing can chat with an applicant', format($$select public.start_applicant_chat(%L)$$, current_setting('t.app_cy')));
reset role; update public.listings set status = 'SUSPENDED' where title = 'Ann Cafe'; set role authenticated; select pg_temp.as_user('ann', '+919000000001');
select pg_temp.blocked('P8 a SUSPENDED listing cannot open chats with applicants', format($$select public.start_applicant_chat(%L)$$, current_setting('t.app_dee')));
select pg_temp.as_user('eve', '+919000000007');
select pg_temp.blocked('P8 nobody can apply once the listing is SUSPENDED', format($$insert into public.applications (job_id, applicant_id, note) values (%L, public.me(), 'late')$$, current_setting('t.barista')));
reset role; update public.listings set status = 'LIVE' where title = 'Ann Cafe';

-- ================================================================ P9 a LIVE listing cannot be moved or re-categorised without re-review
create function pg_temp.status_of(t text) returns text language sql as $$ select status from public.listings where title = t $$;
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
update public.listings set title = 'Ann Cafe & Bakery', description = 'Coffee, cake and bread' where title = 'Ann Cafe';
select pg_temp.ok('P9 title and description edits do not need a re-review', pg_temp.status_of('Ann Cafe & Bakery') = 'LIVE');
update public.listings set category = 'Sweets' where title = 'Ann Cafe & Bakery';
select pg_temp.ok('P9 re-categorising a LIVE listing sends it back to PENDING', pg_temp.status_of('Ann Cafe & Bakery') = 'PENDING');
reset role;
select pg_temp.ok('P9 the re-review path works: with its recommendations and documents intact it can go LIVE again', public.try_go_live((select id from public.listings where title = 'Ann Cafe & Bakery')) = 'LIVE');
set role authenticated; select pg_temp.as_user('ann', '+919000000001');
update public.listings set location = public.geo(28.5355, 77.3910) where title = 'Ann Cafe & Bakery';
select pg_temp.ok('P9 moving a LIVE listing far away sends it back to PENDING', pg_temp.status_of('Ann Cafe & Bakery') = 'PENDING');
reset role;
select pg_temp.ok('P9 recommendations that no longer cover the new spot are dropped (the cap cannot be carried to another place)', (select count(*) = 0 from public.recommendations where listing_id = current_setting('t.ann_listing')::uuid));
select pg_temp.ok('P9 the moved listing cannot slip live on a single new recommendation', public.try_go_live((select id from public.listings where title = 'Ann Cafe & Bakery')) = 'PENDING');
update public.listings set location = public.geo(12.9063, 77.5857), status = 'LIVE' where title = 'Ann Cafe & Bakery';

-- vehicles: plates are stored normalised and unique on the normalised value; changing plate, kind or papers re-reviews
set role authenticated; select pg_temp.as_user('bob', '+919000000002');
insert into public.vehicles (owner_id, kind, model, plate) values (public.me(), 'AUTO', 'Bajaj', 'ka 01 ab 1234');
select pg_temp.ok('P9 a plate is stored upper case without spaces', (select plate = 'KA01AB1234' from public.vehicles where owner_id = public.me()));
select pg_temp.as_user('cy', '+919000000003');
select pg_temp.blocked('P9 the same plate typed differently is a duplicate', $$insert into public.vehicles (owner_id, kind, model, plate) values (public.me(), 'AUTO', 'Piaggio', 'KA-01 ab1234')$$);
select pg_temp.as_user('bob', '+919000000002');
reset role; update public.vehicles set status = 'ACTIVE' where owner_id = pg_temp.pid('bob'); set role authenticated; select pg_temp.as_user('bob', '+919000000002');
update public.vehicles set model = 'Bajaj RE' where owner_id = public.me();
select pg_temp.ok('P9 editing the model of a checked vehicle keeps it ACTIVE', (select status = 'ACTIVE' from public.vehicles where owner_id = public.me()));
update public.vehicles set plate = 'ka01ab1234' where owner_id = public.me();
select pg_temp.ok('P9 retyping the same plate in lower case is not a change', (select status = 'ACTIVE' from public.vehicles where owner_id = public.me()));
update public.vehicles set plate = 'KA02ZZ9999' where owner_id = public.me();
select pg_temp.ok('P9 a new plate sends a checked vehicle back to PENDING', (select status = 'PENDING' from public.vehicles where owner_id = public.me()));
reset role; update public.vehicles set status = 'ACTIVE' where owner_id = pg_temp.pid('bob'); set role authenticated; select pg_temp.as_user('bob', '+919000000002');
update public.vehicles set kind = 'CAB' where owner_id = public.me();
select pg_temp.ok('P9 a new vehicle type sends a checked vehicle back to PENDING', (select status = 'PENDING' from public.vehicles where owner_id = public.me()));
reset role; update public.vehicles set status = 'ACTIVE' where owner_id = pg_temp.pid('bob'); set role authenticated; select pg_temp.as_user('bob', '+919000000002');
update public.vehicles set docs = '[{"kind": "RC", "path": "x/rc.jpg"}]' where owner_id = public.me();
select pg_temp.ok('P9 new documents send a checked vehicle back to PENDING', (select status = 'PENDING' from public.vehicles where owner_id = public.me()));

-- ================================================================ P10 device tokens and text lengths
select pg_temp.as_user('eve', '+919000000007');
\o /dev/null
select format('select public.register_device_token(%L);', 'tok-eve-' || lpad(g::text, 2, '0') || '-abcdefghijklmnopqrstuv') from generate_series(1, 12) g \gexec
\o
select pg_temp.ok('P10 a profile keeps at most 10 device tokens', (select count(*) <= 10 from public.device_tokens));
select pg_temp.ok('P10 the oldest tokens are the ones evicted', (select count(*) = 0 from public.device_tokens where token like 'tok-eve-01-%') and (select count(*) = 1 from public.device_tokens where token like 'tok-eve-12-%'));
\o /dev/null
select format('insert into public.device_tokens (token, profile_id) values (%L, public.me());', 'tok-eve-direct-' || lpad(g::text, 2, '0') || '-abcdefghijklmnopq') from generate_series(1, 12) g \gexec
\o
select pg_temp.ok('P10 direct inserts cannot get around the cap', (select count(*) <= 10 from public.device_tokens));
select pg_temp.blocked('P10 a device token of one character is refused', $$select public.register_device_token('x')$$);
select pg_temp.blocked('P10 a device token of 5000 characters is refused', $$select public.register_device_token(repeat('a', 5000))$$);
select pg_temp.blocked('P10 profiles.name over 80 characters is refused', $$update public.profiles set name = repeat('n', 500) where id = public.me()$$);
select pg_temp.blocked('P10 profiles.bio over 300 characters is refused', $$update public.profiles set bio = repeat('b', 500) where id = public.me()$$);
select pg_temp.blocked('P10 profiles.area over 80 characters is refused', $$update public.profiles set area = repeat('a', 500) where id = public.me()$$);
select pg_temp.allowed('P10 an 80-character name is fine', $$update public.profiles set name = repeat('n', 80) where id = public.me()$$);
select pg_temp.blocked('P10 listings.title over 100 characters is refused', $$insert into public.listings (kind, owner_id, title, category, location) values ('SKILL', public.me(), repeat('t', 200), 'Tutor', public.geo(12.9, 77.6))$$);
select pg_temp.blocked('P10 listings.description over 2000 characters is refused', $$insert into public.listings (kind, owner_id, title, category, description, location) values ('SKILL', public.me(), 'Tutor', 'Tutor', repeat('d ', 1500), public.geo(12.9, 77.6))$$);
select pg_temp.as_user('ann', '+919000000001');
select pg_temp.blocked('P10 messages.body over 4000 characters is refused', format($$insert into public.messages (conversation_id, sender_id, body) values (%L, public.me(), repeat('m', 5000))$$, current_setting('t.grp')));
select pg_temp.blocked('P10 posts.body over 5000 characters is refused', $$insert into public.posts (author_id, body) values (public.me(), repeat('p', 6000))$$);
select pg_temp.blocked('P10 post_comments.body over 1000 characters is refused', format($$insert into public.post_comments (post_id, author_id, body) values (%L, public.me(), repeat('c', 2000))$$, current_setting('t.p4_post')));
select pg_temp.blocked('P10 moments.caption over 200 characters is refused', $$insert into public.moments (author_id, media_path, caption) values (public.me(), public.me()::text || '/c.jpg', repeat('c', 300))$$);
select pg_temp.blocked('P10 jobs.title over 100 characters is refused', format($$insert into public.jobs (listing_id, title, created_by) values (%L, repeat('j', 200), public.me())$$, current_setting('t.ann_listing')));
select pg_temp.blocked('P10 jobs.description over 2000 characters is refused', format($$insert into public.jobs (listing_id, title, description, created_by) values (%L, 'Cook', repeat('j', 3000), public.me())$$, current_setting('t.ann_listing')));
select pg_temp.blocked('P10 conversations.title over 80 characters is refused', $$select public.create_group(repeat('g', 200), '{}')$$);
select pg_temp.as_user('mal', '+919000000005');
select pg_temp.blocked('P10 applications.note over 1000 characters is refused', format($$insert into public.applications (job_id, applicant_id, note) values (%L, public.me(), repeat('a', 2000))$$, current_setting('t.barista')));
reset role;
select pg_temp.blocked('P10 reviews.comment over 1000 characters is refused', format($$insert into public.reviews (listing_id, author_id, vote, comment) values (%L, %L, 1, repeat('r', 2000))$$, current_setting('t.ann_listing'), pg_temp.pid('mal')));

-- ================================================================ P11 delete_my_account really deletes
\o /dev/null
set role authenticated;
select pg_temp.as_user('gone', '+919000000099'); select public.ensure_profile('Gone Person', '9000000099');
reset role;
update public.profiles set created_at = now() - interval '60 days', home = public.geo(12.91, 77.59), bio = 'my bio', area = 'JP Nagar' where auth_uid = 'gone';
insert into public.syncs (requester_id, addressee_id, status) values (pg_temp.pid('gone'), pg_temp.pid('cy'), 'ACCEPTED');
set role authenticated; select pg_temp.as_user('gone', '+919000000099');
insert into public.contact_links (owner_id, profile_id, phones, note) values (public.me(), pg_temp.pid('cy'), '["98450 12345"]', 'gone knows cy');
insert into public.user_settings (profile_id, who_can_message) values (public.me(), 'EVERYONE');
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('eve'));
insert into public.close_friends (profile_id, friend_id) values (public.me(), pg_temp.pid('cy'));
insert into public.moment_mutes (profile_id, muted_id) values (public.me(), pg_temp.pid('cy'));
select public.register_device_token('tok-gone-phone-abcdefghijklmnop');
insert into public.vehicles (owner_id, kind, model, plate, docs) values (public.me(), 'AUTO', 'Bajaj', 'GN01AA0001', '[{"kind": "RC", "path": "rc.jpg"}]');
insert into public.listings (kind, owner_id, title, category, description, area, photo_url, location, details) values ('BUSINESS', public.me(), 'Gone Grill', 'Restaurant', 'my private description', 'JP Nagar', 'https://x/y.jpg', public.geo(12.91, 77.59), '{"hours": "9-5", "cod": true}');
insert into public.listings (kind, owner_id, title, category, description, area, location, details) values ('SKILL', public.me(), 'Gone Plumber', 'Plumber', 'call me any time', 'JP Nagar', public.geo(12.91, 77.59), '{"rate": "500/hr"}');
select pg_temp.as_user('cy', '+919000000003');
insert into public.contact_links (owner_id, profile_id, phones, note) values (public.me(), pg_temp.pid('gone'), '["99999 88888"]', 'cy knows gone');
insert into public.blocks (blocker_id, blocked_id) values (public.me(), pg_temp.pid('gone'));
insert into public.close_friends (profile_id, friend_id) values (public.me(), pg_temp.pid('gone'));
insert into public.moment_mutes (profile_id, muted_id) values (public.me(), pg_temp.pid('gone'));
select pg_temp.as_user('gone', '+919000000099');
insert into public.applications (job_id, applicant_id, note) values (current_setting('t.barista')::uuid, public.me(), 'call me at 9000000099');
select pg_temp.as_user('ann', '+919000000001');
select public.invite(current_setting('t.ann_listing')::uuid, null, (select short_code from public.profiles where id = pg_temp.pid('gone')), 'ADMIN');
select pg_temp.as_user('gone', '+919000000099');
select public.invite((select id from public.listings where title = 'Gone Grill'), null, (select short_code from public.profiles where id = pg_temp.pid('dee')), 'ADMIN');
insert into public.moments (author_id, media_path, audience, caption) values (public.me(), public.me()::text || '/m.mp4', 'SYNCED', 'gone moment');
reset role;
insert into public.moment_views (moment_id, viewer_id, reaction) select id, pg_temp.pid('gone'), '🔥' from public.moments where caption = 'p4 fresh';
insert into public.moment_access (viewer_id, moment_id) select pg_temp.pid('gone'), id from public.moments where caption = 'p4 fresh';
insert into public.vehicle_members (vehicle_id, profile_id, role) select id, pg_temp.pid('gone'), 'ADMIN' from public.vehicles where owner_id = pg_temp.pid('bob');
insert into public.notifications (profile_id, kind, title) values (pg_temp.pid('gone'), 'TEST', 'for gone');
insert into public.conversations (kind, direct_key, created_by) values ('DIRECT', 'gone:cy', pg_temp.pid('gone'));
insert into public.conversation_members (conversation_id, profile_id) select id, x from public.conversations, unnest(array[pg_temp.pid('gone'), pg_temp.pid('cy')]) x where direct_key = 'gone:cy';
select pg_temp.setv('t.gconv', id::text) from public.conversations where direct_key = 'gone:cy';
select pg_temp.setv('t.gid', pg_temp.pid('gone')::text);
select pg_temp.setv('t.glisting', id::text) from public.listings where title = 'Gone Grill';
insert into storage.objects (bucket_id, name, owner) values
  ('avatars', pg_temp.pid('gone')::text || '/a.jpg', 'gone'), ('posts', pg_temp.pid('gone')::text || '/p.jpg', 'gone'), ('moments', pg_temp.pid('gone')::text || '/m.mp4', 'gone'),
  ('docs', pg_temp.pid('gone')::text || '/id.jpg', 'gone'), ('docs', pg_temp.pid('gone')::text || '/rc.jpg', 'gone'),
  ('listing-media', current_setting('t.glisting') || '/cover.jpg', 'gone'),
  ('chat', current_setting('t.gconv') || '/gone-file.pdf', 'gone'), ('chat', current_setting('t.gconv') || '/cy-file.pdf', 'cy'),
  ('avatars', pg_temp.pid('cy')::text || '/a.jpg', 'cy'), ('posts', pg_temp.pid('cy')::text || '/p.jpg', 'cy');
\o
create function pg_temp.left_of(t text, col1 text, col2 text default null) returns bigint language plpgsql as $$
declare n bigint; begin execute format('select count(*) from public.%I where %I = $1 %s', t, col1, case when col2 is null then '' else format('or %I = $1', col2) end) into n using current_setting('t.gid')::uuid; return n; end $$;

set role authenticated; select pg_temp.as_user('gone', '+919000000099');
\o /dev/null
select public.delete_my_account();
\o
reset role;
select pg_temp.ok('P11 contact links the person owned are gone', pg_temp.left_of('contact_links', 'owner_id') = 0);
select pg_temp.ok('P11 contact links other people keep about the person are gone', pg_temp.left_of('contact_links', 'profile_id') = 0);
select pg_temp.ok('P11 user_settings are gone', pg_temp.left_of('user_settings', 'profile_id') = 0);
select pg_temp.ok('P11 blocks in both directions are gone', pg_temp.left_of('blocks', 'blocker_id', 'blocked_id') = 0);
select pg_temp.ok('P11 close friends in both directions are gone', pg_temp.left_of('close_friends', 'profile_id', 'friend_id') = 0);
select pg_temp.ok('P11 moment views are gone', pg_temp.left_of('moment_views', 'viewer_id') = 0);
select pg_temp.ok('P11 moment mutes in both directions are gone', pg_temp.left_of('moment_mutes', 'profile_id', 'muted_id') = 0);
select pg_temp.ok('P11 moment access rows are gone', pg_temp.left_of('moment_access', 'viewer_id') = 0);
select pg_temp.ok('P11 device tokens are gone', pg_temp.left_of('device_tokens', 'profile_id') = 0);
select pg_temp.ok('P11 job applications (with their notes) are gone', pg_temp.left_of('applications', 'applicant_id') = 0);
select pg_temp.ok('P11 invites sent to or by the person are gone', pg_temp.left_of('invites', 'inviter_id', 'invitee_id') = 0);
select pg_temp.ok('P11 vehicles they owned (plates, document paths) are gone', pg_temp.left_of('vehicles', 'owner_id') = 0);
select pg_temp.ok('P11 their seats on other people''s vehicles are gone', pg_temp.left_of('vehicle_members', 'profile_id') = 0);
select pg_temp.ok('P11 notifications addressed to the person are gone', pg_temp.left_of('notifications', 'profile_id') = 0);
select pg_temp.ok('P11 the personal free text of their business listing is emptied', (select description = '' and area = '' and photo_url is null and details = '{}'::jsonb and status = 'DELETED' from public.listings where title = 'Gone Grill'));
select pg_temp.ok('P11 the title of their personal listing is anonymised', (select count(*) = 0 from public.listings where title = 'Gone Plumber') and (select count(*) = 1 from public.listings where owner_id = current_setting('t.gid')::uuid and kind = 'SKILL' and status = 'DELETED' and description = '' and details = '{}'::jsonb));
select pg_temp.ok('P11 the profile itself is anonymised', (select name = '' and bio = '' and area = '' and home is null and status = 'DELETED' from public.profiles where id = current_setting('t.gid')::uuid));
select pg_temp.ok('P11 the phone and payment row are gone', pg_temp.left_of('profile_private', 'profile_id') = 0);
select pg_temp.ok('P11 storage_cleanup queues the person''s files in their own folders and listings',
  pg_temp.scalar($$select count(*) from public.storage_cleanup where name like current_setting('t.gid') || '/%' or name like current_setting('t.glisting') || '/%'$$) = '6');
select pg_temp.ok('P11 storage_cleanup queues the chat file they uploaded', pg_temp.scalar($$select count(*) from public.storage_cleanup where bucket = 'chat' and name like '%/gone-file.pdf'$$) = '1');
select pg_temp.ok('P11 storage_cleanup does not queue anyone else''s files (other avatar, other post, other person''s chat file)',
  pg_temp.scalar($$select count(*) from public.storage_cleanup where name like '%/cy-file.pdf' or name like (select id::text from public.profiles where auth_uid = 'cy') || '/%'$$) = '0');
select pg_temp.ok('P11 the cleanup queue cannot be read by the app', pg_temp.scalar($$select has_table_privilege('authenticated', 'public.storage_cleanup', 'select')::text$$) = 'false');
set role authenticated; select pg_temp.as_user('cy', '+919000000003');
select pg_temp.blocked('P11 a signed-in user cannot read the cleanup queue', $$select * from public.storage_cleanup$$, 'permission denied');
select pg_temp.blocked('P11 a signed-in user cannot write to the cleanup queue', $$insert into public.storage_cleanup (bucket, name) values ('docs', 'x')$$, 'permission denied');

-- ================================================================ P14 unbounded search parameters
reset role;
insert into public.listings (kind, owner_id, title, category, location, status) select 'BUSINESS', pg_temp.pid('dee'), 'Bulk ' || g, 'Cafe', public.geo(12.9100 + g * 0.0001, 77.5900), 'LIVE' from generate_series(1, 130) g;
insert into public.listings (kind, owner_id, title, category, location, status) values ('BUSINESS', pg_temp.pid('dee'), 'Far Shop', 'Cafe', public.geo(13.0827, 80.2707), 'LIVE');
insert into public.jobs (listing_id, title, created_by) select id, 'Far Job', pg_temp.pid('dee') from public.listings where title = 'Far Shop';
set role authenticated; select pg_temp.as_user('cy', '+919000000003');
select pg_temp.ok('P14 search_listings caps the radius at 50 km (a shop 290 km away is not returned for a 1000 km radius)', (select count(*) = 0 from public.search_listings('', 12.91, 77.59, 1000000, null, 1000) where title = 'Far Shop'));
select pg_temp.ok('P14 search_listings caps the limit at 100', (select count(*) <= 100 from public.search_listings('', 12.91, 77.59, 10000, null, 100000)));
select pg_temp.ok('P14 jobs_near caps the radius at 50 km', (select count(*) = 0 from public.jobs_near(12.91, 77.59, 1000000) where title = 'Far Job'));
