// Motion driven from script (the `motion` library), for what moves because of something else or has to carry on from
// wherever it is when where it goes changes: it starts from the value and the speed it has, instead of a CSS
// transition's fixed run from a fixed start, which lags a goal that moves and jumps when cut off. CSS transitions stay
// for a thing's own look (hover, colour, opacity, a bar's fill).
import { animate, frame, MotionGlobalConfig, motionValue, type AnimationPlaybackControls, type MotionValue } from "motion";
import { LEAVE_EASE_CSS, MOVE_FAR_MS, moveEase } from "./curves.ts";

export { animate, type AnimationPlaybackControls };

// One curve for each thing a motion can be (the app's apps/mbui/docs/motion.md, Curves; mbui's @ui.Ease): what comes and
// a control answering on EASE_OUT, what goes on LEAVE_EASE_CSS, a move (seen where it was and where it goes) on the
// move's curve over a length by how far it goes; what the hand lets go of or what follows a goal that moves, a spring.

/** The page's --ease-out: what comes (faded in, from a little smaller, up from a line below), a control answering. */
export const EASE_OUT = [0.2, 0.7, 0.2, 1] as const;
/** The page's --ease-out, as CSS. */
export const EASE_OUT_CSS = "cubic-bezier(0.2, 0.7, 0.2, 1)";
export { LEAVE_EASE_CSS, MOVE_EASE_CSS, MOVE_FAR_MS, MOVE_NEAR_MS, MOVE_PAGE_MS, moveEase } from "./curves.ts";
/**
 * One way in and one way out for what comes and goes in the message list (a message, what settles under it): coming,
 * up from a little below as it fades in (as `[data-enter]` draws a new message); going, a copy where it was shrinking a
 * little as it fades (as a sidebar's row goes, listMotion.ts). Their room opens and closes by the list's law (GLIDE_*),
 * not by these.
 */
export const ENTER = { duration: 220, easing: EASE_OUT_CSS } as const;
export const ENTER_FROM = { opacity: 0, transform: "translateY(6px)" } as const;
export const LEAVE = { duration: 200, easing: LEAVE_EASE_CSS } as const;
export const LEAVE_TO = { opacity: 0, transform: "scale(0.9)" } as const;

/** How the small web services and what makes way for them move (Previews.tsx): a spring, so a goal that moves on while
 * they are on their way (a slot easing in, the room changing again) is followed smoothly, not restarted. */
export const MOVE = { type: "spring", visualDuration: 0.28, bounce: 0 } as const;

/**
 * How a message list's pane goes to where it follows (virtual/list.tsx): each frame a share of what is left, at this
 * rate (e^(-t/τ): about 90% in a quarter second). What changes size in its rows moves by the same law (settling.tsx),
 * so the pane and the row go together: one way, never ahead of the other and back.
 */
export const GLIDE_TAU = 100;
/** That law as a motion of fixed length (to 99.75% of the way at its end), and as its easing. */
export const GLIDE_MS = 600;
export const GLIDE_EASE = `linear(${Array.from({ length: 31 }, (_, i) => ((1 - Math.exp(-(i / 30) * GLIDE_MS / GLIDE_TAU)) / (1 - Math.exp(-GLIDE_MS / GLIDE_TAU))).toFixed(4)).join(", ")})`;

/**
 * The most a motion, or a page moved to, waits for what is here already: the core's answer from what it holds, a picture
 * decoded. Never for the network: what has to come from a station shows when it is there, the motion played and its
 * loading state in its place meanwhile.
 */
export const LOCAL_MS = 100;

/**
 * The most a page opening waits for the core's answer: what it shows, read from the device in the core's own time
 * (slower on a phone, and busy as the app comes back), or that it waits on a station for it. Cut short at LOCAL_MS, a
 * chat on the device came in as its messages' bones, then them (2026-10-31).
 */
export const CORE_MS = 1000;

/**
 * Whether motion is reduced on the page now: its root says so (followMotion; styles/still.ts STILL for the styles).
 * Motion reduced is one clock, not a way of its own: everything moves as it does, every motion taking no time (Motion's
 * `instantAnimations`, `play`, `motionMs`, `glideShare`; for the styles, styles/global.css.ts), so what it ends at and
 * what is done once it is over are the same. Only what loops (restingLoop; styles/still.ts stillLoop) and what shows
 * for a while and goes (styles/still.ts stillFlash) ask; check.sh keeps it out of the rest.
 */
