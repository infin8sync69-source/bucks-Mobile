// trip: the live trip a Bucks rider or driver shared (trusted contacts, SOS). Anyone with the link's token can read that one trip:
// who is driving, the vehicle and plate, pickup and drop, and the driver's position while the trip is on. Nothing else.
// The page is docs/trip/index.html (GitHub Pages); the token travels in the URL fragment, so it never reaches GitHub's logs.
//
// Deploy:  supabase functions deploy trip --no-verify-jwt      (the unguessable token is the authorisation; see trip_safety.sql)
// Secrets: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Allow-Headers": "content-type" };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "GET") return json({ error: "GET ?t=<token>" }, 405);
  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (!/^[A-Za-z0-9_-]{20,40}$/.test(token)) return json({ error: "this link is not valid" }, 404);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "not configured" }, 500);
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/trip_share_view`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_token: token }),
  });
  if (!r.ok) { console.error(`trip_share_view: ${r.status} ${await r.text()}`); return json({ error: "try again in a moment" }, 502); }
  const trip = await r.json();
  if (!trip) return json({ error: "this link has expired" }, 404);
  return json(trip);
});
