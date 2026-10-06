-- Rolled-back live scenario for page types (migration page_types.sql). Paste into the SQL editor; it always ends in an exception
-- whose message is the report, so nothing persists. Expect every line to read "ok" or match its "(expect ...)".
do $$
declare own uuid := '01a0e8d3-90c6-7e7e-9689-219247281404'; cus uuid := '01a0eb93-a5a8-7cae-b7cc-e787c17dc1fa';
  own_sub text := 'sIMjoM9t3QSrZjfxwsuxNsOqgNp2'; cus_sub text := '6WI5Twle8OOHXENCYnqoEqpfKGJ3';
  o text := ''; ngo uuid; shop uuid; sal uuid; it uuid; rs text; n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', own_sub)::text, true); execute 'set local role authenticated';
  -- 1. an older app build inserts a business without a type: it becomes a shop, service from the category
  insert into listings (kind, owner_id, title, category, description, area, location, details, status) values ('BUSINESS', own, 'T Restaurant', 'Restaurant', 'x', 'Pune', geo(18.5,73.8), '{}', 'PENDING') returning id into shop;
  select type_key || '/' || service into rs from listings where id = shop; o := o || 'legacy shop: ' || rs || ' (expect RETAIL_SHOP/FOOD); ';
  -- 2. an NGO: the service follows the type whatever the category says
  insert into listings (kind, owner_id, title, category, description, area, location, details, status, type_key) values ('BUSINESS', own, 'T NGO', 'Restaurant', 'x', 'Pune', geo(18.5,73.8), '{}', 'PENDING', 'NGO_CHARITY') returning id into ngo;
  select type_key || '/' || service into rs from listings where id = ngo; o := o || 'ngo: ' || rs || ' (expect NGO_CHARITY/COMMUNITY); ';
  insert into listings (kind, owner_id, title, category, description, area, location, details, status, type_key) values ('BUSINESS', own, 'T Salon', 'Salon', 'x', 'Pune', geo(18.5,73.8), '{}', 'PENDING', 'LOCAL_SERVICE') returning id into sal;
  -- 3. a type for the wrong kind, an unknown type
  begin insert into listings (kind, owner_id, title, category, description, area, location, details, status, type_key) values ('SKILL', own, 'T Skill', 'Plumber', 'x', 'Pune', geo(18.5,73.8), '{}', 'PENDING', 'NGO_CHARITY'); o := o || 'FAIL skill with business type; ';
  exception when others then o := o || 'ok kind guard (' || sqlerrm || '); '; end;
  begin insert into listings (kind, owner_id, title, category, description, area, location, details, status, type_key) values ('BUSINESS', own, 'T X', 'Shop', 'x', 'Pune', geo(18.5,73.8), '{}', 'PENDING', 'NOPE'); o := o || 'FAIL unknown type; ';
  exception when others then o := o || 'ok unknown type (' || left(sqlerrm, 40) || '); '; end;
  -- 4. items must match the catalogue
  begin insert into items (listing_id, kind, name, price) values (ngo, 'PRODUCT', 'T-shirt', 300); o := o || 'FAIL product on NGO; ';
  exception when others then o := o || 'ok items guard (' || sqlerrm || '); '; end;
  insert into items (listing_id, kind, name, price) values (ngo, 'PROGRAM', 'Evening school', 0) returning id into it; o := o || 'program on NGO ok; ';
  begin insert into items (listing_id, kind, name, price) values (shop, 'PROGRAM', 'Course', 0); o := o || 'FAIL program on shop; ';
  exception when others then o := o || 'ok shop takes products only; '; end;
  insert into items (listing_id, kind, name, price) values (sal, 'SERVICE', 'Haircut', 150); o := o || 'service on salon ok; ';
  -- 5. the type may change while pending (and while the pilot switch is on)
  update listings set type_key = 'COMMUNITY_GROUP' where id = ngo; select type_key || '/' || service into rs from listings where id = ngo; o := o || 'retyped pending: ' || rs || ' (expect COMMUNITY_GROUP/COMMUNITY); ';
  update listings set type_key = 'NGO_CHARITY' where id = ngo;
  execute 'reset role';
  update listings set status = 'LIVE', online = true where id in (ngo, shop, sal);
  -- 6. orders only on shops
  perform set_config('request.jwt.claims', json_build_object('sub', cus_sub)::text, true); execute 'set local role authenticated';
  begin perform place_order(ngo, jsonb_build_array(jsonb_build_object('item_id', it, 'qty', 1)), 18.5, 73.8, 'home', 'UPI', 'PICKUP'); o := o || 'FAIL order on NGO; ';
  exception when others then o := o || 'ok orders guard (' || sqlerrm || '); '; end;
  -- 7. search returns the type; group chips filter by service
  select count(*) into n from search_listings('NGO', 18.5, 73.8, 10000, null, 40, null) s where s.type_key = 'NGO_CHARITY'; o := o || 'search by type label finds NGOs: ' || n || ' (expect >=1); ';
  select count(*) into n from search_listings('', 18.5, 73.8, 10000, array['BUSINESS'], 40, array['LOCAL_SERVICES']) s where s.group_key = 'LOCAL_SERVICES'; o := o || 'local services chip: ' || n || ' (expect >=1); ';
  select count(*) into n from search_listings('', 18.5, 73.8, 10000, array['BUSINESS'], 40, array['FOOD','GROCERY','VEGETABLES','MEAT','SHOPPING']) s where s.group_key <> 'SHOPS'; o := o || 'non-shops under Shops chip: ' || n || ' (expect 0); ';
  select string_agg(key || ':' || state || '/' || supply, ', ') into rs from services_near(18.5458, 73.8176) where key in ('LOCAL_SERVICES','BIZ_PRO','COMMUNITY','INSTITUTIONS','SHOPPING'); o := o || 'tiles Pune: ' || rs || '; ';
  execute 'reset role';
  raise exception 'RESULT %', o;
end $$;
