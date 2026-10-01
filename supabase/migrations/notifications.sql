-- In-app notifications: the "Notifications" tab next to Messages.
--
-- What lands here (the things that need a person to act or want to know), written by database triggers so no app version can
-- forget or fake one: a sync request or acceptance, an invite to run a listing or drive a vehicle, a new order (to the shop),
-- an order changing status (to the buyer), a local recommendation, a listing going live or being paused, a document checked or
-- rejected, and a new review. Chat messages stay in Messages. Push notifications are unchanged (supabase/functions/notify).
--
-- Each row carries a route the app opens when tapped; the app only follows routes it knows (Push.safeRoute).
-- People read only their own rows and can mark them read or delete them; nobody can insert or edit from the app.
set search_path = public, extensions;

create table if not exists public.notifications (
  id          uuid primary key default public.uuid_v7(),
  profile_id  uuid not null references public.profiles on delete cascade,
  kind        text not null,
  title       text not null,
  body        text not null default '',
  route       text,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index if not exists notifications_profile_idx on public.notifications (profile_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select to authenticated using (profile_id = (select public.me()));
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications for delete to authenticated using (profile_id = (select public.me()));
revoke insert, update on public.notifications from authenticated, anon;

-- One notification for one person; never for yourself.
create or replace function public.push_note(p uuid, k text, t text, b text, r text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p is null or p = public.me() then return; end if;
  insert into notifications (profile_id, kind, title, body, route) values (p, k, left(t, 120), left(coalesce(b, ''), 240), r);
end $$;

-- The same note for everyone who runs a listing (owner and admins), except the person who caused it.
create or replace function public.push_note_team(l uuid, k text, t text, b text, r text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare m uuid;
begin
  for m in select profile_id from listing_members where listing_id = l and role in ('OWNER', 'ADMIN') loop perform push_note(m, k, t, b, r); end loop;
end $$;

create or replace function public.pname(p uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select coalesce(nullif(name, ''), 'Someone') from profiles where id = p
$$;

-- ---------- sync ----------
create or replace function public.note_sync() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' and new.status = 'PENDING' then
    perform push_note(new.addressee_id, 'SYNC_REQUEST', pname(new.requester_id) || ' wants to sync with you', 'Accept to message each other and see each other''s posts.', 'sync');
  elsif tg_op = 'UPDATE' and new.status = 'ACCEPTED' and old.status = 'PENDING' then
    perform push_note(new.requester_id, 'SYNC_ACCEPTED', pname(new.addressee_id) || ' accepted your sync request', 'You can message each other now.', 'sync');
  end if;
  return null;
end $$;
drop trigger if exists note_sync on public.syncs;
create trigger note_sync after insert or update of status on public.syncs for each row execute function public.note_sync();

-- ---------- invites ----------
create or replace function public.note_invite() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare what text;
begin
  if new.status <> 'PENDING' then return null; end if;
  what := case when new.listing_id is not null then 'help run ' || coalesce((select title from listings where id = new.listing_id), 'a listing')
               else 'drive ' || coalesce((select nullif(model, '') || ' ' from vehicles where id = new.vehicle_id), '') || coalesce((select plate from vehicles where id = new.vehicle_id), 'a vehicle') end;
  perform push_note(new.invitee_id, 'INVITE', pname(new.inviter_id) || ' invited you to ' || what, 'Open Invites to accept or decline.', 'invites');
  return null;
end $$;
drop trigger if exists note_invite on public.invites;
create trigger note_invite after insert on public.invites for each row execute function public.note_invite();

-- ---------- orders ----------
create or replace function public.note_order() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare shop text; verb text;
begin
  select title into shop from listings where id = new.listing_id;
  if tg_op = 'INSERT' then
    perform push_note_team(new.listing_id, 'ORDER_NEW', 'New order · ₹' || new.subtotal, pname(new.buyer_id) || ' ordered from ' || coalesce(shop, 'your shop') || '. Accept it in time.', 'orders-for/' || new.listing_id);
  elsif new.status is distinct from old.status then
    verb := case new.status when 'ACCEPTED' then 'was accepted' when 'REJECTED' then 'was declined' when 'READY' then 'is ready' when 'PICKED_UP' then 'is on its way'
                            when 'DELIVERED' then 'was delivered' when 'CANCELLED' then case when new.cancelled_by = 'BUYER' then null else 'was cancelled by the shop' end end;
    if verb is not null then perform push_note(new.buyer_id, 'ORDER_UPDATE', 'Your order from ' || coalesce(shop, 'the shop') || ' ' || verb, 'Tap to see the details.', 'cloud-order/' || new.id); end if;
  end if;
  return null;
end $$;
drop trigger if exists note_order on public.orders;
create trigger note_order after insert or update of status on public.orders for each row execute function public.note_order();

-- ---------- recommendations and going live ----------
create or replace function public.note_recommendation() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare l listings; n int;
begin
  select * into l from listings where id = new.listing_id;
  select count(*) into n from recommendations where listing_id = new.listing_id;
  perform push_note_team(new.listing_id, 'RECOMMENDED', 'Someone nearby recommended ' || l.title, n || ' of ' || setting('min_recommendations')::int || ' recommendations so far.', 'studio/' || new.listing_id);
  return null;
end $$;
drop trigger if exists note_recommendation on public.recommendations;
create trigger note_recommendation after insert on public.recommendations for each row execute function public.note_recommendation();

create or replace function public.note_listing_status() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'LIVE' and old.status <> 'LIVE' then
    perform push_note_team(new.id, 'LISTING_LIVE', new.title || ' is live', 'People nearby can find it now. Switch it on when you''re ready for work.', 'studio/' || new.id);
  elsif new.status = 'SUSPENDED' and old.status = 'LIVE' then
    perform push_note_team(new.id, 'LISTING_PAUSED', new.title || ' was paused', case when new.compliance_hold then 'A document expired or is missing. Upload it and it comes back on its own.' else 'Contact Bucks support to sort it out.' end, 'studio/' || new.id);
  end if;
  return null;
end $$;
drop trigger if exists note_listing_status on public.listings;
create trigger note_listing_status after update of status on public.listings for each row execute function public.note_listing_status();

-- ---------- documents and reviews ----------
create or replace function public.note_document() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare lbl text; ttl text;
begin
  if new.status = old.status or new.status not in ('VERIFIED', 'REJECTED') then return null; end if;
  select label into lbl from doc_types where key = new.doc_type; select title into ttl from listings where id = new.listing_id;
  perform push_note(new.uploaded_by, 'DOCUMENT_' || new.status, coalesce(lbl, 'Your document') || case new.status when 'VERIFIED' then ' was checked' else ' was rejected' end,
                    coalesce(ttl, 'Your listing') || case when new.status = 'REJECTED' and new.note <> '' then ': ' || new.note else '' end, 'listing-docs/' || new.listing_id);
  return null;
end $$;
drop trigger if exists note_document on public.listing_documents;
create trigger note_document after update of status on public.listing_documents for each row execute function public.note_document();

create or replace function public.note_review() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare ttl text;
begin
  select title into ttl from listings where id = new.listing_id;
  perform push_note_team(new.listing_id, 'REVIEW', case when new.vote > 0 then 'New recommendation for ' else 'New feedback for ' end || coalesce(ttl, 'your listing'), new.comment, 'studio/' || new.listing_id);
  return null;
end $$;
drop trigger if exists note_review on public.reviews;
create trigger note_review after insert on public.reviews for each row execute function public.note_review();

-- ---------- reading ----------
-- Marks my notifications read: the given ones, or all of them when p_ids is null. Returns how many changed.
create or replace function public.mark_notifications_read(p_ids uuid[] default null) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  update notifications set read_at = now() where profile_id = me() and read_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count; return n;
end $$;

-- Old notifications go after 90 days.
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('bucks-clean-notifications', '40 20 * * *', 'delete from public.notifications where created_at < now() - interval ''90 days''');
  end if;
end $$;

-- ---------- grants ----------
revoke execute on function public.push_note(uuid, text, text, text, text), public.push_note_team(uuid, text, text, text, text), public.pname(uuid),
  public.note_sync(), public.note_invite(), public.note_order(), public.note_recommendation(), public.note_listing_status(), public.note_document(), public.note_review()
  from authenticated, anon, public;
revoke execute on function public.mark_notifications_read(uuid[]) from anon, public;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
grant select, delete on public.notifications to authenticated;
