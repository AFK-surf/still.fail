// Words a finger picks passages of (a message in its chat, screens/MessagePick.tsx; web mobile/pick.tsx): each text in
// them (a paragraph of Markdown, a person's words) says where it is and what it holds; they are taken, in the order
// they read, as one text, and each draws over itself what is picked.
//
// Here too is what the text hooks (Pick's pickable, TextMark's passageMark, Links' linkHold) stand on, which Compose has
// built in: a text's layout (TextLayoutResult), read from what React Native says of it, and the box they draw in.
import { createContext, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { View, type TextLayoutEventData } from "react-native";
import Svg, { Rect as SvgRect } from "react-native-svg";
import { NoTextModifier, type AnnotatedString, type TextLayout, type TextModifier } from "./Annotated";
import { inert } from "./Links";
import { useC, withAlpha } from "./Theme";

// ── a text's layout ────────────────────────────────────────────────────

/** A box: Compose's Rect (left, top, right, bottom). */
export interface Rect { left: number; top: number; right: number; bottom: number }
export const rectWidth = (r: Rect) => r.right - r.left;
export const rectHeight = (r: Rect) => r.bottom - r.top;
export const rectContains = (r: Rect, p: { x: number; y: number }) => p.x >= r.left && p.x < r.right && p.y >= r.top && p.y < r.bottom;

/** A point (Compose's Offset). */
export interface Offset { x: number; y: number }

/**
 * A text as it was laid out (Compose's TextLayoutResult), in the text's own box, dp: its lines and where each
 * character of them is. `text` is what was laid out (layoutInput.text), `fontSize` its size (sp).
 */
export interface TextLayoutResult {
  readonly text: string;
  readonly fontSize: number;
  readonly lineCount: number;
  readonly size: { width: number; height: number };
  getLineForOffset(offset: number): number;
  getLineStart(line: number): number;
  /** Past its last character; `visibleEnd`: past its last one that is not white space. */
  getLineEnd(line: number, visibleEnd?: boolean): number;
  getLineTop(line: number): number;
  getLineBottom(line: number): number;
  getLineBaseline(line: number): number;
  getLineForVerticalPosition(y: number): number;
  /** The x of the edge before `offset`'s character. */
  getHorizontalPosition(offset: number, usePrimaryDirection: boolean): number;
  /** The box of the character at `offset`. */
  getBoundingBox(offset: number): Rect;
  /** The box around [start, end) (getPathForRange(start, end).getBounds()). */
  getPathBounds(start: number, end: number): Rect;
  /** The offset nearest a point. */
  getOffsetForPosition(position: Offset): number;
}

/** How wide a character is, in ems, near enough (a CJK one is a whole em, a narrow Latin one a third). */
function advance(ch: string): number {
  const c = ch.codePointAt(0) ?? 0;
  if (ch === "\n") return 0;
  if ((c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6) || c >= 0x1f300) return 1;
  if (" ".includes(ch)) return 0.27;
  if ("iljI.,:;'|!`".includes(ch)) return 0.28;
  if ("frt()[]{}\"-".includes(ch)) return 0.36;
  if ("mwMW@".includes(ch)) return 0.85;
  if (ch >= "A" && ch <= "Z") return 0.65;
  return 0.55;
}

/**
 * A text's layout from what React Native says of it (onTextLayout: its lines, each with its words, box and baseline).
 * NATIVE: where each character of a line is (Android's Layout.getPrimaryHorizontal / getOffsetForHorizontal) is not
 * said by React Native's onTextLayout; until a native text measurer says it, a line's characters are spread over its
 * width by their usual widths (a CJK character an em, a Latin one by its shape), which is exact for CJK and near for
 * the rest.
 */
export function textLayoutOf(text: string, lines: TextLayoutEventData["lines"], fontSize: number): TextLayoutResult {
  type L = { start: number; end: number; x: number; top: number; bottom: number; baseline: number; edges: number[] };
  const out: L[] = [];
  let at = 0;
  for (const line of lines) {
    const start = Math.min(at, text.length);
    const end = Math.min(text.length, start + line.text.length);
    at = end;
    // Its visible characters fill its width; trailing spaces and the line's break take none of it.
    let visible = end;
    while (visible > start && /\s/.test(text[visible - 1]!)) visible--;
    const weights: number[] = [];
    for (let i = start; i < end; i++) weights.push(i < visible ? advance(text[i]!) : 0);
    const sum = weights.reduce((a, b) => a + b, 0);
    const scale = sum > 0 ? line.width / sum : 0;
    const edges = [line.x];
    for (const w of weights) edges.push(edges[edges.length - 1]! + w * scale);
    out.push({ start, end, x: line.x, top: line.y, bottom: line.y + line.height, baseline: line.y + line.ascender, edges });
  }
  if (out.length === 0) out.push({ start: 0, end: text.length, x: 0, top: 0, bottom: fontSize * 1.4, baseline: fontSize, edges: [0] });
  // What the lines did not hold (a text cut short by its line count) belongs to the last.
  out[out.length - 1]!.end = Math.max(out[out.length - 1]!.end, Math.min(at, text.length));
  const lineOf = (offset: number) => {
    for (let i = 0; i < out.length; i++) if (offset < out[i]!.end) return i;
    return out.length - 1;
  };
  const xOf = (offset: number) => {
    const l = out[lineOf(offset)]!;
    const i = Math.max(0, Math.min(l.edges.length - 1, offset - l.start));
    return l.edges[i]!;
  };
  const width = Math.max(0, ...lines.map((l) => l.x + l.width));
  const height = out[out.length - 1]!.bottom;
  const layout: TextLayoutResult = {
    text,
    fontSize,
    lineCount: out.length,
    size: { width, height },
    getLineForOffset: lineOf,
    getLineStart: (line) => out[line]?.start ?? text.length,
    getLineEnd: (line, visibleEnd = false) => {
      const l = out[line];
      if (!l) return text.length;
      if (!visibleEnd) return l.end;
      let e = l.end;
      while (e > l.start && /\s/.test(text[e - 1]!)) e--;
      return e;
    },
    getLineTop: (line) => out[line]?.top ?? 0,
    getLineBottom: (line) => out[line]?.bottom ?? 0,
    getLineBaseline: (line) => out[line]?.baseline ?? 0,
    getLineForVerticalPosition: (y) => {
      for (let i = 0; i < out.length; i++) if (y < out[i]!.bottom) return i;
      return out.length - 1;
    },
    getHorizontalPosition: (offset) => xOf(offset),
    getBoundingBox: (offset) => {
      const line = lineOf(offset);
      const l = out[line]!;
      const i = Math.max(0, Math.min(l.edges.length - 2, offset - l.start));
      return { left: l.edges[i] ?? l.x, top: l.top, right: l.edges[i + 1] ?? l.edges[i] ?? l.x, bottom: l.bottom };
    },
    getPathBounds: (start, end) => {
      if (end <= start) return { left: 0, top: 0, right: 0, bottom: 0 };
      const first = lineOf(start);
      const last = lineOf(end - 1);
      let left = Infinity;
      let right = -Infinity;
      for (let line = first; line <= last; line++) {
        const l = out[line]!;
        const s = Math.max(start, l.start);
        const e = Math.min(end, l.end);
        if (e <= s) continue;
        left = Math.min(left, l.edges[s - l.start]!);
        right = Math.max(right, l.edges[e - l.start]!);
      }
      if (left === Infinity) return { left: 0, top: 0, right: 0, bottom: 0 };
      return { left, top: out[first]!.top, right, bottom: out[last]!.bottom };
    },
    getOffsetForPosition: (p) => {
      const line = layout.getLineForVerticalPosition(p.y);
      const l = out[line]!;
      let best = l.start;
      let gap = Infinity;
      const last = Math.max(l.start, layout.getLineEnd(line, true));
      for (let o = l.start; o <= last; o++) {
        const d = Math.abs(l.edges[o - l.start]! - p.x);
        if (d < gap) { gap = d; best = o; }
      }
      return best;
    },
  };
  return layout;
}

/** A range's boxes in a text, a line each (none when it is empty). */
export function lineRects(l: TextLayoutResult, start: number, end: number): Rect[] {
  if (start >= end) return [];
  const first = l.getLineForOffset(start);
  const last = l.getLineForOffset(end - 1);
  const out: Rect[] = [];
  for (let line = first; line <= last; line++) {
    const s = Math.max(start, l.getLineStart(line));
    const e = Math.min(end, l.getLineEnd(line));
    if (e <= s) continue;
    const box = l.getPathBounds(s, e);
    if (rectWidth(box) > 0) out.push({ left: box.left, top: l.getLineTop(line), right: box.right, bottom: l.getLineBottom(line) });
  }
  return out;
}

// ── what the text hooks share ──────────────────────────────────────────

/** A text hook's answer, as the Android app's are (Annotated.tsx): what to put on the text, and what to give its onTextLayout. */
export type TextHook = [TextModifier, (e: TextLayout) => void];

// Made when first asked: Annotated.tsx, in an import cycle with this module, may not have loaded yet when it does.
let none: TextHook | null = null;
const NONE_HOOK = (): TextHook => (none ??= [NoTextModifier, () => {}]);
export const noHook = (): TextHook => NONE_HOOK();

/**
 * The size of a text's words from its lines (a hook does not see the text's style): its capitals' height over the
 * face's (Roboto's capitals are .711 of its size), else its ascent and descent over theirs (1.17).
 */
export function emOf(lines: TextLayoutEventData["lines"]): number {
  const l = lines[0];
  if (!l) return 16;
  if (l.capHeight > 0) return l.capHeight / 0.711;
  return (l.ascender + l.descender) / 1.17;
}

/**
 * A text's layout as a hook keeps it: laid out again only when its lines are (React Native says so on every layout).
 * The layout, and what to give the text's onTextLayout.
 */
export function useLaidOut(text: string): [TextLayoutResult | null, (e: TextLayout) => void] {
  const [layout, setLayout] = useState<TextLayoutResult | null>(null);
  const seen = useRef("");
  const laid = (e: TextLayout) => {
    const lines = e.nativeEvent.lines;
    const sig = `${text}\u0000${lines.map((l) => `${l.text.length},${l.x},${l.y},${l.width},${l.height}`).join(";")}`;
    if (sig === seen.current) return;
    seen.current = sig;
    setLayout(textLayoutOf(text, lines, emOf(lines)));
  };
  return [layout, laid];
}

/**
 * What a hook draws behind a text, in its box (Compose's drawBehind): a View as large as the text (AnnotatedText puts
 * what is behind first in a box the text fills), which is also where the hook finds the text on the screen (`view`).
 */
export function TextBox({ view, children }: { view?: (v: View | null) => void; children?: ReactNode }) {
  return <View ref={view} collapsable={false} pointerEvents="none" style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }}>{children}</View>;
}

