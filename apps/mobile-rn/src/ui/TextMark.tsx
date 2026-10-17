// A passage marked in a message's words, as the web marks where a quote leads (Chat.tsx → findText, flashRange; the
// ::highlight(quote-flash) in styles/global.css.ts): whatever text shows it (a paragraph of Markdown, a person's words,
// your bubble) finds it in its own words, whitespace taken as one space, and draws a rounded ground behind just that range.
import { createContext, useContext, useEffect, useMemo, useRef, useSyncExternalStore, type ReactNode } from "react";
import type { View } from "react-native";
import Svg, { Path, Rect as SvgRect } from "react-native-svg";
import { AnnotatedString } from "./Annotated";
import { Ease } from "./Motion";
import { TextBox, noHook, useLaidOut, type Offset, type Rect, type TextHook, type TextLayoutResult } from "./Pick";
import { SMOOTH_SCALE } from "./Smooth";
import { withAlpha } from "./Theme";

/** Kotlin's IntRange: `first` to `last`, both in. */
export interface IntRange { first: number; last: number }

/**
 * What to mark and how strongly now (`level`, the ground's opacity); `found` once some text holds it. With `words` (a
 * search's), each is bold with a hand-drawn stroke under it instead (web [data-search-marks]), drawn in as `drawn` goes
 * in ms (each stroke [STROKE_MS] long, the next [STROKE_GAP_MS] after it, as the web's). What draws it follows it
 * (`subscribe`), as Compose's snapshot state is followed.
 */
export class TextMark {
  readonly needle: string;
  #level = 0;
  #drawn = 0;
  #found = false;
  #version = 0;
  readonly #listeners = new Set<() => void>();
  /** Where the marked range was last laid out: its text's View and the range's box in it. */
  where: { view: View; box: Rect } | null = null;

  constructor(passage: string, readonly color: string, readonly words: string[] = []) {
    this.needle = passage.replace(/\s+/g, " ").trim();
  }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of this.#listeners) l(); }

