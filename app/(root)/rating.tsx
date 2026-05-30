import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { TIP_AMOUNTS } from '@/constants/vehicles';

export default function Rating() {
  const [stars, setStars] = useState(0);
  const [selectedTip, setSelectedTip] = useState<number | null>(null);

  const handleSubmit = () => {
    router.replace('/(root)/(tabs)/home');
  };

  const handleSkip = () => {
    router.replace('/(root)/(tabs)/home');
  };

  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <View style={styles.content}>
        <View style={styles.avatarCircle}>
          <Ionicons name="person" size={32} color={COLORS.white} />
        </View>

        <Text style={styles.title}>Recommend</Text>

        <View style={styles.starsRow}>
          {[1, 2, 3, 4, 5].map((i) => (
            <TouchableOpacity key={i} onPress={() => setStars(i)}>
              <Ionicons
                name={i <= stars ? 'star' : 'star-outline'}
                size={34}
                color={i <= stars ? COLORS.warning : COLORS.border}
              />
            </TouchableOpacity>
          ))}
        </View>

        <View style={styles.tipRow}>
          {TIP_AMOUNTS.map((amount) => (
            <TouchableOpacity
              key={amount}
              style={[
                styles.tipBtn,
                selectedTip === amount && styles.tipBtnSelected,
              ]}
              onPress={() => setSelectedTip(selectedTip === amount ? null : amount)}
            >
              <Text
                style={[
                  styles.tipText,
                  selectedTip === amount && styles.tipTextSelected,
                ]}
              >
                ₹{amount}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity style={styles.submitBtn} onPress={handleSubmit}>
          <Text style={styles.submitText}>Submit</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.skipBtn} onPress={handleSkip}>
          <Text style={styles.skipText}>Skip</Text>
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
    paddingTop: 60,
    paddingHorizontal: 24,
  },
  avatarCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: 24,
  },
  starsRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 32,
  },
  tipRow: {
    flexDirection: 'row',
    gap: 10,
  },
  tipBtn: {
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 20,
  },
  tipBtnSelected: {
    borderColor: COLORS.primary,
    backgroundColor: COLORS.primaryLight,
  },
  tipText: {
    fontSize: 14,
    color: COLORS.muted,
  },
  tipTextSelected: {
    color: COLORS.primary,
    fontWeight: '600',
  },
  footer: {
    paddingHorizontal: 20,
    paddingBottom: 32,
    gap: 10,
  },
  submitBtn: {
    backgroundColor: COLORS.primary,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: 'center',
  },
  submitText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
  skipBtn: {
    alignItems: 'center',
    paddingVertical: 10,
  },
  skipText: {
    color: COLORS.muted,
    fontSize: 15,
  },
});
