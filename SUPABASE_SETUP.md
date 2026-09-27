# Supabase setup

Bucks keeps its data in Supabase (Postgres) and signs people in with Firebase phone OTP.
Supabase trusts the Firebase sign-in, so there is one login and no second password.

## 1. Project
1. https://supabase.com/dashboard → New project. Region: **Mumbai (ap-south-1)**. Save the database password somewhere safe.
2. SQL Editor → paste all of `supabase/schema.sql` → Run. It is safe to run again after updates.

## 2. Trust Firebase sign-ins
1. Supabase → Authentication → Sign In / Providers → **Third-party auth** → Add → **Firebase** → enter your Firebase project ID.
2. Firebase tokens must carry `role: authenticated`. Deploy the small function in `firebase/functions`:
   ```
   npm i -g firebase-tools && firebase login
   cd firebase/functions && npm install && firebase deploy --only functions --project <your-firebase-project-id>
   ```
   (Needs the Firebase Blaze plan, which phone sign-in already needs.)

## 3. Orders that time out
Database → Extensions → enable **pg_cron**, then in the SQL Editor:
```sql
select cron.schedule('expire-orders', '* * * * *', 'select public.expire_orders()');
```

## 4. Give the app its keys
Project Settings → API. Copy the **Project URL** and the **anon public** key into `local.properties`:
```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```
For GitHub builds, add the same two values as repository secrets with those names.
The anon key is meant to be in the app; security comes from the row-level rules in schema.sql.
**Never put the `service_role` key in the app or the repo.**

## 5. Rules that are enforced by the database (tested in `supabase/tests/scenarios.sql`)
- New businesses, skill profiles and drivers start **PENDING** and are invisible until **7 local people** recommend them
  by scanning the owner's QR in person. Recommenders must live within 3 km, stand within 3 km, and have an account at least 14 days old.
- Only owners delete; admins run the listing; nobody can edit their own trust or status.
- Prices are always taken from the database, never from the app.
- Cash on delivery only with the store's own riders. Orders not accepted in 5 minutes are rejected.
- Bikes carry goods only. Deliveries ring online bikes within 3 km of the shop.
- Reviews only after a completed trip or delivered order.

Tunables (7 recommendations, 3 km, 5 minutes, delivery ₹20 + ₹8/km) are rows in the `settings` table.

## Run the tests locally
```
psql -d <scratch database> -f supabase/tests/local_auth_shim.sql -f supabase/schema.sql -f supabase/tests/scenarios.sql
```
