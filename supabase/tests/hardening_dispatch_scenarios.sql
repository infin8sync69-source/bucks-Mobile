\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Hardening scenarios for dispatch, rides, delivery, orders and reviews (supabase/migrations/hardening_dispatch.sql).
-- Every printed line starts with "ok" or "FAIL". Each item is written as the exploit first: on a database WITHOUT the
-- migration the exploit lines print FAIL (the hole is real), with it they print ok. Anything that can raise is called through
-- pg_temp.q / pg_temp.blocked so the script also runs to the end on the unhardened stack.
-- Locations (Bengaluru): pick-up P 12.9250,77.5938; drop D 12.9757,77.6063 (5.8 km); near the pick-up N 12.9262,77.5941; far F 13.2000,77.7000 (31 km).

create or replace function pg_temp.as_user(u text) returns setof text language plpgsql as $$ begin perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false); return; end $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when coalesce(ok, false) then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.eq(actual text, want text, what text) returns text language sql as $$
  select case when actual is not distinct from want then 'ok, ' || what else 'FAIL ' || what || ' (got: ' || left(coalesce(actual, '<null>'), 90) || ', want: ' || left(coalesce(want, '<null>'), 90) || ')' end $$;
-- first column of a query as text, or 'ERR: message'
create or replace function pg_temp.q(sql text) returns text language plpgsql as $$ declare r text; begin execute sql into r; return coalesce(r, '<null>'); exception when others then return 'ERR: ' || sqlerrm; end $$;
create or replace function pg_temp.ok(sql text) returns text language plpgsql as $$ begin execute sql; return 'done'; exception when others then return 'ERR: ' || sqlerrm; end $$;
-- true when the statement raises an error containing `want`
create or replace function pg_temp.blocked(sql text, want text) returns boolean language plpgsql as $$ begin execute sql; return false; exception when others then return sqlerrm ilike '%' || want || '%'; end $$;
create or replace function pg_temp.pid(u text) returns uuid language sql security definer as $$ select id from public.profiles where auth_uid = u $$;
-- superuser helpers (fixtures, ageing rows, reading what a role cannot)
create or replace function pg_temp.run(sql text) returns void language plpgsql security definer as $$ begin execute sql; end $$;
create or replace function pg_temp.sudo(sql text) returns void language plpgsql security definer as $$ begin execute sql; exception when others then null; end $$;
create or replace function pg_temp.sq(sql text) returns text language plpgsql security definer as $$ declare r text; begin execute sql into r; return coalesce(r, '<null>'); exception when others then return 'ERR: ' || sqlerrm; end $$;

create or replace function pg_temp.mkuser(p_u text, p_phone text default null, p_upi text default null) returns uuid language plpgsql security definer as $$
declare pr uuid;
begin
  insert into public.profiles (auth_uid, name) values (p_u, initcap(p_u)) returning id into pr;
  insert into public.profile_private (profile_id, phone, upi_uri) values (pr, coalesce(p_phone, '9800' || lpad((abs(hashtext(p_u)) % 1000000)::text, 6, '0')), p_upi);
  return pr;
end $$;
-- a verified vehicle, online at (lat, lng), optionally with a live DRIVER listing
create or replace function pg_temp.mkdriver(p_u text, p_kind text, p_plate text, p_lat double precision, p_lng double precision, p_phone text default null, p_upi text default null, p_listing boolean default false) returns uuid language plpgsql security definer as $$
declare pr uuid := pg_temp.mkuser(p_u, p_phone, p_upi); vid uuid;
begin
  insert into public.vehicles (owner_id, kind, model, plate, status) values (pr, p_kind, 'Test ' || p_kind, p_plate, 'ACTIVE') returning id into vid;
  insert into public.driver_presence (profile_id, vehicle_id, kind, online, location) values (pr, vid, p_kind, true, public.geo(p_lat, p_lng));
  if p_listing then
    insert into public.listings (kind, owner_id, title, category, area, location) values ('DRIVER', pr, initcap(p_u) || ' Auto', 'Auto', 'Jayanagar', public.geo(p_lat, p_lng));
    update public.listings set status = 'LIVE' where owner_id = pr and kind = 'DRIVER';
  end if;
  return pr;
end $$;
create or replace function pg_temp.mkshop(p_owner text, p_title text, p_lat double precision, p_lng double precision) returns uuid language plpgsql security definer as $$
declare lid uuid;
begin
  insert into public.listings (kind, owner_id, title, category, area, location, details)
    values ('BUSINESS', pg_temp.pid(p_owner), p_title, 'Grocery', 'Jayanagar', public.geo(p_lat, p_lng), '{"cod": true, "free_delivery": false}') returning id into lid;
  update public.listings set status = 'LIVE', online = true where id = lid;
  insert into public.items (listing_id, name, price, unit) values (lid, 'Rice', 62, '1 kg'), (lid, 'Dal', 140, '1 kg');
  return lid;
end $$;
create or replace function pg_temp.item(p_shop uuid, p_name text) returns uuid language sql security definer as $$ select id from public.items where listing_id = p_shop and name = p_name $$;
create or replace function pg_temp.line(p_item uuid, p_qty int) returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty)) $$;

-- move a driver (a fresh presence stamp) / age their presence (triggers off, or the server would re-stamp it) / age a task
create or replace function pg_temp.at(p_u text, p_lat double precision, p_lng double precision) returns void language plpgsql security definer as $$
begin
  update public.driver_presence set location = public.geo(p_lat, p_lng) where profile_id = pg_temp.pid(p_u);
  begin execute format('update public.driver_presence set located_at = null where profile_id = %L', pg_temp.pid(p_u)); exception when undefined_column then null; end;
end $$;
-- pretend the driver's last position change was p_secs ago: the speed check allows slack + presence_max_speed_mps x that time, so a real drive of
-- a few kilometres needs a few minutes on the clock (the script runs in milliseconds)
create or replace function pg_temp.travel(p_u text, p_secs int) returns void language plpgsql security definer as $$
begin
  begin execute format('update public.driver_presence set located_at = now() - make_interval(secs => %s) where profile_id = %L', p_secs, pg_temp.pid(p_u)); exception when undefined_column then null; end;
end $$;
create or replace function pg_temp.pos(p_u text) returns text language plpgsql security definer as $$
declare r text;
begin
  select round(extensions.st_y(location::extensions.geometry)::numeric, 4) || ' ' || round(extensions.st_x(location::extensions.geometry)::numeric, 4) into r
    from public.driver_presence where profile_id = pg_temp.pid(p_u);
  return coalesce(r, '<none>');
end $$;
-- rows a DML statement touched (as the current role); -1 when it was refused
create or replace function pg_temp.rows(sql text) returns int language plpgsql as $$
declare n int; begin execute sql; get diagnostics n = row_count; return n; exception when others then return -1; end $$;
create or replace function pg_temp.age_presence(p_u text, p_secs int) returns void language plpgsql security definer as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  update public.driver_presence set updated_at = now() - make_interval(secs => p_secs) where profile_id = pg_temp.pid(p_u);
  perform set_config('session_replication_role', 'origin', true);
end $$;
create or replace function pg_temp.age_task(p_t uuid, p_secs int) returns void language plpgsql security definer as $$
begin
  update public.tasks set status_at = now() - make_interval(secs => p_secs) where id = p_t;
  begin execute format('update public.tasks set started_at = now() - make_interval(secs => %s) where id = %L and started_at is not null', p_secs, p_t); exception when undefined_column then null; end;
end $$;
create or replace function pg_temp.reset_task(p_t uuid) returns void language plpgsql security definer as $$
begin update public.tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where id = p_t; update public.tasks set status_at = now() where id = p_t; end $$;
create or replace function pg_temp.clean() returns void language plpgsql security definer as $$
begin
  update public.tasks set status = 'CANCELLED' where status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'IN_PROGRESS', 'NO_DRIVER');
  update public.orders set status = 'REJECTED' where status = 'PLACED';
end $$;
create or replace function pg_temp.trip(p_req text, p_drv text, p_status text, p_started_ago int, p_completed_ago int) returns uuid language plpgsql security definer as $$
declare tid uuid;
begin
  insert into public.tasks (type, requester_id, driver_id, vehicle_id, vehicle_kind, pickup, drop_at, km, fare, status)
    values ('RIDE', pg_temp.pid(p_req), pg_temp.pid(p_drv), (select vehicle_id from public.driver_presence where profile_id = pg_temp.pid(p_drv)), 'AUTO',
            public.geo(12.9250, 77.5938), public.geo(12.9757, 77.6063), 7.5, 110, p_status) returning id into tid;
  begin
    execute format('update public.tasks set started_at = now() - make_interval(secs => %s), completed_at = now() - make_interval(secs => %s) where id = %L', p_started_ago, p_completed_ago, tid);
  exception when undefined_column then null; end;
  return tid;
end $$;
-- a delivered pick-up order, accepted p_gap seconds before it was handed over (0 = instantly)
create or replace function pg_temp.done_order(p_buyer text, p_shop uuid, p_gap int) returns uuid language plpgsql security definer as $$
declare oid uuid;
begin
  insert into public.orders (listing_id, buyer_id, lines, subtotal, delivery_mode, status, accept_by)
    values (p_shop, pg_temp.pid(p_buyer), pg_temp.line(pg_temp.item(p_shop, 'Rice'), 1), 62, 'PICKUP', 'DELIVERED', now()) returning id into oid;
  begin
    execute format('update public.orders set accepted_at = now() - make_interval(secs => %s), delivered_at = now() where id = %L', p_gap, oid);
  exception when undefined_column then null; end;
  return oid;
end $$;

create or replace function pg_temp.mktask(p_req text, p_type text, p_status text, p_drv text, p_order uuid default null) returns uuid language plpgsql security definer as $$
declare tid uuid;
begin
  insert into public.tasks (type, requester_id, order_id, driver_id, vehicle_id, vehicle_kind, pickup, drop_at, km, fare, status)
    values (p_type, pg_temp.pid(p_req), p_order, pg_temp.pid(p_drv), (select vehicle_id from public.driver_presence where profile_id = pg_temp.pid(p_drv)),
            case when p_type = 'DELIVERY' then 'BIKE' else 'AUTO' end, public.geo(12.9250, 77.5938), public.geo(12.9757, 77.6063), 7.5, 110, p_status) returning id into tid;
  return tid;
end $$;

-- loops used by the exploits
create or replace function pg_temp.brute(p_task uuid) returns text language plpgsql as $$
declare r public.tasks; i int;
begin
  for i in 0..9999 loop
    begin
      r := public.advance_task(p_task, 'IN_PROGRESS', lpad(i::text, 4, '0'));
      if r.status = 'IN_PROGRESS' then return 'cracked with ' || lpad(i::text, 4, '0') || ' after ' || (i + 1) || ' tries'; end if;
    exception when others then null;
    end;
  end loop;
  return 'not cracked';
