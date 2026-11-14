# Bucks: audit and critique, 10 November 2026

Branch `feat/play-social-v1` (Android `app/`, iOS `ios/`, backend `supabase/`), plus a read-only look at the live Supabase project `bucks-app`.

## How this was done, and what it does not cover

- **Read**: the server functions and access rules, the Android and iOS flow code, the build and CI configuration, the docs.
- **Queried live, read-only**: settings, access rules, function grants, triggers, storage buckets, Supabase's security and performance advisors. Nothing was written to the live project.
- **Executed evidence** comes from the latest CI runs on this branch, not from this machine:
  - Database: 29 suites, 937 scenario checks, 0 failures. These scripts act as riders, drivers, shops, buyers, applicants and staff against a throw-away database.
  - iOS: 169 unit tests pass.
  - Android: debug and minified release builds pass. There are **no Android tests**.
- **Not done**: neither app was run on a phone or emulator. This machine has no JDK, Android SDK tools, Swift, Postgres or Docker, and about 1 GB of free memory. The persona walk-throughs below are code traces, so anything about feel, layout or timing on a real screen is unverified.

## Verdict

The backend is the strongest part: fares, prices, stock, PINs and trust counts are all decided by the server, every table has row security, and I found no way for one signed-in user to read or change another's private data. The product is not ready for the public for four reasons that are not code polish:

1. **No money moves through Bucks.** Every payment is a person-to-person UPI transfer or cash that the app cannot check.
2. **The age and guardian rules are not enforced.** A client that skips the date-of-birth step is treated as an adult.
3. **The live project still has pilot settings and no staff account**, so nobody can approve documents or act on reports.
4. **iOS is a second-class app**: no report flow, no date of birth, English only, and no push while the app is closed.

## Scope and potential

Bucks is eight products in one app: ride hailing, bike delivery, local food and grocery ordering, courier e-commerce, a skilled-services directory, jobs, property listings and a social network with chat. The trust idea that ties them together is good and distinctive: a page goes live only after neighbours recommend it in person, and rankings are plain up/down counts the user can inspect.

The risk is breadth. Each vertical is a two-sided market that needs local density, and the server hides a service until enough supply exists nearby (Properties needs 10 live listers within 10 km). With two profiles and eleven listings live, most of the app will look empty to a new user.

**Recommendation:** launch one wedge in one neighbourhood. The code suggests the strongest candidate is local shops with their own riders (cash on delivery works there, and no Bucks payment is needed). Keep rides behind the service switch until the aggregator licence, driver verification and payments are in place.

## Findings

Severity: **High** blocks a public launch. **Medium** should be fixed before or just after. **Low** is hardening.

### Security and trust

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| S1 | High | An account with no date of birth is treated as an adult. The age gate lives only in the Android screens. | `age_band_of` returns `UNKNOWN` when no row exists; `is_minor` and `pro_allowed` treat that as adult. iOS never calls `set_birth_date`. | Make the server refuse posting, messaging, ordering and rides until a birth date is set. |
| S2 | High | Guardian consent is never asked for and never checked. | `GuardianScreen` and `AgeScreen` (`ui/social/Onboarding.kt`) are not referenced anywhere. No server function reads `guardian_consents`. The consent itself is a typed name and phone (`method = 'DECLARED'`). | Decide the rule. Either make Bucks 18+ for now, or add an OTP to the guardian's phone and have the server hold teen accounts until it arrives. India's DPDP Act expects verifiable consent. |
| S3 | High | Minors can book rides, place orders, open a shop, register a vehicle and apply for jobs. | `request_ride`, `place_order`, `check_application` and the listing and vehicle inserts never look at the age band. | Add the age check to those functions. |
| S4 | High | Live settings are pilot values and there is no staff. | Live `settings`: `min_recommendations = 1`, `recommender_min_account_days = 0`, `pilot_skip_checks = 1`. `staff` has 0 rows. | Run `launch_checklist.sql` to green and add at least one staff profile before inviting anyone. |
| S5 | Medium | `claim-role` gives database access to any Firebase user, not only phone sign-ins. | `supabase/functions/claim-role/index.ts` checks signature, audience, issuer and expiry but not `firebase.sign_in_provider`. | Require `sign_in_provider == "phone"`. Confirm anonymous and email sign-in are off in the Firebase console. |
| S6 | Medium | Deleting an account wipes a bad record. | `delete_my_account` frees the Firebase uid and deletes votes received; the same phone can sign up again with clean trust. | Keep a hashed-phone tombstone with a cooling-off period and the suspension history. |
| S7 | Medium | SMS-pumping exposure. | App Check is in the Android build; the earlier audit notes it is not enforced in the console. iOS has no App Check at all. | Add App Attest on iOS, enforce App Check for Authentication, restrict SMS to +91. |
| S8 | Medium | The iOS release build would ship the Gemini key. | `ios/project.yml` puts `GEMINI_API_KEY` into Info.plist for every configuration. Android blanks it in release. | Blank it for Release, or move the call behind an Edge Function. |
| S9 | Low | The repo is public and holds the Firebase API key and the Supabase anon key. | `firebase/google-services.json` is tracked; the anon key is a fallback in five workflows. Both are designed to be public. | Restrict the Firebase key to the app's package and signing certificate. Keep the service-role key out of CI. |
| S10 | Low | A driver can open a chat with a past rider with no time limit. | `start_direct` allows it while a task between them is `COMPLETED`, and an unpaid trip stays `COMPLETED`. | Limit to 24 hours after the trip, as `contact_for_task` already does. |
| S11 | Low | No screenshot protection on the trip PIN, payment QR and document viewers. No certificate pinning. | No `FLAG_SECURE` in the Android code. | Add `FLAG_SECURE` on those screens. |

