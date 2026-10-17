// How the home list's rows move when the list changes (web/src/listMotion.ts): each row is placed where it was and goes
// to where it is now (the list's layout transition, FLIP), carrying on from wherever it had got to; one gone is drawn by
// a copy that shrinks and fades where it was, under the rows closing over it; one new grows in where it is. A row that
// overtakes others on its way up (a chat with a new message) passes over them on a ground of its own.
import { makeMutable, withDelay, withSpring, withTiming, type LayoutAnimationsValues, type SharedValue } from "react-native-reanimated";
import type { ChatDay, ChatItem } from "../../../../web/src/core/shapes.ts";
import { Ease } from "../ui/Motion";

/** A row's key in the list, kept as it changes: a chat asked for here goes by its `clientKey` before and after its station makes it. */
export function rowKey(item: ChatItem): string {
  return `${item.station}/${item.clientKey ?? item.id}`;
}

export function dayKey(day: ChatDay): string {
  return `h/${day.daysAgo}`;
}

/** What leaves takes this long; the rest start closing over it a little after it begins to go. */
export const LEAVE_MS = 200;
export const CLOSE_DELAY_MS = 100;

/** Motion's `MOVE` (spring, visualDuration 0.28 s, no bounce): stiffness (2π / (0.28 × 1.2))², critically damped. */
const MOVE_STIFFNESS = 350;
/** The MOVE spring as Reanimated takes it (damping ratio 1 at mass 1). */
export const closeGapSpring = { mass: 1, stiffness: MOVE_STIFFNESS, damping: 2 * Math.sqrt(MOVE_STIFFNESS) };

/** The web's `cubic-bezier(0.2, 0.7, 0.2, 1)` for a row coming in, and CSS `ease-out`. */
export const ArriveEasing = Ease.Out;
export const CssEaseOut = Ease.CssOut;

/** Close the space left by departing content with the same delayed spring as archived chat rows (to `to`). */
export function closeGap(to: number) {
  "worklet";
  return withDelay(CLOSE_DELAY_MS, withSpring(to, closeGapSpring));
}

/** How long after the rows change their moves count as theirs (the move starts at the next layout, a frame or two later). */
const CHANGED_MS = 150;

/** A row or day heading gone from the list, drawn where it was while it goes (`y` from the list's top as seen). */
export class Ghost {
  constructor(readonly key: string, readonly y: number, readonly item: ChatItem | null, readonly label: string | null, readonly at: number) {}
}

/**
 * One list's motion: what it showed last (keys in order, and what each was), where each row is placed now, and what
 * the last change set going (rows coming in, rows lifted over others, copies of rows gone). The list's page draws again
 * when the lifted rows or the copies change (`subscribe`, as Compose's state map and list are read).
 */
export class ListMotion {
  #was: string[] | null = null;
  #shown = new Map<string, ChatItem | string>();
  /** Where each row's top is in the list's content (its layout), as last placed. */
  readonly placed = new Map<string, number>();
  /**
   * How far the list is scrolled: `placed` is in the content's coordinates here (a row's layout), where Compose's are
   * the list's own; a copy is drawn this much higher than its row's place.
   */
  offset = 0;
  /** Rows new since the last change, and when they came: they grow in when first drawn. */
  readonly #arrived = new Map<string, number>();
  /** Rows that went ahead of others, and when: they pass over them. */
  readonly lifted = new Map<string, number>();
  #ghosts: Ghost[] = [];
  /** Rows swiped off to be archived (Home.tsx SwipeToArchive): already gone from sight, they leave no copy behind. */
  readonly swiped = new Set<string>();
  /** Read by the rows' layout transitions on the UI thread, so these two are shared values. */
  readonly #closeUntil: SharedValue<number> = makeMutable(0);
  /** When the rows last changed (one in, one out, one ahead of others): only then do they move to their new places. */
  readonly #changedAt: SharedValue<number> = makeMutable(-Infinity);

