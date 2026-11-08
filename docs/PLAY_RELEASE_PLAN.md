# Bucks 1.0 on Google Play: social-first release plan

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

Five tabs, the pattern young people already know:

| Tab | Content |
|---|---|
| **Home** | Moments row, then the feed with two lenses: *Synced* (people you synced with) and *Nearby* (local and public posts). Hidden for under-13s: *Nearby*. |
| **Discover** | Search people by name or Bucks ID, suggestions, people you may know from contacts, trending local posts. |
| **Create** (centre) | One sheet: Post or Moment. |
| **Chats** | Direct and group conversations, sync requests at the top. |
| **Profile** | Your profile, posts, Moments archive, Bucks ID card, settings. |

Notifications live behind the bell on Home. The drawer is removed from the social build, and everything in it moves to Profile
or Settings.

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

## Owner checklist (things only you can do)

1. Google Play Console: finish the developer account and identity verification; create the app `com.bucks.app`.
2. Run `scripts/setup-upload-signing.sh` to create the upload key and add the CI secrets; turn on Play App Signing.
3. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as GitHub repository secrets (the release build needs them).
4. Host the privacy policy, terms of use, child safety standards and account-deletion pages on a website you control, and name a
   grievance officer (IT Rules 2021). Drafts are in `docs/legal/`; have a lawyer review them.
5. Apply the new database migrations to the live Supabase project (`supabase/apply_all.sh`) and run `supabase/launch_checklist.sql`.
6. Play listing forms: Data safety, content rating (IARC questionnaire), target audience 13+, ads (none), news app (no), and the
   child safety standards declaration (required for social apps).
7. Recruit at least 12 closed testers for 14 days before applying for production.
