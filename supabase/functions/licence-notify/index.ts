// licence-notify: sends the licence SMS the database queues (public.billing_messages, supabase/migrations/billing.sql): the start
// of a free licence, reminders before VALID TILL, the lapse and pause notices, win-back, and the payment receipt. Bucks licences
// are renewed outside the apps (Google Play payments policy), so this SMS carries the plan's Razorpay Payment Page link and the
// licence code; the apps only show the status.
//
// Sends through MSG91's Flow API with DLT-approved templates (one per message kind). Until MSG91_AUTHKEY and MSG91_TEMPLATES are
// set it does nothing and leaves the queue alone; messages older than two days are never sent.
//
// Called by pg_cron every 15 minutes in the daytime through public.billing_flush_sms() with the shared x-bucks-secret header
// (the same push_config.webhook_secret as "notify"), and only when something is waiting.
//
// Deploy:  supabase functions deploy licence-notify --no-verify-jwt
// Secrets: MSG91_AUTHKEY; MSG91_TEMPLATES = JSON {"START":"<flow template id>","RENEW_SOON":"…","LAPSED":"…","PAUSED":"…",
//          "WINBACK":"…","PAID":"…"} (a kind without an id is skipped and retried on later runs); BUCKS_WEBHOOK_SECRET optional
//          (else read from push_config). SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
//          Template variables: ##name## ##subject## ##code## ##date## ##grace_date## ##link## (docs/BILLING_SETUP.md).

interface Msg { id: string; phone: string; template: string; vars: Record<string, string> }

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ENV_SECRET = Deno.env.get("BUCKS_WEBHOOK_SECRET") ?? "";
const AUTHKEY = Deno.env.get("MSG91_AUTHKEY") ?? "";
const MSG91 = (Deno.env.get("MSG91_API_BASE") ?? "https://control.msg91.com/api/v5").replace(/\/$/, "");   // override only for local tests
const PER_RUN = 50;

let templates: Record<string, string> = {};
try { templates = JSON.parse(Deno.env.get("MSG91_TEMPLATES") ?? "{}"); } catch { templates = {}; }

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const rest = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: rest, body: JSON.stringify(args) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${text}`);
  return (text ? JSON.parse(text) : null) as T;
}

let dbSecret: { value: string; until: number } | null = null;
async function webhookSecret(): Promise<string> {
  if (ENV_SECRET) return ENV_SECRET;
  if (dbSecret && dbSecret.until > Date.now()) return dbSecret.value;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/push_config?key=eq.webhook_secret&select=value`, { headers: rest }).catch(() => null);
  const rows = r && r.ok ? await r.json().catch(() => []) : [];
  dbSecret = { value: rows?.[0]?.value ?? "", until: Date.now() + 300_000 };
  return dbSecret.value;
}
async function sameSecret(given: string | null): Promise<boolean> {
  const secret = await webhookSecret();
  if (!secret || !given || given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) diff |= secret.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

/** One SMS through MSG91 Flow. Returns null when sent, else the reason. */
async function send(m: Msg): Promise<string | null> {
  const templateId = templates[m.template];
  if (!templateId) return `no MSG91 template for ${m.template}`;
  if (!/^91\d{10}$/.test(m.phone)) return "bad phone";
  const r = await fetch(`${MSG91}/flow`, {
    method: "POST",
    headers: { authkey: AUTHKEY, "Content-Type": "application/json", accept: "application/json" },
    body: JSON.stringify({ template_id: templateId, short_url: "0", recipients: [{ mobiles: m.phone, ...m.vars }] }),
  }).catch((e) => e as Error);
  if (r instanceof Error) return r.message;
  const text = await r.text();
  if (!r.ok) return `MSG91 ${r.status}: ${text.slice(0, 300)}`;
  try { const body = JSON.parse(text); if (body?.type && body.type !== "success") return `MSG91: ${text.slice(0, 300)}`; } catch { /* plain text reply */ }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST with the x-bucks-secret header" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing" }, 500);
  if (!(await sameSecret(req.headers.get("x-bucks-secret")))) return json({ error: "forbidden" }, 403);
  if (!AUTHKEY || Object.keys(templates).length === 0) return json({ ok: true, sent: 0, note: "SMS not configured (MSG91_AUTHKEY, MSG91_TEMPLATES)" });

  const due = await rpc<Msg[]>("billing_outbox_take", { lim: PER_RUN });
  let sent = 0;
  const failed: string[] = [];
  for (const m of due ?? []) {
    const err = await send(m);
    await rpc("billing_outbox_done", { p_id: m.id, p_ok: err === null, p_error: err });
    if (err === null) sent++; else failed.push(`${m.template}: ${err}`);
  }
  console.log(JSON.stringify({ taken: due?.length ?? 0, sent, failed }));
  return json({ ok: true, sent, failed: failed.length });
});