What held up: all 70 tables have row security; signed-out users can call nothing sensitive; every elevated function pins its search path; guard triggers stop owners from changing status, trust, owner or conversation membership; storage is per-owner with private buckets for chat, posts and documents; Supabase's security advisor shows no errors.

### Product and money

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| P1 | High | Payments are on the honour system. | A rider taps "I paid" (`advance_task` to `PAID` is the requester's call; the app says "Bucks can't check it"). Orders have no paid state at all: the shop accepts and packs, then the buyer pays the shop's UPI QR. | Integrate a payment gateway with UPI intent and webhooks, and hold order money until delivery. Until then, limit launch to cash on delivery with the shop's own riders. |
| P2 | High | Refunds are a phone call. | Copy tells the shop "If they already paid you by UPI, refund them". | Follows from P1. |
| P3 | Medium | Deliveries complete with no proof at the door. | `advance_task` to `COMPLETED` needs the rider within 2 km of the drop, and nothing after 30 minutes. There is a pick-up PIN, no drop PIN. | Add a drop PIN shown to the buyer. Tighten `complete_radius_m` to about 200 m for deliveries. |
| P4 | Medium | No commission, platform fee or driver settlement exists. | Fares and delivery fees go straight to the driver or rider. | Fine for a pilot; decide the revenue model before the data model hardens. |
| P5 | Medium | Property listings are a shop with items. | The property form (BHK, area, deposit, availability) and filters are marked "Planned" in `docs/SERVICES_UNLOCK.md`. | Hide the Properties tile until the form exists. |
| P6 | Medium | Ride hailing, food and marketplace selling each need licences. | Already listed as P0-7 in `docs/LAUNCH_READINESS.md`. | Lawyer, before launch. |

### Bugs and fragile code

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| B1 | Medium | New users may hit "not signed in" on the name and birth-date screen. | `NameScreen` calls `set_birth_date`, which needs a profile row. That row is created by `social.signedIn`, which runs in the background after the OTP and retries for up to 6 seconds. Not reproduced; needs a test on a fresh number. | Await `ensure_profile` before showing the screen, or have `set_birth_date` create the profile. |
| B2 | Medium | A lost reply during checkout can place the order twice. | `place_order` has no request id. On a timeout the shop stays in the cart and "Retry" sends it again. | Add a client-generated idempotency key with a unique index. |
| B3 | Medium | The cart shows saved prices and stock. | `Commerce.kt` stores whole item rows on the phone; `CloudCartScreen` never re-reads them. The server charges today's price, so the total can differ from the button. | Re-read items when the cart opens and flag changed lines. |
| B4 | Medium | The app decides by matching English server sentences. | `Dispatch.kt:388` (`"too many wrong PIN"`), `OnboardingScreens.kt:238` (`"not eligible"`), `Jobs.kt:55`. | Return error codes (`raise ... using errcode`, or a JSON code) and map them in the app. |
| B5 | Medium | Server messages are English only, in an app shipping 20 languages. | The server functions raise plain English sentences, and `friendlyError` shows them as is. | Same fix as B4: codes on the server, text in the app. |
| B6 | Medium | Job applications send no notifications. | `applications` has only its check and guard triggers; nothing in `notifications.sql` or the `notify` function mentions it. | Notify the employer on apply and the applicant on shortlist, hire and reject. |
| B7 | Low | `NameScreen` has a hard-coded "Try again." and its own error parsing. | `OnboardingScreens.kt:238`. | Use `friendlyError` and a string resource. |
| B8 | Low | Auto and cab copy still promises deliveries; only bikes get them. | Noted in `Flow`; `claim_task` matches on vehicle kind. | Fix the copy. |

### Experience

| # | Sev | Finding | Fix |
|---|---|---|---|
| U1 | High | Translations are a quarter to three-quarters done, and Kannada is at 22% (957 of 4,250 strings). Because `generateLocaleConfig` is on, all 20 languages will be offered, giving mixed-language screens. Placeholders are consistent in what exists. | Ship only complete languages. Finish Kannada and Hindi first for Bengaluru. |
| U2 | High | Nothing can be browsed before sign-in. The server refuses every signed-out read. This costs conversions and risks Apple guideline 5.1.1(v). | Add a read-only guest mode for search, shop pages and jobs. |
| U3 | Medium | Too many places to do the same thing. Bottom bar (Home, Feed, Services, For you, Profile), a side menu for all provider work, and Home's search box all lead to overlapping lists. "Create" hides Business, Skill, Vehicle and Job behind the menu. | Make one "Work" or "Sell" entry visible on Profile; fold For you into Home. |
| U4 | Medium | Going live is hard to understand: documents, a UPI QR, and seven in-person QR scans from neighbours who themselves need a home pin, a 14-day-old account and no recent move. | Show one checklist with the reason for each step, and let a page take orders in a "new, unrated" state while it collects scans. |
| U5 | Medium | Mixed carts become several orders, each with its own rider, fee, payment and timer, and some can fail while others go through. The screen explains it well, but it is still a lot. | Keep it, but default to one shop per checkout and offer "also order from…" afterwards. |
| U6 | Medium | Accessibility: 208 icons have no description. Some are decorative; action icons need labels for TalkBack. | Audit the icon-only buttons. |
| U7 | Medium | Jobs are thin: pay is free text, the only filter is distance, and there is no saved search or alert. | Structured pay range, type and category filters; alerts. |
| U8 | Low | Three generations of onboarding and a demo mode still live in the Android build (`AuthScreens.kt`, `ui/social/Onboarding.kt`, `FakeBucksRepository`, `SeedData`, `ProCreateScreen`, `EarningsScreen`). | Delete them. |

### iOS against Android

`docs/PARITY.md` is accurate. What it means for a release:

- **No report or block-and-report flow**: App Store guideline 1.2 will reject a social app without it.
- **No date of birth** (see S1), no people search, no Pro profile, no feedback board.
- **No push while the app is closed.** The APNs change is still a proposal file (`ios/server/notify_ios.proposal.ts`), so an iPhone driver will miss ride requests.
- **English only**: there are no localised strings in `ios/Sources`.
- **No App Check, Crashlytics or analytics.**

## Persona walk-throughs (code traces)

| Persona | Path | Where it hurts |
|---|---|---|
| Asha, job seeker | Sign in → Services → Jobs → Jobs near me → Apply with skill pages and a note → wait | She must already own a Skill profile to attach one. She hears nothing back unless she opens "Jobs and applications" (B6). No filters (U7). |
| Ravi, hungry at the office | Search "biryani" → shop → add → cart → Bucks rider, UPI → place → shop has 5 minutes | He pays the shop from the order page after acceptance, and the rider separately at the door: two payments, neither checked (P1). Drop point is his GPS unless he has pinned an address. |
| Meera, groceries from two shops | Adds from both → cart shows 2 orders → places | Two riders, two fees, two timers. One may be rejected after the other is on its way (U5). A timeout can duplicate an order (B2). |
| Imran, buying a table from another city | Shop ships → checkout defaults to Ship → saved address → shop has 24 hours → tracking link | Works end to end on the server (37 checks). Trust depends wholly on the shop honouring a prepaid UPI transfer (P1, P2). |
| Divya, rider | Destination → Auto or Cab → pin → searching (3-minute ring) → PIN → trip → pay → rate | Server fare is fixed, with no waiting or night charge. She must tap "I paid" before she can review. The rider side polls every 5 seconds. |
| Suresh, auto driver | Create vehicle → upload RC, insurance, licence, permit → wait for review → go online | He waits forever today: there is no staff account (S4). On iPhone he misses rings in the background. |
| Lakshmi, renting out a flat | Create Business → category "Property owner" → add the flat as a product | No property fields, and the tile is hidden until 10 listers exist nearby (P5). |
| Arjun, 15 | Enters his real birth date → becomes TEEN with stricter social defaults → no guardian step | Can still book a cab or apply for a job (S2, S3). Enters nothing on iOS and is an adult (S1). |

## Architecture

### Today

```
Android (Compose)  ─┐                                   ┌─ Firebase Auth (phone OTP) + FCM
iOS (SwiftUI)      ─┼─ PostgREST + Realtime ── Supabase ─┤
                    │  (direct from the phone)  Postgres └─ Edge Functions: claim-role, notify
                    └─ Mapbox / public OSM servers        pg_cron: expire orders, tasks, moments
```

- **All business logic is PL/pgSQL**: 253 functions and 102 access policies, called straight from the phones.
- **Dispatch is polling**: a rider's phone reads its ride every 5 seconds, a driver's phone polls for requests every 5 seconds with pushes as a nudge, and the map refreshes every 15 seconds.
- **Schema changes are 43 hand-ordered SQL files** replayed in one transaction by `apply_all.sh`. `schema.sql` drops and re-creates every policy on each run. 62 functions are defined more than once (`search_listings` seven times, `place_order` five), so the real version is whichever file runs last.
- **Each feature is written twice**, in Kotlin and in Swift, each with its own state stores.

### What to change, in order

1. **Real migrations.** Squash today's result into one baseline, then use timestamped, forward-only Supabase migrations with a staging branch. This removes the "wrong file order re-opens a hole" risk the README warns about, and is the cheapest high-value change here.
2. **A payments service.** An Edge Function or small server that creates gateway orders, receives webhooks, and is the only writer of a `payments` ledger. Orders and rides gain a real paid state; refunds become an API call.
3. **Error and event contracts.** Stable error codes from every function (fixes B4 and B5) and a short written list of task and order states both apps share. The iOS test suite already encodes much of it.
4. **Dispatch off polling.** Keep Postgres as the source of truth, but push state through one Realtime channel per trip and per online driver, with polling only as a slow fallback. Move driver positions out of row updates on `driver_presence` and `tasks` (two writes every few seconds per driver) into Realtime broadcast, persisting a sample every 15 to 30 seconds. Row-change subscriptions that evaluate `can_claim` per subscriber will not scale past a few hundred online drivers.
5. **A thin server layer for anything with outside effects**: payments, push fan-out, the AI assistant (so no key ships in an app), document checks, pincode and map lookups. Keep simple reads and writes on PostgREST.
6. **A staff console on the web**, not inside the consumer app: document review, reports, suspensions, settings, with an audit log.
7. **Split the product by modules with one switch each.** `service_rules` already does this on the server; mirror it in both apps so a vertical that is not launched is not in the navigation at all.
8. **Share the rules across platforms.** Either Kotlin Multiplatform for the stores and models (the Android code is already plain Kotlin with little Android in it), or generate both clients' row types and RPC wrappers from the database schema.
9. **Observability.** Crashlytics on iOS, a handful of funnel events on both apps (sign-up, first search, order placed, ride matched, ride completed), and alerts on cron failures and Edge Function errors.
10. **Android tests.** Port the iOS dispatch, cart and booking rule tests, and add three Maestro smoke flows (order, ride, apply).

### Smaller code-shape notes

- Android has 1,647 lines over 200 characters (the longest is 2,440). They compile, but they cannot be reviewed in a diff.
- `runCatching` appears 296 times; many swallow failures silently. Log the non-transport ones to Crashlytics.
- Two sources of truth for the signed-in person (the local `User` in `BucksViewModel` and the cloud profile in `Social`) are behind B1.

## Suggested order of work

1. **This week, no decisions needed:** S4 (launch settings and a staff account), S5, S8, B1, B4 to B7, U1 (ship only finished languages).
2. **Decide:** 18+ only or verified guardian consent (S1 to S3); which single vertical launches first; payment gateway (P1).
3. **Before the App Store:** iOS report flow, date of birth, APNs, App Check, Crashlytics.
4. **Then:** migrations baseline, drop PIN, idempotent checkout, guest browsing, Android tests.
5. **A test on real phones** with two accounts on a staging branch of the database, covering every walk-through above. That is the part this audit could not do.