end $$;
create or replace function pg_temp.churn(p_task uuid, p_n int) returns int language plpgsql as $$
declare done int := 0;
begin
  for i in 1..p_n loop
    begin
      if not public.claim_task(p_task) then exit; end if;
      perform public.advance_task(p_task, 'SEARCHING');
      done := done + 1;
    exception when others then exit;
    end;
  end loop;
  return done;
end $$;
create or replace function pg_temp.harvest() returns text language plpgsql as $$
declare t record; ph text; near int := 0; far int := 0;
begin
  for t in select id, requester_id from public.tasks where status = 'SEARCHING' and requester_id <> public.me() loop
    begin
      if public.claim_task(t.id) then
        select c.phone into ph from public.contact_for_task(t.id) c;
        if ph like '92%' then near := near + 1; elsif ph like '93%' then far := far + 1; end if;
        perform public.advance_task(t.id, 'SEARCHING');
      end if;
    exception when others then null;
    end;
  end loop;
  return 'near=' || near || ' far=' || far;
end $$;
create or replace function pg_temp.spam(p_shop uuid, p_item uuid, p_n int) returns int language plpgsql as $$
declare done int := 0; o uuid;
begin
  for i in 1..p_n loop
    begin
      o := public.place_order(p_shop, pg_temp.line(p_item, 1), 12.9300, 77.6000, 'Heidi home', 'UPI', 'MARKETPLACE');
      perform public.cancel_order(o);
      done := done + 1;
    exception when others then exit;
    end;
  end loop;
  return done;
end $$;
create or replace function pg_temp.harvest_orders(p_shops uuid[]) returns text language plpgsql as $$
declare s uuid; o uuid; c record; phones int := 0; upis int := 0;
begin
  foreach s in array p_shops loop
    begin
      o := public.place_order(s, pg_temp.line(pg_temp.item(s, 'Rice'), 1), 12.9300, 77.6000, 'Gary home', 'UPI', 'MARKETPLACE');
      for c in select * from public.contact_for_order(o) loop
        if c.phone is not null then phones := phones + 1; end if;
        if c.upi_uri is not null then upis := upis + 1; end if;
      end loop;
      perform public.cancel_order(o);
    exception when others then null;
    end;
  end loop;
  return 'phones=' || phones || ' upi=' || upis;
end $$;

-- a request at a chosen spot (drop 5.5 km north), for the sweep
create or replace function pg_temp.mkat(p_req text, p_lat double precision, p_lng double precision, p_label text) returns uuid language plpgsql security definer as $$
declare tid uuid;
begin
  insert into public.tasks (type, requester_id, vehicle_kind, pickup, pickup_label, drop_at, drop_label, km, fare)
    values ('RIDE', pg_temp.pid(p_req), 'AUTO', public.geo(p_lat, p_lng), p_label, public.geo(p_lat + 0.05, p_lng), 'D', 6, 90) returning id into tid;
  return tid;
end $$;
-- one far driver moving his own presence row to each of six spread-out pick-ups, counting the requests he could then read
create or replace function pg_temp.sweep() returns int language plpgsql as $$
declare i int; n int := 0; c int;
begin
  for i in 1..6 loop
    update public.driver_presence set location = public.geo(12.80 + i * 0.03, 77.50 + i * 0.03) where profile_id = public.me();
    select count(*) into c from public.tasks_geo where pickup_label = 'S' || i;
    n := n + c;
  end loop;
  return n;
end $$;
-- a script that walks the presence row towards a pick-up in 250 m hops (each one small, none of them a jump), returning how far it got in metres
create or replace function pg_temp.walk(p_lat double precision, p_lng double precision, p_hops int) returns text language plpgsql as $$
declare i int; la double precision; ln double precision; start_g extensions.geography; d double precision; f double precision;
begin
  select location, extensions.st_y(location::extensions.geometry), extensions.st_x(location::extensions.geometry) into start_g, la, ln from public.driver_presence where profile_id = public.me();
  for i in 1..p_hops loop
    d := extensions.st_distance(public.geo(la, ln), public.geo(p_lat, p_lng));
    exit when d < 250;
    f := 250 / d; la := la + (p_lat - la) * f; ln := ln + (p_lng - ln) * f;
    update public.driver_presence set location = public.geo(la, ln) where profile_id = public.me();
  end loop;
  return round(extensions.st_distance(start_g, (select location from public.driver_presence where profile_id = public.me())))::text;
end $$;
-- an honest driver: 5 seconds pass, the car has moved 100 m north (20 m/s), reported through update_location or written to the presence row; p_steps times
create or replace function pg_temp.drive(p_u text, p_steps int, p_direct boolean) returns text language plpgsql as $$
declare i int; la double precision; ln double precision; refused int := 0; before_g text;
begin
  select extensions.st_y(location::extensions.geometry), extensions.st_x(location::extensions.geometry) into la, ln from public.driver_presence where profile_id = public.me();
  for i in 1..p_steps loop
    perform pg_temp.travel(p_u, 5);
    la := la + 0.0009;   -- about 100 m
    before_g := pg_temp.pos(p_u);
    if p_direct then update public.driver_presence set location = public.geo(la, ln) where profile_id = public.me(); else perform public.update_location(la, ln); end if;
    if pg_temp.pos(p_u) = before_g then refused := refused + 1; end if;
  end loop;
  return refused || ' refused, now at ' || pg_temp.pos(p_u);
end $$;
-- the audit's harvest through a driver who goes quiet instead of handing back: claim, read the phone, stop reporting for 11 minutes,
-- let expire_tasks hand the trip back, come back, repeat
create or replace function pg_temp.silent_harvest(p_u text) returns text language plpgsql as $$
declare t record; ph text; got int := 0; err text := '';
begin
  for t in select id from public.tasks where status = 'SEARCHING' and requester_id <> public.me() order by created_at loop
    begin
      if public.claim_task(t.id) then
        select c.phone into ph from public.contact_for_task(t.id) c;
        if ph is not null then got := got + 1; end if;
        perform pg_temp.age_presence(p_u, 660);
        perform pg_temp.sq('select public.expire_tasks()');
        perform pg_temp.at(p_u, 12.9262, 77.5941);
      end if;
    exception when others then err := sqlerrm; exit;
    end;
  end loop;
  return got || ' phones, ' || case when err ilike '%handed back 3 trips%' then 'stopped by the hand-back cap' else 'stopped by: ' || err end;
end $$;

-- ---------- fixtures ----------
select pg_temp.mkuser('alice', '9100000001', 'upi://pay?pa=alice@okaxis&pn=Alice') as alice \gset
select pg_temp.mkuser('judy', '9100000002', 'upi://pay?pa=judy@okaxis&pn=Judy') as judy \gset
select pg_temp.mkuser('leo', '9100000003') as leo \gset
select pg_temp.mkuser('frank', '9100000004') as frank \gset
select pg_temp.mkuser('heidi', '9100000005') as heidi \gset
select pg_temp.mkuser('gary', '9100000006') as gary \gset
select pg_temp.mkuser('zed', '9100000007') as zed \gset
select pg_temp.mkuser('erin', '9100000011', 'upi://pay?pa=erin@okaxis&pn=Erin') as erin \gset
select pg_temp.mkuser('fay', '9100000012', 'upi://pay?pa=fay@okaxis&pn=Fay') as fay \gset
select count(pg_temp.mkuser(u, '92000000' || n)) as near_riders from (values ('r1', 1), ('r2', 2), ('r3', 3), ('r4', 4)) v(u, n) \gset
select count(pg_temp.mkuser(u, '93000000' || n)) as far_riders from (values ('r5', 5), ('r6', 6), ('r7', 7), ('r8', 8)) v(u, n) \gset
select pg_temp.mkdriver('bob', 'AUTO', 'KA01AB0001', 12.9262, 77.5941, '9100000021', 'upi://pay?pa=bob@okaxis&pn=Bob', true) as bob \gset
select pg_temp.mkdriver('carol', 'AUTO', 'KA01AB0002', 12.9262, 77.5941, '9100000022') as carol \gset
select pg_temp.mkdriver('ivan', 'AUTO', 'KA01AB0003', 13.2000, 77.7000, '9100000023') as ivan \gset
select pg_temp.mkdriver('nina', 'AUTO', 'KA01AB0004', 12.9262, 77.5941, '9100000024', 'upi://pay?pa=nina@okaxis&pn=Nina') as nina \gset
select pg_temp.mkdriver('hank', 'AUTO', 'KA01AB0005', 12.9262, 77.5941, '9100000025') as hank \gset
select pg_temp.mkdriver('olga', 'AUTO', 'KA01AB0006', 12.9262, 77.5941, '9100000026') as olga \gset
select pg_temp.mkdriver('pete', 'AUTO', 'KA01AB0007', 12.9262, 77.5941, '9100000027') as pete \gset
select pg_temp.mkdriver('quin', 'AUTO', 'KA01AB0008', 12.9262, 77.5941, '9100000028') as quin \gset
select pg_temp.mkdriver('mallory', 'AUTO', 'KA01AB0009', 12.9262, 77.5941, '9100000029') as mallory \gset
select pg_temp.mkdriver('dave', 'BIKE', 'KA05CD0001', 12.9262, 77.5941, '9100000031') as dave \gset
select pg_temp.mkdriver('gina', 'BIKE', 'KA05CD0002', 12.9262, 77.5941, '9100000032') as gina \gset
select pg_temp.mkshop('erin', 'Erin Stores', 12.9250, 77.5938) as erin_shop \gset
select pg_temp.mkshop('fay', 'Fay Bakery', 12.9255, 77.5940) as fay_shop \gset
select pg_temp.run(format($$insert into public.listing_members (listing_id, profile_id, role) values (%L, %L, 'STORE_RIDER'), (%L, %L, 'STORE_RIDER')$$, :'erin_shop', :'dave', :'erin_shop', :'gina')) \gset

-- =====================================================================
-- D1  PIN, arrival and completion
-- =====================================================================
select pg_temp.check((select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
                       where a.attrelid = 'public.tasks'::regclass and a.attname = 'pin') not ilike '%random%', 'D1 the PIN default no longer comes from random()');
select pg_temp.eq(pg_temp.q($$select bool_and(p ~ '^[0-9]{4}$') and count(distinct p) > 170 from (select public.new_pin() p from generate_series(1, 200)) s$$), 'true', 'D1 new_pin() gives well-spread 4-digit PINs');

set role authenticated;
select pg_temp.as_user('alice');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as t_a \gset
select pg_temp.as_user('carol');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'t_a')), 'true', 'D1 a driver at the pick-up claims a stranger''s ride');
select pg_temp.at('carol', 13.2000, 77.7000) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'ARRIVED')$$, :'t_a'), 'too far'),
                     'D1 ARRIVED from 31 km away is refused (presence must be within arrive_radius_m of the pick-up)');
