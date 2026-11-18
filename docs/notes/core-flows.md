# Bucks: core feature flows

These flows are based on the code reviewed and the audits run in this session, on the `feat/play-social-v1` branch for Android. Each step names the screen and what the person does. Items marked ⚠️ are known gaps from the audit. Items marked 🆕 were built in this session.

## 0. Getting started (everyone)

1. **Open the app.** Tap the purple splash screen.
2. **Sign in with your phone.** Enter your 10-digit number (+91 is fixed), tap Send, then enter the 6-digit OTP. It may fill in automatically.
3. **Date of birth.** This is required.
   - Under 18: a parent or guardian's name and phone, the relation (Parent is preselected), and a consent checkbox.
   - Under 13: refused for now.
4. **Create your profile.** Your name, then your area (filled in from your location), then an optional bio and interests.
5. **Allow location and notifications** when asked.
6. **Home:** a map with the search bar "Where to, or what do you need?".
   - The bottom bar is **Home · Feed · Services · For you · Profile**.
   - The ☰ menu holds Bucks Pro: Pro profile, pages, vehicles, invites, orders, jobs, Find people, Settings, Help, App versions.

⚠️ Two different progress bars appear (age "1/3", then profile "1/3"). Email sign-up isn't available in the live build.

## 1. Booking a taxi (rider)

1. Home → search bar → choose a **destination** from the suggestions, or pick it on the map.
2. **Choose a ride:** Auto or Cab, with the fare worked out by the server. Bikes never carry passengers.
3. **Confirm pickup:** drag the pin to the exact spot.
4. **Searching:** nearby drivers are rung. Cancel is free and needs no reason.
5. **Driver found:** you see the driver's name, vehicle, plate and your **4-digit PIN**, and can call or message them.
   - Cancelling now needs a reason, e.g. "Taking too long" or "Plans changed".
6. **Driver arrives:** give them the PIN to start the trip.
7. **In ride:** a live map and a Share trip option.
8. **Pay** by UPI or cash, then confirm in the app.
9. **Rate:** ↑ Recommend or ↓ Not recommended. A ↓ needs a reason; a comment is optional.

## 2. Driving (auto, cab or bike owner)

1. ☰ → Bucks Pro → **Create → Vehicle**. Choose the type, enter the plate, and upload the RC, insurance and licence (plus a permit for autos and cabs).
2. **Wait for approval.** 🆕 Bucks staff review it under *Review documents and vehicles*, and you get a notification when it's approved or sent back.
3. **Go online** from the ☰ switch or Home's online button.
   - **Bikes take deliveries only** (pickup and drop).
   - Autos and cabs take passenger rides.
4. **A request rings:** Accept within the ring window.
5. **Go to the pickup** → *Arrived* → **enter the customer's PIN** → trip in progress.
6. **End the trip** at the drop point → collect payment (your UPI QR is shown) → rate the customer.
7. **Handing a trip back** before the PIN is entered needs a reason. The limit is 3 per hour.

⚠️ Auto and cab copy still promises "deliveries", but only bikes get them.

## 3. Quick commerce: local shops and food (buyer)

1. Find a shop in one of these ways:
   - Home search, e.g. "biryani" or "milk"
   - the **Services** tab → a tile (Food, Grocery, Vegetables, Meat, Shopping)
   - **For you**
2. **Open the shop page.** It opens on its catalogue: products with photo, price and stock.
3. **Add** items. Items with options open *Choose*, with the first in-stock option preselected. You can add from several shops; each becomes its own order.
4. **View cart → checkout:**
   - **Delivery:** a Bucks rider (default), the shop's own rider (when the shop has riders), or Pickup.
   - **Payment:** UPI (default). Cash on delivery only works with the shop's own riders.
   - **Deliver to:** your current location plus a label.
5. **Place order.** The shop has 5 minutes to accept. You can cancel while it's waiting.
6. **Order page:** a timeline (Accepted → Packed → Picked up → Delivered) and *Track delivery* on a map.
7. **Rate** the order with ↑/↓ after delivery.

⚠️
- The delivery fee isn't in the "Place order ₹X" total.
- The cart is lost if the app closes.
- Payment method and delivery mode aren't remembered.
- A saved address can't be used as the drop point for local delivery.

## 4. Running a shop (seller)

1. ☰ → **Create → Business → shop type** → name, category and delivery radius (3 km preselected).
   - 🆕 Categories other than food no longer default to Food, so non-food shops aren't asked for an FSSAI licence.
2. **Dashboard:** follow the go-live checklist ("N of M done"):
   - photos
   - products (price, MRP, stock, up to 8 photos)
   - required documents
   - UPI QR
   - recommendations from people nearby
3. **Add store riders:** Team → invite by Bucks ID → role *Store rider* → they accept under Invites.
4. **An order comes in:** a push notification plus a ring on *Orders*.
   - 🆕 **"Accept · auto rider"** (one tap): Bucks rings your riders for cash orders, or nearby Bucks bikes otherwise.
   - 🆕 **"Accept and choose my rider":** pick one (online status shown, last rider preselected). They get it alone for 60 seconds, then it widens.
   - **Reject** needs a reason.
