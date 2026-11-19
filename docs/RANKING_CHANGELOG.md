# Ranking changelog

Every change to how Bucks orders a list (search, suggestions, For you, Explore, people, jobs, the driver ring), newest first. Each
entry says what changed and why, the golden scorecard before and after (`supabase/tests/search_golden_scenarios.sql`), and the field
numbers before and after once logging has data (`discovery_report`). The process is in [DISCOVERY_ALGORITHMS.md §13](DISCOVERY_ALGORITHMS.md).

## 2026-11-19 · "Did they help?" (Android), not yet released

- **What changed:** a day after someone calls, messages, books or gets directions to a page, Home asks whether it helped. The answer
  is the page's normal ↑ or ↓, and, for adults with usage statistics on, a `VOTE` outcome tied to the search it came from.
- **Why:** the trust score has almost no signal (every vote is ↑, most pages have none), and the learning loop had clicks but no
  outcomes.
- **Ranking effect:** none directly. More votes after real contact make the Wilson trust term mean something, and the outcomes are the
  label for fitting weights later (DISCOVERY_ALGORITHMS §13.3).

## 2026-11-19 · Search v1 (`search_quality2.sql`), not yet applied

- **What changed:** `search_listings` keeps its signature but matches whole words only (plurals fold to one key), forgives typos only
  in words of 5 letters or more and only on pages in range, removes filler and modifiers, lets any word match while pages that match
  every meaningful word come first (and alone, when there are some), treats generic words ("shop", "repair", "fresh") as never
  enough, puts shops that ship India-wide after local pages, and orders by trust (a Wilson lower bound) instead of ↑ − ↓. A lexicon of
  about 950 words in English, Hinglish, 5 other languages in Latin letters and 6 scripts replaces the 72 synonyms.
- **Why:** the audit of 2026-11-18 (DISCOVERY_ALGORITHMS §1.3). "taxi" found a USB cable, "milk" a vase 747 km away, "ac repair" a
  carpenter; "tution", "website", "mobile", "laptop", "kaapi", "cheap grocery" and anything in Kannada or Hindi script found nothing.
- **Golden set:** the first baseline is success@3 ≥ 0.95, MRR ≥ 0.90, junk@10 = 0 and every true zero empty. The first Database CI run
  records the exact numbers here.
- **Checked on live data** (temporary objects only, nothing applied): all 15 rows of §1.3 now put the right page first, or return
  nothing where nothing fits. One remains: "cake" still lists a far shop's display stand after the bakery, which the Phase 1 concept
  check removes.
- **Field numbers:** none yet. Logging starts with `discovery_log.sql` and the app builds that send events.