select pg_temp.at('carol', 12.9262, 77.5941) \gset
select pg_temp.q(format($$select advance_task(%L, 'ARRIVED')$$, :'t_a')) \gset
select pg_temp.eq(pg_temp.sq(format($$select status from public.tasks where id = %L$$, :'t_a')), 'ARRIVED', 'D1 near the pick-up she can mark ARRIVED');
select pg_temp.run(format($$update public.tasks set pin = '7391' where id = %L$$, :'t_a')) \gset
select pg_temp.eq(pg_temp.brute(:'t_a'), 'not cracked', 'D1 looping p_pin 0000..9999 does not start the trip');
select pg_temp.eq(pg_temp.q(format($$select pin_attempts from public.tasks where id = %L$$, :'t_a')), '5', 'D1 five wrong PINs are counted and readable by the driver');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'IN_PROGRESS', '7391')$$, :'t_a'), 'too many wrong PIN'),
                     'D1 after 5 wrong PINs even the right one is refused: hand the trip back');
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'SEARCHING')$$, :'t_a')), 'SEARCHING', 'D1 she can still hand the trip back');
select pg_temp.eq(pg_temp.sq(format($$select (pin <> '7391')::text || ' ' || pin_attempts from public.tasks where id = %L$$, :'t_a')), 'true 0', 'D1 a hand-back resets the counter and rotates the PIN');
select pg_temp.run(format($$update public.tasks set status = 'CANCELLED' where id = %L$$, :'t_a')) \gset

-- wrong PIN once: no error, counter up, status unchanged (contract C1)
select pg_temp.as_user('alice');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as t_b \gset
select pg_temp.as_user('bob');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'t_b')), 'true', 'D1 bob at the pick-up claims');
select pg_temp.age_presence('bob', 400) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'ARRIVED')$$, :'t_b'), 'not up to date'), 'D1 ARRIVED with a stale presence is refused (a missing or old location blocks a check that is on)');
select pg_temp.at('bob', 12.9262, 77.5941) \gset
select pg_temp.q(format($$select advance_task(%L, 'ARRIVED')$$, :'t_b')) \gset
select pg_temp.as_user('alice'); select pin as pin_b from tasks_geo where id = :'t_b' \gset
select pg_temp.as_user('bob');
select pg_temp.eq(pg_temp.q(format($$select status || ' ' || pin_attempts || ' [' || pin || ']' from advance_task(%L, 'IN_PROGRESS', %L)$$, :'t_b', case when :'pin_b' = '0000' then '1111' else '0000' end)), 'ARRIVED 1 []',
                  'D1 one wrong PIN returns the task unchanged (ARRIVED), counts it, and never shows the PIN to the driver');
select pg_temp.as_user('alice');
select pg_temp.eq(pg_temp.q(format($$select pin_attempts from tasks_geo where id = %L$$, :'t_b')), '1', 'D1 the requester sees the counter too (tasks_geo.pin_attempts)');
select pg_temp.as_user('heidi');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'IN_PROGRESS', %L)$$, :'t_b', :'pin_b'), 'not your task'), 'D1 a stranger cannot move the task, even with the right PIN');
select pg_temp.as_user('bob');
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'IN_PROGRESS', %L)$$, :'t_b', :'pin_b')), 'IN_PROGRESS', 'D1 the right PIN still starts the trip');

-- COMPLETED: minimum time
select pg_temp.at('bob', 12.9757, 77.6063) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'COMPLETED')$$, :'t_b'), 'only just started'), 'D1 COMPLETED right after IN_PROGRESS is refused (min_trip_seconds)');
select pg_temp.age_task(:'t_b', 120) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'t_b')), 'COMPLETED', 'D1 after the minimum time, at the drop, the trip completes');

-- COMPLETED: geofence
select pg_temp.as_user('alice');
select pg_temp.run(format($$update public.tasks set status = 'PAID' where id = %L$$, :'t_b')) \gset
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as t_c \gset
select pg_temp.as_user('bob');
select pg_temp.at('bob', 12.9262, 77.5941) \gset
select pg_temp.q(format($$select claim_task(%L)$$, :'t_c')) \gset
select pg_temp.q(format($$select advance_task(%L, 'ARRIVED')$$, :'t_c')) \gset
select pg_temp.as_user('alice'); select pin as pin_c from tasks_geo where id = :'t_c' \gset
select pg_temp.as_user('bob');
select pg_temp.q(format($$select advance_task(%L, 'IN_PROGRESS', %L)$$, :'t_c', :'pin_c')) \gset
select pg_temp.age_task(:'t_c', 120) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'COMPLETED')$$, :'t_c'), 'too far from the drop'),
                     'D1 COMPLETED 5.8 km from the drop is refused (presence must be within complete_radius_m)');
select pg_temp.at('bob', 12.9757, 77.6063) \gset
select pg_temp.age_presence('bob', 400) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'COMPLETED')$$, :'t_c'), 'not up to date'), 'D1 COMPLETED with a stale location is refused');
select pg_temp.at('bob', 12.9757, 77.6063) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'t_c')), 'COMPLETED', 'D1 fresh presence at the drop completes');
select pg_temp.run(format($$update public.tasks set status = 'PAID' where id = %L$$, :'t_c')) \gset

-- 0 disables the geometric check
select pg_temp.sudo($$update public.settings set value = 0 where key = 'arrive_radius_m'$$) \gset
select pg_temp.as_user('alice');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as t_d \gset
select pg_temp.as_user('bob');
select pg_temp.at('bob', 12.9262, 77.5941) \gset
select pg_temp.q(format($$select claim_task(%L)$$, :'t_d')) \gset
select pg_temp.at('bob', 13.2000, 77.7000) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'ARRIVED')$$, :'t_d')), 'ARRIVED', 'D1 arrive_radius_m = 0 switches the arrival check off');
select pg_temp.sudo($$update public.settings set value = 800 where key = 'arrive_radius_m'$$) \gset
select pg_temp.clean() \gset
select pg_temp.at('bob', 12.9262, 77.5941) \gset

-- =====================================================================
-- D2  claiming, listing SEARCHING tasks, presence, hand-backs   (+ D3 contact)
-- =====================================================================
select pg_temp.as_user('judy');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as tj \gset
select pg_temp.as_user('ivan');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'tj')), 'false', 'D2 a driver 31 km from the pick-up cannot claim');
select pg_temp.reset_task(:'tj') \gset
select pg_temp.as_user('hank');
select pg_temp.age_presence('hank', 400) \gset
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'tj')), 'false', 'D2 a driver whose presence is stale cannot claim');
select pg_temp.reset_task(:'tj') \gset
select pg_temp.run($$update public.driver_presence set online = false where profile_id = pg_temp.pid('hank')$$) \gset
select pg_temp.check(pg_temp.blocked(format($$select claim_task(%L)$$, :'tj'), 'go online first'), 'D2 an offline driver is told to go online first');
select pg_temp.run($$update public.driver_presence set online = true, location = public.geo(12.9262, 77.5941) where profile_id = pg_temp.pid('hank')$$) \gset
select pg_temp.as_user('nina');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'tj')), 'true', 'D2 an online driver near the pick-up with a fresh presence claims');
select pg_temp.reset_task(:'tj') \gset

-- who can list SEARCHING tasks
select pg_temp.as_user('nina');  select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '1', 'D2 a claimable task is listed to the driver who could claim it');
select pg_temp.as_user('ivan');  select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 an online driver 31 km away does not see the request (requester, pick-up, fare)');
select pg_temp.eq((select count(*)::text from tasks_geo where id = :'tj'), '0', 'D2 ... nor through tasks_geo');
select pg_temp.as_user('dave');  select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 a bike rider does not see an auto request');
select pg_temp.as_user('zed');   select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 someone who is not a driver does not see it');
select pg_temp.as_user('ivan');  select pg_temp.eq((select count(*)::text from open_tasks_near(12.9250, 77.5938) where id = :'tj'), '0', 'D2 open_tasks_near ignores the position the caller passes: a far driver spoofing the pick-up gets nothing');
select pg_temp.as_user('hank');
select pg_temp.age_presence('hank', 400) \gset
select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 a driver with a stale presence does not see it');
select pg_temp.eq((select count(*)::text from open_tasks_near(12.9262, 77.5941) where id = :'tj'), '0', 'D2 ... and is not rung for it');
select pg_temp.at('hank', 12.9262, 77.5941) \gset
select pg_temp.age_task(:'tj', 300) \gset
select pg_temp.as_user('nina');
select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 a request older than ring_window_seconds is no longer listed');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'tj')), 'false', 'D2 ... and can no longer be claimed (stale tasks stay claimable for days otherwise)');
select pg_temp.reset_task(:'tj') \gset

-- a vehicle that stops being ACTIVE takes its driver offline
select pg_temp.as_user('olga');
update vehicles set plate = 'KA01ZZ0999' where owner_id = me();
select pg_temp.eq(pg_temp.sq(format($$select online::text from public.driver_presence where profile_id = %L$$, :'olga')), 'false', 'D2 editing the plate (vehicle back to PENDING) takes the driver offline');
select pg_temp.check(pg_temp.blocked(format($$select claim_task(%L)$$, :'tj'), 'go online first'), 'D2 ... so she cannot claim with an unverified vehicle');
select pg_temp.check(pg_temp.blocked($$update driver_presence set online = true where profile_id = me()$$, ''), 'D2 ... and cannot go online again until Bucks verifies it');
-- defence in depth: a row forced online behind the policies (as the database owner) still cannot claim or see requests with an unverified vehicle
select pg_temp.run(format($$update public.driver_presence set online = true where profile_id = %L$$, :'olga')) \gset
select pg_temp.check(pg_temp.blocked(format($$select claim_task(%L)$$, :'tj'), 'vehicle not verified'), 'D2 an online row with an unverified vehicle is refused by claim_task itself');
select pg_temp.eq((select count(*)::text from tasks where id = :'tj'), '0', 'D2 ... and lists no requests to it');
select pg_temp.run(format($$update public.driver_presence set online = false where profile_id = %L$$, :'olga')) \gset
select pg_temp.as_user('pete');
update vehicles set kind = 'CAB' where owner_id = me();
update driver_presence set online = false where profile_id = me();
select pg_temp.eq(pg_temp.sq(format($$select kind from public.driver_presence where profile_id = %L$$, :'pete')), 'AUTO', 'D2 presence kind is not re-derived from a vehicle that is no longer verified');
select pg_temp.reset_task(:'tj') \gset

-- hand-backs: at most 3 an hour
select pg_temp.as_user('quin');
select pg_temp.eq(pg_temp.churn(:'tj', 6)::text, '3', 'D2 a driver can hand back 3 trips an hour, the 4th raises (claim, hand back, repeat is capped)');
select pg_temp.reset_task(:'tj') \gset

