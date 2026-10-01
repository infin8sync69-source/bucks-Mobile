-- Catalog assertions: read-only checks of how the database is locked down, one "ok:" or "FAIL:" line each. They would have caught
-- the audit findings that came from a re-run of schema.sql (older policies, full grants, internal functions callable) and from tables or
-- functions that were added without the usual posture. Safe to run on any database that has the Bucks stack (it only reads the catalogs).
--   psql -X -q -d <db> -f supabase/tests/catalog_assertions.sql        (or:  psql "$DATABASE_URL" -X -q -f supabase/tests/catalog_assertions.sql)
-- Run it after every migration. It is a psql script with one result per statement; the Supabase SQL Editor only shows the last statement's result.
\pset format unaligned
\pset tuples_only on
\pset pager off

-- ---------- row-level security ----------
select case when count(*) = 0 then 'ok: every public table has row-level security on'
            else 'FAIL: public tables without row-level security: ' || string_agg(c.relname, ', ' order by c.relname) end
from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;

select case when count(*) = 0 then 'ok: every public view is security_invoker (a view otherwise bypasses the tables'' policies)'
            else 'FAIL: public views that bypass row-level security: ' || string_agg(c.relname, ', ' order by c.relname) end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v' and not exists (select 1 from unnest(coalesce(c.reloptions, '{}')) o where o in ('security_invoker=true', 'security_invoker=on', 'security_invoker=1'));

-- ---------- policies ----------
select case when count(*) = 0 then 'ok: no policy on a public table or on Bucks'' storage rules is granted to anon or public'
            else 'FAIL: policies open to anon or public: ' || string_agg(schemaname || '.' || tablename || '.' || policyname, ', ' order by tablename, policyname) end
from pg_policies
where roles && array['anon', 'public']::name[] and (schemaname = 'public' or (schemaname = 'storage' and (policyname like 'bucks\_%' or policyname = 'docs staff read')));

select case when count(*) = 0 then 'ok: the storage policies of older schema.sql versions are gone (bucks_own_folder, bucks_chat)'
            else 'FAIL: schema.sql''s storage policies are in force (hardening_platform.sql is not applied, or schema.sql was re-run after it): ' || string_agg(policyname, ', ') end
from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('bucks_own_folder', 'bucks_chat');

-- Tables the app may only read: no policy lets a signed-in user insert into or update them.
select case when count(*) = 0 then 'ok: reference, review and internal tables have no insert or update policy'
            else 'FAIL: tables that should be read-only from the app have a write policy: ' || string_agg(tablename || '.' || policyname, ', ') end
from pg_policies
where schemaname = 'public' and cmd in ('INSERT', 'UPDATE', 'ALL')
  and tablename in ('settings', 'service_rules', 'doc_types', 'service_doc_rules', 'staff', 'listing_documents', 'service_interest', 'moment_access', 'recommendations',
                    'recommend_tokens', 'task_events', 'reviews', 'moment_views', 'notifications', 'storage_cleanup', 'push_config');

-- ---------- table and column privileges ----------
select case when count(*) = 0 then 'ok: anon has no privilege on any public table or view'
            else 'FAIL: anon holds privileges on: ' || string_agg(c.relname, ', ' order by c.relname) end
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p', 'v') and has_table_privilege('anon', c.oid, 'select, insert, update, delete');

select case when has_column_privilege('authenticated', 'public.profiles', 'home', 'select') then 'FAIL: authenticated can read profiles.home (a person''s real home)'
            else 'ok: authenticated cannot read profiles.home' end;
select case when has_column_privilege('authenticated', 'public.tasks', 'pin', 'select') then 'FAIL: authenticated can read tasks.pin (the rider''s PIN reaches the driver)'
            else 'ok: authenticated cannot read tasks.pin' end;
select case when count(*) = 0 then 'ok: authenticated cannot read the private tables (push_config, storage_cleanup, recommend_tokens, staff)'
            else 'FAIL: authenticated can read: ' || string_agg(t, ', ') end
from unnest(array['push_config', 'storage_cleanup', 'recommend_tokens', 'staff']) t
where to_regclass('public.' || t) is not null and has_table_privilege('authenticated', to_regclass('public.' || t), 'select');
select case when count(*) = 0 then 'ok: authenticated cannot insert or update notifications (only Bucks'' triggers write them)'
            else 'FAIL: authenticated can write notifications' end
from (select 1) x where to_regclass('public.notifications') is not null and has_table_privilege('authenticated', 'public.notifications', 'insert, update');
select case when has_schema_privilege('authenticated', 'public', 'create') or has_schema_privilege('anon', 'public', 'create') then 'FAIL: anon or authenticated can create objects in schema public'
            else 'ok: neither anon nor authenticated can create objects in schema public' end;

