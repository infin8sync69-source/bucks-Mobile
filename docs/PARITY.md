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
| Delivery riders: cart warns when no delivery agent (bike) is online near the shop, "Invite a delivery agent" share in the cart and after "No rider"; owners reminded to add store riders (listing form, dashboard card, Team invite) with what a rider needs to be rung | `ui/Commerce.kt` (`agentsOnlineNear`, `deliveryRadiusM`), `CloudCartScreen.kt`, `DeliveryTrackScreen.kt`, `manage/ListingEditScreen.kt`, `ListingDashboardScreen.kt`, `MembersScreens.kt` | `CommerceStore.swift`, `Invite.swift`, `CloudCartScreen.swift`, `DeliveryTrackScreen.swift`, `Studio/ListingEditScreen.swift`, `ListingDashboardScreen.swift`, `Manage/MembersScreen.swift` | = (iOS shows the dashboard card on every business page: it has no page types to tell shops from organisations) |
| Delivery time a shop promises: presets (10 min, 30 min, 1 hour, 2 hours, same day, 24 hours, 2 days) plus an optional preferred time, in details.delivery_time / delivery_slot; set in the listing form, shown on the profile and in the cart | `ui/DeliveryTimes.kt`, `manage/ListingEditScreen.kt`, `discover/ListingProfileScreen.kt`, `CloudCartScreen.kt` | `BucksCore/DeliveryTimes.swift`, `Studio/ListingEditScreen.swift`, `Discover/ListingProfileTabs.swift`, `CloudCartScreen.swift` | = |
| Terms acceptance: checkbox at sign-up (Android), terms screen after sign-in (iOS); asked again whenever settings.terms_version changes (`terms_status`) | `ui/onboarding/OnboardingScreens.kt`, `ui/BucksAppUi.kt` (dialog), `ui/Social.kt`, `data/BackendSafety.kt` | `Screens/Auth/TermsScreen.swift`, `BucksCore/Session.swift`, `BucksCore/BackendSafety.swift` | = (iOS asks after the code, Android before) |
| Trip safety: SOS sheet on every trip screen (riders and drivers), trusted contacts, live trip link, "Are you OK?" card, staff SOS list | `ui/safety/TripSafety.kt`, `screens/RideScreens.kt`, `screens/DriverScreens.kt`, `social/Settings.kt` | `Screens/Safety/TripSafetyViews.swift`, `Ride/InRideScreen.swift`, `Ride/DriverFoundScreen.swift`, `Driver/DriverTripScreen.swift`, `Account/AccountScreen.swift` | = (iOS shares the live link from a small sheet; staff SOS is in Review reports on Android, its own screen on iOS) |
| Studio: listings, listing edit (incl. shipping settings), items, documents, members, invites, recommendations, vehicles | `ui/screens/manage/*` | `BucksUI/Screens/Studio/*`, `Manage/*`, `Vehicles/*` | = |
| Jobs | `ui/screens/jobs/*` | `BucksUI/Screens/Jobs/*` | = |
| Messages, chat, groups, Sync, contacts | `ui/screens/SocialScreens.kt`, `CloudSocialScreens.kt`, `ContactsScreen.kt` | `BucksUI/Screens/Chat/*` | = |
| Bucks ID, settings (privacy, notifications, appearance, blocked, close friends) | `ui/screens/BucksIdScreen.kt`, `SettingsScreens.kt` | `BucksUI/Screens/Identity/*`, `Settings/*`, `Account/AppearanceScreen.swift` | = |
| Assistant (typed and voice) and the confirmation gate | `ai/*`, `ui/BucksViewModel.kt` | `BucksUI/Assistant/*` | = |
| Push: routes, kinds, quiet hours | `data/Push.kt`, `supabase/functions/notify` | `BucksCore/Push.swift`, `BucksUI/App/PushRouting.swift` | = (needs the APNs server change below) |
| Revision 1 (first closed test): notification bell and one red count badge, sync requests answered from Notifications, log out asks first, people cards in Home search, one-tap arrows with the inline comment box, Explore tab (search, pills, video / image / file pages, places and products my people recommend, viewer with previous and next) | `ui/BucksAppUi.kt`, `ui/components/Components.kt`, `ui/screens/HomeScreens.kt`, `ui/social/Discover.kt`, `ui/screens/ExploreScreen.kt`, `ui/MediaViewer.kt` | `Design/Components.swift` (`NotifAction`, `CountBadge`, `InlineCommentBox`), `Screens/Chat/MessagesScreen.swift`, `Screens/Discover/HomeSearch.swift`, `Screens/Chat/PersonScreen.swift`, `Screens/Discover/ExploreScreen.swift`, `BucksCore/BackendExplore.swift` | = except: iOS doesn't save a still frame (poster) with a new video yet, so Explore shows its videos on a plain dark card |
| "Did they help?": a day after calling, messaging, booking or getting directions to a page, Home asks for a ↑ or ↓ (DISCOVERY_ALGORITHMS §13.8) | `data/HelpAsk.kt`, `ui/screens/HomeScreens.kt` (`HelpAskCard`), `discover/ListingProfileScreen.kt` | not yet | A: Android only for now |
| About you onboarding step (photo, private gender, one line) | `ui/onboarding/OnboardingScreens.kt` (`AboutYouScreen`) | `Screens/Auth/CreateProfileScreen.swift` already asks gender and the line at sign-up; gender is saved to `profile_private` | A: profile pictures (upload, and showing them on avatars) aren't on iOS yet |

