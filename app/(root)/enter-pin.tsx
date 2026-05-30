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

import PinInput from '@/components/PinInput';
import { COLORS } from '@/constants/theme';

const MOCK_PIN = '1234';

export default function EnterPin() {
  const [pin, setPin] = useState('');
  const [error, setError] = useState(false);

  const handlePinComplete = (enteredPin: string) => {
    setPin(enteredPin);
  };

  const handleConfirm = () => {
    if (pin === MOCK_PIN) {
      router.push('/(root)/go-drop');
    } else {
      setError(true);
      Alert.alert('Incorrect PIN', 'Please ask the customer for the correct PIN.');
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
        <Ionicons name="arrow-back" size={22} color={COLORS.text} />
      </TouchableOpacity>

      <View style={styles.content}>
        <Text style={styles.title}>Enter Customer's Pin</Text>
        <Text style={styles.subtitle}>
          Ask the customer for their 4-digit ride PIN
        </Text>

        <View style={styles.pinContainer}>
          <PinInput onComplete={handlePinComplete} />
        </View>

        {error && (
          <Text style={styles.errorText}>Incorrect PIN. Please try again.</Text>
        )}
      </View>

      <View style={styles.footer}>
        <TouchableOpacity
          style={[styles.confirmBtn, !pin && { opacity: 0.5 }]}
          onPress={handleConfirm}
          disabled={!pin}
        >
          <Text style={styles.confirmText}>Confirm Pin</Text>
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
  backBtn: {
    paddingHorizontal: 16,
    paddingTop: 10,
    paddingBottom: 4,
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
    paddingTop: 32,
    alignItems: 'center',
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: COLORS.muted,
    textAlign: 'center',
    marginBottom: 40,
  },
  pinContainer: {
    marginTop: 8,
  },
  errorText: {
    color: COLORS.danger,
    fontSize: 13,
    marginTop: 16,
  },
  footer: {
    paddingHorizontal: 20,
    paddingBottom: 32,
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
