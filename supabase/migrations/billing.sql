-- Provider licences: a simple prepaid renewal, no Autopay. Setup: docs/BILLING_SETUP.md. Tests: supabase/tests/billing_scenarios.sql.
--
-- Who pays: only providers. Every SKILL listing, BUSINESS listing and vehicle (bike, auto, cab) has its own licence with its own
-- code (SK…, BZ…, TX… + 6 characters) and a VALID TILL date. DRIVER listings and buyers never pay. A licence never changes trust,
-- ranking or the go-live rules.
--
-- Renewing is the provider's choice: they pay on the Razorpay Payment Page for their plan (Skills, Taxi, Business), choose
-- 1, 6 or 12 months and type their licence code. Razorpay's signed webhook (payment.captured) reaches billing_apply_event(),
-- which finds the licence by the code (or, failing that, by the payer's phone when it has exactly one licence of that plan) and
-- moves VALID TILL forward. Nothing renews by itself and nothing is ever debited: a provider who ignores it simply expires.
--
-- Life of a licence (one row per listing or vehicle in billing_licences):
--   starts when the listing first goes LIVE or the vehicle is approved (and billing is switched on), already valid for
--     FOUNDING  founding_free_months free (joined before founding_until, first founding_cap licences). Renewals paid until
--               founding_bonus_months after that count double: pay 1 month, get 2 (the same as half price, on fixed page prices)
--     TRIAL     trial_days free
--     (none)    a free period was used before for this plan and phone, or this plate: valid until today, so the grace week runs
--   ACTIVE    paid (or free) and valid_till is ahead
--   GRACE     valid_till has passed: still live for grace_days. But a paid licence whose page or vehicle got fewer than
--             guarantee_min_enquiries enquiries in its last month gets a free month instead (billing_guarantee)
--   EXPIRED   grace over: the listing is SUSPENDED with billing_hold (out of search, profile kept), the vehicle cannot go online.
--             Paying at any time brings it back at once, with the new months counted from the day of payment.
--
-- Reminders: billing_daily() sends a push note and queues an SMS (billing_messages; Edge Function "licence-notify") reminder_days
-- before VALID TILL, on the day it lapses, when it is paused, and winback_days after that. The app only reads my_licences(): it
-- never sells a licence, shows a price or links to the payment page (Google Play payments policy); the SMS carries the link.
--
-- Switched off until billing_config.enabled = 'on': no licences are created and nothing is ever paused.

-- ---------- settings ----------
create table if not exists public.billing_config (key text primary key, value text not null);
alter table public.billing_config enable row level security;
revoke all on public.billing_config from public, anon, authenticated;
insert into public.billing_config (key, value) values
  ('enabled', 'off'),                  -- 'on' to start licences, reminders and pauses
  ('trial_days', '30'),
  ('grace_days', '7'),
  ('founding_until', '2027-03-31'),    -- last day a new listing or vehicle can become a Founding Member (IST)
  ('founding_cap', '500'),             -- at most this many Founding Member licences
  ('founding_free_months', '3'),
  ('founding_bonus_months', '9'),      -- after the free months, renewals paid inside this window count double
  ('reminder_days', '7,3,1'),          -- reminders this many days before VALID TILL
  ('winback_days', '7,30'),            -- reminders this many days after a licence was paused
  ('guarantee_min_enquiries', '1'),    -- a paid licence with fewer enquiries than this in its last guarantee_days gets a free month
                                       -- ('0' switches the guarantee off)
  ('guarantee_days', '30'),
  ('guarantee_max_per_year', '2')      -- at most this many free months per licence in any 365 days
on conflict (key) do nothing;

create or replace function public.billing_cfg(k text) returns text language sql stable security definer set search_path = public, extensions as $$
  select value from public.billing_config where key = k
$$;
create or replace function public.billing_on() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from public.billing_config where key = 'enabled'), 'off') = 'on'
$$;

-- ---------- plans (prices in paise, GST included) ----------
-- The webhook tells the plan and length from the amount paid, so no two active plans may share a price.
create table if not exists public.billing_plans (
  code         text not null check (code in ('SKILL', 'TAXI', 'BUSINESS')),
  months       int  not null check (months in (1, 6, 12)),
  label        text not null,
  price_paise  int  not null check (price_paise > 0),
  page_url     text,                  -- the plan's Razorpay Payment Page (https://rzp.io/… or pages.razorpay.com/…), sent in SMS
  active       boolean not null default true,
  primary key (code, months)
);
create unique index if not exists billing_plans_price_uq on public.billing_plans (price_paise) where active;
alter table public.billing_plans enable row level security;
revoke all on public.billing_plans from public, anon, authenticated;
insert into public.billing_plans (code, months, label, price_paise) values
  ('SKILL',    1, 'Skills',    9900), ('SKILL',    6, 'Skills',    49900), ('SKILL',    12, 'Skills',    99000),
  ('TAXI',     1, 'Taxi',     19900), ('TAXI',     6, 'Taxi',      99900), ('TAXI',     12, 'Taxi',     199000),
  ('BUSINESS', 1, 'Business', 29900), ('BUSINESS', 6, 'Business', 149900), ('BUSINESS', 12, 'Business', 299000)
on conflict (code, months) do nothing;

