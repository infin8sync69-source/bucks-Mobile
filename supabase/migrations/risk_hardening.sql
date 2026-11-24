-- Risk hardening (2026-11-13): fixes from the real-world risk review (docs/RISK_ANALYSIS.md). Safe to re-run.
--
--   R1  Under-18s could post a moment with audience LOCAL straight through the API, so anyone within 5 km (or anyone passing a fake
--       lat/lng to moments_tray) saw it. Their settings already default to SYNCED; now the database enforces it on every moment.
--   R2  A driver's movement allowance (move_credit_m) kept every unused metre. A day parked banked ~3,400 km, after which a fake-GPS
--       app could jump the driver next to any pickup. Leftover allowance is now capped at presence_slack_m after each move.
--   R3  start_direct let a driver and a rider open a chat any time after a COMPLETED trip, ignoring "who can message me". That window
--       now closes 24 hours after the trip ends, the same window contact_for_task uses for the phone number.
--   R4  ensure_profile stored whatever phone the app sent when the token had none. Bucks tokens always carry phone_number (claim-role
--       refuses other sign-ins), so the number now comes from the token only and cannot be set to someone else's.

-- ---------- R1: minors' moments stay with synced people ----------
create or replace function public.guard_minor_moment() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare band text := age_band_of(new.author_id);
begin
  if band in ('CHILD', 'TEEN') then
    if new.audience = 'LOCAL' then new.audience := 'SYNCED'; end if;
    new.location := null;   -- only LOCAL moments use it, and a minor's whereabouts are never stored with a moment
  end if;
  return new;
end $$;
revoke execute on function public.guard_minor_moment() from public, anon, authenticated;

drop trigger if exists moment_minor_guard on public.moments;
create trigger moment_minor_guard before insert or update on public.moments
  for each row execute function public.guard_minor_moment();

-- Moments already up: a minor's LOCAL moment becomes SYNCED (they expire within 24 hours anyway).
update public.moments m set audience = 'SYNCED', location = null
 where m.audience = 'LOCAL' and age_band_of(m.author_id) in ('CHILD', 'TEEN');

-- ---------- R2: no banked movement allowance ----------
create or replace function public.presence_clamp() returns trigger
language plpgsql set search_path = public, extensions as $$
declare v double precision := coalesce(public.setting('presence_max_speed_mps'), 40)::double precision;
        s double precision := coalesce(public.setting('presence_slack_m'), 300)::double precision; credit double precision; d double precision;
begin
  if current_user <> 'authenticated' then return new; end if;
  if tg_op = 'INSERT' then
    new.located_at := case when new.location is not null then now() end;
    new.move_credit_m := s;
    return new;
  end if;
  new.located_at := coalesce(old.located_at, old.updated_at);   -- frozen: a refused write must not restart the clock (presence_touch bumps updated_at on every write)
  new.move_credit_m := old.move_credit_m;
  if new.location is null then new.location := old.location; return new; end if;
  if old.location is null then new.located_at := now(); new.move_credit_m := s; return new; end if;
  d := st_distance(old.location, new.location);
  if d = 0 then return new; end if;
  if v > 0 then
    credit := coalesce(old.move_credit_m, s) + v * greatest(extract(epoch from now() - new.located_at), 0) - d;
    if credit < 0 then new.location := old.location; return new; end if;
    new.move_credit_m := least(credit, s);   -- time spent still lets you move that far once; it is not saved up for later jumps
  end if;
  new.located_at := now();
  return new;
end $$;

create or replace function public.update_location(lat double precision, lng double precision) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := public.me(); p driver_presence; has_row boolean; v double precision := public.dispatch_cfg('presence_max_speed_mps', 40)::double precision;
        s double precision := public.dispatch_cfg('presence_slack_m', 300)::double precision; credit double precision;
begin
  if lat is null or lng is null or not (lat between -90 and 90 and lng between -180 and 180) then raise exception 'that location is not valid'; end if;
  select * into p from driver_presence where profile_id = my for update;
  has_row := found;
  if (not has_row or not p.online) and not exists (select 1 from tasks where driver_id = my and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')) then
    raise exception 'go online first';
  end if;
  if not has_row then return; end if;
  if p.located_at is not null and p.located_at > now() - interval '2 seconds' then return; end if;
  credit := coalesce(p.move_credit_m, s);
  if v > 0 and p.location is not null then
    credit := credit + v * greatest(extract(epoch from now() - coalesce(p.located_at, p.updated_at)), 0) - st_distance(p.location, geo(lat, lng));
    if credit < 0 then return; end if;
    credit := least(credit, s);
  end if;
  update driver_presence set location = geo(lat, lng), located_at = now(), move_credit_m = credit where profile_id = my;
  update tasks set driver_location = geo(lat, lng) where driver_id = my and status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS');
end $$;

-- Allowances already banked are cut back to the slack.
update public.driver_presence set move_credit_m = least(move_credit_m, coalesce(public.setting('presence_slack_m'), 300)::double precision)
 where move_credit_m > coalesce(public.setting('presence_slack_m'), 300)::double precision;

-- ---------- R3: trip chats open only around the trip ----------
create or replace function public.start_direct(p_other uuid) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare k text; c uuid; allowed boolean;
begin
  if me() is null then raise exception 'not signed in'; end if;
  if p_other is null or p_other = me() then raise exception 'that is you'; end if;
  if blocked_between(me(), p_other) then raise exception 'you cannot message this person'; end if;
  k := least(me()::text, p_other::text) || ':' || greatest(me()::text, p_other::text);
  select id into c from conversations where direct_key = k;
  if c is not null then return c; end if;
  allowed := case (select who_can_message from settings_of(p_other)) when 'EVERYONE' then true when 'SYNCED' then synced(me(), p_other) else false end
          or exists (select 1 from tasks t
                      where ((t.requester_id = me() and t.driver_id = p_other) or (t.requester_id = p_other and t.driver_id = me()))
                        and (t.status in ('MATCHED', 'ARRIVED', 'IN_PROGRESS')
                             or (t.status in ('COMPLETED', 'PAID') and t.status_at > now() - interval '24 hours')));
  if not allowed then raise exception 'this person only takes messages from people they have synced with'; end if;
  insert into conversations (kind, direct_key, created_by) values ('DIRECT', k, me()) returning id into c;
  insert into conversation_members (conversation_id, profile_id) values (c, me()), (c, p_other);
  return c;
end $$;

-- ---------- R4: the phone number comes from the sign-in token only ----------
create or replace function public.ensure_profile(p_name text, p_phone text default null) returns public.profiles
language plpgsql security definer set search_path = public, extensions as $$
declare p public.profiles; uid text := auth.jwt()->>'sub';
        ph text := nullif(auth.jwt()->>'phone_number', '');   -- p_phone is kept for older apps and ignored
begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into p from profiles where auth_uid = uid;
  if not found then
    loop
      begin insert into profiles (auth_uid, name) values (uid, left(coalesce(p_name, ''), 80)) returning * into p; exit;
      exception when unique_violation then if exists (select 1 from profiles where auth_uid = uid) then select * into p from profiles where auth_uid = uid; exit; end if; end;  -- short_code clash: retry
    end loop;
  end if;
  insert into profile_private (profile_id, phone) values (p.id, ph) on conflict (profile_id) do update set phone = coalesce(excluded.phone, profile_private.phone);
  return p;
end $$;

revoke execute on function public.start_direct(uuid), public.update_location(double precision, double precision), public.ensure_profile(text, text) from public, anon;
grant execute on function public.start_direct(uuid), public.update_location(double precision, double precision), public.ensure_profile(text, text) to authenticated;
