-- Content screen: listings, items, jobs, posts and moments whose text matches content_screen_terms are left out of search, explore,
-- the feeds, recommendations, the map, store pages, the job board and orders. Matching rows stay in the database.
--
-- How it works
--   content_screen_terms  the term list (English, Hindi, Kannada, Malayalam, Tamil, Telugu and common romanised spellings). No API access:
--                         only the dashboard (owner) and the service role read or change it.
--   content_screened      the ids that matched, kept current by triggers on listings, items, jobs, posts and moments, and rebuilt in full
--                         whenever the term list changes. No API access either.
--   Reads                 restrictive SELECT policies on listings, items and jobs; can_see_post, can_see_moment and post_on_map (which the
--                         feeds, explore, the map and moments all go through); search_listings, search_places, suggest_listings,
--                         for_you, for_you_named, category_suggestions, jobs_near and job_page filter on content_screened directly.
--   Orders                a trigger on orders refuses screened items and shops with the same messages as a sold-out item or a closed shop.
--
-- Who sees what
--   * The owner and the members of a listing see it, its items and its jobs everywhere they did before, their own search included, so
--     nothing changes for them. The author of a post or moment still sees it.
--   * Staff see screened listings, items and jobs on store pages and in direct reads (to moderate), but search, feeds and
--     recommendations show staff what any customer sees.
--   * Everyone else never sees it.
--
-- Matching (screen_hit): the text is lower-cased, zero-width joiners are dropped and everything except a-z, 0-9, Arabic script
-- (Urdu, U+0600-U+06FF) and the Indic blocks (Devanagari to Malayalam, U+0900-U+0DFF) becomes a space. A phrase after "no", "non", "not", "without", "zero" or "nil" is dropped
-- first ("no pork" is not a match). Each term then matches as:
--   WORD    whole words, plus a trailing "s" (pig, pigs; sex toy, sex toys). "ham" never matches "hamburger", "meth" never "methi".
--   EXACT   whole words only (short Indic words whose stems are also ordinary words).
--   PREFIX  a word that starts with the term (Indic stems that take suffixes: ಗಾಂಜಾ, ಗಾಂಜಾವನ್ನು).
--   PART    anywhere, for run-together spellings (sextoy).
-- unless_words lists words or phrases that cancel a term when they appear anywhere in the same text: "wine" next to saree, colour or
-- silk is a colour; "alcohol" next to sanitizer, syrup or medical is a medicine or a cleaner; "weed" next to killer or remover is a garden
-- product. An item is screened with its shop's name and category beside it, so a pharmacy's tonics and a clothes shop's "wine" saree
-- stay visible.
--
-- To change the list, edit it in the SQL editor; the whole screen is rebuilt in the same statement:
--   insert into public.content_screen_terms (term, how, scope, unless_words) values ('example', 'WORD', 'ALL', '{}');
--   delete from public.content_screen_terms where term = 'example';
-- scope SHOP terms apply to listings, items and jobs only (not to posts or moments): "ham" and "gin" are everyday Hinglish words.
-- Run after review_accounts.sql. Re-runnable.

-- ---------- term list and screened ids ----------
create or replace function public.screen_norm(t text) returns text language sql immutable set search_path = public, extensions as $$
  select ' ' || regexp_replace(regexp_replace(lower(translate(coalesce(t, ''), chr(8203) || chr(8204) || chr(8205) || chr(173), '')),
                                              '[' || chr(2404) || chr(2405) || ']', ' ', 'g'),   -- zero-width joiners dropped; danda is a full stop
                               '[^a-z0-9' || chr(1536) || '-' || chr(1791) || chr(2304) || '-' || chr(3583) || ']+', ' ', 'g') || ' '   -- keep Arabic script and U+0900-U+0DFF
$$;
revoke execute on function public.screen_norm(text) from public, anon, authenticated;

create table if not exists public.content_screen_terms (
  term         text primary key,
  how          text not null default 'WORD' check (how in ('WORD', 'EXACT', 'PREFIX', 'PART')),
  scope        text not null default 'ALL' check (scope in ('ALL', 'SHOP')),
  unless_words text[] not null default '{}',
  grp          text not null default '',
  created_at   timestamptz not null default now(),
  constraint content_screen_terms_normal check (term = btrim(regexp_replace(public.screen_norm(term), ' +', ' ', 'g')) and char_length(term) >= 2),
  constraint content_screen_terms_part check (how not in ('PART', 'PREFIX') or char_length(term) >= 3)
);
alter table public.content_screen_terms enable row level security;
revoke all on public.content_screen_terms from public, anon, authenticated;

create table if not exists public.content_screened (
  kind text not null check (kind in ('LISTING', 'ITEM', 'JOB', 'POST', 'MOMENT')),
  ref  uuid not null,
  at   timestamptz not null default now(),
  primary key (kind, ref)
);
alter table public.content_screened enable row level security;
revoke all on public.content_screened from public, anon, authenticated;

-- ---------- matching ----------
create or replace function public.screen_hit(t text, p_scope text default 'ALL') returns boolean
language sql stable security definer set search_path = public, extensions cost 500 as $$
  with r as (select public.screen_norm(t) r),
       n as (select r.r, regexp_replace(r.r, ' (no|non|not|without|zero|nil) [a-z]+', ' ', 'g') s from r)
  select coalesce(btrim(t), '') <> '' and exists (
    select 1 from public.content_screen_terms x, n
    where (x.scope = 'ALL' or p_scope = 'SHOP')
      and case x.how
            when 'WORD'   then position(' ' || x.term || ' ' in n.s) > 0 or position(' ' || x.term || 's ' in n.s) > 0
            when 'EXACT'  then position(' ' || x.term || ' ' in n.s) > 0
            when 'PREFIX' then position(' ' || x.term in n.s) > 0
            else position(x.term in n.s) > 0 end
      -- cancel words are looked up in the text as written, before negations are dropped ("non alcoholic", "pork free")
      and not exists (select 1 from unnest(x.unless_words) u
                      where position(' ' || u || ' ' in n.r) > 0 or position(' ' || u || 's ' in n.r) > 0))
$$;
revoke execute on function public.screen_hit(text, text) from public, anon, authenticated;

-- The string values of a details object (not its keys).
create or replace function public.screen_json(j jsonb) returns text language sql immutable set search_path = public, extensions as $$
  select coalesce(jsonb_path_query_array(coalesce(j, '{}'::jsonb), 'strict $.** ? (@.type() == "string")')::text, '')
$$;
revoke execute on function public.screen_json(jsonb) from public, anon, authenticated;

create or replace function public.screen_listing_text(l public.listings) returns text language sql immutable set search_path = public, extensions as $$
  select concat_ws(' ', l.title, l.category, l.description, l.type_key, public.screen_json(l.details))
$$;
create or replace function public.screen_item_text(i public.items, l public.listings) returns text language sql immutable set search_path = public, extensions as $$
  select concat_ws(' ', i.name, i.group_name, i.description, i.unit, public.screen_json(i.details), '.', l.title, l.category, l.type_key)
$$;
revoke execute on function public.screen_listing_text(public.listings) from public, anon, authenticated;
revoke execute on function public.screen_item_text(public.items, public.listings) from public, anon, authenticated;

