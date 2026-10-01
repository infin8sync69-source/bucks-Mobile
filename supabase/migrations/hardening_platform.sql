-- Bucks hardening: platform, privacy, storage and data hygiene (audit items P1-P11 and P14).
-- Apply LAST, after schema.sql and every other migration (supabase/apply_all.sh does). Idempotent: functions are "or replace", triggers
-- and policies are dropped and re-created, constraints are dropped and re-added NOT VALID (new and edited rows are checked at once, old
-- rows are only reported: the WARNING lines this file prints are the clean-up list), and one-time clean-ups only touch rows that still need them.
-- Tests: supabase/tests/hardening_platform_scenarios.sql (each item starts as an exploit) and supabase/tests/catalog_assertions.sql.
--
--   P1   suggest_people is no longer a location oracle (both homes are snapped to a ~2 km grid before measuring)
--   P2   server-managed fields on insert (profiles, messages, posts, moments), verified phone, UPI link shape
--   P3   posts and moments keep a ~500 m grid position, never the exact GPS fix
--   P4   view_moment precedence bug, reaction size, blocks in interaction notifications, one pending invite per person
--   P5   blocked_between only answers for the caller
--   P6   storage: chat type allow-list and per-uploader change/delete, evidence documents are immutable, path-stealing closed
--   P7   JSON shape checks so one hostile row cannot crash every viewer
--   P8   hidden (not LIVE) listings publish, take applications and post nothing
--   P9   re-review when a LIVE listing moves or changes category; plates normalised and unique
--   P10  device token cap and text length limits
--   P11  delete_my_account removes what it should and queues storage files for removal
--   P14  search radius and limit caps
--
-- Behaviour the current app survives but a newer app should reflect (see the deploy notes in the hand-off):
--   * editing the category or location of a LIVE listing puts it back in review (it disappears from search until re-approved);
--   * a PENDING listing can no longer post as itself; a not-LIVE listing's job cannot take applications;
--   * suggest_people distances come in 2 km steps between the ~2 km grid cells of the caller's stored home and the other person's;
--   * a reaction to a moment is at most 16 characters.
set search_path = public, extensions;
set client_min_messages = warning;   -- hide the "does not exist, skipping" noise of the drop-if-exists lines; the clean-up warnings below still show

-- ---------- helpers ----------

-- The ~500 m grid used for every position that other people can read (0.005 degrees is 555 m north-south, less east-west).
-- Snapping keeps a valid geography point, so every radius filter keeps working; it only makes the stored point coarse.
create or replace function public.snap_grid(g geography) returns geography language sql immutable set search_path = public, extensions as $$
  select case when g is null then null else st_snaptogrid(g::geometry, 0.005)::geography end
$$;

-- A uuid from text, or null when the text is not one (a policy must not fail on a stray folder name).
create or replace function public.try_uuid(t text) returns uuid language sql immutable set search_path = public, extensions as $$
  select case when t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then t::uuid end
$$;

-- ---------- P5: blocked_between only answers for the caller ----------
-- It stays security definer (policies need to read blocks the caller cannot), but a caller can only ask about themselves, so it no longer
-- tells anyone whether two other people blocked each other. Every caller in the schema passes me() as one side.
create or replace function public.blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce(public.me() in (a, b), false)
     and exists (select 1 from blocks where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a))
$$;

-- ---------- P1: suggest_people ----------
-- Before: st_distance(p.home, geo(lat, lng)) for a point the caller chose, no cap on lim. Three calls from three known points with a large
-- lim gave every discoverable person's hidden home to a few metres. Then the reference became the caller's own stored home, rounded to 2 km
-- steps, but the caller owns that home (profiles_update lets anyone set it, and there is no rate limit): moving it along a line and watching
-- where the step flips finds the points exactly 3, 5, 7 ... km from the victim, and three such flips trilaterate the victim to about 13 m.
-- Now both homes are snapped to a 0.02 degree grid (about 2.2 km) before anything is measured, so the answer depends only on which grid
-- cell the other person's home is in, however the caller moves theirs: it shows which ~2 km cell someone lives in and nothing finer.
-- lat and lng stay in the signature so the app keeps working, and are ignored; distance_m is null when either side has no home; lim is
-- 1..50; equal candidates are ordered by mutual count, then distance step, then a hash of (me, candidate), never by exact distance.
create or replace function public.suggest_people(lat double precision, lng double precision, lim int default 20)
returns table (id uuid, name text, short_code text, area text, mutual int, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id)),
       here as (select st_snaptogrid(home::geometry, 0.02)::geography as g from profiles where id = me()),
       cand as (
         select p.id, p.name, p.short_code, p.area,
                (select count(*)::int from syncs s where s.status = 'ACCEPTED' and ((s.requester_id = p.id and s.addressee_id in (select f from mine)) or (s.addressee_id = p.id and s.requester_id in (select f from mine)))) as mutual,
                case when (select g from here) is null or p.home is null then null
                     else round(st_distance(st_snaptogrid(p.home::geometry, 0.02)::geography, (select g from here)) / 2000.0::double precision) * 2000.0::double precision end as step
         from profiles p
         where p.id <> me() and p.status = 'ACTIVE' and (select discoverable from settings_of(p.id))
           and p.id not in (select f from mine) and not blocked_between(me(), p.id)
           and not exists (select 1 from syncs s where s.requester_id = me() and s.addressee_id = p.id))
  select c.id, c.name, c.short_code, c.area, c.mutual, c.step
  from cand c
  order by c.mutual desc, c.step nulls last, md5(me()::text || c.id::text)
  limit greatest(1, least(coalesce(lim, 20), 50))
