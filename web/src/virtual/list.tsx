// A pane's list of which only what shows is made (model.ts says which, and where the pane is): the one place that
// reads the pane and writes to it for that.
//
// The rows made are the pane's own children, each with its item's key on its root element (`data-vk`); the items not
// made between them are room: a spacer above a row that does not follow the one before it, one after the last.
//
// What is read, and when:
// - a scroll: the pane's scrollTop, once, in its event;
// - sizes: an observer's own reports of the pane (its height, its width, its padding) and of each row, after the
//   browser has laid the page out; with them, the pane's scrollTop again (the page is laid out: nothing is worked
//   out for it), for where the browser itself put the pane as it laid out a list grown shorter at its end.
//   Nothing else of the layout is read: no rectangles, no computed style.
// - the pane's scrollHeight, in a scroll's event, only to tell the browser's own pull from a reader's scroll (list.tsx
//   `scrolled`).
// What is written, and when: the spacers' heights with the rows (React's commit), then the pane's scrollTop where the
// model puts it, once; it is read back as it is set (the browser may stop short of it, the page laid out by then).
import { createContext, createElement, useContext, useEffect, useLayoutEffect, useMemo, useReducer, useRef, type ReactNode, type RefObject } from "react";
import { flushSync } from "react-dom";
import { outsideScroll } from "../scrollBounds.ts";
import { Picture } from "../picture.ts";
import { sizesOf, Virtual, type Align, type Item, type Layout, type Row } from "./model.ts";
import * as css from "./list.css.ts";
import { glideClock, glided, glideShare } from "@stillfail/ui/motion.ts";

export type VirtualList = {
  model: Virtual;
  layout: Layout;
  /** The room above a row, as an element before it (null where it follows the row before it), and after the last. */
  above(row: Row, first: boolean): ReactNode;
  after(): ReactNode;
  /** Told after anything changed where the pane is or what it shows; answers how to stop being told. */
  watch(told: () => void): () => void;
  /** This render committed, its visible rows measured, and its anchor written to the pane. */
  committed(): boolean;
  /** To the end, followed again: gliding there, or at once. */
  toEnd(atOnce?: boolean): void;
  /** To an item (model.ts `goto`); false while it is not among the items. */
  goto(key: string, align?: Align, pad?: number): boolean;
  /** The reader looks for something in it (model.ts `reads`): what comes at its end does not move it meanwhile. */
  reads(on: boolean): void;
  /** How far the pane was moved at once to keep its place (not by the reader, not gliding), in all: what stands
   *  below is where it was on screen, though elsewhere in the pane's content. */
  kept(): number;
};

/** How far past the pane's edges rows are made at rest, and how much further ahead of a scroll under way. */
const OVERSCAN = 400;
const BOOST = 2400;
/** After this long without a scroll, it has come to rest. */
const REST_MS = 150;
/** A pane's first moments: what comes then is where it opens, taken at once. */
const OPENING_MS = 500;
/** How long after a list's first rows are drawn the rows past its pane's edges are made. */
const WIDEN_MS = 450;
/** The most rows a selection keeps made. */
const SELECTED = 400;

type Made = {
  model: Virtual;
  gap: number;
  holds: boolean;
  /** Where the pane was last put, or seen to be. */
  written: number;
  committed: Layout | null;
  kept: number;
  /** A glide's own step is being written: not a move made to keep the pane's place. */
  stepping: boolean;
  drawn: string;
  born: number;
  watchers: Set<() => void>;
  frame: number;
  last: number;
  /** Where the browser itself put the pane (a list shorter at its end for a moment): its scroll event is not a reader's. */
  pulled: number | null;
  /** The rows past the pane's edges are made too: from a moment after its first rows are drawn. */
  wide: boolean;
  /** The rows of the last commit. */
  shown: Set<string>;
};

/** How much of the list's gap before it a row takes back (its own negative margin, list.css.ts): held back, all of it;
 *  going with the row before it (`data-joined`), all but JOINED_GAP. */
function takenBack(row: HTMLElement, gap: number): number {
  const unopened = row.hasAttribute("data-enter") && !row.hasAttribute("data-grown");
  return row.hasAttribute("data-held") || row.hasAttribute("data-queued") || unopened ? gap : row.hasAttribute("data-joined") ? gap - css.JOINED_GAP : 0;
}