-- Recompute one row's screen. Items are screened together with their shop's name and category.
create or replace function public.rescreen_one(p_kind text, p_ref uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from content_screened where kind = p_kind and ref = p_ref;
  if p_kind = 'LISTING' then
    insert into content_screened (kind, ref) select 'LISTING', l.id from listings l where l.id = p_ref and screen_hit(screen_listing_text(l), 'SHOP') on conflict do nothing;
  elsif p_kind = 'ITEM' then
    insert into content_screened (kind, ref) select 'ITEM', i.id from items i join listings l on l.id = i.listing_id
    where i.id = p_ref and screen_hit(screen_item_text(i, l), 'SHOP') on conflict do nothing;
  elsif p_kind = 'JOB' then
    insert into content_screened (kind, ref) select 'JOB', j.id from jobs j where j.id = p_ref and screen_hit(concat_ws(' ', j.title, j.description), 'SHOP') on conflict do nothing;
  elsif p_kind = 'POST' then
    insert into content_screened (kind, ref) select 'POST', p.id from posts p where p.id = p_ref and screen_hit(p.body, 'ALL') on conflict do nothing;
  elsif p_kind = 'MOMENT' then
    insert into content_screened (kind, ref) select 'MOMENT', m.id from moments m where m.id = p_ref and screen_hit(m.caption, 'ALL') on conflict do nothing;
  end if;
end $$;
revoke execute on function public.rescreen_one(text, uuid) from public, anon, authenticated;

create or replace function public.rescreen_all() returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from content_screened where true;
  insert into content_screened (kind, ref) select 'LISTING', l.id from listings l where screen_hit(screen_listing_text(l), 'SHOP');
  insert into content_screened (kind, ref) select 'ITEM', i.id from items i join listings l on l.id = i.listing_id where screen_hit(screen_item_text(i, l), 'SHOP');
  insert into content_screened (kind, ref) select 'JOB', j.id from jobs j where screen_hit(concat_ws(' ', j.title, j.description), 'SHOP');
  insert into content_screened (kind, ref) select 'POST', p.id from posts p where screen_hit(p.body, 'ALL');
  insert into content_screened (kind, ref) select 'MOMENT', m.id from moments m where screen_hit(m.caption, 'ALL');
end $$;
revoke execute on function public.rescreen_all() from public, anon, authenticated;

create or replace function public.screen_row() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'DELETE' then
    delete from content_screened where kind = tg_argv[0] and ref = old.id;
    return old;
  end if;
  perform rescreen_one(tg_argv[0], new.id);
  if tg_argv[0] = 'LISTING' and tg_op = 'UPDATE' then   -- an item is screened with its shop's name and category
    perform rescreen_one('ITEM', i.id) from items i where i.listing_id = new.id;
  end if;
  return new;
end $$;
revoke execute on function public.screen_row() from public, anon, authenticated;

create or replace function public.screen_terms_changed() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform rescreen_all();
  return null;
end $$;
revoke execute on function public.screen_terms_changed() from public, anon, authenticated;

drop trigger if exists screen_row on public.listings;
create trigger screen_row after insert or update of title, category, description, details, type_key or delete on public.listings
  for each row execute function public.screen_row('LISTING');
drop trigger if exists screen_row on public.items;
create trigger screen_row after insert or update of name, group_name, description, unit, details, listing_id or delete on public.items
  for each row execute function public.screen_row('ITEM');
drop trigger if exists screen_row on public.jobs;
create trigger screen_row after insert or update of title, description or delete on public.jobs
  for each row execute function public.screen_row('JOB');
drop trigger if exists screen_row on public.posts;
create trigger screen_row after insert or update of body or delete on public.posts
  for each row execute function public.screen_row('POST');
drop trigger if exists screen_row on public.moments;
create trigger screen_row after insert or update of caption or delete on public.moments
  for each row execute function public.screen_row('MOMENT');

-- ---------- read-side helpers ----------
create or replace function public.is_screened(p_kind text, p_ref uuid) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select p_ref is not null and exists (select 1 from public.content_screened s where s.kind = p_kind and s.ref = p_ref)
$$;
revoke execute on function public.is_screened(text, uuid) from public, anon, authenticated;

-- For the row policies: may the signed-in user see this listing / item / job? Owners, members and staff always may.
create or replace function public.screen_visible(p_kind text, p_ref uuid, p_listing uuid) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select not (public.is_screened(p_kind, p_ref) or (p_kind <> 'LISTING' and public.is_screened('LISTING', p_listing)))
      or public.listing_role(p_listing) is not null
      or exists (select 1 from public.listings l where l.id = p_listing and l.owner_id = public.me())
      or public.is_staff()
$$;
revoke execute on function public.screen_visible(text, uuid, uuid) from public, anon;
grant execute on function public.screen_visible(text, uuid, uuid) to authenticated;

drop policy if exists listings_screen on public.listings;
create policy listings_screen on public.listings as restrictive for select to authenticated using (public.screen_visible('LISTING', id, id));
drop policy if exists items_screen on public.items;
create policy items_screen on public.items as restrictive for select to authenticated using (public.screen_visible('ITEM', id, listing_id));
drop policy if exists jobs_screen on public.jobs;
create policy jobs_screen on public.jobs as restrictive for select to authenticated using (public.screen_visible('JOB', id, listing_id));

-- ---------- posts, moments, the map ----------
-- Posts and moments: hidden when their text is screened or they belong to (or are pinned at) a screened listing; the author still sees them.
create or replace function public.can_see_post(p public.posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.deleted_at is null and not blocked_between(me(), p.author_id)
         and (p.listing_id is null or exists (select 1 from listings l where l.id = p.listing_id and (l.status = 'LIVE' or listing_role(l.id) is not null)))
         and (p.author_id = me() or p.visibility in ('PUBLIC', 'LOCAL') or (p.visibility = 'SYNCED' and synced(me(), p.author_id))
              -- a store's posts reach the people who synced with the store (product_feedback.sql)
              or (p.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = p.listing_id)))
         and (p.author_id = me() or (p.listing_id is not null and listing_role(p.listing_id) is not null)
              or not (is_screened('POST', p.id) or is_screened('LISTING', p.listing_id) or is_screened('LISTING', p.place_listing)))
$$;

create or replace function public.can_see_moment(m public.moments, lat double precision default null, lng double precision default null) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select m.expires_at > now() and not blocked_between(me(), m.author_id) and (
    m.author_id = me()
    or (m.audience = 'SYNCED' and synced(me(), m.author_id))
    or (m.audience = 'CLOSE' and exists (select 1 from close_friends c where c.profile_id = m.author_id and c.friend_id = me()))
    or (m.audience = 'LOCAL' and (synced(me(), m.author_id)
        or (lat is not null and m.location is not null and st_dwithin(m.location, geo(lat, lng), 5000))
        or exists (select 1 from moment_access a where a.viewer_id = me() and a.moment_id = m.id))))
    and (m.author_id = me() or not (is_screened('MOMENT', m.id) or is_screened('LISTING', m.listing_id)))
$$;

-- The map is public to every adult on it: no exceptions.
create or replace function public.post_on_map(p public.posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.map_point is not null and p.map_off_by is null and p.deleted_at is null and p.visibility in ('PUBLIC', 'LOCAL')
     and p.map_after <= now()
     and coalesce((select value from settings where key = 'map_enabled'), 1) = 1
     and age_band_of(p.author_id) = 'ADULT'
     and exists (select 1 from map_consent c where c.profile_id = p.author_id and c.allowed)
     and exists (select 1 from profiles a where a.id = p.author_id and a.status = 'ACTIVE')
     and not exists (select 1 from map_kill_zones k where k.district = p.map_district)
     and not (is_screened('POST', p.id) or is_screened('LISTING', p.listing_id) or is_screened('LISTING', p.place_listing)
              or is_screened('LISTING', case when p.map_place = 'LISTING' and p.map_place_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                                             then p.map_place_id::uuid end))
$$;

-- ---------- search and discovery ----------
-- search_listings (search_quality.sql) with the screen: no screened shop (unless it is the searcher's own), no screened product as the
-- matched item or the "from" price.
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m integer default 10000,
                                                  kinds text[] default null, lim integer default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up integer,
               trust_down integer, details jsonb, distance_m double precision, matched_item text, min_price integer, type_key text, group_key text,
               owner_id uuid, owner_name text, matched_price integer)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t),
       vars as (select case when nullif(trim(q), '') is null then '{}'::text[] else public.search_variants(q) end a)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         m.name as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock and i.price > 0
            and not exists (select 1 from content_screened s where s.kind = 'ITEM' and s.ref = i.id)) as min_price,
         l.type_key, t.group_key, l.owner_id, coalesce(nullif(o.name, ''), 'Bucks member'),
         m.price as matched_price
  from listings l left join listing_types t on t.key = l.type_key join profiles o on o.id = l.owner_id
       cross join here cross join term cross join vars
       left join lateral (select i.name, nullif(i.price, 0)::int price from items i
                          where i.listing_id = l.id and term.t is not null and exists (select 1 from unnest(vars.a) v where public.search_item_match(i.name, v))
                            and not exists (select 1 from content_screened s where s.kind = 'ITEM' and s.ref = i.id)
                          order by i.in_stock desc, i.price limit 1) m on true
  where l.status = 'LIVE'
    and not public.blocked_between(public.me(), l.owner_id)
    and (not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
         or l.owner_id = public.me() or public.listing_role(l.id) is not null)
    and (kinds is null or l.kind = any(kinds))
    and (services is null or l.service = any(services))
    and ((l.location is not null and st_dwithin(l.location, here.g, least(greatest(coalesce(radius_m, 10000), 0), 50000)))
         or (l.kind = 'BUSINESS' and lower(coalesce(l.details->>'ships_india', '')) = 'true'))
    and (term.t is null or m.name is not null or exists (select 1 from unnest(vars.a) v where
           l.search @@ websearch_to_tsquery('simple', v) or l.title % v
           or coalesce(l.category, '') ilike '%' || v || '%' or coalesce(t.label, '') ilike '%' || v || '%' or o.name ilike '%' || v || '%'
           or (length(v) >= 5 and (word_similarity(v, l.title) >= 0.6 or word_similarity(v, coalesce(l.category, '')) >= 0.6
                                   or word_similarity(v, coalesce(t.label, '')) >= 0.6))))
  order by (l.online) desc,
           (case when term.t is null then 0 else
              (select max(ts_rank(l.search, websearch_to_tsquery('simple', v)) + similarity(l.title, v) + word_similarity(v, coalesce(l.category, '')))
                 from unnest(vars.a) v) end) desc nulls last,
           (l.trust_up - l.trust_down) desc, distance_m
  limit greatest(1, least(coalesce(lim, 40), 100))
