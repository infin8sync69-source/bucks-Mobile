-- Showcase documents (bucks_31): what a business, NGO or institution shows on its profile to earn trust.
--
-- Not the same as listing_documents. Those are compliance documents (owner ID, GST, RC...) that only Bucks staff open, and a nightly job
-- suspends a listing when one is missing. Showcase documents never affect go-live and are never "Verified by Bucks" unless staff say so.
--
-- Visibility per document:
--   PUBLIC      anyone signed in can open it
--   ON_REQUEST  the profile shows a locked card; a viewer asks, the owner or an admin approves for N days (default 30), revocable
--   PRIVATE     only the owner, admins and Bucks staff
-- Viewers who opened a document can say "looks genuine" / "doesn't look right". That is a viewer signal, not verification, and it
-- never feeds the trust counters. Everything goes through the functions below; the tables have no direct access.

create table if not exists public.listing_showcase_docs (
  id uuid primary key default uuid_v7(),
  listing_id uuid not null references public.listings on delete cascade,
  kind text not null check (kind in ('REGISTRATION', 'LICENCE', 'TAX', 'CERTIFICATE', 'AFFILIATION', 'AWARD', 'REPORT', 'BROCHURE', 'OTHER')),
  title text not null check (char_length(title) between 2 and 60),
  issuer text not null default '' check (char_length(issuer) <= 80),
  number text not null default '' check (char_length(number) <= 40),
  registry text check (registry in ('GST', 'FSSAI', 'MCA')),
  path text not null unique check (char_length(path) between 10 and 300),
  mime text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  size_bytes int not null check (size_bytes between 1 and 10485760),
  visibility text not null default 'ON_REQUEST' check (visibility in ('PUBLIC', 'ON_REQUEST', 'PRIVATE')),
  expires_on date,
  bucks_checked boolean not null default false,
  checks_up int not null default 0,
  checks_down int not null default 0,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists showcase_docs_listing on public.listing_showcase_docs (listing_id, sort, created_at);

create table if not exists public.doc_access_requests (
  id uuid primary key default uuid_v7(),
  doc_id uuid not null references public.listing_showcase_docs on delete cascade,
  requester_id uuid not null references public.profiles on delete cascade,
  message text not null default '' check (char_length(message) <= 200),
  status text not null default 'PENDING' check (status in ('PENDING', 'APPROVED', 'DECLINED', 'REVOKED', 'EXPIRED')),
  decided_by uuid references public.profiles on delete set null,
  decided_at timestamptz,
  expires_at timestamptz not null default now() + interval '7 days',   -- PENDING: the request lapses; APPROVED: the access ends
  created_at timestamptz not null default now()
);
create unique index if not exists doc_request_open on public.doc_access_requests (doc_id, requester_id) where status in ('PENDING', 'APPROVED');
create index if not exists doc_request_by_doc on public.doc_access_requests (doc_id, status);

create table if not exists public.doc_views (
  doc_id uuid not null references public.listing_showcase_docs on delete cascade,
  viewer_id uuid not null references public.profiles on delete cascade,
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  n int not null default 1,
  primary key (doc_id, viewer_id)
);

create table if not exists public.doc_checks (
  doc_id uuid not null references public.listing_showcase_docs on delete cascade,
  profile_id uuid not null references public.profiles on delete cascade,
  vote smallint not null check (vote in (1, -1)),
  comment text not null default '' check (char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (doc_id, profile_id)
);

alter table public.listing_showcase_docs enable row level security;
alter table public.doc_access_requests enable row level security;
alter table public.doc_views enable row level security;
alter table public.doc_checks enable row level security;
revoke all on public.listing_showcase_docs, public.doc_access_requests, public.doc_views, public.doc_checks from anon, authenticated, public;

-- ---------- who may open a document ----------
create or replace function public.showcase_can_open(p_doc uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from listing_showcase_docs d join listings l on l.id = d.listing_id
    where d.id = p_doc and (
      can_manage_listing(d.listing_id) or is_staff()
      or (l.status = 'LIVE' and me() is not null and not blocked_between(me(), l.owner_id) and (
            d.visibility = 'PUBLIC'
            or (d.visibility = 'ON_REQUEST' and exists (select 1 from doc_access_requests r where r.doc_id = d.id and r.requester_id = me() and r.status = 'APPROVED' and r.expires_at > now())))))
  )
$$;

-- Storage policies run as the reader, who cannot read the table; so the check goes through a definer function.
create or replace function public.showcase_path_open(p_path text) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from listing_showcase_docs d where d.path = p_path and showcase_can_open(d.id))
$$;
create policy "docs showcase read" on storage.objects for select using (bucket_id = 'docs' and public.showcase_path_open(name));

-- ---------- shared checks ----------
create or replace function public.showcase_check_fields(p_title text, p_number text, p_registry text) returns void language plpgsql immutable as $$
begin
  if char_length(trim(coalesce(p_title, ''))) < 2 or char_length(trim(p_title)) > 60 then raise exception 'give it a name of 2 to 60 characters'; end if;
  if p_title ~* '(verified|bucks)' then raise exception 'that name could be mistaken for a Bucks check; pick another'; end if;
  if p_registry = 'GST' and upper(trim(coalesce(p_number, ''))) !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then raise exception 'that is not a valid 15-character GSTIN'; end if;
  if p_registry = 'FSSAI' and trim(coalesce(p_number, '')) !~ '^[0-9]{14}$' then raise exception 'an FSSAI number has 14 digits'; end if;
  if p_registry is not null and p_registry <> '' and trim(coalesce(p_number, '')) = '' then raise exception 'enter the registration number to link the official check'; end if;
end $$;

-- ---------- owner: add / edit / delete ----------
create or replace function public.add_showcase_doc(p_listing uuid, p_kind text, p_title text, p_issuer text, p_number text, p_registry text, p_path text, p_mime text, p_size int, p_visibility text, p_expires date)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare new_id uuid; n int;
begin
  if not can_manage_listing(p_listing) then raise exception 'only the owner or an admin can add documents'; end if;
  select count(*) into n from listing_showcase_docs where listing_id = p_listing;
  if n >= 20 then raise exception 'up to 20 documents per profile; remove one first'; end if;
  if p_path is null or p_path not like me()::text || '/%' then raise exception 'upload the file first'; end if;
  perform showcase_check_fields(p_title, p_number, nullif(p_registry, ''));
  insert into listing_showcase_docs (listing_id, kind, title, issuer, number, registry, path, mime, size_bytes, visibility, expires_on, sort)
  values (p_listing, p_kind, trim(p_title), left(trim(coalesce(p_issuer, '')), 80), upper(trim(coalesce(p_number, ''))), nullif(p_registry, ''), p_path, p_mime, p_size, coalesce(p_visibility, 'ON_REQUEST'), p_expires, n)
  returning listing_showcase_docs.id into new_id;
  return new_id;
end $$;

create or replace function public.update_showcase_doc(p_doc uuid, p_title text, p_issuer text, p_number text, p_registry text, p_visibility text, p_expires date) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs;
begin
  select * into d from listing_showcase_docs where id = p_doc for update;
  if not found or not can_manage_listing(d.listing_id) then raise exception 'document not found'; end if;
  perform showcase_check_fields(p_title, p_number, nullif(p_registry, ''));
  update listing_showcase_docs set title = trim(p_title), issuer = left(trim(coalesce(p_issuer, '')), 80), number = upper(trim(coalesce(p_number, ''))), registry = nullif(p_registry, ''),
         visibility = coalesce(p_visibility, visibility), expires_on = p_expires, updated_at = now() where id = p_doc;
  -- Going private ends every open grant: nobody keeps access to a document the owner has taken back.
  if p_visibility = 'PRIVATE' then
    update doc_access_requests set status = 'REVOKED', decided_by = me(), decided_at = now() where doc_id = p_doc and status in ('PENDING', 'APPROVED');
  end if;
end $$;

-- Returns the storage path so the app can remove the file after the row is gone.
create or replace function public.delete_showcase_doc(p_doc uuid) returns text language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs;
begin
  select * into d from listing_showcase_docs where id = p_doc for update;
  if not found or not can_manage_listing(d.listing_id) then raise exception 'document not found'; end if;
  delete from listing_showcase_docs where id = p_doc;
  return d.path;
end $$;

-- ---------- the profile's Documents section ----------
create or replace function public.showcase_docs(p_listing uuid)
returns table (id uuid, listing_id uuid, kind text, title text, issuer text, number text, registry text, mime text, size_bytes int, visibility text, expires_on date,
               bucks_checked boolean, checks_up int, checks_down int, sort int, created_at timestamptz, can_open boolean, my_request text, my_check smallint, pending_requests int)
language plpgsql stable security definer set search_path = public, extensions as $$
declare mgr boolean := can_manage_listing(p_listing); st text; own uuid;
begin
  select l.status, l.owner_id into st, own from listings l where l.id = p_listing;
  if st is null then return; end if;
  if not mgr and (st <> 'LIVE' or me() is null or blocked_between(me(), own)) then return; end if;
  return query
  select d.id, d.listing_id, d.kind, d.title, d.issuer,
         case when mgr or d.visibility = 'PUBLIC' or showcase_can_open(d.id) then d.number else '' end,
         d.registry, d.mime, d.size_bytes, d.visibility, d.expires_on, d.bucks_checked, d.checks_up, d.checks_down, d.sort, d.created_at,
         showcase_can_open(d.id),
         (select r.status from doc_access_requests r where r.doc_id = d.id and r.requester_id = me() and r.status in ('PENDING', 'APPROVED', 'DECLINED') and (r.status = 'DECLINED' or r.expires_at > now()) order by r.created_at desc limit 1),
         (select c.vote from doc_checks c where c.doc_id = d.id and c.profile_id = me()),
         case when mgr then (select count(*)::int from doc_access_requests r where r.doc_id = d.id and r.status = 'PENDING' and r.expires_at > now()) else 0 end
  from listing_showcase_docs d
  where d.listing_id = p_listing and (mgr or d.visibility in ('PUBLIC', 'ON_REQUEST'))
  order by d.sort, d.created_at;
end $$;

-- ---------- viewer: ask, open, say whether it looks genuine ----------
create or replace function public.request_doc_access(p_doc uuid, p_message text default '') returns text language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs; l listings; n int;
begin
  if me() is null then raise exception 'sign in to ask'; end if;
  select * into d from listing_showcase_docs where id = p_doc;
  if not found then raise exception 'document not found'; end if;
  select * into l from listings where id = d.listing_id;
  if l.status <> 'LIVE' or blocked_between(me(), l.owner_id) then raise exception 'document not found'; end if;
  if listing_role(l.id) is not null then raise exception 'this is your own document'; end if;
  if d.visibility <> 'ON_REQUEST' then raise exception '%', case when d.visibility = 'PUBLIC' then 'this document is already open to everyone' else 'the owner keeps this document private' end; end if;
  update doc_access_requests set status = 'EXPIRED' where doc_id = p_doc and requester_id = me() and status in ('PENDING', 'APPROVED') and expires_at < now();
  if exists (select 1 from doc_access_requests where doc_id = p_doc and requester_id = me() and status = 'APPROVED') then return 'APPROVED'; end if;
  if exists (select 1 from doc_access_requests where doc_id = p_doc and requester_id = me() and status = 'PENDING') then return 'PENDING'; end if;
  select count(*) into n from doc_access_requests where requester_id = me() and created_at > now() - interval '1 day';
  if n >= 5 then raise exception 'you have asked for 5 documents today; try again tomorrow'; end if;
  select count(*) into n from doc_access_requests r join listing_showcase_docs x on x.id = r.doc_id where x.listing_id = l.id and r.status = 'PENDING' and r.expires_at > now();
  if n >= 20 then raise exception 'this page has many requests waiting; try again in a few days'; end if;
  if char_length(coalesce(p_message, '')) > 200 then raise exception 'keep the message under 200 characters'; end if;
  insert into doc_access_requests (doc_id, requester_id, message) values (p_doc, me(), trim(coalesce(p_message, '')));
  perform push_note_team(l.id, 'DOC_REQUEST', pname(me()) || ' asked to see ' || d.title, coalesce(nullif(trim(p_message), ''), 'Open Document requests to approve or decline.'), 'doc-requests/' || l.id);
  return 'PENDING';
end $$;

create or replace function public.decide_doc_request(p_req uuid, p_approve boolean, p_days int default 30) returns text language plpgsql security definer set search_path = public, extensions as $$
declare r doc_access_requests; d listing_showcase_docs;
begin
  select * into r from doc_access_requests where id = p_req for update;
  if not found then raise exception 'request not found'; end if;
  select * into d from listing_showcase_docs where id = r.doc_id;
  if not can_manage_listing(d.listing_id) then raise exception 'request not found'; end if;
  if r.status <> 'PENDING' or r.expires_at < now() then raise exception 'this request has already been answered or has lapsed'; end if;
  if p_approve then
    update doc_access_requests set status = 'APPROVED', decided_by = me(), decided_at = now(), expires_at = now() + make_interval(days => least(greatest(coalesce(p_days, 30), 1), 90)) where id = p_req;
    perform push_note(r.requester_id, 'DOC_REQUEST_RESULT', 'You can now open ' || d.title, 'Access lasts ' || least(greatest(coalesce(p_days, 30), 1), 90) || ' days.', 'l/' || d.listing_id);
    return 'APPROVED';
  end if;
  update doc_access_requests set status = 'DECLINED', decided_by = me(), decided_at = now() where id = p_req;
  perform push_note(r.requester_id, 'DOC_REQUEST_RESULT', 'Your request for ' || d.title || ' was declined', 'The owner chose not to share it.', 'l/' || d.listing_id);
  return 'DECLINED';
end $$;

create or replace function public.revoke_doc_access(p_req uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
declare r doc_access_requests; d listing_showcase_docs;
begin
  select * into r from doc_access_requests where id = p_req for update;
  if not found then raise exception 'request not found'; end if;
  select * into d from listing_showcase_docs where id = r.doc_id;
  if not can_manage_listing(d.listing_id) then raise exception 'request not found'; end if;
  update doc_access_requests set status = 'REVOKED', decided_by = me(), decided_at = now() where id = p_req and status in ('PENDING', 'APPROVED');
end $$;

-- Requests waiting, and approvals still running, for the owner / admin to act on.
create or replace function public.doc_requests_for(p_listing uuid)
returns table (id uuid, doc_id uuid, doc_title text, requester_id uuid, requester_name text, relation text, message text, status text, created_at timestamptz, expires_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not can_manage_listing(p_listing) then raise exception 'not allowed'; end if;
  return query
  select r.id, r.doc_id, d.title, r.requester_id, pname(r.requester_id),
         case when exists (select 1 from orders o where o.buyer_id = r.requester_id and o.listing_id = p_listing) then 'Has ordered here'
              when exists (select 1 from listing_syncs s where s.profile_id = r.requester_id and s.listing_id = p_listing) then 'Follows this page'
              else 'No past activity here' end,
         r.message, r.status, r.created_at, r.expires_at
  from doc_access_requests r join listing_showcase_docs d on d.id = r.doc_id
  where d.listing_id = p_listing and r.status in ('PENDING', 'APPROVED') and r.expires_at > now()
  order by (r.status = 'PENDING') desc, r.created_at desc limit 100;
end $$;

-- Opening a document: checks access, remembers that I looked (needed before I can give an opinion), returns where the file is.
create or replace function public.open_showcase_doc(p_doc uuid) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs;
begin
  if not showcase_can_open(p_doc) then raise exception 'you do not have access to this document'; end if;
  select * into d from listing_showcase_docs where id = p_doc;
  if not can_manage_listing(d.listing_id) and not is_staff() then
    insert into doc_views (doc_id, viewer_id) values (p_doc, me()) on conflict (doc_id, viewer_id) do update set last_at = now(), n = doc_views.n + 1;
  end if;
  return jsonb_build_object('path', d.path, 'mime', d.mime, 'title', d.title, 'expires_on', d.expires_on);
end $$;

create or replace function public.check_showcase_doc(p_doc uuid, p_vote int, p_comment text default '') returns void language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs; me_p profiles;
begin
  if p_vote not in (1, -1) then raise exception 'vote must be looks genuine or does not look right'; end if;
  select * into d from listing_showcase_docs where id = p_doc;
  if not found or d.visibility = 'PRIVATE' then raise exception 'document not found'; end if;
  if can_manage_listing(d.listing_id) then raise exception 'you cannot check your own document'; end if;
  select * into me_p from profiles where id = me();
  if me_p.id is null then raise exception 'sign in first'; end if;
  if me_p.created_at > now() - make_interval(days => coalesce(setting('recommender_min_account_days'), 0)::int) then raise exception 'your account is too new to give an opinion'; end if;
  if not exists (select 1 from doc_views v where v.doc_id = p_doc and v.viewer_id = me()) then raise exception 'open the document before giving an opinion'; end if;
  if (select count(*) from doc_checks where profile_id = me() and updated_at > now() - interval '1 hour') >= 20 then raise exception 'slow down; try again later'; end if;
  if char_length(coalesce(p_comment, '')) > 300 then raise exception 'keep the comment under 300 characters'; end if;
  insert into doc_checks (doc_id, profile_id, vote, comment) values (p_doc, me(), p_vote, trim(coalesce(p_comment, '')))
  on conflict (doc_id, profile_id) do update set vote = excluded.vote, comment = excluded.comment, updated_at = now();
  update listing_showcase_docs set checks_up = (select count(*) from doc_checks where doc_id = p_doc and vote = 1), checks_down = (select count(*) from doc_checks where doc_id = p_doc and vote = -1) where id = p_doc;
end $$;

create or replace function public.clear_showcase_check(p_doc uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from doc_checks where doc_id = p_doc and profile_id = me();
  update listing_showcase_docs set checks_up = (select count(*) from doc_checks where doc_id = p_doc and vote = 1), checks_down = (select count(*) from doc_checks where doc_id = p_doc and vote = -1) where id = p_doc;
end $$;

-- Who opened what, newest first (owner / admin).
create or replace function public.doc_view_log(p_listing uuid)
returns table (doc_title text, viewer_id uuid, viewer_name text, last_at timestamptz, times int)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not can_manage_listing(p_listing) then raise exception 'not allowed'; end if;
  return query select d.title, v.viewer_id, pname(v.viewer_id), v.last_at, v.n from doc_views v join listing_showcase_docs d on d.id = v.doc_id
    where d.listing_id = p_listing order by v.last_at desc limit 50;
end $$;

-- Bucks staff mark a showcase document as checked. Nobody else can; nothing else sets the flag.
create or replace function public.review_showcase_doc(p_doc uuid, p_checked boolean) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'only Bucks staff can check documents'; end if;
  update listing_showcase_docs set bucks_checked = p_checked, updated_at = now() where id = p_doc;
end $$;

-- ---------- grants ----------
revoke execute on function public.showcase_path_open(text), public.showcase_can_open(uuid), public.showcase_check_fields(text, text, text),
  public.add_showcase_doc(uuid, text, text, text, text, text, text, text, int, text, date), public.update_showcase_doc(uuid, text, text, text, text, text, date),
  public.delete_showcase_doc(uuid), public.showcase_docs(uuid), public.request_doc_access(uuid, text), public.decide_doc_request(uuid, boolean, int),
  public.revoke_doc_access(uuid), public.doc_requests_for(uuid), public.open_showcase_doc(uuid), public.check_showcase_doc(uuid, int, text),
  public.clear_showcase_check(uuid), public.doc_view_log(uuid), public.review_showcase_doc(uuid, boolean) from anon, public;
grant execute on function public.showcase_path_open(text), public.showcase_can_open(uuid),
  public.add_showcase_doc(uuid, text, text, text, text, text, text, text, int, text, date), public.update_showcase_doc(uuid, text, text, text, text, text, date),
  public.delete_showcase_doc(uuid), public.showcase_docs(uuid), public.request_doc_access(uuid, text), public.decide_doc_request(uuid, boolean, int),
  public.revoke_doc_access(uuid), public.doc_requests_for(uuid), public.open_showcase_doc(uuid), public.check_showcase_doc(uuid, int, text),
  public.clear_showcase_check(uuid), public.doc_view_log(uuid), public.review_showcase_doc(uuid, boolean) to authenticated;
