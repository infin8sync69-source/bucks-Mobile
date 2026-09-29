// Bucks "notify": turns database events into push notifications through Firebase Cloud Messaging (HTTP v1).
//
// Called by the pg_net triggers in supabase/migrations/push.sql with {table, type, record, old_record}.
// Works out who should hear about the event, drops anyone who turned that kind of notification off, marks messages
// quiet during the person's quiet hours (Asia/Kolkata), skips muted chats, and sends one data-only message per phone.
// The app (data/Push.kt) draws the notification from the data keys: type, title, body, route, quiet.
//
// Deploy:  supabase functions deploy notify --no-verify-jwt        (the shared secret is the authentication)
// Secrets: FCM_SERVICE_ACCOUNT; the webhook secret comes from push_config (or BUCKS_WEBHOOK_SECRET) (see docs/PUSH_SETUP.md). SUPABASE_URL and
//          SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
// No dependencies: PostgREST over fetch, RS256 through WebCrypto.

type Row = Record<string, any>;
type Op = "INSERT" | "UPDATE" | "DELETE";
type Kind = "messages" | "orders" | "tasks" | "social";
// orders / tasks: my businesses' new orders and the trips I drive; my_orders / my_trips: orders I place and rides or
// deliveries I book. Same keys and labels as NOTIFY_KEYS in the app (ui/screens/SettingsScreens.kt).
type NotifyKey = "messages" | "sync_requests" | "moments" | "comments" | "orders" | "tasks" | "my_orders" | "my_trips" | "offers";

interface DbEvent { table: string; type: Op; record: Row; old_record?: Row | null }
/** One notification for one person, before their settings are applied. */
interface Note {
  to: string; key: NotifyKey; type: Kind; title: string; body: string;
  /** Screen the tap opens (Push.safeRoute in the app). Empty: the tap only brings the app forward. */
  route: string;
  /** Time-critical (a rider at the door): delivered loud even during quiet hours. */
  urgent?: boolean;
  /** Same tag replaces the previous one on the phone (FCM collapse key). */
  tag?: string;
}
interface ServiceAccount { project_id: string; client_email: string; private_key: string; token_uri?: string }

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// The shared secret the database trigger sends. BUCKS_WEBHOOK_SECRET when set; otherwise read from push_config (the same row
// the trigger reads, so there is nothing to copy by hand). Re-read every 5 minutes so a rotated secret takes effect.
const ENV_SECRET = Deno.env.get("BUCKS_WEBHOOK_SECRET") ?? "";
let dbSecret: { value: string; until: number } | null = null;
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";
const MOMENT_FANOUT_CAP = 500;
const BATCH = 20;

// ---------- PostgREST as the service role (row-level security does not apply) ----------

const restHeaders = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };

async function select<T = Row>(table: string, query: string): Promise<T[]> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: restHeaders });
  if (!r.ok) throw new Error(`select ${table}: ${r.status} ${await r.text()}`);
  return await r.json();
}
async function one<T = Row>(table: string, query: string): Promise<T | null> { return (await select<T>(table, `${query}&limit=1`))[0] ?? null; }
async function remove(table: string, query: string): Promise<void> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { method: "DELETE", headers: { ...restHeaders, Prefer: "return=minimal" } });
  if (!r.ok) console.error(`delete ${table}: ${r.status} ${await r.text()}`);
}
const inList = (ids: string[]) => `in.(${ids.map((i) => `"${i}"`).join(",")})`;

async function names(ids: string[]): Promise<Map<string, string>> {
  const want = [...new Set(ids.filter(Boolean))];
  if (want.length === 0) return new Map();
  const rows = await select<{ id: string; name: string }>("profiles", `id=${inList(want)}&select=id,name`);
  return new Map(rows.map((p) => [p.id, p.name?.trim() || "Someone"]));
}
const nameOf = (m: Map<string, string>, id: string | null | undefined) => (id && m.get(id)) || "Someone";

// ---------- who hears about what ----------

