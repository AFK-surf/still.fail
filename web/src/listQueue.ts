// What changes the height of a chat's message list (docs/list-motion.md): a message flying in from the composer, one
// coming out of its agent's avatar, one simply coming in, the agent's line coming, what comes or goes under a post
// (settling.tsx). Each starts the moment it is asked, together with whatever else changes (2026-10-30: no queue).
//
// A row waiting its turn takes no room (`data-queued`, not displayed: the list counts it as it does a message held back,
// virtual/list.tsx): its room comes when its turn does.
import { GLIDE_EASE, GLIDE_MS, motionMs, play } from "@stillfail/ui/motion.ts";
import { isListPane, listSizing } from "./virtual/list.tsx";

class ListQueue {
  constructor(private readonly pane: Element) {}

  /** `start` at once: nothing waits for another (docs/list-motion.md, 2026-10-30), each row's room going to its new
   *  height from the moment it is asked, together with whatever else changes. What this answers is kept for the
   *  callers' sake: there is nothing left to take out. */
  take(start: () => Promise<unknown> | void): () => void {
    void this.pane;
    try { void Promise.resolve(start()).catch(() => undefined); } catch { /* its own motion's failure is its own */ }
    return () => {};
  }

  /** Whether anything waits: nothing ever does. */
  get busy(): boolean { return false; }
}

const queues = new WeakMap<Element, ListQueue>();

/** The pane of the list `el` is in (or is), if any. */
export function listPaneOf(el: Element): Element | null {
  let pane: Element | null = el;
  while (pane && !isListPane(pane)) pane = pane.parentElement;
  return pane;
}

/** The queue of the list `el` is in (or is): its pane's. Outside a list, a queue of its own that never waits. */
export function listQueue(el: Element): ListQueue {
  const at = listPaneOf(el) ?? el;
  let queue = queues.get(at);
  if (!queue) { queue = new ListQueue(at); queues.set(at, queue); }
  return queue;
}

/**
 * `row` (a list's row just made) takes no room until its turn, then comes in: `start` (its own motion, played as its
 * room comes) says when it is over. What this answers takes it out of the queue (it shows at once, if still waiting).
 */
export function queueRow(row: HTMLElement, start: () => Promise<unknown> | void = () => undefined): () => void {
  const out = listQueue(row).take(() => {
    growRow(row);
    return start();
  });
  return () => out();
}

/** `row`, just come into its list, opens its room from nothing by the list's law, the list held to its end with it
 *  (listSizing): the rows over it go up as it opens, never put up at once nor glided after. */
export function growRow(row: HTMLElement): void {
  const pane = listPaneOf(row);
  if (!pane || document.visibilityState !== "visible") return;
  const height = row.getBoundingClientRect().height;
  if (height < 0.5) return;
  listSizing(pane, motionMs(GLIDE_MS));
  play(row, [{ height: "0px", overflow: "clip" }, { height: `${height}px`, overflow: "clip" }], { duration: GLIDE_MS, easing: GLIDE_EASE });
}

/** A promise over in `ms` (a motion of that length played). */
export const after = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The row of what the reader just did here (an option picked: their answer, in the outbox) takes its turn as they do it,
 * before what comes of it (the options closing): `claimReserved` gives it the row once made, which comes in then, its
 * motion taking `ms`. No row within `wait`, the turn goes.
 */
export function reserveRow(near: Element, ms: number, wait = 5000): void {
  const queue = listQueue(near);
  reserved.get(queue)?.finish();
  let end = () => {};
  const ended = new Promise<void>((resolve) => { end = resolve; });
  const r: Reserved = {
    granted: false, row: null, timer: 0,
    finish() {
      clearTimeout(r.timer);
      if (reserved.get(queue) === r) reserved.delete(queue);
      if (r.row) delete r.row.dataset.queued;
      end();
    },
    come() {
      if (!r.row || !r.granted) return;
      delete r.row.dataset.queued;
      r.timer = window.setTimeout(r.finish, ms);
    },
  };
  r.timer = window.setTimeout(r.finish, wait);
  reserved.set(queue, r);
  queue.take(() => { r.granted = true; r.come(); return ended; });
}

/** Whether `row` is the one a turn was kept for (reserveRow): it comes in that turn, waiting for it meanwhile. */
export function claimReserved(row: HTMLElement): boolean {
  const r = reserved.get(listQueue(row));
  if (!r || r.row) return false;
  clearTimeout(r.timer);
  r.row = row;
  if (!r.granted) row.dataset.queued = "";
  r.come();
  return true;
}

type Reserved = { granted: boolean; row: HTMLElement | null; timer: number; finish(): void; come(): void };
const reserved = new WeakMap<ListQueue, Reserved>();
