# Onboarding v2

Decided 9 November 2026. Code: `ui/onboarding/OnboardingScreens.kt`. Server: `supabase/migrations/onboarding_v2.sql`.

## The flow

| # | Screen | On it | Notes |
|---|---|---|---|
| 1 | **Language** | 22 languages, each in its own script with the English name under it; the phone's language preselected | Tapping redraws the app in that language at once. Shown once; later from Settings → Language or the globe on the phone screen |
| 2 | **Phone** | Country chip (flag + dial code, from the SIM, then the network, then the phone region; searchable list of every country) · number · "I'm 18 or older and agree to the Terms and Privacy Policy" with Terms, Privacy and Guidelines links · **Get code** | The button stays off until the number is valid for that country and the box is ticked. The terms version is recorded on the server after sign-in (`confirm_adult`) |
| 3 | **Code** | One box per digit, auto-verifies when full; "Sent to +91 98765 43210 · Edit"; resend after 30 s | Many phones fill the code in themselves |
| 4 | **Name** | One field · **Let's go** | Then Home |

**Asked later, in context:**
- **Location:** on Home, with the Play disclosure first. The first fix also sets the area.
- **Notifications:** from the second launch, or when a driver goes online.
- **Profile extras:** bio, interests, gender and photo are under Profile → Edit profile.
- **Contacts:** asked only when the person opens Contacts.

**Removed:**
- The splash "Get started" screen.
- The date of birth and guardian consent steps.
- The area, gender, bio and interests steps.
- The two "1/3" progress bars.

## Why (research summary)

- **Language first** is how Indian vernacular apps (ShareChat, Koo) onboard people who don't read English comfortably. Names shown only in English are an anti-pattern.
- **Phone → code → name** is the minimum the big apps ask for (WhatsApp, Grab, Uber, Swiggy). Everything else is progressive profiling.
- **Tutorials and carousels** before any value don't help. NN/g found they don't improve task success.
- **Permissions just in time** (Android guidance): two denials make a refusal permanent, so asking too early can lose the permission for good. Notifications should wait until people know the app.
- **Country** lives inside the phone screen, not on a screen of its own.
- **No progress bar** for a 4-screen flow. One primary button per screen.

## Age

The owner chose a self-declared "I'm 18 or older" with the terms, instead of a date of birth. Trade-off, noted for legal review:

- Teen protections (private by default, not findable by adults) now apply to nobody, because everyone is treated as an adult.
- An under-18 who ticks the box gets adult defaults.
- Play's target audience must be **18+**.

## Measure

Log `onboarding_step_viewed` and `onboarding_step_completed` per screen, plus how often the code fills itself in. There is no trustworthy benchmark for drop-off per step, so the funnel is the only real guide.
