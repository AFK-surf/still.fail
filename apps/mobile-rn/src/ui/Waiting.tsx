// Waiting, drawn one way everywhere (docs/ui-panels.md「等待」; web ui/src/waiting.tsx draws the same). Three kinds:
// - a page or list read for the first time: `Waiting`, placeholders shaped as what will come, breathing, no words (the
//   page's frame, its bar, title and composer, drawn as ever around it); what could not be read said over them in red;
// - a row or button at work: `Spinner` in its place (DoingMark where it is a core call), in one of two sizes;
// - what has a size on its way (a file, an update): `Progress`.
// Words (a pill, a line) come only after a moment (LATER_MS), so what is there at once shows none; what failed says so
// at once, in red.
import { useEffect, useState, type ReactNode } from "react";
import { View, useWindowDimensions, type StyleProp, type ViewStyle } from "react-native";
import Animated, { Easing, ReduceMotion, useAnimatedStyle, useDerivedValue, useSharedValue, withRepeat, withTiming, cancelAnimation, type SharedValue } from "react-native-reanimated";
import Svg, { Circle, Path } from "react-native-svg";
import type { ListNote } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";
import { Ease } from "./Motion";
import { reducedMotion } from "./Parts";
import { Smooth } from "./Smooth";
import { T } from "./Text";
import { useC, withAlpha } from "./Theme";

/** Words about a wait come only when it takes a while: what is there in a moment (from the device) shows none. */
export const LATER_MS = 400;

/** CSS's `ease-in-out`, as the web's breathing and sweeping go. */
const EaseInOut = Easing.bezier(0.42, 0, 0.58, 1);

/** Whether words about a wait show yet: after LATER_MS, or at once with `now` (what failed). */
function useLater(now: boolean): boolean {
  const [shown, setShown] = useState(now);
  useEffect(() => {
    if (now) { setShown(true); return; }
    const id = setTimeout(() => setShown(true), LATER_MS);
    return () => clearTimeout(id);
  }, [now]);
  return shown || now;
}

/** An infinite turn, 0 → 360 every `ms` (Compose's infiniteRepeatable(tween(ms, LinearEasing))). */
function useTurn(ms: number, on = true): SharedValue<number> {
  const turn = useSharedValue(0);
  useEffect(() => {
    if (!on) { cancelAnimation(turn); turn.value = 0; return; }
    turn.value = 0;
    turn.value = withRepeat(withTiming(360, { duration: ms, easing: Easing.linear, reduceMotion: ReduceMotion.Never }), -1, false);
    return () => cancelAnimation(turn);
  }, [ms, on, turn]);
  return turn;
}

/**
 * The turning ring: `inline` (12) in a line of small text (a row's end, a pill), else a button's icon's size (14).
 * A track of the line colour and an arc of the accent; `color` (a solid button's text colour) is the arc's, its track that
 * at 30%. Where it sits says its colour and place, never its size.
 */
export function Spinner({ inline = false, color, modifier: style }: { inline?: boolean; color?: string | null; modifier?: StyleProp<ViewStyle> }) {
  const C = useC();
  const arc = color ?? C.accent;
  const track = color ? withAlpha(color, alphaOf(color) * 0.3) : C.lineStrong;
  const turn = useTurn(reducedMotion() ? 2400 : 800);
  const spin = useAnimatedStyle(() => ({ transform: [{ rotate: `${turn.value}deg` }] }));
  const size = inline ? 12 : 14;
  const w = 2;
  const r = (size - w) / 2;
  const c = size / 2;
  // The web's: a border whose top is the arc, a quarter from its top-left to its top-right.
  const d = Math.SQRT1_2 * r;
  return (
    <View style={[{ width: size, height: size }, style]} accessibilityRole="progressbar">
      <Svg width={size} height={size} style={{ position: "absolute" }}>
        <Circle cx={c} cy={c} r={r} stroke={track} strokeWidth={w} fill="none" />
      </Svg>
      <Animated.View style={[{ position: "absolute", width: size, height: size }, spin]}>
        <Svg width={size} height={size}>
          <Path d={`M${c - d} ${c - d}A${r} ${r} 0 0 1 ${c + d} ${c - d}`} stroke={arc} strokeWidth={w} fill="none" />
        </Svg>
      </Animated.View>
    </View>
  );
}

/** A colour's alpha (0..1): #RRGGBBAA's last two, else opaque. */
function alphaOf(color: string): number {
  return color.length === 9 ? parseInt(color.slice(7, 9), 16) / 255 : 1;
}

/** A button at work (one behaviour for all): the spinner (14) in its icon's place, or before its label; `solid`: the
 *  button's text colour on a solid button. The button itself is not tapped again while `busy` (`disabled={busy}`). */
export function BusyIcon({ busy, solid, icon }: { busy: boolean; solid?: string | null; icon?: (() => ReactNode) | null }) {
  if (busy) return <Spinner color={solid} />;
  return <>{icon?.()}</>;
}

