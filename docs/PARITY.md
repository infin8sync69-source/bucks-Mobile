# Android / iOS parity

The two apps are meant to be the same app: the same screens, copy, flows and rules, on the same backend. This page tracks where
they stand. Update it in the same pull request that changes a feature (see `CONTRIBUTING.md`).

Status: **=** same on both, **A** Android only so far, **i** iOS only so far, **n/a** intentional platform difference (below).

## Features

| Area | Android (`app/src/main/java/com/bucks/app/`) | iOS (`ios/Sources/`) | Status |
|---|---|---|---|
| Sign-in (Firebase phone OTP), create profile | `ui/screens/AuthScreens.kt`, `data/Cloud.kt` | `BucksUI/Screens/Auth/*`, `App/FirebasePhoneAuth.swift` | = |
| Shell: tabs, Bucks Pro side menu, trip bar, cart and Messages in the top bar | `ui/BucksAppUi.kt`, `ui/components/Components.kt` | `BucksUI/App/RootView.swift`, `Shell.swift`, `SideMenu.swift`, `Design/Components.swift` | = |
| Taxi booking: destination, choose ride, movable pick-up pin, searching, driver found, in ride, pay, rate | `ui/screens/RideScreens.kt`, `ui/Dispatch.kt` | `BucksUI/Screens/Ride/*`, `BucksCore/Dispatch.swift`, `Session.swift` | = |
| Driver: online sheet, ride-request ring (tune, loop), trip screen, payment QR, reachability prompts | `ui/screens/DriverScreens.kt`, `data/AppLife.kt`, `data/Push.kt` | `BucksUI/Screens/Driver/*`, `BucksUI/App/RideRing.swift`, `BucksCore/AppLife.swift` | = (battery exemption: n/a) |
| Maps: Mapbox tiles / search / directions with OpenStreetMap fallback, in-app turn-by-turn, location button | `ui/screens/MapsScreen.kt`, `data/MapServices.kt` | `BucksUI/Screens/Maps/*`, `BucksUI/Design/BucksMap.swift`, `BucksCore/MapServices.swift`, `Navigation.swift` | = |
| Feed, posts, Moments | `ui/screens/CloudSocialScreens.kt`, `PostDetailScreen.kt` | `BucksUI/Screens/Feed/*` | = |
| Services, search, For you | `ui/screens/discover/CloudSearchScreen.kt`, `HomeScreens.kt` | `BucksUI/Screens/Discover/ServicesScreen.swift`, `CloudSearchScreen.swift`, `RecommendedScreen.swift` | = |
| Listing profiles: business tabs (Feed, About, Products, Jobs, Reviews), recommend / not recommend on every profile, Reviews tab | `ui/screens/discover/ListingProfileScreen.kt` | `BucksUI/Screens/Discover/ListingProfileScreen.swift`, `ListingProfileTabs.swift` | = |
| Store catalogue: category rail, search, sort, filters, variants, product sheet, product feedback, skeletons | `ui/screens/discover/StoreCatalog.kt` | `BucksUI/Screens/Discover/StoreCatalog.swift`, `Design/Skeleton.swift` | = |
| Cart: one part per shop, one order per shop, per-shop delivery and payment | `ui/Commerce.kt`, `ui/screens/commerce/CloudCartScreen.kt` | `BucksCore/CommerceStore.swift`, `BucksUI/Screens/Commerce/CloudCartScreen.swift` | = |
| Shipping across India: address book, pincode lookup, Mark shipped / delivered, tracking | `ui/screens/commerce/AddressUi.kt`, `OrderShipUi.kt`, `data/Pincode.kt` | `BucksUI/Screens/Commerce/AddressUi.swift`, `OrderShipUi.swift`, `BucksCore/Pincode.swift` | = |
| Orders: my orders, order page, shop inbox (live), delivery tracking | `ui/screens/commerce/*`, `ui/screens/dispatch/DeliveryTrackScreen.kt` | `BucksUI/Screens/Commerce/*` | = |
| Studio: listings, listing edit (incl. shipping settings), items, documents, members, invites, recommendations, vehicles | `ui/screens/manage/*` | `BucksUI/Screens/Studio/*`, `Manage/*`, `Vehicles/*` | = |
| Jobs | `ui/screens/jobs/*` | `BucksUI/Screens/Jobs/*` | = |
| Messages, chat, groups, Sync, contacts | `ui/screens/SocialScreens.kt`, `CloudSocialScreens.kt`, `ContactsScreen.kt` | `BucksUI/Screens/Chat/*` | = |
| Bucks ID, settings (privacy, notifications, appearance, blocked, close friends) | `ui/screens/BucksIdScreen.kt`, `SettingsScreens.kt` | `BucksUI/Screens/Identity/*`, `Settings/*`, `Account/AppearanceScreen.swift` | = |
| Assistant (typed and voice) and the confirmation gate | `ai/*`, `ui/BucksViewModel.kt` | `BucksUI/Assistant/*` | = |
| Push: routes, kinds, quiet hours | `data/Push.kt`, `supabase/functions/notify` | `BucksCore/Push.swift`, `BucksUI/App/PushRouting.swift` | = (needs the APNs server change below) |

Every backend call (RPC and table) the Android app makes in live mode is also made by the iOS app; the RPC names and parameters are
the same. Android's `Backend.momentsOf` is unused (both apps open Moments with `open_moments`).

## Intentional differences

| Android | iOS | Why |
|---|---|---|
| Demo mode with an in-memory fake backend (`FakeBucksRepository`, demo screens such as `ProCreateScreen`, `EarningsScreen`) | not ported | the iOS app is live-only; the macOS preview harness (`ios/Sources/BucksMacPreview`) covers offline screen work |
| Notification channels (`bucks_ride_request`, `bucks_trips`, ...) | categories, threads and interruption levels (time-sensitive for rides) | iOS has no channels |
| Battery-optimisation exemption prompt when a driver goes online | not needed | iOS has no equivalent; background location keeps the driver online |
| Foreground service while a driver is online | Core Location background updates | platform model |
| In-app APK updater | TestFlight / App Store | platform distribution |
| Tablet navigation rail | iPhone layout only | iOS targets iPhone first |

## Open items

- **iPhone push in the background** needs `ios/server/notify_ios.proposal.ts` merged into `supabase/functions/notify` and an APNs key in
  Firebase. Until then iPhones get pushes only while Bucks is open.
- **On-device checks** (camera, speech, Face ID, background location, push) are manual: CI builds and unit-tests the iOS app but does not
  run it on a device.