export const reducedMotion = (): boolean => document.documentElement.hasAttribute("data-reduced-motion");

/** `el.animate`, on the page's clock: with motion reduced, over at once (no delay either), its end and `finished` as ever. */
export function play(el: Element, frames: Keyframe[] | PropertyIndexedKeyframes, timing: KeyframeAnimationOptions): Animation;
export function play(el: Element | null | undefined, frames: Keyframe[] | PropertyIndexedKeyframes, timing: KeyframeAnimationOptions): Animation | undefined;
export function play(el: Element | null | undefined, frames: Keyframe[] | PropertyIndexedKeyframes, timing: KeyframeAnimationOptions): Animation | undefined {
  return el?.animate(frames, reducedMotion() ? { ...timing, duration: 0, delay: 0, endDelay: 0 } : timing);
}

/** A wait that a motion takes (a timer waiting it out, a stand-in held while it plays): none with motion reduced. */
export const motionMs = (ms: number): number => (reducedMotion() ? 0 : ms);

/** The share of what is left that a glide by the message list's law (GLIDE_TAU) goes in `dt` ms: all of it, with motion reduced. */
export const glideShare = (dt: number): number => (reducedMotion() ? 1 : 1 - Math.exp(-dt / GLIDE_TAU));

/**
 * The page's motion reduced, or not, as `choice` says (a device's setting: `reduce`, `full`, or none to follow the
 * system's), from now on: again as the system's changes, and whenever what it returns is called (the setting changed).
 * Each page calls it before its first render; one with no setting of its own follows the system.
 */
export function followMotion(choice: () => string | undefined = () => undefined): () => void {
  const system = matchMedia("(prefers-reduced-motion: reduce)");
  const apply = () => {
    const chosen = choice();
    const reduced = chosen === "reduce" || (chosen !== "full" && system.matches);
    document.documentElement.toggleAttribute("data-reduced-motion", reduced);
    // Every motion Motion plays (`animate`, springs, a value's) there at once, its delay none, its end and finish as ever.
    MotionGlobalConfig.instantAnimations = reduced;
  };
  apply();
  system.addEventListener("change", apply);
  stepSpokes();
  return apply;
}

/** What shows the spokes (styles/spokes.ts): a chat's mark at work, an agent's badge, the ring round an agent at work. */
const SPOKES_SHOWN = '[data-tone="busy"], [data-badge="run"], [data-spokes]';
let spokesStepping = false;

/**
 * The spokes' one clock (styles/spokes.ts spokesTurn): a step every 100 ms said on the root as `data-spoke`, while any
 * show and the page is seen; with motion reduced, none said (they stand at the first step).
 */
function stepSpokes(): void {
  if (spokesStepping) return;
  spokesStepping = true;
  const root = document.documentElement;
  let step = 0;
  setInterval(() => {
    if (document.hidden) return;
    if (reducedMotion() || !document.querySelector(SPOKES_SHOWN)) {
      if (root.dataset.spoke) delete root.dataset.spoke;
      return;
    }
    step = (step + 1) % 8;
    root.dataset.spoke = String(step);
  }, 100);
}

/**
 * A motion that plays for `duration` ms in every `period` and rests the rest of it (a blink, a beat, a breath and then
 * still), starting `at` ms into the period, on one beat for every such loop (performance.now()'s): played once a period,
 * the rest waited out on a timer. As one infinite CSS animation, one the compositor can't run (anything inside an SVG)
 * had the whole page drawn anew every frame, its rests too, at the screen's rate for as long as it showed; one it can
 * run still had it draw every frame of the rests (2026-10-24). Stopped by what it returns; while motion is reduced or
 * it is not drawn, not played.
 */
export function restingLoop(el: Element, frames: Keyframe[], { period, at = 0, duration }: { period: number; at?: number; duration: number }): () => void {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let run: Animation | undefined;
  const next = () => {
    if (stopped) return;
    const now = performance.now();
    timer = setTimeout(() => {
      // With motion reduced, or not drawn (in a pane gone hidden: content-visibility), not played: hidden, it could not
      // go to the compositor, and the page would be drawn anew every frame of it for nothing.
      if (document.hidden || reducedMotion() || el.checkVisibility?.({ visibilityProperty: true, opacityProperty: true, contentVisibilityAuto: true }) === false) return next();
      run = el.animate(frames, { duration });
      // Cut short (cancelled) it goes on all the same, till stopped.
      run.finished.then(next, next);
    }, Math.ceil((now - at + 1) / period) * period + at - now);
  };
  next();
  return () => { stopped = true; clearTimeout(timer); run?.cancel(); };
}

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

