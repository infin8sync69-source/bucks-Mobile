# Recommendation algorithm: proof-weighted arrows

One gesture runs the whole app: **↑ recommended, ↓ not recommended**. It ranks shops, pros, products, services,
drivers, riders and posts, and it decides how far a post reaches. This document reviews what exists today, then sets out the
strategy, the maths and a phased build.

Status: proposal. The weights below are starting values to tune on pilot data, not settled numbers.

---

## 1. Where we are today (audit, October 2026)

### 1.1 Every place an arrow or a trust number exists

| Surface | Stored in | Who can vote | Gate | Weight | Feeds |
|---|---|---|---|---|---|
| Listing recommendation (profile arrows, `rate_listing`) | `reviews` (no order/task) → `listings.trust_up/down` | Anyone signed in, not the team | Listing LIVE, ≤30/hour | 1 | Search rank, badge, header count |
| Trip review (rider → driver, `review(p_task)`) | `reviews` with `task_id` → `listings.trust_up/down` | Rider of a completed trip | Trip completed, one per trip | 1 | Same as above |
| Order review (`review(p_order)`) | `reviews` with `order_id` | Buyer of a delivered order | Delivered, one per order | 1 | **Nothing: no screen calls it** |
| In-person recommend (QR scan, `recommend`) | `recommendations` | Account ≥14 days, home ≤3 km | 2-minute token, location | 1 | Go-live only (7 needed; 1 in pilot) |
| Product arrows (`rate_product`) | `product_ratings` | Anyone, not the store | ≤30/hour, no purchase needed | 1 | Product sort, card % |
| Post arrows | `post_votes` → `posts.up/down` | Anyone signed in | None (no visibility check, no rate limit) | 1 | Notifications only; **the feed ignores votes** |
| Document opinions | `doc_checks` | Account ≥14 days who opened the doc | ≤20/hour | 1 | Document card only, deliberately not trust |
| Driver → customer rating | **Nowhere**: local only, and it lands on the driver's own counters | – | – | – | Nothing |
| Person trust (`profiles.trust_up/down`) | Columns exist | – | – | – | **Never written: always 0** |
| Owner identity (`id_checked`) | `listing_documents` OWNER_ID verified | Staff | – | – | Byline pill only; not used as weight |

### 1.2 How the numbers are used to rank

- **Search** (`search_listings`): online first, then text match, then **net `trust_up − trust_down`**, then distance.
  A net count favours old, busy listings and lets 3 fake votes outrank a new honest shop.