-- one trip at a time, and the presence row is locked while claiming
select pg_temp.as_user('r1');
select (request_ride('AUTO', 12.9251, 77.5939, 'Near the shop', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id as tk \gset
select pg_temp.as_user('nina');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'tj')), 'true', 'D2 nina takes a trip');
select pg_temp.check(pg_temp.blocked(format($$select claim_task(%L)$$, :'tk'), 'current trip'), 'D2 a busy driver cannot claim a second request');
select pg_temp.check((select prosrc ilike '%for update%' from pg_proc where proname = 'claim_task' and pronamespace = 'public'::regnamespace),
                     'D2 claim_task locks the driver''s presence row FOR UPDATE, so two concurrent claims by one driver serialise (checked with two sessions by hand)');

-- D3: contact_for_task
select pg_temp.eq(pg_temp.q(format($$select phone from contact_for_task(%L)$$, :'tj')), '9100000002', 'D3 the driver reads the requester''s phone once matched');
select pg_temp.eq(pg_temp.q(format($$select coalesce(upi_uri, '<none>') from contact_for_task(%L)$$, :'tj')), '<none>', 'D3 the driver never gets the requester''s UPI link');
select pg_temp.as_user('judy');
select pg_temp.eq(pg_temp.q(format($$select phone || ' ' || upi_uri from contact_for_task(%L)$$, :'tj')), '9100000024 upi://pay?pa=nina@okaxis&pn=Nina', 'D3 the rider gets the driver''s phone and UPI link to pay');
select pg_temp.reset_task(:'tj') \gset
select pg_temp.eq(pg_temp.q(format($$select count(*) from contact_for_task(%L)$$, :'tj')), '0', 'D3 nothing is returned for a SEARCHING task (requester)');
select pg_temp.as_user('ivan');
select pg_temp.eq(pg_temp.q(format($$select count(*) from contact_for_task(%L)$$, :'tj')), '0', 'D3 nothing is returned for a SEARCHING task (any driver)');
select pg_temp.clean() \gset

-- the harvest loop from the audit: list SEARCHING tasks, claim, read the phone, hand back, repeat
select pg_temp.as_user('r1'); select (request_ride('AUTO', 12.9251, 77.5939, 'Near 1', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r2'); select (request_ride('AUTO', 12.9252, 77.5939, 'Near 2', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r3'); select (request_ride('AUTO', 12.9253, 77.5939, 'Near 3', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r4'); select (request_ride('AUTO', 12.9254, 77.5939, 'Near 4', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r5'); select (request_ride('AUTO', 13.2001, 77.7001, 'Far 5', 13.2400, 77.7400, 'Far drop', 7.5, 111)).id \gset
select pg_temp.as_user('r6'); select (request_ride('AUTO', 13.2002, 77.7001, 'Far 6', 13.2400, 77.7400, 'Far drop', 7.5, 111)).id \gset
select pg_temp.as_user('r7'); select (request_ride('AUTO', 13.2003, 77.7001, 'Far 7', 13.2400, 77.7400, 'Far drop', 7.5, 111)).id \gset
select pg_temp.as_user('r8'); select (request_ride('AUTO', 13.2004, 77.7001, 'Far 8', 13.2400, 77.7400, 'Far drop', 7.5, 111)).id \gset
select pg_temp.as_user('mallory');
select pg_temp.eq(pg_temp.harvest(), 'near=3 far=0', 'D2 the claim / read-phone / hand-back loop reaches only what is near (3 of the 4 near requesters, 0 of the 4 far) and stops at the hand-back limit (claim_task counts hand-backs)');
select pg_temp.clean() \gset

-- =====================================================================
-- D4  request_ride: the server decides km and fare
-- =====================================================================
select pg_temp.as_user('leo');
select (request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 1)).id as t1 \gset
select pg_temp.eq((select fare || ' ' || km from tasks_geo where id = :'t1'), '110 7.5', 'D4 a client fare of Rs 1 is recomputed: fare_base 20 + 12/km x 7.5 km = Rs 110');
select advance_task(:'t1', 'CANCELLED') \gset
select (request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 0.5, 1)).id as t2 \gset
select pg_temp.eq((select fare || ' ' || km from tasks_geo where id = :'t2'), '110 7.5', 'D4 a km below 0.8x the straight line is clamped to 1.3x straight line (7.5 km)');
select advance_task(:'t2', 'CANCELLED') \gset
select (request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 9999, 100000)).id as t3 \gset
select pg_temp.eq((select fare || ' ' || km from tasks_geo where id = :'t3'), '110 7.5', 'D4 a km above 4x the straight line is clamped too');
select advance_task(:'t3', 'CANCELLED') \gset
select (request_ride('CAB', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 1)).id as t4 \gset
select pg_temp.eq((select fare || ' ' || km from tasks_geo where id = :'t4'), '155 7.5', 'D4 a cab is 20 + 18/km: Rs 155');
select advance_task(:'t4', 'CANCELLED') \gset
select pg_temp.check(pg_temp.blocked($$select request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9250, 77.5938, 'P', 0, 20)$$, 'too short'), 'D4 pick-up = drop is refused: that trip is too short');
select pg_temp.clean() \gset
select pg_temp.check(pg_temp.blocked($$select request_ride('AUTO', 12.9250, 77.5938, 'P', 28.6139, 77.2090, 'Delhi', 2000, 20)$$, 'too far for Bucks'), 'D4 a 1,750 km trip is refused: that trip is too far for Bucks');
select pg_temp.clean() \gset
select pg_temp.check(pg_temp.blocked($$select request_ride('BIKE', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 60)$$, 'goods only'), 'D4 bikes carry goods only');
select pg_temp.check(pg_temp.blocked($$select request_ride('TRUCK', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 60)$$, ''), 'D4 only AUTO and CAB are accepted kinds');
select pg_temp.check(pg_temp.blocked($$select request_ride('AUTO', 'NaN'::float8, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 60)$$, 'not valid'), 'D4 a NaN coordinate is refused');
select pg_temp.check(pg_temp.blocked($$select request_ride('AUTO', 95, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 60)$$, 'not valid'), 'D4 a latitude outside -90..90 is refused');
select pg_temp.clean() \gset
select (request_ride('AUTO', 12.9250, 77.5938, repeat('p', 500), 12.9757, 77.6063, repeat('d', 500), 7.5, 110)).id as t5 \gset
select pg_temp.eq(pg_temp.sq(format($$select length(pickup_label) || ' ' || length(drop_label) from public.tasks where id = %L$$, :'t5')), '120 120', 'D4 labels are cut to 120 characters');
select pg_temp.check(pg_temp.blocked($$select request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 110)$$, 'already have a ride in progress'),
                     'D4 a second ride while one is open is refused (double tap, or a script)');
select pg_temp.check((select count(*) = 1 from pg_indexes where indexname = 'tasks_one_open_ride'), 'D4 the one-open-ride rule is a unique partial index');
select pg_temp.eq((select count(*)::text from public.settings where key in ('fare_base', 'fare_bike_per_km', 'fare_auto_per_km', 'fare_cab_per_km', 'arrive_radius_m', 'complete_radius_m', 'min_trip_seconds', 'claim_fresh_seconds', 'ring_window_seconds')), '9', 'D4 the fare and check settings exist with defaults');
select pg_temp.clean() \gset

-- =====================================================================
-- D5  orders
-- =====================================================================
select pg_temp.as_user('frank');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, '[]'::jsonb, 12.93, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'erin_shop'), 'cart is empty'), 'D5 an order with no lines is refused');
select pg_temp.clean() \gset
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 0)), 'between 1 and 99'), 'D5 quantity 0 is refused');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 100)), 'between 1 and 99'), 'D5 quantity 100 is refused');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, (select jsonb_agg(jsonb_build_object('item_id', %L::uuid, 'qty', 1)) from generate_series(1, 31)), 12.93, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.item(:'erin_shop', 'Rice')), 'too many items'), 'D5 31 lines are refused');
select pg_temp.clean() \gset
select pg_temp.as_user('erin');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Erin home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1)), 'own shop'), 'D5 an owner cannot order from her own shop');
select pg_temp.clean() \gset
select pg_temp.as_user('frank');
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, 'Frank home', 'UPI', 'MARKETPLACE') as o1 \gset
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, 'Frank home', 'UPI', 'MARKETPLACE') as o2 \gset
select place_order(:'fay_shop', pg_temp.line(pg_temp.item(:'fay_shop', 'Rice'), 1), 12.9300, 77.6000, 'Frank home', 'UPI', 'MARKETPLACE') as o3 \gset
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'fay_shop', pg_temp.line(pg_temp.item(:'fay_shop', 'Dal'), 1)), 'orders waiting'),
                     'D5 a fourth order while three wait for a shop to answer is refused');
select pg_temp.clean() \gset
select pg_temp.as_user('heidi');
select pg_temp.eq(pg_temp.spam(:'erin_shop', pg_temp.item(:'erin_shop', 'Rice'), 12)::text, '10', 'D5 place-and-cancel in a loop stops at 10 orders an hour');
select pg_temp.eq(pg_temp.sq(format($$select (count(*) <= 10)::text from public.notifications where kind = 'ORDER_NEW' and body like 'Heidi ordered%%' and profile_id = %L$$, :'erin')), 'true',
                  'D5 the shop is pinged at most 10 times by one buyer an hour');
-- the harvest loop: place, read the owner's phone and UPI, cancel, next shop
select pg_temp.as_user('gary');
select pg_temp.eq(pg_temp.harvest_orders(array[:'erin_shop', :'fay_shop']::uuid[]), 'phones=0 upi=0', 'D5 place / contact_for_order / cancel over the shops reveals no owner phone or UPI');
select pg_temp.as_user('frank');
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, repeat('x', 400), 'UPI', 'PICKUP') as o4 \gset
select pg_temp.eq(pg_temp.sq(format($$select length(drop_label) from public.orders where id = %L$$, :'o4')), '120', 'D5 the drop label is cut to 120 characters');
select pg_temp.eq((select count(*)::text from contact_for_order(:'o4')), '0', 'D5 the buyer gets no owner contact while the order is only PLACED');
select pg_temp.as_user('erin');
select pg_temp.eq((select phone from contact_for_order(:'o4')), '9100000004', 'D5 the shop sees the buyer''s phone from PLACED');
select respond_order(:'o4', true) \gset
select pg_temp.as_user('frank');
select pg_temp.eq((select phone || ' ' || upi_uri from contact_for_order(:'o4')), '9100000011 upi://pay?pa=erin@okaxis&pn=Erin', 'D5 once ACCEPTED the buyer gets the owner''s phone and UPI');
select pg_temp.as_user('erin');
select update_order_status(:'o4', 'CANCELLED') \gset
select pg_temp.as_user('frank');
select pg_temp.eq((select count(*)::text from contact_for_order(:'o4')), '1', 'D5 after the shop cancels an accepted order the buyer can still call about the refund');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 'NaN'::float8, 77.60, 'Frank home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1)), 'not valid'), 'D5 a delivery to a NaN location is refused');
select pg_temp.clean() \gset

