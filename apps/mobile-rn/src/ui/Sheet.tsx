// What lies over the pages: one sheet from the bottom at a time (dragged by
// its grabber between half and full height, or down to close), a message's
// long-press menu, and a short note.
import { BlurView } from "expo-blur";
import { slot, type Slot } from "./Parts";
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { BackHandler, Keyboard, Platform, Pressable, ScrollView, StyleSheet, View, useWindowDimensions } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { type SharedValue, runOnJS, useAnimatedStyle, useSharedValue, withSpring, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { MenuItem, MenuSpec, ReaderSpec, SheetSpec, type Rect } from "../AppState";
import { t } from "../i18n";
import { keyboard } from "./Keyboard";
import { Ease, SheetSpring, motionSpring } from "./Motion";
import { IconIn, NavBack } from "./Parts";
import { Smooth } from "./Smooth";
import { T } from "./Text";
import { useC, withAlpha } from "./Theme";
import { Quiet } from "./Quiet";

/**
 * A sheet (AppState's SheetSpec, as Sheet.kt has it): how much of the screen it takes at first (`height`), and whether
 * its grabber drags it (`draggable`). `fit`: as tall as what it shows instead (that much, over the navigation bar), for
 * one whose content is a known few lines. `onClose`: told when it is closed by hand (a tap beside it, dragged down,
 * back), not otherwise. `solid`: on the page's paper, not frosted (over another app, where there is no page of the app's
 * own to frost: the share sheet). `content`: what it shows, top to bottom.
 * A menu (MenuSpec): `anchor` the box it opens by, in the window (left, top, right, bottom), its items, `onDismiss`.
 * A menu's item (MenuItem): `icon` null: the room for one left empty (a check on another item, say); `action`.
 * The reader (ReaderSpec): `label` what it is (a line, as the history labels it), `content` all of it.
 */
export { MenuItem, MenuSpec, ReaderSpec, SheetSpec, type Rect };

/** Drags the open sheet by its top; `release` has the finger's speed (dp/s of height, up is positive). */
export interface SheetDrag { draggable: boolean; drag: (dy: number) => void; release: (velocity: number) => void; tap: () => void }

/** How far a finger goes before it is a drag (Android's touch slop, 8dp); a sheet's top that drags it (64dp). */
const TOUCH_SLOP = 8;
const DRAG_ZONE = 64;

const LocalSheetDrag = createContext<SheetDrag | null>(null);

/** Android's back, while `enabled`: the newest one asked for is the one run. */
function useBack(enabled: boolean, onBack: () => void) {
  const latest = useRef(onBack);
  latest.current = onBack;
  useEffect(() => {
    if (!enabled) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { latest.current(); return true; });
    return () => sub.remove();
  }, [enabled]);
}

/** expo-blur's intensity for a CSS blur of `px` (as Glass.tsx reckons it). */
const blurOf = (px: number) => ({ intensity: px * 4, blurReductionFactor: 4 }) as const;
const canBlur = Platform.OS === "android" ? (Platform.Version as number) >= 31 : true;

/** `haze`: the Android app's frosting source; here what is behind is blurred as it is (Glass.tsx), so none is needed. */
export function SheetHost({ spec, close }: { spec: SheetSpec | null; haze?: unknown; close: () => void }) {
  const [shown, setShown] = useState<SheetSpec | null>(null);
  if (spec != null && shown !== spec) setShown(spec);
  useBack(spec != null, close);
  // A sheet comes up in the keyboard's place: what was being typed into lets go of it first.
  useEffect(() => { if (spec != null) Keyboard.dismiss(); }, [spec]);
  const scrim = useSharedValue(0);
  useEffect(() => { scrim.value = withTiming(spec != null ? 1 : 0, { duration: 300, easing: Ease.Css }); }, [spec, scrim]);
  const current = shown ?? (spec != null ? spec : null);
  if (current == null) return null;
  return <SheetBody spec={spec} current={current} scrim={scrim} close={close} gone={() => setShown(null)} />;
}

