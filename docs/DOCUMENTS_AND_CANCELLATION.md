# Showcase documents, activity button, cancellation with reasons

Server: `supabase/migrations/showcase_docs.sql`, `cancellation.sql`. Live scenario (rolled back): `supabase/tests/docs_cancel_live_scenario.sql`.

## Showcase documents (a profile's "Documents")
Separate from the compliance documents Bucks staff check for go-live (`listing_documents`). Showcase documents never affect go-live and are never
"checked by Bucks" unless a staff member marks them (`review_showcase_doc`).

| Visibility | Who can open the file |
|---|---|
| PUBLIC | any signed-in user |
| ON_REQUEST | locked card on the profile; a viewer asks, the owner or an admin approves for 1 to 90 days (default 30), revocable |
| PRIVATE | owner, admins, Bucks staff; hidden from everyone else |

Rules
- Kinds: Registration, Licence, Tax, Certificate, Affiliation, Award, Report, Brochure, Other (the owner names "Other"). No owner ID or ownership proof.
- Titles containing "verified" or "bucks" are refused. 2 to 60 characters. PDF, JPG, PNG, WebP up to 10 MB; up to 20 per profile.
- A registration number can carry a registry (GST, FSSAI, MCA). The app links to the registry's own search; it does not check for you. GSTIN and FSSAI formats are validated.
- Requests: 5 per viewer per day, 20 waiting per profile, lapse after 7 days. The owner sees the requester's name and whether they ordered or follow the page. Going PRIVATE ends every open grant.
- Files are read with the viewer's own sign-in, so the storage rule (`showcase_path_open`) decides every time. The viewer screen blocks screenshots and watermarks the viewer's name.
- Viewer opinion ("looks genuine" / "doesn't look right"): only after opening the document, not for the team, 20 per hour, account age as for recommendations.
  Shown as "N of M viewers say it looks genuine" once M is 3 or more. It is a viewer signal, never verification, and never feeds `trust_up`.
- The owner sees who opened what (`doc_view_log`).

Known gaps
- `delete_showcase_doc` and `clear_showcase_check` are written in the migration but need applying (the SQL tool holds statements containing a delete for confirmation).
- Without staff rows nobody can mark a document "checked by Bucks"; the in-app review queue exists, the `staff` table is empty.

## Home buttons
- Provider button (the round Bucks button): only while online as a driver or with a live shop / pro listing. Offline providers get a small "You're offline · Go online" chip in the Home sheet. The online sheet now lists live cloud shops and pro profiles with switches.
- Customer activity pill (bottom left): shown while a ride is open (finding a driver, driver on the way, here, on trip, pay) or an order is open (placed, accepted, ready, on its way, shipped). One item opens its screen; several open a list. Orders refresh every 20 s while Home is on screen.

## Cancellation with reasons
- Rider: `cancel_task`. No reason needed while searching. Once a driver accepted a reason is required and the driver is told. Refused once the trip started, and for order deliveries (cancel the order). The ride stays on screen until the server agrees (the old code cleared it first and swallowed a refusal).
- Driver: `release_task` (hand back before the PIN) with a required reason, logged in `task_events.reason`.
- Buyer: `cancel_order(order, reason)` before the shop accepts; the shop is now notified (it used to hear nothing).
- Shop: `respond_order(order, accept, reason)` and `update_order_status(order, 'CANCELLED', reason)`; the buyer's notification carries the reason.
- `my_cancel_stats()` powers a factual nudge ("You've cancelled N rides after a driver accepted today"). No fees or blocks yet.
- Reasons are optional on the server so older app builds keep working; the new app requires them where it matters.
- The old order functions were renamed `*_old` (not dropped) and made unreachable; drop them later.