async function plan(ev: DbEvent): Promise<Note[]> {
  const r = ev.record;
  switch (ev.table) {
    case "messages": return ev.type === "INSERT" ? await forMessage(r) : [];
    case "orders": return ev.type === "INSERT" ? await forNewOrder(r) : ev.type === "UPDATE" ? await forOrderStatus(r) : [];
    case "tasks": return ev.type === "UPDATE" ? await forTaskStatus(r, ev.old_record ?? null) : [];   // INSERT: drivers poll open_tasks_near
    case "syncs": return ev.type === "INSERT" ? await forSyncRequest(r) : ev.type === "UPDATE" ? await forSyncAccepted(r, ev.old_record ?? null) : [];
    case "moments": return ev.type === "INSERT" ? await forMoment(r) : [];
    case "post_comments": return ev.type === "INSERT" ? await forComment(r) : [];
    case "post_votes": return ev.type === "INSERT" || ev.type === "UPDATE" ? await forLike(r, ev.old_record ?? null) : [];
    case "moment_views": return ev.type === "INSERT" || ev.type === "UPDATE" ? await forReaction(r, ev.old_record ?? null) : [];
    default: return [];
  }
}

function attachmentText(a: Row | null | undefined): string {
  if (!a) return "Sent a message";
  const mime = String(a.mime ?? "");
  if (mime.startsWith("image/")) return "Sent a photo";
  if (mime.startsWith("video/")) return "Sent a video";
  if (mime.startsWith("audio/")) return "Sent a voice note";
  return a.name ? `Sent a file: ${a.name}` : "Sent a file";
}

async function forMessage(m: Row): Promise<Note[]> {
  if (m.deleted_at) return [];
  const conv = await one("conversations", `id=eq.${m.conversation_id}&select=id,kind,title`);
  if (!conv) return [];
  const members = await select<{ profile_id: string; muted_until: string | null }>("conversation_members", `conversation_id=eq.${m.conversation_id}&select=profile_id,muted_until`);
  const others = members.filter((x) => x.profile_id !== m.sender_id);
  if (others.length === 0) return [];
  // People who blocked the sender never hear from them, even inside a group.
  const blocks = await select<{ blocker_id: string }>("blocks", `blocked_id=eq.${m.sender_id}&blocker_id=${inList(others.map((o) => o.profile_id))}&select=blocker_id`);
  const blocked = new Set(blocks.map((b) => b.blocker_id));
  const now = Date.now();
  const sender = nameOf(await names([m.sender_id]), m.sender_id);
  const body = m.moment_id ? `Replied to your moment: ${m.body || ""}`.trim() : (String(m.body ?? "").trim() || attachmentText(m.attachment));
  const title = conv.kind === "DIRECT" ? sender : `${sender} · ${conv.title || (conv.kind === "GROUP" ? "Group" : "Chat")}`;
  return others
    .filter((x) => !blocked.has(x.profile_id) && !(x.muted_until && Date.parse(x.muted_until) > now))
    .map((x) => ({ to: x.profile_id, key: "messages", type: "messages", title, body, route: `chat/${m.conversation_id}`, tag: `chat-${m.conversation_id}` }));
}

function lineSummary(lines: unknown): { items: string; count: number } {
  const arr = Array.isArray(lines) ? (lines as Row[]) : [];
  const count = arr.reduce((s, l) => s + Number(l.qty ?? 1), 0);
  const shown = arr.slice(0, 3).map((l) => `${l.name ?? "Item"} × ${l.qty ?? 1}`).join(", ");
  return { items: arr.length > 3 ? `${shown} +${arr.length - 3} more` : shown, count };
}

async function forNewOrder(o: Row): Promise<Note[]> {
  const listing = await one("listings", `id=eq.${o.listing_id}&select=id,title`);
  const staff = await select<{ profile_id: string }>("listing_members", `listing_id=eq.${o.listing_id}&role=in.(OWNER,ADMIN)&select=profile_id`);
  if (staff.length === 0) return [];
  const buyer = nameOf(await names([o.buyer_id]), o.buyer_id);
  const { items } = lineSummary(o.lines);
  const mode = o.delivery_mode === "PICKUP" ? "customer will collect" : o.delivery_mode === "STORE_RIDER" ? "delivery by your rider" : "delivery by a Bucks rider";
  const pay = o.payment === "COD" ? ", cash on delivery" : "";
  return staff.map((s) => ({
    to: s.profile_id, key: "orders", type: "orders", urgent: true, tag: `order-${o.id}`,
    title: `New order · ₹${o.subtotal} · ${listing?.title ?? "your shop"}`,
    body: `${buyer}: ${items || "order"} · ${mode}${pay}. Accept within 5 minutes.`,
    route: `orders-for/${o.listing_id}`,
  }));
}

