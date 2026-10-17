// Marking an image opened in a preview (web/src/annotate/ImageMarks.tsx): boxes, arrows, lines drawn by hand and
// words, drawn on the image where it is shown (zoomed and panned with it); picked again to move, stretch, recolour or
// remove; undo and redo. Boxes and arrows are numbered: a pin on each, and something said about it in a bubble beside
// it. Done, the image with its marks (and their pins), drawn again at its own size, goes into the chat's draft as a
// new file with a quote per numbered mark, or is downloaded.
//
// The marks are drawn with Skia (@shopify/react-native-skia), the same canvas, paints and paths the Android app draws
// them with: on the screen by the viewer (FilePreview.tsx, a Skia canvas over the picture) and, done, on the image at
// its own size (`render`).
import { ImageFormat, matchFont, PaintStyle, Skia, StrokeCap, StrokeJoin, type SkCanvas, type SkFont, type SkPath } from "@shopify/react-native-skia";
import { requireOptionalNativeModule } from "expo";
import * as LegacyFS from "expo-file-system/legacy";
import { useEffect, useRef, useSyncExternalStore, type ComponentType, type ReactNode } from "react";
import { Pressable, ScrollView, Text, TextInput, View, type StyleProp, type ViewStyle } from "react-native";
import Animated, { useAnimatedStyle } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Smooth } from "../ui/Smooth";
import { StillFailTheme } from "../ui/Theme";
import type { Strokes, ZoomState } from "../ui/Zoom";
import { Picked, uriSource } from "./Composer";
import { Card, NoteBox, type NoteLike } from "./Notes";
import { OfferQuote } from "./Preview";
import { keyboard } from "../ui/Keyboard";

/** A point (Offset there), in the image's pixels or on the stage. */
export interface Offset { x: number; y: number }
/** A size in whole pixels (IntSize there). */
export interface IntSize { width: number; height: number }

const add = (a: Offset, b: Offset): Offset => ({ x: a.x + b.x, y: a.y + b.y });
const hypot = Math.hypot;
const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

export enum MarkTool { Select = "Select", Rect = "Rect", Arrow = "Arrow", Pen = "Pen", Text = "Text" }
export const markToolLabel = (tool: MarkTool): string => t("android-chat.marks.tool." + tool.toLowerCase());

/** still.fail's accent, what is drawn on an image by default (literal: the viewer is dark whatever the theme). */
export const INK = "#E5704A";

/** The colours to draw in; words get an edge of `halo` to stand out on any picture. */
const COLORS: [string, string][] = [
  [INK, "#FFFFFF"], ["#E5484D", "#FFFFFF"], ["#F5C518", "#111111"], ["#30A46C", "#FFFFFF"],
  ["#3E7BFA", "#FFFFFF"], ["#FFFFFF", "#111111"], ["#111111", "#FFFFFF"],
];
const haloOf = (color: string) => COLORS.find((c) => c[0] === color)?.[1] ?? "#FFFFFF";

/** On the screen, whatever the zoom (dp): a line's width, a text's size, how near a finger picks a mark. */
const LINE = 3;
const TEXT = 18;
const REACH = 12;
const LINE_HEIGHT = 1.3;
const BASELINE = 0.98;

/** A mark, in the image's own pixels. `w`: its line (a text's size), set by the zoom when drawn, so it looks the same on the screen. */
export type ImageMark =
  | { kind: "Box"; id: number; color: string; w: number; a: Offset; b: Offset }
  | { kind: "Arrow"; id: number; color: string; w: number; a: Offset; b: Offset }
  | { kind: "Pen"; id: number; color: string; w: number; points: Offset[] }
  | { kind: "Words"; id: number; color: string; w: number; at: Offset; text: string };

const recolored = (s: ImageMark, c: string): ImageMark => ({ ...s, color: c });

/** The face words are drawn in: the system's sans at 600 (Typeface.create(DEFAULT, 600) there), by size. */
const fonts = new Map<number, SkFont>();
function fontOf(size: number, weight: "600" | "700" = "600"): SkFont {
  const key = size * 10 + (weight === "700" ? 1 : 0);
  let f = fonts.get(key);
  if (!f) {
    f = matchFont({ fontFamily: "sans-serif", fontSize: size, fontWeight: weight });
    if (fonts.size > 64) fonts.clear();
    fonts.set(key, f);
  }
  return f;
}

/** How wide words are in the size `w`. */
const measure = (text: string, w: number): number => fontOf(w).measureText(text).width;

interface MarkBox { x: number; y: number; w: number; h: number }

function boxOf(s: ImageMark): MarkBox {
  if (s.kind === "Words") return { x: s.at.x, y: s.at.y, w: measure(s.text, s.w), h: s.w * LINE_HEIGHT };
  const pts = s.kind === "Pen" ? s.points : [s.a, s.b];
  const x = Math.min(...pts.map((p) => p.x)), y = Math.min(...pts.map((p) => p.y));
  return { x, y, w: Math.max(...pts.map((p) => p.x)) - x, h: Math.max(...pts.map((p) => p.y)) - y };
}

/** An arrow's head: its two barbs, back from its point. */
function barbs(a: Offset, b: Offset, w: number): [Offset, Offset] {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len = hypot(dx, dy) > 0 ? hypot(dx, dy) : 1;
  const ux = dx / len, uy = dy / len, size = Math.min(w * 5, len * 0.6), spread = 0.5;
  const back = { x: b.x - ux * size, y: b.y - uy * size };
  return [{ x: back.x - uy * size * spread, y: back.y + ux * size * spread }, { x: back.x + uy * size * spread, y: back.y - ux * size * spread }];
}

/** A rectangle with each corner its own radius (top left, top right, bottom right, bottom left), as a path. */
function roundRect(path: SkPath, x0: number, y0: number, x1: number, y1: number, r: [number, number, number, number]) {
  const [tl, tr, br, bl] = r;
  path.moveTo(x0 + tl, y0);
  path.lineTo(x1 - tr, y0);
  if (tr > 0) path.arcToTangent(x1, y0, x1, y0 + tr, tr);
  path.lineTo(x1, y1 - br);
  if (br > 0) path.arcToTangent(x1, y1, x1 - br, y1, br);
  path.lineTo(x0 + bl, y1);
  if (bl > 0) path.arcToTangent(x0, y1, x0, y1 - bl, bl);
  path.lineTo(x0, y0 + tl);
  if (tl > 0) path.arcToTangent(x0, y0, x0 + tl, y0, tl);
  path.close();
}

