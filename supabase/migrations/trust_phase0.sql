-- bucks_34: recommendations, phase 0 (docs/RECOMMENDATION_ALGORITHM.md section 5).
-- Make the arrows honest before the pilot:
--   1. Listing trust is recounted from reviews by one trigger (no more drifting increments).
--   2. Reviews remember whether they came from a completed order or trip (verified), why a down was given (reason), and when
--      they were last changed (updated_at; created_at is no longer reset by an edit).
--   3. Direct votes (no order or trip) need an account at least vote_min_account_days old and can flip direction once a day.
--   4. A down after an order or a trip needs a reason.
--   5. Post votes: only on a post you can see, never your own, at most 60 an hour.
--   6. Riders and drivers rate the person they carried (profile_votes); it fills profiles.trust_up / trust_down.
-- pilot_skip_checks = 1 skips the account-age gate only, so testers with new accounts can vote; everything else applies.
-- Old function versions are renamed *_v0 (not dropped) so this can be rolled back.

insert into public.settings (key, value) values ('vote_min_account_days', 3) on conflict (key) do nothing;

-- ---------- 1. reviews: verified, reason, updated_at; recount trigger ----------
alter table public.reviews add column if not exists updated_at timestamptz not null default now();
alter table public.reviews add column if not exists reason text;
alter table public.reviews add column if not exists verified boolean generated always as (task_id is not null or order_id is not null) stored;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'reviews_reason_ok') then
    alter table public.reviews add constraint reviews_reason_ok check (reason is null or reason in ('LATE', 'QUALITY', 'PRICE', 'BEHAVIOUR', 'SAFETY', 'OTHER'));
  end if;
end $$;

create or replace function public.recount_listing_trust() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare lid uuid := coalesce(new.listing_id, old.listing_id);
begin
  update listings set trust_up = (select count(*) from reviews where listing_id = lid and vote > 0),
                      trust_down = (select count(*) from reviews where listing_id = lid and vote < 0)
   where id = lid;
  if tg_op = 'UPDATE' and new.listing_id is distinct from old.listing_id then
    update listings set trust_up = (select count(*) from reviews where listing_id = old.listing_id and vote > 0),
                        trust_down = (select count(*) from reviews where listing_id = old.listing_id and vote < 0)
     where id = old.listing_id;
  end if;
  return null;
end $$;
create or replace trigger reviews_recount after insert or update of vote, listing_id or delete on public.reviews for each row execute function public.recount_listing_trust();

-- The age gate for votes that carry no transaction.
create or replace function public.vote_age_ok() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value::int from settings where key = 'pilot_skip_checks'), 0) = 1
      or (select created_at from profiles where id = me()) <= now() - make_interval(days => coalesce((select value::int from settings where key = 'vote_min_account_days'), 3))
$$;

-- ---------- 2. direct listing votes ----------
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'rate_listing_v0') then
    alter function public.rate_listing(uuid, int, text) rename to rate_listing_v0;
    revoke execute on function public.rate_listing_v0(uuid, int, text) from public, anon, authenticated;
  end if;
