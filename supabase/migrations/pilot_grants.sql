-- Grants for the functions and policies of the pilot files (trust_phase0.sql, page_types.sql), which were created without the usual revokes:
-- every function was executable by PUBLIC (so by signed-out callers), trigger bodies were callable from the API, and two policies applied to
-- every role. catalog_assertions.sql flagged all three. Safe to run more than once. Apply after the pilot files (supabase/apply_all.sh does).
set search_path = public, extensions;

-- What the app calls, and what a policy runs as the signed-in person (can_vote_post, in votes_self on post_votes): signed-in callers only.
-- The 5-argument review() is the older signature that earlier app builds still call.
revoke execute on function public.can_vote_post(uuid), public.my_order_review(uuid), public.rate_listing(uuid, integer, text, text),
  public.rate_product(uuid, text, integer, text), public.rate_rider(uuid, integer, text, text), public.review(uuid, uuid, uuid, integer, text),
  public.review(uuid, uuid, uuid, integer, text, text) from public, anon;
grant execute on function public.can_vote_post(uuid), public.my_order_review(uuid), public.rate_listing(uuid, integer, text, text),
  public.rate_product(uuid, text, integer, text), public.rate_rider(uuid, integer, text, text), public.review(uuid, uuid, uuid, integer, text),
  public.review(uuid, uuid, uuid, integer, text, text) to authenticated;

-- Trigger bodies, and vote_age_ok (only called from inside the security definer functions above): executable by nobody through the API.
revoke execute on function public.post_vote_rate(), public.recount_listing_trust(), public.recount_profile_trust(), public.vote_age_ok()
  from public, anon, authenticated;

-- Both policies were created without "to authenticated", so they applied to anon too (anon has no table grants since hardening_platform.sql,
-- but the policy should say what it means).
alter policy listing_types_read on public.listing_types to authenticated;
alter policy profile_votes_mine on public.profile_votes to authenticated;
