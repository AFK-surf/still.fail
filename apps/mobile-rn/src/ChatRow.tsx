// One chat of the list, the same on both platforms: title, its last message, time and station.
import { Pressable, StyleSheet, Text, View } from "react-native";
import type { Chat } from "./data";
import { useColors } from "./theme";

export function ChatRow({ chat, onPress }: { chat: Chat; onPress: () => void }) {
  const c = useColors();
  return (
    <Pressable onPress={onPress} android_ripple={{ color: c.line }} style={({ pressed }) => [s.row, pressed && process.env.EXPO_OS === "ios" && { backgroundColor: c.line }]}>
      <View style={s.top}>
        <Text style={[s.title, { color: c.ink }]} numberOfLines={1}>{chat.title}</Text>
        <Text style={[s.at, { color: c.subtle }]}>{chat.at}</Text>
      </View>
      <View style={s.top}>
        <Text style={[s.last, { color: c.muted }]} numberOfLines={1}>{chat.last}</Text>
        {chat.busy ? <View style={[s.dot, { backgroundColor: c.green }]} /> : chat.unread ? <View style={[s.dot, { backgroundColor: c.accent }]} /> : null}
      </View>
    </Pressable>
  );
}

const s = StyleSheet.create({
  row: { paddingHorizontal: 16, paddingVertical: 10, gap: 3 },
  top: { flexDirection: "row", alignItems: "center", gap: 8 },
  title: { flex: 1, fontSize: 16, fontWeight: "500" },
  at: { fontSize: 12, fontVariant: ["tabular-nums"] },
  last: { flex: 1, fontSize: 14 },
  dot: { width: 8, height: 8, borderRadius: 4 },
});
