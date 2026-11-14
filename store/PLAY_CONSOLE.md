# Play Console: what to enter

Copy-paste answers for every Play Console form, matching the code on `feat/play-social-v1` (9 November 2026).
Items marked **MOCK** are placeholders: replace them after legal review (see the last section).

## Create app

| Field | Value |
|---|---|
| App name | Bucks |
| Default language | English (India), en-IN |
| App or game | App |
| Free or paid | Free |
| Package (set by the first upload) | `com.bucks.app` |

## Store listing (Grow → Store presence → Main store listing)

**App name (30 max):** `bucks: Hyper Local Super App`

**Short description (80 max):**
`Find trusted shops, pros and rides near you, recommended by people you know.`

**Full description:**

```
Bucks is your neighbourhood in one app: the people you know, the shops and professionals around you, and rides when you need to go somewhere.

TRUST YOU CAN SEE
Every shop, professional and driver is ranked by real recommendations from people nearby, not paid ads. Recommendations are given in person by scanning a QR, so they can't be faked. See exactly how something is ranked, and filter to recommendations from people you follow.

FEED AND MOMENTS
Share posts, photos and videos with the people you're synced with, or with your area. Moments disappear after 24 hours.

LOCAL SERVICES AND SHOPS
Order food, groceries and essentials from shops near you. Find a plumber, electrician, tutor or any skill nearby, see their prices and portfolio, and message or book them.

RIDES
Book an auto or cab with a fare worked out up front, a PIN to start your trip and a share-trip option.

CHAT
Direct and group chats with photos and files.

RUN YOUR BUSINESS ON BUCKS
Create a page for your shop, skill or vehicle with Bucks Pro. Take orders, manage your team and riders, and get paid directly by UPI.

SAFE BY DESIGN
Report any post, comment, message or profile. Teen accounts need a parent's consent, are private by default and can't be found by adults they don't know. No ads, no advertising ID, and we never sell your data.
```

**Graphics**

| Asset | File |
|---|---|
| App icon 512×512 | `store/ic_launcher_512.png` |
| Feature graphic 1024×500 | `store/feature_graphic_1024x500.png` |
| Phone screenshots (2–8, 1080×1920 or similar) | Run the **Screenshots** workflow in GitHub Actions, or take them on a phone: Home map, Feed, Services, a shop page, For you, Profile |

**Category:** Social. **Tags:** Social, Local, Shopping.
**Contact email:** infin8sync69@gmail.com. **Website:** https://infin8sync69-source.github.io/bucks-Mobile/legal/

## App content (Policy → App content)

