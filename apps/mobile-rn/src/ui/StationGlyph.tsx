// The stations at a glance, for the corner of the home bar, drawn as the web's (web/src/StationGlyph.tsx):
// a circle cut into one equal arc per station with the bottom slot left open, the still.fail robot in the middle.
// Online arcs are ink and the rest a faint track; past six stations the arcs join into one bar filled to the share
// online. A station whose link is on its way follows the online ones, its arc pulsing. A station failing drops out of
// the ring into the open slot as a red dot (two at most). The robot blinks one eye while one station works and both
// while more do; with the phone itself offline it sleeps and the whole fades.
import { useEffect, useId } from "react";
import { View } from "react-native";
import Animated, { Easing, cancelAnimation, useAnimatedProps, useSharedValue, withRepeat, withSequence, withTiming } from "react-native-reanimated";
import Svg, { Circle, Defs, Ellipse, G, Line, Mask, Path, Rect } from "react-native-svg";
import type { ChatsView } from "../../../../web/src/core/shapes.ts";
import { Ease } from "./Motion";
import { reducedMotion } from "./Parts";
import { useC } from "./Theme";

/** `connecting` is of `dim`: those whose link is on its way. */
export interface GlyphCounts { online: number; dim: number; failing: number; working: number; asleep: boolean; connecting?: number }

/** An arc on the ring, angles in degrees clockwise from 12 o'clock; `lit` is ink, otherwise the track; `pulse` connecting. */
export interface GlyphArc { from: number; to: number; lit: boolean; pulse: boolean }

// All in the web's 24-unit box.
const CX = 12;
const CY = 12;
const R = 9.7;
const W = 1.8;
const GAP = 1.7;
const MAX_ARCS = 6;
const TRACK = 0.18;
const MAX_DOTS = 2;
const GAP_DEG = (((GAP + W) / R) * 180) / Math.PI;

const arc = (from: number, to: number, lit: boolean, pulse = false): GlyphArc => ({ from, to, lit, pulse });

/** Where every part goes: the same as the web's glyphLayout. */
export function glyphLayout(c: GlyphCounts): [GlyphArc[], number[]] {
  const ring = c.online + c.dim;
  const connecting = Math.min(Math.max(c.connecting ?? 0, 0), c.dim);
  const arcs: GlyphArc[] = [];
  if (ring > MAX_ARCS) {
    const slot = 360 / (MAX_ARCS + 1);
    const from = 180 + slot / 2 + GAP_DEG / 2;
    const to = 540 - slot / 2 - GAP_DEG / 2;
    arcs.push(arc(from, to, false));
    const lit = from + ((to - from) * c.online) / ring;
    if (connecting > 0) arcs.push(arc(lit, from + ((to - from) * (c.online + connecting)) / ring, false, true));
    if (c.online > 0) arcs.push(arc(from, lit, true));
  } else if (ring > 0) {
    const slot = 360 / (ring + 1);
    for (let i = 0; i < ring; i++) {
      const mid = 180 + slot * (i + 1);
      arcs.push(arc(mid - slot / 2 + GAP_DEG / 2, mid + slot / 2 - GAP_DEG / 2, i < c.online, i >= c.online && i < c.online + connecting));
    }
  }
  const k = Math.min(c.failing, MAX_DOTS);
  const step = ((3.1 / R) * 180) / Math.PI;
  return [arcs, Array.from({ length: Math.max(0, k) }, (_, i) => 180 + (i - (k - 1) / 2) * step)];
}

/** What the glyph draws: the core's counts for the list (its `glyph`), asleep while the core reaches nothing at all. */
export function glyphCounts(view: ChatsView | null | undefined, asleep: boolean): GlyphCounts {
  const g = view?.glyph;
  return { online: g?.online ?? 0, dim: g?.dim ?? 0, failing: g?.failing ?? 0, working: g?.working ?? 0, asleep, connecting: g?.connecting ?? 0 };
}

/** An arc of the ring as a path: from `from` to `to`, degrees clockwise from 12 o'clock, in units of `u`. */
function arcPath(from: number, to: number, u: number): string {
  const p = (deg: number) => {
    const r = (deg * Math.PI) / 180;
    return `${(CX + R * Math.sin(r)) * u} ${(CY - R * Math.cos(r)) * u}`;
  };
  const sweep = to - from;
  if (sweep <= 0) return "";
  return `M${p(from)}A${R * u} ${R * u} 0 ${sweep > 180 ? 1 : 0} 1 ${p(to)}`;
}

