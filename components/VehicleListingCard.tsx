import React from 'react';
import { View, Text, TouchableOpacity, Switch, StyleSheet, Image } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS } from '@/constants/theme';

interface Vehicle {
  id: string;
  type: string;
  model: string;
  licensePlate: string;
  listingMode: string;
  status: 'offline' | 'online' | 'in_progress';
}

interface VehicleListingCardProps {
  vehicle: Vehicle;
  onToggle: (id: string, isOnline: boolean) => void;
  onEdit: (id: string) => void;
}

const STATUS_TAG: Record<string, { label: string; bg: string; color: string }> = {
  online: { label: 'Taxi', bg: COLORS.primaryLight, color: COLORS.primary },
  in_progress: { label: 'In Progress', bg: COLORS.primaryLight, color: COLORS.primary },
  offline: { label: 'Offline', bg: COLORS.border, color: COLORS.muted },
};

export default function VehicleListingCard({
  vehicle,
  onToggle,
  onEdit,
}: VehicleListingCardProps) {
  const isOnline = vehicle.status === 'online';
  const tag = STATUS_TAG[vehicle.status] ?? STATUS_TAG.offline;

  return (
    <View style={styles.card}>
      <View style={styles.topRow}>
        <View style={styles.vehicleImageBox}>
          <Ionicons name="car-sport" size={32} color={COLORS.muted} />
        </View>

        <View style={styles.info}>
          <Text style={styles.model}>{vehicle.model}</Text>
          <Text style={styles.plate}>{vehicle.licensePlate}</Text>
        </View>

        <View style={[styles.statusTag, { backgroundColor: tag.bg }]}>
          <Text style={[styles.statusText, { color: tag.color }]}>{tag.label}</Text>
        </View>
      </View>

      <View style={styles.bottomRow}>
        {vehicle.status !== 'in_progress' ? (
          <View style={styles.toggleRow}>
            <Switch
              value={isOnline}
              onValueChange={(val) => onToggle(vehicle.id, val)}
              trackColor={{ false: COLORS.border, true: COLORS.success }}
              thumbColor={COLORS.white}
            />
            <Text style={styles.toggleLabel}>
              {isOnline ? 'Go offline' : 'Go online'}
            </Text>
          </View>
        ) : (
          <View style={styles.toggleRow} />
        )}

        <TouchableOpacity
          style={styles.editBtn}
          onPress={() => onEdit(vehicle.id)}
        >
          <Ionicons name="create-outline" size={16} color={COLORS.muted} />
          <Text style={styles.editText}>Edit</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
    backgroundColor: COLORS.white,
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 12,
  },
  vehicleImageBox: {
    width: 60,
    height: 52,
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.card,
  },
  info: {
    flex: 1,
  },
  model: {
    fontSize: 15,
    fontWeight: '700',
    color: COLORS.text,
  },
  plate: {
    fontSize: 13,
    color: COLORS.muted,
    marginTop: 2,
  },
  statusTag: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 20,
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
  },
  bottomRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flex: 1,
  },
  toggleLabel: {
    fontSize: 13,
    color: COLORS.muted,
  },
  editBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  editText: {
    fontSize: 13,
    color: COLORS.muted,
  },
});
