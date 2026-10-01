# End-to-end flow: vendor profile to customer purchase

Verified on the live Supabase project as a rolled-back scenario (nothing left in the data). Not yet tried on a phone.

## Steps checked
1. Vendor creates a BUSINESS listing (SHOPPING) and adds, edits and deletes items. A vendor cannot approve their own listing.
2. Go-live needs at least `min_recommendations` in-person recommendations and every required document VERIFIED (SHOPPING needs OWNER_ID).
3. A customer in another city finds the shop by category or product name. Shops with `details.ships_india` show regardless of distance.
4. Local delivery from too far is refused ("too far, ship it to an address instead"). Bad pincode or COD on a non-COD shop is refused.
5. Address book: add, edit, delete, one default at a time, max 10.
6. Ship order: fee `ship_fee`, free above `free_ship_above`, stock decrements, oversell refused.
7. Vendor rejects (stock returns) or accepts (no rider task for SHIP/PICKUP), marks shipped with carrier and tracking, buyer marks delivered.
8. Reviews: verified order review, direct recommend / not recommend with optional comment, remove, owner cannot rate own listing. Trust counters follow.
9. Notifications reach buyer and vendor at each stage.

## Findings fixed
- `contact_for_order` dropped phone/UPI once an order was SHIPPED; patched.
- URL regex over Postgres repetition limit; replaced.
- Nobody can verify documents: the `staff` table is empty. Aspire More was set LIVE directly in SQL.

## Limits
- Far-away customers can only order from shops that ship across India.
- Aspire More defaults (ship fee 99, free above 1999) are my choices; change in the listing editor.
- Scenario SQL: `supabase/tests/ecommerce_live_scenario.sql` (outline only; the full DO block lived in the session).
