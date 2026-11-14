# Email sequence: Bucks closed test → public launch

**Type:** onboarding (closed test) followed by a short launch-advocate tail
**Goal:** keep at least 12 testers opted in and active for 14 days in a row (Google Play's requirement for new personal developer
accounts before production access), collect useful feedback, then turn testers into launch advocates.
**Audience:** adults (18+) who signed up for early access on the sign-up form. **Never send marketing email to anyone under 18.**
The form must ask for age and only enrol 18+. Teens can join the test only through a parent, and the parent gets the emails.
**Voice:** friendly, plain, short. Honest that it's a test build. No jargon ("sync" is explained the first time).

> **Recruit 20 to 25 testers, not 12.** Some never install, and some leave. Play counts testers who are opted in, and dropping below
> 12 can mean the 14 days start again. Aim for 20+ opted in on day 0.

## Placeholders to fill before sending

| Token | What it is |
|---|---|
| `{{first_name}}` | From the sign-up form |
| `{{optin_link}}` | Play's closed-test opt-in URL (Play Console → Testing → Closed testing → testers → "Join on the web") |
| `{{group_link}}` | The Google Group testers join (Play allows a Google Group as the tester list) |
| `{{play_link}}` | `https://play.google.com/store/apps/details?id=com.bucks.app` (works for testers once they've opted in) |
| `{{reply_to}}` | Your support email (same as `SUPPORT_EMAIL` in the app) |
| `{{test_end_date}}` | Day 14 |
| `{{signup_form_link}}` | The early-access sign-up form (for friends they invite) |
| `{{survey_link}}` | A 5-question form (Google Forms is fine) |
| `{{fix_1..3}}` | Real fixes shipped during the test (from the Feedback board) |

## Sequence overview

| # | Subject (option A) | Purpose | Timing | Primary CTA | Condition |
|---|---|---|---|---|---|
| 1 | You're in. Here's how to get Bucks | Join the group, opt in, install | Day 0 (on sign-up) | Join the test | Everyone |
| 1b | Quick nudge: your Bucks invite is waiting | Recover people who didn't install | Day 2 | Join the test | Not installed (see "How to know who installed") |
| 2 | Do these 3 things in your first 10 minutes | First value: profile, first sync, first Moment | Day 1 (or right after install) | Open Bucks | Installed |
| 3 | Bucks is better with your people | Get them to bring 2+ friends (more testers, better test) | Day 4 | Invite a friend | Installed |
| 3b | Still there? Two minutes is all we need | Re-activate quiet testers | Day 5 | Open Bucks | Installed, inactive 3+ days |
| 4 | What's broken? Tell us (we read everything) | Feedback board + bug reports | Day 7 | Open the Feedback board | Installed |
| 5 | Halfway there, and what we've fixed | Show progress, ask them to keep the app installed | Day 10 | Open Bucks | Installed |
| 6 | Last 2 days of the test: one favour | Stay opted in until the end; final survey | Day 13 | Take the 2-minute survey | Installed |
| 7 | Thank you. Bucks is going public | Launch advocacy: invite friends, review once it's public | Launch day | Share Bucks | Testers who stayed to day 14 |

## Full email drafts

### Email 1: Welcome and install (Day 0)

**Subject options:** You're in. Here's how to get Bucks · Your early access to Bucks · {{first_name}}, Bucks is ready for you
**Preview:** Three quick steps, about 2 minutes. Android only for now.
**Purpose:** get them through Google's opt-in and into the app on the same day.

> Hi {{first_name}},
>
> Thanks for joining the Bucks test. You're one of the first people to try it.
>
> **Bucks is a social app for you and the people close to you:** share posts and 24-hour Moments, chat one-to-one or in groups, and find friends nearby. You choose who sees what.
>
> Getting in takes about 2 minutes. Google needs three steps for test apps:
>
> 1. **Join our tester group:** {{group_link}} (use the Google account on your Android phone)
> 2. **Accept the test invite:** {{optin_link}}
> 3. **Install Bucks from Google Play:** {{play_link}}
>
> One thing to know: **this is a test build.** Some things will break. When they do, that's useful to us, so tell us.
>
> **[Join the test]** → {{optin_link}}
>
> Stuck? Just reply to this email.
>
> The Bucks team

**Segment:** everyone who signed up and confirmed they're 18+.

### Email 1b: Install nudge (Day 2, not installed)

**Subject options:** Quick nudge: your Bucks invite is waiting · Did Google's steps trip you up? · Still want early access?
**Preview:** The most common snag, and how to fix it in 30 seconds.
**Purpose:** fix the usual opt-in problems (wrong Google account, group not joined).

> Hi {{first_name}},
>
> Looks like Bucks isn't on your phone yet. Usually it's one of these:
>
> - **Different Google account.** Join the group with the same account your Play Store uses (Play Store → your photo, top right).
> - **The Play page says "not available".** Open the invite link first: {{optin_link}}. It can take a few minutes to show up.
> - **iPhone.** Sorry, Bucks is Android only for now.
>
> **[Try the invite again]** → {{optin_link}}
>
> Or reply with a screenshot and we'll sort it out.

**Condition:** not installed by day 2. Sent once. If they're still not installed on day 6, stop the sequence (exit: never activated).

### Email 2: First 10 minutes (Day 1, installed)

**Subject options:** Do these 3 things in your first 10 minutes · Your first Moment, your first sync · Make Bucks feel like yours
**Preview:** A profile, a sync and a Moment, and Bucks starts to feel alive.
**Purpose:** the activation moment: one sync and one piece of content.

> Hi {{first_name}},
>
> You're in. Here's how to make Bucks feel like yours in 10 minutes:
>
> **1. Add a bio.** Profile → Edit profile. One line is enough.
>
> **2. Sync with someone.** A *sync* is a two-way connection, like a friend request. Go to **Discover**, search a name or check your contacts, and tap **Sync**.
>
> **3. Share a Moment.** Tap the **+** in the middle → Moment. It disappears after 24 hours, so it doesn't need to be perfect.
>
> **[Open Bucks]** → {{play_link}}
>
> Tip: Settings → Privacy decides who can message you. By default it's only people you've synced with.

### Email 3: Bring your people (Day 4, installed)

**Subject options:** Bucks is better with your people · Who would you invite first? · Test it with friends, not strangers
**Preview:** Invite 2 friends and you'll see what Bucks is really for.
**Purpose:** grow the tester pool and test the social loop properly.

> Hi {{first_name}},
>
> A social app with nobody you know in it is just an empty room. **The test works best when your friends are in it too.**
>
> If you know two people with Android phones who'd like to try Bucks, send them this sign-up link: {{signup_form_link}}
>
> Once they're in, sync with them and try a group chat. That's the part we most want to test.
>
> **[Invite a friend]** → {{signup_form_link}}

**Condition:** installed. Skip if they've already referred 2+ people.

### Email 3b: Re-activation (Day 5, installed but quiet)

**Subject options:** Still there? Two minutes is all we need · We noticed Bucks has been quiet · One quick thing before you forget us
**Preview:** Even a single post helps us test. Here's the quickest one.
**Purpose:** bring back testers who installed but haven't opened the app in 3+ days.

> Hi {{first_name}},
>
> Bucks has been quiet on your phone. No pressure, but even two minutes helps us a lot.
>
> The quickest useful thing: **open Bucks and react to one post**, or **share one Moment**.
>
> And if something put you off, tell us. That's the most useful feedback of all. Just reply.
>
> **[Open Bucks]** → {{play_link}}
>
> Please keep Bucks installed until {{test_end_date}}, even if you don't use it every day. Google counts it.

**Condition:** installed and inactive 3+ days (see "How to know who installed"). Replaces email 3 for that person if both are due.

### Email 4: Feedback (Day 7, installed)

**Subject options:** What's broken? Tell us (we read everything) · One week in: how's Bucks? · Your ideas can change Bucks
**Preview:** The Feedback board is open. Vote on ideas or post your own.
**Purpose:** structured feedback through the in-app board.

> Hi {{first_name}},
>
> You've had Bucks for a week. We'd love to know what you think.
>
> **The Feedback board is in the app:** Profile → ⚙ Settings → Feedback board. Post an idea or a bug, and vote for the ones you agree with. The most-voted ideas go to the top of our list, and you'll see when we plan or ship them.
>
> Good bug reports say: what you did, what you expected, what happened.
>
> **[Open the Feedback board]** → {{play_link}}
>
> Something you'd rather tell us privately? Reply to this email.

### Email 5: Halfway (Day 10, installed)

**Subject options:** Halfway there, and what we've fixed · You asked, we fixed · 4 days left in the Bucks test
**Preview:** Here's what changed because of your feedback.
**Purpose:** show the feedback mattered and keep people installed.

> Hi {{first_name}},
>
> We're past the halfway point. Thanks for sticking with it.
>
> **Fixed or improved because of you:**
> - {{fix_1}}
> - {{fix_2}}
> - {{fix_3}}
>
> Update Bucks from the Play Store to get these.
>
> **Please keep Bucks installed until {{test_end_date}}.** Google needs testers to stay for the full 14 days before we can launch publicly.
>
> **[Update Bucks]** → {{play_link}}

### Email 6: Final stretch and survey (Day 13, installed)

**Subject options:** Last 2 days of the test: one favour · Almost done: 2 minutes of your opinion? · Before the test ends…
**Preview:** A short survey, and please stay opted in until {{test_end_date}}.
**Purpose:** prevent last-day drop-off and collect a final structured signal.

> Hi {{first_name}},
>
> The test ends on **{{test_end_date}}**. Two favours:
>
> 1. **Stay opted in until then.** Please don't leave the test or uninstall early.
> 2. **Answer 5 quick questions (2 minutes):** {{survey_link}}
>
> The survey asks: would you keep using Bucks, what you'd tell a friend about it, the one thing to fix first, and whether you felt safe.
>
> **[Take the 2-minute survey]** → {{survey_link}}

### Email 7: Launch (launch day, testers who completed)

**Subject options:** Thank you. Bucks is going public · You helped build this · Bucks is live on Google Play
**Preview:** Now anyone can join. Here's how to bring your people.
**Purpose:** turn finished testers into the first wave of word of mouth.

> Hi {{first_name}},
>
> **Bucks is now live on Google Play**, and you helped get it there. Thank you.
>
> Two ways to help now:
>
> - **Bring your people.** Share Bucks with friends: {{play_link}}. Friends you sync with make it worth opening.
> - **If you like Bucks, leave an honest review** on Google Play. It helps people decide whether to try it.
>
> Your account and posts carry over. Nothing to reinstall.
>
> **[Share Bucks]** → {{play_link}}

**Policy note:** never offer rewards for reviews or ask only happy users to review. Both break Google Play policy. Ask everyone, and ask
for honesty. Testers can't leave public reviews during the closed test (only private feedback), so the review ask waits for launch.

## Sequence flow

```
[Signs up on the form, confirms 18+] --> Email 1 (Day 0: join + install)
              |
        Installed by Day 2? --No--> Email 1b (Day 2) --> installed by Day 6? --No--> [EXIT: never activated]
              |                                               |
             Yes <--------------------------------------------+
              |
        Email 2 (Day 1 / right after install: first 10 minutes)
              |
        Active in last 3 days? --No--> Email 3b (Day 5: re-activate)
              |                                |
             Yes --> Email 3 (Day 4: invite)   |
              |                                |
              +--------------------------------+
              |
        Email 4 (Day 7: Feedback board)
              |
        Email 5 (Day 10: what we fixed, stay installed)
              |
        Email 6 (Day 13: stay opted in, survey)
              |
        Still opted in on Day 14? --No--> [EXIT: dropped out]
              |
             Yes --> [wait for public launch] --> Email 7 (launch day) --> [EXIT: complete]
```

## Branching and exit rules

- **Exits:** never installed by day 6 · unsubscribed · left the test in Play · asked to be removed · reached email 7.
- **Suppression:** don't send within 24 hours of a support reply to that person. Don't send email 3 to anyone who already referred 2+ people.
- **Re-entry:** none. A tester who leaves and rejoins gets only email 2, then rejoins the schedule at the current day.
- **Age:** anyone who says they're under 18 is not enrolled. If a parent signs up a teen, the parent gets the emails and the teen
  joins with the parent's consent in the app.
- **Unsubscribe link and your postal address in every email** (required by most email providers). Collect consent on the form ("Email
  me about the Bucks test and launch").

## How to know who installed and who's active

The app doesn't send anyone's email address anywhere, and analytics is anonymous, so there's no automatic link between an email and
in-app activity. Keep it simple for a test this size:

1. **Installed:** Play Console → Testing → Closed testing shows how many testers are opted in. For individuals, ask in email 1:
   "Reply 'in' once you've installed."
2. **Active:** in email 2, ask testers to put their Bucks ID (Profile → My Bucks ID) in a one-field form. You can then check their
   last activity yourself. Or skip the per-person branch and send 3b to everyone who hasn't replied or posted on the Feedback board.

## Benchmarks (targets for a small, warm list)

| Metric | Target |
|---|---|
| Email 1 open rate | 60–75% |
| Sign-up → installed | ≥ 60% (so 20 sign-ups give 12 or more installs) |
| Email click-through (emails 2–6) | 12–25% |
| Installed → synced with someone by day 4 | ≥ 50% |
| Posted on the Feedback board | ≥ 30% of installed testers |
| Opted in on day 14 | ≥ 12 people (hard requirement), aim for 15+ |
| Unsubscribe rate | < 1% per email |

## A/B tests (only once the list is 200+; with 20 testers, read the replies instead)

1. **Email 1 subject:** "You're in. Here's how to get Bucks" vs "{{first_name}}, Bucks is ready for you". Measure: installs by day 2.
2. **Email 3 framing:** "Bucks is better with your people" vs "Who would you invite first?". Measure: referrals per send.
3. **Send time:** 7 pm vs 12 noon IST. Measure: click-through within 24 hours.

## Setup checklist (any email tool: Mailchimp, Brevo, Klaviyo, Google Sheets + Gmail for a small list)

1. Make a sign-up form with name, email, Android (yes/no), "I'm 18 or older" (required) and marketing consent.
2. Create the automation, triggered by "form submitted".
3. Add emails 1–6 with the day delays above. Email 7 is a one-off campaign sent on launch day to the "completed" tag.
4. Add the conditions: tag `installed` (from replies or the form), tag `inactive` (manual), tag `completed` (opted in on day 14).
5. Fill every `{{placeholder}}`, send a test to yourself, check the links on an Android phone, then turn it on.
6. Each week, check opt-ins in Play Console, replies, and Feedback board posts.
