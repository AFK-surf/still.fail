// Picking a passage of a message where it is, in its chat (web mobile/pick.tsx): a finger held still on its words picks
// the word under it and, sliding on, widens it by words (the list holds still meanwhile); lifted, the passage has
// handles at its ends to move, and a bar over it to quote it into the chat's draft, copy it, or take all of the message.
// A tap anywhere else lets go of it, as going back does.
import * as Clipboard from "expo-clipboard";
import * as Haptics from "expo-haptics";
import { createContext, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { BackHandler, Pressable, View, type StyleProp, type View as ViewType, type ViewStyle } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated from "react-native-reanimated";
import { app } from "../AppState";
import { t } from "../i18n";
import { useUi } from "../ui/Host";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Drawn, PickedWords, type Offset, type Rect, type Span } from "../ui/Pick";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import type { Draft } from "./Composer";
import { pop } from "./Notes";


/** How long a finger is held still before it picks (Android's long press). */
const LONG_PRESS_MS = 400;
/** How far a finger goes before it is not held still (Android's touch slop, 8dp). */
const TOUCH_SLOP = 8;

type Listener = () => void;

/** What is picked in a list of messages: one passage of one message at a time; quoted into `draft` (none: only copied). */
export class MessagePick {
  readonly #draft: Draft | null;
  readonly #listeners = new Set<Listener>();
  #ts: string | null = null;
  #words: PickedWords | null = null;
  #picked: Span | null = null;
  #dragging = false;
  /** Who said it, as a quote names them, and as what ("agent" or "person"). */
  #author = "";
  #role = "person";