| Form | Answer |
|---|---|
| Privacy policy | https://infin8sync69-source.github.io/bucks-Mobile/legal/privacy |
| App access | Sign-in needed. Give reviewers a Firebase **test phone number** and its fixed code (Firebase console → Authentication → Sign-in method → Phone → Phone numbers for testing). Instructions: "Enter the number, then the code. Choose any date of birth over 18." |
| Ads | No ads |
| Content rating | IARC questionnaire: category **Social / Communication**. Users interact: **Yes**. Users share location: **Yes** (precise during rides and for drivers). Digital purchases: **No**. User-generated content with moderation and reporting: **Yes**. Expect roughly **Teen / 12+** |
| Target audience | **13–15, 16–17, 18+**. Not designed for children under 13. "Appeals to children": No |
| News app | No |
| Data safety | See below |
| Government app | No |
| Financial features | None (payments go directly between UPI apps; Bucks doesn't hold money) |
| Health | No |
| Account deletion | Yes, in app and on the web: https://infin8sync69-source.github.io/bucks-Mobile/legal/delete-account |
| Child safety standards | Standards URL: https://infin8sync69-source.github.io/bucks-Mobile/legal/child-safety. Contact: infin8sync69@gmail.com. In-app reporting: Yes. Complies with child safety laws: Yes |

### Data safety

Encrypted in transit: **Yes**. Users can request deletion: **Yes**. Data shared with third parties: **No** (Firebase, Supabase, Mapbox and the OpenStreetMap and pincode lookup services act as service providers, which Play doesn't count as sharing). Location shown to a driver or customer during a trip is user-initiated transfer, which Play doesn't count as sharing either.

| Data type | Collected | Optional | Purposes |
|---|---|---|---|
| Location → Approximate | Yes | Yes | App functionality |
| Location → Precise | Yes | Yes (rides, deliveries, driver mode) | App functionality, Fraud prevention, security and compliance |
| Personal info → Name | Yes | No | App functionality, Account management |
| Personal info → Phone number | Yes | No | Account management, App functionality (deliveries) |
| Personal info → Address | Yes | Yes | App functionality (deliveries) |
| Personal info → User IDs | Yes | No | App functionality, Account management |
| Personal info → Other (date of birth) | Yes | No | App functionality, Fraud prevention, security and compliance |
| Financial info → Purchase history | Yes | Yes | App functionality |
| Messages → Other in-app messages | Yes | Yes | App functionality |
| Photos and videos | Yes | Yes | App functionality |
| Files and docs (CV, vehicle and business documents) | Yes | Yes | App functionality, Fraud prevention, security and compliance |
| App activity → Other user-generated content | Yes | Yes | App functionality |
| App activity → App interactions | Yes (adults only) | Yes | Analytics |
| App info and performance → Crash logs, Diagnostics | Yes | No | App functionality |
| Device or other IDs (push token) | Yes | No | App functionality |
| Contacts | **Yes**: only the details a person chooses to link to a Bucks profile (the phonebook itself is never uploaded) | Yes | App functionality |
| Financial info → Other financial info (UPI ID / payment QR of drivers and shops) | Yes | Yes | App functionality |

Audio is **not** collected: voice search uses the phone's speech recogniser and Bucks receives only text.

### Sensitive permissions (super-app build)

| Permission | Play Console form | What to enter |
|---|---|---|
| `ACCESS_FINE_LOCATION` | Not a separate form (foreground only; no `ACCESS_BACKGROUND_LOCATION`) | Covered by Data safety → Precise location |
| `FOREGROUND_SERVICE_LOCATION` (`DriverLocationService`) | **App content → Foreground service permissions** | Type: *Location*. Use: "Drivers who go online share their live location so nearby ride and delivery requests can be offered to them and the customer can follow the trip. Runs only while the driver is online, with a persistent notification; stops when they go offline." **Video:** 30–60 s screen recording: Menu → vehicle → Go online → notification appears → accept a request → Go offline → notification disappears. Upload to YouTube as unlisted and paste the link |
| `RECORD_AUDIO` | None (runtime permission, declared in Data safety as not collected) | — |
| `READ_CONTACTS` | None | Data safety: Contacts collected, optional (linked details only) |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Removed from Play builds | — |

## Release (Test and release)

1. Setup → **App signing**: Play App Signing on. Upload key certificate: `~/bucks-upload-signing/upload_certificate.pem`.
2. Then add the **app signing key's SHA-1** (shown on that page) to Firebase → Project settings → Android app `com.bucks.app`, next to the upload key's SHA-1. Phone sign-in fails in Play builds without it.
3. GitHub → Actions → **Android release (Play)** → Run workflow on `feat/play-social-v1` with version `1.0.0`. Download the artifact: `app-release.aab` and `mapping.txt`.
4. **Internal testing** → Create release → upload the `.aab`, then the `mapping.txt` (App bundle explorer → Downloads → ReTrace mapping file).
5. **Closed testing** (personal developer accounts): at least 12 testers opted in for 14 days in a row, then **Apply for production**.
6. **Production**: staged rollout 10% → 50% → 100%.

## Scope

**Decided 9 November 2026: the full super-app ships in 1.0** (social, shops and orders, local services, jobs, rides and driver mode). Before production, confirm with a lawyer: Motor Vehicle Aggregator Guidelines licence for each launch state, Consumer Protection (E-Commerce) Rules 2020 (seller details, grievance officer, refunds), FSSAI for food sellers, GST.

## MOCK details to replace after legal review

Legal review done (14 November 2026). Still open: the company name and address.

| Placeholder | Where |
|---|---|
| Company: **Bucks Technologies Private Limited** | all legal pages |
| Address: **2nd Floor, 12th Main Road, Indiranagar, Bengaluru, Karnataka 560038** | privacy, grievance |
| ✅ Support email: **infin8sync69@gmail.com** (set 14 Nov) | privacy, delete-account, Play contact email, GitHub secret `SUPPORT_EMAIL` |
| ✅ Grievance officer: **Shafeeq Duddiyanda, infin8sync69@gmail.com** (set 14 Nov) | privacy, grievance, GitHub secret `GRIEVANCE_OFFICER` |
| Courts: **Bengaluru** | terms |
| Retention: files 30 days, reports 180 days, ride and order records 8 years (anonymised), email deletion within 7 days | privacy, delete-account. Check the 8-year record rule against `delete_my_account()` before relying on it |

`.example` addresses can't receive mail, so the Help screen's "Email us" button won't reach anyone until the real address is set. Change a secret with `gh secret set SUPPORT_EMAIL`, then remove the draft banner from each page in `docs/legal/`.
