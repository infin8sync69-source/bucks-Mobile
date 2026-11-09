# Onboarding v2

Decided 9 November 2026. Code: `ui/onboarding/OnboardingScreens.kt`. Server: `supabase/migrations/onboarding_v2.sql`.

## The flow

| # | Screen | On it | Notes |
|---|---|---|---|
| 1 | **Language** | 22 languages, each in its own script with the English name under it; the phone's language preselected | Tapping redraws the app in that language at once. Shown once; later from Settings → Language or the globe on the phone screen |
| 2 | **Phone** | Country chip (flag + dial code, from the SIM, then the network, then the phone region; searchable list of every country) · number · "I agree to the Terms and Privacy Policy" with Terms, Privacy and Guidelines links · **Get code** | The button stays off until the number is valid for that country and the box is ticked. The terms version is recorded on the server after sign-in (`record_terms`) |
| 3 | **Code** | One box per digit, auto-verifies when full; "Sent to +91 98765 43210 · Edit"; resend after 30 s | Many phones fill the code in themselves |
| 4 | **Name and date of birth** | Name · date of birth as DD / MM / YYYY (free entry, no default, no hint of the age limit) · **Let's go** | Then Home. Under 13: a neutral "You can't create an account right now", remembered on the phone so Back can't retry. Accounts made before this see a birthday-only version once |

**Asked later, in context:**
- **Location:** on Home, with the Play disclosure first. The first fix also sets the area.
- **Notifications:** from the second launch, or when a driver goes online.
- **Profile extras:** bio, interests, gender and photo are under Profile → Edit profile.
- **Contacts:** asked only when the person opens Contacts.

**Removed:**
- The splash "Get started" screen.
- The guardian consent step (the date of birth moved onto the name screen).
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

**Bucks is for 13 and over** (owner's decision, 9 November 2026). One rule, enforced by the server (`set_birth_date`, `settings.min_signup_age = 13`):

- **Under 13:** refused, and nothing is stored.
- **13 to 17:** the TEEN band, with the protections the server already enforces. Only syncs can message them, Moments are synced-only, adults they share no connection with can't find them, they can't be on the posts map, and there are no analytics. The app shows no extra screen.
- **18 and over:** ADULT.

**For legal review:** India's DPDP Act requires verifiable parental consent for under-18s (DPDP Rules, Rule 10; most obligations reported to apply from about May 2027). The app no longer has a guardian step. Decide before launch whether teens need one, or whether 1.0 should be 18+. Play's target audience is 13+.

## Measure

Log `onboarding_step_viewed` and `onboarding_step_completed` per screen, plus how often the code fills itself in. There is no trustworthy benchmark for drop-off per step, so the funnel is the only real guide.
