-- Phase 1 of the "Recommended here" map (reports/Map feed for Gen Z India.md): the two reads the Home map's Recommended layer uses.
-- Both sit on the Phase 0 guardrails (map_guardrails.sql) and apply the same rules as map_pins: only posts post_on_map() allows, never
-- anyone I've blocked or who blocked me, at most 3 posts per author per place, and places, never authors, on the map itself.
--   map_places      places in a box, ranked, with a category for the chips and a time window ("This week" or all time).
--   map_place_posts the posts behind one place, for the preview card's "See posts", with the columns explore() returns.
-- Ranking ("Most recommended") is the Wilson lower bound of recommends over all votes with one pseudo-vote each way, so 2 of 2 never
-- beats 100 of 101 and a place with no votes yet scores a little above zero rather than nothing.
-- Safe to run more than once. Apply after map_guardrails.sql and explore.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

-- FOOD, SHOPS, SERVICES or AREA (a locality centre). Guessed from the page's kind and category; kept simple on purpose.
create or replace function public.map_category(p_place text, p_kind text, p_category text) returns text language sql immutable set search_path = public, extensions as $$
  select case
    when p_place = 'LOCALITY' or p_kind is null then 'AREA'
    when p_kind = 'SKILL' then 'SERVICES'
    when coalesce(p_category, '') ~* '(food|restaurant|caf|chai|tea|coffee|bakery|sweet|snack|meat|grocer|vegetable|fruit|dairy|milk|biryani|dhaba|juice)' then 'FOOD'
    else 'SHOPS' end
$$;

create or replace function public.map_places(s double precision, w double precision, n double precision, e double precision,
                                              p_days int default 7, p_cat text default null, lim int default 200)
returns table (place text, place_id text, listing_id uuid, name text, category text, lat double precision, lng double precision,
               posts int, up int, down int, latest timestamptz, score double precision)
language sql stable security definer set search_path = public, extensions as $$
  with ok as (
    select p.*, row_number() over (partition by p.map_place_id, p.author_id order by p.up - p.down desc, p.created_at desc) k
    from posts p
    where me() is not null and p.map_point is not null
      and st_intersects(p.map_point, st_makeenvelope(w, s, e, n, 4326)::geography)
      and (coalesce(p_days, 0) <= 0 or p.created_at > now() - make_interval(days => least(p_days, 3650)))
      and post_on_map(p) and not blocked_between(me(), p.author_id)
  ),
  agg as (
    select ok.map_place, ok.map_place_id,
           st_y(min(ok.map_point::geometry)) lat, st_x(min(ok.map_point::geometry)) lng,
           count(*)::int posts, coalesce(sum(ok.up), 0)::int up, coalesce(sum(ok.down), 0)::int down, max(ok.created_at) latest
    from ok where ok.k <= 3
    group by ok.map_place, ok.map_place_id
  ),
  named as (
    select a.*, l.id listing_id, coalesce(l.title, x.name, '') pname, map_category(a.map_place, l.kind, l.category) cat
    from agg a
    left join listings l on a.map_place = 'LISTING' and l.id::text = a.map_place_id
    left join localities x on a.map_place = 'LOCALITY' and x.id::text = a.map_place_id
  ),
  scored as (
    select nm.*, (nm.up + 1)::double precision / (nm.up + nm.down + 2) ph, (nm.up + nm.down + 2)::double precision nn from named nm
  )
  select sc.map_place, sc.map_place_id, sc.listing_id, sc.pname, sc.cat, sc.lat, sc.lng, sc.posts, sc.up, sc.down, sc.latest,
         (sc.ph + 1.9208 / sc.nn - 1.96 * sqrt((sc.ph * (1 - sc.ph) + 0.9604 / sc.nn) / sc.nn)) / (1 + 3.8416 / sc.nn)
  from scored sc
  where p_cat is null or p_cat = '' or upper(p_cat) = 'ALL' or sc.cat = upper(p_cat)
  order by 12 desc, sc.up desc, sc.latest desc
  limit greatest(1, least(coalesce(lim, 200), 500))
$$;

-- The posts at one place, best first. Same columns as explore(), so the apps show them with the feed's own post card.
create or replace function public.map_place_posts(p_place text, p_place_id text, lim int default 40)
returns table (id uuid, author_id uuid, author_name text, author_code text, listing_id uuid, listing_title text, body text, media jsonb, visibility text, area text,
               up int, down int, comments int, my_vote smallint, created_at timestamptz, synced boolean, recommenders int, recommender_name text)
language sql stable security definer set search_path = public, extensions as $$
  with ok as (
    select p.*, row_number() over (partition by p.author_id order by p.up - p.down desc, p.created_at desc) k
    from posts p
    where me() is not null and p.map_place = p_place and p.map_place_id = p_place_id
      and post_on_map(p) and can_see_post(p) and not blocked_between(me(), p.author_id)
  )
  select ok.id, ok.author_id, a.name, a.short_code, ok.listing_id, l.title, ok.body, ok.media, ok.visibility, ok.area,
         ok.up, ok.down, ok.comments, (select v.vote from post_votes v where v.post_id = ok.id and v.profile_id = me()), ok.created_at,
         synced(me(), ok.author_id), 0, null::text
  from ok join profiles a on a.id = ok.author_id left join listings l on l.id = ok.listing_id
  where ok.k <= 3
  order by ok.up - ok.down desc, ok.created_at desc
  limit greatest(1, least(coalesce(lim, 40), 100))
$$;

revoke all on function public.map_places(double precision, double precision, double precision, double precision, int, text, int),
  public.map_place_posts(text, text, int) from public, anon;
grant execute on function public.map_places(double precision, double precision, double precision, double precision, int, text, int),
  public.map_place_posts(text, text, int) to authenticated;
