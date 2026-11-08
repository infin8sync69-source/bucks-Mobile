-- Social safety for the public release (docs/PLAY_RELEASE_PLAN.md):
--   0. Discover: search people by name or Bucks ID, and one person's posts for their profile page.
--   1. Reports: anyone can report a post, comment, Moment, message or person; staff review the queue and act on it.
--   2. Age bands: the date of birth given at sign-up sets CHILD (under 13), TEEN (13 to 17) or ADULT; the band is the server's to set.
--   3. Guardian consent for under-18s (recorded here; the app collects it before a teen or child can use social features).
--   4. Protections that follow the band, enforced here rather than trusted to the app: minors can only be messaged by syncs, their posts
--      never carry an exact location, children post to syncs only, and adults are not offered minors they share no sync with.
--
-- Runs after the hardening files. It redefines two functions; each copy carries every earlier change to it:
--   suggest_people   (latest before this: hardening_platform.sql), plus the minor filter;
--   delete_my_account (latest before this: hardening_platform.sql), plus reports, profile_safety and guardian consent.
set search_path = public, extensions;

insert into public.settings (key, value) values
  ('allow_children', 0),         -- 1 lets under-13s finish sign-up (the kids band ships switched off in 1.0)
  ('adult_age', 18), ('teen_age', 13)
on conflict (key) do nothing;

-- ---------- 2. age bands ----------

-- Kept apart from profiles (which every signed-in person can read): nobody but the person and the server can see someone's age or band,
-- so the band itself can't be used to look for minors. No insert/update grants: only set_birth_date (and staff, in SQL) write it.
create table if not exists public.profile_safety (
  profile_id  uuid primary key references public.profiles on delete cascade,
  birth_date  date not null,
  age_band    text not null check (age_band in ('CHILD', 'TEEN', 'ADULT')),
  set_at      timestamptz not null default now()
);
alter table public.profile_safety enable row level security;
drop policy if exists profile_safety_own on public.profile_safety;
create policy profile_safety_own on public.profile_safety for select to authenticated using (profile_id = (select public.me()));
revoke all on public.profile_safety from anon, authenticated;
grant select on public.profile_safety to authenticated;

create or replace function public.age_band_of(p uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select age_band from profile_safety where profile_id = p), 'UNKNOWN')
$$;
create or replace function public.is_minor(p uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select age_band_of(p) in ('CHILD', 'TEEN')
$$;

-- Set once, from the sign-up screen. A wrong date is corrected by support (staff), never by the person, so nobody can age up to lift the
-- protections. Under-13s are refused while allow_children is 0. Minors start with private defaults.
create or replace function public.set_birth_date(p_date date) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); prev date; years int; band text;
begin
  if my is null then raise exception 'not signed in'; end if;
  if p_date is null or p_date > current_date or p_date < date '1900-01-01' then raise exception 'enter a real date of birth'; end if;
  select birth_date into prev from profile_safety where profile_id = my;
  if prev is not null then
    if prev = p_date then return age_band_of(my); end if;
    raise exception 'your date of birth is already set; contact support to correct it';
  end if;
  years := extract(year from age(current_date, p_date))::int;
  band := case when years >= setting('adult_age') then 'ADULT' when years >= setting('teen_age') then 'TEEN' else 'CHILD' end;
  if band = 'CHILD' and coalesce(setting('allow_children'), 0) < 1 then raise exception 'too young: Bucks is for people aged 13 and over for now'; end if;
  insert into profile_safety (profile_id, birth_date, age_band) values (my, p_date, band);
  if band <> 'ADULT' then
    insert into user_settings (profile_id, who_can_message, discoverable, moments_audience)
    values (my, 'SYNCED', band = 'TEEN', 'SYNCED')
    on conflict (profile_id) do update set who_can_message = 'SYNCED', discoverable = excluded.discoverable, moments_audience = 'SYNCED';
  end if;
  return band;
end $$;

-- ---------- 3. guardian consent ----------

create table if not exists public.guardian_consents (
  profile_id     uuid primary key references public.profiles on delete cascade,
  guardian_name  text not null check (length(guardian_name) between 2 and 80),
  guardian_phone text not null check (guardian_phone ~ '^\+?[0-9 ]{8,20}$'),
  relation       text not null check (relation in ('PARENT', 'GUARDIAN')),
  method         text not null default 'DECLARED' check (method in ('DECLARED', 'OTP', 'DIGILOCKER')),
  consented_at   timestamptz not null default now()
);
alter table public.guardian_consents enable row level security;
drop policy if exists guardian_consents_own on public.guardian_consents;
create policy guardian_consents_own on public.guardian_consents for select to authenticated using (profile_id = (select public.me()));
revoke all on public.guardian_consents from anon, authenticated;
grant select on public.guardian_consents to authenticated;

