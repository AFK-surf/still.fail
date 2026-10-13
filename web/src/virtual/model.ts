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
//   follows, what leaves the end leaves its room behind (`held`): the item at the pane's top stays where it is rather
//   than drop down, so the room is never more than down to the pane's bottom, and never so that no item shows.
// - `read`: an item `offset` below the pane's top: the reader's place, kept as items come above it, are measured other
//   than they were estimated, or the width changes.
// - `goto`: an item to be shown, perhaps not among the items yet: once it is, the pane goes there and reads from it.
//
// While the reader's scroll is under way the pane is not moved under it (a browser stops a scroll, and a finger's
// momentum, when the page sets where it is): what would move it to keep their place is kept as `drift` instead, taken
// from the room above the first row made, so every row shows where it would; once the scroll rests, the pane is put
// where it should be and the room given back, with nothing moving on screen.

export type Item = { key: string; estimate: number };
/** An item's height as measured, and the width of the pane it was measured in. */
export type Size = { height: number; width: number };
/** Where an item gone to stands: `pad` below what covers the pane's top, its middle at the pane's, or its top `pad` below the pane's. */
export type Align = "start" | "center" | "at";
export type Anchor =
  | { kind: "follow"; to: string | null }
  | { kind: "read"; key: string; offset: number }
  | { kind: "goto"; key: string; align: Align; pad: number };
/** An item made: `space` is the room above it (the gap, and with it the items not made between it and the one before). */
export type Row = { key: string; index: number; space: number };
/** `scrollTop` and `total` are the pane's own: less `drift` than where the items stand by their heights. */
export type Layout = { rows: Row[]; after: number; scrollTop: number; total: number; drift: number };
export type Options = {
  gap: number;
  /** How far past the pane's edges items are made, at rest; a scroll under way makes up to `boost` more ahead of it. */
  overscan: number;
  boost?: number;
  lead?: number;
  trail?: number;
};

