# App Store Connect: what to enter

Copy-paste answers for App Store Connect, matching the iOS app on `feat/play-social-v1` (14 November 2026). The Play Console answers
are in `store/PLAY_CONSOLE.md`; both stores use the same name and description. Builds come from CI (`docs/RELEASES.md`).

## App information

| Field | Value |
|---|---|
| Name (30 max) | `bucks: Hyper Local Super App` (the Play name) |
| Subtitle (30 max) | `Trusted shops, pros and rides` |
| Bundle ID | `com.bucksios.app` |
| SKU | `bucks-ios` (any unique text) |
| Primary category | Social Networking. Secondary: Shopping |
| Content rights | Contains third-party content (people's posts, map data): Yes, and you have the rights to it |
| Age rating | User-generated content: yes. Messaging and chat: yes. Advertising, gambling, contests, unrestricted web access: no. Every content descriptor (violence, sexual content, profanity, drugs, horror, medical): none. Aim for 13+; the app itself refuses under-13s and asks a guardian's consent for 13 to 17 |
| Encryption | Nothing to answer: `ITSAppUsesNonExemptEncryption` is false in the app |

## Pricing and availability

Free. Availability: India.

## The version page (1.0.x)

| Field | Value |
|---|---|
| Promotional text (170 max) | `Your neighbourhood in one app: shops, pros and rides near you, ranked by recommendations from people you know. No ads.` |
| Description | The full description in `store/PLAY_CONSOLE.md`, unchanged |
| Keywords (100 max) | `nearby,shops,rides,auto,cab,food,grocery,plumber,services,jobs,chat,neighbourhood,recommend` |
| Support URL | https://infin8sync69-source.github.io/bucks-Mobile/legal/grievance (it has the contact email) |
| Marketing URL | Leave empty |
| Copyright | `2026 Shafeeq Duddiyanda` |
| Screenshots | iPhone 6.9-inch display, portrait, 3 to 10 images (1290 × 2796 or 1320 × 2868). Home map, Feed, Services, a shop page, Explore, Profile. Take them on an iPhone Pro Max from TestFlight, or in the Simulator. iPad: none, the app is iPhone only |
| Build | The 1.0.x build from TestFlight with the same version as the Android release |
| Version release | Manually release this version, so both stores go public on the same day |

## App Review information

| Field | Value |
|---|---|
| Sign-in required | Yes |
| User name | The Firebase test phone number kept for reviewers (Firebase > Authentication > Sign-in method > Phone > Phone numbers for testing) |
| Password | That number's fixed code |
| Contact | Your name, phone and email |

Notes. Version 1.0.4 was rejected under guideline 2.1 (Information Needed, 15 November 2026). Apple asked for the six items below. Paste
the block as it is, after you fill in the two `<...>` parts: the video link and your answer to item 6. Keep it under 4,000 characters.
Attach the screen recording under App Review Information > Attachment, or link to an unlisted video.

```
1. SCREEN RECORDING
Recorded on an iPhone running the latest iOS: <link, or "attached">. It starts at app launch and shows: sign-up and sign-in with a phone number, the date of birth and terms, creating a profile, Home, Feed, a shop page and an order, booking a ride, chat, reporting a post and a review, blocking a person, Help and support, and deleting the account.

2. PURPOSE AND AUDIENCE
Bucks is a local app for neighbourhoods in India. It helps people find nearby shops, service professionals (plumbers, tutors, electricians) and auto and cab rides, and choose them by recommendations from people they know, not paid ads. A business appears only after people who have used it in person recommend it. Bucks also has a local feed, Moments, chat and local jobs. It is for adults and teenagers aged 13 and over in India. Under-13s are refused, and 13 to 17 year olds need a parent's or guardian's consent in the app. It solves a real problem: in small towns, good local businesses and drivers are found by word of mouth, which Bucks puts in one trusted place.

3. HOW TO SET UP AND USE THE APP
Sign in with the demo phone number and code in the Sign-in fields. It is a Firebase test number, so no SMS is sent. Enter any date of birth over 18, accept the terms, and create a profile.
The app shows what is near your location. Our demo shops, drivers and people are in Whitefield, Bengaluru, India. <how a reviewer outside India sees them>
- Home: map, search and rides. Services: shops and pros by category.
- Feed: posts. Long-press or the "..." menu on a post, comment, Moment, message, chat, page or person opens Report and Block. A page's Reviews tab and a job have a flag button to report them.
- Account > Settings > Help and support: contact email, grievance officer and legal pages.
- Account deletion: Account > Settings > Delete account. It deletes the account and its data. Signing in again with the demo number creates a new, empty account.
There is no paid content and nothing to buy in the app.

4. EXTERNAL SERVICES
- Supabase: database, storage and server functions (our backend).
- Firebase Authentication (Google): phone number sign-in. Firebase Cloud Messaging and Apple Push Notification service: notifications.
- Mapbox: maps, place search and routes. OpenStreetMap tiles, Photon (Komoot), Nominatim and OSRM: the fallback when Mapbox is unavailable.
- India Post pincode API (api.postalpincode.in): fills in the area from a pincode.
- Apple frameworks on the device: MapKit, Speech (voice search, turned into text on the phone), Contacts (read on the phone, the phonebook isn't uploaded), Face ID.
- UPI apps and WhatsApp: opened by link, to pay or to invite someone. Bucks does not process payments, and it has no AI service in the release build.

5. REGIONAL DIFFERENCES
The app is available only in India. It works the same everywhere in India. What you see depends on your location: shops, pros, drivers and local posts within a few kilometres. Services such as Food and Rides open in an area only once enough checked local providers are there, so some may show as locked.

6. REGULATED SERVICES
<your answer>
```

How to record the video (item 1). Use a physical iPhone on the latest iOS, with Settings > Control Centre > Screen Recording. Record in India,
near the demo world, so the screens show content. Use a spare Firebase test number, not the reviewers' one, because the recording ends by
deleting the account. Show, in this order:

1. Launch from the home screen: splash, Log in, phone number, code, date of birth, terms, create profile (name, area).
2. Home map, Services, and a shop page with its products and Reviews tab.
3. Put something in the cart and place a cash or UPI order. No money moves in the app.
4. Book a ride from Home: destination, vehicle, request, then cancel.
5. Feed: a post, a comment, a Moment. Open chat and send a message.
6. Report: the "..." menu on a post > Report > pick a reason > send. Then the flag on a review, and the flag on a job.
7. Block: a person's profile > "..." > Block. Show that their content is gone.
8. Account > Settings > Help and support: the email and grievance officer.
9. Account > Settings > Delete account > Delete. End on the logged-out screen.

Items 3 and 6 of the notes need your decision. Item 3 depends on how a reviewer outside India will see content (see below). Item 6 is a
legal answer: Bucks lists rides and shops, drivers upload their own licence and vehicle papers, and payment goes from person to person.
Whether you need a ride-aggregator licence or anything else in India is for you and your lawyer to answer. If you need none, say why in
plain words.

**Location risk.** Apple reviews from outside India (usually the US). Home, Services and the nearby lists use the phone's real position
(`Session.here`). The demo world is in Bengaluru, Kodagu and Kanyakumari. A reviewer in Cupertino will probably see an empty map and
locked services, and that leads to a rejection under 2.1 (app incomplete). The notes cannot fix this alone. Either the reviewers' account
sees the demo world from anywhere, or the recording and notes must carry the review.

## App Privacy

Tracking: No. Privacy policy URL: https://infin8sync69-source.github.io/bucks-Mobile/legal/privacy

Every type below is **linked to the person**, **not used for tracking**, and used for **App Functionality** only. It matches
`ios/App/PrivacyInfo.xcprivacy` once the iOS App Store fixes land (they add Contacts and date of birth to it and correct the contacts
prompt). Submit a build that has them.

| Category | Data type | What it is in Bucks |
|---|---|---|
| Contact Info | Name | Profile name |
| Contact Info | Phone Number | Sign-in number |
| Contact Info | Physical Address | Delivery addresses |
| Location | Precise Location | Pick-up and drop, drivers while online |
| Contacts | Contacts | Only the details a person links to a Bucks profile (the phonebook is never uploaded) |
| User Content | Emails or Text Messages | In-app messages |
| User Content | Photos or Videos | Posts, Moments, messages, documents |
| User Content | Other User Content | Posts, comments, reviews, vehicle and business documents |
| Identifiers | User ID | Bucks ID |
| Purchases | Purchase History | Orders |
| Financial Info | Payment Info | UPI ID or payment QR of drivers and shops |
| Other Data | Other Data Types | Date of birth |

Not collected by the iOS app: health, browsing history, search history (searches aren't stored), sensitive info, audio (voice is turned into
text on the phone), usage data and diagnostics (the iOS app has no analytics or crash reporting yet). If Crashlytics is added to iOS,
add Diagnostics > Crash Data here in the same release.

## Submitting

1. Add the build to the version, fill the fields above, then **Add for Review** > **Submit**.
2. Review usually takes a day or two. Questions come in App Store Connect > App Review; answer there.
3. After approval, release it on the day the Android production rollout starts.
