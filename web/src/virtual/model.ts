// A long list of which only what shows is made: where each of its items stands, which of them are made, and where the
// pane is scrolled to, worked out here from what the page tells it (the items, the heights it measured, the pane's
// size, where the reader scrolled) and from nothing else. No DOM here: VirtualList.tsx reads the page once a frame
// (a scroll's position, an observer's sizes) and writes what `layout()` answers once.
//
// Everything is in the pane's scroll coordinates: 0 is the top of what it scrolls. Before the first item is `lead`
// (the pane's own padding), between two items `gap`, after the last `trail`. An item not measured yet stands as tall
// as its `estimate`; one measured at another width, as tall as it was there, until measured again.
//
// One anchor says where the pane is, whatever changes:
// - `follow`: its end (or, `to`, a message just come, from its top: a long one is read from its start). While it
//   follows, what leaves the end leaves its room behind (`held`), down to the pane's bottom and no further, so nothing
//   above drops down; never so that no item shows.
// - `read`: an item `offset` below the pane's top: the reader's place, kept as items come above it, are measured other
//   than they were estimated, or the width changes.
// - `goto`: an item to be shown, perhaps not among the items yet: once it is, the pane goes there and reads from it.

export type Item = { key: string; estimate: number };
/** An item's height as measured, and the width of the pane it was measured in. */
export type Size = { height: number; width: number };
export type Align = "start" | "center";
export type Anchor =
  | { kind: "follow"; to: string | null }
  | { kind: "read"; key: string; offset: number }
  | { kind: "goto"; key: string; align: Align; pad: number };
/** An item made: `space` is the room above it (the gap, and with it the items not made between it and the one before). */
export type Row = { key: string; index: number; space: number };
export type Layout = { rows: Row[]; after: number; scrollTop: number; total: number };
export type Options = {
  gap: number;
  /** How far past the pane's edges items are made, at rest; a scroll under way makes up to `boost` more ahead of it. */
  overscan: number;
  boost?: number;
  lead?: number;
  trail?: number;
};

/** Under what covers the pane's top, a followed message stops this far below it. */
const UNDER = 12;

export class Virtual {
  private items: Item[] = [];
  private at = new Map<string, number>();
  /** `tops[i]`: the top of item i from the first item's top; `tops[n]`: the last item's bottom. */
  private tops: number[] = [0];
  private height = 0;
  private width = 0;
  /** What floats over the pane's top (a bar): an item is shown below it. */
  private cover = 0;
  private top = 0;
  private anchor: Anchor = { kind: "follow", to: null };
  /** The furthest the content reached while following: what it lost since is held. */
  private reach = 0;
  private pins = new Set<string>();
  /** The pane shows a window short of the list's end: its bottom is not followed. */
  private short = false;
  /** The page takes the pane to where it follows step by step (`place`), not at once. */
  private gliding = false;
  private velocity = 0;
  private readonly gap: number;
  private readonly overscan: number;
  private readonly boost: number;
  private lead: number;
  private trail: number;

  /** The heights measured, by item: the page may hand in those kept from the last time the list showed (`sizesOf`). */
  readonly sizes: Map<string, Size>;

  constructor(options: Options, sizes: Map<string, Size> = new Map()) {
    this.sizes = sizes;
    this.gap = options.gap;
    this.overscan = options.overscan;
    this.boost = options.boost ?? options.overscan * 4;
    this.lead = options.lead ?? 0;
    this.trail = options.trail ?? 0;
  }

  // What the page tells it.

