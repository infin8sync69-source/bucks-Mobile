\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- Swarm Phase 1 scenarios (swarm_core.sql + swarm_phase1.sql): switches default off, the demand field (k-threshold, adults only, lazy
-- decay), ride and order recovery (offers recorded, choices only from the person's tap, follow-ups attributed, nothing booked by an
-- agent), "Notify me", the worker's step function, intent_feedback (opt-in, adults, redaction, RLS), the metrics rollup.
-- The CI database has no pgmq, pg_cron or pg_net: enqueueing is a no-op there, which is itself checked (writes never fail).
update public.settings set value = 0 where key in ('min_trip_seconds', 'arrive_radius_m', 'complete_radius_m', 'presence_max_speed_mps');
create or replace function pg_temp.expect_fail(sql text, want text) returns text language plpgsql as $$
begin execute sql; return 'FAIL (no error): ' || want; exception when others then return case when sqlerrm ilike '%' || want || '%' then 'ok, blocked: ' || sqlerrm else 'FAIL wrong error: ' || sqlerrm end; end $$;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function pg_temp.pid(u text) returns uuid language sql as $$ select id from public.profiles where auth_uid = u $$;
create or replace function pg_temp.check(ok boolean, what text) returns text language sql as $$ select case when ok then 'ok, ' || what else 'FAIL ' || what end $$;
create or replace function pg_temp.ride(u text) returns uuid language plpgsql as $$
begin perform pg_temp.as_user(u); return (public.request_ride('AUTO', 12.9250, 77.5938, 'Jayanagar 4th block', 12.9757, 77.6063, 'MG Road', 7.2, 106)).id; end $$;

\echo '== 0. Every new switch is off'
select pg_temp.check((select count(*) from settings where key in ('demand_field_enabled', 'recovery_enabled', 'intent_feedback_enabled', 'swarm_enabled') and value = 0) = 4, 'four swarm switches are 0');
select pg_temp.check(dispatch_mode_for(null) = 'BROADCAST', 'dispatch_mode_for is BROADCAST');

set role authenticated;
select pg_temp.as_user('asha');   select (public.ensure_profile('Asha (adult rider)', '9000000301')).id is not null;
select pg_temp.as_user('teen');   select (public.ensure_profile('Tanu (teen)', '9000000302')).id is not null;
select pg_temp.as_user('suresh'); select (public.ensure_profile('Suresh (auto driver)', '9000000303')).id is not null;
select pg_temp.as_user('owner');  select (public.ensure_profile('Lakshmi (shop)', '9000000304')).id is not null;
select pg_temp.as_user('owner2'); select (public.ensure_profile('Ganesh (other shop)', '9000000305')).id is not null;
select pg_temp.as_user('nobody'); select (public.ensure_profile('Someone else', '9000000306')).id is not null;
reset role;
insert into profile_safety (profile_id, birth_date, age_band) values
  (pg_temp.pid('asha'), '1990-01-01', 'ADULT'), (pg_temp.pid('teen'), '2011-01-01', 'TEEN'), (pg_temp.pid('suresh'), '1985-01-01', 'ADULT'),
  (pg_temp.pid('owner'), '1980-01-01', 'ADULT'), (pg_temp.pid('nobody'), '1992-01-01', 'ADULT')
  on conflict (profile_id) do update set age_band = excluded.age_band;
insert into guardian_consents (profile_id, guardian_name, guardian_phone, relation) values (pg_temp.pid('teen'), 'Parent', '9000000399', 'PARENT')
  on conflict (profile_id) do nothing;
set role authenticated;

select pg_temp.as_user('suresh');
insert into vehicles (owner_id, kind, model, plate) values (me(), 'AUTO', 'Bajaj RE', 'KA01SW0001');
reset role; update vehicles set status = 'ACTIVE' where plate = 'KA01SW0001'; set role authenticated;
insert into driver_presence (profile_id, vehicle_id, kind, online, location) select me(), id, 'AUTO', false, geo(12.9260, 77.5940) from vehicles where plate = 'KA01SW0001';

\echo '== 1. Field off: a request leaves no mark'
select set_config('t.r0', pg_temp.ride('asha')::text, false) is not null;
reset role;
select pg_temp.check((select count(*) from area_signals) = 0, 'no area_signals while demand_field_enabled = 0');
update settings set value = 1 where key = 'demand_field_enabled';
set role authenticated;
select pg_temp.as_user('asha'); select cancel_task(current_setting('t.r0')::uuid, null, null) is not null;

