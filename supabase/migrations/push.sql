-- Bucks: push notifications (Firebase Cloud Messaging through a Supabase Edge Function).
-- Idempotent: safe to re-run in the SQL Editor after schema.sql.
--
-- Flow: a row lands in messages / orders / tasks / syncs / moments / post_comments -> an AFTER trigger queues one
-- HTTP POST with pg_net (asynchronous: the insert never waits on the network) -> the Edge Function "notify"
-- works out who should hear about it, honours their notification settings and quiet hours, and sends through FCM.
-- The app stores its FCM token in device_tokens after sign-in.
set search_path = public, extensions;

-- ---------- device tokens: one row per phone, owned by whoever is signed in on it ----------

create table if not exists public.device_tokens (
  token       text primary key,
  profile_id  uuid not null references public.profiles on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index if not exists device_tokens_profile_idx on public.device_tokens (profile_id);

alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_self on public.device_tokens;
create policy device_tokens_self on public.device_tokens for all to authenticated
  using (profile_id = public.me()) with check (profile_id = public.me());
grant select, insert, update, delete on public.device_tokens to authenticated;

-- A phone's token follows the person who signs in on it: registering takes the token over from any previous owner
-- (a plain upsert could not, because row-level security hides the old owner's row).
create or replace function public.register_device_token(p_token text, p_platform text default 'android') returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'not signed in'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'empty device token'; end if;
  insert into device_tokens (token, profile_id, platform) values (trim(p_token), me(), coalesce(nullif(trim(p_platform), ''), 'android'))
  on conflict (token) do update set profile_id = excluded.profile_id, platform = excluded.platform, updated_at = now();
end $$;

-- Sign-out: forget this phone so the next person who signs in here does not get my notifications.
create or replace function public.unregister_device_token(p_token text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from device_tokens where token = trim(p_token) and profile_id = me()
$$;

revoke execute on function public.register_device_token(text, text), public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text), public.unregister_device_token(text) to authenticated;

-- ---------- notification settings: my own orders and trips have their own switches ----------
-- "orders" and "tasks" are my businesses' new orders and the trips I drive; "my_orders" and "my_trips" are updates on
-- orders I place and rides or deliveries I book, so a customer who switches the business/driver ones off still hears
-- "Your rider is here". A missing key means on (notify/index.ts wants()), so existing rows need no update.
alter table public.user_settings alter column notify set default
  '{"messages": true, "sync_requests": true, "moments": true, "comments": true, "orders": true, "tasks": true, "my_orders": true, "my_trips": true, "offers": false}';

-- ---------- private configuration: the shared secret the Edge Function checks ----------
-- Nobody reads this through the API (no policies, no grants); only the database owner and trigger functions can.
-- Fill it once:  insert into public.push_config values ('webhook_secret', '<long random string>') on conflict (key) do update set value = excluded.value;

create table if not exists public.push_config (key text primary key, value text not null);
alter table public.push_config enable row level security;
revoke all on public.push_config from public, anon, authenticated;

-- Where the Edge Function lives for this project.
create or replace function public.notify_url() returns text language sql immutable set search_path = public, extensions as $$
  select 'https://lboxctryrktwdsvywfqp.supabase.co/functions/v1/notify'
$$;
revoke execute on function public.notify_url() from public, anon, authenticated;

-- ---------- pg_net: asynchronous HTTP from triggers (installed on Supabase; skipped where it is not available) ----------

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;   -- not relocatable: always lands in schema "net"
  end if;
end $$;

-- ---------- the trigger: queue one webhook call per event ----------
-- Cheap by design: one small select for the secret, one row queued in net.http_request_queue, no waiting on the response.
-- Nothing here can ever block a chat message or an order: without pg_net or without a secret it does nothing, and
-- any error is swallowed.

create or replace function public.push_notify() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare secret text; payload jsonb;
begin
  if to_regproc('net.http_post') is null then return null; end if;
  select value into secret from push_config where key = 'webhook_secret';
  if secret is null or secret = '' then return null; end if;
  -- Only tables with a status column have UPDATE triggers; the nested if keeps new.status out of the INSERT path.
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status then return null; end if;
  end if;
  payload := jsonb_build_object('table', tg_table_name, 'type', tg_op, 'record', to_jsonb(new),
                                'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end);
  perform net.http_post(url := notify_url(), body := payload,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-bucks-secret', secret),
                        timeout_milliseconds := 5000);
  return null;
exception when others then
  return null;
end $$;
revoke execute on function public.push_notify() from public, anon, authenticated;

drop trigger if exists push_messages on public.messages;
create trigger push_messages after insert on public.messages for each row execute function public.push_notify();

drop trigger if exists push_orders on public.orders;
create trigger push_orders after insert or update of status on public.orders for each row execute function public.push_notify();

drop trigger if exists push_tasks on public.tasks;
create trigger push_tasks after insert or update of status on public.tasks for each row execute function public.push_notify();

drop trigger if exists push_syncs on public.syncs;
create trigger push_syncs after insert or update of status on public.syncs for each row execute function public.push_notify();

drop trigger if exists push_moments on public.moments;
create trigger push_moments after insert on public.moments for each row execute function public.push_notify();

drop trigger if exists push_post_comments on public.post_comments;
create trigger push_post_comments after insert on public.post_comments for each row execute function public.push_notify();
