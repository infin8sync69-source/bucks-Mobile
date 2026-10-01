# Launch readiness: gaps before a public release

Audit of the monorepo (Android `app/`, iOS `ios/`, backend `supabase/`) as of the integration branch for PRs #2–#4, 1 October 2026.
The backend was checked by applying the whole stack to PostgreSQL 16 + PostGIS (with Supabase's default grants) and querying the
catalog. The apps were checked by reading the code and the build configuration. Nothing here was checked against the live Supabase,
Firebase, Play Console or App Store Connect projects; those are marked "check in the console".

Priority: **P0** blocks a public launch (store rejection, legal exposure or user harm). **P1** should be done before launch or in
its first days. **P2** is hardening for after launch.

## What is already in good shape

- **Row security everywhere.** All 46 tables have RLS. No policy grants anything to signed-out users. The four tables without
  policies (`staff`, `push_config`, `recommend_tokens`, `storage_cleanup`) are internal and deny by default.
- **Functions locked down.** None of the 120 SECURITY DEFINER functions can be called signed out, even with Supabase's default
  grants. All of them pin `search_path`, and every view is `security_invoker`.
- **Profiles protected.** Phone numbers live in `profile_private`, and `home` is not readable by others. Trust, status and ID
  columns are guarded by a trigger.
- **Storage.** Per-owner folders, private buckets for chat, posts, Moments and documents, and file-type and size limits on every
  bucket.
- **Edge Functions authenticate their callers.** `notify` checks a shared secret; `claim-role` verifies the Firebase ID token
  (signature, audience, issuer, expiry).
- **Account deletion** clears most personal data and posts. See P0-1 for the gap.
- **Safety and trust basics.** SOS (dials 112), share trip, block, and staff review of driver and shop documents.
- **Release hygiene.** The Android self-updater is debug-only (`SELF_UPDATE=false` in release) and `allowBackup` is false. The
  demo OTP "1234" only works in debug builds without Firebase.
- **Tests and checks.** CI covers Android, iOS and the database; there are 18 database scenario suites, about 170 iOS unit tests,
  and a launch checklist (`supabase/launch_checklist.sql`) for the live settings.

## P0: must fix before a public launch

| # | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|
| 1 | **"Delete my account" leaves saved delivery addresses** (name, mobile, house address, pincode) and product ratings/comments. | `delete_my_account()` (`migrations/hardening_platform.sql`) anonymises the profile instead of deleting it, so `on delete cascade` on `addresses` / `product_ratings` never fires. Reproduced locally: the address row survives with all fields. | Delete `addresses` and `product_ratings` for the person in `delete_my_account`, and add a scenario test. | Code |
| 2 | **No way to report content or people**, and no moderation queue. | No report feature on posts, Moments, comments, chats, profiles or listings in either app or the backend (only block). | `reports` table and RPC, a "Report" action wherever content or a profile appears, a staff review screen, and a takedown flow. Apple guideline 1.2, Google Play's UGC policy and India's IT Rules 2021 (grievance officer, time-bound action) expect this. | Code + you |
| 3 | **No privacy policy or terms of use.** | None in the apps, docs or store folder. | Host both on a website and link them from sign-up, Settings and the store listings. Include a DPDP Act 2023 notice and consent at sign-up, a grievance contact, and data retention. Fill in Play's Data safety form and Apple's App Privacy labels. | You (lawyer) + code for links |
| 4 | **No public Android release build.** | `android-build.yml` ships a **debug** APK signed with the pilot key. The `release` build type has no signing config and has never been built; R8/minify has never run on Ktor, Supabase or kotlinx.serialization (`proguard-rules.pro` covers osmdroid only). | Create a Play upload key and enable Play App Signing. Add a `bundleRelease` CI job, fix R8 rules until it builds, smoke-test the minified build on a phone, then upload to an internal test track. | Code + you |
| 5 | **iOS app has no privacy manifest.** | No `PrivacyInfo.xcprivacy`; the app uses UserDefaults and `ProcessInfo.systemUptime` (Apple "required reason" APIs). | Add `ios/App/PrivacyInfo.xcprivacy` declaring those APIs (reasons CA92.1 and 35F9.1) and the data the app collects. App Store Connect rejects uploads without it. | Code |
| 6 | **Live backend not on the reviewed code or launch settings.** | `hardening_dispatch.sql` / `hardening_platform.sql` are not applied to the live project (PR #3). `pilot_test_settings.sql` lowers recommendation counts and service thresholds. | Merge #2–#4, run `supabase/apply_all.sh` on live, revert the pilot settings, and run `supabase/launch_checklist.sql` until every row says ok. Then do its Firebase list: delete test phone numbers (keep one only for App Review), allow SMS to +91 only, restrict API keys, set budget alerts. | You |
| 7 | **Regulatory approvals for the services offered.** | Ride hailing, deliveries, marketplace selling, food. | Confirm with a lawyer before launch: an aggregator licence in each launch state under the Motor Vehicle Aggregator Guidelines (driver verification, insurance, SOS / control-room expectations); Consumer Protection (E-Commerce) Rules 2020 (seller details on listings, grievance officer, return / refund policy); FSSAI for food sellers; GST obligations. | You (lawyer) |

## P1: before launch or in the first days

| # | Gap | Evidence | Fix |
|---|---|---|---|
| 8 | **Firebase App Check is not in the apps**, so it can't be enforced. That leaves SMS-pumping fraud on phone sign-in. | No App Check / Play Integrity / App Attest code in either app. The launch checklist asks to *enforce* App Check, which would break sign-in without the SDK. | Add the App Check SDK (Play Integrity on Android, App Attest on iOS), ship it, watch the metrics, then enforce for Authentication. |
| 9 | **No crash reporting or analytics** on either app. | No Crashlytics, Sentry or analytics dependency. | Add Firebase Crashlytics to both apps (Firebase is already in use) and upload the R8 mapping file and dSYMs with each release. Add a few product events (sign-up, ride booked/completed, order placed). |
| 10 | **iPhones get pushes only while Bucks is open.** | `ios/server/notify_ios.proposal.ts` is not merged; there is no APNs key. | Merge the APNs block into `supabase/functions/notify`, upload an APNs key to Firebase, and test chats, orders and rides on an iPhone with the app closed. |
| 11 | **Free public map servers used in production paths.** | The street name under a pin (`label`) always calls `photon.komoot.io`, even with Mapbox. Without a Mapbox token or on errors, search and routes fall back to public Nominatim, OSRM and OSM tiles, whose usage policies forbid production app traffic. | Use Mapbox reverse geocoding when a token is set (both apps). Treat the public servers as an emergency fallback only, or run your own. Set Mapbox usage and billing alerts. |
| 12 | **The Gemini key would ship inside the app** if set. | `GEMINI_API_KEY` goes into `BuildConfig` (Android) and Info.plist (iOS) and is called from the phone. | Before turning on the AI assistant, move the call behind a Supabase Edge Function with per-user rate limits. |
| 13 | **Store policy declarations** that commonly trigger rejection. | Manifest: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE_LOCATION`, `READ_CONTACTS`. iOS: background location. | Play: the foreground-service declaration with a video, a battery-exemption justification (or drop it), Data safety, content rating and target audience. Apple: a background-location justification and a review demo account (one reserved test number). |
| 14 | **No in-app help or grievance contact.** | No support email, help screen or grievance officer in either app. | Help & Support in Settings (email or WhatsApp, FAQ, grievance officer name and contact), as the IT Rules and E-Commerce Rules expect. |
| 15 | **Capacity and backups.** | Dispatch polls every 5 s per active ride screen; realtime is one socket per app. Supabase plan unknown. | Supabase Pro or higher (no pausing, daily backups, point-in-time recovery). Load-test ride booking and the shop inbox with a few hundred simulated users. Set up uptime alerts and a status page. |

## P2: hardening after launch

| # | Gap | Fix |
|---|---|---|
| 16 | `guard_profile()` compares with `<>`, so changing a NULL `id_issued_at` slips through. | Use `is distinct from` for every guarded column. |
| 17 | Signed-out users hold SELECT grants on tables (they still see nothing because of RLS). | `revoke all on all tables in schema public from anon` as defence in depth, at the end of `apply_all.sh`. |
| 18 | Android has no unit tests (iOS has about 170), and neither app has UI / end-to-end tests. | Port the iOS rule tests (dispatch, cart, booking) to Android, and add a few Maestro or Espresso / XCUITest smoke flows. |
| 19 | Share trip sends text only; SOS only dials 112. | Live trip-tracking link; SOS that also alerts saved emergency contacts with the live location. |
| 20 | Versioning differs: Android `0.2.<run number>`, iOS `1.0 (1)`. | One product version for both apps, git tags per release, a changelog. |
| 21 | Store assets incomplete. | `store/` has only the icon and logo. Add the Play feature graphic, phone screenshots for both stores, descriptions, and a support URL. |
| 22 | Pincode lookup uses a free third-party API (`api.postalpincode.in`) with no SLA. | Fine as best effort (people can type the city); cache results or bundle the pincode list later. |

## Suggested order

1. Code fixes that need no decisions: 1, 5, 11, 16, 17, then 4 (release build in CI).
2. Product work: 2 (reporting and moderation), 14 (help and grievance), 9 (crash reporting), 8 (App Check), 10 (iPhone push).
3. Your side, in parallel: 3 and 7 (lawyer: policies, licences), 6 (live backend and Firebase console), 13 and 21 (store listings),
   15 (Supabase plan and load test).
4. Closed testing (Play internal / closed track, TestFlight) with real drivers, shops and riders in one area, then a staged public
   rollout.
