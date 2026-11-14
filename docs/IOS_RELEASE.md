# Releasing the iOS app

The iOS app is built with Xcode; the project is generated from `ios/project.yml` (XcodeGen) and is not committed.

## One-time setup
1. Apple Developer account, App ID `com.bucksios.app` with Push Notifications, Background Modes (location, remote notifications) and
   Time Sensitive Notifications enabled.
2. Firebase console: add the iOS app (same Firebase project as Android), download `GoogleService-Info.plist` into `ios/App/` (gitignored),
   upload an APNs authentication key (Project settings > Cloud Messaging) and add test phone numbers.
3. `ios/Config/Secrets.xcconfig` from `ios/scripts/make_secrets.sh` (reads `local.properties`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPBOX_TOKEN`, ...).

## Build and run
```bash
cd ios && ./scripts/make_secrets.sh && xcodegen generate && open Bucks.xcodeproj   # then Run
# or from the command line, for the simulator:
xcodebuild -project Bucks.xcodeproj -scheme Bucks -destination 'generic/platform=iOS Simulator' build
```
Simulator sign-in uses a Firebase *test* phone number (the debug build switches app verification off on the simulator only).

## TestFlight
Releases normally come from CI (next section): a `release-v<version>` tag builds iOS and Android from the same commit with the same
version (`docs/RELEASES.md`, which also keeps the log of every release). By hand from a Mac:
1. Use the version of the matching Android release and a build number higher than the last upload:
   `xcodebuild ... MARKETING_VERSION=<version> CURRENT_PROJECT_VERSION=<n>`.
2. Product > Archive in Xcode (or `xcodebuild archive`), then Distribute App > App Store Connect > Upload.
3. In App Store Connect add testers to the internal group; external testers need a short beta review.
4. Add a row to `docs/RELEASES.md` with the commit. Don't push an `ios-v` or `release-v` tag for a build uploaded by hand: either tag
   starts the CI release, which would upload the same version again.

## Releasing from CI (no Mac needed)
`.github/workflows/ios-release.yml` archives the app and uploads it to App Store Connect. Signing is cloud-managed: Xcode creates the
distribution certificate and profile through the API key, so nothing is exported from a keychain.

One-time setup:
1. **Apple Developer Program** membership (paid, yearly). Note the 10-character Team ID (developer.apple.com > Membership).
2. **App ID** `com.bucksios.app` (Apple bundle ids are global and every `com.bucks.*` id is taken, so iOS differs from Android's `com.bucks.app`; it is registered, team `Z8SQVR6GUD`) (Certificates, Identifiers & Profiles > Identifiers) with Push Notifications and Time Sensitive Notifications.
3. **App record** in App Store Connect (My Apps > +) with bundle id `com.bucksios.app`.
4. **App Store Connect API key** (Users and Access > Integrations > App Store Connect API), role **Admin** (cloud signing at upload refuses App Manager keys with "Cloud signing permission error"). Download the `.p8` once;
   note the Key ID and the Issuer ID.
5. **Firebase**: add the iOS app with bundle id `com.bucksios.app`, download `GoogleService-Info.plist`, and upload an APNs authentication
   key (Project settings > Cloud Messaging). Phone sign-in and push both need it.
6. **Repository secrets**: download both files to ~/Downloads and run `ios/scripts/set_release_secrets.sh` (it finds them, reads the Key ID from the file name and asks only for the Issuer ID). Or by hand (run these yourself, from a terminal on your own machine; nothing is printed):
   ```bash
   gh secret set APPLE_TEAM_ID --body "<team id>"
   gh secret set APPSTORE_API_KEY_ID --body "<key id>"
   gh secret set APPSTORE_API_ISSUER_ID --body "<issuer id>"
   base64 -w0 AuthKey_<key id>.p8 | gh secret set APPSTORE_API_KEY_P8_B64
   base64 -w0 GoogleService-Info.plist | gh secret set GOOGLE_SERVICE_INFO_PLIST_B64
   ```
   (`base64 -w0` on Linux; `base64 -i <file>` on a Mac.) `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `MAPBOX_TOKEN` are already set.

Then: Actions > **iOS release (App Store)** > Run workflow, with the version (for example `1.0.0`), or push a tag from any branch:
`git tag ios-v1.0.0 && git push origin ios-v1.0.0` (the build number is the run number). The build shows under TestFlight after
Apple finishes processing. Submitting it for review (screenshots, description, privacy answers, the review demo account) is done in
App Store Connect.

## Before submitting for review
- **Demo account.** App Review cannot receive an SMS. Add one Firebase *test* phone number and code (Authentication > Sign-in method >
  Phone > Phone numbers for testing) and give both in App Review Information, with a note that it is a test number.
- **Report and block.** The Report sheet is on posts, comments, moments, messages, pages, chats and people; Block is in the same menus (guideline 1.2).
- **Account deletion** is under Account > Settings (guideline 5.1.1(v)).
- **Background location** is used only while a driver is online; say so in the review notes.

## Server side for push
The `notify` edge function sends iPhones an alert through APNs (`apnsFor` in `supabase/functions/notify/index.ts`). It takes effect once
the function is redeployed (`supabase functions deploy notify --no-verify-jwt`) and the APNs key is in Firebase (step 5).
`ios/server/push_ios.sql` is an optional constraint on the platform column and is not applied.