-- ---------- functions ----------
-- "Bucks functions": in schema public, not owned by an extension. One statement, one line per assertion.
with f as (
  select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef, p.proconfig, p.proacl, p.proowner
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'))
select case when count(*) = 0 then 'ok: no SECURITY DEFINER function is executable by anon'
            else 'FAIL: SECURITY DEFINER functions executable by anon: ' || string_agg(proname || '(' || args || ')', ', ' order by proname) end
from f where prosecdef and has_function_privilege('anon', oid, 'execute')
union all
select case when count(*) = 0 then 'ok: no SECURITY DEFINER function is executable by PUBLIC'
            else 'FAIL: SECURITY DEFINER functions executable by PUBLIC: ' || string_agg(proname || '(' || args || ')', ', ' order by proname) end
from f where prosecdef and exists (select 1 from aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
union all
select case when count(*) = 0 then 'ok: every SECURITY DEFINER function pins its search_path'
            else 'FAIL: SECURITY DEFINER functions without a search_path: ' || string_agg(proname || '(' || args || ')', ', ' order by proname) end
from f where prosecdef and not exists (select 1 from unnest(coalesce(proconfig, '{}')) c where c like 'search_path=%')
union all
-- Internal helpers, trigger bodies and cron jobs: never callable through the API (a schema.sql re-run re-grants them all).
select case when count(*) = 0 then 'ok: internal functions (guards, triggers, notification writers, cron jobs) are not executable by authenticated'
            else 'FAIL: internal functions callable by authenticated: ' || string_agg(proname || '(' || args || ')', ', ' order by proname) end
from f
where proname in ('synced', 'settings_of', 'expire_orders', 'expire_moments', 'listing_add_owner', 'vehicle_add_owner', 'touch_conversation', 'post_counts', 'on_block',
                  'guard_profile', 'guard_listing', 'guard_vehicle', 'guard_message', 'check_application', 'guard_application', 'guard_conversation_member', 'guard_sync',
                  'guard_post', 'task_status_at', 'presence_touch', 'try_go_live', 'expire_documents', 'listing_service_rules', 'profile_deleted_cleanup', 'listing_compliant',
                  'item_stock_rules', 'order_stock_back', 'push_notify', 'notify_url', 'push_note', 'push_note_team', 'pname', 'note_sync', 'note_invite', 'note_order',
                  'note_recommendation', 'note_listing_status', 'note_document', 'note_review', 'note_comment', 'note_vote', 'note_reaction', 'contact_link_guard',
                  'guard_profile_insert', 'guard_insert_stamps', 'guard_profile_private', 'snap_location', 'guard_listing_reverify', 'prune_recommendations',
                  'vehicle_normalise', 'device_token_cap',
                  'presence_clamp', 'vehicle_offline', 'tasks_hygiene', 'orders_hygiene', 'dispatch_cfg', 'new_pin', 'driver_near_check', 'expire_tasks')
  and has_function_privilege('authenticated', oid, 'execute');

-- ---------- what the hardening migration guarantees ----------
select case when count(*) = 8 then 'ok: location snapping, insert stamps, private-row guard, re-review, recommendation pruning, plate and token triggers are all enabled'
            else 'FAIL: hardening triggers missing or disabled (found ' || count(*) || ' of 8)' end
from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal and t.tgenabled = 'O'
  and (c.relname, t.tgname) in (('posts', 'snap_location'), ('moments', 'snap_location'), ('profiles', 'profile_insert_guard'), ('messages', 'message_stamp'),
                                ('profile_private', 'profile_private_guard'), ('listings', 'listing_reverify'), ('vehicles', 'vehicle_a_normalise'), ('device_tokens', 'device_token_cap'));

-- hardening_dispatch.sql: the speed check on presence, vehicles that stop being ACTIVE take their driver offline, hygiene on tasks and orders.
select case when count(*) = 4 then 'ok: presence speed check, vehicle-offline and task/order hygiene triggers are all enabled'
            else 'FAIL: dispatch hardening triggers missing or disabled (found ' || count(*) || ' of 4; hardening_dispatch.sql is not applied, or schema.sql was re-run after it)' end
from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal and t.tgenabled = 'O'
  and (c.relname, t.tgname) in (('driver_presence', 'presence_clamp'), ('vehicles', 'vehicle_offline'), ('tasks', 'tasks_hygiene'), ('orders', 'orders_hygiene'));

-- A driver who could delete their presence row could insert a fresh one anywhere (skipping the speed check) and reset the hand-back cap.
select case when count(*) = 0 then 'ok: nobody can delete a presence row from the app (no DELETE policy on driver_presence)'
            else 'FAIL: driver_presence has a delete policy (schema.sql was re-run after hardening_dispatch.sql?): ' || string_agg(policyname, ', ') end
from pg_policies where schemaname = 'public' and tablename = 'driver_presence' and cmd in ('DELETE', 'ALL');

select case when count(*) = 1 then 'ok: at most one open ride per rider (unique index tasks_one_open_ride)'
            else 'FAIL: index tasks_one_open_ride is missing (hardening_dispatch.sql is not applied)' end
from pg_indexes where schemaname = 'public' and indexname = 'tasks_one_open_ride';

select case when position('vehicles' in pg_get_functiondef('public.doc_path_locked(text)'::regprocedure)) > 0
            then 'ok: the document files of an ACTIVE vehicle are locked along with VERIFIED listing documents'
            else 'FAIL: doc_path_locked ignores vehicle documents (an older hardening_platform.sql?)' end;

select case when count(*) = 7 then 'ok: the JSON shape and text length checks are in place (messages, posts, moments, profiles, device tokens)'
            else 'FAIL: hardening constraints missing (found ' || count(*) || ' of 7)' end
from pg_constraint where connamespace = 'public'::regnamespace
  and conname in ('messages_attachment_ok', 'posts_media_ok', 'moments_media_path_len', 'profiles_name_len', 'profile_private_upi_ok', 'device_tokens_token_len', 'posts_body_len');

-- Storage checks need the storage schema (Supabase always has it; locally tests/local_auth_shim.sql provides it).
select case when (select allowed_mime_types is null from storage.buckets where id = 'chat') then 'FAIL: the chat bucket accepts any file type (allowed_mime_types is null)'
            else 'ok: the chat bucket has a file type allow-list' end;
select case when count(*) = 0 then 'ok: avatars and listing-media are the only public buckets'
            else 'FAIL: buckets with the wrong public flag: ' || string_agg(id || ' public=' || public, ', ') end
from storage.buckets where id in ('avatars', 'listing-media', 'posts', 'moments', 'chat', 'docs') and ((id in ('avatars', 'listing-media')) <> public);
