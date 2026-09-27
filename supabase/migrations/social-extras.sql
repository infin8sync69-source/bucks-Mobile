-- social-extras: group chat membership after creation.
-- create_group (schema.sql) seeds a group; these two let it grow and shrink. Idempotent; safe to re-run.
-- Everything else the feature needs (rename by any member, leave = delete my membership row, listing chats,
-- moment mutes) is already covered by the policies in schema.sql.

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
