-- ============================================================================
-- Bucks: Aspire More catalogue photos (bucks_27)
-- The Aspire More store (aspiremore.in, Shopify) was imported as a business listing under Shafeeq D E. Its product photos stay on
-- Shopify's CDN (the sandbox and Supabase edge functions can't download them to storage), so a listing or product photo may also be an
-- image of that store's own CDN folder. Everything else must still be in the listing's own listing-media folder.
-- ============================================================================
create or replace function public.media_urls_ok(g jsonb, lid uuid, max_n int) returns boolean language sql immutable set search_path = public, extensions as $$
  select jsonb_typeof(g) = 'array' and jsonb_array_length(g) <= max_n and not exists (
    select 1 from jsonb_array_elements(g) e
    where jsonb_typeof(e) <> 'object'
       or not (coalesce(e->>'url', '') ~ ('^https://[^/]+/storage/v1/object/public/listing-media/' || lid::text || '/[^/]+$')
            or coalesce(e->>'url', '') ~ '^https://cdn\.shopify\.com/s/files/1/0635/7716/1771/[^ ]+$')
       or length(coalesce(e->>'caption', '')) > 200)
$$;
