-- One review() again. trust_phase0.sql renamed the 5-argument review() to review_v0 and added review(..., p_reason text default null);
-- hardening_dispatch.sql then re-created a 5-argument review() with its own checks. Two overloads meant a call with the five common
-- named arguments matched both ("function review(...) is not unique"): the iOS app's reviews failed, and the 5-argument version also
-- added to listings.trust_up/down by hand on top of recount_listing_trust (trust_phase0.sql), counting each review twice.
-- This keeps the 6-argument signature (p_reason optional) with trust_phase0's rules (vote is 1 or -1, a down needs a reason, the
-- trigger recounts trust) plus hardening_dispatch's checks (a ride is paid before it's reviewed, no review of a trip or order that
-- was too short, at most 3 reviews a day), and drops the 5-argument one. Safe to run more than once. Apply after pilot_grants.sql.
set search_path = public, extensions;

drop function if exists public.review(uuid, uuid, uuid, integer, text);

create or replace function public.review(p_listing uuid, p_task uuid, p_order uuid, p_vote int, p_comment text, p_reason text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l listings; ok boolean := false; t tasks; o orders; min_s double precision := public.dispatch_cfg('min_trip_seconds', 60)::double precision;
begin
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  select * into l from listings where id = p_listing;
  if p_task is not null then
    select * into t from tasks x where x.id = p_task and x.requester_id = me() and x.status in ('COMPLETED', 'PAID') and l.kind = 'DRIVER' and l.owner_id = x.driver_id;
    ok := found;
  elsif p_order is not null then
    select * into o from orders x where x.id = p_order and x.buyer_id = me() and x.status = 'DELIVERED' and x.listing_id = p_listing;
    ok := found;
  end if;
  if not ok then raise exception 'you can review after a completed trip or order'; end if;
  if l.owner_id = me() or listing_role(p_listing) is not null then raise exception 'you cannot review your own listing'; end if;
  if p_vote < 0 and coalesce(p_reason, '') not in ('LATE', 'QUALITY', 'PRICE', 'BEHAVIOUR', 'SAFETY', 'OTHER') then raise exception 'pick what went wrong'; end if;
  if p_task is not null and exists (select 1 from reviews r where r.author_id = me() and r.task_id = p_task) then raise exception 'you already reviewed this trip'; end if;
  if p_task is null and exists (select 1 from reviews r where r.author_id = me() and r.order_id = p_order) then raise exception 'you already reviewed this order'; end if;
  if p_task is not null then
    if t.type = 'RIDE' and t.status <> 'PAID' then raise exception 'mark the trip as paid, then review it'; end if;
    if t.started_at is not null and t.completed_at is not null and extract(epoch from t.completed_at - t.started_at) < min_s then raise exception 'that trip was too short to review'; end if;
  else
    if o.accepted_at is not null and o.delivered_at is not null and extract(epoch from o.delivered_at - o.accepted_at) < min_s then raise exception 'that order was too quick to review'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('review:' || me()::text, 0));
  if (select count(*) from reviews r where r.author_id = me() and r.created_at > now() - interval '24 hours') >= 3 then raise exception 'you can post 3 reviews a day; try again tomorrow'; end if;
  -- trust_up / trust_down follow from recount_listing_trust (trust_phase0.sql); no hand-made increment here.
  insert into reviews (listing_id, author_id, task_id, order_id, vote, comment, reason)
  values (p_listing, me(), p_task, p_order, p_vote, left(btrim(coalesce(p_comment, '')), 500), case when p_vote < 0 then p_reason end);
end $$;
revoke execute on function public.review(uuid, uuid, uuid, int, text, text) from public, anon;
grant execute on function public.review(uuid, uuid, uuid, int, text, text) to authenticated;

-- A review through the old 5-argument version left its listing one too high (the trigger's recount, then the hand-made +1). Recount
-- every listing once from its reviews, which is what recount_listing_trust maintains from here on.
update public.listings l set trust_up = c.up, trust_down = c.down
  from (select x.id, (select count(*) from public.reviews r where r.listing_id = x.id and r.vote > 0)::int as up,
                     (select count(*) from public.reviews r where r.listing_id = x.id and r.vote < 0)::int as down from public.listings x) c
 where c.id = l.id and (l.trust_up, l.trust_down) is distinct from (c.up, c.down);
