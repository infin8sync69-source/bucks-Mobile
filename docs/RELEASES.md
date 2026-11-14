# Releases: Android and iOS

Both apps ship **one version number, built from one commit**. Android is `com.bucks.app` on Google Play; iOS is `com.bucksios.app` on
the App Store (Apple bundle ids are global and every `com.bucks.*` id was taken).

## How to release both

```bash
git tag release-v1.0.4 <commit> && git push origin release-v1.0.4
```

That one tag starts **Android release (Play)** (`android-release.yml`: signed `.aab` and `mapping.txt` as an artifact) and **iOS release
(App Store)** (`ios-release.yml`: uploads to TestFlight). Both use the version from the tag. Then:

1. Download the Android artifact and upload the `.aab` and `mapping.txt` to the same Play track the last build is on.
2. In App Store Connect, add the new build to the same TestFlight group, or to the App Store version under review.
3. Add a row to the log below.

`v<version>` (Android only) and `ios-v<version>` (iOS only) still work for a fix to one app. Still, give the other app the same version
from the same commit before the next store submission. A tag-triggered run uses the workflow file of the tagged commit, so
`release-v*` works only on commits that contain this change.

**Build numbers** are per store and only go up. Android: `(major × 10000 + minor × 100 + patch) × 100 + run number mod 100`, from the
Android release run. iOS: the iOS release run number. They don't need to match each other.

**Before tagging:** Android CI and iOS CI are green on that commit, and every migration the apps call is on live (see "Backend" below).

## Release log

| Version | Commit | Android (version code) | iOS (build) | Notes |
|---|---|---|---|---|
| 1.0.0 | `277f874`, `0468804` (Android); `f04d442` (iOS) | 1000001 (10 Nov), 1000003 and 1000004 (11 Nov, `feat/guardian-consent`) | 3 (13 Nov) | Built from different commits. iOS builds 1 and 2 failed in CI and were never uploaded |
| 1.0.1 | `7926f89` (Android); `b7f256f` (iOS) | 1000105 (12 Nov) | 4 (13 Nov) | Different commits: iOS has Revision 1, Android doesn't |
| 1.0.2 | `fe0248b` | — | 5 (13 Nov) | iOS only |
| **1.0.3** | **`db90e9f`** | 1000306 (14 Nov, tag `v1.0.3`, before the support email was set); **1000307** (14 Nov, same tag, Help shows the support email and grievance officer): upload 1000307 | **6** (13 Nov, tag `ios-v1.0.3`) | **First release where both apps are the same code** |
| **1.0.4** | **`6550bfe`** (tag `release-v1.0.4`) | **1000408** (14 Nov): go-online button always on Home for a driver with a checked vehicle | **7** (14 Nov): Help with the support email and grievance officer, Report on reviews and jobs, corrected contacts prompt and privacy manifest | **For the stores.** Both apps from one tag |

## Where things stand (14 November 2026)

| | Android | iOS |
|---|---|---|
| Public store page | None. play.google.com returns 404 for `com.bucks.app` | None. Apple's lookup finds no `com.bucksios.app` |
| Latest build | 1.0.4 (1000408), artifact `bucks-play-1.0.4-1000408` of Android release run 8. Upload it to Play | 1.0.4 (7) on TestFlight |
| Test track | Closed testing ran before Revision 1 (12 Nov). Check Play Console for the current track and tester count | TestFlight. Check App Store Connect for the testers and whether a version was submitted for review |

## Backend: what the apps need on live

The apps run against the live Supabase project (`bucks-app`). Checked and updated on 14 November 2026:

| Piece | In the repo | On live | Effect |
|---|---|---|---|
| `notify` Edge Function with the APNs block (iPhone push) | since 11 Nov (`85ff5d8`) | deployed 14 Nov (version 6, from `db90e9f`) | iPhones get alerts in the background once the APNs key is uploaded in Firebase; until then FCM refuses iPhone sends. Android is unchanged |
| `checkout_safety.sql` | since 11 Nov | applied 14 Nov | A retried checkout returns the first order instead of placing a second one |
| `anon` table grants | revoked at the end of `apply_all.sh` | revoked 14 Nov on the three trip-safety tables, which had been applied on their own | Signed-out users hold no table privileges |
| `billing.sql` | since 13 Nov | not applied | The licence card on Bucks ID and the page dashboards stays empty (both apps ignore the error). Apply it with `docs/BILLING_SETUP.md` when licences start |
| `trip_safety.sql`, `trip` function | uncommitted | applied 13 Nov, `bucks-ride-watch` runs every minute | No released app has the SOS or "Are you OK?" screens yet, and live `notify` doesn't push them |
