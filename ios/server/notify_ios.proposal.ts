// PROPOSAL ONLY (nothing here is applied). Changes to supabase/functions/notify/index.ts so notifications also reach iPhones.
// The iOS app registers its FCM token with platform "ios" (register_device_token); Android's data-only message would arrive silently
// there, so iOS needs an `apns` block with an alert. The app reads the same data keys (type, title, body, route, quiet) on tap.
// Needs the APNs auth key (.p8) uploaded in the Firebase console (Project settings > Cloud Messaging), or FCM answers 401 for iOS tokens.

// 1. deliver(): read the platform with the token.
//      const tokens = await select<{ token: string; profile_id: string; platform: string }>("device_tokens", `profile_id=${inList([...])}&select=token,profile_id,platform`);
//      jobs.push({ token: t.token, platform: t.platform, note: n, quiet });   // and add `platform: string` to the jobs type
//      sendOne(sa, bearer, j.token, j.platform, j.note, j.quiet)

// 2. sendOne(): replace the message literal.
const APNS_COLLAPSE_MAX = 64;   // bytes; APNs rejects a longer apns-collapse-id with 400 BadCollapseId

function apnsFor(n: { type: string; title: string; body: string; tag?: string }, quiet: boolean) {
  const ttl = n.type === "tasks" ? 900 : 86400;
  const collapse = n.tag && new TextEncoder().encode(n.tag).length <= APNS_COLLAPSE_MAX ? { "apns-collapse-id": n.tag } : {};
  return {
    headers: {
      "apns-push-type": "alert",
      "apns-priority": quiet ? "5" : "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + ttl),
      ...collapse,
    },
    payload: {
      aps: {
        alert: { title: n.title, body: n.body },
        "thread-id": n.type,
        category: quiet ? "bucks_quiet" : `bucks_${n.type}`,                 // the categories AppDelegate registers
        "interruption-level": quiet ? "passive" : n.type === "tasks" ? "time-sensitive" : "active",
        ...(quiet ? {} : { sound: "default" }),
      },
    },
  };
}

// const message = {
//   token,
//   android: { ... unchanged ... },
//   ...(platform === "ios" ? { apns: apnsFor(n, quiet) } : {}),
//   data: { type: n.type, title: n.title, body: n.body, route: n.route, quiet: quiet ? "true" : "false" },
// };

// 3. Optional: also drop iOS tokens APNs retired. FCM reports them as 404 UNREGISTERED, which sendOne() already treats as "gone".