/** A list's model, one for each `key` (a chat): made before its rows are, so where it opens can be said to it first. */
/** How large the last pane of each kind of list was (a chat's, a history's: told apart by their gap): a list just
 *  made takes it for its own until its pane reports, so its first rows are the ones that show, not none (a pane of
 *  no height shows nothing) and then, a render later, those. */
const panes = new Map<string, { height: number; width: number; cover: number; lead: number; trail: number }>();
const kindOf = (gap: number, holds: boolean) => `${gap} ${holds}`;

export function useVirtualModel(key: string, gap: number, holds = true): Made {
  return useMemo(() => {
    const model = new Virtual({ gap, overscan: OVERSCAN, boost: BOOST, holds }, sizesOf(key));
    const last = panes.get(kindOf(gap, holds));
    if (last) { model.setEdges(last.lead, last.trail); model.setViewport(last.height, last.width, last.cover); }
    // The first of its kind: most of the window's height, till its pane reports.
    else model.setViewport(Math.round(window.innerHeight * 0.75), 0);
    return fresh(model, gap, holds);
  }, [key, gap, holds]);
}
function fresh(model: Virtual, gap: number, holds: boolean): Made {
  return {
    model, holds,
    gap, committed: null, written: Number.NaN, kept: 0, stepping: false, drawn: "", born: performance.now(), watchers: new Set<() => void>(), frame: 0, last: 0, pulled: null, wide: false, shown: new Set<string>(),
  };
}

