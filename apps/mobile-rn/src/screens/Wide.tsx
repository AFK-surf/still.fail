// A screen wider than a phone (an opened foldable, a phone on its side), as web mobile/app.tsx WIDE draws it: the pages
// the screen's whole width; at its bottom left, level with the composer and as tall, a button raises the latest chats
// over the page (the composer starts beside it); Home's new-chat button is at its bottom right.
import { useEffect, useState } from "react";
import { BackHandler, FlatList, Pressable, View, type ViewStyle } from "react-native";
import Animated, { useAnimatedKeyboard, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTopic } from "../../../../web/src/core/react.ts";
import type { ChatsView } from "../../../../web/src/core/shapes.ts";
import { app, chatOfKey, screenId, type Screen } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { lerpColor, raised, useC, type StillFailColors } from "../ui/Theme";
import { Waiting } from "../ui/Waiting";
import { ChatRowBody, DecisionsCapsule, decisionsWaiting } from "./Home";

/** Wider than this, the screen is wide (web: app.tsx WIDE). */
export const WideAt = 680;

/** A new chat on a wide screen: a column up to 680 wide in the middle, with at least 72 of room either side. */
export const NewChatColumn: ViewStyle = { paddingHorizontal: 72, width: "100%", maxWidth: 680 + 2 * 72, alignSelf: "center" };

/** Where the composer starts on a wide screen: beside the latest chats' button (10 + 52 + 10). */
export const BesideRecent = 72;

/**
 * ui/Glass.kt floatingStill: a capsule where nothing runs under it, the glass over the plain page drawn as it comes out
 * (`--raised` at 72% over the paper), a breath of shadow round it. (Glass.tsx has the frosted one, Floating.)
 */
export function floatingStill(C: StillFailColors, tint?: string): ViewStyle {
  return {
    backgroundColor: lerpColor(C.bg, tint ?? raised(C), 0.72),
    elevation: 1, shadowColor: "#0000004D", shadowOpacity: 0.3, shadowRadius: 1, shadowOffset: { width: 0, height: 0.5 },
  };
}

/** The keyboard or the system's bars at the foot, whichever is higher: what is at the bottom sits over it. */
function useFoot() {
  const keyboard = useAnimatedKeyboard();
  const insets = useSafeAreaInsets();
  return useAnimatedStyle(() => ({ paddingBottom: Math.max(keyboard.height.value, insets.bottom) }));
}

/** What is at the screen's bottom corners, over the page (Home draws its own new-chat button only when not wide). */
export function WideCorners({ current, top }: { current: WorkspaceEntry; top: Screen }) {
  const foot = useFoot();
  switch (top.kind) {
    case "Home":
      return <HomeCorner current={current} foot={foot} />;
    // The decisions: one at a time, back to the list; their foot is theirs.
    case "Decisions":
      return null;
    // The drive's reader and player take the whole screen: their controls are where the button would be.
    case "DriveRead":
    case "DrivePlay":
      return null;
    default:
      return <Recent current={current} top={top} foot={foot} />;
  }
}

function HomeCorner({ current, foot }: { current: WorkspaceEntry; foot: ReturnType<typeof useFoot> }) {
  const C = useC();
  const decisions = decisionsWaiting(current);
  return (
    <Animated.View pointerEvents="box-none" style={[{ position: "absolute", right: 0, bottom: 0 }, foot]}>
      <View style={{ marginRight: 10, marginBottom: 10, flexDirection: "row", gap: 10, alignItems: "center" }}>
        <DecisionsCapsule n={decisions} ground={(content, style) => <View style={[floatingStill(C), { borderRadius: 28, overflow: "hidden" }, style]}>{content}</View>} />
        <NewChatDisc />
      </View>
    </Animated.View>
  );
}

/**
 * The new-chat button: a disc of the 奏 capsule's glass in the accent, 令 white (Home.tsx's Toolbar). Not frosted over the
 * pages (app.haze): drawn inside what that blurs, a frosted ring there shows the blur's own edges.
 */
export function NewChatDisc() {
  const C = useC();
  return (
    <Pressable
      onPress={() => app.push({ kind: "NewChat" })}
      accessibilityLabel={t("android-misc.wide.newChat")}
      android_ripple={{ color: "#FFFFFF33", borderless: false }}
      style={[floatingStill(C, C.accent), { width: 56, height: 56, borderRadius: 28, overflow: "hidden", alignItems: "center", justifyContent: "center" }]}
    >
      <Icon icon={Icons.Ling} size={44} color="#FFFFFF" />
    </Pressable>
  );
}

/**
 * The button for the latest chats, at the screen's bottom left as high as the composer is (ChatHost.tsx: 10 from the
 * foot, 52 tall on one line), and the chats it raises over the page (not dimmed): the list's first six, the open one
 * marked; a new chat at their head, the whole list at their foot. One picked takes the place of the page open.
 */
