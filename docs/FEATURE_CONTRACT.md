# Feature contract for parallel work

Several features are built at the same time in separate git worktrees and merged afterwards.
This file says what already exists, what each feature may touch, and what it must hand back.

## What exists (read these first)
- `supabase/schema.sql` — the whole database: tables, row-level security, and the functions the app calls (`search_listings`, `place_order`,
  `respond_order`, `request_ride`, `open_tasks_near`, `claim_task`, `advance_task`, `update_location`, `contact_for_task`, `invite`,
  `respond_invite`, `recommend_token`, `recommend`, `review`, `start_listing_chat`, `inbox`, ...). It is applied to the live Supabase project.
- `app/src/main/java/com/bucks/app/data/Backend.kt` — Kotlin wrapper for every function and table above (`Backend.search`, `Backend.placeOrder`, ...)
  plus row classes (`ListingRow`, `ItemRow`, `OrderRow`, `TaskRow`, `JobRow`, ...). `Backend.client` is public for extensions.
- `app/src/main/java/com/bucks/app/ui/Social.kt` — the pattern for cloud state: a plain class `(scope, repo, toast)` holding Compose state,
  actions wrapped in `go { }` so failures become toasts, `social.me` (my `ProfileRow`), `social.here` (my `LatLng`), `social.names` (id → name).
- `app/src/main/java/com/bucks/app/ui/screens/CloudSocialScreens.kt` — the pattern for cloud screens; also `SignedImage(vm, bucket, path, modifier)`
  for private files and `ago(iso)`.
- `app/src/main/java/com/bucks/app/ui/components/` — `Components.kt` (BucksTopBar, ContentColumn, BucksCard, PrimaryButton, SmallButton, Chip,
  FlowChips, Muted, Label, SectionTitle, ListRow, Avatar, TrustBadge, Pill*, BucksField, Sheet, SearchBar, BucksMap/MapPin/pinAt),
  `Qr.kt` (qrBitmap, scanQr, BucksQr), `Motion.kt`.
- `data/Upload.kt` (`Upload.read(ctx, uri)` → `Picked` bytes for `Backend.upload(bucket, path, bytes)`), `data/Prefs.kt`, `data/Geo.kt`.
- Storage buckets and who may read them are in schema.sql under "file storage". Public: `avatars`, `listing-media` (use `Backend.publicUrl`).
  Private: `chat`, `moments`, `posts`, `docs` (use `SignedImage` / `Backend.signedUrl`). Path rule: first folder = owner id (or listing id for
  listing-media, conversation id for chat).
- Routes for every feature are already in `ui/nav/Routes.kt` (LISTING, MY_LISTINGS, LISTING_EDIT, ITEM_EDIT, VEHICLE_EDIT, RECOMMEND_SHOW,
  RECOMMEND_SCAN, MEMBERS, INVITES, VEHICLE_STATS, CLOUD_CART, CLOUD_ORDER, MY_ORDERS, VENDOR_ORDERS, DELIVERY_TRACK, PAYMENT_QR, LISTING_JOBS,
  JOB, JOB_NEW, MY_APPLICATIONS, JOBS_NEAR, GROUP_NEW). Use them; do not add or rename routes.

## Rules for every feature
1. Work only in your own git worktree and branch (`git -C /home/user/bucks-Mobile worktree add /home/user/wt/<feature> -b feat/<feature>`).
2. Create new files; do not edit the shared files below unless the ownership table says you own them:
   `ui/BucksAppUi.kt`, `ui/nav/Routes.kt`, `ui/BucksViewModel.kt`, `data/Backend.kt`, `data/Cloud.kt`, `gradle/libs.versions.toml`,
   `app/build.gradle.kts`, `supabase/schema.sql`, `ui/Social.kt`, `ui/screens/CloudSocialScreens.kt`.
   - Need a new Backend call? Put it in `data/Backend<Feature>.kt` as `suspend fun Backend.xxx(...)` using `Backend.client.postgrest` / `.storage`.
   - Need schema changes? Put them in `supabase/migrations/<feature>.sql` (idempotent, RLS for every new table, `set search_path = public, extensions`),
     and tests in `supabase/tests/<feature>_scenarios.sql` in the style of `supabase/tests/social_scenarios.sql`. Run them locally:
     start Postgres with `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/tmp/bucks-pg/data -o '-p 5433 -k /tmp' -l /var/tmp/bucks-pg/log -w start"`,
     then `psql -h /tmp -p 5433 -U postgres -c "drop database if exists <db>" -c "create database <db>"` and apply
     `supabase/tests/local_auth_shim.sql`, `supabase/schema.sql`, your migration, your tests, in one psql session. Stop Postgres when done.
   - Need a Gradle dependency? Do not edit Gradle; list it in your report and the integrator adds it.