\echo '== 2. Field on: adults count, a teen does not; no coordinates or ids stored'
select set_config('t.r1', pg_temp.ride('asha')::text, false) is not null;
select set_config('t.rt', pg_temp.ride('teen')::text, false) is not null;
reset role;
select pg_temp.check((select sum(n) from area_signal_hours where signal = 'REQUEST') = 1, 'one REQUEST counted (the teen''s request left out)');
select pg_temp.check((select cell from area_signals limit 1) = area_cell(geo(12.9250, 77.5938)), 'stored as an area cell: ' || (select cell from area_signals limit 1));
select pg_temp.check(not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name in ('area_signals', 'area_signal_hours')
  and (udt_name in ('geography', 'geometry', 'uuid'))), 'area_signals has no location or uuid columns');
set role authenticated;
select pg_temp.as_user('asha');
select pg_temp.check((select count(*) from area_signals) = 0, 'a member cannot read area_signals');

\echo '== 3. k-threshold: the driver card says nothing under 3 events, then shows them'
select pg_temp.as_user('suresh');
select pg_temp.check((select count(*) from recent_requests_near(12.9260, 77.5940)) = 0, 'driver sees nothing at 1 event');
select pg_temp.as_user('nobody');
select pg_temp.check((select count(*) from recent_requests_near(12.9260, 77.5940)) = 0, 'a non-driver gets nothing');
reset role;
select pg_temp.check((select count(*) from area_heat(area_cell(geo(12.9250, 77.5938)), 'RIDE')) = 0, 'area_heat empty under k');

\echo '== 4. NO_DRIVER: UNFILLED mark and a recovery offer (always recorded); nothing is booked by the system'
set role authenticated;
select pg_temp.as_user('asha');
select (advance_task(current_setting('t.r1')::uuid, 'NO_DRIVER')).status;
reset role;
select pg_temp.check((select sum(n) from area_signal_hours where signal = 'UNFILLED') = 1, 'UNFILLED counted');
select pg_temp.check((select count(*) from recovery_offers where subject_kind = 'TASK' and subject_id = current_setting('t.r1')::uuid and reason = 'NO_DRIVER' and choice is null) = 1,
  'recovery offer recorded with no choice');
select pg_temp.check((select count(*) from tasks where requester_id = pg_temp.pid('asha')) = 2, 'no task created by recovery (still 2 for Asha)');
select set_config('t.r2', pg_temp.ride('asha')::text, false) is not null;  -- a third event in the cell (this one is a manual rebook)
reset role;
select pg_temp.check((select followup_id from recovery_offers where subject_id = current_setting('t.r1')::uuid) is null, 'a rebook without a tap is not attributed');
set role authenticated;
select pg_temp.as_user('suresh');
select pg_temp.check((select requests_7d from recent_requests_near(12.9260, 77.5940)) = 2 and (select requests_3h from recent_requests_near(12.9260, 77.5940)) is null,
  'driver card at k=3 events: requests this week 2, last-3-hours count hidden under k');
reset role;
select pg_temp.check((select count(*) from area_heat(area_cell(geo(12.9250, 77.5938)), 'RIDE')) = 2, 'area_heat shows REQUEST and UNFILLED at k');
select pg_temp.check((select heat from area_heat(area_cell(geo(12.9250, 77.5938)), 'RIDE') where signal = 'UNFILLED') between 2.99 and 3.0, 'UNFILLED weighs 3');
-- lazy decay: age the row by one tau; the read applies exp(-1)
update area_signals set updated_at = now() - make_interval(secs => setting('signal_tau_s')::int) where signal = 'UNFILLED';
select pg_temp.check((select heat from area_heat(area_cell(geo(12.9250, 77.5938)), 'RIDE') where signal = 'UNFILLED') between 1.09 and 1.12, 'decayed to 3/e on read');

\echo '== 5. The recovery card: only the person''s own tap records a choice; the follow-up booking is attributed'
set role authenticated;
select pg_temp.as_user('asha'); select cancel_task(current_setting('t.r2')::uuid, null, null) is not null;
select pg_temp.as_user('nobody');
select pg_temp.check(not recovery_choice('TASK', current_setting('t.r1')::uuid, 'TRY_AGAIN'), 'someone else''s tap changes nothing');
select pg_temp.as_user('asha');
select 'unknown choice -> ' || pg_temp.expect_fail(format($$select recovery_choice('TASK', %L, 'BOOK_FOR_ME')$$, current_setting('t.r1')), 'unknown choice');
select pg_temp.check(recovery_choice('TASK', current_setting('t.r1')::uuid, 'TRY_CAB'), 'Asha taps Try a cab');
reset role; update recovery_offers set followup_id = null where subject_id = current_setting('t.r1')::uuid; set role authenticated;
select set_config('t.r3', pg_temp.ride('asha')::text, false) is not null;
reset role;
select pg_temp.check((select followup_id from recovery_offers where subject_id = current_setting('t.r1')::uuid) = current_setting('t.r3')::uuid, 'the booking she made after tapping is the follow-up');
select pg_temp.check(not has_function_privilege('authenticated', 'public.swarm_step(text, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.swarm_read(text, integer, integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.rollup_swarm_metrics(date)', 'execute'), 'worker RPCs are service_role only');

