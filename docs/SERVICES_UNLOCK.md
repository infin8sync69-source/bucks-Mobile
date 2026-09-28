# Services: unlock rules, listings and documents

How Bucks decides which services a customer can use where they stand, what each kind of provider lists, and which of
their documents are public or private. Implemented in `supabase/migrations/services.sql` (tests:
`supabase/tests/services_scenarios.sql`) and in the app under `ui/Services.kt`, the Services tab, the listing editor and
`screens/manage/DocumentsScreens.kt`.

Confidence tags: **[Certain]** built and tested; **[Likely]** strong inference; **[Guessing]** needs checking. Every
legal point below is [Likely] at best and needs review by a lawyer before launch.

---

## 1. Three decisions that shape everything

**1. Online counts cannot unlock a service.** "At least 4 delivery riders online" flips many times an hour as riders log
in and out, so the tile would lock and unlock under the customer's thumb. Bucks separates two questions:

| Question | Counted from | Changes | Decides |
|---|---|---|---|
| Is there enough supply here? | Providers who passed the community cap and document checks (LIVE listings, ACTIVE vehicles) | Rarely: only when someone joins, is suspended or leaves | LOCKED vs unlocked |
| Can I use it right now? | Providers online now | By the minute | QUIET vs OPEN |

So a service shows one of four states: **SOON** (switched off by Bucks), **LOCKED** (not enough checked supply),
**QUIET** (unlocked, but not enough providers online right now) and **OPEN**. [Certain]

**2. Geography is a circle around the customer, not a named locality.** For each service the supply is counted within a
fixed radius of where the customer stands, and that radius is the distance the service is actually served from. So
"Food is open" also means "restaurants can reach you". [Certain]

**3. The community cap multiplies the cold-start effort.** A listing needs 7 in-person recommendations to go live. Food at
10 restaurants therefore needs 70 recommendations before it opens anywhere. That is deliberate (trust) but slow. Section
6 lists ways to shorten it without weakening trust. [Certain on the arithmetic, Guessing on how slow it feels in the field]

---

## 2. The services menu

11 tiles, 5 per row. Defaults live in the `service_rules` table and can be tuned in the Supabase dashboard without an
app release (re-running the migration never overwrites tuned values). [Certain]

| Tile | Icon | Supply that counts | Radius | Unlocks at | Open now needs | Customer tap goes to |
|---|---|---|---|---|---|---|
| Taxi | LocalTaxi | Checked cabs that went online here in the last 14 days | 5 km | 3 | 1 cab online | Ride booking, cab |
| Auto | ElectricRickshaw | Checked autos, same rule | 5 km | 3 | 1 auto online | Ride booking, auto |
| Parcel | DeliveryDining | Checked bikes, same rule | 3 km | 4 | 2 bikes online | **Switched off (SOON)**: the parcel booking flow is not built yet |
| Food | Restaurant | LIVE restaurants, bakeries, cafés, cloud kitchens | 5 km | 10 | 3 open | Search, Food only |
| Grocery | LocalGroceryStore | LIVE grocery, supermarket, dairy | 3 km | 5 | 1 open | Search, Grocery only |
| Vegetables | Eco | LIVE vegetable and fruit sellers | 3 km | 3 | 1 open | Search |
| Meat | KebabDining | LIVE chicken, mutton, fish, egg shops | 3 km | 2 | 1 open | Search |
| Shopping | ShoppingBag | LIVE other shops (electronics, hardware, clothing, repair, salon, tailor…) | 5 km | 5 | 1 open | Search |
| Gigs | Handyman | LIVE skill profiles (plumbers, tutors, electricians…) | 5 km | 8 | none (booked ahead) | Search, skills |
| Jobs | Work | Open jobs posted by LIVE businesses | 10 km | 5 | none | Jobs near me |
| Properties | Apartment | LIVE property owners, agents and builders | 10 km | 10 | none | Search |

