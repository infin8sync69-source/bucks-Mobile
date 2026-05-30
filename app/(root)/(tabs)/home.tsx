import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
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

const { height } = Dimensions.get('window');

export default function HomeScreen() {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const mapRef = useRef<MapView>(null);
  const { setUserLocation } = useLocationStore();
  const { incomingRequest, setIncomingRequest } = useRideStore();

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

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <AppHeader
        onMenuPress={() => setDrawerOpen(true)}
        chatBadge={10}
      />

      <View style={styles.mapContainer}>
        <MapView
          ref={mapRef}
          style={StyleSheet.absoluteFillObject}
          provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
          initialRegion={BENGALURU_REGION}
          showsUserLocation
          showsMyLocationButton={false}
        />
      </View>

      <View style={styles.searchBar}>
        <TouchableOpacity
          style={styles.searchRow}
          onPress={() => router.push('/(root)/find-ride')}
        >
          <Ionicons name="search-outline" size={18} color={COLORS.muted} />
          <Text style={styles.searchText}>Search</Text>
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
  container: {
    flex: 1,
    backgroundColor: COLORS.white,
  },
  mapContainer: {
    flex: 1,
  },
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
  searchText: {
    fontSize: 15,
    color: COLORS.muted,
  },
});
