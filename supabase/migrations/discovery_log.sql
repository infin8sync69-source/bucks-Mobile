-- What people search for and what they do next, kept so search can be measured and keep learning (docs/DISCOVERY_ALGORITHMS.md
-- Phase 0.4 and §13, the learning loop). Safe to run more than once. Apply after search_quality2.sql (supabase/apply_all.sh does).
--
-- Who is logged: only adults who have not switched analytics off (Settings › Appearance and data), the same switch and the same rule as
-- the app's analytics. The apps send nothing otherwise, and the server drops anything from a person under 18 or whose age is not known,
-- so children are never logged (DPDP Act s.9(3)). People search keeps no text: the name typed is never stored.
-- What is kept: the query (at most 100 characters; phone numbers and email addresses replaced by #), an area cell of about 2 km (0.02°, the grid
-- suggest_people already uses), never coordinates; then what was shown and opened, and what was done (call, message, directions, cart,
-- order, booking, sync, vote). Owners' and team members' own pages are left out.
-- How long: raw rows 90 days, daily aggregates 13 months (settings). Rows go when the account is deleted, and the person can delete
-- them at any time (discovery_forget_me, which the apps call when analytics is switched off).
-- Who can read it: nobody through the API. Staff read the weekly report (discovery_report), which shows counts and normalised query
-- words, never who searched.
--
-- The learning loop on top: every night discovery_daily() rolls up yesterday, mines candidates for the lexicon (a query that found
-- nothing or nothing worth opening, then rephrased within a minute into one that was opened; queries that keep finding nothing;
-- "Not what I wanted" feedback) and purges old rows. A person reviews the candidates every week (lexicon_accept, lexicon_reject); an
-- accepted word is live at once and is copied into git with a golden-set case (lexicon_export).
set search_path = public, extensions;

insert into public.settings (key, value) values
  ('discovery_logging_on', 1),        -- master switch for log_discovery
  ('rate_discovery_per_hour', 240),   -- log_discovery calls per person per hour; each call carries at most 200 events
  ('discovery_raw_days', 90),         -- raw query and event rows are kept this long
  ('discovery_stats_months', 13),     -- daily aggregates are kept this long
  ('lexicon_min_searchers', 2)        -- a mined candidate needs this many different people (one person cannot plant a word)
on conflict (key) do nothing;

-- ---------- 1. tables (no policies, no grants: written by log_discovery, read by staff functions) ----------
create table if not exists public.discovery_queries (
  id          uuid primary key,                      -- made by the app, so the events that follow can point at it without a round trip
  at          timestamptz not null default now(),
  viewer      uuid not null references public.profiles on delete cascade,
  surface     text not null check (surface in ('SEARCH', 'HOME', 'SERVICES', 'EXPLORE', 'PEOPLE', 'PLACES', 'SIMILAR', 'FOR_YOU', 'JOBS')),
  q           text check (length(q) <= 100),         -- null for people search
  q_norm      text check (length(q_norm) <= 200),    -- search_norm(q): what the aggregates and the mining group by
  cell        text check (length(cell) <= 24),       -- '12.18,75.92'
  radius_m    int,
  filters     jsonb not null default '{}',
  n_results   int,
  latency_ms  int,
  app         text check (length(app) <= 40),        -- 'android 1.0.10 (13)'
  ranker      text not null default 'v1' check (length(ranker) <= 20)   -- which ranking made the list (search_quality2 is v1)
);
create index if not exists discovery_queries_at on public.discovery_queries (at);
create index if not exists discovery_queries_viewer on public.discovery_queries (viewer, at);

