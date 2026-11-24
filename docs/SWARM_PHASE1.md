# Swarm Phase 1: signals and recovery

Phase 1 of the swarm design (`docs/ai/reports/Swarm intelligence for Bucks.md`, table "Phases open only when measured density says
so"). Postgres is the blackboard; agents leave decaying marks; **no agent books, pays, accepts a ride or touches SOS**. Phase 0
(`swarm_core.sql`: offer log, `dispatch_mode_for` = BROADCAST) is live since 2026-11-19. Phase 2 waves and Phase 3 batching stay off:
Kodagu is too sparse.

## Status

| Piece | Where | State |
|---|---|---|
| Migration `swarm_phase1.sql` | `supabase/migrations/`, in `apply_all.sh` after `swarm_core.sql` | Built; Database CI green (`swarm_phase1_scenarios` 54 ok, 0 fail); dry-run on prod in a rolled-back transaction 2026-11-24 (pgmq 1.5.1 installed, both queues, send / read / archive / dead-letter, rollup, cron jobs: all OK, nothing kept). **Applied to prod 2026-11-24** (owner's go-ahead): pgmq 1.5.1, `recovery_q` and `nudge_q`, 9 tables, 8 triggers, 3 cron jobs; every switch 0. |
| `swarm-worker` Edge Function | `supabase/functions/swarm-worker/` | **Deployed to prod 2026-11-24** (v1, `verify_jwt` off, shared-secret auth). Checked: no secret gives 403; an authenticated drain sent from the database gives 200 and reads both queues. |
| Apps (Android + iOS) | see `docs/PARITY.md` | Built; ships with the next app release |
| `notify` | unchanged | Phase 1 needs no notify change. Do not redeploy notify from this branch. |

## What it adds (every switch defaults to 0)

| Switch in `settings` | Turns on |
|---|---|
| `demand_field_enabled` | A3: `area_signals` decayed counters (REQUEST, UNFILLED, COMPLETED, INTEREST, SUPPLY_ONLINE) per area cell, written by triggers on `tasks`, `service_interest`, `driver_presence`; read by `recent_requests_near` (the driver card) and `area_heat` |
| `recovery_enabled` | A4: enqueueing to `recovery_q` / `nudge_q`, the worker's pushes, "Notify me when a driver is online" |
| `intent_feedback_enabled` | inserts into `intent_feedback` (also needs the person's opt-in, `set_intent_feedback_optin`) |

Always on (measurement only, like Phase 0's offer log): a `recovery_offers` row when a ride ends NO_DRIVER or a shop turns an order
down, the person's taps (`recovery_choice`), follow-up attribution, and the nightly `swarm_metrics_daily` rollup.

Privacy rules: area cells only (never coordinates or user ids) in `area_signals`; nothing shown for a cell under `signal_k_min` (3)
events in 7 days; only known adults feed the field and the metrics (DPDP s.9(3)); `intent_feedback` is opt-in, adults only, redacted
(`redact_pii`: phones, UPI ids, long numbers, 4-6 digit PINs), rate-limited by `rate_hit('intent_feedback')`, insert-only for members.

## Turning it on (each step needs the owner's go-ahead)

1. ~~Apply `swarm_phase1.sql`~~ (done 2026-11-24). With all switches 0 it changes no behaviour; it only records recovery offers and
   writes the nightly rollup.
2. ~~Deploy `swarm-worker`~~ (done 2026-11-24): `supabase functions deploy swarm-worker --no-verify-jwt` (uses the `FCM_SERVICE_ACCOUNT` secret and
   `push_config.webhook_secret`, like notify).
3. `update settings set value = 1 where key = 'demand_field_enabled';` then, once the worker is deployed, `recovery_enabled`.

Off again: set the switch to 0. Queued messages are skipped (`swarm_step` answers `recovery_enabled is 0`).

## Exit criteria to watch

```sql
-- Recovery conversion and unfilled rate per zone (area cell), last 14 days
select zone, service, sum(requests) req, sum(unfilled) unfilled, round(sum(unfilled)::numeric / nullif(sum(requests), 0), 3) unfilled_rate,
       sum(recovery_shown) shown, sum(recovery_tapped) tapped, sum(recovery_converted) converted,
       round(sum(recovery_converted)::numeric / nullif(sum(recovery_shown), 0), 3) conversion
  from swarm_metrics_daily where day > current_date - 14 group by 1, 2 order by req desc;

-- Zero recovery actions without a user tap: the worker has no RPC that creates a task or an order, so every follow-up must have a tap.
select count(*) as followups_without_tap from recovery_offers where followup_id is not null and chosen_at is null;   -- must be 0
-- Manual rebooks that ignored the card (not a violation; tells whether the card is noticed)
select sum(recovery_untapped_followups) from swarm_metrics_daily where day > current_date - 14;
-- Dead letters (alert on any)
select * from agent_dead order by created_at desc limit 20;
```

## Not in Phase 1

The driver hand-back trigger for A4 (notify already re-rings), the A5 demand-tips nudger (`nudger_enabled`, Phase 3), `ai_drafts`
for orders (Ask Bucks is on hold), separate `swarm-recovery` secret keys (the worker uses the service role for now), app UI for
`intent_feedback` (arrives with the on-device Tier 1 model).
