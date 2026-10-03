// A picture's viewer (FilePreview.tsx) opening out of the chat's thumbnail of it and closing back into it, as the
// phones' app does: the viewer's own picture is what moves (drawn where it is, carried from the thumbnail's box), the
// thumbnail hidden meanwhile, so only one picture is ever on the screen. One progress `p` carries it all: 0 is the
// thumbnail (its box, its corners, the picture cropped to it as the chat shows it), 1 the picture where the viewer puts
// it (zoomed and panned, or not); the viewer's ground and its bars come in with it. With no thumbnail on the screen, the
// viewer fades, as it always has.
import { LOCAL_MS, reducedMotion } from "./motion.ts";

/** How long it takes to open out of the thumbnail, and to close back into it; both slowing into place. */
const OPEN = 320;
const CLOSE = 280;
const EASE = "cubic-bezier(.2, .8, .2, 1)";
/** Opened or closed with no thumbnail to go from or to. */
const FADE = 140;
const FADE_EASE = "cubic-bezier(.2, .7, .2, 1)";

/** What names a thumbnail of a file in the chat (`data-viewer-thumb`), and the viewer showing the same file. */
export const thumbId = (station: string, sessionKey: string, path: string): string => `${station}\n${sessionKey}\n${path}`;

/** The thumbnail `id` names, if one is on the screen. */
function thumbOf(id: string): HTMLElement | null {
  for (const el of document.querySelectorAll<HTMLElement>("[data-viewer-thumb]")) {
    if (el.dataset.viewerThumb !== id) continue;
    const r = el.getBoundingClientRect();
    if (r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth) return el;
  }
  return null;
}

/**
 * Where a thumbnail shows its picture (proportioned like `to`): its whole box, or, letterboxed in it (Chat.tsx's
 * imageBox), the picture fitted inside, centred.
 */
function shownIn(thumb: HTMLElement, to: DOMRect): { left: number; top: number; width: number; height: number } {
  const box = thumb.getBoundingClientRect();
  if (thumb.dataset.letterbox === undefined) return box;
  const k = Math.min(box.width / to.width, box.height / to.height);
  const width = to.width * k, height = to.height * k;
  return { left: box.left + (box.width - width) / 2, top: box.top + (box.height - height) / 2, width, height };
}

/** An element's inline styles to put back as they were. */
function keep(el: HTMLElement, props: string[]): () => void {
  const was = props.map((p) => [p, el.style.getPropertyValue(p), el.style.getPropertyPriority(p)] as const);
  return () => { for (const [p, v, pr] of was) { if (v) el.style.setProperty(p, v, pr); else el.style.removeProperty(p); } };
}

export interface ViewerFlight {
  /** The viewer (`root`) has just been put up for the file `id` names (before it is first painted). */
  open(id: string): void;
  /** The viewer, showing the file `id` names now, closes; `done` takes it down once it is back in its thumbnail. */
  close(id: string, done: () => void): void;
  /** It was taken down (whatever it was doing). */
  stop(): void;
}

