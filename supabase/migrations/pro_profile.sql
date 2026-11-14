-- Pro profile: one professional profile per person (headline, summary, experience, education, skills, certifications, work preferences)
-- and their CV files. Bucks Pro menu > Pro profile. No AI here: the person fills and edits everything; reading a CV to fill the profile
-- is planned separately.
--   * Adults only (not CHILD or TEEN; social_safety.sql age bands).
--   * Visibility: EVERYONE (signed in), SYNCED or ONLY_ME, and any section can be hidden. Blocks apply both ways.
--   * CVs are private to their owner (files in the private docs bucket, <profile id>/cv-...); sending a CV to an employer comes with jobs.
--   * Everything goes when the account is deleted (the profile row is kept anonymised, so on delete cascade never fires: a trigger does it).
-- Safe to run more than once. Apply after social_safety.sql and profile_media.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

-- ---------- who may have one, and who may see it ----------
create or replace function public.pro_allowed() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.me() is not null and public.age_band_of(public.me()) not in ('CHILD', 'TEEN')
$$;

create table if not exists public.pro_profiles (
  profile_id       uuid primary key references public.profiles on delete cascade,
  headline         text not null default '' check (length(headline) <= 120),
  summary          text not null default '' check (length(summary) <= 2000),
  open_to          text[] not null default '{}' check (open_to <@ array['WORK', 'GIGS', 'HIRING']),
  years_experience int check (years_experience between 0 and 60),
  job_types        text[] not null default '{}' check (job_types <@ array['FULL_TIME', 'PART_TIME', 'CONTRACT', 'GIG', 'INTERNSHIP', 'APPRENTICESHIP']),
  work_radius_km   int check (work_radius_km between 1 and 500),
  expected_pay     text not null default '' check (length(expected_pay) <= 60),
  availability     text not null default '' check (length(availability) <= 60),
  languages        text[] not null default '{}' check (cardinality(languages) <= 10),
  visibility       text not null default 'EVERYONE' check (visibility in ('EVERYONE', 'SYNCED', 'ONLY_ME')),
  hidden_sections  text[] not null default '{}' check (hidden_sections <@ array['EXPERIENCE', 'EDUCATION', 'SKILLS', 'CERTIFICATIONS', 'PREFERENCES', 'SERVICES']),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- True when I may see person [p]'s Pro profile (and, with [section], that section): always my own; someone else's while it exists, they
-- are an active adult, neither of us blocked the other, its visibility lets me in, and the section isn't hidden.
create or replace function public.can_see_pro(p uuid, section text default null) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.me() is not null and (p = public.me() or exists (
    select 1 from public.pro_profiles x join public.profiles pr on pr.id = x.profile_id
    where x.profile_id = p and pr.status = 'ACTIVE' and not public.blocked_between(public.me(), p) and public.age_band_of(p) not in ('CHILD', 'TEEN')
      and (x.visibility = 'EVERYONE' or (x.visibility = 'SYNCED' and public.synced(public.me(), p)))
      and (section is null or not (section = any (x.hidden_sections)))))
$$;

-- ---------- sections ----------
create table if not exists public.pro_experience (
  id          uuid primary key default public.uuid_v7(),
  profile_id  uuid not null references public.profiles on delete cascade,
  title       text not null check (length(btrim(title)) between 1 and 100),
  org         text not null default '' check (length(org) <= 100),
  location    text not null default '' check (length(location) <= 80),
  start_month date not null,
  end_month   date check (end_month is null or end_month >= start_month),   -- null: still there
  description text not null default '' check (length(description) <= 1000),
  created_at  timestamptz not null default now()
);
create index if not exists pro_experience_profile_idx on public.pro_experience (profile_id, start_month desc);

create table if not exists public.pro_education (
  id          uuid primary key default public.uuid_v7(),
  profile_id  uuid not null references public.profiles on delete cascade,
  course      text not null check (length(btrim(course)) between 1 and 120),
  institute   text not null default '' check (length(institute) <= 120),
  start_year  int check (start_year between 1950 and 2100),
  end_year    int check (end_year between 1950 and 2100),
  grade       text not null default '' check (length(grade) <= 40),
  created_at  timestamptz not null default now(),
  check (end_year is null or start_year is null or end_year >= start_year)
);
create index if not exists pro_education_profile_idx on public.pro_education (profile_id);

create table if not exists public.pro_skills (
  id          uuid primary key default public.uuid_v7(),
  profile_id  uuid not null references public.profiles on delete cascade,
  name        text not null check (length(btrim(name)) between 1 and 60),
  level       text not null default 'INTERMEDIATE' check (level in ('BEGINNER', 'INTERMEDIATE', 'EXPERT')),
  years       int check (years between 0 and 60),
  created_at  timestamptz not null default now()
);
create unique index if not exists pro_skills_one_name on public.pro_skills (profile_id, lower(btrim(name)));

create table if not exists public.pro_certifications (
  id            uuid primary key default public.uuid_v7(),
  profile_id    uuid not null references public.profiles on delete cascade,
  name          text not null check (length(btrim(name)) between 1 and 120),
  issuer        text not null default '' check (length(issuer) <= 120),
  issued_on     date,
  expires_on    date check (expires_on is null or issued_on is null or expires_on >= issued_on),
  credential_id text not null default '' check (length(credential_id) <= 80),
  created_at    timestamptz not null default now()
);
create index if not exists pro_certifications_profile_idx on public.pro_certifications (profile_id);

-- CV files: only the owner reads these rows (and the files: the docs bucket's own-folder rules, hardening_platform.sql).
create table if not exists public.pro_cvs (
  id          uuid primary key default public.uuid_v7(),
  profile_id  uuid not null references public.profiles on delete cascade,
  path        text not null check (path like profile_id::text || '/cv-%' and length(path) <= 300),
  file_name   text not null check (length(btrim(file_name)) between 1 and 200),
  mime        text not null check (mime in ('application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'image/jpeg', 'image/png')),
  size_bytes  bigint not null check (size_bytes between 1 and 10485760),
  is_primary  boolean not null default false,
  uploaded_at timestamptz not null default now()
);
create unique index if not exists pro_cvs_one_primary on public.pro_cvs (profile_id) where is_primary;

-- The private docs bucket takes PDF and photos; CVs also come as Word .docx (not the old .doc, which can carry macros).
do $$ begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets set allowed_mime_types = array(select distinct m from unnest(coalesce(allowed_mime_types, '{}') ||
      array['application/vnd.openxmlformats-officedocument.wordprocessingml.document']) m)
     where id = 'docs' and not ('application/vnd.openxmlformats-officedocument.wordprocessingml.document' = any (coalesce(allowed_mime_types, '{}')));
  end if;
end $$;

-- ---------- limits and stamps ----------
create or replace function public.pro_limits() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare n int; cap int := case tg_table_name when 'pro_experience' then 30 when 'pro_education' then 15 when 'pro_skills' then 40
                                            when 'pro_certifications' then 30 when 'pro_cvs' then 5 else 1000 end;
begin
  execute format('select count(*) from public.%I where profile_id = $1', tg_table_name) into n using new.profile_id;
  if n >= cap then raise exception 'you can keep up to % here; remove one first', cap; end if;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['pro_experience', 'pro_education', 'pro_skills', 'pro_certifications', 'pro_cvs'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_limit', t);
    execute format('create trigger %I before insert on public.%I for each row execute function public.pro_limits()', t || '_limit', t);
  end loop;
end $$;

create or replace function public.pro_touch() returns trigger language plpgsql set search_path = public, extensions as $$
begin new.updated_at := now(); new.created_at := coalesce(old.created_at, now()); return new; end $$;
drop trigger if exists pro_profiles_touch on public.pro_profiles;
create trigger pro_profiles_touch before update on public.pro_profiles for each row execute function public.pro_touch();

-- A deleted account keeps no professional record (delete_my_account anonymises the profile row; its docs files are already queued).
create or replace function public.pro_clear_on_delete() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'DELETED' and old.status is distinct from 'DELETED' then
    delete from public.pro_cvs where profile_id = new.id;
    delete from public.pro_certifications where profile_id = new.id;
    delete from public.pro_skills where profile_id = new.id;
    delete from public.pro_education where profile_id = new.id;
    delete from public.pro_experience where profile_id = new.id;
    delete from public.pro_profiles where profile_id = new.id;
  end if;
  return null;
end $$;
drop trigger if exists pro_clear_on_delete on public.profiles;
create trigger pro_clear_on_delete after update of status on public.profiles for each row execute function public.pro_clear_on_delete();

-- ---------- row-level security ----------
alter table public.pro_profiles enable row level security;
alter table public.pro_experience enable row level security;
alter table public.pro_education enable row level security;
alter table public.pro_skills enable row level security;
alter table public.pro_certifications enable row level security;
alter table public.pro_cvs enable row level security;

drop policy if exists pro_profiles_read on public.pro_profiles;
create policy pro_profiles_read on public.pro_profiles for select to authenticated using (public.can_see_pro(profile_id));
drop policy if exists pro_profiles_insert on public.pro_profiles;
create policy pro_profiles_insert on public.pro_profiles for insert to authenticated with check (profile_id = public.me() and public.pro_allowed());
drop policy if exists pro_profiles_update on public.pro_profiles;
create policy pro_profiles_update on public.pro_profiles for update to authenticated using (profile_id = public.me()) with check (profile_id = public.me() and public.pro_allowed());
drop policy if exists pro_profiles_delete on public.pro_profiles;
create policy pro_profiles_delete on public.pro_profiles for delete to authenticated using (profile_id = public.me());

do $$ declare t text; s text; begin
  foreach t in array array['pro_experience', 'pro_education', 'pro_skills', 'pro_certifications'] loop
    s := case t when 'pro_experience' then 'EXPERIENCE' when 'pro_education' then 'EDUCATION' when 'pro_skills' then 'SKILLS' else 'CERTIFICATIONS' end;
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_see_pro(profile_id, %L))', t || '_read', t, s);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('create policy %I on public.%I for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me() and public.pro_allowed())', t || '_write', t);
  end loop;
end $$;
drop policy if exists pro_cvs_own on public.pro_cvs;
create policy pro_cvs_own on public.pro_cvs for all to authenticated using (profile_id = public.me()) with check (profile_id = public.me() and public.pro_allowed());

-- ---------- grants ----------
revoke all on public.pro_profiles, public.pro_experience, public.pro_education, public.pro_skills, public.pro_certifications, public.pro_cvs from public, anon;
grant select, insert, update, delete on public.pro_profiles, public.pro_experience, public.pro_education, public.pro_skills, public.pro_certifications, public.pro_cvs to authenticated;
revoke execute on function public.pro_allowed(), public.can_see_pro(uuid, text) from public, anon;
grant execute on function public.pro_allowed(), public.can_see_pro(uuid, text) to authenticated;
revoke execute on function public.pro_limits(), public.pro_touch(), public.pro_clear_on_delete() from public, anon, authenticated;
