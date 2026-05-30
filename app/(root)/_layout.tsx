import { Stack } from 'expo-router';

const Layout = () => {
  return (
    <Stack>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="manage-listings" options={{ headerShown: false }} />
      <Stack.Screen name="list-vehicle" options={{ headerShown: false }} />
      <Stack.Screen name="edit-vehicle" options={{ headerShown: false }} />
      <Stack.Screen name="find-ride" options={{ headerShown: false }} />
      <Stack.Screen name="confirm-pickup" options={{ headerShown: false }} />
      <Stack.Screen name="locating-driver" options={{ headerShown: false }} />
      <Stack.Screen name="no-driver" options={{ headerShown: false }} />
      <Stack.Screen name="driver-arriving" options={{ headerShown: false }} />
      <Stack.Screen name="active-ride" options={{ headerShown: false }} />
      <Stack.Screen name="payment" options={{ headerShown: false }} />
      <Stack.Screen name="go-pickup" options={{ headerShown: false }} />
      <Stack.Screen name="cancel-reason" options={{ headerShown: false }} />
      <Stack.Screen name="enter-pin" options={{ headerShown: false }} />
      <Stack.Screen name="go-drop" options={{ headerShown: false }} />
      <Stack.Screen name="collect-payment" options={{ headerShown: false }} />
      <Stack.Screen name="rating" options={{ headerShown: false }} />
    </Stack>
  );
};

export default Layout;