## Backend calls only Android makes

`scripts/hygiene.sh` (the Hygiene check on every pull request) compares the RPCs the two apps call and fails when Android calls one
that iOS doesn't and this table doesn't list. Port the feature, then delete its row. Audited 15 November 2026.

| Feature not on iOS yet | Android | RPCs iOS doesn't call | Size |
|---|---|---|---|
| Search measurement (DISCOVERY_ALGORITHMS Phase 0): the search, the first 10 results shown, opens and what is done next, for adults with usage statistics on; switching them off deletes what was kept. iOS first needs a usage-statistics switch, and the App Store privacy answers must declare search history | `data/DiscoveryLog.kt`, `ui/Discover.kt`, `discover/CloudSearchScreen.kt`, `discover/ListingProfileScreen.kt`, `ui/Commerce.kt`, `screens/SettingsScreens.kt` | `log_discovery`, `discovery_forget_me` | Medium |
| The demand loop: "Tell me when one joins" and "Know one? Invite them" when a search finds nothing, and "Searches you're waiting for" in notification settings | `ui/Discover.kt`, `discover/CloudSearchScreen.kt`, `screens/SettingsScreens.kt`, `data/BackendDiscover.kt` | `want_notify`, `my_wanted`, `cancel_wanted` | Small |
| Showcase documents on a page (add, check, request and grant access, view log), category suggestions | `data/BackendDocs.kt`, `ui/screens/manage/ShowcaseDocsManageScreen.kt`, `ui/screens/discover/ShowcaseDocsUi.kt` | `showcase_docs`, `add_showcase_doc`, `update_showcase_doc`, `delete_showcase_doc`, `open_showcase_doc`, `check_showcase_doc`, `clear_showcase_check`, `request_doc_access`, `decide_doc_request`, `revoke_doc_access`, `doc_requests_for`, `doc_view_log`, `category_suggestions` | Large (about 650 lines of Kotlin) |
| Map privacy: consent to show posts on the map, my map posts, "it shows my location" report | `data/BackendMap.kt`, `ui/screens/MapPrivacyScreen.kt` | `set_map_consent`, `set_post_on_map`, `my_map_posts`, `report_map_location`, `for_you` | Small |
| Delivery riders for a shop's order (assign, reassign), rating the rider, my review of an order | `data/BackendDelivery.kt`, `data/BackendStudio.kt`, `ui/Commerce.kt` | `order_delivery`, `reassign_delivery`, `rate_rider`, `my_order_review` | Medium |
| Staff queues: reports, vehicle checks | `ui/Safety.kt`, `ui/screens/manage/DocumentsScreens.kt` | `report_queue`, `review_report`, `vehicles_to_review`, `review_vehicle` | Medium (staff only) |
| Places in search (find a place, add one), the page owner line and phone on a page | `data/BackendDiscover.kt`, `ui/screens/discover/OwnerLine.kt` | `search_places`, `add_place`, `listing_owner`, `listing_phone` | Medium |
| Cancellation history shown before cancelling | `data/BackendCancel.kt`, `ui/components/CancelSheet.kt` | `my_cancel_stats` | Small |
| App language (20 languages on Android; iOS is English only) | `data/AppLanguages.kt`, `res/values-*/` | `set_my_locale` | Large: every iOS string is hard-coded in English |
| Synced-only feed tab, Moments by author | `data/Backend.kt` | `feed_synced`, `moments_of` | Small (`moments_of` is unused on Android too) |
| Pro profile (table access, no RPC) and analytics / Crashlytics | `ui/screens/pro/*`, `data/BackendPro.kt`, `data/Analytics.kt` | n/a | Large |

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

