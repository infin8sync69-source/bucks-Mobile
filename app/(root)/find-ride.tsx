import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { VEHICLE_TYPES } from '@/constants/vehicles';

const FREQUENTLY_VISITED = [
  { id: '1', name: 'Maruthi Residency', address: '5th Main Rd, Jayanagar, Bengaluru' },
  { id: '2', name: 'Castle Layout', address: 'Castle Layout, Kasturinagar, Bengaluru' },
  { id: '3', name: 'TVS Synergy', address: 'Jayanagar 4th block, Bengaluru' },
];

export default function FindRide() {
  const [selectedVehicle, setSelectedVehicle] = useState<string | null>(null);

  const handleConfirm = () => {
    if (selectedVehicle) {
      router.push('/(root)/(tabs)/home');
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
        <Ionicons name="arrow-back" size={22} color={COLORS.text} />
      </TouchableOpacity>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scroll}>
        <Text style={styles.sectionLabel}>Frequently Visited</Text>

        {FREQUENTLY_VISITED.map((place) => (
          <TouchableOpacity key={place.id} style={styles.placeRow}>
            <View style={styles.placeIcon}>
              <Ionicons name="location-outline" size={18} color={COLORS.muted} />
            </View>
            <View style={styles.placeInfo}>
              <Text style={styles.placeName}>{place.name}</Text>
              <Text style={styles.placeAddr} numberOfLines={1}>{place.address}</Text>
            </View>
          </TouchableOpacity>
        ))}

        <TouchableOpacity style={styles.savedRow}>
          <View style={styles.savedIcon}>
            <Ionicons name="bookmark-outline" size={18} color={COLORS.warning} />
          </View>
          <Text style={styles.savedText}>Saved Places</Text>
        </TouchableOpacity>

        <Text style={[styles.sectionLabel, { marginTop: 20 }]}>Choose Vehicle</Text>

        {VEHICLE_TYPES.map((v) => (
          <TouchableOpacity
            key={v.id}
            style={[
              styles.vehicleRow,
              selectedVehicle === v.id && styles.vehicleRowSelected,
            ]}
            onPress={() => setSelectedVehicle(v.id)}
          >
            <View style={styles.vehicleIconBox}>
              <Ionicons
                name={
                  v.id === 'car' ? 'car-sport' :
                  v.id === 'auto' ? 'car-outline' : 'bicycle'
                }
                size={28}
                color={selectedVehicle === v.id ? COLORS.primary : COLORS.muted}
              />
            </View>
            <View style={styles.vehicleInfo}>
              <Text style={styles.vehicleLabel}>{v.label}</Text>
              <Text style={styles.vehicleFare}>{v.fareRange}</Text>
            </View>
            {selectedVehicle === v.id && (
              <Ionicons name="checkmark-circle" size={22} color={COLORS.primary} />
            )}
          </TouchableOpacity>
        ))}
      </ScrollView>

      <View style={styles.footer}>
        <TouchableOpacity
          style={[styles.confirmBtn, !selectedVehicle && { opacity: 0.5 }]}
          onPress={handleConfirm}
          disabled={!selectedVehicle}
        >
          <Text style={styles.confirmText}>Confirm</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: COLORS.white },
  backBtn: {
    paddingHorizontal: 16,
    paddingTop: 10,
    paddingBottom: 4,
  },
  scroll: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  sectionLabel: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
    marginBottom: 10,
    marginTop: 8,
  },
  placeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  placeIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: COLORS.card,
    alignItems: 'center',
    justifyContent: 'center',
  },
  placeInfo: { flex: 1 },
  placeName: { fontSize: 14, fontWeight: '600', color: COLORS.text },
  placeAddr: { fontSize: 12, color: COLORS.muted, marginTop: 2 },
  savedRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 12,
  },
  savedIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#FEF3C7',
    alignItems: 'center',
    justifyContent: 'center',
  },
  savedText: { fontSize: 14, fontWeight: '600', color: COLORS.text },
  vehicleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 14,
    paddingHorizontal: 14,
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    marginBottom: 10,
  },
  vehicleRowSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  vehicleIconBox: {
    width: 48,
    height: 48,
    borderRadius: 10,
    backgroundColor: COLORS.card,
    alignItems: 'center',
    justifyContent: 'center',
  },
  vehicleInfo: { flex: 1 },
  vehicleLabel: { fontSize: 15, fontWeight: '700', color: COLORS.text },
  vehicleFare: { fontSize: 13, color: COLORS.muted, marginTop: 2 },
  footer: { paddingHorizontal: 16, paddingBottom: 32, paddingTop: 12 },
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
