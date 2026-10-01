#!/usr/bin/env bash
# Applies the whole Bucks database, schema.sql and every migration, in the one order that is safe. Use this for the first install and for
# every later change; never paste schema.sql (or one migration) into the SQL Editor on a live project: schema.sql drops every policy,
# re-grants full privileges and brings back older versions of functions, and only the migrations after it put things right again.
#
#   DATABASE_URL='postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres' supabase/apply_all.sh
#   supabase/apply_all.sh --print-order      # list the files in the order they would run, connect to nothing
#
# DATABASE_URL must be the direct connection (port 5432) or the session pooler, not the transaction pooler (port 6543), because the whole run
# is one transaction and sets a session setting. If any file fails nothing is changed. The run holds locks on most tables for a few seconds:
# do it when the app is quiet. It never runs supabase/pilot_test_settings.sql (test projects only) and never touches storage files.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Order matters: services.sql before studio.sql (studio replaces listing_service_rules and place_order), the two hardening files last.
files=(
  schema.sql
  migrations/manage.sql
  migrations/owner_read.sql
  migrations/commerce.sql
  migrations/discover.sql
  migrations/jobs.sql
  migrations/dispatch.sql
  migrations/social-extras.sql
  migrations/contact_links.sql
  migrations/services.sql
  migrations/studio.sql
  migrations/push.sql
  migrations/notifications.sql
  migrations/interactions.sql
  migrations/hardening_dispatch.sql
  migrations/hardening_platform.sql
)

case "${1:-}" in
  --print-order|--dry-run|-n)
    i=1; for f in "${files[@]}"; do
      printf '%2d. supabase/%s%s\n' "$i" "$f" "$([ -f "$here/$f" ] || echo '   (missing)')"; i=$((i + 1))
    done
    exit 0 ;;
  -h|--help)
    sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1 (use --print-order or --help)" >&2; exit 2 ;;
esac

missing=0
for f in "${files[@]}"; do [ -f "$here/$f" ] || { echo "missing supabase/$f" >&2; missing=1; }; done
[ "$missing" -eq 0 ] || exit 1
: "${DATABASE_URL:?set DATABASE_URL to the direct or session-pooler connection string}"
command -v psql >/dev/null || { echo "psql is not installed" >&2; exit 1; }

# One transaction, stop at the first error, and lift schema.sql's re-run guard for this session only.
args=(-X -q -v ON_ERROR_STOP=1 --single-transaction -c "set bucks.allow_schema_rerun = 'on'")
for f in "${files[@]}"; do args+=(-f "$here/$f"); done
echo "Applying ${#files[@]} files from $here ..."
psql "$DATABASE_URL" "${args[@]}"
echo "Done. Check the result with: psql \"\$DATABASE_URL\" -X -f supabase/tests/catalog_assertions.sql   and   supabase/launch_checklist.sql"