  constructor(draft: Draft | null) { this.#draft = draft; }

  subscribe = (l: Listener) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  #changed() { for (const l of this.#listeners) l(); }

  /** The message picked from. */
  get ts() { return this.#ts; }
  /** Its words. */
  get words() { return this.#words; }
  get picked() { return this.#picked; }
  /** A finger is widening it or moving one of its ends (its bar goes meanwhile). */
  get dragging() { return this.#dragging; }
  set dragging(on: boolean) { if (on !== this.#dragging) { this.#dragging = on; this.#changed(); } }

  get quotes() { return this.#draft != null; }

  start(ts: string, words: PickedWords, author: string, role: string, span: Span) {
    if (this.#words !== words && this.#words) this.#words.drawn = [];
    this.#ts = ts;
    this.#words = words;
    this.#author = author;
    this.#role = role;
    this.set(span);
  }

  set(span: Span) {
    this.#picked = span;
    if (this.#words) this.#words.drawn = [[span, Drawn.Picked]];
    this.#changed();
  }

  clear() {
    if (this.#words) this.#words.drawn = [];
    this.#ts = null;
    this.#words = null;
    this.#picked = null;
    this.#dragging = false;
    this.#changed();
  }

  /** Into the draft as a quote, its comment line taking the focus (Composer.tsx); then let go. */
  quote() {
    const picked = this.#picked;
    const text = picked && this.#words ? this.#words.textOf(picked).trim() : "";
    if (text.length > 0) this.#draft?.quote(this.#author, text, this.#ts, this.#role);
    this.clear();
  }
}

/** What a page reads of a pick, drawn again as it changes. */
export function usePick<T>(pick: MessagePick | null, select: (p: MessagePick) => T): T | undefined {
  return useSyncExternalStore(
    (l) => (pick ? pick.subscribe(l) : () => undefined),
    () => (pick ? select(pick) : undefined),
  );
}

/** The list's picking, for the messages in it (none: their words are only read). */
export const LocalMessagePick = createContext<MessagePick | null>(null);

/** A hold on a message's words (messagePick): the gesture, and the view it is measured from. */
export interface PickHold { gesture: ReturnType<typeof Gesture.Pan> | null; ref: (v: ViewType | null) => void }

/** What holds a message's words where passages are picked in place: a finger held still there picks. */
export function Hold({ hold, style, children }: { hold: PickHold; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  if (!hold.gesture) return <View style={style}>{children}</View>;
  return (
    <GestureDetector gesture={hold.gesture}>
      <View ref={hold.ref} collapsable={false} style={style}>{children}</View>
    </GestureDetector>
  );
}

/**
 * The hook for one message's words where passages are picked in place (LocalMessagePick): a hold for what holds them
 * (a finger held still there picks), and the words to give the texts inside (LocalPickedWords). Nothing for a
 * message without words; a hold on a link in them is the link's menu (ui/Links.tsx).
 */
export function messagePick(ts: string, author: string, role: string, text: string): [PickHold, PickedWords | null] {
  const pick = useContext(LocalMessagePick);
  const ui = useUi();
  const off = pick == null || text.trim().length === 0;
  const words = useMemo(() => new PickedWords(), [ts]);
  const said = useRef<[string, string]>([author, role]);
  said.current = [author, role];
  // Out of the list (scrolled far off, gone): what was picked in it goes too.
  useEffect(() => () => { if (pick && pick.words === words) pick.clear(); }, [pick, words]);
  const gesture = useMemo(() => {
    if (!pick) return null;
    let anchor: Span | null = null;
    // Lifted, moved (the list scrolls) or taken by something in it before a long press's time: not a hold.
    return Gesture.Pan()
      .activateAfterLongPress(LONG_PRESS_MS)
      .shouldCancelWhenOutside(false)
      .runOnJS(true)
      .onStart((e) => {
        anchor = null;
        if (ui.menu != null) return;
        const at = words.offsetAt({ x: e.x, y: e.y });
        if (at == null) return;
        anchor = words.wordAt(at);
        pick.start(ts, words, said.current[0], said.current[1], anchor);
        pick.dragging = true;
        Haptics.performAndroidHapticsAsync(Haptics.AndroidHaptics.Long_Press).catch(() => undefined);
      })
      .onUpdate((e) => {
        const a = anchor;
        if (!a) return;
        const at = words.offsetAt({ x: e.x, y: e.y });
        if (at == null) return;
        const w = words.wordAt(at);
        pick.set(w.start >= a.start ? { start: a.start, end: Math.max(a.end, w.end) } : { start: w.start, end: a.end });
      })
      .onFinalize(() => {
        if (anchor) pick.dragging = false;
        anchor = null;
      });
  }, [pick, words, ts, ui]);
  const ref = (v: ViewType | null) => { if (v) words.base = v; };
  if (off) return [{ gesture: null, ref: () => undefined }, null];
  return [{ gesture, ref }, words];
}

/** A tap nothing under it took, anywhere in it: what is picked is let go of (the props for the view round the list). */
export function letsGoOfPick(pick: MessagePick) {
  let down: { x: number; y: number } | null = null;
  return {
    onTouchStart: (e: { nativeEvent: { pageX: number; pageY: number; touches: unknown[] } }) => {
      down = pick.picked != null && e.nativeEvent.touches.length <= 1 ? { x: e.nativeEvent.pageX, y: e.nativeEvent.pageY } : null;
    },
    onTouchMove: (e: { nativeEvent: { pageX: number; pageY: number } }) => {
      if (down && Math.hypot(e.nativeEvent.pageX - down.x, e.nativeEvent.pageY - down.y) > TOUCH_SLOP) down = null;
    },
    onTouchEnd: () => {
      // Not while a finger moves one of its ends, or the bar over it took the tap (it keeps its touches).
      if (down && !pick.dragging && !barTouched) pick.clear();
      down = null;
      barTouched = false;
    },
    onTouchCancel: () => { down = null; },
  };
}

/** The bar over the passage took the touch going on (a tap between its buttons is not one on the list). */
let barTouched = false;

/** Drawn again each frame while `on`: what follows what moves without telling (the list's scroll, the words laid out). */
function useEachFrame(on: boolean) {
  const [, tick] = useState(0);
  useEffect(() => {
    if (!on) return;
    let frame = requestAnimationFrame(function next() { tick((n) => n + 1); frame = requestAnimationFrame(next); });
    return () => cancelAnimationFrame(frame);
  }, [on]);
}

/** Where `view` is in `base` (both drawn), as laid out now: measured at once (the new architecture measures in step). */
function positionIn(view: ViewType, base: ViewType): Offset | null {
  let out: Offset | null = null;
  try { view.measureLayout(base, (x, y) => { out = { x, y }; }, () => undefined); } catch { /* not drawn */ }
  return out;
}

/**
 * Over the list: the picked passage's handles and its bar (over it; under it when the bar over the list is too near),
 * the bar gone while the list moves or the passage is being changed. `follow` reads where the list is scrolled to (this
 * follows it: drawn again each frame while something is picked); `top` and `bottom` are what the bar and the composer
 * cover of it.
 */
export function PickLayer({ pick, follow, moving, top, bottom, style }: { pick: MessagePick; follow: () => unknown; moving: boolean; top: number; bottom: number; style?: StyleProp<ViewStyle> }) {
  usePick(pick, (p) => p.picked);
  usePick(pick, (p) => p.dragging);
  const picked = pick.picked;
  const words = pick.words;
  useEffect(() => {
    if (picked == null) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { pick.clear(); return true; });
    return () => sub.remove();
  }, [picked != null, pick]); // eslint-disable-line react-hooks/exhaustive-deps
  const layer = useRef<ViewType | null>(null);
  const [size, setSize] = useState<{ width: number; height: number } | null>(null);
  useEachFrame(words != null && picked != null);
  useSyncExternalStore(words?.subscribe ?? noSubscribe, () => words?.version ?? 0);
  follow();
  const content = (() => {
    if (words == null || picked == null) return null;
    const at = size;
    const base = words.base;
    if (!at || !base || !layer.current) return null;
    // The words' place to this one's.
    const shift = positionIn(base, layer.current);
    if (!shift) return null;
    const lines: Rect[] = words.rects(picked);
    if (lines.length === 0) return null;
    const handles = <Handles words={words} lines={lines} shift={shift} picked={picked} setPicked={(s) => pick.set(s)} setDragging={(d) => { pick.dragging = d; }} />;
    if (pick.dragging || moving) return handles;
    const first = translate(lines[0]!, shift);
    const last = translate(lines[lines.length - 1]!, shift);
    const width = at.width;
    // Over the passage; under it (clear of the end's knob) when the bar over the list is too near; on the screen
    // when the passage runs past it.
    const over = first.top - 52;
    const y = coerceIn(over < top + 8 ? last.bottom + 28 : over, top + 8, Math.max(at.height - bottom - 48, top + 8));
    const x = coerceIn(lines.length > 1 ? width / 2 : (first.left + first.right) / 2, 130, Math.max(width - 130, 130));
    const everything = picked.start === 0 && picked.end >= words.text().length;
    return (
      <>
        {handles}
        <PickBar
          x={x} y={y} quotes={pick.quotes} everything={everything}
          onQuote={() => pick.quote()}
          onCopy={() => {
            Clipboard.setStringAsync(words.textOf(picked)).catch(() => undefined);
            app.toast = t("android-chat.annotate.copied");
            pick.clear();
          }}
          onAll={() => pick.set({ start: 0, end: words.text().length })}
        />
      </>
    );
  })();
  return (
    <View ref={layer} collapsable={false} pointerEvents="box-none" style={style} onLayout={(e) => setSize({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
      {content}
    </View>
  );
}

const noSubscribe = () => () => undefined;
const coerceIn = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);
const translate = (r: Rect, by: Offset): Rect => ({ left: r.left + by.x, top: r.top + by.y, right: r.right + by.x, bottom: r.bottom + by.y });

/**
 * What to do with the picked passage, over it: on the ground every panel that pops up stands on (web styles/glass.ts
 * panel: opaque, a line round it; glass over the messages would let their words read through). Placed by its middle
 * (`x` is where its middle goes).
 */
function PickBar({ x, y, quotes, everything, onQuote, onCopy, onAll }: { x: number; y: number; quotes: boolean; everything: boolean; onQuote: () => void; onCopy: () => void; onAll: () => void }) {
  const C = useC();
  const [w, setW] = useState<number | null>(null);
  const popped = pop();
  return (
    <View
      style={{ position: "absolute", left: x - (w ?? 0) / 2, top: y, opacity: w == null ? 0 : 1 }}
      onLayout={(e) => setW(e.nativeEvent.layout.width)}
      // A touch between its buttons stays on it (not a tap on the list, which lets go of the passage).
      onStartShouldSetResponder={() => true}
      onTouchStart={() => { barTouched = true; }}
    >
      <Animated.View style={popped}>
        <Smooth
          radius={20}
          stroke={{ width: 1, color: C.line }}
          style={{ height: 40, flexDirection: "row", alignItems: "center", paddingHorizontal: 4, backgroundColor: C.surface, elevation: 8, shadowColor: "#000000" }}
        >
          {quotes && <BarButton label={t("android-chat.pick.quote")} icon={Icons.Quote} onClick={onQuote} />}
          <BarButton label={t("common.copy")} icon={Icons.Copy} onClick={onCopy} />
          {!everything && <BarButton label={t("android-chat.annotate.selectAll")} icon={null} onClick={onAll} />}
        </Smooth>
      </Animated.View>
    </View>
  );
}

function BarButton({ label, icon, onClick }: { label: string; icon: IconPaths | null; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={16}>
      <Pressable
        onPress={onClick}
        android_ripple={{ color: `${C.ink}1A` }}
        style={{ height: 32, paddingHorizontal: 12, flexDirection: "row", alignItems: "center", gap: 5 }}
      >
        {icon && <Icon icon={icon} size={15} color={C.ink} />}
        <T size={14} color={C.ink}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/**
 * The picked passage's two ends, each a handle a finger moves: a line down its side with a knob. `lines` are the
 * passage's in the words' place, `shift` takes them to where the handles are placed.
 */
function Handles({ words, lines, shift, picked, setPicked, setDragging }: { words: PickedWords; lines: Rect[]; shift: Offset; picked: Span; setPicked: (s: Span) => void; setDragging: (on: boolean) => void }) {
  return (
    <>
      <Handle start words={words} lines={lines} shift={shift} picked={picked} setPicked={setPicked} setDragging={setDragging} />
      <Handle start={false} words={words} lines={lines} shift={shift} picked={picked} setPicked={setPicked} setDragging={setDragging} />
    </>
  );
}

function Handle({ start, words, lines, shift, picked, setPicked, setDragging }: { start: boolean; words: PickedWords; lines: Rect[]; shift: Offset; picked: Span; setPicked: (s: Span) => void; setDragging: (on: boolean) => void }) {
  const C = useC();
  const accent = C.accent;
  const line = start ? lines[0]! : lines[lines.length - 1]!;
  const lineHeight = line.bottom - line.top;
  const x = (start ? line.left : line.right) + shift.x;
  // The finger's room: 36dp round the knob; the knob over the start's line, under the end's.
  const room = 36;
  const top = (start ? line.top - 28 : line.top) + shift.y;
  const left = x - room / 2;
  // What the gesture reads as it goes (it is made once): the passage now, the ends, where the box is.
  const now = useRef({ picked, lines, box: { x: left, y: top }, shift });
  now.current = { picked, lines, box: { x: left, y: top }, shift };
  const gesture = useMemo(() => {
    let grab: Offset = { x: 0, y: 0 };
    let held: Span = picked;
    // A point in the box, in the words' place.
    const within = (p: Offset) => ({ x: p.x + now.current.box.x - now.current.shift.x, y: p.y + now.current.box.y - now.current.shift.y });
    return Gesture.Pan()
      .minDistance(0)
      .runOnJS(true)
      .onBegin((e) => {
        const finger = within({ x: e.x, y: e.y });
        // Where the finger is off the end's middle, kept, so that the end does not jump to under it.
        const ls = now.current.lines;
        const first = ls[0]!;
        const last = ls[ls.length - 1]!;
        const end = start ? { x: first.left, y: (first.top + first.bottom) / 2 } : { x: last.right, y: (last.top + last.bottom) / 2 };
        grab = { x: end.x - finger.x, y: end.y - finger.y };
        held = now.current.picked;
        setDragging(true);
      })
      .onUpdate((e) => {
        const p = within({ x: e.x, y: e.y });
        const at = words.offsetAt({ x: p.x + grab.x, y: p.y + grab.y });
        if (at == null) return;
        held = start ? { ...held, start: Math.min(at, held.end - 1) } : { ...held, end: Math.max(at, held.start + 1) };
        setPicked(held);
      })
      .onFinalize(() => setDragging(false));
  }, [start, words]);
  const knob = 6;
  const w = 2;
  const lineTop = start ? lineHeight + 28 - lineHeight : 0;
  return (
    <GestureDetector gesture={gesture}>
      <View style={{ position: "absolute", left, top, width: room, height: lineHeight + 28 }}>
        <View style={{ position: "absolute", left: room / 2 - w / 2, top: lineTop, width: w, height: lineHeight, backgroundColor: accent }} />
        <View
          style={{
            position: "absolute", width: knob * 2, height: knob * 2, borderRadius: knob, backgroundColor: accent, left: room / 2 - knob,
            top: (start ? lineTop - knob + 1 : lineTop + lineHeight + knob - 1) - knob,
          }}
        />
      </View>
    </GestureDetector>
  );
}
