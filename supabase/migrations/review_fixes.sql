-- Fixes from the pilot code review (build 81). Safe to run more than once. Apply after showcase_docs.sql, cancellation.sql and dispatch.sql.

-- ---------- 1. Names that could pass for a Bucks check ----------
-- Folds case, look-alike digits and every non-letter away, so "V3rified", "B u c k s" and "verified-by-bucks" all match.
create or replace function public.showcase_name_ok(p text) returns boolean language sql immutable set search_path = public, extensions as $$
  select regexp_replace(translate(lower(coalesce(p, '')), '013457@$', 'oleastas'), '[^a-z]', '', 'g') !~ '(verified|bucks)'
$$;

-- ---------- 2. add / update: issuer is screened too, the file must be a real showcase upload, edits drop the Bucks check ----------
create or replace function public.add_showcase_doc(p_listing uuid, p_kind text, p_title text, p_issuer text, p_number text, p_registry text, p_path text, p_mime text, p_size int, p_visibility text, p_expires date)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare new_id uuid; n int;
begin
  if not can_manage_listing(p_listing) then raise exception 'only the owner or an admin can add documents'; end if;
  select count(*) into n from listing_showcase_docs where listing_id = p_listing;
  if n >= 20 then raise exception 'up to 20 documents per profile; remove one first'; end if;
  -- Only files uploaded by the showcase screen (showcase-*) count; a compliance file in the same folder can't be published by naming its path.
  if p_path is null or p_path not like me()::text || '/showcase-%' then raise exception 'upload the file first'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'docs' and o.name = p_path) then raise exception 'upload the file first'; end if;
  if not showcase_name_ok(p_issuer) then raise exception 'that issuer could be mistaken for a Bucks check; use the real issuer'; end if;
  perform showcase_check_fields(p_title, p_number, nullif(p_registry, ''));
  insert into listing_showcase_docs (listing_id, kind, title, issuer, number, registry, path, mime, size_bytes, visibility, expires_on, sort)
  values (p_listing, p_kind, trim(p_title), left(trim(coalesce(p_issuer, '')), 80), upper(trim(coalesce(p_number, ''))), nullif(p_registry, ''), p_path, p_mime, p_size, coalesce(p_visibility, 'ON_REQUEST'), p_expires, n)
  returning listing_showcase_docs.id into new_id;
  return new_id;
end $$;

create or replace function public.update_showcase_doc(p_doc uuid, p_title text, p_issuer text, p_number text, p_registry text, p_visibility text, p_expires date) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs; changed boolean;
begin
  select * into d from listing_showcase_docs where id = p_doc for update;
  if not found or not can_manage_listing(d.listing_id) then raise exception 'document not found'; end if;
  if not showcase_name_ok(p_issuer) then raise exception 'that issuer could be mistaken for a Bucks check; use the real issuer'; end if;
  perform showcase_check_fields(p_title, p_number, nullif(p_registry, ''));
  -- A Bucks check covers what staff saw; change any of it and the badge goes until staff look again.
  changed := trim(p_title) is distinct from d.title or upper(trim(coalesce(p_number, ''))) is distinct from d.number
          or nullif(p_registry, '') is distinct from d.registry or p_expires is distinct from d.expires_on;
  update listing_showcase_docs set title = trim(p_title), issuer = left(trim(coalesce(p_issuer, '')), 80), number = upper(trim(coalesce(p_number, ''))), registry = nullif(p_registry, ''),
         visibility = coalesce(p_visibility, visibility), expires_on = p_expires, bucks_checked = case when changed then false else bucks_checked end, updated_at = now() where id = p_doc;
  if p_visibility = 'PRIVATE' then
    update doc_access_requests set status = 'REVOKED', decided_by = me(), decided_at = now() where doc_id = p_doc and status in ('PENDING', 'APPROVED');
  end if;
end $$;

-- ---------- 3. Storage read policy: signed-in users only, and re-runnable ----------
do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "docs showcase read" on storage.objects;
    create policy "docs showcase read" on storage.objects for select to authenticated using (bucket_id = 'docs' and public.showcase_path_open(name));
  end if;
