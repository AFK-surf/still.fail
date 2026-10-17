// The search at the top of the home lists (web mobile/Home.tsx SearchField, SearchPage): a field there once a list is
// scrolled to its top; tapped, the list goes up and away with the bars, the field comes up from where it was to the
// top (narrowing as 取消 comes in beside it), and under it the chats the words find (the core's `chatSearch`, as ⌘K's on
// the wide screen), then the messages that have them, newest first, each opening its chat at it. 取消 (or back) puts the
// field back in the list.
import { useEffect, useRef, useState } from "react";
import { BackHandler, FlatList, Keyboard, Pressable, Text, TextInput, View } from "react-native";
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { ChatItem, ChatSearchView, FoundMessage } from "../../../../web/src/core/shapes.ts";
import { app } from "../AppState";
import { Topics, page, rememberTopic } from "../data/Topics";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { Ease } from "../ui/Motion";
import { SectionHeader, reducedMotion } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { sp, T } from "../ui/Text";
import { dp, useC, withAlpha } from "../ui/Theme";
import { ChatRowBody } from "./Home";
import { keyboard } from "../ui/Keyboard";

/** How many of the messages that have the words the search lists, under the chats. */
const FOUND_MESSAGES = 50;

/** The field's height, and the room over it in the search's bar (as the home bar's: 8dp under the status bar). */
const FIELD = 38;
const BAR_TOP = 8;

/**
 * At a list's top: tapped, the search opens from it (`onOpen`, with its top in the window and its width). `hidden`
 * while the search's field is it (one field at a time, flying from and back to here).
 */
export function SearchField({ onOpen, hidden }: { onOpen: (top: number, width: number) => void; hidden: boolean }) {
  const C = useC();
  const at = useRef<View>(null);
  return (
    <View style={{ paddingLeft: 16, paddingRight: 16, paddingBottom: 6 }}>
      <View ref={at} collapsable={false} style={{ height: FIELD, opacity: hidden ? 0 : 1 }}>
        <Smooth radius={FIELD / 2} style={{ flex: 1, backgroundColor: withAlpha(C.ink, 0.06) }}>
          <Pressable
            onPress={() => at.current?.measureInWindow((_x, y, width) => onOpen(y, width))}
            android_ripple={{ color: withAlpha(C.ink, 0.1) }}
            style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: 12 }}
          >
            <Icon icon={Icons.Search} size={17} color={C.muted} />
            <T size={15} color={C.muted} numberOfLines={1}>{t("android-chat.search.field")}</T>
          </Pressable>
        </Smooth>
      </View>
    </View>
  );
}

type Found = { key: string; kind: "update" | "none" | "chats" | "messages" } | { key: string; kind: "chat"; item: ChatItem } | { key: string; kind: "found"; found: FoundMessage };

/**
 * The search over the home lists, its field come up from `from` (its top in the list, in the window) to the bar, from
 * `wide` (its width there) to the room 取消 leaves it; `onLeave` as it starts going back, `onClose` once it is back
 * there. The words typed stay while a chat opened from it is read.
 */
