# Billing: provider licences on Razorpay Payment Pages

Providers renew a licence when they choose to. There is no Autopay and nothing is ever debited. Each skill page, business page and
vehicle has its own licence, with a code (`SK…`, `BZ…`, `TX…`) and a **VALID TILL** date shown on the provider's **Bucks ID** card.
Buyers and riders never pay Bucks.

| Plan | 1 month | 6 months | 12 months |
| --- | --- | --- | --- |
| Skills (one skill page) | ₹99 | ₹499 | ₹990 |
| Taxi (one vehicle) | ₹199 | ₹999 | ₹1,990 |
| Business (one business page) | ₹299 | ₹1,499 | ₹2,990 |

6 months is about one month free, 12 months about two months free (16–17% off).

Prices include GST. They live in `billing_plans` and can be changed there; the webhook tells the plan and length from the amount
paid, so **no two active plans may share a price** (a unique index enforces it).

New licences start free: **Founding Members** (joined before `founding_until`, first 500) get 3 free months, and renewals paid in the
9 months after that **count double** (pay 1 month, get 2, the same as half price on fixed page prices). Everyone after gets a
30-day free licence. A free period is given once per person and plan (hashed phone number) and once per vehicle plate.

Licences are sold **outside the app** (Google Play payments policy; Apple is stricter, see below): the SMS carries the payment page
link and the licence code, and the apps only show the code, the state and VALID TILL. Nothing in either app can mark a licence
as paid; the server decides from Razorpay's signed webhooks.

## What is in the code

| Piece | File | Does |
| --- | --- | --- |
| Database | `supabase/migrations/billing.sql` | Plans, licences, payments ledger, events, the SMS queue, holds, the daily job, webhook handling, owner and staff functions |
| Tests | `supabase/tests/billing_scenarios.sql` | Codes, founding and trials, the no-enquiry free month, one free period, reminders, lapse/grace/pause, payments by code and by phone, wrong plan, replays, founding double time, vehicles, staff, the SMS queue |
| Webhook | `supabase/functions/razorpay-webhook/index.ts` | Checks `X-Razorpay-Signature`, passes `payment.captured` to `billing_apply_event` |
| SMS | `supabase/functions/licence-notify/index.ts` | Sends the queued SMS through MSG91 (DLT templates); does nothing until configured |
| Android | `data/BackendBilling.kt`, `ui/screens/manage/PlanCard.kt`, `ui/screens/BucksIdScreen.kt`, `res/values/strings_billing.xml` | Licences on the Bucks ID card and below it, on the listing dashboard and on each vehicle. No prices, buttons or links |
| iOS | `BucksCore/BackendBilling.swift`, `BucksUI/Screens/Identity/BucksIdScreen.swift` | Licences on the Bucks ID card and below it: code, state, dates only |

## How a licence moves

```
listing goes LIVE / vehicle approved
  -> FOUNDING (3 free months) or TRIAL (30 days), or valid until today if a free period was used before
  -> 7, 3 and 1 days before VALID TILL: push + SMS "valid till 10 Apr, renew with code SK7K Q2MP: <page link>"
  -> VALID TILL passes: GRACE, still live 7 days, push + SMS
  -> grace over: EXPIRED (paused). Listing SUSPENDED with billing_hold, out of search, profile and recommendations kept;
     vehicle can't go online. Push + SMS, then win-back SMS 7 and 30 days later.
  -> a payment at any time: VALID TILL moves forward and the listing or vehicle is back at once
```

**No-enquiry guarantee:** when a *paid* licence reaches VALID TILL and its page got no enquiry through Bucks in the last 30 days
(no new chat about it and no order; for a vehicle, no ride or delivery it accepted), Bucks adds a free month instead of a lapse
notice, and tells the owner. Only while the page is LIVE or the vehicle ACTIVE, at most twice per licence in 365 days. Owners see
their 30-day enquiry count on the Bucks ID screen and the listing dashboard, so the value is visible before they decide to renew.

Paying while still valid (or in grace) adds to VALID TILL; paying after the pause counts from the day of payment. A listing held for a
document **and** for its licence comes back only when both are cleared.

**Matching a payment to a licence:** the code typed on the page (any form field, case and spaces ignored); if none matches, the
payer's phone when that person has exactly one licence of the plan paid for. Anything else (mistyped code with two licences, a
Taxi amount with a Skills code, an amount that is no plan) is stored as `UNMATCHED` for staff.

## Setup, in order

1. **Razorpay Dashboard**
   - KYC is done (Nov 2026). Submit the website or app for review if the account still shows "Limited" (needed for live keys).
   - Set the brand name to *Bucks* and add the logo, so the payment page and bank statements say Bucks.
   - Create three **Payment Pages** (Payment Pages > Create), one per plan, titled *Bucks Skills licence*, *Bucks Taxi licence* and
     *Bucks Business licence*. On each:
     - a description, for example (Skills): *"₹99 for 1 month, ₹499 for 6 months, ₹990 for 12 months. Enter the licence code shown
       on your Bucks ID card."* Taxi: ₹199 / ₹999 / ₹1,990. Business: ₹299 / ₹1,499 / ₹2,990;
     - three fixed-amount items: 1, 6 and 12 months at the prices above (only one can be chosen per payment);
     - a required text field **Licence code** (any field name works; the webhook reads every field);
     - the phone field required (it is the fallback when the code is mistyped);
     - Hindi and other languages switched on if offered.
   - Webhooks: URL `https://lboxctryrktwdsvywfqp.supabase.co/functions/v1/razorpay-webhook`, a long random secret, event
     **`payment.captured`** only.
