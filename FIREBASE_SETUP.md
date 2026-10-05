# Firebase setup (ride-hailing pilot)

The app turns on real sign-in and live rides when `app/google-services.json` exists at build time.
Without it, it runs the on-device demo (fake drivers, code 1234 in debug builds only).

## 1. Create the project
1. https://console.firebase.google.com → **Add project** → name it `Bucks`.
2. **Upgrade to the Blaze plan** (bottom-left, "Upgrade"). Phone sign-in SMS needs it. Set a budget alert
   (e.g. ₹1,000/month) under Google Cloud → Billing → Budgets.

## 2. Register the Android app
1. Project overview → **Add app** → Android. Package name: `com.bucks.app`.
2. Add the **SHA-1 and SHA-256** fingerprints. On the Mac, in the project folder:
   `./gradlew signingReport` → copy SHA1 and SHA-256 from the `debug` variant.
   Before Play release, also add the fingerprints from Play Console → Test and release → App integrity → App signing.
   Without these, phone sign-in falls back to a browser reCAPTCHA or fails.
3. Download **google-services.json** and put it at `app/google-services.json`.

## 3. Turn on the services
1. **Authentication** → Get started → Sign-in method → **Phone** → Enable.
   Under "Phone numbers for testing" add e.g. `+91 99999 00001` / code `123456` (and a second one).
   Test numbers don't send SMS: use them for your own testing and give one to the Play review team.
2. **Firestore Database** → Create database → **Production mode** → location **asia-south1 (Mumbai)**.
3. Firestore → **Rules** → paste the contents of `firestore.rules` → **Publish**.

## 4. Build and test with two phones
```
./gradlew assembleDebug
```
- Phone A (driver): sign in → Manage listings → add a vehicle → wait for "verified" → switch it online.
- Phone B (rider, within 5 km of A): sign in → Taxi → pick a destination → choose the **same vehicle type** → Confirm pick-up.
- A rings → Accept → I've arrived → enter B's PIN → End ride. B sees each step, pays, rates.
