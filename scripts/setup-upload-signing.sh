#!/usr/bin/env bash
# One-time setup for Google Play: creates the upload key that android-release.yml signs Play bundles with, stores it as GitHub
# secrets, and prints the certificate Play Console asks for. Google keeps the real app signing key (Play App Signing); this key only
# proves an upload came from you, and Play support can reset it if it is ever lost. Separate from the pilot key on purpose.
#
# Needs: keytool (any JDK; Android Studio ships one) and the GitHub CLI signed in (gh auth login).
# Run once from the repo:  bash scripts/setup-upload-signing.sh
set -euo pipefail
REPO="${REPO:-infin8sync69-source/bucks-Mobile}"
if ! keytool -help >/dev/null 2>&1; then
  echo "Java is not installed (keytool doesn't run). Install it with:  brew install --cask temurin   then run this script again."; exit 1
fi
command -v gh >/dev/null || { echo "GitHub CLI not found. Install it and run: gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "GitHub CLI is not signed in. Run:  gh auth login   then this script again."; exit 1; }
trap 'echo "Stopped at line $LINENO. Paste this output to get help."' ERR
if gh secret list -R "${REPO}" | grep -q '^UPLOAD_KEYSTORE_B64'; then
  echo "UPLOAD_KEYSTORE_B64 already exists on ${REPO}. If Play already knows that key, replacing it means asking Play support for an upload key reset."; exit 1
fi
PASS="$(openssl rand -hex 16)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
keytool -genkeypair -keystore "$TMP/upload.jks" -storetype PKCS12 -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=Bucks upload, O=Bucks, C=IN" >/dev/null
keytool -exportcert -rfc -keystore "$TMP/upload.jks" -alias upload -storepass "$PASS" > "$TMP/upload_certificate.pem"
echo "Saving it as GitHub secrets on ${REPO}..."
base64 < "$TMP/upload.jks" | tr -d '\n' | gh secret set UPLOAD_KEYSTORE_B64 -R "${REPO}"
printf '%s' "$PASS" | gh secret set UPLOAD_KEYSTORE_PASSWORD -R "${REPO}"
BACKUP="$HOME/bucks-upload-signing"; mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
cp "$TMP/upload.jks" "$TMP/upload_certificate.pem" "$BACKUP/"; printf '%s\n' "$PASS" > "$BACKUP/password.txt"; chmod 600 "$BACKUP"/*
echo "Done. Secrets UPLOAD_KEYSTORE_B64 and UPLOAD_KEYSTORE_PASSWORD are set on ${REPO}."
echo "Backup: $BACKUP (keep it safe and private)."
echo "Next: in Play Console create the app (package com.bucks.app), keep Play App Signing on, and when asked for the upload key"
echo "certificate use $BACKUP/upload_certificate.pem. Then run the 'Android release (Play)' workflow and upload the .aab to Internal testing."
echo "Also add this key's SHA-1 to the Firebase Android app (Project settings) so phone sign-in works in Play builds:"
keytool -list -v -keystore "$BACKUP/upload.jks" -alias upload -storepass "$PASS" | grep -E "SHA1:|SHA-1:" || true
echo "and, once Play has created the app signing key, its SHA-1 from Play Console > Setup > App signing as well."
