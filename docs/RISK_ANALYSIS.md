# Bucks: real-world risk analysis

Reviewed 2026-11-13 on `feat/play-social-v1`, against the live Supabase project `bucks-app` (read-only queries), the four Edge Functions, the Android manifest and build, and the iOS sources. Nothing was changed in production during the review.

**Scale today:** 28 active profiles (18 of them demo seed accounts), 2 staff members, 0 open reports.

**Verdict:** the server is unusually well hardened for a pilot. Every table has row-level security, the 146 elevated functions check ownership, and guard triggers stop people editing their own trust scores, statuses, owners or counters. Fares, delivery fees and order totals are worked out on the server. The biggest risks are no longer code bugs. They are **pilot switches still on in production**, **Firebase console settings SQL can't see**, and **people and process** (one production database, two reviewers, UPI paid outside the app).

Severity: **Critical** = likely and serious harm (safety, money, legal) · **High** · **Medium** · **Low**.

---

## 1. Fixed in this change (`supabase/migrations/risk_hardening.sql`, applied to `bucks-app` on 2026-11-13)

| # | Scenario | Severity | Fix |
|---|---|---|---|
| R1 | **A 15-year-old posts a moment "Nearby".** Their settings default to *Synced*, but the API accepted `audience = LOCAL` on insert. Anyone within 5 km could see it, and so could anyone who sent a fake lat/lng to `moments_tray`, along with a location accurate to about 500 m. | Critical (child safety) | A new trigger `moment_minor_guard` forces SYNCED and drops the location on every moment by an under-18. Live data: 0 such moments right now. |
| R2 | **A driver uses a fake-GPS app to grab rides.** The speed cap (40 m/s) let unused allowance build up: a phone parked for a day banked about 3,400 km and could then jump next to any pickup. **Live:** one driver row has 4,652 km banked. | High | After each move the allowance is capped at `presence_slack_m` (300 m), in both `update_location` and `presence_clamp`. Existing banked allowance is cut back. |
| R3 | **A driver keeps messaging a rider after the trip.** `start_direct` allowed a new chat any time after a COMPLETED trip, ignoring the rider's "who can message me" setting. | High (harassment) | A chat can only be opened during the trip or within 24 hours of it ending (the same window as the phone number). Blocking still works at any time. |
| R4 | **Phone spoofing.** `ensure_profile` saved whatever phone number the app sent when the token had none. That would let a modified app show someone else's number to drivers and shops. | Medium | The number now comes only from the sign-in token. All 10 real accounts already have it from the token; the 18 without a phone are demo accounts. |
| R5 | **Pilot mode slips into launch.** `launch_checklist.sql` didn't check `pilot_skip_checks` or `vote_min_account_days`, both of which are still on pilot values. | High | Checks 17–19 added. The revert block in `pilot_test_settings.sql` now covers both settings. |

## 2. Needs your decision (production config, not code)

| # | Scenario | Severity | Action |
|---|---|---|---|
| C1 | **A fake pharmacy, clinic or taxi page goes live instantly.** `pilot_skip_checks = 1` makes `try_go_live` publish every new page with **0 recommendations and no licence documents**. `expire_documents` also never suspends pages with expired licences. | **Critical** before public launch | Set `pilot_skip_checks = 0`. Pending pages will then need recommendations and documents. |
| C2 | **Trust farming with throwaway SIMs.** `min_recommendations = 1`, `recommender_min_account_days = 0` and `vote_min_account_days = 0`. A single new account can take a page live and vote straight away. | High | Launch values are 7 / 14 / 3 (the revert block in `pilot_test_settings.sql`). All 15 services are also forced open (`service_rules.mode = 'ON'`), so a service is listed even with no checked providers. |
| C3 | **SMS pumping and bot sign-ups.** OTP rate limits, the SMS region lock, App Check enforcement and deleting test phone numbers are all in the Firebase console. | High (cost and abuse) | Work through the six hand checks at the top of `launch_checklist.sql`. |
| C4 | **The Firebase API key in `firebase/google-services.json`** is in a public repo. That's normal for Firebase, but only safe if the key is restricted. | Medium | Restrict it to `com.bucks.app` and its SHA-1 fingerprints, and to the Identity Toolkit, Installations and FCM APIs. |