/**
 * A value going from `from` to `to` by the message list's law, stepped each frame as the list's pane steps, from this
 * frame (what changes size in a row as the pane goes along with it: settling.tsx). `set` draws it; done once there
 * (`finished`), or stopped where it is (`cancel`, `finished` then never settles).
 */
export function glideValue(from: number, to: number, set: (value: number) => void): { finished: Promise<void>; cancel(): void } {
  let value = from;
  let last = glideClock();
  let frame = 0;
  let done: () => void = () => {};
  const finished = new Promise<void>((resolve) => { done = resolve; });
  const step = (now: number) => {
    const dt = Math.max(0, Math.min(64, now - last));
    last = now;
    const left = to - value;
    value = Math.abs(left) < 0.25 ? to : value + left * glideShare(dt);
    set(value);
    if (value === to) { frame = 0; done(); }
    else frame = requestAnimationFrame(step);
  };
  set(value);
  frame = requestAnimationFrame(step);
  return { finished, cancel() { cancelAnimationFrame(frame); frame = 0; } };
}

/** The frame the list's pane last stepped in while it glides. */
let paneStep: number | null = null;
/** Said by the list (virtual/list.tsx) at each step of a glide, and null once it stops. */
export function glided(at: number | null): void { paneStep = at; }
/**
 * The time what goes along with the pane starts its clock at: the pane's last step while it glides, else this frame.
 * Both then take their next step in the same frame, by the same law, from the same time: they go together.
 */
export function glideClock(): number {
  const now = (document.timeline.currentTime as number | null) ?? performance.now();
  // A glide stopped without saying so: not a clock to start on.
  return paneStep !== null && now - paneStep < 100 ? paneStep : now;
}

/**
 * A number drawn by `draw` going to its goal by the message list's law (GLIDE_TAU): each frame a share of what is
 * left, from where it is. Never past its goal, nor back: what goes along with the list's pane (an activity keeping its
 * place) moves as the pane does, one way, from the same moment.
 */
export function glider(start: number, draw: (value: number) => void): Follower {
  let value = start;
  let goal = start;
  let frame = 0;
  let last = 0;
  const step = (now: number) => {
    const dt = Math.max(0, Math.min(64, now - last));
    last = now;
    const left = goal - value;
    value = Math.abs(left) < 0.5 ? goal : value + left * glideShare(dt);
    draw(value);
    frame = value === goal ? 0 : requestAnimationFrame(step);
  };
  return {
    get value() { return value; },
    get moving() { return frame !== 0; },
    to(next) {
      goal = next;
      if (frame || value === next) return;
      // On the pane's clock: its next step and this one are taken together.
      last = glideClock();
      frame = requestAnimationFrame(step);
    },
    jump(next) {
      cancelAnimationFrame(frame);
      frame = 0;
      goal = value = next;
      draw(next);
    },
    stop() { cancelAnimationFrame(frame); frame = 0; },
  };
}

const changing = new WeakMap<HTMLElement, AnimationPlaybackControls>();
/**
 * Lets go of the values a motion held on `el`, now and again once Motion has drawn its frame: it draws a motion's last
 * value (its own end, or where a stopped one was) in the frame after it says it is done, over the rules again, and that
 * stayed: a line unfolded kept the width it had then, and the words it grew to after were cut to their first letter.
 */
function letGo(el: HTMLElement, props: Iterable<string>): void {
  const all = [...props];
  for (const p of all) el.style.removeProperty(p);
  frame.postRender(() => { if (!changing.has(el)) for (const p of all) el.style.removeProperty(p); });
}
/** A computed value as the motion takes it: a bare number (opacity) as a number, which it would otherwise end at once. */
const asValue = (v: string): string | number => (/^-?(\d+\.?\d*|\.\d+)$/.test(v.trim()) ? Number(v) : v);
/**
 * A transform's `none` (what the rules give where there is none) as the same functions as its other end, at rest:
 * Motion reads `none` as that other end with every number 0, so `scale(0.5)` to `none` went to `scale(0)`, and stayed.
 */