Why these numbers: a customer should see real choice on the first open. Your examples (5 shops, 10 restaurants, 4
riders) are kept. Meat and vegetables are lower because far fewer such shops exist per neighbourhood. Vehicles count
"worked here in the last 14 days", because a vehicle has no fixed address. [Likely]

**Pharmacy is left out on purpose.** Selling medicines online needs its own licensing and prescription checks. [Likely]
Bike taxis (passengers on bikes) stay out: bikes carry goods only, as decided earlier, and Karnataka has banned bike
taxis. [Likely]

**Delivery dependency.** Food, Grocery, Vegetables, Meat and Shopping deliver through riders. When no Bucks rider is
online nearby, the service can still be open, but search says "order for pickup, or from shops with their own riders".
[Certain]

**Pilot switches.** Each service has a `mode`: `AUTO` follows the rule, `ON` forces it unlocked (the "open now" check still
applies), `OFF` shows "coming soon". Launch values: everything `AUTO` except Parcel `OFF`. For a ride-only pilot, set
the others to `OFF` in the dashboard. [Certain]

### What the customer sees

- **LOCKED tile**: dim, with a padlock. Tapping opens a sheet: "Food opens here once 10 restaurants within 5 km of you
  are on Bucks and checked", a progress bar ("3 of 10 so far"), "12 people near you are waiting", a **Notify me** button,
  and "Run a restaurant? **List it**", which opens the listing form with Food preselected. [Certain]
- **SOON tile**: same sheet, "coming soon" wording, Notify me. [Certain]
- **QUIET tile**: normal, with an amber dot. It opens, with a note like "No autos online near you right now". [Certain]
- **OPEN tile**: goes straight in. [Certain]
- **No location**: the menu says "Turn on location to see which services are open where you are". It never shows the
  map's default centre as if it were the person's area. [Certain]

### Notify me (the demand side)

`service_interest` stores who wants which service and where. It is a toggle, and people see only the count near them,
never who. Uses: tell suppliers "42 people near you want Food"; pick where to recruit shops next; and, later, send a push
when the tile unlocks. The push itself is not built yet. [Certain for the list, Guessing on the push timing]

---

## 3. Geography: what the circle means in practice

| Situation | What happens | Why it is acceptable |
|---|---|---|
| Customer on the edge of a busy area | Counts include shops across the "border": no artificial locality lines | Matches reality: those shops can serve them |
| Customer moves 2 km | The menu re-checks (every ~500 m of movement) and may change | The service really is different there |
| Dense centre vs thin suburb | Same thresholds, so suburbs unlock later | Correct for quality; tune per city later if needed |
| Two customers 100 m apart | Almost always the same answer | Circles overlap heavily |
| One shop suspended | That circle may drop below the threshold and lock | Rare, because supply counts only checked providers |

