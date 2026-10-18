// A new chat and a chat are one page (web mobile/ChatHost.tsx): what is above changes (a new chat's scene, then the chat
// it made), the composer at its foot is one, kept, with what is typed and the focus, as a new chat becomes its chat. What
// the composer writes to is the page's: it says so (`Host.spec`), and the composer asks it when a message goes.
//
// What is sent is drawn where it arrives and moved from where it comes from (web madeChat.ts), the same in a new chat and
// in a chat: its words stay where they were typed until its row is in the list, then that row (the real one, whatever it
// becomes: outbox, then the chat's message) is drawn over the composer from the words' place and size to its own, its
// bubble and time coming in around it; the composer's hint comes back once the words have left the composer. Its words
// go piece by piece (cut where the field's lines break and where the bubble's do): each from where it was typed to its
// place in the bubble, so a message of many lines leaves the field as it was, its lines neither spreading nor rewrapping
// at once. Both now share the field's typography and wrapping width. A new
// chat's scene leaves first (up out of view, its choices fading where they are), and the chat's list comes up after the
// words, out of the composer's top edge. Nothing is crossfaded over anything. The files sent with them go the same way,
// each from its tile in the composer to its place in the message (a picture's crop opening out to its own proportions);
// files sent with no words fly on their own, their row coming in where it is.
//
// Here the row and the files are drawn over the composer by drawing them again there (the same elements, in the
// overlay), the one in the list hidden meanwhile: React Native records no drawing to play elsewhere, as Compose's
// GraphicsLayer does.
import { createContext, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Pressable, StyleSheet, Text, View, type StyleProp, type TextLayoutEventData, type ViewStyle } from "react-native";
import Animated, { Easing as REasing, makeMutable, useAnimatedStyle, useSharedValue, withTiming, type SharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { screenId, type Screen, type ScreenOf } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { LocalWide } from "../ui/ChatInk";
import { Backdrop, ComposerCorner, ComposerFilesIn, ComposerInset, Floating, LocalFrostSource, useFrostName } from "../ui/Glass";
import { keyboard } from "../ui/Keyboard";
import { Ease } from "../ui/Motion";
import { reducedMotion } from "../ui/Parts";
import { textLayoutOf, type TextLayoutResult } from "../ui/Pick";
import { concentric, Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import type { LazyListState } from "../ui/Follow";
import { ChatScreen } from "./Chat";
import { Animatable, eased, useAnimatable } from "./ChatMotion";
import { ChatRefMenu, ComposerBar, DraftExtras, MorphContent, rememberMorph, type Draft, type FieldBox, type Morph, type Pending } from "./Composer";
import { NewChatScreen } from "./NewChat";
import { LocalSendTextWidth, SendTextStyle } from "./SendText";
import { BesideRecent, floatingStill, NewChatColumn } from "./Wide";


// ── where things are ──

/** A box: where it is and how big (dp). */
export interface Box { x: number; y: number; width: number; height: number }

/** Where `view` is in `base` (both drawn), as laid out now: measured at once (the new architecture measures in step). */
export function boxIn(view: View | null | undefined, base: View | null | undefined): Box | null {
  if (!view || !base) return null;
  let out: Box | null = null;
  try { view.measureLayout(base, (x, y, width, height) => { out = { x, y, width, height }; }, () => undefined); } catch { /* not drawn */ }
  return out;
}

/**
 * Something drawn, as Compose's LayoutCoordinates names it: its view (null once it is gone: not attached), and the list
 * row it is in, if any (its place is then read through the list's scroll as the list has it, not as it last told).
 */
export interface LayoutCoordinates { view: View | null; row?: string | null }

/** The page's places: the host's overlay (what flies is drawn in it), the list's pane, and the list in it. */
export class Where {
  overlay: View | null = null;
  pane: View | null = null;
  list: LazyListState | null = null;
  /** The list's room before its rows across (its start padding). */
  start = 0;
  /** Each row of the list's view, by its key (what is in it is measured from it). */
  readonly rows = new Map<string, View>();

  /** Where the row `key` is in the pane, as the list has it now (null while it is not laid out in view). */
  rowAt(key: string): Box | null {
    const list = this.list;
    if (!list) return null;
    const info = list.layoutInfo;
    const it = info.visibleItemsInfo.find((i) => i.key === key);
    return it ? { x: this.start, y: it.offset + info.beforeContentPadding, width: info.viewportSize.width - 2 * this.start, height: it.size } : null;
  }

  /** Where `c` is in the pane. */
  inPane(c: LayoutCoordinates): Box | null {
    if (!c.view) return null;
    if (c.row != null && this.list) {
      const row = this.rowAt(c.row);
      const inner = boxIn(c.view, this.rows.get(c.row));
      if (row && inner) return { x: row.x + inner.x, y: row.y + inner.y, width: inner.width, height: inner.height };
    }
    return boxIn(c.view, this.pane);
  }

  /** Where `c` is in the overlay. */
  inOverlay(c: LayoutCoordinates | View | null | undefined): Box | null {
    if (!c) return null;
    const coords: LayoutCoordinates = "measureLayout" in c ? { view: c as View } : (c as LayoutCoordinates);
    if (coords.row != null && this.list) {
      const pane = boxIn(this.pane, this.overlay);
      const b = this.inPane(coords);
      if (pane && b) return { x: pane.x + b.x, y: pane.y + b.y, width: b.width, height: b.height };
    }
    return boxIn(coords.view, this.overlay);
  }
}

/** What the composer writes to, as the page above it says: where (its station, and the chat not offered to `@`), the draft, and what its buttons do. */
export interface ComposerSpec {
  station: string; here: string | null; draft: Draft; placeholder: string;
  notices?: () => ReactNode;
  onPlus: () => void; onType?: () => void; onSend: () => void;
}
/** A ComposerSpec as Kotlin's constructor makes one (named arguments: the object). */
export function ComposerSpec(spec: ComposerSpec): ComposerSpec { return spec; }

type Listener = () => void;

/** A piece of the words: `clip`, its room in the bubble's words; `at`, where it starts there (its baseline); `from`, the same in the field's. */
export class Piece {
  constructor(readonly clip: { left: number; top: number; right: number; bottom: number }, readonly at: { x: number; y: number }, readonly from: { x: number; y: number }, readonly shown: boolean) {}
}

/**
 * A file sent with the words (`path`, the station's): `from`, its tile in the composer (in the host), drawn as `tile`
 * until its place in the message is laid out (`to`, drawn there as `content` instead of in the row).
 */
export class FlyingFile {
  to: LayoutCoordinates | null = null;
  content: ReactNode = null;
  constructor(readonly path: string, readonly from: { left: number; top: number; width: number; height: number }, readonly tile: ReactNode) {}
}

/** A file's tile in the composer: where it is and what it shows (`taken` by a flight, which keeps drawing it). */
export class Tile {
  view: View | null = null;
  taken = false;
  constructor(public content: ReactNode) {}
}

/**
 * A message's words on their way from the composer to their row: `from`, where their first line's letters start (in the
 * host), at `fromSize`; `field`, the field's own corner and width (where they wait, drawn as typed, until the row is in
 * the list); `top`, the composer's top edge. `carried`: the list comes up with them (a new chat's first message).
 */
export class Flight {
  /** How far the field had scrolled its words: to their end (the caret's, as it sends), when they are taller than it. */
  readonly scroll: number;
  #placed = false;
  #ready = false;
  #key: string | null = null;
  beforePositions = new Map<string, number>();
  row: LayoutCoordinates | null = null;
  bubble: LayoutCoordinates | null = null;
  /** Where the bubble's letters start in it, and their size; `pad`, where its words are in it. */
  inBubble = { x: 0, y: 0 };
  pad = { x: 0, y: 0 };
  #words: TextLayoutResult | null = null;
  #cut: Piece[] | null = null;
  /** How wide the bubble's words are laid out (their box), for drawing them again piece by piece. */
  wordsWidth = 0;
  toSize = 1;
  /** How far above its place the list starts (a new chat's: the words' way up), once the row is laid out. */
  rise: number | null = null;
  readonly progress = new Animatable(0);
  /** The bubble's ground, as its row draws it, and its words' ink. */
  groundColor: string | null = null;
  wordsColor: string | null = null;
  /** The row the words went into, as it is drawn (drawn again over the composer while they fly). */
  rowElement: ReactNode = null;

  constructor(
    readonly text: string, readonly from: { x: number; y: number }, readonly fromSize: number, readonly field: { x: number; y: number },
    readonly fieldWidth: number, readonly fieldHeight: number, readonly top: number,
    readonly carried: boolean, readonly before: Set<string>,
    /** The field's words as laid out when sent (`text` starting at `lead` in them: what is sent is trimmed). */
    readonly typed: TextLayoutResult | null = null, readonly lead: number = 0,
    /** The files sent with them, from their tiles in the composer. */
    readonly files: FlyingFile[] = [],
    private readonly changed: () => void = () => undefined,
  ) {
    this.scroll = Math.max(0, (typed?.size.height ?? 0) - fieldHeight);
  }

  /** Its row is laid out in the list (not only composed ahead, out of sight): they go from then on. */
  get placed() { return this.#placed; }
  set placed(on: boolean) { if (on !== this.#placed) { this.#placed = on; this.changed(); } }
  /** The real list has completed its final layout; only transforms animate after this. */
  get ready() { return this.#ready; }
  set ready(on: boolean) { if (on !== this.#ready) { this.#ready = on; this.changed(); } }
  /** The row the words went into (its key in the list), once it is there. */
  get key() { return this.#key; }
  set key(k: string | null) { if (k !== this.#key) { this.#key = k; this.changed(); } }
  /** The bubble's words as laid out (its row's, as it is now). */
  get words() { return this.#words; }
  set words(w: TextLayoutResult | null) { if (w !== this.#words) { this.#words = w; this.#cut = null; } }

  /**
   * How far it has come (eased): across, and up. In an open chat across first and up a little after, so the words
   * rise on a curve (web madeChat.ts flight()); a new chat's first words both at once.
   */
  e(): number { return this.carried ? eased(Ease.Arrive)(this.progress.value) : this.settle(); }
  across(): number { return this.carried ? this.e() : eased(Ease.Flight)(Math.min(1, this.#fly() / 0.88)); }
  up(): number { return this.carried ? this.e() : eased(Ease.Flight)(Math.max(0, (this.#fly() - 0.12) / 0.88)); }
  /**
   * In an open chat the words start as typed, then unfold into their bubble during the flight.
   * Its ground and time come in with the unfolding, without a pause at the destination.
   */
  #fly(): number { return Math.min(1, this.progress.value / FLY); }
  settle(): number { return this.carried ? this.e() : eased(Ease.Arrive)(Math.min(1, Math.max(0, (this.progress.value - SETTLE) / (1 - SETTLE)))); }
  /** How much of the bubble's ground shows (around the words, drawn by the host in an open chat): coming in from half way, all there as they come. */
  ground(): number { return this.carried ? this.e() : Math.min(1, Math.max(0, (this.progress.value - SETTLE) / (FLY - SETTLE))); }
  /** Where the list is drawn now, off its place. */
  shift(): number { return this.carried ? (this.rise ?? 0) * (1 - this.e()) : 0; }

  /**
   * The words cut into the pieces that fly on their own: runs that are on one line both in the field and in the
   * bubble. Null when the two are not the same words (a reference to a chat is a chip in the bubble): the row then
   * flies whole.
   */
  pieces(): Piece[] | null {
    if (this.#cut) return this.#cut;
    const w = this.#words;
    const t = this.typed;
    if (!w || !t) return null;
    const s = w.text;
    const was = t.text;
    const lead = this.lead;
    if (s.length === 0 || lead < 0 || lead + s.length > was.length || was.substring(lead, lead + s.length) !== s) return null;
    const cuts = new Set<number>([0, s.length]);
    for (let i = 0; i < w.lineCount; i++) cuts.add(w.getLineStart(i));
    for (let i = 0; i < t.lineCount; i++) { const c = t.getLineStart(i) - lead; if (c >= 0 && c <= s.length) cuts.add(c); }
    const ends = [...cuts].sort((a, b) => a - b);
    const out: Piece[] = [];
    for (let i = 0; i + 1 < ends.length; i++) {
      const a = ends[i]!;
      const b = ends[i + 1]!;
      if (s.substring(a, b).trim().length === 0) continue;
      const lb = w.getLineForOffset(a);
      const lf = t.getLineForOffset(a + lead);
      const x = w.getHorizontalPosition(a, true);
      const left = a === w.getLineStart(lb) ? 0 : x;
      const right = b >= w.getLineEnd(lb) ? w.size.width : w.getHorizontalPosition(b, true);
      const middle = (t.getLineTop(lf) + t.getLineBottom(lf)) / 2 - this.scroll;
      out.push(new Piece(
        { left, top: w.getLineTop(lb), right, bottom: w.getLineBottom(lb) }, { x, y: w.getLineBaseline(lb) },
        { x: t.getHorizontalPosition(a + lead, true), y: t.getLineBaseline(lf) - this.scroll },
        // Scrolled out of the field: not to be seen there, it comes in on its way.
        middle >= 0 && middle <= this.fieldHeight,
      ));
    }
    // What was scrolled out of the field comes with the first piece that showed, laid out as in the bubble (one
    // block with it, not each from its own place out of sight).
    const first = out.find((p) => p.shown);
    const k = t.fontSize / w.fontSize;
    if (first) for (let i = 0; i < out.length; i++) {
      const p = out[i]!;
      if (!p.shown) out[i] = new Piece(p.clip, p.at, { x: first.from.x + (p.at.x - first.at.x) * k, y: first.from.y + (p.at.y - first.at.y) * k }, false);
    }
    this.#cut = out;
    return out;
  }

  /** The bubble of a row flown into: where its letters start (`pad`: its padding; `line`, `size`: its line height and letters' size). */
  bubbleAt(coords: LayoutCoordinates, host: Host, pad: { x: number; y: number }, line: number, size: number) {
    this.bubble = coords;
    this.pad = pad;
    this.inBubble = { x: pad.x, y: pad.y + (line - size) / 2 };
    this.toSize = size;
    if (this.rise == null) {
      const b = host.where.inOverlay(coords);
      if (b) this.rise = this.from.y - (b.y + this.inBubble.y);
    }
  }
}

/** The page's composer and what moves around it. */
export class Host {
  readonly #listeners = new Set<Listener>();
  #version = 0;
  #queued = false;
  subscribe = (l: Listener) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  /** Told after what is being drawn now (what changes as a page draws, e.g. the row words go into, is drawn next). */
  #changed = () => {
    this.#version++;
    if (this.#queued) return;
    this.#queued = true;
    queueMicrotask(() => { this.#queued = false; for (const l of this.#listeners) l(); });
  };

  /** What a sheet over the page frosts (app.haze): kept as Kotlin's Host has it. */
  readonly haze: object = {};
  /** Where the overlay, the list's pane and the list are. */
  readonly where = new Where();

  #spec: ComposerSpec | null = null;
  get spec() { return this.#spec; }
  set spec(s: ComposerSpec | null) { if (s !== this.#spec) { this.#spec = s; this.#changed(); } }
  #composerHeight = 0;
  /** The composer's room at the foot, with its margins (what the page above keeps clear of). */
  get composerHeight() { return this.#composerHeight; }
  set composerHeight(h: number) { if (h !== this.#composerHeight) { this.#composerHeight = h; this.#changed(); } }
  #naturalHeight = 0;
  /** Measured from the composer's final content, independent of its visual height animation. */
  get naturalHeight() { return this.#naturalHeight; }
  set naturalHeight(h: number) { if (h !== this.#naturalHeight) { this.#naturalHeight = h; this.#changed(); } }
  roomForList(): number {
    const shown = this.flight?.carried === false && this.naturalHeight > 0 ? this.naturalHeight : this.composerHeight;
    // One text line, its padding, toolbar and margins: focusing uses space already kept by the list.
    const reserved = Math.max(36, SendTextStyle.lineHeight + 14) + (ComposerInset * 2 + 18 + 4 + 36);
    return Math.max(shown, reserved);
  }
  readonly rowPositions = new Map<string, number>();
  prepareFlight: ((f: Flight) => Promise<void>) | null = null;
  /** The field: its box in the capsule, as the composer last said where it is. */
  field: { x: number; y: number; width: number; height: number } | null = null;
  fieldText: TextLayoutResult | null = null;
  #fieldWidth = 0;
  get fieldWidth() { return this.#fieldWidth; }
  set fieldWidth(w: number) { if (w !== this.#fieldWidth) { this.#fieldWidth = w; this.#changed(); } }
  capsule: View | null = null;
  get overlay(): View | null { return this.where.overlay; }
  /** The composer's file tiles, by the draft's id for each. */
  readonly tiles = new Map<number, Tile>();
  /** A message (seq) to show once the chat's list is in place (Screen.Chat.at), or now that it is (the bell that leads to
   * what waits to be decided: Chat.tsx JumpToAsk), the pages before it brought in. */
  #goTo: number | null = null;
  get goTo() { return this.#goTo; }
  set goTo(seq: number | null) { if (seq !== this.#goTo) { this.#goTo = seq; this.#changed(); } }
  /** The words to mark in that message (opened from a search, Search.tsx), instead of flashing it. */
  goToWords: string[] = [];
  #flight: Flight | null = null;
  get flight() { return this.#flight; }
  #hintAway = false;
  /** The composer's hint is away (words just sent are over it). */
  get hintAway() { return this.#hintAway; }
  set hintAway(on: boolean) { if (on !== this.#hintAway) { this.#hintAway = on; this.#changed(); } }
  #leaving = false;
  /** A new chat's scene leaving, as it becomes its chat. */
  get leaving() { return this.#leaving; }
  set leaving(on: boolean) { if (on !== this.#leaving) { this.#leaving = on; this.#changed(); } }
  /** How far the scene has left (ms of SCENE_LEAVE_MS), for its worklets. */
  readonly leave: SharedValue<number> = makeMutable(0);
  still = false;
  #sends = 0;
  /** How many messages the composer has sent: the list goes to its end with each (Chat.tsx). */
  get sends() { return this.#sends; }
  /** How far up the words are (Flight.up), for the rows that make room for them (sendReflow), each frame. */
  readonly up: SharedValue<number> = makeMutable(1);
  /** Where the list is drawn off its place (Flight.shift), each frame. */
  readonly shift: SharedValue<number> = makeMutable(0);
  /** The rows that make room as words fly in (sendReflow): each one's shift. */
  readonly reflows = new Map<string, SharedValue<number>>();

  /**
   * `text` is sent from the composer (before the draft is emptied): its words stay where they are until their row is in
   * the list, the first outgoing one not among `before` (the outbox's as it was sent: it is this device's own, so what
   * comes into it is what was just sent from here). `files`, the draft's as it is sent: those up go from their tiles.
   */
  sending(text: string, carried: boolean, files: Pending[] = [], before: Set<string> = this.rows) {
    this.#sends++;
    this.#flight = null;
    this.#hold = null;
    this.#changed();
    const overlay = this.where.overlay;
    const capsule = this.capsule;
    const fieldIn = this.field;
    if (this.still || fieldIn == null || overlay == null || capsule == null) return;
    const cap = boxIn(capsule, overlay);
    if (!cap) return;
    const taken: [Tile, FlyingFile][] = [];
    for (const p of files) {
      const path = p.done?.path;
      if (path == null) continue;
      const tile = this.tiles.get(p.id);
      const at = tile ? boxIn(tile.view, overlay) : null;
      if (!tile || !at) continue;
      taken.push([tile, new FlyingFile(path, { left: at.x, top: at.y, width: at.width, height: at.height }, tile.content)]);
    }
    if (text.length === 0 && taken.length === 0) return;
    for (const [tile] of taken) tile.taken = true;
    const at = { x: cap.x + fieldIn.x, y: cap.y + fieldIn.y };
    // The field and bubble share the same line metrics.
    const from = { x: at.x, y: at.y + (SendTextStyle.lineHeight - SendTextStyle.fontSize) / 2 };
    const typed = this.fieldText;
    if (!carried) this.#hold = this.contentHeight;
    const f = new Flight(
      text, from, SendTextStyle.fontSize, at, fieldIn.width, fieldIn.height, cap.y,
      carried, before, typed, typed ? typed.text.indexOf(text) : -1, taken.map(([, ff]) => ff), this.#changed,
    );
    f.beforePositions = this.#positions();
    this.#flight = f;
    // Only words pass over the hint; files alone leave it where it is.
    this.#hintAway = text.length > 0;
    this.#changed();
  }

  /** Where each row is drawn now (its place and the room it is making), in the overlay. */
  #positions(): Map<string, number> {
    const out = new Map<string, number>();
    for (const [id, shift] of this.reflows) {
      const y = this.rowY(id);
      if (y != null) out.set(id, y + shift.value);
    }
    return out;
  }

  /** How far down the overlay the row `id` of the list is laid out. */
  rowY(id: string): number | null {
    const pane = boxIn(this.where.pane, this.where.overlay);
    const b = this.where.rowAt(id);
    return pane && b ? pane.y + b.y : null;
  }

  /** What was sent did not go (or its row never came): the composer is as it was. */
  notSent() {
    if (this.#flight?.placed !== true) { this.#flight = null; this.#hintAway = false; this.#hold = null; this.#changed(); }
  }

  /** A new chat becomes its chat: its scene leaves. */
  madeChat() { this.leaving = true; }

  #hold: number | null = null;
  /**
   * The composer's content kept as tall as when the words were sent, until they are half way (it comes down then, not
   * from under them as they set out); `contentHeight`, how tall it is as laid out (held or not).
   */
  get hold() { return this.#hold; }
  set hold(h: number | null) { if (h !== this.#hold) { this.#hold = h; this.#changed(); } }
  contentHeight = 0;
  morph: Morph | null = null;

  /** The rows the list shows now (by key): what was there before a message is sent is not where it goes. */
  rows: Set<string> = new Set();

  /**
   * Whether the row `id` is where the words sent go: the first row of this device's own that was not in the list when
   * they were sent (`mine`: an outbox entry, or a message of the viewer's; the outbox may be let go before the list
   * has shown it, when the station is quick).
   */
  takes(id: string, mine: boolean): boolean {
    const f = this.#flight;
    if (!f) return false;
    if (f.key == null && mine && !f.before.has(id)) f.key = id;
    return f.key === id;
  }

  /** How far down the host `c` is. */
  overlayY(c: LayoutCoordinates | View | null | undefined): number | null {
    return this.where.inOverlay(c)?.y ?? null;
  }

  landed(f: Flight) { if (this.#flight === f) { this.#flight = null; this.#hintAway = false; this.#hold = null; this.#changed(); } }
}

/** What a part reads of the host, drawn again when it changes (`select` gives something compared as it is). */
export function useHost<T>(host: Host | null | undefined, select: (h: Host) => T): T | undefined {
  return useSyncExternalStore((l) => (host ? host.subscribe(l) : () => undefined), () => (host ? select(host) : undefined));
}

/** The flight a row's content is drawn for (its bubble says where its letters are; its ground and time come in with it). */
export const LocalFlight = createContext<Flight | null>(null);
export const LocalFlightHost = createContext<Host | null>(null);
/** Drawn again over the composer (the row flown into, as it flies): it says nothing of where it is. */
export const LocalFlightCopy = createContext(false);
/** The list row what is inside is in (Chat.tsx: its key), for where it is measured from. */
export const LocalRow = createContext<string | null>(null);

/** A row the words fly into: drawn by the host over the composer, from where they were to here, instead of in the list. */
export function Flying({ host, f, row, children }: { host: Host; f: Flight | null; row: string; children?: ReactNode }) {
  const view = useRef<View | null>(null);
  useHost(host, (h) => h.flight);
  if (f) f.rowElement = children;
  // Landed: here again, in the frame the host stops drawing it.
  const away = f != null && host.flight === f;
  return (
    <View
      ref={view}
      collapsable={false}
      style={{ opacity: away ? 0 : 1 }}
      onLayout={() => { if (f) { f.row = { view: view.current, row }; f.placed = true; } }}
    >
      {children}
    </View>
  );
}

/** A file's tile in the composer, kept drawn (and where) for the flight that may take it from there. */
export function SendTile({ host, id, style, children }: { host: Host | null | undefined; id: number; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const tile = useMemo(() => new Tile(children), [id]); // eslint-disable-line react-hooks/exhaustive-deps
  tile.content = children;
  useEffect(() => {
    if (!host) return;
    host.tiles.set(id, tile);
    return () => { if (host.tiles.get(id) === tile) host.tiles.delete(id); };
  }, [host, id, tile]);
  return <View ref={(v) => { tile.view = v; }} collapsable={false} style={style}>{children}</View>;
}
/** Modifier.sendTile as Kotlin names it: the tile itself (SendTile). */
export const sendTile = SendTile;

/** A file in a message flown into: drawn by the host from its tile in the composer to here, instead of here. */
export function LandingFile({ path, style, children }: { path: string; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const f = useContext(LocalFlight);
  const host = useContext(LocalFlightHost);
  const copy = useContext(LocalFlightCopy);
  const row = useContext(LocalRow);
  const view = useRef<View | null>(null);
  useHost(host, (h) => h.flight);
  const file = f?.files.find((it) => it.path === path) ?? null;
  // Only while flown into: the chat's other files are drawn where they are.
  if (!f || !host || !file || copy) return <View style={style}>{children}</View>;
  file.content = children;
  return (
    <View
      ref={view}
      collapsable={false}
      style={[style, { opacity: host.flight === f ? 0 : 1 }]}
      onLayout={() => {
        file.to = { view: view.current, row };
        // Sent with no words: the list rises (a new chat's) from where the first file was.
        if (f.text.length === 0 && f.rise == null) {
          const b = host.where.inOverlay(file.to);
          if (b) f.rise = file.from.top - b.y;
        }
      }}
    >
      {children}
    </View>
  );
}
export const landingFile = LandingFile;

/** Existing rows also use FLIP: laid out once at their destination, that displacement undone in drawing. */
export function SendReflow({ host, id, children }: { host: Host; id: string; children?: ReactNode }) {
  const shift = useSharedValue(0);
  useEffect(() => {
    host.reflows.set(id, shift);
    return () => { if (host.reflows.get(id) === shift) host.reflows.delete(id); };
  }, [host, id, shift]);
  // A draw transform cannot feed back into the layout it is reckoned from.
  const moved = useAnimatedStyle(() => ({ transform: [{ translateY: shift.value }] }));
  return <Animated.View style={moved}>{children}</Animated.View>;
}
export const sendReflow = SendReflow;

/** The page: a new chat, or a chat (the one it became), above; the composer at its foot; what flies, over both. */
export function ChatHost({ current, screen }: { current: WorkspaceEntry; screen: Screen }) {
  const host = useMemo(() => new Host(), []);
  host.still = reducedMotion();
  const wide = useContext(LocalWide);
  const chat = screen.kind === "Chat" ? (screen as ScreenOf<"Chat">) : null;
  // Where to go, once each time the chat or its place changes (not on every drawing: the page clears it once there).
  const goKey = chat ? `${screenId(chat)}|${chat.at ?? ""}|${(chat.words ?? []).join("\u0000")}` : "";
  const went = useRef<string | null>(null);
  if (went.current !== goKey) {
    went.current = goKey;
    host.goToWords = chat?.words ?? [];
    host.goTo = chat?.at ?? null;
  }
  const leaving = useHost(host, (h) => h.leaving) ?? false;
  const fieldWidth = useHost(host, (h) => h.fieldWidth) ?? 0;
  useEffect(() => {
    if (!leaving) return;
    host.leave.value = 0;
    host.leave.value = withTiming(SCENE_LEAVE_MS, { duration: SCENE_LEAVE_MS, easing: REasing.linear });
    const done = setTimeout(() => { host.leaving = false; }, SCENE_LEAVE_MS);
    return () => clearTimeout(done);
  }, [leaving, host]);
  // Over the keyboard, and the system's bar at the foot.
  const kb = keyboard();
  const insets = useSafeAreaInsets();
  const foot = useAnimatedStyle(() => ({ paddingBottom: Math.max(kb.value, insets.bottom) }));
  // A new chat keeps a column in the middle of a wide screen (Wide.tsx), its composer too; a chat is the screen's width.
  const column = wide && chat == null ? NewChatColumn : null;
  const frosted = useFrostName("host");
  return (
    <LocalSendTextWidth.Provider value={fieldWidth}>
      <Animated.View style={[{ flex: 1 }, foot]}>
        <View style={{ flex: 1 }}>
          {/* What the composer frosts (Chat.kt's host.haze): the chat and the new chat's scene. */}
          <Backdrop name={frosted} style={StyleSheet.absoluteFill}>
            <View style={StyleSheet.absoluteFill}>
              {chat && <ChatScreen key={screenId(chat)} station={chat.station} of={chat.of} host={host} />}
              {/* A new chat's scene stays over its chat while it leaves. */}
              {(chat == null || leaving) && (
                <View key="new" style={[{ position: "absolute", top: 0, bottom: 0, alignSelf: "center", width: "100%" }, wide ? NewChatColumn : null]}>
                  <NewChatScreen current={current} host={host} leaving={chat != null} />
                </View>
              )}
            </View>
          </Backdrop>
          <LocalFrostSource.Provider value={frosted}>
            <View pointerEvents="box-none" style={[{ position: "absolute", left: 0, right: 0, bottom: 0 }, column]}>
              <HostComposer host={host} besideRecent={wide && chat != null} />
            </View>
          </LocalFrostSource.Provider>
          <FlightLayer host={host} />
        </View>
      </Animated.View>
    </LocalSendTextWidth.Provider>
  );
}

/** How long a new chat's scene takes to leave (web madeChat.css.ts: up 140 ms; its choices fade in 80). */
export const SCENE_LEAVE_MS = 140;

export function HostComposer({ host, style, overContent = true, besideRecent }: { host: Host; style?: StyleProp<ViewStyle>; overContent?: boolean; besideRecent?: boolean }) {
  const C = useC();
  const wide = useContext(LocalWide);
  const spec = useHost(host, (h) => h.spec);
  const hintAway = useHost(host, (h) => h.hintAway) ?? false;
  const held = useHost(host, (h) => h.hold) ?? null;
  const morph = rememberMorph();
  host.morph = morph;
  const capsule = useRef<View | null>(null);
  // Back once the words are out of the composer, eased (going is at once).
  const hint = useSharedValue(1);
  useEffect(() => {
    if (hintAway) hint.value = 0;
    else hint.value = withTiming(1, { duration: 200, easing: Ease.Arrive });
  }, [hintAway, hint]);
  if (!spec) return null;
  const draft = spec.draft;
  const composerChrome = ComposerInset * 2 + 18;
  const beside = besideRecent ?? wide;
  const frame: ViewStyle = { padding: ComposerInset };
  const inner = (
    // Held taller than what it holds (words just sent leaving it): that at its foot, as it was.
    <MorphContent m={morph}>
      <View style={{ minHeight: held ?? 0, justifyContent: "flex-end" }}>
        <View
          style={{ gap: 8 }}
          onLayout={(e) => {
            const { width, height } = e.nativeEvent.layout;
            // Own bubbles always wrap at the expanded field width, so focusing cannot reflow the history.
            host.fieldWidth = Math.max(0, width - 28);
            host.contentHeight = height;
            host.naturalHeight = height + composerChrome;
          }}
        >
          {spec.notices?.()}
          <DraftExtras draft={draft} host={host} />
          <ComposerBar
            draft={draft} placeholder={spec.placeholder} onPlus={spec.onPlus} onType={spec.onType ?? (() => undefined)} onSend={spec.onSend}
            hint={hint} morph={morph} station={spec.station}
            onField={(at: FieldBox) => {
              // Where the field is in the capsule: the capsule is measured as it moves (the keyboard), the field in it is not.
              const cap = capsule.current;
              if (!cap) return;
              cap.measureInWindow((x, y) => { host.field = { x: at.x - x, y: at.y - y, width: at.width, height: at.height }; });
            }}
            onFieldText={(l: TextLayoutEventData) => { host.fieldText = textLayoutOf(l.lines.map((it) => it.text).join(""), l.lines, SendTextStyle.fontSize); }}
          />
          {draft.error != null && <T size={12} color={C.red} style={{ paddingHorizontal: 6 }}>{draft.error}</T>}
        </View>
      </View>
    </MorphContent>
  );
  return (
    <View style={[{ width: "100%" }, style]} pointerEvents="box-none">
      <ChatRefMenu draft={draft} station={spec.station} here={spec.here} haze={host.haze} style={{ paddingHorizontal: 10 }} />
      {/* A capsule floating over the page, which runs on around it. On a wide screen beside the latest chats' button
          (Wide.tsx), which is level with it. */}
      <View
        onLayout={(e) => { host.composerHeight = e.nativeEvent.layout.height; }}
        style={{ width: "100%", paddingLeft: beside ? BesideRecent : 10, paddingRight: 10, paddingTop: 8, paddingBottom: 10 }}
      >
        <View ref={(v) => { capsule.current = v; host.capsule = v; }} collapsable={false}>
          {/* A tap on the capsule's own room is a tap on the field. */}
          <Pressable onPress={() => { draft.focus++; }} android_disableSound>
            {overContent ? (
              <Floating radius={ComposerCorner} style={frame}>{inner}</Floating>
            ) : (
              <Smooth radius={ComposerCorner} style={[floatingStill(C), frame]}>{inner}</Smooth>
            )}
          </Pressable>
        </View>
      </View>
    </View>
  );
}

/** Drawn again each frame while `on`. */
function useEachFrame(on: boolean) {
  const [, tick] = useState(0);
  useEffect(() => {
    if (!on) return;
    let frame = requestAnimationFrame(function next() { tick((n) => n + 1); frame = requestAnimationFrame(next); });
    return () => cancelAnimationFrame(frame);
  }, [on]);
}

/** Over the composer: the words sent, where they wait, then their row on its way to its place. */
function FlightLayer({ host }: { host: Host }) {
  const C = useC();
  const f = useHost(host, (h) => h.flight) ?? null;
  useHost(host, (h) => h.flight?.placed);
  useHost(host, (h) => h.flight?.ready);
  const bound = useHost(host, (h) => h.flight?.key) ?? null;
  useAnimatable(f?.progress);
  useEachFrame(f != null);
  const overlay = useRef<View | null>(null);

  // What is told after the frame is drawn: the rows' room, the list's place, the hint.
  const after = useRef<() => void>(() => undefined);
  useLayoutEffect(() => { after.current(); });

  useEffect(() => {
    if (!f) return;
    // The row never came into sight: the composer is as it was. Not a wait for the station: a flight only starts for a
    // row the core makes here at once (Composer.tsx's onSend), and a refused send gives the words back by itself.
    const t = setTimeout(() => { if (!f.placed) host.notSent(); }, 2000);
    return () => clearTimeout(t);
  }, [f, host]);

  useEffect(() => {
    if (!f || bound == null) return;
    let gone = false;
    void (async () => {
      // Not while its row is only composed ahead, out of sight: once the list shows it.
      while (!f.placed) {
        await new Promise<void>((r) => { const off = host.subscribe(() => { off(); r(); }); });
        if (gone) return;
      }
      if (!f.carried) { await host.prepareFlight?.(f); if (gone) return; f.ready = true; }
      // A new chat's: once its choices have faded (web: 90 ms after what leaves has begun to).
      // The composer comes down once they are half way.
      if (!f.carried) {
        const off = f.progress.subscribe(() => { if (f.progress.value >= SETTLE) { off(); if (host.flight === f) host.hold = null; } });
      }
      await f.progress.animateTo(1, f.carried ? ARRIVE_MS : FLIGHT_MS, (x) => x, f.carried ? 90 : 0);
      if (!gone) host.landed(f);
    })();
    return () => { gone = true; };
  }, [f, bound, host]);

  const where = host.where;
  const drawn: ReactNode[] = [];
  const tell: (() => void)[] = [];
  // The rows making room for them, and the list's place (a new chat's comes up after the words).
  tell.push(() => {
    host.up.value = f && !f.carried ? f.up() : 1;
    host.shift.value = f ? f.shift() : 0;
    for (const [id, sv] of host.reflows) {
      const from = f?.beforePositions.get(id);
      const to = host.rowY(id);
      const shift = f && !f.carried && from != null && to != null ? (from - to) * (1 - f.up()) : 0;
      if (sv.value !== shift) sv.value = shift;
      if (to != null) host.rowPositions.set(id, to + shift);
    }
  });

  if (f) (() => {
    const row = f.row?.view ? f.row : null;
    const bubble = f.bubble?.view ? f.bubble : null;
    const wordless = f.text.length === 0;
    const rowBox = row ? where.inOverlay(row) : null;
    const bubbleBox = bubble ? where.inOverlay(bubble) : null;
    if ((!f.carried && !f.ready) || !rowBox || (!bubbleBox && !wordless) || !where.overlay) {
      // Until their row is drawn in the list, the words stay as they were typed, as the field showed them
      // (scrolled to its last lines when there were more than it holds), and the files as their tiles were; they
      // go in the frame it is.
      for (const ff of f.files) drawn.push(<At key={`t${ff.path}`} x={ff.from.left} y={ff.from.top} w={ff.from.width} h={ff.from.height}>{ff.tile}</At>);
      if (wordless) return;
      drawn.push(
        <View key="typed" style={{ position: "absolute", left: f.field.x, top: f.field.y, width: f.fieldWidth, height: f.fieldHeight, overflow: "hidden" }}>
          <Text style={[SendTextStyle, { color: C.ink, width: f.fieldWidth, position: "absolute", left: 0, top: -f.scroll }]}>{f.typed?.text ?? f.text}</Text>
        </View>,
      );
      return;
    }
    const copy = (key: string, x: number, y: number, s: number, inRow: { x: number; y: number }) => (
      <View
        key={key}
        pointerEvents="none"
        style={{ position: "absolute", left: 0, top: 0, width: rowBox.width, transformOrigin: [0, 0, 0], transform: [{ translateX: x }, { translateY: y }, { scale: s }, { translateX: -inRow.x }, { translateY: -inRow.y }] }}
      >
        <LocalFlightCopy.Provider value={true}>{f.rowElement}</LocalFlightCopy.Provider>
      </View>
    );
    if (wordless || !bubbleBox) {
      // Files alone: the row comes in where it is (its time with it), the files flying into it.
      drawn.push(copy("row", rowBox.x, rowBox.y, 1, { x: 0, y: 0 }));
      files(f, where, drawn);
      return;
    }
    const across = f.across();
    const up = f.up();
    const settle = f.settle();
    // The destination is the real bubble's laid-out position. No predicted foot, scroll delta or follower.
    const to = { x: bubbleBox.x + f.inBubble.x, y: bubbleBox.y + f.inBubble.y };
    const at = { x: f.from.x + (to.x - f.from.x) * across, y: f.from.y + (to.y - f.from.y) * up };
    const k = f.fromSize / f.toSize;
    // At the size typed until they settle (a new chat's: on the way).
    const s = k + (1 - k) * (f.carried ? up : settle);
    const inRow = { x: to.x - rowBox.x, y: to.y - rowBox.y };
    const words = f.words;
    const pieces = f.pieces();
    // Where the bubble's words are once in place.
    const home = { x: bubbleBox.x + f.pad.x, y: bubbleBox.y + f.pad.y };
    // In an open chat the words go as one block, as typed, its first letters (the first that showed) to theirs,
    // only those the field showed (more than six lines: the rest come in as they settle), their bubble's ground
    // coming in round them from half way; come, it opens out to the whole bubble as they settle into it.
    const lead = pieces ? (pieces.find((p) => p.shown) ?? pieces[0] ?? null) : null;
    const spots = !pieces || !lead ? null : pieces.map((p) => {
      // From where the field had it to where the bubble has it.
      const a = { x: f.field.x + p.from.x, y: f.field.y + p.from.y };
      const b = { x: home.x + p.at.x, y: home.y + p.at.y };
      if (f.carried) return { x: a.x + (b.x - a.x) * across, y: a.y + (b.y - a.y) * up };
      const block = { x: home.x + lead.at.x + (p.from.x - lead.from.x), y: home.y + lead.at.y + (p.from.y - lead.from.y) };
      const m = { x: a.x + (block.x - a.x) * across, y: a.y + (block.y - a.y) * up };
      return { x: m.x + (b.x - m.x) * settle, y: m.y + (b.y - m.y) * settle };
    });
    let ground: { left: number; top: number; right: number; bottom: number } | null = null;
    if (!f.carried && pieces && spots && lead) {
      let shown = pieces.map((_, i) => i).filter((i) => pieces[i]!.shown);
      if (shown.length === 0) shown = pieces.map((_, i) => i);
      const topOf = (i: number) => spots[i]!.y + (pieces[i]!.clip.top - pieces[i]!.at.y) * s;
      const footOf = (i: number) => spots[i]!.y + (pieces[i]!.clip.bottom - pieces[i]!.at.y) * s;
      const seen = Math.min(...shown.map(topOf));
      const top = seen + (Math.min(...pieces.map((_, i) => topOf(i))) - seen) * settle - f.pad.y;
      const bottom = Math.max(...shown.map(footOf)) + f.pad.y;
      const left = home.x - f.pad.x + (spots[pieces.indexOf(lead)]!.x - (home.x + lead.at.x));
      ground = { left, top, right: left + bubbleBox.width, bottom };
    }
    // What shows: the bubble (what the field did not show is not there yet), then the row as it is (its time).
    const view = ground
      ? { top: ground.top, bottom: ground.bottom + Math.max(0, rowBox.y + rowBox.height - ground.bottom) * settle }
      : { top: -1e5, bottom: 1e5 };
    // Under the words: where they cross on the way, the words stay readable.
    files(f, where, drawn);
    const inside: ReactNode[] = [];
    // The row (its words, when they fly apart, drawn by the pieces below and not in it; and its ground, above).
    inside.push(copy("row", at.x, at.y - view.top, s, inRow));
    if (ground && f.groundColor != null) {
      inside.push(
        <Smooth key="ground" radius={18} pointerEvents="none" style={{ position: "absolute", left: ground.left, top: ground.top - view.top, width: ground.right - ground.left, height: ground.bottom - ground.top, backgroundColor: f.groundColor, opacity: f.ground() }} />,
      );
    }
    if (words && pieces && spots) pieces.forEach((p, i) => {
      const there = spots[i]!;
      inside.push(
        <View key={`p${i}`} pointerEvents="none" style={{ position: "absolute", left: 0, top: 0, transformOrigin: [0, 0, 0], transform: [{ translateX: there.x }, { translateY: there.y - view.top }, { scale: s }, { translateX: -p.at.x }, { translateY: -p.at.y }] }}>
          <View style={{ position: "absolute", left: p.clip.left, top: p.clip.top, width: p.clip.right - p.clip.left, height: p.clip.bottom - p.clip.top, overflow: "hidden", opacity: p.shown || !f.carried ? 1 : across }}>
            <Text style={[SendTextStyle, { color: f.wordsColor ?? C.ink, width: f.wordsWidth || words.size.width, position: "absolute", left: -p.clip.left, top: -p.clip.top }]}>{words.text}</Text>
          </View>
        </View>,
      );
    });
    drawn.push(
      <View key="view" pointerEvents="none" style={{ position: "absolute", left: 0, right: 0, top: view.top, height: view.bottom - view.top, overflow: "hidden" }}>
        {inside}
      </View>,
    );
    // Out of the composer (its top edge as it is now, changing shape as they go): its hint comes back.
    const capTop = boxIn(host.capsule, where.overlay)?.y ?? f.top;
    if (host.hintAway && at.y + (rowBox.height - inRow.y) * s <= capTop) tell.push(() => { host.hintAway = false; });
  })();
  after.current = () => { for (const t of tell) t(); };

  return (
    <View
      ref={(v) => { overlay.current = v; host.where.overlay = v; }}
      collapsable={false}
      pointerEvents="none"
      style={StyleSheet.absoluteFill}
    >
      {drawn}
    </View>
  );
}

/** Something drawn at a box in the overlay. */
function At({ x, y, w, h, children }: { x: number; y: number; w: number; h: number; children?: ReactNode }) {
  return <View style={{ position: "absolute", left: x, top: y, width: w, height: h }}>{children}</View>;
}

/**
 * The files of a flight, each from its tile in the composer to its place in the message: across and up as the words go
 * (on a curve in an open chat), its box growing from the tile's to its own, what is in it cropped to the box as it is
 * (a picture opening out from the tile's square crop), corners from the composer's to its own.
 */
function files(flight: Flight, where: Where, drawn: ReactNode[]) {
  if (flight.files.length === 0) return;
  const across = flight.across();
  const up = flight.up();
  const fromCorner = concentric(ComposerCorner, ComposerFilesIn);
  const toCorner = 10;
  for (const ff of flight.files) {
    const end = ff.to?.view ? where.inOverlay(ff.to) : null;
    if (!end || ff.content == null || end.width === 0 || end.height === 0) {
      drawn.push(<At key={`f${ff.path}`} x={ff.from.left} y={ff.from.top} w={ff.from.width} h={ff.from.height}>{ff.tile}</At>);
      continue;
    }
    const a = ff.from;
    const left = a.left + (end.x - a.left) * across;
    const top = a.top + (end.y - a.top) * up;
    const w = a.width + (end.width - a.width) * up;
    const h = a.height + (end.height - a.height) * up;
    const c = Math.max(w / end.width, h / end.height);
    const corner = fromCorner + (toCorner - fromCorner) * up;
    drawn.push(
      <Smooth key={`f${ff.path}`} radius={corner} amount={up} style={{ position: "absolute", left, top, width: w, height: h }}>
        <View style={{ position: "absolute", left: (w - end.width * c) / 2, top: (h - end.height * c) / 2, width: end.width, height: end.height, transformOrigin: [0, 0, 0], transform: [{ scale: c }] }}>
          <LocalFlightCopy.Provider value={true}>{ff.content}</LocalFlightCopy.Provider>
        </View>
      </Smooth>,
    );
  }
}

/** How long a new chat's first words take to their place (web madeChat.ts: 480 ms, Ease.Arrive). */
export const ARRIVE_MS = 480;
/**
 * One continuous motion: start unfolding 144 ms into the 480 ms flight, then finish opening by 600 ms.
 * There is no pause at the destination; the composer starts closing as the bubble opens.
 */
export const FLIGHT_MS = 600;
export const FLY = 0.8;
export const SETTLE = 0.24;
