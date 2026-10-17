// A list that keeps to its newest end (web/src/scroll.ts), with the reader not
// touching it: a new message arriving while the list is at its end is followed
// down until its top reaches the top, so a long one is read from its start;
// anything else growing below keeps the end in view. Any scroll it did not make
// itself (the reader's finger and its fling, a code box within it handing on
// at its edge, a jump) sets the new position, as the web's `moved`: once the
// list is at rest, at the end it follows again, elsewhere it stays put.
// Something the reader opens in the list (stay) is not new: it is not followed.
// The list growing shorter (the keyboard) keeps its bottom in place.
// A list whose end is not where it ends (short: a chat's window short of its
// newest) is never followed: what comes in below is a page read, not said.
// Following glides (scroll.ts glide): each frame covers the same share of what
// is left, 1 - e^(-dt/100ms), so a long way is quick and a goal that moves on
// (a reply still growing) is followed without a restart; the reader's finger
// takes the list from it at once. The list's first moments, and anything the
// list does not grow by (the keyboard), are taken at once.
//
// Compose's LazyListState, which the Android app follows, is here too (LazyListState): what a FlatList says of itself
// (its scroll, its size, its cells' places), and its scrolls, one at a time, a finger taking the list from them.
import { useEffect, useMemo, useSyncExternalStore, type ComponentType, type ReactNode, type RefObject } from "react";
import { StyleSheet, View, type FlatList, type LayoutChangeEvent, type NativeScrollEvent, type NativeSyntheticEvent, type StyleProp, type ViewStyle } from "react-native";
import { reducedMotion } from "./Parts";

// ── the list's state ───────────────────────────────────────────────────

/** A scroll taken over by another (the reader's finger, a newer scroll): what was waiting in it ends with this. */
export class CancellationException extends Error {
  constructor() { super("scroll taken over"); this.name = "CancellationException"; }
}

/** The next frame's time, in ms (Compose's withFrameNanos, in ms). */
export function withFrameMillis(): Promise<number> {
  return new Promise((resolve) => requestAnimationFrame((t) => resolve(t)));
}

/** An item laid out in view (Compose's LazyListItemInfo): its offset from the viewport's start (after the padding before), its size. */
export interface LazyListItemInfo { index: number; key: string | null; offset: number; size: number }

/** What the list laid out (Compose's LazyListLayoutInfo). */
export interface LazyListLayoutInfo {
  totalItemsCount: number;
  visibleItemsInfo: LazyListItemInfo[];
  viewportStartOffset: number;
  viewportEndOffset: number;
  beforeContentPadding: number;
  afterContentPadding: number;
  mainAxisItemSpacing: number;
  viewportSize: { width: number; height: number };
}

/** What a scroll can do while it has the list (Compose's ScrollScope). */
export interface ScrollScope { scrollBy(px: number): number }

/** What a list draws itself with: the props to give its FlatList, its items' count and its paddings told. */
export interface ListBinding {
  ref: (list: FlatList<unknown> | null) => void;
  onScroll: (e: NativeSyntheticEvent<NativeScrollEvent>) => void;
  scrollEventThrottle: number;
  onLayout: (e: LayoutChangeEvent) => void;
  onContentSizeChange: (w: number, h: number) => void;
  onScrollBeginDrag: () => void;
  onScrollEndDrag: () => void;
  onMomentumScrollBegin: () => void;
  onMomentumScrollEnd: () => void;
  onScrollToIndexFailed: (info: { index: number; averageItemLength: number }) => void;
  // Any item: the cell reads only its index and key.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  CellRendererComponent: ComponentType<any>;
}

interface CellProps { index: number; cellKey?: string; onLayout?: (e: LayoutChangeEvent) => void; style?: StyleProp<ViewStyle>; children?: ReactNode }

/** A FlatList's state as Compose's LazyListState: where it is, what is laid out, and its scrolls. */
export class LazyListState {
  #bound: FlatList<unknown> | null = null;
  /** Told by bind; else read from the FlatList itself (its data, its content's padding and gap). */
  #told: { count: number; before: number; after: number; spacing: number } | null = null;
  #y = 0;
  #viewport = { width: 0, height: 0 };
  #content = 0;
  readonly #items = new Map<number, { y: number; size: number; key: string | null }>();
  #dragging = false;
  #flinging = false;
  #scrolling = 0;
  #current: { cancelled: boolean } | null = null;
  #version = 0;
  readonly #listeners = new Set<() => void>();