/** How many items measured say how far off the estimates are, and how many measured at a width settle it there. */
const SAMPLE = 5;
const SETTLED = 8;
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
  /** While following: the item at the pane's top and how far below it its top is, and the room held after the last
   *  item so that it stays there as what is below it gets shorter. */
  private eye: { key: string; offset: number } | null = null;
  private held = 0;
  private pins = new Set<string>();
  /** The pane shows a window short of the list's end: its bottom is not followed. */
  private short = false;
  /** The page takes the pane to where it follows step by step (`place`), not at once. */
  private gliding = false;
  private velocity = 0;
  /** How much taller the items measured are than they were estimated, in all; and the width it is settled for. */
  private scale = 1;
  private settled = -1;
  private guessing = false;
  /** A scroll of the reader's is under way. */
  private moving = false;
  /** How far the pane is from where it should be by its anchor, held until the scroll rests. */
  private drift = 0;
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
    if (trimmed || !items.length) this.release();
    if (!items.length && this.anchor.kind !== "goto") this.anchor = { kind: "follow", to: null };
    this.settle();
  }
  /** Heights measured (an observer's report), in the pane as wide as it is now. */
  measured(heights: Iterable<readonly [key: string, height: number]>): void {
    let changed = false;
    let guessed = false;
    for (const [key, height] of heights) {
      const was = this.sizes.get(key);
      if (was && was.height === height && was.width === this.width) continue;
      const i = this.at.get(key);
      // Shorter than it was taken to be before it was measured here: it was never that tall, and no room is held for it.
      if (i !== undefined && was?.width !== this.width && height < this.heightOf(i)) guessed = true;
      this.sizes.set(key, { height, width: this.width });
      changed = changed || i !== undefined;
    }
    if (!changed) return;
    if (guessed) this.release();
    this.retop();
    this.settle();
  }
  /** The pane's size, and what covers its top. A new width lays every item out anew: nothing is held from before it. */
  setViewport(height: number, width: number, cover = this.cover): void {
    if (height === this.height && width === this.width && cover === this.cover) return;
    // Room is held for what leaves the list's end, not for the pane itself changing: following, it stays at its end.
    this.release();
    this.height = height;
    this.width = width;
    this.cover = cover;
    this.settle();
  }
  /** The room before the first item and after the last (the pane's padding). */
  setEdges(lead: number, trail: number): void {
    if (lead === this.lead && trail === this.trail) return;
    this.release();
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
  scrolled(at: number): void {
    const top = at + this.drift;
    // Scrolled to an end of what the pane has while more is held past it: the pane is put where it should be now
    // (the scroll has nowhere to go on to).
    if ((this.drift > 0 && at <= 1) || (this.drift < 0 && at >= this.bottom() - this.drift - 1)) this.drift = 0;
    if (Math.abs(top - this.top) < 1) return;
    this.moving = true;
    this.velocity = top - this.top;
    // Scrolled up, what was held is let go: it is not held again.
    if (top < this.top) this.release();
    this.top = top;
    if (!this.short && this.bottom() - top <= 2) this.anchor = { kind: "follow", to: null };
    else this.note();
    this.guard();
    this.eye = this.anchor.kind === "follow" ? this.see() : null;
  }
  /** The scroll came to rest: nothing more is made ahead of it, and the pane is put where it should be. */
  rested(): void {
    this.velocity = 0;
    this.moving = false;
    this.drift = 0;
  }
  /** The page's own step toward where the pane follows (a glide). */
  place(top: number): void {
    this.moving = false;
    this.drift = 0;
    this.top = Math.min(Math.max(0, top), this.bottom());
    this.arrived();
    this.eye = this.anchor.kind === "follow" ? this.see() : null;
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
    this.still();
    this.settle();
  }
  /** To an item (`Align`); one not among the items yet, when it is. */
  goto(key: string, align: Align = "start", pad = 0): boolean {
    this.anchor = { kind: "goto", key, align, pad };
    this.release();
    this.still();
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
        : a.align === "at" ? this.topOf(i) - a.pad
          : this.topOf(i) + this.heightOf(i) / 2 - this.height / 2;
    return Math.min(end, Math.max(0, to));
  }
  /** The items to make, the room around them, and where the pane is scrolled. */
  layout(): Layout {
    const n = this.items.length;
    const ahead = Math.min(this.boost, Math.abs(this.velocity) * 4);
    const from = this.top - this.overscan - (this.velocity < 0 ? ahead : 0);
    // Following, everything from the pane down to the list's end is made, however far below the pane it reaches for
    // now (a long message just come, the pane still on its way down): what stands after it (the agent's activity,
    // the next message) is there to be seen coming, and for what moves between them (a reply out of its avatar).
    const to = this.anchor.kind === "follow" ? Number.POSITIVE_INFINITY : this.top + this.height + this.overscan + (this.velocity > 0 ? ahead : 0);
    const made = new Set<number>();
    for (let i = this.firstReaching(from); i < n && this.topOf(i) < to; i++) made.add(i);
    for (const key of this.pins) { const i = this.at.get(key); if (i !== undefined) made.add(i); }
    if (this.anchor.kind !== "follow" || this.anchor.to !== null) {
      const i = this.at.get(this.anchor.kind === "follow" ? this.anchor.to! : this.anchor.key);
      if (i !== undefined) made.add(i);
    }
    const rows: Row[] = [];
    let end = 0;
    this.guessing = false;
    for (const i of [...made].sort((a, b) => a - b)) {
      if (this.sizes.get(this.items[i]!.key)?.width !== this.width) this.guessing = true;
      rows.push({ key: this.items[i]!.key, index: i, space: this.tops[i]! - end });
      end = this.tops[i]! + this.heightOf(i);
    }
    // What is held of the pane's place comes out of the room above the first row: no more than there is of it.
    // More held than there is room for: the pane is put where it should be now.
    const head = rows[0];
    if (!head || this.drift > head.space || this.top - this.drift < 0) this.drift = 0;
    if (head) head.space -= this.drift;
    const total = this.total();
    return { rows, after: total - this.lead - this.trail - end, scrollTop: this.top - this.drift, total: total - this.drift, drift: this.drift };
  }
  get mode(): Anchor { return this.anchor; }
  /** How far the pane is from the end of what it scrolls, and from its start. */
  get toEnd(): number { return Math.max(0, this.bottom() - this.top); }
  get toStart(): number { return this.top; }
  /** Where the pane is, by the items' own places (what is held under a scroll counted in). */
  get where(): number { return this.top; }
  /** How tall the pane is, and whether all there is fits in it (nothing to scroll). */
  get paneHeight(): number { return this.height; }
  get paneWidth(): number { return this.width; }
  /** A row of the last layout stands at a height not measured yet in the pane as wide as it is: where the rows after
   *  it are is a guess until the page reports it. */
  get guessed(): boolean { return this.guessing; }
  /** How much taller than its estimate an item not measured is taken to be. */
  get scaled(): number { return this.scale; }
  get fits(): boolean { return this.total() <= this.height; }
  /** What covers the pane's top. */
  get covered(): number { return this.cover; }
  keyAt(index: number): string | undefined { return this.items[index]?.key; }
  indexOf(key: string): number | undefined { return this.at.get(key); }
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
    return this.sizes.get(item.key)?.height ?? item.estimate * this.scale;
  }
  private topOf(i: number): number { return this.lead + this.tops[i]!; }
  private retop(): void {
    const n = this.items.length;
    // The items measured say how far off the estimates are: those not measured yet are taken that much taller or shorter.
    // From a few of them on (one tall message says nothing of the rest), and settled once enough are measured at this
    // width: taken anew with every message measured, the items above the pane would shift a little each time, and
    // what stands over the list by where its rows are (an avatar flying to its message) with them.
    if (this.settled !== this.width) {
      let measured = 0;
      let estimated = 0;
      let count = 0;
      let here = 0;
      for (const item of this.items) {
        const size = this.sizes.get(item.key);
        if (!size || size.height <= 0 || item.estimate <= 0) continue;
        measured += size.height;
        estimated += item.estimate;
        count++;
        if (size.width === this.width) here++;
      }
      this.scale = count >= SAMPLE ? Math.min(4, Math.max(0.25, measured / estimated)) : 1;
      if (here >= SETTLED) this.settled = this.width;
    }
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
  /** How tall it is with what is held at its end, while following. */
  private total(): number { return this.natural() + (this.anchor.kind === "follow" ? this.held : 0); }
  private release(): void {
    this.held = 0;
    this.eye = null;
  }
  /** The item at the pane's top (below what covers it), and where its top is. */
  private see(): { key: string; offset: number } | null {
    const i = this.firstReaching(this.top + this.cover + 1);
    return i < this.items.length ? { key: this.items[i]!.key, offset: this.topOf(i) - this.top } : null;
  }
  /** The furthest the pane scrolls. */
  private bottom(): number { return Math.max(0, this.total() - this.height); }
  /** The reader's place as the pane stands: the first item reaching below what covers its top. */
  private note(): void {
    const i = this.firstReaching(this.top + this.cover + 1);
    this.anchor = i < this.items.length ? { kind: "read", key: this.items[i]!.key, offset: this.topOf(i) - this.top } : { kind: "follow", to: null };
  }
  /** The pane is where it is put from now on: no scroll of the reader's goes on under it. */
  private still(): void {
    this.moving = false;
    this.velocity = 0;
    this.drift = 0;
  }
  /** The pane put where its anchor says, after anything changed. */
  private settle(): void {
    const from = this.top;
    this.resettle();
    this.eye = this.anchor.kind === "follow" ? this.see() : null;
    // Under a scroll of the reader's, it stays where their scroll has it: how far it should have gone is held.
    if (this.moving) this.drift += this.top - from;
  }
  private resettle(): void {
    // A window short of the list's end has no end to follow: the reader's place is where the pane is.
    if (this.short && this.anchor.kind === "follow") this.note();
    const a = this.anchor;
    if (a.kind === "follow") {
      // What is below the item at the pane's top got shorter: it stays where it is, the room it would have dropped by
      // held after the last item.
      this.held = 0;
      const i = this.eye ? this.at.get(this.eye.key) : undefined;
      // Where the pane is now that the items above it stand where they do: what shows has not moved.
      const here = i === undefined ? this.top : Math.max(0, this.topOf(i) - this.eye!.offset);
      if (i !== undefined) this.held = Math.max(0, here - Math.max(0, this.natural() - this.height));
      const to = this.target();
      // On from there to where it follows: by the page's steps while it glides, else at once.
      this.top = !this.gliding || to < here ? to : here;
      this.arrived();
    } else {
      this.release();
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
    if (n && this.held > 0 && this.top + this.cover >= this.topOf(n - 1) + this.heightOf(n - 1)) this.release();
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