-- ---------- licences, payments, events, messages, free-period claims ----------
create table if not exists public.billing_licences (
  id                  uuid primary key default public.uuid_v7(),
  code                text not null unique,                      -- what the provider types on the payment page
  owner_id            uuid not null references public.profiles on delete cascade,
  listing_id          uuid unique references public.listings on delete set null,
  vehicle_id          uuid unique references public.vehicles on delete set null,
  plan_code           text not null check (plan_code in ('SKILL', 'TAXI', 'BUSINESS')),
  founding            boolean not null default false,
  free_kind           text check (free_kind in ('FOUNDING', 'TRIAL')),   -- the free period it started with, if any
  valid_from          timestamptz not null default now(),
  valid_till          timestamptz not null,
  founding_bonus_until timestamptz,                              -- renewals paid before this count double
  paid                boolean not null default false,            -- at least one payment has been applied
  held                boolean not null default false,            -- paused for not renewing
  held_at             timestamptz,
  held_from_live      boolean not null default false,            -- the listing was LIVE when billing paused it (so paying brings it back)
  stage               int not null default 0,                    -- reminders sent for the current valid_till (see billing_daily)
  last_months         int,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (num_nonnulls(listing_id, vehicle_id) <= 1)
);
create index if not exists billing_licences_owner_idx on public.billing_licences (owner_id);
create index if not exists billing_licences_till_idx on public.billing_licences (valid_till);
alter table public.billing_licences enable row level security;
revoke all on public.billing_licences from public, anon, authenticated;

create table if not exists public.billing_payments (
  payment_id        text primary key,                            -- pay_…
  licence_id        uuid references public.billing_licences on delete set null,
  owner_id          uuid references public.profiles on delete set null,
  plan_code         text,
  months            int,
  amount_paise      int not null,
  gst_paise         int not null,                                -- 18% GST inside the amount
  contact           text,                                        -- the payer's phone as Razorpay reported it
  code_given        text,                                        -- what the payer typed, as received
  status            text not null check (status in ('APPLIED', 'UNMATCHED', 'REFUNDED')),
  valid_till_before timestamptz,
  valid_till_after  timestamptz,
  bonus_days        int not null default 0,
  note              text not null default '',
  paid_at           timestamptz not null default now()
);
create index if not exists billing_payments_unmatched_idx on public.billing_payments (paid_at) where status = 'UNMATCHED';
alter table public.billing_payments enable row level security;
revoke all on public.billing_payments from public, anon, authenticated;

create table if not exists public.billing_events (
  id          text primary key,                                  -- Razorpay's x-razorpay-event-id (a replay is ignored)
  event       text not null,
  payment_id  text,
  licence_id  uuid references public.billing_licences on delete set null,
  payload     jsonb not null,
  result      text not null default '',
  received_at timestamptz not null default now()
);
alter table public.billing_events enable row level security;
revoke all on public.billing_events from public, anon, authenticated;

-- SMS waiting for licence-notify. Only messages younger than two days are sent: a stale reminder is worse than none.
create table if not exists public.billing_messages (
  id         uuid primary key default public.uuid_v7(),
  licence_id uuid references public.billing_licences on delete cascade,
  phone      text not null,                                      -- 91XXXXXXXXXX
  template   text not null check (template in ('START', 'RENEW_SOON', 'LAPSED', 'PAUSED', 'WINBACK', 'PAID')),
  vars       jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  attempts   int not null default 0,
  error      text
);
create index if not exists billing_messages_queue_idx on public.billing_messages (created_at) where sent_at is null;
alter table public.billing_messages enable row level security;
revoke all on public.billing_messages from public, anon, authenticated;

create table if not exists public.billing_free_claims (
  claim_key  text primary key,                                   -- sha256 of plan + phone (or profile), or of the vehicle plate
  created_at timestamptz not null default now()
);
alter table public.billing_free_claims enable row level security;
revoke all on public.billing_free_claims from public, anon, authenticated;

-- ---------- the hold flags ----------
alter table public.listings add column if not exists billing_hold boolean not null default false;
alter table public.vehicles add column if not exists billing_hold boolean not null default false;

create or replace function public.billing_mark_wants_live(p_listing uuid) returns void language sql security definer set search_path = public, extensions as $$
  update public.billing_licences set held_from_live = true where listing_id = p_listing
$$;

-- Owners can never set or clear a hold, and a held listing can never be LIVE (also when a document check brings it back).
-- Named zz_ so it runs after the other before-triggers have settled new.status.
create or replace function public.billing_listing_guard() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' then
    if tg_op = 'INSERT' then new.billing_hold := false;
    elsif new.billing_hold <> old.billing_hold then raise exception 'licences are managed by Bucks'; end if;
  end if;
  if new.billing_hold and new.status = 'LIVE' then
    new.status := 'SUSPENDED'; new.online := false;
    perform public.billing_mark_wants_live(new.id);   -- a document check tried to bring it back: renewing should
  end if;
  return new;
end $$;
drop trigger if exists zz_billing_listing_guard on public.listings;
create trigger zz_billing_listing_guard before insert or update on public.listings for each row execute function public.billing_listing_guard();

create or replace function public.billing_vehicle_guard() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if current_user = 'authenticated' then
    if tg_op = 'INSERT' then new.billing_hold := false;
    elsif new.billing_hold <> old.billing_hold then raise exception 'licences are managed by Bucks'; end if;
  end if;
  return new;
end $$;
drop trigger if exists zz_billing_vehicle_guard on public.vehicles;
create trigger zz_billing_vehicle_guard before insert or update on public.vehicles for each row execute function public.billing_vehicle_guard();