function SheetBody({ spec, current, scrim, close, gone }: { spec: SheetSpec | null; current: SheetSpec; scrim: SharedValue<number>; close: () => void; gone: () => void }) {
  const C = useC();
  const window = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [total, setTotal] = useState(window.height);
  // How tall a sheet is at first: its share of the screen, or what it shows over the navigation bar (most of the screen at most).
  const foot = insets.bottom;
  const tall = (of: SheetSpec) => ((of.fit ?? null) != null ? Math.min(of.fit! + foot, total * 0.9) : of.height * total);
  const height = useSharedValue(tall(current));
  const offset = useSharedValue(tall(current));
  useEffect(() => {
    if (spec != null) {
      const target = tall(spec);
      if (offset.value > 1) {
        height.value = target;
        offset.value = withSpring(0, SheetSpring);
      } else {
        height.value = withSpring(target, SheetSpring);
      }
    } else {
      offset.value = withSpring(height.value, SheetSpring, (finished) => { if (finished) runOnJS(gone)(); });
    }
    // Its target read once per sheet, as the Android app's LaunchedEffect(spec) does.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spec]);
  const min = 120;
  const base = tall(current);
  const held = useRef<number | null>(null);
  // Let go: on to where it settles at the speed the finger left it (height per second, up is more).
  const settle = (to: number, velocity = 0) => { height.value = withSpring(to, { ...SheetSpring, velocity }); };
  const paper = C.bg;
  const glass = withAlpha(C.surface, 0.8);
  // One per sheet: a new one would restart the grabber's gesture halfway through a drag.
  const drag = useMemo<SheetDrag>(() => ({
    draggable: current.draggable ?? false,
    // A draggable sheet between half and full height (or down to close); any other only down, to close.
    // Where the finger has it, kept here at once (the height follows a moment later, as its snaps run): let go
    // in the same moment as the last move, it is judged by where the finger was.
    drag: (dy) => {
      const from = held.current ?? height.value;
      const to = Math.max(min, Math.min((current.draggable ?? false) ? total * 0.94 : base, from - dy));
      held.current = to;
      height.value = to;
    },
    release: (v) => {
      const at = held.current ?? height.value;
      held.current = null;
      const f = at / total;
      if (!(current.draggable ?? false)) { if (base - at > 80) close(); else settle(base, v); }
      else if (f < 0.3) close();
      else settle(f > 0.72 ? total * 0.94 : total * 0.55, v);
    },
    tap: () => settle(height.value > total * 0.9 ? total * 0.55 : total * 0.94),
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [current, total]);

  // With a finger its top (the grabber and the head, 64dp) drags it, as web mobile's does.
  const start = useRef(0);
  const pan = useMemo(() => Gesture.Pan()
    .runOnJS(true)
    .manualActivation(true)
    .onTouchesDown((e, m) => {
      const t0 = e.changedTouches[0];
      if (!t0 || t0.y > DRAG_ZONE) { m.fail(); return; }
      start.current = t0.absoluteY;
    })
    .onTouchesMove((e, m) => {
      const t0 = e.allTouches[0];
      if (t0 && Math.abs(t0.absoluteY - start.current) > TOUCH_SLOP) m.activate();
    })
    .onChange((e) => drag.drag(e.changeY))
    .onEnd((e, ended) => drag.release(ended ? -e.velocityY : 0)), [drag]);

  const typing = keyboard();
  const sheet = useAnimatedStyle(() => {
    // Its height read as it is laid out: a drag moves it without making its content again. The keyboard up
    // (a field of its own), it grows by what the keyboard takes over the navigation bar, so what it shows
    // stays as tall over the keyboard and not squeezed under it.
    const over = Math.max(0, typing.value - foot);
    const h = Math.max(0, Math.min(total, height.value + over));
    return { height: h, transform: [{ translateY: offset.value }] };
  });
  // A field of the sheet's own brings the keyboard up under the sheet, not over it.
  const pad = useAnimatedStyle(() => ({ paddingBottom: Math.max(typing.value, foot) }));
  const dim = useAnimatedStyle(() => ({ opacity: scrim.value }));

  return (
    <View style={StyleSheet.absoluteFill} onLayout={(e) => setTotal(e.nativeEvent.layout.height)}>
      <Pressable style={StyleSheet.absoluteFill} onPress={close}>
        <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: "rgba(0,0,0,0.28)" }, dim]} />
      </Pressable>
      <Animated.View style={[{ position: "absolute", left: 0, right: 0, bottom: 0 }, sheet]}>
        <GestureDetector gesture={pan}>
          <Smooth radius={[26, 26, 0, 0]} style={{ flex: 1, elevation: 24, shadowColor: "#000", shadowOpacity: 0.25, shadowRadius: 24, shadowOffset: { width: 0, height: 8 } }} onStartShouldSetResponder={() => true}>
            {/* Frosted glass over the page, as the bars and capsules are. The web's backdrop has the scrim in it (it
                frosts all that is behind it); here the pages alone are the source, so the scrim goes under the glass. */}
            {(current.solid ?? false) || !canBlur ? (
              <View style={[StyleSheet.absoluteFill, { backgroundColor: paper }]} />
            ) : (
              <Quiet style={StyleSheet.absoluteFill}><BlurView experimentalBlurMethod="dimezisBlurView" {...blurOf(28)} tint="default" style={StyleSheet.absoluteFill} /></Quiet>
            )}
            {!(current.solid ?? false) && (
              <>
                <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: "rgba(0,0,0,0.28)" }, dim]} />
                <View style={[StyleSheet.absoluteFill, { backgroundColor: glass }]} />
              </>
            )}
            <Animated.View style={[{ flex: 1 }, pad]}>
              <LocalSheetDrag.Provider value={drag}>{current.content()}</LocalSheetDrag.Provider>
            </Animated.View>
          </Smooth>
        </GestureDetector>
      </Animated.View>
    </View>
  );
}

