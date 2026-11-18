\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Licence scenarios: Skills, Taxi and Business licences with codes, Founding Members and trials, one free period per person and
-- plate, reminders and the SMS queue, Payment Page payments (by code, by phone, wrong plan, unknown amount, replayed), founding
-- double time, the no-enquiry free month, lapse, grace, pause and restore, vehicles on hold, what owners and staff can and cannot do.
-- Every check prints "ok, ..." or "FAIL ...". Run inside a transaction you roll back.
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
-- ensure_profile takes the phone from the sign-in token only (risk_hardening.sql), as the app's real tokens carry it.
create or replace function pg_temp.as_phone(u text, ph text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'phone_number', ph)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.lid(t text) returns uuid language sql as $$ select id from public.listings where title = t $$;
create or replace function pg_temp.lic(t text) returns public.billing_licences language sql as $$
  select b.* from public.billing_licences b left join public.listings l on l.id = b.listing_id left join public.vehicles v on v.id = b.vehicle_id
  where l.title = t or v.plate = t $$;
-- A Payment Page payment as Razorpay's payment.captured webhook carries it.
create or replace function pg_temp.paid(ev text, pay text, rupees int, contact text, typed text) returns text language sql as $$
  select public.billing_apply_event(ev, jsonb_build_object('event', 'payment.captured', 'payload', jsonb_build_object('payment', jsonb_build_object('entity',
    jsonb_build_object('id', pay, 'amount', rupees * 100, 'contact', contact, 'status', 'captured',
                       'notes', case when typed is null then '{}'::jsonb else jsonb_build_object('licence_code', typed) end)))))
$$;
-- Moves a licence's dates back by n days, as if time had passed.
create or replace function pg_temp.age(t text, n int) returns void language sql as $$
  update public.billing_licences set valid_till = valid_till - make_interval(days => n), valid_from = valid_from - make_interval(days => n),
         founding_bonus_until = founding_bonus_until - make_interval(days => n), held_at = held_at - make_interval(days => n)
   where id = (pg_temp.lic(t)).id $$;

set role authenticated;
select pg_temp.as_phone('plumber', '9000000501'); select (public.ensure_profile('Ravi (plumber)', '9000000501')).id is not null;
select pg_temp.as_phone('shop', '9000000502');    select (public.ensure_profile('Meena (shop)', '9000000502')).id is not null;
select pg_temp.as_phone('driver', '9000000503');  select (public.ensure_profile('Imran (auto)', '9000000503')).id is not null;
select pg_temp.as_phone('late', '9000000504');    select (public.ensure_profile('Asha (joins late)', '9000000504')).id is not null;
select pg_temp.as_phone('staff1', '9000000505');  select (public.ensure_profile('Bucks staff', '9000000505')).id is not null;
reset role;
insert into staff (profile_id) values (pg_temp.pid('staff1'));
update billing_plans set page_url = 'https://rzp.io/rzp/test-' || lower(code) where months = 1;
insert into listings (kind, owner_id, title, category, area, location) values
  ('SKILL',    pg_temp.pid('plumber'), 'Ravi Plumbing',   'Plumber', 'Jayanagar', geo(12.9250, 77.5938)),
  ('BUSINESS', pg_temp.pid('shop'),    'Meena Stores',    'Grocery', 'Jayanagar', geo(12.9252, 77.5940)),
  ('SKILL',    pg_temp.pid('plumber'), 'Ravi Plumbing 2', 'Plumber', 'Jayanagar', geo(12.9250, 77.5938));

\echo '== 1. Billing off (the default): going live creates nothing'
update listings set status = 'LIVE' where title = 'Ravi Plumbing';
select pg_temp.check((select count(*) from billing_licences) = 0, 'no licence while billing is off');
update listings set status = 'PENDING' where title = 'Ravi Plumbing';

\echo '== 2. Plans: four lengths per plan, every price different'
select pg_temp.check((select count(*) from billing_plans where active) = 9, '9 plans (3 kinds x 1, 6, 12 months)');
select pg_temp.check((select count(distinct price_paise) from billing_plans where active) = 9, 'no two plans share a price');