create or replace function public.record_guardian_consent(p_name text, p_phone text, p_relation text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  if not is_minor(my) then raise exception 'guardian consent is only needed for people under 18'; end if;
  insert into guardian_consents (profile_id, guardian_name, guardian_phone, relation)
  values (my, btrim(p_name), regexp_replace(btrim(p_phone), '\s+', ' ', 'g'), upper(p_relation))
  on conflict (profile_id) do update set guardian_name = excluded.guardian_name, guardian_phone = excluded.guardian_phone,
    relation = excluded.relation, method = 'DECLARED', consented_at = now();
end $$;

-- What the app needs on start: the band and whether a guardian has consented (null for adults).
create or replace function public.my_safety() returns table (age_band text, birth_date_set boolean, guardian_consent boolean)
language sql stable security definer set search_path = public, extensions as $$
  select age_band_of(me()), exists (select 1 from profile_safety where profile_id = me()),
         case when is_minor(me()) then exists (select 1 from guardian_consents g where g.profile_id = me()) end
  where me() is not null
$$;

-- ---------- 4. protections that follow the band ----------

-- Minors: only syncs can message them; children are never discoverable.
create or replace function public.guard_minor_settings() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare band text := age_band_of(new.profile_id);
begin
  if band in ('CHILD', 'TEEN') then
    if new.who_can_message = 'EVERYONE' then new.who_can_message := 'SYNCED'; end if;
    if new.moments_audience = 'LOCAL' then new.moments_audience := 'SYNCED'; end if;
    if band = 'CHILD' then new.discoverable := false; new.who_can_sync := 'NOBODY'; end if;
  end if;
  return new;
end $$;
drop trigger if exists user_settings_minor_guard on public.user_settings;
create trigger user_settings_minor_guard before insert or update on public.user_settings for each row execute function public.guard_minor_settings();

-- Minors' posts: a teen's location is blurred to a ~2 km cell (Nearby still works, the exact spot is never stored); a child's post has no
-- location and is for syncs only.
create or replace function public.guard_minor_post() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare band text := age_band_of(new.author_id);
begin
  if band = 'TEEN' then
    if new.location is not null then new.location := st_snaptogrid(new.location::geometry, 0.02)::geography; end if;
  elsif band = 'CHILD' then
    new.location := null; new.visibility := 'SYNCED';
  end if;
  return new;
end $$;
drop trigger if exists post_minor_guard on public.posts;
create trigger post_minor_guard before insert or update on public.posts for each row execute function public.guard_minor_post();

-- suggest_people from hardening_platform.sql, plus: children are never suggested; teens are suggested to other teens, and to adults only when
-- they already share a sync (mutual > 0). People who haven't given a date of birth yet are treated as adults for this list.
create or replace function public.suggest_people(lat double precision, lng double precision, lim int default 20)
returns table (id uuid, name text, short_code text, area text, mutual int, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id)),
       here as (select st_snaptogrid(home::geometry, 0.02)::geography as g from profiles where id = me()),
       cand as (
         select p.id, p.name, p.short_code, p.area, age_band_of(p.id) as age_band,
                (select count(*)::int from syncs s where s.status = 'ACCEPTED' and ((s.requester_id = p.id and s.addressee_id in (select f from mine)) or (s.addressee_id = p.id and s.requester_id in (select f from mine)))) as mutual,
                case when (select g from here) is null or p.home is null then null
                     else round(st_distance(st_snaptogrid(p.home::geometry, 0.02)::geography, (select g from here)) / 2000.0::double precision) * 2000.0::double precision end as step
         from profiles p
         where p.id <> me() and p.status = 'ACTIVE' and (select discoverable from settings_of(p.id))
           and p.id not in (select f from mine) and not blocked_between(me(), p.id)
           and not exists (select 1 from syncs s where s.requester_id = me() and s.addressee_id = p.id)
           and age_band_of(p.id) <> 'CHILD')
  select c.id, c.name, c.short_code, c.area, c.mutual, c.step
  from cand c
  where c.age_band <> 'TEEN' or age_band_of(me()) = 'TEEN' or c.mutual > 0
  order by c.mutual desc, c.step nulls last, md5(me()::text || c.id::text)
  limit greatest(1, least(coalesce(lim, 20), 50))
$$;

