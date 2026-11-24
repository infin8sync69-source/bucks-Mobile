# Reminders, notifications and dunning for a ₹99–₹499/month provider subscription (Razorpay Subscriptions + UPI Autopay, India, as of Nov 2026)

Research date: 2026-11-13. Most numbers below come from vendor blogs or secondary reporting; primary sources are marked. Anything not marked as a primary source should be re-checked before it goes into a budget or a compliance sign-off.

## Channels and regulation in India (SMS/DLT, WhatsApp, Razorpay's own notifications, push, RCS, IVR)

### Takeaway
SMS still works for bulk messages, but every header, template, URL and callback number has to be pre-registered on DLT. Costs run about ₹0.15–0.25 per SMS. A WhatsApp utility template costs about ₹0.115 since 1 Oct 2026, and utility messages sent inside the 24h service window are no longer free. Razorpay already sends its own SMS and email for most subscription events. The bank or UPI app sends the RBI-mandated pre-debit notice, not the merchant. So Bucks's own messages should add to these, not repeat them.

### Cited Findings
**SMS / TRAI DLT**
- **Feb 2025 amendment.** TRAI notified the TCCCPR (Second Amendment) Regulations, 2025 on 12 Feb 2025 (TRAI press release No. 11/2025). It standardised header suffixes: -P promotional, -S service, -T transactional, -G government. Operators append the suffix based on the registered template type during DLT scrubbing. — [TRAI PR 11/2025](https://cms.trai.gov.in/sites/default/files/2025-02/PR_No.11of2025.pdf) (primary; the fetch failed, so details come from [JSA summary](https://www.jsalaw.com/wp-content/uploads/2025/02/JSA-Prism-Telecommunications_February-2025_TCCCPR-amendments.Final_.pdf) and [Tanla](https://www.tanla.com/udayreddy/trai-mandates-new-message-suffixes-heres-what-you-need-to-know))
- **Suffix rollout.** Reported as live from about 6 May 2025. COAI later said all TSPs had implemented it. — [Storyboard18](https://www.storyboard18.com/how-it-works/why-your-sms-now-looks-like-a-code-trais-new-message-format-explained-70270.htm); [Voice&Data/COAI](https://www.voicendata.com/opinion/coai-comments-on-header-suffix-rules-for-messages-9499026)
- **Service Explicit category.** The Feb 2025 amendment reportedly discontinued the "Service Explicit" category, leaving Promotional, Service (implicit) and Transactional. — [Message Central India SMS guideline](https://www.messagecentral.com/sms-guideline/india) (vendor)
- **Complaint thresholds.** The amendment reportedly extended the complaint window to 7 days. Action against a sender is triggered by 5 complaints in 10 days. — [Storyboard18](https://www.storyboard18.com/how-it-works/trai-tightens-rules-against-spam-introduces-provision-of-stricter-penalties-56616.htm)
- **URL/APK/OTT whitelisting.** From 1 Sep 2024, any URL, APK or OTT link in an SMS must be whitelisted on DLT before sending. Shortened URLs must be whitelisted too. Operators were told to block SMS with unregistered URLs by end Sep 2024 and to implement message traceability by 31 Oct 2024. — [Tanla explainer](https://tanla.com/blog-posts/trais-whitelisting-directive-explained-everything-you-need-to-know); [Zoho community notice](https://help.zoho.com/portal/en-gb/community/topic/important-update-new-trai-guidelines-for-sms-campaigns-24-9-2024?page=1)
- **Callback numbers: dates conflict.** Zoho says callback numbers were also covered from 1 Sep 2024. Tanla says callback-number rules would come later. — [Zoho](https://help.zoho.com/portal/fr/community/topic/important-update-new-trai-guidelines-for-sms-campaigns-1) vs [Tanla](https://tanla.com/blog-posts/trais-whitelisting-directive-explained-everything-you-need-to-know)
- **Whitelisting cost.** Free for enterprises on at least one DLT platform (Vodafone Idea's). — [Tanla](https://tanla.com/blog-posts/trais-whitelisting-directive-explained-everything-you-need-to-know)
- **Promotional time window.** Promotional SMS is limited to 10 AM–9 PM IST, with DND scrubbing. Transactional and service messages can go 24/7. — [Message Central](https://www.messagecentral.com/sms-guideline/india) (vendor; the 9 AM vs 10 AM start is not verified against the TCCCPR text)
- **SMS cost.** MSG91 list rates are reported at about ₹0.25/SMS for 5,000 messages, falling to ₹0.16 at about 9.6 lakh, with negotiated rates near ₹0.13. 18% GST is extra. — [getpulsesignal](https://getpulsesignal.com/pricing/msg91). Typical transactional range is ₹0.15–0.25 — [richautomate](https://richautomate.in/blog/sms-api-pricing-india-2026). Reported OTP costs: MSG91 about ₹0.15, Gupshup about ₹0.17, Kaleyra about ₹0.18 — [Message Central blog](https://www.messagecentral.com/blog/sms-otp-pricing-india) (competitor blog)
- **DLT approval time.** Header and template approvals take about 24–48h and carry small one-time fees. — [richautomate](https://richautomate.in/blog/sms-api-pricing-india-2026)

**WhatsApp Business Platform**
- **Pricing model.** Meta charges per delivered template message, with marketing, utility and authentication categories (plus authentication-international). Utility and authentication have monthly volume tiers that reset monthly; marketing has none. — [Meta pricing docs](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing.md) (primary)
- **Utility inside the service window.** Free from 1 Jul 2025. From 1 Oct 2026 the pricing type changed from `free_customer_service` to `regular`, so these messages are now charged. A free tier of 1,000 service messages per phone number per month started the same day. — [Meta pricing docs](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing.md) (primary)
- **India timeline.** India's marketing rate rose on 1 Jan 2026. India billing localisation means accounts must move to INR by 31 Dec 2026, or delivery stops on 1 Jan 2027. The authentication-international rate rose on 1 Apr 2026. — [Meta pricing docs](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing.md) (primary)
- **India rates from 1 Oct 2026.** Utility and service ₹0.115 per delivered message. Marketing ₹0.8631, which was ₹0.7846 before 1 Jan 2026. Taxes are extra. — [TelecomTalk](https://telecomtalk.info/whatsappbusiness-price-reveal-telegram-arattai-may-benefit/1012403/); [baat.ai](https://baat.ai/blog/whatsapp-pricing-per-message). AiSensy lists ₹1.09 marketing and ₹0.145 utility, which probably include its markup — [AiSensy](https://m.aisensy.com/blog/whatsapp-api-new-pricing/). The official INR rate card was not opened directly.
- **Click-to-WhatsApp ads.** These open a free entry-point window of up to 7 days in which all categories are free. — [Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing.md)

**Razorpay's own notifications** — [Razorpay Subscriptions notifications](https://razorpay.com/docs/payments/subscriptions/notifications.md) (primary)
- **Events covered.** Razorpay sends email and SMS to customers on: Created (auth link), Initialized (auth paid), Charged Successfully, Completed, Charge Failed (every move to pending, with an "Update Card" option), Card Updated, Invoice Charge (manual charge, incl. halted → active), Halted (with "Update Card"), Cancelled, and Subscription Updated.
- **What the docs don't say.** They don't say whether these notifications can be disabled, or exactly when they are sent.

**Pre-debit notice (RBI)**
- **RBI rule.** The issuer (bank or UPI) must notify the customer at least 24h before each recurring debit. The notice must carry merchant name, amount, date/time, mandate reference and reason. Post-debit alerts must also carry grievance-redressal details. — [ecorpit summary of RBI Digital Payments E-mandate Directions 2026](https://ecorpit.com/rbi-e-mandate-directions-2026-recurring-payments-engineering-checklist/) (secondary); [RBI notification PDF](https://rbidocs.rbi.org.in/rdocs/notification/PDFs/396MDD002E435ECA145509929FC3ACBCFD0E9.PDF) (primary)
- **2026 Directions.** Issued 21 Apr 2026 (RBI/DPSS/2026-27/396) and effective immediately. They allow no-AFA debits up to ₹15,000 per transaction. They let the customer opt out of a single debit or the whole mandate, with AFA. — [ecorpit](https://ecorpit.com/rbi-e-mandate-directions-2026-recurring-payments-engineering-checklist/)
- **Razorpay flow.** Razorpay sends the PDN through the issuing bank and by default debits about 25h after the PDN is delivered. NPCI allows up to 3 retries against one PDN. Creating a charge on the last day of the cycle fails because the PDN needs 24h. — [Razorpay UPI recurring docs](https://razorpay.com/docs/payments/recurring-payments/upi.md); [Razorpay subsequent payments](https://razorpay.com/docs/payments/payment-gateway/s2s-integration/recurring-payments/upi/subsequent-payments?preferred-country=IN)

**Push**
- **Android 13 permission.** From Android 13, apps must request the POST_NOTIFICATIONS runtime permission before sending notifications. — [Android Open Source Project](https://source.android.com/docs/core/display/notification-perm); [Android Developers tips](https://medium.com/androiddevelopers/top-tips-for-adopting-androids-notification-permission-bf69afd677b8)
- **Opt-in rates.** Average Android 13 opt-in is about 60%, down from 80–90% before Android 13. It ranges from 76% in gaming to 43% in EdTech. — [Netcore study](https://netcorecloud.com/?p=94067) (global, not India-specific)

**RCS**
- **Jio.** Tiered RCS pricing from Sep 2026: marketing ₹0.27–0.30, transactional ₹0.25, OTP ₹0.11–0.16 per message. The earlier flat rate was ₹0.08–0.10. — [Inc42](https://inc42.com/buzz/jio-introduces-new-rcs-business-messaging-rates-for-iphone-users-in-india/)
- **Airtel.** Reported at about ₹0.11 per message on Google's platform, with an 80:20 revenue share. — [Angel One](https://www.angelone.in/news/market-updates/airtel-and-google-partner-to-bring-rcs-messaging-to-india)
- **Vi.** No published rate was found, and Vi support is described as limited.

### Inferences
- **Utility cost now matches SMS.** At ₹0.115 for a WhatsApp utility template vs about ₹0.15–0.25 for SMS, utility WhatsApp costs about the same as SMS or less, with better trust signals (verified business name, buttons). Use WhatsApp first for users who opted in, and fall back to SMS.
- **Register everything before launch.** Register the SMS sender header as Service-Implicit or Transactional ("-S" or "-T"). Whitelist on DLT every URL domain to be used: rzp.io, the Bucks domain and any short-link domain. Messages with unregistered links will be blocked silently.
- **Don't duplicate Razorpay.** Razorpay already sends "charged" and "failed" SMS and email, and the bank or UPI app sends the PDN. Bucks's own messages should add context (the listing name, leads earned) and give one clear action. They should not send a second receipt for every event.
- **Push is status-only.** Plan for about 40% of Android 13+ users never granting notification permission, so push cannot be the only channel for payment-critical messages.

### Gaps
- **Primary texts not read.** The TRAI PR/TCCCPR PDF itself was not read (the fetch failed). The promotional time window (9 vs 10 AM), the exact definition of "service implicit", and the callback-number whitelisting date are all unverified.
- **No primary WhatsApp India rate.** Meta's official INR rate card was not opened, so the ₹0.115 / ₹0.8631 figures rest on TelecomTalk/baat.ai.
- **Not researched.** IVR/voice cost for low-literacy users (Exotel/Kaleyra pricing) and iOS push best practices were not covered for lack of time.
- **Razorpay settings unclear.** No source says whether Razorpay subscription SMS can be switched off or branded.

## Cadence and timing

### Takeaway
Razorpay fixes the retry schedule for UPI Autopay: fail at T, retries at T+1, T+2 and T+3, then halted. Bucks's messages should line up around those retries. Common advice is 3–5 dunning messages over 7–14 days. NPCI reportedly blocks AutoPay execution at 10:00–13:00, which affects when debits land.

### Cited Findings
- **Retry schedule.** For cards and UPI Autopay, a charge that fails on day T moves the subscription to `pending`. Razorpay retries on T+1, T+2 and T+3, then moves it to `halted`. eMandate retries wait for bank confirmation, which can take more than 24h. Bank holidays shift the charge to T-1 (or T-3 if T-1 is also a holiday). — [Razorpay Payment Retries](https://razorpay.com/docs/payments/subscriptions/payment-retries.md) (primary)
- **Recovering a halted subscription.** Once halted, invoices are still created but not auto-charged. The customer must retry manually or change the payment method. When the subscription goes from pending or halted back to active, only later invoices are charged. — [Razorpay webhooks](https://razorpay.com/docs/webhooks/subscriptions.md) (primary)
- **NPCI execution windows (2026).** NPCI's 2026 "Traffic Management" framework reportedly restricts AutoPay execution during 10:00–13:00. Banks are told to move recurring debits to before 10:00, 13:00–17:00, or after 21:30. — [Republic World](https://republicworld.com/business/upi-autopay-failure-morning-peak-hours-npci-new-rules-2026) (single news source, no circular cited)
- **Number of messages.** Reported as 3–5 dunning emails, or 4–5 over 10–14 days, with the first on the day of failure. These figures are attributed to Chargebee or Recurly but couldn't be verified. — [dev.to insightlab](https://dev.to/insightlab/the-dunning-email-sequence-that-recovers-30-of-failed-payments-2edh); [lowcode.agency](https://www.lowcode.agency/blog/build-dunning-email-sequence-for-failed-payments)
- **Retry days.** Days 1, 3, 5 and 7 are attributed to Recurly as optimal retry days. Emails should go just before or after a retry. — [dunningcompare](https://dunningcompare.pages.dev/stats/dunning-recovery-statistics-2026) (secondary)
- **Promotional quiet hours.** Promotional SMS is limited to 10:00–21:00 IST (see the first section).

### Inferences
Proposed schedule, synthesised from the sources above. It is not a published benchmark.

**Trial ending**
- **T-3 days:** WhatsApp/SMS "Your free trial ends on {date}. ₹{amt}/month starts then, via UPI Autopay."
- **T-1 day:** push only.
- A 10-day reminder is only worth sending for trials of 14 days or more.

**Pre-debit**
- The bank or UPI app sends the PDN, so Bucks needs nothing extra unless it is the first debit after the trial.
- Optionally, on T-1 send push or WhatsApp: "Keep ₹{amt} in your linked account tomorrow."

**Charge success**
- Rely on Razorpay's SMS/email receipt, plus a push or in-app status update.
- Monthly, optionally send one WhatsApp utility "value receipt" (leads earned this month).

**Failed payment (UPI)**
- **T+0, within an hour of `subscription.pending`, 10:00–20:00 local:** WhatsApp/SMS explaining the likely cause, with one action.
- **T+2:** a second reminder.
- **T+3 / on `halted`:** a "pay once via link" message.
- **Grace period:** reminders on day 5 and day 7 of the grace period.
- That is 3–4 Bucks messages in total, plus Razorpay's own.

**Win-back**
- 7, 30 and 60 days after cancel or halt.
- Each needs marketing-category consent (WhatsApp marketing template, or promotional SMS within 10:00–21:00).
- Stop after 3.

**Send times**
- Avoid 10:00–13:00 for debits.
- For drivers and shop owners, messages around 08:00–09:30 or 19:00–21:00 are plausible, but no India-specific study was found.

### Gaps
- **No India-specific timing study.** I found no evidence on the best time of day or week to reach Indian small-business owners or drivers. OneSignal, CleverTap and MoEngage India benchmarks didn't turn up.
- **Fatigue data missing.** I found no evidence on the opt-out or fatigue threshold for transactional WhatsApp/SMS in India.
- **No primary NPCI circular.** I couldn't find NPCI's circular on the 2026 execution windows.

## Dunning benchmarks and India/UPI recovery tactics

### Takeaway
Published recovery rates vary widely. They run about 25–57% with automated retries and about 45–70% when retries are combined with good messaging. Almost all come from vendors or second-hand attributions. I found no UPI-specific recovery benchmark.

### Cited Findings
- **Recurly's metric.** Recurly defines dunning recovery rate as the % of renewal invoices that entered dunning and were recovered during the dunning window, and benchmarks it per industry. — [Recurly docs](https://docs.recurly.com/docs/dunning-benchmarks) (primary)
- **Recurly figures (second-hand).** A median of 34% of failed charges recovered is attributed to Recurly's 2025 report — [StealthAgents](https://stealthagents.com/research/ai-subscription-billing-automation-statistics-2026). A 47.6% median is attributed to Recurly via Slicker — [Orb](https://www.withorb.com/blog/dunning-failed-payment-recovery-statistics). Both are unverified secondary attributions.
- **Stripe.** Stripe's aggregate is reported as about 55–57% of failed recurring payments recovered, and Smart Retries are claimed to recover about 9% more than a fixed schedule. Stripe counts recoveries by any means (including emails), not just retries. — [Stripe docs on recovery analytics](https://docs.stripe.com/billing/revenue-recovery/recovery-analytics) (metric definition is primary; figures via [flycode](https://www.flycode.com/blog/stripe-smart-retries-adaptive-acceptance-explained-2026))
- **Independent B2C estimates.** Smart Retries alone recover 25–35% — [Redux Payments](https://www.reduxpayments.com/blog/stripe-smart-retries-explained) (vendor). One developer saw 38% from retries alone and 44–46% with a 3-step sequence added — [dev.to](https://dev.to/toolkitonline/how-we-recovered-47-of-failed-stripe-payments-without-hiring-a-csm-3ehj).
- **Email effect.** One email recovers about 12–18%, vs 28–35% for a 5-email sequence. About 25% of Chargebee dunning recoveries reportedly come via the update-payment link rather than a retry. — [dunningcompare](https://dunningcompare.pages.dev/stats/dunning-recovery-statistics-2026) (secondary)
- **Halted = manual action.** Once a Razorpay subscription is halted, recovery requires customer action (manual pay or method change), so messaging is the only recovery lever at that point. — [Razorpay](https://razorpay.com/docs/payments/subscriptions/payment-retries.md)
- **UPI specifics.** NPCI's RuPay/UPI AutoPay failure template says the transaction failed "due to <Reason for decline>", so a reason code is available. — [NPCI circular](https://www.npci.org.in/PDF/npci/rupay/2022/Circular-RuPay-AutoPay-AFA-Limit-enhancement-and-compliance.pdf). Insufficient balance at debit time is the commonly cited cause, and users are advised to keep balance 24h before the debit — [Whalesbook](https://www.whalesbook.com/news/English/personal-finance/RBI-Autopay-Rules-Explained-How-to-Avoid-Payment-Failures-on-Subscriptions-and-Bills/69107474f204a604cc5e696d) (low-quality source). The customer can also skip a single debit or revoke the mandate from their UPI app after the PDN — [Razorpay](https://razorpay.com/docs/payments/recurring-payments/upi.md); [ecorpit](https://ecorpit.com/rbi-e-mandate-directions-2026-recurring-payments-engineering-checklist/).

### Inferences
- **Pick the tactic from the failure reason.** Read `payment.error_code` / `error_reason` from the `subscription.pending` payload, which includes the payment entity:
  - Insufficient funds: "top up by {retry date}" (tomorrow's retry is automatic).
  - Mandate revoked or paused by the user: "re-approve Autopay" link (new subscription link).
  - Bank or UPI app down: "nothing to do, we'll retry tomorrow".
  - After halt: "pay ₹{amt} once via this link" (Razorpay payment link on rzp.io), then offer to set up Autopay again.
- **Low prices may help.** At ₹99–₹499, debits sit well below the ₹15,000 no-AFA limit, so AFA prompts are not a failure cause. Recovery rates for low-value UPI debits may be higher than card-based SaaS benchmarks, but this is unverified.

### Gaps
- **No India or UPI benchmark.** No Razorpay, Cashfree or NPCI data was found on UPI Autopay failure rates by reason, or on recovery rates.
- **No primary dunning reports.** The original Recurly, Chargebee and Paddle reports were not found, and all their numbers are second-hand.

## Copy, personalisation and trusted links

### Takeaway
I found no published, sourced examples of effective English or Hindi dunning copy for India. The drafts below are illustrations built from the regulatory rules above, not tested copy.

### Cited Findings
- **Fixed templates.** SMS templates must be pre-registered on DLT with variable placeholders, and the URL domain must be whitelisted. — [Tanla](https://tanla.com/blog-posts/trais-whitelisting-directive-explained-everything-you-need-to-know)
- **WhatsApp categories.** WhatsApp templates are categorised as utility or marketing. Win-back or promotional wording pushes a template into the marketing category (₹0.8631 vs ₹0.115). — [Meta pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing.md); [TelecomTalk](https://telecomtalk.info/whatsappbusiness-price-reveal-telegram-arattai-may-benefit/1012403/)
- **Visible sender suffix.** The -S/-T suffix now appears in the sender header, which gives users a visible signal of a registered service or transactional sender. — [Storyboard18](https://www.storyboard18.com/how-it-works/why-your-sms-now-looks-like-a-code-trais-new-message-format-explained-70270.htm)

### Inferences
**Draft copy (illustrative only)**
- **EN (pending, low balance):** "Hi {name}, ₹{amt} for your Bucks listing '{listing}' couldn't be collected today. Please keep ₹{amt} in your UPI-linked bank account; we'll try again automatically tomorrow. No need to share any OTP or PIN. –Bucks"
- **HI:** "नमस्ते {name}, आपकी Bucks लिस्टिंग '{listing}' के ₹{amt} आज नहीं कट पाए। कृपया अपने UPI से जुड़े खाते में ₹{amt} रखें, हम कल अपने-आप दोबारा कोशिश करेंगे। कोई OTP या PIN किसी से शेयर न करें। –Bucks"
- **EN (halted):** "Hi {name}, your listing '{listing}' got {leads} enquiries this month. To keep it live, pay ₹{amt} once here: https://rzp.io/... (Razorpay). Bucks will never ask for your UPI PIN."

**Trust rules**
- One action per message.
- Only two link domains, both DLT-whitelisted (rzp.io and the Bucks domain).
- Never ask for a PIN or OTP, and say so in the message.
- A consistent sender header and WhatsApp verified business name.
- Mirror every message in-app, so users can check the status without tapping a link ("open the Bucks app > Billing to verify").
- Avoid urgency words like "account blocked" or "last warning" that resemble scams.

**Localisation**
- Hindi and regional-language templates each need separate DLT/WhatsApp approval.
- Choose the language from the app's locale setting. The repo already has 20 locales.

### Gaps
- **No tested copy.** No A/B-tested Indian dunning copy was found, and there is no data on the effect of vernacular vs English on recovery.
- **No phishing-fear data.** No survey data was found on Indian users' fear of payment links. This was not searched in depth because of the time budget.

## Event-to-message mapping (Razorpay subscription webhooks)

### Takeaway
Razorpay sends 10 subscription webhooks. Each can map to at most one Bucks message, chosen to avoid repeating what Razorpay or the bank already sends.

### Cited Findings
- **The 10 webhooks.**
  - `subscription.authenticated`: the first payment or authorisation is made.
  - `subscription.activated`: the subscription goes to active from authenticated, pending or halted.
  - `subscription.charged`: each successful charge.
  - `subscription.completed`
  - `subscription.updated`
  - `subscription.pending`: a charge failed. It fires again on each failed retry.
  - `subscription.halted`: retries are exhausted.
  - `subscription.cancelled`
  - `subscription.paused`
  - `subscription.resumed`
  - Payloads include the subscription entity, plus a payment entity if a payment was attempted.
  - — [Razorpay subscription webhooks](https://razorpay.com/docs/webhooks/subscriptions.md) (primary)

### Inferences
| Event | Razorpay already sends | Bucks action |
|---|---|---|
| authenticated | SMS/email "Initialized" | Push and in-app "Autopay set up, first debit {date}". No SMS. |
| activated (from authenticated) | – | In-app status. Push "Listing is live". |
| activated (from pending/halted) | "Invoice Charge" SMS/email | WhatsApp utility "You're back on, thanks". Cancel the remaining dunning. |
| charged | "Charged Successfully" SMS/email | Push status only. Optionally a monthly WhatsApp value summary. |
| pending (1st) | "Charge Failed" email/SMS | WhatsApp/SMS with the reason-specific action, within 1h, 10:00–20:00. |
| pending (repeat) | Same | Only on the second-to-last retry (T+2): one reminder. |
| halted | "Halted" SMS/email | WhatsApp/SMS "pay once" rzp.io link, plus push. Start the grace-period clock. |
| paused | – | Push and in-app "Paused until {date}". No SMS. |
| resumed | – | Push "Welcome back". |
| cancelled | "Cancelled" SMS/email | In-app only. Win-back at 7/30/60 days with marketing consent. |
| completed / updated | Email/SMS | In-app only. |

### Gaps
- **Unknown overlap with Razorpay.** I don't know whether Razorpay's own customer SMS can be turned off or white-labelled. If it can't, Bucks's messages must be framed as complementary to Razorpay's, not the main channel.
