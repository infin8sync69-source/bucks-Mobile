# Push notifications setup

Bucks sends push notifications through Firebase Cloud Messaging (FCM). Nothing in the app polls: when a row lands in
`messages`, `orders`, `tasks`, `syncs`, `moments` or `post_comments`, a database trigger queues one HTTP call with
`pg_net` to the Supabase Edge Function `notify`, which works out who should hear about it, applies their
notification settings and quiet hours, and sends a data-only message to each of their phones. The app draws the
notification and opens the right screen when it is tapped.

```
phone A inserts a message ──► Postgres trigger (push_notify) ──► pg_net POST /functions/v1/notify
                                                                        │  x-bucks-secret
                                                                        ▼
                                              Edge Function: recipients, settings, quiet hours, mutes
                                                                        │  OAuth2 (service account)
                                                                        ▼
                                              FCM HTTP v1 ──► phone B: BucksMessagingService ──► notification ──► tap ──► route
```

Pieces:
- `supabase/migrations/push.sql` — `device_tokens` table, `register_device_token` / `unregister_device_token`, the sealed `push_config`
  table, `notify_url()`, the `push_notify()` trigger function and its triggers.
- `supabase/functions/notify/index.ts` — the Edge Function (Deno, no dependencies).
- `app/.../data/Push.kt` — `BucksMessagingService` (token registration, notification channels, deep links) and `object Push`.
- `app/.../data/BackendPush.kt` — the two token calls on `Backend`.

Setup takes about fifteen minutes. Steps 1 to 5 are done once per project.

## 1. Apply the migration

Supabase → SQL Editor → paste `supabase/migrations/push.sql` → Run. It is safe to re-run. It enables `pg_net`
(Database → Extensions shows it on afterwards), creates the tables, functions and triggers.

## 2. Firebase service account key

The Edge Function signs in to FCM as a service account of the Firebase project the app uses (the one `app/google-services.json` came from).

1. Firebase console → Project settings (gear) → **Service accounts** → **Generate new private key** → Confirm.
   A JSON file downloads (`<project>-firebase-adminsdk-xxxxx.json`). Keep it private; it can send notifications as your app.
2. Make sure the **Firebase Cloud Messaging API (V1)** is enabled: Project settings → Cloud Messaging → "Firebase Cloud Messaging API (V1)" → Enabled.
   (If it says disabled, click the three dots → Manage API in Google Cloud Console → Enable.)

## 3. Set the three secrets

Two go to the Edge Function, one to the database. Pick a long random string for the webhook secret; the database
sends it with every call and the function refuses anything without it.

```bash
# from the repository root, once: npm i -g supabase && supabase login && supabase link --project-ref lboxctryrktwdsvywfqp
WEBHOOK_SECRET=$(openssl rand -hex 32); echo "$WEBHOOK_SECRET"     # keep this: it goes into the database below

supabase secrets set BUCKS_WEBHOOK_SECRET="$WEBHOOK_SECRET"
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/Downloads/<project>-firebase-adminsdk-xxxxx.json)"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into every Edge Function automatically; do not set them.

Then store the same webhook secret in the database (SQL Editor). Only trigger functions can read this table; the app
cannot (`push_scenarios.sql` checks that):

```sql
insert into public.push_config (key, value) values ('webhook_secret', '<the WEBHOOK_SECRET printed above>')
on conflict (key) do update set value = excluded.value;
```

Until this row exists the triggers do nothing, so the migration can be applied ahead of the function.

## 4. Deploy the function

```bash
supabase functions deploy notify --no-verify-jwt
```

`--no-verify-jwt` is required: the caller is the database, not a signed-in person, and the shared secret is the authentication.
Redeploy the same way after changing `index.ts`. Logs: Supabase → Edge Functions → notify → Logs (or `supabase functions logs notify`).

## 5. Check the app build has FCM

`gradle/libs.versions.toml` carries `firebase-messaging` and `app/build.gradle.kts` has `implementation(libs.firebase.messaging)`
(same Firebase BOM as sign-in). `app/google-services.json` must be present, as for phone sign-in. Android 13+ asks for
the notification permission on first sign-in; the app already requests `POST_NOTIFICATIONS`.

## 6. Test

**a. The function on its own** (no database involved). Use a real conversation id and a phone that has signed in
with the app (it registered its token on sign-in, see `select * from device_tokens` in the SQL Editor as the owner):

```bash
curl -s -X POST https://lboxctryrktwdsvywfqp.supabase.co/functions/v1/notify \
  -H "Content-Type: application/json" -H "x-bucks-secret: $WEBHOOK_SECRET" \
  -d '{"table":"messages","type":"INSERT","record":{"id":"00000000-0000-0000-0000-000000000001","conversation_id":"<conversation uuid>","sender_id":"<sender profile uuid>","body":"Test from curl","created_at":"2026-01-01T00:00:00Z"}}'
