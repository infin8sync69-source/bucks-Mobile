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

Automating this in CI needs the signing certificate and an App Store Connect API key as repository secrets; add `ios-release.yml` (macOS
runner, manual trigger) once those exist. Until then releases are cut from a Mac by the person holding the signing identity.

## Server side for push
iPhone push needs the changes proposed in `ios/server/` (an APNs block in the `notify` edge function). They are reviewed and applied by the
backend owner, never from an app pull request.
