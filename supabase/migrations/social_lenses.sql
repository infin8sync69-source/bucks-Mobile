-- What the Feed and For you tabs show (UX restructure, 2026-11-09):
--   Feed: posts from people I'm synced with and pages I sync with, and my own. No strangers' public or nearby posts.
--   For you: only what my synced people recommend: posts they voted up (when at least 2 of them did, so one person's vote can't be
--            read off the list), and shops, pros and products they recommended or reviewed well. Counts only, never their names.
-- feed() stays as it was for older app builds.
-- Safe to run more than once. Apply after map_guardrails.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

create or replace function public.feed_synced(before timestamptz default now(), lim int default 30)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, p.author_id, a.name, a.short_code, p.listing_id, l.title, p.body, p.media, p.visibility, p.area, p.up, p.down, p.comments,
         (select v.vote from post_votes v where v.post_id = p.id and v.profile_id = me()), p.created_at, synced(me(), p.author_id)
  from posts p join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
  where me() is not null and p.created_at < coalesce(before, now()) and can_see_post(p)
    and (p.author_id = me() or synced(me(), p.author_id)
         or (p.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = p.listing_id)))
  order by p.created_at desc
  limit greatest(1, least(coalesce(lim, 30), 100))
$$;

-- [kind]: POST, LISTING or PRODUCT. [recommenders] is how many of my synced people recommend it. For a PRODUCT, [id] is the product key and
-- [listing_id] its shop. Newest recommendation first among equals; at most [lim] (up to 60).
create or replace function public.for_you(lim int default 40)
returns table (kind text, id text, listing_id uuid, title text, subtitle text, photo_url text, recommenders int, latest timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (
    select case when s.requester_id = me() then s.addressee_id else s.requester_id end pid
    from syncs s where s.status = 'ACCEPTED' and me() in (s.requester_id, s.addressee_id)
  ),
  posts_up as (
    select 'POST'::text kind, p.id::text id, p.listing_id, coalesce(l.title, a.name) title, left(p.body, 140) subtitle,
           (select m->>'path' from jsonb_array_elements(p.media) m limit 1) photo_url, count(*)::int recommenders, max(p.created_at) latest
    from post_votes v join mine on mine.pid = v.profile_id join posts p on p.id = v.post_id
         join profiles a on a.id = p.author_id left join listings l on l.id = p.listing_id
    where v.vote = 1 and p.author_id <> me() and p.created_at > now() - interval '90 days' and can_see_post(p)
    group by p.id, l.title, a.name having count(*) >= 2),
  listings_up as (
    select 'LISTING'::text, l.id::text, l.id, l.title, concat_ws(' · ', nullif(l.category, ''), nullif(l.area, '')), l.photo_url,
           count(distinct r.pid)::int, max(r.at)
    from (select x.listing_id, x.recommender_id pid, x.created_at at from recommendations x
          union all select v.listing_id, v.author_id, v.created_at from reviews v where v.vote = 1) r
         join mine on mine.pid = r.pid join listings l on l.id = r.listing_id
    where l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
    group by l.id),
  products_up as (
    select 'PRODUCT'::text, pr.product_key, l.id, coalesce((select coalesce(i.details->>'product', i.name) from items i
             where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key limit 1), 'A product'),
           l.title, (select i.photo_url from items i where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key and i.photo_url is not null limit 1),
           count(*)::int, max(pr.updated_at)
    from product_ratings pr join mine on mine.pid = pr.profile_id join listings l on l.id = pr.listing_id
    where pr.vote = 1 and l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
    group by l.id, pr.product_key)
  select * from (select * from posts_up union all select * from listings_up union all select * from products_up) x
  where me() is not null
  order by x.recommenders desc, x.latest desc
  limit greatest(1, least(coalesce(lim, 40), 60))
$$;

revoke all on function public.feed_synced(timestamptz, int), public.for_you(int) from public, anon;
grant execute on function public.feed_synced(timestamptz, int), public.for_you(int) to authenticated;