3. Screens are cloud-only: they assume `vm.social.enabled` and `vm.social.me != null`. Demo mode keeps the old screens; the integrator adds the switch.
4. State lives in one class per feature, constructed as `Name(scope: CoroutineScope, social: Social, toast: (String) -> Unit)`, file `ui/<Name>.kt`,
   following `Social.kt`. Screens take `vm: BucksViewModel` and reach the state as `vm.<name>` (the integrator adds `val <name> = Name(viewModelScope, social, ::toast)`
   to `BucksViewModel`). Reference it exactly as agreed in the ownership table.
5. Compose style as in the existing screens: Material 3, the shared components, `Gutter` padding, `Muted` for secondary text, buttons from Components.
   Every screen has a `BucksTopBar` with a back arrow unless it is a tab. Every list has an empty state that tells the user what to do next.
6. There is no local Android compiler. Before you finish, run the parse check on every Kotlin file you wrote:
   `K=/tmp/claude-0/-home-user/1f03ebc4-2678-5dce-b408-070b118e81d9/scratchpad/kotlinc/bin/kotlinc; $K <files> -d /tmp/kc-out 2>&1 | grep -E "error: (expecting|unexpected|syntax|unclosed|unresolved reference: [a-z])" | grep -v "unresolved reference: [A-Z]"`
   Only syntax errors matter (missing libraries show as unresolved references to capitalised names and can be ignored). Also re-read your code
   against `Backend.kt` signatures and the Compose APIs used in existing screens; mismatches cost a 7-minute CI round trip each.
7. Commit in your worktree with a clear message ending in the two attribution lines:
   `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01A4HgH7o2NV6HeUEztmbaCC`.
8. Your final answer is the structured report the integrator works from: exact wiring lines (NavHost `composable(...)` entries, the state-holder
   line for BucksViewModel, cloud/demo switches to make, Gradle dependencies), files created, SQL files, and known gaps.

