// Push delivery for swarm-worker: the FCM HTTP v1 sender, notification settings and quiet hours, copied from notify/index.ts
// (same keys, same quiet hours in Asia/Kolkata, same APNs alert for iPhones) so swarm-worker can ship without redeploying notify.
// Keep the two in step; when notify is next refactored this file and notify should share one module (supabase/functions/_shared).
type Row = Record<string, any>;
export type Kind = "messages" | "orders" | "tasks" | "ride" | "social";
export type NotifyKey = "messages" | "sync_requests" | "moments" | "comments" | "orders" | "tasks" | "my_orders" | "my_trips" | "offers";
/** One notification for one person, before their settings are applied (the same shape notify uses). */
export interface Note { to: string; key: NotifyKey; type: Kind; title: string; body: string; route: string; urgent?: boolean; tag?: string }
interface ServiceAccount { project_id: string; client_email: string; private_key: string; token_uri?: string }

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";
const BATCH = 20;
const restHeaders = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };
async function select<T = Row>(table: string, query: string): Promise<T[]> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: restHeaders });
  if (!r.ok) throw new Error(`select ${table}: ${r.status} ${await r.text()}`);
  return await r.json();
}
async function remove(table: string, query: string): Promise<void> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { method: "DELETE", headers: { ...restHeaders, Prefer: "return=minimal" } });
  if (!r.ok) console.error(`delete ${table}: ${r.status} ${await r.text()}`);
}
const inList = (ids: string[]) => `in.(${ids.map((i) => `"${i}"`).join(",")})`;

// ---------- settings: on/off per kind, quiet hours in Asia/Kolkata ----------

interface Settings { notify: Record<string, unknown> | null; quiet_hours: { from?: string; to?: string } | null }

function wants(s: Settings | undefined, key: NotifyKey): boolean {
  const v = s?.notify?.[key];
  return typeof v === "boolean" ? v : key !== "offers";   // same defaults as user_settings.notify (schema.sql, push.sql)
}
function minutesOf(hhmm: unknown): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm ?? "").trim());
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);
  return h > 23 || mi > 59 ? null : h * 60 + mi;
}
function nowInKolkata(): number {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Kolkata", hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date());
  const h = Number(parts.find((p) => p.type === "hour")?.value ?? 0) % 24;
  const m = Number(parts.find((p) => p.type === "minute")?.value ?? 0);
  return h * 60 + m;
}
function inQuietHours(s: Settings | undefined): boolean {
  const from = minutesOf(s?.quiet_hours?.from), to = minutesOf(s?.quiet_hours?.to);
  if (from === null || to === null || from === to) return false;
  const now = nowInKolkata();
  return from < to ? now >= from && now < to : now >= from || now < to;   // "22:00" -> "07:00" wraps midnight
}

// ---------- FCM HTTP v1 ----------

let cachedToken: { value: string; expiresAt: number } | null = null;

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

