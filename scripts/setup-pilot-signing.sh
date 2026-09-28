#!/usr/bin/env bash
# One-time setup: creates the signing key every Bucks test build is signed with, and stores it as GitHub secrets.
# Without it each CI build gets a throwaway key, so Android refuses to install a new build over the old one
# (testers must uninstall first, losing their data) and the in-app "Update" button cannot work.
#
# Needs: keytool (any JDK; Android Studio ships one) and the GitHub CLI signed in (gh auth login).
# Run once from the repo:  bash scripts/setup-pilot-signing.sh
# Keep the backup it writes to your home folder: if the key is lost, every tester has to reinstall once more.
set -euo pipefail
REPO="${REPO:-infin8sync69-source/bucks-Mobile}"
# macOS ships a placeholder keytool that only says "Unable to locate a Java Runtime", so check that it really runs.
if ! keytool -help >/dev/null 2>&1; then
  echo "Java is not installed (keytool doesn't run). Install it with:  brew install --cask temurin   then run this script again."; exit 1
fi
command -v gh >/dev/null || { echo "GitHub CLI not found. Install it and run: gh auth login"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "GitHub CLI is not signed in. Run:  gh auth login   (as infin8sync69-source), then this script again."; exit 1; }
trap 'echo "Stopped at line $LINENO. Paste this output to get help."' ERR
echo "Creating the pilot signing key…"
if gh secret list -R "$REPO" | grep -q '^PILOT_KEYSTORE_B64'; then
  echo "PILOT_KEYSTORE_B64 already exists on $REPO. Replacing it would break updates for everyone who installed a pilot build."; exit 1
fi
PASS="$(openssl rand -hex 16)"   # 32 hex characters; openssl ships with macOS and Linux
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
keytool -genkeypair -keystore "$TMP/pilot.jks" -storetype PKCS12 -alias pilot -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=Bucks pilot, O=Bucks, C=IN" >/dev/null
echo "Saving it as GitHub secrets on $REPO…"
base64 < "$TMP/pilot.jks" | tr -d '\n' | gh secret set PILOT_KEYSTORE_B64 -R "$REPO"
printf '%s' "$PASS" | gh secret set PILOT_KEYSTORE_PASSWORD -R "$REPO"
BACKUP="$HOME/bucks-pilot-signing"; mkdir -p "$BACKUP"; chmod 700 "$BACKUP"
cp "$TMP/pilot.jks" "$BACKUP/pilot.jks"; printf '%s\n' "$PASS" > "$BACKUP/password.txt"; chmod 600 "$BACKUP"/*
echo "Done. Secrets PILOT_KEYSTORE_B64 and PILOT_KEYSTORE_PASSWORD are set on $REPO."
echo "Backup: $BACKUP (keep it safe and private)."
echo "Next: push any commit. Testers install that build once (uninstall the old one first); after that, updates install in place."
