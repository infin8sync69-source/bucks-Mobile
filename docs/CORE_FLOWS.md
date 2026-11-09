# Bucks core feature flows

The step-by-step flow of every core feature in the Android app (branch `feat/play-social-v1`), as the code and the end-to-end audit of
2026-11-09 found it. ⚠️ marks a known gap; 🆕 marks what was added on 2026-11-08/09 and still needs a check on a phone.

Shell: bottom bar **Home (map, search) · Feed · Services · For you · Profile**; the ☰ menu holds Bucks Pro (Pro profile, pages, vehicles,
invites, orders, jobs, Find people, Settings, Help, App versions).

## 0. Getting started (everyone)
1. Splash → tap to start.
2. Phone sign-in: 10-digit number (+91 fixed) → Send → 6-digit OTP (may fill itself).
3. Date of birth (required). Under 18: guardian name, phone, relation (Parent preselected) and consent. Under 13: refused for now.
4. Create profile: name → area (filled from location) → optional bio and interests.
5. Allow location and notifications.
6. Home: map with "Where to, or what do you need?".

⚠️ Two progress bars contradict each other ("1/3" on the age screen, "1/3" on the profile). Email sign-up is hidden in cloud builds.

## 1. Booking a taxi (rider)
1. Home search → pick a destination (or on the map).
2. Choose ride: Auto or Cab; the server prices it. Bikes never carry passengers.
3. Confirm pickup: drag the pin.
4. Searching: nearby drivers are rung. Cancelling is free, no reason needed.
5. Driver found: name, vehicle, plate, your 4-digit PIN; call or message. Cancelling now asks for a reason.
6. Give the PIN when the driver arrives; the trip starts.
7. In ride: live map, Share trip.
8. Pay by UPI or cash, then confirm in the app.
9. Rate: ↑ Recommend / ↓ Not recommended (a ↓ needs a reason).

