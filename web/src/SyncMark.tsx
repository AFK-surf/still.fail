// The list catching up on what changed while away (the chats' `syncing`; docs/ui-panels.md 等待): beside the list's
// filter, the refresh mark turning in the grey of what says nothing (a turn each 1.4s, slow at its ends), its words its
// tip and what it is said to be. Only once it has gone on a while (LATER_MS): a moment's catching up shows nothing. Once
// all is here, it becomes a tick: it goes on from where it is and as fast as it turns, slowing to rest where it looks
// upright again (`settle`), its arrows drawn back along their strokes, then the tick drawn as a hand ticks (no two marks
// fading over each other); there a second, then it fades. As mbui's `@sf.sync_key`.
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import { Svg } from "@stillfail/ui/icons.tsx";
import { Tip } from "@stillfail/ui/parts.tsx";
import { LATER_MS } from "@stillfail/ui/waiting.css.ts";
import { STILL } from "@stillfail/ui/styles/still.ts";
import * as css from "./SyncMark.css.ts";

/** A turn; how long it takes to come to rest, at least and at most; how far on in that the arrows start to go; how
 *  near rest (of a turn's 2π) it may stop where it is. */
const TURN_MS = 1400;
const SETTLE_LEAST = 150;
const SETTLE_MOST = 700;
const GONE = 0.8;
const NEAR = 0.03;
/** How long the arrows take to be drawn back and the tick to be drawn (begun as they are mostly back), how long the
 *  tick stays, and how long it takes to fade. */
const BACK_MS = 180;
const TICK_MS = 240;
const DONE_MS = 1000;
const OUT_MS = 400;

export function SyncMark({ syncing, size = 32, mark = 16 }: { syncing: string | null | undefined; size?: number; mark?: number }) {
  const on = !!syncing;
  const [phase, setPhase] = useState<"none" | "on" | "done" | "out">("none");
  // how long it takes to come to rest, once taken over (the tick's way starts then: data-ticked)
  const [settle, setSettle] = useState<number | null>(null);
  // (turning again after a tick: its own turn anew, the one taken over gone)
  const [round, setRound] = useState(0);
  const turning = useRef<HTMLSpanElement>(null);
  const said = useRef("");
  if (syncing) said.current = syncing;
  useEffect(() => {
    if (on) {
      const at = setTimeout(() => setPhase("on"), LATER_MS);
      return () => clearTimeout(at);
    }
    // Gone: what showed becomes a tick, then fades; what had not shown yet, nothing.
    setPhase((was) => (was === "on" ? "done" : "none"));
    return undefined;
  }, [on]);
  // Done: the turn taken over where it is, brought to rest (before it is painted done)
  const taken = useRef(false);
  useLayoutEffect(() => {
    const el = turning.current;
    if (phase === "on" && taken.current) {
      taken.current = false;
      setSettle(null);
      setRound((r) => r + 1);
    }
    if (phase !== "done" || !el) return;
    taken.current = true;
    setSettle(settleTurn(el) * GONE);
  }, [phase]);
  useEffect(() => {
    if (phase !== "done" && phase !== "out") return;
    const at = setTimeout(() => setPhase(phase === "done" ? "out" : "none"), phase === "done" ? (settle ?? 0) + BACK_MS + TICK_MS + DONE_MS : OUT_MS);
    return () => clearTimeout(at);
  }, [phase, settle]);
  if (phase === "none") return null;
  return (
    <Tip label={said.current}>
      <span className={css.syncMark} style={{ width: size, height: size, "--settle": `${settle ?? 0}ms` } as CSSProperties} data-phase={phase}
        data-ticked={settle !== null || undefined}
        role="status" aria-label={said.current} tabIndex={0}>
        <span key={round} ref={turning} className={css.syncTurning}>
          {/* refresh (icons.tsx), each curve from where its head is, each head's two strokes from their corner */}
          <Svg size={mark}>
            <path className={css.syncBack} pathLength={1} d="M20 9Q18.5 3.5 12 3.5Q7.5 3.5 5 7 M20 9V4 M20 9H15" />
            <path className={css.syncBack} pathLength={1} d="M4 15Q5.5 20.5 12 20.5Q16.5 20.5 19 17" />
            <path className={css.syncBack} pathLength={1} d="M4 15V20" />
            <path className={css.syncBack} pathLength={1} d="M4 15H9" />
          </Svg>
        </span>
        <span className={css.syncTickAt}>
          <Svg size={mark}><path className={css.syncTick} pathLength={1} d="M4.5 12L9.5 17L19.5 6.5" /></Svg>
        </span>
      </span>
    </Tip>
  );
}

/** The mark's turn on `el` taken over where it is and as fast as it goes, slowing evenly to rest on the next half turn
 *  on (two arrows: the same turned half round) without going back; how long that takes (none where it is at rest there
 *  already, or with motion reduced). As mbui's `sync_rest`. */
function settleTurn(el: HTMLElement): number {
  const turn = el.getAnimations()[0];
  const t = turn?.currentTime;
  if (!turn || typeof t !== "number" || document.querySelector(STILL)) {
    turn?.cancel();
    return 0;
  }
  const m = new DOMMatrix(getComputedStyle(el).transform);
  const from = (Math.atan2(m.b, m.a) + 2 * Math.PI) % (2 * Math.PI);
  // as fast as it turns there (its ease, near enough smoothstep's)
  const k = (t % TURN_MS) / TURN_MS;
  const speed = (6 * k * (1 - k) * 2 * Math.PI) / TURN_MS;
  turn.cancel();
  if (from - Math.floor(from / Math.PI) * Math.PI <= NEAR && speed * SETTLE_LEAST <= NEAR) return 0;
  // a cubic from `speed` to none goes back unless what it has to go is at least a third of `speed` over its time
  let to = Math.ceil((from - NEAR) / Math.PI) * Math.PI;
  while (to <= from || speed * SETTLE_LEAST > 3 * (to - from)) to += Math.PI;
  const ms = Math.min(SETTLE_MOST, Math.max(SETTLE_LEAST, speed > 0 ? (2 * (to - from)) / speed : SETTLE_MOST));
  // (the cubic as an ease: leaving at its speed, a third of the way along)
  const lead = (ms * speed) / (to - from) / 3;
  el.animate([{ transform: `rotate(${from}rad)` }, { transform: `rotate(${to}rad)` }], {
    duration: ms, easing: `cubic-bezier(0.3333, ${lead}, 0.6667, 1)`,
  });
  return ms;
}