  get level() { return this.#level; }
  set level(v: number) { if (v !== this.#level) { this.#level = v; this.#changed(); } }
  get drawn() { return this.#drawn; }
  set drawn(v: number) { if (v !== this.#drawn) { this.#drawn = v; this.#changed(); } }
  get found() { return this.#found; }
  set found(v: boolean) { if (v !== this.#found) { this.#found = v; this.#changed(); } }
}

/** A search's stroke: how long one takes to draw in, and how long after one the next starts (web global.css.ts). */
export const STROKE_MS = 520;
export const STROKE_GAP_MS = 180;

/** The mark for the words inside (a message a quote led to), if any. */
export const LocalTextMark = createContext<TextMark | null>(null);

const isSpace = (c: string) => /\s/.test(c);

/** Where `needle` (whitespace as one space) is in `text`: its first and last character, or null. */
export function findPassage(text: string, needle: string): IntRange | null {
  if (needle.length === 0) return null;
  let flat = "";
  const back: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const c = isSpace(text[i]!) ? " " : text[i]!;
    if (c === " " && flat.endsWith(" ")) continue;
    flat += c;
    back.push(i);
  }
  const at = flat.indexOf(needle);
  return at < 0 ? null : { first: back[at]!, last: back[at + needle.length - 1]! };
}

/** Where each of `words` (case aside) is in `text`, in order (a search's words, marked where it led). */
export function findWords(text: string, words: string[]): IntRange[] {
  const lower = text.toLowerCase();
  if (lower.length !== text.length) return [];
  const out: IntRange[] = [];
  for (const w of words.map((x) => x.toLowerCase()).filter((x) => x.length > 0)) {
    let at = lower.indexOf(w);
    while (at >= 0) { out.push({ first: at, last: at + w.length - 1 }); at = lower.indexOf(w, at + w.length); }
  }
  return out.sort((a, b) => a.first - b.first);
}

/** Ease.Standard as a function of JS (Reanimated keeps its curves as factories). */
const standard = (() => {
  const e = Ease.Standard as unknown as { factory?: () => (t: number) => number } | ((t: number) => number);
  return typeof e === "function" ? e : e.factory!();
})();

/** A point of the cubic from p0 to p3, `t` of the way. */
function cubic(p0: Offset, p1: Offset, p2: Offset, p3: Offset, t: number): Offset {
  const u = 1 - t;
  return {
    x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
    y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y,
  };
}

/** What a mark draws behind a text: the strokes under its words, or the ground under its passage. */
function MarkBehind({ mark, ranges, layout }: { mark: TextMark; ranges: IntRange[]; layout: TextLayoutResult }) {
  useSyncExternalStore(mark.subscribe, () => mark.version);
  const l = layout;
  const shapes: ReactNode[] = [];
  if (mark.words.length > 0) {
    // Each word's stroke under it, a line at a time (one that wraps has two), drawn in as `drawn` reaches it.
    const width = 2.5;
    let i = 0;
    for (const r of ranges) {
      if (r.last >= l.text.length) continue;
      for (let line = l.getLineForOffset(r.first); line <= l.getLineForOffset(r.last); line++) {
        const from = Math.max(r.first, l.getLineStart(line));
        const to = Math.min(r.last + 1, l.getLineEnd(line, true));
        if (to <= from) continue;
        const left = l.getHorizontalPosition(from, true) - 2;
        const right = l.getHorizontalPosition(to, true) + 2;
        const y = l.getLineBaseline(line) + 4;
        const p = standard(Math.min(1, Math.max(0, (mark.drawn - i * STROKE_GAP_MS) / STROKE_MS)));
        i++;
        if (p <= 0) continue;
        const w = right - left;
        const p0 = { x: left, y };
        const p1 = { x: left + w * 0.25, y: y - 3 };
        const p2 = { x: left + w * 0.55, y: y + 2 };
        const p3 = { x: right, y: y - 2 };
        // The stroke's first `p` of its length (PathMeasure.getSegment there): the curve sampled, cut where it reaches it.
        const pts = Array.from({ length: 33 }, (_, k) => cubic(p0, p1, p2, p3, k / 32));
        const lengths = [0];
        for (let k = 1; k < pts.length; k++) lengths.push(lengths[k - 1]! + Math.hypot(pts[k]!.x - pts[k - 1]!.x, pts[k]!.y - pts[k - 1]!.y));
        const goal = lengths[lengths.length - 1]! * p;
        let d = `M${p0.x} ${p0.y}`;
        for (let k = 1; k < pts.length; k++) {
          if (lengths[k]! <= goal) { d += `L${pts[k]!.x} ${pts[k]!.y}`; continue; }
          const f = (goal - lengths[k - 1]!) / Math.max(1e-6, lengths[k]! - lengths[k - 1]!);
          d += `L${pts[k - 1]!.x + (pts[k]!.x - pts[k - 1]!.x) * f} ${pts[k - 1]!.y + (pts[k]!.y - pts[k - 1]!.y) * f}`;
          break;
        }
        shapes.push(<Path key={`s${i}-${line}`} d={d} stroke={mark.color} strokeWidth={width} strokeLinecap="round" fill="none" />);
      }
    }
  } else if (mark.level > 0) {
    // A rounded ground on each of its lines, as tall as the words (not the line: lines apart stay apart),
    // a little past their ends.
    const em = l.fontSize;
    const pad = 3;
    for (const r of ranges) {
      if (r.last >= l.text.length) continue;
      for (let line = l.getLineForOffset(r.first); line <= l.getLineForOffset(r.last); line++) {
        const from = Math.max(r.first, l.getLineStart(line));
        const to = Math.min(r.last + 1, l.getLineEnd(line, true));
        if (to <= from) continue;
        const mid = l.getLineBaseline(line) - em * 0.36;
        const box = {
          left: l.getBoundingBox(from).left - pad, top: Math.max(l.getLineTop(line), mid - em * 0.72),
          right: l.getBoundingBox(to - 1).right + pad, bottom: Math.min(l.getLineBottom(line), mid + em * 0.72),
        };
        // drawSmooth's 5dp corner (a superellipse over a radius a quarter longer), as a round one that long.
        shapes.push(<SvgRect key={`g${r.first}-${line}`} x={box.left} y={box.top} width={box.right - box.left} height={box.bottom - box.top} rx={5 * SMOOTH_SCALE} ry={5 * SMOOTH_SCALE} fill={withAlpha(mark.color, mark.level)} />);
      }
    }
  }
  if (shapes.length === 0) return null;
  return <Svg style={{ position: "absolute", left: -8, top: 0 }} width={l.size.width + 16} height={l.size.height + 8} viewBox={`-8 0 ${l.size.width + 16} ${l.size.height + 8}`}>{shapes}</Svg>;
}

/**
 * The hook for a text that may hold the marked passage: what to put on the text (it draws behind the range) and what
 * to give the text's onTextLayout. Nothing when no mark is asked for or the text does not hold it.
 */
export function passageMark(text: string): TextHook {
  const mark = useContext(LocalTextMark);
  const ranges = useMemo(
    () => (mark == null ? [] : mark.words.length > 0 ? findWords(text, mark.words) : [findPassage(text, mark.needle)].filter((r): r is IntRange => r != null)),
    [text, mark, mark?.needle, mark?.words],
  );
  const [layout, laid] = useLaidOut(text);
  const view = useRef<View | null>(null);
  const first = ranges[0];
  // Where the marked range was laid out: the first text that holds it keeps it, unless that one is gone.
  const place = () => {
    const v = view.current;
    if (!mark || !first || !layout || !v) return;
    if (mark.where == null || mark.where.view === v) mark.where = { view: v, box: layout.getPathBounds(first.first, first.last + 1) };
  };
  useEffect(() => { if (mark && ranges.length > 0 && !mark.found) mark.found = true; }, [mark, ranges]);
  useEffect(place, [mark, first, layout]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => { if (mark && view.current && mark.where?.view === view.current) mark.where = null; }, [mark]);
  if (mark == null || ranges.length === 0) return noHook();
  return [
    {
      behind: (
        <TextBox view={(v) => { view.current = v; place(); }}>
          {layout && <MarkBehind mark={mark} ranges={ranges} layout={layout} />}
        </TextBox>
      ),
    },
    laid,
  ];
}

/** `text` with a search's words (the mark's, if any) in bold, as they are marked (web ::highlight(search-hit)). */
export function markWeight(text: AnnotatedString): AnnotatedString {
  const mark = useContext(LocalTextMark);
  const words = mark?.words ?? [];
  const ranges = useMemo(() => (words.length === 0 ? [] : findWords(text.text, words)), [text.text, words]);
  return useMemo(() => {
    if (ranges.length === 0) return text;
    const spans = [...text.spanStyles, ...ranges.map((r) => ({ item: { fontWeight: "600" as const }, start: r.first, end: r.last + 1 }))];
    return new AnnotatedString(text.text, spans, text.links, text.inlines);
  }, [text, ranges]);
}

/**
 * The marked range's middle, in `pane`'s place (null until laid out). Measured, so it is answered a moment later (the
 * Android app reads its layout's coordinates at once).
 */
export function middleIn(mark: TextMark, pane: View): Promise<Offset | null> {
  const where = mark.where;
  if (!where) return Promise.resolve(null);
  return new Promise((resolve) => {
    where.view.measureLayout(
      pane,
      (x, y) => resolve({ x: x + (where.box.left + where.box.right) / 2, y: y + (where.box.top + where.box.bottom) / 2 }),
      () => resolve(null),
    );
  });
}
