/**
 * rideService — all Supabase interactions for the P2P ride flow.
 *
 * Customer side:
 *   createRide → subscribeToRide (watch status changes)
 *
 * Driver side:
 *   subscribeToDriverRequests (Realtime INSERT on rides table)
 *   claimRide (atomic UPDATE; RLS rejects if another driver was first)
 *   updateRideStatus
 *   streamDriverLocation (upsert every 3s while online)
 */

import { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from './supabase';

// ── Types ──────────────────────────────────────────────────────────────────

export interface RideRow {
  id: string;
  customer_id: string;
  driver_id: string | null;
  vehicle_type: string;
  pickup_lat: number;
  pickup_lng: number;
  pickup_address: string;
  drop_lat: number;
  drop_lng: number;
  drop_address: string;
  fare: number;
  pin_code: string;
  status: 'searching' | 'accepted' | 'pickup' | 'active' | 'done' | 'cancelled';
  cancel_reason: string | null;
  customer_rating: number | null;
  driver_rating: number | null;
  tip_amount: number;
  created_at: string;
}

export interface CreateRideParams {
  customerId: string;
  vehicleType: string;
  pickupLat: number;
  pickupLng: number;
  pickupAddress: string;
  dropLat: number;
  dropLng: number;
  dropAddress: string;
  fare: number;
}

// ── Helpers ────────────────────────────────────────────────────────────────

function generatePin(): string {
  return Math.floor(1000 + Math.random() * 9000).toString();
}

// ── Customer: create ride ──────────────────────────────────────────────────

export async function createRide(params: CreateRideParams): Promise<RideRow> {
  const { data, error } = await supabase
    .from('rides')
    .insert({
      customer_id: params.customerId,
      vehicle_type: params.vehicleType,
      pickup_lat: params.pickupLat,
      pickup_lng: params.pickupLng,
      pickup_address: params.pickupAddress,
      drop_lat: params.dropLat,
      drop_lng: params.dropLng,
      drop_address: params.dropAddress,
      fare: params.fare,
      pin_code: generatePin(),
      status: 'searching',
    })
    .select()
    .single();

  if (error) throw error;
  return data as RideRow;
}

// ── Customer: watch ride status changes ───────────────────────────────────

export function subscribeToRide(
  rideId: string,
  onChange: (ride: RideRow) => void,
): RealtimeChannel {
  return supabase
    .channel(`ride:${rideId}`)
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'rides',
        filter: `id=eq.${rideId}`,
      },
      (payload) => onChange(payload.new as RideRow),
    )
    .subscribe();
}

// ── Driver: listen for new searching rides ────────────────────────────────

export function subscribeToDriverRequests(
  vehicleType: string,
  onRequest: (ride: RideRow) => void,
): RealtimeChannel {
  return supabase
    .channel('driver_requests')
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'rides',
        filter: `vehicle_type=eq.${vehicleType}`,
      },
      (payload) => {
        const ride = payload.new as RideRow;
        if (ride.status === 'searching') onRequest(ride);
      },
    )
    .subscribe();
}

// ── Driver: atomic first-accept claim (RLS enforces one winner) ───────────

export async function claimRide(
  rideId: string,
  driverId: string,
  vehicleId: string,
): Promise<RideRow | null> {
  const { data, error } = await supabase
    .from('rides')
    .update({
      driver_id: driverId,
      vehicle_id: vehicleId,
      status: 'accepted',
    })
    .eq('id', rideId)
    .eq('status', 'searching')
    .is('driver_id', null)
    .select()
    .single();

  // PGRST116 = no rows matched → another driver claimed first
  if (error?.code === 'PGRST116') return null;
  if (error) throw error;
  return data as RideRow;
}

// ── Shared: update ride status ─────────────────────────────────────────────

export async function updateRideStatus(
  rideId: string,
  status: RideRow['status'],
  extra?: Partial<RideRow>,
): Promise<void> {
  const { error } = await supabase
    .from('rides')
    .update({ status, ...extra })
    .eq('id', rideId);

  if (error) throw error;
}

// ── Driver: stream live location (call every 3s while online) ────────────

export async function streamDriverLocation(
  userId: string,
  lat: number,
  lng: number,
): Promise<void> {
  const { error } = await supabase.from('driver_locations').upsert({
    user_id: userId,
    lat,
    lng,
    updated_at: new Date().toISOString(),
  });
  if (error) console.warn('location stream error:', error.message);
}

// ── Customer: subscribe to nearby driver positions ────────────────────────

export function subscribeToNearbyDrivers(
  onUpdate: (positions: Array<{ userId: string; lat: number; lng: number }>) => void,
): RealtimeChannel {
  return supabase
    .channel('driver_locations')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'driver_locations' },
      async () => {
        // Refetch the full set after any change; keeps logic simple
        const { data } = await supabase
          .from('driver_locations')
          .select('user_id, lat, lng');
        onUpdate(
          (data ?? []).map((r: any) => ({
            userId: r.user_id,
            lat: r.lat,
            lng: r.lng,
          })),
        );
      },
    )
    .subscribe();
}

// ── Driver: submit rating ─────────────────────────────────────────────────

export async function submitRating(
  rideId: string,
  role: 'customer' | 'driver',
  rating: number,
  tip?: number,
): Promise<void> {
  const patch: Partial<RideRow> =
    role === 'customer'
      ? { customer_rating: rating, tip_amount: tip ?? 0 }
      : { driver_rating: rating };

  const { error } = await supabase.from('rides').update(patch).eq('id', rideId);
  if (error) throw error;
}
