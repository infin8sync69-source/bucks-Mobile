-- App Review: the store reviewers' sign-in numbers see the demo world from wherever they are.
--
-- Apple and Google review from outside India, where Bucks has no shops, pros or drivers nearby, so the app would look empty. A number
-- listed here (a Firebase "phone number for testing", given to the reviewers in the store consoles) gets a fixed position from
-- review_anchor(), and the apps use it instead of the phone's GPS for that account only. Everyone else is unaffected.
--
-- The numbers are not in the repository. Add one in the SQL editor (the dashboard runs as the owner):
--   insert into public.review_accounts (phone, lat, lng, label, note)
--   values ('+91XXXXXXXXXX', 13.003, 77.745, 'Whitefield, Bengaluru', 'App Store and Play review');
-- Remove a row once that number is deleted from Firebase.

create table if not exists public.review_accounts (
  phone      text primary key check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  lat        double precision not null check (lat between -90 and 90),
  lng        double precision not null check (lng between -180 and 180),
  label      text not null default '' check (length(label) <= 80),
  note       text not null default '',
  created_at timestamptz not null default now()
);
alter table public.review_accounts enable row level security;
-- No policies: nobody reads or writes the table through the API. review_anchor() reads it as its owner.
revoke all on public.review_accounts from public, anon, authenticated;

-- The fixed position for the signed-in number, or no row. The number comes from the sign-in token only.
create or replace function public.review_anchor() returns table (lat double precision, lng double precision, label text)
language sql stable security definer set search_path = public as $$
  select r.lat, r.lng, r.label from public.review_accounts r
  where r.phone = nullif(auth.jwt()->>'phone_number', '')
$$;
revoke execute on function public.review_anchor() from public, anon;
grant execute on function public.review_anchor() to authenticated;
