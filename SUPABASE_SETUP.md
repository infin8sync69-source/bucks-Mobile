# Supabase setup

Bucks keeps its data in Supabase (Postgres) and signs people in with Firebase phone OTP.
Supabase trusts the Firebase sign-in, so there is one login and no second password.

## 1. Project (done)
Project **bucks-app** exists in Mumbai (ap-south-1), ref `lboxctryrktwdsvywfqp`, URL `https://lboxctryrktwdsvywfqp.supabase.co`.
`supabase/schema.sql` on its own creates 32 tables, 56 functions, 76 policies (70 on the tables, 6 on `storage.objects`), 6 storage buckets, realtime on 8 tables and
2 pg_cron jobs (order time-outs, Moments clean-up). The migrations in `supabase/migrations/` then add tables and functions and replace parts of the base.

**Apply the database with `supabase/apply_all.sh`, never by pasting a file into the SQL Editor.** `schema.sql` is not safe to re-run: it drops every policy in `public`,
re-grants full table privileges (undoing the column protections on `profiles.home` and `tasks.pin`) and `execute` on every function (making internal ones such as
`push_note` callable), and re-creates older versions of functions that later migrations replaced. The script applies `schema.sql` and then every migration, in this order,
in one transaction:

```
DATABASE_URL='postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres' supabase/apply_all.sh     # direct or session-pooler connection, not port 6543
```

schema.sql, manage, owner_read, commerce, discover, jobs, dispatch, social-extras, contact_links, services, **studio (after services)**, push, notifications, interactions,
hardening_dispatch, hardening_platform. What each file does, how to run the tests locally and the known limits are in `supabase/README.md`. After applying, run
`supabase/tests/catalog_assertions.sql` (every line `ok`) and, before real users, `supabase/launch_checklist.sql` (every row `ok`).
`supabase/pilot_test_settings.sql` is for **test projects only**: it lowers the recommendation count, the account age and every service's `min_supply` so two phones can
exercise everything. Never run it on the production project.

The GitHub build already carries the project URL and the anon key, so no secrets are needed for the demo build.

## 2. Trust Firebase sign-ins
1. Supabase → Authentication → Sign In / Providers → **Third-party auth** → Add → **Firebase** → enter your Firebase project ID.
2. Supabase only accepts a Firebase token that carries `role: authenticated`. The deployed mechanism is the **`claim-role` Edge Function**
   (`supabase/functions/claim-role/index.ts`): right after sign-in, when its token has no role claim yet, the app calls it once and then refreshes the token.
   Deploy it and give it the Firebase service account:
   ```
   supabase functions deploy claim-role --no-verify-jwt     # it verifies the caller's Firebase ID token itself
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat <project>-firebase-adminsdk-xxxxx.json)"
   ```
   (Firebase console → Project settings → Service accounts → Generate new private key. The same secret sends push notifications, see `docs/PUSH_SETUP.md`;
   `FIREBASE_SERVICE_ACCOUNT` also works.) `firebase/functions` (`setSupabaseRole`, a Firebase Auth trigger) sets the same claim on the Blaze plan; the app accepts either
   but does not need it, and it is not what is deployed.

## 3. Scheduled jobs (pg_cron, created by the SQL files)
`expire_orders` every minute and `expire_moments` hourly (schema.sql); `expire_documents` daily and a 90-day notification clean-up daily (services.sql, notifications.sql);
`expire_tasks` every minute (hardening_dispatch.sql). They are skipped where pg_cron is not installed; `launch_checklist.sql` checks they exist.

## 4. Give the app its keys
Project Settings → API. Copy the **Project URL** and the **anon public** key into `local.properties`:
```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```
For GitHub builds, add the same two values as repository secrets with those names.
The anon key is meant to be in the app; security comes from the row-level rules in the SQL files.
**Never put the `service_role` key in the app or the repo.**

## 5. Rules that are enforced by the database (tested in `supabase/tests/`)
- New businesses, skill profiles, assets and drivers start **PENDING** and are invisible until they have `min_recommendations` (**7**) local recommendations, made by scanning the
  owner's QR in person, **and** (for services that need papers) every required document verified by Bucks staff. A recommender's saved home must be within
  `recommend_radius_m` (**3 km**) of the listing, they must stand within 3 km when they scan, and their account must be at least `recommender_min_account_days` (**14**) old.
  Home and position are reported by the app, so this stops casual gaming, not a modified client. Moving a LIVE listing or changing its category sends it back to PENDING.
- Only owners delete; admins run the listing; nobody can edit their own trust or status.
- Shop orders are priced by the database: item prices come from the `items` table and the delivery fee from `settings` (`delivery_base_fee` + `delivery_fee_per_km` x the
  server-measured distance), never from the app. Ride fares are computed by `request_ride` from the `fare_*` settings since `hardening_dispatch.sql` (it uses the app's
  distance only when it is plausible against the straight line); before that migration the app sent the fare itself.
- Cash on delivery only with the store's own riders, and only for shops that turned it on. Orders not accepted in 5 minutes are rejected.
- Bikes carry goods only. Deliveries ring online bikes within `delivery_radius_m` (3 km) of the shop; rides ring within `ride_radius_m` (5 km).
- Since `hardening_dispatch.sql`: a driver claims only from a fresh position near the pick-up with a verified vehicle, arrives within 800 m and completes within 2 km of the drop (or
  after `max(30 min, 6 min per km)`), a position that moves faster than 40 m/s (cumulatively, not only in one jump) is ignored, one driver claims at most 3 trips an hour (hand-backs count, including automatic ones),
  the requester's PIN allows 5 tries, and one rider has one open ride. The settings are listed in `supabase/README.md`; a device-test project may set the geometric ones to 0.
- A person chooses their own stored home, so `suggest_people` snaps both homes to a ~2 km grid before measuring: it shows which 2 km cell a person is in and nothing finer.
- Reviews only after a completed trip or delivered order, one per trip or order, never of your own listing.

Tunables (7 recommendations, 3 km, 14 days, 5 minutes, delivery ₹20 + ₹8/km) are rows in the `settings` table; the unlock numbers of each service are rows in `service_rules`
(see `docs/SERVICES_UNLOCK.md`).

## Run the tests locally
See `supabase/README.md`: a scratch database, `supabase/tests/local_auth_shim.sql`, `supabase/apply_all.sh`, then `supabase/tests/catalog_assertions.sql` and any `*_scenarios.sql`.