```

Expected: `{"ok":true,"table":"messages","type":"INSERT","recipients":1,"phones":1,"sent":1,"failed":0,"removed_tokens":0}` and a
notification on the other member's phone within a second or two. `"skipped":"no phones registered"` means the
recipient has no row in `device_tokens` (sign in on the phone again). A wrong secret gives `403`.

**b. End to end**: send a chat message from one phone; the other phone gets it. In the SQL Editor
`select id, status_code, error_msg from net._http_response order by id desc limit 5;` shows the last calls the
database made and what the function answered (`net.http_request_queue` is empty most of the time: the worker drains it in seconds).

**c. Locally**, the SQL side runs without pg_net (`supabase/tests/push_scenarios.sql` substitutes a recording
`net.http_post` and checks each trigger queues exactly one call with the row and the secret):

```bash
psql -d <scratch db> -f supabase/tests/local_auth_shim.sql -f supabase/schema.sql -f supabase/migrations/push.sql -f supabase/tests/push_scenarios.sql
```

## What gets sent, and to whom

| Event | Who | Setting key | Opens |
|---|---|---|---|
| message inserted | every other member of the chat, unless they muted it or blocked the sender | `messages` | that chat |
| order placed | owner and admins of the shop | `orders` | the shop's order inbox |
| order status changed (accepted, rejected, ready, picked up, delivered) | the buyer | `orders` | that order |
| task matched / arrived / (delivery) out for delivery / (ride) completed | the requester | `tasks` | delivery tracking, or Home for rides |
| driver dropped a matched task (back to SEARCHING) | the requester | `tasks` | as above |
| task cancelled by the customer, or marked paid | the driver | `tasks` | Home |
| sync request / sync accepted | the addressee / the requester | `sync_requests` | Sync |
| moment posted | people synced with the author (close friends only for CLOSE), not those who muted them; capped at 500 | `moments` | that person's moments |
| comment on a post | the post's author | `comments` | Feed |

Task inserts notify nobody: online drivers are rung through `open_tasks_near`, which they poll.

Settings come from `user_settings.notify` (a key set to `false` switches that kind off; a missing key means on,
except `offers`). `quiet_hours` (`{"from":"22:00","to":"07:00"}`, Asia/Kolkata, may wrap midnight) turns a
notification quiet: it is sent with normal priority and `quiet=true`, and the app shows it on a silent channel.
Ride, delivery and new-order notifications are never quiet: someone is waiting at the door.

Data keys the app receives: `type` (`messages`, `orders`, `tasks`, `social`), `title`, `body`, `route`, `quiet`.
Channels on the phone: Messages, Orders, Rides and deliveries (high importance, ringtone), Sync/Moments/comments, Quiet hours.

## Token lifecycle

- On sign-in the app calls `Push.registerIfSignedIn()`: FCM token → `register_device_token`, which takes the token over from
  whoever used the phone before.
- FCM rotates tokens occasionally; `onNewToken` re-registers.
- On sign-out `Push.unregister()` removes the row and retires the token at FCM, so the next person on the phone
  never gets the previous person's notifications.
- When FCM answers `UNREGISTERED` (app uninstalled), the function deletes that token.

## Troubleshooting

- `403 forbidden` from the function: `BUCKS_WEBHOOK_SECRET` and the `push_config` row differ. Set both again.
- `Google OAuth 400 invalid_grant`: the service-account JSON is not the one from this Firebase project, or was
  revoked. Generate a new key and set `FCM_SERVICE_ACCOUNT` again.
- `FCM 403 SENDER_ID_MISMATCH`: the phone's token belongs to a different Firebase project than the service account.
  `google-services.json` in the app and the service account must come from the same project.
- `FCM 404 UNREGISTERED`: normal after an uninstall; the token is removed.
- Nothing arrives, function logs empty: the trigger is not firing. Check `select * from push_config` (as the owner),
  `select extname from pg_extension where extname = 'pg_net'`, and `net._http_response` for errors.
- Notifications arrive but tapping opens Home: the route is not one the app knows (`Push.safeRoute`), which is the
  safe fallback.
