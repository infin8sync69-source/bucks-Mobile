-- Launch checklist: a READ-ONLY query, one row per check, result "ok" or "FAIL". Run it in the Supabase SQL Editor (or psql) against the production
-- project before real users are invited, and again after every migration; every row must say ok. It changes nothing.
--
--   psql "$DATABASE_URL" -X -f supabase/launch_checklist.sql
--
-- What it looks for: the pilot's test-mode settings (supabase/pilot_test_settings.sql lowers the recommendation count to 1, the account age to 0 days
-- and every service's min_supply to 1 so two phones can exercise everything; a device-test project may also have set the dispatch checks arrive_radius_m,
-- complete_radius_m, min_trip_seconds and presence_max_speed_mps to 0 so mock locations can jump), accounts still on the published test phone numbers,
-- and whether the pieces production needs are in place (push secret, staff reviewer, cron jobs, the hardening migrations, data the new checks would refuse).
-- Launch values are the ones in docs/SERVICES_UNLOCK.md and the commented revert block of supabase/pilot_test_settings.sql.
--
-- WHAT SQL CANNOT SEE: the Firebase console. Check these by hand before launch (Firebase console > Authentication and Project settings):
--   1. Sign-in method > Phone > "Phone numbers for testing": delete every number. Test numbers skip SMS and use a fixed code, so anyone who knows one signs in as that person.
--   2. Authentication > Settings > SMS region policy: allow only India (+91) (or the countries you launch in), so SMS-pumping fraud cannot run up the bill.
--   3. App Check (Project settings > App Check): register the Android app with Play Integrity and enforce it for Authentication, then for Cloud Messaging as available.
--   4. API key restrictions (Google Cloud console > APIs and services > Credentials): the Android key restricted to package com.bucks.app and the pilot and Play
--      SHA-1 fingerprints, and to the Identity Toolkit, Firebase Installations and FCM APIs only; no unrestricted key anywhere.
--   5. Billing: the Blaze budget alert from FIREBASE_SETUP.md exists, and the FCM_SERVICE_ACCOUNT secret of the Edge Functions is the only copy of the service account key.
--   6. Supabase dashboard: Authentication > Third-party auth lists only your Firebase project; the service_role key is not in the app, the repository or CI logs.
with expected_min_supply(key, n) as (values
  ('TAXI', 3), ('AUTO', 3), ('PARCEL', 4), ('FOOD', 10), ('GROCERY', 5), ('VEGETABLES', 3), ('MEAT', 2), ('SHOPPING', 5), ('GIGS', 8), ('JOBS', 5), ('PROPERTIES', 10)),