const restingLike = (other: string): string => other.replace(/([a-zA-Z0-9]+)\(([^)]*)\)/g, (_, fn: string, args: string) => {
  const parts = args.split(",").map((a) => a.trim());
  if (fn === "matrix") return "matrix(1, 0, 0, 1, 0, 0)";
  if (fn === "matrix3d") return "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)";
  if (fn.startsWith("scale")) return `${fn}(${parts.map(() => "1").join(", ")})`;
  return `${fn}(${parts.map((a) => `0${/[a-z%]+$/i.exec(a)?.[0] ?? ""}`).join(", ")})`;
});
const TRANSFORMS = new Set(["transform", "scale", "rotate", "translate"]);
const resting: Record<string, string> = { scale: "1", rotate: "0deg", translate: "0px" };
/** Both ends of a property's motion as Motion can go between them. */
const ends = (p: string, [start, end]: [string, string]): [string, string] => {
  if (!TRANSFORMS.has(p)) return [start, end];
  const rest = (v: string, other: string) => (v.trim() !== "none" ? v : p === "transform" ? (other.trim() === "none" ? "none" : restingLike(other)) : resting[p]!);
  return [rest(start, end), rest(end, start)];
};
/** Each property's keyframes as Motion takes them. */
const keyframes = (frames: Record<string, [string, string]>) =>
  Object.fromEntries(Object.entries(frames).map(([p, f]) => [p, ends(p, f).map(asValue)]));
/**
 * Does `change` (a class or an attribute that lays things out anew) and moves each of `moves`' properties from where
 * it shows now to where the change puts it; cut off by the next one, that goes on from wherever this had got to. The
 * rules stay the truth: the values it holds while moving are let go of when it ends. Resolves once all have got there
 * (not if a later one cuts them off).
 */
export function moveState(moves: [HTMLElement, string[]][], change: () => void, transition: object = { duration: MOVE_FAR_MS / 1000, ease: moveEase }): Promise<void> {
  const from = moves.map(([el, props]) => { const style = getComputedStyle(el); return props.map((p) => style.getPropertyValue(p)); });
  // Where the panes they are in are scrolled. Its end is read laid out, and a pane that its end makes shorter (a row
  // folding away at the bottom of a list) is pulled up at once, before they are held where they were: put back below.
  const panes = new Map<HTMLElement, number>();
  for (const [el] of moves) for (let n = el.parentElement; n; n = n.parentElement) if (n.scrollTop > 0 && !panes.has(n)) panes.set(n, n.scrollTop);
  for (const [el, props] of moves) {
    changing.get(el)?.stop();
    changing.delete(el);
    for (const p of props) el.style.removeProperty(p);
  }
  change();
  const runs: Promise<unknown>[] = [];
  moves.forEach(([el, props], i) => {
    const style = getComputedStyle(el);
    const frames: Record<string, [string, string]> = {};
    props.forEach((p, j) => { const to = style.getPropertyValue(p); if (to !== from[i]![j]) frames[p] = [from[i]![j]!, to]; });
    if (!Object.keys(frames).length) return letGo(el, props);
    // Held where it was until the motion takes it (from the next frame): the change is never seen at once.
    for (const [p, [start]] of Object.entries(frames)) el.style.setProperty(p, start);
    const run = animate(el, keyframes(frames), transition);
    changing.set(el, run);
    runs.push(run.finished);
    void run.finished.then(() => {
      if (changing.get(el) !== run) return;
      changing.delete(el);
      letGo(el, props);
    }, () => {});
  });
  for (const [pane, top] of panes) if (pane.scrollTop !== top) pane.scrollTop = top;
  return Promise.all(runs).then(() => undefined, () => undefined);
}

/**
 * Moves each of `moves`' properties from the value given to where the rules put it now (a thing coming in, drawn at
 * its place from the first frame); a moveState on the same element later goes on from wherever this had got to.
 */
export function arrive(moves: [HTMLElement, Record<string, string>][], transition: object = { duration: MOVE_FAR_MS / 1000, ease: moveEase }): void {
  for (const [el, from] of moves) {
    changing.get(el)?.stop();
    const style = getComputedStyle(el);
    const frames: Record<string, [string, string]> = {};
    for (const [p, start] of Object.entries(from)) {
      el.style.removeProperty(p);
      frames[p] = [start, style.getPropertyValue(p)];
    }
    for (const [p, [start]] of Object.entries(frames)) el.style.setProperty(p, start);
    const run = animate(el, keyframes(frames), transition);
    changing.set(el, run);
    void run.finished.then(() => {
      if (changing.get(el) !== run) return;
      changing.delete(el);
      letGo(el, Object.keys(from));
    }, () => {});
  }
}
