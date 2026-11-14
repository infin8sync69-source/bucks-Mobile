I can't run an audit from here: this side channel can't read code, query the database or make test requests. Ask for it in the main conversation and it can be done there; it needs tools and should run after the onboarding and translation work, since both change the attack surface. Here's what we already know from this session and what a full audit should cover.

## Already known from this session

**Good:**
- Every table has row-level security, and none of it lets signed-out users read or write anything.
- About 120 server functions run with elevated rights; all of them fix their search path, and none can be called while signed out.
- The Supabase security scan showed nothing critical.
- Phone numbers are stored in a separate private table.
- The demo OTP "1234" works only in debug builds.
- Analytics never uses a user ID or advertising ID.
- The app doesn't allow backups and only its launcher screen is exposed to other apps.
- Driver location jumps are capped (speed limit, movement allowance), and fake-location apps are blocked when booking rides.

**Open risks:**
- **SMS-pumping and bot sign-ups.** App Check is now in the Play build, but it isn't enforced in the Firebase console. The SMS region isn't locked to India, and the test phone numbers haven't been confirmed deleted. Bots can drain your SMS budget and mass-create accounts.
- **Fake recommendations.** The live database still has the pilot settings: 1 recommendation instead of 7, and accounts can recommend on day 0 instead of after 14 days. Someone could farm trust scores with throwaway accounts.
- **No staff reviewer.** Nobody can action reports or approve documents.
- **The 18+ checkbox** is a self-declaration that anyone can tick.
- **The Supabase anon key** is in a public repo and inside the app. That's by design, so all protection rests on the database security rules being correct.
- **About 140 server functions** can be called by any signed-in user. Each one is a place where someone could tamper with input.

## What a full audit should cover
1. **Authentication:** OTP brute-force and resend limits, Firebase token checks in the `claim-role` function, session handling, account takeover by reusing a phone number.
2. **Server functions:** go through all ~140 that signed-in users can call, looking for missing ownership checks, ways to reference other people's data by ID, and unlimited inputs.
3. **Data access rules:** try to read other people's messages, addresses, documents and phone numbers directly through the database API.
4. **File storage:** guessable file paths, file-type tricks, and reading private documents or chat files.
5. **Bots and abuse:**
   - Rate limits on posts, messages, reports, orders and ride requests.
   - Spam that rings drivers with fake ride requests.
   - Fake orders that waste shops' time.
   - Mass reports used to get someone taken down.
6. **Faking things in the app:** fake GPS for rides and recommendations, a modified APK that skips checks the app does locally, and editing prices or fares (fares should be calculated on the server; that needs confirming).
7. **The app itself:** what's exposed to other apps, deep links, notification spoofing, and the WebView if there is one.
8. **Social manipulation:** grooming paths (contacting strangers), pretending to be a business, abusing guardian consent, and how fast reports actually get actioned.
9. **Secrets and supply chain:** dependency vulnerabilities and scanning the repo history for leaked keys.

When you run it in the main conversation, aim it at a test copy of the database, not production, for anything beyond reading.
