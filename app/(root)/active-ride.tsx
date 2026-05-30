import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Platform,
  Animated,
} from 'react-native';
import MapView, { Polyline, Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useRideStore } from '@/store/rideStore';

const MOCK_ROUTE = [
  { latitude: 13.082, longitude: 77.568 },
  { latitude: 13.075, longitude: 77.578 },
  { latitude: 13.068, longitude: 77.588 },
  { latitude: 13.058, longitude: 77.598 },
];

const TOTAL_DURATION_SECS = 25 * 60;

export default function ActiveRide() {
  const { activeRide } = useRideStore();
  const [message, setMessage] = useState('');
  const [secondsLeft, setSecondsLeft] = useState(TOTAL_DURATION_SECS);
  const progressAnim = useRef(new Animated.Value(0)).current;

  const dropAddress = activeRide?.dropAddress ?? 'Nexus Mall, Koramangala';
  const driverName  = activeRide?.driverName ?? 'John D.';
  const distance    = activeRide?.distance ?? 5.4;

  useEffect(() => {
    // Animate progress bar over trip duration
    Animated.timing(progressAnim, {
      toValue: 1,
      duration: TOTAL_DURATION_SECS * 1000,
      useNativeDriver: false,
    }).start();

    const timer = setInterval(() => {
      setSecondsLeft((s) => Math.max(0, s - 1));
    }, 1000);

    return () => clearInterval(timer);
  }, [progressAnim]);

  const minsLeft = Math.ceil(secondsLeft / 60);

  return (
    <View style={styles.container}>
      <MapView
        style={StyleSheet.absoluteFillObject}
        provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
        initialRegion={{
          ...BENGALURU_REGION,
          latitude: 13.07,
          longitude: 77.583,
          latitudeDelta: 0.06,
          longitudeDelta: 0.06,
        }}
      >
        <Polyline
          coordinates={MOCK_ROUTE}
          strokeColor={COLORS.primary}
          strokeWidth={4}
        />
        <Marker coordinate={MOCK_ROUTE[0]}>
          <View style={styles.driverMarker}>
            <Text style={{ fontSize: 22 }}>🛺</Text>
          </View>
        </Marker>
        <Marker coordinate={MOCK_ROUTE[MOCK_ROUTE.length - 1]} pinColor={COLORS.danger} />
      </MapView>

      <SafeAreaView edges={['bottom']} style={styles.card}>
        {/* Header */}
        <View style={styles.headerRow}>
          <Text style={styles.title}>On the way 🛺</Text>
          <Text style={styles.eta}>{minsLeft} min left</Text>
        </View>

        <Text style={styles.destination} numberOfLines={1}>
          {dropAddress} · {distance} km
        </Text>

        {/* Progress bar */}
        <View style={styles.progressWrap}>
          <View style={styles.progressLabels}>
            <Text style={styles.progressLabel}>
              {activeRide?.pickupAddress?.split(',')[0] ?? 'Jayanagar'}
            </Text>
            <Text style={styles.progressLabel}>
              {dropAddress.split(',')[0]}
            </Text>
          </View>
          <View style={styles.progressTrack}>
            <Animated.View
              style={[
                styles.progressFill,
                {
                  width: progressAnim.interpolate({
                    inputRange: [0, 1],
                    outputRange: ['5%', '95%'],
                  }),
                },
              ]}
            />
          </View>
        </View>

        {/* Message driver */}
        <View style={styles.messageRow}>
          <TouchableOpacity>
            <Ionicons name="call-outline" size={20} color={COLORS.muted} />
          </TouchableOpacity>
          <TextInput
            style={styles.messageInput}
            placeholder={`Message ${driverName}…`}
            placeholderTextColor={COLORS.muted}
            value={message}
            onChangeText={setMessage}
          />
          <TouchableOpacity>
            <Ionicons name="send" size={18} color={COLORS.primary} />
          </TouchableOpacity>
        </View>

        {/* Live location link */}
        <TouchableOpacity style={styles.liveRow}>
          <Ionicons name="location" size={14} color={COLORS.primary} />
          <Text style={styles.liveText}>Share live location with family</Text>
        </TouchableOpacity>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  driverMarker: {
    backgroundColor: COLORS.white,
    borderRadius: 20,
    padding: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 4,
  },
  card: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: COLORS.white,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 28,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    gap: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.1,
    shadowRadius: 16,
    elevation: 16,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  title: { fontSize: 20, fontWeight: '700', color: COLORS.text },
  eta: {
    fontSize: 13,
    fontWeight: '600',
    color: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 10,
  },
  destination: { fontSize: 13, color: COLORS.muted, marginTop: -4 },
  progressWrap: {
    backgroundColor: COLORS.card,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    gap: 6,
  },
  progressLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  progressLabel: { fontSize: 11, color: COLORS.muted },
  progressTrack: {
    height: 5,
    backgroundColor: COLORS.border,
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: COLORS.primary,
    borderRadius: 3,
  },
  messageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: COLORS.card,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 11,
  },
  messageInput: { flex: 1, fontSize: 14, color: COLORS.text },
  liveRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    justifyContent: 'center',
  },
  liveText: { fontSize: 12, color: COLORS.primary, fontWeight: '600' },
});
