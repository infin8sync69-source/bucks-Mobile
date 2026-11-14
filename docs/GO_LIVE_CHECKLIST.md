# Bucks 1.0 (super-app) go-live checklist

Final audit, 9 November 2026, branch `feat/play-social-v1`. Scope: the full super-app (social, shops and orders, local services,
jobs, rides and driver mode) for Android on Google Play, India, ages 13+. Form answers are in `store/PLAY_CONSOLE.md`.

Legend: ✅ done · 🔧 fixed in this audit · ⬜ open. Owner: **You**, **Code** (Claude can do it), **Legal**.

## 0. Status on 14 November 2026 (Android and iOS)

Neither app is public: Google Play has no page for `com.bucks.app` and the App Store has none for `com.bucksios.app`. Both are on
1.0.3 from commit `db90e9f` (versions and tracks: `docs/RELEASES.md`). Checked from the repository, GitHub, the live Supabase project
and the public store pages. Play Console, App Store Connect and Firebase need a sign-in, so items that depend on them say "check".

**Done since 9 November:** B1 (the token has the `workflow` scope), B2 (upload key; signed bundles build), B3 except the two contact
secrets, B4 (2 staff reviewers), D3, A1 and A3 (as `guardian_gate.sql`) on live. Live passes every launch check except the 6 pilot settings.

**Done on 14 November:** lawyer review of the legal pages; support email and grievance officer on the pages and in the `SUPPORT_EMAIL` and `GRIEVANCE_OFFICER` secrets (G2); `notify` redeployed with the iPhone alert (G10, server side); `checkout_safety.sql` applied (G14); the `anon` grants revoked (G15).

**Blocks public release on both stores**

| # | Item | Owner |
|---|---|---|
| G1 | The operator's real legal name and address on privacy, terms, grievance and the index page (they still show the placeholder "Bucks Technologies Private Limited, Indiranagar" with a "still being confirmed" note). The E-Commerce Rules need the legal name and address shown. Contacts and lawyer review: ✅ 14 Nov | You |
| G2 | ✅ 14 Nov. `SUPPORT_EMAIL` and `GRIEVANCE_OFFICER` are set; Android 1.0.3 was rebuilt so Help shows them | — |
| G3 | Licences for what 1.0 offers: Motor Vehicle Aggregator licence in each launch state (rides), E-Commerce Rules, FSSAI (food sellers), GST (L2, L3). Being open source doesn't exempt Bucks: its server matches riders with drivers and sets the fare, which is what Section 93 of the Motor Vehicles Act calls an aggregator, and the licence goes to whoever runs the service. Without a licence: launch with TAXI and AUTO set to `OFF` (their tiles show "Soon") and add a server check that refuses ride requests and going online while they are off | Legal + your call |
| G4 | On launch day, revert the pilot settings (D1). 6 live checks fail: `min_recommendations` 1 (7), `recommender_min_account_days` 0 (14), `vote_min_account_days` 0 (3), `pilot_skip_checks` 1 (0), 15 services forced ON (0; set them to AUTO, rides included), PARCEL ON (OFF). **What it does to today's data (14 Nov):** the next nightly `expire_documents` run suspends 46 of the 52 live pages, which went live in the pilot without their required documents (Owner ID; FSSAI for food, grocery, meat and vegetables; trade licence for meat). They come back by themselves once the documents are approved. New pages need 7 recommendations from accounts at least 14 days old, and 27 of the 29 accounts are under a week old, so no new page can go live for about two weeks after the switch | You, or Code with your OK |
| G5 | Firebase console (D2): delete the test numbers except the reviewers' one, SMS to +91 only, API key restrictions, budget alert. Check | You |
| G6 | Trip safety is live on the server (`trip_safety.sql`, the `trip` function, `bucks-ride-watch` every minute) but its app screens are uncommitted and in no build. Ship it in the next release of both apps with `notify` redeployed, or switch the checks off until then (`ride_*_minutes` and `ride_offroute_m` to 0) | Code + your OK |

