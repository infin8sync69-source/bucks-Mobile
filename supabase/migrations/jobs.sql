-- Bucks: jobs feature (businesses post jobs, people apply with their skill profiles).
-- Adds to supabase/schema.sql; safe to re-run. Tables `jobs` and `applications` and their
-- row-level security already live in schema.sql. This file adds:
--   jobs_near(lat, lng, radius_m)  open jobs of LIVE listings near a point, nearest first
--   jobs_with_counts               jobs + application counts (security_invoker, so managers see everyone's)
--   job_page(p_job)                one job with its business, readable by managers, applicants and (while open) everyone
--   my_applications()              my applications with job and business titles, even after the job closed
--   guard_application()            the rules for changing an application (who may withdraw, who may decide)
--   check_application()            the rules for applying (not to your own listing, only with your own skill profiles)
--   start_applicant_chat(p_app)    a manager opens a direct chat with an applicant, whatever their message setting
set search_path = public, extensions;

-- ---------- reading ----------

-- Open jobs near a point, from live listings only, nearest first.
create or replace function public.jobs_near(lat double precision, lng double precision, radius_m int default 15000)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, pay text, job_type text, created_at timestamptz, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.pay, j.job_type, j.created_at, st_distance(l.location, public.geo(lat, lng)) as distance_m
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.open and l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, public.geo(lat, lng), radius_m)
  order by distance_m, j.created_at desc
  limit 100
$$;

-- Jobs with how many people applied. Row-level security still applies (security_invoker): a manager sees every
-- application on their jobs, an applicant only their own, so the counts are only meaningful for managers.
drop view if exists public.jobs_with_counts;
create view public.jobs_with_counts with (security_invoker = true) as
  select j.id, j.listing_id, j.title, j.description, j.pay, j.job_type, j.open, j.created_by, j.created_at,
         (select count(*) from public.applications a where a.job_id = j.id and a.status <> 'WITHDRAWN')::int as applications,
         (select count(*) from public.applications a where a.job_id = j.id and a.status = 'APPLIED')::int as new_applications
  from public.jobs j;
grant select on public.jobs_with_counts to authenticated;

-- One job with its business. Visible while open, and always to the people who run the listing and to anyone who applied.
create or replace function public.job_page(p_job uuid)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, description text, pay text, job_type text, open boolean, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.description, j.pay, j.job_type, j.open, j.created_at
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.id = p_job and public.me() is not null
    and (j.open or public.can_manage_listing(j.listing_id) or exists (select 1 from public.applications a where a.job_id = j.id and a.applicant_id = public.me()))
$$;

-- My applications with the job and business names, newest first. Closed jobs are hidden from the jobs table by
-- row-level security, so this reads through security definer to keep the titles.
create or replace function public.my_applications()
returns table (id uuid, job_id uuid, status text, note text, created_at timestamptz, job_title text, job_open boolean, pay text, job_type text, listing_id uuid, listing_title text, area text)
language sql stable security definer set search_path = public, extensions as $$
  select a.id, a.job_id, a.status, a.note, a.created_at, j.title, j.open, j.pay, j.job_type, l.id, l.title, l.area
  from public.applications a join public.jobs j on j.id = a.job_id join public.listings l on l.id = j.listing_id
  where a.applicant_id = public.me()
  order by a.created_at desc
$$;

-- ---------- rules ----------

-- Applying: not to a job of a listing you run, and only with skill profiles you own.
create or replace function public.check_application() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare j public.jobs; n int;
begin
  select * into j from public.jobs where id = new.job_id;
  if j.id is null then raise exception 'this job no longer exists'; end if;
  if not j.open then raise exception 'this job is closed'; end if;
  if public.can_manage_listing(j.listing_id) then raise exception 'you cannot apply to a job at your own listing'; end if;
  new.skill_listing_ids := (select coalesce(array_agg(distinct s), '{}') from unnest(new.skill_listing_ids) s);
  select count(*) into n from public.listings where id = any(new.skill_listing_ids) and kind = 'SKILL' and owner_id = new.applicant_id;
  if n <> coalesce(array_length(new.skill_listing_ids, 1), 0) then raise exception 'you can only apply with your own skill profiles'; end if;
  return new;
end $$;
drop trigger if exists application_check on public.applications;
create trigger application_check before insert on public.applications for each row execute function public.check_application();

-- Changing an application: the applicant may only withdraw (and not after being turned down); the people who run
-- the listing may shortlist, reject or hire, but never withdraw for someone or touch a withdrawn application.
-- Nobody edits the note or the skill profiles after applying. Runs as the caller (like the other guards in
-- schema.sql), so current_user tells app traffic from Bucks' own functions.
create or replace function public.guard_application() returns trigger language plpgsql set search_path = public, extensions as $$
declare l uuid;
begin
  if current_user <> 'authenticated' then return new; end if;
  if new.job_id <> old.job_id or new.applicant_id <> old.applicant_id or new.skill_listing_ids <> old.skill_listing_ids or new.note <> old.note or new.created_at <> old.created_at then
    raise exception 'an application cannot be changed after it is sent';
  end if;
  if new.status = old.status then
    if old.status = 'WITHDRAWN' and old.applicant_id = public.me() then raise exception 'this application was already withdrawn'; end if;
    return new;
  end if;
  select listing_id into l from public.jobs where id = old.job_id;
  if old.applicant_id = public.me() then
    if new.status <> 'WITHDRAWN' then raise exception 'you can only withdraw your application'; end if;
    if old.status = 'WITHDRAWN' then raise exception 'this application was already withdrawn'; end if;
    if old.status = 'REJECTED' then raise exception 'this application was already declined'; end if;
  elsif public.can_manage_listing(l) then
    if new.status = 'WITHDRAWN' then raise exception 'only the applicant can withdraw'; end if;
    if old.status = 'WITHDRAWN' then raise exception 'the applicant withdrew this application'; end if;
    if new.status not in ('APPLIED', 'SHORTLISTED', 'REJECTED', 'HIRED') then raise exception 'unknown status'; end if;
  else
    raise exception 'not allowed';
  end if;
  return new;
end $$;
drop trigger if exists application_guard on public.applications;
create trigger application_guard before update on public.applications for each row execute function public.guard_application();

-- ---------- talking to an applicant ----------

-- The people who run a listing open (or reuse) a one-to-one chat with someone who applied to one of its jobs,
-- whatever that person's "who can message me" setting says: applying is asking the business to get in touch.
-- One direction only (the applicant reaches the business through start_listing_chat, the shared listing inbox),
-- only while the application stands (not withdrawn), and blocks always win. Same direct_key as start_direct,
-- so it is the same conversation either function would open.
create or replace function public.start_applicant_chat(p_application uuid) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare a public.applications; l uuid; k text; c uuid;
begin
  if public.me() is null then raise exception 'not signed in'; end if;
  select * into a from public.applications where id = p_application;
  if a.id is not null then select listing_id into l from public.jobs where id = a.job_id; end if;
  if a.id is null or l is null or not public.can_manage_listing(l) then raise exception 'this application is not available'; end if;
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

-- ---------- grants ----------
revoke execute on function public.jobs_near(double precision, double precision, int), public.job_page(uuid), public.my_applications() from public, anon;
grant execute on function public.jobs_near(double precision, double precision, int), public.job_page(uuid), public.my_applications() to authenticated;
revoke execute on function public.start_applicant_chat(uuid) from public, anon;
grant execute on function public.start_applicant_chat(uuid) to authenticated;
-- Trigger bodies run only as triggers; nobody calls them through the API.
revoke execute on function public.check_application(), public.guard_application() from authenticated, anon, public;
