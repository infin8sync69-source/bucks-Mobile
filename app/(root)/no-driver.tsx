import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { COLORS } from '@/constants/theme';

export default function NoDriver() {
  return (
    <SafeAreaView style={styles.container} edges={['top', 'bottom']}>
      <View style={styles.content}>
        <Text style={styles.emoji}>😔</Text>
        <Text style={styles.title}>No drivers nearby</Text>
        <Text style={styles.body}>
          All drivers in your area are offline or busy right now.{'\n'}
          Try again in a few minutes.
        </Text>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity
          style={styles.retryBtn}
          onPress={() => router.replace('/(root)/locating-driver')}
        >
          <Text style={styles.retryText}>Try Again</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.homeBtn}
          onPress={() => router.replace('/(root)/(tabs)/home')}
        >
          <Text style={styles.homeText}>Back to Home</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: COLORS.white },
  content: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
    gap: 14,
  },
  emoji: { fontSize: 56, marginBottom: 4 },
  title: {
    fontSize: 22,
    fontWeight: '700',
    color: COLORS.text,
    textAlign: 'center',
  },
  body: {
    fontSize: 14,
    color: COLORS.muted,
    textAlign: 'center',
    lineHeight: 22,
  },
  footer: {
    paddingHorizontal: 20,
    paddingBottom: 36,
    gap: 10,
  },
  retryBtn: {
    backgroundColor: COLORS.primary,
    borderRadius: 14,
    paddingVertical: 15,
    alignItems: 'center',
  },
  retryText: { color: COLORS.white, fontSize: 16, fontWeight: '700' },
  homeBtn: {
    borderRadius: 14,
    paddingVertical: 13,
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: COLORS.border,
  },
  homeText: { color: COLORS.primary, fontSize: 15, fontWeight: '600' },
});