  /** `ref`: the FlatList, when the page holds it itself (`ref={list}`, with `{...state.listProps}`). */
  constructor(private readonly ref: RefObject<FlatList<any> | null> | null = null) {}

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of [...this.#listeners]) l(); }

  get #list(): FlatList<unknown> | null { return (this.ref?.current as FlatList<unknown> | null | undefined) ?? this.#bound; }
  get #own(): { count: number; before: number; after: number; spacing: number } {
    if (this.#told) return this.#told;
    const props = this.#list?.props;
    const pad = StyleSheet.flatten(props?.contentContainerStyle) ?? {};
    const num = (...v: unknown[]) => { for (const x of v) if (typeof x === "number") return x; return 0; };
    return {
      count: (props?.data as ArrayLike<unknown> | null | undefined)?.length ?? 0,
      before: num(pad.paddingTop, pad.paddingVertical, pad.padding),
      after: num(pad.paddingBottom, pad.paddingVertical, pad.padding),
      spacing: num(pad.rowGap, pad.gap),
    };
  }
  get #count() { return this.#own.count; }
  get #before() { return this.#own.before; }
  get #after() { return this.#own.after; }
  get #spacing() { return this.#own.spacing; }

  get #max() { return Math.max(0, this.#content - this.#viewport.height); }

  get layoutInfo(): LazyListLayoutInfo {
    const top = this.#y;
    const bottom = this.#y + this.#viewport.height;
    const visible: LazyListItemInfo[] = [];
    for (const [index, it] of this.#items) {
      if (index >= this.#count) continue;
      if (it.y < bottom && it.y + it.size > top) visible.push({ index, key: it.key, offset: it.y - top - this.#before, size: it.size });
    }
    visible.sort((a, b) => a.index - b.index);
    return {
      totalItemsCount: this.#count,
      visibleItemsInfo: visible,
      viewportStartOffset: -this.#before,
      viewportEndOffset: this.#viewport.height - this.#before,
      beforeContentPadding: this.#before,
      afterContentPadding: this.#after,
      mainAxisItemSpacing: this.#spacing,
      viewportSize: { ...this.#viewport },
    };
  }

  get canScrollForward(): boolean { return this.#y < this.#max - 0.5; }
  get canScrollBackward(): boolean { return this.#y > 0.5; }
  /** A finger on it, its fling, or a scroll of the app's own. */
  get isScrollInProgress(): boolean { return this.#dragging || this.#flinging || this.#scrolling > 0; }
  get firstVisibleItemIndex(): number { return this.layoutInfo.visibleItemsInfo[0]?.index ?? 0; }
  get firstVisibleItemScrollOffset(): number { return Math.max(0, -(this.layoutInfo.visibleItemsInfo[0]?.offset ?? 0)); }

  /**
   * The props for the FlatList it is the state of: `count` its items, `before` and `after` its content's padding at
   * its start and end, `spacing` between two items (Arrangement.spacedBy).
   */
  bind(count: number, { before = 0, after = 0, spacing = 0 }: { before?: number; after?: number; spacing?: number } = {}): ListBinding {
    const was = this.#told;
    if (!was || count !== was.count || before !== was.before || after !== was.after || spacing !== was.spacing) {
      this.#told = { count, before, after, spacing };
      for (const k of [...this.#items.keys()]) if (k >= count) this.#items.delete(k);
      queueMicrotask(() => this.#changed());
    }
    return this.#binding;
  }

  /** The props for its FlatList when the page holds the list's ref itself: all of bind's but `ref`. */
  get listProps(): Omit<ListBinding, "ref" | "onScrollToIndexFailed"> {
    const { ref: _ref, onScrollToIndexFailed: _failed, ...rest } = this.#binding;
    return rest;
  }

  readonly #Cell = (props: CellProps) => (
    <View
      {...props}
      onLayout={(e) => {
        props.onLayout?.(e);
        const { y, height } = e.nativeEvent.layout;
        const was = this.#items.get(props.index);
        if (was && was.y === y && was.size === height) return;
        this.#items.set(props.index, { y, size: height, key: props.cellKey ?? null });
        this.#changed();
      }}
    />
  );

  readonly #binding: ListBinding = {
    ref: (list) => { this.#bound = list; },
    onScroll: (e) => {
      const { contentOffset, contentSize, layoutMeasurement } = e.nativeEvent;
      this.#y = contentOffset.y;
      this.#content = contentSize.height;
      if (layoutMeasurement.height !== this.#viewport.height) this.#viewport = { width: layoutMeasurement.width, height: layoutMeasurement.height };
      this.#changed();
    },
    scrollEventThrottle: 16,
    onLayout: (e) => {
      const { width, height } = e.nativeEvent.layout;
      if (width === this.#viewport.width && height === this.#viewport.height) return;
      this.#viewport = { width, height };
      this.#changed();
    },
    onContentSizeChange: (_w, h) => { if (h !== this.#content) { this.#content = h; this.#changed(); } },
    // The reader's finger takes the list from what the app was doing with it.
    onScrollBeginDrag: () => { this.#cancel(); this.#dragging = true; this.#changed(); },
    onScrollEndDrag: () => { this.#dragging = false; this.#changed(); },
    onMomentumScrollBegin: () => { this.#flinging = true; this.#changed(); },
    onMomentumScrollEnd: () => { this.#flinging = false; this.#changed(); },
    onScrollToIndexFailed: ({ index, averageItemLength }) => {
      // Not laid out yet: as near as the rows that are say, then there once it is.
      this.#to(Math.min(this.#max, index * averageItemLength));
      requestAnimationFrame(() => this.#list?.scrollToIndex({ index, animated: false }));
    },
    CellRendererComponent: this.#Cell,
  };

  #cancel() {
    if (this.#current) { this.#current.cancelled = true; this.#current = null; }
  }

  /** Puts the list at `y` at once (as far as it goes); how far it moved. */
  #to(y: number): number {
    const target = Math.max(0, Math.min(this.#max, y));
    const used = target - this.#y;
    if (used === 0) return 0;
    this.#list?.scrollToOffset({ offset: target, animated: false });
    this.#y = target;
    this.#changed();
    return used;
  }

  /**
   * A scroll of the app's own (Compose's scroll {}): `block` has the list until it ends, or until another scroll or the
   * reader's finger takes it (its next move then throws CancellationException).
   */
  async scroll(block: (scope: ScrollScope) => Promise<void> | void): Promise<void> {
    this.#cancel();
    const token = { cancelled: false };
    this.#current = token;
    this.#scrolling++;
    this.#changed();
    try {
      await block({
        scrollBy: (px) => {
          if (token.cancelled) throw new CancellationException();
          return this.#to(this.#y + px);
        },
      });
      if (token.cancelled) throw new CancellationException();
    } finally {
      this.#scrolling--;
      if (this.#current === token) this.#current = null;
      this.#changed();
    }
  }

  /** Whether the scroll under way (if any) was taken over: for a block awaiting a frame. */
  cancelledNow(): boolean { return this.#current == null && this.#scrolling > 0; }

  /** By `px` (down is positive) as far as it goes; how far it went. */
  async scrollBy(px: number): Promise<number> {
    let used = 0;
    await this.scroll((s) => { used = s.scrollBy(px); });
    return used;
  }

  /** Item `index` at the viewport's start, `scrollOffset` further on (as far as the list goes). */
  async scrollToItem(index: number, scrollOffset = 0): Promise<void> {
    await this.scroll(async (s) => {
      const it = this.#items.get(index);
      if (it) { s.scrollBy(it.y - this.#before + scrollOffset - this.#y); return; }
      if (index < 0 || index >= this.#count) return;
      this.#list?.scrollToIndex({ index, viewOffset: -scrollOffset, animated: false });
      await withFrameMillis();
    });
  }

  /** As scrollToItem, gliding there (the system's smooth scroll). */
  async animateScrollToItem(index: number, scrollOffset = 0): Promise<void> {
    const it = this.#items.get(index);
    if (it) this.#list?.scrollToOffset({ offset: Math.max(0, Math.min(this.#max, it.y - this.#before + scrollOffset)), animated: true });
    else if (index >= 0 && index < this.#count) this.#list?.scrollToIndex({ index, viewOffset: -scrollOffset, animated: true });
  }
}

/** The state of a list, kept with the page (Compose's rememberLazyListState). */
export function rememberLazyListState(ref: RefObject<FlatList<any> | null> | null = null): LazyListState {
  return useMemo(() => new LazyListState(ref), [ref]);
}

// ── following its end ──────────────────────────────────────────────────

export class Follow {
  #placed = false;
  #on = false;
  #short = false;
  #anchor: unknown = null;
  #paused = false;
  #own = 0;
  /** Half a second after it was placed: from then on what comes in is glided after. */
  grown = false;
  /** Where an item is, by key (-1: not in the list). */
  indexOf: (key: unknown) => number = () => -1;
  /** A message was gone to (its top under the bar): the list keeping it there through a resize (the keyboard going as
   *  the chat opens from a search) rather than what is at its bottom, until the reader moves it. */
  topHeld = false;
  /** Someone else moved the list since it was last at rest. */
  touched = false;
  /** How much slower the system has motion (its animator scale; React Native says only whether it is off). */
  motionScale = 1;
  #version = 0;
  readonly #listeners = new Set<() => void>();

  constructor(readonly list: LazyListState, private readonly margin: number) {}

  /** The props for the FlatList it follows (its state's: its scroll, its size, its cells' places). */
  get listProps(): Omit<ListBinding, "ref" | "onScrollToIndexFailed"> { return this.list.listProps; }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of [...this.#listeners]) l(); }

  /** Until the list is first put in place (its end, a remembered place, the unread line) nothing is followed. */
  get placed() { return this.#placed; }
  set placed(v: boolean) { if (v !== this.#placed) { this.#placed = v; this.#changed(); } }
  get on() { return this.#on; }
  set on(v: boolean) { if (v !== this.#on) { this.#on = v; this.#changed(); } }
  /** Its end is not where it ends (a chat's window short of the newest): not followed, whatever is in view. */
  get short() { return this.#short; }
  set short(v: boolean) { if (v !== this.#short) { this.#short = v; this.#changed(); } }
  /** The message being followed, by key: kept in view from its top. */
  get anchor() { return this.#anchor; }
  set anchor(v: unknown) { if (v !== this.#anchor) { this.#anchor = v; this.#changed(); } }
  /** Something else puts the list in place for now, frame by frame (words sent flying in, ChatHost.tsx): not followed meanwhile. */
  get paused() { return this.#paused; }
  set paused(v: boolean) { if (v !== this.#paused) { this.#paused = v; this.#changed(); } }
  /** How many of its own scrolls are going. */
  get own() { return this.#own; }
  set own(v: number) { if (v !== this.#own) { this.#own = v; this.#changed(); } }

  /** The list at its end, and that the end: once at rest there, it follows. */
  atEnd(): boolean { return !this.short && !this.list.canScrollForward; }

  async #mine<T>(block: () => Promise<T>): Promise<T> {
    this.own++;
    try { return await block(); } finally { this.own--; }
  }

  /** The reader opened something in the list to read it: what it grows by is not new, so not followed. */
  stay() {
    if (!this.placed) return;
    this.on = false;
    this.anchor = null;
  }

  toEnd(): Promise<void> {
    return this.#mine(async () => {
      const info = this.list.layoutInfo;
      const count = info.totalItemsCount;
      if (count === 0) return;
      // Jumping to an item throws away what is on screen and lays it out again; with the last one already in
      // view (most of the time: following), scrolling the rest of the way keeps what is there.
      if ((info.visibleItemsInfo[info.visibleItemsInfo.length - 1]?.index ?? -1) < count - 1) await this.list.scrollToItem(count - 1);
      // Past the last item's top to its end, however tall it has grown.
      await this.list.scrollBy(1_000_000);
    });
  }

  /** Back to the newest, following again: it glides there (web: the pane's `to-bottom`). */
  async jump(): Promise<void> {
    this.anchor = null;
    this.on = true;
    await this.#glide();
  }

  hold(): Promise<void> {
    return this.#mine(async () => {
      // What a newly opened list first shows (images loading, the rest of it coming in) is taken at once.
      if (this.grown) return this.#glide();
      const at = this.#anchorIndex();
      // The list stops at its end by itself, so this is the anchor's top or the end, whichever comes first.
      if (at != null) await this.list.scrollToItem(at, -this.margin);
      else if (this.list.canScrollForward) await this.toEnd();
    });
  }

  #anchorIndex(): number | null {
    if (this.anchor == null) return null;
    const i = this.indexOf(this.anchor);
    return i >= 0 ? i : null;
  }

  /**
   * How far down the goal is (the anchor's top, else the end; whichever comes first), as the list is laid out now;
   * null when the anchor is above what is laid out (taken at once instead). What is not laid out yet is reckoned by
   * the rows that are, and read again each frame as it comes in.
   */
  #left(): number | null {
    const info = this.list.layoutInfo;
    const shown = info.visibleItemsInfo;
    const last = shown[shown.length - 1];
    if (!last) return 0;
    const count = info.totalItemsCount;
    const spacing = info.mainAxisItemSpacing;
    const bottom = last.offset + last.size;
    const average = Math.floor(shown.reduce((a, it) => a + it.size, 0) / shown.length) + spacing;
    const end = bottom - (info.viewportEndOffset - info.afterContentPadding) + (count - 1 - last.index) * average;
    const at = this.#anchorIndex();
    if (at == null) return end;
    const top = shown.find((it) => it.index === at)?.offset ?? (at < shown[0]!.index ? null : bottom + spacing + (at - last.index - 1) * average);
    if (top == null) return null;
    return Math.min(top - this.margin, end);
  }

  /** Glides to the goal (see left), each frame 1 - e^(-dt/100ms) of what is left, slowed as the system slows animations. */
  #glide(): Promise<void> {
    return this.#mine(async () => {
      const scale = Math.max(0.001, this.motionScale);
      // Far below what is laid out (the newest many rows away), it goes most of the way at once: the list would lay
      // out every row it passes in one frame.
      const info = this.list.layoutInfo;
      const lastShown = info.visibleItemsInfo[info.visibleItemsInfo.length - 1]?.index;
      if (lastShown === undefined) return;
      if (this.anchor == null && info.totalItemsCount - 1 - lastShown > 12) await this.list.scrollToItem(info.totalItemsCount - 1 - 6);
      let above = false;
      await this.list.scroll(async (s) => {
        let last = -1;
        for (;;) {
          const left = this.#left();
          if (left == null) { above = true; return; }
          if (this.paused) return;
          // Nearly there, or the goal back up (the content grew shorter): put there at once, as the web does.
          if (left < 1) { if (Math.abs(left) > 0.01) s.scrollBy(left); return; }
          const now = await withFrameMillis();
          const dt = last < 0 ? 16 : Math.min(64, now - last);
          last = now;
          // The list lays out whole pixels (a fraction waits for the next): the tail goes at least one a frame,
          // so it lands exactly instead of waiting on fractions that may never add up.
          let step = left * (1 - Math.exp(-dt / (100 * scale)));
          if (step < 1) step = Math.min(left, 1);
          const used = s.scrollBy(step);
          // The list's end reached before the goal.
          if (Math.abs(used) < 0.5 && Math.abs(step) >= 0.5) return;
        }
      });
      const at = this.#anchorIndex();
      if (above && at != null) await this.list.scrollToItem(at, -this.margin);
    });
  }
}

/** `of`: the list's state, or the page's ref to its FlatList (its state then made here). */
export function rememberFollow(of: LazyListState | RefObject<FlatList<any> | null>): Follow {
  const own = useMemo(() => (of instanceof LazyListState ? null : new LazyListState(of)), [of]);
  const list = own ?? (of as LazyListState);
  const margin = 12;
  const follow = useMemo(() => new Follow(list, margin), [list]);
  follow.motionScale = reducedMotion() ? 0 : 1;
  useEffect(() => {
    let live = true;
    let grownTimer: ReturnType<typeof setTimeout> | null = null;
    let lastScroll: [boolean, boolean] | null = null;
    let lastShort: boolean | null = null;
    let lastHeight = -1;
    let lastContent: string | null = null;
    let holding = false;
    let again = false;

    // The content changed while following: hold the anchor, or the end.
    const hold = async () => {
      if (holding) { again = true; return; }
      holding = true;
      try {
        do {
          again = false;
          if (!follow.placed || !follow.on || follow.short || follow.paused || list.isScrollInProgress) continue;
          // A glide the reader's finger took over ends here; one another scroll (the keyboard's) cut short goes on.
          while (live && follow.on && !follow.short && !follow.touched) {
            try { await follow.hold(); break; } catch (e) {
              if (!(e instanceof CancellationException) || !live) throw e;
              await withFrameMillis();
            }
          }
        } while (again && live);
      } finally { holding = false; }
    };

    const check = () => {
      if (!live) return;
      if (follow.placed && grownTimer == null && !follow.grown) grownTimer = setTimeout(() => { follow.grown = true; }, 500);
      // A scroll it did not make itself, once the list is at rest: at the end it follows again, elsewhere it stops.
      const scroll: [boolean, boolean] = [list.isScrollInProgress, follow.own > 0];
      if (!lastScroll || lastScroll[0] !== scroll[0] || lastScroll[1] !== scroll[1]) {
        lastScroll = scroll;
        const [scrolling, own] = scroll;
        if (scrolling && !own && follow.placed) { follow.touched = true; follow.anchor = null; follow.topHeld = false; }
        if (!scrolling && follow.touched) { follow.touched = false; follow.on = follow.atEnd(); }
      }
      // Short of its end, nothing is followed; back at it (the last page in), at rest at the end it follows again.
      if (lastShort !== follow.short) {
        lastShort = follow.short;
        if (follow.short) { follow.on = false; follow.anchor = null; }
        else if (follow.placed && !follow.on && !list.isScrollInProgress) follow.on = !list.canScrollForward;
      }
      // The list itself grew shorter or taller (the keyboard coming up, or going): what was at its bottom stays at
      // its bottom, as the web keeps the distance from the bottom through a resize.
      const info = list.layoutInfo;
      const h = info.viewportSize.height;
      if (h !== lastHeight) {
        if (lastHeight > 0 && h > 0 && follow.placed && !follow.topHeld) {
          const by = lastHeight - h;
          follow.own++;
          list.scrollBy(by).catch(() => undefined).finally(() => { follow.own--; });
        }
        if (h > 0) lastHeight = h;
      }
      const last = info.visibleItemsInfo[info.visibleItemsInfo.length - 1];
      const content = JSON.stringify([info.totalItemsCount, last?.index ?? null, last?.size ?? null, follow.placed && follow.on, String(follow.anchor), follow.paused]);
      if (content !== lastContent) {
        lastContent = content;
        hold().catch(() => undefined);
      }
    };
    const offList = list.subscribe(check);
    const offFollow = follow.subscribe(check);
    check();
    return () => {
      live = false;
      offList();
      offFollow();
      if (grownTimer) clearTimeout(grownTimer);
    };
  }, [follow, list]);
  return follow;
}

/** Whether the reader is away from the end, by more than a corner of the screen. */
export function awayFromEnd(list: LazyListState): boolean {
  const corner = 120;
  return useSyncExternalStore(list.subscribe, () => {
    const info = list.layoutInfo;
    const last = info.visibleItemsInfo[info.visibleItemsInfo.length - 1];
    if (!last) return false;
    return last.index < info.totalItemsCount - 1 || last.offset + last.size - info.viewportEndOffset > corner;
  });
}

/** Whether the list's end is in view, all of its last item: the reader has seen the newest. */
export function endInView(list: LazyListState): boolean {
  return useSyncExternalStore(list.subscribe, () => {
    const info = list.layoutInfo;
    const last = info.visibleItemsInfo[info.visibleItemsInfo.length - 1];
    return last != null && last.index === info.totalItemsCount - 1 && last.offset + last.size <= info.viewportEndOffset + 2;
  });
}