**Google Play production**

| # | Item | Owner |
|---|---|---|
| G7 | Upload 1.0.3 (1000307, artifact `bucks-play-1.0.3-1000307`) to the closed track, so Android testers run the same code as iOS testers | You |
| G8 | 12+ testers opted in for 14 days in a row on closed testing, then Apply for production. Check the start date and tester count in Play Console | You |
| G9 | App content forms (Data safety, foreground service with the video, content rating, target audience, child safety) and the Play app-signing SHA-1 in Firebase (B5). Check | You |

**App Store review**

| # | Item | Owner |
|---|---|---|
| G10 | iPhone push in the background. ✅ `notify` version 6 (with the APNs block) deployed 14 Nov. Left: upload the APNs key (.p8) in Firebase (Project settings > Cloud Messaging); until then FCM refuses iPhone sends and drivers on iPhone aren't rung | You |
| G11 | Contact details inside the iOS app (guideline 1.2 asks for them in apps with user content): iOS has no Help screen, support email or grievance contact | Code |
| G12 | Report on reviews and jobs on iOS (Android has it), and the staff report queue on iOS | Code |
| G13 | App Store Connect: every field, the App Privacy answers and the review notes are in `store/APP_STORE_CONNECT.md`. Still yours: iPhone 6.9-inch screenshots and the reviewers' Firebase test number | You |

**Soon after (P1)**

| # | Item | Owner |
|---|---|---|
| G14 | ✅ 14 Nov. `checkout_safety.sql` applied: a retried checkout returns the first order | — |
| G15 | ✅ 14 Nov. Signed-out users hold no table privileges in `public` | — |
| G16 | iOS: Crashlytics and App Check (App Attest). App Check can't be enforced for sign-in until iOS has it | Code |
| G17 | iOS: the 20 languages Android has (iOS is English only), profile photos, Feedback board, Pro profile (`docs/PARITY.md`) | Code |
| G18 | Supabase plan with backups and point-in-time recovery, and a load test (LAUNCH_READINESS 15). Check the plan | You |

## 1. What the audit covered

| Area | How | Result |
|---|---|---|
| Play policy (app code) | Read-only review of permissions, Data safety, UGC, deletion, debug leftovers, R8, payments, minors | 4 P0 found, all fixed (section 2) |
| Live backend | Supabase security and performance advisors; `supabase/launch_checklist.sql` run against production; migration list compared with the repo | All migrations applied. 13 launch checks fail (section 3) |
| Release build | GitHub Android CI: `bundleRelease` with R8, unit tests | See the CI run for the commit with this file |
| Database logic | GitHub Database CI: scenario suites on PostgreSQL + PostGIS | See the same CI run |
| On-device | Not possible from the dev machine (no phone or emulator) | Manual test plan, section 5 |

## 2. Fixed in this audit 🔧

| # | Problem | Fix |
|---|---|---|
| 1 | Invites in Play builds linked to a GitHub APK and said "allow install unknown apps" (Device and Network Abuse policy) | `ui/Invite.kt`: Play builds link to the Play Store listing; only self-updating pilot builds use the APK link |
| 2 | Contact details linked to a Bucks person are saved on the server, but the app, privacy policy and Data safety all said contacts are never uploaded | In-app text, privacy policy and Data safety now declare it (optional, visible only to the owner) |
| 3 | Data safety and permission answers assumed the social-only build | Precise location, the driver foreground-service declaration (with video), and UPI payment info declared; IARC answer corrected |
| 4 | No terms acceptance at sign-in (UGC policy) | Sign-in screen: "By continuing you agree to the Terms and Community Guidelines…" with Terms, Guidelines and Privacy links |
| 5 | Release manifest stripped location, the driver service and the microphone, which rides and driver mode need | Restored. Only `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` stays out (restricted by Play); drivers get the battery settings list instead |
| 6 | Public map and pincode services weren't in the privacy policy | Added: OpenStreetMap services (Photon, Nominatim, OSRM) and api.postalpincode.in |
| 7 | A local release build could ship the Gemini key | Release builds always have an empty `GEMINI_API_KEY` |
| 8 | The age gate let people through if the safety check failed once | `ui/Safety.kt` retries (up to about 50 s) |
| 9 | Settings, Help, Log out and orders couldn't be reached from Profile | Profile has a Settings gear and a "Your account" section |
| 10 | Legal pages didn't exist online | Live at https://infin8sync69-source.github.io/bucks-Mobile/legal/ (placeholder details) |

