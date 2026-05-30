import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Animated,
  Platform,
  Alert,
} from 'react-native';
import MapView, { PROVIDER_GOOGLE } from 'react-native-maps';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';

import { COLORS } from '@/constants/theme';
import { BENGALURU_REGION } from '@/constants/vehicles';
import { useLocationStore } from '@/store';
import { useRideStore } from '@/store/rideStore';

const DOT_COUNT = 3;
const TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

export default function LocatingDriver() {
  const { userAddress } = useLocationStore();
  const { activeRide } = useRideStore();
  const [elapsed, setElapsed] = useState(0);

  // Animated broadcast dots
  const dotAnims = useRef(
    Array.from({ length: DOT_COUNT }, (_, i) =>
      new Animated.Value(0),
    ),
  ).current;

  const rippleScale = useRef(new Animated.Value(0.4)).current;
  const rippleOpacity = useRef(new Animated.Value(0.7)).current;

  useEffect(() => {
    // Ripple loop
    Animated.loop(
      Animated.parallel([
        Animated.sequence([
          Animated.timing(rippleScale, { toValue: 1.4, duration: 1800, useNativeDriver: true }),
          Animated.timing(rippleScale, { toValue: 0.4, duration: 0, useNativeDriver: true }),
        ]),
        Animated.sequence([
          Animated.timing(rippleOpacity, { toValue: 0, duration: 1800, useNativeDriver: true }),
          Animated.timing(rippleOpacity, { toValue: 0.7, duration: 0, useNativeDriver: true }),
        ]),
      ]),
    ).start();

    // Bouncing dots
    const dotSequences = dotAnims.map((anim, i) =>
      Animated.loop(
        Animated.sequence([
          Animated.delay(i * 200),
          Animated.timing(anim, { toValue: 1, duration: 400, useNativeDriver: true }),
          Animated.timing(anim, { toValue: 0, duration: 400, useNativeDriver: true }),
        ]),
      ),
    );
    dotSequences.forEach((seq) => seq.start());

    // Elapsed timer (display only)
    const timer = setInterval(() => setElapsed((e) => e + 1), 1000);

    // Timeout → no driver found
    const timeout = setTimeout(() => {
      router.replace('/(root)/no-driver');
    }, TIMEOUT_MS);

    return () => {
      clearInterval(timer);
      clearTimeout(timeout);
    };
  }, []);

  const formatElapsed = () => {
    const m = Math.floor(elapsed / 60);
    const s = elapsed % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  const handleCancel = () => {
    Alert.alert('Cancel Search', 'Stop looking for a driver?', [
      { text: 'Keep searching', style: 'cancel' },
      {
        text: 'Cancel',
        style: 'destructive',
        onPress: () => router.replace('/(root)/(tabs)/home'),
      },
    ]);
  };

  const region = {
    latitude: BENGALURU_REGION.latitude,
    longitude: BENGALURU_REGION.longitude,
    latitudeDelta: 0.02,
    longitudeDelta: 0.02,
  };

  return (
    <View style={styles.container}>
      {/* Map — top 42% */}
      <View style={styles.mapWrap}>
        <MapView
          style={StyleSheet.absoluteFillObject}
          provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
          initialRegion={region}
          scrollEnabled={false}
          zoomEnabled={false}
        />
        <Animated.View
          style={[
            styles.ripple,
            { transform: [{ scale: rippleScale }], opacity: rippleOpacity },
          ]}
          pointerEvents="none"
        />
      </View>

      {/* Bottom sheet */}
      <SafeAreaView edges={['bottom']} style={styles.sheet}>
        <View style={styles.spinnerRow}>
          <View style={styles.spinner} />
          <View>
            <Text style={styles.locatingTitle}>Locating your Driver</Text>
            <View style={styles.dotsRow}>
              {dotAnims.map((anim, i) => (
                <Animated.View
                  key={i}
                  style={[
                    styles.dot,
                    {
                      transform: [
                        {
                          translateY: anim.interpolate({
                            inputRange: [0, 1],
                            outputRange: [0, -5],
                          }),
                        },
                      ],
                    },
                  ]}
                />
              ))}
            </View>
          </View>
        </View>

        <View style={styles.pickupBox}>
          <View style={[styles.pickupDot, { backgroundColor: COLORS.success }]} />
          <Text style={styles.pickupText} numberOfLines={1}>
            {userAddress ?? 'TVS Synergy, Jayanagar 4th block, Bengaluru'}
          </Text>
        </View>

        <Text style={styles.broadcastText}>
          Broadcasting to nearby online drivers…
        </Text>
        <Text style={styles.elapsedText}>{formatElapsed()}</Text>

        <TouchableOpacity style={styles.cancelBtn} onPress={handleCancel}>
          <Text style={styles.cancelText}>Cancel Search</Text>
        </TouchableOpacity>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: COLORS.white },
  mapWrap: {
    height: '42%',
    position: 'relative',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  ripple: {
    position: 'absolute',
    width: 140,
    height: 140,
    borderRadius: 70,
    backgroundColor: 'rgba(124,58,237,0.18)',
  },
  sheet: {
    flex: 1,
    paddingHorizontal: 20,
    paddingTop: 24,
    gap: 14,
    alignItems: 'center',
  },
  spinnerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  spinner: {
    width: 44,
    height: 44,
    borderRadius: 22,
    borderWidth: 4,
    borderColor: COLORS.primaryLight,
    borderTopColor: COLORS.primary,
    // Note: CSS animation not available; in RN use Animated.loop
  },
  locatingTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: COLORS.text,
    marginBottom: 6,
  },
  dotsRow: {
    flexDirection: 'row',
    gap: 6,
    alignItems: 'flex-end',
    height: 16,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: COLORS.primary,
  },
  pickupBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    alignSelf: 'stretch',
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  pickupDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    flexShrink: 0,
  },
  pickupText: {
    fontSize: 13,
    color: COLORS.text,
    flex: 1,
  },
  broadcastText: {
    fontSize: 13,
    color: COLORS.muted,
    textAlign: 'center',
  },
  elapsedText: {
    fontSize: 12,
    color: COLORS.muted,
    fontVariant: ['tabular-nums'],
  },
  cancelBtn: {
    marginTop: 'auto',
    alignSelf: 'stretch',
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: COLORS.border,
  },
  cancelText: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.muted,
  },
});
