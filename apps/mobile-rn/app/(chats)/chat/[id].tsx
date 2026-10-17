import { router, Stack, useLocalSearchParams } from "expo-router";
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { chats } from "../../../src/data";
import { useColors } from "../../../src/theme";
import { TOP, TopBar } from "../../../src/TopBar";

export default function ChatPage() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const chat = chats.find((x) => x.id === id) ?? chats[0]!;
  const c = useColors();
  const insets = useSafeAreaInsets();
  const ios = Platform.OS === "ios";
  const body = (
    <ScrollView contentInsetAdjustmentBehavior="automatic" style={{ backgroundColor: c.bg }} contentContainerStyle={[s.body, !ios && { paddingTop: insets.top + TOP + 12 }]}>
      {ios && <Stack.Screen options={{ title: chat.title }} />}
      <View style={[s.mine, { backgroundColor: c.bubble }]}><Text style={[s.text, { color: c.ink }]}>{chat.title}</Text></View>
      <Text style={[s.text, { color: c.ink }]}>{chat.last}</Text>
      <Text style={[s.at, { color: c.subtle }]}>{chat.at} · {chat.station}</Text>
    </ScrollView>
  );
  // iOS: the scrolling view is the page itself (see the chats' list).
  if (ios) return body;
  return (
    <View style={{ flex: 1, backgroundColor: c.bg }}>
      {body}
      {!ios && <TopBar title={chat.title} left={<Pressable hitSlop={10} style={{ padding: 8 }} onPress={() => router.back()}><Text style={{ color: c.ink, fontSize: 22 }}>‹</Text></Pressable>} />}
    </View>
  );
}

const s = StyleSheet.create({
  body: { padding: 16, gap: 14 },
  mine: { alignSelf: "flex-end", maxWidth: "80%", borderRadius: 18, paddingHorizontal: 14, paddingVertical: 9 },
  text: { fontSize: 16, lineHeight: 24 },
  at: { fontSize: 12 },
});
