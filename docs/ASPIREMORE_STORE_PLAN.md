# Aspire More on Bucks: what the business profile needs, and how to build it

Aspire More (aspiremore.in) is a Shopify store selling handcrafted home décor (vases, sculptures, trays, lanterns, clocks…) from Pune, shipped across India by courier. Bucks' business profile was designed for a neighbourhood shop that delivers by a local rider. This plan closes the gap so Aspire More runs as a full store inside Bucks.

## 1. Where things stand (done on 30 Sep)

| | |
|---|---|
| Business listing | **Aspire More**, owned by Shafeeq D E, service Shopping, category Home décor, area Pashan Pune, live, online |
| Catalogue | 204 active Shopify products → **284 items** (one per variant), 12 categories (Vases, Sculptures & Figurines, Trays, Lanterns…), ₹300–₹49,300, up to 8 photos each, 12 gallery photos |
| Details | address, phone, email, website, "ships across India" flag, Shopify product URL and SKU on every item |
| Not imported | 114 **archived** Shopify products (withdrawn from sale); Shopify stock quantities (the public feed only says in stock / out of stock); the dark logo (an SVG the app cannot show; the brand banner is the listing photo for now) |
| Photos | stay on Shopify's CDN (`cdn.shopify.com`, this store's folder only, allowed by migration `bucks_27`) |

Anyone can already open the store from Menu → Bucks Pro (owner) or its link (customers).

## 2. What Aspire More needs that the profile does not do yet

| Need | Today | Gap |
|---|---|---|
| **Products with options** (Small / Regular / Set) | every variant is a separate card ("Stag — Small", "Stag — Regular", "Stag — Set") | no product page with an option picker, one price range, one gallery |
| **Ship by courier across India** | delivery is pickup, the store's own rider, or a Bucks rider inside a radius | no "ship to my address", pincode check, shipping fee, courier or tracking number |
| **Online payment** | UPI QR to the seller, or cash on delivery with own riders only | a buyer in another city needs prepaid (UPI/cards) with a paid/failed status and refunds |
| **Be found outside Pune** | search is by distance from the buyer | a Pune store is invisible to everyone else; there is no "ships to you" |
| **Browse 284 items** | flat list, one section per group | no collections tabs, in-store search, sort or price filter, no paging |
| **Brand presentation** | one photo, a description, hours | no banner plus logo, story, policies (returns, shipping), social links, GST number |
| **Stock** | in stock / out of stock | real quantities, low-stock alerts, sold-out badge |
| **Keep Shopify and Bucks in step** | one-time import | price, stock and new products drift; orders live in two places |
| **Seller operations** | accept / reject / ready / picked up | pack, ship with tracking, delivered, returns, invoices (GST) |

## 3. Plan

Sizes are for one developer, working days. Each phase ships on its own.

