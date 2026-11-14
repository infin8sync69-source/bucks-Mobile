-- Profile details asked at the end of onboarding (About you: picture, gender, one line about me).
-- The picture and the line use columns that already exist (profiles.photo_url, profiles.bio). Gender is new and private: it lives in
-- profile_private, which only its owner can read or write (policy private_self), and is never shown on a profile.
-- Safe to run again.

alter table public.profile_private add column if not exists gender text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profile_private_gender_ok') then
    alter table public.profile_private add constraint profile_private_gender_ok check (gender is null or gender in ('WOMAN', 'MAN', 'NON_BINARY', 'UNSAID'));
  end if;
end $$;
