#!/bin/sh
# Writes ios/Config/Secrets.xcconfig from the Android project's local.properties (SUPABASE_URL, SUPABASE_ANON_KEY, and GEMINI_API_KEY /
# MAPBOX_TOKEN / SUPPORT_EMAIL / GRIEVANCE_OFFICER when set) and, when present, the REVERSED_CLIENT_ID in ios/App/GoogleService-Info.plist.
# Nothing is printed: the file is gitignored.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
props="$here/../local.properties"
out="$here/Config/Secrets.xcconfig"
get() { grep -E "^$1=" "$props" 2>/dev/null | head -1 | cut -d= -f2-; }
url="$(get SUPABASE_URL)"; key="$(get SUPABASE_ANON_KEY)"
if [ -z "$url" ] || [ -z "$key" ]; then echo "SUPABASE_URL / SUPABASE_ANON_KEY not found in $props" >&2; exit 1; fi
# xcconfig treats // as a comment, so the scheme's slashes are spelled with $()
url_x="$(printf '%s' "$url" | sed 's#//#/$()/#')"
gem="$(get GEMINI_API_KEY)"
mapbox="$(get MAPBOX_TOKEN)"
# Help's contact details are free text that may hold a link: every slash gets a $() after it, so no // can start a comment.
support="$(get SUPPORT_EMAIL | sed 's#/#/$()#g')"
officer="$(get GRIEVANCE_OFFICER | sed 's#/#/$()#g')"
rev=""
if [ -f "$here/App/GoogleService-Info.plist" ]; then rev="$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$here/App/GoogleService-Info.plist" 2>/dev/null || true)"
  [ -n "$rev" ] || { app_id="$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$here/App/GoogleService-Info.plist" 2>/dev/null || true)"; [ -z "$app_id" ] || rev="app-$(printf '%s' "$app_id" | tr ':' '-')"; }   # encoded app id when the file has no REVERSED_CLIENT_ID
fi
{ echo "SUPABASE_URL = $url_x"; echo "SUPABASE_ANON_KEY = $key"; [ -n "$gem" ] && echo "GEMINI_API_KEY = $gem"; [ -n "$mapbox" ] && echo "MAPBOX_TOKEN = $mapbox"; [ -n "$rev" ] && echo "REVERSED_CLIENT_ID = $rev"
  [ -n "$support" ] && echo "SUPPORT_EMAIL = $support"; [ -n "$officer" ] && echo "GRIEVANCE_OFFICER = $officer"; true; } > "$out"
echo "Wrote $out"
