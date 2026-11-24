# Trip safety: SOS, trusted contacts, live trip links, ride alerts

What riders, drivers and delivery riders can do when something is wrong, and what Bucks staff do about it. Server: `supabase/migrations/trip_safety.sql`. Push: `functions/notify` (tables `sos_events`, `ride_alerts`). Live page: `docs/trip/index.html` and `functions/trip`. Apps: Android `ui/safety/TripSafety.kt`, iOS `Screens/Safety/TripSafetyViews.swift`.

## For people using Bucks

| Feature | Where | What happens |
|---|---|---|
| **SOS** | Every trip screen: driver on the way, driver arrived, in the ride (riders), and the whole trip (drivers and delivery riders) | Bucks staff are alerted at once (push, whatever their settings). The sheet offers **Call 112**, **Text my trusted contacts** (one SMS with the vehicle, plate, a map link and the live trip link) and **Share live trip link**. Calling 112 and the SMS work even when Bucks can't be reached. "I'm safe now" closes the alert. |
| **Trusted contacts** | Android: Settings → Safety. iOS: Account → Safety | Up to 5 Indian mobile numbers. They don't need Bucks. |
| **Share trip** | Trip screens | Shares a link to a live page: driver, vehicle, plate, pickup, drop, and the driver's position every 15 s while the trip is on. It stops showing the location when the trip ends, and the link expires after 12 hours. |
| **Are you OK?** | In the ride | If the ride has **stopped for 8 minutes**, **drifted 3 km further from the drop than the pickup was**, or the **driver's phone stopped reporting for 6 minutes**, the rider gets a push and a card: *I'm OK* or *SOS*. No answer in **5 minutes**: an SOS is raised for them automatically. |

The thresholds are in `settings` (`ride_stop_alert_minutes`, `ride_offroute_m`, `ride_silent_alert_minutes`, `ride_alert_escalate_minutes`). Set one to 0 to switch that check off.

## For Bucks staff: when an SOS comes in

1. **Open the SOS list straight away.** Android: Settings → Review reports (SOS is at the top). iOS: Account → SOS alerts. It shows the person, their role (rider, driver, or AUTO for an unanswered "Are you OK?"), the other person, the vehicle, and where they are.
2. **Call the person.** If they don't answer, or say they're in danger, **call 112** and give the police the vehicle, plate, the driver's or rider's name and phone, and the live trip link.
3. **Call the other person** only if it's safe to do so, and never tell them who raised the alert.
4. **Close the alert** once the person is safe or the police have it. Then record what happened in the report register (see [LAW_ENFORCEMENT.md](LAW_ENFORCEMENT.md) §6).
5. If the driver or rider did something wrong, **suspend their account** from the report queue, and keep the records (the legal hold applies if they delete their account).

Target: every SOS answered within **2 minutes**, round the clock. That needs someone on call. With 2 staff accounts today, that is the biggest gap.

## Not built yet

- Women-safety extras: preferring a woman driver, a late-night check-in on every ride, and sharing the trip automatically with a chosen contact.
- Sending SMS from the server to trusted contacts (needs MSG91 DLT templates). Today the person's own phone sends it.
- Audio recording during a ride, and a direct link to the state's ERSS-112 system (the Motor Vehicle Aggregator Guidelines expect panic buttons to be linked to it).
- Police verification of drivers.