  /** The list's items now. `trimmed`: some left an end as the list's window moved along (their room is not held). */
  setItems(items: Item[], trimmed = false): void {
    this.items = items;
    this.at = new Map(items.map((item, i) => [item.key, i]));
    this.retop();
    if (trimmed || !items.length) this.reach = 0;
    if (!items.length && this.anchor.kind !== "goto") this.anchor = { kind: "follow", to: null };
    this.settle();
  }
  /** Heights measured (an observer's report), in the pane as wide as it is now. */
  measured(heights: Iterable<readonly [key: string, height: number]>): void {
    let changed = false;
    for (const [key, height] of heights) {
      const was = this.sizes.get(key);
      if (was && was.height === height && was.width === this.width) continue;
      this.sizes.set(key, { height, width: this.width });
      changed = changed || this.at.has(key);
    }
    if (!changed) return;
    this.retop();
    this.settle();
  }
  /** The pane's size, and what covers its top. A new width lays every item out anew: nothing is held from before it. */
  setViewport(height: number, width: number, cover = this.cover): void {
    if (height === this.height && width === this.width && cover === this.cover) return;
    if (width !== this.width) this.reach = 0;
    this.height = height;
    this.width = width;
    this.cover = cover;
    this.settle();
  }
  /** The room before the first item and after the last (the pane's padding). */
  setEdges(lead: number, trail: number): void {
    if (lead === this.lead && trail === this.trail) return;
    this.lead = lead;
    this.trail = trail;
    this.settle();
  }
  setShort(short: boolean): void {
    if (short === this.short) return;
    this.short = short;
    if (short && this.anchor.kind === "follow") this.note();
    this.settle();
  }
  /** The pane was scrolled to `top`: by the reader, unless it is where this put it. */
  scrolled(top: number): void {
    if (Math.abs(top - this.top) < 1) return;
    this.velocity = top - this.top;
    // Scrolled up, what was held is let go: it is not held again.
    if (top < this.top) this.reach = 0;
    this.top = top;
    if (!this.short && this.bottom() - top <= 2) this.anchor = { kind: "follow", to: null };
    else this.note();
    this.guard();
  }
  /** The scroll came to rest: nothing more is made ahead of it. */
  rested(): void { this.velocity = 0; }
  /** The page's own step toward where the pane follows (a glide). */
  place(top: number): void {
    this.top = Math.min(Math.max(0, top), this.bottom());
    this.arrived();
  }
  /** Whether following goes by the page's steps (`place` toward `target()`) or at once. */
  glide(on: boolean): void {
    this.gliding = on;
    if (!on) this.settle();
  }
  /** To the end, followed from now on; with `to`, a message just come, to its top when it is taller than the pane. */
  follow(to: string | null = null): void {
    if (this.short) return;
    this.anchor = { kind: "follow", to };
    this.settle();
  }
  /** To an item, at the pane's top (`pad` below what covers it) or its middle; one not among the items yet, when it is. */
  goto(key: string, align: Align = "start", pad = 0): boolean {
    this.anchor = { kind: "goto", key, align, pad };
    this.reach = 0;
    this.settle();
    return this.at.has(key);
  }
  /** An item kept made wherever the pane is (it holds the focus, a selection, something open, or it is moving). */
  pin(key: string, on = true): void {
    if (on) this.pins.add(key);
    else this.pins.delete(key);
  }

  // What it answers.

  /** Where the pane goes by its anchor. */
  target(): number {
    const a = this.anchor;
    if (a.kind === "follow") {
      const end = this.bottom();
      const i = a.to === null ? undefined : this.at.get(a.to);
      return i === undefined ? end : Math.min(end, Math.max(0, this.topOf(i) - this.cover - UNDER));
    }
    const i = this.at.get(a.key);
    if (i === undefined) return Math.min(this.top, this.bottom());
    const end = Math.max(0, this.natural() - this.height);
    const to = a.kind === "read" ? this.topOf(i) - a.offset
      : a.align === "start" ? this.topOf(i) - this.cover - a.pad
        : this.topOf(i) + this.heightOf(i) / 2 - this.height / 2;
    return Math.min(end, Math.max(0, to));
  }
  /** The items to make, the room around them, and where the pane is scrolled. */
  layout(): Layout {
    const n = this.items.length;
    const ahead = Math.min(this.boost, Math.abs(this.velocity) * 4);
    const from = this.top - this.overscan - (this.velocity < 0 ? ahead : 0);
    const to = this.top + this.height + this.overscan + (this.velocity > 0 ? ahead : 0);
    const made = new Set<number>();
    for (let i = this.firstReaching(from); i < n && this.topOf(i) < to; i++) made.add(i);
    for (const key of this.pins) { const i = this.at.get(key); if (i !== undefined) made.add(i); }
    if (this.anchor.kind !== "follow" || this.anchor.to !== null) {
      const i = this.at.get(this.anchor.kind === "follow" ? this.anchor.to! : this.anchor.key);
      if (i !== undefined) made.add(i);
    }
    const rows: Row[] = [];
    let end = 0;
    for (const i of [...made].sort((a, b) => a - b)) {
      rows.push({ key: this.items[i]!.key, index: i, space: this.tops[i]! - end });
      end = this.tops[i]! + this.heightOf(i);
    }
    const total = this.total();
    return { rows, after: total - this.lead - this.trail - end, scrollTop: this.top, total };
  }
  get mode(): Anchor { return this.anchor; }
  /** How far the pane is from the end of what it scrolls, and from its start. */
  get toEnd(): number { return Math.max(0, this.bottom() - this.top); }
  get toStart(): number { return this.top; }
  /** The items that show in the pane, first and last (indices); null with none. */
  showing(): { first: number; last: number } | null {
    const first = this.firstReaching(this.top + this.cover);
    if (first >= this.items.length || this.topOf(first) >= this.top + this.height) return null;
    let last = first;
    while (last + 1 < this.items.length && this.topOf(last + 1) < this.top + this.height) last++;
    return { first, last };
  }
  /** Where an item's top is, from the pane's top; undefined for one not among the items. */
  offsetOf(key: string): number | undefined {
    const i = this.at.get(key);
    return i === undefined ? undefined : this.topOf(i) - this.top;
  }

