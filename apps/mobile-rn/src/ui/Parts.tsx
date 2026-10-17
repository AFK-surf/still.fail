// The concept's small parts: model marks with their state badge, people's
// avatars, rings, toggles, segmented choices, navigation bars and list cards.
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Image, Pressable, View, type PressableAndroidRippleConfig, type StyleProp, type ViewStyle } from "react-native";
import Animated, { useAnimatedStyle, useReducedMotion, useSharedValue, withRepeat, withTiming, cancelAnimation } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle, Path, Rect } from "react-native-svg";
import { SvgXml } from "react-native-svg";
import type { HostDetail, Maker, Meter, Person, Quota } from "../../../../web/src/core/shapes.ts";
import { ChatState } from "../data/Chats";
import { Drawing } from "./Drawing";
import { Drawables, type DrawableName } from "./Drawables";
import { Icon, Icons } from "./Icon";
import { StationIcons, type IconPaths } from "./IconSet";
import { useUi } from "./Host";
import { Ease } from "./Motion";
import { Smooth } from "./Smooth";
import { T } from "./Text";
import { lerpColor, useC, withAlpha, type StillFailColors } from "./Theme";

export { Illustration } from "./Drawing";

/** Compose's ripple in `color` (its pressed alpha, 10%), bounded by what it is on: `android_ripple` for a Pressable. */
export function ripple(color: string): PressableAndroidRippleConfig {
  return { color: withAlpha(color, 0.1), borderless: false };
}

// ── model marks ────────────────────────────────────────────────────────

const MAKER_MARKS: Record<string, DrawableName> = {
  anthropic: "maker_anthropic", openai: "maker_openai", deepseek: "maker_deepseek",
  qwen: "maker_qwen", zhipu: "maker_zhipu", gemini: "maker_gemini",
  kimi: "maker_kimi", minimax: "maker_minimax", xai: "maker_xai",
  mistral: "maker_mistral",
  xiaomi: "maker_xiaomi",
  "ant-ling": "maker_ant_ling",
  openrouter: "maker_openrouter",
  vercel: "maker_vercel",
  cloudflare: "maker_cloudflare",
  azure: "maker_azure",
  groq: "maker_groq",
  together: "maker_together",
  fireworks: "maker_fireworks",
  cerebras: "maker_cerebras",
  huggingface: "maker_huggingface",
  nvidia: "maker_nvidia",
  baseten: "maker_baseten",
  dsh: "maker_dsh",
};

/** Marks of one colour, drawn in the page's ink. */
const MONO = new Set(["anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter", "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface", "nvidia", "baseten", "dsh"]);

/** A drawing with every colour in it made `tint`, its alpha kept (ColorFilter.tint, SrcIn). */
function tinted(svg: string, tint: string): string {
  return svg.replace(/(fill|stroke)="#[0-9A-Fa-f]{3,8}"/g, `$1="${tint}"`);
}