create table if not exists public.discovery_events (
  id           bigint generated always as identity primary key,
  query_id     uuid,                                 -- the search it came from; no foreign key, its batch may arrive later
  at           timestamptz not null default now(),
  viewer       uuid not null references public.profiles on delete cascade,
  kind         text not null check (kind in ('IMPRESSION', 'OPEN', 'CALL', 'MESSAGE', 'DIRECTIONS', 'ADD_TO_CART', 'ORDER', 'BOOK', 'SYNC',
                                             'VOTE', 'SHARE', 'SUGGESTION_TAP', 'FEEDBACK')),
  subject_type text check (subject_type in ('LISTING', 'ITEM', 'PROFILE', 'POST', 'JOB', 'PLACE')),
  subject_id   uuid,
  position     int check (position between 0 and 500),
  detail       text check (detail in ('WRONG_RESULTS', 'MISSING', 'OTHER', 'UP', 'DOWN'))   -- FEEDBACK: what was wrong; VOTE: ↑ or ↓. Never free text
);
create index if not exists discovery_events_query on public.discovery_events (query_id);
create index if not exists discovery_events_at on public.discovery_events (at);
create index if not exists discovery_events_viewer on public.discovery_events (viewer);

create table if not exists public.query_stats_daily (
  day          date not null,
  cell         text not null default '',
  q_norm       text not null,
  surface      text not null default 'SEARCH',
  searches     int not null default 0,
  searchers    int not null default 0,
  zero_results int not null default 0,
  opens        int not null default 0,
  actions      int not null default 0,
  primary key (day, cell, q_norm, surface)
);

-- The review queue of the learning loop. means '' is a query that keeps finding nothing and waits for a person to say what it means.
create table if not exists public.lexicon_candidates (
  term        text not null check (length(term) between 1 and 60),
  means       text not null default '' check (length(means) <= 60),
  source      text not null check (source in ('REFORMULATION', 'ZERO_RESULTS', 'FEEDBACK')),
  evidence    int not null default 0,                -- how many times it happened in the window
  searchers   int not null default 0,                -- how many different people
  first_seen  date not null default current_date,
  last_seen   date not null default current_date,
  status      text not null default 'new' check (status in ('new', 'accepted', 'rejected')),
  decided_by  text,
  decided_at  timestamptz,
  note        text,
  primary key (term, means)
);