\echo '== 3. Billing on, inside the founding window: Founding Member licences with codes'
update billing_config set value = 'on' where key = 'enabled';
update billing_config set value = to_char(current_date + 30, 'YYYY-MM-DD') where key = 'founding_until';
update listings set status = 'LIVE' where title in ('Ravi Plumbing', 'Meena Stores');
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).founding and (pg_temp.lic('Ravi Plumbing')).plan_code = 'SKILL', 'skill listing -> founding SKILL licence');
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).code ~ '^SK[2-9A-HJKMNP-Z]{6}$', 'skill code looks like SK + 6');
select pg_temp.check((pg_temp.lic('Meena Stores')).code like 'BZ%', 'business code starts BZ');
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).valid_till between now() + interval '89 days' and now() + interval '93 days', 'three free months');
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).founding_bonus_until between now() + interval '360 days' and now() + interval '370 days', 'double-time window runs 9 more months');
select pg_temp.check(exists (select 1 from billing_messages where licence_id = (pg_temp.lic('Ravi Plumbing')).id and template = 'START' and phone = '919000000501'
                             and vars->>'code' = (pg_temp.lic('Ravi Plumbing')).code and vars->>'link' = 'https://rzp.io/rzp/test-skill'), 'start SMS queued with code and page link');
update listings set status = 'SUSPENDED' where title = 'Ravi Plumbing'; update listings set status = 'LIVE' where title = 'Ravi Plumbing';
select pg_temp.check((select count(*) from billing_licences where listing_id = pg_temp.lid('Ravi Plumbing')) = 1, 'going live again does not add a second licence');

\echo '== 4. One free period per person and plan: a second skill page needs a licence now (grace week)'
update listings set status = 'LIVE' where title = 'Ravi Plumbing 2';
select pg_temp.check(not (pg_temp.lic('Ravi Plumbing 2')).founding and (pg_temp.lic('Ravi Plumbing 2')).valid_till <= now(), 'second skill page -> no free period');
select pg_temp.check(exists (select 1 from billing_messages where licence_id = (pg_temp.lic('Ravi Plumbing 2')).id and template = 'LAPSED'), 'lapse SMS queued at once');

\echo '== 5. After the founding window: the standard 30-day trial'
update billing_config set value = to_char(current_date - 1, 'YYYY-MM-DD') where key = 'founding_until';
insert into listings (kind, owner_id, title, category, area, location, status) values ('SKILL', pg_temp.pid('late'), 'Asha Tuition', 'Tutor', 'Jayanagar', geo(12.9251, 77.5939), 'LIVE');
select pg_temp.check((pg_temp.lic('Asha Tuition')).free_kind = 'TRIAL' and (pg_temp.lic('Asha Tuition')).valid_till between now() + interval '29 days' and now() + interval '31 days', '30-day trial');

\echo '== 6. Owners read their licences, never write them'
set role authenticated; select pg_temp.as_user('plumber');
select pg_temp.check((select count(*) from my_licences()) = 2, 'plumber sees two licences');
select pg_temp.check((select state from my_licences() where subject = 'Ravi Plumbing') = 'FOUNDING', 'state FOUNDING');
select pg_temp.check((select state from my_licences() where subject = 'Ravi Plumbing 2') = 'GRACE', 'second page in GRACE');
select pg_temp.expect_fail('select * from billing_licences', 'permission denied');
select pg_temp.expect_fail('select * from billing_plans', 'permission denied');
select pg_temp.expect_fail($$update listings set billing_hold = true where title = 'Ravi Plumbing'$$, 'managed by Bucks');
select pg_temp.expect_fail($$select billing_apply_event('x', '{}'::jsonb)$$, 'permission denied');
select pg_temp.expect_fail($$select billing_staff_extend((select licence_id from my_licences() limit 1), 30, 'me')$$, 'staff only');
reset role;

\echo '== 7. Reminders 7, 3 and 1 day before VALID TILL, each once; a short time left skips the earlier ones'
select pg_temp.age('Asha Tuition', 24);   -- 6 days left
select billing_daily() >= 1;
select pg_temp.check((pg_temp.lic('Asha Tuition')).stage = 1, 'first reminder at 6 days left');
select billing_daily();
select pg_temp.check((select count(*) from billing_messages where licence_id = (pg_temp.lic('Asha Tuition')).id and template = 'RENEW_SOON') = 1, 'not sent twice');
select pg_temp.age('Asha Tuition', 5);    -- 1 day left: the 3-day reminder was missed, only the 1-day one goes
select billing_daily();
select pg_temp.check((pg_temp.lic('Asha Tuition')).stage = 3, 'jumped to the last reminder');
select pg_temp.check((select count(*) from billing_messages where licence_id = (pg_temp.lic('Asha Tuition')).id and template = 'RENEW_SOON') = 2, 'one more SMS, not two');