/**
 * What is waited on (a spinner before it), or with `error` what is wrong (in red, at once): a grey capsule. Over a
 * viewer's content (a player buffering, a remote screen connecting) it floats: `ground` clear and a glass in `style`.
 */
export function WaitPill({ text, error = false, modifier: style, ground, ink }: { text: string; error?: boolean; modifier?: StyleProp<ViewStyle>; ground?: string; ink?: string }) {
  const C = useC();
  const shown = useLater(error);
  return (
    <View
      style={[{ opacity: shown ? 1 : 0 }, style, { backgroundColor: ground ?? C.chip, borderRadius: 999, paddingHorizontal: 12, paddingVertical: 6, flexDirection: "row", alignItems: "center", gap: 8 }]}
      accessible
      accessibilityLiveRegion="polite"
    >
      {!error && <Spinner inline />}
      <T size={13} line={18} color={error ? C.red : (ink ?? C.muted)} numberOfLines={2} ellipsizeMode="tail" align="center" style={{ flexShrink: 1 }}>{text}</T>
    </View>
  );
}

/** A wait said in a line of its own where a row or a section's content will be (a spinner before it), or in red what is wrong. */
export function WaitLine({ text, error = false, modifier: style }: { text?: string; error?: boolean; modifier?: StyleProp<ViewStyle> }) {
  const C = useC();
  const shown = useLater(error);
  return (
    <View style={[style, { opacity: shown ? 1 : 0, flexDirection: "row", alignItems: "center", gap: 8 }]} accessible accessibilityLiveRegion="polite">
      {!error && <Spinner inline />}
      <T size={13} line={18} color={error ? C.red : C.muted}>{text ?? t("common.reading")}</T>
    </View>
  );
}

/** The shapes of what will come: rows (a list's: a title and a line), messages (a chat's) or cards (a settings page's). */
export enum WaitShape { Rows, Messages, Cards }

/** How much the shapes show: breathing (1 → 0.5 → 1 in 1.4s) while waited on, still under reduced motion; faded and still with `still`. */
export function rememberBreath(still = false): Readonly<SharedValue<number>> {
  const reduced = reducedMotion();
  const pulse = useSharedValue(1);
  const breathe = !still && !reduced;
  useEffect(() => {
    if (!breathe) { cancelAnimation(pulse); pulse.value = 1; return; }
    pulse.value = 1;
    pulse.value = withRepeat(withTiming(0.5, { duration: 700, easing: EaseInOut }), -1, true);
    return () => cancelAnimation(pulse);
  }, [breathe, pulse]);
  return useDerivedValue(() => (still ? 0.6 : pulse.value));
}

/**
 * Something to come drawn as a grey placeholder breathing (a station's figures, a page of a document): as WaitShapes.
 * A hook: the animated style for an Animated.View (Modifier.breathing there).
 */
export function breathing(alpha: Readonly<SharedValue<number>>) {
  return useAnimatedStyle(() => ({ opacity: alpha.value }));
}

/** One of the shapes: grey, a capsule unless `radius` (a Smooth corner) says otherwise. */
function Placeholder({ width, height, radius }: { width?: number; height: number; radius?: number }) {
  const C = useC();
  if (radius !== undefined) return <Smooth radius={radius} style={{ width, height, backgroundColor: C.bubble }} />;
  return <View style={{ width, height, borderRadius: height / 2, backgroundColor: C.bubble }} />;
}

/**
 * The shapes of what will come, breathing: rows as the chats' list's (66 high, a title and a line, a
 * picture at the end), a chat's messages (theirs with a picture on the left, the viewer's on the right) or a settings
 * page's cards.
 */
export function WaitShapes({ shape = WaitShape.Rows, count, still = false, modifier: style }: { shape?: WaitShape; count?: number | null; still?: boolean; modifier?: StyleProp<ViewStyle> }) {
  const breath = breathing(rememberBreath(still));
  const window = useWindowDimensions();
  const [width, setWidth] = useState(window.width);
  const m = [style, { alignSelf: "stretch" as const }, breath];
  const hidden = { accessibilityElementsHidden: true, importantForAccessibility: "no-hide-descendants" as const };
  switch (shape) {
    case WaitShape.Rows:
      return (
        <Animated.View style={m} {...hidden}>
          {Array.from({ length: count ?? 7 }, (_, i) => (
            <View key={i} style={{ height: 66, paddingLeft: 22, paddingRight: 16, flexDirection: "row", alignItems: "center", gap: 12 }}>
              <View style={{ flex: 1, gap: 10 }}>
                <Placeholder width={TITLES[i % TITLES.length]} height={13} />
                <Placeholder width={LINES[i % LINES.length]} height={10} />
              </View>
              <Placeholder width={22} height={22} />
            </View>
          ))}
        </Animated.View>
      );
    case WaitShape.Messages: {
      const most = width * 0.7;
      return (
        <Animated.View style={[m, { paddingTop: 8 }]} onLayout={(e) => setWidth(e.nativeEvent.layout.width)} {...hidden}>
          <View style={{ gap: 14 }}>
            {MESSAGES.slice(0, count ?? MESSAGES.length).map(([mine, w, h], i) => (
              <View key={i} style={{ flexDirection: "row", paddingHorizontal: 16, justifyContent: mine ? "flex-end" : "flex-start" }}>
                {!mine && <><Placeholder width={28} height={28} /><View style={{ width: 10 }} /></>}
                <Placeholder width={Math.min(w, most)} height={h} radius={18} />
              </View>
            ))}
          </View>
        </Animated.View>
      );
    }
    case WaitShape.Cards:
      return (
        <Animated.View style={[m, { paddingHorizontal: 12, gap: 16 }]} {...hidden}>
          {/* A page's card's corner (Parts.tsx Card). */}
          {Array.from({ length: count ?? 3 }, (_, i) => <Placeholder key={i} height={CARDS[i % CARDS.length]!} radius={20} />)}
        </Animated.View>
      );
  }
}