  // How it works them out.

  private heightOf(i: number): number {
    const item = this.items[i]!;
    return this.sizes.get(item.key)?.height ?? item.estimate;
  }
  private topOf(i: number): number { return this.lead + this.tops[i]!; }
  private retop(): void {
    const n = this.items.length;
    const tops = new Array<number>(n + 1);
    let y = 0;
    for (let i = 0; i < n; i++) {
      tops[i] = y;
      y += this.heightOf(i) + (i < n - 1 ? this.gap : 0);
    }
    tops[n] = y;
    this.tops = tops;
  }
  /** The first item whose bottom is below `y` (the count of items with none). */
  private firstReaching(y: number): number {
    let lo = 0;
    let hi = this.items.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.topOf(mid) + this.heightOf(mid) > y) hi = mid;
      else lo = mid + 1;
    }
    return lo;
  }
  /** How tall the content is by its items alone. */
  private natural(): number { return this.lead + this.tops[this.items.length]! + this.trail; }
  /** How tall it is with what is held at its end: only while following, only down to the pane's bottom. */
  private total(): number {
    const natural = this.natural();
    if (this.anchor.kind !== "follow") return natural;
    return Math.max(natural, Math.min(this.reach, this.top + this.height));
  }
  /** The furthest the pane scrolls. */
  private bottom(): number { return Math.max(0, this.total() - this.height); }
  /** The reader's place as the pane stands: the first item reaching below what covers its top. */
  private note(): void {
    const i = this.firstReaching(this.top + this.cover + 1);
    this.anchor = i < this.items.length ? { kind: "read", key: this.items[i]!.key, offset: this.topOf(i) - this.top } : { kind: "follow", to: null };
  }
  /** The pane put where its anchor says, after anything changed. */
  private settle(): void {
    // A window short of the list's end has no end to follow: the reader's place is where the pane is.
    if (this.short && this.anchor.kind === "follow") this.note();
    const a = this.anchor;
    if (a.kind === "follow") {
      this.reach = Math.max(this.reach, this.natural());
      const to = this.target();
      if (!this.gliding || to < this.top) this.top = to;
      this.arrived();
    } else {
      this.top = this.target();
      // Gone to: read from there, so it stays as what is above it is measured.
      if (a.kind === "goto") { const i = this.at.get(a.key); if (i !== undefined) this.anchor = { kind: "read", key: a.key, offset: this.topOf(i) - this.top }; }
      // The reader's item gone: their place is where the pane is.
      else if (!this.at.has(a.key)) this.note();
    }
    this.guard();
  }
  /** A followed message taller than what is left of the pane, reached: read from its start, its place kept from here. */
  private arrived(): void {
    const a = this.anchor;
    if (a.kind !== "follow" || a.to === null) return;
    const i = this.at.get(a.to);
    if (i === undefined) { this.anchor = { kind: "follow", to: null }; return; }
    const to = this.target();
    if (to < this.bottom() - 0.5 && Math.abs(this.top - to) < 1) this.anchor = { kind: "read", key: a.to, offset: this.topOf(i) - this.top };
  }
  /** Never a pane of held room alone: with items, one of them shows, or what is held is let go. */
  private guard(): void {
    const n = this.items.length;
    if (n && this.top + this.cover >= this.topOf(n - 1) + this.heightOf(n - 1) && this.total() > this.natural()) {
      this.reach = 0;
      this.top = Math.min(this.top, this.bottom());
    }
    this.top = Math.min(Math.max(0, this.top), this.bottom());
  }
}

/** The heights measured in the lists lately shown, kept by list (a chat come back to is laid out as it was): the
 *  latest `KEPT` of them. */
const KEPT = 20;
const kept = new Map<string, Map<string, Size>>();
export function sizesOf(list: string): Map<string, Size> {
  const sizes = kept.get(list) ?? new Map<string, Size>();
  kept.delete(list);
  kept.set(list, sizes);
  while (kept.size > KEPT) kept.delete(kept.keys().next().value!);
  return sizes;
}
