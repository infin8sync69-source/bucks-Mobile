# supabase/

The Bucks database: one base file, a stack of migrations that replace parts of it, and the tests that hold it together.

## Apply it: one command, never a paste

```
DATABASE_URL='postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres' supabase/apply_all.sh
supabase/apply_all.sh --print-order        # only lists the files below in order, connects to nothing
```

Use the direct connection (port 5432) or the session pooler, not the transaction pooler (6543). The script runs every file below in one
transaction with `psql -v ON_ERROR_STOP=1`: if one fails nothing changes. It holds locks on most tables for a few seconds, so run it when the app
is quiet. Run it for the first install and after every change to any file in this list. Then check the result:

```
psql "$DATABASE_URL" -X -f supabase/tests/catalog_assertions.sql     # every line must say ok
psql "$DATABASE_URL" -X -f supabase/launch_checklist.sql             # every row must say ok before real users are invited
```

**Do not paste `schema.sql` or a single migration into the SQL Editor on a live project.** `schema.sql` is the base, not an idempotent patch: it
drops every policy in `public` and re-creates the first versions, re-grants full table privileges (undoing the column protections on
`profiles.home` and `tasks.pin`) and `execute` on every function (making internal ones such as `push_note` callable through the API), and re-creates
older versions of functions that later migrations replaced (`recommend` goes live without the document check, `review` loses its own-listing and
duplicate checks, `claim_task`, `open_tasks_near`, `contact_for_task` and `place_order` revert, `open_tasks_near` returns the PIN again). It now refuses to
run on a database that already has Bucks tables (`schema.sql would undo later migrations: run supabase/apply_all.sh`); `apply_all.sh` lifts that guard for
its own session only (`set bucks.allow_schema_rerun = 'on'`) and follows it with every migration, which puts everything back. A migration on its own is
safe to re-run (each is idempotent) but must run after the ones before it in the order below.

## The order and what each file does