end $$;
create or replace function public.rate_listing(p_listing uuid, p_vote int, p_comment text default '', p_reason text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c text := btrim(coalesce(p_comment, '')); n int; old reviews;
begin
  if me() is null then raise exception 'sign in first'; end if;
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  if length(c) > 500 then raise exception 'keep the comment under 500 characters'; end if;
  if not exists (select 1 from listings l where l.id = p_listing and l.status = 'LIVE') then raise exception 'this profile is not live'; end if;
  if listing_role(p_listing) is not null then raise exception 'you cannot rate your own profile'; end if;
  if not vote_age_ok() then raise exception 'new accounts can recommend after a few days on Bucks'; end if;
  select count(*) into n from reviews where author_id = me() and updated_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'too many ratings this hour, try again later'; end if;
  select * into old from reviews where listing_id = p_listing and author_id = me() and task_id is null and order_id is null for update;
  if found then
    if old.vote <> p_vote and old.updated_at > now() - interval '24 hours' then raise exception 'you can change your vote again tomorrow'; end if;
    update reviews set vote = p_vote::smallint, comment = c, reason = case when p_vote < 0 then p_reason end, updated_at = now() where id = old.id;
  else
    insert into reviews (listing_id, author_id, vote, comment, reason) values (p_listing, me(), p_vote::smallint, c, case when p_vote < 0 then p_reason end);
  end if;
end $$;
grant execute on function public.rate_listing(uuid, int, text, text) to authenticated;

create or replace function public.clear_listing_rating(p_listing uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  -- the recount trigger takes the vote back off the listing
  delete from reviews where listing_id = p_listing and author_id = me() and task_id is null and order_id is null;
end $$;

-- ---------- 3. verified reviews after a completed order or trip ----------
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'review_v0') then
    alter function public.review(uuid, uuid, uuid, int, text) rename to review_v0;
    revoke execute on function public.review_v0(uuid, uuid, uuid, int, text) from public, anon, authenticated;
  end if;
end $$;
create or replace function public.review(p_listing uuid, p_task uuid, p_order uuid, p_vote int, p_comment text, p_reason text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l listings; ok boolean := false;
begin
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  select * into l from listings where id = p_listing;
  if p_task is not null then
    select exists (select 1 from tasks t where t.id = p_task and t.requester_id = me() and t.status in ('COMPLETED', 'PAID') and l.kind = 'DRIVER' and l.owner_id = t.driver_id) into ok;
  elsif p_order is not null then
    select exists (select 1 from orders o where o.id = p_order and o.buyer_id = me() and o.status = 'DELIVERED' and o.listing_id = p_listing) into ok;
  end if;
  if not ok then raise exception 'you can review after a completed trip or order'; end if;
  if l.owner_id = me() or listing_role(p_listing) is not null then raise exception 'you cannot review your own listing'; end if;
  if p_vote < 0 and coalesce(p_reason, '') not in ('LATE', 'QUALITY', 'PRICE', 'BEHAVIOUR', 'SAFETY', 'OTHER') then raise exception 'pick what went wrong'; end if;
  if p_task is not null and exists (select 1 from reviews r where r.author_id = me() and r.task_id = p_task) then raise exception 'you already reviewed this trip'; end if;
  if p_task is null and exists (select 1 from reviews r where r.author_id = me() and r.order_id = p_order) then raise exception 'you already reviewed this order'; end if;
  insert into reviews (listing_id, author_id, task_id, order_id, vote, comment, reason)
  values (p_listing, me(), p_task, p_order, p_vote, left(btrim(coalesce(p_comment, '')), 500), case when p_vote < 0 then p_reason end);
end $$;
grant execute on function public.review(uuid, uuid, uuid, int, text, text) to authenticated;

-- My review of one order, so the order screen knows whether to ask.
create or replace function public.my_order_review(p_order uuid) returns smallint language sql stable security definer set search_path = public, extensions as $$
  select vote from reviews where order_id = p_order and author_id = me() limit 1
$$;
grant execute on function public.my_order_review(uuid) to authenticated;

-- ---------- 4. product votes: same age gate and daily flip limit ----------
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'rate_product_v0') then
    alter function public.rate_product(uuid, text, int, text) rename to rate_product_v0;
    revoke execute on function public.rate_product_v0(uuid, text, int, text) from public, anon, authenticated;
  end if;
end $$;
create or replace function public.rate_product(p_listing uuid, p_key text, p_vote int, p_comment text default '') returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c text := btrim(coalesce(p_comment, '')); n int; old public.product_ratings; who text;
begin
  if public.me() is null then raise exception 'sign in first'; end if;
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  if length(c) > 500 then raise exception 'keep the comment under 500 characters'; end if;
  if not exists (select 1 from public.listings l where l.id = p_listing and l.status = 'LIVE') then raise exception 'this store is not open for feedback'; end if;
  if public.can_manage_listing(p_listing) then raise exception 'you cannot rate your own product'; end if;
  if not exists (select 1 from public.items i where i.listing_id = p_listing and public.item_product_key(i.details, i.id) = p_key) then raise exception 'that product is not in this store'; end if;
  if not public.vote_age_ok() then raise exception 'new accounts can recommend after a few days on Bucks'; end if;
  select count(*) into n from public.product_ratings where profile_id = public.me() and updated_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'too many ratings this hour, try again later'; end if;
  select * into old from public.product_ratings where listing_id = p_listing and product_key = p_key and profile_id = public.me();
  if found and old.vote <> p_vote and old.updated_at > now() - interval '24 hours' then raise exception 'you can change your vote again tomorrow'; end if;
  insert into public.product_ratings (listing_id, product_key, profile_id, vote, comment) values (p_listing, p_key, public.me(), p_vote::smallint, c)
  on conflict (listing_id, product_key, profile_id) do update set vote = excluded.vote, comment = excluded.comment, updated_at = now();
  if c <> '' and c is distinct from old.comment then
    select name into who from public.profiles where id = public.me();
    perform public.push_note_team(p_listing, 'PRODUCT_FEEDBACK', coalesce(who, 'Someone') || ' ' || case when p_vote = 1 then 'recommends' else 'does not recommend' end || ' a product', left(c, 140), 'studio/' || p_listing);
  end if;
end $$;
grant execute on function public.rate_product(uuid, text, int, text) to authenticated;

-- ---------- 5. post votes ----------
alter table public.post_votes add column if not exists created_at timestamptz not null default now();
-- Definer helper so the policy can read posts without leaning on the caller's grants.
create or replace function public.can_vote_post(p_post uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from posts p where p.id = p_post and p.author_id <> me() and can_see_post(p))
$$;
alter policy votes_self on public.post_votes using (profile_id = me()) with check (profile_id = me() and public.can_vote_post(post_id));
create or replace function public.post_vote_rate() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if (select count(*) from post_votes where profile_id = new.profile_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'too many votes this hour, try again later';
  end if;
  new.created_at := now();
  return new;
end $$;
create or replace trigger post_vote_rate before insert or update of vote on public.post_votes for each row execute function public.post_vote_rate();

-- ---------- 6. people: the driver rates the rider (and later the shop rates the buyer) ----------
create table if not exists public.profile_votes (
  id uuid primary key default uuid_v7(),
  subject_id uuid not null references public.profiles(id) on delete cascade,
  voter_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  vote smallint not null check (vote in (1, -1)),
  reason text check (reason is null or reason in ('LATE', 'QUALITY', 'PRICE', 'BEHAVIOUR', 'SAFETY', 'OTHER')),
  comment text not null default '' check (length(comment) <= 500),
  created_at timestamptz not null default now(),
  check (subject_id <> voter_id)
);
create unique index if not exists profile_votes_one_per_task on public.profile_votes (voter_id, task_id) where task_id is not null;
alter table public.profile_votes enable row level security;
-- Only the voter reads their own vote; everyone sees the totals on profiles.
do $$ begin if not exists (select 1 from pg_policies where policyname = 'profile_votes_mine') then
create policy profile_votes_mine on public.profile_votes for select using (voter_id = me());
end if; end $$;
grant select on public.profile_votes to authenticated;

create or replace function public.recount_profile_trust() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare sid uuid := coalesce(new.subject_id, old.subject_id);
begin
  update profiles set trust_up = (select count(*) from profile_votes where subject_id = sid and vote > 0),
                      trust_down = (select count(*) from profile_votes where subject_id = sid and vote < 0)
   where id = sid;
  return null;
end $$;
create or replace trigger profile_votes_recount after insert or update or delete on public.profile_votes for each row execute function public.recount_profile_trust();

create or replace function public.rate_rider(p_task uuid, p_vote int, p_comment text default '', p_reason text default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare t tasks;
begin
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  select * into t from tasks where id = p_task;
  if not found or t.driver_id is distinct from me() or t.status not in ('COMPLETED', 'PAID') then raise exception 'you can rate the customer after the trip'; end if;
  if p_vote < 0 and coalesce(p_reason, '') not in ('LATE', 'QUALITY', 'PRICE', 'BEHAVIOUR', 'SAFETY', 'OTHER') then raise exception 'pick what went wrong'; end if;
  if exists (select 1 from profile_votes where voter_id = me() and task_id = p_task) then raise exception 'you already rated this trip'; end if;
  insert into profile_votes (subject_id, voter_id, task_id, vote, reason, comment)
  values (t.requester_id, me(), p_task, p_vote, case when p_vote < 0 then p_reason end, left(btrim(coalesce(p_comment, '')), 500));
end $$;
grant execute on function public.rate_rider(uuid, int, text, text) to authenticated;

-- ---------- one-time: recount everything so the numbers start honest ----------
update public.listings l set trust_up = (select count(*) from public.reviews r where r.listing_id = l.id and r.vote > 0),
                             trust_down = (select count(*) from public.reviews r where r.listing_id = l.id and r.vote < 0);
update public.profiles p set trust_up = (select count(*) from public.profile_votes v where v.subject_id = p.id and v.vote > 0),
                             trust_down = (select count(*) from public.profile_votes v where v.subject_id = p.id and v.vote < 0);