-- Search people by name or Bucks ID, for the Discover tab. Same rules as suggest_people: discoverable, active, not blocked either way, never
-- children, teens only for teens or when there's a mutual sync. A Bucks ID typed in full finds that person even when they're not
-- discoverable (they shared it), unless they're a child or a block stands between you.
create or replace function public.search_people(q text, lim int default 30)
returns table (id uuid, name text, short_code text, area text, mutual int, synced boolean)
language sql stable security definer set search_path = public, extensions as $$
  with term as (select replace(replace(btrim(coalesce(q, '')), '%', ''), '_', '') t),   -- LIKE wildcards are dropped, not escaped
       mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id)),
       cand as (
         select p.id, p.name, p.short_code, p.area, age_band_of(p.id) as band,
                (select count(*)::int from syncs s where s.status = 'ACCEPTED' and ((s.requester_id = p.id and s.addressee_id in (select f from mine)) or (s.addressee_id = p.id and s.requester_id in (select f from mine)))) as mutual,
                p.id in (select f from mine) as synced,
                upper((select t from term)) = p.short_code as by_code
         from profiles p
         where length((select t from term)) >= 2 and p.id <> me() and p.status = 'ACTIVE' and not blocked_between(me(), p.id)
           and (p.name ilike '%' || (select t from term) || '%' or upper((select t from term)) = p.short_code))
  select c.id, c.name, c.short_code, c.area, c.mutual, c.synced
  from cand c
  where c.band <> 'CHILD'
    and (c.synced or c.by_code or (select discoverable from settings_of(c.id)))
    and (c.band <> 'TEEN' or c.synced or age_band_of(me()) = 'TEEN' or c.mutual > 0)
  order by c.by_code desc, c.synced desc, c.mutual desc, c.name
  limit greatest(1, least(coalesce(lim, 30), 50))
$$;

-- One person's posts that I'm allowed to see, newest first, for their profile page (feed() is about my area and my syncs).
create or replace function public.posts_by(p_author uuid, before timestamptz default now(), lim int default 30)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.author_id, a.name, a.short_code, p.listing_id, l.title, p.body, p.media, p.visibility, p.area, p.up, p.down, p.comments,
         (select v.vote from post_votes v where v.post_id = p.id and v.profile_id = me()), p.created_at, synced(me(), p.author_id)
  from posts p join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
  where p.author_id = p_author and p.listing_id is null and p.created_at < coalesce(before, now()) and can_see_post(p)
  order by p.created_at desc
  limit greatest(1, least(coalesce(lim, 30), 100))
$$;

-- ---------- 1. reports ----------

create table if not exists public.reports (
  id           uuid primary key default public.uuid_v7(),
  reporter_id  uuid not null references public.profiles on delete cascade,
  target_kind  text not null check (target_kind in ('POST', 'COMMENT', 'MOMENT', 'MESSAGE', 'PROFILE')),
  target_id    uuid not null,
  target_owner uuid references public.profiles on delete set null,     -- who posted it (or the person reported)
  reason       text not null check (reason in ('SPAM', 'HARASSMENT', 'HATE', 'NUDITY', 'VIOLENCE', 'SELF_HARM', 'CHILD_SAFETY', 'SCAM', 'IMPERSONATION', 'OTHER')),
  detail       text not null default '' check (length(detail) <= 500),
  status       text not null default 'OPEN' check (status in ('OPEN', 'ACTIONED', 'DISMISSED')),
  action       text check (action in ('REMOVED', 'BANNED', 'NONE')),
  reviewed_by  uuid references public.profiles on delete set null,
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now(),
  unique (reporter_id, target_kind, target_id)
);
create index if not exists reports_open_idx on public.reports (created_at) where status = 'OPEN';
create index if not exists reports_target_idx on public.reports (target_kind, target_id);
alter table public.reports enable row level security;
drop policy if exists reports_read on public.reports;
create policy reports_read on public.reports for select to authenticated using (reporter_id = (select public.me()) or (select public.is_staff()));
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;

-- File a report. The reporter must be able to see what they report (so nobody reports by guessing ids). Reporting the same thing twice is a
-- no-op. A person reported for CHILD_SAFETY or SELF_HARM goes to the top of the staff queue (ordering in report_queue).
create or replace function public.report_content(p_kind text, p_target uuid, p_reason text, p_detail text default '') returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); owner uuid; rid uuid; k text := upper(p_kind);
begin
  if my is null then raise exception 'not signed in'; end if;
  owner := case k
    when 'POST'    then (select p.author_id from posts p where p.id = p_target and can_see_post(p))
    when 'COMMENT' then (select c.author_id from post_comments c join posts p on p.id = c.post_id where c.id = p_target and can_see_post(p))
    when 'MOMENT'  then (select m.author_id from moments m where m.id = p_target)
    when 'MESSAGE' then (select m.sender_id from messages m where m.id = p_target and is_member(m.conversation_id))
    when 'PROFILE' then (select p.id from profiles p where p.id = p_target)
  end;
  if owner is null then raise exception 'nothing to report: it was removed or you can''t see it'; end if;
  if owner = my then raise exception 'you can''t report yourself'; end if;
  insert into reports (reporter_id, target_kind, target_id, target_owner, reason, detail)
  values (my, k, p_target, owner, upper(p_reason), left(coalesce(btrim(p_detail), ''), 500))
  on conflict (reporter_id, target_kind, target_id) do nothing
  returning id into rid;
  return coalesce(rid, (select id from reports where reporter_id = my and target_kind = k and target_id = p_target));
