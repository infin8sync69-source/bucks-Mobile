-- Legal hold and terms versions (2026-11-13). Safe to re-run. See docs/LAW_ENFORCEMENT.md and docs/legal/privacy.md.
--
-- 1. legal_holds: when someone deletes their account, delete_my_account first seals a copy of their registration details (IT Rules,
--    2021 rule 3(1)(h): keep for 180 days after the account is cancelled). Nobody can read it through the API: no policies, no grants.
--    Authorised staff read it in the SQL editor to answer a lawful request. A daily job deletes it after 180 days, unless
--    preserve_until (set by hand when an authority asks for preservation) is later.
-- 2. settings.terms_version is the version of the Terms everyone must have accepted; terms_status() tells the app whether to ask again.

-- ---------- 1. legal hold ----------
create table if not exists public.legal_holds (
  profile_id      uuid primary key,
  auth_uid        text,
  short_code      text,
  name            text,
  phone           text,
  account_created timestamptz,
  birth_date      date,
  age_band        text,
  guardian        jsonb,
  terms_version   text,
  vehicles        jsonb not null default '[]',   -- [{id, kind, plate, model}]
  listings        jsonb not null default '[]',   -- [{id, kind, title}]
  task_ids        uuid[] not null default '{}',  -- rides and deliveries requested or driven (latest 500)
  order_ids       uuid[] not null default '{}',  -- orders placed (latest 500)
  reason          text not null default 'ACCOUNT_DELETED',
  held_at         timestamptz not null default now(),
  purge_after     timestamptz not null default now() + interval '180 days',
  preserve_until  timestamptz,                   -- an authority asked us to preserve it (set by hand, with a note)
  preserve_note   text
);
alter table public.legal_holds enable row level security;
revoke all on public.legal_holds from public, anon, authenticated;

create or replace function public.legal_hold_snapshot(p uuid, p_reason text default 'ACCOUNT_DELETED') returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into legal_holds (profile_id, auth_uid, short_code, name, phone, account_created, birth_date, age_band, guardian, terms_version,
                           vehicles, listings, task_ids, order_ids, reason)
  select pr.id, pr.auth_uid, pr.short_code, pr.name, pp.phone, pr.created_at, ps.birth_date, ps.age_band,
         (select to_jsonb(g) - 'profile_id' from guardian_consents g where g.profile_id = pr.id),
         pr.terms_version,
         coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'kind', v.kind, 'plate', v.plate, 'model', v.model)) from vehicles v where v.owner_id = pr.id), '[]'),
         coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'title', l.title)) from listings l where l.owner_id = pr.id), '[]'),
         coalesce((select array_agg(x.id) from (select t.id from tasks t where pr.id in (t.requester_id, t.driver_id) order by t.created_at desc limit 500) x), '{}'),
         coalesce((select array_agg(x.id) from (select o.id from orders o where o.buyer_id = pr.id order by o.created_at desc limit 500) x), '{}'),
         p_reason
  from profiles pr
  left join profile_private pp on pp.profile_id = pr.id
  left join profile_safety ps on ps.profile_id = pr.id
  where pr.id = p
  on conflict (profile_id) do update set
    auth_uid = excluded.auth_uid, short_code = excluded.short_code, name = excluded.name, phone = coalesce(excluded.phone, legal_holds.phone),
    account_created = excluded.account_created, birth_date = excluded.birth_date, age_band = excluded.age_band, guardian = excluded.guardian,
    terms_version = excluded.terms_version, vehicles = excluded.vehicles, listings = excluded.listings, task_ids = excluded.task_ids,
    order_ids = excluded.order_ids, reason = excluded.reason, held_at = now(), purge_after = now() + interval '180 days';
end $$;
revoke execute on function public.legal_hold_snapshot(uuid, text) from public, anon, authenticated;

create or replace function public.purge_legal_holds() returns int
language sql security definer set search_path = public, extensions as $$
  with x as (delete from legal_holds where purge_after < now() and (preserve_until is null or preserve_until < now()) returning 1)
  select count(*)::int from x
$$;
revoke execute on function public.purge_legal_holds() from public, anon, authenticated;

