// Another workspace coming in (./Workspaces.tsx): its lists slide in from the side as the ones left slide out, and its
// name in its capsule the same way, as a pager's pages (apps/android/…/screens/Home.kt the same). Each workspace is a page
// of its own (mounted anew), so what was on screen goes as a copy, drawn in the new page under its bar (the one real
// bar, its glass over both) until it has gone.
import { LOCAL_MS } from "../motion.ts";

/** What was on screen as the workspace was left, for the one coming in. */
export interface Arrival {
  /** A copy of the lists, as they were (scrolled as they were). */
  lists: HTMLElement | null;
  scrolls: number[];
  /** The name that was in the capsule. */
  name: string;
  /** 1: the next one (in from the right); -1: the one before. */
  way: 1 | -1;
  /** Where the finger left the name (px), swiped. */
  from: number;
  /** How wide the capsule with the name was (px). */
  dock: number;
}

export const SWITCH_MS = 280;
export const SWITCH_EASE = "cubic-bezier(.2, .8, .2, 1)";

let leaving: Arrival | null = null;

const still = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Before going to another workspace: what `lists` shows and its `name` (in a capsule `dock` wide), for the one coming in to slide over. */
export function leave(lists: HTMLElement | null, name: string, way: 1 | -1, dock: number, from = 0): void {
  if (still()) { leaving = null; return; }
  const copy = lists?.cloneNode(true) as HTMLElement | undefined;
  const scrolls = lists ? [...lists.children].map((pane) => (pane as HTMLElement).scrollTop) : [];
  leaving = { lists: copy ?? null, scrolls, name, way, from, dock };
}

/** For the workspace coming in, once: what was left (null when it came in any other way). */
export function arrival(): Arrival | null {
  const taken = leaving;
  leaving = null;
  return taken;
}

/**
 * The lists of the workspace come in (`panes`) over what was left (`come`): the copy put after them, in place at
 * once, then both slide once the new lists are read (`ready`), or after `LOCAL_MS` (only the device is waited for).
 * Returns when it starts, to start the bar's name with it.
 */
export function slideIn(come: Arrival, panes: HTMLElement, ready: () => boolean, started: () => void): () => void {
  const copy = come.lists;
  if (copy) {
    copy.setAttribute("aria-hidden", "true");
    copy.inert = true;
    Object.assign(copy.style, { background: "var(--m-bg)", pointerEvents: "none" });
    panes.after(copy);
    [...copy.children].forEach((pane, i) => { (pane as HTMLElement).scrollTop = come.scrolls[i] ?? 0; });
  }
  let timer = 0;
  let done = false;
  const go = () => {
    if (done) return;
    done = true;
    clearInterval(timer);
    started();
    const timing = { duration: SWITCH_MS, easing: SWITCH_EASE };
    panes.animate([{ transform: `translateX(${come.way * 100}%)` }, { transform: "translateX(0)" }], timing);
    const out = copy?.animate([{ transform: "translateX(0)" }, { transform: `translateX(${-come.way * 100}%)` }], { ...timing, fill: "forwards" });
    void out?.finished.then(() => copy?.remove(), () => copy?.remove());
  };
  const until = performance.now() + LOCAL_MS;
  if (ready()) go();
  else timer = window.setInterval(() => { if (ready() || performance.now() >= until) go(); }, 16);
  return () => { clearInterval(timer); copy?.remove(); };
}