/** The flights of the viewer drawn by `root` (its picture: `[data-viewer-picture]` in an fpStage `stage`; its grounds: itself and `[data-viewer-ground]`; its bars: `[data-floats]` and `steps`). */
export function viewerFlight(root: () => HTMLElement | null, { stage: stageClass, steps }: { stage: string; steps: string }): ViewerFlight {
  let p = 1;
  let clock: Animation | null = null;
  let frame = 0;
  let hidden: HTMLElement | null = null;
  let waiting = 0;
  let restore: (() => void)[] = [];
  let closing = false;
  /** Waiting to open (nothing shown yet), on its way, or at rest (a fade counts as at rest). */
  let phase: "wait" | "fly" | "rest" = "rest";

  const settle = () => {
    cancelAnimationFrame(frame);
    clearTimeout(waiting);
    clock?.cancel();
    clock = null;
    for (const r of restore) r();
    restore = [];
  };
  const show = () => { if (hidden) hidden.style.visibility = ""; hidden = null; };

  /** Where everything is drawn at `p`, from the thumbnail `thumb`. */
  const draw = (el: HTMLElement, thumb: HTMLElement, at: number) => {
    const picture = el.querySelector<HTMLElement>("[data-viewer-picture]");
    const stage = picture?.closest<HTMLElement>(`.${stageClass}`);
    if (!picture || !stage) return false;
    // Where the picture is in place (the stage unmoved), and where the thumbnail is.
    stage.style.transform = "none";
    stage.style.clipPath = "none";
    const to = picture.getBoundingClientRect();
    const box = stage.getBoundingClientRect();
    if (!to.width || !to.height) return false;
    const from = shownIn(thumb, to);
    // Covering the thumbnail's box at the start, as a cropped picture does, and at its own size at the end.
    const s0 = Math.max(from.width / to.width, from.height / to.height);
    const s = s0 + (1 - s0) * at;
    const tx = to.left + to.width / 2, ty = to.top + to.height / 2;
    const cx = from.left + from.width / 2 + (tx - from.left - from.width / 2) * at;
    const cy = from.top + from.height / 2 + (ty - from.top - from.height / 2) * at;
    // The crop, in the stage's own (unscaled) terms: the thumbnail's box growing into the picture's; its corners going.
    const w = (from.width + (to.width - from.width) * at) / s;
    const h = (from.height + (to.height - from.height) * at) / s;
    const radius = (parseFloat(getComputedStyle(thumb).borderTopLeftRadius) || 0) * (1 - at) / s;
    const ox = tx - box.left, oy = ty - box.top;
    stage.style.transformOrigin = `${ox}px ${oy}px`;
    stage.style.transform = `translate(${cx - tx}px, ${cy - ty}px) scale(${s})`;
    const top = Math.max(0, oy - h / 2), left = Math.max(0, ox - w / 2);
    const bottom = Math.max(0, box.height - oy - h / 2), right = Math.max(0, box.width - ox - w / 2);
    stage.style.clipPath = `inset(${top}px ${right}px ${bottom}px ${left}px round ${radius}px)`;
    return true;
  };

  /** From `p` to `goal` over `ms`, from or to `thumb`; `landed` once there. */
  const fly = (el: HTMLElement, thumb: HTMLElement, goal: number, ms: number, landed: () => void) => {
    settle();
    const start = p;
    const picture = el.querySelector<HTMLElement>("[data-viewer-picture]");
    const stage = picture?.closest<HTMLElement>(`.${stageClass}`);
    if (!stage) { landed(); return; }
    // What comes in with the picture, each from what it would show at rest (a bar faded stays faded).
    const grounds = [el, ...el.querySelectorAll<HTMLElement>("[data-viewer-ground]")];
    const bars = [...el.querySelectorAll<HTMLElement>(`[data-floats], .${steps}`)];
    restore = [
      keep(stage, ["transform", "transform-origin", "clip-path"]),
      ...grounds.map((g) => keep(g, ["background-color"])),
      ...bars.map((b) => keep(b, ["opacity", "transition"])),
      keep(el, ["opacity"]),
    ];
    // (The viewer's own fade in is not for a flight, nor, taken off, to come again after one.)
    el.style.animation = "none";
    const ground = grounds.map((g) => { g.style.backgroundColor = ""; return getComputedStyle(g).backgroundColor; });
    const shown = bars.map((b) => { b.style.transition = "none"; b.style.opacity = ""; return parseFloat(getComputedStyle(b).opacity); });
    el.style.opacity = "1";
    phase = "fly";
    hidden = thumb;
    thumb.style.visibility = "hidden";
    // The one timeline all of it follows (what moves is read anew each frame): paused and stepped, so is it.
    const run = el.animate([{ opacity: 1 }, { opacity: 1 }], { duration: ms, easing: EASE });
    clock = run;
    const place = () => {
      const e = run.effect?.getComputedTiming().progress ?? 1;
      p = start + (goal - start) * (run.playState === "finished" ? 1 : e);
      draw(el, thumb, p);
      grounds.forEach((g, i) => { g.style.backgroundColor = `color-mix(in srgb, ${ground[i]} ${p * 100}%, transparent)`; });
      bars.forEach((b, i) => { b.style.opacity = `${shown[i]! * p}`; });
    };
    const tick = () => { place(); frame = requestAnimationFrame(tick); };
    place();
    frame = requestAnimationFrame(tick);
    void run.finished.then(() => {
      if (clock !== run) return;
      p = goal;
      phase = "rest";
      landed();
    }, () => {});
  };

  /** No thumbnail: the viewer fades in or out where it is. */
  const fade = (el: HTMLElement, goal: number, landed: () => void) => {
    const from = parseFloat(getComputedStyle(el).opacity);
    settle();
    restore = [keep(el, ["opacity"])];
    el.style.animation = "none";
    phase = "rest";
    const run = el.animate([{ opacity: goal ? 0 : from }, { opacity: goal }], { duration: FADE, easing: FADE_EASE, fill: "forwards" });
    clock = run;
    void run.finished.then(() => { if (clock === run) landed(); }, () => {});
  };

  return {
    open(id) {
      closing = false;
      const el = root();
      const thumb = thumbOf(id);
      if (!el || !thumb || reducedMotion()) return;
      // Nothing shows until the picture can go from the thumbnail (its size known, placed), or what is here is shown.
      p = 0;
      phase = "wait";
      restore = [keep(el, ["opacity"])];
      el.style.animation = "none";
      el.style.opacity = "0";
      // Waited for only as long as what is here already takes (its size sent with it, its thumbnail's picture): what
      // has to come over the network (at no time known) it does not wait for, it fades in and shows it coming.
      const began = performance.now();
      const look = () => {
        if (closing) return;
        const picture = el.querySelector<HTMLElement>("[data-viewer-picture]");
        const video = picture instanceof HTMLVideoElement ? picture : null;
        const ready = !!picture && picture.style.visibility !== "hidden" && picture.getBoundingClientRect().width > 0 && (!video || video.readyState >= 2);
        const there = thumbOf(id);
        if (ready && there) { fly(el, there, 1, OPEN, () => { settle(); show(); }); return; }
        if (performance.now() - began > LOCAL_MS || !there) { p = 1; fade(el, 1, settle); return; }
        frame = requestAnimationFrame(look);
      };
      look();
    },
    close(id, done) {
      if (closing) return;
      closing = true;
      const el = root();
      // Not shown yet: nothing to take back.
      if (!el || reducedMotion() || phase === "wait") { settle(); done(); return; }
      const thumb = thumbOf(id) ?? (hidden?.dataset.viewerThumb === id ? hidden : null);
      const picture = el.querySelector<HTMLElement>("[data-viewer-picture]");
      if (thumb && picture && picture.getBoundingClientRect().width > 0) {
        // A video goes back into its thumbnail showing the frame it was at, and stays so (a still of where it was left).
        const still = thumb.querySelector("video");
        if (still && picture instanceof HTMLVideoElement && Number.isFinite(picture.currentTime)) still.currentTime = picture.currentTime;
        // From wherever it is: on its way in, or at rest (zoomed, panned or not).
        if (phase !== "fly") p = 1;
        fly(el, thumb, 0, CLOSE, () => { done(); show(); });
      } else {
        show();
        fade(el, 0, done);
      }
    },
    stop() {
      settle();
      show();
    },
  };
}