async function forOrderStatus(o: Row): Promise<Note[]> {
  const listing = await one("listings", `id=eq.${o.listing_id}&select=id,title`);
  const shop = listing?.title ?? "The shop";
  const drop = o.drop_label ? ` to ${o.drop_label}` : "";
  const text: Record<string, [string, string]> = {
    ACCEPTED: [`${shop} accepted your order`, o.delivery_mode === "PICKUP" ? "It is being prepared. Collect it from the shop when it is ready." : `It is being prepared. A rider will bring it${drop}.`],
    REJECTED: ["Order not accepted", `${shop} could not take your order this time. You have not been charged.`],
    READY: ["Your order is ready", o.delivery_mode === "PICKUP" ? `Collect it from ${shop}.` : `${shop} has packed it. A rider will pick it up.`],
    PICKED_UP: ["On the way", `The rider has picked up your order from ${shop}.`],
    DELIVERED: ["Delivered", `Your order from ${shop} has arrived. Tell others how it went.`],
    CANCELLED: ["Order cancelled", `Your order from ${shop} was cancelled.`],
  };
  const t = text[String(o.status)];
  if (!t) return [];
  return [{ to: o.buyer_id, key: "my_orders", type: "orders", title: t[0], body: t[1], route: `cloud-order/${o.id}`, tag: `order-${o.id}` }];
}

async function forTaskStatus(t: Row, old: Row | null): Promise<Note[]> {
  const ride = t.type === "RIDE";
  const nm = await names([t.driver_id, old?.driver_id].filter(Boolean) as string[]);
  const driver = nameOf(nm, t.driver_id ?? old?.driver_id);
  const pickup = t.pickup_label || (ride ? "your pick-up point" : "the shop");
  const drop = t.drop_label || "your address";
  // A ride's tap opens nothing: the rider's trip screen is already on top (a cold start restores it through
  // dispatch.resume()), and "home" would push Home, which does not show the rider's trip, over it.
  const route = ride ? "" : `delivery/${t.id}`;
  // The person who booked it hears about their trip; the driver hears about cancellations and payment on Home (DriverTripScreen).
  const note = (title: string, body: string): Note => ({ to: t.requester_id, key: "my_trips", type: "tasks", title, body, route, urgent: true, tag: `task-${t.id}` });
  const toDriver = (to: string, title: string, body: string): Note => ({ to, key: "tasks", type: "tasks", title, body, route: "home", urgent: true, tag: `task-${t.id}` });
  switch (String(t.status)) {
    case "MATCHED":
      return [ride ? note("Rider found", `${driver} is coming to ${pickup}. Share PIN ${t.pin} when they arrive.`) : note("Rider assigned", `${driver} is going to ${pickup} to pick up your order.`)];
    case "ARRIVED":
      return [ride ? note("Your rider is here", `${driver} is at ${pickup}. Share PIN ${t.pin} to start the trip.`) : note("Rider at the shop", `${driver} is collecting your order from ${pickup}.`)];
    case "IN_PROGRESS":
      return ride ? [] : [note("Out for delivery", `${driver} is on the way to ${drop}.`)];
    case "COMPLETED":
      // A delivery's completion also marks the order DELIVERED, which sends its own notification.
      return ride ? [note("Trip complete", `Pay ₹${t.fare} to ${driver} by UPI or cash, then confirm in the app.`)] : [];
    case "SEARCHING":
      if (old && ["MATCHED", "ARRIVED"].includes(String(old.status))) {
        const dropped = nameOf(nm, old.driver_id);
        return [note("Looking for another rider", `${dropped} could not take it. Ringing other riders nearby.`)];
      }
      return [];
    case "CANCELLED":
      // The customer cancelled: tell the driver who was on the way.
      return old?.driver_id ? [toDriver(old.driver_id, ride ? "Trip cancelled" : "Delivery cancelled", "The customer cancelled. Stay online for the next one.")] : [];
    case "PAID":
      return t.driver_id ? [toDriver(t.driver_id, "Payment confirmed", `The customer marked ₹${t.fare} as paid${t.paid_with ? ` by ${String(t.paid_with).toLowerCase()}` : ""}.`)] : [];
    default:
      return [];
  }
}

