import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';

const FARE = 101;

export default function CollectPayment() {
  const [receivedCash, setReceivedCash] = useState(false);

  const handleReceived = () => {
    router.push('/(root)/rating');
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <View style={styles.content}>
        <Text style={styles.fare}>₹{FARE}</Text>

        <View style={styles.qrBox}>
          {/* QR code placeholder */}
          <View style={styles.qrPlaceholder}>
            <Ionicons name="qr-code" size={120} color={COLORS.text} />
          </View>
        </View>

        <TouchableOpacity
          style={styles.cashRow}
          onPress={() => setReceivedCash(!receivedCash)}
        >
          <Ionicons
            name={receivedCash ? 'checkbox' : 'checkbox-outline'}
            size={22}
            color={COLORS.success}
          />
          <Text style={styles.cashText}>Receive Cash</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity
          style={styles.receivedBtn}
          onPress={handleReceived}
        >
          <Text style={styles.receivedText}>Received</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.white,
  },
  content: {
    flex: 1,
    alignItems: 'center',
    paddingTop: 48,
    paddingHorizontal: 20,
  },
  fare: {
    fontSize: 42,
    fontWeight: '800',
    color: COLORS.text,
    marginBottom: 28,
  },
  qrBox: {
    borderWidth: 1.5,
    borderColor: COLORS.border,
    borderRadius: 16,
    padding: 20,
    marginBottom: 24,
    alignItems: 'center',
  },
  qrPlaceholder: {
    width: 160,
    height: 160,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cashRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    alignSelf: 'stretch',
  },
  cashText: {
    fontSize: 15,
    color: COLORS.text,
    fontWeight: '500',
  },
  footer: {
    paddingHorizontal: 20,
    paddingBottom: 32,
  },
  receivedBtn: {
    backgroundColor: COLORS.success,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: 'center',
  },
  receivedText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
});
