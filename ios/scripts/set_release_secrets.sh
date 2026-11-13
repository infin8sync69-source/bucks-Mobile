#!/usr/bin/env bash
# Sets the GitHub secrets the iOS release workflow needs, from the files Apple and Firebase gave you.
# Nothing is printed except names and checks. Run from anywhere:  ios/scripts/set_release_secrets.sh [folder]
# The folder (default ~/Downloads) must hold AuthKey_<KEYID>.p8 (App Store Connect API key) and GoogleService-Info.plist (Firebase iOS app).
set -euo pipefail
dir="${1:-$HOME/Downloads}"
die() { echo "✗ $*" >&2; exit 1; }

p8="$(ls -t "$dir"/AuthKey_*.p8 2>/dev/null | head -1 || true)"
[ -n "$p8" ] || die "No AuthKey_*.p8 in $dir. Download it from App Store Connect > Users and Access > Integrations > App Store Connect API."
grep -q "BEGIN PRIVATE KEY" "$p8" || die "$p8 is not a .p8 private key."
key_id="$(basename "$p8" .p8)"; key_id="${key_id#AuthKey_}"
[[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] || die "Could not read a 10-character Key ID from the file name $(basename "$p8")."

plist="$(ls -t "$dir"/GoogleService-Info*.plist 2>/dev/null | head -1 || true)"
[ -n "$plist" ] || die "No GoogleService-Info.plist in $dir. Download it from Firebase > Project settings > your iOS app."
grep -q "<string>com.bucksios.app</string>" "$plist" || die "$(basename "$plist") is not for bundle id com.bucksios.app (add the iOS app with that id in Firebase)."
grep -q "REVERSED_CLIENT_ID" "$plist" || die "$(basename "$plist") has no REVERSED_CLIENT_ID (phone sign-in needs it)."

read -r -p "Issuer ID (the long id with dashes at the top of the App Store Connect API page): " issuer
issuer="$(printf '%s' "$issuer" | tr -d '[:space:]')"
[[ "$issuer" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "That does not look like an Issuer ID."

gh secret set APPSTORE_API_KEY_ID --body "$key_id"
gh secret set APPSTORE_API_ISSUER_ID --body "$issuer"
base64 -w0 "$p8" | gh secret set APPSTORE_API_KEY_P8_B64
base64 -w0 "$plist" | gh secret set GOOGLE_SERVICE_INFO_PLIST_B64
echo "✓ All four set (Key ID $key_id, from $(basename "$p8") and $(basename "$plist")). Keep the .p8 somewhere safe; Apple will not give it again."
