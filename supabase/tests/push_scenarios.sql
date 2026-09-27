\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Push notifications: device tokens, the sealed config table and the webhook triggers.
-- Run after local_auth_shim.sql, schema.sql and migrations/push.sql in the same psql session.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;

\echo '== 0. pg_net: real queue on Supabase, a recording stand-in elsewhere'
select case when exists (select 1 from pg_extension where extname = 'pg_net') then 'pg_net is installed: requests go to net.http_request_queue'
            else 'pg_net not available locally: using a stand-in net.http_post that records calls' end;
create table if not exists public.push_test_calls (id serial primary key, url text, body jsonb, headers jsonb);
do $$ begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    create schema if not exists net;
    create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{"Content-Type": "application/json"}', timeout_milliseconds int default 5000)
      returns bigint language sql as $f$ insert into public.push_test_calls (url, body, headers) values (url, body, headers) returning id $f$;
  end if;
end $$;

set role authenticated;
select pg_temp.as_user('priya'); select (public.ensure_profile('Priya', '9000000021')).id is not null;
select pg_temp.as_user('arun');  select (public.ensure_profile('Arun', '9000000022')).id is not null;
reset role; update profiles set home = geo(12.9063, 77.5857) where auth_uid in ('priya', 'arun'); set role authenticated;

\echo '== 1. Device tokens: mine only; a token follows whoever signs in on the phone'
select pg_temp.as_user('arun');
select register_device_token('fcm-token-phone-A', 'android');
select register_device_token('fcm-token-phone-A');   -- re-registering the same token is fine
select 'Arun sees his tokens: ' || string_agg(token || ' (' || platform || ')', ', ') from device_tokens;
select 'empty token -> ' || pg_temp.expect_fail($$select register_device_token('  ')$$, 'empty');
select 'forge a row for someone else -> ' || pg_temp.expect_fail(format($$insert into device_tokens (token, profile_id) values ('forged', %L)$$, pg_temp.pid('priya')), 'row-level security');
select pg_temp.as_user('priya');
select 'Priya sees Arun''s tokens: ' || count(*) from device_tokens;
select register_device_token('fcm-token-phone-A');  -- Priya signs in on the same phone
select 'phone A now belongs to Priya: ' || count(*) from device_tokens where token = 'fcm-token-phone-A';
select pg_temp.as_user('arun');
select 'Arun lost phone A: ' || count(*) from device_tokens;
select register_device_token('fcm-token-phone-B');
select unregister_device_token('fcm-token-phone-B');
select 'after sign-out on phone B: ' || count(*) from device_tokens;
select 'unregister someone else''s token silently does nothing: ' || (select unregister_device_token('fcm-token-phone-A') is null);
select pg_temp.as_user('priya'); select 'Priya still has phone A: ' || count(*) from device_tokens;

\echo '== 1b. Notification settings: my own orders and trips have their own switches, on by default'
select pg_temp.as_user('arun');
insert into user_settings (profile_id) values (me()) on conflict (profile_id) do nothing;
select 'new settings row: my_orders=' || (notify->>'my_orders') || ' my_trips=' || (notify->>'my_trips') || ' orders=' || (notify->>'orders') || ' tasks=' || (notify->>'tasks') || ' offers=' || (notify->>'offers')
  from user_settings where profile_id = me();
select case when (notify->>'my_orders')::boolean and (notify->>'my_trips')::boolean then 'ok: customer updates on by default' else 'FAIL: my_orders/my_trips not on by default' end
  from user_settings where profile_id = me();
update user_settings set notify = notify || '{"orders": false, "tasks": false}' where profile_id = me();
select case when (notify->>'my_orders')::boolean and (notify->>'my_trips')::boolean then 'ok: business/driver switches off, own order and trip updates still on' else 'FAIL: switching off orders/tasks turned off my own updates' end
  from user_settings where profile_id = me();
delete from user_settings where profile_id = me();