const AnimatedPath = Animated.createAnimatedComponent(Path);
const AnimatedEllipse = Animated.createAnimatedComponent(Ellipse);

export function StationGlyph({ counts, size = 24, tint }: { counts: GlyphCounts; size?: number; tint?: string }) {
  const C = useC();
  const [arcs, dots] = glyphLayout(counts);
  const ink = tint ?? C.ink;
  const red = C.red;
  const blinking = counts.asleep ? 0 : counts.working;
  const still = reducedMotion();
  const mask = `glyph-${useId().replace(/:/g, "")}`;

  // A blink: open most of the time, shut for a moment (the web's 2.6s, shut at 93%).
  const eye = useSharedValue(1);
  const blinks = blinking > 0 && !still;
  useEffect(() => {
    if (!blinks) { cancelAnimation(eye); eye.value = 1; return; }
    eye.value = 1;
    eye.value = withRepeat(withSequence(
      withTiming(1, { duration: 2288, easing: Easing.linear }),
      withTiming(0.1, { duration: 130, easing: Easing.linear }),
      withTiming(1, { duration: 182, easing: Easing.linear }),
    ), -1, false);
    return () => cancelAnimation(eye);
  }, [blinks, eye]);

  // A link on its way: its arc breathes between the track and ink (the web's 1.4s); held halfway with motion reduced.
  const pulse = useSharedValue(0.5);
  const pulses = arcs.some((a) => a.pulse) && !still;
  useEffect(() => {
    if (!pulses) { cancelAnimation(pulse); pulse.value = 0.5; return; }
    pulse.value = TRACK;
    pulse.value = withRepeat(withTiming(0.85, { duration: 700, easing: Ease.Standard }), -1, true);
    return () => cancelAnimation(pulse);
  }, [pulses, pulse]);
  const pulseProps = useAnimatedProps(() => ({ strokeOpacity: pulse.value }));

  const u = size / 24;
  const ry0 = useAnimatedProps(() => {
    const ry = 1.25 * (blinking >= 2 ? eye.value : 1);
    return { ry: ry * u };
  });
  const ry1 = useAnimatedProps(() => {
    const ry = 1.25 * (blinking >= 1 ? eye.value : 1);
    return { ry: ry * u };
  });

  return (
    <View style={{ width: size, height: size, opacity: counts.asleep ? 0.4 : 1 }}>
      <Svg width={size} height={size}>
        <Defs>
          {/* What the robot's face has cut out of it: its eyes, or shut ones asleep (BlendMode.Clear there). */}
          <Mask id={mask} x="0" y="0" width={size} height={size} maskUnits="userSpaceOnUse">
            <Rect x={0} y={0} width={size} height={size} fill="#fff" />
            {counts.asleep ? (
              [[9.2, 10.8], [13.2, 14.8]].map(([a, b], i) => (
                <Line key={i} x1={a! * u} y1={12.1 * u} x2={b! * u} y2={12.1 * u} stroke="#000" strokeWidth={1.2 * u} strokeLinecap="round" />
              ))
            ) : (
              <>
                <AnimatedEllipse cx={10.3 * u} cy={12 * u} rx={1.1 * u} ry={1.25 * u} fill="#000" animatedProps={ry0} />
                <AnimatedEllipse cx={13.7 * u} cy={12 * u} rx={1.1 * u} ry={1.25 * u} fill="#000" animatedProps={ry1} />
              </>
            )}
          </Mask>
        </Defs>
        {arcs.map((a, i) =>
          a.pulse && !a.lit ? (
            <AnimatedPath key={i} d={arcPath(a.from, a.to, u)} stroke={ink} strokeWidth={W * u} strokeLinecap="round" fill="none" animatedProps={pulseProps} />
          ) : (
            <Path key={i} d={arcPath(a.from, a.to, u)} stroke={ink} strokeOpacity={a.lit ? 1 : TRACK} strokeWidth={W * u} strokeLinecap="round" fill="none" />
          ),
        )}
        {dots.map((d, i) => {
          const r = (d * Math.PI) / 180;
          return <Circle key={`d${i}`} cx={(CX + R * Math.sin(r)) * u} cy={(CY - R * Math.cos(r)) * u} r={1.25 * u} fill={red} />;
        })}
        <G mask={`url(#${mask})`}>
          <Rect x={7.1 * u} y={7.9 * u} width={9.8 * u} height={8.2 * u} rx={3 * u} ry={3 * u} fill={ink} />
        </G>
      </Svg>
    </View>
  );
}
