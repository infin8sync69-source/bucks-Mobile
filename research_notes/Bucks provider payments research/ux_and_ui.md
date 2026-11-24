# UX and UI for provider plan status and payment flows (India, Android-first, consumption-only)

Scope note: research done 13 Nov 2026 with about 17 search/fetch calls. Primary sources are Google Play policy/developer docs, Razorpay docs, Google design research and NN/g. Several useful items (real PhonePe/GPay approval screens, partner-app teardowns, Indian design team blogs) could not be verified and are listed under Gaps instead of being guessed.

## 1. What to show in the in-app Plan status card, and how (states, tone, banners vs cards)

### Takeaway
Show one persistent status card with a single dominant fact per state (days left, paid-until date, or next charge amount and date), keep access during a short grace window, and escalate only to a persistent (non-dismissable-until-fixed) banner when entitlement is about to be lost. Google Play's own lifecycle (grace period keeps access, account hold removes it, recovery restores without fuss) is a good mental model to copy, mapped onto Razorpay's subscription states.

### Cited Findings
- Google Play models payment failure as a recovery period: a grace period followed by account hold. "During a grace period, the user should retain access to subscription benefits"; after grace ends the subscription enters account hold "and they lose entitlement." — [Android Developers: subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- Play recommends that during grace and account hold "you should also encourage the user to fix their payment method"; Play itself shows a temporary snackbar on app open with a deep link to fix payment. When a subscription recovers in grace the renewal date does not reset; recovering from account hold moves the billing date to the recovery date. Default account hold is 60 days minus grace. — [Android Developers: subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- Razorpay subscription states: Created, Authenticated (customer completed the mandate/auth transaction), Active, Pending (an auto-charge failed; Razorpay keeps retrying), Halted (all retries used up), Paused (only Active can be paused; pausing an Authenticated subscription cancels it), Cancelled (cannot restart), Expired (auth not completed by start_at), Completed. In Halted, invoices still generate but no auto-charge is attempted, and after reactivation previously failed charges are not retried. — [Razorpay: Subscription states](https://razorpay.com/docs/payments/subscriptions/states/)
- Razorpay emails card-based customers in Pending with a CTA to change card; the states page does not mention SMS for other states, and merchants learn of failures via webhooks. — [Razorpay: Subscription states](https://razorpay.com/docs/payments/subscriptions/states/)
- Razorpay advertises "Smart Payment Retries" but the docs reviewed give no retry count/schedule. — [Razorpay Subscriptions docs](https://razorpay.com/docs/payments/subscriptions/)
- Banner vs snackbar: snackbars are transient (about 4-10 s) with at most one action; a banner fits "when information requires action or awareness over multiple page interactions, but does not need to block the user", and one spec cites subscription expiry as a banner example. Banners are reportedly not listed as a component in Material 3 (unofficial reports). — [Koder DS banners](https://kds.koder.dev/en-US/reference/components-banners.html); [Koder DS snackbars](https://kds.koder.dev/en-US/reference/components-snackbars.html); [Kotlin Slack thread](https://slack-chats.kotlinlang.org/t/2708406/i-have-noticed-that-the-material-design-banner-component-was)
- Tone for warnings: NN/g says take a positive tone, don't blame the user, put accountability on the system, avoid humour, and match the message's severity to its impact (some users only need a warning and can keep moving). — [NN/g error-message scoring rubric](https://www.nngroup.com/articles/error-messages-scoring-rubric/); [NN/g error-message guidelines](https://www.nngroup.com/articles/error-message-guidelines/)
- Google's tech-writing guidance on error messages likewise covers setting a non-blaming, non-alarming tone. — [Google: Set the right tone](https://developers.google.com/tech-writing/error-messages/set-tone)

### Inferences
- Map Razorpay states to app states (proposed; validate against webhook data):

| App state | Razorpay state(s) | Primary fact (big, number-first) | Secondary line | Visual | Tone / colour | Access |
|---|---|---|---|---|---|---|
| Free trial | none or Created | "12 days left" + linear progress draining | "Free until 25 Nov" | Linear progress, neutral chip "Trial" | Neutral/primary | Full |
| Founding free | none (internal flag) | "Free for you" / "Founding member" badge | "No payment needed until 1 Apr 2027" (or "for life" if true) | Badge, no countdown | Celebratory but calm | Full |
| Waiting for approval | Created (link sent, not approved) | "Approve ₹X/month in your UPI app" | "We sent the link by SMS and WhatsApp to 98xxxxxx21" | Step indicator 1-2-3 | Neutral info | Per trial rules |
| Active | Authenticated / Active | "Paid until 10 Dec" | "Next: ₹199 on 10 Dec via UPI Autopay (PhonePe)" | Green check chip "Active" | Positive, quiet | Full |
| Charge coming | Active, within 24-48 h of debit | "₹199 will be taken on 10 Dec" | "Keep balance in your bank account" | Info chip | Neutral | Full |
| Payment due / retrying (grace) | Pending | "Payment did not go through" | "We will try again on 12 Dec. You are still live until 17 Dec (5 days)" | Amber chip, countdown to grace end | Amber, non-blaming ("did not go through", not "you failed") | Full (grace) |
| Failed / on hold | Halted | "Your plan is on hold" | "Customers can't find you in search. Your profile and recommendations are safe." | Persistent banner on Home + card | Amber/red-orange, never pure alarm red full-screen | Reduced |
| Paused | Paused (customer paused in UPI app or by us) | "Plan paused" | "Your profile, reviews and recommendations stay. Search listing is off." | Grey chip | Neutral, dignified | Reduced |
| Cancelled | Cancelled / Expired / Completed | "Plan ended on 3 Dec" | "Everything you built is saved. Restart anytime." | Grey | Neutral, welcoming | Reduced |

- Use the card (persistent, on a Plan/Account screen and a compact version on the provider Home) for all states; add a persistent top banner only for Pending-near-end-of-grace and Halted; never use a snackbar for billing state (it disappears).
- Countdown visual: a linear progress bar that drains plus a large number ("5 days") is easier than a circular ring at small sizes and at 200% font; show the absolute date alongside the relative count ("5 days, until 17 Dec").
- Do not reset trust: on recovery, show a brief positive confirmation ("Payment received. You are live again.") and return the card to quiet Active.
- Since Razorpay Halted does not retry old charges, the recovery path is "approve a new link" (new mandate) rather than "pay the old invoice" in most cases; copy should say "approve again" not "pay dues".

### Gaps
- No verified teardowns found for Jio, Airtel Thanks, Swiggy One, Zomato Gold, Spotify, Netflix, Uber driver, Urban Company partner, Shopify/Dukaan status cards in this pass (Mobbin/Page Flows are login-walled). Rapido/Namma Yatri/Uber/Ola auto-driver subscriptions exist (daily ₹9-29 style login fees; cab ₹500 above ₹10,000 earnings) but no UX description of how the pass status is shown was found — [Business Standard](https://business-standard.com/companies/start-ups/after-cabs-rapido-extends-saas-based-zero-commission-model-to-auto-drivers-124021300846_1.html); [Outlook Business](https://www.outlookbusiness.com/companies/ola-and-uber-introduces-subscription-based-plans-for-auto-drivers). These are relevant precedents for Indian small providers paying a flat platform fee.
- Razorpay retry count and interval not documented on the pages read; needed to compute the "We will try again on..." date.

## 2. Communicating "check your SMS/WhatsApp" in a consumption-only app without breaking Google Play policy

### Takeaway
Google Play explicitly allows consumption-only apps to tell users that purchase options exist elsewhere, as long as there is no direct link (or link to a page that leads to payment). Plain informational copy like "We have sent your plan link by SMS and WhatsApp" with no tappable link, no button that opens the Razorpay URL, and no pressure language is the safe pattern. Sending the link itself happens outside the app (SMS/WhatsApp/email), which Google explicitly permits.

### Cited Findings
- Consumption-only means no product or service, digital or physical, can be purchased from within the app; Play allows any app to be consumption-only even if part of a paid service. — [Google Play Console Help: Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- For consumption-only apps, developers may share information about purchase options elsewhere without direct links. Google's own example wordings: "You can purchase this book directly on our website", "Go to our website to upgrade your subscription to Premium", "Need extra lives? Head to our website to purchase more", and "This movie isn't available to rent in the app. However, any movie you rent through our website.com will be immediately available to view in the app." — [Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- Prohibited for apps outside that allowance: "directly linking to a webpage that could lead to an alternate payment method" and "using language that encourages a user to purchase the digital item outside of the app." Links to account management, privacy or help pages are fine if they do not eventually lead to a prohibited payment method. — [Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- Outside the app, developers are free to communicate with users about alternative purchase options (email and "other channels outside of the app"). — [Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en); [Android Developers Blog commerce FAQ (2020)](https://android-developers.googleblog.com/2020/09/commerce-update-faqs.html)
- The help page does not address push notifications specifically. — [Google Play Console Help](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)

### Inferences
- Allowed-style in-app copy (informational, no link, no button that opens payment):
  - "Your Bucks plan is managed outside the app. We have sent the details by SMS and WhatsApp to 98xxxxxx21."
  - "Plan: ₹199 a month, paid with UPI Autopay. Details are in the SMS from Bucks."
  - Hindi: "आपका प्लान ऐप के बाहर मैनेज होता है। जानकारी SMS और WhatsApp पर भेजी गई है।"
- Avoid in-app: a "Pay now" / "Renew" / "Subscribe" button; a copyable or tappable Razorpay URL; a button that opens WhatsApp with the link pre-filled; QR codes for the link; urgency like "Pay today to stay live!". A "Send link again" button that triggers your server to re-send SMS/WhatsApp is a grey area: it does not link in-app, but it arguably facilitates purchase; treat as a policy risk to confirm with Play policy support before shipping. (inference, not confirmed by source)
- Push notifications are not addressed by the policy page; a push that deep-links into a payment URL is effectively an in-app link and should be avoided; push that says "Check your SMS from Bucks" is closer to the allowed informational pattern (inference).
- Make status read-only facts the main content (paid-until, next charge, mandate app) so the card is clearly "account information", which Google permits.

### Gaps
- Whether Play classifies a B2B listing fee for providers as a "digital good" requiring Play Billing at all (vs. a service exempt from Play Billing) was not researched here; that determines how strict this needs to be. Exact policy on "resend link" buttons not found.

## 3. UPI Autopay mandate approval via Razorpay link: steps, what users see, drop-off, customisation

### Takeaway
The external journey is short (open link, pick UPI app, review mandate, enter UPI PIN, success) and confirms in real time, but the app hand-off and PIN step is where users drop off (Razorpay itself says nearly 30% of subscribers drop off before registration). Pre-explaining the exact screens, the cap, the 24-hour pre-debit notice and "cancel anytime in your UPI app" is the main lever the app controls.

### Cited Findings
- Razorpay: create Plans and Subscription Links in the Dashboard and share them by SMS/email; requires Flash Checkout enabled. — [Razorpay Subscriptions docs](https://razorpay.com/docs/payments/subscriptions/)
- Customer journey per Razorpay: select plan, get directed to preferred UPI app, confirm by entering UPI PIN, registration successful in real time (vs 2 days-2 weeks for other recurring modes). Customers can pause or cancel from their UPI app and the merchant is notified in real time; customers get a notification 24 hours before each debit; customers can change the authorised account when a debit fails. — [Razorpay blog: What is UPI Autopay](https://razorpay.com/blog/what-is-upi-autopay-recurring-payments-razorpay-subscriptions/)
- Razorpay-hosted registration page shows max billing amount, frequency and expiry before authorising; minimum registration amount ₹1 for UPI; UPI Collect flow for mandates is deprecated (intent/link flows remain). — [Razorpay UPI recurring docs](https://razorpay.com/docs/payments/recurring-payments/upi) (via search summary; page not fully fetched)
- Razorpay UPI recurring FAQ: max ₹15,000 per debit without extra authorisation; debits above need additional customer authorisation; pre-debit notification 24 h before; subsequent charge initiated 25 h after pre-debit notification; customers can pause or cancel but not modify a mandate in their UPI app; intent-supported PSP apps include GPay, PhonePe, Paytm, Amazon Pay, BHIM; registration is real-time once MPIN entered. — [Razorpay UPI recurring FAQs](https://razorpay.com/docs/payments/recurring-payments/upi/faqs?preferred-country=IN)
- Only the customer can resume a subscription they paused from their UPI app; the merchant cannot. — [Razorpay docs via search summary](https://razorpay.com/docs/payments/recurring-payments/upi)
- A mandate is defined by maximum amount per debit, frequency, start date and validity; frequencies include weekly, monthly, quarterly, half-yearly, yearly, as-presented. — [PhonePe Business: UPI Autopay mandates](https://business.phonepe.com/articles/understanding-upi-autopay-mandates-everything-you-need-to-know); [Juspay mandates docs](https://juspay.io/mandates/docs/mandates/description)
- Limits conflict across sources: ₹15,000 without AFA (Razorpay FAQ, Zoho, Business Today on the 2026 RBI e-mandate framework) vs ₹1,00,000 "standard UPI mandate limit" (Paytm) vs ₹50,000 (Yuno). Likely different categories; irrelevant for a sub-₹15,000 plan. — [Razorpay FAQ](https://razorpay.com/docs/payments/recurring-payments/upi/faqs?preferred-country=IN); [Business Today, Apr 2026](https://www.businesstoday.in/personal-finance/news/story/rbi-caps-recurring-payments-at-rs15000-without-otp-under-new-e-mandate-framework-526759-2026-04-21); [Paytm blog](https://paytm.com/blog/payments/upi/upi-mandates-with-paytm/); [Zoho](https://www.zoho.com/payments/academy/payment-processing/upi-autopay-mandates-and-recurring-debits.html)
- 24-hour pre-debit notification is a consistent requirement (NPCI RuPay AutoPay circular; RBI framework per Zoho). — [NPCI circular PDF](https://www.npci.org.in/PDF/npci/rupay/2022/Circular-RuPay-AutoPay-AFA-Limit-enhancement-and-compliance.pdf); [Zoho](https://www.zoho.com/payments/academy/payment-processing/upi-autopay-mandates-and-recurring-debits.html)
- Drop-off: Razorpay says nearly 30% of subscribers drop off before registration is completed (vendor claim). Cashfree claims 91% registration/execution success; Setu >99% execution. Third-party commentary says registration (app redirect and PIN) is the highest drop-off stage and low debit success is mostly behaviour/insufficient balance, not tech (~0.5% technical decline). — [Razorpay blog: UPI Autopay with Intelligent Revenue Protect](https://razorpay.com/blog/upi-autopay-with-intelligent-revenue-protect/); [Cashfree](https://www.cashfree.com/upi-autopay/); [Setu](https://setu.co/real-time-payments/upi/automate-collections); [The Mainstream, Feb 2026](https://themainstream.co.in/?p=105895)
- Third-party UX recommendations (no cited evidence): fall back to another UPI app immediately if setup fails; show mandates with pause/cancel; offer pause before cancellation; send 24 h reminder by SMS/WhatsApp; schedule retries with back-off (example 12 h). — [ProductGrowth: UPI AutoPay benchmarks](https://productgrowth.in/insights/fintech/upi-autopay-mandate-benchmarks/)
- Approval screen in UPI apps (unverified, from a third-party guide and a QA test script for a clone app): user reviews merchant, amount, frequency and validity, sees a "maximum limit per debit" field, and approves with UPI PIN. — [BankBazaar](https://www.bankbazaar.com/ifsc/upi-autoay.html); [TestMu AI script](https://www.testmuai.com/use-cases/kane-cli/autopay-mandate-setup/)
- Razorpay checkout customisation: Checkout Styling lets you set colours (HEX/RGB/HSL), brand name and logo (square, min 256x256 px, max 1 MB), fonts, borders, sidebar graphics, festive themes, and a "Razorpay Trusted Business" badge. Checkout supports Hindi, Marathi, Gujarati, Telugu, Tamil and more; an older release also listed Kannada and Bengali (current Kannada support unconfirmed). — [Razorpay Checkout Styling](https://razorpay.com/docs/payments/dashboard/account-settings/checkout-styling/); [Razorpay local language checkout](https://razorpay.com/docs/payments/payment-gateway/web-integration/standard/local-lang); [Razorpay vernacular checkout blog](https://razorpay.com/blog/vernacular-checkout-by-razorpay-accept-payments-from-your-customers-in-their-language/)

### Inferences
- External journey, roughly 4-5 taps: (1) tap link in SMS/WhatsApp, (2) Razorpay page shows plan name, ₹ amount, frequency, max amount, validity; tap UPI / pick app, (3) UPI app opens with mandate request, review, (4) enter UPI PIN, (5) success screen, then SMS from bank/UPI app. Drop-off risks: link opens in WhatsApp in-app browser (intent to UPI app may fail; advise "open in Chrome"), wrong UPI app chosen, alarm at seeing a "maximum amount" higher than the price, PIN hesitation, and returning to Bucks not knowing it worked.
- Set the mandate max amount equal to or close to the plan price (fixed plan), because a higher cap shown in the UPI app looks like a risk; if a higher cap is needed for future price changes, explain it in advance ("Your UPI app will show up to ₹299. We will only take ₹199.").
- Pre-explainer in the app (go-live checklist step), allowed because it is informational and unlinked: a 3-panel illustrated "What you will see" with mock screenshots of the Razorpay page and UPI PIN step, plus a voice note button. Example copy:
  1. "You will get an SMS and WhatsApp from Bucks with a link."
  2. "It opens a Razorpay page. It shows ₹199 every month."
  3. "Choose your UPI app (PhonePe, Google Pay, Paytm). Enter your UPI PIN. This is the same PIN you use to pay in shops."
  4. "Your bank will message you 1 day before each payment. You can pause or cancel anytime in your UPI app."
- After return, Bucks should reflect Authenticated quickly via webhook and show "Done. UPI Autopay is on with PhonePe." so the provider does not try twice.
- Brand the Razorpay page with the Bucks logo and colour so the hand-off feels continuous, and set its language to match the provider's app language where Razorpay supports it.

### Gaps
- No verified, current screenshots or step counts for PhonePe/GPay/Paytm mandate approval screens; no NPCI UX guideline document for mandate screens was found. No independent drop-off data per step. Whether the Razorpay subscription link page (vs standard checkout) honours the language and styling settings was not confirmed.

## 4. Designing for low literacy and Indian languages

### Takeaway
Lead with icons and big numerals, short everyday words, voice as a first-class option, and layouts that tolerate longer and taller scripts; test at 200% font scale and with TalkBack. Google's NBU research emphasises visual affordances, minimal text input, dense/vibrant rather than sparse visuals, explicit reassurance at sensitive steps, and human helpers.

### Cited Findings
- Google field research: users "rely on visual affordances like icons"; minimise text-based inputs and remove hierarchies only understood through language; test with people who cannot read; a sparse, muted app "just couldn't compete for the user's attention"; state reassurance at sensitive steps (Google Station: "Your number is safe with us" with FAQ link); India has 22 languages with over a million speakers each; less than 2% of Indians have credit cards; people trust word-of-mouth and in-person helpers. — [Google Design: Connectivity, culture and credit](https://design.google/library/connectivity-culture-and-credit)
- Google's Voice Playbook: make voice easy to find with simple, large icons reachable in one tap; break long text into shorter sentences when read aloud. — [Google: Voice users playbook](https://blog.google/technology/next-billion-users/voice-users-playbook/)
- Google NBU / Gates Foundation Digital Confidence Design Tools principles include letting users explore before committing, giving timely guidance, and reducing navigation hierarchy (via search summary). — [Last Mile Money: Designing for new internet users](https://medium.com/last-mile-money/designing-for-new-internet-users-26d1f7d842dc)
- Many new users rely on "teachers" (family members, shop owners) to navigate their phone (secondary source). — [Joris van Mens: Building for the next billion](https://medium.com/@jorisvanmens/building-for-the-next-billion-a8a645b74f9e)
- Text expansion: plan ~35% average (Transifex), up to 50% (Shopify Polaris), 30-40% (SimpleLocalize); short labels expand most; test with 50% longer placeholder text. Hindi and Tamil are mainly a vertical-space problem (taller glyphs) and need fonts with glyph coverage. No Hindi/Tamil-specific percentage found. — [Shopify Polaris i18n](https://polaris.shopify.com/foundations/internationalization); [Transifex](https://www.transifex.com/blog/2015/localization-friendly-ui-design-part-1); [SimpleLocalize](https://simplelocalize.io/blog/posts/text-expansion-ui-localization/); [Design Systems Collective](https://www.designsystemscollective.com/your-design-system-speaks-english-c1b5e89e03dc)
- Android 14+ supports nonlinear font scaling to 200% (Samsung offers 200% on older versions); use sp for text and line height, dp for layout; test with `@Preview(fontScale = 2f)`; swapping Row for FlowRow lets buttons wrap at 200%. — [ProAndroidDev / droidcon: Font size considerations](https://www.droidcon.com/2024/02/08/font-size-considerations-for-accessibility/); [Flutter Android 14 migration note](https://docs.flutter.dev/release/breaking-changes/android-14-nonlinear-text-scaling-migration); [CommonsWare: Text will not always scale](https://commonsware.com/blog/2023/07/08/text-will-not-always-scale.html)

### Inferences
- Number-first layout: the single biggest element on the card is the number ("5", "₹199", "10 Dec"), with an icon (calendar, rupee, shield) and a 2-4 word label. Avoid sentences as the primary carrier of meaning.
- ₹ formatting: "₹199" (no space, no ".00"), Indian grouping for larger values ("₹1,00,000"); use locale-aware formatting (Android `NumberFormat`/ICU with `en-IN` / `hi-IN`). Dates: "10 Dec" / "10 दिस॰" style short month via locale formatter; never numeric-only "10/12" (ambiguous). Keep Western digits by default (most Indian apps and UPI apps use them), unless user picks native digits (inference; verify per language).
- Voice notes: a "Listen" speaker button on the plan card and the mandate explainer, recorded in each supported language, reading the same short sentences.
- Copy rules: present tense, second person, under ~8 words per line, no jargon ("mandate" -> "UPI Autopay"; "halted" -> "on hold"; "invoice" -> "receipt").
- TalkBack: give the card a single merged content description that reads the full state ("Plan active. Paid until 10 December. Next payment 199 rupees on 10 December by UPI Autopay."); speak dates fully and say "rupees" rather than the symbol; ensure progress bars expose a state description ("5 of 14 days left").
- Allow 50% width growth and extra line height for Devanagari/Tamil/Kannada; let chips and buttons wrap (FlowRow); avoid fixed-height cards.

### Gaps
- No Indian-language-specific expansion data, no PhonePe/CRED/Swiggy/Zomato/Groww design-blog material on vernacular billing UX was retrieved in this pass.

## 5. Paused-state UX that preserves dignity and makes return easy

### Takeaway
Paused/held/cancelled should read as a neutral, reversible status, not a punishment: say plainly what stays (profile, reviews, recommendations, history) and what is off (search listing, new leads), and make "how to come back" a single clear step. Note that if the provider paused in their UPI app, only they can resume there.

### Cited Findings
- Only Active subscriptions can be paused in Razorpay; pausing an Authenticated one cancels it; Cancelled cannot be restarted (a new subscription is needed). — [Razorpay: Subscription states](https://razorpay.com/docs/payments/subscriptions/states/)
- Customers can pause or cancel UPI mandates from their UPI app; merchants cannot resume a customer-paused subscription. — [Razorpay UPI FAQs](https://razorpay.com/docs/payments/recurring-payments/upi/faqs?preferred-country=IN); [Razorpay UPI recurring docs](https://razorpay.com/docs/payments/recurring-payments/upi)
- Play's model: recovery from account hold restores access and the same purchase continues (no re-onboarding). — [Android Developers: subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- Recommendation to offer pause before cancellation (vendor guidance, unsourced). — [ProductGrowth](https://productgrowth.in/insights/fintech/upi-autopay-mandate-benchmarks/)
- NN/g: non-blaming, system-accountable tone. — [NN/g rubric](https://www.nngroup.com/articles/error-messages-scoring-rubric/)

### Inferences
- Paused card example copy:
  - Title: "Plan paused"
  - Keeps (green tick list): "Your profile", "Your reviews and recommendations", "Your messages"
  - Off for now (grey dash list): "Showing in search", "New customer requests"
  - Return: if paused in UPI app: "To restart, open your UPI app > Autopay > Bucks > Resume." If cancelled/halted: "To come back, we will send you a new link by SMS. Tell us when you are ready." (avoid in-app payment link)
- Never hide the profile, never show "Your account is suspended"; avoid red for Paused/Cancelled; reserve amber for the actionable Halted state only.
- Keep the value dashboard visible while paused ("You got 42 profile views in October") to make return motivated, not shamed.

### Gaps
- No sourced case studies of pause-state UX in Indian partner apps found.

## 6. Trust markers, receipts and the surrounding provider experience (checklist, value dashboard, badges)

### Takeaway
Trust comes from naming the rails people already know (UPI app names, Razorpay), stating the cap and the 24-hour notice, and "cancel anytime in your UPI app" (which is factually true). Logos should be used only per brand rules; plain text names are safer. A receipts list and a value dashboard reinforce that the fee is worth it.

### Cited Findings
- Explicit reassurance at sensitive steps works in Indian contexts ("Your number is safe with us"). — [Google Design](https://design.google/library/connectivity-culture-and-credit)
- Pre-debit notice 24 h before each charge; pause/cancel in UPI app; real-time confirmation. — [Razorpay blog](https://razorpay.com/blog/what-is-upi-autopay-recurring-payments-razorpay-subscriptions/); [Razorpay UPI FAQs](https://razorpay.com/docs/payments/recurring-payments/upi/faqs?preferred-country=IN)
- Razorpay offers a "Trusted Business" badge and branded checkout. — [Razorpay Checkout Styling](https://razorpay.com/docs/payments/dashboard/account-settings/checkout-styling/)
- Razorpay Subscriptions handles invoicing for each debit. — [Razorpay blog](https://razorpay.com/blog/what-is-upi-autopay-recurring-payments-razorpay-subscriptions/)

### Inferences
- In-app trust line under the plan card (informational, no link): "UPI Autopay by Razorpay. Your bank tells you 1 day before each payment. Pause or cancel anytime in your UPI app."
- Show mandate facts: "UPI app: PhonePe", "Limit: ₹199 a month", "Valid till: Dec 2027".
- Receipts view: list "10 Nov - ₹199 - Paid" with download/share as PDF; as a read-only account record it is within Play's "account management" allowance as long as it does not lead to payment (inference from policy).
- Go-live checklist note: final item "Turn on your plan - we will send a link by SMS" with status chip (Waiting / Done). Before it, show the "What you will see" explainer.
- Value dashboard: number tiles (profile views, searches you appeared in, calls/messages, recommendations) for this billing period, ideally next to "₹199 this month" so value vs price is visible.
- Badges: "Founding member", "Verified", "Live" chips on profile; keep "Live" tied to plan state so providers see the consequence of hold/pause concretely.
- Logos: NPCI/UPI/Razorpay marks have brand-usage rules; prefer text plus generic shield icon unless permission/guidelines are checked (inference).

### Gaps
- NPCI/UPI and Razorpay logo usage guidelines not retrieved.

## 7. Material 3 / Compose and SwiftUI component patterns

### Takeaway
Build the status as an M3 Card (ElevatedCard/OutlinedCard) containing an AssistChip/SuggestionChip-style status chip, a large number, a LinearProgressIndicator for countdown, and supporting text; use a persistent inline banner-like card (M3 has no official banner) for hold states and avoid snackbars for billing state. Use theme colour roles (primary/tertiary/error containers) so dark mode is automatic, and test at fontScale 2f.

### Cited Findings
- Snackbars are transient and single-action; persistent, action-needed messages fit banners; M3 reportedly dropped the banner component (unofficial). — [Koder DS banners](https://kds.koder.dev/en-US/reference/components-banners.html); [Kotlin Slack](https://slack-chats.kotlinlang.org/t/2708406/i-have-noticed-that-the-material-design-banner-component-was); [Compose Material3 Snackbar API](https://kotlinlang.org/api/compose-multiplatform/material3/androidx.compose.material3/-snackbar.html)
- Compose large-font testing via `@Preview(fontScale = 2f)`; use FlowRow for wrapping actions. — [droidcon: Font size considerations](https://www.droidcon.com/2024/02/08/font-size-considerations-for-accessibility/)

### Inferences
- Compose sketch: `ElevatedCard { Row { Icon; Text(status chip) } ; Text("5", style = displaySmall); Text("days left, until 17 Dec", bodyMedium); LinearProgressIndicator(progress = { daysLeft / total }); Text(secondary) }`, with `Modifier.semantics(mergeDescendants = true) { contentDescription = ... }` and `stateDescription` on the progress.
- Colour roles: Active -> primaryContainer/ tertiary for success tick; Grace -> a custom "warning" container (M3 has no warning role; define amber container/onContainer pair for light and dark); Halted -> errorContainer (soft) not solid error; Paused/Cancelled -> surfaceVariant. Define all as tokens with dark variants; check contrast in both.
- SwiftUI parity: `GroupBox` or custom card with `ProgressView(value:)`, `Label` with SF Symbol, `.accessibilityElement(children: .combine)`, Dynamic Type sizes up to accessibility XXXL; capsule status chip.
- Avoid relying on colour alone: every state has an icon and a word.

### Gaps
- Official m3.material.io pages for cards, chips and progress indicators were not fetched in this pass; guidance above is standard practice, not quoted.