-- =====================================================================
-- D6  reviews
-- =====================================================================
select pg_temp.mkuser('tina', '9100000041') as tina \gset
select pg_temp.mkuser('uma', '9100000042') as uma \gset
select pg_temp.mkuser('vic', '9100000043') as vic \gset
select pg_temp.mkuser('karl', '9100000044') as karl \gset
select pg_temp.mkuser('wes', '9100000045') as wes \gset
select pg_temp.sq($$select id::text from public.listings where kind = 'DRIVER' and owner_id = pg_temp.pid('bob')$$) as bob_listing \gset
select pg_temp.trip('tina', 'bob', 'PAID', 0, 0) as v1 \gset
select pg_temp.trip('uma', 'bob', 'COMPLETED', 600, 300) as v2 \gset
select pg_temp.trip('vic', 'bob', 'PAID', 600, 300) as v3 \gset
select pg_temp.as_user('tina');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, %L, null, 1, 'phantom trip')$$, :'bob_listing', :'v1'), 'too short'), 'D6 a trip that ran 0 seconds cannot be reviewed (two accounts farming trust)');
select pg_temp.as_user('uma');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, %L, null, 1, 'not paid')$$, :'bob_listing', :'v2'), 'paid'), 'D6 a completed but unpaid trip cannot be reviewed yet');
select pg_temp.as_user('vic');
select pg_temp.eq(pg_temp.ok(format($$select review(%L, %L, null, 1, 'Safe driving')$$, :'bob_listing', :'v3')), 'done', 'D6 a paid trip that took 5 minutes can be reviewed');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, %L, null, 1, 'again')$$, :'bob_listing', :'v3'), 'already reviewed'), 'D6 ... once');
select pg_temp.trip('karl', 'bob', 'PAID', 600, 300) as k1 \gset
select pg_temp.trip('karl', 'bob', 'PAID', 600, 300) as k2 \gset
select pg_temp.trip('karl', 'bob', 'PAID', 600, 300) as k3 \gset
select pg_temp.trip('karl', 'bob', 'PAID', 600, 300) as k4 \gset
select pg_temp.as_user('karl');
select pg_temp.eq(pg_temp.ok(format($$select review(%L, %L, null, 1, 'one')$$, :'bob_listing', :'k1')) || pg_temp.ok(format($$select review(%L, %L, null, 1, 'two')$$, :'bob_listing', :'k2')) || pg_temp.ok(format($$select review(%L, %L, null, 1, 'three')$$, :'bob_listing', :'k3')), 'donedonedone', 'D6 three reviews in a day go through');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, %L, null, 1, 'four')$$, :'bob_listing', :'k4'), 'reviews a day'), 'D6 the fourth review in 24 hours is refused');
select pg_temp.done_order('wes', :'erin_shop', 0) as w1 \gset
select pg_temp.done_order('wes', :'erin_shop', 900) as w2 \gset
select pg_temp.as_user('wes');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, null, %L, 1, 'instant')$$, :'erin_shop', :'w1'), 'too quick'), 'D6 an order accepted and delivered in the same instant cannot be reviewed');
select pg_temp.eq(pg_temp.ok(format($$select review(%L, null, %L, 1, 'Fresh rice')$$, :'erin_shop', :'w2')), 'done', 'D6 an order that took 15 minutes can be reviewed');
select pg_temp.done_order('erin', :'erin_shop', 900) as w3 \gset
select pg_temp.as_user('erin');
select pg_temp.check(pg_temp.blocked(format($$select review(%L, null, %L, 1, 'my own shop')$$, :'erin_shop', :'w3'), 'your own listing'), 'D6 an owner still cannot review her own shop');

-- =====================================================================
-- D7  lifecycle: expire_tasks and cancelling a trip whose driver vanished
-- =====================================================================
select pg_temp.mkuser('ted', '9100000051') as ted \gset
select pg_temp.mkuser('uwe', '9100000052') as uwe \gset
select pg_temp.mkuser('val', '9100000053') as val \gset
select pg_temp.mkuser('wim', '9100000054') as wim \gset
select pg_temp.mkuser('xan', '9100000055') as xan \gset
select pg_temp.mkuser('yul', '9100000056') as yul \gset
select pg_temp.mkuser('ursula', '9100000057') as ursula \gset
select pg_temp.mkdriver('sam', 'AUTO', 'KA01AB0021', 12.9262, 77.5941) as sam \gset
select pg_temp.mkdriver('sue', 'AUTO', 'KA01AB0022', 12.9262, 77.5941) as sue \gset
select pg_temp.mkdriver('sid', 'AUTO', 'KA01AB0023', 12.9262, 77.5941) as sid \gset
select pg_temp.mkdriver('sky', 'BIKE', 'KA05CD0024', 12.9262, 77.5941) as sky \gset
select pg_temp.clean() \gset
select pg_temp.run(format($$insert into public.orders (listing_id, buyer_id, lines, subtotal, delivery_mode, status, accept_by) values (%L, %L, %L, 62, 'MARKETPLACE', 'ACCEPTED', now()) returning id$$, :'erin_shop', :'ursula', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1))) \gset
select pg_temp.sq(format($$select id::text from public.orders where buyer_id = %L$$, :'ursula')) as ord_d \gset
select pg_temp.mktask('ted', 'RIDE', 'SEARCHING', null) as e_old \gset
select pg_temp.mktask('uwe', 'RIDE', 'SEARCHING', null) as e_new \gset
select pg_temp.mktask('ursula', 'DELIVERY', 'SEARCHING', null, :'ord_d') as e_del \gset
select pg_temp.mktask('val', 'RIDE', 'MATCHED', 'sam') as e_ms \gset
select pg_temp.mktask('wim', 'RIDE', 'MATCHED', 'sue') as e_mf \gset
select pg_temp.mktask('xan', 'RIDE', 'ARRIVED', 'sid') as e_as \gset
select pg_temp.run(format($$update public.tasks set status_at = now() - interval '400 seconds' where id in (%L, %L)$$, :'e_old', :'e_del')) \gset
select pg_temp.run(format($$update public.tasks set pin = '4242' where id = %L$$, :'e_ms')) \gset
select pg_temp.age_presence('sam', 700) \gset
select pg_temp.age_presence('sid', 700) \gset
select pg_temp.check(pg_temp.blocked($$select public.expire_tasks()$$, 'permission denied'), 'D7 expire_tasks is not callable from the API');
select pg_temp.eq(pg_temp.sq($$select public.expire_tasks()$$), '4', 'D7 expire_tasks moves 2 stale requests to NO_DRIVER and hands back 2 trips whose driver has been silent for 10 minutes');
select pg_temp.eq(pg_temp.sq(format($$select (select status from public.tasks where id = %L) || ',' || (select status from public.tasks where id = %L) || ',' || (select status from public.tasks where id = %L)$$, :'e_old', :'e_new', :'e_del')),
                  'NO_DRIVER,SEARCHING,NO_DRIVER', 'D7 old SEARCHING rides and deliveries become NO_DRIVER, a fresh one stays');
select pg_temp.eq(pg_temp.sq(format($$select status || ' ' || coalesce(driver_id::text, 'none') || ' ' || (pin <> '4242')::text from public.tasks where id = %L$$, :'e_ms')), 'SEARCHING none true', 'D7 a MATCHED trip with a silent driver goes back to SEARCHING, driver cleared, PIN rotated');
select pg_temp.eq(pg_temp.sq(format($$select status from public.tasks where id = %L$$, :'e_as')), 'SEARCHING', 'D7 an ARRIVED trip with a silent driver goes back to SEARCHING');
select pg_temp.eq(pg_temp.sq(format($$select (status = 'MATCHED' and driver_id = %L)::text from public.tasks where id = %L$$, :'sue', :'e_mf')), 'true', 'D7 a MATCHED trip whose driver is alive is left alone');
select pg_temp.eq(pg_temp.sq(format($$select count(*)::text from public.task_events where task_id = %L and event = 'CANCELLED'$$, :'e_ms')), '1', 'D7 the vanished driver gets a CANCELLED event (on the owner''s dashboard, and counted by the 3 an hour that claim_task allows)');

-- cancelling an IN_PROGRESS trip
select pg_temp.run(format($$update public.tasks set status = 'CANCELLED' where id in (%L, %L, %L, %L, %L)$$, :'e_old', :'e_new', :'e_ms', :'e_as', :'e_mf')) \gset
select pg_temp.mktask('ted', 'RIDE', 'IN_PROGRESS', 'sue') as e_ip \gset
select pg_temp.as_user('ted');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'CANCELLED')$$, :'e_ip'), 'cannot go from IN_PROGRESS'), 'D7 the rider cannot cancel a trip under way while the driver''s phone is reporting');
select pg_temp.age_presence('sue', 700) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'CANCELLED')$$, :'e_ip')), 'CANCELLED', 'D7 ... but can once the driver has been silent for over 10 minutes');
select pg_temp.run(format($$update public.tasks set status = 'CANCELLED' where id = %L$$, :'e_del')) \gset
select pg_temp.run(format($$update public.orders set status = 'PICKED_UP' where id = %L$$, :'ord_d')) \gset
select pg_temp.mktask('ursula', 'DELIVERY', 'IN_PROGRESS', 'sky', :'ord_d') as e_dip \gset
select pg_temp.as_user('ursula');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'CANCELLED')$$, :'e_dip'), 'cannot go from IN_PROGRESS'), 'D7 a delivery under way with a live rider cannot be cancelled by the buyer');
select pg_temp.age_presence('sky', 700) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'CANCELLED')$$, :'e_dip')), 'CANCELLED', 'D7 with a silent rider the buyer can cancel');
select pg_temp.eq(pg_temp.sq(format($$select status || ' ' || cancelled_by from public.orders where id = %L$$, :'ord_d')), 'CANCELLED BUYER', 'D7 ... which closes the order that would otherwise stay PICKED_UP for ever');
select pg_temp.clean() \gset

