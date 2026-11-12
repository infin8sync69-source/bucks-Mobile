-- Explore (the tab that was "For you"), revision 1 after the first closed test.
--   explore()        posts from beyond my own feed that I'm allowed to see: public ones, ones from people and pages I sync with, and
--                    ones the people I'm synced with voted up. Those come first, with how many of them did and the name of one, so the
--                    app can say "Asha and 22 others recommended". Filtered by what the post carries (VIDEO, IMAGE, FILE) and by words.
--   for_you_named()  for_you()'s shops, pros and products, with the name of one synced person who recommends each.
-- This changes one rule of social_lenses.sql on purpose: for_you() gave counts only, never names. A name shown here is always someone
-- I'm synced with, and only on something they recommended. for_you() itself is unchanged, for app builds that still call it.
-- Safe to run more than once. Apply after social_lenses.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

create or replace function public.explore(p_kind text default 'ALL', q text default null, lim int default 60)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean, recommenders int, recommender_name text)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (
    select case when s.requester_id = me() then s.addressee_id else s.requester_id end pid
    from syncs s where s.status = 'ACCEPTED' and me() in (s.requester_id, s.addressee_id)
  ),
  term as (select nullif(replace(replace(btrim(coalesce(q, '')), '%', ''), '_', ''), '') t),   -- LIKE wildcards are dropped, not escaped
  base as (
    select p.id, p.author_id, a.name author_name, a.short_code author_code, p.listing_id, l.title listing_title, p.body, p.media, p.visibility, p.area,
           p.up, p.down, p.comments, p.created_at,
           (select count(*)::int from post_votes v join mine on mine.pid = v.profile_id where v.post_id = p.id and v.vote = 1) recs
    from posts p join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
    where me() is not null and p.author_id <> me() and p.created_at > now() - interval '180 days' and can_see_post(p)
      and case upper(coalesce(p_kind, 'ALL'))
            when 'VIDEO' then exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p.media) = 'array' then p.media else '[]'::jsonb end) m
                                      where m->>'mime' like 'video/%' or m->>'path' ilike '%.mp4')
            when 'IMAGE' then exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p.media) = 'array' then p.media else '[]'::jsonb end) m
                                      where m->>'mime' like 'image/%' and m->>'path' not ilike '%.mp4')
            when 'FILE'  then exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p.media) = 'array' then p.media else '[]'::jsonb end) m
                                      where m->>'mime' <> '' and m->>'mime' not like 'image/%' and m->>'mime' not like 'video/%' and m->>'path' not ilike '%.mp4')
            else true end
      and ((select t from term) is null or p.body ilike '%' || (select t from term) || '%'
           or a.name ilike '%' || (select t from term) || '%' or l.title ilike '%' || (select t from term) || '%')
  )
  select b.id, b.author_id, b.author_name, b.author_code, b.listing_id, b.listing_title, b.body, b.media, b.visibility, b.area, b.up, b.down, b.comments,
         (select v.vote from post_votes v where v.post_id = b.id and v.profile_id = me()), b.created_at, synced(me(), b.author_id), b.recs,
         case when b.recs > 0 then (select pr.name from post_votes v join mine on mine.pid = v.profile_id join profiles pr on pr.id = v.profile_id
                                    where v.post_id = b.id and v.vote = 1 and pr.name <> '' order by pr.name limit 1) end
  from base b
  where b.recs > 0 or b.visibility = 'PUBLIC' or synced(me(), b.author_id)
     or (b.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = b.listing_id))
  order by (b.recs > 0) desc, b.recs desc, b.created_at desc
  limit greatest(1, least(coalesce(lim, 60), 100))
$$;

create or replace function public.for_you_named(lim int default 40)
returns table (kind text, id text, listing_id uuid, title text, subtitle text, photo_url text, recommenders int, latest timestamptz, recommender_name text)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (
    select case when s.requester_id = me() then s.addressee_id else s.requester_id end pid
    from syncs s where s.status = 'ACCEPTED' and me() in (s.requester_id, s.addressee_id)
  ),
  listings_up as (
    select 'LISTING'::text kind, l.id::text id, l.id listing_id, l.title, concat_ws(' · ', nullif(l.category, ''), nullif(l.area, '')) subtitle, l.photo_url,
           count(distinct r.pid)::int recommenders, max(r.at) latest, min(nullif(pr.name, '')) recommender_name
    from (select x.listing_id, x.recommender_id pid, x.created_at at from recommendations x
          union all select v.listing_id, v.author_id, v.created_at from reviews v where v.vote = 1) r
         join mine on mine.pid = r.pid join profiles pr on pr.id = r.pid join listings l on l.id = r.listing_id
    where l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
    group by l.id),
  products_up as (
    select 'PRODUCT'::text, pr.product_key, l.id, coalesce((select coalesce(i.details->>'product', i.name) from items i
             where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key limit 1), 'A product'),
           l.title, (select i.photo_url from items i where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key and i.photo_url is not null limit 1),
           count(*)::int, max(pr.updated_at), min(nullif(who.name, ''))
    from product_ratings pr join mine on mine.pid = pr.profile_id join profiles who on who.id = pr.profile_id join listings l on l.id = pr.listing_id
    where pr.vote = 1 and l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
    group by l.id, pr.product_key)
  select * from (select * from listings_up union all select * from products_up) x
  where me() is not null
  order by x.recommenders desc, x.latest desc
  limit greatest(1, least(coalesce(lim, 40), 60))
$$;

revoke all on function public.explore(text, text, int), public.for_you_named(int) from public, anon;
grant execute on function public.explore(text, text, int), public.for_you_named(int) to authenticated;

-- A video's still frame (posts.media[].poster, saved beside the video when it is posted) is readable by exactly the people who can read
-- the video: whoever can see the post, and only when the post's author owns the folder. Added beside bucks_posts_read
-- (hardening_platform.sql), which matches media[].path and is left as it is.
do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists bucks_posts_poster_read on storage.objects;
    create policy bucks_posts_poster_read on storage.objects for select to authenticated
      using (bucket_id = 'posts' and exists (select 1 from public.posts p
               where public.can_see_post(p) and (storage.foldername(name))[1] = p.author_id::text
                 and p.media @> jsonb_build_array(jsonb_build_object('poster', name))));
  end if;
end $$;