$$;

-- ---------- P2: server-managed fields on insert ----------
-- profiles: profile_guard only covers UPDATE, so a self-inserted row could carry a backdated created_at (defeating the 14-day rule for
-- recommenders), forged trust, a chosen Bucks ID or an old ID-card date. ensure_profile (security definer, not "authenticated") is unaffected.
create or replace function public.guard_profile_insert() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' then
    new.created_at := now(); new.trust_up := 0; new.trust_down := 0; new.status := 'ACTIVE';
    new.short_code := public.new_short_code(); new.id_issued_at := now();
  end if;
  return new;
end $$;
drop trigger if exists profile_insert_guard on public.profiles;
create trigger profile_insert_guard before insert on public.profiles for each row execute function public.guard_profile_insert();

-- messages, posts, moments: the clock and the edited/deleted markers belong to the server on insert (a future created_at pinned a post to the
-- top of the feed and a chat to the top of the inbox). Edits and deletes still go through the update guards.
create or replace function public.guard_insert_stamps() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' then
    new.created_at := now();
    if tg_table_name = 'messages' then new.edited_at := null; new.deleted_at := null;
    elsif tg_table_name = 'posts' then new.deleted_at := null; end if;
  end if;
  return new;
end $$;
drop trigger if exists message_stamp on public.messages;
create trigger message_stamp before insert on public.messages for each row execute function public.guard_insert_stamps();
drop trigger if exists post_stamp on public.posts;
create trigger post_stamp before insert on public.posts for each row execute function public.guard_insert_stamps();
drop trigger if exists moment_stamp on public.moments;
create trigger moment_stamp before insert on public.moments for each row execute function public.guard_insert_stamps();

-- ensure_profile from schema.sql: the phone comes from the verified sign-in token (Firebase puts phone_number in it) and the typed one is ignored
-- then; only when the token has no phone claim does the app's value stand. Name and phone are bounded.
create or replace function public.ensure_profile(p_name text, p_phone text default null) returns public.profiles
language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles; uid text := auth.jwt()->>'sub';
        ph text := coalesce(nullif(auth.jwt()->>'phone_number', ''), nullif(left(btrim(p_phone), 20), ''));
begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into p from profiles where auth_uid = uid;
  if not found then
    loop
      begin insert into profiles (auth_uid, name) values (uid, left(coalesce(p_name, ''), 80)) returning * into p; exit;
      exception when unique_violation then if exists (select 1 from profiles where auth_uid = uid) then select * into p from profiles where auth_uid = uid; exit; end if; end;  -- short_code clash: retry
    end loop;
  end if;
  insert into profile_private (profile_id, phone) values (p.id, ph) on conflict (profile_id) do update set phone = coalesce(excluded.phone, profile_private.phone);
  return p;
end $$;

-- profile_private: the owner may not rewrite the verified phone, and the payment link has to look like a UPI payment link. Legacy junk in
-- upi_uri that the owner did not touch is cleared the next time the row is written (so the check below can never block a sign-in).
create or replace function public.guard_profile_private() returns trigger language plpgsql set search_path = public, extensions as $$
declare v text := nullif(auth.jwt()->>'phone_number', '');
begin
  if current_user = 'authenticated' then
    if v is not null then new.phone := v;
    elsif tg_op = 'UPDATE' then new.phone := old.phone;
    else new.phone := null; end if;
  end if;
  new.upi_uri := nullif(btrim(new.upi_uri), '');
  if new.upi_uri ~* '^upi://pay\?' then new.upi_uri := 'upi://pay?' || substr(new.upi_uri, 11); end if;
  if tg_op = 'UPDATE' and new.upi_uri is not null and new.upi_uri is not distinct from old.upi_uri and (new.upi_uri !~ '^upi://pay\?' or length(new.upi_uri) > 500) then new.upi_uri := null; end if;
  return new;
end $$;
drop trigger if exists profile_private_guard on public.profile_private;
create trigger profile_private_guard before insert or update on public.profile_private for each row execute function public.guard_profile_private();

-- ---------- P3: posts and moments never keep the exact GPS fix ----------
-- LOCAL posts and moments are readable by every signed-in person (only feed() applies the radius), so the stored point is the ~500 m grid
-- point, whatever the app sends. Existing rows are snapped once here (a moment lives 24 hours, posts are the ones that matter).
create or replace function public.snap_location() returns trigger language plpgsql set search_path = public, extensions as $$
begin new.location := public.snap_grid(new.location); return new; end $$;
drop trigger if exists snap_location on public.posts;
create trigger snap_location before insert or update of location on public.posts for each row execute function public.snap_location();
drop trigger if exists snap_location on public.moments;
create trigger snap_location before insert or update of location on public.moments for each row execute function public.snap_location();
update public.posts set location = public.snap_grid(location) where location is not null and not st_equals(location::geometry, public.snap_grid(location)::geometry);
update public.moments set location = public.snap_grid(location) where location is not null and not st_equals(location::geometry, public.snap_grid(location)::geometry);