-- =====================================================================
-- D8  presence and location
-- =====================================================================
select pg_temp.mkdriver('walt', 'AUTO', 'KA01AB0031', 12.9262, 77.5941) as walt \gset
select pg_temp.as_user('zed');
select pg_temp.check(pg_temp.blocked($$select update_location(12.93, 77.60)$$, 'go online first'), 'D8 update_location from someone who is not online is refused');
select pg_temp.as_user('walt');
select pg_temp.check(pg_temp.blocked($$select update_location(91, 77.60)$$, 'not valid'), 'D8 latitude 91 is refused');
select pg_temp.check(pg_temp.blocked($$select update_location(12.93, 181)$$, 'not valid'), 'D8 longitude 181 is refused');
select pg_temp.check(pg_temp.blocked($$select update_location('NaN'::float8, 77.60)$$, 'not valid'), 'D8 NaN is refused');
select pg_temp.check(pg_temp.blocked($$select update_location(12.93, 'Infinity'::float8)$$, 'not valid'), 'D8 Infinity is refused');
select update_location(12.9270, 77.5945) \gset
select update_location(12.9280, 77.5950) \gset
select pg_temp.eq(pg_temp.sq(format($$select round(extensions.st_y(location::extensions.geometry)::numeric, 4) from public.driver_presence where profile_id = %L$$, :'walt')), '12.9270', 'D8 a second update within 2 seconds is ignored');
select pg_temp.sudo(format($$update public.driver_presence set located_at = now() - interval '10 seconds' where profile_id = %L$$, :'walt')) \gset
select update_location(12.9280, 77.5950) \gset
select pg_temp.eq(pg_temp.sq(format($$select round(extensions.st_y(location::extensions.geometry)::numeric, 4) from public.driver_presence where profile_id = %L$$, :'walt')), '12.9280', 'D8 later updates apply');
-- a trip keeps its live position even when the driver is forced offline mid-trip
select pg_temp.mkuser('xia', '9100000061') as xia \gset
select pg_temp.mkdriver('wren', 'AUTO', 'KA01AB0032', 12.9262, 77.5941) as wren \gset
select pg_temp.as_user('xia'); select (request_ride('AUTO', 12.9250, 77.5938, 'P', 12.9757, 77.6063, 'D', 7.5, 110)).id as t_x \gset
select pg_temp.as_user('wren'); select claim_task(:'t_x') \gset
select pg_temp.run(format($$update public.driver_presence set online = false where profile_id = %L$$, :'wren')) \gset
select update_location(12.9270, 77.5945) \gset
select pg_temp.eq(pg_temp.sq(format($$select round(extensions.st_y(driver_location::extensions.geometry)::numeric, 4) from public.tasks where id = %L$$, :'t_x')), '12.9270', 'D8 a driver forced offline mid-trip still moves on the rider''s map');
select pg_temp.clean() \gset
-- the map: 30 rows, fresh presence only, the same columns
select pg_temp.mkdriver('stale1', 'AUTO', 'KA01AB0041', 13.0500, 77.6200) as stale1 \gset
select pg_temp.mkdriver('fresh1', 'AUTO', 'KA01AB0042', 13.0500, 77.6200) as fresh1 \gset
select pg_temp.age_presence('stale1', 240) \gset
select pg_temp.run($$select pg_temp.mkdriver('f' || lpad(g::text, 2, '0'), 'AUTO', 'KA01FF' || lpad(g::text, 4, '0'), 12.9500 + g * 0.0002, 77.6000) from generate_series(1, 40) g$$) \gset
select pg_temp.as_user('alice');
select pg_temp.eq((select count(*)::text from online_drivers_near(12.9500, 77.6000)), '30', 'D8 the map lists at most 30 drivers');
select pg_temp.eq((select string_agg(name, ',' order by name) from online_drivers_near(13.0500, 77.6200)), 'Fresh1', 'D8 a driver whose presence is older than claim_fresh_seconds is off the map');
select pg_temp.eq((select count(*)::text from online_drivers_near(12.9250, 77.5938, 2147483647) where name = 'Ivan'), '0', 'D8 a huge radius is capped at 10 km (Ivan is 31 km away)');
select pg_temp.eq(pg_get_function_result('public.online_drivers_near(double precision,double precision,integer)'::regprocedure),
                  'TABLE(profile_id uuid, kind text, lat double precision, lng double precision, name text, model text, plate text, up integer, down integer)', 'D8 the map function keeps every column the app reads');

-- =====================================================================
-- D9  input hygiene, and what a store rider may read
-- =====================================================================
select pg_temp.mkuser('vera', '9100000071') as vera \gset
select pg_temp.trip('vera', 'bob', 'COMPLETED', 600, 300) as p1 \gset
select pg_temp.trip('vera', 'bob', 'COMPLETED', 600, 300) as p2 \gset
select pg_temp.trip('vera', 'bob', 'COMPLETED', 600, 300) as p3 \gset
select pg_temp.trip('vera', 'bob', 'COMPLETED', 600, 300) as p4 \gset
select pg_temp.trip('vera', 'bob', 'COMPLETED', 600, 300) as p5 \gset
select pg_temp.as_user('vera');
select pg_temp.eq(pg_temp.q(format($$select paid_with from advance_task(%L, 'PAID', null, 'Google Pay')$$, :'p1')), 'UPI', 'D9 "Google Pay" is stored as UPI');
select pg_temp.eq(pg_temp.q(format($$select paid_with from advance_task(%L, 'PAID', null, 'Cash on delivery')$$, :'p2')), 'CASH', 'D9 anything containing cash is CASH');
select pg_temp.eq(pg_temp.q(format($$select paid_with from advance_task(%L, 'PAID', null, %L)$$, :'p3', repeat('<script>', 700))), 'UPI', 'D9 a 5,600-character payment note is stored as UPI');
select pg_temp.eq(pg_temp.q(format($$select paid_with from advance_task(%L, 'PAID', null, null)$$, :'p4')), '<null>', 'D9 no payment method stays empty');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'PAID', null, 'Cash')$$, :'p4'), 'cannot go'), 'D9 a trip is paid once');
select pg_temp.eq((select string_agg(conname || ':' || convalidated::text, ',' order by conname) from pg_constraint where conname in ('tasks_labels_ok', 'tasks_paid_with_ok', 'orders_label_ok')),
                  'orders_label_ok:false,tasks_labels_ok:false,tasks_paid_with_ok:false', 'D9 the new CHECK constraints exist and are NOT VALID (old rows survive)');
-- only the requester sets the payment method
select pg_temp.mktask('vera', 'RIDE', 'IN_PROGRESS', 'bob') as p6 \gset
select pg_temp.age_task(:'p6', 300) \gset
select pg_temp.at('bob', 12.9757, 77.6063) \gset
select pg_temp.as_user('bob');
select pg_temp.eq(pg_temp.q(format($$select coalesce(paid_with, '<null>') from advance_task(%L, 'COMPLETED', null, 'hax')$$, :'p6')), '<null>', 'D9 a driver cannot write the payment method');
select pg_temp.at('bob', 12.9262, 77.5941) \gset

-- store riders read only the orders they carry
select pg_temp.as_user('frank');
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, 'Frank home', 'COD', 'STORE_RIDER') as so1 \gset
select pg_temp.as_user('gary');
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Dal'), 1), 12.9310, 77.6010, 'Gary home', 'COD', 'STORE_RIDER') as so2 \gset
select pg_temp.as_user('erin');
select respond_order(:'so1', true) \gset
select respond_order(:'so2', true) \gset
select pg_temp.eq((select count(*)::text from orders where listing_id = :'erin_shop'), pg_temp.sq(format($$select count(*)::text from public.orders where listing_id = %L$$, :'erin_shop')), 'D9 the owner reads every order of the shop');
select pg_temp.run(format($$insert into public.listing_members (listing_id, profile_id, role) values (%L, %L, 'ADMIN')$$, :'erin_shop', :'fay')) \gset
select pg_temp.as_user('fay');
select pg_temp.eq((select count(*)::text from orders where listing_id = :'erin_shop'), pg_temp.sq(format($$select count(*)::text from public.orders where listing_id = %L$$, :'erin_shop')), 'D9 an admin reads every order of the shop');
select pg_temp.as_user('dave');
select pg_temp.eq(pg_temp.q(format($$select claim_task((select id from public.tasks where order_id = %L))$$, :'so1')), 'true', 'D9 the store rider claims one delivery');
select pg_temp.eq((select string_agg(id::text, ',') from orders where listing_id = :'erin_shop'), :'so1', 'D9 a store rider reads only the order he carries (not the shop''s other orders, buyers or addresses)');
select pg_temp.as_user('gina');
select pg_temp.eq((select count(*)::text from orders where listing_id = :'erin_shop'), '0', 'D9 a store rider with no delivery reads no orders');
select pg_temp.as_user('frank');
select pg_temp.eq((select count(*)::text from orders where buyer_id = :'frank'), pg_temp.sq(format($$select count(*)::text from public.orders where buyer_id = %L$$, :'frank')), 'D9 buyers still read their own orders');
select pg_temp.clean() \gset

-- =====================================================================
-- D10  the normal ride and the normal delivery still work end to end
-- =====================================================================
select pg_temp.mkuser('pam', '9100000081', 'upi://pay?pa=pam@okaxis&pn=Pam') as pam \gset
select pg_temp.mkdriver('dan', 'AUTO', 'KA01AB0051', 12.9262, 77.5941, '9100000082', 'upi://pay?pa=dan@okaxis&pn=Dan', true) as dan \gset
select pg_temp.as_user('pam');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 110)).id as ride \gset
select pg_temp.eq((select fare || ' ' || km || ' ' || status from tasks_geo where id = :'ride'), '110 7.5 SEARCHING', 'D10 ride: Rs 110 for 7.5 km, searching');
select pg_temp.as_user('dan');
select pg_temp.eq((select count(*)::text from open_tasks_near(12.9262, 77.5941) where id = :'ride'), '1', 'D10 ride: the driver 130 m away is rung');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'ride')), 'true', 'D10 ride: claimed');
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'ARRIVED')$$, :'ride')), 'ARRIVED', 'D10 ride: arrived at the pick-up');
select pg_temp.as_user('pam'); select pin as ride_pin from tasks_geo where id = :'ride' \gset
select pg_temp.eq(pg_temp.q(format($$select phone || ' ' || upi_uri from contact_for_task(%L)$$, :'ride')), '9100000082 upi://pay?pa=dan@okaxis&pn=Dan', 'D10 ride: the rider has the driver''s phone and UPI link');
select pg_temp.as_user('dan');
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'IN_PROGRESS', %L)$$, :'ride', :'ride_pin')), 'IN_PROGRESS', 'D10 ride: PIN entered, trip started');
select pg_temp.travel('dan', 900) \gset
select update_location(12.9755, 77.6060) \gset
select pg_temp.age_task(:'ride', 180) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'ride')), 'COMPLETED', 'D10 ride: completed at the drop');
select pg_temp.as_user('pam');
select pg_temp.eq(pg_temp.q(format($$select status || ' ' || paid_with from advance_task(%L, 'PAID', null, 'Google Pay')$$, :'ride')), 'PAID UPI', 'D10 ride: paid');
select pg_temp.sudo(format($$update public.tasks set started_at = now() - interval '9 minutes', completed_at = now() - interval '2 minutes' where id = %L$$, :'ride')) \gset
select pg_temp.eq(pg_temp.ok(format($$select review(%L, %L, null, 1, 'Smooth ride')$$, (select listing_id from task_driver(:'ride')), :'ride')), 'done', 'D10 ride: reviewed');
select pg_temp.eq(pg_temp.sq($$select trust_up::text from public.listings where title = 'Dan Auto'$$), '1', 'D10 ride: the driver''s trust went up');
select pg_temp.eq(pg_temp.sq(format($$select count(*)::text from public.task_events where task_id = %L and event in ('ACCEPTED', 'COMPLETED')$$, :'ride')), '2', 'D10 ride: accepted and completed are on the owner''s dashboard');

