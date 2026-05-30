import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Alert,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';

import { COLORS } from '@/constants/theme';
import { LISTING_MODES } from '@/constants/vehicles';
import { useUserStore } from '@/store/userStore';

export default function ListVehicle() {
  const [vehicleType, setVehicleType] = useState('');
  const [licensePlate, setLicensePlate] = useState('');
  const [listingMode, setListingMode] = useState('');
  const [docUri, setDocUri] = useState<string | null>(null);
  const [showModeDropdown, setShowModeDropdown] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const { addVehicle } = useUserStore();

  const pickDocument = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.8,
    });
    if (!result.canceled) {
      setDocUri(result.assets[0].uri);
    }
  };

  const handleSubmit = async () => {
    if (!vehicleType.trim() || !licensePlate.trim() || !listingMode) {
      Alert.alert('Please fill all required fields');
      return;
    }
    setSubmitting(true);
    await new Promise((r) => setTimeout(r, 800));
    addVehicle({
      id: Date.now().toString(),
      type: vehicleType.toLowerCase().trim(),
      licensePlate: licensePlate.toUpperCase().trim(),
      listingMode,
      docUrl: docUri,
      verified: false,
      status: 'offline',
    });
    setSubmitting(false);
    router.back();
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView showsVerticalScrollIndicator={false}>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={COLORS.text} />
        </TouchableOpacity>

        <Text style={styles.title}>List your vehicle</Text>

        <View style={styles.form}>
          <Text style={styles.label}>Vehicle type</Text>
          <TextInput
            style={styles.input}
            placeholder="eg., Car, Auto"
            placeholderTextColor={COLORS.muted}
            value={vehicleType}
            onChangeText={setVehicleType}
            autoCapitalize="words"
          />

          <Text style={styles.label}>License Plate</Text>
          <TextInput
            style={styles.input}
            placeholder="eg., KA00XX0000"
            placeholderTextColor={COLORS.muted}
            value={licensePlate}
            onChangeText={setLicensePlate}
            autoCapitalize="characters"
          />

          <Text style={styles.label}>Listing Mode</Text>
          <TouchableOpacity
            style={styles.dropdown}
            onPress={() => setShowModeDropdown(!showModeDropdown)}
          >
            <Text style={listingMode ? styles.dropdownValue : styles.dropdownPlaceholder}>
              {listingMode || 'Select a Mode'}
            </Text>
            <Ionicons
              name={showModeDropdown ? 'chevron-up' : 'chevron-down'}
              size={18}
              color={COLORS.muted}
            />
          </TouchableOpacity>

          {showModeDropdown && (
            <View style={styles.dropdownList}>
              {LISTING_MODES.map((mode) => (
                <TouchableOpacity
                  key={mode}
                  style={styles.dropdownItem}
                  onPress={() => {
                    setListingMode(mode);
                    setShowModeDropdown(false);
                  }}
                >
                  <Text style={styles.dropdownItemText}>{mode}</Text>
                </TouchableOpacity>
              ))}
            </View>
          )}

          <Text style={styles.label}>Upload your documents</Text>
          <TouchableOpacity style={styles.uploadBox} onPress={pickDocument}>
            {docUri ? (
              <Ionicons name="checkmark-circle" size={32} color={COLORS.success} />
            ) : (
              <Ionicons name="add" size={32} color={COLORS.text} />
            )}
          </TouchableOpacity>
        </View>
      </ScrollView>

      <View style={styles.footer}>
        <TouchableOpacity
          style={[styles.submitBtn, submitting && { opacity: 0.7 }]}
          onPress={handleSubmit}
          disabled={submitting}
        >
          <Text style={styles.submitText}>
            {submitting ? 'Submitting...' : 'Submit and Verify'}
          </Text>
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
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: COLORS.text,
    paddingHorizontal: 16,
    marginBottom: 24,
    marginTop: 8,
  },
  form: {
    paddingHorizontal: 16,
    gap: 4,
  },
  label: {
    fontSize: 14,
    color: COLORS.muted,
    marginBottom: 6,
    marginTop: 16,
  },
  input: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 13,
    fontSize: 15,
    color: COLORS.text,
    backgroundColor: COLORS.white,
  },
  dropdown: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 13,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  dropdownPlaceholder: {
    color: COLORS.muted,
    fontSize: 15,
  },
  dropdownValue: {
    color: COLORS.text,
    fontSize: 15,
  },
  dropdownList: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 10,
    marginTop: 4,
    overflow: 'hidden',
  },
  dropdownItem: {
    paddingHorizontal: 14,
    paddingVertical: 13,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  dropdownItemText: {
    fontSize: 15,
    color: COLORS.text,
  },
  uploadBox: {
    width: 90,
    height: 90,
    borderRadius: 16,
    backgroundColor: COLORS.card,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 4,
  },
  footer: {
    paddingHorizontal: 16,
    paddingBottom: 32,
    paddingTop: 16,
  },
  submitBtn: {
    backgroundColor: COLORS.black,
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: 'center',
  },
  submitText: {
    color: COLORS.white,
    fontSize: 16,
    fontWeight: '700',
  },
});
