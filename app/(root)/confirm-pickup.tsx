import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
  Platform,
} from 'react-native';
import MapView, { Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useLocationStore } from '@/store';

export default function ConfirmPickup() {
  const { userLatitude, userLongitude } = useLocationStore();
  const scaleAnim = useRef(new Animated.Value(0.4)).current;
  const opacityAnim = useRef(new Animated.Value(0.8)).current;

  useEffect(() => {
    Animated.loop(
      Animated.parallel([
        Animated.sequence([
          Animated.timing(scaleAnim, { toValue: 1.3, duration: 1800, useNativeDriver: true }),
          Animated.timing(scaleAnim, { toValue: 0.4, duration: 0, useNativeDriver: true }),
        ]),
        Animated.sequence([
          Animated.timing(opacityAnim, { toValue: 0, duration: 1800, useNativeDriver: true }),
          Animated.timing(opacityAnim, { toValue: 0.8, duration: 0, useNativeDriver: true }),
        ]),
      ]),
    ).start();
  }, [scaleAnim, opacityAnim]);

  const region = {
    latitude: userLatitude ?? BENGALURU_REGION.latitude,
    longitude: userLongitude ?? BENGALURU_REGION.longitude,
    latitudeDelta: 0.01,
    longitudeDelta: 0.01,
  };

  return (
    <View style={styles.container}>
      <MapView
        style={StyleSheet.absoluteFillObject}
        provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
        initialRegion={region}
        showsUserLocation={false}
      >
        <Marker coordinate={{ latitude: region.latitude, longitude: region.longitude }}>
          <View style={styles.markerOuter}>
            <View style={styles.markerInner} />
          </View>
        </Marker>
      </MapView>

      {/* Ripple animation */}
      <View style={styles.rippleWrap} pointerEvents="none">
        <Animated.View
          style={[
            styles.ripple,
            { transform: [{ scale: scaleAnim }], opacity: opacityAnim },
          ]}
        />
      </View>

      <View style={styles.footer}>
        <View style={styles.headerRow}>
          <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
            <Ionicons name="arrow-back" size={22} color={COLORS.text} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Confirm pick-up location</Text>
        </View>
        <TouchableOpacity
          style={styles.confirmBtn}
          onPress={() => router.push('/(root)/locating-driver')}
        >
          <Text style={styles.confirmText}>Confirm pick-up</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  rippleWrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 140,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ripple: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: 'rgba(124,58,237,0.18)',
  },
  markerOuter: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 4,
  },
  markerInner: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#fff',
  },
  footer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: COLORS.white,
    paddingHorizontal: 20,
    paddingTop: 18,
    paddingBottom: 36,
    gap: 14,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
    elevation: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  backBtn: { padding: 2 },
  headerTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: COLORS.text,
    flex: 1,
  },
  confirmBtn: {
    backgroundColor: COLORS.primary,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: 'center',
  },
  confirmText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
});
