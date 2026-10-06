# Page types: businesses, organisations and institutions on one profile

Problem today: every non-skill profile is `kind = BUSINESS`, falls under the Shopping service, shows a Products tab and an Add-to-cart button. An NGO,
a school or a residents' association looks like a shop that sells nothing. This plan fixes that without a new `kind` (a new kind would fall through
the service trigger to SHOPPING and break about 130 kind checks in the Android app).

## 1. The idea in one line
Every profile has a **page type**. The type decides what the page is called, which tabs it has, what its catalogue is (Products, Services,
Programs, Events or nothing), what the big button does (Add to cart, Book, Get a quote, Enquire, Volunteer, Join, Directions), where it shows up
in Home and search, which documents make sense for it, and which trust line it shows. The shell is one screen; the type fills it in.

## 2. Page types (6 groups, 14 types)

| Group (Home tile, search chip) | Type | Catalogue tab | Primary button | Other tabs | Reviews |
|---|---|---|---|---|---|
| Shops | Retail shop | Products (cart) | Add to cart | Feed, About, Jobs | yes |
| Shops | Online store (ships India) | Products (cart) | Add to cart | About, Feed | yes |
| Local services | Salon, clinic, repair, coaching, gym... | Services (price, duration) | Book | Gallery, About, Feed | yes |
| Companies | IT company / agency | Services (from-price or quote) | Get a quote | Work (portfolio), About, Team, Jobs | yes |
| Companies | Freelancer collective | Team first, then Services | Hire | Work, About | yes |
| Companies | Professional firm (CA, legal, architect) | Services | Enquire | About, Team, Feed | yes |
| Companies | Manufacturer / wholesaler | Catalogue (no cart, per-unit price) | Get a quote | About, Jobs, Feed | yes |
| NGOs and groups | NGO / charity / trust | Programs | Volunteer (Give later) | About, Volunteer, Team, Feed | yes |
| NGOs and groups | Community group | Events | Join | About, Feed, Team | no |
| Institutions | School / college | Programs (courses, classes) | Admission enquiry | About, Campus (gallery), Team, Jobs, Feed | yes |
| Institutions | Hospital | Services (departments) | Book | About, Team, Feed | yes |
| Institutions | Place of worship | Events | Directions | About, Gallery, Feed | no |
| Institutions | Association / society | Events | Join | About, Team, Jobs, Feed | no |
| Pros (existing) | Skill profile | Services | Request | Portfolio, Feed, About | yes |

Rules that make the difference visible:
- **Products exist only on the two Shop types.** The server refuses an order on any other type (`orders_module_guard`). Everyone else has a
  catalogue of Services, Programs or Events, which lead to a request, never a cart.
- **Customers never see an empty tab.** A tab shows only when it has content or the viewer manages the page. Owners see the empty tab with an Add prompt.
- **The type is shown**, not hidden: a small chip under the name ("NGO · Yerawada", "School · Baner"), the group icon on the card, and the group
  chip in search. Colour stays the brand colour; the icon and the chip carry the meaning.
- **Trust line** pairs "N neighbours recommended in person" with the registration state: "Registration: self-declared", "Registration: checking",
  "Registration: checked by Bucks". Self-declared claims (CBSE affiliation, 80G) are labelled as such until staff check the document.

## 3. Home and discovery
- Four new service rows next to the existing ones: **Local services** (5 km), **Companies** (25 km), **NGOs and groups** (10 km), **Institutions**
  (10 km). Shopping shows shops only. `services_near` already counts supply per row, so a tile hides until there is one page of that kind nearby.
- Search chips become groups: Shops, Local services, Companies, NGOs and groups, Institutions, Pros, Buy and rent, Drivers.
- Ranking (discovery track): for request-based types, "replies in about N minutes" and "N requests done" replace "N products".

## 4. Engagement model: one Request object for everything that is not a cart
`listing_requests`: QUOTE, BOOKING, ENQUIRY (admission, general), VOLUNTEER, JOIN. States: SENT, SEEN, REPLIED, ACCEPTED, DONE, DECLINED,
CANCELLED, EXPIRED. Each type has a small form (template) and a time-to-answer (booking 24 h, quote 72 h, volunteer 7 days, admission 14 days).
The owner gets a **Requests inbox** shaped like the vendor orders inbox (New / Active / Done, realtime, quick replies: Confirm, Suggest a time,
Send a quote, Decline with a reason). The requester gets **My requests** with a timeline, and can leave a verified review only after DONE.
This replaces the current "open a chat with a prefilled line", which has no state and cannot be reviewed.

