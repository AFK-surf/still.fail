// Motion driven from script (the `motion` library), for what moves because of something else or has to carry on from
// wherever it is when where it goes changes: it starts from the value and the speed it has, instead of a CSS
// transition's fixed run from a fixed start, which lags a goal that moves and jumps when cut off. CSS transitions stay
// for a thing's own look (hover, colour, opacity, a bar's fill).
import { animate, motionValue, type AnimationPlaybackControls, type MotionValue } from "motion";

export { animate, type AnimationPlaybackControls };

/** The page's --ease-out. */
export const EASE_OUT = [0.2, 0.7, 0.2, 1] as const;
/** How the small web services and what makes way for them move (Previews.tsx): a spring, so a goal that moves on while
 * they are on their way (a slot easing in, the room changing again) is followed smoothly, not restarted. */
export const MOVE = { type: "spring", visualDuration: 0.28, bounce: 0 } as const;

export const reducedMotion = (): boolean => matchMedia("(prefers-reduced-motion: reduce)").matches;

/**
 * A number drawn by `draw` whenever it changes: `to` goes there from where it is (at the speed it has, if it is still
 * on its way), `jump` is there at once. Going to where it is already going changes nothing.
 */
export interface Follower { readonly value: number; readonly moving: boolean; to(goal: number, transition?: object): void; jump(goal: number): void; stop(): void }
export function follower(start: number, draw: (value: number) => void): Follower {
  const value: MotionValue<number> = motionValue(start);
  value.on("change", draw);
  let goal = start;
  let run: AnimationPlaybackControls | null = null;
  return {
    get value() { return value.get(); },
    get moving() { return run !== null; },
    to(next, transition = MOVE) {
      if (next === goal && (run || value.get() === next)) return;
      goal = next;
      if (reducedMotion()) return this.jump(next);
      run = animate(value, next, transition);
      void run.finished.then(() => { if (goal === next) run = null; }, () => {});
    },
    jump(next) {
      run?.stop();
      run = null;
      goal = next;
      value.jump(next);
      draw(next);
    },
    stop() { run?.stop(); run = null; value.destroy(); },
  };
}

const changing = new WeakMap<HTMLElement, AnimationPlaybackControls>();
/**
 * Does `change` (a class or an attribute that lays things out anew) and moves each of `moves`' properties from where
 * it shows now to where the change puts it; cut off by the next one, that goes on from wherever this had got to. The
 * rules stay the truth: the values it holds while moving are let go of when it ends.
 */
export function moveState(moves: [HTMLElement, string[]][], change: () => void, transition: object = { duration: 0.38, ease: EASE_OUT }): void {
  const from = moves.map(([el, props]) => { const style = getComputedStyle(el); return props.map((p) => style.getPropertyValue(p)); });
  for (const [el, props] of moves) {
    changing.get(el)?.stop();
    changing.delete(el);
    for (const p of props) el.style.removeProperty(p);
  }
  change();
  if (reducedMotion()) return;
  moves.forEach(([el, props], i) => {
    const style = getComputedStyle(el);
    const frames: Record<string, [string, string]> = {};
    props.forEach((p, j) => { const to = style.getPropertyValue(p); if (to !== from[i]![j]) frames[p] = [from[i]![j]!, to]; });
    if (!Object.keys(frames).length) return;
    // Held where it was until the motion takes it (from the next frame): the change is never seen at once.
    for (const [p, [start]] of Object.entries(frames)) el.style.setProperty(p, start);
    const run = animate(el, frames, transition);
    changing.set(el, run);
    void run.finished.then(() => {
      if (changing.get(el) !== run) return;
      changing.delete(el);
      for (const p of props) el.style.removeProperty(p);
    }, () => {});
  });
}
