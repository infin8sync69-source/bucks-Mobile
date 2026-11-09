-- Onboarding v2 (November 2026): Language → Phone (country, "I agree to the Terms") → Code → Name and date of birth → Home.
--
-- One simple age rule: Bucks is for people 13 and over (settings.min_signup_age). set_birth_date refuses anyone younger and stores
-- nothing for them. 13 to 17 year olds get the TEEN band, and with it the protections the server already enforces (private by
-- default, only syncs can message them, adults they don't know can't find them, no analytics); the app shows no extra step for it.

insert into public.settings (key, value) values ('min_signup_age', 13) on conflict (key) do nothing;
-- record_terms stores which version of the Terms each person accepted. Profiles also remember the country (ISO 3166 code) and app
-- language the person chose, for currency, payments and the language of notifications.

alter table public.profiles add column if not exists terms_version text;
alter table public.profiles add column if not exists terms_accepted_at timestamptz;
alter table public.profiles add column if not exists country text check (country ~ '^[A-Z]{2}$');
alter table public.profiles add column if not exists language text check (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$');

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
  if band = 'CHILD' and coalesce(setting('allow_children'), 0) < 1 then raise exception 'too young: not eligible'; end if;
  if years < coalesce(setting('min_signup_age'), 13) then raise exception 'not eligible'; end if;
  insert into profile_safety (profile_id, birth_date, age_band) values (my, p_date, band);
  if band <> 'ADULT' then
    insert into user_settings (profile_id, who_can_message, discoverable, moments_audience)
    values (my, 'SYNCED', band = 'TEEN', 'SYNCED')
    on conflict (profile_id) do update set who_can_message = 'SYNCED', discoverable = excluded.discoverable, moments_audience = 'SYNCED';
  end if;
  return band;
end $$;

create or replace function public.record_terms(p_version text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  update profiles set terms_version = left(coalesce(p_version, ''), 40), terms_accepted_at = now() where id = my;
end $$;

create or replace function public.set_my_locale(p_country text, p_language text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me();
begin
  if my is null then raise exception 'not signed in'; end if;
  update profiles set country = coalesce(upper(nullif(btrim(p_country), '')), country), language = coalesce(nullif(btrim(p_language), ''), language)
   where id = my;
end $$;

revoke execute on function public.record_terms(text), public.set_my_locale(text, text) from public, anon;
grant execute on function public.record_terms(text), public.set_my_locale(text, text) to authenticated;