\echo '== 8. Lapse: a grace week, then paused (out of search, profile kept)'
select pg_temp.age('Asha Tuition', 2);    -- expired yesterday
select billing_daily();
select pg_temp.check((select status from listings where title = 'Asha Tuition') = 'LIVE', 'still live in grace');
select pg_temp.check(exists (select 1 from billing_messages where licence_id = (pg_temp.lic('Asha Tuition')).id and template = 'LAPSED'), 'lapse SMS');
select pg_temp.age('Asha Tuition', 7);
select billing_daily();
select pg_temp.check((select status = 'SUSPENDED' and billing_hold from listings where title = 'Asha Tuition'), 'paused after the grace week');
select pg_temp.check((pg_temp.lic('Asha Tuition')).held and (pg_temp.lic('Asha Tuition')).held_from_live, 'held, remembers it was live');
select pg_temp.check(exists (select 1 from notifications where profile_id = pg_temp.pid('late') and kind = 'BILLING' and title ilike '%paused%'), 'owner told');
update listings set status = 'LIVE' where title = 'Asha Tuition';
select pg_temp.check((select status from listings where title = 'Asha Tuition') = 'SUSPENDED', 'a held listing cannot be set LIVE');
select pg_temp.age('Asha Tuition', 7);
select billing_daily();
select pg_temp.check(exists (select 1 from billing_messages where licence_id = (pg_temp.lic('Asha Tuition')).id and template = 'WINBACK'), 'win-back SMS 7 days after pausing');

\echo '== 9. Paying by code brings it back at once, counted from today'
select pg_temp.check(pg_temp.paid('ev1', 'pay_1', 499, '9999999999', ' ' || lower((pg_temp.lic('Asha Tuition')).code) || ' ') = 'applied', 'code typed in lower case with spaces still matches');
select pg_temp.check((select status from listings where title = 'Asha Tuition') = 'LIVE' and not (pg_temp.lic('Asha Tuition')).held, 'back LIVE');
select pg_temp.check((pg_temp.lic('Asha Tuition')).valid_till between now() + interval '180 days' and now() + interval '185 days', '6 months from today');
select pg_temp.check((select months = 6 and amount_paise = 49900 and gst_paise = 7612 and status = 'APPLIED' from billing_payments where payment_id = 'pay_1'), 'ledger: 6 months, GST part');
select pg_temp.check(pg_temp.paid('ev1', 'pay_1', 499, '', null) = 'duplicate', 'replayed event ignored');
select pg_temp.check(pg_temp.paid('ev1b', 'pay_1', 499, '', null) = 'payment already applied', 'same payment in another event ignored');

\echo '== 10. Paying early adds to VALID TILL; founding renewals in the window count double'
select pg_temp.age('Ravi Plumbing', 85);  -- 5 days of free months left
select pg_temp.paid('ev2', 'pay_2', 99, '', (pg_temp.lic('Ravi Plumbing')).code);
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).valid_till between now() + interval '63 days' and now() + interval '67 days', '1 month paid -> 2 months added after the free days');
select pg_temp.check((select bonus_days between 28 and 31 from billing_payments where payment_id = 'pay_2'), 'bonus days recorded');
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).stage = 0, 'reminders start over');

\echo '== 11. Paying by phone when no code was typed: only with exactly one licence of that plan'
select pg_temp.check(pg_temp.paid('ev3', 'pay_3', 299, '+91 90000 00502', null) = 'applied', 'Meena: one business licence -> matched by phone');
select pg_temp.check(pg_temp.paid('ev4', 'pay_4', 99, '9000000501', null) = 'unmatched', 'Ravi: two skill licences -> left for staff');

\echo '== 12. Wrong plan or unknown amount: kept for staff'
select pg_temp.check(pg_temp.paid('ev5', 'pay_5', 199, '', (pg_temp.lic('Ravi Plumbing 2')).code) = 'unmatched', 'Taxi price with a Skills code');
select pg_temp.check(pg_temp.paid('ev6', 'pay_6', 250, '', (pg_temp.lic('Ravi Plumbing 2')).code) = 'unmatched', 'amount that is no plan');
select pg_temp.check((select note from billing_payments where payment_id = 'pay_6') = 'amount matches no plan', 'reason recorded');
select pg_temp.check(public.billing_apply_event('ev7', '{"event":"order.paid","payload":{}}'::jsonb) = 'ignored', 'other events stored and ignored');