\echo '== 6. Notify me: refused while recovery is off; on, a driver coming online nearby queues it (no pgmq here: no error)'
set role authenticated;
select pg_temp.as_user('asha'); select cancel_task(current_setting('t.r3')::uuid, null, null) is not null;
select pg_temp.check(not notify_me_when_driver_online('AUTO', 12.9250, 77.5938), 'false while recovery_enabled = 0');
reset role; update settings set value = 1 where key = 'recovery_enabled'; set role authenticated;
select pg_temp.check(notify_me_when_driver_online('AUTO', 12.9250, 77.5938), 'alert set');
select pg_temp.check((select count(*) from recovery_alerts) = 1, 'Asha sees her own alert');
select pg_temp.as_user('suresh');
update driver_presence set online = true where profile_id = me();
select pg_temp.check(true, 'driver went online without an error (enqueue is a no-op without pgmq)');
reset role;
select pg_temp.check((select sum(n) from area_signal_hours where signal = 'SUPPLY_ONLINE') = 1, 'SUPPLY_ONLINE counted');

\echo '== 7. The worker''s step: proposes and notifies, books nothing'
select pg_temp.check((swarm_step('recovery_q', jsonb_build_object('kind', 'RIDE_NO_DRIVER', 'offer', (select id from recovery_offers where subject_id = current_setting('t.r1')::uuid), 'task', current_setting('t.r1')))) ->> 'skip' = 'already acted',
  'ride recovery skipped: she already tapped and rebooked');
select set_config('t.n', (swarm_step('nudge_q', jsonb_build_object('kind', 'DRIVER_ONLINE', 'profile', pg_temp.pid('asha'), 'vehicle_kind', 'AUTO')))::text, false) is not null;
select pg_temp.check(current_setting('t.n')::jsonb -> 'notes' -> 0 ->> 'title' = 'A driver is online near you', 'driver-online note planned');
select pg_temp.check((select count(*) from recovery_alerts) = 0 and (select count(*) from notifications where profile_id = pg_temp.pid('asha') and kind = 'RECOVERY') = 1, 'alert used once, bell notification written');
select pg_temp.check((swarm_step('nudge_q', jsonb_build_object('kind', 'DRIVER_ONLINE', 'profile', pg_temp.pid('asha'), 'vehicle_kind', 'AUTO'))) ->> 'skip' = 'alert gone', 'a second delivery of the same message does nothing');
select 'unknown message -> ' || pg_temp.expect_fail($$select swarm_step('recovery_q', '{"kind":"BOOK_RIDE"}')$$, 'unknown message kind');
select pg_temp.check((select count(*) from agent_events where kind in ('PROPOSED', 'NOTIFIED', 'SKIPPED')) >= 2, 'agent_events audit rows written');

\echo '== 8. An order the shop turns down: recovery offer, similar shops for the buyer only'
set role authenticated;
select pg_temp.as_user('owner');
update profile_private set upi_uri = 'upi://pay?pa=lakshmi@okaxis&pn=Lakshmi' where profile_id = me();
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Swarm Stores', 'Grocery', 'Rice, dal', 'Jayanagar', geo(12.9250, 77.5938), '{"cod": true}');
insert into items (listing_id, name, price, unit) values ((select id from listings where title = 'Swarm Stores'), 'Toor dal', 140, '1 kg');
select pg_temp.as_user('owner2');
update profile_private set upi_uri = 'upi://pay?pa=ganesh@okaxis&pn=Ganesh' where profile_id = me();
insert into listings (kind, owner_id, title, category, description, area, location, details)
  values ('BUSINESS', me(), 'Ganesh Provisions', 'Grocery', 'Dal and more', 'Jayanagar', geo(12.9270, 77.5950), '{"cod": true}');
