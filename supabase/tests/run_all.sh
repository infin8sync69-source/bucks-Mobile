#!/usr/bin/env bash
# Builds a throw-away database with the whole stack (local_auth_shim.sql + apply_all.sh), then runs catalog_assertions.sql and every
# scenario suite in its own copy. Exits non-zero if anything prints FAIL or raises an ERROR. Used by .github/workflows/database-ci.yml;
# run it locally the same way (PostgreSQL 15+ with PostGIS; connection from the usual PG* environment variables):
#
#   supabase/tests/run_all.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
db="bucks_ci_$$"
cleanup() { dropdb --if-exists "$db" >/dev/null 2>&1; }
trap cleanup EXIT

createdb "$db" || exit 1
psql -d "$db" -X -q -v ON_ERROR_STOP=1 -f "$here/local_auth_shim.sql" >/dev/null || exit 1
if ! out="$(DATABASE_URL="postgresql:///$db" "$here/../apply_all.sh" 2>&1)"; then
  grep -v NOTICE <<<"$out"; echo "::error::apply_all.sh failed"; exit 1
fi
grep -v NOTICE <<<"$out"

failed=0
report() {   # name, output
  local n="$1" out="$2" ok bad
  ok=$(grep -cE '(^|[[:space:]])ok\b' <<<"$out"); bad=$(grep -cE 'FAIL|ERROR' <<<"$out")
  printf '%-36s ok=%-4s fail=%s\n' "$n" "$ok" "$bad"
  if [ "$bad" -ne 0 ]; then failed=1; grep -E 'FAIL|ERROR' <<<"$out" | head -20 | sed "s/^/::error::$n: /"; fi
}

report catalog_assertions "$(psql -d "$db" -X -q -f "$here/catalog_assertions.sql" 2>&1)"
for t in "$here"/*scenarios.sql; do
  n="$(basename "$t" .sql)"; copy="${db}_s"
  dropdb --if-exists "$copy" >/dev/null 2>&1; createdb -T "$db" "$copy" || exit 1
  report "$n" "$(psql -d "$copy" -X -q -f "$t" 2>&1)"
  dropdb "$copy"
done
exit "$failed"
