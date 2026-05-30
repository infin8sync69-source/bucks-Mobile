import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Platform,
  KeyboardAvoidingView,
} from 'react-native';
import MapView, { Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useRideStore } from '@/store/rideStore';

type PayMethod = 'cash' | 'upi';

export default function Payment() {
  const { activeRide } = useRideStore();
  const [method, setMethod] = useState<PayMethod>('cash');
  const [upiId, setUpiId] = useState('');

  const fare        = activeRide?.fare ?? 101;
  const dropAddress = activeRide?.dropAddress ?? 'Nexus Mall, Koramangala';

  const handlePay = () => {
    router.push('/(root)/rating');
  };

  const region = {
    latitude: BENGALURU_REGION.latitude - 0.02,
    longitude: BENGALURU_REGION.longitude + 0.02,
    latitudeDelta: 0.012,
    longitudeDelta: 0.012,
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      {/* Small map showing destination */}
      <View style={styles.mapWrap}>
        <MapView
          style={StyleSheet.absoluteFillObject}
          provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
          initialRegion={region}
          scrollEnabled={false}
          zoomEnabled={false}
        >
          <Marker coordinate={{ latitude: region.latitude, longitude: region.longitude }}
            pinColor={COLORS.danger}
          />
        </MapView>
        <View style={styles.arrivedBanner}>
          <Ionicons name="checkmark-circle" size={16} color={COLORS.success} />
          <Text style={styles.arrivedText}>Arrived at destination</Text>
        </View>
      </View>

      <SafeAreaView edges={['bottom']} style={styles.sheet}>
        {/* Fare */}
        <View style={styles.fareBlock}>
          <Text style={styles.fareAmount}>₹{fare}</Text>
          <Text style={styles.fareAddress} numberOfLines={1}>{dropAddress}</Text>
        </View>

        {/* Payment options */}
        <View style={styles.optionsWrap}>
          <TouchableOpacity
            style={[styles.option, method === 'cash' && styles.optionSelected]}
            onPress={() => setMethod('cash')}
          >
            <Ionicons
              name="cash-outline"
              size={22}
              color={method === 'cash' ? COLORS.primary : COLORS.muted}
            />
            <Text style={[styles.optionText, method === 'cash' && styles.optionTextSelected]}>
              Pay Cash
            </Text>
            {method === 'cash' && (
              <Ionicons name="checkmark-circle" size={20} color={COLORS.primary} style={styles.optionCheck} />
            )}
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.option, method === 'upi' && styles.optionSelected]}
            onPress={() => setMethod('upi')}
          >
            <Ionicons
              name="phone-portrait-outline"
              size={22}
              color={method === 'upi' ? COLORS.primary : COLORS.muted}
            />
            <Text style={[styles.optionText, method === 'upi' && styles.optionTextSelected]}>
              Pay via UPI
            </Text>
            {method === 'upi' && (
              <Ionicons name="checkmark-circle" size={20} color={COLORS.primary} style={styles.optionCheck} />
            )}
          </TouchableOpacity>

          {method === 'upi' && (
            <TextInput
              style={styles.upiInput}
              placeholder="e.g. 9876543210@paytm or name@upi"
              placeholderTextColor={COLORS.muted}
              value={upiId}
              onChangeText={setUpiId}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
            />
          )}
        </View>

        <TouchableOpacity style={styles.payBtn} onPress={handlePay}>
          <Text style={styles.payBtnText}>Pay ₹{fare}</Text>
        </TouchableOpacity>
      </SafeAreaView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: COLORS.white },
  mapWrap: {
    height: 200,
    position: 'relative',
  },
  arrivedBanner: {
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
  arrivedText: { fontSize: 13, fontWeight: '600', color: COLORS.success },
  sheet: {
    flex: 1,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 24,
    gap: 16,
  },
  fareBlock: { alignItems: 'center', gap: 4 },
  fareAmount: { fontSize: 44, fontWeight: '900', color: COLORS.text },
  fareAddress: { fontSize: 13, color: COLORS.muted },
  optionsWrap: { gap: 10 },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderWidth: 1.5,
    borderColor: COLORS.border,
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 14,
    backgroundColor: COLORS.white,
  },
  optionSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  optionText: { flex: 1, fontSize: 15, color: COLORS.muted, fontWeight: '500' },
  optionTextSelected: { color: COLORS.primary, fontWeight: '600' },
  optionCheck: { marginLeft: 'auto' },
  upiInput: {
    borderWidth: 1.5,
    borderColor: COLORS.border,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 14,
    color: COLORS.text,
    backgroundColor: COLORS.white,
  },
  payBtn: {
    marginTop: 'auto',
    backgroundColor: COLORS.primary,
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: 'center',
  },
  payBtnText: { color: COLORS.white, fontSize: 16, fontWeight: '700' },
});