function pathOf(s: ImageMark): SkPath {
  const path = Skia.Path.Make();
  switch (s.kind) {
    case "Box": {
      const b = boxOf(s);
      const r = Math.min(s.w * 1.5, Math.min(b.w / 2, b.h / 2));
      roundRect(path, b.x, b.y, b.x + b.w, b.y + b.h, [r, r, r, r]);
      break;
    }
    case "Arrow": {
      const [l, r] = barbs(s.a, s.b, s.w);
      path.moveTo(s.a.x, s.a.y); path.lineTo(s.b.x, s.b.y); path.moveTo(l.x, l.y); path.lineTo(s.b.x, s.b.y); path.lineTo(r.x, r.y);
      break;
    }
    case "Pen": {
      const p = s.points;
      path.moveTo(p[0]!.x, p[0]!.y);
      if (p.length < 3) p.slice(1).forEach((q) => path.lineTo(q.x, q.y));
      else {
        // Through the midpoints, each point bending the line: smooth, however jerky the finger.
        for (let i = 1; i < p.length - 1; i++) path.quadTo(p[i]!.x, p[i]!.y, (p[i]!.x + p[i + 1]!.x) / 2, (p[i]!.y + p[i + 1]!.y) / 2);
        path.lineTo(p[p.length - 1]!.x, p[p.length - 1]!.y);
      }
      break;
    }
    case "Words": break;
  }
  return path;
}

/** A box or an arrow: numbered, with something said about it. */
const numbered = (s: ImageMark) => s.kind === "Box" || s.kind === "Arrow";

/** The numbered marks' numbers, in the order they were drawn (one removed, those after it move up). */
function numbersOf(marks: ImageMark[]): Map<number, number> {
  const m = new Map<number, number>();
  marks.filter(numbered).forEach((s, i) => m.set(s.id, i + 1));
  return m;
}

/**
 * Where a numbered mark's pin points (a box's top-left corner, an arrow's tail), in the image's pixels, kept in the
 * image (`natural`) whole: the pin, 24 by 24 at `k` image px a dp, sits up and to the right of its point.
 */
function pinPoint(s: ImageMark, natural: IntSize, k: number): Offset {
  const p = s.kind === "Box" ? (() => { const b = boxOf(s); return { x: b.x, y: b.y }; })() : s.kind === "Arrow" ? s.a : { x: 0, y: 0 };
  return { x: clamp(p.x, 2 * k, Math.max(2 * k, natural.width - 22 * k)), y: clamp(p.y, 22 * k, Math.max(22 * k, natural.height - 2 * k)) };
}

/** A shadow's blur radius as Android's setShadowLayer takes it, as Skia's sigma. */
const sigmaOf = (radius: number) => (radius > 0 ? radius * 0.57735 + 0.5 : 0);

/** The numbered marks' pins, as they show while marking (web's ImageMarks.tsx render): the mark's colour, edged and numbered in its halo. */
function drawPins(canvas: SkCanvas, marks: ImageMark[], natural: IntSize) {
  for (const [id, n] of numbersOf(marks)) {
    const s = marks.find((m) => m.id === id)!;
    const k = s.w / LINE;
    const p = pinPoint(s, natural, k);
    const x = p.x - 2 * k, y = p.y - 22 * k, size = 24 * k, edge = 2 * k;
    const shape = (inset: number, r: number, point: number) => {
      const path = Skia.Path.Make();
      roundRect(path, x + inset, y + inset, x + size - inset, y + size - inset, [r, r, r, point]);
      return path;
    };
    const halo = haloOf(s.color);
    const paint = Skia.Paint();
    paint.setAntiAlias(true);
    paint.setColor(Skia.Color(halo));
    paint.setImageFilter(Skia.ImageFilter.MakeDropShadow(0, 2 * k, sigmaOf(3 * k), sigmaOf(3 * k), Skia.Color("rgba(0,0,0,0.2196)"), null));
    canvas.drawPath(shape(0, 12 * k, 3 * k), paint);
    paint.setImageFilter(null);
    paint.setColor(Skia.Color(s.color));
    canvas.drawPath(shape(edge, 10 * k, 1.5 * k), paint);
    // 650 there: Skia's system faces come by the hundred, the nearest below.
    const font = fontOf(11 * k);
    const text = Skia.Paint();
    text.setAntiAlias(true);
    text.setColor(Skia.Color(halo));
    const m = font.getMetrics();
    const mid = y + size / 2 - (m.descent + m.ascent) / 2;
    const words = `${n}`;
    canvas.drawText(words, x + size / 2 - font.measureText(words).width / 2, mid, text, font);
  }
}

/** The marks drawn on `canvas`, in the image's pixels; with `pinned` (the image's size), the numbered ones' pins over them. */
export function drawMarks(canvas: SkCanvas, marks: ImageMark[], pinned: IntSize | null = null) {
  for (const s of marks) {
    if (s.kind === "Words") {
      const font = fontOf(s.w);
      const edge = Skia.Paint();
      edge.setAntiAlias(true);
      edge.setStyle(PaintStyle.Stroke); edge.setStrokeWidth(s.w * 0.22); edge.setStrokeJoin(StrokeJoin.Round);
      edge.setColor(Skia.Color(haloOf(s.color)));
      canvas.drawText(s.text, s.at.x, s.at.y + s.w * BASELINE, edge, font);
      const fill = Skia.Paint();
      fill.setAntiAlias(true);
      fill.setColor(Skia.Color(s.color));
      canvas.drawText(s.text, s.at.x, s.at.y + s.w * BASELINE, fill, font);
    } else {
      const line = Skia.Paint();
      line.setAntiAlias(true);
      line.setStyle(PaintStyle.Stroke); line.setStrokeCap(StrokeCap.Round); line.setStrokeJoin(StrokeJoin.Round);
      line.setColor(Skia.Color(s.color)); line.setStrokeWidth(s.w);
      canvas.drawPath(pathOf(s), line);
    }
  }
  if (pinned != null) drawPins(canvas, marks, pinned);
}

