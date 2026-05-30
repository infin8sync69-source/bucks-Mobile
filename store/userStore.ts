import { create } from 'zustand';

interface Vehicle {
  id: string;
  type: string;
  licensePlate: string;
  listingMode: string;
  docUrl: string | null;
  verified: boolean;
  status: 'offline' | 'online' | 'in_progress';
}

interface UserStore {
  name: string;
  title: string;
  phone: string;
  avatarInitials: string;
  vehicles: Vehicle[];
  setUser: (data: { name: string; title?: string; phone?: string }) => void;
  setVehicles: (vehicles: Vehicle[]) => void;
  addVehicle: (vehicle: Vehicle) => void;
  updateVehicleStatus: (vehicleId: string, status: Vehicle['status']) => void;
}

export const useUserStore = create<UserStore>((set, get) => ({
  name: 'John Doe',
  title: 'Software Engineer',
  phone: '',
  avatarInitials: 'JD',
  vehicles: [],
  setUser: (data) =>
    set({
      name: data.name,
      title: data.title ?? get().title,
      phone: data.phone ?? get().phone,
      avatarInitials: data.name
        .split(' ')
        .map((w) => w[0])
        .join('')
        .slice(0, 2)
        .toUpperCase(),
    }),
  setVehicles: (vehicles) => set({ vehicles }),
  addVehicle: (vehicle) =>
    set((state) => ({ vehicles: [...state.vehicles, vehicle] })),
  updateVehicleStatus: (vehicleId, status) =>
    set((state) => ({
      vehicles: state.vehicles.map((v) =>
        v.id === vehicleId ? { ...v, status } : v
      ),
    })),
}));
