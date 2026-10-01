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

### Phase 5: Shopify sync: dropped
Decision (1 Oct): orders are handled only in Bucks, and there is no Shopify token, so there is no sync. The catalogue was imported once and is now managed in Bucks. Prices and stock changed in Shopify will not follow; edit them in Bucks (Menu → Bucks Pro → Aspire More). Re-import of new products is a one-off script if ever wanted.

### Phase 6: Seller tools (5 days)
- Stock quantities with low-stock alerts, bulk price and stock edit, CSV import and export.
- GST invoice PDF per order, returns and refund requests, simple sales report (orders, revenue, top items).

### Phase 7: Trust, legal, polish (3 days)
- Store policy pages, GST number and legal name on the profile, product and store reviews after delivery (reviews already exist for shops), image alt text, report and takedown.
- Legal review of the marketplace terms (sellers ship across state lines; consumer-protection e-commerce rules apply).

**Total about 30 working days (6 weeks) without the Shopify sync.** Smallest useful cut: **Phases 1, 2 and 4 with the UPI shortcut from Phase 3 (about 3 weeks)**: a proper store page, courier orders, and discoverability.

## 4. Data changes (sketch)

- `items`: `product_key text`, `variant_label text`, `stock` used for real quantities, `compare_at` already `mrp`.
- `listings`: `banner_url`, `logo_url`, `reach text default 'LOCAL'`, `policies jsonb`, `social jsonb`.
- `orders`: `delivery_mode` adds `SHIP`; `ship_address jsonb`, `ship_pincode`, `carrier`, `tracking_no`, `shipping_fee`, `payment_status`, `gateway_ref`.
- New: `addresses` (per buyer).
- All new tables keep row-level security; payment and tracking fields are written only by server functions.

## 5. Decisions (1 Oct)

1. **Fulfilment: handled only in Bucks.** No Shopify order push, no sync (Phase 5 dropped).
2. **Payments: brainstorm below.**
3. **Archived products (114): left out.**
4. **Shopify token: ignored**, so stock stays in stock / out of stock, edited in Bucks.
5. **Aspire More as a model: recommended below.**
6. **Profile tabs: Feed, About, Products, Jobs, Reviews** (done in build 71; photos moved into About; a store with products opens on Products).

### Payments: options

| Option | How it works | Good | Watch out |
|---|---|---|---|
| **A. UPI to the seller** (today) | buyer pays the seller's UPI ID or QR, seller confirms | no fees, no KYC, works now | nothing confirms it automatically, "I paid" disputes, no refund tools, weak trust for a buyer in another city |
| **B. Cash on delivery** | pay the courier | buyers expect it in India | returns to origin cost the seller; needs a limit (for example under ₹3,000) and a small COD fee |
| **C. Seller's own gateway** (Razorpay, Cashfree or PhonePe PG) | the seller connects their own gateway account; Bucks creates the payment through it and a webhook marks the order paid | prepaid orders, automatic status, refunds; **money goes straight to the seller, Bucks never holds it**, so far less regulation | each seller needs their own gateway KYC (days); keys must be stored as server secrets |
| **D. Bucks collects and pays out** (marketplace split) | Bucks is the merchant, splits to sellers | one checkout for everyone, can take a commission | payment-aggregator and escrow rules, GST on commission, refunds and chargebacks become Bucks' job; needs legal and CA advice first |

**Recommendation:** ship in three steps.
1. **Now (pilot):** A + B. Each order gets a reference; the buyer taps "I have paid" and the seller confirms; COD only where the store enables it, with a cap. Nothing ships until the seller marks the payment received.
2. **Next (about 6 days):** C for Aspire More. Their Shopify shop already takes online payments, so a Razorpay or Cashfree account is likely quick to get. Prepaid orders cannot be shipped until the webhook confirms them; refunds from the order screen.
3. **Later, only if many sellers join:** D, after legal and tax advice.

### Aspire More as the model for national brands: recommendation

Make it the **template, but keep the pilot small.** Add the general flag (`listings.reach = INDIA`, Phase 4) instead of anything Aspire-specific, since it costs the same. Only Bucks staff can set it, so no seller can turn it on for themselves. Do not open self-serve national selling until courier orders, payment and the returns policy have been tested with Aspire More for a few weeks. It keeps the pilot honest: local services stay local, and one national store proves the courier and payment path.

## 6. Risks

- **Marketplace rules and tax:** cross-state sales, GST invoices and returns are real obligations; get advice before real orders.
- **Two sources of truth:** without Phase 5, prices and stock drift from Shopify.
- **Hotlinked photos:** if the store renames or removes a file, the photo breaks; Phase 5 can copy images into storage once a server that can reach Shopify is available.
- **Support load:** courier delays and returns are handled by the seller, not Bucks; make that clear in the terms.
