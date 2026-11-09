# Bucks 1.0 (super-app) go-live checklist

Final audit, 9 November 2026, branch `feat/play-social-v1`. Scope: the full super-app (social, shops and orders, local services,
jobs, rides and driver mode) for Android on Google Play, India, ages 13+. Form answers are in `store/PLAY_CONSOLE.md`.

Legend: ✅ done · 🔧 fixed in this audit · ⬜ open. Owner: **You**, **Code** (Claude can do it), **Legal**.

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
| D3 | Set `search_path` on 4 functions (`cancel_reason_label`, `cancel_reason_ok`, `item_product_key`, `showcase_check_fields`) | Code |

**App (P1 from the audit)**

| # | Item | Owner |
|---|---|---|
| A1 | Report on business listings, reviews and recommendations, jobs and the feedback board (now only posts, comments, Moments, messages and profiles) | Code |
| A2 | Firebase App Check with Play Integrity (blocks SMS-pumping fraud and scripted sign-ups) | Code + You (console) |
| A3 | Server-side age enforcement: posting, messaging and booking refused until a date of birth is set | Code |
| A4 | Account deletion: re-authenticate first, so older sessions don't fail with "requires recent login" | Code |
| A5 | Check that teens can't go online as drivers or book rides alone | Code |
| A6 | The PROGRAM item type: make it in-person only, so online courses don't need Play Billing | Code |

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
