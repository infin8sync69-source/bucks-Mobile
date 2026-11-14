# Payment rails, regulation and app-store rules for monthly provider subscriptions (Razorpay Subscriptions + UPI Autopay), India, as of Nov 2026

Scope note: research done 13 Nov 2026. About 23 tool calls. Primary sources fetched in full: the RBI E-mandate Framework 2026, the Google Play Payments policy and its explainer, Apple App Store Review Guidelines, and these Razorpay docs: payment retries, workflow, subscription webhooks, UPI recurring, pricing. Everything else comes from search-result summaries of secondary sources and is marked as such. "Background knowledge, verify" marks points from prior knowledge that I could not re-source this session.

## 1. RBI e-mandate framework (pre-debit notice, AFA limits, who notifies, modification/cancellation, 2025-26 changes)

### Takeaway
Since 21 April 2026 one consolidated RBI direction governs recurring debits on cards, PPIs and UPI: the "Digital Payments – E-mandate Framework, 2026" (RBI/DPSS/2026-27/396). It repeals the 2019-2024 circulars. Its rules: AFA at mandate registration and on the first debit; later debits up to ₹15,000 each need no AFA; the issuer (not the merchant) sends a pre-debit notice at least 24 hours ahead; customers can opt out of a debit, modify or withdraw at any time (with AFA); customers pay no charge. Every Bucks price point (₹99-₹4,990) is well under ₹15,000, so renewals need no AFA.