do $$
declare t text;
begin
  foreach t in array array['discovery_queries', 'discovery_events', 'query_stats_daily', 'lexicon_candidates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------- 2. small helpers ----------
create or replace function public.discovery_cell(lat double precision, lng double precision) returns text
language sql immutable parallel safe set search_path = public, extensions as $$
  select case when lat between -90 and 90 and lng between -180 and 180
              then to_char(round((lat / 0.02)::numeric) * 0.02, 'FM990.00') || ',' || to_char(round((lng / 0.02)::numeric) * 0.02, 'FM9990.00') end
$$;
create or replace function public.discovery_uuid(s text) returns uuid language sql immutable parallel safe set search_path = public, extensions as $$
  select case when s ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then s::uuid end
$$;
create or replace function public.discovery_int(s text, lo int, hi int) returns int language sql immutable parallel safe set search_path = public, extensions as $$
  select case when s ~ '^-?\d{1,9}$' then case when s::bigint between lo and hi then s::int end end   -- the format first, then the cast
$$;
create or replace function public.discovery_num(s text) returns double precision language sql immutable parallel safe set search_path = public, extensions as $$
  select case when s ~ '^-?\d{1,3}(\.\d{1,12})?$' then s::double precision end
$$;
-- What a person typed, with anything that looks like a phone number (6 or more digits, spaces and dashes allowed) or an email address
-- replaced by #, before it is stored.
create or replace function public.discovery_mask(t text) returns text language sql immutable parallel safe set search_path = public, extensions as $$
  select regexp_replace(regexp_replace(coalesce(t, ''), '\S+@\S+', '#', 'g'), '\d[\d\s().+-]{4,}\d', '#', 'g')
$$;
-- The time an event happened, as the app saw it, kept within the last day and never in the future.
create or replace function public.discovery_ts(s text) returns timestamptz language plpgsql stable set search_path = public, extensions as $$
begin
  if s is null or s !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' then return now(); end if;
  return least(now(), greatest(now() - interval '1 day', s::timestamptz));
exception when others then
  return now();
end $$;
-- Words that may be shown to a person reviewing the queue: no phone-like numbers, not too long, not someone's name.
create or replace function public.discovery_safe_text(t text) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select t is not null and length(t) between 2 and 40 and t !~ '#' and t !~ '\d{6,}'
     and not exists (select 1 from profiles p where p.status = 'ACTIVE' and length(p.name) >= 3 and lower(p.name) = lower(t))
$$;

-- ---------- 3. writing: log_discovery ----------
-- p_events: a JSON array of at most 200 objects.
--   {"t": "QUERY", "id": uuid, "surface": "SEARCH", "q": "...", "lat": 12.18, "lng": 75.91, "radius_m": 10000, "filters": {...},
--    "n": 12, "ms": 140, "app": "android 1.0.10 (13)", "ranker": "v1", "at": "2026-11-18T10:15:00Z"}
--   {"t": "IMPRESSION", "query_id": uuid, "subject_type": "LISTING", "ids": [uuid, ...]}         one row per id, its index the position
--   {"t": "OPEN" | "CALL" | ..., "query_id": uuid, "subject_type": "LISTING", "subject_id": uuid, "position": 2}
--   {"t": "FEEDBACK", "query_id": uuid, "detail": "WRONG_RESULTS" | "MISSING" | "OTHER"}
--   {"t": "VOTE", "query_id": uuid or absent, "subject_type": "LISTING", "subject_id": uuid, "detail": "UP" | "DOWN"}   the answer to
--      "Did they help?" or a vote right after opening a result: what the search led to
-- Anything malformed is skipped, never an error, so an app bug can't break search. Returns how many rows were stored.
create or replace function public.log_discovery(p_events jsonb) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  my uuid := me(); e jsonb; t text; n int := 0; qid uuid; sid uuid; st text; surf text; q text; ts timestamptz; i int;
begin
  if my is null or coalesce(setting('discovery_logging_on'), 1) < 1 then return 0; end if;
  if age_band_of(my) <> 'ADULT' then return 0; end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' then return 0; end if;
  if jsonb_array_length(p_events) > 200 then raise exception 'at most 200 events in one call' using errcode = 'P0001'; end if;
  perform rate_hit('discovery');

  for e in select x from jsonb_array_elements(p_events) x where jsonb_typeof(x) = 'object' loop
    t := upper(coalesce(e->>'t', ''));
    ts := discovery_ts(e->>'at');
    if t = 'QUERY' then
      qid := discovery_uuid(e->>'id');
      surf := upper(coalesce(e->>'surface', 'SEARCH'));
      continue when qid is null or surf not in ('SEARCH', 'HOME', 'SERVICES', 'EXPLORE', 'PEOPLE', 'PLACES', 'SIMILAR', 'FOR_YOU', 'JOBS');
      q := case when surf = 'PEOPLE' then null
                else nullif(btrim(left(discovery_mask(e->>'q'), 100)), '') end;
      insert into discovery_queries (id, at, viewer, surface, q, q_norm, cell, radius_m, filters, n_results, latency_ms, app, ranker)
      values (qid, ts, my, surf, q, nullif(btrim(search_norm(q)), ''),
              discovery_cell(discovery_num(e->>'lat'), discovery_num(e->>'lng')),
              discovery_int(e->>'radius_m', 0, 1000000),
              case when jsonb_typeof(e->'filters') = 'object' and octet_length((e->'filters')::text) <= 500 then e->'filters' else '{}' end,
              discovery_int(e->>'n', 0, 100000), discovery_int(e->>'ms', 0, 600000),
              left(e->>'app', 40), coalesce(nullif(left(e->>'ranker', 20), ''), 'v1'))
      on conflict (id) do nothing;
      if found then n := n + 1; end if;
    elsif t in ('IMPRESSION', 'OPEN', 'CALL', 'MESSAGE', 'DIRECTIONS', 'ADD_TO_CART', 'ORDER', 'BOOK', 'SYNC', 'VOTE', 'SHARE', 'SUGGESTION_TAP', 'FEEDBACK') then
      qid := discovery_uuid(e->>'query_id');
      st := upper(e->>'subject_type');
      if st is not null and st not in ('LISTING', 'ITEM', 'PROFILE', 'POST', 'JOB', 'PLACE') then continue; end if;
      if t = 'IMPRESSION' and jsonb_typeof(e->'ids') = 'array' then
        i := 0;
        for sid in select discovery_uuid(v) from jsonb_array_elements_text(e->'ids') v loop
          if sid is not null and i < 50
             and not (coalesce(st, '') = 'LISTING' and exists (select 1 from listing_members m where m.listing_id = sid and m.profile_id = my)) then
            insert into discovery_events (query_id, at, viewer, kind, subject_type, subject_id, position) values (qid, ts, my, t, st, sid, i);
            n := n + 1;
          end if;
          i := i + 1;
        end loop;
      else
        sid := discovery_uuid(e->>'subject_id');
        continue when coalesce(st, '') = 'LISTING' and exists (select 1 from listing_members m where m.listing_id = sid and m.profile_id = my);
        continue when t <> 'FEEDBACK' and qid is null and sid is null;
        insert into discovery_events (query_id, at, viewer, kind, subject_type, subject_id, position, detail)
        values (qid, ts, my, t, st, sid, discovery_int(e->>'position', 0, 500),
                case when t = 'FEEDBACK' and upper(e->>'detail') in ('WRONG_RESULTS', 'MISSING', 'OTHER') then upper(e->>'detail')
                     when t = 'VOTE' and upper(e->>'detail') in ('UP', 'DOWN') then upper(e->>'detail') end);
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end $$;

-- The person's own rows, gone now. The apps call it when analytics is switched off.
create or replace function public.discovery_forget_me() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); a int; b int;
begin
  if my is null then return 0; end if;
  delete from discovery_events where viewer = my; get diagnostics a = row_count;
  delete from discovery_queries where viewer = my; get diagnostics b = row_count;
  return a + b;
