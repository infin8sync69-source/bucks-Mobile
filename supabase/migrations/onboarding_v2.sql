-- Onboarding v2 (November 2026): Language → Phone (country, "I'm 18 or older and agree to the Terms") → Code → Name → Home.
-- No date of birth any more: confirm_adult records the person's own 18+ confirmation and which terms they accepted, and sets the
-- ADULT band (so adult-only analytics work as before). Bands set earlier from a date of birth are kept. Profiles also remember the
-- country (ISO 3166 code) and app language the person chose, for currency, payments and the language of notifications.

alter table public.profile_safety alter column birth_date drop not null;
alter table public.profile_safety add column if not exists terms_version text;
alter table public.profile_safety add column if not exists terms_accepted_at timestamptz;

alter table public.profiles add column if not exists country text check (country ~ '^[A-Z]{2}$');
alter table public.profiles add column if not exists language text check (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$');

create or replace function public.confirm_adult(p_terms_version text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  insert into profile_safety (profile_id, birth_date, age_band, terms_version, terms_accepted_at)
  values (my, null, 'ADULT', left(coalesce(p_terms_version, ''), 40), now())
  on conflict (profile_id) do update set terms_version = excluded.terms_version, terms_accepted_at = excluded.terms_accepted_at;
end $$;

create or replace function public.set_my_locale(p_country text, p_language text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  update profiles set country = coalesce(upper(nullif(btrim(p_country), '')), country), language = coalesce(nullif(btrim(p_language), ''), language)
   where id = my;
end $$;

revoke execute on function public.confirm_adult(text), public.set_my_locale(text, text) from public, anon;
grant execute on function public.confirm_adult(text), public.set_my_locale(text, text) to authenticated;
