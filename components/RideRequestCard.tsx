import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS } from '@/constants/theme';

interface RideRequest {
  id: string;
  vehicleType: string;
  fare: number;
  customerName?: string;
  pickupAddress: string;
  dropAddress: string;
  pickupDistance?: number;
  dropDistance?: number;
  customerInitials?: string;
}

interface RideRequestCardProps {
  ride: RideRequest;
  onAccept: () => void;
  onDismiss: () => void;
}

export default function RideRequestCard({
  ride,
  onAccept,
  onDismiss,
}: RideRequestCardProps) {
  const initials = ride.customerInitials ?? ride.customerName?.slice(0, 2).toUpperCase() ?? 'JD';

  return (
    <View style={styles.overlay}>
      <View style={styles.card}>
        <View style={styles.topRow}>
          <View style={styles.vehicleTag}>
            <Text style={styles.vehicleTagText}>{ride.vehicleType ?? 'Auto'}</Text>
          </View>
          <TouchableOpacity onPress={onDismiss}>
            <Ionicons name="close" size={20} color={COLORS.muted} />
          </TouchableOpacity>
        </View>

        <Text style={styles.fare}>₹{ride.fare}</Text>

        <View style={styles.avatarRow}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{initials}</Text>
          </View>
        </View>

        <View style={styles.addressBox}>
          <View style={styles.addressRow}>
            <View style={[styles.dot, { backgroundColor: COLORS.success }]} />
            <Text style={styles.addressText} numberOfLines={1}>
              {ride.pickupAddress}
            </Text>
          </View>
          <View style={styles.addressRow}>
            <View style={[styles.dot, { backgroundColor: COLORS.danger }]} />
            <Text style={styles.addressText} numberOfLines={1}>
              {ride.dropAddress}
            </Text>
          </View>
        </View>

        <View style={styles.distRow}>
          <Text style={styles.distText}>
            Pickup: <Text style={styles.distBold}>{ride.pickupDistance ?? 200}m</Text>
          </Text>
          <Text style={styles.distText}>
            Drop: <Text style={styles.distBold}>{ride.dropDistance ?? 5}km</Text>
          </Text>
        </View>

        <TouchableOpacity style={styles.acceptBtn} onPress={onAccept}>
          <Text style={styles.acceptText}>Accept</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 70,
    paddingHorizontal: 16,
  },
  card: {
    backgroundColor: COLORS.white,
    borderRadius: 16,
    padding: 16,
    borderWidth: 1.5,
    borderColor: COLORS.primary,
    borderStyle: 'dashed',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 8,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  vehicleTag: {
    backgroundColor: COLORS.primaryLight,
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 20,
  },
  vehicleTagText: {
    color: COLORS.primary,
    fontWeight: '600',
    fontSize: 13,
  },
  fare: {
    fontSize: 26,
    fontWeight: '800',
    color: COLORS.text,
    marginBottom: 10,
  },
  avatarRow: {
    marginBottom: 12,
  },
  avatar: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: COLORS.white,
    fontWeight: '700',
    fontSize: 14,
  },
  addressBox: {
    backgroundColor: COLORS.card,
    borderRadius: 10,
    padding: 10,
    gap: 8,
    marginBottom: 10,
  },
  addressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  addressText: {
    fontSize: 13,
    color: COLORS.text,
    flex: 1,
  },
  distRow: {
    flexDirection: 'row',
    gap: 20,
    marginBottom: 14,
  },
  distText: {
    fontSize: 13,
    color: COLORS.muted,
  },
  distBold: {
    fontWeight: '700',
    color: COLORS.text,
  },
  acceptBtn: {
    backgroundColor: COLORS.primary,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  acceptText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
});