Not built yet, and why: **named localities** (polygons such as "Jayanagar 4th Block"). They read nicely in marketing, but
drawing and maintaining them costs effort and adds border effects. If needed for campaigns ("Food is now open in
Jayanagar!"), add a `zones` table and label a circle's centre with its zone. The unlock logic does not change. [Likely]

**Per-city tuning, later.** When a second city launches, add an optional `city` column to `service_rules` overrides. One
row set per city lets, say, Mysuru unlock Food at 6 instead of 10. [Guessing on what the numbers should be]

Performance: every count uses PostGIS `ST_DWithin` on GiST-indexed points. For a pilot of 100 users and a few hundred
listings the call takes milliseconds. [Likely] Past about 50,000 listings, cache `services_near` per ~500 m grid cell
for a minute. [Guessing]

---

## 4. What each provider lists

Every provider has the same universal profile: title, category, description, photo, area, location, products or services,
reviews, recommendations. The table lists what differs per service (stored in `listings.details` or `items`).

| Service | Listing kind | Key details | Items | Status |
|---|---|---|---|---|
| Food | BUSINESS | Hours, delivery radius, free delivery, cash on delivery, cuisine, veg / non-veg | Dishes with price, group (Starters, Biryani…), photo, in stock | Built, except cuisine and veg flag, which are free-text details today |
| Grocery | BUSINESS | Same as Food | Products with MRP, unit (1 kg, 500 g), stock | Built |
| Vegetables | BUSINESS | Same, plus "sourced from" (optional) | Produce by kg, today's price | Built (price per kg via unit) |
| Meat | BUSINESS | Same, plus halal / jhatka, fresh / frozen (details) | Cuts by weight | Built (flags as details) |
| Shopping | BUSINESS | Hours, delivery, category | Products | Built |
| Gigs | SKILL | Experience level, rate, languages, area worked | Services with price per visit / hour | Built |
| Jobs | Posted by a BUSINESS | Title, type (full-time, part-time, gig), pay, description | none | Built |
| Properties | BUSINESS (owner, agent or builder) | Agent / owner, RERA number when registered | **Each property**: rent / sale / lease, type, BHK, carpet area, furnished, price, deposit, available from, photos | Profile built. **The property item form (BHK, sq ft, deposit) is not built yet**: properties are plain items today |
| Taxi, Auto, Parcel | DRIVER profile plus vehicle | Vehicle kind, model, languages; plate shown as last 4 characters | none | Built |

Rules that apply to all:
- A business picks **one service** (the tile customers find it under). It decides the documents required. Once live, the
  service can only be changed by Bucks, so a grocery cannot become a restaurant without an FSSAI check. [Certain]
- Skills are always Gigs. Drivers have no tile of their own: their vehicles count towards Taxi, Auto or Parcel. [Certain]

---

## 5. Documents: public, private and in between

### Three levels of visibility

| Level | Who sees it | Examples |
|---|---|---|
| **Public** | Every signed-in user | Business name, photo, area, products, prices, reviews, recommendation count, a "checked by Bucks" tick per verified document, and the number of FSSAI, GSTIN and RERA registrations |
| **Shared during an engagement** | Only the other party, only while it lasts | Driver's full plate and phone during a trip, a shop's UPI link during an order, an applicant's application to that one business |
| **Private** | The uploader and Bucks staff only | Every document **file**, ID numbers (never kept), ownership proof, trade licence numbers, home location |

The document files live in the private `docs` storage bucket, under the uploader's own folder. Even the listing's admins
see only the status, not the file. Customers get `listing_badges`: a tick, a label, an expiry date, and the number only
for document types marked `public_number`. [Certain]

### Why these numbers are public

- **FSSAI**: food businesses must display their FSSAI licence or registration number, and e-commerce food platforms must
  show it for every seller. [Likely]
- **RERA**: registered agents and projects must quote their RERA number in advertisements. [Likely]
- **GSTIN**: it is printed on every invoice anyway, and showing it builds trust. [Likely]

### What each service asks for

(* = required to go live)

| Service | Documents |
|---|---|
| Food | Owner ID\*, FSSAI\*, GST, Trade licence, Shop & establishment |
| Grocery | Owner ID\*, FSSAI\*, GST, Shop & establishment |
| Vegetables | Owner ID\*, FSSAI\* (basic registration covers small sellers), GST |
| Meat | Owner ID\*, FSSAI\*, Municipal trade licence\*, GST |
| Shopping | Owner ID\*, GST, Shop & establishment, Trade licence |
| Gigs | Owner ID\*, Trade licence or certificate (e.g. electrical wireman licence), Police clearance (earns a "background checked" badge) |
| Properties | Owner ID\*, RERA, Ownership proof (private), Owner's authorisation letter (when listing for someone else) |
| Taxi / Auto / Parcel | Vehicle documents on the vehicle, already built: RC, insurance, permit; driving licence. Moving these into the same document system is a later step |

Legal basis, [Likely]: FSSAI registration or licence applies to every food business, including small vegetable
sellers. E-commerce platforms are expected to onboard only FSSAI-registered food sellers. Meat shops need a municipal
licence. RERA applies to agents and projects, not to owners renting their own flat, so RERA is optional.

### Identity documents: what Bucks does not keep

The owner ID asks for PAN, voter ID, passport or driving licence, and says **do not upload Aadhaar** (or use the
masked Aadhaar from the UIDAI site). The Aadhaar Act restricts who may store Aadhaar numbers. The DPDP Act 2023 asks
for data minimisation, so Bucks keeps the file for checking and **never stores the ID number** (`asks_number = false`, and
the server blanks it). [Likely on both laws] DigiLocker would remove the need to upload ID at all. It needs a partner
agreement, so it is a later step. [Likely]

### Lifecycle

```
MISSING --upload--> PENDING --staff approves--> VERIFIED --expiry date passes--> EXPIRED
                       |                                                          |
                       +--staff rejects (with a reason)--> REJECTED               +-- replace --> PENDING
```

- **Going live needs both gates**: 7 neighbour recommendations **and** every required document VERIFIED. Whichever
  finishes last takes the listing live automatically (`try_go_live`). [Certain]
- **Expiry**: a daily job at 02:05 IST marks documents past their date EXPIRED; the badge disappears at once. A live
  listing gets **7 days of grace**, then it is paused (`SUSPENDED` with `compliance_hold`) and disappears from search.
  Uploading a new document and having it verified brings it back live automatically. [Certain]
- **Safeguards**: a verified required document cannot be deleted, only replaced. Numbers are checked for format (FSSAI
  is 14 digits; GSTIN follows the official pattern). Expired documents cannot be uploaded. A document type that does not
  belong to the service is refused. The file must sit in the uploader's own folder. [Certain]
- **Staff review**: people in the `staff` table get **Review documents** in Settings. It shows the queue oldest first, with
  open file, approve, and reject with a reason the owner sees. Add a staff member with
  `insert into staff (profile_id) values ('<profile id>')`. [Certain]
- **Account deletion** removes the person's notify-me pins, their document rows and their files in storage. [Certain]

---

## 6. Risks and open decisions

1. **Cold start is slow by design.** Food needs 10 × 7 = 70 in-person recommendations. Options, each keeping the
   trust idea:
   (a) count listings whose documents are verified towards the *progress bar* (not the unlock), so early shops see
   momentum;
   (b) run "founding shop" drives where Bucks staff collect recommendations at a market;
   (c) lower `min_recommendations` for the pilot area only. **Decision needed.**
2. **Parcel is off** until a person-to-person parcel booking flow exists (pickup and drop, package note, PIN at both
   ends). **Decision needed on priority.**
3. **Property details** (BHK, carpet area, deposit, available from) need their own item form and filters. **Planned.**
4. **Vehicle documents** still use the older per-vehicle list (RC, insurance, permit). Move them into
   `listing_documents`-style rows with expiry, so insurance expiry pauses a vehicle the same way. **Planned.**
5. **Push when a tile unlocks** for the people who asked. **Planned.**
6. **Legal review** of every [Likely] above before public launch: FSSAI e-commerce onboarding, RERA display, Aadhaar
   storage, DPDP consent wording, and two-wheeler goods delivery on private number plates. **Required.**

---

## 7. Operating it

| Task | How |
|---|---|
| Change a threshold | Dashboard → `service_rules` → edit `min_supply`, `min_online` or `radius_m` |
| Close a service for the pilot | Set its `mode` to `OFF` |
| Force a service open | Set its `mode` to `ON` |
| Add a staff reviewer | `insert into staff (profile_id) values ('…')` |
| Require a new document | Add a row to `doc_types` and to `service_doc_rules` |
| See what is waiting | The app's **Review documents** screen, or `select * from listing_documents where status = 'PENDING'` |
