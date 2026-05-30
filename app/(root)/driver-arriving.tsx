import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Platform,
} from 'react-native';
import MapView, { Polyline, Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useRideStore } from '@/store/rideStore';

const MOCK_ROUTE = [
  { latitude: 13.095, longitude: 77.535 },
  { latitude: 13.09,  longitude: 77.548 },
  { latitude: 13.085, longitude: 77.558 },
  { latitude: 13.082, longitude: 77.568 },
];

export default function DriverArriving() {
  const { activeRide } = useRideStore();
  const [message, setMessage] = useState('');

  const driverName = activeRide?.driverName ?? 'John D.';
  const fare       = activeRide?.fare ?? 101;
  const pinCode    = activeRide?.pinCode ?? '3016';
  const eta        = activeRide?.eta ?? 4;

  return (
    <View style={styles.container}>
      <MapView
        style={StyleSheet.absoluteFillObject}
        provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
        initialRegion={{
          ...BENGALURU_REGION,
          latitude: 13.087,
          longitude: 77.552,
          latitudeDelta: 0.04,
          longitudeDelta: 0.04,
        }}
      >
        <Polyline
          coordinates={MOCK_ROUTE}
          strokeColor={COLORS.primary}
          strokeWidth={3}
          lineDashPattern={[6, 3]}
        />
        {/* Driver position */}
        <Marker coordinate={MOCK_ROUTE[0]}>
          <View style={styles.driverMarker}>
            <Text style={styles.driverMarkerText}>🛺</Text>
          </View>
        </Marker>
        {/* Customer position */}
        <Marker coordinate={MOCK_ROUTE[MOCK_ROUTE.length - 1]}>
          <View style={styles.customerMarker}>
            <View style={styles.customerMarkerDot} />
          </View>
        </Marker>
      </MapView>

      <SafeAreaView edges={['bottom']} style={styles.card}>
        {/* ETA row */}
        <View style={styles.etaRow}>
          <View>
            <Text style={styles.etaLabel}>Driver on the way</Text>
            <Text style={styles.etaValue}>{eta} mins · Pickup: 200m</Text>
          </View>
          <View style={[styles.statusPill, { backgroundColor: COLORS.primaryLight }]}>
            <Text style={[styles.statusPillText, { color: COLORS.primary }]}>Auto</Text>
          </View>
        </View>

        {/* Driver chip */}
        <View style={styles.driverChip}>
          <View style={styles.driverAvatar}>
            <Text style={styles.driverAvatarText}>JD</Text>
          </View>
          <View style={styles.driverInfo}>
            <Text style={styles.driverName}>{driverName} · Auto</Text>
            <Text style={styles.driverPlate}>AB00AB0000</Text>
          </View>
          <View style={styles.fareTag}>
            <Text style={styles.fareTagLabel}>Fare</Text>
            <Text style={styles.fareTagValue}>₹{fare}</Text>
          </View>
        </View>

        {/* Message row */}
        <View style={styles.messageRow}>
          <TouchableOpacity>
            <Ionicons name="call-outline" size={20} color={COLORS.muted} />
          </TouchableOpacity>
          <TextInput
            style={styles.messageInput}
            placeholder="Message your driver…"
            placeholderTextColor={COLORS.muted}
            value={message}
            onChangeText={setMessage}
          />
          <TouchableOpacity>
            <Ionicons name="send" size={18} color={COLORS.primary} />
          </TouchableOpacity>
        </View>

        {/* PIN display */}
        <View style={styles.pinBox}>
          <View>
            <Text style={styles.pinLabel}>Your ride PIN</Text>
            <Text style={styles.pinDigits}>{pinCode}</Text>
          </View>
          <Text style={styles.pinHint}>
            Share with driver{'\n'}when they arrive
          </Text>
        </View>
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
  driverMarkerText: { fontSize: 22 },
  customerMarker: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: COLORS.primary + '33',
    alignItems: 'center',
    justifyContent: 'center',
  },
  customerMarkerDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: COLORS.primary,
  },
  card: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: COLORS.white,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 24,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    gap: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.1,
    shadowRadius: 16,
    elevation: 16,
  },
  etaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  etaLabel: { fontSize: 18, fontWeight: '700', color: COLORS.text },
  etaValue: { fontSize: 13, color: COLORS.muted, marginTop: 2 },
  statusPill: {
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 20,
  },
  statusPillText: { fontSize: 12, fontWeight: '700' },
  driverChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: COLORS.card,
    borderRadius: 14,
    padding: 12,
  },
  driverAvatar: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  driverAvatarText: { color: COLORS.white, fontWeight: '700', fontSize: 14 },
  driverInfo: { flex: 1 },
  driverName: { fontSize: 14, fontWeight: '700', color: COLORS.text },
  driverPlate: { fontSize: 12, color: COLORS.muted, marginTop: 2 },
  fareTag: { alignItems: 'flex-end' },
  fareTagLabel: { fontSize: 10, color: COLORS.muted },
  fareTagValue: { fontSize: 16, fontWeight: '800', color: COLORS.primary },
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
  pinBox: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: COLORS.primaryLight,
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  pinLabel: { fontSize: 11, color: COLORS.muted, marginBottom: 2 },
  pinDigits: {
    fontSize: 26,
    fontWeight: '900',
    letterSpacing: 10,
    color: COLORS.primary,
    fontVariant: ['tabular-nums'],
  },
  pinHint: { fontSize: 11, color: COLORS.muted, textAlign: 'right', lineHeight: 17 },
});