/**
 * A page's or list's content while it is read the first time: its shapes breathing, what it
 * waits on (`note`, else `text`, else 正在读取) said only to a screen reader; over them in red what could not be read
 * (`error`, `note.failing`), the shapes then still. The page's frame (its bar, title, composer) is drawn around it as ever.
 */
export function Waiting({ shape = WaitShape.Rows, count, text, error, note, modifier: style }: { shape?: WaitShape; count?: number | null; text?: string | null; error?: string | null; note?: ListNote | null; modifier?: StyleProp<ViewStyle> }) {
  const failing = [...(error != null ? [error] : []), ...(note?.failing ?? []).map((f) => f.text)];
  const reading = error == null && (note?.reading ?? true);
  const said = note?.text ?? text ?? t("common.reading");
  return (
    <View style={[style, { alignSelf: "stretch" }]} accessibilityLabel={reading ? said : undefined}>
      {failing.length > 0 && (
        <View style={{ paddingLeft: 20, paddingRight: 20, paddingTop: 14, paddingBottom: 4, alignItems: "center", gap: 8 }}>
          {failing.map((f, i) => <WaitPill key={i} text={f} error />)}
        </View>
      )}
      <WaitShapes shape={shape} count={count} still={!reading} />
    </View>
  );
}

/**
 * How much has come of what has a size (0…1), or with `part` null a bar that sweeps while that is not known: a capsule
 * 3 high, its track the accent at 18%, what has come the accent. Under reduced motion an unknown one is a full bar, faint.
 */
export function Progress({ part, modifier: style, color }: { part: number | null | undefined; modifier?: StyleProp<ViewStyle>; color?: string }) {
  const C = useC();
  const tone = color ?? C.accent;
  const a = alphaOf(tone);
  const known = part == null ? null : Math.min(1, Math.max(0, part));
  const reduced = reducedMotion();
  const shown = useSharedValue(known ?? 0);
  useEffect(() => {
    if (known !== null) shown.value = withTiming(known, { duration: 200, easing: Ease.Out });
  }, [known, shown]);
  const fill = useAnimatedStyle(() => ({ width: `${shown.value * 100}%` }));
  // The web's: a segment 40% wide, from just before the track's start to just past its end, again and again.
  const sweeping = known === null && !reduced;
  const sweep = useSharedValue(-1);
  const [segment, setSegment] = useState(0);
  useEffect(() => {
    if (!sweeping) { cancelAnimation(sweep); return; }
    sweep.value = -1;
    sweep.value = withRepeat(withTiming(2.5, { duration: 1400, easing: EaseInOut }), -1, false);
    return () => cancelAnimation(sweep);
  }, [sweeping, sweep]);
  const moving = useAnimatedStyle(() => ({ transform: [{ translateX: sweep.value * segment }] }));
  return (
    <View
      style={[style, { alignSelf: "stretch", height: 3, borderRadius: 1.5, overflow: "hidden", backgroundColor: withAlpha(tone, a * 0.18) }]}
      accessibilityRole="progressbar"
      accessibilityValue={known === null ? undefined : { min: 0, max: 100, now: Math.round(known * 100) }}
    >
      {known !== null ? (
        <Animated.View style={[{ height: 3, borderRadius: 1.5, backgroundColor: tone }, fill]} />
      ) : reduced ? (
        <View style={{ height: 3, borderRadius: 1.5, backgroundColor: withAlpha(tone, a * 0.35) }} />
      ) : (
        <Animated.View onLayout={(e) => setSegment(e.nativeEvent.layout.width)} style={[{ width: "40%", height: 3, borderRadius: 1.5, backgroundColor: tone }, moving]} />
      )}
    </View>
  );
}

const TITLES = [150, 110, 170, 130, 96, 160, 120];
const LINES = [230, 190, 250, 170, 210, 200, 180];
const MESSAGES: [mine: boolean, width: number, height: number][] = [[false, 220, 40], [false, 160, 58], [true, 180, 40], [false, 240, 76], [true, 120, 40], [false, 200, 40]];
const CARDS = [120, 88, 152, 104];
