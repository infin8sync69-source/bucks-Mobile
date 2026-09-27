-- social-extras: group chat membership after creation, what members may change, the listing inbox as seen by
-- the people who run the listing, and nearby moments that can actually be opened.
-- create_group (schema.sql) seeds a group; add_group_members / remove_group_member let it grow and shrink.
-- Leave = delete my membership row (policy cm_leave); rename = update the title (policy conv_rename, title only).
-- Idempotent; safe to re-run. Runs after schema.sql (re-applying schema.sql re-grants whole tables).

-- Add synced, unblocked people to a group I'm in. Anyone in the group may invite their own synced people;
-- returns how many were actually added (skips strangers, blocked people and people already in the group).
create or replace function public.add_group_members(p_conv uuid, p_members uuid[]) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare m uuid; n int := 0; k text;
begin
  select kind into k from conversations where id = p_conv;
  if k is null or not is_member(p_conv) then raise exception 'you are not in this group'; end if;
  if k <> 'GROUP' then raise exception 'only groups can take more people'; end if;
  foreach m in array coalesce(p_members, '{}') loop
    if m <> me() and synced(me(), m) and not blocked_between(me(), m) then
      insert into conversation_members (conversation_id, profile_id) values (p_conv, m) on conflict do nothing;
      if found then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $$;

-- Group admins can remove someone else; people leave on their own by deleting their membership row (policy cm_leave).
create or replace function public.remove_group_member(p_conv uuid, p_member uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k text; my_role text;
begin
  select c.kind, cm.role into k, my_role from conversations c join conversation_members cm on cm.conversation_id = c.id and cm.profile_id = me() where c.id = p_conv;
  if k is null then raise exception 'you are not in this group'; end if;
  if k <> 'GROUP' then raise exception 'only groups have members to remove'; end if;
  if my_role <> 'ADMIN' then raise exception 'only a group admin can remove people'; end if;
  if p_member = me() then raise exception 'leave the group instead'; end if;
  delete from conversation_members where conversation_id = p_conv and profile_id = p_member;
end $$;

revoke execute on function public.add_group_members(uuid, uuid[]), public.remove_group_member(uuid, uuid) from public, anon;
grant execute on function public.add_group_members(uuid, uuid[]), public.remove_group_member(uuid, uuid) to authenticated;

-- ---------- what members may change ----------
-- A member's own row: only last_read_at, muted_until and archived. Role and membership are set by the security-definer
-- functions (create_group, add_group_members, start_listing_chat, ...), which run as the owner and pass this guard.
create or replace function public.guard_conversation_member() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' and (new.role <> old.role or new.conversation_id <> old.conversation_id or new.profile_id <> old.profile_id) then
    raise exception 'not allowed';
  end if;
  return new;
end $$;
drop trigger if exists conversation_member_guard on public.conversation_members;
create trigger conversation_member_guard before update on public.conversation_members for each row execute function public.guard_conversation_member();
revoke execute on function public.guard_conversation_member() from authenticated, anon, public;

-- A group's members may rename it and nothing else: kind, direct_key, listing_id, created_by and last_message_at
-- are written only by security-definer functions and the message trigger.
revoke update on public.conversations from authenticated;
grant update (title) on public.conversations to authenticated;

-- ---------- inbox ----------
-- Same columns as schema.sql. For the people who run a listing (ADMIN in a LISTING chat) other_* is the customer,
-- so their inbox tells customers apart; title stays the listing's title. Customers still see the listing only.
create or replace function public.inbox() returns table (conversation_id uuid, kind text, title text, other_id uuid, other_name text, other_code text,
  last_body text, last_at timestamptz, unread int, muted boolean, archived boolean)
language sql stable security definer set search_path = public, extensions as $$
  select c.id, c.kind,
         coalesce(c.title, op.name), op.id, op.name, op.short_code,
         (select case when m.deleted_at is not null then 'Message deleted' when m.body = '' then coalesce(m.attachment->>'name', 'Attachment') else m.body end
            from messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
         c.last_message_at,
         (select count(*)::int from messages m where m.conversation_id = c.id and m.sender_id <> me() and m.created_at > mine.last_read_at),
         coalesce(mine.muted_until > now(), false), mine.archived
  from conversation_members mine join conversations c on c.id = mine.conversation_id
  left join lateral (select p.* from conversation_members o join profiles p on p.id = o.profile_id
                      where o.conversation_id = c.id and o.profile_id <> me()
                        and (c.kind = 'DIRECT' or (c.kind = 'LISTING' and mine.role = 'ADMIN' and o.role = 'MEMBER'))
                      order by o.profile_id limit 1) op on true
  where mine.profile_id = me()
  order by c.last_message_at desc
$$;

-- ---------- nearby moments that can be opened ----------
-- moments_tray / moments_of admit LOCAL moments within 5 km of the viewer's current position, but the moments table
-- policy and the storage policy only have can_see_moment(m, null, null), with no position. open_moments records which
-- moments the viewer was shown from where they stand; can_see_moment then admits those without a position, so the
-- media can be signed. Rows go when the moment does (cascade), and blocks still win.
create table if not exists public.moment_access (
  viewer_id  uuid not null references public.profiles on delete cascade,
  moment_id  uuid not null references public.moments on delete cascade,
  granted_at timestamptz not null default now(),
  primary key (viewer_id, moment_id)
);
create index if not exists moment_access_moment_idx on public.moment_access (moment_id);
alter table public.moment_access enable row level security;
drop policy if exists maccess_read on public.moment_access;
create policy maccess_read on public.moment_access for select to authenticated using (viewer_id = public.me());
revoke all on public.moment_access from public, anon, authenticated;
grant select on public.moment_access to authenticated;

create or replace function public.can_see_moment(m public.moments, lat double precision default null, lng double precision default null) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select m.expires_at > now() and not blocked_between(me(), m.author_id) and (
    m.author_id = me()
    or (m.audience = 'SYNCED' and synced(me(), m.author_id))
    or (m.audience = 'CLOSE' and exists (select 1 from close_friends c where c.profile_id = m.author_id and c.friend_id = me()))
    or (m.audience = 'LOCAL' and (synced(me(), m.author_id)
        or (lat is not null and m.location is not null and st_dwithin(m.location, geo(lat, lng), 5000))
        or exists (select 1 from moment_access a where a.viewer_id = me() and a.moment_id = m.id))))
$$;

-- What the viewer opens: moments_of, plus access rows for the nearby moments among them.
create or replace function public.open_moments(p_author uuid, lat double precision, lng double precision) returns setof public.moments
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  insert into moment_access (viewer_id, moment_id)
    select me(), m.id from moments m where m.author_id = p_author and m.author_id <> me() and m.audience = 'LOCAL' and can_see_moment(m, lat, lng)
    on conflict do nothing;
  return query select m.* from moments m where m.author_id = p_author and can_see_moment(m, lat, lng) order by m.created_at;
end $$;
revoke execute on function public.open_moments(uuid, double precision, double precision) from public, anon;
grant execute on function public.open_moments(uuid, double precision, double precision) to authenticated;
