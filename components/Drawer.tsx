import React, { useEffect, useRef } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  Animated,
  StyleSheet,
  Dimensions,
  TouchableWithoutFeedback,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { COLORS } from '@/constants/theme';
import { useUserStore } from '@/store/userStore';

const { width } = Dimensions.get('window');
const DRAWER_WIDTH = width * 0.72;

interface DrawerProps {
  visible: boolean;
  onClose: () => void;
}

export default function Drawer({ visible, onClose }: DrawerProps) {
  const slideAnim = useRef(new Animated.Value(-DRAWER_WIDTH)).current;
  const { name, title, avatarInitials } = useUserStore();

  useEffect(() => {
    Animated.timing(slideAnim, {
      toValue: visible ? 0 : -DRAWER_WIDTH,
      duration: 260,
      useNativeDriver: true,
    }).start();
  }, [visible]);

  const handleManageListings = () => {
    onClose();
    router.push('/(root)/manage-listings');
  };

  const handleManageId = () => {
    onClose();
  };

  const handleAccountSettings = () => {
    onClose();
  };

  const handleLogout = () => {
    onClose();
  };

  if (!visible) return null;

  return (
    <View style={StyleSheet.absoluteFill}>
      <TouchableWithoutFeedback onPress={onClose}>
        <View style={styles.overlay} />
      </TouchableWithoutFeedback>

      <Animated.View
        style={[styles.drawer, { transform: [{ translateX: slideAnim }] }]}
      >
        <View style={styles.header}>
          <Text style={styles.title}>Manage Accounts</Text>
          <TouchableOpacity onPress={onClose}>
            <Ionicons name="arrow-back" size={22} color={COLORS.primary} />
          </TouchableOpacity>
        </View>

        <View style={styles.divider} />

        <TouchableOpacity style={styles.menuItem} onPress={handleManageId}>
          <Ionicons name="person-circle-outline" size={22} color={COLORS.muted} />
          <Text style={styles.menuText}>Manage ID</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.menuItem, styles.menuItemActive]}
          onPress={handleManageListings}
        >
          <Ionicons name="archive" size={22} color={COLORS.primary} />
          <Text style={[styles.menuText, { color: COLORS.primary, fontWeight: '600' }]}>
            Manage Listings
          </Text>
        </TouchableOpacity>

        <View style={styles.spacer} />

        <View style={styles.divider} />

        <TouchableOpacity style={styles.menuItem} onPress={handleAccountSettings}>
          <Ionicons name="settings-outline" size={22} color={COLORS.muted} />
          <Text style={styles.menuText}>Account Settings</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.menuItem} onPress={handleLogout}>
          <Ionicons name="log-out-outline" size={22} color={COLORS.muted} />
          <Text style={styles.menuText}>Logout</Text>
        </TouchableOpacity>

        <View style={styles.divider} />

        <View style={styles.userCard}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{avatarInitials}</Text>
          </View>
          <View>
            <Text style={styles.userName}>{name}</Text>
            <Text style={styles.userTitle}>{title}</Text>
          </View>
        </View>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
  drawer: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: DRAWER_WIDTH,
    backgroundColor: COLORS.white,
    paddingTop: 52,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingBottom: 16,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.primary,
  },
  divider: {
    height: 1,
    backgroundColor: COLORS.border,
    marginHorizontal: 0,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 20,
    paddingVertical: 14,
  },
  menuItemActive: {
    backgroundColor: COLORS.primaryLight,
    marginHorizontal: 8,
    borderRadius: 10,
  },
  menuText: {
    fontSize: 15,
    color: COLORS.muted,
  },
  spacer: {
    flex: 1,
  },
  userCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: COLORS.primaryLight,
  },
  avatar: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: COLORS.white,
    fontWeight: '700',
    fontSize: 15,
  },
  userName: {
    fontSize: 15,
    fontWeight: '700',
    color: COLORS.text,
  },
  userTitle: {
    fontSize: 12,
    color: COLORS.muted,
    marginTop: 1,
  },
});
