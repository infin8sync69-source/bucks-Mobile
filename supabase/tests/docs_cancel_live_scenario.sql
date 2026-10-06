-- Rolled-back live scenario: showcase documents (Public / On request / Private, requests, viewer opinion) and cancellation with reasons.
-- Run in the SQL editor; it always ends in an exception whose message is the report, so nothing is kept.
do $$
declare
  own uuid := '01a0e8d3-90c6-7e7e-9689-219247281404'; cus uuid := '01a0eb93-a5a8-7cae-b7cc-e787c17dc1fa';
  own_sub text := 'sIMjoM9t3QSrZjfxwsuxNsOqgNp2'; cus_sub text := '6WI5Twle8OOHXENCYnqoEqpfKGJ3';
  lid uuid := '01a0f1cb-60f4-7025-8e10-1d020ab0ad5b';
  d1 uuid; d2 uuid; d3 uuid; rq uuid; r text; n int; j jsonb; o text := ''; t1 uuid; t2 uuid; t3 uuid; t4 uuid; o1 uuid; o2 uuid; o3 uuid; itm uuid; st text; rs text;
  addr jsonb := '{"name":"Test","phone":"9876543210","line1":"12 Test street","city":"Pune","state":"Maharashtra","pincode":"411008"}';
begin
  update listings set status = 'LIVE', compliance_hold = false, online = true where id = lid;   -- test only, rolled back
  select id into itm from items where listing_id = lid and in_stock limit 1;
  insert into storage.objects (bucket_id, name) values ('docs', own || '/iso-test.pdf'), ('docs', own || '/udyam-test.pdf'), ('docs', own || '/brochure-test.pdf');

  -- ===== owner adds documents =====
  perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  d1 := add_showcase_doc(lid, 'CERTIFICATE', 'ISO 9001 certificate', 'TUV', '', '', own || '/iso-test.pdf', 'application/pdf', 12345, 'PUBLIC', null);
  d2 := add_showcase_doc(lid, 'REGISTRATION', 'Udyam registration', 'MSME', 'UDYAM-MH-01-0000001', '', own || '/udyam-test.pdf', 'application/pdf', 2000, 'ON_REQUEST', null);
  d3 := add_showcase_doc(lid, 'OTHER', 'Internal price list', '', '', '', own || '/brochure-test.pdf', 'application/pdf', 900, 'PRIVATE', null);
  o := o || 'owner added 3 docs; ';
  begin perform add_showcase_doc(lid, 'OTHER', 'Bucks verified GST', '', '', '', own || '/x1.pdf', 'application/pdf', 10, 'PUBLIC', null); o := o || 'FAIL impersonating title allowed; ';
  exception when others then o := o || 'ok title guard (' || sqlerrm || '); '; end;
  begin perform add_showcase_doc(lid, 'TAX', 'GST certificate', '', '27ABCDE1234F1Z', 'GST', own || '/x2.pdf', 'application/pdf', 10, 'PUBLIC', null); o := o || 'FAIL bad GSTIN allowed; ';
  exception when others then o := o || 'ok GSTIN guard (' || sqlerrm || '); '; end;
  begin perform add_showcase_doc(lid, 'OTHER', 'Someone elses file', '', '', '', cus || '/x3.pdf', 'application/pdf', 10, 'PUBLIC', null); o := o || 'FAIL foreign path allowed; ';
  exception when others then o := o || 'ok path guard (' || sqlerrm || '); '; end;
  select count(*) into n from showcase_docs(lid); o := o || 'owner sees ' || n || ' (expect 3); ';

  -- ===== customer =====
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  select count(*) into n from showcase_docs(lid); o := o || 'customer sees ' || n || ' (expect 2, private hidden); ';
  select count(*) into n from showcase_docs(lid) where id = d2 and can_open = false and number = ''; o := o || 'locked card hides number: ' || n || ' (expect 1); ';
  select count(*) into n from storage.objects where bucket_id = 'docs' and name = own || '/iso-test.pdf'; o := o || 'storage public doc readable: ' || n || ' (expect 1); ';
  select count(*) into n from storage.objects where bucket_id = 'docs' and name = own || '/udyam-test.pdf'; o := o || 'storage locked doc readable: ' || n || ' (expect 0); ';
  begin perform open_showcase_doc(d2); o := o || 'FAIL opened locked doc; '; exception when others then o := o || 'ok locked (' || sqlerrm || '); '; end;
  begin perform open_showcase_doc(d3); o := o || 'FAIL opened private doc; '; exception when others then o := o || 'ok private (' || sqlerrm || '); '; end;
  begin perform request_doc_access(d1); o := o || 'FAIL requested a public doc; '; exception when others then o := o || 'ok public needs no request (' || sqlerrm || '); '; end;
  begin perform request_doc_access(d3); o := o || 'FAIL requested a private doc; '; exception when others then o := o || 'ok private no request (' || sqlerrm || '); '; end;
  r := request_doc_access(d2, 'I am deciding whether to order in bulk'); o := o || 'request -> ' || r || '; ';
  r := request_doc_access(d2); o := o || 'again -> ' || r || ' (expect PENDING); ';
  begin perform check_showcase_doc(d1, 1, 'x'); o := o || 'FAIL opinion before opening; '; exception when others then o := o || 'ok must open first (' || sqlerrm || '); '; end;
  j := open_showcase_doc(d1); o := o || 'opened public doc path ' || (j->>'path') || '; ';
  perform check_showcase_doc(d1, 1, 'Looks like the real certificate');
  select checks_up || '/' || checks_down into rs from showcase_docs(lid) where id = d1; o := o || 'checks ' || rs || ' (expect 1/0); ';
  perform check_showcase_doc(d1, -1, 'Changed my mind');
  select checks_up || '/' || checks_down into rs from showcase_docs(lid) where id = d1; o := o || 'after change ' || rs || ' (expect 0/1); ';
  begin perform add_showcase_doc(lid, 'OTHER', 'Mine', '', '', '', cus || '/m.pdf', 'application/pdf', 10, 'PUBLIC', null); o := o || 'FAIL customer added doc; ';
  exception when others then o := o || 'ok customer cannot add (' || sqlerrm || '); '; end;

  -- ===== owner answers =====
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  select id, relation into rq, rs from doc_requests_for(lid) limit 1; o := o || 'owner sees request, relation: ' || coalesce(rs, 'none') || '; ';
  begin perform check_showcase_doc(d1, 1, ''); o := o || 'FAIL owner checked own doc; '; exception when others then o := o || 'ok owner cannot check own (' || sqlerrm || '); '; end;
  r := decide_doc_request(rq, true, 30); o := o || 'decision ' || r || '; ';
  begin perform decide_doc_request(rq, false); o := o || 'FAIL decided twice; '; exception when others then o := o || 'ok single decision; '; end;

  -- ===== customer opens after approval =====
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  j := open_showcase_doc(d2); o := o || 'approved open ok; ';
  select count(*) into n from showcase_docs(lid) where id = d2 and can_open and number <> ''; o := o || 'number visible after approval: ' || n || ' (expect 1); ';
  select count(*) into n from storage.objects where bucket_id = 'docs' and name = own || '/udyam-test.pdf'; o := o || 'storage after approval: ' || n || ' (expect 1); ';

  -- ===== owner revokes, then makes it private =====
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  perform revoke_doc_access(rq);
  select count(*) into n from doc_view_log(lid); o := o || 'view log rows ' || n || '; ';
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  begin perform open_showcase_doc(d2); o := o || 'FAIL open after revoke; '; exception when others then o := o || 'ok revoked; '; end;
  select count(*) into n from storage.objects where bucket_id = 'docs' and name = own || '/udyam-test.pdf'; o := o || 'storage after revoke: ' || n || ' (expect 0); ';
  r := request_doc_access(d2, 'please reconsider'); o := o || 're-request -> ' || r || '; ';
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  perform update_showcase_doc(d2, 'Udyam registration', 'MSME', 'UDYAM-MH-01-0000001', '', 'PRIVATE', null);
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  select count(*) into n from showcase_docs(lid) where id = d2; o := o || 'after private, customer sees it: ' || n || ' (expect 0); ';
  execute 'reset role';

  -- ===== rides =====
  insert into tasks (type, requester_id, vehicle_kind, pickup, drop_at, km, fare) values ('RIDE', cus, 'AUTO', geo(12.97, 77.59), geo(12.98, 77.60), 3, 60) returning id into t1;
  insert into tasks (type, requester_id, vehicle_kind, pickup, drop_at, km, fare, status, driver_id) values ('RIDE', cus, 'AUTO', geo(12.97, 77.59), geo(12.98, 77.60), 3, 60, 'MATCHED', own) returning id into t2;
  insert into tasks (type, requester_id, vehicle_kind, pickup, drop_at, km, fare, status, driver_id) values ('RIDE', cus, 'AUTO', geo(12.97, 77.59), geo(12.98, 77.60), 3, 60, 'ARRIVED', own) returning id into t3;
  insert into tasks (type, requester_id, vehicle_kind, pickup, drop_at, km, fare, status, driver_id) values ('RIDE', cus, 'AUTO', geo(12.97, 77.59), geo(12.98, 77.60), 3, 60, 'IN_PROGRESS', own) returning id into t4;
  perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  perform cancel_task(t1);
  begin perform cancel_task(t2); o := o || 'FAIL matched cancel without reason; '; exception when others then o := o || 'ok matched needs reason (' || sqlerrm || '); '; end;
  begin perform cancel_task(t2, 'NOT_A_REASON'); o := o || 'FAIL bad reason; '; exception when others then o := o || 'ok bad reason (' || sqlerrm || '); '; end;
  begin perform cancel_task(t4, 'PLANS_CHANGED'); o := o || 'FAIL cancelled a ride in progress; '; exception when others then o := o || 'ok in-progress refused (' || sqlerrm || '); '; end;
  perform cancel_task(t2, 'PLANS_CHANGED', 'sorry');
  j := my_cancel_stats(); o := o || 'rider stats ' || (j->>'rider_day') || ' (expect 1); ';
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  begin perform release_task(t3, 'NOT_A_REASON'); o := o || 'FAIL bad driver reason; '; exception when others then o := o || 'ok driver reason checked; '; end;
  perform release_task(t3, 'RIDER_NO_SHOW');
  begin perform release_task(t4, 'TOO_FAR'); o := o || 'FAIL released in-progress ride; '; exception when others then o := o || 'ok in-progress not releasable; '; end;
  j := my_cancel_stats(); o := o || 'driver stats ' || (j->>'driver_day') || ' (expect 1); ';
  execute 'reset role';
  select status into st from tasks where id = t1; o := o || 'searching ride cancelled without reason: ' || st || '; ';
  select status || '/' || cancel_reason || '/' || cancel_after into rs from tasks where id = t2; o := o || 'matched ride: ' || rs || '; ';
  select status || '/' || coalesce(driver_id::text, 'no driver') into rs from tasks where id = t3; o := o || 'driver released: ' || rs || '; ';
  select count(*) into n from task_events where task_id = t3 and event = 'CANCELLED' and reason = 'RIDER_NO_SHOW'; o := o || 'release logged: ' || n || ' (expect 1); ';

  perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  o1 := place_order_ship(lid, jsonb_build_array(jsonb_build_object('item_id', itm, 'qty', 1)), addr, 'UPI');
  o2 := place_order_ship(lid, jsonb_build_array(jsonb_build_object('item_id', itm, 'qty', 1)), addr, 'UPI');
  o3 := place_order_ship(lid, jsonb_build_array(jsonb_build_object('item_id', itm, 'qty', 1)), addr, 'UPI');
  begin perform cancel_order(o2, 'NOT_A_REASON'); o := o || 'FAIL bad buyer reason; '; exception when others then o := o || 'ok buyer reason checked; '; end;
  perform cancel_order(o2, 'CHANGED_MIND');
  execute 'reset role'; perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  begin perform respond_order(o1, false, 'NOT_A_REASON'); o := o || 'FAIL bad reject reason; '; exception when others then o := o || 'ok reject reason checked; '; end;
  perform respond_order(o1, false, 'OUT_OF_STOCK');
  perform respond_order(o3, true); perform update_order_status(o3, 'CANCELLED', 'CLOSED');
  execute 'reset role';
  select status || '/' || cancel_reason into rs from orders where id = o2; o := o || 'buyer cancel: ' || rs || '; ';
  select status || '/' || cancel_reason into rs from orders where id = o1; o := o || 'shop reject: ' || rs || '; ';
  select status || '/' || cancelled_by || '/' || cancel_reason into rs from orders where id = o3; o := o || 'shop cancel after accept: ' || rs || '; ';
  select count(*) into n from notifications where profile_id = own and title = 'Order cancelled' and body like '%changed their mind%'; o := o || 'shop told buyer cancelled: ' || n || ' (expect 1); ';
  select count(*) into n from notifications where profile_id = cus and body like 'Reason: Out of stock%'; o := o || 'buyer told reject reason: ' || n || ' (expect 1); ';
  select count(*) into n from notifications where profile_id = cus and body like 'Reason: Shop is closed%'; o := o || 'buyer told cancel reason: ' || n || ' (expect 1); ';
  raise exception 'RESULT %', o;
end $$;
