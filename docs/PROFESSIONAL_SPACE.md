# Studio: the professional space

What changed and why, for the "My listings" redesign (branch `pilot-release-fixes`, migration `supabase/migrations/studio.sql`).

## The problem with the old "My listings"

- One long card per listing with 5 to 8 small buttons (Edit, Products, Documents, Members, Orders, Jobs, View profile), no hierarchy.
- It never said what was missing before a listing could go live, only "3 of 7 recommendations". Documents were a separate screen reached after saving.
- Businesses, skills, the driver profile and vehicles lived in four tabs, one of which (Vehicles) jumped to another screen.
- No photos beyond one per listing and one per product; no stock; no way to post as the business; reviews only on the public page.
- Nothing for selling or renting a house, flat, shop, vehicle or equipment.
- A fixed-width list: on tablets and landscape phones it was a narrow strip.

## Principles (from marketplace seller apps: Swiggy/Zomato partner, Google Business Profile, OLX/NoBroker, Urban Company partner)

1. **Personal and professional are separate.** Personal profile = bottom bar ("Profile"). Everything you run = hamburger menu ("Studio").
2. **One dashboard per listing** with a clear "what's next". A checklist beats a paragraph.
3. **The one thing you do daily is one tap**: open / close, available / not available. It sits on the card, on the dashboard and in the menu.
4. **Create is one button** that asks "what do you want to offer?", not a tab per kind.
5. **Photos sell.** Gallery / portfolio on every listing, up to 8 photos per product.
6. **Responsive**: grids that go from 1 to 3 columns; forms capped at a readable width.

## Structure

```
Bottom bar:  Home · Feed · Services · For you · Profile (personal)
Hamburger:   Studio
  ├─ Bucks ID mini card  → Bucks ID card (QR, barcode, 1-year validity, UUID)
  ├─ Studio home         → hub of everything you run
  ├─ quick rows: each listing with its status and on/off switch → its dashboard
  ├─ active vehicle card with its online switch
  ├─ Create a listing
  ├─ Invites · My orders · Jobs and applications · Recommend a neighbour
  └─ Account settings · Logout
```

### Studio home (hub)
- Summary: "2 live · 1 waiting to go live · 1 open now · 1 vehicle".
- Filter chips: All · Businesses · Skills · Assets · Driving (driver profile + vehicles), with counts.
- Cards in an adaptive grid (300 dp min: 1 column on phones, 2 to 3 on tablets): cover photo, kind, title, price (assets) or category, status pill, on/off switch when live, recommendation progress when pending.
- **Create** button → sheet: Business · Skill profile · Asset to sell, rent or lease · Vehicle · Driver profile.
- Invites banner, Bucks ID card and "Recommend a neighbour" shortcuts.

### Listing dashboard (`studio/{id}`)
- Top bar: customer view, share, menu (Edit details, Documents, Team, Delete).
- Status strip on every tab: live + switch, or "not live yet: n of N", or paused for documents.
- Tabs by kind:
  - Business: Overview · Products · Photos · Feed · Reviews
  - Skill: Overview · Services · Portfolio · Feed · Reviews
  - Asset: Overview · Photos · Reviews
  - Driver: Overview · Photos · Reviews (vehicles from Overview)
- **Overview**: cover, **go-live checklist** (describe it, photos, products/services or vehicle, documents, recommendations; the last two are marked "Needed to go live" because the server enforces them), stats (recommended, synced, % positive, team), About with the public facts, and a Manage grid (Edit, Documents, Team, Orders, Jobs, Payment QR, Vehicles, Recommend code, Customer view).
- **Products / Services**: add, search (over 6 items), group filter, row with photo, price and MRP, stock left, in-stock switch, menu (Edit, Duplicate, Remove).
- **Photos / Portfolio**: grid, add up to 10 at a time (20 total), tap for caption, make cover, move earlier/later, remove.
- **Feed**: post as the listing (text + photo); list of its posts with delete.
- **Reviews**: % positive, recommend / don't counts, in-person recommendations, and every review.

### Forms
- **Asset**: type (house, flat, villa, plot, shop, office, warehouse, PG/room, commercial space, vehicle, equipment, other), mode (sell, rent, lease, PG), price with unit (total / month / year / day), deposit, negotiable, size, bedrooms, furnishing, available from, year and km for vehicles, description, locality, cover photo. Property types belong to the Properties service, so Bucks checks the owner's ID before they go live; vehicles and equipment need no documents.
- **Product / service**: up to 8 photos (first is main), name, description, price, MRP, unit, brand (products), pricing model and duration (services: fixed, per hour, per visit, starting from, on quote), group, in stock, optional stock count.
- **Vehicle**: RC, insurance, driving licence, permit (autos and cabs), PUC (optional), with a "2 of 3 required" meter and a hint per document.

### Bucks ID card
Credit-card layout: wordmark, name, area, the 8-character ID, the account UUID, valid from / valid till (1 year), a Code 128 barcode and a QR code (both scan with the in-app scanner). Renew opens in the last 30 days and after it lapses (`renew_bucks_id()`); an expired ID can't be used by others to sync until renewed.

## Server (studio.sql)
| Change | Rule |
|---|---|
| `listings.kind` + `ASSET` | `details.mode` in SELL/RENT/LEASE/PG, `details.price` a number ≥ 0, `price_unit` in TOTAL/MONTH/YEAR/DAY |
| Asset service | property types → PROPERTIES (its documents apply); others → no service |
| `listings.gallery` | ≤ 20 `{url, caption}`; every URL must be in `listing-media/<this listing>/`; caption ≤ 200 |
| `items.description / stock / photos / details` | description ≤ 1000; stock ≥ 0 or null; ≤ 8 photos from the listing's folder |
| Stock | stock 0 → out of stock; back from 0 → in stock; `place_order` refuses more than is left and takes it; rejected, timed-out and cancelled orders give it back |
| `profiles.id_issued_at` | readable by all, set only by `renew_bucks_id()` |

Tests: `supabase/tests/studio_scenarios.sql` (25 checks); all 11 suites pass on the combined schema.

## Not done yet (next)
- Enquiries inbox for assets (today "Enquire" opens a chat with the owner).
- Bulk product import (CSV / photo of a price list).
- Vehicle documents per driver (each invited driver uploads their own licence) and staff review of vehicle documents inside the app.
- Reordering products by drag.