function moved(s: ImageMark, dx: number, dy: number): ImageMark {
  const d = { x: dx, y: dy };
  switch (s.kind) {
    case "Words": return { ...s, at: add(s.at, d) };
    case "Pen": return { ...s, points: s.points.map((p) => add(p, d)) };
    case "Box": case "Arrow": return { ...s, a: add(s.a, d), b: add(s.b, d) };
  }
}

/** Stretched from `anchor` by (sx, sy) (words: evenly, by sx). */
function scaled(s: ImageMark, anchor: Offset, sx: number, sy: number): ImageMark {
  const m = (p: Offset): Offset => ({ x: anchor.x + (p.x - anchor.x) * sx, y: anchor.y + (p.y - anchor.y) * sy });
  switch (s.kind) {
    case "Words": { const k = Math.max(0.2, Math.abs(sx)); return { ...s, w: s.w * k, at: { x: anchor.x + (s.at.x - anchor.x) * k, y: anchor.y + (s.at.y - anchor.y) * k } }; }
    case "Pen": return { ...s, points: s.points.map(m) };
    case "Box": case "Arrow": return { ...s, a: m(s.a), b: m(s.b) };
  }
}

/** A handle of a picked mark: a corner of its box (the opposite one stays), or an end of an arrow. */
type MarkHandle = { kind: "Corner"; cx: number; cy: number } | { kind: "End"; b: boolean };

function handles(s: ImageMark): [MarkHandle, Offset][] {
  if (s.kind === "Arrow") return [[{ kind: "End", b: false }, s.a], [{ kind: "End", b: true }, s.b]];
  const b = boxOf(s);
  const corners: [number, number][] = s.kind === "Words" ? [[1, 1]] : [[0, 0], [1, 0], [0, 1], [1, 1]];
  return corners.map(([cx, cy]) => [{ kind: "Corner", cx, cy }, { x: b.x + cx * b.w, y: b.y + cy * b.h }]);
}

function segment(p: Offset, a: Offset, b: Offset): number {
  const dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
  const t = l2 === 0 ? 0 : clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0, 1);
  return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

/** How far `p` is from the mark's line (words: 0 inside their box). */
function distance(s: ImageMark, p: Offset): number {
  switch (s.kind) {
    case "Words": { const b = boxOf(s); return p.x >= b.x && p.x <= b.x + b.w && p.y >= b.y && p.y <= b.y + b.h ? 0 : Number.MAX_VALUE; }
    case "Arrow": { const [l, r] = barbs(s.a, s.b, s.w); return Math.min(segment(p, s.a, s.b), segment(p, l, s.b), segment(p, r, s.b)); }
    case "Pen": {
      if (s.points.length === 1) return hypot(p.x - s.points[0]!.x, p.y - s.points[0]!.y);
      let least = Number.MAX_VALUE;
      for (let i = 0; i + 1 < s.points.length; i++) least = Math.min(least, segment(p, s.points[i]!, s.points[i + 1]!));
      return least;
    }
    case "Box": {
      const b = boxOf(s);
      const c = [{ x: b.x, y: b.y }, { x: b.x + b.w, y: b.y }, { x: b.x + b.w, y: b.y + b.h }, { x: b.x, y: b.y + b.h }];
      const ring = [...c, c[0]!];
      let least = Number.MAX_VALUE;
      for (let i = 0; i + 1 < ring.length; i++) least = Math.min(least, segment(p, ring[i]!, ring[i + 1]!));
      return least;
    }
  }
}

/** Words being written: new ones, or those of the text `id` again. */
class MarkWriting {
  constructor(readonly id: number | null, readonly at: Offset, readonly text: string, readonly w: number, readonly color: string) {}
  with({ text = this.text, color = this.color }: { text?: string; color?: string }) { return new MarkWriting(this.id, this.at, text, this.w, color); }
}

type MarkDrag =
  | { kind: "Draw"; shape: ImageMark }
  | { kind: "Move"; id: number; from: Offset; orig: ImageMark; handle: MarkHandle | null; before: ImageMark[]; changed: boolean };

interface MarkDoc { shapes: ImageMark[]; past: ImageMark[][]; future: ImageMark[][] }

/** How tall a note's box at the foot is, and the room over it (dp). */
const NOTE_BOX = 140;
/** What is read into memory to be sent (Composer.tsx IN_MEMORY): a bigger one goes up from its file as it is read. */
const MAX_MARKED = 16 * 1024 * 1024;

/** What puts a file into the phone's Downloads (MediaStore.Downloads there). */
interface DownloadsModule { save(uri: string, name: string, mime: string): Promise<boolean> }
// NATIVE: a module that copies a file into the phone's Downloads through MediaStore.Downloads (no dialog, as the
// Android app does): `StillfailDownloads.save(uri, name, mime)`; until it is there, a marked image cannot be downloaded.
const Downloads = requireOptionalNativeModule<DownloadsModule>("StillfailDownloads");

/**
 * Marking one image, zoomed by `zoom` (`density`: the zoom's units a dp, 1 where it works in dp as React Native lays
 * out). What it holds is watched (`useImageMarks`): whatever reads it draws again as it changes.
 */
