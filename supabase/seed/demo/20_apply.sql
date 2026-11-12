-- The closed-test demo world, step 2 of 3: 10_data.sql (staging tables) -> this function -> 99_revert.sql to undo.
-- Applied to the live project on 2026-11-12 06:43 UTC (Android revision 1). Run the dry run first: it does everything and then raises
-- "DRY RUN OK {...counts...}", which rolls it back.
--     select demo_seed.apply(true);     -- dry run
--     select demo_seed.apply(false);    -- for real
-- Needs the staging schema from 10_data.sql (python3 build_demo.py writes it). Refuses to run twice (demo people already there).
-- What it makes: 18 demo people in 3 places (Gonikoppal/Kodagu, Whitefield/Bengaluru, Kallukoottam/Kanyakumari), 23 shops with 159
-- products, 18 gigs, 12 jobs, 30 posts with votes and comments, shop reviews and recommendations; syncs every adult profile (testers
-- and demo people) with every other; makes every adult follow the demo shops; opens every service (service_rules.mode = 'ON') and
-- lowers the recommendation thresholds to 1 recommendation / 0 days, as supabase/pilot_test_settings.sql does.
-- Push notifications are silenced while it runs (the webhook secret is blanked inside the transaction and put back at the end).
-- Photos: one real photo per product in items.photo_url and listings.photo_url (Wikimedia Commons, credits in items.details.credit);
-- gallery/photos stay empty because the database only accepts the listing's own storage files there (listings_gallery_ok).
create or replace function demo_seed.apply(dry boolean default true) returns text language plpgsql security definer set search_path = public, extensions as $f$
declare v_secret text; n jsonb := '{}'::jsonb; c int;
begin
  if exists (select 1 from profiles where auth_uid like 'demo:%') then raise exception 'demo world already exists; run the revert first'; end if;
  select value into v_secret from push_config where key = 'webhook_secret';
  update push_config set value = '' where key = 'webhook_secret';

  -- ---- people ----
  insert into profiles (auth_uid, name, bio, area, home, status)
    select 'demo:' || p.slug, p.name, p.bio, c.label, geo(c.lat + (abs(hashtext(p.slug)) % 1000) / 1000.0 * 0.02 - 0.01, c.lng + (abs(hashtext(p.slug || 'x')) % 1000) / 1000.0 * 0.02 - 0.01), 'ACTIVE'
    from demo_seed.people p join demo_seed.clusters c on c.key = p.cluster;
  insert into profile_private (profile_id) select id from profiles where auth_uid like 'demo:%';
  insert into profile_safety (profile_id, birth_date, age_band) select id, date '1992-05-15', 'ADULT' from profiles where auth_uid like 'demo:%';
  n := n || jsonb_build_object('people', (select count(*) from profiles where auth_uid like 'demo:%'));

  -- ---- shops and products ----
  insert into listings (id, kind, owner_id, title, category, description, photo_url, area, location, details, status, online, service, type_key, gallery)
    select s.id, 'BUSINESS', pr.id, s.title, t.category, t.about,
           (select 'https://thumb.wikimedia.org/wikipedia/commons/thumb/' || i.photo from demo_seed.items i where i.shop_key = s.shop_key and i.photo is not null order by i.ord limit 1),
           c.label, geo(c.lat + s.dlat, c.lng + s.dlng),
           jsonb_build_object('demo', true, 'cod', true, 'hours', 'Daily ' || t.hours, 'org_type', 'PRODUCT', 'free_delivery', t.free_delivery, 'delivery_radius_km', t.radius_km),
           'LIVE', true, t.service, 'RETAIL_SHOP', '[]'::jsonb
    from demo_seed.shops s join demo_seed.shop_tpl t on t.shop_key = s.shop_key join demo_seed.clusters c on c.key = s.cluster join profiles pr on pr.auth_uid = 'demo:' || s.owner_slug;
  insert into items (listing_id, kind, name, price, mrp, unit, group_name, photo_url, in_stock, stock, description, photos, details, sort)
    select s.id, 'PRODUCT', i.name, i.price, i.mrp, i.unit, i.grp, 'https://thumb.wikimedia.org/wikipedia/commons/thumb/' || i.photo, true, 40 + (abs(hashtext(i.name)) % 60),
           i.name || ' from ' || s.title || '. Fresh stock, fair price.', '[]'::jsonb,
           jsonb_build_object('demo', true, 'product', i.name, 'credit', i.credit), i.ord
    from demo_seed.shops s join demo_seed.items i on i.shop_key = s.shop_key;
  n := n || jsonb_build_object('shops', (select count(*) from listings where details->>'demo' = 'true' and kind = 'BUSINESS'), 'items', (select count(*) from items where details->>'demo' = 'true'));

  -- ---- gigs (skills) and jobs ----
  insert into listings (kind, owner_id, title, category, description, area, location, details, status, online, service)
    select 'SKILL', pr.id, v.title, v.category, v.title || '. Reliable, on time, fair rates. Message me to book.', c.label, geo(c.lat + (abs(hashtext(v.title || v.owner)) % 1000) / 1000.0 * 0.02 - 0.01, c.lng + (abs(hashtext(v.owner || v.title)) % 1000) / 1000.0 * 0.02 - 0.01),
           jsonb_build_object('demo', true, 'rate', v.rate, 'hours', v.hours, 'level', v.level, 'languages', to_jsonb(string_to_array(v.langs, ', '))), 'LIVE', true, 'GIGS'
    from (values
      ('kodagu','kodagu4','Full-stack web developer','Software developer','₹900/hour','Mon to Sat, 10am to 8pm','Expert','English, Hindi'),('kodagu','kodagu5','Maths and Science tutor (classes 8 to 12)','Tutor','₹500/hour','Evenings 4pm to 9pm','Expert','English, Kannada'),
      ('kodagu','kodagu2','Electrician for homes and shops','Electrician','₹400/visit','Daily 8am to 7pm','Experienced','Tamil, English'),('kodagu','kodagu0','Plumber, leaks and fittings','Plumber','₹350/visit','Daily 8am to 7pm','Experienced','Tamil, Malayalam'),
      ('kodagu','kodagu4','Wedding and event photographer','Photographer','₹3,000/hour','Weekends and festivals','Expert','English, Hindi'),('kodagu','kodagu5','Yoga trainer, home sessions','Yoga instructor','₹600/session','Mornings 5:30am to 9am','Expert','English, Hindi'),
      ('blr','blr4','Full-stack web developer','Software developer','₹1,200/hour','Mon to Sat, 10am to 8pm','Expert','English, Hindi'),('blr','blr5','Yoga trainer, home sessions','Yoga instructor','₹800/session','Mornings 5:30am to 9am','Expert','English, Hindi'),
      ('blr','blr2','Electrician for homes and shops','Electrician','₹500/visit','Daily 8am to 7pm','Experienced','Kannada, English'),('blr','blr1','Logo and social media designer','Designer','₹900/hour','Mon to Fri, 11am to 7pm','Experienced','English, Hindi'),
      ('blr','blr5','Maths and Science tutor (classes 8 to 12)','Tutor','₹700/hour','Evenings 4pm to 9pm','Expert','English, Kannada'),('blr','blr0','Carpenter, furniture repair','Carpenter','₹900/day','Mon to Sat, 9am to 6pm','Experienced','Kannada, English'),
      ('kk','kk4','Electrician for homes and shops','Electrician','₹400/visit','Daily 8am to 7pm','Experienced','Tamil, English'),('kk','kk4','Plumber, leaks and fittings','Plumber','₹350/visit','Daily 8am to 7pm','Experienced','Tamil, Malayalam'),
      ('kk','kk5','Wedding and event photographer','Photographer','₹3,000/hour','Weekends and festivals','Expert','English, Tamil'),('kk','kk3','Maths and Science tutor (classes 8 to 12)','Tutor','₹400/hour','Evenings 4pm to 9pm','Expert','Tamil, English'),
      ('kk','kk5','Logo and social media designer','Designer','₹600/hour','Mon to Fri, 11am to 7pm','Experienced','English, Tamil'),('kk','kk3','Carpenter, furniture repair','Carpenter','₹800/day','Mon to Sat, 9am to 6pm','Experienced','Tamil, English')
    ) v(cluster, owner, title, category, rate, hours, level, langs) join demo_seed.clusters c on c.key = v.cluster join profiles pr on pr.auth_uid = 'demo:' || v.owner;
  insert into jobs (listing_id, title, description, pay, job_type, open, created_by)
    select s.id, j.title, j.descr, j.pay, j.job_type, true, l.owner_id
    from (select s.*, row_number() over (partition by cluster order by shop_key) rn from demo_seed.shops s) s join listings l on l.id = s.id
    join (values (1,'Delivery partner','Deliver orders on your own bike in the area. Fuel allowance and weekly payout.','₹15,000 to ₹20,000 per month','FULL_TIME'),(2,'Sales associate','Help customers, keep shelves tidy and handle billing.','₹14,000 to ₹18,000 per month','FULL_TIME'),
                (3,'Weekend helper','Saturday and Sunday shifts, 10am to 6pm.','₹600 per day','PART_TIME'),(4,'Festival season packing','Two weeks of packing and wrapping for the festival rush.','₹700 per day','GIG')) j(rn, title, descr, pay, job_type) on j.rn = s.rn;
  n := n || jsonb_build_object('gigs', (select count(*) from listings where details->>'demo' = 'true' and kind = 'SKILL'), 'jobs', (select count(*) from jobs j join listings l on l.id = j.listing_id where l.details->>'demo' = 'true'));

  -- ---- everyone adult synced with everyone, and following the demo shops ----
  insert into syncs (requester_id, addressee_id, status)
    select a.id, b.id, 'ACCEPTED' from profiles a join profiles b on a.id < b.id
    where a.status = 'ACTIVE' and b.status = 'ACTIVE' and age_band_of(a.id) = 'ADULT' and age_band_of(b.id) = 'ADULT'
      and not exists (select 1 from syncs s where (s.requester_id = a.id and s.addressee_id = b.id) or (s.requester_id = b.id and s.addressee_id = a.id));
  get diagnostics c = row_count; n := n || jsonb_build_object('new_syncs', c);
  update syncs s set status = 'ACCEPTED' where status = 'PENDING' and age_band_of(requester_id) = 'ADULT' and age_band_of(addressee_id) = 'ADULT';
  get diagnostics c = row_count; n := n || jsonb_build_object('pending_accepted', c);
  insert into listing_syncs (profile_id, listing_id) select p.id, l.id from profiles p cross join listings l where l.details->>'demo' = 'true' and age_band_of(p.id) = 'ADULT' and p.status = 'ACTIVE' on conflict do nothing;

  -- ---- posts, votes, comments ----
  create temp table _t(ord int, body text, vis text, hrs int) on commit drop;
  insert into _t values (0,'Fresh batch just out of the oven. Come early, the first tray goes quickly!','PUBLIC',3),(1,'Best filter coffee in {area}? Asking for a friend.','PUBLIC',5),(2,'Rain since morning, perfect weather for pakoras and chai.','LOCAL',8),(3,'Anyone know a good plumber near {area}? Water pressure has dropped.','LOCAL',12),
    (4,'Weekend plan: long walk, big breakfast, no phone. Who is in?','SYNCED',20),(5,'New stock arrived today. Do check it out and tell us what you think.','PUBLIC',26),(6,'Small town, big hearts. Thank you for supporting local shops this season.','PUBLIC',30),
    (7,'Looking for a tutor for class 10 maths. Recommendations please.','LOCAL',40),(8,'Photographers and designers: what do you use for quick edits on the phone?','PUBLIC',52),(9,'Sunset from the terrace today. {area} is beautiful in this light.','PUBLIC',70);
  create temp table _p(id uuid, cluster text, author uuid, ord int) on commit drop;
  with ins as (
    insert into posts (author_id, listing_id, body, media, visibility, location, area, created_at)
      select pr.id, case when t.ord in (0,5) then (select l.id from listings l where l.owner_id = pr.id and l.kind = 'BUSINESS' and l.details->>'demo' = 'true' order by l.title limit 1) end,
             replace(t.body, '{area}', split_part(c.label, ',', 1)), '[]'::jsonb, t.vis, geo(c.lat + (t.ord - 5) * 0.0015, c.lng + (t.ord % 4 - 2) * 0.002), split_part(c.label, ',', 1), now() - make_interval(hours => t.hrs)
      from demo_seed.clusters c join _t t on true join profiles pr on pr.auth_uid = 'demo:' || c.key || ((t.ord) % 6)::text
      returning id, author_id, body)
  insert into _p select i.id, null, i.author_id, null from ins i;
  update _p set cluster = (select c.key from demo_seed.clusters c join demo_seed.people pe on pe.cluster = c.key where 'demo:' || pe.slug = (select auth_uid from profiles where id = _p.author) limit 1);
  update _p set ord = (select t.ord from _t t join posts po on po.id = _p.id where po.body = replace(t.body, '{area}', split_part(po.area, ',', 1)) limit 1);
  -- everyone in the cluster recommends (up-votes) the others' posts; a third of the people from the other clusters do too
  insert into post_votes (post_id, profile_id, vote)
    select p.id, v.id, 1 from _p p join profiles v on v.auth_uid like 'demo:%' and v.id <> p.author
    where v.auth_uid like 'demo:' || p.cluster || '%' or abs(hashtext(v.auth_uid || p.id::text)) % 3 = 0 on conflict do nothing;
  insert into post_comments (post_id, author_id, body)
    select p.id, v.id, (array['Totally agree!','Count me in.','Thanks for sharing, will visit this week.','Great suggestion.','Same here, very good.','Looks wonderful.','Do you deliver nearby?','Recommended. Been there twice.'])[1 + abs(hashtext(v.auth_uid || p.id::text)) % 8]
    from _p p join profiles v on v.auth_uid like 'demo:' || p.cluster || '%' and v.id <> p.author where abs(hashtext(v.id::text || p.id::text)) % 3 = 0;
  n := n || jsonb_build_object('posts', (select count(*) from _p));

  -- ---- shop reviews and recommendations from the neighbours ----
  insert into reviews (listing_id, author_id, vote, comment)
    select l.id, v.id, 1, (array['Great quality and quick service.','Always fresh, never disappointed.','Fair prices and friendly owner.','Delivery was on time. Will order again.','My go-to shop in the area.'])[1 + abs(hashtext(v.auth_uid || l.id::text)) % 5]
    from listings l join profiles o on o.id = l.owner_id join profiles v on v.auth_uid like 'demo:%' and v.id <> l.owner_id and substring(v.auth_uid from 6 for 3) = substring(o.auth_uid from 6 for 3)
    where l.details->>'demo' = 'true' and l.kind = 'BUSINESS' and abs(hashtext(v.id::text || l.id::text)) % 2 = 0 on conflict do nothing;
  insert into recommendations (listing_id, recommender_id, at_location)
    select l.id, v.id, l.location from listings l join profiles o on o.id = l.owner_id join profiles v on v.auth_uid like 'demo:%' and v.id <> l.owner_id and substring(v.auth_uid from 6 for 3) = substring(o.auth_uid from 6 for 3)
    where l.details->>'demo' = 'true' and l.kind = 'BUSINESS' on conflict do nothing;

  -- ---- unlock everything for the test (revert: 99_revert.sql) ----
  update settings set value = '1' where key = 'min_recommendations';
  update settings set value = '0' where key in ('recommender_min_account_days', 'vote_min_account_days');
  update service_rules set mode = 'ON', updated_at = now();
  n := n || jsonb_build_object('rules_on', (select count(*) from service_rules where mode = 'ON'), 'live_demo_listings', (select count(*) from listings where details->>'demo' = 'true' and status = 'LIVE'));

  update push_config set value = v_secret where key = 'webhook_secret';
  if dry then raise exception 'DRY RUN OK %', n::text; end if;
  return n::text;
end $f$;
