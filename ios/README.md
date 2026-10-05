# Bucks for iOS (SwiftUI)

The iOS app, a port of the whole Android app in `app/` (cloud mode only: the demo/offline paths are not ported): same Supabase backend and Firebase phone sign-in, the same ride and driver state machine, and every screen the Android app has with the same copy, flow and navigation: taxi booking and driving, Home, Feed and Moments, Services, For you, search and listing profiles, cart and orders, Studio (listings, items, vehicles, documents, members, invites, recommendations), jobs, chat and Sync, Bucks ID, contacts, maps and directions, settings, the voice/typed assistant with its confirmation sheet, realtime and push. The owner's launch focus is the taxi flow. It targets iOS 17+.

## Layout

| Path | What it is | Android counterpart |
|---|---|---|
| `Sources/BucksCore` | Logic with no UI (Foundation + CoreLocation only): models, PostgREST/Storage client, ride and driver state machine, session | `data/*`, `ui/Dispatch.kt`, `ui/BucksViewModel.kt`, `ui/Social.kt` |
| `Sources/BucksUI` | SwiftUI screens, design system, navigation | `ui/screens/*`, `ui/components/*`, `ui/theme/*` |
| `App` | The iOS app target: `@main`, Firebase phone sign-in and Messaging, entitlements, assets (Info.plist is generated from `project.yml`) | `MainActivity`, `Cloud.kt`, `Push.kt`, manifest |
| `server` | Proposals for the Supabase side (never applied): iPhone push delivery | `supabase/functions/notify` |
| `Tests/BucksCoreTests` | Unit tests, including the dispatch engine against a scripted fake Supabase | |
| `project.yml` | XcodeGen spec that produces `Bucks.xcodeproj` | `app/build.gradle.kts` |

`BucksCore` and `BucksUI` also build on macOS, so the logic and screens can be compiled and tested without an iOS SDK:

```bash
cd ios
swift build --target BucksUI   # compiles every screen
swift test --no-parallel       # unit tests (Swift Testing; no Xcode needed). --no-parallel is required: the tests share one global fake server
```

### Trying the screens on a Mac (no Xcode, no Firebase, no server)

`BucksMacPreview` is a macOS-only harness: it runs the real `RootView` against `FakeSupabase.swift`, an in-process stand-in for the Supabase project, with a pretend position in Jayanagar and a simulated driver/customer. Phone sign-in accepts the code `123456`.

```bash
swift build
.build/debug/BucksMacPreview --signed-in                      # opens a 390×844 window on Home
.build/debug/BucksMacPreview                                  # starts at the splash/sign-in flow
.build/debug/BucksMacPreview --signed-in --scenario rider     # scripted booking → ride → pay → rate, screenshots in /private/tmp/claude-501/shots
.build/debug/BucksMacPreview --signed-in --scenario driver    # go online → ring → accept → PIN → payment → rate
.build/debug/BucksMacPreview --signed-in --scenario screens   # vehicles, stats, payment QR, account, edit profile
# more scenarios (shell, chat, feed, discover, studio, …) are registered in Sources/BucksMacPreview/Registry.swift
```

Add `--quit` to exit when a scenario finishes. Screenshots are taken of the harness's own window only.

### File map (Android → iOS)

| Android | iOS |
|---|---|
| `data/Backend.kt`, `BackendDispatch.kt`, `Models.kt`, `Errors.kt` | `BucksCore/Backend.swift`, `BackendRides.swift`, `Models.swift`, `Errors.swift` |
| `data/BackendManage.kt` (vehicles) | `BucksCore/BackendVehicles.swift` |
| `data/MapServices.kt`, `Geo.kt`, `Here.kt` | `MapServices.swift`, `Geo.swift`, `Location.swift` |
| `ui/Dispatch.kt` | `BucksCore/Dispatch.swift` |
| `ui/BucksViewModel.kt` + `ui/Social.kt` (taxi parts) | `BucksCore/Session.swift` |
| `data/AppLife.kt` (`RingAlert`) | `BucksCore/AppLife.swift` |
| `data/Cloud.kt` (Firebase phone auth) | `App/FirebasePhoneAuth.swift` |
| `ui/nav/Routes.kt`, `BucksAppUi.kt`, `BottomTab`/`BucksBottomBar` | `BucksUI/App/Navigation.swift`, `RootView.swift` (MainStack), `Shell.swift`, `SideMenu.swift` |
| `data/Push.kt`, `BackendPush.kt` | `BucksCore/Push.swift`, `BucksUI/App/PushRouting.swift`, `App/FirebasePush.swift` |
| `Backend.postgresChangeFlow` (supabase-kt Realtime) | `BucksCore/Realtime.swift` (`Backend.shared.changes`) |
| `ui/screens/*` (all areas), `ui/components/*`, `ui/theme/*` | `BucksUI/Screens/*`, `BucksUI/Design/*`, `BucksUI/Media/*`, `BucksUI/Assistant/*` |
| `data/Backend*.kt`, `ui/*Store`-style view-model parts | `BucksCore/Backend<Area>.swift`, `*Store.swift` on `AppSession` |

## Build and run

You need a Mac with **Xcode 16+** (the App Store app, not just the command-line tools) and an Apple Developer account for a real device.

