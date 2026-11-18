-- Places that maps miss in tier 2/3 towns. Place search (search_places) looks, in this order, at:
--   1. Bucks itself: live shops and pros by name, and the areas they are listed in;
--   2. places people dropped a pin for (add_place) when nothing else knew them;
--   3. India Post localities: every post office's village or locality with its pincode, district and state
--      (supabase/seed/localities, from the All India Pincode Directory, data.gov.in, Government Open Data License - India).
-- The app shows these first, then OpenStreetMap / Mapbox results (MapServices).
-- Safe to run more than once. Apply after search_quality.sql (supabase/apply_all.sh does). The locality rows are loaded
-- separately (supabase/seed/load_localities.sql), not by this file.
set search_path = public, extensions;

-- ---------- India Post localities ----------
create table if not exists public.localities (
  id       bigint generated always as identity primary key,
  name     text not null,
  district text not null default '',
  state    text not null default '',
  pincode  text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  lat      double precision not null check (lat between 6 and 38),
  lng      double precision not null check (lng between 68 and 98),
  unique (name, pincode)
);
create index if not exists localities_name_trgm on public.localities using gin (lower(name) gin_trgm_ops);
create index if not exists localities_pincode on public.localities (pincode);
alter table public.localities enable row level security;   -- read through search_places only
revoke all on public.localities from public, anon, authenticated;

-- ---------- places people add ----------
create table if not exists public.user_places (
  id         uuid primary key default public.uuid_v7(),
  name       text not null check (length(btrim(name)) between 2 and 60),
  area       text not null default '' check (length(area) <= 60),
  lat        double precision not null check (lat between 6 and 38),
  lng        double precision not null check (lng between 68 and 98),
  created_by uuid references public.profiles on delete set null,
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists user_places_name_trgm on public.user_places using gin (lower(name) gin_trgm_ops);
create index if not exists user_places_by on public.user_places (created_by, created_at desc);
alter table public.user_places enable row level security;  -- added through add_place, read through search_places
revoke all on public.user_places from public, anon, authenticated;

-- Save a place the maps don't know ("Sai Baba Temple, Ward 12", "Gupta Kirana gali"). The same name within 150 m is the same
-- place: its id comes back instead of a copy. Up to 20 a day per person.
create or replace function public.add_place(p_name text, p_lat double precision, p_lng double precision, p_area text default '') returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare n text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'); a text := left(btrim(coalesce(p_area, '')), 60); found_id uuid;
begin
  if me() is null then raise exception 'sign in first'; end if;
  if length(n) < 2 or length(n) > 60 then raise exception 'give the place a name (2 to 60 letters)'; end if;
  if p_lat is null or p_lng is null or p_lat not between 6 and 38 or p_lng not between 68 and 98 then raise exception 'put the pin on a place in India'; end if;
  select id into found_id from user_places
   where not hidden and lower(name) = lower(n) and st_dwithin(geo(lat, lng), geo(p_lat, p_lng), 150) limit 1;
  if found_id is not null then return found_id; end if;
  if (select count(*) from user_places where created_by = me() and created_at > now() - interval '1 day') >= 20 then
    raise exception 'you have added 20 places today; try again tomorrow'; end if;
  insert into user_places (name, area, lat, lng, created_by) values (n, a, p_lat, p_lng, me()) returning id into found_id;
  return found_id;
end $$;

-- Bucks staff take down a wrong or abusive place.
create or replace function public.hide_place(p_place uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  update user_places set hidden = true where id = p_place;
  if not found then raise exception 'place not found'; end if;
end $$;

-- ---------- search ----------
-- [source]: BUCKS (a live page), AREA (an area pages are listed in), PEOPLE (a dropped pin), POST (India Post locality).
-- A 6-digit query is a pincode: its localities, nearest first. Otherwise names that start with the query come first, then close
-- spellings; within each, nearest to (lat, lng). At most [lim] (up to 20) rows.
create or replace function public.search_places(q text, lat double precision, lng double precision, lim int default 10)
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
      and (lower(l.title) like '%' || p.t || '%' or lower(l.title) % p.t)
      and st_dwithin(l.location, p.here, 100000)
    order by prefix desc, d limit 4),
  areas as (
    select 'AREA'::text source, null::text id, min(l.area) name, 'Area on Bucks · ' || count(*) || ' listed' detail,
           avg(st_y(l.location::geometry)) lat, avg(st_x(l.location::geometry)) lng, min(st_distance(l.location, p.here)) d,
           bool_or(lower(l.area) like p.t || '%') prefix
    from listings l, p
    where length(p.t) >= 3 and l.status = 'LIVE' and l.location is not null and l.area <> ''
      and (lower(l.area) like p.t || '%' or lower(l.area) % p.t) and st_dwithin(l.location, p.here, 100000)
    group by lower(l.area) order by prefix desc, d limit 3),
  people as (
    select 'PEOPLE'::text source, u.id::text id, u.name, coalesce(nullif(u.area, ''), 'Added by people on Bucks') detail, u.lat, u.lng,
           st_distance(geo(u.lat, u.lng), p.here) d, (lower(u.name) like p.t || '%') prefix
    from user_places u, p
    where length(p.t) >= 2 and not u.hidden and (u.created_by is null or not blocked_between(me(), u.created_by))
      and (lower(u.name) like '%' || p.t || '%' or lower(u.name) % p.t) and st_dwithin(geo(u.lat, u.lng), p.here, 100000)
    order by prefix desc, d limit 4),
  post_hits as (
    select x.*, (lower(x.name) like p.t || '%') prefix from localities x, p where p.t ~ '^[1-9][0-9]{5}$' and x.pincode = p.t
    union all
    select x.*, (lower(x.name) like p.t || '%') from localities x, p
    -- Names that start with the query: anywhere. Close spellings (typos): only within 100 km, so "hindupr" doesn't bring far-off look-alikes.
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

-- ---------- grants ----------
revoke all on function public.add_place(text, double precision, double precision, text), public.hide_place(uuid),
              public.search_places(text, double precision, double precision, int) from public, anon;
grant execute on function public.add_place(text, double precision, double precision, text), public.hide_place(uuid),
              public.search_places(text, double precision, double precision, int) to authenticated;
