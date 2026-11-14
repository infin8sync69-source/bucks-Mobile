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

Notes (paste as is):

```
Sign in with the phone number and code above. It is a Firebase test number, so no SMS is sent. Choose any date of birth over 18.

Report and Block are in the menu on posts, comments, Moments, messages, chats, pages and people. Account deletion: Account > Settings > Delete account.

Background location is used only while a driver is online with a checked vehicle (the round bucks button on Home > go online). It stops when they go offline.

Rides and shop orders are paid directly between people by UPI or cash, outside the app. Bucks sells nothing in the app.
```

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