| # | File | What it does |
|---|------|--------------|
| 1 | `schema.sql` | Extensions, tables, row-level security, the core functions (people, listings, vehicles, orders, tasks, reviews, jobs, chat, feed, moments), storage buckets and their first policies, cron jobs, realtime. |
| 2 | `migrations/manage.sql` | My invites, hides `profiles.home` from the API, vehicle re-review on plate/type/documents, `delete_listing`. |
| 3 | `migrations/owner_read.sql` | Owners can read their own listing or vehicle straight after inserting it. |
| 4 | `migrations/commerce.sql` | Cart and checkout rules (`place_order`, `respond_order`, `cancel_order`, `contact_for_order`, order status). |
| 5 | `migrations/discover.sql` | `listing_points`, `listing_counts`, blocks close the listing chat. |
| 6 | `migrations/jobs.sql` | Jobs near me, job page, application rules, `start_applicant_chat`. |
| 7 | `migrations/dispatch.sql` | Task views with coordinates, the PIN only for its customer, ringing and claiming, presence rules, `delete_my_account`. |
| 8 | `migrations/social-extras.sql` | Group members, what members may change, nearby moments that can be opened, post edit guard. |
| 9 | `migrations/contact_links.sql` | Private contact details attached to people you are synced with. |
| 10 | `migrations/services.sql` | Services menu and unlock rules, listing documents and their review, `recommend` with the document gate, `search_listings` by service. |
| 11 | `migrations/studio.sql` | Assets, galleries, item stock, the Bucks ID card. **After `services.sql`** (it replaces `listing_service_rules` and `place_order`). |
| 12 | `migrations/push.sql` | Device tokens, `push_notify` webhook to the `notify` Edge Function. |
| 13 | `migrations/notifications.sql` | In-app notifications written by triggers. |
| 14 | `migrations/interactions.sql` | Comment, like and reaction notifications. |
| 15 | `migrations/ring_drivers.sql` | `drivers_to_ring`: who the `notify` function pushes a new ride or delivery request to. |
| 16 | `migrations/aspire_media.sql` | `media_urls_ok` also accepts the Aspire More store's own Shopify CDN photos. |
| 17 | `migrations/product_feedback.sql` | Product recommend / not recommend, the slim `catalog_items`, a store's posts in its followers' Feed. |
| 18 | `migrations/ecommerce.sql` | Shipping across India (`place_order_ship`, address book, `ship_order`, `mark_delivered`), local delivery inside the shop's radius, `rate_listing`. |
| 19 | `migrations/hardening_dispatch.sql` | Audit fixes for dispatch, rides, deliveries, orders and reviews (its `place_order`, `place_order_ship` and `contact_for_order` keep ecommerce.sql's rules). |
| 20 | `migrations/hardening_platform.sql` | Audit fixes for privacy, storage, data shape and account deletion (P1 to P14 of the audit; the header of the file lists them; its `search_listings` and `can_see_post` keep ecommerce.sql's and product_feedback.sql's rules). |

The two hardening files come last on purpose: they redefine the latest version of functions that earlier files define.

Not part of the order:

- `pilot_test_settings.sql` is **for test projects only**. It lowers the recommendation count to 1, the recommender's account age to 0 days and every service's `min_supply` to 1
  so two phones can exercise every flow. Never run it on the production project; `launch_checklist.sql` flags every value it changes.
- `launch_checklist.sql` is a read-only query (one row per check) for the production project, with the Firebase console checks SQL cannot see listed in its header.
- `tests/` holds the scenario suites, `tests/catalog_assertions.sql` and the local Supabase stand-in `tests/local_auth_shim.sql`.
- `functions/` holds the Edge Functions (`claim-role`, `notify`); they are deployed with the Supabase CLI, not applied to the database.

## Run the tests locally

You need PostgreSQL 15 or newer with PostGIS installed (Postgres.app, or `brew install postgresql@16 postgis`). `schema.sql` creates the extensions itself.

```
createdb bucks_test
psql -d bucks_test -X -q -v ON_ERROR_STOP=1 -f supabase/tests/local_auth_shim.sql     # stand-in for Supabase's auth and storage schemas and roles
DATABASE_URL=postgresql:///bucks_test supabase/apply_all.sh                             # the whole stack, as production gets it
psql -d bucks_test -X -q -f supabase/tests/catalog_assertions.sql                       # read-only, prints ok / FAIL lines
```

Each `*_scenarios.sql` file creates its own people and rows, so run it in a throw-away copy of the database and read the lines it prints
(`ok`, `FAIL`, or plain results that the suite describes):

```
createdb -T bucks_test scratch
psql -d scratch -X -q -f supabase/tests/hardening_platform_scenarios.sql | grep -E "FAIL|ERROR"    # no output means all passed
dropdb scratch
```

`ecommerce_scenarios.sql` checks shipping, local delivery radius, store search and follower posts as they stand after the hardening files (which redefine those functions).
`hardening_platform_scenarios.sql` starts every audit item as an exploit: run against the stack **without** `hardening_platform.sql` it prints `FAIL: ... (exploit works ...)`
lines, with it every line is `ok`. `local_auth_shim.sql` is only for tests: it is not applied to Supabase, and a real project needs neither it nor a local copy of `auth` or `storage`.

## Dispatch settings (rows of `public.settings`, all created by `hardening_dispatch.sql`; change with `update public.settings set value = ... where key = ...`)

| Key | Default | Meaning |
|-----|---------|---------|
| `arrive_radius_m` | 800 | A driver must be this close to the pick-up to mark ARRIVED. 0 switches the check off. |
| `complete_radius_m` | 2000 | ... and this close to the drop to mark COMPLETED (waived after `max(30 min, 6 min per km)`). 0 switches it off. |
| `min_trip_seconds` | 60 | Minimum time from IN_PROGRESS to COMPLETED, and the shortest trip or order that can be reviewed. |
| `claim_fresh_seconds` | 180 | A driver's presence must be this fresh to claim, see requests or show on the map (the app's heartbeat is 60 s). |
| `ring_window_seconds` | 180 | A request is offered to drivers for this long (from when it last started searching), then becomes NO_DRIVER. |
| `presence_max_speed_mps` | 40 | A driver's movement allowance (metres) grows by this much per second; a reported position that costs more than the allowance is ignored. 0 switches the check off. |
| `presence_slack_m` | 300 | The allowance a new presence row starts with (so the first reports are not refused for GPS noise). |
| `fare_base`, `fare_bike_per_km`, `fare_auto_per_km`, `fare_cab_per_km` | 20, 8, 12, 18 | The ride fare `request_ride` computes: base plus the vehicle kind's rate per km (bikes carry goods only, so the bike rate is not used for rides). |