-- delete_my_account: unchanged except for the first step, which seals the registration record before anything is removed.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); uid text; mine text[];
begin
  if my is null then raise exception 'not signed in'; end if;
  perform legal_hold_snapshot(my, 'ACCOUNT_DELETED');
  select auth_uid into uid from profiles where id = my;
  select coalesce(array_agg(id::text), '{}') into mine from listings where owner_id = my;
  if to_regclass('storage.objects') is not null then
    insert into storage_cleanup (bucket, name)
      select o.bucket_id, o.name from storage.objects o
       where (o.bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(o.name))[1] = my::text)
          or (o.bucket_id = 'listing-media' and (storage.foldername(o.name))[1] = any(mine))
          or (o.bucket_id = 'chat' and uid in (to_jsonb(o) ->> 'owner_id', to_jsonb(o) ->> 'owner'))
    on conflict do nothing;
  end if;
  delete from driver_presence where profile_id = my;
  update tasks set status = 'CANCELLED' where requester_id = my and status in ('SEARCHING', 'MATCHED', 'ARRIVED', 'NO_DRIVER');
  insert into task_events (task_id, driver_id, vehicle_id, event) select id, my, vehicle_id, 'CANCELLED' from tasks where driver_id = my and status in ('MATCHED', 'ARRIVED');
  update tasks set status = 'SEARCHING', driver_id = null, vehicle_id = null, driver_location = null where driver_id = my and status in ('MATCHED', 'ARRIVED');
  delete from profile_private where profile_id = my;
  delete from syncs where my in (requester_id, addressee_id);
  update listings set status = 'DELETED', online = false, photo_url = null, description = '', area = '', gallery = '[]',
                      details = case when kind = 'ASSET' then details else '{}'::jsonb end,
                      title = case when kind = 'BUSINESS' then title else 'Deleted listing' end
   where owner_id = my;
  delete from posts where author_id = my;
  delete from moments where author_id = my;
  delete from post_comments where author_id = my;
  delete from post_votes where profile_id = my;
  update messages set deleted_at = now() where sender_id = my and deleted_at is null;
  delete from conversation_members where profile_id = my;
  delete from close_friends where my in (profile_id, friend_id);
  delete from listing_syncs where profile_id = my;
  delete from contact_links where my in (owner_id, profile_id);
  delete from user_settings where profile_id = my;
  delete from blocks where my in (blocker_id, blocked_id);
  delete from moment_views where viewer_id = my;
  delete from moment_mutes where my in (profile_id, muted_id);
  delete from moment_access where viewer_id = my;
  delete from device_tokens where profile_id = my;
  delete from applications where applicant_id = my;
  delete from invites where my in (inviter_id, invitee_id);
  delete from vehicles where owner_id = my;
  delete from vehicle_members where profile_id = my;
  delete from notifications where profile_id = my;
  delete from recommendations where recommender_id = my;
  delete from staff where profile_id = my;
  if to_regclass('public.addresses') is not null then delete from addresses where profile_id = my; end if;
  if to_regclass('public.product_ratings') is not null then delete from product_ratings where profile_id = my; end if;
  if to_regclass('public.profile_votes') is not null then delete from profile_votes where my in (voter_id, subject_id); end if;
  if to_regclass('public.doc_access_requests') is not null then delete from doc_access_requests where requester_id = my; end if;
  if to_regclass('public.doc_views') is not null then delete from doc_views where viewer_id = my; end if;
  if to_regclass('public.doc_checks') is not null then delete from doc_checks where profile_id = my; end if;
  delete from reports where reporter_id = my;
  delete from guardian_consents where profile_id = my;
  delete from profile_safety where profile_id = my;
  if to_regclass('public.feedback_posts') is not null then delete from feedback_votes where profile_id = my; delete from feedback_posts where author_id = my; end if;
  update profiles set name = '', bio = '', area = '', photo_url = null, home = null, status = 'DELETED', auth_uid = 'deleted:' || id::text where id = my;
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('bucks-purge-legal-holds', '50 20 * * *', 'select public.purge_legal_holds()');   -- 02:20 IST
  end if;
end $$;

-- ---------- 2. terms versions ----------
-- settings.value is numeric, so the version is stored as YYYYMMDD (20261113) and shown to the apps as YYYY-MM-DD, the form Legal.TERMS_VERSION uses.
-- Bump it (and TERMS_VERSION in both apps) whenever docs/legal/terms.md or privacy.md change in a way people must accept again.
insert into public.settings (key, value) values ('terms_version', 20261113)
  on conflict (key) do update set value = excluded.value;

-- What the app needs to decide whether to show "We've updated our terms": the current version, the one this person accepted, and needed.
create or replace function public.terms_status() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  with cur as (select regexp_replace(value::bigint::text, '^(\d{4})(\d{2})(\d{2})$', '\1-\2-\3') v from settings where key = 'terms_version')
  select jsonb_build_object('current', (select v from cur), 'accepted', p.terms_version, 'accepted_at', p.terms_accepted_at,
                            'needed', (select v from cur) is not null and p.terms_version is distinct from (select v from cur))
  from profiles p
  where p.id = me()
$$;
revoke execute on function public.terms_status() from public, anon;
grant execute on function public.terms_status() to authenticated;

-- record_terms never goes back to an older version: an app on a second phone that still remembers the old one must not undo an acceptance.
create or replace function public.record_terms(p_version text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); v text := left(btrim(coalesce(p_version, '')), 40);
begin
  if my is null then raise exception 'not signed in'; end if;
  if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'unknown terms version'; end if;
  update profiles set terms_version = v, terms_accepted_at = now()
   where id = my and (terms_version is null or terms_version !~ '^\d{4}-\d{2}-\d{2}$' or terms_version <= v);
end $$;
revoke execute on function public.record_terms(text) from public, anon;
grant execute on function public.record_terms(text) to authenticated;