-- ---------- P4: moments, interaction notifications, invites ----------
-- view_moment: "not found or not can_see_moment(..) and audience <> 'LOCAL'" let every LOCAL moment through (expired, blocked, never shown).
-- A viewer now always has to be able to see the moment (open_moments records nearby LOCAL moments, so the normal flow is unchanged).
create or replace function public.view_moment(p_moment uuid, p_reaction text default null) returns void language plpgsql security definer set search_path = public, extensions as $$
declare m moments; r text := nullif(btrim(p_reaction), '');
begin
  if length(r) > 16 then raise exception 'a reaction is one emoji, at most 16 characters'; end if;
  select * into m from moments where id = p_moment;
  if not found or not can_see_moment(m, null, null) then raise exception 'not available'; end if;
  if m.author_id = me() then return; end if;
  insert into moment_views (moment_id, viewer_id, reaction) values (p_moment, me(), r)
    on conflict (moment_id, viewer_id) do update set reaction = coalesce(excluded.reaction, moment_views.reaction);
end $$;

-- interactions.sql notifications, plus: nobody is told about an action by someone they blocked (or who blocked them), and one person changing a
-- moment reaction again and again rings its author once an hour, not every time.
create or replace function public.note_comment() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare p posts; who text; m uuid;
begin
  select * into p from posts where id = new.post_id;
  if not found or p.deleted_at is not null then return null; end if;
  who := pname(new.author_id);
  if p.author_id <> new.author_id and not blocked_between(new.author_id, p.author_id) then
    perform push_note(p.author_id, 'COMMENT', who || ' commented on your post', new.body, 'post/' || p.id);
  end if;
  for m in select distinct author_id from post_comments where post_id = new.post_id and author_id not in (new.author_id, p.author_id) loop
    if not blocked_between(new.author_id, m) then
      perform push_note(m, 'COMMENT_THREAD', who || ' also commented on a post you commented on', new.body, 'post/' || p.id);
    end if;
  end loop;
  return null;
end $$;

create or replace function public.note_vote() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare p posts; t text;
begin
  if new.vote <> 1 or (tg_op = 'UPDATE' and old.vote = 1) then return null; end if;
  select * into p from posts where id = new.post_id;
  if not found or p.deleted_at is not null or p.author_id = new.profile_id or blocked_between(new.profile_id, p.author_id) then return null; end if;
  t := pname(new.profile_id) || ' recommended your post';
  if exists (select 1 from notifications where profile_id = p.author_id and kind = 'POST_LIKE' and route = 'post/' || p.id and title = t and created_at > now() - interval '1 day') then return null; end if;
  perform push_note(p.author_id, 'POST_LIKE', t, left(p.body, 120), 'post/' || p.id);
  return null;
end $$;

create or replace function public.note_reaction() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare a uuid; who text;
begin
  if coalesce(new.reaction, '') = '' or (tg_op = 'UPDATE' and old.reaction is not distinct from new.reaction) then return null; end if;
  select author_id into a from moments where id = new.moment_id;
  if a is null or a = new.viewer_id or blocked_between(new.viewer_id, a) then return null; end if;
  who := pname(new.viewer_id);
  -- Changing a reaction over and over must not ring the author each time: one note per person per hour.
  if exists (select 1 from notifications where profile_id = a and kind = 'MOMENT_REACTION' and starts_with(title, who || ' reacted ') and created_at > now() - interval '1 hour') then return null; end if;
  perform push_note(a, 'MOMENT_REACTION', who || ' reacted ' || new.reaction || ' to your moment', 'Your moment is up for 24 hours.', 'feed');
  return null;
end $$;

-- invite from schema.sql, plus: not across a block, and one pending invite per person per listing or vehicle (each one is a notification).
-- Pending duplicates that exist today keep the newest and revoke the rest, so the unique index can be built.
update public.invites i set status = 'REVOKED'
  from (select id, row_number() over (partition by coalesce(listing_id, vehicle_id), invitee_id order by created_at desc, id desc) as n
        from public.invites where status = 'PENDING') d
  where i.id = d.id and d.n > 1;
create unique index if not exists invites_one_pending on public.invites (coalesce(listing_id, vehicle_id), invitee_id) where status = 'PENDING';

