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

-- ---------- privacy: where people live, and who recommended whom ----------
-- profiles.home is a person's real home; only recommend() and suggest_people() (security definer) need it. The API gets every
-- other column, so any client must name its columns (select=* is refused once one column is withheld; Backend.profiles and
-- profileByCode do). Re-applying schema.sql re-grants the whole table, so this migration always runs after it.
revoke select on public.profiles from authenticated;
grant select (id, auth_uid, short_code, name, bio, area, photo_url, trust_up, trust_down, status, created_at) on public.profiles to authenticated;

-- A recommendation row carries the recommender and the exact point they stood at. The listing's team sees its own
-- rows (the hub counts them); a recommender sees their own; nobody else. Public counts come from listing_counts() (discover.sql).
drop policy if exists recs_read on public.recommendations;
create policy recs_read on public.recommendations for select to authenticated
  using (recommender_id = public.me() or public.listing_role(listing_id) is not null);

-- ---------- vehicles: verification is per kind, plate and documents ----------
-- Bucks checks a specific vehicle's papers. The owner may still edit anything, but changing the type, the plate or the
-- documents of a checked vehicle puts it back to PENDING. Documents are compared by their storage paths, so the app
-- re-sending the same list in a different JSON shape or key order does not restart the check.
create or replace function public.guard_vehicle() returns trigger language plpgsql set search_path = public, extensions as $$
declare old_paths text[]; new_paths text[];
begin
  if current_user = 'authenticated' then
    if new.status <> old.status or new.owner_id <> old.owner_id then raise exception 'vehicle status is managed by Bucks'; end if;
    select coalesce(array_agg(x.p order by x.p), '{}') into old_paths
      from jsonb_array_elements(case when jsonb_typeof(old.docs) = 'array' then old.docs else '[]'::jsonb end) e, lateral (select coalesce(e->>'path', e#>>'{}') as p) x;
    select coalesce(array_agg(x.p order by x.p), '{}') into new_paths
      from jsonb_array_elements(case when jsonb_typeof(new.docs) = 'array' then new.docs else '[]'::jsonb end) e, lateral (select coalesce(e->>'path', e#>>'{}') as p) x;
    if new.kind <> old.kind or new.plate <> old.plate or new_paths <> old_paths then new.status := 'PENDING'; end if;
  end if;
  return new;
end $$;

-- Only a checked (ACTIVE) vehicle can go online; going offline is always allowed, even after a suspension.
drop policy if exists presence_insert on public.driver_presence;
drop policy if exists presence_update on public.driver_presence;
create policy presence_insert on public.driver_presence for insert to authenticated
  with check (profile_id = public.me() and public.vehicle_role(vehicle_id) is not null
              and (not online or exists (select 1 from public.vehicles v where v.id = vehicle_id and v.status = 'ACTIVE')));
create policy presence_update on public.driver_presence for update to authenticated using (profile_id = public.me())
  with check (profile_id = public.me() and public.vehicle_role(vehicle_id) is not null
              and (not online or exists (select 1 from public.vehicles v where v.id = vehicle_id and v.status = 'ACTIVE')));

-- ---------- deleting a vehicle or a listing that has history ----------
-- A vehicle's trips stay with the driver (task_events.driver_id, tasks.driver_id); the vehicle reference is simply cleared,
-- so the owner can remove a vehicle that has taken trips. vehicle_stats is driven from vehicles, so the dashboard row disappears.
alter table public.tasks drop constraint if exists tasks_vehicle_id_fkey;
alter table public.tasks add constraint tasks_vehicle_id_fkey foreign key (vehicle_id) references public.vehicles on delete set null;
alter table public.task_events alter column vehicle_id drop not null;
alter table public.task_events drop constraint if exists task_events_vehicle_id_fkey;
alter table public.task_events add constraint task_events_vehicle_id_fkey foreign key (vehicle_id) references public.vehicles on delete set null;

-- Orders are the buyer's history and must outlive the shop (orders.listing_id has no cascade on purpose). A listing that
-- never took an order is deleted outright; one with finished orders is emptied (products, members, recommendations, reviews,
-- jobs, posts, chats go, as a delete would take them) and kept as a hidden DELETED row that the orders still point to.
-- While an order is still open the owner has to finish or reject it first.
alter table public.listings drop constraint if exists listings_status_check;
alter table public.listings add constraint listings_status_check check (status in ('PENDING', 'LIVE', 'SUSPENDED', 'DELETED'));

create or replace function public.delete_listing(p_listing uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare n_orders int; n_open int;
begin
  if coalesce(listing_role(p_listing), '') <> 'OWNER' then raise exception 'only the owner can delete a listing'; end if;
  select count(*), count(*) filter (where status in ('PLACED', 'ACCEPTED', 'READY', 'PICKED_UP')) into n_orders, n_open from orders where listing_id = p_listing;
  if n_open > 0 then raise exception 'this shop has orders in progress; finish or reject them first'; end if;
  if n_orders = 0 then delete from listings where id = p_listing; return; end if;
  delete from items where listing_id = p_listing;
  delete from listing_members where listing_id = p_listing;
  delete from listing_syncs where listing_id = p_listing;
  delete from invites where listing_id = p_listing;
  delete from recommendations where listing_id = p_listing;
  delete from recommend_tokens where listing_id = p_listing;
  delete from reviews where listing_id = p_listing;
  delete from jobs where listing_id = p_listing;
  delete from posts where listing_id = p_listing;
  delete from moments where listing_id = p_listing;
  delete from conversations where listing_id = p_listing;
  update listings set status = 'DELETED', online = false, photo_url = null where id = p_listing;
end $$;

revoke execute on function public.delete_listing(uuid) from public, anon;
grant execute on function public.delete_listing(uuid) to authenticated;
