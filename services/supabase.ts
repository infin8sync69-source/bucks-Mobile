import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';

const ExpoSecureStoreAdapter = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: ExpoSecureStoreAdapter,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});

export type Database = {
  public: {
    Tables: {
      users: {
        Row: {
          id: string;
          clerk_id: string;
          phone: string;
          name: string;
          title: string | null;
          avatar_url: string | null;
          created_at: string;
        };
        Insert: Omit<Database['public']['Tables']['users']['Row'], 'created_at'>;
      };
      vehicles: {
        Row: {
          id: string;
          user_id: string;
          type: string;
          license_plate: string;
          listing_mode: string;
          doc_url: string | null;
          verified: boolean;
          status: 'offline' | 'online' | 'in_progress';
          created_at: string;
        };
        Insert: Omit<Database['public']['Tables']['vehicles']['Row'], 'id' | 'created_at' | 'verified' | 'status'>;
      };
      rides: {
        Row: {
          id: string;
          customer_id: string;
          driver_id: string | null;
          vehicle_id: string | null;
          vehicle_type: string;
          pickup_lat: number;
          pickup_lng: number;
          pickup_address: string;
          drop_lat: number;
          drop_lng: number;
          drop_address: string;
          fare: number;
          pin_code: string;
          status: 'searching' | 'accepted' | 'pickup' | 'active' | 'done' | 'cancelled';
          cancel_reason: string | null;
          created_at: string;
        };
      };
      driver_locations: {
        Row: {
          user_id: string;
          lat: number;
          lng: number;
          heading: number | null;
          updated_at: string;
        };
      };
    };
  };
};