$$;

-- search_places (places.sql): no screened shop among the Bucks places, none counted in an area, no screened place name added by people.
create or replace function public.search_places(q text, lat double precision, lng double precision, lim integer default 10)
returns table (source text, id text, name text, detail text, lat double precision, lng double precision, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with p as (select lower(regexp_replace(btrim(coalesce(q, '')), '\s+', ' ', 'g')) t, public.geo(lat, lng) here,
                    greatest(1, least(coalesce(lim, 10), 20)) n),
  bucks as (
    select 'BUCKS'::text source, l.id::text id, l.title name, concat_ws(', ', nullif(l.category, ''), nullif(l.area, '')) detail,
           st_y(l.location::geometry) lat, st_x(l.location::geometry) lng, st_distance(l.location, p.here) d,
           (lower(l.title) like p.t || '%') prefix
    from listings l, p
    where length(p.t) >= 2 and l.status = 'LIVE' and l.location is not null and not blocked_between(me(), l.owner_id)
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
      and (lower(l.title) like '%' || p.t || '%' or lower(l.title) % p.t)
      and st_dwithin(l.location, p.here, 100000)
    order by prefix desc, d limit 4),
  areas as (
    select 'AREA'::text source, null::text id, min(l.area) name, 'Area on Bucks · ' || count(*) || ' listed' detail,
           avg(st_y(l.location::geometry)) lat, avg(st_x(l.location::geometry)) lng, min(st_distance(l.location, p.here)) d,
           bool_or(lower(l.area) like p.t || '%') prefix
    from listings l, p
    where length(p.t) >= 3 and l.status = 'LIVE' and l.location is not null and l.area <> ''
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
      and (lower(l.area) like p.t || '%' or lower(l.area) % p.t) and st_dwithin(l.location, p.here, 100000)
    group by lower(l.area) order by prefix desc, d limit 3),
  people as (
    select x.* from (
      select 'PEOPLE'::text source, u.id::text id, u.name, coalesce(nullif(u.area, ''), 'Added by people on Bucks') detail, u.lat, u.lng,
             st_distance(geo(u.lat, u.lng), p.here) d, (lower(u.name) like p.t || '%') prefix
      from user_places u, p
      where length(p.t) >= 2 and not u.hidden and (u.created_by is null or not blocked_between(me(), u.created_by))
        and (lower(u.name) like '%' || p.t || '%' or lower(u.name) % p.t) and st_dwithin(geo(u.lat, u.lng), p.here, 100000)
      order by prefix desc, d limit 8) x
    where not public.screen_hit(x.name, 'SHOP')
    order by x.prefix desc, x.d limit 4),
  post_hits as (
    select x.*, (lower(x.name) like p.t || '%') prefix from localities x, p where p.t ~ '^[1-9][0-9]{5}$' and x.pincode = p.t
    union all
    select x.*, (lower(x.name) like p.t || '%') from localities x, p
    where length(p.t) >= 3 and p.t !~ '^[0-9]+$'
      and (lower(x.name) like p.t || '%' or (lower(x.name) % p.t and st_dwithin(geo(x.lat, x.lng), p.here, 100000)))),
  post as (
    select 'POST'::text source, x.id::text id, x.name, concat_ws(', ', nullif(x.district, ''), nullif(x.state, '')) || ' ' || x.pincode detail,
           x.lat, x.lng, st_distance(geo(x.lat, x.lng), p.here) d, x.prefix
    from post_hits x, p order by x.prefix desc, d limit 8)
  select r.source, r.id, r.name, r.detail, r.lat, r.lng, r.d from (
    select 1 o, source, id, name, detail, lat, lng, d from bucks
    union all select 2, source, id, name, detail, lat, lng, d from areas
    union all select 3, source, id, name, detail, lat, lng, d from people
    union all select 4, source, id, name, detail, lat, lng, d from post
  ) r
  order by r.o, r.d
  limit (select n from p)
$$;

create or replace function public.suggest_listings(lat double precision, lng double precision, lim integer default 20)
returns table (id uuid, kind text, title text, category text, area text, synced_recommenders integer, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  with mine as (select case when requester_id = me() then addressee_id else requester_id end f from syncs where status = 'ACCEPTED' and me() in (requester_id, addressee_id))
  select l.id, l.kind, l.title, l.category, l.area,
         ((select count(*) from recommendations r where r.listing_id = l.id and r.recommender_id in (select f from mine))
          + (select count(*) from reviews v where v.listing_id = l.id and v.vote = 1 and v.author_id in (select f from mine)))::int as n,
         st_distance(l.location, geo(lat, lng))
  from listings l
  where l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, geo(lat, lng), 15000)
    and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
  order by n desc, (l.trust_up - l.trust_down) desc, st_distance(l.location, geo(lat, lng))
  limit lim
$$;

-- for_you (social_lenses.sql) and for_you_named (explore.sql): posts go through can_see_post; no screened shop, no screened product.
create or replace function public.for_you(lim integer default 40)
returns table (kind text, id text, listing_id uuid, title text, subtitle text, photo_url text, recommenders integer, latest timestamptz)
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
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
    group by l.id),
  products_up as (
    select 'PRODUCT'::text, pr.product_key, l.id, coalesce((select coalesce(i.details->>'product', i.name) from items i
             where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key limit 1), 'A product'),
           l.title, (select i.photo_url from items i where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key and i.photo_url is not null limit 1),
           count(*)::int, max(pr.updated_at)
    from product_ratings pr join mine on mine.pid = pr.profile_id join listings l on l.id = pr.listing_id
    where pr.vote = 1 and l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
      and not exists (select 1 from items i join content_screened s on s.kind = 'ITEM' and s.ref = i.id
                      where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key)
    group by l.id, pr.product_key)
  select * from (select * from posts_up union all select * from listings_up union all select * from products_up) x
  where me() is not null
  order by x.recommenders desc, x.latest desc
  limit greatest(1, least(coalesce(lim, 40), 60))