## Ownership
| Feature | Owns (may create/edit) | State class | Notes |
|---|---|---|---|
| discover | `ui/Discover.kt`, `ui/screens/discover/*.kt`, `data/BackendDiscover.kt` | `vm.discover` | Universal listing profile (`Routes.LISTING`) for BUSINESS / SKILL / DRIVER, cloud search screen with the universal search card, reviews, sync-with-listing, "Message" via `Backend.startListingChat`, "Order" → `Routes.CLOUD_CART` (cart lives in `vm.commerce`, see below), "Jobs" tab → `Routes.listingJobs(id)`, "Book" for drivers → existing ride flow. |
| manage | `ui/MyListings.kt`, `ui/screens/manage/*.kt`, `data/BackendManage.kt` | `vm.myListings` | Create/edit/delete businesses (+ products with photos in `listing-media`), skills (+ services), vehicles (+ document photos in `docs`), online toggles, my listings hub (`MY_LISTINGS`, `MY_VEHICLES`), recommendation QR (`RECOMMEND_SHOW` shows `recommend_token` as `BucksQr.forRecommendation`, refreshed every 90 s; `RECOMMEND_SCAN` scans and calls `Backend.recommend(token, here)`, shows "n of 7"), admins and store riders (`MEMBERS`: invite by Bucks ID, remove; `INVITES`: accept/decline), vehicle admins, vehicle owner dashboard (`VEHICLE_STATS` from `Backend.vehicleStats`). |
| commerce | `ui/Commerce.kt`, `ui/screens/commerce/*.kt`, `data/BackendCommerce.kt` | `vm.commerce` | Cart over cloud items (one shop at a time), checkout (`CLOUD_CART`: delivery mode marketplace / store rider / pickup, payment UPI / cash-on-delivery only with store riders, drop location = `social.here` + label), `Backend.placeOrder`, my orders (`MY_ORDERS`), order page (`CLOUD_ORDER`) with status timeline and, once a delivery task exists, a link to `DELIVERY_TRACK`; vendor inbox (`VENDOR_ORDERS`) with realtime on `orders`, 5-minute countdown, accept / reject via `Backend.respondOrder`. |
| dispatch | `ui/Dispatch.kt`, `ui/screens/dispatch/*.kt`, `data/BackendDispatch.kt`, **and** `ui/BucksViewModel.kt`, `data/Cloud.kt`, `data/DriverLocationService.kt`, `ui/screens/RideScreens.kt`, `ui/screens/DriverScreens.kt` | `vm.dispatch` | Move rides and deliveries off Firestore onto Supabase `tasks`: presence (`Backend.setPresence` on going online, heartbeat), ringing (`Backend.openTasksNear` every 5 s while online + realtime on `tasks`), claim / pass / advance with PIN, driver location through `DriverLocationService` → `Backend.updateLocation`; rider side follows its task row (realtime) through SEARCHING → MATCHED → ARRIVED → IN_PROGRESS → COMPLETED → PAID; `DELIVERY_TRACK` for a buyer following a delivery. Driver payment QR (`PAYMENT_QR`): pick a QR image, decode with zxing `MultiFormatReader`, keep only `upi://pay?...`, save via `Backend.setPaymentLink`; rider's Pay screen fetches `Backend.contactFor(task)` and opens the UPI app with `am=` fare filled in (Intent ACTION_VIEW on the upi:// URI with the amount replaced/added), then the rider confirms "Paid". Firestore ride code may be deleted once replaced; keep the demo (non-cloud) simulation working. |
| jobs | `ui/Jobs.kt`, `ui/screens/jobs/*.kt`, `data/BackendJobs.kt` | `vm.jobs` | Business posts jobs (`JOB_NEW`), job list for a listing (`LISTING_JOBS`), job page (`JOB`) with apply (choose my skill listings + note), applications management for owners/admins (shortlist / reject / hire), my applications (`MY_APPLICATIONS`), jobs near me (`JOBS_NEAR`, needs a `jobs_near(lat, lng)` SQL function in your migration). |
| push | `data/Push.kt`, `supabase/migrations/push.sql`, `supabase/functions/notify/index.ts`, `docs/PUSH_SETUP.md`, `app/src/main/AndroidManifest.xml` (service entry only) | none (functions on `Backend`) | Device tokens table (`device_tokens(profile_id, token, platform, updated_at)` with RLS), `FirebaseMessagingService` that registers the token after sign-in and shows notifications in channels (messages, orders, tasks, social), deep links into the app. Server side: a Supabase Edge Function `notify` that receives database webhooks (messages, orders, tasks, syncs, moments inserts), looks up recipients, honours `user_settings.notify` and `quiet_hours`, and sends through FCM HTTP v1 using a service-account secret; the SQL to create the webhooks (`supabase_functions.http_request` triggers or `pg_net`). Gradle: `com.google.firebase:firebase-messaging` (report it; do not edit Gradle). |
| social-extras | `ui/Social.kt`, `ui/screens/CloudSocialScreens.kt`, `data/BackendSocialExtras.kt` | `vm.social` (existing) | Group chats: create (`GROUP_NEW`: pick synced people, title), rename, leave; show sender names in groups. Video Moments: allow `PickVisualMedia.VideoOnly` (≤ 30 MB), upload as VIDEO, play in the viewer with Media3 ExoPlayer (report the Gradle dependency). Listing chats in the inbox open the listing name. |

The integrator merges every branch into `pilot-release-fixes`, adds the state holders to `BucksViewModel`, the NavHost entries and cloud/demo
switches to `BucksAppUi`, the Gradle dependencies, then pushes and fixes whatever the GitHub build reports until it is green.
