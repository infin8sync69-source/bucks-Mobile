import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Platform,
} from 'react-native';
import MapView, { Polyline, PROVIDER_GOOGLE } from 'react-native-maps';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { CANCEL_REASONS_DRIVER, BENGALURU_REGION } from '@/constants/vehicles';

const MOCK_ROUTE = [
  { latitude: 13.09, longitude: 77.54 },
  { latitude: 13.085, longitude: 77.55 },
  { latitude: 13.08, longitude: 77.565 },
  { latitude: 13.075, longitude: 77.575 },
];

export default function CancelReason() {
  const [selected, setSelected] = useState<string | null>(null);

  const handleSelect = (reason: string) => {
    setSelected(reason);
    setTimeout(() => {
      router.replace('/(root)/(tabs)/home');
    }, 300);
  };

  return (
    <View style={styles.container}>
      <MapView
        style={styles.map}
        provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
        initialRegion={{
          ...BENGALURU_REGION,
          latitude: 13.08,
          longitude: 77.565,
        }}
      >
        <Polyline
          coordinates={MOCK_ROUTE}
          strokeColor={COLORS.primary}
          strokeWidth={3}
        />
      </MapView>

      <View style={styles.bottomCard}>
        <TouchableOpacity style={styles.backRow} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={20} color={COLORS.text} />
          <Text style={styles.backTitle}>Why do you want to cancel the ride</Text>
        </TouchableOpacity>

        {CANCEL_REASONS_DRIVER.map((reason) => (
          <TouchableOpacity
            key={reason}
            style={[
              styles.reasonRow,
              selected === reason && styles.reasonRowSelected,
            ]}
            onPress={() => handleSelect(reason)}
          >
            <Text style={styles.reasonText}>{reason}</Text>
          </TouchableOpacity>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  map: { flex: 1 },
  bottomCard: {
    backgroundColor: COLORS.white,
    paddingHorizontal: 16,
    paddingTop: 20,
    paddingBottom: 32,
    gap: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
    elevation: 12,
  },
  backRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginBottom: 8,
  },
  backTitle: {
    fontSize: 15,
    fontWeight: '700',
    color: COLORS.text,
    flex: 1,
  },
  reasonRow: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  reasonRowSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  reasonText: {
    fontSize: 14,
    color: COLORS.text,
  },
});
