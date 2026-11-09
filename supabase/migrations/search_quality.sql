-- Search that finds what people type in tier 2/3 towns (docs/CORE_FLOWS.md §6):
--   1. plurals ("plumbers" finds a plumber, "batteries" a battery),
--   2. small typos ("electrecian", "plumbr") on names, categories and products,
--   3. everyday and vernacular words ("bijli wala", "darzi", "kirana") mapped to the categories people list under,
--   4. a product matches on all its words in any order ("basmati rice" finds "Rice, Basmati 1 kg"),
--   5. the result carries the matched product's own price (matched_price), not just the shop's cheapest item.
-- search_listings from delivery_assignment.sql, otherwise unchanged (blocks, radius, ships_india, ordering).
-- Safe to run more than once. Apply after delivery_assignment.sql (supabase/apply_all.sh does).
set search_path = public, extensions;

-- ---------- 1. words people use → what the pages are listed as ----------
create table if not exists public.search_synonyms (word text primary key, means text not null);
alter table public.search_synonyms enable row level security;   -- read only through search_variants (security definer)
revoke all on public.search_synonyms from public, anon, authenticated;

insert into public.search_synonyms (word, means) values
  ('bijli wala', 'electrician'), ('bijliwala', 'electrician'), ('wireman', 'electrician'), ('electric', 'electrician'),
  ('nal wala', 'plumber'), ('nalwala', 'plumber'), ('pipe fitter', 'plumber'), ('plumbing', 'plumber'),
  ('mistri', 'mason'), ('raj mistri', 'mason'), ('construction', 'mason'),
  ('badhai', 'carpenter'), ('carpentry', 'carpenter'), ('furniture repair', 'carpenter'),
  ('darzi', 'tailor'), ('tailoring', 'tailor'), ('stitching', 'tailor'), ('alteration', 'tailor'),
  ('dhobi', 'laundry'), ('istri', 'laundry'), ('ironing', 'laundry'), ('dry clean', 'laundry'),
  ('nai', 'barber'), ('hair cut', 'barber'), ('haircut', 'barber'), ('salon', 'barber'), ('parlour', 'beauty'), ('parlor', 'beauty'),
  ('kirana', 'grocery'), ('kiryana', 'grocery'), ('general store', 'grocery'), ('provision', 'grocery'), ('supermarket', 'grocery'),
  ('sabzi', 'vegetables'), ('sabji', 'vegetables'), ('subzi', 'vegetables'), ('veggies', 'vegetables'), ('phal', 'fruits'),
  ('dawai', 'pharmacy'), ('dawa', 'pharmacy'), ('medical', 'pharmacy'), ('chemist', 'pharmacy'), ('medicine', 'pharmacy'),
  ('doodh', 'milk'), ('dairy', 'milk'), ('mithai', 'sweets'), ('halwai', 'sweets'),
  ('dhaba', 'restaurant'), ('hotel', 'restaurant'), ('khana', 'food'), ('tiffin', 'food'), ('mess', 'food'),
  ('rangai', 'painter'), ('painting', 'painter'), ('putai', 'painter'),
  ('ac repair', 'ac mechanic'), ('ac service', 'ac mechanic'), ('fridge repair', 'appliance repair'), ('tv repair', 'appliance repair'),
  ('mobile repair', 'phone repair'), ('bike repair', 'mechanic'), ('garage', 'mechanic'), ('puncture', 'mechanic'),
  ('tuition', 'tutor'), ('coaching', 'tutor'), ('teacher', 'tutor'),
  ('maid', 'house help'), ('bai', 'house help'), ('cook', 'house help'), ('driver', 'driver'), ('taxi', 'cab'), ('rickshaw', 'auto')
on conflict (word) do nothing;

-- ---------- 2. the forms of a query to look for ----------
-- One word to its singular: batteries → battery, boxes → box, plumbers → plumber; glass, bus and short words stay.
create or replace function public.search_singular(w text) returns text language sql immutable set search_path = public, extensions as $$
  select case
    when length(w) > 4 and w ~ 'ies$' then regexp_replace(w, 'ies$', 'y')
    when length(w) > 4 and w ~ '(ch|sh|x|ss|z)es$' then regexp_replace(w, 'es$', '')
    when length(w) > 3 and w ~ 's$' and w !~ '(ss|us|is)$' then regexp_replace(w, 's$', '')
    else w end
$$;