## 2. Driving (auto, cab or bike owner)
1. ☰ → Create → Vehicle: type, plate, RC, insurance, licence (plus permit for auto and cab).
2. 🆕 Bucks staff approve it (Settings › Review documents and vehicles); the owner is notified either way.
3. Go online (☰ switch or Home's online button). Bikes take deliveries only; autos and cabs take rides.
4. A request rings → Accept within the ring window.
5. Drive to the pickup → Arrived → enter the customer's PIN → in progress.
6. End at the drop → collect payment (your UPI QR shows) → rate the customer.
7. Handing back before the PIN needs a reason; at most 3 an hour.

⚠️ Copy still promises autos and cabs "deliveries"; only bikes get them.

## 3. Quick commerce: local shops and food (buyer)
1. Find a shop: Home search ("biryani", "milk"), Services tile (Food, Grocery, Vegetables, Meat, Shopping) or For you.
2. Shop page opens on its catalogue (photo, price, stock).
3. Add items (items with options: Choose, first in-stock option preselected). Several shops = several orders.
4. View cart → checkout:
   - Delivery: Bucks rider (default), shop's own rider (when it has riders), or Pickup.
   - Payment: UPI (default); cash on delivery only with the shop's own riders.
   - Deliver to: current location plus a label.
5. Place order. The shop has 5 minutes to accept; the buyer can cancel until then.
6. Order page: Accepted → Packed → Picked up → Delivered, with Track delivery.
7. Rate the order (↑/↓) once delivered.

⚠️ The delivery fee isn't in the "Place order ₹X" total; the cart is lost if the app closes; payment and delivery choices aren't
remembered; a saved address can't be the drop point for local delivery.

## 4. Running a shop (seller)
1. ☰ → Create → Business → shop type → name, category, delivery radius (3 km preselected). 🆕 Non-food categories no longer default to
   Food (so no FSSAI licence is asked of shoe or toy shops).
2. Dashboard go-live checklist ("N of M done"): photos, products (price, MRP, stock, up to 8 photos), documents, UPI QR, local
   recommendations.
3. Store riders: Team → invite by Bucks ID → role Store rider → they accept under Invites.
4. New order: push plus a ring on Orders.
   - 🆕 **Accept · auto rider** (one tap): your riders for a cash order, Bucks bikes nearby otherwise.
   - 🆕 **Accept and choose my rider**: online status shown, last rider preselected; they get it alone for 60 seconds, then it widens.
   - Reject needs a reason.
5. 🆕 Follow the delivery: ringing → "Ravi is coming to collect" (plate) → at the shop → on the way. Hand over with the pickup PIN on the
   card. Ring again or Send my rider if nobody takes it. Call your own rider.
6. Mark Packed → the rider picks up and delivers; a cash order is collected by the rider.

⚠️ No product variants (size, colour). The Cash on delivery switch does nothing without store riders or courier shipping.

## 5. E-commerce: shipping across India
1. Seller turns on courier shipping on the business form; the page is found from anywhere.
2. Buyer: checkout defaults to Ship when the shop is far and ships. Saved address (default preselected) or a new one (pincode fills
   city and state). UPI, or cash on delivery when the shop allows it.
3. Seller: accept (within 24 hours) → pack → Mark shipped (carrier, tracking number) → Mark delivered.
4. Buyer tracks with the carrier link, then rates.

## 6. Finding a skilled person (plumber, electrician)
1. Home search "plumber" → Search, or Services → Local services or Gigs tile.
2. Result cards: photo, name, category, distance, online, "by owner", matched service and price, ↑/↓ badge. Filters: All, Pros, Shops…;
   radius 3/10/25 km. 🆕 Filters reset on each new search; blocked owners are left out.
3. Open a profile: Feed, About (documents, team, jobs), Gallery, Services with prices, Recommendations.
4. Message, or Request/Book a service (opens chat with a first line), Sync, Recommend / Not recommend, Share, Directions.

⚠️ No call button; search uses GPS only (no area picker); no plural, typo or vernacular matching; pros are listed only when LIVE
(7 in-person recommendations).

## 7. Offering a skill (pro)
1. ☰ → Create → Skill profile: skill, category (required), experience (Intermediate preselected), rate, languages, description;
   area and location filled.
2. Dashboard: portfolio (up to 20 photos), services with prices.
3. Go live: 7 people nearby recommend by scanning your QR; gig work also needs a photo ID.
4. 🆕 Pro profile (☰ → Pro profile): headline, about, experience, education, skills, licences and certificates, services offered,
   work preferences, visibility and hidden sections, CV upload (PDF, Word or photo; private).

## 8. Jobs
1. Employer: business dashboard → Jobs → New job (title, description, pay, type).
2. Job seeker: search "jobs" or Services → Jobs → Jobs near me → open → Apply (attach skill pages, optional note).
3. Employer reviews applicants and messages them.
4. Job seeker follows them under ☰ → Jobs and applications.

Planned: apply with the Pro profile and CV, job alerts, a fit line ("matches 4 of 5").

## 9. Social networking
1. Feed: Moments row, then posts from syncs and nearby. ↑/↓ (🆕 full breakdown once you've voted; you can vote on your own posts),
   comments, 🆕 full-screen photos and videos with swipe, zoom and voting.
2. Create: Post (text, photos, video; Nearby / Synced only / Everyone) or Moment (24 hours).
3. Connect: ☰ → Find people (name or Bucks ID), or a person's profile → Sync → they accept.
4. Chat: direct and group, photos and files, sync requests.
5. Profile: 🆕 profile picture and cover photo (change, view, remove), posts, media, files, recommendations.
6. Safety: Report posts, comments, Moments, messages and people; block; close friends; privacy; Safety centre; stricter defaults for
   minors, enforced by the server.

## 10. Settings and updates
- Settings: edit profile, Bucks ID, privacy, blocked, close friends, notifications and quiet hours, appearance, help, feedback board,
  legal, log out, delete account.
- 🆕 App versions: your build, every published test build of every branch, one-tap install of a newer one. Play builds update through
  the Play Store.

## Status
- Server: everything above is live, including the Pro profile, delivery assignment and vehicle review (migrations bucks_39–41).
- Not yet checked on a phone: every 🆕 item.
- Android only for now: the 🆕 items. iOS has the super-app layout but not the social screens, Pro profile, media features or delivery
  assignment.