export function useVirtualList(pane: RefObject<HTMLElement | null>, made: Made, items: Item[], options: {
  /** What floats over the pane's top, from the room before its first item (its padding). */
  cover?: (lead: number) => number;
  /** Navigation rows may fold while the pane stays put. Commit their new window on the next frame,
   * rather than mount more observed rows during ResizeObserver delivery (a loop error in WebKit). */
  deferResize?: boolean;
  short?: boolean;
  /** Items left an end as the list's window moved along. */
  trimmed?: boolean;
  /** Whether what just came at the end is followed gliding (a message said as the reader watches) or at once. */
  smooth?: boolean;
  /** A message just come at the end: followed from its top (a long one is read from its start). */
  arrived?: string | null;
}): VirtualList {
  const { short = false, trimmed = false, smooth = false, arrived = null, deferResize = false } = options;
  const [, redraw] = useReducer((n: number) => n + 1, 0);
  const { model, gap } = made;
  const cover = useRef(options.cover);
  cover.current = options.cover;

  // The items as they are now, before the rows are drawn from them.
  // What comes gliding starts a glide; one under way goes on through what comes at once (list.tsx `step` ends it).
  if (smooth && performance.now() - made.born > OPENING_MS && model.mode.kind === "follow") model.glide(true);
  model.setShort(short);
  model.setItems(items, trimmed);
  if (arrived !== null && model.mode.kind === "follow") model.follow(arrived);
  // Drawn as a picture (../picture.ts), nothing measures it: all of it, from its start.
  const layout = useContext(Picture) ? model.whole() : model.layout();
  made.drawn = signature(layout);

  const self = useMemo(() => {
    const tell = () => { for (const told of made.watchers) told(); };
    /** The pane put where the model has it, at once. */
    const put = (el: HTMLElement) => {
      const top = model.layout().scrollTop;
      if (Math.abs(top - made.written) < 0.5 || outsideScroll(el)) return;
      const before = made.written;
      el.scrollTop = top;
      // As far as the browser took it: short of it while rows stand shorter than they were taken to be.
      made.written = el.scrollTop;
      if (!made.stepping && !Number.isNaN(before)) made.kept += made.written - before;
    };
    /** After the model changed outside a render: the rows drawn anew if they are others, the pane put in place. */
    const sync = (el: HTMLElement, moved = true) => {
      if (signature(model.layout()) !== made.drawn) flushSync(redraw);
      else if (moved) put(el);
      step(el);
      tell();
    };
    /** Toward where it follows, a share of what is left each frame (about 90% in a quarter second). */
    const step = (el: HTMLElement) => {
      if (made.frame) return;
      // Nothing to glide to: what comes next is taken at once, until something glides again.
      if (model.mode.kind !== "follow" || !(Math.abs(model.target() - model.where) > 0.5)) { model.glide(false); return; }
      // On the clock what closes in a row starts on (rowHeights.ts): the two go as one.
      made.last = glideClock();
      const glide = (now: number) => {
        // Keep this frame owned while a synchronous render runs its layout effects.
        // Those effects call step too: clearing it here starts a second glide, resets
        // last after this frame's timestamp, and lets the two chains pull backwards.
        // Down as well as up: back toward it as what is below closes (model.ts `coming`).
        const left = model.target() - model.where;
        if (model.mode.kind !== "follow" || Math.abs(left) < 0.5) {
          // There: what came meanwhile is taken at once.
          made.frame = 0;
          glided(null);
          model.glide(false);
          if (signature(model.layout()) !== made.drawn) flushSync(redraw);
          else put(el);
          tell();
          return;
        }
        const dt = Math.max(0, Math.min(64, now - made.last));
        glided(now);
        made.last = now;
        model.place(Math.abs(left) < 1 ? model.target() : model.where + left * glideShare(dt));
        made.stepping = true;
        if (signature(model.layout()) !== made.drawn) flushSync(redraw);
        else put(el);
        made.stepping = false;
        tell();
        made.frame = requestAnimationFrame(glide);
      };
      made.frame = requestAnimationFrame(glide);
    };
    return { tell, put, sync, step };
  }, [made, model]);

  // The rows drawn: the pane where the model has it. Not yet while a row just made stands at a guessed height: the
  // observer reports it in this frame, once the page is laid out, and the pane is put then, where it belongs; put
  // now, the browser laid the new rows out here, in the middle of the task, and again after they were measured. (A
  // frame on, it is put all the same: a row that reports nothing would leave it waiting.)
  useLayoutEffect(() => {
    const el = pane.current;
    if (!el) return;
    // The pane may first appear after loading, or React may have replaced its className this commit.
    if (!el.classList.contains(css.pane)) el.classList.add(css.pane);
    let later = 0;
    // Only for rows made in this very commit (each reports once it is laid out); nor a pane never put yet (its own
    // size comes with the same report). Any other time the pane is put now: no report may be coming.
    made.committed = layout;
    const fresh = layout.rows.some((r) => !made.shown.has(r.key));
    made.shown = new Set(layout.rows.map((r) => r.key));
    // (And not in a glide's own step: each step is where the pane is to be now.)
    // (Nor a pane gone to an item: its rows are made there, and it is put there with them, by what is guessed of the
    // way, then where they turn out to stand. Left where it was a frame, it would show none of them, and the browser,
    // its content replaced, would scroll it: the reader's doing, as far as the list can tell.)
    if (!made.stepping && !made.frame && ((fresh && model.guessed && model.mode.kind !== "goto") || Number.isNaN(made.written))) later = requestAnimationFrame(() => { self.put(el); self.step(el); self.tell(); });
    else self.put(el);
    self.step(el);
    self.tell();
    return () => cancelAnimationFrame(later);
  });

  // Known as a list's pane from its first rows on (listQueue.ts): whether it is where it goes.
  useLayoutEffect(() => {
    const el = pane.current;
    if (!el) return;
    stills.set(el, (px) => !(model.mode.kind === "follow" && Math.abs(model.target() - model.where) > px));
    return () => { stills.delete(el); };
  }, [pane, model]);

  // Its first rows drawn, the rows past the pane's edges are made, ready for a scroll: not in the frame the list opens
  // in, nor in the frames of what brings it in (a panel sliding open), but once that is over; at the reader's first
  // scroll, if that comes sooner.
  const some = items.length > 0;
  useEffect(() => {
    const el = pane.current;
    if (!el || !some || made.wide) return;
    let timer = 0;
    const frame = requestAnimationFrame(() => { timer = window.setTimeout(() => { if (made.wide) return; made.wide = true; model.widen(); self.sync(el, false); }, WIDEN_MS); });
    return () => { cancelAnimationFrame(frame); clearTimeout(timer); };
  }, [pane, made, model, self, some]);

  useEffect(() => {
    const el = pane.current;
    if (!el) return;
    let rest = 0;
    const scrolled = () => {
      const top = el.scrollTop;
      clearTimeout(rest);
      if (outsideScroll(el)) return;
      // At rest: the pane put where it should be (what was held under the scroll), fewer rows made ahead.
      rest = window.setTimeout(() => { model.rested(); self.sync(el); }, REST_MS);
      if (Math.abs(top - made.written) < 1) return;
      // The browser's own, put right already (the observer below): no one scrolled.
      if (made.pulled !== null && Math.abs(top - made.pulled) < 1) { made.pulled = null; return; }
      made.pulled = null;
      // The browser's own, not heard of yet: following its end with no one's hand on it, the pane is further up and at
      // the very end of what it has now (what was at the end got shorter: a row's own part folding, reported to the
      // observer a frame later). The pane's height is read for it, here alone.
      if (model.mode.kind === "follow" && top < made.written && performance.now() - input > 400 && el.scrollHeight - el.clientHeight - top <= 1) {
        made.written = top;
        self.sync(el);
        return;
      }
      // The reader's: a glide stops where it is.
      if (!made.wide) { made.wide = true; model.widen(); }
      cancelAnimationFrame(made.frame);
      made.frame = 0;
      glided(null);
      model.glide(false);
      made.written = top;
      model.scrolled(top);
      // Not moved under the reader's scroll, unless the model has nothing left to hold what it should move by.
      self.sync(el);
    };
    el.addEventListener("scroll", scrolled, { passive: true });
    // When the reader last had a hand on the pane (a wheel, a finger, a key, the scrollbar).
    let input = 0;
    const touched = () => { input = performance.now(); };
    for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.addEventListener(type, touched, { passive: true });
    // What of the gap each row's last told height took back (takenBack): a row's own changing is told from there.
    const taken = new WeakMap<HTMLElement, number>();
    let resizeFrame = 0;
    const sizes = new ResizeObserver((entries) => {
      // A reader's scroll was heard before this in the frame: the pane anywhere else than it was put is the browser's
      // doing as it laid the page out (what left the list's end left the pane past its end). The model puts it back.
      const at = el.scrollTop;
      if (!Number.isNaN(made.written) && Math.abs(at - made.written) >= 1 && !outsideScroll(el)) { made.pulled = at; made.written = at; }
      const heights: ([string, number] | [string, number, number])[] = [];
      for (const entry of entries) {
        const box = entry.borderBoxSize[0];
        if (!box) continue;
        if (entry.target === el) {
          // The pane's padding is where its content box starts and what is left under it.
          const content = entry.contentRect;
          const lead = content.top;
          const trail = Math.max(0, box.blockSize - content.top - content.height);
          const over = cover.current?.(lead) ?? 0;
          model.setEdges(lead, trail);
          model.setViewport(box.blockSize, content.width, over);
          panes.set(kindOf(gap, made.holds), { height: box.blockSize, width: content.width, cover: over, lead, trail });
          continue;
        }
        const row = entry.target as HTMLElement;
        const key = row.dataset.vk;
        // A row held back takes no room, not even the gap before it (its own negative margin); one that goes with the row
        // before it, all but JOINED_GAP of it. One closing something in it says what it is going to stand at
        // (rowHeights.ts): the pane goes toward that once, along with it.
        const to = row.dataset.settlesTo;
        const less = takenBack(row, gap);
        taken.set(row, less);
        if (key !== undefined && row.isConnected) heights.push(to === undefined ? [key, box.blockSize - less] : [key, box.blockSize - less, Number(to) - less]);
      }
      // What a click in the pane just grew or shrank is the reader's doing, nothing new: their place is kept from here.
      if (opening && heights.length) model.stay();
      // What grows at the end as the reader watches (a reply coming, an image loading) is followed gliding; the pane
      // itself resized lays everything out anew, taken at once.
      if (!entries.some((e) => e.target === el) && performance.now() - made.born > OPENING_MS && model.mode.kind === "follow") model.glide(!sizingNow(el));
      model.measured(heights);
      if (deferResize) {
        if (!resizeFrame) resizeFrame = requestAnimationFrame(() => { resizeFrame = 0; self.sync(el); });
      } else self.sync(el);
    });
    sizes.observe(el);
    // A click in the pane, until two frames after it.
    let opening = false;
    const clicked = () => { opening = true; requestAnimationFrame(() => requestAnimationFrame(() => { opening = false; })); };
    el.addEventListener("click", clicked, true);
    // Unless what it did was send something (a decision's option picked, Decisions.tsx): what that brings is new.
    const sent = () => { opening = false; };
    el.addEventListener("sent", sent);
    const watchRow = (n: Node) => { if (n instanceof HTMLElement && n.dataset.vk !== undefined) sizes.observe(n); };
    for (const n of el.children) watchRow(n);
    const rows = new MutationObserver((records) => {
      for (const r of records) {
        r.addedNodes.forEach(watchRow);
        r.removedNodes.forEach((n) => { if (n instanceof HTMLElement) sizes.unobserve(n); });
      }
    });
    rows.observe(el, { childList: true });
    // A row says what it is going to stand at as it starts closing something (rowHeights.ts), before any frame of it:
    // the pane is sent there with what else comes in the same frame (a message sent as a card's options close), not
    // first toward that alone and then back.
    // Done (or undone), it stands at what it is.
    const settling = new MutationObserver((records) => {
      const heights: ([string, number] | [string, number, number])[] = [];
      for (const r of records) {
        const row = r.target as HTMLElement;
        const key = row.dataset.vk;
        const size = key === undefined ? undefined : model.sizes.get(key);
        if (row.parentElement !== el || !size) continue;
        const less = takenBack(row, gap);
        // Gone with the row before it, or apart again: the same box, standing on more or less of the gap.
        if (r.attributeName === "data-joined") {
          const was = taken.get(row) ?? less;
          taken.set(row, less);
          if (was !== less) heights.push([key!, size.height + was - less]);
          continue;
        }
        const to = row.dataset.settlesTo;
        heights.push(to === undefined ? [key!, size.height] : [key!, size.height, Number(to) - less]);
      }
      if (!heights.length) return;
      // A glide under way is brought up to this frame first, toward where it was going: what closes starts from this
      // frame (settling.tsx), and the pane's share of it from here too, not from its last step before.
      const now = (document.timeline.currentTime as number | null) ?? performance.now();
      if (made.frame && now > made.last && model.mode.kind === "follow") {
        const left = model.target() - model.where;
        model.place(model.where + left * glideShare(Math.min(64, now - made.last)));
        glided(now);
        made.last = now;
      }
      if (performance.now() - made.born > OPENING_MS && model.mode.kind === "follow") model.glide(!sizingNow(el));
      model.measured(heights);
      self.sync(el);
    });
    settling.observe(el, { subtree: true, attributes: true, attributeFilter: ["data-settles-to", "data-joined"] });
    // A row that holds the focus stays made while it does, and so do the rows a selection runs through, from the one
    // it starts in to the one it ends in: what is copied is all of it, however far the pane has gone on meanwhile.
    let held: string[] = [];
    const rowOf = (n: Node | null): string | undefined => {
      for (let at: Node | null = n; at && at !== el; at = at.parentNode) if (at.parentNode === el && at instanceof HTMLElement) return at.dataset.vk;
      return undefined;
    };
    const hold = () => {
      const selection = document.getSelection();
      const now = new Set<string>();
      const focused = rowOf(document.activeElement);
      if (focused !== undefined) now.add(focused);
      if (selection && !selection.isCollapsed) {
        const a = rowOf(selection.anchorNode);
        const b = rowOf(selection.focusNode);
        const from = a === undefined ? undefined : model.indexOf(a);
        const to = b === undefined ? undefined : model.indexOf(b);
        if (from !== undefined && to !== undefined) {
          for (let i = Math.min(from, to); i <= Math.max(from, to) && now.size < SELECTED; i++) now.add(model.keyAt(i)!);
        }
      }
      const before = held;
      held = [...now];
      for (const k of before) if (!now.has(k)) model.pin(k, false);
      for (const k of held) model.pin(k);
      if (before.length !== held.length || before.some((k) => !now.has(k))) self.sync(el, false);
    };
    el.addEventListener("focusin", hold);
    el.addEventListener("focusout", hold);
    document.addEventListener("selectionchange", hold);
    return () => {
      settling.disconnect();
      clearTimeout(rest);
      cancelAnimationFrame(made.frame);
      made.frame = 0;
      glided(null);
      el.removeEventListener("scroll", scrolled);
      for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.removeEventListener(type, touched);
      el.removeEventListener("click", clicked, true);
      el.removeEventListener("sent", sent);
      el.removeEventListener("focusin", hold);
      el.removeEventListener("focusout", hold);
      document.removeEventListener("selectionchange", hold);
      cancelAnimationFrame(resizeFrame);
      sizes.disconnect();
      rows.disconnect();
      for (const k of held) model.pin(k, false);
    };
  }, [pane, made, model, self, gap, deferResize]);

  return useMemo<VirtualList>(() => ({
    model,
    layout,
    // A spacer cancels the list's gap on the sides it has a neighbour: its height is all the room there is.
    above: (row, first) => (first ? (row.space > 0 ? spacer(`above ${row.key}`, row.space, "first") : null) : Math.abs(row.space - gap) > 0.5 ? spacer(`above ${row.key}`, row.space, "between") : null),
    after: () => (layout.after > 0 ? spacer("after", layout.after, layout.rows.length ? "last" : "only") : null),
    committed: () => made.committed === layout && !model.guessed && Math.abs(made.written - model.layout().scrollTop) < 1,
    watch: (told) => { made.watchers.add(told); return () => { made.watchers.delete(told); }; },
    toEnd: (atOnce = false) => {
      const el = pane.current;
      model.glide(!atOnce);
      model.follow();
      if (el) self.sync(el);
    },
    goto: (key, align = "start", pad = 0) => {
      const el = pane.current;
      cancelAnimationFrame(made.frame);
      made.frame = 0;
      glided(null);
      model.glide(false);
      const there = model.goto(key, align, pad);
      if (el) self.sync(el);
      return there;
    },
    reads: (on) => {
      model.reads(on);
      const el = pane.current;
      if (el) self.sync(el);
    },
    kept: () => made.kept,
  }), [model, layout, made, self, pane, gap]);
}