async function forSyncRequest(s: Row): Promise<Note[]> {
  if (s.status !== "PENDING") return [];
  const who = nameOf(await names([s.requester_id]), s.requester_id);
  return [{ to: s.addressee_id, key: "sync_requests", type: "social", title: `${who} wants to sync`, body: "Open Sync to accept, or just ignore it.", route: "sync", tag: `sync-${s.requester_id}` }];
}

async function forSyncAccepted(s: Row, old: Row | null): Promise<Note[]> {
  if (s.status !== "ACCEPTED" || old?.status === "ACCEPTED") return [];
  const who = nameOf(await names([s.addressee_id]), s.addressee_id);
  return [{ to: s.requester_id, key: "sync_requests", type: "social", title: `${who} synced with you`, body: "You can now message each other and see each other's posts and Moments.", route: "sync", tag: `sync-${s.addressee_id}` }];
}

async function forMoment(m: Row): Promise<Note[]> {
  const a = m.author_id;
  const syncs = await select<{ requester_id: string; addressee_id: string }>("syncs", `status=eq.ACCEPTED&or=(requester_id.eq.${a},addressee_id.eq.${a})&select=requester_id,addressee_id&limit=${MOMENT_FANOUT_CAP}`);
  let people = syncs.map((s) => (s.requester_id === a ? s.addressee_id : s.requester_id));
  if (m.audience === "CLOSE") {
    const close = new Set((await select<{ friend_id: string }>("close_friends", `profile_id=eq.${a}&select=friend_id`)).map((c) => c.friend_id));
    people = people.filter((p) => close.has(p));
  }
  if (people.length === 0) return [];
  const muted = new Set((await select<{ profile_id: string }>("moment_mutes", `muted_id=eq.${a}&profile_id=${inList(people)}&select=profile_id`)).map((x) => x.profile_id));
  const author = nameOf(await names([a]), a);
  const body = String(m.caption ?? "").trim() || (m.media_type === "VIDEO" ? "A new video. It disappears in 24 hours." : "A new photo. It disappears in 24 hours.");
  return people.filter((p) => !muted.has(p)).slice(0, MOMENT_FANOUT_CAP)
    .map((p) => ({ to: p, key: "moments", type: "social", title: `${author} posted a moment`, body, route: `moments/${a}`, tag: `moment-${a}` }));
}

async function forComment(c: Row): Promise<Note[]> {
  const post = await one<{ author_id: string; deleted_at: string | null }>("posts", `id=eq.${c.post_id}&select=author_id,deleted_at`);
  if (!post || post.deleted_at || post.author_id === c.author_id) return [];
  const who = nameOf(await names([c.author_id]), c.author_id);
  return [{ to: post.author_id, key: "comments", type: "social", title: `${who} commented on your post`, body: String(c.body ?? ""), route: `post/${c.post_id}`, tag: `post-${c.post_id}` }];
}

// An up-vote on my post. The database trigger also writes the in-app row and skips repeats within a day.
async function forLike(v: Row, old: Row | null): Promise<Note[]> {
  if (v.vote !== 1 || old?.vote === 1) return [];
  const post = await one<{ author_id: string; body: string; deleted_at: string | null }>("posts", `id=eq.${v.post_id}&select=author_id,body,deleted_at`);
  if (!post || post.deleted_at || post.author_id === v.profile_id) return [];
  const who = nameOf(await names([v.profile_id]), v.profile_id);
  return [{ to: post.author_id, key: "comments", type: "social", title: `${who} recommended your post`, body: String(post.body ?? "").slice(0, 120), route: `post/${v.post_id}`, tag: `like-${v.post_id}-${v.profile_id}` }];
}

// A reaction to my moment (a plain view has no reaction and says nothing).
async function forReaction(v: Row, old: Row | null): Promise<Note[]> {
  const reaction = String(v.reaction ?? "");
  if (!reaction || old?.reaction === reaction) return [];
  const m = await one<{ author_id: string }>("moments", `id=eq.${v.moment_id}&select=author_id`);
  if (!m || m.author_id === v.viewer_id) return [];
  const who = nameOf(await names([v.viewer_id]), v.viewer_id);
  return [{ to: m.author_id, key: "moments", type: "social", title: `${who} reacted ${reaction} to your moment`, body: "Your moment is up for 24 hours.", route: "feed", tag: `reaction-${v.moment_id}-${v.viewer_id}` }];
}

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