## 3. Blockers before the first Play upload ⬜

| # | Item | Owner | How |
|---|---|---|---|
| B1 | Grant `workflow` scope so CI changes can be pushed | You | `gh auth refresh -h github.com -s workflow`, then Claude pushes the waiting commit |
| B2 | Create the Play upload key | You | `PATH=~/.local/toolchains/jdk17/bin:$PATH bash scripts/setup-upload-signing.sh`. Back up `~/bucks-upload-signing` somewhere safe and offline |
| B3 | GitHub secrets for the release build | You | `gh secret set` for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPPORT_EMAIL`, `GRIEVANCE_OFFICER` (commands in the chat) |
| B4 | **Add a staff reviewer.** Without one, no driver, vehicle or shop document can be approved | You | Supabase SQL editor: `insert into public.staff (profile_id) select id from public.profiles where short_code = '<your Bucks ID>';` |
| B5 | Firebase: add the upload key SHA-1, and after the first upload the Play app-signing SHA-1 | You | Firebase console → Project settings → Android app. Without them phone sign-in fails in Play builds |
| B6 | Firebase: a test phone number for Play reviewers | You | Authentication → Phone → numbers for testing (one only, for review). Put it in Play → App access |

## 4. Before production (after closed testing) ⬜

**Legal and business**

| # | Item | Owner |
|---|---|---|
| L1 | Replace every placeholder (company, address, emails, officer names: table at the end of `store/PLAY_CONSOLE.md`); have a lawyer review all six pages; remove the draft banners | You + Legal |
| L2 | Rides: Motor Vehicle Aggregator Guidelines licence for each launch state (driver verification, insurance, SOS) | Legal |
| L3 | Shops: Consumer Protection (E-Commerce) Rules 2020 (seller details on listings, refunds, grievance officer); FSSAI for food sellers; GST | Legal |
| L4 | Real support and grievance mailboxes; `gh secret set SUPPORT_EMAIL` and `GRIEVANCE_OFFICER` with real values | You |

**Backend (production settings)**

| # | Item | Owner |
|---|---|---|
| D1 | Revert the pilot test settings: run the revert block in `supabase/pilot_test_settings.sql`. Fixes 12 of the 13 failing checks (min_recommendations 1→7, account age 0→14 days, min_supply per service). Then re-run `supabase/launch_checklist.sql` until every row says ok | You (or Code with your OK) |
| D2 | Firebase console items listed at the top of `supabase/launch_checklist.sql`: delete test numbers (keep the reviewer one until approval), SMS region India only, API key restrictions, budget alert | You |
| D3 | 🔧 `search_path` pinned on the 4 flagged functions (`supabase/migrations/search_path_fixes.sql`) | Code: apply to live after CI passes |

**App (P1 from the audit)**

| # | Item | Owner |
|---|---|---|
| A1 | 🔧 Report on business pages, recommendations and reviews, jobs and feedback posts; staff takedowns suspend the page, delete the review or feedback, or close the job (`report_more_kinds.sql`). Product ratings stay out (no row id) | Code: apply to live after CI passes |
| A2 | 🔧 App Check (Play Integrity) installed in Play builds. **You:** Firebase console → App Check → register `com.bucks.app` with Play Integrity (needs the Play app-signing SHA-256); watch the metrics in *monitor* mode, and **enforce only after the pilot APKs are retired** (they can't pass Play Integrity) | Code ✅ + You |
| A3 | 🔧 The database refuses posts, comments, Moments, messages, reviews, feedback, orders, bookings, pages, vehicles, jobs and applications until the date of birth (and, for under-18s, guardian consent) is set (`age_enforcement.sql`). Kill switch: `settings.enforce_age = 0` | Code: apply to live after CI passes |
| A4 | 🔧 Deletion checks the sign-in is recent first; if not, nothing is deleted and the person signs in again, so they're never half-deleted | Code ✅ |
| A5 | 🔧 Teens can't add vehicles, go online, book rides, create pages or post jobs (database triggers). They can order from shops and apply to jobs: **check both with a lawyer** (child labour rules for job applications) | Code ✅ + Legal |
| A6 | 🔧 Program form: only live classes (in person or online), "recorded courses, videos and downloads can't be sold on Bucks" | Code ✅ |

## 5. On-device test plan

Install the Play build from **Internal testing**, not the pilot APK: it is minified and signed differently, so it can fail where the
pilot doesn't. Use two phones (A and B), one of them Android 14 or newer. Tick each row.

**Account and safety**
- [ ] Fresh install → sign in with a real number → OTP arrives and auto-fills
- [ ] Sign-in screen shows Terms, Guidelines and Privacy, and each opens its page
- [ ] Date of birth: 25 years old → straight in; 15 → guardian step; 11 → refused
- [ ] Profile: Settings gear and "Your account" open Settings, Orders and activity, Bucks ID, Help
- [ ] Settings → Delete account on a throwaway account → can't sign back into the old profile

**Social**
- [ ] A posts with a photo → B (synced) sees it in Feed; B votes and comments
- [ ] Moment → visible to B → gone after 24 h
- [ ] Chat A↔B with a photo and a file; push notification arrives with the app closed
- [ ] Report a post, a comment and a profile → appears in the staff queue (needs B4)
- [ ] Block B → B's posts and messages disappear for A

**Shops and orders**
- [ ] Create a shop → add products → upload documents → staff approves (B4) → shop goes live (needs D1 values or enough recommendations)
- [ ] B orders → shop accepts → rider flow → delivered → B rates
- [ ] Cash on delivery and UPI paths; delivery fee shows in the total

**Rides and driver mode**
- [ ] A adds a vehicle with documents → staff approves → goes online → **persistent notification shows**
- [ ] "Stay reachable" → Fix now → opens battery settings (not a crash)
- [ ] B books an auto → A's phone rings with the app in the background → accept → PIN → trip → end → pay → rate
- [ ] A goes offline → notification disappears and location stops (screen-record this: it's the Play foreground-service video)

**Other**
- [ ] Invite a contact → the message links to the Play Store, with no "unknown apps" text
- [ ] Voice search: mic permission prompt → search runs
- [ ] Search "plumber", "biryani", a pincode; map place search; directions
- [ ] Dark mode, font size 200%, airplane mode on and off (no crash, sensible errors)
- [ ] Crashlytics shows the build (Firebase → Crashlytics) after a forced test crash or a day of use

## 6. Launch sequence

1. B1–B6 done → run **Android release (Play)** with version `1.0.0` → upload the `.aab` and `mapping.txt` to **Internal testing**.
2. Run section 5 on the internal build. Fix, rebuild with `1.0.1`, repeat.
3. **Closed testing**: 12+ testers for 14 days (personal developer account). Use `docs/marketing/EMAIL_SEQUENCE_CLOSED_TEST.md`. Meanwhile do section 4.
4. Apply for production → staged rollout **10% → 50% → 100%**, holding each step at least 2 days.
5. Rollback triggers: crash-free users below 99.5%, any CSAE or self-harm report not handled within 24 h, sign-in failures, or a payment or trip state bug. Halt the rollout in Play Console (Production → Manage release → Halt) and fix forward.
