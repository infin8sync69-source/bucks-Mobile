# Bucks 1.0 on Google Play: social-first release plan

> **Superseded on 9 November 2026:** the owner decided to ship the full super-app in 1.0 (rides, driver mode, shops, services, jobs and social). The `SOCIAL_ONLY` flag no longer exists. The current form answers and launch steps are in `store/PLAY_CONSOLE.md` and `docs/GO_LIVE_CHECKLIST.md`.

Decided with the product owner on 8 November 2026:

- **Scope:** social only. Feed, Moments, chat and groups, Sync (connections), profiles, notifications, search for people.
  Rides, deliveries, shops and orders, jobs and business listings stay in the code behind feature flags and are switched off in
  the Play build. They come back one at a time, after their licences and Play declarations are ready.
- **Audience:** everyone, from children to adults. The app adapts to the person's age band and to their network (who they have
  synced with). See "Age-adaptive safety" below.
- **Foundation over features:** no new complex features in 1.0. Make the existing social logic solid, safe, accessible and
  pleasant, then ship.

## Release phases

| Phase | What | Who | Done when |
|---|---|---|---|
| 0. Foundation | Feature flags; Play build drops ride/commerce permissions; version 1.0.0; Crashlytics; App Check (Play Integrity) | Code | Release bundle builds in CI with the flags off |
| 1. Safety and compliance | Report posts, comments, Moments, messages and people; staff review queue; age gate and age bands; parental consent for under-18s; Help, grievance officer, privacy policy and terms links; account deletion web page | Code + owner | Every UGC surface has Report; sign-up asks for date of birth |
| 2. UI and UX | New navigation and user flows (below); design tokens; accessibility pass | Code | Screenshots reviewed by the owner |
| 3. Store and testing | Upload key, Play listing, Data safety, content rating, target audience, closed test | Owner + code | 12+ testers for 14 days on the closed track (required for new personal developer accounts) |
| 4. Launch | Production with staged rollout 10% → 50% → 100%, watching Crashlytics and reports | Owner + code | Crash-free users ≥ 99.5% and no open P0 reports |

## Information architecture

One app shell, the super-app layout (`ui/BucksAppUi.kt`); the social-only shell (Home · Discover · Create · Chats · Profile) was retired.

| Tab | Content |
|---|---|
| **Home** | The map with search ("Where to, or what do you need?"), rides and an open trip or order. |
| **Feed** | Moments row and the feed (Synced and Nearby posts); create a post or Moment from here. |
| **Services** | The service tiles: book a ride, shops, local services, jobs; locked tiles invite people to list. |
| **For you** | Recommended near you, ranked by recommendations. |
| **Profile** | Your profile, posts, media, files and recommendations; Activity and Settings tabs. |

The **menu** (top left) holds Bucks Pro: your pages and vehicles, invites, orders, jobs, Recommend a local, Find people, Settings,
Help and Logout. Messages and the cart are in the top bar. The onboarding gate (date of birth, guardian consent), reporting, person
profiles, notifications, the safety centre, help and the feedback board come from the social screens in `ui/social/`.

## Key user flows

1. **First run:** Welcome → phone or email → OTP → date of birth → (under 18: parent's phone and consent) → name, username and
   photo → interests → find friends (contacts, with a prominent disclosure, or suggestions) → notification permission → Home.
2. **Connect:** Discover → profile → Sync → request appears at the top of their Chats → accept → both feeds update.
3. **Share:** Create → Post (text, photos, video, audience: Synced / Nearby / Public) or Moment (24 h, audience: Synced / Close
   friends) → it shows in Home straight away.
4. **Talk:** profile or Chats → message → photos and files → group with several syncs.
5. **Stay safe:** long-press or ⋯ on any post, comment, Moment, message or profile → Report / Block / Mute. Settings → Privacy
   and Safety holds every control in one place.

## Age-adaptive safety

The person's band is worked out from the date of birth they give at sign-up and is stored on the server, where the rules are
enforced (the app only reflects them).

| | Kids (under 13) | Teens (13 to 17) | Adults (18+) |
|---|---|---|---|
| Account | Created and managed by a parent | Parent's consent (OTP to the parent's phone) | Self |
| Profile | Private, not discoverable | Private by default, discoverable only by syncs of syncs | Public by default |
| Sync requests | Parent approves each one | From anyone; teen accepts | From anyone |
| Messages | Only approved syncs | Only syncs | Setting (default: syncs) |
| Posts | Synced only | Synced or Nearby (no exact location) | Any audience |
| Location | None | Area name only | Area and distance |
| Discovery by adults | No | Adults can't find teens they have no mutual sync with | — |