/** The sheet's grabber: drags a draggable sheet, and a tap switches it between half and full. */
export function SheetGrab() {
  const C = useC();
  const drag = useContext(LocalSheetDrag);
  const bar = <View style={{ width: 38, height: 5, borderRadius: 3, backgroundColor: C.line }} />;
  const inner = { alignSelf: "stretch" as const, paddingVertical: 4, alignItems: "center" as const, justifyContent: "center" as const };
  return (
    <View style={{ alignSelf: "stretch", paddingTop: 8, paddingBottom: 4 }}>
      {/* Its drag is the sheet's top's (SheetHost); a tap switches a draggable sheet between half and full. */}
      {drag?.draggable === true ? <Pressable onPress={() => drag.tap()} style={inner}>{bar}</Pressable> : <View style={inner}>{bar}</View>}
    </View>
  );
}

export function SheetHead({ title, trailing, lead }: { title: string; trailing?: Slot | null; lead?: Slot | null }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 8, paddingLeft: 18, paddingRight: 18, paddingTop: 4, paddingBottom: 10 }}>
      {slot(lead)}
      <T size={17} weight="700" color={C.ink} style={{ flex: 1 }}>{title}</T>
      {slot(trailing)}
    </View>
  );
}

// ── the long-press menu ────────────────────────────────────────────────

// A short, nearly critically damped spring: quick off the mark, soft at its
// destination, and continuous in speed when the user reverses it.
const MenuSpring = { ...motionSpring(0.24, 0.08), restDisplacementThreshold: 0.001 };

export function MenuHost({ spec, closed }: { spec: MenuSpec | null; closed: () => void }) {
  const [shown, setShown] = useState<MenuSpec | null>(null);
  if (spec != null && shown !== spec) setShown(spec);
  const current = spec ?? shown;
  if (current == null) return null;
  return <MenuBody spec={spec} current={current} closed={closed} gone={() => setShown(null)} />;
}

function MenuBody({ spec, current, closed, gone }: { spec: MenuSpec | null; current: MenuSpec; closed: () => void; gone: () => void }) {
  const C = useC();
  const window = useWindowDimensions();
  const [box, setBox] = useState({ width: window.width, height: window.height });
  // Keep the closed state alive before the first menu is mounted, and keep its
  // content until both the menu and its backdrop have finished leaving.
  const visible = spec != null;
  const scrim = useSharedValue(0);
  const alpha = useSharedValue(0);
  const scale = useSharedValue(0.9);
  const left = useRef({ scrim: false, menu: false });
  useEffect(() => {
    left.current = { scrim: false, menu: false };
    const done = (which: "scrim" | "menu") => {
      left.current[which] = true;
      if (left.current.scrim && left.current.menu) gone();
    };
    scrim.value = withTiming(visible ? 1 : 0, { duration: 200, easing: Ease.Standard }, (finished) => { if (finished && !visible) runOnJS(done)("scrim"); });
    if (visible) {
      alpha.value = withTiming(1, { duration: 160, easing: Ease.Out });
      scale.value = withSpring(1, MenuSpring);
    } else {
      alpha.value = withTiming(0, { duration: 120, easing: Ease.CssOut });
      scale.value = withSpring(0.9, MenuSpring, (finished) => { if (finished) runOnJS(done)("menu"); });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);
  const close = () => { current.onDismiss?.(); closed(); };
  useBack(spec != null, close);

  const width = 180;
  const x = Math.max(12, Math.min(current.anchor.left, box.width - width - 12));
  // Under the message, or over it when there is no room below.
  const menuHeight = 45 * current.items.length;
  const below = current.anchor.bottom + 6;
  const y = below + menuHeight < box.height - 24 ? below : Math.max(24, current.anchor.top - menuHeight - 6);
  const origin = y === below ? "left top" : "left bottom";
  const dim = useAnimatedStyle(() => ({ opacity: scrim.value }));
  const menu = useAnimatedStyle(() => ({ opacity: alpha.value, transform: [{ scale: scale.value }] }));
  return (
    <View style={StyleSheet.absoluteFill} onLayout={(e) => setBox({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
      <Pressable style={StyleSheet.absoluteFill} onPress={close}>
        <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: "rgba(0,0,0,0.28)" }, dim]} />
      </Pressable>
      <Animated.View style={[{ position: "absolute", left: x, top: y, width, transformOrigin: origin }, menu]} pointerEvents={visible ? "auto" : "none"}>
        <Smooth radius={14} style={{ width, backgroundColor: C.surface, elevation: 18, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 18, shadowOffset: { width: 0, height: 6 } }}>
          {current.items.map((item, i) => (
            <Pressable
              key={i}
              onPress={() => { closed(); item.action(); }}
              android_ripple={{ color: withAlpha(C.ink, 0.1) }}
              style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: 16, paddingVertical: 12 }}
            >
              <T size={15} color={C.ink}>{item.label}</T>
              {item.icon != null ? <IconIn icon={item.icon} size={16} /> : <View style={{ width: 16, height: 16 }} />}
            </Pressable>
          ))}
        </Smooth>
      </Animated.View>
    </View>
  );
}