$$;

create or replace function public.for_you_named(lim integer default 40)
returns table (kind text, id text, listing_id uuid, title text, subtitle text, photo_url text, recommenders integer, latest timestamptz, recommender_name text)
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
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
    group by l.id),
  products_up as (
    select 'PRODUCT'::text, pr.product_key, l.id, coalesce((select coalesce(i.details->>'product', i.name) from items i
             where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key limit 1), 'A product'),
           l.title, (select i.photo_url from items i where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key and i.photo_url is not null limit 1),
           count(*)::int, max(pr.updated_at), min(nullif(who.name, ''))
    from product_ratings pr join mine on mine.pid = pr.profile_id join profiles who on who.id = pr.profile_id join listings l on l.id = pr.listing_id
    where pr.vote = 1 and l.status = 'LIVE' and l.owner_id <> me() and not blocked_between(me(), l.owner_id)
      and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
      and not exists (select 1 from items i join content_screened s on s.kind = 'ITEM' and s.ref = i.id
                      where i.listing_id = l.id and item_product_key(i.details, i.id) = pr.product_key)
    group by l.id, pr.product_key)
  select * from (select * from listings_up union all select * from products_up) x
  where me() is not null
  order by x.recommenders desc, x.latest desc
  limit greatest(1, least(coalesce(lim, 40), 60))
$$;

-- category_suggestions (review_fixes.sql): categories offered while creating a listing come from unscreened listings only.
create or replace function public.category_suggestions(p_kind text, p_q text default '') returns table (category text, uses integer)
language sql stable security definer set search_path = public, extensions as $$
  select min(l.category) as category, count(*)::int as uses
  from listings l
  where l.kind = p_kind and l.status in ('LIVE', 'PENDING') and me() is not null
    and l.category is not null and char_length(trim(l.category)) between 2 and 40
    and l.category !~* '(verified|bucks)'
    and not exists (select 1 from content_screened s where s.kind = 'LISTING' and s.ref = l.id)
    and (coalesce(p_q, '') = '' or l.category ilike '%' || p_q || '%')
  group by lower(trim(l.category))
  order by count(*) desc, min(l.category)
  limit 40
$$;

-- jobs_near and job_page (hardening_platform.sql): no job at a screened shop, no screened job, unless it is the viewer's own.
create or replace function public.jobs_near(lat double precision, lng double precision, radius_m integer default 15000)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, pay text, job_type text, created_at timestamptz, distance_m double precision)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.pay, j.job_type, j.created_at, st_distance(l.location, public.geo(lat, lng)) as distance_m
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.open and l.status = 'LIVE' and l.location is not null and st_dwithin(l.location, public.geo(lat, lng), least(greatest(coalesce(radius_m, 15000), 0), 50000))
    and not exists (select 1 from public.content_screened s where (s.kind = 'LISTING' and s.ref = l.id) or (s.kind = 'JOB' and s.ref = j.id))
  order by distance_m, j.created_at desc
  limit 100
$$;

