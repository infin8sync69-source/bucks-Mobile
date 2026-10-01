-- ============================================================================
-- Bucks: product feedback, follower feed, slim catalogue (bucks_28)
--  1. product_ratings: anyone signed in can recommend / not recommend any product of a live store, with an optional comment (one per person
--     per product, editable). Written only through rate_product(), read through product_ratings_summary() / product_ratings_list().
--  2. can_see_post: a store's posts are visible to the people who synced with the store (listing_syncs), so they show in their Feed.
--  3. catalog_items(): a store's items without descriptions and extra photos (about a tenth of the size) for the Products tab; the full
--     row is fetched when a product is opened.
--  4. push_posts: a store's new post is pushed to its followers (the notify function does the fan-out).
-- ============================================================================

create table if not exists public.product_ratings (
  listing_id  uuid not null references public.listings on delete cascade,
  product_key text not null check (length(product_key) between 1 and 80),
  profile_id  uuid not null references public.profiles on delete cascade,
  vote        smallint not null check (vote in (1, -1)),
  comment     text not null default '' check (length(comment) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (listing_id, product_key, profile_id)
);
create index if not exists product_ratings_lookup on public.product_ratings (listing_id, product_key, updated_at desc);
create index if not exists product_ratings_by_person on public.product_ratings (profile_id, updated_at desc);
alter table public.product_ratings enable row level security;
drop policy if exists product_ratings_read on public.product_ratings;
create policy product_ratings_read on public.product_ratings for select to authenticated using (not public.blocked_between(public.me(), profile_id));
revoke insert, update, delete on public.product_ratings from authenticated, anon;

-- The key a product is rated under: the Shopify product id for imported stores (all its options share one rating), else the item's own id.
create or replace function public.item_product_key(d jsonb, item_id uuid) returns text language sql immutable as $$
  select coalesce(nullif(d->>'product_id', ''), item_id::text)
$$;

create or replace function public.rate_product(p_listing uuid, p_key text, p_vote int, p_comment text default '') returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c text := btrim(coalesce(p_comment, '')); n int; old_comment text; who text;
begin
  if public.me() is null then raise exception 'sign in first'; end if;
  if p_vote not in (1, -1) then raise exception 'choose recommend or not recommend'; end if;
  if length(c) > 500 then raise exception 'keep the comment under 500 characters'; end if;
  if not exists (select 1 from public.listings l where l.id = p_listing and l.status = 'LIVE') then raise exception 'this store is not open for feedback'; end if;
  if public.can_manage_listing(p_listing) then raise exception 'you cannot rate your own product'; end if;
  if not exists (select 1 from public.items i where i.listing_id = p_listing and public.item_product_key(i.details, i.id) = p_key) then raise exception 'that product is not in this store'; end if;
  select count(*) into n from public.product_ratings where profile_id = public.me() and updated_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'too many ratings this hour, try again later'; end if;
  select comment into old_comment from public.product_ratings where listing_id = p_listing and product_key = p_key and profile_id = public.me();
  insert into public.product_ratings (listing_id, product_key, profile_id, vote, comment) values (p_listing, p_key, public.me(), p_vote::smallint, c)
  on conflict (listing_id, product_key, profile_id) do update set vote = excluded.vote, comment = excluded.comment, updated_at = now();
  if c <> '' and c is distinct from old_comment then
    select name into who from public.profiles where id = public.me();
    perform public.push_note_team(p_listing, 'PRODUCT_FEEDBACK', coalesce(who, 'Someone') || ' ' || case when p_vote = 1 then 'recommends' else 'does not recommend' end || ' a product', left(c, 140), 'studio/' || p_listing);
  end if;
end $$;

create or replace function public.clear_product_rating(p_listing uuid, p_key text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from public.product_ratings where listing_id = p_listing and product_key = p_key and profile_id = public.me()
$$;

-- One call for the whole store: per product, recommends, not-recommends, comments, and my own vote.
create or replace function public.product_ratings_summary(p_listing uuid) returns table (product_key text, up int, down int, comments int, mine int)
language sql stable security definer set search_path = public, extensions as $$
  select r.product_key, (count(*) filter (where r.vote = 1))::int, (count(*) filter (where r.vote = -1))::int,
         (count(*) filter (where r.comment <> ''))::int, (max(r.vote) filter (where r.profile_id = public.me()))::int
  from public.product_ratings r
  where r.listing_id = p_listing and not public.blocked_between(public.me(), r.profile_id)
  group by r.product_key
$$;

-- Comments on one product, newest first, with who wrote them.
create or replace function public.product_ratings_list(p_listing uuid, p_key text, p_before timestamptz default now(), p_lim int default 20)
returns table (profile_id uuid, name text, vote int, comment text, updated_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select r.profile_id, p.name, r.vote::int, r.comment, r.updated_at
  from public.product_ratings r join public.profiles p on p.id = r.profile_id
  where r.listing_id = p_listing and r.product_key = p_key and r.comment <> '' and r.updated_at < p_before and not public.blocked_between(public.me(), r.profile_id)
  order by r.updated_at desc limit least(greatest(p_lim, 1), 50)
$$;

revoke execute on function public.rate_product(uuid, text, int, text), public.clear_product_rating(uuid, text), public.product_ratings_summary(uuid), public.product_ratings_list(uuid, text, timestamptz, int) from public, anon;
grant execute on function public.rate_product(uuid, text, int, text), public.clear_product_rating(uuid, text), public.product_ratings_summary(uuid), public.product_ratings_list(uuid, text, timestamptz, int) to authenticated;

-- ---------- 2. a store's posts reach the people who synced with it ----------
create or replace function public.can_see_post(p posts) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select p.deleted_at is null and not blocked_between(me(), p.author_id) and
         (p.author_id = me() or p.visibility in ('PUBLIC', 'LOCAL') or (p.visibility = 'SYNCED' and synced(me(), p.author_id))
          or (p.listing_id is not null and exists (select 1 from listing_syncs s where s.profile_id = me() and s.listing_id = p.listing_id)))
$$;

-- ---------- 3. slim catalogue ----------
create or replace function public.catalog_items(p_listing uuid) returns setof public.items
language sql stable set search_path = public, extensions as $$
  select i.id, i.listing_id, i.kind, i.name, i.price, i.mrp, i.unit, i.group_name, i.photo_url, i.in_stock, i.sort, i.created_at,
         ''::text as description, i.stock,
         case when jsonb_array_length(i.photos) > 0 then jsonb_build_array(i.photos -> 0) else '[]'::jsonb end as photos,
         jsonb_strip_nulls(jsonb_build_object('product_id', i.details -> 'product_id', 'product', i.details -> 'product', 'variant', i.details -> 'variant',
                                              'sku', i.details -> 'sku', 'vendor', i.details -> 'vendor', 'brand', i.details -> 'brand', 'veg', i.details -> 'veg')) as details
  from public.items i where i.listing_id = p_listing order by i.sort
$$;
grant execute on function public.catalog_items(uuid) to authenticated;
revoke execute on function public.catalog_items(uuid) from anon, public;

-- ---------- 4. push a store's new post to its followers ----------
drop trigger if exists push_posts on public.posts;
create trigger push_posts after insert on public.posts for each row when (new.listing_id is not null) execute function public.push_notify();