export function SearchPage({ scope, from, wide, onLeave = () => {}, onClose }: { scope: string; from: number; wide: number; onLeave?: () => void; onClose: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const [query, setQuery] = useState("");
  const search = rememberTopic<ChatSearchView>(Topics.chatSearch(scope, query, null, null, null, FOUND_MESSAGES));
  // While the next words are looked up, what the last ones found stays.
  const kept = useRef<ChatSearchView | null>(null);
  if (search.value) kept.current = search.value;
  const view = search.value ?? kept.current;
  const words = query.trim().length > 0;
  const chats = words ? view?.items ?? [] : [];
  const messages = words ? view?.messages ?? [] : [];
  // Where the field is laid out (under the status bar, as the home bar's top), so its move is known before it is drawn.
  const to = insets.top + BAR_TOP;
  const still = reducedMotion();
  const up = useSharedValue(still ? 1 : 0);
  const [leaving, setLeaving] = useState(false);
  const field = useRef<TextInput>(null);
  const room = useSharedValue(0);
  const cancelWidth = useSharedValue(0);
  // One keyboard for the app (ui/Keyboard.tsx): a second one asked of Reanimated with other window options blanks the window.
  const ime = keyboard();
  useEffect(() => {
    field.current?.focus();
    up.value = withTiming(1, { duration: 280, easing: Ease.Arrive });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const close = () => {
    if (leaving) return;
    setLeaving(true);
    Keyboard.dismiss();
    onLeave();
    if (still) onClose();
    else up.value = withTiming(0, { duration: 240, easing: Ease.Standard }, (done) => { if (done) runOnJS(onClose)(); });
  };
  // Back (the system's) closes it, until it is going.
  const closing = useRef(close);
  closing.current = close;
  useEffect(() => {
    if (leaving) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { closing.current(); return true; });
    return () => sub.remove();
  }, [leaving]);

  // As wide as the list's while there, narrowing to its room as it comes up (and back as it goes): 取消 comes in with
  // its right edge, not the field jumping between the two widths.
  const fieldStyle = useAnimatedStyle(() => {
    const r = room.value;
    const now = r === 0 ? undefined : wide > 0 ? Math.max(0, Math.round(wide + (r - wide) * up.value)) : r;
    return { width: now, transform: [{ translateY: (from - to) * (1 - up.value) }] };
  });
  const cancelStyle = useAnimatedStyle(() => ({ opacity: up.value, transform: [{ translateX: (cancelWidth.value + 12) * (1 - up.value) }] }));
  const listStyle = useAnimatedStyle(() => ({ opacity: up.value }));
  const imeStyle = useAnimatedStyle(() => ({ paddingBottom: ime.value }));

  const rows: Found[] = [];
  if (words && view == null && search.error != null) rows.push({ key: "update", kind: "update" });
  if (words && view != null && chats.length === 0 && messages.length === 0) rows.push({ key: "none", kind: "none" });
  if (chats.length > 0) {
    rows.push({ key: "chats", kind: "chats" });
    for (const item of chats) rows.push({ key: `c/${item.station}/${item.id}`, kind: "chat", item });
  }
  if (messages.length > 0) {
    rows.push({ key: "messages", kind: "messages" });
    for (const found of messages) rows.push({ key: `m/${found.station}/${found.thread}/${found.seq}`, kind: "found", found });
  }

  // Over the lists (faded away, still there): nothing under it is touched through it.
  return (
    <Animated.View style={[{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }, imeStyle]} onStartShouldSetResponder={() => true}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 12, paddingTop: insets.top + BAR_TOP, paddingLeft: 16, paddingRight: 16, paddingBottom: 8 }}>
        <View style={{ flex: 1, height: FIELD }} onLayout={(e) => { room.value = e.nativeEvent.layout.width; }}>
          <Animated.View style={[{ height: FIELD }, fieldStyle]}>
            <Smooth radius={FIELD / 2} style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: 12, backgroundColor: withAlpha(C.ink, 0.06) }}>
              <Icon icon={Icons.Search} size={17} color={C.muted} />
              <View style={{ flex: 1, justifyContent: "center" }}>
                {query.length === 0 && <T size={16} color={C.muted} numberOfLines={1} style={{ position: "absolute", left: 0, right: 0 }}>{t("android-chat.search.field")}</T>}
                <TextInput
                  ref={field}
                  value={query}
                  onChangeText={setQuery}
                  multiline={false}
                  cursorColor={C.accent}
                  selectionColor={withAlpha(C.accent, 0.4)}
                  returnKeyType="search"
                  accessibilityLabel={t("android-chat.search.field")}
                  style={{ fontSize: sp(16), color: C.ink, padding: 0, margin: 0, includeFontPadding: false }}
                />
              </View>
            </Smooth>
          </Animated.View>
        </View>
        <Animated.View style={cancelStyle} onLayout={(e) => { cancelWidth.value = e.nativeEvent.layout.width; }}>
          <Pressable disabled={leaving} onPress={close}>
            <T size={16} color={C.accent}>{t("android-chat.search.cancel")}</T>
          </Pressable>
        </Animated.View>
      </View>
      <Animated.View style={[{ flex: 1 }, listStyle]}>
        <FlatList
          data={rows}
          keyExtractor={(r) => r.key}
          keyboardShouldPersistTaps="handled"
          renderItem={({ item: r }) => {
            switch (r.kind) {
              case "update": return <SearchNote text={t("android-chat.search.update")} />;
              case "none": return <SearchNote text={t("android-chat.search.none")} />;
              case "chats": return <SectionHeader title={t("android-chat.search.chats")} />;
              case "messages": return <SectionHeader title={t("android-chat.search.messages")} />;
              case "chat": return <ChatRowBody item={r.item} lead="agents" held={false} modifier={{ onPress: () => app.push({ kind: "Chat", station: r.item.station, of: page(r.item) }) }} />;
              case "found": return <FoundRow found={r.found} words={view?.words} />;
            }
          }}
        />
      </Animated.View>
    </Animated.View>
  );
}

function SearchNote({ text }: { text: string }) {
  const C = useC();
  return <T size={14} color={C.muted} style={{ paddingHorizontal: 22, paddingVertical: 16 }}>{text}</T>;
}

/**
 * A message the words found: its chat, who said it and when, over the line that has them (in ink, bold); tapped, its
 * chat opens at it, the words marked there.
 */
function FoundRow({ found, words }: { found: FoundMessage; words: string[] | undefined }) {
  const C = useC();
  const parts: { text: string; marked: boolean }[] = [];
  let at = 0;
  for (const m of found.marks) {
    const from = Math.trunc(m.from);
    const to = Math.trunc(m.to);
    if (from < at || to > found.text.length) continue;
    parts.push({ text: found.text.substring(at, from), marked: false });
    parts.push({ text: found.text.substring(from, to), marked: true });
    at = to;
  }
  parts.push({ text: found.text.substring(at), marked: false });
  const meta = [found.by.length > 0 ? found.by : null, found.time?.["createdAt"]?.ago ?? null].filter((x): x is string => x !== null).join(" · ");
  return (
    <Pressable
      onPress={() => app.push({ kind: "Chat", station: found.station, of: page(found.chat), at: found.seq, words })}
      android_ripple={{ color: withAlpha(C.ink, 0.1) }}
      style={{ height: dp(66), paddingLeft: 22, paddingRight: 16, justifyContent: "center" }}
    >
      <View style={{ height: 22, flexDirection: "row", alignItems: "center", gap: 8 }}>
        <T size={15} line={22} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{found.chat.title}</T>
        <T size={12} color={C.muted} numberOfLines={1}>{meta}</T>
      </View>
      <T size={14} line={20} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ height: 20 }}>
        {parts.map((p, i) => (p.marked ? <Text key={i} style={{ color: C.ink, fontWeight: "600" }}>{p.text}</Text> : p.text))}
      </T>
    </Pressable>
  );
}
