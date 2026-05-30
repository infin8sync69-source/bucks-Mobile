import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

import VehicleListingCard from '@/components/VehicleListingCard';
import { COLORS } from '@/constants/theme';
import { useUserStore } from '@/store/userStore';

export default function ManageListings() {
  const { vehicles, updateVehicleStatus } = useUserStore();

  const handleToggle = (id: string, isOnline: boolean) => {
    updateVehicleStatus(id, isOnline ? 'online' : 'offline');
  };

  const handleEdit = (id: string) => {
    router.push('/(root)/edit-vehicle');
  };

  const isEmpty = vehicles.length === 0;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={COLORS.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Manage Listings</Text>
        <View style={{ width: 22 }} />
      </View>

      <View style={styles.tabs}>
        <View style={styles.tabActive}>
          <Text style={styles.tabTextActive}>Vehicles</Text>
        </View>
      </View>

      {isEmpty ? (
        <TouchableOpacity
          style={styles.emptyContainer}
          onPress={() => router.push('/(root)/list-vehicle')}
        >
          <View style={styles.addCircle}>
            <Ionicons name="add" size={40} color={COLORS.text} />
          </View>
          <Text style={styles.addLabel}>Add Vehicle</Text>
        </TouchableOpacity>
      ) : (
        <ScrollView
          contentContainerStyle={styles.list}
          showsVerticalScrollIndicator={false}
        >
          {vehicles.map((v) => (
            <VehicleListingCard
              key={v.id}
              vehicle={{
                id: v.id,
                type: v.type,
                model: v.type === 'car' ? 'Honda City' : v.type === 'auto' ? 'Auto' : 'Bike',
                licensePlate: v.licensePlate,
                listingMode: v.listingMode,
                status: v.status,
              }}
              onToggle={handleToggle}
              onEdit={handleEdit}
            />
          ))}
        </ScrollView>
      )}

      {!isEmpty && (
        <TouchableOpacity
          style={styles.fab}
          onPress={() => router.push('/(root)/list-vehicle')}
        >
          <Ionicons name="add" size={24} color={COLORS.muted} />
        </TouchableOpacity>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.white,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
    color: COLORS.text,
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  tabActive: {
    paddingBottom: 10,
    borderBottomWidth: 2,
    borderBottomColor: COLORS.primary,
  },
  tabTextActive: {
    fontSize: 15,
    fontWeight: '600',
    color: COLORS.text,
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  addCircle: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: '#F3F4F6',
    alignItems: 'center',
    justifyContent: 'center',
  },
  addLabel: {
    fontSize: 14,
    color: COLORS.muted,
  },
  list: {
    padding: 16,
    paddingBottom: 100,
  },
  fab: {
    position: 'absolute',
    bottom: 24,
    right: 20,
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#E5E7EB',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
