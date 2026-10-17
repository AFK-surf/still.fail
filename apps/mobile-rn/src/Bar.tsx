// The bottom bar as the Android app draws it (ui/Bar.kt, simplified): a floating frosted capsule of the places, and a
// frosted ball over the place shown that travels there on a spring.
import type { BottomTabBarProps } from "@react-navigation/bottom-tabs";
import { BlurView } from "expo-blur";
import * as Haptics from "expo-haptics";
import { useEffect, useRef } from "react";
import { Animated, Pressable, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Icon, type IconName } from "./Icon";
import { useColors } from "./theme";

const TRACK = 56;
const INSET = 6;
const PLACE = 68;
const icons: Record<string, IconName> = { "(chats)": "chats", files: "folder", profiles: "key", stations: "server" };

export function Bar({ state, navigation }: BottomTabBarProps) {
  const c = useColors();
  const insets = useSafeAreaInsets();
  const x = useRef(new Animated.Value(state.index)).current;
  useEffect(() => {
    Animated.spring(x, { toValue: state.index, useNativeDriver: true, stiffness: 380, damping: 30, mass: 1 }).start();
  }, [state.index]);
  // The bar steps aside on a page pushed over a place's first page (a chat opened from the list).
  const pushed = (state.routes[state.index]?.state?.index ?? 0) > 0;
  const width = state.routes.length * PLACE + INSET * 2;
  const ball = TRACK - INSET * 2;
  if (pushed) return null;
  return (
    <View pointerEvents="box-none" style={[s.wrap, { bottom: insets.bottom + 12 }]}>
      <View style={[s.shadow, { width, borderRadius: TRACK / 2 }]}>
        <BlurView experimentalBlurMethod="dimezisBlurView" intensity={60} tint={c.dark ? "dark" : "light"} style={[s.glass, { width, borderRadius: TRACK / 2 }]}>
          <View style={[StyleSheet.absoluteFill, { backgroundColor: c.raised, opacity: 0.72 }]} />
          <Animated.View
            style={[s.ball, { width: PLACE - 4, height: ball, borderRadius: ball / 2, backgroundColor: c.dark ? "#ffffff1a" : "#0000000d",
              transform: [{ translateX: x.interpolate({ inputRange: [0, 1], outputRange: [INSET + 2, INSET + 2 + PLACE] }) }] }]}
          />
          {state.routes.map((route, i) => {
            const on = state.index === i;
            return (
              <Pressable
                key={route.key}
                accessibilityRole="tab"
                accessibilityState={{ selected: on }}
                style={s.place}
                onPress={() => {
                  Haptics.selectionAsync();
                  if (!on) navigation.navigate(route.name);
                }}
              >
                <Icon name={icons[route.name] ?? "chats"} color={on ? c.accent : c.muted} />
              </Pressable>
            );
          })}
        </BlurView>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { position: "absolute", left: 0, right: 0, alignItems: "center" },
  shadow: { height: TRACK, elevation: 6, shadowColor: "#000", backgroundColor: "transparent" },
  glass: { height: TRACK, flexDirection: "row", paddingHorizontal: INSET, overflow: "hidden" },
  ball: { position: "absolute", top: INSET, left: 0 },
  place: { width: PLACE, height: TRACK, alignItems: "center", justifyContent: "center" },
});
