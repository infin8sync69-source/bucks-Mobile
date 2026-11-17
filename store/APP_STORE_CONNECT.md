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
the block as it is, after you fill in the one `<...>` part, the video. Keep it under 4,000 characters. Attach the screen recording under
App Review Information > Attachment, or link to an unlisted video. Do the steps in "Before resubmitting" below first.

```
1. SCREEN RECORDING
Recorded on an iPhone running the latest iOS: <link, or "attached">. It starts at launch and shows sign-up and sign-in, date of birth and terms, creating a profile, Home, Feed, a shop and an order, a ride, chat, reporting a post and a review, blocking a person, Help, and deleting the account.

2. PURPOSE AND AUDIENCE
Bucks is a local app for neighbourhoods in India. People find nearby shops, professionals (plumbers, tutors, electricians) and auto and cab rides, chosen by recommendations from people they know, not paid ads: a business appears only after people who used it in person recommend it. It also has a local feed, Moments, chat and jobs. It is for people aged 13 and over in India; under-13s are refused and 13 to 17 year olds need a parent's consent in the app. In small towns good businesses and drivers are found by word of mouth; Bucks puts that in one trusted place.

3. SETUP
Sign in with the demo number and code in the Sign-in fields. It is a Firebase test number, so no SMS is sent. Enter a date of birth over 18, accept the terms and create a profile.
The app shows what is near you. This demo account always stands in Whitefield, Bengaluru, wherever you are, so you see our demo shops, professionals, posts and people. Drivers may not be online during review, so a ride request can go unanswered; the video shows a ride.
- Home: map, search, rides. Services: shops and pros by category.
- Report and Block: the "..." menu or a long press on posts, comments, Moments, messages, chats, pages and people; a flag button on reviews and jobs.
- Help: Account > Settings > Help and support (contact email, grievance officer, legal pages).
- Delete account: Account > Settings > Delete account.
- Background location is used only while a driver is online, and stops when they go offline.
There is no paid content, subscription or in-app purchase. Nothing is sold in the app and businesses pay nothing to be listed.

4. EXTERNAL SERVICES
- Supabase: our backend (database, storage, server functions).
- Firebase Authentication: phone sign-in. Firebase Cloud Messaging and APNs: notifications.
- Mapbox: maps, place search, routes. OpenStreetMap, Photon, Nominatim and OSRM as a fallback.
- India Post pincode API: the area from a pincode.
- On the device: MapKit, Speech (voice search), Contacts (read on the phone, not uploaded), Face ID.
- UPI apps and WhatsApp, opened by link to pay or invite. Bucks processes no payments and uses no AI service.

5. REGIONAL DIFFERENCES
Available only in India, and the same everywhere in India. You see shops, pros, drivers and posts within a few kilometres. A service such as Food or Rides opens in an area once enough local providers are there, so some may show as locked.

6. REGULATED SERVICES AND THIRD-PARTY MATERIAL
Bucks is not in a regulated industry such as banking, payments, lending, insurance, health care, gambling or crypto. It holds and moves no money: customers pay shops and drivers directly in cash or with their own UPI app. Bucks employs no drivers and owns no vehicles. Drivers, shops and professionals are independent and hold their own licences; drivers add their driving licence, registration, insurance and permit, and food businesses their FSSAI licence.
Map data: OpenStreetMap and Mapbox, credited on the map. Demo product photos: Wikimedia Commons under Creative Commons, credited at https://infin8sync69-source.github.io/bucks-Mobile/DEMO_CREDITS. Everything else is ours or posted by users.
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

About item 6. Apple asks for documents only from apps in regulated fields (finance, health, gambling and the like). Bucks is not one, and
the answer says so without claiming any certificate. It's all true as of 15 November: no billing tables are on the live database, so
nobody pays. Two things stay with you and your lawyer. India's Motor Vehicle Aggregator Guidelines 2020 may ask a ride platform for a state
licence; that is a question for Indian law, not for App Review. And if provider licences go on sale later (`docs/BILLING_SETUP.md`),
guideline 3.1.3 needs another look first.

## Before resubmitting

1. **Supabase** (done 15 Nov): `supabase/migrations/review_accounts.sql` is on live and holds the reviewers' number. A number is added in
   the SQL editor with
   `insert into public.review_accounts (phone, lat, lng, label, note) values ('+91XXXXXXXXXX', 13.003, 77.745, 'Whitefield, Bengaluru', 'App Review');`
   and then stands in Whitefield (14 live demo listings) wherever it signs in. Use a made-up number that no Bucks account has: a real one
   would move that person's account too.
2. **Firebase** (done 15 Nov): the same number is under Authentication > Sign-in method > Phone > Phone numbers for testing, with its code.
   Put both in the Sign-in fields above.
3. **Build**: submit **1.0.9 (build 12)** (`docs/RELEASES.md`). It has the reviewer position, registers for push at launch, and sends one
   code request at a time (earlier builds could send two SMS and two robot pages). Phone sign-in is checked by a silent push only while
   Firebase holds an APNs key whose environment is **Sandbox & Production**: the first key was Sandbox-only, so every TestFlight build fell
   back to the "I'm not a robot" page until it was replaced on 16 Nov.
4. **Check it on your iPhone** from TestFlight: sign in with a real number (checked 17 Nov on 1.0.9: one SMS, no robot page), then sign
   in with the reviewers' number and see Whitefield shops on Home.
5. **Record the video** (above), fill in item 1, choose build 1.0.9 (12) on the version page, and reply in App Store Connect with **Submit**.

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
