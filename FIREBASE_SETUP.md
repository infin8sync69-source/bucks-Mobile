# Firebase setup (ride-hailing pilot)

The app turns on real sign-in and live rides when `app/google-services.json` exists at build time.
Without it, it runs the on-device demo (fake drivers, code 1234 in debug builds only).
Firebase is used for phone sign-in and push notifications only; every record lives in Supabase (`SUPABASE_SETUP.md`).

## 1. Create the project
1. https://console.firebase.google.com → **Add project** → name it `Bucks`.
2. **Upgrade to the Blaze plan** (bottom-left, "Upgrade"). Phone sign-in SMS needs it. Set a budget alert
   (e.g. ₹1,000/month) under Google Cloud → Billing → Budgets.

## 2. Register the Android app
1. Project overview → **Add app** → Android. Package name: `com.bucks.app`.
2. Add the **SHA-1 and SHA-256** fingerprints of the key your builds are signed with. Pilot builds (the ones testers install, from CI) are signed with the **pilot key**
   (alias `pilot`, made by `scripts/setup-pilot-signing.sh`; its backup is `~/bucks-pilot-signing/pilot.jks` with the password beside it, and CI holds it as the
   `PILOT_KEYSTORE_B64` and `PILOT_KEYSTORE_PASSWORD` secrets), **not** the debug key. Print both fingerprints from the pilot keystore:
   ```
   keytool -list -v -keystore ~/bucks-pilot-signing/pilot.jks -alias pilot
   ```
   Copy the `SHA1:` and `SHA256:` lines under "Certificate fingerprints" into Project settings → Your apps → **Add fingerprint** (register both).
   A build made on your own machine without the pilot key uses your local debug key instead: `./gradlew signingReport` prints its fingerprints; add them only if you sign in from such builds.
   Before Play release, also add the fingerprints from Play Console → Test and release → App integrity → App signing.
   Without the right fingerprints, phone sign-in falls back to a browser reCAPTCHA or fails.
3. Download **google-services.json** and put it at `app/google-services.json`.

## 3. Turn on sign-in
1. **Authentication** → Get started → Sign-in method → **Phone** → Enable.
2. Then follow `SUPABASE_SETUP.md` step 2 (Third-party auth and the `claim-role` function), so Supabase accepts the Firebase sign-in.
3. Test phone numbers (optional, for your own testing only): Phone → "Phone numbers for testing" lets a number skip the SMS and use a fixed code, so **anyone who knows the pair signs in as that person**.
   Create your own numbers with a random code that you generate (`LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 6`), keep them in a password manager, never write them in this repository, a document or a chat,
   and **delete every test number before real users are invited**. Give the Play review team their own credentials through Play Console → App content → App access, not through the repo.
   Before launch also work through the Firebase checklist at the top of `supabase/launch_checklist.sql` (SMS region policy, App Check, API key restrictions).

## 4. Build and test with two phones
```
./gradlew assembleDebug
```
- Phone A (driver): sign in → Manage listings → add a vehicle → wait for "verified" → switch it online.
- Phone B (rider, within 5 km of A): sign in → Taxi → pick a destination → choose the **same vehicle type** → Confirm pick-up.
- A rings → Accept → I've arrived → enter B's PIN → End ride. B sees each step, pays, rates.
