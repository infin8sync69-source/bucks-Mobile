-- Removes the closed-test demo world and puts the launch settings back. Safe to run more than once.
-- Run it before real users are invited (docs/DEMO_WORLD.md). It does NOT put the four sync requests that the seed accepted back to PENDING.
begin;
-- Demo shops (their products, jobs, reviews, recommendations, follows and members go with them) and demo gigs.
delete from public.listings where details->>'demo' = 'true';
-- Demo people (their posts, votes, comments, syncs and private rows go with them).
delete from public.profiles where auth_uid like 'demo:%';
-- The syncs the seed created between the real testers.
delete from public.syncs s using public.profiles a, public.profiles b
  where a.id = s.requester_id and b.id = s.addressee_id and s.created_at >= timestamptz '2026-11-12 06:43:52+00' and s.status = 'ACCEPTED';
-- Launch values (docs/SERVICES_UNLOCK.md).
update public.settings set value = '7'  where key = 'min_recommendations';
update public.settings set value = '14' where key = 'recommender_min_account_days';
update public.settings set value = '3'  where key = 'vote_min_account_days';
update public.service_rules set mode = 'AUTO', updated_at = now();
update public.service_rules set mode = 'OFF' where key = 'PARCEL';
-- The helper and its schedule, if they were ever installed.
drop function if exists public.demo_autosync();
drop schema if exists demo_seed cascade;
commit;
