// The chats' pages: on iOS the system's navigation bar (large title, Liquid Glass, edge swipe back); on Android
// still.fail's own frosted top bar, drawn by each page.
import { Stack } from "expo-router";
import { Platform, Pressable } from "react-native";
import { Icon } from "../../src/Icon";
import { useColors } from "../../src/theme";

export default function ChatsLayout() {
  const c = useColors();
  const ios = Platform.OS === "ios";
  return (
    <Stack
      screenOptions={{
        headerShown: ios,
        headerTransparent: ios,
        headerTintColor: c.accent,
        headerTitleStyle: { color: c.ink },
        contentStyle: { backgroundColor: c.bg },
        animation: ios ? "default" : "slide_from_right",
      }}
    >
      <Stack.Screen
        name="index"
        options={{
          title: "对话",
          headerLargeTitle: true,
          headerLargeTitleShadowVisible: false,
          headerLeft: () => <Pressable hitSlop={10} style={{ padding: 8 }}><Icon name="settings" color={c.accent} size={22} /></Pressable>,
          headerRight: () => <Pressable hitSlop={10} style={{ padding: 8 }}><Icon name="plus" color={c.accent} size={22} /></Pressable>,
        }}
      />
      <Stack.Screen name="chat/[id]" options={{ title: "", headerLargeTitle: false }} />
    </Stack>
  );
}