end $$;

-- An account that is deleted takes its rows with it (delete_my_account sets status DELETED; the profile row stays).
create or replace function public.discovery_forget() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from discovery_events where viewer = new.id;
  delete from discovery_queries where viewer = new.id;
  return new;
end $$;
drop trigger if exists discovery_forget on public.profiles;
create trigger discovery_forget after update of status on public.profiles
  for each row when (new.status = 'DELETED' and old.status is distinct from 'DELETED') execute function public.discovery_forget();

-- ---------- 4. the nightly jobs ----------
-- The searches of one day (India time) that were not just a step of typing: the same person searched a longer query that starts with
-- this one within 10 seconds.
create or replace function public.discovery_settled(p_from timestamptz, p_to timestamptz)
returns table (id uuid, at timestamptz, viewer uuid, surface text, q text, q_norm text, cell text, n_results int, opened boolean, acted boolean)
language sql stable security definer set search_path = public, extensions as $$
  select d.id, d.at, d.viewer, d.surface, d.q, d.q_norm, coalesce(d.cell, ''), d.n_results,
         exists (select 1 from discovery_events e where e.query_id = d.id and e.kind = 'OPEN'),
         exists (select 1 from discovery_events e where e.query_id = d.id
                  and e.kind in ('CALL', 'MESSAGE', 'DIRECTIONS', 'ADD_TO_CART', 'ORDER', 'BOOK', 'SYNC'))
  from discovery_queries d
  where d.at >= p_from and d.at < p_to and d.q_norm is not null
    and not exists (select 1 from discovery_queries x
                    where x.viewer = d.viewer and x.at > d.at and x.at <= d.at + interval '10 seconds'
                      and x.q_norm <> d.q_norm and left(x.q_norm, length(d.q_norm)) = d.q_norm)