select pg_temp.mkuser('cy', '9100000091', 'upi://pay?pa=cy@okaxis&pn=Cy') as cy \gset
select pg_temp.mkuser('bea', '9100000092') as bea \gset
select pg_temp.mkdriver('ray', 'BIKE', 'KA05CD0053', 12.9262, 77.5941, '9100000093') as ray \gset
select pg_temp.mkshop('cy', 'Cy Mart', 12.9250, 77.5938) as cy_shop \gset
select pg_temp.as_user('bea');
select place_order(:'cy_shop', pg_temp.line(pg_temp.item(:'cy_shop', 'Rice'), 2), 12.9300, 77.6000, 'Bea home', 'UPI', 'MARKETPLACE') as dord \gset
select pg_temp.eq((select subtotal || ' ' || delivery_fee || ' ' || status from orders where id = :'dord'), '124 29 PLACED', 'D10 delivery: 2 x Rs 62 plus a Rs 29 fee (20 + 8/km x 1.1 km)');
select pg_temp.as_user('cy'); select respond_order(:'dord', true) \gset
select pg_temp.as_user('ray');
select pg_temp.eq(pg_temp.q(format($$select claim_task((select id from public.tasks where order_id = %L))$$, :'dord')), 'true', 'D10 delivery: the bike rider near the shop claims');
select id as dtask from tasks_geo where order_id = :'dord' \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'ARRIVED')$$, :'dtask')), 'ARRIVED', 'D10 delivery: at the shop');
select pg_temp.eq((select count(*)::text from orders where id = :'dord'), '0', 'D10 delivery: a Bucks rider carrying a marketplace delivery still reads no order (buyer, address)');
select pg_temp.as_user('bea'); select pin as dpin from tasks_geo where id = :'dtask' \gset
select pg_temp.as_user('ray');
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'IN_PROGRESS', %L)$$, :'dtask', :'dpin')), 'IN_PROGRESS', 'D10 delivery: PIN entered, order picked up');
select pg_temp.eq(pg_temp.sq(format($$select status from public.orders where id = %L$$, :'dord')), 'PICKED_UP', 'D10 delivery: the order is PICKED_UP');
select pg_temp.travel('ray', 300) \gset
select update_location(12.9299, 77.5999) \gset
select pg_temp.age_task(:'dtask', 180) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'dtask')), 'COMPLETED', 'D10 delivery: completed near the buyer''s door');
select pg_temp.eq(pg_temp.sq(format($$select status from public.orders where id = %L$$, :'dord')), 'DELIVERED', 'D10 delivery: the order is DELIVERED');
select pg_temp.sudo(format($$update public.orders set accepted_at = now() - interval '20 minutes', delivered_at = now() - interval '2 minutes' where id = %L$$, :'dord')) \gset
select pg_temp.as_user('bea');
select pg_temp.eq(pg_temp.ok(format($$select review(%L, null, %L, 1, 'Quick and fresh')$$, :'cy_shop', :'dord')), 'done', 'D10 delivery: the buyer reviews the shop');

-- =====================================================================
-- RT  the review of this migration: each finding starts as the exploit (on the version before the review these lines print FAIL)
-- =====================================================================
select pg_temp.clean() \gset
select pg_temp.mkuser('rita', '9100000101') as rita \gset
select pg_temp.mkdriver('faraday', 'AUTO', 'KA01AB0061', 13.2000, 77.7000, '9100000102') as faraday \gset

-- RT-02  every check measures from driver_presence.location, so that position may only move the way a vehicle can
select pg_temp.as_user('rita');
select (request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.5, 110)).id as t_rt \gset
select pg_temp.as_user('faraday');
select pg_temp.travel('faraday', 5) \gset
select update_location(12.9250, 77.5938) \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 update_location to the pick-up from 31 km away in a few seconds is ignored');
select pg_temp.eq((select count(*)::text from tasks where id = :'t_rt'), '0', 'RT-02 ... so the request (requester, labels, fare) is not listed to him');
select pg_temp.eq((select count(*)::text from tasks_geo where id = :'t_rt'), '0', 'RT-02 ... nor through tasks_geo');
select pg_temp.eq(pg_temp.q(format($$select claim_task(%L)$$, :'t_rt')), 'false', 'RT-02 ... and he cannot claim it');
select pg_temp.eq(pg_temp.q(format($$select count(*) from contact_for_task(%L)$$, :'t_rt')), '0', 'RT-02 ... or read the requester''s phone');
select pg_temp.rows($$update driver_presence set location = geo(12.9250, 77.5938) where profile_id = me()$$) as n1 \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 the same jump written straight to the presence row (what the app''s own upsert does) is dropped');
select pg_temp.rows($$update driver_presence set location = geo(12.9250, 77.5938), located_at = now() - interval '10 years' where profile_id = me()$$) as n2 \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... also with a located_at forged into the past to buy time');
select pg_temp.rows($$update driver_presence set location = geo(12.9250, 77.5938), move_credit_m = 1e12 where profile_id = me()$$) as n2b \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... or with a movement allowance forged to a huge number');
select pg_temp.rows($$update driver_presence set location = null where profile_id = me()$$) as n3 \gset
select pg_temp.rows($$update driver_presence set location = geo(12.9250, 77.5938) where profile_id = me()$$) as n4 \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... and clearing the position first does not make the next one a "first fix"');
select pg_temp.rows($$insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), vehicle_id, 'AUTO', true, geo(12.9250, 77.5938) from driver_presence where profile_id = me()
                      on conflict (profile_id) do update set location = excluded.location, online = excluded.online$$) as n5 \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... and so is the same jump through an insert ... on conflict do update');
select pg_temp.rows($$insert into driver_presence (profile_id, vehicle_id, kind, online, location, located_at, move_credit_m) select me(), vehicle_id, 'AUTO', true, geo(12.9250, 77.5938), now() - interval '10 years', 1e12 from driver_presence where profile_id = me()
                      on conflict (profile_id) do update set location = excluded.location, located_at = excluded.located_at, move_credit_m = excluded.move_credit_m$$) as n5b \gset
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... with the clock and the allowance forged inside the upsert as well');
select pg_temp.eq(pg_temp.rows($$delete from driver_presence where profile_id = me()$$)::text, '0', 'RT-02 he cannot delete his presence row to insert a fresh one somewhere else (the app never deletes it)');
select pg_temp.eq(pg_temp.pos('faraday'), '13.2000 77.7000', 'RT-02 ... the row is still there');
select count(pg_temp.mkat('r' || i, 12.80 + i * 0.03, 77.50 + i * 0.03, 'S' || i)) as n_sweep from generate_series(1, 6) i \gset
select pg_temp.eq(pg_temp.sweep()::text, '0', 'RT-02 moving presence to six spread-out pick-ups reads none of the requests (it enumerated all six before)');
select pg_temp.check(pg_temp.walk(12.9250, 77.5938, 200)::int < 1000, 'RT-02 walking the presence row towards the pick-up in 250 m hops does not add up to a jump (130 hops reached it before)');
select pg_temp.eq((select count(*)::text from tasks where id = :'t_rt'), '0', 'RT-02 ... and the request is still not listed to him');

-- ... and honest movement is not in the way
select pg_temp.mkdriver('drover', 'AUTO', 'KA01AB0066', 12.9262, 77.5941, '9100000109') as drover \gset
select pg_temp.as_user('drover');
select pg_temp.eq(pg_temp.drive('drover', 120, false), '0 refused, now at 13.0342 77.5941', 'RT-02 ten minutes of honest driving (20 m/s, a report every 5 seconds, 12 km) through update_location is never refused');
select pg_temp.eq(pg_temp.drive('drover', 60, true), '0 refused, now at 13.0882 77.5941', 'RT-02 ... nor five minutes written straight to the presence row (what the app''s heartbeat does)');
select pg_temp.mkdriver('ravi', 'AUTO', 'KA01AB0064', 12.9262, 77.5941, '9100000107') as ravi \gset
select pg_temp.as_user('ravi');
select pg_temp.travel('ravi', 60) \gset
select update_location(12.9300, 77.5980) \gset
select pg_temp.eq(pg_temp.pos('ravi'), '12.9300 77.5980', 'RT-02 a real 600 m drive reported through update_location is taken');
select pg_temp.travel('ravi', 5) \gset
select pg_temp.rows($$update driver_presence set location = geo(12.9305, 77.5985) where profile_id = me()$$) as n6 \gset
select pg_temp.eq(pg_temp.pos('ravi'), '12.9305 77.5985', 'RT-02 a short move written to the presence row is taken');
select pg_temp.rows($$insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), vehicle_id, 'AUTO', true, geo(12.9305, 77.5985) from driver_presence where profile_id = me()
                      on conflict (profile_id) do update set vehicle_id = excluded.vehicle_id, kind = excluded.kind, online = excluded.online, location = excluded.location$$) as n7 \gset
select pg_temp.eq(pg_temp.pos('ravi') || ' ' || pg_temp.sq(format($$select online::text from public.driver_presence where profile_id = %L$$, :'ravi')), '12.9305 77.5985 true', 'RT-02 the 60-second heartbeat upsert at the same spot keeps working');
select pg_temp.travel('ravi', 5) \gset
select update_location(13.2000, 77.7000) \gset
select pg_temp.eq(pg_temp.pos('ravi'), '12.9305 77.5985', 'RT-02 31 km in 5 seconds is refused for him as well');
select pg_temp.travel('ravi', 1200) \gset
select update_location(13.2000, 77.7000) \gset
select pg_temp.eq(pg_temp.pos('ravi'), '13.2000 77.7000', 'RT-02 after 20 minutes the same 31 km is fine: it is a speed limit (40 m/s), not a fence');
select pg_temp.sudo($$update public.settings set value = 0 where key = 'presence_max_speed_mps'$$) \gset
select pg_temp.travel('ravi', 5) \gset
select pg_temp.rows($$update driver_presence set location = geo(12.9250, 77.5938) where profile_id = me()$$) as n8 \gset
select pg_temp.eq(pg_temp.pos('ravi'), '12.9250 77.5938', 'RT-02 presence_max_speed_mps = 0 switches the speed check off (device tests with mock locations)');
select pg_temp.sudo($$update public.settings set value = 40 where key = 'presence_max_speed_mps'$$) \gset
select pg_temp.mkuser('fiona', '9100000108') as fiona \gset
select pg_temp.run(format($$insert into public.vehicles (owner_id, kind, model, plate, status) values (%L, 'AUTO', 'Test AUTO', 'KA01AB0065', 'ACTIVE')$$, :'fiona')) \gset
select pg_temp.as_user('fiona');
select pg_temp.rows($$insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'AUTO', true, geo(13.5000, 77.9000) from vehicles where owner_id = me()$$) as n9 \gset
select pg_temp.eq(pg_temp.pos('fiona'), '13.5000 77.9000', 'RT-02 a first position has nothing to be compared with and is taken as sent');

