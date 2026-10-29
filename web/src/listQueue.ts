// What changes the height of a chat's message list plays one at a time (docs/list-motion.md): a message flying in from
// the composer, one coming out of its agent's avatar, one simply coming in, the agent's line coming, what comes under a
// post (what is answered there goes only out of sight: settling.tsx). Each waits its turn here, in the order they came; a turn is over once its own motion is and the list has gone
// where it moved it to (virtual/list.tsx `listStill`). What only fades, turns or changes its words is not in it.
//
// A row waiting its turn takes no room (`data-queued`, not displayed: the list counts it as it does a message held back,
// virtual/list.tsx): its room comes when its turn does.
import { isListPane, listStill } from "./virtual/list.tsx";

type Turn = { start: () => Promise<unknown> | void; over: boolean };

/** The most a turn holds the next one back, whatever it says (one whose motion never says it is over). */
const MOST_MS = 3000;
/** How far the list's pane may be from where it goes and count as there: what comes next does not set out while the last moves. */
const THERE_PX = 0.5;

class ListQueue {
  private readonly waiting: Turn[] = [];
  private on: Turn | null = null;

  constructor(private readonly pane: Element) {}

  /** `start` once it is this one's turn (at once, none being under way): what it answers says when its motion is over.
   *  What this answers takes it out (not yet started: it never is; under way: the next one goes). */
  take(start: () => Promise<unknown> | void): () => void {
    const turn: Turn = { start, over: false };
    this.waiting.push(turn);
    this.next();
    return () => {
      const i = this.waiting.indexOf(turn);
      if (i >= 0) this.waiting.splice(i, 1);
      if (this.on === turn) this.done(turn);
    };
  }

  /** Whether anything is under way or waiting. */
  get busy(): boolean { return this.on !== null || this.waiting.length > 0; }

  private next(): void {
    if (this.on) return;
    const turn = this.waiting.shift();
    if (!turn) return;
    this.on = turn;
    const timer = setTimeout(() => this.done(turn), MOST_MS);
    let ran: Promise<unknown> | void;
    try { ran = turn.start(); } catch { ran = undefined; }
    void Promise.resolve(ran).catch(() => undefined).then(() => {
      clearTimeout(timer);
      if (this.on !== turn) return;
      // Then the list where it went: looked at from two frames on (what it moved is measured in the frame after it,
      // and the list sets out then).
      const still = () => {
        if (this.on !== turn) return;
        if (!this.pane.isConnected || listStill(this.pane, THERE_PX)) this.done(turn);
        else requestAnimationFrame(still);
      };
      requestAnimationFrame(() => requestAnimationFrame(still));
    });
  }

  private done(turn: Turn): void {
    if (this.on !== turn || turn.over) return;
    turn.over = true;
    this.on = null;
    this.next();
  }
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
  row.dataset.queued = "";
  const out = listQueue(row).take(() => {
    delete row.dataset.queued;
    return start();
  });
  return () => { delete row.dataset.queued; out(); };
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