end $$;

-- Staff: the open queue, most urgent first, with how many people reported the same thing.
create or replace function public.report_queue(lim int default 50)
returns table (id uuid, target_kind text, target_id uuid, target_owner uuid, owner_name text, reason text, detail text, reporters int, created_at timestamptz, preview text)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.target_kind, r.target_id, r.target_owner, o.name, r.reason, r.detail,
         (select count(*)::int from reports x where x.target_kind = r.target_kind and x.target_id = r.target_id and x.status = 'OPEN'),
         r.created_at,
         left(case r.target_kind
           when 'POST'    then (select body from posts where id = r.target_id)
           when 'COMMENT' then (select body from post_comments where id = r.target_id)
           when 'MOMENT'  then (select caption from moments where id = r.target_id)
           when 'MESSAGE' then (select body from messages where id = r.target_id)
           when 'PROFILE' then (select name || ' · ' || bio from profiles where id = r.target_id)
         end, 280)
  from reports r left join profiles o on o.id = r.target_owner
  where is_staff() and r.status = 'OPEN'
  order by (r.reason in ('CHILD_SAFETY', 'SELF_HARM')) desc, r.created_at
  limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- Staff decision on a report. REMOVE takes the content down (and closes every open report on it); BAN also suspends the owner;
-- DISMISS closes this report only.
create or replace function public.review_report(p_report uuid, p_action text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r public.reports; a text := upper(p_action);
begin
  if not is_staff() then raise exception 'staff only'; end if;
  select * into r from reports where id = p_report for update;
  if not found then raise exception 'no such report'; end if;
  if a = 'DISMISS' then
    update reports set status = 'DISMISSED', action = 'NONE', reviewed_by = me(), reviewed_at = now() where id = p_report; return;
  end if;
  if a not in ('REMOVE', 'BAN') then raise exception 'action must be REMOVE, BAN or DISMISS'; end if;
  case r.target_kind
    when 'POST'    then update posts set deleted_at = now() where id = r.target_id and deleted_at is null;
    when 'COMMENT' then delete from post_comments where id = r.target_id;
    when 'MOMENT'  then delete from moments where id = r.target_id;
    when 'MESSAGE' then update messages set deleted_at = now() where id = r.target_id and deleted_at is null;
    else null;
  end case;
  if a = 'BAN' and r.target_owner is not null then update profiles set status = 'BANNED' where id = r.target_owner and status = 'ACTIVE'; end if;
  update reports set status = 'ACTIONED', action = case a when 'BAN' then 'BANNED' else 'REMOVED' end, reviewed_by = me(), reviewed_at = now()
   where target_kind = r.target_kind and target_id = r.target_id and status = 'OPEN';
end $$;

-- ---------- account deletion ----------
-- delete_my_account from hardening_platform.sql, plus: the reports I filed, my date of birth and band, and the guardian consent. Reports about me stay (staff records; target_owner is cleared when the profile row goes, which it never does).
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); uid text; mine text[];
begin
  if my is null then raise exception 'not signed in'; end if;
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
  delete from reports where reporter_id = my;
  delete from guardian_consents where profile_id = my;
  delete from profile_safety where profile_id = my;
  update profiles set name = '', bio = '', area = '', photo_url = null, home = null, status = 'DELETED', auth_uid = 'deleted:' || id::text where id = my;
end $$;

-- ---------- grants ----------
revoke execute on function public.guard_minor_settings(), public.guard_minor_post() from public, anon, authenticated;
-- Only server functions ask for someone's band; exposing these to signed-in callers would let anyone look up who is a minor.
revoke execute on function public.age_band_of(uuid), public.is_minor(uuid) from public, anon, authenticated;
revoke execute on function public.set_birth_date(date), public.my_safety(), public.record_guardian_consent(text, text, text),
                           public.report_content(text, uuid, text, text), public.report_queue(int), public.review_report(uuid, text),
                           public.suggest_people(double precision, double precision, int), public.delete_my_account(),
                           public.search_people(text, int), public.posts_by(uuid, timestamptz, int) from public, anon;
grant execute on function public.set_birth_date(date), public.my_safety(), public.record_guardian_consent(text, text, text),
                          public.report_content(text, uuid, text, text), public.report_queue(int), public.review_report(uuid, text),
                          public.suggest_people(double precision, double precision, int), public.delete_my_account(),
                          public.search_people(text, int), public.posts_by(uuid, timestamptz, int) to authenticated;