-- A vehicle on hold cannot go online (claim_task already needs the driver online). Going offline is always allowed.
create or replace function public.billing_presence_guard() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.online and exists (select 1 from vehicles v where v.id = new.vehicle_id and v.billing_hold) then
    raise exception 'this vehicle''s Bucks licence has expired; we''ve sent the renewal details to your phone by SMS';
  end if;
  return new;
end $$;
drop trigger if exists zz_billing_presence_guard on public.driver_presence;
create trigger zz_billing_presence_guard before insert or update on public.driver_presence for each row execute function public.billing_presence_guard();

-- The owner hears why the listing was paused (notifications.sql's version, plus the licence case).
create or replace function public.note_listing_status() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'LIVE' and old.status <> 'LIVE' then
    perform push_note_team(new.id, 'LISTING_LIVE', new.title || ' is live', 'People nearby can find it now. Switch it on when you''re ready for work.', 'studio/' || new.id);
  elsif new.status = 'SUSPENDED' and old.status = 'LIVE' then
    perform push_note_team(new.id, 'LISTING_PAUSED', new.title || ' was paused',
      case when new.billing_hold then 'Its Bucks licence has expired. We''ve sent the renewal details to your phone by SMS.'
           when new.compliance_hold then 'A document expired or is missing. Upload it and it comes back on its own.'
           else 'Contact Bucks support to sort it out.' end, 'studio/' || new.id);
  end if;
  return null;
end $$;

-- ---------- helpers ----------
create or replace function public.billing_ist_day(t timestamptz) returns text language sql stable set search_path = public, extensions as $$
  select to_char(t at time zone 'Asia/Kolkata', 'FMDD Mon YYYY')
$$;

-- SK / TX / BZ + 6 characters without look-alikes (no 0, 1, I, L, O).
create or replace function public.billing_new_code(p_plan text) returns text language plpgsql volatile security definer set search_path = public, extensions as $$
declare alphabet text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ'; c text; b bytea;
begin
  loop
    b := gen_random_bytes(6);
    c := case p_plan when 'SKILL' then 'SK' when 'TAXI' then 'TX' else 'BZ' end;
    for i in 0..5 loop c := c || substr(alphabet, (get_byte(b, i) % length(alphabet)) + 1, 1); end loop;
    exit when not exists (select 1 from billing_licences where code = c);
  end loop;
  return c;
end $$;

-- A typed code as the database stores it: upper case, no spaces or dashes.
create or replace function public.billing_norm_code(t text) returns text language sql immutable set search_path = public, extensions as $$
  select upper(regexp_replace(coalesce(t, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

create or replace function public.billing_phone(p_owner uuid) returns text language sql stable security definer set search_path = public, extensions as $$
  select '91' || right(regexp_replace(phone, '\D', '', 'g'), 10) from profile_private where profile_id = p_owner and length(regexp_replace(phone, '\D', '', 'g')) >= 10
$$;

create or replace function public.billing_subject(l billing_licences) returns text language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select x.title from listings x where x.id = l.listing_id), (select v.plate from vehicles v where v.id = l.vehicle_id), 'Your Bucks page')
$$;

-- Queues one SMS for the licence's owner (nothing when billing is off or the phone is unknown).
create or replace function public.billing_queue_sms(l billing_licences, p_template text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare ph text := billing_phone(l.owner_id); page text;
begin
  if ph is null or not billing_on() then return; end if;
  select page_url into page from billing_plans where code = l.plan_code and months = 1;
  insert into billing_messages (licence_id, phone, template, vars)
  values (l.id, ph, p_template, jsonb_build_object(
    'name', coalesce((select split_part(name, ' ', 1) from profiles where id = l.owner_id), ''),
    'subject', left(billing_subject(l), 30), 'code', l.code, 'date', billing_ist_day(l.valid_till),
    'grace_date', billing_ist_day(l.valid_till + make_interval(days => billing_cfg('grace_days')::int)),
    'link', coalesce(page, '')));
end $$;

create or replace function public.billing_claim_key(p_plan text, p_owner uuid, p_plate text) returns text
language sql stable security definer set search_path = public, extensions as $$
  select encode(sha256(convert_to(case
    when p_plate is not null then 'plate:' || upper(regexp_replace(p_plate, '[^A-Za-z0-9]', '', 'g'))
    else 'owner:' || p_plan || ':' || coalesce((select regexp_replace(phone, '\D', '', 'g') from profile_private where profile_id = p_owner), p_owner::text)
  end, 'UTF8')), 'hex')
$$;

-- ---------- starting a licence ----------
-- Creates the licence for a listing or a vehicle that just became usable. Returns its free_kind ('NONE' when no free period was
-- given), or null when billing is off, the subject already has one, or it is not billable.
create or replace function public.billing_start(p_listing uuid, p_vehicle uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare owner uuid; plan text; plate text; key text; is_founding boolean; l billing_licences; till timestamptz;
begin
  if not billing_on() then return null; end if;
  if p_listing is not null then
    select x.owner_id, case x.kind when 'SKILL' then 'SKILL' when 'BUSINESS' then 'BUSINESS' end into owner, plan from listings x where x.id = p_listing;
    if plan is null or exists (select 1 from billing_licences where listing_id = p_listing) then return null; end if;
  else
    select v.owner_id, 'TAXI', v.plate into owner, plan, plate from vehicles v where v.id = p_vehicle;
    if owner is null or exists (select 1 from billing_licences where vehicle_id = p_vehicle) then return null; end if;
  end if;
  if owner is null then return null; end if;

  key := billing_claim_key(plan, owner, plate);
  is_founding := (now() at time zone 'Asia/Kolkata')::date <= billing_cfg('founding_until')::date
              and (select count(*) from billing_licences where founding) < billing_cfg('founding_cap')::int;
  insert into billing_free_claims (claim_key) values (key) on conflict do nothing;
  if not found then
    -- Already had a free period for this plan (or this plate): valid until now, so the grace week runs while they renew.
    insert into billing_licences (code, owner_id, listing_id, vehicle_id, plan_code, valid_till, stage)
    values (billing_new_code(plan), owner, p_listing, p_vehicle, plan, now(), 99) returning * into l;
    perform push_note(owner, 'BILLING', billing_subject(l) || ': licence needed',
      format('The free period was used before, so a licence is needed now. It stays live until %s. Licence code %s.',
             billing_ist_day(now() + make_interval(days => billing_cfg('grace_days')::int)), l.code), 'bucks-id');
    perform billing_queue_sms(l, 'LAPSED');
    return 'NONE';
  elsif is_founding then
    till := now() + make_interval(months => billing_cfg('founding_free_months')::int);
    insert into billing_licences (code, owner_id, listing_id, vehicle_id, plan_code, founding, free_kind, valid_till, founding_bonus_until)
    values (billing_new_code(plan), owner, p_listing, p_vehicle, plan, true, 'FOUNDING', till,
            till + make_interval(months => billing_cfg('founding_bonus_months')::int)) returning * into l;
    perform push_note(owner, 'BILLING', 'You''re a Bucks Founding Member',
      format('%s is licensed free until %s. Renewals in the %s months after that count double.', billing_subject(l), billing_ist_day(till),
             billing_cfg('founding_bonus_months')), 'bucks-id');
  else
    till := now() + make_interval(days => billing_cfg('trial_days')::int);
    insert into billing_licences (code, owner_id, listing_id, vehicle_id, plan_code, free_kind, valid_till)
    values (billing_new_code(plan), owner, p_listing, p_vehicle, plan, 'TRIAL', till) returning * into l;
    perform push_note(owner, 'BILLING', 'Your free licence has started', format('%s is licensed free until %s.', billing_subject(l), billing_ist_day(till)), 'bucks-id');
  end if;
  perform billing_queue_sms(l, 'START');
  return l.free_kind;
end $$;

create or replace function public.billing_on_listing_live() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'LIVE' and (tg_op = 'INSERT' or old.status <> 'LIVE') and new.kind in ('SKILL', 'BUSINESS') then perform billing_start(new.id, null); end if;
  return null;
end $$;
drop trigger if exists billing_listing_live on public.listings;
create trigger billing_listing_live after insert or update of status on public.listings for each row execute function public.billing_on_listing_live();

create or replace function public.billing_on_vehicle_active() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'ACTIVE' and (tg_op = 'INSERT' or old.status <> 'ACTIVE') then perform billing_start(null, new.id); end if;
  return null;
end $$;
drop trigger if exists billing_vehicle_active on public.vehicles;
create trigger billing_vehicle_active after insert or update of status on public.vehicles for each row execute function public.billing_on_vehicle_active();

-- When billing is switched on for a project that already has live providers: give each of them a licence.
create or replace function public.billing_backfill() returns int language plpgsql security definer set search_path = public, extensions as $$
declare n int := 0; r record;
begin
  if not billing_on() then raise exception 'switch billing on first (billing_config.enabled = on)'; end if;
  for r in select id from listings where status = 'LIVE' and kind in ('SKILL', 'BUSINESS') and id not in (select listing_id from billing_licences where listing_id is not null) loop
    if billing_start(r.id, null) is not null then n := n + 1; end if;
  end loop;
  for r in select id from vehicles where status = 'ACTIVE' and id not in (select vehicle_id from billing_licences where vehicle_id is not null) loop
    if billing_start(null, r.id) is not null then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---------- hold and release ----------
create or replace function public.billing_pause(l billing_licences) returns void language plpgsql security definer set search_path = public, extensions as $$
declare was_live boolean := false;
begin
  if l.listing_id is not null then
    select status = 'LIVE' into was_live from listings where id = l.listing_id;
    -- status is named here so note_listing_status (an "update of status" trigger) tells the team why.
    update listings set billing_hold = true, status = case when status = 'LIVE' then 'SUSPENDED' else status end, online = false
     where id = l.listing_id and not billing_hold;
  elsif l.vehicle_id is not null then
    update vehicles set billing_hold = true where id = l.vehicle_id and not billing_hold;
    update driver_presence set online = false where vehicle_id = l.vehicle_id and online;
  end if;
  update billing_licences set held = true, held_at = now(), held_from_live = held_from_live or coalesce(was_live, false), updated_at = now() where id = l.id;
end $$;

create or replace function public.billing_unpause(l billing_licences) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if l.listing_id is not null then
    update listings set billing_hold = false,
           status = case when status = 'SUSPENDED' and not compliance_hold and l.held_from_live then 'LIVE' else status end
     where id = l.listing_id and billing_hold;
  elsif l.vehicle_id is not null then
    update vehicles set billing_hold = false where id = l.vehicle_id and billing_hold;
  end if;
  update billing_licences set held = false, held_at = null, held_from_live = false where id = l.id;
end $$;

-- Moves VALID TILL forward by p_months (paid) or p_days (staff), from VALID TILL while it is still valid or in its grace week (the
-- grace days were used), or from now once it was paused. Founding renewals inside the bonus window count double. Returns the row.
create or replace function public.billing_extend(p_licence uuid, p_months int, p_days int, p_paid boolean) returns billing_licences
language plpgsql security definer set search_path = public, extensions as $$
declare l billing_licences; start timestamptz; base_end timestamptz; bonus interval := interval '0';
begin
  select * into l from billing_licences where id = p_licence for update;
  if not found then raise exception 'licence not found'; end if;
  start := case when l.held then now() else l.valid_till end;
  base_end := start + make_interval(months => coalesce(p_months, 0), days => coalesce(p_days, 0));
  if p_paid and l.founding and l.founding_bonus_until > start then
    bonus := least(base_end, l.founding_bonus_until) - start;
  end if;
  update billing_licences set valid_till = base_end + bonus, stage = 0, paid = paid or p_paid,
         last_months = case when p_paid then p_months else last_months end, updated_at = now()
   where id = l.id returning * into l;
  perform billing_unpause(l);
  select * into l from billing_licences where id = l.id;
  return l;
end $$;

-- ---------- enquiries and the no-enquiry guarantee ----------
-- An enquiry is something a customer started through Bucks: for a page, a new chat about it or an order (by anyone who is not on
-- its team); for a vehicle, a ride or delivery it accepted and did not cancel.
create or replace function public.billing_enquiries(l billing_licences, p_from timestamptz, p_to timestamptz) returns int
language sql stable security definer set search_path = public, extensions as $$
  select case when l.listing_id is not null then
    (select count(*) from conversations c where c.listing_id = l.listing_id and c.kind = 'LISTING' and c.created_at >= p_from and c.created_at < p_to
        and c.created_by <> l.owner_id and not exists (select 1 from listing_members m where m.listing_id = l.listing_id and m.profile_id = c.created_by))
  + (select count(*) from orders o where o.listing_id = l.listing_id and o.created_at >= p_from and o.created_at < p_to
        and o.buyer_id <> l.owner_id and not exists (select 1 from listing_members m where m.listing_id = l.listing_id and m.profile_id = o.buyer_id))
  else
    (select count(*) from tasks t where t.vehicle_id = l.vehicle_id and t.created_at >= p_from and t.created_at < p_to
        and t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'PAID'))
  end::int
$$;

-- When a paid licence reaches VALID TILL with (almost) no enquiries in its last guarantee_days, Bucks adds a free month instead of
-- asking for money: providers pay for results, not promises. Only while the page was LIVE or the vehicle ACTIVE, at most
-- guarantee_max_per_year times in 365 days. Returns true when it extended the licence.
create or replace function public.billing_guarantee(l billing_licences) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare need int := coalesce(billing_cfg('guarantee_min_enquiries'), '0')::int; days int := coalesce(billing_cfg('guarantee_days'), '30')::int;
        got int; used int; t timestamptz;
begin
  if need <= 0 or not l.paid or l.held then return false; end if;
  if l.listing_id is not null and not exists (select 1 from listings where id = l.listing_id and status = 'LIVE') then return false; end if;
  if l.vehicle_id is not null and not exists (select 1 from vehicles where id = l.vehicle_id and status = 'ACTIVE') then return false; end if;
  select count(*) into used from billing_events where licence_id = l.id and event = 'guarantee.free_month' and received_at > now() - interval '365 days';
  if used >= coalesce(billing_cfg('guarantee_max_per_year'), '2')::int then return false; end if;
  got := billing_enquiries(l, l.valid_till - make_interval(days => days), l.valid_till);
  if got >= need then return false; end if;
  t := (billing_extend(l.id, 0, days, false)).valid_till;
  insert into billing_events (id, event, licence_id, payload, result)
  values ('guarantee:' || l.id || ':' || extract(epoch from l.valid_till)::bigint, 'guarantee.free_month', l.id,
          jsonb_build_object('enquiries', got, 'days', days), 'extended') on conflict (id) do nothing;
  perform push_note(l.owner_id, 'BILLING', billing_subject(l) || ': a free month from Bucks',
    format('Customers didn''t reach you through Bucks last month, so your licence is extended free till %s. Nothing to pay.', billing_ist_day(t)), 'bucks-id');
  return true;
end $$;

-- ---------- the daily run (10:00 IST): reminders, lapses, pauses, win-back ----------
-- stage counts what was sent for the current valid_till: 1..R reminders before it, R+1 the lapse notice, R+2 the pause,
-- then one more per winback_days. billing_extend resets it to 0.
create or replace function public.billing_daily() returns int language plpgsql security definer set search_path = public, extensions as $$
declare l billing_licences; n int := 0; grace interval := make_interval(days => billing_cfg('grace_days')::int);
        rem int[] := coalesce(string_to_array(nullif(billing_cfg('reminder_days'), ''), ',')::int[], '{}');
        win int[] := coalesce(string_to_array(nullif(billing_cfg('winback_days'), ''), ',')::int[], '{}');
        r int; days_left int; subj text; st int;
begin
  if not billing_on() then return 0; end if;
  r := coalesce(array_length(rem, 1), 0);
  for l in select * from billing_licences where valid_till < now() + make_interval(days => coalesce(rem[1], 0) + 1) or held for update loop
    subj := billing_subject(l);
    days_left := ceil(extract(epoch from l.valid_till - now()) / 86400)::int;
    st := least(l.stage, r + 2 + coalesce(array_length(win, 1), 0));
    if l.stage = 99 then st := r + 1; end if;   -- started without a free period: the lapse notice was sent at the start

    if not l.held and now() < l.valid_till then
      if st < r and days_left <= rem[st + 1] then
        -- Skip reminders a short licence has already passed (a 1-month renewal never gets the 7-day one twice).
        while st + 1 < r and days_left <= rem[st + 2] loop st := st + 1; end loop;
        update billing_licences set stage = st + 1, updated_at = now() where id = l.id;
        perform push_note(l.owner_id, 'BILLING', format('%s: licence valid till %s', subj, billing_ist_day(l.valid_till)),
          format('Renew it any time with licence code %s. We''ve sent the details to your phone by SMS.', l.code), 'bucks-id');
        perform billing_queue_sms(l, 'RENEW_SOON');
        n := n + 1;
      end if;

    elsif not l.held and now() < l.valid_till + grace then
      if st <= r and billing_guarantee(l) then
        n := n + 1;   -- no enquiries last month: a free month instead of a lapse notice
      elsif st <= r then
        update billing_licences set stage = r + 1, updated_at = now() where id = l.id;
        perform push_note(l.owner_id, 'BILLING', subj || ': licence expired',
          format('It stays live until %s. Renew with licence code %s; we''ve sent the details by SMS.', billing_ist_day(l.valid_till + grace), l.code), 'bucks-id');
        perform billing_queue_sms(l, 'LAPSED');
        n := n + 1;
      end if;

    elsif not l.held then
      perform billing_pause(l);
      update billing_licences set stage = r + 2, updated_at = now() where id = l.id;
      perform push_note(l.owner_id, 'BILLING', subj || ' is paused',
        format('Its licence expired, so it''s hidden from search. Your profile and recommendations are kept. Renew with code %s and it comes back at once.', l.code), 'bucks-id');
      select * into l from billing_licences where id = l.id;
      perform billing_queue_sms(l, 'PAUSED');
      n := n + 1;

    elsif st >= r + 2 and st - (r + 2) < coalesce(array_length(win, 1), 0)
          and l.held_at <= now() - make_interval(days => win[st - (r + 2) + 1]) then
      update billing_licences set stage = st + 1, updated_at = now() where id = l.id;
      perform billing_queue_sms(l, 'WINBACK');
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------- Razorpay webhooks (already signature-checked by the Edge Function) ----------
-- Uses payment.captured from the Payment Pages. Every other event is stored and ignored. The plan and length come from the amount;
-- the licence from the code typed on the page (any note that looks like one), else from the payer's phone when that owner has
-- exactly one licence of the plan. Anything that does not fit is kept as UNMATCHED for staff (billing_staff_assign or a refund).
create or replace function public.billing_apply_event(p_event_id text, p_event jsonb) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare ev text := p_event->>'event'; pay jsonb := p_event #> '{payload,payment,entity}';
        pid text; amt int; contact text; given text := ''; typed text; v text; plan billing_plans; l billing_licences; before timestamptz;
        was_held boolean; res text; owner uuid; n int;
begin
  if coalesce(p_event_id, '') = '' then raise exception 'event id required'; end if;
  insert into billing_events (id, event, payment_id, payload) values (p_event_id, coalesce(ev, ''), pay->>'id', p_event) on conflict (id) do nothing;
  if not found then return 'duplicate'; end if;
  if ev is distinct from 'payment.captured' or pay is null then
    update billing_events set result = 'ignored' where id = p_event_id; return 'ignored';
  end if;

  pid := pay->>'id';
  if exists (select 1 from billing_payments where payment_id = pid) then
    update billing_events set result = 'payment already applied' where id = p_event_id; return 'payment already applied';
  end if;
  amt := coalesce((pay->>'amount')::int, 0);
  contact := right(regexp_replace(coalesce(pay->>'contact', ''), '\D', '', 'g'), 10);

  if jsonb_typeof(pay->'notes') = 'object' then
    for v in select value from jsonb_each_text(pay->'notes') loop
      given := left(trim(given || ' ' || v), 200);
      if typed is null and billing_norm_code(v) ~ '^(SK|TX|BZ)[2-9A-HJKMNP-Z]{6}$' then typed := billing_norm_code(v); end if;
    end loop;
  end if;

  select * into plan from billing_plans where price_paise = amt and active;
  if plan.code is not null then
    if typed is not null then select * into l from billing_licences b where b.code = typed; end if;
    if l.id is null and contact <> '' then
      select count(*), min(b.id::text)::uuid into n, l.id from billing_licences b join profile_private pp on pp.profile_id = b.owner_id
       where right(regexp_replace(pp.phone, '\D', '', 'g'), 10) = contact and b.plan_code = plan.code;
      if n <> 1 then l.id := null; end if;
      if l.id is not null then select * into l from billing_licences where id = l.id; end if;
    end if;
  end if;

  if plan.code is null or l.id is null or l.plan_code <> plan.code then
    select pp.profile_id into owner from profile_private pp where contact <> '' and right(regexp_replace(pp.phone, '\D', '', 'g'), 10) = contact limit 1;
    insert into billing_payments (payment_id, licence_id, owner_id, plan_code, months, amount_paise, gst_paise, contact, code_given, status, note)
    values (pid, l.id, coalesce(l.owner_id, owner), plan.code, plan.months, amt, amt - round(amt / 1.18)::int, contact, given, 'UNMATCHED',
            case when plan.code is null then 'amount matches no plan'
                 when l.id is null then 'no licence for this code or phone'
                 else format('paid for %s, licence is %s', plan.code, l.plan_code) end);
    res := 'unmatched';
  else
    before := l.valid_till; was_held := l.held;
    l := billing_extend(l.id, plan.months, 0, true);
    insert into billing_payments (payment_id, licence_id, owner_id, plan_code, months, amount_paise, gst_paise, contact, code_given, status,
                                  valid_till_before, valid_till_after, bonus_days)
    values (pid, l.id, l.owner_id, plan.code, plan.months, amt, amt - round(amt / 1.18)::int, contact, given, 'APPLIED',
            before, l.valid_till,
            greatest(0, round(extract(epoch from l.valid_till - ((case when was_held then now() else before end) + make_interval(months => plan.months))) / 86400))::int);
    perform push_note(l.owner_id, 'BILLING', 'Licence renewed',
      format('%s is licensed till %s. Thank you.', billing_subject(l), billing_ist_day(l.valid_till)), 'bucks-id');
    perform billing_queue_sms(l, 'PAID');
    res := 'applied';
  end if;
  update billing_events set licence_id = l.id, result = res where id = p_event_id;
  return res;
end $$;

-- ---------- what the provider's app may read (status only: no prices, no links) ----------
drop function if exists public.my_licences();
create or replace function public.my_licences()
returns table (licence_id uuid, code text, listing_id uuid, vehicle_id uuid, subject text, plan_code text, plan_label text, state text,
               founding boolean, free_kind text, valid_from timestamptz, valid_till timestamptz, grace_until timestamptz,
               founding_bonus_until timestamptz, paid boolean, enquiries_month int)
language sql stable security definer set search_path = public, extensions as $$
  select l.id, l.code, l.listing_id, l.vehicle_id, billing_subject(l), l.plan_code,
         case l.plan_code when 'SKILL' then 'Skills' when 'TAXI' then 'Taxi' else 'Business' end,
         case when l.held then 'EXPIRED'
              when now() >= l.valid_till then 'GRACE'
              when not l.paid and l.free_kind is not null then l.free_kind
              else 'ACTIVE' end,
         l.founding, l.free_kind, l.valid_from, l.valid_till, l.valid_till + make_interval(days => billing_cfg('grace_days')::int),
         l.founding_bonus_until, l.paid, billing_enquiries(l, now() - interval '30 days', now())
  from billing_licences l
  where l.owner_id = public.me() and (l.listing_id is not null or l.vehicle_id is not null)
  order by l.created_at
$$;

-- ---------- licence-notify: the SMS queue ----------
create or replace function public.billing_outbox_take(lim int default 50)
returns table (id uuid, phone text, template text, vars jsonb)
language sql security definer set search_path = public, extensions as $$
  update billing_messages m set attempts = attempts + 1
   where m.id in (select x.id from billing_messages x where x.sent_at is null and x.attempts < 3 and x.created_at > now() - interval '2 days'
                  order by x.created_at limit greatest(1, least(coalesce(lim, 50), 200)) for update skip locked)
  returning m.id, m.phone, m.template, m.vars
$$;

create or replace function public.billing_outbox_done(p_id uuid, p_ok boolean, p_error text) returns void
language sql security definer set search_path = public, extensions as $$
  update billing_messages set sent_at = case when p_ok then now() end, error = case when p_ok then null else left(p_error, 500) end where id = p_id
$$;

create or replace function public.billing_notify_url() returns text language sql stable set search_path = public, extensions as $$
  select replace(public.notify_url(), '/functions/v1/notify', '/functions/v1/licence-notify')
$$;
create or replace function public.billing_flush_sms() returns void language plpgsql security definer set search_path = public, extensions as $$
declare secret text;
begin
  if to_regproc('net.http_post') is null or not billing_on() then return; end if;
  if not exists (select 1 from billing_messages where sent_at is null and attempts < 3 and created_at > now() - interval '2 days') then return; end if;
  select value into secret from push_config where key = 'webhook_secret';
  if coalesce(secret, '') = '' then return; end if;
  perform net.http_post(url := billing_notify_url(), body := '{"run":"queue"}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-bucks-secret', secret), timeout_milliseconds := 10000);
end $$;

-- ---------- staff ----------
create or replace function public.billing_staff_view(q text default '', lim int default 50)
returns table (licence_id uuid, code text, owner_id uuid, owner_name text, subject text, plan_code text, founding boolean, held boolean,
               valid_till timestamptz, paid_paise bigint, last_paid_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select l.id, l.code, l.owner_id, o.name, billing_subject(l), l.plan_code, l.founding, l.held, l.valid_till,
         (select coalesce(sum(amount_paise), 0) from billing_payments b where b.licence_id = l.id and b.status = 'APPLIED'),
         (select max(paid_at) from billing_payments b where b.licence_id = l.id and b.status = 'APPLIED')
  from billing_licences l join profiles o on o.id = l.owner_id
  where public.is_staff()
    and (coalesce(q, '') = '' or o.name ilike '%' || q || '%' or o.short_code = upper(q) or l.code = billing_norm_code(q)
         or exists (select 1 from listings x where x.id = l.listing_id and x.title ilike '%' || q || '%')
         or exists (select 1 from vehicles v where v.id = l.vehicle_id and v.plate ilike '%' || q || '%'))
  order by l.updated_at desc limit greatest(1, least(coalesce(lim, 50), 200))
$$;

-- Free days (a referral month, a goodwill week). A paused subject comes back at once.
create or replace function public.billing_staff_extend(p_licence uuid, p_days int, p_reason text) returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare l billing_licences;
begin
  if not is_staff() then raise exception 'staff only'; end if;
  if p_days is null or p_days < 1 or p_days > 366 then raise exception 'between 1 and 366 days'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'say why'; end if;
  l := billing_extend(p_licence, 0, p_days, false);
  insert into billing_events (id, event, licence_id, payload, result)
  values ('staff:' || gen_random_uuid(), 'staff.extend', l.id, jsonb_build_object('by', public.me(), 'days', p_days, 'reason', left(p_reason, 300)), 'extended');
  return l.valid_till;
end $$;

-- Applies an UNMATCHED payment to a licence (the payer mistyped the code). The plan must match what was paid for.
create or replace function public.billing_staff_assign(p_payment text, p_licence uuid) returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare p billing_payments; l billing_licences; before timestamptz;
begin
  if not is_staff() then raise exception 'staff only'; end if;
  select * into p from billing_payments where payment_id = p_payment for update;
  if not found or p.status <> 'UNMATCHED' then raise exception 'not an unmatched payment'; end if;
  if p.months is null then raise exception 'the amount matches no plan; refund it in the Razorpay Dashboard'; end if;
  select * into l from billing_licences where id = p_licence;
  if not found then raise exception 'licence not found'; end if;
  if l.plan_code <> p.plan_code then raise exception 'this payment was for the % plan, the licence is %', p.plan_code, l.plan_code; end if;
  before := l.valid_till;
  l := billing_extend(l.id, p.months, 0, true);
  update billing_payments set licence_id = l.id, owner_id = l.owner_id, status = 'APPLIED', valid_till_before = before, valid_till_after = l.valid_till,
         note = 'assigned by staff ' || public.me()::text where payment_id = p_payment;
  perform push_note(l.owner_id, 'BILLING', 'Licence renewed', format('%s is licensed till %s. Thank you.', billing_subject(l), billing_ist_day(l.valid_till)), 'bucks-id');
  perform billing_queue_sms(l, 'PAID');
  return l.valid_till;
end $$;

-- Marks a payment refunded in the Razorpay Dashboard (records only; nothing is sent to Razorpay).
create or replace function public.billing_staff_refunded(p_payment text, p_reason text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_staff() then raise exception 'staff only'; end if;
  update billing_payments set status = 'REFUNDED', note = left(coalesce(p_reason, ''), 300) where payment_id = p_payment and status = 'UNMATCHED';
  if not found then raise exception 'not an unmatched payment'; end if;
end $$;

-- Sends the renewal details again by SMS on the next run.
create or replace function public.billing_staff_resend(p_licence uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare l billing_licences;
begin
  if not is_staff() then raise exception 'staff only'; end if;
  select * into l from billing_licences where id = p_licence;
  if not found then raise exception 'licence not found'; end if;
  perform billing_queue_sms(l, case when l.held then 'PAUSED' when now() >= l.valid_till then 'LAPSED' else 'RENEW_SOON' end);
end $$;

-- ---------- schedules ----------
do $$ begin
  if to_regnamespace('cron') is not null then
    -- Drop the jobs of the earlier Autopay draft if it was ever applied.
    perform cron.unschedule(jobname) from cron.job where jobname in ('bucks-billing-links');
    perform cron.schedule('bucks-billing-daily', '30 4 * * *', 'select public.billing_daily()');            -- 10:00 IST
    perform cron.schedule('bucks-billing-sms', '*/15 3-14 * * *', 'select public.billing_flush_sms()');     -- 08:30-20:15 IST
  end if;
end $$;

-- ---------- grants ----------
revoke execute on function public.billing_cfg(text), public.billing_on(), public.billing_listing_guard(), public.billing_vehicle_guard(),
  public.billing_presence_guard(), public.billing_claim_key(text, uuid, text), public.billing_start(uuid, uuid), public.billing_on_listing_live(),
  public.billing_on_vehicle_active(), public.billing_backfill(), public.billing_pause(billing_licences), public.billing_unpause(billing_licences),
  public.billing_mark_wants_live(uuid), public.billing_new_code(text), public.billing_phone(uuid), public.billing_subject(billing_licences),
  public.billing_queue_sms(billing_licences, text), public.billing_extend(uuid, int, int, boolean), public.billing_daily(),
  public.billing_apply_event(text, jsonb), public.billing_outbox_take(int), public.billing_outbox_done(uuid, boolean, text),
  public.billing_notify_url(), public.billing_flush_sms(), public.note_listing_status(),
  public.billing_enquiries(billing_licences, timestamptz, timestamptz), public.billing_guarantee(billing_licences)
  from public, anon, authenticated;
grant execute on function public.billing_apply_event(text, jsonb), public.billing_outbox_take(int), public.billing_outbox_done(uuid, boolean, text)
  to service_role;
revoke execute on function public.my_licences(), public.billing_staff_view(text, int), public.billing_staff_extend(uuid, int, text),
  public.billing_staff_assign(text, uuid), public.billing_staff_refunded(text, text), public.billing_staff_resend(uuid) from public, anon;
grant execute on function public.my_licences(), public.billing_staff_view(text, int), public.billing_staff_extend(uuid, int, text),
  public.billing_staff_assign(text, uuid), public.billing_staff_refunded(text, text), public.billing_staff_resend(uuid) to authenticated;
