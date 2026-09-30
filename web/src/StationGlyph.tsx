// The stations at a glance: the phone's home bar has it in its corner, the wide screen's sidebar at its foot (the
// Android app's ui/StationGlyph.kt draws the same):
// a circle cut into one equal arc per station with the bottom slot left open, the still.fail robot in the middle.
// Online arcs are ink and the rest a faint track; past six stations the arcs join into one bar filled to the share
// online. A station failing drops out of the ring into the open slot as a red dot (two at most). The robot blinks one
// eye while one station works and both while more do; with the phone itself offline it sleeps and the whole fades.
import { useId } from "react";
import type { ChatsView } from "./api.ts";
import * as css from "./StationGlyph.css.ts";

export interface GlyphCounts { online: number; dim: number; failing: number; working: number; asleep: boolean }

const CX = 12, CY = 12, R = 9.7, W = 1.8, GAP = 1.7, MAX_ARCS = 6, TRACK = 0.18, MAX_DOTS = 2;
const GAP_DEG = ((GAP + W) / R) * 180 / Math.PI;

/** An arc on the ring, angles in degrees clockwise from 12 o'clock; `lit` is ink, otherwise the track. */
export interface GlyphArc { from: number; to: number; lit: boolean }

/** Where every part goes, shared in shape with the Android app so the two draw the same thing. */
export function glyphLayout(c: GlyphCounts): { arcs: GlyphArc[]; dots: number[] } {
  const ring = c.online + c.dim, arcs: GlyphArc[] = [];
  if (ring > MAX_ARCS) {
    const slot = 360 / (MAX_ARCS + 1), from = 180 + slot / 2 + GAP_DEG / 2, to = 540 - slot / 2 - GAP_DEG / 2;
    arcs.push({ from, to, lit: false });
    if (c.online) arcs.push({ from, to: from + (to - from) * c.online / ring, lit: true });
  } else if (ring) {
    const slot = 360 / (ring + 1);
    for (let i = 0; i < ring; i++) {
      const mid = 180 + slot * (i + 1);
      arcs.push({ from: mid - slot / 2 + GAP_DEG / 2, to: mid + slot / 2 - GAP_DEG / 2, lit: i < c.online });
    }
  }
  const k = Math.min(c.failing, MAX_DOTS), step = (3.1 / R) * 180 / Math.PI;
  const dots = Array.from({ length: k }, (_, i) => 180 + (i - (k - 1) / 2) * step);
  return { arcs, dots };
}

/** What the glyph draws: the core's counts for the list (its `glyph`), asleep while the core reaches nothing at all. */
export function glyphCounts(view: ChatsView | undefined, asleep: boolean): GlyphCounts {
  const g = view?.glyph;
  return { online: g?.online ?? 0, dim: g?.dim ?? 0, failing: g?.failing ?? 0, working: g?.working ?? 0, asleep };
}

const at = (deg: number, r = R) => [CX + r * Math.sin(deg * Math.PI / 180), CY - r * Math.cos(deg * Math.PI / 180)] as const;
const n = (v: number) => +v.toFixed(3);
function arcPath(from: number, to: number) {
  const [x0, y0] = at(from), [x1, y1] = at(to);
  return `M${n(x0)} ${n(y0)}A${R} ${R} 0 ${to - from > 180 ? 1 : 0} 1 ${n(x1)} ${n(y1)}`;
}

export function StationGlyph({ counts, size = 24 }: { counts: GlyphCounts; size?: number }) {
  // Only characters a url(#…) takes as they are: CSS.escape is not there when the site is rendered ahead (SSR).
  const mask = `station-glyph-${useId().replace(/[^\w-]/g, "")}`;
  const { arcs, dots } = glyphLayout(counts);
  const blinking = counts.asleep ? 0 : counts.working;
  return (
    <svg className={css.stationGlyph} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
      <defs>
        <mask id={mask}>
          <rect width="24" height="24" fill="#fff" />
          {counts.asleep
            ? <path d="M9.2 12.1H10.8M13.2 12.1H14.8" stroke="#000" strokeWidth="1.2" strokeLinecap="round" />
            : [10.3, 13.7].map((x, i) => <ellipse key={x} className={css.glyphEye} cx={x} cy="12" rx="1.1" ry="1.25" fill="#000"
                data-blink={blinking >= (i ? 1 : 2) || undefined} />)}
        </mask>
      </defs>
      <g className={css.glyphPart} opacity={counts.asleep ? 0.4 : 1}>
        {arcs.map((a, i) => <path key={i} className={css.glyphPart} d={arcPath(a.from, a.to)} fill="none" stroke="currentColor"
          strokeWidth={W} strokeLinecap="round" strokeOpacity={a.lit ? 1 : TRACK} />)}
        {dots.map((d) => { const [x, y] = at(d); return <circle key={d} cx={n(x)} cy={n(y)} r="1.25" className={css.glyphDot} />; })}
        <rect x="7.1" y="7.9" width="9.8" height="8.2" rx="3" fill="currentColor" mask={`url(#${mask})`} />
      </g>
    </svg>
  );
}
