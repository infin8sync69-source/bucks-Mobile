-- Report business pages, reviews and recommendations, jobs and feedback-board posts (Play UGC policy: every surface where people
-- publish something can be reported). Extends social_safety.sql: the reports.target_kind check, report_content, report_queue and
-- review_report. Product ratings have no row id and stay out (their comments are short and shown only on the product).
--
-- Takedowns: LISTING → status SUSPENDED (the team is notified by note_listing_status); REVIEW → deleted (reviews_recount fixes the
-- trust counts); JOB → closed; FEEDBACK → deleted. BAN also suspends the owner's account, as for the other kinds.

do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid = 'public.reports'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%target_kind%' loop
    execute format('alter table public.reports drop constraint %I', c);
  end loop;
end $$;
alter table public.reports add constraint reports_target_kind_check
  check (target_kind in ('POST', 'COMMENT', 'MOMENT', 'MESSAGE', 'PROFILE', 'LISTING', 'REVIEW', 'JOB', 'FEEDBACK'));

-- File a report. The reporter must be able to see what they report (so nobody reports by guessing ids). Reporting the same thing twice is a
-- no-op. Reports for CHILD_SAFETY or SELF_HARM go to the top of the staff queue (ordering in report_queue).
create or replace function public.report_content(p_kind text, p_target uuid, p_reason text, p_detail text default '') returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := me(); owner uuid; rid uuid; k text := upper(p_kind);
begin
  if my is null then raise exception 'not signed in'; end if;
  owner := case k
    when 'POST'     then (select p.author_id from posts p where p.id = p_target and can_see_post(p))
    when 'COMMENT'  then (select c.author_id from post_comments c join posts p on p.id = c.post_id where c.id = p_target and can_see_post(p))
    when 'MOMENT'   then (select m.author_id from moments m where m.id = p_target)
    when 'MESSAGE'  then (select m.sender_id from messages m where m.id = p_target and is_member(m.conversation_id))
    when 'PROFILE'  then (select p.id from profiles p where p.id = p_target)
    when 'LISTING'  then (select l.owner_id from listings l where l.id = p_target and l.status = 'LIVE')
    when 'REVIEW'   then (select r.author_id from reviews r join listings l on l.id = r.listing_id where r.id = p_target and l.status = 'LIVE')
    when 'JOB'      then (select coalesce(j.created_by, l.owner_id) from jobs j join listings l on l.id = j.listing_id where j.id = p_target and j.open)
    when 'FEEDBACK' then (select f.author_id from feedback_posts f where f.id = p_target)
  end;
  if owner is null then raise exception 'nothing to report: it was removed or you can''t see it'; end if;
  if owner = my then raise exception 'you can''t report yourself'; end if;
  insert into reports (reporter_id, target_kind, target_id, target_owner, reason, detail)
  values (my, k, p_target, owner, upper(p_reason), left(coalesce(btrim(p_detail), ''), 500))
  on conflict (reporter_id, target_kind, target_id) do nothing
  returning id into rid;
  return coalesce(rid, (select id from reports where reporter_id = my and target_kind = k and target_id = p_target));
end $$;

-- Staff: the open queue, most urgent first, with how many people reported the same thing.
create or replace function public.report_queue(lim int default 50)
returns table (id uuid, target_kind text, target_id uuid, target_owner uuid, owner_name text, reason text, detail text, reporters int, created_at timestamptz, preview text)
language sql stable security definer set search_path = public, extensions as $$
  select r.id, r.target_kind, r.target_id, r.target_owner, o.name, r.reason, r.detail,
         (select count(*)::int from reports x where x.target_kind = r.target_kind and x.target_id = r.target_id and x.status = 'OPEN'),
         r.created_at,
         left(case r.target_kind
           when 'POST'     then (select body from posts where id = r.target_id)
           when 'COMMENT'  then (select body from post_comments where id = r.target_id)
           when 'MOMENT'   then (select caption from moments where id = r.target_id)
           when 'MESSAGE'  then (select body from messages where id = r.target_id)
           when 'PROFILE'  then (select name || ' · ' || bio from profiles where id = r.target_id)
           when 'LISTING'  then (select 'Page: ' || title || ' · ' || description from listings where id = r.target_id)
           when 'REVIEW'   then (select 'Review of ' || l.title || ': ' || v.comment from reviews v join listings l on l.id = v.listing_id where v.id = r.target_id)
           when 'JOB'      then (select 'Job: ' || title || ' · ' || description from jobs where id = r.target_id)
           when 'FEEDBACK' then (select 'Feedback: ' || title || ' · ' || body from feedback_posts where id = r.target_id)
         end, 280)
  from reports r left join profiles o on o.id = r.target_owner
  where is_staff() and r.status = 'OPEN'
  order by (r.reason in ('CHILD_SAFETY', 'SELF_HARM')) desc, r.created_at
  limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- Staff decision on a report. REMOVE takes the content down (and closes every open report on it); BAN also suspends the owner;
-- DISMISS closes this report only.
create or replace function public.review_report(p_report uuid, p_action text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare r public.reports; a text := upper(p_action);
begin
  if not is_staff() then raise exception 'staff only'; end if;
  select * into r from reports where id = p_report for update;
  if not found then raise exception 'no such report'; end if;
  if a = 'DISMISS' then
    update reports set status = 'DISMISSED', action = 'NONE', reviewed_by = me(), reviewed_at = now() where id = p_report; return;
  end if;
  if a not in ('REMOVE', 'BAN') then raise exception 'action must be REMOVE, BAN or DISMISS'; end if;
  case r.target_kind
    when 'POST'     then update posts set deleted_at = now() where id = r.target_id and deleted_at is null;
    when 'COMMENT'  then delete from post_comments where id = r.target_id;
    when 'MOMENT'   then delete from moments where id = r.target_id;
    when 'MESSAGE'  then update messages set deleted_at = now() where id = r.target_id and deleted_at is null;
    when 'LISTING'  then update listings set status = 'SUSPENDED', online = false where id = r.target_id and status in ('LIVE', 'PENDING');
    when 'REVIEW'   then delete from reviews where id = r.target_id;
    when 'JOB'      then update jobs set open = false where id = r.target_id;
    when 'FEEDBACK' then delete from feedback_posts where id = r.target_id;
    else null;
  end case;
  if a = 'BAN' and r.target_owner is not null then update profiles set status = 'BANNED' where id = r.target_owner and status = 'ACTIVE'; end if;
  update reports set status = 'ACTIONED', action = case a when 'BAN' then 'BANNED' else 'REMOVED' end, reviewed_by = me(), reviewed_at = now()
   where target_kind = r.target_kind and target_id = r.target_id and status = 'OPEN';
end $$;