- **Feed** (`feed`): newest first. The comment says "boosted by votes"; the code does not boost.
- **Driver dispatch**: distance only. Trust is fetched but unused.
- **Products**: client-side sort by percentage, then vote count.
- **"Top rated" / agent replies**: raw up count (cloud) or percentage (demo).
- `suggest_listings` (friends' recommendations first) exists on the server and is never called.

### 1.3 What is wrong

1. **The trust number is not trustworthy.** The direct vote (`rate_listing`) has no transaction, locality or account-age gate,
   and it moves search rank. Meanwhile the app's copy says "only reviews tied to a completed transaction count". That
   copy is false in the cloud build. Fix the copy or the rule before the pilot; I recommend fixing the rule.
2. **Four formulas for one idea**: net count (search), percentage (demo, products), raw up count (Top rated), rounded
   percentage (product cards).
3. **No weighting anywhere.** A day-old account counts the same as a verified customer of three years.
4. **Verified purchases never happen** because no screen calls `review(p_order)`.
5. **People have no trust.** Driver → rider ratings vanish; profile trust columns are dead.
6. **"Recommendations" means two different things**: the go-live count (QR scans) and the up-votes shown on the profile.
7. **The in-person gate trusts the phone**: home location and scan coordinates are client-supplied.
8. **Posts**: anyone can vote on any post id, including their own and ones they cannot see.
9. **Bookkeeping drifts**: listing trust is incremented in place (it already needed a repair), while the others are recounted.
10. **No tests** cover `rate_listing`, `rate_product`, post votes or document opinions.

---

## 2. Strategy

### 2.1 The idea in one line

> **Every arrow is weighted by who cast it and what they did. Reach and rank are earned from real people, never bought.**

Google Maps, JustDial and Zomato count stars from anyone and sell placement next to them. Bucks counts arrows from people
it knows to be real, weights each one by proof of an actual interaction, and personalises the result by the viewer's own
circle. That is the disruptive part, and it is also the part competitors cannot copy without giving up ad revenue.

### 2.2 Principles

1. **One gesture, many clocks.** The same arrow means different things on different subjects. A post's arrows measure
   relevance and fade in days. A shop's measure reliability and build up over a year. A driver's measure safety, where
   one serious ↓ matters more than ten ↑. Hence one table and one formula family, with a decay and asymmetry per subject type.
2. **Proof beats volume.** A ↓ from a buyer whose order arrived late outweighs ten ↑ from strangers.
3. **People earn credibility by being right.** A voter whose past arrows agreed with what verified customers later
   found gains weight; a voter who habitually disagrees with the evidence loses it.
4. **Reputation is portable across a person's pages.** Every page is "by" a real person, so a plumber with a strong record
   who opens a second page starts with that record as the prior, not from zero.
5. **New is not bad.** Too little evidence shows "New", never a red arrow. New pages get guaranteed exploration slots.
6. **Downvotes are accountable.** A ↓ on something you transacted with needs a reason. The owner can reply, and the
   voter can mark it resolved.
7. **No pay-to-rank, ever.** If sponsored slots ever exist, they are labelled, separate, and never touch the score.

### 2.3 The display rule

- Show **one arrow and one number: the larger side**, decided on *weighted* sums.
- The number is **people**, not weight (people understand "↓ 12"; they do not understand "↓ 7.4").
- Until there is enough evidence (weighted total under 3, roughly three verified customers), show **New**.
- On a business or a driver, the ↓ side is shown only once at least **3 different verified** people voted ↓. One
  competitor cannot turn a new shop red; a genuinely bad shop gets there within days.
- Tap the arrow and the split, the reasons and the comments open. Nothing is hidden, only summarised.

### 2.4 The comment box

- Every arrow tap opens it (built in build 91 for posts; listings and products already had it).
- **↑: optional.** Most people will not write, and forcing it suppresses honest positive signal.
- **↓ on something you transacted with: a reason chip is required** (Late, Quality, Price, Behaviour, Safety, Other), plus
  optional text. Reasons become structured insight for the owner and catch Safety reports for staff.
- **↓ on a post: optional.** A reason chip ("Misleading", "Spam", "Offensive") feeds moderation.

---

## 3. The maths

### 3.1 Voter credibility C(u), 0.05 to 1.0, recomputed nightly

```
C(u) = clamp( 0.20                                  phone-verified (everyone)
            + 0.20 · id_checked                     photo ID checked by staff (face check later: +0.10)
            + 0.15 · min(age_days / 90, 1)          account age
            + 0.20 · min(log2(1 + done) / 5, 1)     completed orders/trips/bookings, as buyer or seller
            + 0.25 · accuracy(u)                    see 3.4; 0 until 10 resolved votes
            − penalties(u),                          upheld reports, ring flags, velocity flags
          0.05, 1.0 )
```

A new account weighs about 0.2, a year-old active ID-checked user about 0.8.

### 3.2 Evidence E(vote)

| Proof behind the vote | E |
|---|---|
| Completed transaction with this subject (delivered order, finished trip, completed booking) | 1.00 |
| In-person QR recommendation | 0.80 |
| Saw it: opened the post or doc, or viewed the listing or product for ≥10 s in the last 30 days | 0.40 |
| No proof (direct vote) | 0.15 |
| Owner, team member, or the post's author | 0 (refused) |

### 3.3 Weight, decay and score

```
w(vote)  = C(voter) · E(vote) · decay(age; half_life[type]) · relation(voter, viewer)?   (relation only in personal rank)
W+ = Σ w over ↑,  W− = Σ w over ↓ (times asym[type] for ↓)

half_life:  POST 2 days · PRODUCT 365 · LISTING 365 · SKILL 365 · DRIVER 180 · PROFILE 365 · DOC never
asym (↓ multiplier): DRIVER safety-reason 3.0 · everything else 1.0
```

**Ranking score**: the Wilson lower bound on the weighted share of ↑, with a prior.

```
p  = (W+ + k·m) / (W+ + W− + k)          k = 3, m = prior mean
     m = owner's reputation (3.5) if the owner has any, else 0.70
n  = W+ + W− + k
score = (p + z²/2n − z·√(p(1−p)/n + z²/4n²)) / (1 + z²/n)      z = 1.28 (80%)
```

Why this one: a page with 4 verified ↑ and nothing else outranks one with 40 anonymous ↑ and 15 ↓. A page with 1 ↑ does
not outrank a page with 30 ↑ and 2 ↓. The prior keeps new pages near the middle rather than at the bottom.

### 3.4 Accuracy: credibility is earned by being right

When a subject has at least 10 verified (E = 1) votes, its verified ↑ share is its ground truth. For every voter who voted on it
**before** that point, record whether their arrow agreed with the truth. Then

`accuracy(u) = (agreements + 1) / (resolved + 2) · 2 − 1`, clipped at 0.

Early, honest voters gain weight; shills and grudge-voters lose it, without anyone accusing them of anything.

### 3.5 Owner reputation (portable)

```
R(owner) = weighted mean of score over the owner's pages (weights = n of each page) + conduct votes on the person (driver→rider, buyer↔seller)
```

R is used as the prior `m` for any new page by that owner, and it is shown on the byline sheet ("Raghu's pages: ↑ 214").

### 3.6 Where the score is used

| Place | Rule |
|---|---|
| Search and Services lists | `relevance · 0.5 + score · 0.35 + nearness · 0.15`, online first; 1 in 5 slots reserved for a "New nearby" page with no score yet |
| Personal rank (default lens) | Add `+0.15 · share of my synced people who voted ↑` (revives `suggest_listings`) |
| Feed | `recency(half-life 18 h) · (1 + 2·(score − 0.5)) · author C · relation (synced 2.0, same area 1.3)`; posts whose ↓ side is shown collapse behind "Not recommended · tap to show" |
| Post reach (earned in waves) | Wave 1: synced + 1 km. Wave 2 (3 km): after ≥5 weighted votes with score ≥ 0.6. Wave 3 (city): ≥20 with score ≥ 0.7. Never forced into feeds by money. |
| Driver dispatch | Ring order = distance band (500 m) then score; a driver with ≥2 Safety ↓ in 30 days is held for staff review |
| Products | Product sort by score; cart suggestions only from score ≥ 0.6 |
| Go-live | In-person recommendations stay a separate gate (people vouching a place is real) and do not inflate the score |

---

## 4. Anti-gaming

- One vote per person per subject; edits allowed with a 24 h cooldown, and history kept (no `created_at` reset).
- Velocity guard: if a subject gets more than 4× its usual daily weighted votes, new votes are held at weight 0 until a
  staff member or the nightly job clears them.
- Rings: pairs or small groups who mostly ↑ each other's pages and nobody else are flagged; their mutual votes are weighted ×0.1.
- Device and account clusters: many accounts on one device, or created within minutes and voting on the same subject.
- Server-side location: a QR scan must match the scanner's last server-seen location, not only the coordinates they send.
- Retaliation: the public sees "A verified customer" for ↓ votes (Bucks keeps the name); the owner can reply and report.
- Deleted accounts: their votes stop counting (today they keep counting).

---

## 5. Implementation plan

### Phase 0 (before the pilot, 2–3 days): honesty fixes

1. Call `review(p_order)` from the delivered-order screen (a "How was it?" arrow prompt) so verified buyers exist.
2. Store `verified` on `reviews`, and show "Verified customer" on those comments.
3. Gate `rate_listing` and `rate_product`: account at least 3 days old, and cooldown on edits; stop resetting `created_at`.
4. Post votes: check `can_see_post`, refuse your own posts, ≤60/hour.
5. Driver → rider rating goes to the server (a person-level vote; see Phase 1 table), not the driver's own counters.
6. Fix the false copy ("only transaction reviews count") until Phase 1 makes it true.
7. Apply the display rule from 2.3 (New until 3; ↓ shown only with 3 verified ↓) on unweighted counts for now.
8. Tests for all of the above (live rolled-back scenarios, same pattern as `page_types_live_scenario.sql`).

### Phase 1 (2–3 weeks): one vote table, weights, one score

- **`votes`**: `(id, subject_type, subject_id, voter_id, vote, reason, comment, evidence_type, evidence_id, created_at, updated_at, status)`,
  one row per voter and subject. Backfill from `reviews`, `product_ratings`, `post_votes` and `doc_checks`; the old RPCs become thin wrappers.
- **`voter_credibility`**: `(profile_id, c, parts jsonb, computed_at)`, nightly via `pg_cron`.
- **`subject_scores`**: `(subject_type, subject_id, up_n, down_n, w_up, w_down, score, shown_side, shown_n, verified_down_n, updated_at)`,
  updated by trigger on each vote (using the current credibility snapshot) and fully recomputed nightly.
- `listings.trust_up/down` and `posts.up/down` become generated from `subject_scores` (kept for the clients that read them).
- Search, the feed and dispatch read `score`. One Kotlin `VoteMark` and one Swift equivalent render `shown_side`/`shown_n`.
- Reason chips in the feedback box; ↓ reason required when there is a transaction.

### Phase 2 (pilot data, 4–8 weeks): learning and reach

- Accuracy (3.4), owner reputation as prior (3.5), earned-reach waves for posts, velocity and ring detection, owner replies and
  "resolved", collapsed ↓ posts, the "New nearby" exploration slot, personal rank from synced people.

### Phase 3 (scale)

- Face check raises C; a public "How Bucks ranks" page with the formula; a monthly transparency report (votes held, rings found);
  a per-subject "why this rank" view for owners.

### What to measure

- Share of weighted votes with proof (target: over 60% by end of pilot).
- Does score predict behaviour? Repeat orders, cancellations and complaints per score band.
- Time for a new honest page to get its first 3 verified votes.
- Share of ↓ with a reason; Safety reports per 1,000 trips.
- Reports of retaliation or brigading.

### Honest caveat

With about 100 pilot users there is not enough data for any weighting to be statistically meaningful. In the pilot, what matters is
the plumbing: every transaction ends in an arrow prompt, every vote records its proof, and the display never lies. Tune
the weights in Phase 2 on real data.
