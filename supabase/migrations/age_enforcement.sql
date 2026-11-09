-- Age rules enforced by the database, not only by the app's onboarding gate (which a modified or failing client could skip).
--
-- 1. Account ready: a signed-in person can't post, comment, share a Moment, message, review, give feedback, order, book, list or apply
--    until their date of birth is set (profile_safety) and, for under-18s, a guardian has consented (guardian_consents).
-- 2. Adults only: vehicles, going online as a driver, booking rides, creating business/skill/asset pages and posting jobs need the
--    ADULT band (Motor Vehicle Aggregator Guidelines, minors' contracts, child labour). Teens can still order from shops (an adult
--    shop delivers) and apply to jobs (the employer decides; check with a lawyer before launch).
--
-- Both apply only to requests made by a signed-in person (me() is set). Background jobs, cron and staff tools with no caller pass.
-- settings.enforce_age = 0 switches both off (the scenario test runner does, so older suites can create people without a birth date;
-- in production it stays 1).

insert into public.settings (key, value) values ('enforce_age', 1) on conflict (key) do nothing;

create or replace function public.account_ready_error(p uuid) returns text
language sql stable security definer set search_path = public, extensions as $$
  select case
    when p is null or coalesce(setting('enforce_age'), 1) < 1 then null
    when not exists (select 1 from profile_safety s where s.profile_id = p) then 'add your date of birth first: open Bucks and finish signing up'
    when age_band_of(p) <> 'ADULT' and not exists (select 1 from guardian_consents g where g.profile_id = p) then 'a parent or guardian needs to agree first: open Bucks and finish signing up'
    else null end
$$;

create or replace function public.require_ready_account() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare err text := account_ready_error(me());
begin
  if err is not null then raise exception '%', err using errcode = 'P0001'; end if;
  return new;
end $$;

create or replace function public.require_adult() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null or coalesce(setting('enforce_age'), 1) < 1 then return new; end if;
  -- Going offline, and delivery tasks a shop creates for its order, are never blocked.
  if tg_table_name = 'driver_presence' and not coalesce(new.online, false) then return new; end if;
  if tg_table_name = 'tasks' and (new.type <> 'RIDE' or new.requester_id is distinct from my) then return new; end if;
  if age_band_of(my) <> 'ADULT' then
    raise exception '%', case tg_table_name
      when 'tasks'    then 'rides can be booked by people 18 and over; ask a parent or guardian to book for you'
      when 'jobs'     then 'jobs can be posted by people 18 and over'
      when 'listings' then 'pages for businesses, skills and properties are for people 18 and over'
      else 'driving on Bucks is for people 18 and over' end using errcode = 'P0001';
  end if;
  return new;
end $$;

revoke execute on function public.require_ready_account(), public.require_adult() from public, anon, authenticated;
revoke execute on function public.account_ready_error(uuid) from public, anon;

do $$
declare t text;
begin
  foreach t in array array['posts', 'post_comments', 'moments', 'messages', 'reviews', 'feedback_posts', 'orders', 'tasks', 'listings', 'vehicles', 'jobs', 'applications'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists a0_require_ready_account on public.%I', t);
      execute format('create trigger a0_require_ready_account before insert on public.%I for each row execute function public.require_ready_account()', t);
    end if;
  end loop;
  foreach t in array array['vehicles', 'listings', 'jobs', 'tasks'] loop
    execute format('drop trigger if exists a1_require_adult on public.%I', t);
    execute format('create trigger a1_require_adult before insert on public.%I for each row execute function public.require_adult()', t);
  end loop;
  drop trigger if exists a1_require_adult on public.driver_presence;
  create trigger a1_require_adult before insert or update of online on public.driver_presence for each row execute function public.require_adult();
end $$;
