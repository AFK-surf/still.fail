// Android: a page's frosted top bar (ui/Glass.kt: the page's paper at 70% over a blur), with its name and actions.
import { BlurView } from "expo-blur";
import type { ReactNode } from "react";
import { StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useColors } from "./theme";

export const TOP = 52;

export function TopBar({ title, left, right }: { title: string; left?: ReactNode; right?: ReactNode }) {
  const c = useColors();
  const insets = useSafeAreaInsets();
  return (
    <BlurView experimentalBlurMethod="dimezisBlurView" intensity={60} tint={c.dark ? "dark" : "light"} style={[s.bar, { paddingTop: insets.top, height: insets.top + TOP }]}>
      <View style={[StyleSheet.absoluteFill, { backgroundColor: c.bg, opacity: 0.7 }]} />
      <View style={s.side}>{left}</View>
      <Text style={[s.title, { color: c.ink }]} numberOfLines={1}>{title}</Text>
      <View style={[s.side, { alignItems: "flex-end" }]}>{right}</View>
      <View style={[s.line, { backgroundColor: c.line }]} />
    </BlurView>
  );
}

const s = StyleSheet.create({
  bar: { position: "absolute", top: 0, left: 0, right: 0, flexDirection: "row", alignItems: "center", paddingHorizontal: 8, overflow: "hidden" },
  side: { width: 56, justifyContent: "center" },
  title: { flex: 1, textAlign: "center", fontSize: 17, fontWeight: "600" },
  line: { position: "absolute", left: 0, right: 0, bottom: 0, height: StyleSheet.hairlineWidth },
});