// ── a short note ───────────────────────────────────────────────────────

/**
 * What a toast says. A write its station did not answer may have been done (the core's `unconfirmed`, client/core-ts/src/
 * station/sync.ts): said as not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
 */
export function said(message: string): string {
  return message
    .replace(/^(?:没能|无法)([^：]*)：((?:不确定做没做成|无法确认是否成功)：)/, "$1：$2")
    .replace(/^Couldn't ([^:]*): ((?:Unsure if it went through|Couldn't confirm it went through): )/, "$1: $2");
}

export function ToastHost({ toast, done }: { toast: string | null; done: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const text = toast != null ? said(toast) : null;
  const latest = useRef(done);
  latest.current = done;
  useEffect(() => {
    if (text == null) return;
    const id = setTimeout(() => latest.current(), 2600);
    return () => clearTimeout(id);
  }, [text]);
  // Kept while it fades, so it fades with its words.
  const [last, setLast] = useState("");
  if (text != null && last !== text) setLast(text);
  const [present, setPresent] = useState(text != null);
  if (text != null && !present) setPresent(true);
  const alpha = useSharedValue(0);
  useEffect(() => {
    alpha.value = withTiming(text != null ? 1 : 0, { duration: 200, easing: Ease.Css }, (finished) => {
      if (finished && text == null) runOnJS(setPresent)(false);
    });
  }, [text != null]); // eslint-disable-line react-hooks/exhaustive-deps
  const fade = useAnimatedStyle(() => ({ opacity: alpha.value }));
  return (
    <View style={[StyleSheet.absoluteFill, { paddingBottom: insets.bottom + 90, alignItems: "center", justifyContent: "flex-end" }]} pointerEvents="none">
      {present && (
        <Animated.View style={[{ paddingHorizontal: 24 }, fade]}>
          <Smooth radius={18} style={{ backgroundColor: C.ink, paddingHorizontal: 16, paddingVertical: 10 }}>
            <T color={C.bg} size={14}>{last}</T>
          </Smooth>
        </Animated.View>
      )}
    </View>
  );
}

/** The reader comes in from the side over everything; back (or ‹) returns to where it was opened. */
export function ReaderHost({ spec, close }: { spec: ReaderSpec | null; close: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const window = useWindowDimensions();
  const [shown, setShown] = useState<ReaderSpec | null>(null);
  if (spec != null && shown !== spec) setShown(spec);
  useBack(spec != null, close);
  const [width, setWidth] = useState(window.width);
  // web mobile's mReader: translateX 100% → 0 and back, 300ms (.4, 0, .2, 1).
  const x = useSharedValue(1);
  useEffect(() => {
    x.value = withTiming(spec != null ? 0 : 1, { duration: 300, easing: Ease.Standard }, (finished) => {
      if (finished && spec == null) runOnJS(setShown)(null);
    });
  }, [spec != null]); // eslint-disable-line react-hooks/exhaustive-deps
  const slide = useAnimatedStyle(() => ({ transform: [{ translateX: x.value * width }] }));
  const current = spec ?? shown;
  if (current == null) return null;
  return (
    <Animated.View
      style={[StyleSheet.absoluteFill, { backgroundColor: C.bg, paddingTop: insets.top, paddingBottom: insets.bottom }, slide]}
      onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
      onStartShouldSetResponder={() => true}
    >
      <View style={{ alignSelf: "stretch", flexDirection: "row", paddingLeft: 10, paddingRight: 16, paddingTop: 6, paddingBottom: 10 }}>
        <NavBack label={t("android-misc.reader.back")} onClick={close} />
      </View>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 30, gap: 12 }}>
        <View style={{ flexDirection: "row", alignItems: "center" }}>{current.label()}</View>
        {current.content()}
      </ScrollView>
    </Animated.View>
  );
}