**Launch staging:** the Play target audience for 1.0 is 13 and over. The kids band is built and tested in 1.0 but switched on in
1.1, together with the Families policy declarations (no precise location, Families-approved SDKs only, teacher/parent review).

## Accessibility and design rules

- Every touch target is at least 48 dp; every icon button has a content description; tab and button labels are words, not only icons.
- Text follows the system font scale up to 200% without clipping; contrast ≥ 4.5:1 for text in both themes.
- Reduced motion respected (already in place); dark mode is first-class.
- Copy is short, friendly and plain; no jargon ("Sync" is explained the first time it appears).

## Analytics, feedback and growth

- **Analytics:** Firebase Analytics with a fixed event list (`data/Analytics.kt`): sign_up, post_created, moment_created,
  comment_added, sync_requested, sync_accepted, message_sent, group_created, search, report_filed, feedback_posted, plus screen views
  by route name. Collection is **off** until the server confirms an adult, and adults can opt out (Settings → Appearance and data).
  Never for under-18s (DPDP Act §9). No advertising ID (`AD_ID` removed), no user ID, no content in events.
- **Crash reports:** Crashlytics for everyone, with no identifier; the R8 mapping file is uploaded with release builds.
- **Feedback board:** Settings → Feedback board (and Help). Ideas and bugs, upvotes, staff status and a public note
  (`supabase/migrations/feedback_board.sql`).
- **Email sequence:** `docs/marketing/EMAIL_SEQUENCE_CLOSED_TEST.md` takes testers from opt-in through the 14-day closed test to
  launch. It goes to adults only, from a sign-up form outside the app.

## Data safety form (answers that match the code)

| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Phone number | Yes | No | Account management | No |
| Name, user IDs (Bucks ID) | Yes | No | App functionality | No |
| Date of birth (age) | Yes | No | App functionality, safety | No |
| Approximate location | Yes | No | App functionality (Nearby) | Yes |
| Photos, videos | Yes | No | App functionality | Yes |
| Messages (in-app) | Yes | No | App functionality | Yes |
| Other user-generated content (posts, comments, feedback) | Yes | No | App functionality | Yes |
| Contacts | **No** (read on device, never uploaded) | No | — | — |
| App interactions (analytics) | Yes, adults only | No | Analytics | Yes (opt-out) |
| Crash logs, diagnostics | Yes | No | App functionality | No |
| Device ID (push token) | Yes | No | App functionality | No |

Data is encrypted in transit (HTTPS); people can request deletion (in app, and on the web page `legal/delete-account`).

## Owner checklist (things only you can do)

1. Google Play Console: finish the developer account and identity verification; create the app `com.bucks.app`.
2. Run `scripts/setup-upload-signing.sh` to create the upload key and add the CI secrets; turn on Play App Signing.
3. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as GitHub repository secrets (the release build needs them).
4. Legal pages: drafts are in `docs/legal/` (privacy, terms, community guidelines, child safety, account deletion, grievance). Fill
   every `[bracketed]` item, have a lawyer review them, and publish them: either turn on GitHub Pages for this repo (main branch,
   `/docs` folder; the app's default `LEGAL_BASE_URL` points there) or host them on your own domain and set `LEGAL_BASE_URL`.
   Name a grievance officer and a child-safety contact.
4a. Add repository secrets `SUPPORT_EMAIL` and `GRIEVANCE_OFFICER` (shown in Help) next to `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
4b. Firebase console: Analytics is already part of the project; turn on Crashlytics, and set Analytics data retention.
5. Apply the new database migrations to the live Supabase project (`supabase/apply_all.sh`) and run `supabase/launch_checklist.sql`.
6. Play listing forms: Data safety, content rating (IARC questionnaire), target audience 13+, ads (none), news app (no), and the
   child safety standards declaration (required for social apps).
7. Recruit at least 12 closed testers for 14 days before applying for production.