### Cited Findings
- Framework issued 21 Apr 2026 as RBI/DPSS/2026-27/396 and "effective immediately" (¶1(b)). It applies to all payment system providers and participants handling recurring transactions on cards, PPI or UPI, domestic or cross-border (¶2). — [RBI notification Id=13374](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Repealed (¶11): DPSS.CO.PD.No.447/02.14.003/2019-20 (21 Aug 2019, cards); DPSS.CO.PD No.1324/02.23.001/2019-20 (10 Jan 2020, UPI); DPSS.CO.PD No.754 (4 Dec 2020); CO.DPSS.POLC.No.S34 (31 Mar 2021); the IBA clarification (8 Oct 2021); S-518 (16 Jun 2022); S-882 (12 Dec 2023); S528 (22 Aug 2024). These older circulars are superseded. — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Registration: "The mandate shall be registered only after successful validation of additional factor of authentication (AFA)" (¶4(a)). The first transaction also needs AFA, which can be combined with registration (¶5(a)). — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- A mandate must state its validity period. The customer may change the validity or withdraw the mandate at any time, and must be told this at registration (¶4(b)). Mandates can be fixed or variable. Variable mandates sit under an RBI overall cap, and the customer may set a maximum per debit (¶4(c)). The text fetched did not state the cap. — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- "Any modification in, or withdrawal of, an existing e-mandate shall require AFA validation by the issuer" (¶4(e)). The customer can choose or change the channel for pre-debit notices, such as SMS or email (¶4(d)). — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Pre-transaction notification (¶6): the issuer sends it "at least 24 hours prior to the actual charge / debit". Minimum content: merchant name, amount, debit date/time, mandate reference number, and reason for the debit. The customer can opt out of a single transaction or the whole mandate. The issuer validates the opt-out with AFA and must confirm it to the customer (¶6(c)). FASTag and NCMC auto-replenish are exempt (¶6(d)). — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Post-transaction notification (¶7), sent by the issuer: merchant name, amount, date/time, transaction and mandate reference numbers, reason, and grievance details. — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Limits (¶8): (a) up to ₹15,000 per transaction without AFA, with AFA above that; (b) up to ₹1,00,000 without AFA for insurance premiums, mutual-fund subscriptions and credit-card bill payments. — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374); summarised by [Taxmann](https://www.taxmann.com/post/blog/rbi-e-mandate-framework-for-recurring-payments/), [Business Today, 22 Apr 2026](https://www.businesstoday.in/personal-finance/banking/story/now-control-your-auto-debit-payments-rbis-new-rules-explained-526860-2026-04-22)
- "No charges shall be levied to the customer for availing the e-mandate facility" (¶10(a)). Acquirers must make sure the merchants they onboard comply (¶10(c)). The issuer must run dispute redressal (¶9), and RBI's limited-liability rules for unauthorised transactions apply to e-mandate debits (¶9(b)). — [RBI](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=13374)
- Razorpay's UPI recurring docs repeat the rule that customers must be notified "at least 24 hours prior to initiating each debit". They do not say which party sends the notice. — [Razorpay UPI recurring](https://razorpay.com/docs/payments/recurring-payments/upi)

### Inferences
- The merchant has no legal duty to send the pre-debit notice. The issuer does: for UPI, that is the payer's bank/PSP app; for cards, the card issuer. In practice the merchant's gateway (Razorpay, as payee PSP/acquirer) triggers the notify call. The merchant's only job is to make sure the gateway has the charge scheduled at least 24 hours ahead. Bucks should still send its own in-app or WhatsApp reminder 2-3 days before renewal, because it reduces "surprise" revocations. That reminder is a product choice, not a legal requirement.
- Because the customer can opt out of any single debit or withdraw at any time, the backend must treat "mandate revoked or paused by customer" as a normal state, not an error.
- Fixed-amount monthly mandates at ₹99-₹4,990 never reach the ₹15,000 AFA ceiling. A plan upgrade that raises the amount above the mandate's maximum needs a new or modified mandate, and the customer must authorise it with AFA.

### Gaps
- The fetched text did not show the "overall cap" for variable mandates. It also did not settle whether "transaction reference number" belongs in the pre-debit notice; secondary sources disagree on that.

## 2. NPCI UPI Autopay: flow, success and failure rates, retries, execution windows, Reserve Pay, UPI Lite

### Takeaway
UPI Autopay mandates are created in the payer's UPI app (GPay, PhonePe, Paytm) with the UPI PIN. Debits up to ₹15,000 then run without a PIN. NPCI's 21 May 2025 API-discipline circular (in force from 31 Jul/1 Aug 2025) limits each execution to one attempt plus three retries. These debits may only run outside peak hours, which are 10:00-13:00 and 17:00-21:30. Failures come mostly from user behaviour rather than technical faults, chiefly low balance and revoked mandates. About 20 million mandates were revoked per month in 2025, and roughly 20% of subsequent debits fail.

### Cited Findings
- Flow: at registration the customer picks a monthly, weekly or as-presented frequency and a validity period, and sets the maximum amount. The token or mandate is created after the authorisation transaction. On each due date the acquiring bank/payee PSP sends a collect request. Example apps named: Google Pay, PhonePe, Paytm. Razorpay Subscriptions supports weekly, monthly, quarterly and yearly plans. — [Razorpay UPI recurring](https://razorpay.com/docs/payments/recurring-payments/upi)
- NPCI circular dated 21 May 2025 on 10 high-volume UPI APIs. Members had to comply by 31 Jul 2025 and give undertakings by 31 Aug 2025. Autopay execution is limited to one initial attempt plus three retries per mandate, run "at moderated TPS only during non-peak hours". Peak hours are 10 AM-1 PM and 5 PM-9:30 PM. Penalties include API restrictions and suspension of onboarding. These points come from secondary press, not the circular itself. — [Digit](https://www.digit.in/news/general/upi-alert-npcis-new-rules-kick-in-from-august-1-heres-what-changes.html), [Upstox](https://upstox.com/news/personal-finance/latest-updates/balance-checks-to-autopay-mandates-these-upi-transactions-will-face-restrictions-from-august-1/article-170413), [Taxscan](https://www.taxscan.in/upi-auto-pay-transactions-to-be-restricted-from-august-1-as-new-api-rules-kick-in/521991), [Paytm blog](https://paytm.com/blog/payments/upi/upi-rules-update-august-1-npci-new-guidelines)
- One source describes a 90-second minimum gap between retries, but ties it to status-check calls, not autopay execution. That point is unconfirmed for Autopay. — [Digit](https://www.digit.in/news/general/upi-alert-npcis-new-rules-kick-in-from-august-1-heres-what-changes.html)
- In Dec 2025 NPCI was reported to be reviewing changes to UPI Collect and Autopay after finding design gaps that fraud exploited. — [Angel One](https://www.angelone.in/news/market-updates/npci-plans-to-tighten-rules-on-upi-collect-and-autopay-to-combat-rising-fraud)
- About 20 million UPI Autopay mandates were revoked per month, mostly after debits failed for low customer balance (Sep 2025). — [Business Standard](https://www.business-standard.com/amp/finance/news/upi-autopay-revocations-hit-20-mn-monthly-over-low-customer-balances-125090700500_1.html)
- Razorpay says about 20% of subsequent debits fail, from insufficient balance, bank downtime or cancelled mandates. — [Razorpay blog](https://razorpay.com/blog/upi-autopay-vs-card-e-mandates/)
- A Feb 2026 report says low success comes mostly from user behaviour, insufficient balance, expired mandates and bank limits. Technical declines are about 0.5%. — [The Mainstream](https://themainstream.co.in/?p=105895)
- A vendor reports business-decline rates on AutoPay executions across the top 50 banks averaging about 74% in mid-2025, mainly from low balances. That is a vendor figure with no stated methodology. — [Cashfree blog](https://www.cashfree.com/blog/saas-payment-failures-india/). Vendor marketing claims: Setu says 94% transaction success ([Setu](https://setu.co/real-time-payments/upi/automate-collections)). Zoho models a 10% first-attempt failure rate as an assumption ([Zoho](https://www.zoho.com/payments/academy/payment-processing/upi-autopay-charges-limits-and-economics.html)).
- Mint describes the industry as rethinking Autopay because of persistent failures. — [Mint via Magzter](https://www.magzter.com/es/stories/newspaper/Mint-Ahmedabad/UPI-AUTOPAYS-ENDLESS-WOES-FORCING-AN-INDUSTRY-RETHINK)
- UPI Reserve Pay, formerly SBMD (Single Block Multiple Debit): the customer blocks an amount once and the merchant makes several partial debits against it. NPCI's maximum is ₹10,000, and one source cites a 90-day validity. No pre-debit notice is needed. Bank coverage started with ICICI and Axis savings accounts and is expanding. — [Pine Labs docs](https://www.pinelabs.com/docs/online-payments/upi-reserve-pay), [Pine Labs FAQ](https://www.pinelabs.com/docs/online-payments/upi-reserve-pay/faqs), [Lawrbit](https://www.lawrbit.com/article/what-is-new-in-upi-rules-2025-key-changes-you-should-know/), [Cashfree docs](https://www.cashfree.com/docs/payments/upi-reserve-pay/reserve-pay)
- PayU's "UPI NXT" pairs Reserve Pay with "UPI Autopay Interoperability", meaning mandate portability across acquirers. This is a provider announcement. — [search summary; PayU](https://payu.in/blog/wp-json/wp/v2/posts/16003)

### Inferences
- Debits will in practice be executed off-peak (after 21:30 or before 10:00, or 13:00-17:00), and "charged" webhooks can arrive hours after the scheduled time. Bucks should not drop a provider's listing at 00:00 on the due date. A grace window of at least 3-4 days fits the T+1 to T+3 retries.
- The four NPCI attempts (1 + 3) match Razorpay's T, T+1, T+2, T+3 card/UPI retry schedule (section 3). There is no room for extra merchant-side auto-retries on the same mandate within a cycle. Recovery after `halted` has to be a customer-initiated payment or a new mandate.
- Reserve Pay is a poor fit for monthly subscriptions (cap ₹10,000, short validity, limited banks). UPI Lite is for small on-device payments and cannot carry recurring mandates.

### Gaps
- I did not retrieve the NPCI circular text itself (NPCI circulars are PDFs on npci.org.in). The retry count and peak hours rest on consistent secondary reporting.
- UPI Lite and recurring payments: no source found this session. From background knowledge (verify), UPI Lite does not support Autopay mandates.
- Background knowledge, verify: NPCI circulars in 2025 required UPI apps to let users view and port all their Autopay mandates across apps (via the "UPI Help" / mandate-management feature, reported deadline about 31 Dec 2025). No source retrieved.
- I found no official NPCI success or failure statistics for Autopay. The only figures are from vendors and the press.
- Mandate-creation success rates by app (PhonePe, GPay, Paytm): no reliable published data found.

## 3. Razorpay Subscriptions specifics; alternatives

### Takeaway
Model: Plan (period, interval, amount) → Subscription (`total_count`, optional `start_at`, upfront addons, offer) → authentication transaction → active. With a future `start_at` and no upfront amount, the authentication charge is ₹5, refunded automatically. That is the usual free-trial pattern. A failed charge moves the subscription to `pending`, with UPI and card retries on T+1, T+2 and T+3. After that it moves to `halted`: invoices are still generated but not auto-charged, and reactivating does not re-bill missed invoices. Razorpay prices UPI subscriptions on request. Cards on subscriptions cost 0.9% on top of the 2% platform fee. GST is 18% on fees only, and settlement is T+1.

### Cited Findings
- Lifecycle: create Plan → create Subscription → customer completes the authentication transaction → Subscription activates when the billing cycle starts. Payments are auto-captured, and the card-validation authorisation payment is auto-refunded. Razorpay creates the customer record on a successful authentication. — [Razorpay workflow](https://razorpay.com/docs/payments/subscriptions/workflow.md)
- Authentication amount by case:
  - Immediate start, no upfront: Plan Amount
  - Future start, no upfront: ₹5, auto-refunded
  - Immediate start with upfront: Upfront + Plan
  - Future start with upfront: Upfront only
  - Immediate-start authentication amounts are not refunded.
  - Every case except future start with no upfront generates an invoice.

  — [Razorpay workflow](https://razorpay.com/docs/payments/subscriptions/workflow.md); also [search summary of docs](https://razorpay.com/docs/subscriptions/create/)
- Collection methods: Checkout (pass `subscription_id` to Razorpay Checkout), or Subscription Links (pick a Plan, add upfront amount and customer details, send by email and/or SMS, Razorpay-hosted page). Active subscriptions can be updated, paused, resumed or cancelled. — [Razorpay workflow](https://razorpay.com/docs/payments/subscriptions/workflow.md)
- An invoice is created at the start of each cycle and a charge is attempted. It stays `issued` until paid, then becomes `paid` and fires `invoice.paid`, and the customer gets an email. Razorpay warns: check charge status before providing or continuing services. — [Razorpay workflow](https://razorpay.com/docs/payments/subscriptions/workflow.md)
- Retries, cards and UPI: T=0 fails → `pending` → retries once a day on T+1, T+2, T+3 → `halted`. Emandate (NACH) retries only after the previous result arrives, which can take more than 24 hours. A bank-holiday charge moves to T-1, or to T-3 if T-1 is also a holiday. — [Razorpay payment retries](https://razorpay.com/docs/payments/subscriptions/payment-retries/). Note: the Singapore docs describe the schedule differently ("retried thrice, once every day for 3 days"). — [search summary](https://razorpay.com/docs/sg/payments/subscriptions/payment-retries.md)
- Halted: invoices are still created but not auto-charged, and you must charge them manually. Updating the card returns the subscription to `active`. The customer gets a payment-failure email with a hosted page where they can retry, update the card or switch method. Switching method is supported only from a card; UPI and emandate customers can switch only to a card. Setting `subscription_card_change` (1/0) controls card changes. — [Razorpay payment retries](https://razorpay.com/docs/payments/subscriptions/payment-retries/)
- Subscription webhook events:
  - `subscription.authenticated`: first payment made
  - `subscription.activated`: moved to active from authenticated, pending or halted; from pending or halted, only future invoices are charged
  - `subscription.charged`
  - `subscription.completed`
  - `subscription.updated`
  - `subscription.pending`: fires on each further failure
  - `subscription.halted`: retries exhausted
  - `subscription.cancelled`
  - `subscription.paused`
  - `subscription.resumed`

  Payloads carry the subscription entity, plus the payment entity if a payment was attempted. — [Razorpay subscription webhooks](https://razorpay.com/docs/webhooks/subscriptions.md), [search summary](https://razorpay.com/docs/webhooks/subscriptions)
- Signature: verify against the raw request body and do not parse it first. After rotating the secret, validate retries of older requests with the old secret. — [Razorpay subscription webhooks](https://razorpay.com/docs/webhooks/subscriptions.md)
- Pricing (Razorpay page): UPI 2% platform fee (UPI is zero-MDR by policy, so the 2% is called a platform fee); cards 2%, corporate cards 2.15%, international up to 3%. Subscriptions on cards: 0.9% plus platform fee. Subscriptions via UPI: "Pricing available on request". GST of 18% applies to Razorpay's fee only. Settlement T+1 or instant (instant is a separately priced add-on). — [Razorpay pricing](https://razorpay.com/pricing). Conflict: a Razorpay blog gives "2% + 0.99% subscription fee". — [Razorpay blog](https://razorpay.com/blog/cheapest-payment-gateway-for-recurring-billing-e-nach-upi-autopay-and-subscription/)
- UPI Autopay mandate creation is allowed up to ₹1,00,000 in Razorpay Subscriptions, though debits above ₹15,000 need AFA. — [search summary of Razorpay docs](https://razorpay.com/docs/payments/subscriptions/supported-payment-methods.md)
- Alternatives:
  - Cashfree Subscriptions: ₹7.5 per mandate creation, plus ₹5 per UPI AutoPay presentation under ₹1,000 or ₹15 for ₹1,000 and above. No setup fee or AMC. — [Cashfree pricing docs](https://www.cashfree.com/docs/help/account/pricing). Conflict: Cashfree's main charges page shows "₹7.5 + ₹7.5". — [Cashfree charges](https://www.cashfree.com/payment-gateway-charges/)
  - Checkout rates (third-party comparison, not autopay): Razorpay 2%, Cashfree 1.95%, PayU 2%, each plus GST. — [SureCart](https://surecart.com/blog/razorpay-vs-cashfree-vs-payu-wordpress-india/)
  - Setu markets UPI Autopay collections (94% success claim). — [Setu](https://setu.co/real-time-payments/upi/automate-collections)
  - Zoho warns that a "zero-MDR" recurring debit still carries platform fees, failed-attempt costs and recovery costs. — [Zoho](https://www.zoho.com/payments/academy/payment-processing/upi-autopay-charges-limits-and-economics.html)

### Inferences
- Free trial: create the subscription with `start_at` = trial end and no upfront amount. The customer pays ₹5 now, refunded automatically, and the first real charge falls on `start_at`. With an immediate start the customer pays the full first month at authentication.
- Bucks webhook handler, suggested mapping:
  - `subscription.charged` / `invoice.paid` → extend `paid_until`
  - `subscription.pending` → keep the listing live and show a "payment failed" banner (grace period)
  - `subscription.halted` → mark lapsed and prompt to re-pay or re-mandate
  - `subscription.cancelled` / `completed` → end at `current_end`
  - `subscription.activated` after halted → active, but missed invoices stay unpaid unless you charge them manually

  Store the event and payment IDs and process idempotently, since nothing in the docs guarantees delivery order.
- Fees, worked example (assuming the 2% UPI platform fee applies and the subscription add-on is extra): on ₹99 the fee is about ₹1.98 plus 18% GST ≈ ₹2.34, before any subscription surcharge. Cashfree's flat per-debit model (₹5 on sub-₹1,000) is worse for ₹99 plans (≈5%) and better for ₹4,990 plans (₹15 ≈ 0.3%). Get written quotes; Razorpay's UPI subscription pricing is "on request".
- Razorpay's hosted retry page cannot switch a UPI subscriber to a fresh UPI mandate (UPI can only switch to a card). For UPI recovery after halt, Bucks should create a new subscription or link.

### Gaps
- Webhook header name (`X-Razorpay-Signature`, HMAC-SHA256 with the webhook secret), the event-ID header, delivery retry policy and ordering: the subscription webhook page did not state these. Check razorpay.com/docs/webhooks/validate-test and the general webhook best-practices page. Background knowledge, verify: the signature is HMAC-SHA256 over the raw body in `X-Razorpay-Signature`; Razorpay sends `x-razorpay-event-id` for deduplication and retries failed deliveries for up to 24 hours.
- Offers on subscriptions (`offer_id`, number of discounted cycles), `customer_notify` and `notify_info` were not retrieved this session.
- Whether Razorpay itself sends UPI pre-debit notifications on the merchant's behalf: not stated in the docs fetched.
- PayU, Juspay and PhonePe PG subscription pricing: not found this session.

## 4. GST, invoicing, e-commerce operator rules, TDS u/s 194-O

### Takeaway
GST at 18% applies to gateway fees. Bucks's own monthly listing or visibility fee to providers is Bucks's own taxable supply of services. If Bucks is only selling its own service, not collecting money for providers' customer sales, then the e-commerce-operator machinery (CGST s.52 TCS, s.24 compulsory registration for ECOs, Income-tax s.194-O TDS) is very likely not triggered. Those rules cover operators that facilitate third-party supplies and collect the consideration.

### Cited Findings
- Razorpay charges 18% GST on its platform fee, not on the transaction amount. — [Razorpay pricing](https://razorpay.com/pricing)
- s.194-O TDS rate was cut from 1% to 0.1% from 1 Oct 2024 (Finance (No. 2) Act 2024). It applies to sales of goods or services "through" an e-commerce operator. There is a ₹5 lakh threshold for individual/HUF sellers who furnish PAN or Aadhaar, and a higher rate without PAN (5% per one source). — [ClearTax](https://cleartax.in/s/section-194o), [TaxGuru](https://taxguru.in/income-tax/section-194-o-amendment-lower-tds-rate-e-commerce-payments.html)
- CGST s.24(ix) and (x): persons supplying through an ECO, and ECOs required to collect TCS, must register regardless of turnover. s.52 TCS is a separate levy (secondary sources conflict: 1% vs 0.5% rate). — [TaxGuru](https://taxguru.in/income-tax/tds-obligations-e-commerce-operators-section-194-o.html), [TaxTMI](https://www.taxtmi.com/tmi_notes?id=1879)

### Inferences
- The fee is Bucks's own supply, likely online advertising or listing services. The 18% GST rate and the SAC classification (e.g. 998365/998366 for online advertising, or 9983 generally) are background knowledge; verify with a CA.
- 194-O and s.52 TCS apply when Bucks collects payment for providers' sales to consumers. A pure subscription paid by providers to Bucks falls outside them. If Bucks later takes bookings or payments on behalf of providers, both regimes switch on, and providers selling services through Bucks would also need GST registration under s.24(ix) (some service-supplier exemptions exist, background knowledge, verify).
- Registration threshold for Bucks itself: background knowledge, verify. ₹20 lakh aggregate turnover for services (₹10 lakh in special-category states), CGST s.22. Voluntary registration lets Bucks issue tax invoices, and providers who are registered can claim ITC.
- Invoices: each paid cycle needs a GST tax invoice (CGST Rule 46 fields: GSTIN, invoice number series, date, recipient GSTIN if B2B, SAC, taxable value, tax split, place of supply). Background knowledge, verify. Razorpay Subscriptions generates "invoices" for billing, but they may not be compliant GST tax invoices unless configured with GST details. Bucks may need its own invoice generator. Collect an optional provider GSTIN and state at signup to set place of supply (IGST vs CGST+SGST).
- The Income-tax Act, 2025 replaced the 1961 Act from 1 Apr 2026, so section numbers (including 194-O) may have been renumbered. Background knowledge, verify.

### Gaps
- No primary CBIC or GST Council notifications were fetched. The SAC code, threshold and invoice-rule points are unsourced this session and need CA confirmation.
- The current s.52 TCS rate is unverified because sources conflict.

## 5. Google Play and Apple App Store rules for provider subscriptions (listings and visibility)

### Takeaway
Google Play: the Payments policy exempts only physical goods, physical services, bill payments, P2P/auctions/donations and gambling. It does not list advertising or visibility as an exception. A paid "listing/visibility/boost" plan that unlocks in-app features is digital, so Play Billing is required by default. The alternatives in India are Google's alternative billing program (fee reduced by 4 points, e.g. 15% → 11%) or making the Android app consumption-only for paid status, with purchase on the web and no in-app links. Apple is explicit: under 3.1.3(g), buying ads or "boosts" displayed in the same app must use IAP. A provider plan bought on the web can only be shown as status on iOS, with no in-app call to action; the US storefront is the exception.

### Cited Findings
- Google Play Payments policy §2: Play-distributed apps "requiring or accepting payment for access to in-app features or services" must use Play billing, except under §3, §8, §9. §3 exceptions: "purchase or rental of physical goods", "purchase of physical services", credit card or utility bill remittance, "peer-to-peer payments, online auctions, and tax exempt donations", online gambling. Advertising is not listed as an exception. — [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)
- §4 anti-steering: "apps may not lead users to a payment method other than Google Play's billing system", covering listings, in-app promos, webviews, buttons, links, ads and sign-up flows. §8 allows alternative in-app billing in eligible countries after program enrolment, and §9 allows linking out where eligible. — [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)
- Google explainer: "Google Play allows any app to be consumption-only, even if it is part of a paid service". Consumption-only apps "do not enable users to purchase access to digital goods or services from within the app". Communicating outside the app (e.g. email) is allowed. Business productivity and financial software count as cloud services that require Billing. For India and South Korea, developers may offer an alternative billing system alongside Play billing, with the service fee reduced by 4% (e.g. 11% vs 15%). — [Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- The India alternative billing program is per-package enrolment in Play Console, separate from the User Choice Billing pilot. Developers may use web payments in an embedded webview. Alternative billing APIs became mandatory by a "Manual Sunset Date". — [Google Play Help 13306652](https://support.google.com/googleplay/android-developer/answer/13306652), [13821247](https://support.google.com/googleplay/android-developer/answer/13821247)
- History (older): after the CCI orders of Oct 2022, user choice billing was extended to all Indian developers from 26 Apr 2023. In Mar 2024 the CCI opened a probe into UCB fees (11-26%) but denied interim relief. CCI has argued at NCLAT that the 10-30% fees hinder developers. — [Inc42](https://inc42.com/buzz/following-cci-order-google-extends-user-choice-billing-indian-devs), [TechCrunch](https://techcrunch.com/2024/03/15/india-orders-antitrust-probe-into-google-app-store-practices/amp/), [Inc42 NCLAT](https://inc42.com/buzz/googles-10-30-service-fee-on-app-purchase-hindering-app-developers-cci-tells-nclat/), [ThePrint](https://theprint.in/india/india-starts-inquiry-into-google-payments-antitrust-compliance/1570509)
- 2026 Google fee overhaul: rollout from 30 Jun 2026 in the UK, US and EEA. The service fee is split from a 5% billing fee and starts at 10% on the first $1M. Japan and South Korea follow on 31 Dec 2026 and the rest of the world on 30 Sep 2027. India is not named, so it presumably falls in "rest of world". — [Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-news/google-play-revamps-billing-with-lower-developer-fees)
- Apple 3.1.1: unlocking features or functionality (subscriptions, premium access) requires IAP. — [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple 3.1.3 intro: apps in 3.1.3 "cannot, within the app, encourage users to use a purchasing method other than in-app purchase, except for apps on the United States storefront and as set forth in 3.1.1(a) and 3.1.3(a)". Out-of-app communications are allowed. — [Apple](https://developer.apple.com/app-store/review/guidelines/)
- Apple 3.1.3(b) multiplatform: users may access content, subscriptions or features acquired on other platforms or your website, "provided those items are also available as in-app purchases within the app". — [Apple](https://developer.apple.com/app-store/review/guidelines/)
- Apple 3.1.3(e): physical goods or services "consumed outside of the app" must use non-IAP methods. — [Apple](https://developer.apple.com/app-store/review/guidelines/)
- Apple 3.1.3(g): ad-management apps for advertisers do not need IAP, but "buying advertisements to display in the same app (such as sales of 'boosts' for posts in a social media app) must use in-app purchase". — [Apple](https://developer.apple.com/app-store/review/guidelines/)
- Apple 3.1.3(a) reader apps cover only magazines, newspapers, books, audio, music and video, so they do not apply to Bucks. 3.1.5 covers cryptocurrencies only and is not relevant. — [Apple](https://developer.apple.com/app-store/review/guidelines/)

### Inferences
- The fee is for visibility and listing inside the Bucks app, a digital service consumed in-app. That is not a "physical service": the provider's physical service is sold to consumers, but Bucks's product to the provider is digital. Neither store's physical-goods/services exemption reliably covers it, and Apple's 3.1.3(g) treats such purchases as needing IAP.
- Options, lowest store risk first:
  - **(a)** Sell provider plans only on a web dashboard (Razorpay). The Android and iOS apps show paid status read-only, with no price, buy button, link or "upgrade on web" text. Contact providers by email or WhatsApp outside the app.
    - On iOS this is a gray area. 3.1.3(b) technically requires the item to also be offered via IAP. Apps that only display status for an account bought elsewhere usually pass if nothing in the app references purchasing, but there is rejection risk. One mitigation is a separate "Bucks for Business" web-only product.
    - On Android, the consumption-only route is explicitly allowed.
  - **(b)** Android only: enrol in India alternative billing and run Razorpay in-app, paying Google roughly 11% (15% for subscriptions minus 4) on top of the Razorpay fee. Users must also be offered Play Billing.
  - **(c)** Use Play Billing / IAP for in-app purchases, at a 15% subscription fee, while keeping web sales.
- If plans are sold to providers via WhatsApp or sales reps (offline B2B onboarding), the risk falls further, as long as the apps contain no steering.

### Gaps
- The Apple page's last-updated date was not captured. Any 2026 Apple changes for India (e.g. entitlements or an alternative payment regime in India) were not found.
- The current status of the CCI investigation and NCLAT appeal in 2025-2026 was not found, and the search returned nothing dated 2026.
- Whether Google treats "business listing visibility" as an advertising exception: no explicit statement found. Google's policy is silent on ads.

## 6. DPDP Act 2023 / DPDP Rules 2025

### Takeaway
The DPDP Rules were notified on 13/14 Nov 2025 with a staggered start. Most Data Fiduciary duties (notice, security safeguards, breach reporting, retention and erasure, children's data) apply 18 months after notification, around 13-14 May 2027. The SPDI Rules 2011, which cover passwords and financial data, apply until then. Bucks stores phone numbers, names and Razorpay customer, subscription and payment IDs, and should build DPDP-grade consent notices, security and retention now.

### Cited Findings
- Rules notified 13 Nov 2025 per Khaitan, 14 Nov 2025 per the PIB press note. Rules 1, 2 and 17-21 (the Data Protection Board) took effect immediately. Rule 4 (consent managers) takes effect after 1 year (about 14 Nov 2026). Rules 3, 5-16, 22 and 23 take effect after 18 months (13/14 May 2027). — [Storyboard18](https://www.storyboard18.com/amp/digital/breaking-govt-notifies-final-dpdp-rules-sets-staggered-rollout-with-key-obligations-for-data-fiduciaries-84201.htm), [PIB doc](https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf), [Anantam IAS](https://anantamias.com/current-affairs/dpdp-rules-2025-notified/?pdf=1)
- The 18-month provisions cover notice, security safeguards, breach reporting, retention, children's data, SDF obligations, international transfers, the research exemption and government information powers. — [AZB Partners](https://www.azbpartners.com/bank/indias-digital-personal-data-protection-act-phased-rollout-and-key-compliance-milestones/)
- The SPDI Rules 2011 stay in force for the 18-month transition. — [Legal500 / Saga Legal](https://www.legal500.com/firms/237811-saga-legal/c-india/news-and-developments/the-privacy-timer-starts-now-analysing-the-dpdp-rules-and-its-18-month-countdown)
- The Rules prescribe no fixed timeline for notifying Data Principals of a breach; the Board timeline differs. — [India Briefing / Khaitan summary](https://www.india-briefing.com/news/dpdp-rules-2025-india-data-protection-law-compliance-40769.html)

### Inferences
- Do not store card or bank numbers. Keep only Razorpay IDs (customer_id, subscription_id, payment_id, token/mandate id), plan, status, amounts and dates. Razorpay, a PCI-DSS entity and RBI-authorised PA, holds the instrument data. RBI's card-on-file tokenisation rules (background knowledge) already bar merchants from storing card data.
- The phone number is personal data. It needs a clear itemised notice at signup (purpose: account and billing communications), and marketing consent should be separate. Restrict access by RLS, encrypt at rest (Supabase default), and log access.
- Retention conflict: DPDP requires erasure once the purpose ends. GST law requires keeping invoices and accounts, background knowledge says for about 72 months from the annual-return due date (CGST s.36). Keep invoice records under a legal-obligation basis, and delete or anonymise other provider data on account closure.
- Breach response: plan for notifying both the Data Protection Board and affected users. CERT-In's 6-hour incident reporting (2022 directions) also applies (background knowledge, verify).

### Gaps
- The exact Rule numbers for retention periods and breach timelines (e.g. the 72-hour Board report) were not verified from the gazette text this session.
- I did not check whether the RBI payment-data localisation circular (Apr 2018) imposes anything on a merchant that holds only gateway IDs. Background knowledge suggests it binds payment system operators, not merchants.
