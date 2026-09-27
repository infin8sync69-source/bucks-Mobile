-- Discover: the universal listing profile (business / skill / driver) and cloud search.
-- Apply after schema.sql. Idempotent: every object is created "or replace".
--
-- 1. listing_points: a listing's coordinates as plain numbers. PostGIS geography reaches the app through
--    PostgREST as EWKB hex, so the app reads lat/lng from this view instead (security_invoker: the
--    listings row-level security applies, so a pending listing stays hidden from everyone but its team).
-- 2. listing_counts(): the public numbers a profile shows, in one call.
-- 3. Blocks close the listing chat too: start_listing_chat refuses a customer blocked by (or blocking) anyone who
--    runs the listing, and msg_send refuses a message into a LISTING conversation between blocked people, the same
--    rule start_direct and DIRECT conversations already follow.

set search_path = public, extensions;

create or replace view public.listing_points with (security_invoker = true) as
  select l.id, st_y(l.location::geometry) as lat, st_x(l.location::geometry) as lng
  from public.listings l
  where l.location is not null;

grant select on public.listing_points to authenticated;

-- Recommendations from neighbours, people synced with the listing, people who run it, open jobs.
-- Returns no row for a listing I may not see (pending and not mine), the same rule as listings_read.
create or replace function public.listing_counts(p_listing uuid)
returns table (recommendations int, syncs int, members int, open_jobs int)
language sql stable security definer set search_path = public, extensions as $$
  select (select count(*) from public.recommendations r where r.listing_id = p_listing)::int,
         (select count(*) from public.listing_syncs s where s.listing_id = p_listing)::int,
         (select count(*) from public.listing_members m where m.listing_id = p_listing)::int,
         (select count(*) from public.jobs j where j.listing_id = p_listing and j.open)::int
  where exists (select 1 from public.listings l where l.id = p_listing and (l.status = 'LIVE' or public.listing_role(l.id) is not null))
$$;

revoke execute on function public.listing_counts(uuid) from public, anon;
grant execute on function public.listing_counts(uuid) to authenticated;

-- Message a business or pro: everyone who runs the listing (owner and admins) shares one inbox with the customer.
-- Same as schema.sql plus the block check: the "Message" button on a profile must not get past a block that
-- start_direct already enforces. blocked_between is symmetric, so it also stops a customer who blocked the shop.
create or replace function public.start_listing_chat(p_listing uuid) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare c uuid; l listings;
begin
  select * into l from listings where id = p_listing and status = 'LIVE';
  if not found then raise exception 'not available'; end if;
  if listing_role(p_listing) is not null then raise exception 'this is your own listing'; end if;
  if exists (select 1 from listing_members m where m.listing_id = p_listing and m.role in ('OWNER', 'ADMIN') and blocked_between(me(), m.profile_id)) then
    raise exception 'you cannot message this listing';
  end if;
  select cm.conversation_id into c from conversations cv join conversation_members cm on cm.conversation_id = cv.id
   where cv.kind = 'LISTING' and cv.listing_id = p_listing and cv.created_by = me() and cm.profile_id = me() limit 1;
  if c is not null then return c; end if;
  insert into conversations (kind, listing_id, created_by, title) values ('LISTING', p_listing, me(), l.title) returning id into c;
  insert into conversation_members (conversation_id, profile_id) values (c, me());
  insert into conversation_members (conversation_id, profile_id, role)
    select c, profile_id, 'ADMIN' from listing_members where listing_id = p_listing and role in ('OWNER', 'ADMIN') on conflict do nothing;
  return c;
end $$;

revoke execute on function public.start_listing_chat(uuid) from public, anon;
grant execute on function public.start_listing_chat(uuid) to authenticated;

-- A message may not go into a DIRECT or LISTING conversation between two people who block each other; an existing
-- listing chat goes quiet in both directions once either side blocks (groups keep schema.sql's rule: members only).
drop policy if exists msg_send on public.messages;
create policy msg_send on public.messages for insert to authenticated with check (
  sender_id = public.me() and public.is_member(conversation_id)
  and not exists (select 1 from public.conversations c join public.conversation_members o on o.conversation_id = c.id
                  where c.id = messages.conversation_id and c.kind in ('DIRECT', 'LISTING') and o.profile_id <> public.me() and public.blocked_between(public.me(), o.profile_id)));