/** The mark of the company that made a model (the core says which); for one it does not know, its runtime's maker's (DeepSeek Harness's own). */
export function MakerIcon({ maker, runtime, size, modifier: modifier_, style = modifier_ }: { maker: Maker | null | undefined; runtime: string | null | undefined; size: number; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const id = maker?.id && maker.id in MAKER_MARKS ? maker.id : runtime === "codex" ? "openai" : runtime === "dsh" ? "dsh" : "anthropic";
  const d = Drawables[MAKER_MARKS[id]!];
  const mono = MONO.has(id);
  const xml = useMemo(() => (mono ? tinted(d.svg, C.ink) : d.svg), [d, mono, C.ink]);
  return (
    <View style={[{ width: size, height: size }, style]} accessibilityLabel={maker?.name}>
      <SvgXml xml={xml} width={size} height={size} />
    </View>
  );
}

/** A state badge: solid orange = block, a still hollow orange ring = at work, red = failed; done has none. Nothing blinks. */
export function Badge({ state, size, ring, around, modifier: modifier_, style = modifier_ }: { state: ChatState; size: number; ring: number; around: string; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const r = size / 2;
  const inner = r - ring;
  const w = Math.min(2.5, inner);
  return (
    <View style={[{ width: size, height: size }, style]}>
      <Svg width={size} height={size}>
        <Circle cx={r} cy={r} r={r} fill={around} />
        {state === ChatState.Block && <Circle cx={r} cy={r} r={inner} fill={C.accent} />}
        {state === ChatState.Failed && <Circle cx={r} cy={r} r={inner} fill={C.red} />}
        {state === ChatState.Running && <Circle cx={r} cy={r} r={inner - w / 2} fill="none" stroke={C.accent} strokeWidth={w} />}
      </Svg>
    </View>
  );
}

const AGENT_RED = "#E5484D";
const AGENT_YELLOW = "#F2B01E";

/**
 * An agent's state at its mark's corner in the chat list's colours (web ui.css.ts agentMark, ChatMark.css.ts): a 12dp
 * disc of the ground, red in it when it wants someone (blocked, failed), at work a turning yellow 8dp ring with a faint
 * quarter; nothing when done. No halo: the mark is small.
 */
export function AgentStateMark({ state, around, modifier: modifier_, style = modifier_ }: { state: ChatState; around: string; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const reduced = reducedMotion();
  const turning = state === ChatState.Running && !reduced;
  const turn = useSharedValue(0);
  useEffect(() => {
    if (!turning) { cancelAnimation(turn); turn.value = 0; return; }
    turn.value = 0;
    turn.value = withRepeat(withTiming(360, { duration: 1200, easing: (t: number) => { "worklet"; return t; } }), -1, false);
    return () => cancelAnimation(turn);
  }, [turning, turn]);
  const spin = useAnimatedStyle(() => ({ transform: [{ rotate: `${turn.value}deg` }] }));
  if (state === ChatState.Done) return null;
  const size = 12;
  const r = size / 2;
  const ring = 2;
  // The web's 8px box with a 2px border: the stroke's middle 3px from the centre.
  const rr = r - ring - ring / 2;
  // Round ends (web: styles/busyRing.ts), the arc shortened by the half stroke they add so the gap stays a quarter.
  const cap = ((ring / (rr * 2)) * 180) / Math.PI;
  const from = 45 + cap;
  const sweep = 270 - 2 * cap;
  const at = (deg: number) => {
    const a = (deg * Math.PI) / 180;
    return `${r + rr * Math.cos(a)} ${r + rr * Math.sin(a)}`;
  };
  return (
    <View style={[{ width: size, height: size }, style]}>
      <Svg width={size} height={size} style={{ position: "absolute" }}>
        <Circle cx={r} cy={r} r={r} fill={around} />
        {state === ChatState.Running
          ? <Circle cx={r} cy={r} r={rr} fill="none" stroke={withAlpha(AGENT_YELLOW, 0.25)} strokeWidth={ring} />
          : <Circle cx={r} cy={r} r={r - ring} fill={AGENT_RED} />}
      </Svg>
      {state === ChatState.Running && (
        <Animated.View style={[{ position: "absolute", width: size, height: size }, spin]}>
          <Svg width={size} height={size}>
            <Path d={`M${at(from)}A${rr} ${rr} 0 1 1 ${at(from + sweep)}`} fill="none" stroke={AGENT_YELLOW} strokeWidth={ring} strokeLinecap="round" />
          </Svg>
        </Animated.View>
      )}
    </View>
  );
}

/** An agent: its model maker's mark on a soft tile, with its state as a badge. */
export function ModelMark({ maker, runtime, size = 36, state, around, listMark = false }: { maker: Maker | null | undefined; runtime: string; size?: number; state?: ChatState | null; around?: string; listMark?: boolean }) {
  const C = useC();
  const ground = around ?? C.bg;
  const xs = size < 30;
  const corner = xs ? 6 : 11;
  const corner3: StyleProp<ViewStyle> = { position: "absolute", right: -3, bottom: -3 };
  return (
    <View style={{ width: size, height: size }}>
      <Smooth radius={corner} stroke={{ width: 1, color: C.line }} style={{ width: size, height: size, backgroundColor: C.surface, alignItems: "center", justifyContent: "center" }}>
        <MakerIcon maker={maker} runtime={runtime} size={xs ? size * 0.6 : size * 0.56} />
      </Smooth>
      {listMark
        ? state != null && <AgentStateMark state={state} around={ground} modifier={corner3} />
        : state != null && state !== ChatState.Done && <Badge state={state} size={xs ? 11 : 15} ring={xs ? 1.5 : 2} around={ground} modifier={corner3} />}
    </View>
  );
}

// ── people ─────────────────────────────────────────────────────────────

const AVATAR = ["#5B7BB2", "#2F8F5B", "#B9471F", "#8A6BB0", "#3F8C99", "#B0842F"];

/** Java's String.hashCode, which the Android app picks the colour by. */
function hashCode(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  return h;
}

export function avatarColor(id: string): string {
  const n = AVATAR.length;
  return AVATAR[((hashCode(id.toLowerCase()) % n) + n) % n]!;
}

export function initial(name: string): string {
  const first = name.trim().charAt(0);
  return first ? first.toUpperCase() : "?";
}

export function Avatar({ id, name, size, modifier: modifier_, style = modifier_, picture }: { id: string; name: string; size: number; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; picture?: string | null }) {
  // Their picture (a Google account's) once it is here; their initial on their colour until then, or without one.
  const image = rememberPicture(picture);
  return (
    <View style={[style, { width: size, height: size, borderRadius: size / 2, overflow: "hidden", backgroundColor: avatarColor(id), alignItems: "center", justifyContent: "center" }]}>
      {image != null
        ? <Image source={{ uri: image }} accessibilityLabel={name} style={{ width: size, height: size }} resizeMode="cover" />
        : <T color="#FFFFFF" weight="600" size={size * 0.5} line={size * 0.5}>{initial(name)}</T>}
    </View>
  );
}

/** Pictures by URL as drawn (data URLs), once each for the app's life (the core fetches and keeps their bytes: `picture`). */
const pictures = new Map<string, string>();

function rememberPicture(url: string | null | undefined): string | null {
  const ui = useUi();
  const known = url ? (pictures.get(url) ?? null) : null;
  const [loaded, setLoaded] = useState<{ url: string; uri: string } | null>(null);
  useEffect(() => {
    if (!url || pictures.has(url)) return;
    let live = true;
    ui.core.call("picture", { url }).then(
      (answer) => {
        const { type, bytes } = answer as { type?: string; bytes?: string };
        if (!bytes) return;
        const uri = `data:${type || "image/png"};base64,${bytes}`;
        pictures.set(url, uri);
        if (live) setLoaded({ url, uri });
      },
      () => undefined,
    );
    return () => { live = false; };
  }, [url, ui]);
  return known ?? (loaded && loaded.url === url ? loaded.uri : null);
}

/** People overlapping a little, each ringed in the page's color. */
export function PeopleStack({ people, size = 18, ring }: { people: Person[]; size?: number; ring?: string }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row" }}>
      {people.map((p, i) => (
        <View key={p.id} style={{ transform: [{ translateX: -5 * i }], zIndex: -i, width: size + 3, height: size + 3, borderRadius: (size + 3) / 2, overflow: "hidden", backgroundColor: ring ?? C.bg, alignItems: "center", justifyContent: "center" }}>
          <Avatar id={p.id} name={p.shown.display} size={size} picture={p.shown.picture} />
        </View>
      ))}
    </View>
  );
}

// ── rings ──────────────────────────────────────────────────────────────

/** How full, as a colour: the core's level (ok | amber | red). */
function levelColor(c: StillFailColors, level: string): string {
  return level === "red" ? c.red : level === "amber" ? c.warn : level === "progress" ? c.accent : c.green;
}

/** One window of an allowance (the one an agent is short of) as a chip, its mark before what is left: as the web's QuotaChip. */
export function QuotaChip({ mark, left, level, small = true }: { mark: string; left: number; level: string; small?: boolean }) {
  return <FillChip fill={leftOf(left)} level={level} mark={mark} text={`${left}%`} small={small} />;
}

/** A profile's allowance in a line: the web's chips (QuotaChips), one per window. */
export function QuotaRings({ quota }: { quota: Quota | null | undefined }) {
  return <QuotaChips quota={quota} />;
}

/**
 * A profile's allowance, compact, as the web's QuotaBars draws it: a rounded box per window (shortest first) with what
 * is left written in it (its mark too when there is more than one), its ground filled from the left as far as is left.
 * Its number in the ink's colour while there is plenty, in its colour once it runs low. `small`: a lower line.
 */
export function QuotaChips({ quota, small = false }: { quota: Quota | null | undefined; small?: boolean }) {
  const windows = quota?.state === "ok" ? quota.windows : [];
  if (windows.length === 0) return null;
  const lone = windows.length === 1;
  return (
    <View style={{ flexDirection: "row", gap: 8, alignItems: "center" }}>
      {windows.map((w, i) => <FillChip key={i} fill={leftOf(w.left)} level={w.level} mark={lone ? null : w.mark} text={`${w.left}%`} small={small} />)}
    </View>
  );
}

/**
 * A machine's CPU, memory and disk as an allowance's boxes are drawn (QuotaChips): each its name and what is left, its
 * ground filled as far as is used (a fuller box, less room). `alerts`: only the ones running low, as the web's station
 * cards do.
 */
export function MeterChips({ meters, modifier: modifier_, style = modifier_, alerts = false }: { meters: Meter[]; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; alerts?: boolean }) {
  return (
    <View style={[style, { flexDirection: "row", gap: 8, alignItems: "center" }]}>
      {meters.filter((m) => !alerts || m.level !== "ok").map((m, i) => <FillChip key={i} fill={usedOf(m.left)} level={m.level} mark={m.short} text={m.remaining} />)}
    </View>
  );
}

/** How much of what a runtime's install downloads is in: the allowance's rounded box, filled in the accent as it comes. As the web's ProgressChip. */
export function DownloadChip({ percent }: { percent: number }) {
  return <FillChip fill={Math.min(100, Math.max(0, percent))} level="progress" mark={null} text={`${percent}%`} />;
}

// How far a box is filled or a dial's cells lit, as the web decides it (components.tsx): an allowance as a battery, as
// far as is left; a machine's CPU, memory or disk as a disk's bar, as far as is used, though its words say what is left.
const leftOf = (left: number) => Math.min(100, Math.max(0, left));
const usedOf = (left: number) => 100 - leftOf(left);

/**
 * A rounded box with a figure in it (its mark before it, when given) and its ground filled from the left as far as `fill`
 * (0–100): a quiet grey while it is ok, the colour of the core's level, faintly, once it is not, the figure then in that
 * colour too. Level `progress`: a download's share, in the accent, its fill moving smoothly to each new one. As the
 * web's FillChip (components.tsx).
 */
function FillChip({ fill, level, mark, text, small = false }: { fill: number; level: string; mark: string | null; text: string; small?: boolean }) {
  const c = useC();
  const tone = levelColor(c, level);
  const low = level === "amber" || level === "red";
  const target = Math.min(100, Math.max(0, fill));
  const drawn = useSharedValue(target);
  useEffect(() => {
    drawn.value = level === "progress" ? withTiming(target, { duration: 500, easing: Ease.Standard }) : target;
  }, [target, level, drawn]);
  const filled = useAnimatedStyle(() => ({ width: `${drawn.value}%` }));
  const ground = low || level === "progress" ? withAlpha(tone, 0.2) : withAlpha(c.muted, 0.22);
  const fs = small ? 10 : 11;
  return (
    <Smooth radius={6} style={{ height: small ? 16 : 20, backgroundColor: c.chip, alignItems: "center", justifyContent: "center" }}>
      <Animated.View style={[{ position: "absolute", left: 0, top: 0, bottom: 0, backgroundColor: ground }, filled]} />
      <View style={{ flexDirection: "row", paddingHorizontal: small ? 5 : 8, gap: 5, alignItems: "baseline" }}>
        {/* On one baseline: a mark in Chinese (内存) sits lower in its line than figures do. */}
        {mark != null && <T size={fs} line={fs} weight="600" color={lerpColor(c.ink, c.muted, 0.5)}>{mark}</T>}
        <T size={fs} line={fs} weight="600" color={low ? tone : c.ink}>{text}</T>
      </View>
    </Smooth>
  );
}

/**
 * A profile's allowance on its own page, as the web's QuotaBars draws it there: each window's number large, ten cells
 * lit as far as is left, its name and when it refills. The number is the ink's colour while there is plenty.
 */
export function QuotaDials({ quota, modifier: modifier_, style = modifier_ }: { quota: Quota | null | undefined; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const windows = quota?.state === "ok" ? quota.windows : [];
  if (windows.length === 0) return null;
  return (
    <View style={[style, { flexDirection: "row", flexWrap: "wrap", columnGap: 36, rowGap: 12 }]}>
      {windows.map((w, i) => <Dial key={i} number={`${w.left}`} unit="%" fill={leftOf(w.left)} level={w.level} label={w.label} note={w.refills} style={{ minWidth: 96 }} />)}
    </View>
  );
}

/**
 * A machine's CPU, memory and disk on its own page, as an allowance's windows on its profile's (QuotaDials): each what is
 * left large over its cells (lit as far as is used), what it is and what it is out of. As the web's MeterDials (components.tsx); a row of three
 * that share the width, a phone being narrow.
 */
export function MeterDials({ meters, modifier: modifier_, style = modifier_ }: { meters: Meter[]; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  return (
    <View style={[style, { alignSelf: "stretch", flexDirection: "row", gap: 16 }]}>
      {meters.map((m, i) => <Dial key={i} number={m.big} unit={m.unit} fill={usedOf(m.left)} level={m.level} label={m.title} note={m.total} style={{ flex: 1, minWidth: 0 }} />)}
    </View>
  );
}

/** A figure large, ten cells lit as far as `fill` (0–100) in the colour of its level, its name and a quiet note under. */
function Dial({ number, unit, fill, level, label, note, style }: { number: string; unit: string; fill: number; level: string; label: string; note?: string | null; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  const tone = levelColor(C, level);
  const low = level === "amber" || level === "red";
  const lit = Math.round(fill / 10);
  return (
    <View style={[style, { gap: 2 }]}>
      <View style={{ flexDirection: "row", alignItems: "flex-end" }}>
        <T size={28} line={32} weight="600" style={{ letterSpacing: -0.56 }} color={low ? tone : C.ink} numberOfLines={1}>{number}</T>
        <T size={15} line={26} weight="500" color={C.muted} style={{ paddingLeft: 1 }} numberOfLines={1}>{unit}</T>
      </View>
      <View style={{ flexDirection: "row", paddingTop: 4, paddingBottom: 6, gap: 2 }}>
        {Array.from({ length: 10 }, (_, i) => <View key={i} style={{ width: 7, height: 14, borderRadius: 2, backgroundColor: i < lit ? tone : C.chip }} />)}
      </View>
      <T size={13} weight="500" color={C.ink} numberOfLines={1}>{label}</T>
      <T size={12} color={C.muted} numberOfLines={1}>{note ?? " "}</T>
    </View>
  );
}

/** The rest of a machine, a quiet row each (its hostname, chip, how long it has been up, the process): as the web's HostDetails. */
export function HostDetails({ details, modifier: modifier_, style = modifier_ }: { details: HostDetail[]; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  return (
    <View style={[style, { gap: 8 }]}>
      {details.map((d, i) => (
        <View key={i} style={{ flexDirection: "row", gap: 16 }}>
          <T size={13} line={20} color={C.subtle} style={{ minWidth: 52 }}>{d.label}</T>
          <T size={13} line={20} color={C.muted} style={{ flex: 1 }}>{d.value}</T>
        </View>
      ))}
    </View>
  );
}

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or a key, OpenCode for OpenCode Go. */
export function ProviderMark({ runtime, kind, size = 16, mark }: { runtime: string; kind: string | null | undefined; size?: number; mark?: string | null }) {
  const C = useC();
  if (kind === "opencode-go" || mark === "opencode") {
    const u = size / 24;
    return (
      <Svg width={size} height={size}>
        <Rect x={6 * u} y={4 * u} width={12 * u} height={16 * u} fill="none" stroke={C.ink} strokeWidth={2.4 * u} />
      </Svg>
    );
  }
  // A key on a listed provider: its maker's mark, or the generic plug where there is none.
  if (kind === "api-provider") {
    if (mark != null && mark in MAKER_MARKS) return <MakerIcon maker={{ id: mark, name: mark }} runtime={runtime} size={size} />;
    return <IconIn icon={Icons.Plug} size={size} tint={C.ink} />;
  }
  return <MakerIcon maker={runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : { id: "openai", name: "OpenAI" }} runtime={runtime} size={size} />;
}

// ── controls ───────────────────────────────────────────────────────────

/** Whether the person asked for less motion (animations off in the system settings). */
export function reducedMotion(): boolean {
  return useReducedMotion();
}

/**
 * A segmented choice: a track that tints whatever it sits on (the text colour
 * at 6%), and a light thumb that slides to the chosen option. Without `track`
 * what it sits in (a capsule) is its track.
 */
export function Seg({ options, selected, onSelect, modifier: modifier_, style = modifier_, height = 30, fill = false, radius = 10, inset = 2, track = true }: {
  options: string[]; selected: number; onSelect: (i: number) => void; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; height?: number; fill?: boolean; radius?: number; inset?: number; track?: boolean;
}) {
  const C = useC();
  // Where each option sits in the track: (x, width).
  const [places, setPlaces] = useState<[number, number][]>(() => options.map(() => [0, 0]));
  const known = useRef(options);
  if (known.current !== options && known.current.join("\u0000") !== options.join("\u0000")) {
    known.current = options;
    setPlaces(options.map(() => [0, 0]));
  }
  const x = useSharedValue(0);
  const w = useSharedValue(0);
  const [shown, setShown] = useState(false);
  const still = reducedMotion();
  const [tx, tw] = places[selected] ?? [0, 0];
  useEffect(() => {
    if (tw === 0) return;
    // The first placement and reduced motion jump; a change of choice slides.
    if (w.value === 0 || still) { x.value = tx; w.value = tw; setShown(true); return; }
    const ease = { duration: 240, easing: Ease.Decel };
    x.value = withTiming(tx, ease);
    w.value = withTiming(tw, ease);
  }, [tx, tw, still, x, w]);
  const thumb = useAnimatedStyle(() => ({ transform: [{ translateX: x.value }], width: w.value }));
  const thumbRadius = Math.max(0, radius - inset);
  return (
    <Smooth radius={radius} style={[{ alignSelf: "flex-start" }, style, { height, padding: inset }, track && { backgroundColor: withAlpha(C.ink, 0.06) }]}>
      {shown && (
        <Animated.View style={[{ position: "absolute", left: inset, top: inset, bottom: inset }, thumb]}>
          {/* In a capsule, a soft tint of the text colour: the capsule's glass shows through it. On a track, a light
              thumb with a hairline all round, not an elevation shadow (which falls below and makes it look low). */}
          {!track
            ? <Smooth radius={thumbRadius} style={{ flex: 1, backgroundColor: withAlpha(C.ink, C.dark ? 0.13 : 0.08) }} />
            : <Smooth radius={thumbRadius} stroke={{ width: 0.5, color: C.line }} style={{ flex: 1, backgroundColor: C.dark ? "#3A3B40" : "#FFFFFF" }} />}
        </Animated.View>
      )}
      <View style={[{ flexDirection: "row", height: "100%" }, fill && { alignSelf: "stretch" }]}>
        {options.map((label, i) => (
          <Pressable
            key={i}
            onLayout={(e) => {
              const { x: px, width } = e.nativeEvent.layout;
              setPlaces((was) => {
                const at = was[i];
                if (at && at[0] === px && at[1] === width) return was;
                const next = options.map((_, k) => was[k] ?? ([0, 0] as [number, number]));
                next[i] = [px, width];
                return next;
              });
            }}
            onPress={() => onSelect(i)}
            style={[{ height: "100%", paddingHorizontal: fill ? 12 : 10, alignItems: "center", justifyContent: "center" }, fill && { flex: 1 }]}
          >
            <T size={fill ? 14 : 13} weight={i === selected && !track ? "600" : undefined} color={i === selected ? C.ink : C.muted} numberOfLines={1}>{label}</T>
          </Pressable>
        ))}
      </View>
    </Smooth>
  );
}

export function IconIn({ icon, size = 18, tint, modifier: modifier_, style = modifier_ }: { icon: IconPaths; size?: number; tint?: string; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle> }) {
  const C = useC();
  return (
    <View style={[{ width: size, height: size }, style]}>
      <Icon icon={icon} size={size} color={tint ?? C.ink} />
    </View>
  );
}

/**
 * A station where it is named (web/src/StationMark.tsx): its `icon` first, one of still.fail's (glyph:<name>, StationIcons;
 * glyph:<name>:<colour> in one of MARK_COLORS, else `tint`) or a picture put up (a data URL); else its emoji; else `none`
 * (nothing when null). A glyph this build does not know shows the emoji kept beside it.
 */
export function StationMark({ emoji, icon, size, tint, modifier: modifier_, style = modifier_, none }: { emoji: string | null | undefined; icon: string | null | undefined; size: number; tint: string; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; none?: IconPaths | null }) {
  const glyph = StationIcons.of(icon);
  const picture = useMemo(() => stationPicture(icon), [icon]);
  const color = markColor(glyphColor(icon));
  if (glyph != null) return <IconIn icon={glyph.icon} size={size} tint={color ?? tint} modifier={style} />;
  if (picture != null) {
    return (
      <Smooth radius={size * 0.24} style={[style, { width: size, height: size }]}>
        <Image source={picture} style={{ width: size, height: size }} resizeMode="cover" />
      </Smooth>
    );
  }
  if (emoji != null) return <T size={size * 0.9} line={size} style={style as never}>{emoji}</T>;
  if (none != null) return <IconIn icon={none} size={size} tint={tint} modifier={style} />;
  return null;
}

/** The colours a glyph can be given, in the picker's order (web/src/StationMark.tsx's MARK_COLORS). */
export const MARK_COLORS = ["red", "orange", "amber", "green", "teal", "blue", "purple", "pink"];

/** The colour a glyph was given (glyph:<name>:<colour>); null for none, or one this build does not know. */
export function glyphColor(icon: string | null | undefined): string | null {
  if (!icon?.startsWith("glyph:")) return null;
  const rest = icon.slice("glyph:".length);
  const at = rest.indexOf(":");
  const color = at < 0 ? "" : rest.slice(at + 1);
  return MARK_COLORS.includes(color) ? color : null;
}

/** A colour of MARK_COLORS for the theme in use (web/src/StationMark.css.ts's); null for none. A hook (C). */
export function markColor(color: string | null | undefined): string | null {
  const C = useC();
  if (color == null) return null;
  return (C.dark ? MARK_DARK : MARK_LIGHT)[color] ?? null;
}

const MARK_LIGHT: Record<string, string> = {
  red: "#BC4945", orange: "#B75400", amber: "#A16700", green: "#0E8C41",
  teal: "#008D90", blue: "#2D74CA", purple: "#835CBE", pink: "#B24981",
};
const MARK_DARK: Record<string, string> = {
  red: "#FB9890", orange: "#F5A06F", amber: "#E0AE57", green: "#7CCD8E",
  teal: "#3BCFCF", blue: "#82BAFF", purple: "#C3A5F9", pink: "#F197C2",
};

/** Whether a station has anything to be shown by (StationMark draws nothing for it otherwise). */
export function hasStationMark(emoji: string | null | undefined, icon: string | null | undefined): boolean {
  return !!emoji || !!icon;
}

/** A picture put up as a station's icon (a data URL), as an Image's source; null for none or one that is not. */
export function stationPicture(icon: string | null | undefined): { uri: string } | null {
  if (icon == null || !icon.startsWith("data:image/") || !icon.includes("base64,")) return null;
  return { uri: icon };
}

// ── navigation ─────────────────────────────────────────────────────────

/** Back, in the accent color, with where it goes back to. */
export function NavBack({ label, onClick }: { label: string; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={8}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", paddingRight: 6, paddingTop: 4, paddingBottom: 4 }}>
        <IconIn icon={Icons.ChevronLeft} size={22} tint={C.accent} />
        <T size={17} color={C.accent}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** A round chip-colored button in a bar. */
export function NavButton({ icon, onClick, iconSize = 18 }: { icon: IconPaths; onClick: () => void; iconSize?: number }) {
  const C = useC();
  // The icon alone, no disc behind it: a bar's buttons are quiet.
  return (
    <View style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden" }}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}>
        <IconIn icon={icon} size={iconSize} />
      </Pressable>
    </View>
  );
}

/** A page's compact bar: back, a centered title, and one action. No line under it: the page's paper runs on. */
export function NavBar({ back, onBack, title, sub, trailing }: { back: string; onBack: () => void; title: string; sub?: (() => ReactNode) | null; trailing?: (() => ReactNode) | null }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ alignSelf: "stretch", backgroundColor: C.bg, paddingTop: insets.top }}>
      <View style={{ paddingLeft: 10, paddingRight: 16, paddingTop: 6, paddingBottom: 10, minHeight: 6 + 32 + 10 }}>
        {/* As the web's (mobile/parts.css.ts mNavbar): the buttons and the title's first line share one 32dp line at the
            top; a title's second line (sub) hangs below it rather than pushing the title up off the back button's line. */}
        <View style={{ alignSelf: "stretch", paddingHorizontal: 84, alignItems: "center" }}>
          <View style={{ height: 30, alignItems: "center", justifyContent: "center" }}>
            <T size={16} weight="600" color={C.ink} numberOfLines={1} ellipsizeMode="tail" align="center">{title}</T>
          </View>
          <View style={{ height: 2 }} />
          {sub != null && <View style={{ transform: [{ translateY: -4 }], flexDirection: "row", alignItems: "center", gap: 5 }}>{sub()}</View>}
        </View>
        <View style={{ position: "absolute", left: 10, top: 6, height: 32, justifyContent: "center" }}>
          <NavBack label={back} onClick={onBack} />
        </View>
        {trailing != null && <View style={{ position: "absolute", right: 16, top: 6, height: 32, justifyContent: "center", alignItems: "flex-end" }}>{trailing()}</View>}
      </View>
    </View>
  );
}

/** A page's large title (stations, settings): a small line over a big word; none when `small` is empty. `lead` goes before the word (a workspace's mark). */
export function LargeTitle({ small, big, lead }: { small: string; big: string; lead?: (() => ReactNode) | null }) {
  const C = useC();
  const word = <T size={32} weight="700" color={C.ink} style={{ letterSpacing: -0.6 }}>{big}</T>;
  return (
    <View style={{ paddingLeft: 16, paddingRight: 16, paddingBottom: 6 }}>
      {small.length > 0 && <T size={13} color={C.muted}>{small}</T>}
      {lead == null ? word : <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>{lead()}{word}</View>}
    </View>
  );
}

// ── lists and cards ────────────────────────────────────────────────────

export function SectionHeader({ title, trailing, start = 20 }: { title: string; trailing?: string | null; start?: number }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", flexDirection: "row", alignItems: "flex-end", paddingLeft: start, paddingRight: 20, paddingTop: 14, paddingBottom: 6 }}>
      <T size={15} weight="600" color={C.ink}>{title}</T>
      <View style={{ flex: 1 }} />
      {trailing != null && <T size={13} color={C.muted}>{trailing}</T>}
    </View>
  );
}

export function Card({ modifier: modifier_, style = modifier_, onClick, content, children: kids }: { modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; onClick?: (() => void) | null; content?: () => ReactNode; children?: ReactNode }) {
  const C = useC();
  const children = content ? content() : kids;
  const inner: ViewStyle = { paddingHorizontal: 16, paddingVertical: 14 };
  return (
    <View style={[style, { paddingHorizontal: 12, paddingBottom: 10, alignSelf: "stretch" }]}>
      <Smooth radius={20} style={{ backgroundColor: C.surface }}>
        {onClick != null
          ? <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={inner}>{children}</Pressable>
          : <View style={inner}>{children}</View>}
      </Smooth>
    </View>
  );
}

/** Rows on one rounded card; the card groups them, no lines between. */
export function ListCard({ modifier: modifier_, style = modifier_, content, children: kids }: { modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; content?: () => ReactNode; children?: ReactNode }) {
  const C = useC();
  const children = content ? content() : kids;
  return (
    <View style={[style, { paddingHorizontal: 12, paddingBottom: 10, alignSelf: "stretch" }]}>
      <Smooth radius={16} style={{ backgroundColor: C.surface }}>{children}</Smooth>
    </View>
  );
}

export function ListRow({ onClick, content, children: kids }: { onClick?: (() => void) | null; content?: () => ReactNode; children?: ReactNode }) {
  const C = useC();
  const children = content ? content() : kids;
  const row: ViewStyle = { alignSelf: "stretch", flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 12 };
  if (onClick == null) return <View style={row}>{children}</View>;
  return <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={row}>{children}</Pressable>;
}

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure).
 */
export function Splash({ label, now = false }: { label?: string | null; now?: boolean }) {
  const C = useC();
  const still = reducedMotion();
  const lift = useSharedValue(0);
  useEffect(() => {
    lift.value = withRepeat(withTiming(1, { duration: 900, easing: Ease.Standard }), -1, true);
    return () => cancelAnimation(lift);
  }, [lift]);
  const [shown, setShown] = useState(now);
  useEffect(() => {
    if (now) { setShown(true); return; }
    const id = setTimeout(() => setShown(true), 1000);
    return () => clearTimeout(id);
  }, [now]);
  const float = useAnimatedStyle(() => ({ transform: [{ translateY: still ? 0 : -lift.value * 5 }] }));
  return (
    <View style={{ flex: 1, alignSelf: "stretch", backgroundColor: C.bg, padding: 24, alignItems: "center", justifyContent: "center", gap: 16 }}>
      <Animated.View style={float}><Mark size={56} /></Animated.View>
      {label != null && <T color={C.muted} size={13} align="center" style={{ opacity: shown ? 1 : 0 }}>{label}</T>}
    </View>
  );
}

export function Mark({ size = 14 }: { size?: number }) {
  const C = useC();
  return <Drawing name={C.dark ? "stillfail_mark_dark" : "stillfail_mark"} width={size} height={size} />;
}

export function SlackMark({ size = 13 }: { size?: number }) {
  return <Drawing name="slack" width={size} height={size} />;
}
