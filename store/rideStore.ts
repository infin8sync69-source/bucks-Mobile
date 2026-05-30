import { create } from 'zustand';

type RideStatus = 'idle' | 'searching' | 'accepted' | 'pickup' | 'active' | 'done' | 'cancelled';

interface ActiveRide {
  id: string;
  customerId: string;
  driverId: string | null;
  vehicleType: string;
  pickupLat: number;
  pickupLng: number;
  pickupAddress: string;
  dropLat: number;
  dropLng: number;
  dropAddress: string;
  fare: number;
  pinCode: string;
  status: RideStatus;
  customerName?: string;
  driverName?: string;
  eta?: number;
  distance?: number;
}

interface RideStore {
  activeRide: ActiveRide | null;
  incomingRequest: ActiveRide | null;
  isOnline: boolean;
  setActiveRide: (ride: ActiveRide | null) => void;
  setIncomingRequest: (ride: ActiveRide | null) => void;
  setOnline: (online: boolean) => void;
  updateRideStatus: (status: RideStatus) => void;
  clearRide: () => void;
}

export const useRideStore = create<RideStore>((set) => ({
  activeRide: null,
  incomingRequest: null,
  isOnline: false,
  setActiveRide: (ride) => set({ activeRide: ride }),
  setIncomingRequest: (request) => set({ incomingRequest: request }),
  setOnline: (online) => set({ isOnline: online }),
  updateRideStatus: (status) =>
    set((state) => ({
      activeRide: state.activeRide ? { ...state.activeRide, status } : null,
    })),
  clearRide: () => set({ activeRide: null, incomingRequest: null }),
}));
