-- Bucks: push notifications on iPhone. PROPOSAL ONLY: nothing here has been applied anywhere.
--
-- What the app does: after sign-in it calls the existing rpc register_device_token(p_token, p_platform) with the FCM token that
-- Firebase Messaging derives from the APNs token, and p_platform = 'ios'. push.sql already accepts any platform text, so the
-- function and table need no change to STORE an iPhone token.
--
-- What the server must change to REACH it (supabase/functions/notify/index.ts, not SQL):
--   1. deliver(): select "token,profile_id,platform" from device_tokens (platform is already a column).
--   2. sendOne(): for platform = 'ios' also send an apns block (full code in notify_ios.proposal.ts). A data-only message does not show on
--      iOS in the background. Two limits that bite: apns-collapse-id may be at most 64 bytes (tags such as "like-<uuid>-<uuid>" are 78,
--      and APNs rejects the whole push), so longer tags are left out; and apns-expiration should mirror the Android ttl.
--      Keep the existing data { type, title, body, route, quiet } so the app reads the route when the notification is tapped.
--   3. FCM needs the APNs auth key (.p8) uploaded under Firebase console > Project settings > Cloud Messaging.
--
-- Optional hardening below: only the two platforms the apps send.

alter table public.device_tokens drop constraint if exists device_tokens_platform_check;
alter table public.device_tokens add constraint device_tokens_platform_check check (platform in ('android', 'ios')) not valid;
-- Run once the existing rows are known to be clean:  alter table public.device_tokens validate constraint device_tokens_platform_check;
