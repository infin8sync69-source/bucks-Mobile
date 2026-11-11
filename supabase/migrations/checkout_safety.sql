-- Bucks: an order can't be placed twice by a retried request. Safe to run more than once. Apply after hardening_dispatch.sql
-- (supabase/apply_all.sh runs it last).
--
-- The problem: the phone sends place_order, the server places it, the answer is lost (tunnel, lift, a dropped connection). The cart still
-- shows the shop and "Retry" sends the same order again.
-- The fix: the phone makes up one id per checkout attempt and sends it with the order. The first call with that id places the order;
-- any later call with the same id from the same buyer answers the same order and changes nothing.
--   place_order_once(p_ref, ...)       place_order's arguments after the id
--   place_order_ship_once(p_ref, ...)  place_order_ship's arguments after the id
-- place_order and place_order_ship stay as they are for app versions that don't send an id.
set search_path = public, extensions;

alter table public.orders add column if not exists client_ref uuid;
create unique index if not exists orders_buyer_ref_idx on public.orders (buyer_id, client_ref) where client_ref is not null;

-- The id reaches the new row through a transaction-local setting that only the *_once functions write, so the existing place_order
-- functions (redefined by several migrations) need no change and nobody can attach an id to an order any other way.
create or replace function public.order_take_ref() returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.client_ref := nullif(current_setting('bucks.order_ref', true), '')::uuid;
  return new;
end $$;
drop trigger if exists order_take_ref on public.orders;
create trigger order_take_ref before insert on public.orders for each row execute function public.order_take_ref();

create or replace function public.place_order_once(p_ref uuid, p_listing uuid, p_lines jsonb, p_lat double precision, p_lng double precision, p_drop_label text, p_payment text, p_mode text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := public.me(); oid uuid;
begin
  if my is null then raise exception 'not signed in'; end if;
  if p_ref is null then raise exception 'missing request id'; end if;
  -- The same lock place_order takes, so a second call with this id waits for the first and then finds its order.
  perform pg_advisory_xact_lock(hashtextextended('order:' || my::text, 0));
  select id into oid from orders where buyer_id = my and client_ref = p_ref;
  if oid is not null then return oid; end if;
  perform set_config('bucks.order_ref', p_ref::text, true);
  oid := public.place_order(p_listing, p_lines, p_lat, p_lng, p_drop_label, p_payment, p_mode);
  perform set_config('bucks.order_ref', '', true);
  return oid;
end $$;

create or replace function public.place_order_ship_once(p_ref uuid, p_listing uuid, p_lines jsonb, p_address jsonb, p_payment text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare my uuid := public.me(); oid uuid;
begin
  if my is null then raise exception 'not signed in'; end if;
  if p_ref is null then raise exception 'missing request id'; end if;
  perform pg_advisory_xact_lock(hashtextextended('order:' || my::text, 0));
  select id into oid from orders where buyer_id = my and client_ref = p_ref;
  if oid is not null then return oid; end if;
  perform set_config('bucks.order_ref', p_ref::text, true);
  oid := public.place_order_ship(p_listing, p_lines, p_address, p_payment);
  perform set_config('bucks.order_ref', '', true);
  return oid;
end $$;

revoke execute on function public.order_take_ref() from authenticated, anon, public;
revoke execute on function public.place_order_once(uuid, uuid, jsonb, double precision, double precision, text, text, text),
  public.place_order_ship_once(uuid, uuid, jsonb, jsonb, text) from anon, public;
grant execute on function public.place_order_once(uuid, uuid, jsonb, double precision, double precision, text, text, text),
  public.place_order_ship_once(uuid, uuid, jsonb, jsonb, text) to authenticated;