### Phase 1: Storefront that looks like a store (5 days)
- **Product with variants.** New `items.product_key` (the Shopify product id) and `items.variant_label`. The store shows one card per product ("From ₹1,500"); the product page has an option picker (Small / Regular / Set) that switches price, photo and stock; the cart line keeps the variant. Existing rows already carry `details.product_id` and `details.variant`, so no re-import is needed.
- **Collections.** Tabs from `group_name` (12 collections), "All", and in-store search and sort (price, newest).
- **Store header.** Separate `banner_url` and `logo_url` on the listing, badges ("Ships across India", "Handcrafted", "Since …"), website and social links, policy links (Shopify's shipping, refund, privacy and terms pages).
- **Product page.** Swipeable photo pager, cleaned description (drop the repeated title line), MRP and discount, share link, "More from this collection".
- **Performance.** Ask Shopify's CDN for sized photos (`?width=600` in lists, 1200 on the page); page the item list (30 at a time).
- *Done when:* the store opens in under 2 seconds on mobile data, 284 items browse smoothly, and a "Small / Regular / Set" product shows as one card.

### Phase 2: Courier delivery (8 days)
- New order mode `SHIP` beside pickup / store rider / Bucks rider; **address book** on the buyer (name, phone, full address, pincode, saved).
- Store settings: ships-to (India / states / pincode list), **shipping rule** (flat ₹ or free above ₹X), handling days.
- Order lifecycle for SHIP: `PLACED → CONFIRMED → PACKED → SHIPPED → DELIVERED` (+ `CANCELLED`, `RETURN_REQUESTED`). The seller enters courier and tracking number; the buyer sees a tracking card and gets a notification at every step (push already exists).
- Seller order screen: pack, ship (with tracking number and link), print packing slip.
- *Done when:* a buyer in another city places an order, the seller ships it with a tracking number, and both see each status.

### Phase 3: Online payments (6 days, plus business KYC lead time)
- Pilot shortcut (2 days): UPI intent to the store's UPI ID with "I have paid" plus seller confirmation (what rides do today).
- Real gateway (Razorpay or Cashfree): an edge function creates the payment order, a webhook marks it paid or failed, refunds from the seller screen, payment status on the order. Secrets stay server-side.
- Cash on delivery allowed only where the store turns it on (with a limit).
- *Done when:* a prepaid order cannot be shipped until the gateway confirms it, and a refund reverses the status.

### Phase 4: Found outside Pune (3 days)
- `listings.reach` = `LOCAL` or `INDIA`. Search and the Shopping service include `INDIA` stores for everyone, ranked below nearby ones; a "Ships to you" chip and pincode check ("Delivers to 560078") on the store and product pages.
- Home and Services: a "Brands that ship to you" row.
- *Done when:* a Bengaluru test account finds Aspire More from search and Services.

### Phase 5: Stay in sync with Shopify (8 days)
- A Shopify custom app (Admin API token, read products and inventory, write orders) stored as an edge-function secret.
- **Pull:** products, prices, photos, availability and stock quantities, on a schedule and on Shopify webhooks (`products/update`, `inventory_levels/update`), with a mapping table (`shopify_map`: Bucks item ↔ Shopify variant). Shopify stays the source of truth for the catalogue.
- **Push:** every paid Bucks order becomes a Shopify order (so fulfilment, GST and courier stay in one place); Shopify shipment updates flow back as `SHIPPED` and `DELIVERED`.
- Optional: import archived products as "not available" so old links do not break.
- *Done when:* changing a price or stock in Shopify shows in Bucks within minutes, and a Bucks order appears in Shopify.

### Phase 6: Seller tools (5 days)
- Stock quantities with low-stock alerts, bulk price and stock edit, CSV import and export.
- GST invoice PDF per order, returns and refund requests, simple sales report (orders, revenue, top items).

### Phase 7: Trust, legal, polish (3 days)
- Store policy pages, GST number and legal name on the profile, product and store reviews after delivery (reviews already exist for shops), image alt text, report and takedown.
- Legal review of the marketplace terms (sellers ship across state lines; consumer-protection e-commerce rules apply).

**Total about 38 working days (7 to 8 weeks).** Smallest useful cut: **Phases 1, 2 and 4 with the UPI shortcut from Phase 3 (about 3 weeks)**: a proper store page, courier orders, and discoverability.

## 4. Data changes (sketch)

- `items`: `product_key text`, `variant_label text`, `stock` used for real quantities, `compare_at` already `mrp`.
- `listings`: `banner_url`, `logo_url`, `reach text default 'LOCAL'`, `policies jsonb`, `social jsonb`.
- `orders`: `delivery_mode` adds `SHIP`; `ship_address jsonb`, `ship_pincode`, `carrier`, `tracking_no`, `shipping_fee`, `payment_status`, `gateway_ref`.
- New: `addresses` (per buyer), `shopify_map`, `shopify_events`.
- All new tables keep row-level security; payment and tracking fields are written only by server functions.

## 5. Decisions needed from you

1. **Fulfilment.** Should orders placed in Bucks be pushed into Shopify (recommended, one place to ship from), or handled inside Bucks only?
2. **Payments.** Razorpay, Cashfree, or the UPI shortcut for now? A gateway needs the business's KYC and takes days to approve.
3. **Archived products** (114): leave out, or bring in as "not available"?
4. **Stock.** Can you create a Shopify custom app token (Settings → Apps → Develop apps, read products and inventory, write orders) so quantities come through?
5. **Location.** The store is in **Pune**, so Bengaluru testers will not see it in "near me" until Phase 4. Meanwhile it opens from its link and from Bucks Pro.
6. **Logo.** Send a dark PNG or JPG of the logo (the site's dark logo is an SVG); until then the brand banner is the listing photo.
7. **Scope.** Is Aspire More the pilot model for all national brands, or a one-off? It changes how much of Phase 4 becomes a general "brands" feature.

## 6. Risks

- **Marketplace rules and tax:** cross-state sales, GST invoices and returns are real obligations; get advice before real orders.
- **Two sources of truth:** without Phase 5, prices and stock drift from Shopify.
- **Hotlinked photos:** if the store renames or removes a file, the photo breaks; Phase 5 can copy images into storage once a server that can reach Shopify is available.
- **Support load:** courier delays and returns are handled by the seller, not Bucks; make that clear in the terms.