## 3. Residual risks by real-world scenario (accepted or process-level)

### Safety and people
- **Grooming paths.** Adults can't find under-13s at all. Teens only show up to other teens or to people with mutual syncs, and their DMs default to *Synced*. Posts from teens can still be LOCAL/PUBLIC, with the location snapped to about 2 km. *Recommendation:* decide whether teen posts should also be limited to Synced.
- **The 18+ and guardian checks are self-declared.** The date of birth is set once and can't be changed afterwards, but nothing verifies it. This is a legal and Play Families exposure. *Mitigate:* DigiLocker age check later, plus a clear statement in the terms.
- **Rider's exact pickup and drop.** Every verified driver within 5 km sees these while a request is ringing. That's inherent to ride-hailing, but home addresses go to several strangers. *Mitigate:* show only the pickup to drivers until one accepts.
- **Moderation capacity.** Two staff accounts, and reports are never actioned automatically. That protects against mass-report takedowns, but harmful content stays up until a person looks. *Mitigate:* a response-time target (for example 24 h, and 1 h for CSAM or safety), plus an auto-hide after N reports from distinct, aged accounts.
- **Existing chats outlive trips.** R3 stops *new* trip chats after 24 h, but a chat that was opened during the trip stays open until one side blocks.

### Money and commerce
- **UPI and cash are settled outside the app (accepted by design, 2026-11-13).** Bucks never holds or moves money. "Mark as paid" is the rider's word against the driver's. *Keep it that way, and:* say plainly in the terms that payment disputes and refunds are between the buyer and the provider, and use reviews and reports as the remedy.
- **Fake orders.** Limited to 3 waiting and 10 per hour per buyer, and stock is returned when an order is cancelled or rejected. A ring of throwaway accounts could still tie up a small shop's stock for 5-minute windows. That's acceptable at pilot scale.
- **Ride spam.** Each request rings every nearby driver; the limit is 15 per hour per account and cancelling while searching is free. *Mitigate:* after 3 free cancels a day, make cancelling cost something (for example a cool-down).
- **Licence billing** trusts only HMAC-verified Razorpay webhooks, and replays are ignored. Good.

### Platform and operations
- **Production is the only database.** There's no staging project, and every migration lands on live users. *Mitigate:* a Supabase branch or second project for migrations; confirm point-in-time recovery (PITR) and daily backups are on.
- **Single points of failure.** FCM ringing depends on `pg_net` reaching the `notify` function, and all 5 cron jobs are present. If push fails, drivers miss rides without any warning. *Mitigate:* an alert on notify errors in the Edge Function logs.
- **Pilot self-update (debug builds only)** downloads APKs from GitHub Releases. Android only installs an update signed with the same key, so anyone attacking this would need both the GitHub account and the pilot keystore. Keep 2FA on and keep the keystore only in CI secrets.
- **Public avatars bucket.** Profile photos, including teens', can be fetched by URL without signing in. *Consider:* making minors' avatars private.

### Verified as fine (no action)
Signed-out users can't read or write anything. Phone numbers sit in a private table and are released only to the other side of an active trip or order. Driver positions on the map are blurred by 300 m and rotate hourly. The trip PIN locks after 5 wrong tries, and trips can't be completed too fast or far from the drop. Prices are worked out on the server. File types and sizes are limited per bucket, and private files are scoped by owner or conversation. `claim-role` accepts only Google-signed phone tokens. `notify` and `licence-notify` need a shared secret. Android: no backups, only the launcher activity is exported, push routes are allow-listed, there's no WebView, and no Gemini key in release builds. No service-role key or private key was found in git history.

---

## Applying

```bash
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 --single-transaction -f supabase/migrations/risk_hardening.sql
psql "$DATABASE_URL" -X -f supabase/launch_checklist.sql
```

Then, when you're ready to leave pilot mode, run the revert block in `supabase/pilot_test_settings.sql`.
