-- Manage feature: owners' own listings, vehicles, admins and recommendations.
-- Safe to re-run. Apply after supabase/schema.sql.
set search_path = public, extensions;

-- Invites addressed to me, with who sent them and what they are for. The invitee cannot read a
-- pending listing or someone else's vehicle through row-level security until they accept, so the
-- names come from this function instead of the tables.
create or replace function public.my_invites()
returns table (id uuid, listing_id uuid, vehicle_id uuid, inviter_id uuid, inviter_name text, role text, title text, kind text, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select i.id, i.listing_id, i.vehicle_id, i.inviter_id, p.name as inviter_name, i.role,
         coalesce(l.title, nullif(trim(v.model || ' ' || v.plate), ''), 'A vehicle') as title,
         coalesce(l.kind, 'VEHICLE') as kind,
         i.created_at
  from public.invites i
  join public.profiles p on p.id = i.inviter_id
  left join public.listings l on l.id = i.listing_id
  left join public.vehicles v on v.id = i.vehicle_id
  where i.invitee_id = public.me() and i.status = 'PENDING'
  order by i.created_at desc
$$;

revoke execute on function public.my_invites() from public, anon;
grant execute on function public.my_invites() to authenticated;
