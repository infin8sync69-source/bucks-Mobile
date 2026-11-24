-- Profile pictures and cover photos for people and pages.
--   profiles.photo_url  existed but nothing wrote it; the app now uploads it to avatars/<profile id>/.
--   profiles.cover_url  new: the band behind a person's profile, in avatars/<profile id>/.
--   listings.cover_url  new: the band behind a page; listings.photo_url stays the page's picture (search cards, the round photo).
-- Every profile is readable by every signed-in person and the app loads these links on sight, so a link must point at the owner's own
-- folder in our public buckets (the same rule as listings.gallery in media_urls_ok): no outside address can be used to see who opened
-- a profile. Safe to run more than once. Apply after hardening_platform.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

alter table public.profiles add column if not exists cover_url text;
alter table public.listings add column if not exists cover_url text;

-- True for null, or a public URL of one file directly inside <bucket>/<folder>/ on a Supabase storage host.
create or replace function public.own_media_url_ok(u text, bucket text, folder uuid) returns boolean language sql immutable set search_path = public, extensions as $$
  select u is null or (length(u) <= 500 and u ~ ('^https://[^/]+/storage/v1/object/public/' || bucket || '/' || folder::text || '/[A-Za-z0-9._-]+$'))
$$;
revoke execute on function public.own_media_url_ok(text, text, uuid) from public, anon;
grant execute on function public.own_media_url_ok(text, text, uuid) to authenticated;

alter table public.profiles drop constraint if exists profiles_photo_url_ok;
alter table public.profiles add constraint profiles_photo_url_ok check (public.own_media_url_ok(photo_url, 'avatars', id));
alter table public.profiles drop constraint if exists profiles_cover_url_ok;
alter table public.profiles add constraint profiles_cover_url_ok check (public.own_media_url_ok(cover_url, 'avatars', id));
alter table public.listings drop constraint if exists listings_cover_url_ok;
alter table public.listings add constraint listings_cover_url_ok check (public.own_media_url_ok(cover_url, 'listing-media', id));

-- profiles has column-level grants (profiles.home is never readable), so the new column is granted on its own. listings has table grants.
grant select (cover_url), update (cover_url) on public.profiles to authenticated;

-- A deleted account or page keeps no pictures. delete_my_account already clears profiles.photo_url and queues the files for removal.
create or replace function public.clear_media_on_delete() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.status = 'DELETED' and old.status is distinct from 'DELETED' then
    new.cover_url := null;
    if tg_table_name = 'profiles' then new.photo_url := null; end if;
  end if;
  return new;
end $$;
revoke execute on function public.clear_media_on_delete() from public, anon, authenticated;
drop trigger if exists profile_media_on_delete on public.profiles;
create trigger profile_media_on_delete before update of status on public.profiles for each row execute function public.clear_media_on_delete();
drop trigger if exists listing_media_on_delete on public.listings;
create trigger listing_media_on_delete before update of status on public.listings for each row execute function public.clear_media_on_delete();