async function sendOne(sa: ServiceAccount, bearer: string, token: string, n: Note, quiet: boolean): Promise<SendResult> {
  const message = {
    token,
    android: { priority: quiet ? "normal" : "high", ttl: n.type === "tasks" ? "900s" : "86400s", ...(n.tag ? { collapse_key: n.tag } : {}) },
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

async function deliver(notes: Note[]): Promise<Row> {
  if (notes.length === 0) return { recipients: 0, sent: 0 };
  const people = [...new Set(notes.map((n) => n.to))];
  const settings = new Map((await select<Settings & { profile_id: string }>("user_settings", `profile_id=${inList(people)}&select=profile_id,notify,quiet_hours`)).map((s) => [s.profile_id, s]));
  const wanted = notes.filter((n) => wants(settings.get(n.to), n.key));
  if (wanted.length === 0) return { recipients: people.length, sent: 0, skipped: "everyone turned this off" };
  const tokens = await select<{ token: string; profile_id: string }>("device_tokens", `profile_id=${inList([...new Set(wanted.map((n) => n.to))])}&select=token,profile_id`);
  if (tokens.length === 0) return { recipients: people.length, sent: 0, skipped: "no phones registered" };
  const sa = JSON.parse(FCM_SERVICE_ACCOUNT) as ServiceAccount;
  const bearer = await accessToken(sa);
  const jobs: { token: string; note: Note; quiet: boolean }[] = [];
  for (const n of wanted) {
    const quiet = !n.urgent && inQuietHours(settings.get(n.to));
    for (const t of tokens) if (t.profile_id === n.to) jobs.push({ token: t.token, note: n, quiet });
  }
  let sent = 0, failed = 0;
  const gone: string[] = [];
  for (let i = 0; i < jobs.length; i += BATCH) {
    const results = await Promise.all(jobs.slice(i, i + BATCH).map((j) => sendOne(sa, bearer, j.token, j.note, j.quiet).catch((e) => { console.error(e); return "failed" as SendResult; })));
    results.forEach((res, k) => { if (res === "sent") sent++; else if (res === "gone") gone.push(jobs[i + k].token); else failed++; });
  }
  if (gone.length > 0) await remove("device_tokens", `token=${inList([...new Set(gone)])}`);
  return { recipients: people.length, phones: jobs.length, sent, failed, removed_tokens: gone.length };
}

// ---------- HTTP entry point ----------

function json(body: Row, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
async function webhookSecret(): Promise<string> {
  if (ENV_SECRET) return ENV_SECRET;
  if (dbSecret && dbSecret.until > Date.now()) return dbSecret.value;
  const row = await one<{ value: string }>("push_config", "key=eq.webhook_secret&select=value").catch(() => null);
  dbSecret = { value: row?.value ?? "", until: Date.now() + 300_000 };
  return dbSecret.value;
}
async function sameSecret(given: string | null): Promise<boolean> {
  const SECRET = await webhookSecret();
  if (!SECRET || !given || given.length !== SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < SECRET.length; i++) diff |= SECRET.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST {table, type, record, old_record} with the x-bucks-secret header" }, 405);
  if (!(await sameSecret(req.headers.get("x-bucks-secret")))) return json({ error: "forbidden" }, 403);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing" }, 500);
  if (!FCM_SERVICE_ACCOUNT) return json({ error: "FCM_SERVICE_ACCOUNT secret is not set (see docs/PUSH_SETUP.md)" }, 500);
  let ev: DbEvent;
  try { ev = await req.json(); } catch { return json({ error: "body is not JSON" }, 400); }
  if (!ev || typeof ev.table !== "string" || typeof ev.type !== "string" || !ev.record || typeof ev.record !== "object") return json({ error: "expected {table, type, record}" }, 400);
  try {
    const notes = await plan(ev);
    const result = await deliver(notes);
    return json({ ok: true, table: ev.table, type: ev.type, ...result });
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
