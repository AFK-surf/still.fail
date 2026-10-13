// A pane's list of which only what shows is made (model.ts says which, and where the pane is): the one place that
// reads the pane and writes to it for that.
//
// The rows made are the pane's own children, each with its item's key on its root element (`data-vk`); the items not
// made between them are room: a spacer above a row that does not follow the one before it, one after the last.
//
// What is read, and when:
// - a scroll: the pane's scrollTop, once, in its event;
// - sizes: an observer's own reports of the pane (its height, its width, its padding) and of each row, after the
//   browser has laid the page out. Nothing else of the layout is read: no rectangles, no computed style.
// What is written, and when: the spacers' heights with the rows (React's commit), then the pane's scrollTop where the
// model puts it, once; it is read back as it is set (the browser may stop short of it, the page laid out by then).
import { createElement, useEffect, useLayoutEffect, useMemo, useReducer, useRef, type ReactNode, type RefObject } from "react";
import { flushSync } from "react-dom";
import { sizesOf, Virtual, type Align, type Item, type Layout, type Row } from "./model.ts";
import * as css from "./list.css.ts";

export type VirtualList = {
  model: Virtual;
  layout: Layout;
  /** The room above a row, as an element before it (null where it follows the row before it), and after the last. */
  above(row: Row, first: boolean): ReactNode;
  after(): ReactNode;
  /** Told after anything changed where the pane is or what it shows; answers how to stop being told. */
  watch(told: () => void): () => void;
  /** To the end, followed again: gliding there, or at once. */
  toEnd(atOnce?: boolean): void;
  /** To an item (model.ts `goto`); false while it is not among the items. */
  goto(key: string, align?: Align, pad?: number): boolean;
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
/** The most rows a selection keeps made. */
const SELECTED = 400;

type Made = {
  model: Virtual;
  gap: number;
  /** Where the pane was last put, or seen to be. */
  written: number;
  kept: number;
  /** A glide's own step is being written: not a move made to keep the pane's place. */
  stepping: boolean;
  drawn: string;
  born: number;
  watchers: Set<() => void>;
  frame: number;
  last: number;
};

/** A list's model, one for each `key` (a chat): made before its rows are, so where it opens can be said to it first. */
export function useVirtualModel(key: string, gap: number): Made {
  return useMemo(() => ({
    model: new Virtual({ gap, overscan: OVERSCAN, boost: BOOST }, sizesOf(key)),
    gap, written: Number.NaN, kept: 0, stepping: false, drawn: "", born: performance.now(), watchers: new Set<() => void>(), frame: 0, last: 0,
  }), [key, gap]);
}

export function useVirtualList(pane: RefObject<HTMLElement | null>, made: Made, items: Item[], options: {
  /** What floats over the pane's top, from the room before its first item (its padding). */
  cover?: (lead: number) => number;
  short?: boolean;
  /** Items left an end as the list's window moved along. */
  trimmed?: boolean;
  /** Whether what just came at the end is followed gliding (a message said as the reader watches) or at once. */
  smooth?: boolean;
  /** A message just come at the end: followed from its top (a long one is read from its start). */
  arrived?: string | null;
}): VirtualList {
  const { short = false, trimmed = false, smooth = false, arrived = null } = options;
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
  const layout = model.layout();
  made.drawn = signature(layout);

  const self = useMemo(() => {
    const tell = () => { for (const told of made.watchers) told(); };
    /** The pane put where the model has it, at once. */
    const put = (el: HTMLElement) => {
      const top = model.layout().scrollTop;
      if (Math.abs(top - made.written) < 0.5) return;
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
      if (model.mode.kind !== "follow" || !(model.target() > model.where + 0.5)) { model.glide(false); return; }
      made.last = performance.now();
      const glide = (now: number) => {
        made.frame = 0;
        const left = model.target() - model.where;
        if (model.mode.kind !== "follow" || left < 0.5) {
          // There: what came meanwhile is taken at once.
          model.glide(false);
          if (signature(model.layout()) !== made.drawn) flushSync(redraw);
          else put(el);
          tell();
          return;
        }
        const dt = Math.min(64, now - made.last);
        made.last = now;
        model.place(left < 1 ? model.target() : model.where + left * (1 - Math.exp(-dt / 100)));
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

  // The rows drawn: the pane where the model has it.
  useLayoutEffect(() => {
    const el = pane.current;
    if (!el) return;
    self.put(el);
    self.step(el);
    self.tell();
  });

  useEffect(() => {
    const el = pane.current;
    if (!el) return;
    let rest = 0;
    const scrolled = () => {
      const top = el.scrollTop;
      clearTimeout(rest);
      // At rest: the pane put where it should be (what was held under the scroll), fewer rows made ahead.
      rest = window.setTimeout(() => { model.rested(); self.sync(el); }, REST_MS);
      if (Math.abs(top - made.written) < 1) return;
      // The reader's: a glide stops where it is.
      cancelAnimationFrame(made.frame);
      made.frame = 0;
      model.glide(false);
      made.written = top;
      model.scrolled(top);
      // Not moved under the reader's scroll, unless the model has nothing left to hold what it should move by.
      self.sync(el);
    };
    el.addEventListener("scroll", scrolled, { passive: true });
    const sizes = new ResizeObserver((entries) => {
      const heights: [string, number][] = [];
      for (const entry of entries) {
        const box = entry.borderBoxSize[0];
        if (!box) continue;
        if (entry.target === el) {
          // The pane's padding is where its content box starts and what is left under it.
          const content = entry.contentRect;
          const lead = content.top;
          model.setEdges(lead, Math.max(0, box.blockSize - content.top - content.height));
          model.setViewport(box.blockSize, content.width, cover.current?.(lead) ?? 0);
          continue;
        }
        const row = entry.target as HTMLElement;
        const key = row.dataset.vk;
        // A row held back takes no room, not even the gap before it (its own negative margin).
        if (key !== undefined && row.isConnected) heights.push([key, box.blockSize - (row.hasAttribute("data-held") ? gap : 0)]);
      }
      // What grows at the end as the reader watches (a reply coming, an image loading) is followed gliding; the pane
      // itself resized lays everything out anew, taken at once.
      if (!entries.some((e) => e.target === el) && performance.now() - made.born > OPENING_MS && model.mode.kind === "follow") model.glide(true);
      model.measured(heights);
      self.sync(el);
    });
    sizes.observe(el);
    const watchRow = (n: Node) => { if (n instanceof HTMLElement && n.dataset.vk !== undefined) sizes.observe(n); };
    for (const n of el.children) watchRow(n);
    const rows = new MutationObserver((records) => {
      for (const r of records) {
        r.addedNodes.forEach(watchRow);
        r.removedNodes.forEach((n) => { if (n instanceof HTMLElement) sizes.unobserve(n); });
      }
    });
    rows.observe(el, { childList: true });
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
      clearTimeout(rest);
      cancelAnimationFrame(made.frame);
      made.frame = 0;
      el.removeEventListener("scroll", scrolled);
      el.removeEventListener("focusin", hold);
      el.removeEventListener("focusout", hold);
      document.removeEventListener("selectionchange", hold);
      sizes.disconnect();
      rows.disconnect();
      for (const k of held) model.pin(k, false);
    };
  }, [pane, made, model, self, gap]);

  return useMemo<VirtualList>(() => ({
    model,
    layout,
    // A spacer cancels the list's gap on the sides it has a neighbour: its height is all the room there is.
    above: (row, first) => (first ? (row.space > 0 ? spacer(`above ${row.key}`, row.space, "first") : null) : Math.abs(row.space - gap) > 0.5 ? spacer(`above ${row.key}`, row.space, "between") : null),
    after: () => (layout.after > 0 ? spacer("after", layout.after, layout.rows.length ? "last" : "only") : null),
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
      model.glide(false);
      const there = model.goto(key, align, pad);
      if (el) self.sync(el);
      return there;
    },
    kept: () => made.kept,
  }), [model, layout, made, self, pane, gap]);
}

function spacer(key: string, height: number, where: "first" | "between" | "last" | "only"): ReactNode {
  return createElement("div", { key, className: css.spacer, "data-where": where, "aria-hidden": true, style: { height: `${height}px` } });
}

/** What of a layout the rows drawn depend on. */
function signature(layout: Layout): string {
  return `${layout.rows.map((r) => `${r.key}:${r.space}`).join("|")}|${layout.after}`;
}