insert into items (listing_id, name, price, unit) values ((select id from listings where title = 'Ganesh Provisions'), 'Toor dal', 150, '1 kg');
reset role; update listings set status = 'LIVE', online = true where title in ('Swarm Stores', 'Ganesh Provisions'); set role authenticated;
select pg_temp.as_user('asha');
select set_config('t.o1', place_order((select id from listings where title = 'Swarm Stores'), jsonb_build_array(jsonb_build_object('item_id', (select id from items where name = 'Toor dal' and price = 140), 'qty', 1)), 12.9300, 77.6000, '', 'UPI', 'PICKUP')::text, false) is not null;
reset role; update orders set status = 'REJECTED', cancel_reason = 'OUT_OF_STOCK' where id = current_setting('t.o1')::uuid; set role authenticated;
select pg_temp.check((select count(*) from recovery_offers where subject_kind = 'ORDER' and subject_id = current_setting('t.o1')::uuid and reason = 'OUT_OF_STOCK') = 1, 'order recovery offer recorded');
select pg_temp.check(not exists (select 1 from order_alternatives(current_setting('t.o1')::uuid) where title = 'Swarm Stores'), 'the shop that said no is not suggested');
select 'similar shops for the buyer: ' || coalesce((select string_agg(title || ' (' || array_to_string(matched_items, ',') || ')', '; ') from order_alternatives(current_setting('t.o1')::uuid)), 'none');
select pg_temp.as_user('nobody');
select 'someone else asks -> ' || pg_temp.expect_fail(format($$select * from order_alternatives(%L)$$, current_setting('t.o1')), 'order not found');
reset role;
select pg_temp.check((swarm_step('recovery_q', jsonb_build_object('kind', 'ORDER_LOST', 'offer', (select id from recovery_offers where subject_id = current_setting('t.o1')::uuid), 'order', current_setting('t.o1')))) -> 'notes' -> 0 ->> 'route'
  = 'similar-shops/' || current_setting('t.o1'), 'order recovery note links to similar-shops/<order>');
select pg_temp.check((select count(*) from orders where buyer_id = pg_temp.pid('asha')) = 1, 'no order placed by recovery');

\echo '== 9. intent_feedback: off, then opt-in adults only, own rows only, redacted'
set role authenticated;
select pg_temp.as_user('asha');
select 'switch off -> ' || pg_temp.expect_fail($$insert into intent_feedback (locale, tier, utterance) values ('en', 1, 'auto to mg road')$$, 'not being collected');
reset role; update settings set value = 1 where key = 'intent_feedback_enabled'; set role authenticated;
select 'not opted in -> ' || pg_temp.expect_fail($$insert into intent_feedback (locale, tier, utterance) values ('en', 1, 'auto to mg road')$$, 'Help improve Bucks');
select pg_temp.as_user('teen');
select 'a teen opts in -> ' || pg_temp.expect_fail($$select set_intent_feedback_optin(true)$$, '18 and over');
select pg_temp.as_user('asha');
select pg_temp.check(set_intent_feedback_optin(true), 'Asha opts in');
insert into intent_feedback (locale, tier, utterance, predicted, final_action, corrected)
  values ('en', 1, 'send 250 to ravi@okaxis or call +91 98450 12345, my pin is 4321', '{"tool":"pay"}', '{"tool":"search"}', true);
select 'someone else''s profile_id -> ' || pg_temp.expect_fail(format($$insert into intent_feedback (profile_id, locale, tier, utterance) values (%L, 'en', 1, 'x')$$, pg_temp.pid('nobody')), 'permission denied');
reset role;
select pg_temp.check((select utterance from intent_feedback) = 'send 250 to [upi] or call [phone], my pin is [pin]', 'redacted: ' || (select utterance from intent_feedback));
select pg_temp.check((select profile_id from intent_feedback) = pg_temp.pid('asha'), 'stored under her own id');
select pg_temp.check(redact_pii('acct 1234 5678 9012 and 560034') = 'acct [number] and [pin]', 'long digit runs and 6-digit numbers stripped: ' || redact_pii('acct 1234 5678 9012 and 560034'));
set role authenticated; select pg_temp.as_user('asha');
select pg_temp.check((select count(*) from intent_feedback) = 0, 'members cannot read intent_feedback back');
select pg_temp.check(not set_intent_feedback_optin(false), 'opting out');
reset role;
select pg_temp.check((select count(*) from intent_feedback) = 0, 'opting out deleted her rows');

\echo '== 10. Metrics rollup'
select pg_temp.check(rollup_swarm_metrics((now() at time zone 'Asia/Kolkata')::date) > 0, 'rollup wrote rows');
select 'ALL/RIDE: requests ' || requests || ', unfilled ' || unfilled || ', rate ' || coalesce(unfilled_rate::text, '-') || ', recovery shown ' || recovery_shown || ', tapped ' || recovery_tapped
       || ', converted ' || recovery_converted || ', untapped rebooks ' || recovery_untapped_followups
  from swarm_metrics_daily where zone = 'ALL' and service = 'RIDE' and day = (now() at time zone 'Asia/Kolkata')::date;
select pg_temp.check((select requests from swarm_metrics_daily where zone = 'ALL' and service = 'RIDE' and day = (now() at time zone 'Asia/Kolkata')::date) = 4,
  'four adult ride requests today (the teen''s left out)');
select pg_temp.check((select recovery_converted from swarm_metrics_daily where zone = 'ALL' and service = 'RIDE' and day = (now() at time zone 'Asia/Kolkata')::date) = 1, 'one converted recovery');
select pg_temp.check(rollup_swarm_metrics((now() at time zone 'Asia/Kolkata')::date) > 0, 'rollup is re-runnable');