- **iPhone push in the background**: the APNs block is in `supabase/functions/notify`. It works once that function is redeployed and an
  APNs key is in Firebase. Until then iPhones get pushes only while Bucks is open.
- **On-device checks** (camera, speech, Face ID, background location, push) are manual: CI builds and unit-tests the iOS app but does not
  run it on a device.

## Social-first 1.0 (Android first)

| Feature | Android | iOS | Follow-up |
|---|---|---|---|
| Social screens in the one shell (the social-only shell is retired; the app uses the super-app layout) | `ui/BucksAppUi.kt` hosting `ui/social/*` | iOS already has the super-app layout | Port the social screens below |
| Date of birth, age bands, guardian consent for under-18s | `ui/onboarding/OnboardingScreens.kt`, `ui/social/Onboarding.kt` (`GuardianScreen`), `ui/Safety.kt` | `BucksUI/Screens/Auth/BirthDateScreen.swift`, `GuardianScreen.swift`, `AppSession.needsGuardian` | = (server enforces the rules for both apps) |
| Report sheet and staff report queue | `ui/social/Report.kt`, `Settings.kt`, `discover/ListingProfileScreen.kt` (Reviews tab), `jobs/JobScreen.kt` | Report sheet: `BucksUI/Screens/Settings/ReportSheet.swift` (posts, comments, moments, messages, pages, chats, people, recommendations and reviews in a page's Reviews tab, jobs). When a review or job can be reported is `ReportTarget.review` / `.job` in `BucksCore/BackendSafety.swift`: someone else's review with words in it, on a live page; an open job of a business you don't run (iOS hides what `report_content` refuses, where Android shows a button that fails). "It shows my location" and the staff queue: not yet | Port the staff queue and "it shows my location". A job report names the business in the sheet (Android passes the job title) |
| Store reviewers stand at the demo world | Not yet | `BucksCore/ReviewAnchor.swift`, `AppSession.useReviewAnchor`: a number in `review_accounts` (`supabase/migrations/review_accounts.sql`) gets a fixed position from `review_anchor()` instead of GPS | Android: call `review_anchor()` after sign-in and use it in place of the location fix, so Play's reviewers see the demo world too |
| Help: common questions, contact us, grievance officer (IT Rules 2021), legal pages | `ui/social/Settings.kt` (`HelpScreen`), `ui/social/Legal.kt`; `SUPPORT_EMAIL`, `GRIEVANCE_OFFICER` from `app/build.gradle.kts` | `BucksUI/Screens/Settings/HelpScreen.swift`, `BucksCore/Legal.swift`; the same two secrets reach Info.plist (`SupportEmail`, `GrievanceOfficer`) through `Config/Secrets.xcconfig`; opened from Account > Settings (Help and legal) and the side menu | = except: no feedback board link (iOS has no board yet); with no support address in the build, iOS shows the grievance page link where Android shows only a line of text; the FAQ answers name the iOS screens (Home search and Sync instead of Discover, press and hold a message to report it, Profile > Settings) and the Nearby audience Moments have on both apps |
| People search, person profile | `ui/social/Discover.kt`, `Profile.kt` | `Screens/Discover/HomeSearch.swift` (people cards), `Screens/Chat/PersonScreen.swift` | = (no cover/profile photos, see About you) |
| Feedback board | `ui/social/Feedback.kt`, `data/BackendFeedback.kt` | `Screens/Settings/FeedbackBoardScreen.swift`, `BucksCore/BackendFeedback.swift` | = |
| Pro profile (Bucks Pro menu): intro, experience, education, skills, certificates, services, preferences, visibility, CV files | `ui/screens/pro/*`, `data/BackendPro.kt`, `supabase/migrations/pro_profile.sql` | Not yet | Reading a CV to fill the profile is planned (AI waitlist) |
| Colour themes (Purple, Sapphire, Emerald, Ruby, Graphite) in Appearance | `ui/theme/Theme.kt` (`Accent`), `ui/screens/SettingsScreens.kt` | `BucksUI/Design/Theme.swift` (colour tables per `Prefs.Accent`), `Screens/Account/AppearanceScreen.swift` | Same values on both; change them together |
| Analytics (adults only) and Crashlytics | `data/Analytics.kt` | Not yet | |