Audience features for organisations: Sync (follow) brings posts to the Feed, Events can carry an RSVP later, Programs carry an enquiry, Team shows
people with titles, Give (UPI details for an NGO) appears only after the registration document is checked by Bucks, and Bucks never handles money.

## 5. Owner experience
**Set up a page** (replaces "Add a business"): 5 steps, 5 required inputs.
1. What is it? Six group cards with one-line examples, plus "Just my skill" for the existing skill flow.
2. Type chips for that group, the name, the category picker (searchable, add your own), a duplicate-name notice.
3. Where and when: GPS-locked "create it where you are", hours presets.
4. Contact and registration: phone, website, registration number (optional, marked self-declared).
5. Review and create. The page is PENDING until go-live (pilot switch on: live at once).

**Dashboard** adapts: Go-live card counts only what the type needs; tiles are Requests, Catalogue (Products / Services / Programs / Events as the
type says), Team (roles from the type), Documents (only the types' documents), Give (NGO, later), Preview as customer.

## 6. Data model (one migration, idempotent)
- `listing_types(key, group_key, label, default_service, tabs[], cta, stat_keys[], roles[], fields jsonb, docs[], reg_doc, request_template jsonb)`.
- `listing_categories(key, type_key, parent_key, label, service, aliases[], starter_items jsonb)`; the free-text `listings.category` stays for search.
- `listings` += `type_key`, `category_key`, `tags[]` (max 8). Backfill: existing BUSINESS rows become Retail shop, or Online store when `ships_india`.
  The mock organisations get their types by `details.org_type`.
- `items.kind` += PROGRAM, EVENT. `jobs.job_type` += VOLUNTEER. `listing_members.role` += MEMBER (outside `can_manage_listing`, so policies stay).
- `service_rules` += 4 rows; `doc_types` += NGO_REG, TAX_12A, TAX_80G, FCRA, UDYAM, AFFILIATION, CLINICAL_REG, PRO_REG, all `required = false`
  (so no new page can be blocked on an empty staff table).
- Triggers: `listing_service_rules` derives the service from category then type and ignores the client's value; `listing_type_guard` checks type/kind,
  category belongs to type, type immutable once live, copies the category label into `category`; `orders_module_guard` rejects orders on non-shop types.
- `listing_requests` + RPCs `create_request`, `respond_request`, `my_requests`, `listing_requests_for`, cron expiry.

## 7. Apps
- Android: `ProfileSpecs.kt` (`specFor(kind, typeKey)` with the legacy spec when null), null-safe `serviceDef`, SetupWizardScreen, SchemaForm for
  About fields, ListingProfileScreen reads tabs and CTA from the spec, RequestSheet, RequestsInboxScreen, MyRequestsScreen, group chips in search,
  four Home tiles. iOS: the same screens in `BucksUI`, sharing the JSON spec.
- Ship the app's null-safe fallbacks **before** inserting the new service rows: old builds dereference `serviceDef(...)!!`.

## 8. Order of work and cut line
P0 (about 2 weeks): migration + backfill, type registry in both apps, profile shell by type, wizard, Products limited to shops, orders guard,
Home tiles and search chips, mock data re-typed, rolled-back scenario tests. P1 (about 1 week): Request object, inbox, My requests, Programs /
Events / Volunteer, Team titles, verified review from DONE. P2: Give, RSVP capacity, type change by staff, more roles.

## 9. Risks and what is not verified
- Nothing here was run on a device; the design review stage of the workflow that produced this did not finish, so the spec has not been attacked.
- Constraint names on the live DB must be looked up, not assumed, when extending `items.kind` and `jobs.job_type`.
- The pilot switch (`pilot_skip_checks`) makes every new page live at once; turn it off before real users.
- Legal check needed before Give is shown outside the invite-only pilot (FCRA, 80G claims).

## 10. Status (6 Oct 2026)
- Server: `supabase/migrations/page_types.sql` applied live. 13 types, 4 new Home tiles, type guard, items guard, orders guard, search returns
  `type_key` / `group_key`, mock data re-typed (NGO and schools hold Programs, groups hold Events, shops keep Products). Live scenario
  `supabase/tests/page_types_live_scenario.sql` passes: 14 checks, rolled back.
- Android: `ui/PageTypes.kt` registry; profile shell, cards, search chips, create wizard, edit, items and dashboard in progress on `pilot-release-fixes`.
- Not yet: the Request object and inbox (P1), Give, RSVP, listing_categories taxonomy (the free-text category picker covers it), iOS port of the shell.