5. 🆕 **Watch the delivery:** ringing → "Ravi is coming to collect" (with plate) → at the shop → on the way.
   - Hand the parcel over with the **pickup PIN** shown on the card.
   - **Ring again** or **Send my rider** if nobody takes it.
6. **Mark Packed**, then the rider picks it up and delivers. Cash on delivery is collected by the rider.

⚠️ Products have no sizes or colours yet. The "Cash on delivery" switch does nothing unless you have store riders or courier shipping.

## 5. E-commerce: shipping across India

1. **Seller:** turn on courier shipping on the business form. The page is then findable from anywhere.
2. **Buyer:** when the shop is far away and ships, checkout defaults to **Ship**.
   - Pick a saved address (the default is preselected), or add one; the pincode fills in city and state.
   - Pay by UPI, or cash on delivery if the shop allows it.
3. **Seller:** accept (within 24 hours) → pack → **Mark shipped** with the carrier and tracking number → **Mark delivered**.
4. **Buyer:** tracks with the carrier link, then rates the order.

## 6. Finding a skilled person (plumber, electrician…)

1. Home search → type "plumber" → Search. Or use Services → a Local services or Gigs tile.
2. **Results:** cards showing photo, name, category, distance, online status, "by owner", the matched service and price, and the ↑/↓ badge.
   - The filters are All, Pros, Shops and the like, plus radius 3, 10 or 25 km.
   - 🆕 Old filters reset on a new search, and people you've blocked are left out.
3. **Open a profile:** Feed, About (documents, team, jobs), Gallery or portfolio, Services with prices, and Recommendations.
4. **Contact or engage:**
   - **Message**, or **Request/Book** a service, which opens a chat with a first line filled in.
   - **Sync**, to follow their posts.
   - **Recommend / Not recommend**, Share, Directions.

⚠️
- There's no way to call.
- You can't choose a different area; search uses GPS only.
- No plural, typo or Hindi and Kannada matching ("plumbers", "bijli wala").
- Pros appear only once they're LIVE, which needs 7 in-person recommendations.

## 7. Offering a skill (pro)

1. ☰ → **Create → Skill profile** → skill name, category (required), experience (Intermediate preselected), rate, languages and description. Area and location are filled in.
2. **Dashboard:** add portfolio photos (up to 20) and services with prices.
3. **Go live:** 7 people nearby recommend you by scanning your QR in person. Gig work also needs a photo ID.
4. 🆕 **Pro profile** (☰ → Pro profile):
   - headline, About, experience, education, skills, licences and certificates, services you offer, work preferences
   - who can see it, and sections you can hide
   - **CV upload** (PDF, Word or photo, private to you)

## 8. Jobs

1. **Employer:** a business dashboard → Jobs → **New job**: title, description, pay, type.
2. **Job seeker:** search "jobs", or Services → Jobs tile → **Jobs near me** → open a job → **Apply**. You attach your skill pages and an optional note.
3. **Employer:** sees the applicants → **Message** the applicant.
4. **Job seeker:** ☰ → *Jobs and applications* shows where each application stands.

Planned: apply with your Pro profile and CV attached, job alerts, a "matches 4 of 5" fit line.

## 9. Social networking

1. **Feed tab:** Moments row, then posts from people you're synced with and from nearby.
   - ↑/↓ on posts. 🆕 You see both counts once you've voted, and you can vote on your own posts.
   - Comments.
   - 🆕 Tap a photo or video to see it full screen, with swipe, zoom and voting.
2. **Create:** **Post** (text, photos or video; audience Nearby, Synced only or Everyone) or **Moment** (gone after 24 hours).
3. **Connect:** ☰ → *Find people* (name or Bucks ID), or open someone's profile → **Sync** → they accept.
4. **Chat:** direct and group chats, photos and files, sync requests.
5. **Profile tab:** 🆕 profile picture and cover photo (change, view full screen, remove), posts, media, files, recommendations.
6. **Safety:**
   - **Report** posts, comments, Moments, messages and people.
   - Block, close friends, privacy settings, the Safety centre.
   - Minors get stricter defaults, enforced by the server.

## 10. Settings and app updates

- **Settings:** edit profile, Bucks ID, privacy, blocked people, close friends, notifications (with quiet hours), appearance, help, feedback board, legal pages, log out, delete account.
- 🆕 **App versions:** see your build, list every published test build on any branch, and install a newer one with one tap. Play Store builds update through the Play Store.

### Status legend
- **Live in the database:** everything above, including the Pro profile, delivery assignment and vehicle review.
- **Still to test on a phone:** all of the 🆕 items.
- **Android only for now:** the 🆕 items. iOS has the super-app layout but not the social screens, Pro profile, media features or delivery assignment.
