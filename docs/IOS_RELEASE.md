# Releasing the iOS app

The iOS app is built with Xcode; the project is generated from `ios/project.yml` (XcodeGen) and is not committed.

## One-time setup
1. Apple Developer account, App ID `com.bucks.app` with Push Notifications, Background Modes (location, remote notifications) and
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
1. Pick the build number: the same counter as the Android build (`BUILD_NUMBER` from `android-build.yml`, i.e. the number in the release tag
   `build-<n>`). Set it with `xcodebuild ... CURRENT_PROJECT_VERSION=<n>` (or edit `ios/project.yml`); `MARKETING_VERSION` follows `0.2.<n>`'s
   major.minor, so both apps show the same version.
2. Product > Archive in Xcode (or `xcodebuild archive`), then Distribute App > App Store Connect > Upload.
3. In App Store Connect add testers to the internal group; external testers need a short beta review.
4. Tag the commit `ios-build-<n>` so Android's `build-<n>` and iOS's `ios-build-<n>` point at the same code.

## Releasing from CI (no Mac needed)
`.github/workflows/ios-release.yml` archives the app and uploads it to App Store Connect. Signing is cloud-managed: Xcode creates the
distribution certificate and profile through the API key, so nothing is exported from a keychain.

One-time setup:
1. **Apple Developer Program** membership (paid, yearly). Note the 10-character Team ID (developer.apple.com > Membership).
2. **App ID** `com.bucks.app` (Certificates, Identifiers & Profiles > Identifiers) with Push Notifications and Time Sensitive Notifications.
3. **App record** in App Store Connect (My Apps > +) with bundle id `com.bucks.app`.
4. **App Store Connect API key** (Users and Access > Integrations > App Store Connect API), role App Manager. Download the `.p8` once;
   note the Key ID and the Issuer ID.
5. **Firebase**: add the iOS app with bundle id `com.bucks.app`, download `GoogleService-Info.plist`, and upload an APNs authentication
   key (Project settings > Cloud Messaging). Phone sign-in and push both need it.
6. **Repository secrets** (run these yourself, from a terminal on your own machine; nothing is printed):
   ```bash
   gh secret set APPLE_TEAM_ID --body "<team id>"
   gh secret set APPSTORE_API_KEY_ID --body "<key id>"
   gh secret set APPSTORE_API_ISSUER_ID --body "<issuer id>"
   base64 -w0 AuthKey_<key id>.p8 | gh secret set APPSTORE_API_KEY_P8_B64
   base64 -w0 GoogleService-Info.plist | gh secret set GOOGLE_SERVICE_INFO_PLIST_B64
   ```
   (`base64 -w0` on Linux; `base64 -i <file>` on a Mac.) `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `MAPBOX_TOKEN` are already set.

Then: Actions > **iOS release (App Store)** > Run workflow, with the version (for example `1.0.0`). The build shows under TestFlight after
Apple finishes processing. Submitting it for review (screenshots, description, privacy answers, the review demo account) is done in
App Store Connect.

## Before submitting for review
- **Demo account.** App Review cannot receive an SMS. Add one Firebase *test* phone number and code (Authentication > Sign-in method >
  Phone > Phone numbers for testing) and give both in App Review Information, with a note that it is a test number.
- **Report and block.** The Report sheet is on posts, moments, pages, chats and people; Block is in the same menus (guideline 1.2).
- **Account deletion** is under Account > Settings (guideline 5.1.1(v)).
- **Background location** is used only while a driver is online; say so in the review notes.

## Server side for push
The `notify` edge function sends iPhones an alert through APNs (`apnsFor` in `supabase/functions/notify/index.ts`). It takes effect once
the function is redeployed (`supabase functions deploy notify --no-verify-jwt`) and the APNs key is in Firebase (step 5).
`ios/server/push_ios.sql` is an optional constraint on the platform column and is not applied.