`ride_radius_m` (5 km) and `delivery_radius_m` (3 km) decide who is rung. A project used for device tests with mock locations can set `arrive_radius_m`, `complete_radius_m`,
`min_trip_seconds` and `presence_max_speed_mps` to 0 so a phone can jump between places; `launch_checklist.sql` (rows 13 to 16) flags every one that is left at 0 in production.
The `bucks-expire-tasks` pg_cron job runs `expire_tasks()` every minute (only where pg_cron exists; otherwise schedule it yourself): it turns unanswered requests into NO_DRIVER and hands a
trip back when its driver has been silent for 10 minutes.

## Files in storage are queued for removal, not removed

SQL cannot delete storage objects. `delete_my_account()` writes the name of every file the person owned (their avatar, post, moment and document folders,
their listings' `listing-media` folders, and chat files whose uploader is them) into `public.storage_cleanup (bucket, name, queued_at)`. Nothing in the app can read or
write that table. **Something with the service role still has to process it**: an Edge Function on a schedule that reads the rows, calls
`supabase.storage.from(bucket).remove([name])` and deletes each queue row it removed (until it exists, deleted accounts leave their files behind, so
check the queue is empty from time to time: `select bucket, count(*) from public.storage_cleanup group by 1`). The app also removes the person's `docs`
folder before it calls `delete_my_account`, but `docs` files that back a VERIFIED listing document can no longer be deleted from the app (that is intended), so they are queued here.

## Known limits of the current design

- `recommend(token, lat, lng)` trusts the position the app reports and `profiles.home` is whatever the person saved: the 3 km and 14-day rules stop casual gaming, not someone
  with a modified client or many accounts.
- `suggest_people` snaps both homes (the caller's and the other person's) to a 0.02 degree grid, about 2 km, and shows the distance between the two grid points in 2 km steps. An account
  chooses its own home, so moving it around shows which grid cell someone lives in and nothing finer: that cell (about 2 km across) is what the feature reveals by design.
  Rate limiting home changes was left out: after snapping there is no finer position left to protect, and a limit would reject a tester who corrects a wrong pin.
- A driver's position is what every proximity check measures from (claiming, listing requests, ARRIVED, COMPLETED), and the driver reports it. Two things keep that honest enough:
  each presence row has a movement allowance that starts at `presence_slack_m` and grows by `presence_max_speed_mps` metres for every second since the last accepted position change,
  and a reported position that costs more than the allowance is dropped and the old one kept (a vehicle never runs out; 250 m hops in a loop or one 31 km jump do; waiting D / 40
  seconds buys a jump of D metres, so this is a speed bump), and `claim_task` lets one driver account claim at most 3 trips an hour (counting hand-backs, including the ones
  `expire_tasks` makes for a driver who went quiet), which caps how many requester phone numbers one account can read. An account holding several verified vehicles can still reset its history by deleting
  one (the presence row goes with it), and several accounts multiply every per-account limit.
- A trip that is IN_PROGRESS is closed by the driver near the drop (or from anywhere once `max(30 min, 6 min per km)` have passed since it started), by the rider once the driver has
  been silent for 10 minutes, or by staff with `select staff_close_task('<task id>', 'COMPLETED' or 'CANCELLED')` (a row in `staff` is required, see `services.sql`).
- `conversation_members.last_read_at` of the other members is readable by any member of the chat even when they turned read receipts off (only `seen_up_to()` honours the setting).
  Fixing it needs the app to name its columns on that table (like `profiles`), then `revoke select` plus a column grant.
- Orders and trips keep the buyer's or rider's address and coordinates after the account is deleted (the other party's record).
- The constraints added by `hardening_platform.sql` are `NOT VALID`: new and edited rows are checked, old rows are not. Its warnings name any old rows that break a limit; clean them, then
  `alter table public.<table> validate constraint <name>;`.