  #version = 0;
  readonly #listeners = new Set<() => void>();
  subscribe = (l: () => void) => {
    this.#listeners.add(l);
    return () => { this.#listeners.delete(l); };
  };
  /** Changes each time the copies or the lifted rows do (what the page's snapshot reads). */
  version = () => this.#version;
  #changed() {
    this.#version++;
    for (const l of this.#listeners) l();
  }

  get ghosts(): readonly Ghost[] { return this.#ghosts; }
  /** A copy done going: dropped. */
  dropGhost(g: Ghost) {
    const at = this.#ghosts.indexOf(g);
    if (at < 0) return;
    this.#ghosts = this.#ghosts.filter((x) => x !== g);
    this.#changed();
  }
  /** A row's ground over the others done: it lies with the rest again (when it is still that lift). */
  dropLift(key: string, lift: number) {
    if (this.lifted.get(key) !== lift) return;
    this.lifted.delete(key);
    this.#changed();
  }

  /**
   * The list as drawn now, in order: sets what moves from what was drawn last. `visible` are the keys on screen (only
   * those leave by a copy). Nothing moves the first time, or with no motion wanted.
   */
  update(days: ChatDay[], visible: Set<string>, still: boolean) {
    const keys: string[] = [];
    const now = new Map<string, ChatItem | string>();
    for (const day of days) {
      const d = dayKey(day);
      keys.push(d);
      now.set(d, day.label);
      for (const item of day.items) {
        const k = rowKey(item);
        keys.push(k);
        now.set(k, item);
      }
    }
    const before = this.#was;
    if (before && before.length === keys.length && before.every((k, i) => k === keys[i])) { this.#shown = now; return; }
    this.#was = keys;
    const old = this.#shown;
    this.#shown = now;
    // Nothing to move from (the list's first rows), or no motion wanted: only where they are is kept.
    if (!before || before.length === 0 || still) return;
    const t = Date.now();
    this.#changedAt.value = t;
    const oldSet = new Set(before);
    const newSet = new Set(keys);
    const gone = before.filter((k) => !newSet.has(k));
    for (const key of keys) if (!oldSet.has(key)) this.#arrived.set(key, t);
    // Which of the rows there before and now went ahead of others: they pass over the rest.
    const kept = keys.filter((k) => oldSet.has(k));
    const keptBefore = before.filter((k) => newSet.has(k));
    const rank = new Map(keptBefore.map((k, i) => [k, i] as const));
    kept.forEach((key, i) => {
      if (!key.startsWith("h/") && (rank.get(key) ?? i) > i) { this.lifted.set(key, t); }
    });
    for (const key of gone) {
      const y = this.placed.get(key);
      if (y === undefined) continue;
      if (!visible.has(key) || this.swiped.delete(key)) continue;
      const what = old.get(key);
      this.#ghosts = [...this.#ghosts, new Ghost(key, y - this.offset, typeof what === "object" ? what : null, typeof what === "string" ? what : null, t)];
    }
    if (gone.length > 0) this.#closeUntil.value = t + 50;
    for (const k of [...this.placed.keys()]) if (!newSet.has(k)) this.placed.delete(k);
    for (const k of [...this.swiped]) if (!newSet.has(k)) this.swiped.delete(k);
    for (const [k, at] of [...this.#arrived]) if (t - at >= 500) this.#arrived.delete(k);
  }

  /** Whether the row came just now: it is then drawn growing in (once). */
  arriving(key: string): boolean {
    const at = this.#arrived.get(key);
    if (at === undefined) return false;
    this.#arrived.delete(key);
    return Date.now() - at < 400;
  }

  /** How long a row waits before it moves: the rows closing over one gone start a little after it begins to go. */
  delayFor(key: string): number {
    return Date.now() <= this.#closeUntil.value && this.liftedAt(key) === null ? CLOSE_DELAY_MS : 0;
  }

  /** When the row went ahead of others, if that was just now (its ground lasts 480 ms). */
  liftedAt(key: string): number | null {
    const at = this.lifted.get(key);
    return at !== undefined && Date.now() - at < 480 ? at : null;
  }

  /**
   * A row's placement (its layout transition): the web's MOVE spring, after `delayFor` (asked when the move starts); taken
   * at once when the rows did not just change, as the move is then the list's own layout (something over the rows
   * growing or going, its width), not a row going elsewhere.
   */
  placement(key: string) {
    const changedAt = this.#changedAt;
    const closeUntil = this.#closeUntil;
    // Whether it is lifted is known as the change is drawn (update runs in that render), when this is made again.
    const lifted = this.liftedAt(key) !== null;
    const spring = closeGapSpring;
    return (values: LayoutAnimationsValues) => {
      "worklet";
      const now = Date.now();
      const at = { originX: withTiming(values.targetOriginX, { duration: 0 }), width: withTiming(values.targetWidth, { duration: 0 }), height: withTiming(values.targetHeight, { duration: 0 }) };
      if (now - changedAt.value >= CHANGED_MS) {
        return { initialValues: { originX: values.currentOriginX, originY: values.currentOriginY, width: values.currentWidth, height: values.currentHeight }, animations: { ...at, originY: withTiming(values.targetOriginY, { duration: 0 }) } };
      }
      const wait = now <= closeUntil.value && !lifted ? CLOSE_DELAY_MS : 0;
      return {
        initialValues: { originX: values.currentOriginX, originY: values.currentOriginY, width: values.currentWidth, height: values.currentHeight },
        animations: { ...at, originY: wait > 0 ? withDelay(wait, withSpring(values.targetOriginY, spring)) : withSpring(values.targetOriginY, spring) },
      };
    };
  }
}

/**
 * `days` as shown: while `hold` (a finger on the list, or it scrolling), rows keep their places and their days, each
 * with what is new of it, so the row about to be tapped does not move away; ones gone go, new ones (and ones pinned or
 * let go) come in where they would be. Let go, the list is as it is (web: useHeldOrder, there while the mouse is over the list).
 */
export class HeldOrder {
  #shown: ChatDay[] = [];

  of(days: ChatDay[], hold: boolean): ChatDay[] {
    if (!hold) { this.#shown = days; return days; }
    const fresh = new Map<string, ChatItem>();
    for (const day of days) for (const item of day.items) fresh.set(rowKey(item), item);
    const held = new Set<string>();
    // One pinned or let go is no longer held: it goes where it goes now.
    const out: [ChatDay, ChatItem[]][] = this.#shown.map((day) => [day, day.items.flatMap((item) => {
      const now = fresh.get(rowKey(item));
      if (!now || (now.pinned === true) !== (item.pinned === true)) return [];
      held.add(rowKey(item));
      return [now];
    })]);
    // New rows go into their own day, where they would be in it (a day not shown yet comes in its place).
    for (const day of days) day.items.forEach((item, i) => {
      if (held.has(rowKey(item))) return;
      let into = out.findIndex(([d]) => d.daysAgo === day.daysAgo);
      if (into < 0) {
        const at = out.findIndex(([d]) => d.daysAgo > day.daysAgo);
        into = at < 0 ? out.length : at;
        out.splice(into, 0, [day, []]);
      }
      const items = out[into]![1];
      items.splice(Math.min(i, items.length), 0, item);
    });
    this.#shown = out.map(([day, items]) => ({ ...day, items })).filter((d) => d.items.length > 0);
    return this.#shown;
  }
}

/**
 * The mark each chat has and since when, to know one that has just come: both lists pop it, also as its row is drawn
 * anew on the way to its new place (web: ChatMark.tsx `shown`). Fed from the whole list, so a row off screen as its
 * mark changes does not pop when scrolled to later.
 */
export const MarksSeen = {
  seen: new Map<string, [unknown, number]>(),

  note(key: string, tone: unknown) {
    const had = this.seen.get(key);
    if (had === undefined) this.seen.set(key, [tone, -Infinity]);
    else if (had[0] !== tone) this.seen.set(key, [tone, Date.now()]);
  },

  /** Whether the mark came within the last 300 ms. */
  fresh(key: string): boolean {
    const since = this.seen.get(key)?.[1];
    if (since === undefined) return false;
    return since !== -Infinity && Date.now() - since <= 300;
  },
};