// ── the words being picked ─────────────────────────────────────────────

/** A passage: from `start` up to `end` (offsets in the words as one text). */
export interface Span { start: number; end: number }

/** How the words draw a passage: picked (a ground), noted (a line under it), or the note open (a stronger line). */
export enum Drawn { Picked, Noted, Open }

/** A text in the words: what it holds and, once laid out, where. */
class Piece {
  layout: TextLayoutResult | null = null;
  view: View | null = null;
  /** Where it was last seen in the words' place, and how big (a scroll moves both: not a change). */
  at: Offset | null = null;
  box: { width: number; height: number } | null = null;
  constructor(readonly text: string) {}
}

/** The words of one message being picked from: the texts in them, and what to draw over them. */
export class PickedWords {
  static Piece = Piece;
  readonly pieces: Piece[] = [];
  /** Where the words are laid out: the place everything is measured in (its View). */
  base: View | null = null;
  #drawn: [Span, Drawn][] = [];
  #laidOut = 0;
  readonly #listeners = new Set<() => void>();
  #version = 0;

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of this.#listeners) l(); }

  /** What is drawn over the words now. */
  get drawn(): [Span, Drawn][] { return this.#drawn; }
  set drawn(d: [Span, Drawn][]) { this.#drawn = d; this.#changed(); }
  /** Something is picked or noted in them: their links are drawn, not tapped, meanwhile (a tap lets go). */
  get picking(): boolean { return this.#drawn.length > 0; }
  /** Bumped when a text is laid out again (what is placed over the words follows). */
  get laidOut(): number { return this.#laidOut; }
  set laidOut(n: number) { this.#laidOut = n; this.#changed(); }

  /** Where a piece is in the words' place: measured again (a text laid out, the words' place set). */
  measure(piece: Piece) {
    const base = this.base;
    const view = piece.view;
    if (!base || !view) return;
    view.measureLayout(base, (x, y, width, height) => {
      const was = piece.at;
      piece.box = { width, height };
      if (!was || was.x !== x || was.y !== y) { piece.at = { x, y }; this.laidOut++; }
    }, () => undefined);
  }

  private placed() { return this.pieces.filter((p) => p.layout != null && p.view != null && p.at != null && this.base != null); }

  /** The texts laid out, in the order they read (top to bottom, then left to right), each with where it starts. */
  order(): [Piece, number][] {
    if (!this.base) return [];
    let at = 0;
    return this.placed()
      .sort((a, b) => a.at!.y - b.at!.y || a.at!.x - b.at!.x)
      .map((p) => { const r: [Piece, number] = [p, at]; at += p.text.length + 1; return r; });
  }

  /** All of it as one text (its texts one to a line). */
  text(): string { return this.order().map(([p]) => p.text).join("\n"); }

  /** The text of a passage. */
  textOf(span: Span): string {
    const t = this.text();
    const c = (n: number) => Math.max(0, Math.min(t.length, n));
    return t.substring(c(span.start), c(span.end));
  }

  /** The boxes of a passage's lines, in the words' place. */
  rects(span: Span): Rect[] {
    if (!this.base) return [];
    return this.order().flatMap(([p, start]) => {
      const l = p.layout!;
      const s = Math.max(0, Math.min(p.text.length, span.start - start));
      const e = Math.max(0, Math.min(p.text.length, span.end - start));
      const o = p.at!;
      return lineRects(l, s, e).map((r) => ({ left: r.left + o.x, top: r.top + o.y, right: r.right + o.x, bottom: r.bottom + o.y }));
    });
  }

  /** The offset in the words of a point in their place; past the first or last text, their start or end. */
  offsetAt(point: Offset): number | null {
    if (!this.base) return null;
    const order = this.order();
    if (order.length === 0) return null;
    // The text whose lines hold the point's height (the nearest across, beside a table's cell); else the next one down.
    const boxes = order.map(([p, start]) => {
      const box = p.box ?? p.layout!.size;
      return [p, start, { left: p.at!.x, top: p.at!.y, right: p.at!.x + box.width, bottom: p.at!.y + box.height }] as const;
    });
    const row = boxes.filter(([, , box]) => point.y >= box.top && point.y < box.bottom);
    let hit: (typeof boxes)[number] | undefined;
    let best = Infinity;
    for (const b of row) {
      const box = b[2];
      const d = point.x < box.left ? box.left - point.x : point.x > box.right ? point.x - box.right : 0;
      if (d < best) { best = d; hit = b; }
    }
    if (!hit) {
      const below = boxes.find(([, , box]) => point.y < box.top);
      return below ? below[1] : this.text().length;
    }
    const [p, start] = hit;
    const local = { x: point.x - p.at!.x, y: point.y - p.at!.y };
    return start + Math.max(0, Math.min(p.text.length, p.layout!.getOffsetForPosition(local)));
  }

  /** The word at an offset (as a phone picks one: a word as it is; a space or a mark, only that character). */
  wordAt(at: number): Span {
    const text = this.text();
    if (text.length === 0) return { start: 0, end: 0 };
    const i = Math.max(0, Math.min(text.length - 1, at));
    const Segmenter = (Intl as unknown as { Segmenter?: new (l?: string, o?: { granularity: "word" }) => { segment(s: string): Iterable<{ segment: string; index: number; isWordLike?: boolean }> } }).Segmenter;
    if (Segmenter) {
      for (const s of new Segmenter(undefined, { granularity: "word" }).segment(text)) {
        if (i >= s.index && i < s.index + s.segment.length) {
          return s.isWordLike && s.segment.trim() !== "" ? { start: s.index, end: s.index + s.segment.length } : { start: i, end: i + 1 };
        }
      }
      return { start: i, end: i + 1 };
    }
    // Without the system's word breaks (Hermes has no Intl.Segmenter): a run of letters and figures is a word, as
    // BreakIterator takes Latin words; a CJK character is one on its own (BreakIterator's dictionary would take more).
    const ch = text[i]!;
    if (/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(ch)) return { start: i, end: i + 1 };
    const word = /[\p{L}\p{N}_'’]/u;
    if (!word.test(ch)) return { start: i, end: i + 1 };
    const cjk = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;
    let s = i;
    while (s > 0 && word.test(text[s - 1]!) && !cjk.test(text[s - 1]!)) s--;
    let e = i + 1;
    while (e < text.length && word.test(text[e]!) && !cjk.test(text[e]!)) e++;
    return { start: s, end: e };
  }
}

/** The words that may be picked from, for the texts inside (none: they are only read). */
export const LocalPickedWords = createContext<PickedWords | null>(null);

/** What is drawn over a piece: its picked ground, its notes' lines. */
function PieceMarks({ words, piece, layout }: { words: PickedWords; piece: Piece; layout: TextLayoutResult }) {
  const C = useC();
  useSyncExternalStore(words.subscribe, () => words.version);
  if (words.drawn.length === 0) return null;
  const start = words.order().find(([p]) => p === piece)?.[1];
  if (start === undefined) return null;
  const accent = C.accent;
  const marks: ReactNode[] = [];
  words.drawn.forEach(([span, how], k) => {
    const s = Math.max(0, Math.min(piece.text.length, span.start - start));
    const e = Math.max(0, Math.min(piece.text.length, span.end - start));
    lineRects(layout, s, e).forEach((r, j) => {
      if (how === Drawn.Picked) {
        marks.push(<SvgRect key={`${k}-${j}`} x={r.left} y={r.top} width={rectWidth(r)} height={rectHeight(r)} fill={withAlpha(accent, 0.26)} />);
      } else {
        const thick = how === Drawn.Open ? 2 : 1.5;
        const color = how === Drawn.Open ? accent : withAlpha(accent, 0.7);
        // Under the words, as the web's text-underline-offset: 3px below their baseline.
        const y = layout.getLineBaseline(layout.getLineForVerticalPosition((r.top + r.bottom) / 2)) + 3;
        marks.push(<SvgRect key={`${k}-${j}`} x={r.left} y={y} width={rectWidth(r)} height={thick} fill={color} />);
      }
    });
  });
  return <Svg style={{ position: "absolute", left: 0, top: 0 }} width={layout.size.width + 4} height={layout.size.height + 6}>{marks}</Svg>;
}

/**
 * The hook for a text in words that may be picked from: what to put on the text (it says where it is and draws what is
 * picked and noted over it) and what to give the text's onTextLayout. Nothing outside such words.
 */
export function pickable(text: string): TextHook {
  const words = useContext(LocalPickedWords);
  const piece = useMemo(() => new Piece(text), [text]);
  const [layout, laid] = useLaidOut(text);
  useEffect(() => {
    if (!words) return;
    words.pieces.push(piece);
    return () => {
      const i = words.pieces.indexOf(piece);
      if (i >= 0) words.pieces.splice(i, 1);
    };
  }, [words, piece]);
  useEffect(() => {
    if (!words || !layout) return;
    const was = piece.layout;
    piece.layout = layout;
    if (was?.size.width !== layout.size.width || was?.size.height !== layout.size.height || was?.text !== layout.text) words.laidOut++;
    words.measure(piece);
  }, [words, piece, layout]);
  if (!words) return NONE_HOOK();
  return [
    {
      behind: (
        <TextBox view={(v) => { piece.view = v; if (v) words.measure(piece); }}>
          {layout && <PieceMarks words={words} piece={piece} layout={layout} />}
        </TextBox>
      ),
    },
    laid,
  ];
}

/** `text` as the words it is in show it: while something is picked in them, its links drawn but not to tap (Links.tsx). */
export function pickedText(text: AnnotatedString): AnnotatedString {
  const words = useContext(LocalPickedWords);
  const picking = useSyncExternalStore(words?.subscribe ?? noSubscribe, () => words?.picking ?? false);
  return useMemo(() => (picking ? inert(text) : text), [picking, text]);
}

const noSubscribe = () => () => {};
