import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import MapView, { PROVIDER_GOOGLE } from 'react-native-maps';
import * as Location from 'expo-location';
import { router } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

import AppHeader from '@/components/AppHeader';
import Drawer from '@/components/Drawer';
import RideRequestCard from '@/components/RideRequestCard';
import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useLocationStore } from '@/store';
import { useRideStore } from '@/store/rideStore';
import { useUserStore } from '@/store/userStore';
import {
  subscribeToDriverRequests,
  streamDriverLocation,
} from '@/services/rideService';

export default function HomeScreen() {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const mapRef = useRef<MapView>(null);

  const { setUserLocation } = useLocationStore();
  const { incomingRequest, setIncomingRequest, isOnline } = useRideStore();
  const { vehicles } = useUserStore();

  // ── Acquire GPS + reverse-geocode on mount ──────────────────────────────
  useEffect(() => {
    (async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      const loc = await Location.getCurrentPositionAsync({});
      const addr = await Location.reverseGeocodeAsync({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
      });
      setUserLocation({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        address: `${addr[0]?.name ?? ''}, ${addr[0]?.region ?? ''}`,
      });
      mapRef.current?.animateToRegion({
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        latitudeDelta: 0.05,
        longitudeDelta: 0.05,
      });
    })();
  }, []);

  // ── Supabase Realtime: listen for incoming ride requests ─────────────
  useEffect(() => {
    if (!isOnline) return;
    const onlineVehicle = vehicles.find((v) => v.status === 'online');
    const vehicleType = onlineVehicle?.type ?? 'auto';

    const channel = subscribeToDriverRequests(vehicleType, (ride) => {
      setIncomingRequest({
        id: ride.id,
        customerId: ride.customer_id,
        driverId: null,
        vehicleType: ride.vehicle_type,
        pickupLat: ride.pickup_lat,
        pickupLng: ride.pickup_lng,
        pickupAddress: ride.pickup_address,
        dropLat: ride.drop_lat,
        dropLng: ride.drop_lng,
        dropAddress: ride.drop_address,
        fare: ride.fare,
        pinCode: ride.pin_code,
        status: 'searching',
        customerInitials: 'PS',
        pickupDistance: 200,
        dropDistance: 5,
      });
    });

    return () => { channel.unsubscribe(); };
  }, [isOnline, vehicles]);

  // ── Stream driver GPS every 3s while online ──────────────────────────
  useEffect(() => {
    if (!isOnline) return;
    const interval = setInterval(async () => {
      const loc = await Location.getLastKnownPositionAsync();
      if (loc) {
        // Replace 'mock-user-id' with Clerk userId in production
        await streamDriverLocation('mock-user-id', loc.coords.latitude, loc.coords.longitude);
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [isOnline]);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <AppHeader onMenuPress={() => setDrawerOpen(true)} chatBadge={10} />

      <View style={styles.mapContainer}>
        <MapView
          ref={mapRef}
          style={StyleSheet.absoluteFillObject}
          provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
          initialRegion={BENGALURU_REGION}
          showsUserLocation
          showsMyLocationButton={false}
        />
        {isOnline && (
          <View style={styles.onlinePill}>
            <View style={styles.onlineDot} />
            <Text style={styles.onlineText}>You're online</Text>
          </View>
        )}
      </View>

      <View style={styles.searchBar}>
        <TouchableOpacity
          style={styles.searchRow}
          onPress={() => router.push('/(root)/find-ride')}
        >
          <Ionicons name="search-outline" size={18} color={COLORS.muted} />
          <Text style={styles.searchText}>Where to?</Text>
        </TouchableOpacity>
      </View>

      {incomingRequest && (
        <RideRequestCard
          ride={incomingRequest}
          onAccept={() => {
            setIncomingRequest(null);
            router.push('/(root)/go-pickup');
          }}
          onDismiss={() => setIncomingRequest(null)}
        />
      )}

      <Drawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: COLORS.white },
  mapContainer: { flex: 1 },
  onlinePill: {
    position: 'absolute',
    top: 12,
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: COLORS.white,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  onlineDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: COLORS.success,
  },
  onlineText: { fontSize: 13, fontWeight: '600', color: COLORS.text },
  searchBar: {
    backgroundColor: COLORS.white,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 2,
  },
  searchText: { fontSize: 15, color: COLORS.muted },
});
