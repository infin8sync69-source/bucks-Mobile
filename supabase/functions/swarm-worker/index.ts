// Bucks "swarm-worker": drains the swarm Phase 1 queues (pgmq recovery_q and nudge_q, supabase/migrations/swarm_phase1.sql).
//
// Woken by swarm_kick() (pg_net, right after a message is sent, and once a minute by pg_cron while recovery_enabled = 1) with
// {"drain": true} and the x-bucks-secret header. For each message: read it with a visibility timeout longer than one step, ask the
// database what to do (swarm_step: one transaction that writes the in-app notification and the audit row and returns the pushes),
// send the pushes, then archive the message. A message read more than swarm_dead_after times goes to agent_dead and staff are told.
//
// What it never does: book a ride, place an order, accept, pay or touch SOS. Recovery only *proposes*: the rider or buyer taps a choice
// in the app, which runs today's booking flow with its confirm sheet. The worker holds no RPC that could create a task or an order.
//
// Deploy:  supabase functions deploy swarm-worker --no-verify-jwt        (the shared secret is the authentication)
// Secrets: FCM_SERVICE_ACCOUNT (same as notify); the webhook secret comes from push_config (or BUCKS_WEBHOOK_SECRET).
//          SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
import { deliver, type Note } from "./push.ts";

type Row = Record<string, any>;
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ENV_SECRET = Deno.env.get("BUCKS_WEBHOOK_SECRET") ?? "";
const QUEUES = ["recovery_q", "nudge_q"] as const;
const VISIBILITY_S = 60;          // longer than the worst step (one RPC + a handful of FCM sends)
const PER_QUEUE = 10;             // messages per queue per wake
const DEAD_AFTER_DEFAULT = 5;     // settings.swarm_dead_after
const BUDGET_MS = 20_000;         // stop taking new messages after this; the rest wait for the next kick

const restHeaders = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };
async function rpc<T = any>(fn: string, args: Row): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: restHeaders, body: JSON.stringify(args) });
  if (!r.ok) throw new Error(`${fn}: ${r.status} ${(await r.text()).slice(0, 300)}`);
  const text = await r.text();
  return (text ? JSON.parse(text) : null) as T;
}
async function select<T = Row>(table: string, query: string): Promise<T[]> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${query}`, { headers: restHeaders });
  if (!r.ok) throw new Error(`select ${table}: ${r.status} ${await r.text()}`);
  return await r.json();
}

let dbSecret: { value: string; until: number } | null = null;
async function webhookSecret(): Promise<string> {
  if (ENV_SECRET) return ENV_SECRET;
  if (dbSecret && dbSecret.until > Date.now()) return dbSecret.value;
  const row = (await select<{ value: string }>("push_config", "key=eq.webhook_secret&select=value&limit=1").catch(() => []))[0];
  dbSecret = { value: row?.value ?? "", until: Date.now() + 300_000 };
  return dbSecret.value;
}
async function sameSecret(given: string | null): Promise<boolean> {
  const s = await webhookSecret();
  if (!s || !given || given.length !== s.length) return false;
  let diff = 0;
  for (let i = 0; i < s.length; i++) diff |= s.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}
async function deadAfter(): Promise<number> {
  const row = (await select<{ value: number }>("settings", "key=eq.swarm_dead_after&select=value&limit=1").catch(() => []))[0];
  const n = Number(row?.value);
  return Number.isFinite(n) && n > 0 ? n : DEAD_AFTER_DEFAULT;
}

interface Msg { msg_id: number; read_ct: number; message: Row }
interface Step { notes?: Note[]; skip?: string }

async function drain(): Promise<Row> {
  const started = Date.now();
  const limit = await deadAfter();
  const out: Row = {};
  for (const q of QUEUES) {
    const stats = { read: 0, done: 0, skipped: 0, pushed: 0, dead: 0, retry: 0 };
    out[q] = stats;
    if (Date.now() - started > BUDGET_MS) continue;
    const msgs = (await rpc<Msg[]>("swarm_read", { p_queue: q, p_vt: VISIBILITY_S, p_n: PER_QUEUE })) ?? [];
    for (const m of msgs) {
      stats.read++;
      if (m.read_ct > limit) {
        await rpc("swarm_dead_letter", { p_queue: q, p_msg_id: m.msg_id, p_read_ct: m.read_ct, p_message: m.message, p_error: `read ${m.read_ct} times` });
        stats.dead++;
        continue;
      }
      try {
        const step = (await rpc<Step>("swarm_step", { p_queue: q, p_message: m.message })) ?? {};
        if (step.notes?.length) {
          const r = await deliver(step.notes);
          stats.pushed += Number(r.sent ?? 0);
        } else stats.skipped++;
        await rpc("swarm_archive", { p_queue: q, p_msg_id: m.msg_id });
        stats.done++;
      } catch (e) {
        // Left on the queue: it reappears after the visibility timeout and is retried until read_ct passes the limit.
        console.error(`${q} #${m.msg_id}: ${e}`);
        stats.retry++;
        if (m.read_ct >= limit) {
          await rpc("swarm_dead_letter", { p_queue: q, p_msg_id: m.msg_id, p_read_ct: m.read_ct, p_message: m.message, p_error: String(e).slice(0, 900) })
            .catch((d) => console.error(`dead letter ${q} #${m.msg_id}: ${d}`));
          stats.dead++;
        }
      }
    }
  }
  return out;
}

function json(body: Row, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST {\"drain\": true} with the x-bucks-secret header" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing" }, 500);
  if (!(await sameSecret(req.headers.get("x-bucks-secret")))) return json({ error: "forbidden" }, 403);
  try {
    return json({ ok: true, ...(await drain()) });
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