-- The query as typed, each word made singular, and what a known phrase or word means (whole query first, then word by word).
create or replace function public.search_variants(q text) returns text[] language sql stable security definer set search_path = public, extensions as $$
  with t as (select lower(regexp_replace(trim(coalesce(q, '')), '\s+', ' ', 'g')) raw),
       s as (select raw, (select string_agg(public.search_singular(w), ' ' order by n) from unnest(string_to_array(raw, ' ')) with ordinality u(w, n)) sing from t),
       forms as (
         select raw f from s union select sing from s
         union select y.means from s join search_synonyms y on y.word in (s.raw, s.sing)
         union select (select string_agg(coalesce(y.means, w), ' ' order by n) from unnest(string_to_array(s.sing, ' ')) with ordinality u(w, n)
                        left join search_synonyms y on y.word = w) from s)
  select coalesce(array_agg(distinct f) filter (where f <> ''), '{}') from forms
$$;

-- Does a product name answer a query form: every word of it (in any order), or close enough for a typo.
create or replace function public.search_item_match(name text, v text) returns boolean language sql immutable set search_path = public, extensions as $$
  select coalesce((select bool_and(name ilike '%' || w || '%') from unnest(string_to_array(v, ' ')) w where w <> ''), false)
      or (length(v) >= 5 and word_similarity(v, name) >= 0.6)
$$;

-- ---------- 3. search ----------
drop function if exists public.search_listings(text, double precision, double precision, int, text[], int, text[]);
create or replace function public.search_listings(q text, lat double precision, lng double precision, radius_m int default 10000, kinds text[] default null,
                                                  lim int default 40, services text[] default null)
returns table (id uuid, kind text, title text, category text, description text, photo_url text, area text, online boolean, trust_up int, trust_down int,
               details jsonb, distance_m double precision, matched_item text, min_price int, type_key text, group_key text, owner_id uuid, owner_name text,
               matched_price int)
language sql stable security definer set search_path = public, extensions as $$
  with here as (select public.geo(lat, lng) g), term as (select nullif(trim(q), '') t),
       vars as (select case when nullif(trim(q), '') is null then '{}'::text[] else public.search_variants(q) end a)
  select l.id, l.kind, l.title, l.category, l.description, l.photo_url, l.area, l.online, l.trust_up, l.trust_down, l.details,
         st_distance(l.location, here.g) as distance_m,
         m.name as matched_item,
         (select min(i.price) from items i where i.listing_id = l.id and i.in_stock and i.price > 0) as min_price,
         l.type_key, t.group_key, l.owner_id, coalesce(nullif(o.name, ''), 'Bucks member'),
         m.price as matched_price
  from listings l left join listing_types t on t.key = l.type_key join profiles o on o.id = l.owner_id
       cross join here cross join term cross join vars
       -- The cheapest in-stock product that answers the query (out of stock only when nothing else does).
       left join lateral (select i.name, nullif(i.price, 0)::int price from items i
                          where i.listing_id = l.id and term.t is not null and exists (select 1 from unnest(vars.a) v where public.search_item_match(i.name, v))
                          order by i.in_stock desc, i.price limit 1) m on true
  where l.status = 'LIVE'
    and not public.blocked_between(public.me(), l.owner_id)
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

-- ---------- grants ----------
revoke all on function public.search_listings(text, double precision, double precision, int, text[], int, text[]) from public, anon;
grant execute on function public.search_listings(text, double precision, double precision, int, text[], int, text[]) to authenticated;
revoke all on function public.search_variants(text) from public, anon;
grant execute on function public.search_variants(text) to authenticated;
revoke all on function public.search_singular(text), public.search_item_match(text, text) from public, anon;
grant execute on function public.search_singular(text), public.search_item_match(text, text) to authenticated;

-- ---------- 4. call the owner, when they allow it ----------
-- A page's owner can show a Call button (details.show_phone). Then the page gives their verified phone, and only that: never
-- to anyone they blocked or who blocked them, and nothing when the switch is off or the page isn't live.
create or replace function public.listing_phone(p_listing uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select o.phone from listings l join profiles o on o.id = l.owner_id
  where l.id = p_listing and l.status = 'LIVE' and l.kind in ('BUSINESS', 'SKILL')
    and lower(coalesce(l.details->>'show_phone', '')) = 'true' and nullif(o.phone, '') is not null
    and public.me() is not null and not public.blocked_between(public.me(), l.owner_id)
$$;
revoke all on function public.listing_phone(uuid) from public, anon;
grant execute on function public.listing_phone(uuid) to authenticated;
