export const VEHICLE_TYPES = [
  {
    id: 'car',
    label: 'Four Wheel',
    fareRange: '₹220–250',
    icon: require('../assets/icons/car.png'),
    dbType: 'car',
  },
  {
    id: 'auto',
    label: 'Three Wheel',
    fareRange: '₹120–135',
    icon: require('../assets/icons/map.png'),
    dbType: 'auto',
  },
  {
    id: 'bike',
    label: 'Two Wheel',
    fareRange: '₹60–85',
    icon: require('../assets/icons/point.png'),
    dbType: 'bike',
  },
] as const;

export const LISTING_MODES = ['Taxi', 'Auto', 'Bike Taxi', 'Rental'];

export const CANCEL_REASONS_DRIVER = [
  "Customer hasn't reached the location yet....",
  'The Drop-off location is too far',
  'Customer requested cancellation',
  'Incorrect pick-up location',
];

export const CANCEL_REASONS_CUSTOMER = [
  'Wrong pickup location',
  'Driver taking too long to arrive',
  'ETA keeps increasing',
  'Incorrect pick-up location',
];

export const VEHICLE_STATUS = {
  offline: { label: 'Offline', bg: '#E5E7EB', color: '#6B7280' },
  online: { label: 'Online', bg: '#D1FAE5', color: '#065F46' },
  taxi: { label: 'Taxi', bg: '#7C3AED', color: '#FFFFFF' },
  in_progress: { label: 'In Progress', bg: '#7C3AED', color: '#FFFFFF' },
};

export const TIP_AMOUNTS = [10, 20, 30, 50];

export const BENGALURU_REGION = {
  latitude: 13.0827,
  longitude: 77.5877,
  latitudeDelta: 0.0922,
  longitudeDelta: 0.0421,
};