2. **Database**: apply the stack as usual (`supabase/apply_all.sh`; `billing.sql` is last). Billing starts **off**.
3. **Page links** (SQL editor, as the project owner); the SMS sends the plan's 1-month row link:
   ```sql
   update billing_plans set page_url = 'https://rzp.io/rzp/…' where code = 'SKILL';
   update billing_plans set page_url = 'https://rzp.io/rzp/…' where code = 'TAXI';
   update billing_plans set page_url = 'https://rzp.io/rzp/…' where code = 'BUSINESS';
   ```
4. **SMS (MSG91)**: register the sender ID and six templates on DLT, with the page domain (`rzp.io` or `pages.razorpay.com`)
   whitelisted for links (TRAI requires every URL in an SMS to be registered). Then create the MSG91 Flow templates with the
   variables `##name## ##subject## ##code## ##date## ##grace_date## ##link##`. Suggested wording:

   | Kind | Text |
   | --- | --- |
   | START | Hi ##name##, your Bucks licence for ##subject## is free till ##date##. Your licence code is ##code##. -Bucks |
   | RENEW_SOON | ##subject##: your Bucks licence is valid till ##date##. Renew at ##link## with code ##code##. -Bucks |
   | LAPSED | ##subject##: your Bucks licence has expired. It stays live till ##grace_date##. Renew at ##link## with code ##code##. -Bucks |
   | PAUSED | ##subject## is hidden from Bucks search because its licence expired. Renew at ##link## with code ##code## and it is back at once. -Bucks |
   | WINBACK | ##name##, customers are still searching for you on Bucks. Renew ##subject## at ##link## with code ##code##. -Bucks |
   | PAID | Thank you. Your Bucks licence for ##subject## is valid till ##date##. -Bucks |

   Secrets:
   ```bash
   supabase secrets set RAZORPAY_WEBHOOK_SECRET=... MSG91_AUTHKEY=... MSG91_TEMPLATES='{"START":"…","RENEW_SOON":"…","LAPSED":"…","PAUSED":"…","WINBACK":"…","PAID":"…"}'
   supabase functions deploy razorpay-webhook --no-verify-jwt
   supabase functions deploy licence-notify --no-verify-jwt
   ```
   `licence-notify` uses the same shared secret as `notify` (`push_config.webhook_secret`), so push must already be set up
   (docs/PUSH_SETUP.md). pg_cron calls it every 15 minutes between 08:30 and 20:15 IST, only when messages are waiting. Until SMS is
   configured the push notes still go out, and field reps can share the page links and codes by hand.
5. **Switch on**, then give providers who are already live their licence:
   ```sql
   update billing_config set value = 'on' where key = 'enabled';
   select billing_backfill();
   ```
6. **Test end to end in test mode** with one listing and one vehicle: pay on the test page with the code, check VALID TILL on the
   Bucks ID card, and `select * from billing_payments order by paid_at desc` as the owner. Then repeat with live mode.

## Settings (`billing_config`)

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `off` | `on` starts licences, reminders and pauses |
| `trial_days` | 30 | Standard free licence |
| `grace_days` | 7 | Still live after VALID TILL |
| `founding_until` | 2027-03-31 | Last day to become a Founding Member (IST) |
| `founding_cap` | 500 | Most Founding Member licences |
| `founding_free_months` | 3 | Free months for Founding Members |
| `founding_bonus_months` | 9 | After the free months, renewals paid in this window count double |
| `reminder_days` | 7,3,1 | Reminders this many days before VALID TILL (largest first) |
| `winback_days` | 7,30 | SMS this many days after a licence was paused |
| `guarantee_min_enquiries` | 1 | A paid licence with fewer enquiries than this in its last `guarantee_days` gets a free month (`0` = off) |
| `guarantee_days` | 30 | The window counted, and the free days given |
| `guarantee_max_per_year` | 2 | Most free months per licence in 365 days |

## Staff, from the SQL editor until the web console exists

```sql
select * from billing_staff_view('Meena');                                  -- find a provider by name, Bucks ID, code, title or plate
select * from billing_payments where status = 'UNMATCHED' order by paid_at;  -- payments to sort out
select billing_staff_assign('pay_…', '<licence id>');                       -- apply a mistyped payment to the right licence
select billing_staff_refunded('pay_…', 'why');                              -- after refunding it in the Razorpay Dashboard
select billing_staff_extend('<licence id>', 30, 'referral month');         -- free days; a paused page comes back
select billing_staff_resend('<licence id>');                               -- send the renewal SMS again
select * from billing_events order by received_at desc limit 50;           -- every webhook and what it did
```
(`billing_staff_*` need a profile in `staff`; from the SQL editor read the tables directly or run as that profile.)

## Known gaps

- **Apple**: guideline 3.1.3(b)/(g) may require in-app purchase for visibility bought outside the app. The iOS screen shows only
  the code, state and dates, with no payment wording. Confirm with App Review before release.
- **Google Play**: the Android card says renewal details come by SMS, with no price, button or link. Have a Play policy
  specialist confirm the wording.
- **Translations**: the new Android strings are English only; other languages fall back to English.
- **GST invoices**: the ledger records the GST part; Bucks needs a GSTIN and tax invoices (confirm format and SAC with a CA).
- **Refunds** are recorded by staff only; a refund made in the Dashboard does not change VALID TILL by itself.
- **Staff console**: the functions exist; there is no screen yet.
