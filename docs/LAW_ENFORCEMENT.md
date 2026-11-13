# Requests from the police and the authorities

How Bucks staff handle a request for user data, an order to remove content, or an emergency. **Draft for legal review.** Have a lawyer confirm it, and name the people below, before launch.

The public promise is in [terms §5](legal/terms.md) and the [privacy policy](legal/privacy.md) ("Sharing with the police and the authorities").

## Who does what

| Role | Who | Does |
|---|---|---|
| **Nodal contact** (named in the grievance page once Bucks is a significant intermediary) | _to be named_ | Receives every request, checks it, decides, replies |
| **Data officer** | _to be named; at most two people_ | Runs the SQL below in the Supabase SQL editor. Nobody else reads `legal_holds` |
| Lawyer | _to be named_ | Anything unclear, any request from outside India, any request to keep it secret |

Requests come by email to the grievance address, or on paper. **Never answer a request made only by phone or WhatsApp.** Ask for it in writing from an official address.

## 1. Check the request (same day)

A valid request:

- comes from a police officer, a court, or a government agency, on letterhead or from an official email (`*.gov.in`, `*.nic.in`);
- names the law it is made under: for example section 94 of the BNSS 2023 (a summons to produce documents), sections 69 or 79(3)(b) of the IT Act, IT Rules 3(1)(d) or 3(1)(j), or a court order;
- says **which account** (Bucks ID, the phone number, or a link) and **what information**, for **what period**.

If something is missing, write back and ask for it. Don't share anything yet. Log every request in the register (step 5), including the ones you refuse.

## 2. Time limits

| Request | Deadline |
|---|---|
| Information under IT Rules 3(1)(j) (to verify identity, or to prevent, detect, investigate or prosecute an offence) | **72 hours** from the order |
| Remove content: a court order, or notice from the appropriate government or its agency, under 3(1)(d) | **36 hours** |
| Intimate images or impersonation complaint under 3(2)(b) | **24 hours** |
| Child sexual abuse material | Remove at once. Report to NCRB (cybercrime.gov.in) and, under POCSO s.19, to the local police |
| Emergency: a life is at risk now | As fast as you can, the same day. Then ask for the written request |

## 3. Find the data (data officer)

Use only the Supabase SQL editor (it runs as the owner). Copy the results into the request's folder. Don't paste them into chat.

**A live account, by phone or Bucks ID:**

```sql
select p.id, p.short_code, p.name, pp.phone, p.created_at, p.status, p.terms_version, p.terms_accepted_at, ps.birth_date, ps.age_band
from profiles p left join profile_private pp on pp.profile_id = p.id left join profile_safety ps on ps.profile_id = p.id
where pp.phone = '+91XXXXXXXXXX' or p.short_code = 'XXXXXX';
```

**A deleted account** (sealed for 180 days after deletion):

```sql
select * from legal_holds where phone = '+91XXXXXXXXXX' or short_code = 'XXXXXX';
```

**Trips** (rides and deliveries) for a profile id, in a period:

```sql
select t.id, t.type, t.status, t.created_at, t.started_at, t.completed_at, t.requester_id, t.driver_id, t.vehicle_id,
       st_y(t.pickup::geometry) pickup_lat, st_x(t.pickup::geometry) pickup_lng, t.pickup_label,
       st_y(t.drop_at::geometry) drop_lat, st_x(t.drop_at::geometry) drop_lng, t.drop_label, t.km, t.fare, t.paid_with
from tasks t where '<profile id>' in (t.requester_id, t.driver_id) and t.created_at between '<from>' and '<to>'
order by t.created_at;
select * from task_events where task_id = '<task id>' order by at;
```

**Vehicle of a trip:** `select id, kind, plate, model, owner_id from vehicles where id = '<vehicle id>';` (or `legal_holds.vehicles` if the owner deleted their account).

**Orders:** `select * from orders where buyer_id = '<profile id>' and created_at between '<from>' and '<to>';`

**Reports and removed content:** `select * from reports where target_owner = '<profile id>' or reporter_id = '<profile id>';` The `snapshot` column holds what was reported.

**Messages:** share chat content only under a court order or a request that specifically names the conversation. `select * from messages where conversation_id = '<id>' and created_at between '<from>' and '<to>';` Messages a person deleted show an empty body.

Share **only what the request covers**: the account named, the period named, the fields named.

## 4. Preserve

If the authority asks you to keep data for an investigation, or you expect a request:

```sql
update legal_holds set preserve_until = now() + interval '1 year', preserve_note = '<authority, reference, date>' where profile_id = '<id>';
```

For a live account, export the rows above into the request folder now. The person could delete their account tomorrow, and the sealed record holds only registration details, not trips or messages.

## 5. Reply and record

- Reply from the grievance address, with the data as a password-protected PDF or spreadsheet. Send the password separately.
- Keep a **register**, one row per request: date received, authority, officer, reference number, law cited, account, what was asked, what was shared, date replied, who handled it. Keep the register for at least 3 years.
- Don't tell the user about a request when the request says not to or telling them could put someone at risk. Otherwise, the lawyer decides.

## 6. Emergencies (before any request)

When someone may be about to come to serious harm (a missing rider, a threat of violence, self-harm, a child at risk):

1. Call **112** and give the police what they need to find the person: the trip, the driver and vehicle, the last location.
2. Note who you called, when, and what you shared, in the register.
3. Ask the police to send the written request afterwards.
