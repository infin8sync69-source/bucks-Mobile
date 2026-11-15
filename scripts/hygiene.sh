#!/usr/bin/env bash
# Code hygiene gate for both apps, run by .github/workflows/hygiene.yml and by hand: scripts/hygiene.sh
# It fails on things that must never ship: leftover debug output, unfinished-work markers, merge-conflict markers, crash-on-purpose
# calls in app code, private keys, and large binaries outside the seed data. Each rule prints the offending lines.
set -uo pipefail
cd "$(dirname "$0")/.."
KT=app/src/main/java
SW="ios/Sources/BucksCore ios/Sources/BucksUI ios/App"
fail=0
rule() {  # rule "<what>" <grep args...>
  local what="$1"; shift
  local out; out="$(grep -rnE "$@" 2>/dev/null || true)"
  if [ -n "$out" ]; then echo "✗ $what"; echo "$out" | cut -c1-200 | head -20; fail=1; else echo "✓ $what"; fi
}
rule "No TODO / FIXME / HACK / XXX markers in app code" '\b(TODO|FIXME|HACK|XXX)\b' $KT $SW
rule "No debug output on Android (println, Log.d, Log.v, printStackTrace)" 'println\(|Log\.[dv]\(|printStackTrace\(' $KT
rule "No debug output on iOS (print, NSLog, debugPrint, dump)" '(^|[^A-Za-z_.])(print|NSLog|debugPrint|dump)\(' $SW
rule "No fatalError / preconditionFailure in iOS app code" 'fatalError\(|preconditionFailure\(' $SW
rule "No merge-conflict markers" '^(<<<<<<<|>>>>>>>) ' app ios supabase docs scripts .github
rule "No private keys or live payment keys in the repo" -e '^-----BEGIN [A-Z ]*PRIVATE KEY-----$|sk_live_[A-Za-z0-9]|rzp_live_[A-Za-z0-9]' app ios supabase scripts .github docs
rule "No Supabase service-role key in app code" 'service_role' $KT $SW
# iOS must make every backend call Android makes, or say why not in docs/PARITY.md ("Backend calls only Android makes").
a="$(grep -rhoE 'rpc\("[a-z_0-9]+"' $KT | sed 's/rpc("//;s/"//' | sort -u)"
i="$(grep -rhoE 'rpc(List|Void)?\("[a-z_0-9]+"' $SW | sed -E 's/rpc(List|Void)?\("//;s/"//' | sort -u)"
missing=""
for r in $(comm -23 <(echo "$a") <(echo "$i")); do grep -q "\`$r\`" docs/PARITY.md || missing="$missing $r"; done
if [ -n "$missing" ]; then echo "✗ Backend calls Android makes that iOS doesn't, and docs/PARITY.md doesn't list:$missing"; fail=1; else echo "✓ Every Android-only backend call is listed in docs/PARITY.md"; fi
big="$(git ls-files -z | xargs -0 du -k 2>/dev/null | awk '$1 > 1024' | grep -v 'supabase/seed/' || true)"
if [ -n "$big" ]; then echo "✗ Files over 1 MB outside supabase/seed"; echo "$big"; fail=1; else echo "✓ No files over 1 MB outside the seed data"; fi
exit $fail