end $$;

-- ---------- 4. clear_showcase_check: must be signed in and the document must exist; recount under the row lock ----------
create or replace function public.clear_showcase_check(p_doc uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if me() is null then raise exception 'sign in first'; end if;
  perform 1 from listing_showcase_docs where id = p_doc for update;
  if not found then return; end if;
  delete from doc_checks where doc_id = p_doc and profile_id = me();
  update listing_showcase_docs set checks_up = (select count(*) from doc_checks where doc_id = p_doc and vote = 1), checks_down = (select count(*) from doc_checks where doc_id = p_doc and vote = -1) where id = p_doc;
end $$;

-- ---------- 5. Categories other owners added (the app's "Added by others" group) ----------
create or replace function public.category_suggestions(p_kind text, p_q text default '') returns table (category text, uses int)
language sql stable security definer set search_path = public, extensions as $$
  select min(l.category) as category, count(*)::int as uses
  from listings l
  where l.kind = p_kind and l.status in ('LIVE', 'PENDING') and me() is not null
    and l.category is not null and char_length(trim(l.category)) between 2 and 40
    and l.category !~* '(verified|bucks)'
    and (coalesce(p_q, '') = '' or l.category ilike '%' || p_q || '%')
  group by lower(trim(l.category))
  order by count(*) desc, min(l.category)
  limit 40
$$;

-- ---------- 6. advance_task no longer cancels or hands back without a reason ----------
-- The app uses cancel_task / release_task for those; the old route skipped the reason, the stats and the order-delivery rule.
create or replace function public.advance_task(p_task uuid, p_status text, p_pin text default null, p_paid_with text default null) returns public.tasks
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  select * into t from tasks where id = p_task for update;
  if not found then raise exception 'task not found'; end if;
  if p_status = 'CANCELLED' then raise exception 'cancel it from the ride or order screen so a reason is recorded'; end if;
  if t.driver_id = me() then
    if p_status = 'ARRIVED' and t.status = 'MATCHED' then null;
    elsif p_status = 'IN_PROGRESS' and t.status = 'ARRIVED' then if p_pin is distinct from t.pin then raise exception 'that PIN does not match'; end if;
    elsif p_status = 'COMPLETED' and t.status = 'IN_PROGRESS' then
      insert into task_events (task_id, driver_id, vehicle_id, event, km, fare) values (t.id, me(), t.vehicle_id, 'COMPLETED', t.km, t.fare);
      if t.order_id is not null then update orders set status = 'DELIVERED' where id = t.order_id; end if;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
    if p_status = 'IN_PROGRESS' and t.order_id is not null then update orders set status = 'PICKED_UP' where id = t.order_id; end if;
  elsif t.requester_id = me() then
    if p_status = 'NO_DRIVER' and t.status = 'SEARCHING' then null;
    elsif p_status = 'PAID' and t.status = 'COMPLETED' then null;
    else raise exception 'cannot go from % to %', t.status, p_status; end if;
  else raise exception 'not your task'; end if;
  update tasks set status = p_status, paid_with = coalesce(p_paid_with, paid_with) where id = p_task returning * into t;
  if t.requester_id is distinct from me() then t.pin := ''; end if;
  return t;
end $$;

revoke execute on function public.showcase_name_ok(text), public.category_suggestions(text, text) from anon, public;
grant execute on function public.category_suggestions(text, text) to authenticated;

-- ---------- 7. Opinions: one at a time per document, and only while I can still open it ----------
create or replace function public.check_showcase_doc(p_doc uuid, p_vote int, p_comment text default '') returns void language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs; me_p profiles;
begin
  if p_vote not in (1, -1) then raise exception 'vote must be looks genuine or does not look right'; end if;
  select * into d from listing_showcase_docs where id = p_doc for update;
  if not found or d.visibility = 'PRIVATE' then raise exception 'document not found'; end if;
  if can_manage_listing(d.listing_id) then raise exception 'you cannot check your own document'; end if;
  if not showcase_can_open(p_doc) then raise exception 'you no longer have access to this document'; end if;
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

-- ---------- 8. Requests: private documents are not confirmed to exist, a decline cools off for a day, revoking tells the person ----------
create or replace function public.request_doc_access(p_doc uuid, p_message text default '') returns text language plpgsql security definer set search_path = public, extensions as $$
declare d listing_showcase_docs; l listings; n int;
begin
  if me() is null then raise exception 'sign in to ask'; end if;
  select * into d from listing_showcase_docs where id = p_doc;
  if not found then raise exception 'document not found'; end if;
  select * into l from listings where id = d.listing_id;
  if l.status <> 'LIVE' or blocked_between(me(), l.owner_id) then raise exception 'document not found'; end if;
  if listing_role(l.id) is not null then raise exception 'this is your own document'; end if;
  if d.visibility = 'PRIVATE' then raise exception 'document not found'; end if;
  if d.visibility = 'PUBLIC' then raise exception 'this document is already open to everyone'; end if;
  update doc_access_requests set status = 'EXPIRED' where doc_id = p_doc and requester_id = me() and status in ('PENDING', 'APPROVED') and expires_at < now();
  if exists (select 1 from doc_access_requests where doc_id = p_doc and requester_id = me() and status = 'APPROVED') then return 'APPROVED'; end if;
  if exists (select 1 from doc_access_requests where doc_id = p_doc and requester_id = me() and status = 'PENDING') then return 'PENDING'; end if;
  if exists (select 1 from doc_access_requests where doc_id = p_doc and requester_id = me() and status = 'DECLINED' and decided_at > now() - interval '1 day') then
    raise exception 'the owner declined this request; you can ask again tomorrow'; end if;
  select count(*) into n from doc_access_requests where requester_id = me() and created_at > now() - interval '1 day';
  if n >= 5 then raise exception 'you have asked for 5 documents today; try again tomorrow'; end if;
  select count(*) into n from doc_access_requests r join listing_showcase_docs x on x.id = r.doc_id where x.listing_id = l.id and r.status = 'PENDING' and r.expires_at > now();
  if n >= 20 then raise exception 'this page has many requests waiting; try again in a few days'; end if;
  if char_length(coalesce(p_message, '')) > 200 then raise exception 'keep the message under 200 characters'; end if;
  insert into doc_access_requests (doc_id, requester_id, message) values (p_doc, me(), trim(coalesce(p_message, '')));
  perform push_note_team(l.id, 'DOC_REQUEST', pname(me()) || ' asked to see ' || d.title, coalesce(nullif(trim(p_message), ''), 'Open Document requests to approve or decline.'), 'doc-requests/' || l.id);
  return 'PENDING';
end $$;

create or replace function public.revoke_doc_access(p_req uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
declare r doc_access_requests; d listing_showcase_docs;
begin
  select * into r from doc_access_requests where id = p_req for update;
  if not found then raise exception 'request not found'; end if;
  select * into d from listing_showcase_docs where id = r.doc_id;
  if not can_manage_listing(d.listing_id) then raise exception 'request not found'; end if;
  if r.status = 'APPROVED' then
    update doc_access_requests set status = 'REVOKED', decided_by = me(), decided_at = now() where id = p_req;
    perform push_note(r.requester_id, 'DOC_REQUEST_RESULT', 'Access to ' || d.title || ' ended', 'The owner has taken it back.', 'l/' || d.listing_id);
  elsif r.status = 'PENDING' then
    update doc_access_requests set status = 'REVOKED', decided_by = me(), decided_at = now() where id = p_req;
  end if;
end $$;

-- decide_doc_request: a missing answer is an error, not a decline
create or replace function public.decide_doc_request(p_req uuid, p_approve boolean, p_days int default 30) returns text language plpgsql security definer set search_path = public, extensions as $$
declare r doc_access_requests; d listing_showcase_docs;
begin
  if p_approve is null then raise exception 'approve or decline'; end if;
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