export class ImageMarks implements Strokes {
  readonly #listeners = new Set<() => void>();
  #version = 0;
  #changed() { this.#version++; for (const l of this.#listeners) l(); }
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }

  #on = false;
  #tool = MarkTool.Rect;
  #color = INK;
  #palette = false;
  #doc: MarkDoc = { shapes: [], past: [], future: [] };
  #picked: number | null = null;
  #drag: MarkDrag | null = null;
  #writing: MarkWriting | null = null;
  /** What is said about each numbered mark (by its id; kept apart from the marks, so undoing a move keeps it), and the one whose bubble is open. */
  readonly #comments = new Map<number, string>();
  #note: number | null = null;
  #busy = false;
  #error: string | null = null;
  #nextId = 1;
  #lastDown: [number, number] = [0, 0];
  /** The last marked image made, on the disk (it may be bigger than is kept in memory). */
  #made: string | null = null;

  constructor(private readonly zoom: ZoomState, private readonly density: number) {}

  get on() { return this.#on; }
  get tool() { return this.#tool; }
  get color() { return this.#color; }
  get palette() { return this.#palette; }
  set palette(v: boolean) { this.#palette = v; this.#changed(); }
  get shapes() { return this.#doc.shapes; }
  get canUndo() { return this.#doc.past.length > 0; }
  get canRedo() { return this.#doc.future.length > 0; }
  get picked() { return this.#picked; }
  get busy() { return this.#busy; }
  set busy(v: boolean) { this.#busy = v; this.#changed(); }
  get error() { return this.#error; }
  set error(v: string | null) { this.#error = v; this.#changed(); }

  get any() { return this.shapes.length > 0 || (this.#writing?.text.trim() ?? "") !== ""; }
  get pickedShape(): ImageMark | null { const id = this.#picked; return id == null ? null : this.shapes.find((s) => s.id === id) ?? null; }
  get shownColor() { return this.#writing?.color ?? this.pickedShape?.color ?? this.#color; }

  #setDoc(d: MarkDoc) { this.#doc = d; this.#changed(); }

  start() { this.#on = true; this.#error = null; this.#changed(); }

  leave() {
    this.#on = false; this.#doc = { shapes: [], past: [], future: [] }; this.#picked = null; this.#drag = null; this.#writing = null; this.#error = null; this.#palette = false;
    this.#comments.clear(); this.#note = null;
    if (this.#made) void LegacyFS.deleteAsync(this.#made, { idempotent: true }).catch(() => undefined);
    this.#made = null;
    this.#changed();
  }

  /** Back: closes a mark's bubble, puts down the words being written, closes the colours, lets go of the picked mark, else stops marking. */
  back() {
    if (this.#note != null) { this.#note = null; this.#changed(); }
    else if (this.#writing != null) this.putDown();
    else if (this.#palette) this.palette = false;
    else if (this.#picked != null) { this.#picked = null; this.#changed(); }
    else this.leave();
  }

  #commit(next: ImageMark[], before: ImageMark[] | null = null) {
    const d = this.#doc;
    this.#setDoc({ shapes: next, past: [...d.past, before ?? d.shapes], future: [] });
  }

  undo() {
    const d = this.#doc;
    if (d.past.length > 0) this.#doc = { shapes: d.past[d.past.length - 1]!, past: d.past.slice(0, -1), future: [d.shapes, ...d.future] };
    this.#picked = null; this.#note = null;
    this.#changed();
  }

  redo() {
    const d = this.#doc;
    if (d.future.length > 0) this.#doc = { shapes: d.future[0]!, past: [...d.past, d.shapes], future: d.future.slice(1) };
    this.#picked = null; this.#note = null;
    this.#changed();
  }

  remove(id: number) { this.#commit(this.shapes.filter((s) => s.id !== id)); this.#picked = null; this.#note = null; this.#changed(); }

  /** The words being written, put down (all of them gone: the text they were, removed). */
  putDown() {
    const w = this.#writing;
    if (!w) return;
    this.#writing = null;
    this.#changed();
    const text = w.text.trim();
    if (w.id != null) {
      const was = this.shapes.find((s) => s.id === w.id);
      if (!was || was.kind !== "Words") return;
      if (was.text === text && was.color === w.color) return;
      this.#commit(text !== "" ? this.shapes.map((s) => (s.id === w.id ? { kind: "Words", id: was.id, color: w.color, w: was.w, at: was.at, text } : s)) : this.shapes.filter((s) => s.id !== w.id));
    } else if (text !== "") this.#commit([...this.shapes, { kind: "Words", id: this.#nextId++, color: w.color, w: w.w, at: w.at, text }]);
  }

  pickTool(tool: MarkTool) { this.putDown(); this.#note = null; this.#tool = tool; if (tool !== MarkTool.Select) this.#picked = null; this.#changed(); }

  /** A colour to draw in next; the picked mark (or the words being written) takes it at once. */
  pickColor(c: string) {
    this.#color = c;
    this.#palette = false;
    const w = this.#writing;
    const id = this.#picked;
    if (w != null) this.#writing = w.with({ color: c });
    else if (id != null) this.#commit(this.shapes.map((s) => (s.id === id ? recolored(s, c) : s)));
    this.#changed();
  }

  #edit(s: Extract<ImageMark, { kind: "Words" }>) { this.#picked = null; this.#writing = new MarkWriting(s.id, s.at, s.text, s.w, s.color); this.#changed(); }

  // ── a finger on the image (ui/Zoom.tsx's Strokes) ──

  down(at: Offset) {
    if (this.zoom.natural == null) return;
    this.#palette = false;
    if (this.#writing != null) { this.putDown(); return; }
    if (this.#note != null) { this.#note = null; this.#changed(); return; }
    const p = this.zoom.toPicture(at);
    const reach = REACH / this.zoom.scale;
    const tool = this.#tool;
    if (tool === MarkTool.Select || tool === MarkTool.Text) {
      // The picked mark's handles first, then the marks, the topmost first.
      const ps = this.pickedShape;
      if (tool === MarkTool.Select && ps != null) {
        const h = handles(ps).find(([, q]) => hypot(q.x - p.x, q.y - p.y) < reach * 1.4);
        if (h) { this.#markDown(ps, p, h[0]); return; }
      }
      const hit = [...this.shapes].reverse().find((s) => s.id !== this.#writing?.id && (tool === MarkTool.Select || s.kind === "Words") && distance(s, p) <= s.w / 2 + reach);
      if (hit) { this.#markDown(hit, p, null); return; }
      if (tool === MarkTool.Select) { this.#picked = null; this.#changed(); return; }
      const w = TEXT / this.zoom.scale;
      this.#writing = new MarkWriting(null, { x: p.x, y: p.y - w * 0.65 }, "", w, this.#color);
      this.#changed();
      return;
    }
    const w = LINE / this.zoom.scale;
    const id = this.#nextId++;
    const color = this.#color;
    this.#drag = { kind: "Draw", shape: tool === MarkTool.Pen ? { kind: "Pen", id, color, w, points: [p] } : tool === MarkTool.Arrow ? { kind: "Arrow", id, color, w, a: p, b: p } : { kind: "Box", id, color, w, a: p, b: p } };
    this.#changed();
  }

  #markDown(s: ImageMark, p: Offset, handle: MarkHandle | null) {
    // Words pressed twice are written again.
    const now = Date.now();
    const again = this.#lastDown[0] === s.id && now - this.#lastDown[1] < 400;
    this.#lastDown = [s.id, now];
    if (s.kind === "Words" && (this.#tool === MarkTool.Text || (again && handle == null))) { this.putDown(); this.#edit(s); return; }
    this.#picked = s.id;
    this.#drag = { kind: "Move", id: s.id, from: p, orig: s, handle, before: this.shapes, changed: false };
    this.#changed();
  }

  move(at: Offset) {
    const d = this.#drag;
    if (!d) return;
    const p = this.zoom.toPicture(at);
    if (d.kind === "Draw") {
      const s = d.shape;
      this.#drag = { kind: "Draw", shape: s.kind === "Pen" ? { ...s, points: [...s.points, p] } : s.kind === "Box" || s.kind === "Arrow" ? { ...s, b: p } : s };
      this.#changed();
      return;
    }
    const o = d.orig;
    const h = d.handle;
    let next: ImageMark;
    if (h == null) next = moved(o, p.x - d.from.x, p.y - d.from.y);
    else if (h.kind === "End") next = o.kind === "Arrow" ? (h.b ? { ...o, b: p } : { ...o, a: p }) : o;
    else {
      const b = boxOf(o);
      const anchor = { x: b.x + (1 - h.cx) * b.w, y: b.y + (1 - h.cy) * b.h };
      const corner = { x: b.x + h.cx * b.w, y: b.y + h.cy * b.h };
      const ratio = (to: number, from: number, a: number) => (Math.abs(from - a) < 1e-6 ? 1 : (to - a) / (from - a));
      next = scaled(o, anchor, ratio(p.x, corner.x, anchor.x), ratio(p.y, corner.y, anchor.y));
    }
    const cur = this.#doc;
    this.#doc = { shapes: cur.shapes.map((s) => (s.id === d.id ? next : s)), past: cur.past, future: cur.future };
    if (!d.changed) this.#drag = { ...d, changed: true };
    this.#changed();
  }

  up() {
    const d = this.#drag;
    if (!d) return;
    this.#drag = null;
    if (d.kind === "Draw") {
      // A tap, not a drag: nothing drawn.
      const s = d.shape;
      if (s.kind === "Words") { this.#changed(); return; }
      const first = s.kind === "Pen" ? s.points[0]! : s.a;
      const rest = s.kind === "Pen" ? s.points : [s.b];
      if (rest.some((q) => hypot(q.x - first.x, q.y - first.y) > 4 / this.zoom.scale)) {
        this.#commit([...this.shapes, s]);
        // A box or an arrow, drawn: what to say about it, at once.
        if (numbered(s)) this.#note = s.id;
      }
    } else if (d.changed) {
      const cur = this.#doc;
      this.#doc = { shapes: cur.shapes, past: [...cur.past, d.before], future: [] };
    }
    this.#changed();
  }

  cancel() {
    const d = this.#drag;
    if (d?.kind === "Move" && d.changed) { const cur = this.#doc; this.#doc = { shapes: d.before, past: cur.past, future: cur.future }; }
    this.#drag = null;
    this.#changed();
  }

  /** All the marks as they show, the words still being written included. */
  all(): ImageMark[] {
    const w = this.#writing;
    const text = w?.text.trim() ?? "";
    let all = this.shapes;
    if (w != null && text !== "") {
      all = w.id != null ? all.map((s) => (s.id === w.id && s.kind === "Words" ? { ...s, color: w.color, text } : s)) : [...all, { kind: "Words", id: -1, color: w.color, w: w.w, at: w.at, text }];
    }
    return all;
  }

  /** What is drawn now over the image: the marks, the one being drawn, not the words being written. */
  drawn(): ImageMark[] {
    const d = this.#drag;
    const list = d?.kind === "Draw" ? [...this.shapes, d.shape] : this.shapes;
    return list.filter((s) => s.id !== this.#writing?.id);
  }

  /** The picked mark's dashed box and handles, over the marks (`k`: screen units per image px). */
  drawPicked(canvas: SkCanvas, k: number) {
    const s = this.pickedShape;
    if (!s || this.#tool !== MarkTool.Select) return;
    const density = this.density;
    const reach = (REACH / 2) * density / k;
    const paint = Skia.Paint();
    paint.setAntiAlias(true); paint.setStyle(PaintStyle.Stroke); paint.setColor(Skia.Color("rgba(255,255,255,0.851)")); paint.setStrokeWidth(density / k);
    if (s.kind !== "Arrow") {
      const b = boxOf(s);
      paint.setPathEffect(Skia.PathEffect.MakeDash([4 * density / k, 3 * density / k], 0));
      canvas.drawRect(Skia.XYWHRect(b.x - reach, b.y - reach, b.w + 2 * reach, b.h + 2 * reach), paint);
    }
    const fill = Skia.Paint();
    fill.setAntiAlias(true); fill.setColor(Skia.Color("#FFFFFF"));
    const ring = Skia.Paint();
    ring.setAntiAlias(true); ring.setStyle(PaintStyle.Stroke); ring.setColor(Skia.Color(INK)); ring.setStrokeWidth(1.5 * density / k);
    for (const [h, at] of handles(s)) {
      const c = h.kind === "Corner" ? { x: at.x + (h.cx === 1 ? 1 : -1) * reach, y: at.y + (h.cy === 1 ? 1 : -1) * reach } : at;
      canvas.drawCircle(c.x, c.y, 6 * density / k, fill);
      canvas.drawCircle(c.x, c.y, 6 * density / k, ring);
    }
  }

  /** Where the words being written (or the open bubble) end on the stage (the zoom's units), to keep them clear of the keyboard; null when none are. */
  writingBottom(): number | null {
    const r = this.zoom.rect();
    if (!r) return null;
    const id = this.#note;
    if (id != null) {
      const s = this.shapes.find((m) => m.id === id);
      const natural = this.zoom.natural;
      if (!s || !natural) return null;
      // Its box is at the foot, over the keyboard: the mark's pin kept above it.
      return r.top + pinPoint(s, natural, this.density / this.zoom.k).y * this.zoom.k + NOTE_BOX * this.density;
    }
    const w = this.#writing;
    if (!w) return null;
    return r.top + (w.at.y + w.w * LINE_HEIGHT) * this.zoom.k;
  }

  /** A quote per numbered mark of `all` (on the image `made`, of `natural` size, from `original`): where it is, for the agent (the first line is also what the composer shows), and what was said. */
  quotes(all: ImageMark[], made: string, original: string, natural: IntSize): OfferQuote[] {
    return [...numbersOf(all)].map(([id, n]) => {
      const s = all.find((m) => m.id === id)!;
      const r = Math.round;
      const what = s.kind === "Box"
        ? (() => { const b = boxOf(s); return t("android-chat.marks.box.where", { x: r(b.x), y: r(b.y), w: r(b.w), h: r(b.h) }); })()
        : s.kind === "Arrow" ? t("android-chat.marks.arrow.where", { ax: r(s.a.x), ay: r(s.a.y), bx: r(s.b.x), by: r(s.b.y) }) : "";
      return new OfferQuote(
        t("android-chat.marks.quote.title", { original, n }),
        what + "\n" + t("android-chat.marks.quote.on", { made, width: natural.width, height: natural.height, original, n }),
        (this.#comments.get(id) ?? "").trim(), null, "image",
      );
    });
  }

  /** The numbered marks' notes, in their numbers' order. */
  notes(): ImageNote[] {
    return [...numbersOf(this.shapes)].map(([id, n]) => {
      const s = this.shapes.find((m) => m.id === id)!;
      return new ImageNote(this, id, n, s.kind === "Box" ? t("android-chat.marks.note.box") : t("android-chat.marks.note.arrow"), s.color);
    });
  }

  /** What is said about a numbered mark. */
  commentOf(id: number): string { return this.#comments.get(id) ?? ""; }
  setComment(id: number, v: string) { this.#comments.set(id, v); this.#changed(); }

  /** The note being written, if one is. */
  get openNote(): ImageNote | null { const id = this.#note; return id == null ? null : this.notes().find((x) => x.id === id) ?? null; }
  /** The mark whose bubble is open. */
  get note(): number | null { return this.#note; }

  /** Opens the note of the mark `id` (none: closes it). */
  open(id: number | null) { this.putDown(); this.#picked = null; this.#note = id; this.#changed(); }

  /** The words being written, if they are. */
  get writing(): MarkWriting | null { return this.#writing; }
  setWriting(text: string) { const w = this.#writing; if (w) { this.#writing = w.with({ text }); this.#changed(); } }

  /**
   * The numbered marks' pins where they are on the screen, each at its own size whatever the zoom (as a page's
   * marks show theirs). A tap on a pin opens its note.
   */
  Pins = () => <MarksPins marks={this} zoom={this.zoom} density={this.density} />;

  /** The words being written, where they go on the screen, in their size and colour. */
  WritingField = () => <MarksWriting marks={this} zoom={this.zoom} density={this.density} />;

  /**
   * The image (its whole bytes) with the marks drawn on it, as a PNG at its own size, as web's (a canvas of the
   * image's size, `toBlob("image/png")`), with its size and a small picture. Drawn by Skia on a surface of the image's
   * size and encoded there (the Android app reads it in bands and writes the PNG a row at a time, never holding it
   * whole: Skia here holds the image whole while it draws). It is kept in a file; its bytes come in memory only up to
   * [MAX_MARKED]: a bigger one is handed on to be read from that file as it goes up, and [save] puts it in Downloads.
   */
  async render(bytes: Uint8Array, natural: IntSize): Promise<Picked | null> {
    const all = this.all();
    if (this.#made) void LegacyFS.deleteAsync(this.#made, { idempotent: true }).catch(() => undefined);
    this.#made = null;
    const image = Skia.Image.MakeImageFromEncoded(Skia.Data.fromBytes(bytes));
    if (!image) return null;
    const w = image.width(), h = image.height();
    const surface = Skia.Surface.Make(w, h);
    if (!surface) throw new Error(t("android-chat.marks.tooBig"));
    const canvas = surface.getCanvas();
    canvas.drawImage(image, 0, 0);
    // The marks are in the image's own pixels (as shown: `natural`).
    canvas.save();
    canvas.scale(w / Math.max(1, natural.width), h / Math.max(1, natural.height));
    drawMarks(canvas, all, natural);
    canvas.restore();
    surface.flush();
    const marked = surface.makeImageSnapshot();
    const png = marked.encodeToBytes(ImageFormat.PNG, 100);
    if (png.length === 0) throw new Error(t("android-chat.file.drawFailed"));
    // A small picture of it, its longer side about 160 px.
    const side = Math.max(1, Math.floor(Math.max(w, h) / 160));
    const sw = Math.max(1, Math.floor(w / side)), sh = Math.max(1, Math.floor(h / side));
    const small = Skia.Surface.Make(sw, sh);
    let picture: string | null = null;
    const dir = LegacyFS.cacheDirectory ?? "";
    const stamp = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
    try {
      const file = `${dir}marked-${stamp}.png`;
      await LegacyFS.writeAsStringAsync(file, marked.encodeToBase64(ImageFormat.PNG, 100), { encoding: LegacyFS.EncodingType.Base64 });
      this.#made = file;
      if (small) {
        const paint = Skia.Paint();
        paint.setAntiAlias(true);
        small.getCanvas().drawImageRect(marked, Skia.XYWHRect(0, 0, w, h), Skia.XYWHRect(0, 0, sw, sh), paint);
        small.flush();
        const thumb = `${dir}marked-${stamp}-small.png`;
        await LegacyFS.writeAsStringAsync(thumb, small.makeImageSnapshot().encodeToBase64(ImageFormat.PNG, 100), { encoding: LegacyFS.EncodingType.Base64 });
        picture = thumb;
      }
    } catch (e) {
      throw new Error(t("android-chat.file.drawFailed"), { cause: e });
    }
    const size = png.length;
    if (size > MAX_MARKED) {
      const file = this.#made;
      return new Picked("", new Uint8Array(0), w, h, picture, size, () => uriSource(file, size));
    }
    return new Picked("", png, w, h, picture);
  }

  /** The marked image last made ([render]) put in the phone's Downloads, streamed from its file. */
  async save(name: string): Promise<boolean> {
    const file = this.#made;
    if (!file || !Downloads) return false;
    try { return await Downloads.save(file, name, "image/png"); } catch { return false; }
  }
}

/** A numbered mark as its note's box and card show it (Notes.tsx): its number, what it is, what is said about it. */
export class ImageNote implements NoteLike {
  constructor(private readonly marks: ImageMarks, readonly id: number, readonly n: number, readonly text: string, readonly color: string) {}
  get comment(): string { return this.marks.commentOf(this.id); }
  set comment(v: string) { this.marks.setComment(this.id, v); }
}

/** Draws the caller again whenever `marks` change. */
export function useImageMarks(marks: ImageMarks): number {
  return useSyncExternalStore(marks.subscribe, () => marks.version);
}

function MarksPins({ marks, zoom, density }: { marks: ImageMarks; zoom: ZoomState; density: number }) {
  useImageMarks(marks);
  const r = zoom.rect();
  const natural = zoom.natural;
  if (!r || !natural) return null;
  const k = zoom.k;
  const numbers = numbersOf(marks.shapes);
  if (numbers.size === 0) return null;
  // From the zoom's units to the layout's.
  const dp = (v: number) => v / density;
  return (
    <>
      {marks.shapes.map((s) => {
        const n = numbers.get(s.id);
        if (n == null) return null;
        const p = pinPoint(s, natural, density / k);
        const x = r.left + p.x * k, y = r.top + p.y * k;
        const open = marks.note === s.id;
        const halo = haloOf(s.color);
        return (
          <View
            key={s.id}
            style={{
              position: "absolute", left: dp(x) - 2, top: dp(y) - 22, width: 24, height: 24,
              transform: [{ scale: open ? 1.12 : 1 }], transformOrigin: `${(2 / 24) * 100}% ${(22 / 24) * 100}%`,
            }}
          >
            <Smooth radius={[12, 12, 12, 3]} style={{ flex: 1, backgroundColor: halo, padding: 2, elevation: 3, shadowColor: "#000", shadowOpacity: 0.25, shadowRadius: 3, shadowOffset: { width: 0, height: 1 } }}>
              <Smooth radius={[12, 12, 12, 3]} style={{ flex: 1, backgroundColor: s.color }}>
                <Pressable
                  onPress={() => marks.open(open ? null : s.id)} accessibilityLabel={t("android-chat.marks.pin", { n })}
                  style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
                >
                  <Text style={{ fontSize: 11, lineHeight: 11 * 1.4, fontWeight: "700", color: halo, includeFontPadding: false }}>{`${n}`}</Text>
                </Pressable>
              </Smooth>
            </Smooth>
          </View>
        );
      })}
    </>
  );
}

function MarksWriting({ marks, zoom, density }: { marks: ImageMarks; zoom: ZoomState; density: number }) {
  useImageMarks(marks);
  const field = useRef<TextInput>(null);
  const w = marks.writing;
  useEffect(() => { if (w) field.current?.focus(); }, [w?.id, w?.at.x, w?.at.y]); // eslint-disable-line react-hooks/exhaustive-deps
  const r = zoom.rect();
  if (!w || !r) return null;
  const k = zoom.k;
  const dp = (v: number) => v / density;
  // In the layout's units, as big as the zoom draws it (not grown by the system's text size: it is drawn on the image).
  const size = dp(w.w * k);
  const width = dp(Math.max(measure(w.text, w.w) + w.w * 2, w.w * 6) * k);
  const halo = haloOf(w.color);
  return (
    <View style={{ position: "absolute", left: dp(r.left + w.at.x * k), top: dp(r.top + w.at.y * k), width, height: dp(w.w * LINE_HEIGHT * k) }}>
      <TextInput
        ref={field} value={w.text} onChangeText={(v) => marks.setWriting(v)} multiline={false} allowFontScaling={false}
        placeholder={t("android-chat.marks.write")} placeholderTextColor={`${w.color}8C`}
        cursorColor={w.color} selectionColor={`${w.color}59`}
        returnKeyType="done" onSubmitEditing={() => marks.putDown()}
        style={{
          padding: 0, margin: 0, includeFontPadding: false, width: "100%", height: "100%",
          color: w.color, fontSize: size, lineHeight: size * LINE_HEIGHT, fontWeight: "600",
          textShadowColor: halo, textShadowRadius: w.w * k * 0.2 / density, textShadowOffset: { width: 0, height: 0 },
        }}
      />
    </View>
  );
}

// ── the bars ───────────────────────────────────────────────────────────

/** In the top bar while marking: what to do with the marks. */
export function MarksActions({ marks, canDraft, onDownload, onDraft }: { marks: ImageMarks; canDraft: boolean; onDownload: () => void; onDraft: () => void }) {
  useImageMarks(marks);
  const able = !marks.busy && marks.any;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 4 }}>
      {marks.error != null && <Text numberOfLines={1} style={{ fontSize: 13, lineHeight: 13 * 1.4, color: "#FF7B6B", paddingHorizontal: 6 }}>{marks.error}</Text>}
      <Smooth radius={15} style={{ height: 30 }}>
        <Pressable onPress={() => marks.leave()} android_ripple={{ color: "rgba(255,255,255,0.12)", borderless: false }} style={{ height: 30, paddingHorizontal: 10, alignItems: "center", justifyContent: "center" }}>
          <Text style={{ fontSize: 13, lineHeight: 13 * 1.4, color: "rgba(255,255,255,0.6)" }}>{t("common.cancel")}</Text>
        </Pressable>
      </Smooth>
      <PictureButton icon={Icons.Download} label={t("android-chat.marks.downloadMarked")} enabled={able} onClick={onDownload} />
      {canDraft && (
        <View style={{ marginLeft: 4 }}>
          <Smooth radius={15} style={{ height: 30, backgroundColor: INK, opacity: able ? 1 : 0.4 }}>
            <Pressable
              disabled={!able} onPress={onDraft} android_ripple={{ color: "rgba(255,255,255,0.2)", borderless: false }}
              style={{ height: 30, paddingHorizontal: 12, flexDirection: "row", alignItems: "center", gap: 5 }}
            >
              <Icon icon={Icons.Send} size={12} color="#FFFFFF" />
              <Text style={{ fontSize: 13, lineHeight: 13 * 1.4, fontWeight: "600", color: "#FFFFFF" }}>{marks.busy ? t("android-chat.marks.making") : t("android-chat.preview.put")}</Text>
            </Pressable>
          </Smooth>
        </View>
      )}
    </View>
  );
}

/** Frosted glass over a picture, as the viewer makes it (FilePreview.tsx darkGlass): what the bars stand on. */
export type Glass = ComponentType<{ style?: StyleProp<ViewStyle>; children?: ReactNode }>;

/** The tools, at the bottom over the image, frosted as the top bar; the colours in a row above them. */
export function MarksTools({ marks, glass: G }: { marks: ImageMarks; glass: Glass }) {
  useImageMarks(marks);
  const tools: [MarkTool, IconPaths][] = [[MarkTool.Select, Icons.Cursor], [MarkTool.Rect, Icons.Square], [MarkTool.Arrow, Icons.ArrowUpRight], [MarkTool.Pen, Icons.Scribble], [MarkTool.Text, Icons.Text]];
  const picked = marks.pickedShape;
  return (
    <View style={{ alignItems: "center", gap: 12 }}>
      {marks.palette && (
        // The glass's own corners, then a circle's ends.
        <View style={{ borderRadius: 999, overflow: "hidden" }}>
          <G style={{ padding: 4, flexDirection: "row", gap: 2 }}>
            {COLORS.map(([c]) => (
              <View key={c} style={{ width: 32, height: 32, borderRadius: 16, overflow: "hidden", backgroundColor: c === marks.shownColor ? "rgba(255,255,255,0.16)" : "transparent" }}>
                <Pressable onPress={() => marks.pickColor(c)} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}><Swatch c={c} /></Pressable>
              </View>
            ))}
          </G>
        </View>
      )}
      <G style={{ height: 44, paddingHorizontal: 2, flexDirection: "row", alignItems: "center", gap: 2 }}>
        {tools.map(([tool, icon]) => <PictureButton key={tool} icon={icon} label={markToolLabel(tool)} pressed={marks.tool === tool} onClick={() => marks.pickTool(tool)} />)}
        <Gap />
        <Smooth radius={12} style={{ width: 32, height: 32 }}>
          <Pressable onPress={() => { marks.palette = !marks.palette; }} accessibilityLabel={t("android-chat.marks.color")} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
            <Swatch c={marks.shownColor} />
          </Pressable>
        </Smooth>
        {picked != null && <PictureButton icon={Icons.Trash} label={t("common.delete")} onClick={() => marks.remove(picked.id)} />}
        <Gap />
        <PictureButton icon={Icons.Retry} label={t("android-chat.marks.undo")} enabled={marks.canUndo} onClick={() => marks.undo()} />
        <PictureButton icon={Icons.Redo} label={t("android-chat.marks.redo")} enabled={marks.canRedo} onClick={() => marks.redo()} />
      </G>
    </View>
  );
}

/**
 * The foot while marking, as the notes have it (Notes.tsx), in the viewer's dark: the note being written in
 * its box (over the keyboard), else the notes as cards over the tools (a tap opens one again).
 */
export function MarksFoot({ marks, haze, glass }: { marks: ImageMarks; haze: unknown; glass: Glass }) {
  useImageMarks(marks);
  const open = marks.openNote;
  return (
    <StillFailTheme dark>
      {open != null ? (
        <OverKeyboard key={open.id}>
          <View style={{ paddingHorizontal: 12 }}>
            <NoteBox note={open} onDone={() => marks.open(null)} onRemove={() => marks.remove(open.id)} />
          </View>
        </OverKeyboard>
      ) : (
        <View style={{ alignItems: "center", gap: 10 }}>
          {(() => {
            const notes = marks.notes();
            return notes.length > 0 ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ width: "100%", flexGrow: 0 }} contentContainerStyle={{ paddingHorizontal: 16, gap: 8 }}>
                {notes.map((x) => <Card key={x.id} note={x} open={false} haze={haze} onClick={() => marks.open(x.id)} />)}
              </ScrollView>
            ) : null;
          })()}
          <MarksTools marks={marks} glass={glass} />
        </View>
      )}
    </StillFailTheme>
  );
}

/** Kept over the keyboard as it comes up (WindowInsets.keyboard less the navigation bar's). */
function OverKeyboard({ children }: { children: ReactNode }) {
  // One keyboard for the app (ui/Keyboard.tsx): a second one asked of Reanimated with other window options blanks the window.
  const ime = keyboard();
  const bottom = useSafeAreaInsets().bottom;
  const lift = useAnimatedStyle(() => ({ paddingBottom: Math.max(0, ime.value - bottom) }));
  return <Animated.View style={lift}>{children}</Animated.View>;
}

function Swatch({ c }: { c: string }) {
  // Its ring a 1.5 line inside its edge, at half white.
  return <View style={{ width: 16, height: 16, borderRadius: 8, backgroundColor: c, borderWidth: 1.5, borderColor: "rgba(255,255,255,0.5)" }} />;
}

function Gap() {
  return <View style={{ marginHorizontal: 4, width: 1, height: 18, backgroundColor: "rgba(255,255,255,0.1)" }} />;
}

/** A 32dp icon button (named `label`) on a picture's bars (web's iconBtn in the dark viewer). */
export function PictureButton({ icon, label, enabled = true, pressed = false, tint = "rgba(255,255,255,0.6)", onClick }: { icon: IconPaths; label: string; enabled?: boolean; pressed?: boolean; tint?: string; onClick: () => void }) {
  return (
    <Smooth radius={12} style={{ width: 32, height: 32, backgroundColor: pressed ? "rgba(255,255,255,0.16)" : "transparent", opacity: enabled ? 1 : 0.35 }}>
      <Pressable
        disabled={!enabled} onPress={onClick} accessibilityLabel={label} android_ripple={{ color: "rgba(255,255,255,0.12)", borderless: false }}
        style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
      >
        <Icon icon={icon} size={18} color={pressed ? "#F4F4F5" : tint} />
      </Pressable>
    </Smooth>
  );
}
