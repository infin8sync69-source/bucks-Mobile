-- Every profile has the same five tabs: Feed, About, Gallery, <catalogue>, Recommendations.
-- The catalogue tab is per page: the owner names it ("Products", "Products and Services", "Courses and Events")
-- and picks what it holds. Both live in listings.details:
--   catalogue_label  text, at most 24 characters (the app trims)
--   catalogue_kinds  json array, a subset of PRODUCT, SERVICE, PROGRAM, EVENT
-- Without catalogue_kinds a page falls back to its type's item_kinds, so existing pages keep working.

-- The kinds a page may list: its own choice when set, else its type's.
create or replace function public.listing_item_kinds(p_listing uuid) returns text[] language sql stable security definer set search_path = public, extensions as $$
  select coalesce(
    (select array_agg(k) from jsonb_array_elements_text(case when jsonb_typeof(l.details->'catalogue_kinds') = 'array' then l.details->'catalogue_kinds' else '[]'::jsonb end) k
      where k in ('PRODUCT', 'SERVICE', 'PROGRAM', 'EVENT')),
    t.item_kinds)
  from public.listings l left join public.listing_types t on t.key = l.type_key where l.id = p_listing
$$;
revoke execute on function public.listing_item_kinds(uuid) from public, anon;
grant execute on function public.listing_item_kinds(uuid) to authenticated;

create or replace function public.items_kind_guard() returns trigger language plpgsql set search_path = public, extensions as $$
declare kinds text[];
begin
  kinds := public.listing_item_kinds(new.listing_id);
  if kinds is not null and not (new.kind = any(kinds)) then
    raise exception 'this page lists %, not %', lower(array_to_string(kinds, ' or ')) || 's', lower(new.kind) || 's';
  end if;
  return new;
end $$;

-- Orders exist only on a business page whose catalogue holds products.
create or replace function public.orders_module_guard() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.listings l where l.id = new.listing_id and l.kind = 'BUSINESS' and 'PRODUCT' = any(coalesce(public.listing_item_kinds(l.id), '{}'))) then
    raise exception 'this page does not sell products';
  end if;
  return new;
end $$;