$$;

create or replace function public.discovery_rollup(p_day date default null) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_day, (now() at time zone 'Asia/Kolkata')::date - 1); n int;
begin
  delete from query_stats_daily where day = d;
  insert into query_stats_daily (day, cell, q_norm, surface, searches, searchers, zero_results, opens, actions)
  select d, s.cell, s.q_norm, s.surface, count(*), count(distinct s.viewer), count(*) filter (where s.n_results = 0),
         count(*) filter (where s.opened), count(*) filter (where s.acted)
  from discovery_settled(d::timestamp at time zone 'Asia/Kolkata', (d + 1)::timestamp at time zone 'Asia/Kolkata') s
  group by s.cell, s.q_norm, s.surface;
  get diagnostics n = row_count;
  return n;
end $$;

-- Candidates for the lexicon from the last p_days. Only searches, only text that passes discovery_safe_text, only what at least
-- lexicon_min_searchers different people did (feedback: one is enough), never a word the lexicon already has or a candidate that
-- was decided before.
create or replace function public.discovery_mine(p_days int default 30) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare k int := greatest(1, coalesce(setting('lexicon_min_searchers'), 2)::int); n int;
begin
  with s as (select * from discovery_settled(now() - make_interval(days => p_days), now()) where surface = 'SEARCH'),
  -- a search that found nothing worth opening, then another by the same person within a minute that was opened
  reform as (
    select btrim(search_clean(a.q)) term, btrim(search_clean(b.q)) means, a.viewer
    from s a join s b on b.viewer = a.viewer and b.at > a.at and b.at <= a.at + interval '60 seconds'
    where not a.opened and b.opened and a.q_norm <> b.q_norm and left(b.q_norm, length(a.q_norm)) <> a.q_norm
      and not exists (select 1 from s c where c.viewer = a.viewer and c.at > a.at and c.at < b.at)),
  zero as (select btrim(search_clean(q)) term, ''::text means, viewer from s where n_results = 0),
  fb as (
    select btrim(search_clean(d.q)) term, ''::text means, d.viewer
    from discovery_events e join discovery_queries d on d.id = e.query_id
    where e.kind = 'FEEDBACK' and e.at > now() - make_interval(days => p_days) and d.surface = 'SEARCH' and d.q is not null),
  seen as (
    select term, means, 'REFORMULATION' source, count(*) evidence, count(distinct viewer) searchers from reform group by term, means
    union all select term, means, 'ZERO_RESULTS', count(*), count(distinct viewer) from zero group by term, means
    union all select term, means, 'FEEDBACK', count(*), count(distinct viewer) from fb group by term, means),
  ok as (
    select distinct on (f.term, f.means) f.* from seen f
    where discovery_safe_text(f.term) and (f.means = '' or discovery_safe_text(f.means))
      and (f.searchers >= k or (f.source = 'FEEDBACK' and f.searchers >= 1))
      and not exists (select 1 from search_lexicon x where x.term_key = btrim(search_norm(f.term)))
    order by f.term, f.means, f.searchers desc)
  insert into lexicon_candidates as c (term, means, source, evidence, searchers, first_seen, last_seen)
  select term, means, source, evidence, searchers, current_date, current_date from ok
  on conflict (term, means) do update set evidence = excluded.evidence, searchers = excluded.searchers, last_seen = current_date
    where c.status = 'new';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.discovery_purge() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare raw_days int := coalesce(setting('discovery_raw_days'), 90)::int; keep_months int := coalesce(setting('discovery_stats_months'), 13)::int; a int; b int; c int;
begin
  delete from discovery_events where at < now() - make_interval(days => raw_days); get diagnostics a = row_count;
  delete from discovery_queries where at < now() - make_interval(days => raw_days); get diagnostics b = row_count;
  delete from query_stats_daily where day < current_date - make_interval(months => keep_months); get diagnostics c = row_count;
  return a + b + c;
