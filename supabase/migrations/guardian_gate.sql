-- Bucks: under-18s need a parent's or guardian's consent before they can do anything others see (November 2026). Safe to run more than once.
-- Apply after social_safety.sql (is_minor, guardian_consents) and security_hardening.sql; supabase/apply_all.sh runs it last.
--
--   1. Consent gate: a minor (TEEN or CHILD band) with no row in guardian_consents can't create posts, comments, Moments, messages, sync
--      requests, pages, jobs, applications, orders, rides or reviews. The app shows the guardian step instead (ui/social/Onboarding.kt);
--      this makes the rule hold for any client. Refusals carry detail = 'BK_GUARDIAN_NEEDED'.
--   2. Driving is for adults: vehicles can only be added by someone 18 or over (BK_ADULT_ONLY), whatever their consent.
-- Writes with no caller (cron, the system) are never gated. Reports and feedback stay open to everyone, so a minor can always ask for help.
set search_path = public, extensions;

-- True when this person may act: an adult, someone who hasn't given a date of birth yet (the onboarding gate asks first), or a minor
-- whose guardian has agreed.
create or replace function public.guardian_ok(p uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select not is_minor(p) or exists (select 1 from guardian_consents g where g.profile_id = p)
$$;

-- BEFORE INSERT trigger; TG_ARGV[0] is 'consent' (the gate) or 'adult' (adults only).
create or replace function public.guardian_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then return new; end if;
  if tg_argv[0] = 'adult' and is_minor(my) then
    raise exception 'you need to be 18 or over for this' using detail = 'BK_ADULT_ONLY';
  end if;
  if not guardian_ok(my) then
    raise exception 'a parent or guardian needs to agree before you can use this' using detail = 'BK_GUARDIAN_NEEDED';
  end if;
  return new;
end $$;

revoke execute on function public.guardian_ok(uuid), public.guardian_guard() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values ('posts', 'consent'), ('post_comments', 'consent'), ('moments', 'consent'), ('messages', 'consent'),
                                 ('syncs', 'consent'), ('listings', 'consent'), ('jobs', 'consent'), ('applications', 'consent'),
                                 ('orders', 'consent'), ('tasks', 'consent'), ('reviews', 'consent'), ('vehicles', 'adult')) v(t, rule) loop
    if to_regclass('public.' || r.t) is not null then
      execute format('drop trigger if exists a1_guardian on public.%I', r.t);
      execute format('create trigger a1_guardian before insert on public.%I for each row execute function public.guardian_guard(%L)', r.t, r.rule);
    end if;
  end loop;
end $$;