create or replace function public.invite(p_listing uuid, p_vehicle uuid, p_short_code text, p_role text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare invitee uuid; inv uuid;
begin
  if p_listing is not null and coalesce(listing_role(p_listing), '') <> 'OWNER' then raise exception 'only the owner can invite'; end if;
  if p_vehicle is not null and coalesce(vehicle_role(p_vehicle), '') <> 'OWNER' then raise exception 'only the owner can invite'; end if;
  if p_vehicle is not null and p_role <> 'ADMIN' then raise exception 'vehicles only have admins'; end if;
  select id into invitee from profiles where short_code = upper(trim(p_short_code)) and status = 'ACTIVE';
  if invitee is null then raise exception 'no one has that Bucks ID'; end if;
  if invitee = me() then raise exception 'you already own this'; end if;
  if blocked_between(me(), invitee) then raise exception 'you cannot invite this person'; end if;
  if exists (select 1 from invites where invitee_id = invitee and status = 'PENDING' and listing_id is not distinct from p_listing and vehicle_id is not distinct from p_vehicle) then
    raise exception 'this person already has a pending invite';
  end if;
  begin
    insert into invites (listing_id, vehicle_id, inviter_id, invitee_id, role) values (p_listing, p_vehicle, me(), invitee, p_role) returning id into inv;
  exception when unique_violation then raise exception 'this person already has a pending invite';
  end;
  return inv;
end $$;

-- ---------- P6: storage ----------
do $$ begin
  if to_regclass('storage.objects') is not null and to_regclass('storage.buckets') is not null then
    -- (a) chat: the bucket insert in schema.sql uses "on conflict do nothing", so an existing bucket never got a type list. Set it now.
    -- Allowed: photos, mp4 video, pdf, plain text, docx/xlsx/pptx. Not allowed: apk, html, js, svg, zip, unknown binaries.
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
      ('chat', 'chat', false, 26214400, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'application/pdf', 'text/plain',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'])
    on conflict (id) do update set allowed_mime_types = excluded.allowed_mime_types, file_size_limit = excluded.file_size_limit, public = false;
  end if;
end $$;

-- True while a file is approved evidence: a VERIFIED listing document, or a document of a vehicle Bucks has approved (ACTIVE). The vehicle
-- side reads the paths the way guard_vehicle does (docs is a list of {kind, path} objects, or of bare path strings). Replacing a vehicle
-- document sends the vehicle back to PENDING first (guard_vehicle), so the app's replace flow (new file, update docs, delete the old file)
-- still works: by the time the old file goes, the vehicle is no longer ACTIVE and no longer lists it.
create or replace function public.doc_path_locked(p text) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.listing_documents d where d.path = p and d.status = 'VERIFIED')
      or exists (select 1 from public.vehicles v, jsonb_array_elements(case when jsonb_typeof(v.docs) = 'array' then v.docs else '[]'::jsonb end) e
                 where v.status = 'ACTIVE' and coalesce(e ->> 'path', e #>> '{}') = p)
$$;

do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists bucks_own_folder on storage.objects;
    drop policy if exists bucks_own_read on storage.objects;
    drop policy if exists bucks_own_insert on storage.objects;
    drop policy if exists bucks_own_update on storage.objects;
    drop policy if exists bucks_own_delete on storage.objects;
    drop policy if exists bucks_chat on storage.objects;
    drop policy if exists bucks_chat_read on storage.objects;
    drop policy if exists bucks_chat_insert on storage.objects;
    drop policy if exists bucks_chat_update on storage.objects;
    drop policy if exists bucks_chat_delete on storage.objects;
    drop policy if exists bucks_moments_read on storage.objects;
    drop policy if exists bucks_posts_read on storage.objects;

    -- Your own folder in avatars, posts, moments and docs. (b) docs: once a listing document is VERIFIED, or a vehicle is ACTIVE, its file cannot
    -- be overwritten or removed (the row would stay approved while the paper changed); replacing the document sends the row back to PENDING and
    -- frees the old file.
    create policy bucks_own_read on storage.objects for select to authenticated
      using (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text);
    create policy bucks_own_insert on storage.objects for insert to authenticated
      with check (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text);
    create policy bucks_own_update on storage.objects for update to authenticated
      using (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text and (bucket_id <> 'docs' or not public.doc_path_locked(name)))
      with check (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text and (bucket_id <> 'docs' or not public.doc_path_locked(name)));
    create policy bucks_own_delete on storage.objects for delete to authenticated
      using (bucket_id in ('avatars', 'posts', 'moments', 'docs') and (storage.foldername(name))[1] = public.me()::text and (bucket_id <> 'docs' or not public.doc_path_locked(name)));

    -- (a) chat files: members upload and read; only the uploader changes or removes a file. Storage stamps the uploader's token subject on the
    -- object (owner_id, or owner where the subject is a uuid); to_jsonb keeps this working whichever of the two columns exists.
    create policy bucks_chat_read on storage.objects for select to authenticated
      using (bucket_id = 'chat' and public.is_member(public.try_uuid((storage.foldername(name))[1])));
    create policy bucks_chat_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'chat' and public.is_member(public.try_uuid((storage.foldername(name))[1])));
    create policy bucks_chat_update on storage.objects for update to authenticated
      using (bucket_id = 'chat' and public.is_member(public.try_uuid((storage.foldername(name))[1]))
             and (select auth.jwt() ->> 'sub') in (to_jsonb(objects) ->> 'owner_id', to_jsonb(objects) ->> 'owner'))
      with check (bucket_id = 'chat' and public.is_member(public.try_uuid((storage.foldername(name))[1]))
             and (select auth.jwt() ->> 'sub') in (to_jsonb(objects) ->> 'owner_id', to_jsonb(objects) ->> 'owner'));
    create policy bucks_chat_delete on storage.objects for delete to authenticated
      using (bucket_id = 'chat' and public.is_member(public.try_uuid((storage.foldername(name))[1]))
             and (select auth.jwt() ->> 'sub') in (to_jsonb(objects) ->> 'owner_id', to_jsonb(objects) ->> 'owner'));

    -- (c) Moment and post media are readable by whoever can see a live moment / visible post that uses the file, and only if the row's author owns
    -- the folder the file is in. A row that merely names someone else's path (any signed-in user can write one) opens nothing.
    create policy bucks_moments_read on storage.objects for select to authenticated
      using (bucket_id = 'moments' and exists (select 1 from public.moments m
               where m.media_path = name and (storage.foldername(name))[1] = m.author_id::text and public.can_see_moment(m, null, null)));
    create policy bucks_posts_read on storage.objects for select to authenticated
      using (bucket_id = 'posts' and exists (select 1 from public.posts p
               where public.can_see_post(p) and (storage.foldername(name))[1] = p.author_id::text
                 and p.media @> jsonb_build_array(jsonb_build_object('path', name))));
  end if;
end $$;

-- ---------- P7: JSON that the app reads with jsonPrimitive must have the right shape ----------
-- A message attachment is an object with string path, name, mime and a numeric size (width and height numeric when present); post media is an
-- array of objects with a string path and mime. Anything else crashes the feed or chat of everyone who loads the row.
create or replace function public.attachment_ok(j jsonb) returns boolean language sql immutable set search_path = public, extensions as $$
  select j is null or coalesce(
    jsonb_typeof(j) = 'object'
    and jsonb_typeof(j -> 'path') = 'string' and length(j ->> 'path') between 1 and 300
    and jsonb_typeof(j -> 'name') = 'string' and length(j ->> 'name') <= 300
    and jsonb_typeof(j -> 'mime') = 'string' and length(j ->> 'mime') <= 100
    and jsonb_typeof(j -> 'size') = 'number'
    and (jsonb_typeof(j -> 'width') is null or jsonb_typeof(j -> 'width') = 'number')
    and (jsonb_typeof(j -> 'height') is null or jsonb_typeof(j -> 'height') = 'number'), false)
$$;
create or replace function public.post_media_ok(j jsonb) returns boolean language sql immutable set search_path = public, extensions as $$
  select case when jsonb_typeof(j) <> 'array' then false
    else jsonb_array_length(j) <= 10 and not exists (
      select 1 from jsonb_array_elements(j) e
      where jsonb_typeof(e) <> 'object' or jsonb_typeof(e -> 'path') is distinct from 'string' or jsonb_typeof(e -> 'mime') is distinct from 'string'
         or length(e ->> 'path') not between 1 and 300 or length(e ->> 'mime') > 100) end
$$;

-- ---------- P8: a listing that is not LIVE publishes, hires and posts nothing ----------
-- jobs_read / apps_apply / job_page / start_applicant_chat / the feed all let a PENDING, SUSPENDED or deleted-owner listing act in public.
drop policy if exists jobs_read on public.jobs;
create policy jobs_read on public.jobs for select to authenticated
  using ((open and exists (select 1 from public.listings l where l.id = listing_id and l.status = 'LIVE')) or public.listing_role(listing_id) is not null);
drop policy if exists apps_apply on public.applications;
create policy apps_apply on public.applications for insert to authenticated
  with check (applicant_id = public.me() and status = 'APPLIED'
              and exists (select 1 from public.jobs j join public.listings l on l.id = j.listing_id where j.id = job_id and j.open and l.status = 'LIVE'));

-- check_application from jobs.sql, plus the listing has to be LIVE.
create or replace function public.check_application() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare j public.jobs; n int;
begin
  select * into j from public.jobs where id = new.job_id;
  if j.id is null then raise exception 'this job no longer exists'; end if;
  if not j.open then raise exception 'this job is closed'; end if;
  if not exists (select 1 from public.listings where id = j.listing_id and status = 'LIVE') then raise exception 'this job is not open for applications'; end if;
  if public.can_manage_listing(j.listing_id) then raise exception 'you cannot apply to a job at your own listing'; end if;
  new.skill_listing_ids := (select coalesce(array_agg(distinct s), '{}') from unnest(new.skill_listing_ids) s);
  select count(*) into n from public.listings where id = any(new.skill_listing_ids) and kind = 'SKILL' and owner_id = new.applicant_id;
  if n <> coalesce(array_length(new.skill_listing_ids, 1), 0) then raise exception 'you can only apply with your own skill profiles'; end if;
  return new;
end $$;

-- job_page from jobs.sql: open jobs of LIVE listings for everyone; the listing's team and people who applied always see it.
create or replace function public.job_page(p_job uuid)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, description text, pay text, job_type text, open boolean, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.description, j.pay, j.job_type, j.open, j.created_at
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.id = p_job and public.me() is not null
    and ((j.open and l.status = 'LIVE') or public.can_manage_listing(j.listing_id) or exists (select 1 from public.applications a where a.job_id = j.id and a.applicant_id = public.me()))
$$;

-- start_applicant_chat from jobs.sql, plus the listing has to be LIVE.
create or replace function public.start_applicant_chat(p_application uuid) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare a public.applications; l uuid; k text; c uuid;
begin
  if public.me() is null then raise exception 'not signed in'; end if;
  select * into a from public.applications where id = p_application;
  if a.id is not null then select listing_id into l from public.jobs where id = a.job_id; end if;
  if a.id is null or l is null or not public.can_manage_listing(l) or not exists (select 1 from public.listings x where x.id = l and x.status = 'LIVE') then
    raise exception 'this application is not available';
  end if;
  if a.applicant_id = public.me() then raise exception 'that is you'; end if;
  if a.status = 'WITHDRAWN' then raise exception 'they withdrew this application'; end if;
  if public.blocked_between(public.me(), a.applicant_id) then raise exception 'you cannot message this person'; end if;
  k := least(public.me()::text, a.applicant_id::text) || ':' || greatest(public.me()::text, a.applicant_id::text);
  select id into c from public.conversations where direct_key = k;
  if c is not null then return c; end if;
  insert into public.conversations (kind, direct_key, created_by) values ('DIRECT', k, public.me()) returning id into c;
  insert into public.conversation_members (conversation_id, profile_id) values (c, public.me()), (c, a.applicant_id);
  return c;
end $$;

-- can_see_post from schema.sql, plus a post made as a listing is only seen while that listing is LIVE (or by its team); this is what feed()
-- and the posts and storage policies all ask. posts_write also stops a not-LIVE listing from posting as itself.
create or replace function public.can_see_post(p public.posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.deleted_at is null and not blocked_between(me(), p.author_id)
         and (p.listing_id is null or exists (select 1 from listings l where l.id = p.listing_id and (l.status = 'LIVE' or listing_role(l.id) is not null)))
         and (p.author_id = me() or p.visibility in ('PUBLIC', 'LOCAL') or (p.visibility = 'SYNCED' and synced(me(), p.author_id)))
$$;
drop policy if exists posts_write on public.posts;
create policy posts_write on public.posts for insert to authenticated
  with check (author_id = public.me() and up = 0 and down = 0 and comments = 0
              and (listing_id is null or (public.can_manage_listing(listing_id) and exists (select 1 from public.listings l where l.id = listing_id and l.status = 'LIVE'))));

-- ---------- P9: a LIVE listing that moves or changes category is re-reviewed; plates are normalised ----------
-- guard_listing locks status, trust, owner and kind; location and category were free, which let a LIVE listing carry its local recommendations
-- to another place, or change what it sells, without anyone looking. From the app (role "authenticated") such an edit now sends it back to
-- PENDING and offline; a service change is still refused by listing_service_rules. Title and description stay free. Runs after listing_guard and
-- before listing_service (triggers fire by name).
create or replace function public.guard_listing_reverify() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and old.status = 'LIVE'
     and (new.category is distinct from old.category or st_astext(new.location) is distinct from st_astext(old.location)) then
    new.status := 'PENDING'; new.online := false;
  end if;
  return new;
end $$;
drop trigger if exists listing_reverify on public.listings;
create trigger listing_reverify before update on public.listings for each row execute function public.guard_listing_reverify();

-- Recommendations only count where the listing is: when it moves, the ones whose recommender's home or standing point no longer lies within
-- the recommend radius of the new place are dropped (recommend() enforced both at the time). Otherwise the cap could be carried anywhere.
create or replace function public.prune_recommendations() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.location is null then
    delete from recommendations where listing_id = new.id;
  else
    delete from recommendations r using profiles p
     where r.listing_id = new.id and p.id = r.recommender_id
       and not (st_dwithin(new.location, r.at_location, setting('recommend_radius_m')) and p.home is not null and st_dwithin(new.location, p.home, setting('recommend_radius_m')));
  end if;
  return null;
end $$;
drop trigger if exists listing_prune_recs on public.listings;
create trigger listing_prune_recs after update of location on public.listings for each row
  when (st_astext(old.location) is distinct from st_astext(new.location)) execute function public.prune_recommendations();

-- Plates: upper case letters and digits only (spaces, dashes and dots dropped), so "ka 01-ab 1234" and "KA01AB1234" are one vehicle. guard_vehicle
-- (manage.sql) already sends a checked vehicle back to PENDING when its plate, type or documents change; this trigger is named to fire before it,
-- so retyping the same plate in another case is not a change. Existing plates are normalised and a unique index on the normalised value is built,
-- but only when no two existing vehicles collapse to the same plate (otherwise a warning says so and nothing is touched).
create or replace function public.norm_plate(p text) returns text language sql immutable set search_path = public, extensions as $$
  select regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g')
$$;
create or replace function public.vehicle_normalise() returns trigger language plpgsql set search_path = public, extensions as $$
begin new.plate := public.norm_plate(new.plate); return new; end $$;
drop trigger if exists vehicle_a_normalise on public.vehicles;
create trigger vehicle_a_normalise before insert or update on public.vehicles for each row execute function public.vehicle_normalise();
do $$ begin
  if exists (select 1 from public.vehicles group by public.norm_plate(plate) having count(*) > 1) then
    raise warning 'vehicles: plates that differ only in case, spaces or dashes exist; plates were not normalised and the unique index was not built. Merge or delete the duplicates, then re-run this file.';
  else
    update public.vehicles set plate = public.norm_plate(plate) where plate <> public.norm_plate(plate);
    create unique index if not exists vehicles_plate_norm_key on public.vehicles (public.norm_plate(plate));
  end if;
end $$;

-- ---------- P10: device tokens ----------
-- A profile keeps at most 10 phones (the newest); notify sends one FCM call per token per event. The trigger is security definer because the
-- token that pushes the count over may have just been taken over from another person by register_device_token.
create or replace function public.device_token_cap() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from device_tokens where profile_id = new.profile_id and token in (
    select t.token from device_tokens t where t.profile_id = new.profile_id order by (t.token = new.token) desc, t.updated_at desc, t.token offset 10);
  return null;
end $$;
drop trigger if exists device_token_cap on public.device_tokens;
create trigger device_token_cap after insert or update of profile_id on public.device_tokens for each row execute function public.device_token_cap();

-- ---------- P11: delete_my_account ----------
-- Files cannot be removed from SQL, so the names of everything a person owns in storage are queued here and something with the service role
-- (an Edge Function on a schedule, or the app before it calls delete_my_account) has to delete them and then the queue rows. See supabase/README.md.
create table if not exists public.storage_cleanup (
  bucket    text not null,
  name      text not null,
  queued_at timestamptz not null default now(),
  primary key (bucket, name)
);
alter table public.storage_cleanup enable row level security;
revoke all on public.storage_cleanup from public, anon, authenticated;

-- delete_my_account from dispatch.sql, plus: the queue above, and deletion of everything that pointed at the person and would only have gone
-- with a real delete of the profile row (which never happens, the row is anonymised): contact links in both directions, settings, blocks, close
-- friends, moment views, mutes and access, device tokens, job applications, invites, vehicles and seats, notifications, the places they stood
-- when recommending, staff standing; and the personal free text of their listings (business names stay, buyers' order history names them).
-- Not touched: trips, orders and reviews (the other party's records, as decided in dispatch.sql).
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
  -- What I said and shared goes too: posts (their votes and comments cascade), moments, my comments and votes elsewhere,
  -- my messages (blanked like "delete message", so the other side sees "Message deleted") and my place in every chat.
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
  update profiles set name = '', bio = '', area = '', photo_url = null, home = null, status = 'DELETED', auth_uid = 'deleted:' || id::text where id = my;
end $$;

-- ---------- P14: search radius and limit ----------
-- search_listings from services.sql and jobs_near from jobs.sql with the radius capped at 50 km and the limit at 100; feed() (schema.sql) gets
-- the same caps, since an unbounded radius returns every LOCAL post that exists.
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null,
                                                  lim int default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int,
               details jsonb, distance_m double precision, matched_item text, min_price int)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         (select i.name from items i where i.listing_id = l.id and term.t is not null and i.name ilike '%' || term.t || '%' order by i.price limit 1) as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock) as min_price
  from listings l, here, term
  where l.status = 'LIVE'
    and (kinds is null or l.kind = any(kinds))
    and (services is null or l.service = any(services))
    and l.location is not null and st_dwithin(l.location, here.g, least(greatest(coalesce(radius_m, 10000), 0), 50000))
    and (term.t is null or l.search @@ websearch_to_tsquery('simple', term.t) or l.title % term.t or l.category ilike '%' || term.t || '%'
         or exists (select 1 from items i where i.listing_id = l.id and i.name ilike '%' || term.t || '%'))
  order by (l.online) desc,
           (case when term.t is null then 0 else ts_rank(l.search, websearch_to_tsquery('simple', term.t)) + similarity(l.title, term.t) end) desc,
           (l.trust_up - l.trust_down) desc, distance_m
  limit greatest(1, least(coalesce(lim, 40), 100))
$$;

create or replace function public.jobs_near(lat double precision, lng double precision, radius_m int default 15000)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, pay text, job_type text, created_at timestamptz, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.pay, j.job_type, j.created_at, st_distance(l.location, public.geo(lat, lng)) as distance_m
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.open and l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, public.geo(lat, lng), least(greatest(coalesce(radius_m, 15000), 0), 50000))
  order by distance_m, j.created_at desc
  limit 100
$$;

create or replace function public.feed(lat double precision, lng double precision, radius_m int default 5000, before timestamptz default now(), lim int default 30)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.author_id, a.name, a.short_code, p.listing_id, l.title, p.body, p.media, p.visibility, p.area, p.up, p.down, p.comments,
         (select v.vote from post_votes v where v.post_id = p.id and v.profile_id = me()), p.created_at, synced(me(), p.author_id)
  from posts p join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
  where p.created_at < before and can_see_post(p)
    and (p.author_id = me() or synced(me(), p.author_id)
         or (p.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = p.listing_id))
         or p.visibility = 'PUBLIC'
         or (p.visibility = 'LOCAL' and p.location is not null and st_dwithin(p.location, geo(lat, lng), least(greatest(coalesce(radius_m, 5000), 0), 50000))))
  order by p.created_at desc
  limit greatest(1, least(coalesce(lim, 30), 100))
$$;

-- ---------- constraints (NOT VALID: every new and edited row is checked, existing rows are only reported) ----------
-- Dropped and re-added on each run, so this file is the single source of the limits. After cleaning any rows the warnings name, make one
-- permanent with:  alter table public.<table> validate constraint <name>;
do $$
declare c record; n bigint;
begin
  for c in select * from (values
    ('profiles',        'profiles_name_len',          'length(name) <= 80'),
    ('profiles',        'profiles_bio_len',           'length(bio) <= 300'),
    ('profiles',        'profiles_area_len',          'length(area) <= 80'),
    ('profile_private', 'profile_private_upi_ok',     $e$upi_uri is null or (upi_uri ~ '^upi://pay\?' and length(upi_uri) <= 500)$e$),
    ('listings',        'listings_title_len',         'length(title) <= 100'),
    ('listings',        'listings_description_len',   'length(description) <= 2000'),
    ('messages',        'messages_body_len',          'length(body) <= 4000'),
    ('messages',        'messages_attachment_ok',     'public.attachment_ok(attachment)'),
    ('posts',           'posts_body_len',             'length(body) <= 5000'),
    ('posts',           'posts_media_ok',             'public.post_media_ok(media)'),
    ('post_comments',   'post_comments_body_len',     'length(body) <= 1000'),
    ('reviews',         'reviews_comment_len',        'length(comment) <= 1000'),
    ('applications',    'applications_note_len',      'length(note) <= 1000'),
    ('jobs',            'jobs_title_len',             'length(title) <= 100'),
    ('jobs',            'jobs_description_len',       'length(description) <= 2000'),
    ('moments',         'moments_caption_len',        'length(caption) <= 200'),
    ('moments',         'moments_media_path_len',     'length(media_path) between 1 and 300'),
    ('moment_views',    'moment_views_reaction_len',  'reaction is null or length(reaction) <= 16'),
    ('conversations',   'conversations_title_len',    'title is null or length(title) <= 80'),
    ('device_tokens',   'device_tokens_token_len',    'length(token) between 16 and 4096'),
    ('device_tokens',   'device_tokens_platform_len', 'length(platform) <= 20')
  ) v(t, n, e) loop
    execute format('alter table public.%I drop constraint if exists %I', c.t, c.n);
    execute format('alter table public.%I add constraint %I check (%s) not valid', c.t, c.n, c.e);
    execute format('select count(*) from public.%I where not coalesce(%s, true)', c.t, c.e) into n;
    if n > 0 then raise warning '% existing row(s) of % break % (left as they are: fix them, then validate the constraint)', n, c.t, c.n; end if;
  end loop;
end $$;

-- ---------- grants ----------
-- Everything below that the app calls, or that a policy, constraint or trigger runs as the signed-in person, is executable by "authenticated"
-- only. Trigger bodies and internal helpers are executable by nobody through the API.
revoke execute on function public.snap_grid(geography), public.try_uuid(text), public.attachment_ok(jsonb), public.post_media_ok(jsonb), public.norm_plate(text),
  public.doc_path_locked(text), public.blocked_between(uuid, uuid), public.suggest_people(double precision, double precision, int), public.ensure_profile(text, text),
  public.view_moment(uuid, text), public.invite(uuid, uuid, text, text), public.job_page(uuid), public.start_applicant_chat(uuid), public.can_see_post(public.posts),
  public.delete_my_account(), public.search_listings(text, double precision, double precision, int, text[], int, text[]),
  public.jobs_near(double precision, double precision, int), public.feed(double precision, double precision, int, timestamptz, int) from public, anon;
grant execute on function public.snap_grid(geography), public.try_uuid(text), public.attachment_ok(jsonb), public.post_media_ok(jsonb), public.norm_plate(text),
  public.doc_path_locked(text), public.blocked_between(uuid, uuid), public.suggest_people(double precision, double precision, int), public.ensure_profile(text, text),
  public.view_moment(uuid, text), public.invite(uuid, uuid, text, text), public.job_page(uuid), public.start_applicant_chat(uuid), public.can_see_post(public.posts),
  public.delete_my_account(), public.search_listings(text, double precision, double precision, int, text[], int, text[]),
  public.jobs_near(double precision, double precision, int), public.feed(double precision, double precision, int, timestamptz, int) to authenticated;
revoke execute on function public.guard_profile_insert(), public.guard_insert_stamps(), public.guard_profile_private(), public.snap_location(),
  public.note_comment(), public.note_vote(), public.note_reaction(), public.check_application(), public.guard_listing_reverify(), public.prune_recommendations(),
  public.vehicle_normalise(), public.device_token_cap() from public, anon, authenticated;

reset client_min_messages;
