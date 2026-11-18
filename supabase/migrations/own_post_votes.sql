-- People may recommend (or not) their own posts. can_vote_post (trust_phase0.sql) refused a vote by the post's author; it now only
-- requires that the voter can see the post. Post arrows rank and notify, they don't feed anyone's trust (listings.trust_*,
-- profiles.trust_*), so a self-vote moves only that post's own count. note_vote already sends no notification for it.
-- Safe to run more than once. Apply after trust_phase0.sql and pilot_grants.sql (supabase/apply_all.sh does).
create or replace function public.can_vote_post(p_post uuid) returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from posts p where p.id = p_post and can_see_post(p))
$$;
revoke execute on function public.can_vote_post(uuid) from public, anon;
grant execute on function public.can_vote_post(uuid) to authenticated;