\echo '== 13. Staff: assign an unmatched payment, extend, refund, resend'
set role authenticated; select pg_temp.as_user('staff1');
select pg_temp.check(billing_staff_assign('pay_4', (select licence_id from billing_staff_view('Ravi Plumbing 2') limit 1)) > now() + interval '20 days', 'staff applies the payment to the right page');
select pg_temp.expect_fail($$select billing_staff_assign('pay_5', (select licence_id from billing_staff_view('Ravi Plumbing 2') limit 1))$$, 'plan');
select billing_staff_refunded('pay_6', 'not a plan amount');
select pg_temp.check(billing_staff_extend((select licence_id from billing_staff_view('Meena Stores') limit 1), 30, 'referral') > now() + interval '55 days', 'free month added');
select billing_staff_resend((select licence_id from billing_staff_view('Meena Stores') limit 1));
reset role;
select pg_temp.check((select status from billing_payments where payment_id = 'pay_6') = 'REFUNDED', 'refund recorded');

\echo '== 14a. No-enquiry guarantee: a paid month with no enquiries is followed by a free month'
update billing_licences set valid_till = now() - interval '1 hour', stage = 0 where id = (pg_temp.lic('Meena Stores')).id;
select billing_daily();
select pg_temp.check((pg_temp.lic('Meena Stores')).valid_till between now() + interval '29 days' and now() + interval '30 days', 'Meena: no enquiries -> 30 free days');
select pg_temp.check(exists (select 1 from billing_events where licence_id = (pg_temp.lic('Meena Stores')).id and event = 'guarantee.free_month'), 'recorded');
select pg_temp.check(not exists (select 1 from billing_messages where licence_id = (pg_temp.lic('Meena Stores')).id and template = 'LAPSED'), 'no lapse SMS');
insert into conversations (kind, listing_id, created_by, created_at) values ('LISTING', pg_temp.lid('Ravi Plumbing'), pg_temp.pid('shop'), now() - interval '2 days');
update billing_licences set valid_till = now() - interval '1 hour', stage = 0 where id = (pg_temp.lic('Ravi Plumbing')).id;
select billing_daily();
select pg_temp.check((pg_temp.lic('Ravi Plumbing')).valid_till < now() and (pg_temp.lic('Ravi Plumbing')).stage = 4, 'Ravi: one enquiry -> normal lapse');
set role authenticated; select pg_temp.as_user('plumber');
select pg_temp.check((select enquiries_month from my_licences() where subject = 'Ravi Plumbing') = 1, 'owner sees 1 enquiry this month');
reset role;
update billing_config set value = '0' where key = 'guarantee_min_enquiries';
update billing_licences set valid_till = now() - interval '1 hour', stage = 0 where id = (pg_temp.lic('Meena Stores')).id;
select billing_daily();
select pg_temp.check((pg_temp.lic('Meena Stores')).valid_till < now(), 'guarantee can be switched off');
update billing_config set value = '1' where key = 'guarantee_min_enquiries';

\echo '== 14. Vehicles: Taxi licence by plate; a paused vehicle cannot go online'
insert into vehicles (owner_id, kind, plate, status) values (pg_temp.pid('driver'), 'AUTO', 'KA01AB1234', 'ACTIVE');
select pg_temp.check((pg_temp.lic('KA01AB1234')).code like 'TX%', 'vehicle -> TX licence');
update billing_licences set valid_till = now() - interval '8 days' where id = (pg_temp.lic('KA01AB1234')).id;
select billing_daily();
select pg_temp.check((select billing_hold from vehicles where plate = 'KA01AB1234'), 'vehicle on hold after the grace week');
select pg_temp.paid('ev8', 'pay_8', 1990, '', (pg_temp.lic('KA01AB1234')).code);
select pg_temp.check(not (select billing_hold from vehicles where plate = 'KA01AB1234')
                     and (pg_temp.lic('KA01AB1234')).valid_till > now() + interval '364 days', 'yearly payment releases it for 12 months');

\echo '== 15. The SMS queue'
select pg_temp.check((select count(*) from billing_outbox_take(500)) > 0, 'outbox hands out waiting messages');
select pg_temp.check((select count(*) from billing_messages where sent_at is null and attempts = 0) = 0, 'each counted as an attempt');
update billing_messages set created_at = now() - interval '3 days';
select pg_temp.check((select count(*) from billing_outbox_take(500)) = 0, 'messages older than two days are never sent');