create or replace function public.job_page(p_job uuid)
returns table (id uuid, listing_id uuid, listing_title text, area text, title text, description text, pay text, job_type text, open boolean, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select j.id, j.listing_id, l.title, l.area, j.title, j.description, j.pay, j.job_type, j.open, j.created_at
  from public.jobs j join public.listings l on l.id = j.listing_id
  where j.id = p_job and public.me() is not null
    and ((j.open and l.status = 'LIVE') or public.can_manage_listing(j.listing_id) or exists (select 1 from public.applications a where a.job_id = j.id and a.applicant_id = public.me()))
    and (public.can_manage_listing(j.listing_id) or public.listing_role(j.listing_id) is not null
         or not exists (select 1 from public.content_screened s where (s.kind = 'LISTING' and s.ref = l.id) or (s.kind = 'JOB' and s.ref = j.id)))
$$;

-- ---------- orders ----------
-- place_order and place_order_ship already refuse a sold-out item or a closed shop; a screened one gets the same answer.
create or replace function public.screen_order() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if is_screened('LISTING', new.listing_id) then raise exception 'this shop is not taking orders'; end if;
  if exists (select 1 from jsonb_array_elements(case when jsonb_typeof(new.lines) = 'array' then new.lines else '[]'::jsonb end) x
             join content_screened s on s.kind = 'ITEM'
             where coalesce(x->>'item_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and s.ref = (x->>'item_id')::uuid) then
    raise exception 'an item is no longer available';
  end if;
  return new;
end $$;
revoke execute on function public.screen_order() from public, anon, authenticated;
drop trigger if exists screen_order on public.orders;
create trigger screen_order before insert on public.orders for each row execute function public.screen_order();

-- ---------- the term list ----------
-- Colour, fabric and garment words: "wine", "champagne" and "cocktail" next to these are a colour or a dress, not a drink.
drop trigger if exists screen_terms_changed on public.content_screen_terms;
with colour(w) as (select array['colour', 'color', 'coloured', 'colored', 'shade', 'saree', 'sari', 'kurti', 'kurta', 'dress', 'shirt', 'tshirt',
                                'lehenga', 'dupatta', 'silk', 'cotton', 'fabric', 'gown', 'blouse', 'jeans', 'trouser', 'pant', 'frock', 'maroon',
                                'velvet', 'satin', 'georgette', 'chiffon', 'linen', 'lipstick', 'nail', 'polish', 'paint', 'shoe', 'sandal', 'bag',
                                'handbag', 'wallet', 'purse', 'sweater', 'hoodie', 'jacket', 'churidar', 'chudidar', 'salwar', 'nighty', 'bedsheet',
                                'curtain', 'cushion', 'sofa', 'vinegar', 'glass', 'glasses', 'goblet',
                                'non alcoholic', 'alcohol free', 'tone', 'toned', 'finish', 'finished', 'hue', 'gold', 'golden', 'metallic', 'matte', 'glossy', 'decor', 'leatherite', 'leather', 'ceramic', 'porcelain', 'clothing', 'fashion', 'boutique', 'textile', 'textiles', 'garment', 'garments', 'tailor']),
     medical(w) as (select array['sanitizer', 'sanitiser', 'isopropyl', 'rubbing', 'swab', 'wipe', 'denatured', 'surgical spirit', 'alcohol free',
                                 'alcohol based', 'syrup', 'tablet', 'capsule', 'tonic', 'arishta', 'arishtam', 'asava', 'asavam', 'tincture',
                                 'homeopathy', 'homeopathic', 'ayurvedic', 'ayurveda', 'medical', 'medicals', 'pharmacy', 'chemist', 'chemists',
                                 'pharma', 'medicine', 'perfume', 'deodorant', 'deo', 'fragrance', 'attar', 'toner', 'serum', 'mouthwash', 'lab',
                                 'laboratory', 'hospital', 'clinic'])
insert into public.content_screen_terms (term, how, scope, unless_words, grp)
select v.term, v.how, v.scope,
       case v.unless when 'COLOUR' then (select w from colour) when 'MEDICAL' then (select w from medical) else string_to_array(v.unless, ',') end,
       v.grp
from (values
  -- pork (English, romanised, Hindi, Kannada, Malayalam, Tamil, Telugu)
  ('pork', 'WORD', 'ALL', 'pork free,masala powder,masala mix,spice mix', 'pork'), ('pig', 'WORD', 'ALL', 'guinea,iron,piggy,bank,soft,plush,toy,doll,figurine,cartoon,peppa,statue', 'pork'),
  ('piglet', 'WORD', 'ALL', 'soft,plush,toy,doll,cartoon', 'pork'), ('swine', 'WORD', 'ALL', 'swine flu', 'pork'),
  ('bacon', 'WORD', 'ALL', 'chicken,turkey,veg,vegan', 'pork'), ('lard', 'WORD', 'ALL', 'lard free', 'pork'),
  
  ('prosciutto', 'WORD', 'ALL', '', 'pork'), ('pancetta', 'WORD', 'ALL', '', 'pork'), ('chorizo', 'WORD', 'ALL', 'chicken,veg', 'pork'),
  ('chourico', 'WORD', 'ALL', 'chicken,veg', 'pork'), ('goa sausage', 'WORD', 'ALL', 'chicken', 'pork'), ('sorpotel', 'WORD', 'ALL', 'masala,chicken', 'pork'), ('porcine', 'WORD', 'ALL', '', 'pork'), ('pig fat', 'WORD', 'ALL', '', 'pork'),
  ('pandi curry', 'WORD', 'ALL', '', 'pork'), ('pandi fry', 'WORD', 'ALL', '', 'pork'), ('pandi roast', 'WORD', 'ALL', '', 'pork'), ('pandi masala', 'WORD', 'ALL', '', 'pork'), ('pandi kari', 'WORD', 'ALL', '', 'pork'), ('pandi meat', 'WORD', 'ALL', '', 'pork'),
  ('panni kari', 'WORD', 'ALL', '', 'pork'), ('panni curry', 'WORD', 'ALL', '', 'pork'), ('panni fry', 'WORD', 'ALL', '', 'pork'), ('panni irachi', 'WORD', 'ALL', '', 'pork'), ('khinzir', 'WORD', 'ALL', '', 'pork'), ('خنزیر', 'EXACT', 'ALL', '', 'pork'), ('خنزير', 'EXACT', 'ALL', '', 'pork'),
  ('suar', 'WORD', 'ALL', '', 'pork'), ('suwar', 'WORD', 'ALL', '', 'pork'), ('sooar', 'WORD', 'ALL', '', 'pork'), 
  ('panri', 'WORD', 'ALL', '', 'pork'),
  ('सूअर', 'PREFIX', 'ALL', '', 'pork'), ('सुअर', 'PREFIX', 'ALL', '', 'pork'), ('पोर्क', 'EXACT', 'ALL', '', 'pork'),
  ('ಹಂದಿ', 'PREFIX', 'ALL', '', 'pork'), ('ಪೋರ್ಕ್', 'EXACT', 'ALL', '', 'pork'),
  ('പന്നി', 'EXACT', 'ALL', '', 'pork'), ('പന്നിയിറച്ചി', 'PREFIX', 'ALL', '', 'pork'), ('പോർക്ക്', 'EXACT', 'ALL', '', 'pork'),
  ('பன்றி', 'PREFIX', 'ALL', '', 'pork'), ('போர்க்', 'EXACT', 'ALL', '', 'pork'),
  ('పంది', 'EXACT', 'ALL', '', 'pork'), ('పందిమాంసం', 'PREFIX', 'ALL', '', 'pork'), ('పోర్క్', 'EXACT', 'ALL', '', 'pork'),
  -- alcohol
  ('alcohol', 'WORD', 'ALL', 'MEDICAL', 'alcohol'), ('alcoholic', 'WORD', 'ALL', 'MEDICAL', 'alcohol'), ('liquor', 'WORD', 'ALL', '', 'alcohol'),
  ('liqueur', 'WORD', 'ALL', '', 'alcohol'), ('beer', 'WORD', 'ALL', 'root,ginger,non alcoholic,alcohol free,0 0,zero alcohol,mug,glass,opener', 'alcohol'), ('wine', 'WORD', 'ALL', 'COLOUR', 'alcohol'),
  ('whisky', 'WORD', 'ALL', '', 'alcohol'), ('whiskey', 'WORD', 'ALL', '', 'alcohol'), ('whiskies', 'WORD', 'ALL', '', 'alcohol'),
  ('vodka', 'WORD', 'ALL', '', 'alcohol'), ('rum', 'WORD', 'ALL', 'essence,flavour,flavor,raisin', 'alcohol'), ('gin', 'WORD', 'SHOP', 'cotton,ginning', 'alcohol'),
  ('brandy', 'WORD', 'ALL', '', 'alcohol'), ('tequila', 'WORD', 'ALL', '', 'alcohol'), ('cognac', 'WORD', 'ALL', 'COLOUR', 'alcohol'), ('champagne', 'WORD', 'ALL', 'COLOUR', 'alcohol'),
  ('scotch', 'WORD', 'ALL', 'brite,tape,egg,bonnet', 'alcohol'), ('cider', 'WORD', 'ALL', 'vinegar', 'alcohol'),
  ('cocktail', 'WORD', 'ALL', 'dress,saree,gown,ring,frock,fruit,party wear,mocktail', 'alcohol'),
  ('toddy', 'WORD', 'ALL', 'jaggery,nungu,ice apple,neera,candy,sugar,fruit', 'alcohol'), ('arrack', 'WORD', 'ALL', '', 'alcohol'),
  ('daru', 'WORD', 'ALL', '', 'alcohol'), ('daaru', 'WORD', 'ALL', '', 'alcohol'),
  ('sharab', 'WORD', 'ALL', '', 'alcohol'), ('sharaab', 'WORD', 'ALL', '', 'alcohol'), ('madira', 'WORD', 'ALL', '', 'alcohol'),
  ('madya', 'WORD', 'ALL', '', 'alcohol'), ('madyam', 'WORD', 'ALL', '', 'alcohol'), ('sarayi', 'WORD', 'ALL', '', 'alcohol'),
  ('saarayi', 'WORD', 'ALL', '', 'alcohol'), ('saraayi', 'WORD', 'ALL', '', 'alcohol'), ('charayam', 'WORD', 'ALL', '', 'alcohol'),
  ('chaarayam', 'WORD', 'ALL', '', 'alcohol'), ('sarayam', 'WORD', 'ALL', '', 'alcohol'), ('hooch', 'WORD', 'ALL', '', 'alcohol'),
  ('tharra', 'WORD', 'ALL', '', 'alcohol'), ('imfl', 'WORD', 'ALL', '', 'alcohol'), ('pub', 'WORD', 'ALL', '', 'alcohol'),
  ('brewery', 'WORD', 'ALL', '', 'alcohol'), ('breweries', 'WORD', 'ALL', '', 'alcohol'), ('brewpub', 'WORD', 'ALL', '', 'alcohol'),
  ('microbrewery', 'WORD', 'ALL', '', 'alcohol'), ('distillery', 'WORD', 'ALL', '', 'alcohol'), ('tavern', 'WORD', 'ALL', '', 'alcohol'),
  ('bar and restaurant', 'WORD', 'ALL', '', 'alcohol'), ('bar restaurant', 'WORD', 'ALL', '', 'alcohol'), ('bar n restaurant', 'WORD', 'ALL', '', 'alcohol'),
  ('bar and lounge', 'WORD', 'ALL', '', 'alcohol'), ('lounge bar', 'WORD', 'ALL', '', 'alcohol'), ('rooftop bar', 'WORD', 'ALL', '', 'alcohol'),
  ('sports bar', 'WORD', 'ALL', '', 'alcohol'), ('family bar', 'WORD', 'ALL', '', 'alcohol'), ('dance bar', 'WORD', 'ALL', '', 'alcohol'),
  ('bevco', 'WORD', 'ALL', '', 'alcohol'), ('bevq', 'WORD', 'ALL', '', 'alcohol'), ('tasmac', 'WORD', 'ALL', '', 'alcohol'),
  ('cashew feni', 'WORD', 'ALL', '', 'alcohol'), ('coconut feni', 'WORD', 'ALL', '', 'alcohol'), ('goa feni', 'WORD', 'ALL', '', 'alcohol'), ('tsbcl', 'WORD', 'ALL', '', 'alcohol'), ('apsbcl', 'WORD', 'ALL', '', 'alcohol'), ('ksbcl', 'WORD', 'ALL', '', 'alcohol'),
  ('royal stag whisky', 'WORD', 'ALL', '', 'alcohol'), ('imperial blue whisky', 'WORD', 'ALL', '', 'alcohol'), ('شراب', 'EXACT', 'ALL', '', 'alcohol'),
  ('old monk', 'WORD', 'ALL', '', 'alcohol'), ('smirnoff', 'WORD', 'ALL', '', 'alcohol'), ('budweiser', 'WORD', 'ALL', '', 'alcohol'),
  ('heineken', 'WORD', 'ALL', '', 'alcohol'), ('carlsberg', 'WORD', 'ALL', '', 'alcohol'), ('bacardi', 'WORD', 'ALL', '', 'alcohol'),
  ('johnnie walker', 'WORD', 'ALL', '', 'alcohol'), 
  
  ('kingfisher strong', 'WORD', 'ALL', '', 'alcohol'), ('kingfisher ultra', 'WORD', 'ALL', '', 'alcohol'),
  ('breezer', 'WORD', 'ALL', '', 'alcohol'),
  ('शराब', 'PREFIX', 'ALL', '', 'alcohol'), ('दारू', 'PREFIX', 'ALL', '', 'alcohol'), ('मदिरा', 'PREFIX', 'ALL', '', 'alcohol'), ('मद्य', 'PREFIX', 'ALL', '', 'alcohol'),
  ('बीयर', 'EXACT', 'ALL', '', 'alcohol'), ('बियर', 'EXACT', 'ALL', '', 'alcohol'), ('व्हिस्की', 'PREFIX', 'ALL', '', 'alcohol'),
  ('वोडका', 'PREFIX', 'ALL', '', 'alcohol'), ('ताड़ी', 'EXACT', 'ALL', '', 'alcohol'),
  ('ಮದ್ಯ', 'PREFIX', 'ALL', '', 'alcohol'), ('ಸಾರಾಯಿ', 'PREFIX', 'ALL', '', 'alcohol'), ('ಹೆಂಡ', 'EXACT', 'ALL', '', 'alcohol'),
  ('ಬಿಯರ್', 'EXACT', 'ALL', '', 'alcohol'), ('ವಿಸ್ಕಿ', 'EXACT', 'ALL', '', 'alcohol'), ('ಕಳ್ಳು', 'EXACT', 'ALL', '', 'alcohol'),
  ('മദ്യ', 'PREFIX', 'ALL', '', 'alcohol'), ('ചാരായ', 'PREFIX', 'ALL', '', 'alcohol'), ('കള്ള്', 'EXACT', 'ALL', '', 'alcohol'),
  ('കള്ളുഷാപ്പ', 'PREFIX', 'ALL', '', 'alcohol'), ('ബിയർ', 'EXACT', 'ALL', '', 'alcohol'), ('വിസ്കി', 'EXACT', 'ALL', '', 'alcohol'),
  ('மதுபான', 'PREFIX', 'ALL', '', 'alcohol'), ('சாராய', 'PREFIX', 'ALL', '', 'alcohol'), ('பீர்', 'EXACT', 'ALL', '', 'alcohol'),
  ('விஸ்கி', 'EXACT', 'ALL', '', 'alcohol'), ('டாஸ்மாக', 'PREFIX', 'ALL', '', 'alcohol'),
  ('మద్య', 'PREFIX', 'ALL', '', 'alcohol'), ('సారా', 'EXACT', 'ALL', '', 'alcohol'), ('కల్లు', 'EXACT', 'ALL', '', 'alcohol'),
  ('బీరు', 'EXACT', 'ALL', '', 'alcohol'), ('బీర్', 'EXACT', 'ALL', '', 'alcohol'), ('విస్కీ', 'EXACT', 'ALL', '', 'alcohol'),
  -- intoxicants (pharmacy medicines are not on this list)
  ('weed', 'WORD', 'ALL', 'killer,remover,removal,control,cutter,trimmer,mat,garden,lawn,grass,pulling,puller,brush,sea,wacker,weedicide,herbicide,spray,kill,farm,agriculture', 'drugs'),
  ('ganja', 'WORD', 'ALL', '', 'drugs'), ('gaanja', 'WORD', 'ALL', '', 'drugs'), ('ganjaa', 'WORD', 'ALL', '', 'drugs'), ('kanja', 'WORD', 'ALL', '', 'drugs'),
  ('kanjav', 'WORD', 'ALL', '', 'drugs'), ('kanjavu', 'WORD', 'ALL', '', 'drugs'), ('marijuana', 'WORD', 'ALL', '', 'drugs'),
  ('marihuana', 'WORD', 'ALL', '', 'drugs'), ('cannabis', 'WORD', 'ALL', 'cbd,hemp seed,hemp oil', 'drugs'), ('hashish', 'WORD', 'ALL', '', 'drugs'),
  ('charas', 'WORD', 'ALL', '', 'drugs'), ('bhang', 'WORD', 'ALL', '', 'drugs'), ('afeem', 'WORD', 'ALL', '', 'drugs'), ('afim', 'WORD', 'ALL', '', 'drugs'),
  ('opium', 'WORD', 'ALL', 'perfume,edp,edt,fragrance,deodorant,spray,attar', 'drugs'), ('heroin', 'WORD', 'ALL', '', 'drugs'),
  ('cocaine', 'WORD', 'ALL', '', 'drugs'), ('mdma', 'WORD', 'ALL', '', 'drugs'), ('ecstasy', 'WORD', 'ALL', '', 'drugs'), ('lsd', 'WORD', 'ALL', '', 'drugs'),
  ('meth', 'WORD', 'ALL', '', 'drugs'), ('methamphetamine', 'WORD', 'ALL', '', 'drugs'), ('mephedrone', 'WORD', 'ALL', '', 'drugs'),
  ('bhukki', 'WORD', 'ALL', '', 'drugs'), ('aphim', 'WORD', 'ALL', '', 'drugs'), ('kanchavu', 'WORD', 'ALL', '', 'drugs'), ('ganjayi', 'WORD', 'ALL', '', 'drugs'), ('nallamandu', 'WORD', 'ALL', '', 'drugs'), ('hash oil', 'WORD', 'ALL', '', 'drugs'), ('malana cream', 'WORD', 'ALL', '', 'drugs'),
  ('گانجا', 'EXACT', 'ALL', '', 'drugs'), ('چرس', 'EXACT', 'ALL', '', 'drugs'), ('افیون', 'EXACT', 'ALL', '', 'drugs'),
  ('magic mushroom', 'WORD', 'ALL', '', 'drugs'), ('shrooms', 'WORD', 'ALL', '', 'drugs'), 
  ('smack', 'WORD', 'SHOP', '', 'drugs'), 
  ('poppy husk', 'WORD', 'ALL', '', 'drugs'), ('doda post', 'WORD', 'ALL', '', 'drugs'), ('illegal drugs', 'WORD', 'ALL', '', 'drugs'),
  ('party drugs', 'WORD', 'ALL', '', 'drugs'), ('recreational drugs', 'WORD', 'ALL', '', 'drugs'), ('street drugs', 'WORD', 'ALL', '', 'drugs'),
  ('drug dealer', 'WORD', 'ALL', '', 'drugs'), ('drug peddler', 'WORD', 'ALL', '', 'drugs'),
  ('गांजा', 'PREFIX', 'ALL', '', 'drugs'), ('गाँजा', 'PREFIX', 'ALL', '', 'drugs'), ('चरस', 'EXACT', 'ALL', '', 'drugs'), ('अफीम', 'PREFIX', 'ALL', '', 'drugs'),
  ('भांग', 'EXACT', 'ALL', '', 'drugs'), ('हेरोइन', 'PREFIX', 'ALL', '', 'drugs'), ('कोकीन', 'PREFIX', 'ALL', '', 'drugs'),
  ('ಗಾಂಜಾ', 'PREFIX', 'ALL', '', 'drugs'), ('ಅಫೀಮು', 'PREFIX', 'ALL', '', 'drugs'),
  ('കഞ്ചാവ', 'PREFIX', 'ALL', '', 'drugs'), ('എംഡിഎംഎ', 'PREFIX', 'ALL', '', 'drugs'),
  ('கஞ்சா', 'PREFIX', 'ALL', '', 'drugs'), ('அபின்', 'EXACT', 'ALL', '', 'drugs'),
  ('గంజాయ', 'PREFIX', 'ALL', '', 'drugs'), ('నల్లమందు', 'PREFIX', 'ALL', '', 'drugs'),
  -- adult products and services
  ('sex toy', 'WORD', 'ALL', '', 'adult'), ('sextoy', 'PART', 'ALL', '', 'adult'), ('adult toy', 'WORD', 'ALL', '', 'adult'),
  ('adult store', 'WORD', 'ALL', '', 'adult'), ('adult shop', 'WORD', 'ALL', '', 'adult'), ('sex shop', 'WORD', 'ALL', '', 'adult'),
  ('dildo', 'PART', 'ALL', '', 'adult'), ('vibrator', 'WORD', 'ALL', 'concrete,needle,motor,construction,plate,poker,mobile,phone,massager,hair', 'adult'),
  ('fleshlight', 'PART', 'ALL', '', 'adult'), ('butt plug', 'WORD', 'ALL', '', 'adult'), ('buttplug', 'PART', 'ALL', '', 'adult'),
  ('anal plug', 'WORD', 'ALL', '', 'adult'), ('masturbat', 'PART', 'ALL', '', 'adult'), ('sex doll', 'WORD', 'ALL', '', 'adult'),
  ('cock ring', 'WORD', 'ALL', '', 'adult'), ('penis pump', 'WORD', 'ALL', '', 'adult'), ('penis enlarger', 'WORD', 'ALL', '', 'adult'),
  ('penis enlargement', 'WORD', 'ALL', '', 'adult'), ('strap on', 'WORD', 'ALL', '', 'adult'), ('strapon', 'WORD', 'ALL', '', 'adult'),
  ('bdsm', 'WORD', 'ALL', '', 'adult'), ('bondage', 'WORD', 'ALL', '', 'adult'), ('erotic', 'WORD', 'ALL', '', 'adult'),
  ('porn', 'WORD', 'ALL', '', 'adult'), ('porno', 'WORD', 'ALL', '', 'adult'), ('pornography', 'WORD', 'ALL', '', 'adult'),
  ('pornographic', 'WORD', 'ALL', '', 'adult'), ('xxx', 'WORD', 'ALL', '', 'adult'), ('escort service', 'WORD', 'ALL', '', 'adult'),
  ('call girl', 'WORD', 'ALL', '', 'adult'), ('body to body massage', 'WORD', 'ALL', '', 'adult'),
  ('love doll', 'WORD', 'ALL', '', 'adult'), ('blue film', 'WORD', 'ALL', '', 'adult'), ('nude video call', 'WORD', 'ALL', '', 'adult'), ('callgirl', 'WORD', 'ALL', '', 'adult'), ('gigolo', 'WORD', 'ALL', '', 'adult'), ('playboy job', 'WORD', 'ALL', '', 'adult'),
  ('b2b massage', 'WORD', 'ALL', '', 'adult'), ('nuru massage', 'WORD', 'ALL', '', 'adult'), ('cross massage', 'WORD', 'ALL', '', 'adult'), ('happy ending massage', 'WORD', 'ALL', '', 'adult'), ('randi', 'WORD', 'ALL', '', 'adult'), ('chudai', 'WORD', 'ALL', '', 'adult'),
  ('वेश्या', 'PREFIX', 'ALL', '', 'adult'), ('देह व्यापार', 'EXACT', 'ALL', '', 'adult'), ('जिस्मफरोशी', 'PREFIX', 'ALL', '', 'adult'), ('रंडी', 'EXACT', 'ALL', '', 'adult'), ('ವೇಶ್ಯೆ', 'EXACT', 'ALL', '', 'adult'), ('വേശ്യ', 'PREFIX', 'ALL', '', 'adult'),
  ('പെൺവാണിഭ', 'PREFIX', 'ALL', '', 'adult'), ('விபச்சார', 'PREFIX', 'ALL', '', 'adult'), ('వ్యభిచార', 'PREFIX', 'ALL', '', 'adult'), ('వేశ్య', 'EXACT', 'ALL', '', 'adult'), 
  ('सेक्स टॉय', 'EXACT', 'ALL', '', 'adult'),
  -- gambling, sorcery and riba (astrology, ruqyah, chess, cards and ludo without a stake stay visible)
  ('casino', 'WORD', 'ALL', '', 'gambling'), ('gambling', 'WORD', 'ALL', '', 'gambling'), ('betting', 'WORD', 'ALL', '', 'gambling'),
  ('bookie', 'WORD', 'ALL', '', 'gambling'), ('satta matka', 'WORD', 'ALL', '', 'gambling'), ('satta king', 'WORD', 'ALL', '', 'gambling'),
  ('satta bazar', 'WORD', 'ALL', '', 'gambling'), ('matka result', 'WORD', 'ALL', '', 'gambling'), ('lottery', 'WORD', 'ALL', '', 'gambling'),
  ('teen patti', 'WORD', 'ALL', '', 'gambling'),
  ('andar bahar', 'WORD', 'ALL', '', 'gambling'), ('kalyan matka', 'WORD', 'ALL', '', 'gambling'), ('mumbai matka', 'WORD', 'ALL', '', 'gambling'), ('rummy cash', 'WORD', 'ALL', '', 'gambling'), ('cash rummy', 'WORD', 'ALL', '', 'gambling'), ('real money game', 'WORD', 'ALL', '', 'gambling'), ('online poker', 'WORD', 'ALL', '', 'gambling'),
  ('jinn hazir', 'WORD', 'ALL', '', 'gambling'), ('hamzad', 'WORD', 'ALL', '', 'gambling'), ('sifli amal', 'WORD', 'ALL', '', 'gambling'),
  -- riba: lending at interest in the local idiom (bank and savings ads use the bare interest words, which stay visible)
  ('vattiku panam', 'WORD', 'ALL', '', 'riba'), ('meter vatti', 'WORD', 'ALL', '', 'riba'), ('kandu vatti', 'WORD', 'ALL', '', 'riba'), ('palisakku panam', 'WORD', 'ALL', '', 'riba'), ('byaj par paisa', 'WORD', 'ALL', '', 'riba'), ('baddi saala', 'WORD', 'ALL', '', 'riba'), ('vaddi ki dabbulu', 'WORD', 'ALL', '', 'riba'), 
  ('black magic', 'WORD', 'ALL', 'ruqyah,ruqya,quran,quranic', 'gambling'), ('vashikaran', 'WORD', 'ALL', '', 'gambling'), ('kala jadu', 'WORD', 'ALL', 'ruqyah,ruqya,quran,quranic', 'gambling'),
  ('kaala jadu', 'WORD', 'ALL', 'ruqyah,ruqya,quran,quranic', 'gambling'),
  -- clearly illegal goods
  ('firearm', 'WORD', 'ALL', '', 'illegal'), ('pistol', 'WORD', 'ALL', 'toy,water,spray,paint,glue,grease,nozzle,foam,wash,washer,car,garden,massage', 'illegal'),
  ('revolver', 'WORD', 'ALL', 'toy', 'illegal'), ('desi katta', 'WORD', 'ALL', '', 'illegal'), ('ammunition', 'WORD', 'ALL', '', 'illegal'),
  ('live cartridge', 'WORD', 'ALL', '', 'illegal'), ('explosive', 'WORD', 'ALL', '', 'illegal'), ('detonator', 'WORD', 'ALL', '', 'illegal'),
  ('gelatin stick', 'WORD', 'ALL', '', 'illegal'), ('gelatine stick', 'WORD', 'ALL', '', 'illegal'), ('fake currency', 'WORD', 'ALL', '', 'illegal'),
  ('counterfeit', 'WORD', 'ALL', '', 'illegal'), ('fake note', 'WORD', 'ALL', '', 'illegal'), ('fake id', 'WORD', 'ALL', '', 'illegal'),
  ('fake aadhaar', 'WORD', 'ALL', '', 'illegal'), ('fake aadhar', 'WORD', 'ALL', '', 'illegal'), ('fake pan card', 'WORD', 'ALL', '', 'illegal'),
  ('fake certificate', 'WORD', 'ALL', '', 'illegal'), ('fake degree', 'WORD', 'ALL', '', 'illegal'), ('fake marksheet', 'WORD', 'ALL', '', 'illegal'),
  ('fake passport', 'WORD', 'ALL', '', 'illegal'), ('fake license', 'WORD', 'ALL', '', 'illegal'), ('fake licence', 'WORD', 'ALL', '', 'illegal'),
  ('hacked account', 'WORD', 'ALL', '', 'illegal'), ('cloned card', 'WORD', 'ALL', '', 'illegal'), ('hawala', 'WORD', 'ALL', '', 'illegal'),
  ('elephant ivory', 'WORD', 'ALL', '', 'illegal'), ('ivory tusk', 'WORD', 'ALL', '', 'illegal'), ('tiger skin', 'WORD', 'ALL', '', 'illegal'),
  ('tiger claw', 'WORD', 'ALL', '', 'illegal'), ('tiger nail', 'WORD', 'ALL', '', 'illegal'), ('leopard skin', 'WORD', 'ALL', '', 'illegal'),
  ('rhino horn', 'WORD', 'ALL', '', 'illegal'), ('pangolin', 'WORD', 'ALL', '', 'illegal'), ('star tortoise', 'WORD', 'ALL', '', 'illegal'),
  ('kidney for sale', 'WORD', 'ALL', '', 'illegal'), ('sell kidney', 'WORD', 'ALL', '', 'illegal'), ('organ for sale', 'WORD', 'ALL', '', 'illegal'),
  ('red mercury', 'WORD', 'ALL', '', 'illegal'),
  ('copper iridium', 'WORD', 'ALL', '', 'illegal'), ('money doubling', 'WORD', 'ALL', '', 'illegal'), ('double money', 'WORD', 'ALL', '', 'illegal'), ('hatha jodi', 'WORD', 'ALL', '', 'illegal'), ('country made pistol', 'WORD', 'ALL', '', 'illegal'), ('rice puller', 'WORD', 'ALL', '', 'illegal')
) v(term, how, scope, unless, grp)
on conflict (term) do update set how = excluded.how, scope = excluded.scope, unless_words = excluded.unless_words, grp = excluded.grp;

create trigger screen_terms_changed after insert or update or delete or truncate on public.content_screen_terms
  for each statement execute function public.screen_terms_changed();

-- Screen everything already on Bucks.
select public.rescreen_all();