function Recent({ current, top, foot }: { current: WorkspaceEntry; top: Screen; foot: ReturnType<typeof useFoot> }) {
  const C = useC();
  // Put away when the page changes under them (a new chat becoming its chat, a link opened), as web's on a new address.
  const topId = screenId(top);
  const [open, setOpen] = useState(false);
  useEffect(() => setOpen(false), [topId]);
  useEffect(() => {
    if (!open) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { setOpen(false); return true; });
    return () => sub.remove();
  }, [open]);
  // Shown while open, and while it goes (fadeOut 160, scaleOut 200).
  const [shown, setShown] = useState(open);
  useEffect(() => {
    if (open) { setShown(true); return; }
    const gone = setTimeout(() => setShown(false), 200);
    return () => clearTimeout(gone);
  }, [open]);
  // In: fading 180ms as it grows from .6 in 280; out: 160 and 200, from its bottom-left corner.
  const fadeIn = useSharedValue(0);
  const grow = useSharedValue(0);
  useEffect(() => {
    fadeIn.value = withTiming(open ? 1 : 0, { duration: open ? 180 : 160 });
    grow.value = withTiming(open ? 1 : 0, { duration: open ? 280 : 200 });
  }, [open, fadeIn, grow]);
  const fade = useAnimatedStyle(() => ({ opacity: fadeIn.value, transform: [{ scale: 0.6 + 0.4 * grow.value }] }));
  return (
    <>
      {open && <Pressable style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }} onPress={() => setOpen(false)} />}
      {shown && (
        <Animated.View pointerEvents="box-none" style={[{ position: "absolute", left: 0, bottom: 0 }, foot]}>
          <Animated.View style={[{ marginLeft: 10, marginBottom: 72, transformOrigin: "8% 110%" }, fade]}>
            <RecentList current={current} top={top} close={() => setOpen(false)} />
          </Animated.View>
        </Animated.View>
      )}
      <Animated.View pointerEvents="box-none" style={[{ position: "absolute", left: 0, bottom: 0 }, foot]}>
        <Pressable
          onPress={() => setOpen(!open)}
          accessibilityLabel={t("android-misc.wide.recent")}
          style={[
            { marginLeft: 10, marginBottom: 10, width: 52, height: 52, borderRadius: 26, overflow: "hidden", alignItems: "center", justifyContent: "center" },
            open ? { backgroundColor: C.ink, elevation: 1 } : floatingStill(C),
          ]}
        >
          <Icon icon={Icons.Chats} size={22} color={open ? C.bg : C.ink} />
        </Pressable>
      </Animated.View>
    </>
  );
}

function RecentList({ current, top, close }: { current: WorkspaceEntry; top: Screen; close: () => void }) {
  const C = useC();
  const chats = useTopic<ChatsView>({ topic: "chats", scope: current.workspace.id, mine: false });
  const view = chats.value;
  const items = view ? view.days.flatMap((d) => d.items).slice(0, 6) : [];
  let body;
  if (!view) body = <Waiting count={4} text={t("android-misc.wide.loading")} error={chats.error?.message} modifier={{ paddingBottom: 8 }} />;
  // No rows: what the list says in their place (the core's `note`), as the home list does: its rows to come
  // while read, or what could not be; else that there are none.
  else if (view.days.length === 0) {
    const note = view.note;
    body = note && (note.reading || note.failing.length > 0)
      ? <Waiting count={4} text={t("android-misc.wide.loading")} note={note} modifier={{ paddingBottom: 8 }} />
      : <T size={14} color={C.muted} style={{ padding: 18 }}>{t("android-misc.wide.empty")}</T>;
  } else body = (
    <FlatList
      style={{ flexGrow: 0, flexShrink: 1, paddingHorizontal: 6 }}
      data={items}
      keyExtractor={(item) => `${item.station}/${item.id}`}
      renderItem={({ item }) => {
        const here = top.kind === "Chat" && top.station === item.station && chatOfKey(top.of) === item.session;
        return (
          <Smooth radius={14} style={{ backgroundColor: here ? C.accentBg : "transparent" }}>
            <Pressable
              android_ripple={{ color: `${C.ink}1A` }}
              onPress={() => { close(); if (!here) app.open({ kind: "Chat", station: item.station, of: { session: item.session } }); }}
            >
              <ChatRowBody item={item} lead={view.leading ?? "agents"} held={false} />
            </Pressable>
          </Smooth>
        );
      }}
    />
  );
  return (
    <Smooth
      radius={22}
      style={[floatingStill(C), { width: 340, maxHeight: 560, elevation: 14, shadowColor: "#00000033" }]}
    >
      <View style={{ flexDirection: "row", alignItems: "center", paddingLeft: 18, paddingRight: 12, paddingTop: 12, paddingBottom: 6 }}>
        <T size={15} weight="600" color={C.ink} style={{ flex: 1 }}>{t("android-misc.wide.recent")}</T>
        <Pressable
          onPress={() => { close(); app.open({ kind: "NewChat" }); }}
          accessibilityLabel={t("android-misc.wide.newChat")}
          android_ripple={{ color: "#FFFFFF33" }}
          style={{ width: 32, height: 32, borderRadius: 16, overflow: "hidden", backgroundColor: C.accent, alignItems: "center", justifyContent: "center" }}
        >
          <Icon icon={Icons.Ling} size={26} color="#FFFFFF" />
        </Pressable>
      </View>
      {body}
      <View style={{ height: 0.5, backgroundColor: C.line }} />
      <Pressable
        onPress={() => { close(); app.home(); }}
        android_ripple={{ color: `${C.ink}1A` }}
        style={{ flexDirection: "row", alignItems: "center", paddingLeft: 18, paddingRight: 16, paddingTop: 12, paddingBottom: 12 }}
      >
        <T size={14} color={C.accentInk} style={{ flex: 1 }}>{t("android-misc.wide.all")}</T>
        <Icon icon={Icons.ChevronRight} size={16} color={C.accentInk} />
      </Pressable>
    </Smooth>
  );
}