/** OAuth2 access token for the service account: a self-signed RS256 JWT exchanged at Google's token endpoint, cached 50 minutes. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now()) return cachedToken.value;
  const tokenUri = sa.token_uri || "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: tokenUri, iat: now, exp: now + 3600 }));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${b64url(signature)}`;
  const r = await fetch(tokenUri, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }) });
  if (!r.ok) throw new Error(`Google OAuth ${r.status}: ${await r.text()}`);
  const j = await r.json();
  cachedToken = { value: j.access_token, expiresAt: Date.now() + 50 * 60 * 1000 };
  return j.access_token;
}

type SendResult = "sent" | "gone" | "failed";

// The category ids the iOS app registers (ios/Sources/BucksCore/Push.swift PushKind.categoryId), by note type.
const APNS_CATEGORY: Record<string, string> = { messages: "bucks_messages", orders: "bucks_orders", tasks: "bucks_trips", ride: "bucks_ride_request", social: "bucks_social" };
const APNS_COLLAPSE_MAX = 64;   // bytes; APNs rejects a longer apns-collapse-id with 400 BadCollapseId

// iPhones: a data-only message does not show in the background there, so they also get an alert. The app reads the same data keys on tap.
// Needs the APNs auth key (.p8) uploaded in the Firebase console (Project settings > Cloud Messaging), or FCM answers 401 for iOS tokens.
function apnsFor(n: Note, quiet: boolean) {
  // "ride": a new request ringing a driver: it lapses with the ring window and rings with the Bucks tune (ios/App/ride_request.wav).
  const ttl = n.type === "ride" ? 120 : n.type === "tasks" ? 900 : 86400;
  const collapse = n.tag && new TextEncoder().encode(n.tag).length <= APNS_COLLAPSE_MAX ? { "apns-collapse-id": n.tag } : {};
  return {
    headers: { "apns-push-type": "alert", "apns-priority": quiet ? "5" : "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + ttl), ...collapse },
    payload: {
      aps: {
        alert: { title: n.title, body: n.body },
        "thread-id": n.type,
        category: quiet ? "bucks_quiet" : APNS_CATEGORY[n.type] ?? "bucks_social",
        "interruption-level": quiet ? "passive" : n.type === "tasks" || n.type === "ride" ? "time-sensitive" : "active",
        ...(quiet ? {} : { sound: n.type === "ride" ? "ride_request.wav" : "default" }),
      },
    },
  };
}

async function sendOne(sa: ServiceAccount, bearer: string, token: string, platform: string, n: Note, quiet: boolean): Promise<SendResult> {
  const message = {
    token,
    ...(platform === "ios" ? { apns: apnsFor(n, quiet) } : {}),
    android: { priority: quiet ? "normal" : "high", ttl: n.type === "ride" ? "120s" : n.type === "tasks" ? "900s" : "86400s", ...(n.tag ? { collapse_key: n.tag } : {}) },
    data: { type: n.type, title: n.title, body: n.body, route: n.route, quiet: quiet ? "true" : "false" },
  };
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" }, body: JSON.stringify({ message }),
  });
  if (r.ok) return "sent";
  const text = await r.text();
  // The phone uninstalled the app or FCM retired the token: forget it.
  if ((r.status === 404 && text.includes("UNREGISTERED")) || (r.status === 400 && /not a valid FCM registration token|INVALID_ARGUMENT/.test(text) && text.includes("token"))) return "gone";
  console.error(`FCM ${r.status} for ${n.type}/${n.route}: ${text.slice(0, 300)}`);
  return "failed";
}

export async function deliver(notes: Note[]): Promise<Row> {
  if (notes.length === 0) return { recipients: 0, sent: 0 };
  const people = [...new Set(notes.map((n) => n.to))];
  const settings = new Map((await select<Settings & { profile_id: string }>("user_settings", `profile_id=${inList(people)}&select=profile_id,notify,quiet_hours`)).map((s) => [s.profile_id, s]));
  const wanted = notes.filter((n) => wants(settings.get(n.to), n.key));
  if (wanted.length === 0) return { recipients: people.length, sent: 0, skipped: "everyone turned this off" };
  const tokens = await select<{ token: string; profile_id: string; platform: string }>("device_tokens", `profile_id=${inList([...new Set(wanted.map((n) => n.to))])}&select=token,profile_id,platform`);
  if (tokens.length === 0) return { recipients: people.length, sent: 0, skipped: "no phones registered" };
  if (!FCM_SERVICE_ACCOUNT) return { recipients: people.length, sent: 0, skipped: "FCM_SERVICE_ACCOUNT is not set" };
  const sa = JSON.parse(FCM_SERVICE_ACCOUNT) as ServiceAccount;
  const bearer = await accessToken(sa);
  const jobs: { token: string; platform: string; note: Note; quiet: boolean }[] = [];
  for (const n of wanted) {
    const quiet = !n.urgent && inQuietHours(settings.get(n.to));
    for (const t of tokens) if (t.profile_id === n.to) jobs.push({ token: t.token, platform: t.platform, note: n, quiet });
  }
  let sent = 0, failed = 0;
  const gone: string[] = [];
  for (let i = 0; i < jobs.length; i += BATCH) {
    const results = await Promise.all(jobs.slice(i, i + BATCH).map((j) => sendOne(sa, bearer, j.token, j.platform, j.note, j.quiet).catch((e) => { console.error(e); return "failed" as SendResult; })));
    results.forEach((res, k) => { if (res === "sent") sent++; else if (res === "gone") gone.push(jobs[i + k].token); else failed++; });
  }
  if (gone.length > 0) await remove("device_tokens", `token=${inList([...new Set(gone)])}`);
  return { recipients: people.length, phones: jobs.length, sent, failed, removed_tokens: gone.length };
}