checks(n, what, expected, actual) as (
  select 10, 'settings.min_recommendations', '7', coalesce((select value::text from public.settings where key = 'min_recommendations'), 'missing')
  union all
  select 11, 'settings.recommender_min_account_days', '14', coalesce((select value::text from public.settings where key = 'recommender_min_account_days'), 'missing')
  union all
  select 12, 'settings.recommend_radius_m', '3000', coalesce((select value::text from public.settings where key = 'recommend_radius_m'), 'missing')
  union all
  select 13, 'settings.arrive_radius_m (0 switches the arrival check off)', '800', coalesce((select value::text from public.settings where key = 'arrive_radius_m'), 'missing')
  union all
  select 14, 'settings.complete_radius_m (0 switches the drop check off)', '2000', coalesce((select value::text from public.settings where key = 'complete_radius_m'), 'missing')
  union all
  select 15, 'settings.min_trip_seconds (0 lets a trip complete and be reviewed at once)', '60', coalesce((select value::text from public.settings where key = 'min_trip_seconds'), 'missing')
  union all
  select 16, 'settings.presence_max_speed_mps (0 lets a driver''s position jump anywhere)', '40', coalesce((select value::text from public.settings where key = 'presence_max_speed_mps'), 'missing')
  union all
  select 20 + row_number() over (order by e.key), 'service_rules.min_supply ' || e.key, e.n::text, coalesce((select r.min_supply::text from public.service_rules r where r.key = e.key), 'missing')
  from expected_min_supply e
  union all
  select 40, 'service_rules: services forced open (mode ON is a pilot override)', '0', (select count(*)::text from public.service_rules where mode = 'ON')
  union all
  select 41, 'service_rules.mode PARCEL (its booking flow is not built)', 'OFF', coalesce((select mode from public.service_rules where key = 'PARCEL'), 'missing')
  union all
  select 50, 'accounts on the published test phone numbers (+91 99999 000xx)', '0',
         (select count(*)::text from public.profile_private where regexp_replace(coalesce(phone, ''), '\D', '', 'g') ~ '^(91)?99999000[0-9]{2}$')
  union all
  select 60, 'push_config.webhook_secret set (32+ characters)', 'true', coalesce((select (length(value) >= 32)::text from public.push_config where key = 'webhook_secret'), 'false')
  union all
  select 61, 'staff members who can review documents (at least 1)', 'true', (select (count(*) >= 1)::text from public.staff)
  union all
  select 62, 'pg_cron jobs: expire-orders, expire-moments, expire-documents, clean-notifications, expire-tasks (without the last, unanswered requests stay open and a silent driver keeps a trip)', '5',
         case when to_regclass('cron.job') is null then 'pg_cron not installed'
              else (xpath('/row/c/text()', query_to_xml($q$select count(*) as c from cron.job where jobname in ('bucks-expire-orders', 'bucks-expire-moments', 'bucks-expire-documents', 'bucks-clean-notifications', 'bucks-expire-tasks')$q$, false, true, '')))[1]::text end
  union all
  select 70, 'hardening_platform.sql applied (storage_cleanup exists)', 'true', (to_regclass('public.storage_cleanup') is not null)::text
  union all
  select 75, 'hardening_dispatch.sql applied (staff_close_task exists)', 'true', (to_regprocedure('public.staff_close_task(uuid, text)') is not null)::text
  union all
  select 71, 'chat bucket has a file type allow-list', 'true', case when to_regclass('storage.buckets') is null then 'no storage schema'
              else coalesce((select (allowed_mime_types is not null)::text from storage.buckets where id = 'chat'), 'no chat bucket') end
  union all
  select 72, 'existing messages with a malformed attachment (crash the chat screen)', '0',
         case when to_regprocedure('public.attachment_ok(jsonb)') is null then 'hardening_platform.sql not applied'
              else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.messages where not coalesce(public.attachment_ok(attachment), true)', false, true, '')))[1]::text end
  union all
  select 73, 'existing posts with malformed media (crash the feed)', '0',
         case when to_regprocedure('public.post_media_ok(jsonb)') is null then 'hardening_platform.sql not applied'
              else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.posts where not public.post_media_ok(media)', false, true, '')))[1]::text end
  union all
  select 74, 'existing rows longer than the new text limits (they block edits to those rows)', '0',
         (select count(*)::text from (
            select 1 from public.profiles where length(name) > 80 or length(bio) > 300 or length(area) > 80
            union all select 1 from public.listings where length(title) > 100 or length(description) > 2000
            union all select 1 from public.messages where length(body) > 4000
            union all select 1 from public.posts where length(body) > 5000
            union all select 1 from public.post_comments where length(body) > 1000
            union all select 1 from public.reviews where length(comment) > 1000
            union all select 1 from public.moments where length(caption) > 200
            union all select 1 from public.jobs where length(title) > 100 or length(description) > 2000
            union all select 1 from public.applications where length(note) > 1000) x)
)
select n, what as "check", expected, actual, case when actual = expected then 'ok' else 'FAIL' end as result
from checks
union all
select 999, 'SUMMARY: checks that are not ok', '0', count(*)::text, case when count(*) = 0 then 'ok' else 'FAIL' end
from checks where actual is distinct from expected
order by 1;
