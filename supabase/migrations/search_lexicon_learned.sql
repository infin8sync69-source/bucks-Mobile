-- Words that people added or reviewed on the live project (search_lexicon rows with source 'staff' or 'mined'), mirrored here every
-- week from lexicon_export(), so that git and the golden set stay the record of what search knows (docs/DISCOVERY_ALGORITHMS.md §13.2).
-- Every word here has a case in supabase/tests/search_golden_scenarios.sql. Safe to run more than once. Apply after search_quality2.sql
-- (supabase/apply_all.sh does). To add the week's words, paste the export into:
--
--   insert into public.search_lexicon (term, means, kind, lang, status, source, reviewed_by, reviewed_at) values
--     <the rows lexicon_export() printed>
--   on conflict (term, means) do nothing;
set search_path = public, extensions;
