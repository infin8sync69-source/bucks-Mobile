# The closed-test demo world

Applied to the live Supabase project on 2026-11-12 for the Play closed test. Full write-up and the ten-round verification:
the "Bucks user-journey verification" document (shared with the owner).

| File | What it does |
|---|---|
| `supabase/seed/demo/catalog.py`, `build_demo.py`, `10_data.sql` | Shops, products and people, and the staging data generated from them |
| `supabase/seed/demo/fetch_images.py`, `pick_images.py`, `chosen.json` | Where each product photo came from (Wikimedia Commons) |
| `supabase/seed/demo/20_apply.sql` | `demo_seed.apply(true)` is a dry run (rolls back), `apply(false)` is the real thing |
| `supabase/seed/demo/99_revert.sql` | Removes every demo shop, gig, person and sync, and restores the launch settings |
| `docs/DEMO_CREDITS.md` | Photo credits (CC BY and CC BY-SA need them) |

Demo rows are found by `profiles.auth_uid like 'demo:%'` and `listings.details->>'demo' = 'true'`. **Run the revert before real users are invited.**
Not installed: `public.demo_autosync()` and its 5-minute schedule (newcomers synced with the demo people); it needs an approved cron job.