1. **Firebase.** In the Firebase console (the same project Android uses) add an **iOS app** with bundle ID `com.bucks.app` and download `GoogleService-Info.plist` into `ios/App/` (it is gitignored). Phone sign-in on iOS needs one of: an **APNs authentication key** uploaded under Project settings > Cloud Messaging (silent-push verification and, later, the pushes themselves), or the reCAPTCHA fallback, which works once the URL scheme below is set. For development add test numbers under Authentication > Sign-in method > Phone, as on Android.
2. **Supabase values.** `./scripts/make_secrets.sh` writes `Config/Secrets.xcconfig` from the repo's `local.properties` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, optional `GEMINI_API_KEY` and `MAPBOX_TOKEN`) and, once the plist is in place, the `REVERSED_CLIENT_ID` that the reCAPTCHA fallback needs. Run it after step 1.
3. **Generate the project and open it.**
   ```bash
   brew install xcodegen
   cd ios && xcodegen generate && open Bucks.xcodeproj
   ```
   Xcode resolves the Firebase package on first open. Pick your team under Signing & Capabilities, choose a device, and run. Push does not work on the Simulator (no APNs token); use a device.
4. Capabilities for your team: **Push Notifications** and **Time Sensitive Notifications** (both in `App/Bucks.entitlements`; `aps-environment` is switched to production by the distribution profile) and **Background Modes** (location, remote notifications: already in the generated plist).

Without `GoogleService-Info.plist` or the Supabase values the app still launches and shows the sign-in screens, but sign-in and rides are unavailable, exactly like Android without `google-services.json`.

### Info.plist keys (generated from `project.yml`)

| Key | Why |
|---|---|
| `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription` | pick-up point, nearby lists; an online driver keeps sharing with the screen off (`UIBackgroundModes: location`) |
| `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` | photos/videos for posts, Moments and chat (`UIImagePickerController`), QR scan, voice commands |
| `NSSpeechRecognitionUsageDescription` | the assistant's push-to-talk (`SFSpeechRecognizer`) |
| `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` | picking documents/QR images; saving photos and videos from the viewer (`PHPhotoLibrary` add-only) |
| `NSContactsUsageDescription` | the phone-contacts screen (`CNContactStore`) |
| `NSFaceIDUsageDescription` | confirming larger orders and payments (`LAContext`) |
| `UIBackgroundModes: location, remote-notification` | driver on duty; silent push for phone-auth verification |
| `LSApplicationQueriesSchemes` | `upi`, `tez`, `phonepe`, `paytmmp`, `gpay`, `tel`, `sms` |
| `CFBundleURLTypes` (`REVERSED_CLIENT_ID`) | the reCAPTCHA fallback of phone sign-in |
| `SupabaseURL`, `SupabaseAnonKey`, `GeminiAPIKey`, `MapboxToken` | from `Config/Secrets.xcconfig` |

## How it matches Android

- **One engine.** `Dispatch.swift` is a function-by-function port of `Dispatch.kt`: the same 5-second server polling, claim/retry and lost-answer recovery, PIN attempts (5), the no-driver timer from the server's `ring_window_seconds`, the same toasts. `Session.swift` carries the booking rules (`fare = km x rate + 20`, trip 0.2-150 km, the fake-location check).
- **Server stays the truth.** Rides, vehicles and presence go through the same RPCs and views; vehicle activation is decided server-side.
- **Realtime.** `Realtime.swift` is a Phoenix-protocol (vsn 1.0.0) client for Supabase Realtime, one shared socket with a channel per consumer, answering the heartbeat, refreshing the token on open channels, reconnecting with backoff and rejoining. Like Android it is a nudge on top of the polling, which stays as the safety net; consumers cancel their task to leave the channel.
- **Push.** The server's FCM sender reaches iPhones through Firebase Messaging (APNs token -> FCM token, stored with `register_device_token(p_platform: 'ios')`). The route allow-list is identical to `Push.safeRoute`. A tapped notification is kept in `PushInbox` and opened once signed in. iOS has no channels: each kind becomes a category, thread and interruption level (rides and deliveries are time-sensitive; quiet hours are passive).
- **Shell.** Bottom bar, "Bucks Pro" side menu (also an edge swipe on tab roots), trip-in-progress bar, centred ring card, location disclosure and notification prompts after the intro, sign-out resets every store and the router.
- **Maps.** The same providers as Android: Mapbox tiles (Streets / Satellite), place search and Directions when `MAPBOX_TOKEN` is set, OpenStreetMap (tiles, Photon, Nominatim, OSRM) otherwise. `BucksMap` is an `MKMapView` drawing those tiles through `MKTileOverlay` with Android's muted colour filter, dot markers and route styling; in-app turn-by-turn uses the same step wording, voice points and re-route rule as `MapsScreen.kt`.
- **Driver on duty.** Android's foreground service becomes Core Location with background updates; the position goes to `update_location` at most every 5 seconds. A ringing request while the app is in the background posts a time-sensitive local notification.

## Server proposals (not applied)

`server/push_ios.sql` and `server/notify_ios.proposal.ts`: the `notify` function sends Android-style data-only messages, which iOS does not show in the background. The proposal adds an `apns` alert block for tokens with platform `ios` (category, thread, interruption level, expiration; `apns-collapse-id` only when the tag is 64 bytes or shorter, because APNs rejects longer ones) and an optional platform check on `device_tokens`. Until it is applied iPhones receive pushes only while Bucks is open.

## Remaining known gaps

- **CI builds, devices test.** `.github/workflows/ios-ci.yml` builds the package, runs the unit tests and builds the whole app (with Firebase) for the Simulator on every pull request. Signing, a real device and TestFlight are still manual.
- **Push on iPhone** needs the server proposal above and an APNs key in Firebase.
- **In-app updates.** Android's APK updater has no iOS counterpart (TestFlight).
- **Swipe-back** is off on screens that hide the system back button (booking and ride screens use their own back arrow, as Android does), and Android's tablet rail is not ported (iPhone only).
- **Realtime after the app was suspended** reconnects when the next heartbeat or read fails (up to about 50 s); the 5-second polls cover that time.
- The macOS preview harness fakes Supabase; real-device behaviour of camera, speech, Face ID, background location and push is untested here.