end $$;

create or replace function public.discovery_daily() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  return jsonb_build_object('rolled_up', discovery_rollup(), 'candidates', discovery_mine(30), 'purged', discovery_purge());
end $$;

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('bucks-discovery-daily', '5 21 * * *', 'select public.discovery_daily()');   -- 02:35 IST
  end if;
end $$;

-- ---------- 5. staff: the weekly review ----------
-- Everything a person needs for the weekly review, as one JSON document: the numbers of the last p_days against the targets of
-- DISCOVERY_ALGORITHMS §9.2, the queries that found nothing, the candidate queue and the state of the lexicon. Counts and normalised
-- words only, never who searched.
create or replace function public.discovery_report(p_days int default 7) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare r jsonb; d int := least(greatest(coalesce(p_days, 7), 1), 90);
begin
  if not is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  with s as (select * from discovery_settled(now() - make_interval(days => d), now()) where surface = 'SEARCH'),
       lat as (select latency_ms from discovery_queries where surface = 'SEARCH' and at > now() - make_interval(days => d) and latency_ms is not null),
       reform as (select count(*) n from s a where not a.opened
                    and exists (select 1 from s b where b.viewer = a.viewer and b.at > a.at and b.at <= a.at + interval '30 seconds'))
  select jsonb_build_object(
    'days', d,
    'searches', (select count(*) from s),
    'searchers', (select count(distinct viewer) from s),
    'zero_result_rate', (select round(avg((n_results = 0)::int)::numeric, 3) from s),
    'open_rate', (select round(avg(opened::int)::numeric, 3) from s),
    'action_rate', (select round(avg(acted::int)::numeric, 3) from s),
    'reformulation_rate', (select round(reform.n::numeric / nullif((select count(*) from s), 0), 3) from reform),
    'p95_latency_ms', (select percentile_disc(0.95) within group (order by latency_ms) from lat),
    -- what searches led to: ↑ and ↓ given to pages after contact ("Did they help?") or right after opening a result
    'outcomes', (select jsonb_build_object('up', count(*) filter (where detail = 'UP'), 'down', count(*) filter (where detail = 'DOWN'),
                                          'from_search', count(*) filter (where query_id is not null))
                 from discovery_events where kind = 'VOTE' and at > now() - make_interval(days => d)),
    'top_queries', (select coalesce(jsonb_agg(x order by x.searches desc), '[]') from (
        select q_norm q, count(*) searches, count(distinct viewer) searchers, count(*) filter (where n_results = 0) zero, count(*) filter (where opened) opens
        from s where discovery_safe_text(q_norm) group by q_norm order by count(*) desc limit 25) x),
    'zero_results', (select coalesce(jsonb_agg(x order by x.searches desc), '[]') from (
        select q_norm q, count(*) searches, count(distinct viewer) searchers, count(distinct cell) cells
        from s where n_results = 0 and discovery_safe_text(q_norm) group by q_norm order by count(*) desc limit 25) x),
    'candidates', (select coalesce(jsonb_agg(to_jsonb(c) - 'decided_by' - 'decided_at' order by c.searchers desc, c.evidence desc), '[]')
                   from (select * from lexicon_candidates where status = 'new' order by searchers desc, evidence desc limit 40) c),
    'lexicon', jsonb_build_object(
        'live', (select count(*) from search_lexicon where status = 'live'),
        'by_kind', (select jsonb_object_agg(kind, n) from (select kind, count(*) n from search_lexicon where status = 'live' group by kind) k),
        'awaiting_native_review', (select count(*) from search_lexicon where status = 'live' and reviewed_at is null and lang !~ '(^en$|-Latn$)'),
        'learned', (select count(*) from search_lexicon where source <> 'seed')),
    'weeks', (select coalesce(jsonb_agg(w order by w.week), '[]') from (
        select date_trunc('week', day)::date week, sum(searches) searches,
               round(sum(zero_results)::numeric / nullif(sum(searches), 0), 3) zero_result_rate,
               round(sum(opens)::numeric / nullif(sum(searches), 0), 3) open_rate
        from query_stats_daily where surface = 'SEARCH' and day > current_date - 56 group by 1) w),
    'targets', jsonb_build_object('zero_result_rate', '< 0.10', 'reformulation_rate', '< 0.25', 'p95_latency_ms', '< 200', 'open_rate', 'rising'))
  into r;
  return r;
