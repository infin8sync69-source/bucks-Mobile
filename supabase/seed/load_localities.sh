#!/usr/bin/env bash
# Loads India Post localities (supabase/seed/localities/*.csv: name, district, state, pincode, lat, lng) into public.localities.
# Source: All India Pincode Directory, data.gov.in (Government Open Data License - India; attribution required), cleaned by
# supabase/seed/clean_localities.py (then commas and quotes removed from names, split in 4 files): office suffixes (B.O, S.O...) removed, points outside India or >40 km from their
# pincode's other offices replaced by the pincode's median point, duplicates dropped.
# Usage: DATABASE_URL=postgresql://... supabase/seed/load_localities.sh    (safe to rerun: existing rows are kept)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for f in "$here"/localities/localities-*.csv; do
  psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 \
    -c "create temp table l_in (name text, district text, state text, pincode text, lat double precision, lng double precision)" \
    -c "\\copy l_in from '$f' with (format csv)" \
    -c "insert into public.localities (name, district, state, pincode, lat, lng) select * from l_in on conflict (name, pincode) do nothing"
  echo "loaded $(basename "$f")"
done
psql "$DATABASE_URL" -X -A -t -c "select count(*) || ' localities' from public.localities"
