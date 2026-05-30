import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  Platform,
} from 'react-native';
import MapView, { Polyline, Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';

const MOCK_ROUTE = [
  { latitude: 13.075, longitude: 77.575 },
  { latitude: 13.068, longitude: 77.585 },
  { latitude: 13.06, longitude: 77.595 },
  { latitude: 13.055, longitude: 77.6 },
];

export default function GoDrop() {
  const [message, setMessage] = useState('');

  return (
    <View style={styles.container}>
      <MapView
        style={styles.map}
        provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
        initialRegion={{
          ...BENGALURU_REGION,
          latitude: 13.065,
          longitude: 77.588,
        }}
      >
        <Polyline
          coordinates={MOCK_ROUTE}
          strokeColor={COLORS.primary}
          strokeWidth={3}
        />
        <Marker coordinate={MOCK_ROUTE[0]} pinColor={COLORS.success} />
        <Marker coordinate={MOCK_ROUTE[MOCK_ROUTE.length - 1]} pinColor={COLORS.danger} />
      </MapView>

      <View style={styles.bottomCard}>
        <Text style={styles.customerName}>Customer Name</Text>
        <Text style={styles.eta}>25 mins{'  '}Drop: 5.4KM</Text>

        <View style={styles.messageRow}>
          <TouchableOpacity style={styles.phoneBtn}>
            <Ionicons name="call-outline" size={20} color={COLORS.muted} />
          </TouchableOpacity>
          <TextInput
            style={styles.messageInput}
            placeholder="Message your customer...."
            placeholderTextColor={COLORS.muted}
            value={message}
            onChangeText={setMessage}
          />
          <TouchableOpacity>
            <Ionicons name="send" size={18} color={COLORS.muted} />
          </TouchableOpacity>
        </View>

        <TouchableOpacity
          style={styles.primaryBtn}
          onPress={() => router.push('/(root)/collect-payment')}
        >
          <Text style={styles.primaryBtnText}>Go to Drop</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  map: { flex: 1 },
  bottomCard: {
    backgroundColor: COLORS.white,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 32,
    gap: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
    elevation: 12,
  },
  customerName: {
    fontSize: 20,
    fontWeight: '700',
    color: COLORS.text,
  },
  eta: {
    fontSize: 14,
    color: COLORS.muted,
    marginTop: -4,
  },
  messageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: COLORS.card,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  phoneBtn: { padding: 2 },
  messageInput: {
    flex: 1,
    fontSize: 14,
    color: COLORS.text,
  },
  primaryBtn: {
    backgroundColor: COLORS.primary,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: 'center',
    marginTop: 4,
  },
  primaryBtnText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
});