end $$;

-- Accept a word: it is live at once (source mined, with who reviewed it), and the candidates for that word leave the queue.
create or replace function public.lexicon_accept(p_term text, p_means text, p_kind text, p_lang text default 'en', p_note text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare who text := (select name from profiles where id = me());
begin
  if not is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  if p_kind not in ('SAME', 'CONCEPT', 'GENERIC', 'FILLER', 'MODIFIER') then raise exception 'kind must be SAME, CONCEPT, GENERIC, FILLER or MODIFIER'; end if;
  insert into search_lexicon (term, means, kind, lang, status, source, note, reviewed_by, reviewed_at)
  values (btrim(lower(p_term)), btrim(lower(coalesce(p_means, ''))), p_kind, coalesce(p_lang, 'en'), 'live', 'mined', p_note, who, now())
  on conflict (term, means) do update set kind = excluded.kind, lang = excluded.lang, status = 'live', source = 'mined',
    note = coalesce(excluded.note, search_lexicon.note), reviewed_by = excluded.reviewed_by, reviewed_at = now();
  update lexicon_candidates set status = 'accepted', decided_by = who, decided_at = now(), note = coalesce(p_note, note)
  where btrim(search_norm(term)) = btrim(search_norm(p_term)) and status = 'new';
end $$;

-- Reject a candidate (means '' rejects every candidate for the word). It is kept, so the loop never proposes it again.
create or replace function public.lexicon_reject(p_term text, p_means text default '', p_note text default null) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare who text := (select name from profiles where id = me()); n int;
begin
  if not is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  update lexicon_candidates set status = 'rejected', decided_by = who, decided_at = now(), note = coalesce(p_note, note)
  where term = btrim(lower(p_term)) and (coalesce(p_means, '') = '' or means = btrim(lower(p_means))) and status <> 'accepted';
  get diagnostics n = row_count;
  return n;
end $$;

-- The words people added or reviewed, as SQL to paste into supabase/migrations/search_lexicon_learned.sql, so git and the golden
-- set stay the record of what search knows.
create or replace function public.lexicon_export() returns text
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  return coalesce((
    select string_agg(format('(%L, %L, %L, %L, %L, %L, %L, %L)', term, means, kind, lang, status, source, reviewed_by, reviewed_at), E',\n  ' order by term, means)
    from search_lexicon where source <> 'seed'), '');
end $$;

-- ---------- grants ----------
revoke all on function public.log_discovery(jsonb), public.discovery_forget_me() from public, anon;
grant execute on function public.log_discovery(jsonb), public.discovery_forget_me() to authenticated;
revoke all on function public.discovery_report(int), public.lexicon_accept(text, text, text, text, text), public.lexicon_reject(text, text, text),
                       public.lexicon_export() from public, anon;
grant execute on function public.discovery_report(int), public.lexicon_accept(text, text, text, text, text), public.lexicon_reject(text, text, text),
                          public.lexicon_export() to authenticated;   -- each checks is_staff()
revoke all on function public.discovery_forget(), public.discovery_settled(timestamptz, timestamptz), public.discovery_rollup(date),
                       public.discovery_mine(int), public.discovery_purge(), public.discovery_daily(), public.discovery_safe_text(text),
                       public.discovery_cell(double precision, double precision), public.discovery_uuid(text), public.discovery_int(text, int, int),
                       public.discovery_num(text), public.discovery_ts(text), public.discovery_mask(text)
  from public, anon, authenticated;
