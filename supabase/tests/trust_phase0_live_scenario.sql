-- Live, rolled-back check of trust_phase0.sql. Run as one statement; it always ends with RESULT ... (an exception), so nothing is kept.
-- Voter: Shafeeq (owner of other pages, driver of ala's paid trips). Subject: Glow Salon (run by ala), ala's posts, ala as a rider.
do $$
declare
  shafeeq uuid := '01a0e8d3-90c6-7e7e-9689-219247281404'; ala uuid := '01a0eb93-a5a8-7cae-b7cc-e787c17dc1fa';
  glow uuid := '01a10fa9-cfba-7993-87d9-62bf80a6fc72'; trip uuid := '01a0f102-1d5b-7c74-ac04-b6a54f980e2a';
  ala_post uuid; own_post uuid; r text := ''; up0 int; up1 int; dn int; ok boolean;
begin
  select trust_up into up0 from listings where id = glow;
  select id into ala_post from posts where author_id = ala and deleted_at is null and visibility in ('PUBLIC', 'LOCAL') limit 1;
  select id into own_post from posts where author_id = shafeeq and deleted_at is null limit 1;
  perform set_config('request.jwt.claims', '{"sub":"sIMjoM9t3QSrZjfxwsuxNsOqgNp2"}', true);
  set local role authenticated;

  -- 1. a direct vote is recounted onto the listing
  perform rate_listing(glow, 1, 'Great haircut');
  reset role; select trust_up into up1 from listings where id = glow; set local role authenticated;
  r := r || case when up1 = up0 + 1 then '1:ok ' else format('1:FAIL(%s->%s) ', up0, up1) end;

  -- 2. flipping the same day is refused
  begin perform rate_listing(glow, -1, 'changed my mind'); r := r || '2:FAIL '; exception when others then r := r || case when sqlerrm like '%tomorrow%' then '2:ok ' else '2:FAIL(' || sqlerrm || ') ' end; end;

  -- 3. clearing takes it back off
  perform clear_listing_rating(glow);
  reset role; select trust_up into up1 from listings where id = glow; set local role authenticated;
  r := r || case when up1 = up0 then '3:ok ' else '3:FAIL ' end;

  -- 4. a down after a trip needs a reason; the rider's trust is recounted; once per trip
  begin perform rate_rider(trip, -1, 'kept me waiting'); r := r || '4a:FAIL '; exception when others then r := r || case when sqlerrm like '%what went wrong%' then '4a:ok ' else '4a:FAIL(' || sqlerrm || ') ' end; end;
  perform rate_rider(trip, -1, 'kept me waiting', 'LATE');
  reset role; select trust_down into dn from profiles where id = ala; set local role authenticated;
  r := r || case when dn >= 1 then '4b:ok ' else '4b:FAIL ' end;
  begin perform rate_rider(trip, 1, ''); r := r || '4c:FAIL '; exception when others then r := r || '4c:ok '; end;

  -- 5. post votes: someone else's visible post yes, your own no
  if ala_post is not null then
    begin insert into post_votes (post_id, profile_id, vote) values (ala_post, shafeeq, 1) on conflict (post_id, profile_id) do update set vote = 1; r := r || '5a:ok ';
    exception when others then r := r || '5a:FAIL(' || sqlerrm || ') '; end;
  else r := r || '5a:skip '; end if;
  if own_post is not null then
    begin insert into post_votes (post_id, profile_id, vote) values (own_post, shafeeq, 1); r := r || '5b:FAIL ';
    exception when others then r := r || '5b:ok '; end;
  else r := r || '5b:skip '; end if;

  -- 6. the account-age gate applies once the pilot switch is off
  reset role;
  update settings set value = 0 where key = 'pilot_skip_checks';
  update settings set value = 100000 where key = 'vote_min_account_days';
  set local role authenticated;
  begin perform rate_listing(glow, 1, ''); r := r || '6:FAIL '; exception when others then r := r || case when sqlerrm like '%few days%' then '6:ok' else '6:FAIL(' || sqlerrm || ')' end; end;

  raise exception 'RESULT %', r;
end $$;
