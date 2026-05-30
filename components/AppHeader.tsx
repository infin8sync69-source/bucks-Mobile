import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS } from '@/constants/theme';

interface AppHeaderProps {
  onMenuPress: () => void;
  chatBadge?: number;
}

export default function AppHeader({ onMenuPress, chatBadge = 0 }: AppHeaderProps) {
  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={onMenuPress} style={styles.menuBtn}>
        <Ionicons name="menu" size={24} color={COLORS.text} />
      </TouchableOpacity>

      <Text style={styles.logo}>bucks</Text>

      <TouchableOpacity style={styles.chatBtn}>
        <Ionicons name="chatbubble-ellipses-outline" size={22} color={COLORS.text} />
        {chatBadge > 0 && (
          <View style={styles.badge}>
            <Text style={styles.badgeText}>{chatBadge > 99 ? '99+' : chatBadge}</Text>
          </View>
        )}
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: COLORS.white,
  },
  menuBtn: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logo: {
    fontSize: 22,
    fontWeight: '800',
    fontStyle: 'italic',
    color: COLORS.primary,
    letterSpacing: -0.5,
  },
  chatBtn: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badge: {
    position: 'absolute',
    top: -4,
    right: -4,
    backgroundColor: COLORS.primary,
    borderRadius: 8,
    minWidth: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
  },
  badgeText: {
    color: COLORS.white,
    fontSize: 9,
    fontWeight: '700',
  },
});