\echo '== 2. The webhook secret is sealed'
select 'app reads push_config -> ' || pg_temp.expect_fail($$select * from public.push_config$$, 'permission denied');
select 'app calls notify_url() -> ' || pg_temp.expect_fail($$select public.notify_url()$$, 'permission denied');
reset role;
select 'notify_url: ' || public.notify_url();

\echo '== 3. Without a secret the triggers stay silent'
delete from public.push_config where key = 'webhook_secret'; delete from public.push_test_calls;
set role authenticated;
select pg_temp.as_user('arun'); select 'sync request: ' || request_sync(pg_temp.pid('priya'));
reset role;
select 'calls queued without a secret: ' || count(*) from public.push_test_calls;

\echo '== 4. With a secret: messages, syncs, orders and tasks each queue one call carrying the row and the secret'
insert into public.push_config values ('webhook_secret', 'test-secret') on conflict (key) do update set value = excluded.value;
set role authenticated;
select pg_temp.as_user('priya');
select 'Priya syncs back: ' || request_sync(pg_temp.pid('arun'));     -- UPDATE of syncs.status -> 1 call
select set_config('t.conv', start_direct(pg_temp.pid('arun'))::text, false) is not null;
insert into messages (conversation_id, sender_id, body) values (current_setting('t.conv')::uuid, me(), 'Order ready, come by 6');   -- INSERT -> 1 call
reset role;
select 'calls so far: ' || count(*) from public.push_test_calls;
select 'message call: table=' || (body->>'table') || ' type=' || (body->>'type') || ' body="' || (body->'record'->>'body') || '" secret=' || (headers->>'x-bucks-secret') || ' url ok=' || (url = public.notify_url())
  from public.push_test_calls where body->>'table' = 'messages';
select 'sync call: table=' || (body->>'table') || ' type=' || (body->>'type') || ' status ' || (body->'old_record'->>'status') || ' -> ' || (body->'record'->>'status')
  from public.push_test_calls where body->>'table' = 'syncs';

-- A live shop, so an order can be placed; accepting it creates a delivery task.
delete from public.push_test_calls;
insert into listings (id, kind, owner_id, title, category, area, location, status) values ('019a0000-0000-7000-8000-000000000001', 'BUSINESS', pg_temp.pid('priya'), 'Priya Stores', 'Grocery', 'JP Nagar', geo(12.9063, 77.5857), 'LIVE');
insert into items (id, listing_id, name, price) values ('019a0000-0000-7000-8000-000000000002', '019a0000-0000-7000-8000-000000000001', 'Sugar 1 kg', 45);
set role authenticated;
select pg_temp.as_user('arun');
select set_config('t.order', place_order('019a0000-0000-7000-8000-000000000001', '[{"item_id": "019a0000-0000-7000-8000-000000000002", "qty": 2}]', 12.91, 77.59, 'Home, 4th block', 'UPI', 'MARKETPLACE')::text, false) is not null;
select pg_temp.as_user('priya');
select respond_order(current_setting('t.order')::uuid, true);
reset role;
select 'order + accept + delivery task: ' || string_agg((body->>'table') || ':' || (body->>'type') || ':' || (body->'record'->>'status'), ', ' order by id) from public.push_test_calls;
select 'delivery task carries the order id: ' || ((body->'record'->>'order_id') = current_setting('t.order')) from public.push_test_calls where body->>'table' = 'tasks';

\echo '== 5. A status update that does not change the status is not sent'
delete from public.push_test_calls;
update public.orders set status = status where id = current_setting('t.order')::uuid;
select 'calls for a no-op status update: ' || count(*) from public.push_test_calls;

\echo '== 6. On Supabase the same calls sit in the pg_net queue'
create or replace function pg_temp.queue_info() returns text language plpgsql as $$
declare n bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then return 'skipped: pg_net not installed here'; end if;
  execute 'select count(*) from net.http_request_queue' into n;
  return 'pg_net queue rows (the worker drains them within seconds): ' || n;
end $$;
select pg_temp.queue_info();
drop table if exists public.push_test_calls;