-- RT-03  the claim cap counts hand-backs however they happen, so going quiet does not reset it
select pg_temp.clean() \gset
select pg_temp.as_user('r1'); select (request_ride('AUTO', 12.9251, 77.5939, 'Cycle 1', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r2'); select (request_ride('AUTO', 12.9252, 77.5939, 'Cycle 2', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r3'); select (request_ride('AUTO', 12.9253, 77.5939, 'Cycle 3', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.as_user('r4'); select (request_ride('AUTO', 12.9254, 77.5939, 'Cycle 4', 12.9757, 77.6063, 'MG Road', 7.5, 111)).id \gset
select pg_temp.mkdriver('cyc', 'AUTO', 'KA01AB0062', 12.9262, 77.5941, '9100000103') as cyc \gset
select pg_temp.as_user('cyc');
select pg_temp.eq(pg_temp.silent_harvest('cyc'), '3 phones, stopped by the hand-back cap', 'RT-03 claim / read the phone / go quiet / be handed back / repeat gives 3 phones an hour (it gave every requester before)');
select pg_temp.eq(pg_temp.sq(format($$select count(*)::text from public.task_events where driver_id = %L and event = 'CANCELLED'$$, :'cyc')), '3', 'RT-03 each automatic hand-back is a CANCELLED event, like the driver''s own');
select pg_temp.check(pg_temp.blocked(format($$select claim_task((select id from public.tasks where pickup_label = 'Cycle 4'))$$), 'handed back 3 trips'), 'RT-03 the fourth claim in the hour says why it is refused');
select pg_temp.eq(pg_temp.rows($$delete from driver_presence where profile_id = me()$$)::text, '0', 'RT-03 deleting the presence row (which handed a trip back at once) is not possible from the app');
select pg_temp.sudo(format($$update public.task_events set at = now() - interval '2 hours' where driver_id = %L$$, :'cyc')) \gset
select pg_temp.eq(pg_temp.q(format($$select claim_task((select id from public.tasks where pickup_label = 'Cycle 4'))$$)), 'true', 'RT-03 an hour later he can claim again');

-- RT-04  a trip whose destination changed can still be closed, by the driver after a long time or by staff
select pg_temp.clean() \gset
select pg_temp.mkuser('rod', '9100000111') as rod \gset
select pg_temp.mkuser('ross', '9100000112') as ross \gset
select pg_temp.mkuser('rex', '9100000113') as rex \gset
select pg_temp.mkdriver('drew', 'AUTO', 'KA01AB0063', 12.9262, 77.5941, '9100000105') as drew \gset
select pg_temp.mktask('rod', 'RIDE', 'IN_PROGRESS', 'drew') as g1 \gset
select pg_temp.age_task(:'g1', 1200) \gset
select pg_temp.as_user('drew');
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'COMPLETED')$$, :'g1'), 'too far from the drop'), 'RT-04 20 minutes into a 7.5 km trip, 5.6 km from the drop: still refused');
select pg_temp.age_task(:'g1', 2700) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'g1')), 'COMPLETED', 'RT-04 45 minutes in (max(30 min, 6 min per km)) the driver can complete from where he is: the rider changed the destination');
select pg_temp.mktask('ross', 'RIDE', 'IN_PROGRESS', 'drew') as g2 \gset
select pg_temp.run(format($$update public.tasks set km = 20 where id = %L$$, :'g2')) \gset
select pg_temp.age_task(:'g2', 3600) \gset
select pg_temp.check(pg_temp.blocked(format($$select advance_task(%L, 'COMPLETED')$$, :'g2'), 'too far from the drop'), 'RT-04 a 20 km trip gets 6 minutes a km: an hour in is still refused');
select pg_temp.age_task(:'g2', 7800) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'g2')), 'COMPLETED', 'RT-04 ... and 130 minutes in it can be completed');
select pg_temp.mktask('rex', 'RIDE', 'IN_PROGRESS', 'drew') as g3 \gset
select pg_temp.age_task(:'g3', 2700) \gset
select pg_temp.age_presence('drew', 400) \gset
select pg_temp.eq(pg_temp.q(format($$select status from advance_task(%L, 'COMPLETED')$$, :'g3')), 'COMPLETED', 'RT-04 after the wait a stale location no longer blocks completion (the phone may be off)');

select pg_temp.mkuser('stella', '9100000114') as stella \gset
select pg_temp.mkuser('rin', '9100000115') as rin \gset
select pg_temp.mkuser('rue', '9100000116') as rue \gset
select pg_temp.mkuser('ruth', '9100000117') as ruth \gset
select pg_temp.mkdriver('dax', 'BIKE', 'KA05CD0066', 12.9262, 77.5941, '9100000118') as dax \gset
select pg_temp.run(format($$insert into public.staff (profile_id) values (%L)$$, :'stella')) \gset
select pg_temp.mktask('rin', 'RIDE', 'IN_PROGRESS', 'drew') as g4 \gset
select pg_temp.as_user('drew');
select pg_temp.check(pg_temp.blocked(format($$select staff_close_task(%L)$$, :'g4'), 'only Bucks staff'), 'RT-04 a driver cannot close a trip through the staff function');
select pg_temp.as_user('rin');
select pg_temp.check(pg_temp.blocked(format($$select staff_close_task(%L, 'CANCELLED')$$, :'g4'), 'only Bucks staff'), 'RT-04 nor can the rider');
select pg_temp.as_user('stella');
select pg_temp.check(pg_temp.blocked(format($$select staff_close_task(%L, 'PAID')$$, :'g4'), 'COMPLETED or CANCELLED'), 'RT-04 staff choose COMPLETED or CANCELLED');
select pg_temp.eq(pg_temp.q(format($$select staff_close_task(%L)$$, :'g4')), 'COMPLETED', 'RT-04 staff can close a stuck trip as COMPLETED');
select pg_temp.eq(pg_temp.sq(format($$select status || ' ' || (select count(*) from public.task_events where task_id = %L and event = 'COMPLETED') from public.tasks where id = %L$$, :'g4', :'g4')), 'COMPLETED 1', 'RT-04 ... the driver gets the COMPLETED event, the rider can pay');
select pg_temp.check(pg_temp.blocked(format($$select staff_close_task(%L, 'CANCELLED')$$, :'g4'), 'trip under way'), 'RT-04 only a trip under way can be closed that way');
select pg_temp.run(format($$insert into public.orders (listing_id, buyer_id, lines, subtotal, delivery_mode, status, accept_by) values (%L, %L, %L, 62, 'MARKETPLACE', 'PICKED_UP', now()), (%L, %L, %L, 62, 'MARKETPLACE', 'PICKED_UP', now())$$,
                         :'erin_shop', :'rue', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), :'erin_shop', :'ruth', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1))) \gset
select pg_temp.sq(format($$select id::text from public.orders where buyer_id = %L$$, :'rue')) as ord_rue \gset
select pg_temp.sq(format($$select id::text from public.orders where buyer_id = %L$$, :'ruth')) as ord_ruth \gset
select pg_temp.mktask('rue', 'DELIVERY', 'IN_PROGRESS', 'dax', :'ord_rue') as g5 \gset
select pg_temp.mktask('ruth', 'DELIVERY', 'IN_PROGRESS', 'dax', :'ord_ruth') as g6 \gset
select pg_temp.as_user('stella');
select pg_temp.eq(pg_temp.q(format($$select staff_close_task(%L, 'COMPLETED')$$, :'g5')), 'COMPLETED', 'RT-04 a stuck delivery closed as COMPLETED...');
select pg_temp.eq(pg_temp.sq(format($$select status from public.orders where id = %L$$, :'ord_rue')), 'DELIVERED', 'RT-04 ... delivers its order');
select pg_temp.eq(pg_temp.q(format($$select staff_close_task(%L, 'CANCELLED')$$, :'g6')), 'CANCELLED', 'RT-04 a stuck delivery closed as CANCELLED...');
select pg_temp.eq(pg_temp.sq(format($$select status || ' ' || cancelled_by || ' ' || (select count(*) from public.task_events where task_id = %L and event = 'MISSED') from public.orders where id = %L$$, :'g6', :'ord_ruth')), 'CANCELLED BUYER 1', 'RT-04 ... cancels its order and the rider gets a MISSED event');

-- RT-05  orders the shop can no longer answer do not count against the buyer
select pg_temp.clean() \gset
select pg_temp.mkuser('benji', '9100000119') as benji \gset
select pg_temp.as_user('benji');
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, 'Benji home', 'UPI', 'MARKETPLACE') as b1 \gset
select place_order(:'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1), 12.9300, 77.6000, 'Benji home', 'UPI', 'MARKETPLACE') as b2 \gset
select place_order(:'fay_shop', pg_temp.line(pg_temp.item(:'fay_shop', 'Rice'), 1), 12.9300, 77.6000, 'Benji home', 'UPI', 'MARKETPLACE') as b3 \gset
select pg_temp.run(format($$update public.orders set accept_by = now() - interval '2 hours' where buyer_id = %L and status = 'PLACED'$$, :'benji')) \gset
select pg_temp.eq(pg_temp.ok(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Benji home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1))), 'done',
                  'RT-05 three orders the shop never answered (still PLACED, past accept_by, no cron running) do not block the next one');
select pg_temp.eq(pg_temp.ok(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Benji home', 'UPI', 'MARKETPLACE')$$, :'erin_shop', pg_temp.line(pg_temp.item(:'erin_shop', 'Rice'), 1))), 'done', 'RT-05 ... nor the one after');
select pg_temp.eq(pg_temp.ok(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Benji home', 'UPI', 'MARKETPLACE')$$, :'fay_shop', pg_temp.line(pg_temp.item(:'fay_shop', 'Rice'), 1))), 'done', 'RT-05 ... up to three orders that are still open');
select pg_temp.check(pg_temp.blocked(format($$select place_order(%L, %L::jsonb, 12.93, 77.60, 'Benji home', 'UPI', 'MARKETPLACE')$$, :'fay_shop', pg_temp.line(pg_temp.item(:'fay_shop', 'Dal'), 1)), 'orders waiting'), 'RT-05 a fourth order that is still open is refused as before');
select pg_temp.clean() \gset