function spacer(key: string, height: number, where: "first" | "between" | "last" | "only"): ReactNode {
  return createElement("div", { key, className: css.spacer, "data-where": where, "aria-hidden": true, style: { height: `${height}px` } });
}

/** Each list's pane, and whether it is where it goes (its glide over, or within `px` of it): listQueue.ts. */
const stills = new WeakMap<Element, (px: number) => boolean>();
export const isListPane = (el: Element): boolean => stills.has(el);

/** Until when rows of a list's pane go to new heights of their own (listSizing): what grows or shrinks then is laid
 *  out where it is at each frame, the pane held to its end with it, not glided after (docs/list-motion.md, 2026-10-30). */
const sizingUntil = new WeakMap<Element, number>();

/** Rows of `pane` going to their new heights for `ms` from now (a row's room opening or closing by the list's law). */
export function listSizing(pane: Element, ms: number): void {
  sizingUntil.set(pane, Math.max(sizingUntil.get(pane) ?? 0, performance.now() + ms));
}

/** Whether rows of `pane` go to their new heights now. */
const sizingNow = (pane: Element): boolean => (sizingUntil.get(pane) ?? 0) > performance.now();
export const listStill = (pane: Element, px = 0.5): boolean => stills.get(pane)?.(px) ?? true;

/** What of a layout the rows drawn depend on. */
function signature(layout: Layout): string {
  return `${layout.rows.map((r) => `${r.key}:${r.space}`).join("|")}|${layout.after}`;
}

/**
 * A row's own state (a group opened, a text unfolded) goes when the row is unmade: while something in it is open, it
 * stays made. `KeepRow` is how a row says so to its list (what it answers ends it); `useRowKept` makes it for the row
 * of `key`, `useKeepRow(open)` is for what opens.
 */
export const KeepRow = createContext<() => () => void>(() => () => {});
export function useKeepRow(open: boolean): void {
  const hold = useContext(KeepRow);
  useEffect(() => (open ? hold() : undefined), [open, hold]);
}
export function useRowKept(model: Virtual, key: string): () => () => void {
  // How many things are open in it: none, it is made and unmade as the pane goes by like any other.
  const open = useRef(0);
  return useMemo(() => () => {
    if (open.current++ === 0) model.pin(key);
    return () => { if (--open.current === 0) model.pin(key, false); };
  }, [model, key]);
}
