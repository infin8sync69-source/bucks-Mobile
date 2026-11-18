// razorpay-webhook: receives Razorpay webhooks for Bucks provider licences and hands each verified event to the database
// (public.billing_apply_event in supabase/migrations/billing.sql), which decides everything: which licence a Payment Page payment
// renews, by how many months, or that staff must look at it. Nothing in the apps can mark a licence as paid.
//
// Deploy:  supabase functions deploy razorpay-webhook --no-verify-jwt     (Razorpay's signature is the authentication)
// Secret:  RAZORPAY_WEBHOOK_SECRET = the secret typed in Razorpay Dashboard > Account & Settings > Webhooks for this URL.
//          SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
// Razorpay: URL https://<project>.supabase.co/functions/v1/razorpay-webhook, event payment.captured (docs/BILLING_SETUP.md).
//
// Replies 200 once the event is stored (also for a repeat or an event Bucks does not use), 401 for a bad signature, and 500
// when the database could not be reached, so Razorpay retries later. No dependencies: HMAC through WebCrypto.

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const hex = (buf: ArrayBuffer) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

/** Razorpay signs the raw request body with HMAC-SHA256 and the webhook secret, hex encoded, in X-Razorpay-Signature. */
async function signatureOk(rawBody: string, given: string | null): Promise<boolean> {
  if (!WEBHOOK_SECRET || !given) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const want = hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody)));
  const got = given.trim().toLowerCase();
  if (got.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ got.charCodeAt(i);
  return diff === 0;
}

async function rpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!WEBHOOK_SECRET) return json({ error: "RAZORPAY_WEBHOOK_SECRET is not set (see docs/BILLING_SETUP.md)" }, 500);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing" }, 500);

  const raw = await req.text();   // the exact bytes Razorpay signed: read once, before any parsing
  if (!(await signatureOk(raw, req.headers.get("x-razorpay-signature")))) return json({ error: "bad signature" }, 401);

  let event: Record<string, unknown>;
  try { event = JSON.parse(raw); } catch { return json({ error: "body is not JSON" }, 400); }
  if (typeof event?.event !== "string") return json({ error: "not a Razorpay event" }, 400);

  // Razorpay sends the same x-razorpay-event-id on every retry of one event; the database ignores a repeat.
  const eventId = req.headers.get("x-razorpay-event-id") ||
    "sha256:" + hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw)));

  try {
    const result = await rpc("billing_apply_event", { p_event_id: eventId, p_event: event });
    console.log(JSON.stringify({ event: event.event, id: eventId, result }));
    return json({ ok: true, result });
  } catch (e) {
    console.error(e);
    return json({ error: "could not store the event; Razorpay will retry" }, 500);
  }
});
