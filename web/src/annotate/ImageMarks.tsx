// Marking an image opened over the page (FilePreview.tsx): boxes, arrows, lines drawn by hand and words, drawn on the
// image where it is shown (zoomed and panned with it); picked again to move, resize, recolour or remove. Boxes and
// arrows are numbered, as a preview's marks are (Marks.tsx): a pin on each, and something said about it in a frosted
// bubble beside it. Done, the image with its marks (and their pins) goes into the chat's draft as a new file, with a
// quote per numbered mark saying where it is and what was said about it (or, outside a chat, is downloaded).
import { useCallback, useContext, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { ArrowUpRight, Cursor, Download, Edit, Redo, Retry, Scribble, Send, Square, Text, Trash } from "../icons.tsx";
import { DraftKey, offerToDraft, type DraftQuote } from "../draft.ts";
import { Tip } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./ImageMarks.css.ts";
import * as marksCss from "./Marks.css.ts";

type Tool = "select" | "rect" | "arrow" | "pen" | "text";
interface P { x: number; y: number }
/**
 * A mark, in the image's own pixels. `w`: its line (a text's size), set by how far in it was zoomed when drawn, so it
 * looks the same on the screen whatever the zoom.
 */
type Shape = { id: number; color: string; w: number } & (
  | { tool: "rect" | "arrow"; a: P; b: P }
  | { tool: "pen"; points: P[] }
  | { tool: "text"; at: P; text: string });
type Box = { x: number; y: number; w: number; h: number };

const TOOLS: { tool: Tool; label: string; key: string; icon: ReactNode }[] = [
  { tool: "select", label: "选择", key: "V", icon: <Cursor size={18} /> },
  { tool: "rect", label: "框", key: "R", icon: <Square size={18} /> },
  { tool: "arrow", label: "箭头", key: "A", icon: <ArrowUpRight size={18} /> },
  { tool: "pen", label: "画笔", key: "P", icon: <Scribble size={18} /> },
  { tool: "text", label: "文字", key: "T", icon: <Text size={18} /> },
];
/** The colours to draw in; words get an edge of `halo` to stand out on any picture. */
const COLORS: { color: string; name: string; halo: string }[] = [
  { color: css.INK, name: "橙", halo: "#fff" },
  { color: "#e5484d", name: "红", halo: "#fff" },
  { color: "#f5c518", name: "黄", halo: "#111" },
  { color: "#30a46c", name: "绿", halo: "#fff" },
  { color: "#3e7bfa", name: "蓝", halo: "#fff" },
  { color: "#ffffff", name: "白", halo: "#111" },
  { color: "#111111", name: "黑", halo: "#fff" },
];
const haloOf = (color: string) => COLORS.find((c) => c.color === color)?.halo ?? "#fff";
/** On the screen, whatever the zoom: a line's width, a text's size, how near the pointer picks a mark (px). */
const LINE = 3, TEXT = 18, REACH = 8;
/** A text's line height, and its baseline from the line's top (in its size). */
const LINE_HEIGHT = 1.3, BASELINE = 0.98;
const FONT = `-apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", system-ui, sans-serif`;

/** A shape's line as path data (the SVG draws it, and so does the canvas, as a Path2D). */
function pathOf(s: Shape): string {
  if (s.tool === "rect") {
    const { x, y, w, h } = boxOf(s), r = Math.min(s.w * 1.5, w / 2, h / 2);
    return `M${x + r} ${y}H${x + w - r}Q${x + w} ${y} ${x + w} ${y + r}V${y + h - r}Q${x + w} ${y + h} ${x + w - r} ${y + h}`
      + `H${x + r}Q${x} ${y + h} ${x} ${y + h - r}V${y + r}Q${x} ${y} ${x + r} ${y}Z`;
  }
  if (s.tool === "arrow") {
    const [left, right] = barbs(s);
    return `M${s.a.x} ${s.a.y}L${s.b.x} ${s.b.y}M${left.x} ${left.y}L${s.b.x} ${s.b.y}L${right.x} ${right.y}`;
  }
  if (s.tool === "pen") {
    const p = s.points;
    if (p.length < 3) return `M${p[0]!.x} ${p[0]!.y}` + p.slice(1).map((q) => `L${q.x} ${q.y}`).join("");
    // Through the midpoints, each point bending the line: smooth, however jerky the pointer.
    let d = `M${p[0]!.x} ${p[0]!.y}`;
    for (let i = 1; i < p.length - 1; i++) d += `Q${p[i]!.x} ${p[i]!.y} ${(p[i]!.x + p[i + 1]!.x) / 2} ${(p[i]!.y + p[i + 1]!.y) / 2}`;
    const last = p[p.length - 1]!;
    return d + `L${last.x} ${last.y}`;
  }
  return "";
}

/** An arrow's head: its two barbs, back from its point. */
function barbs(s: { a: P; b: P; w: number }): [P, P] {
  const dx = s.b.x - s.a.x, dy = s.b.y - s.a.y, len = Math.hypot(dx, dy) || 1;
  const ux = dx / len, uy = dy / len, size = Math.min(s.w * 5, len * 0.6), spread = 0.5;
  const back = { x: s.b.x - ux * size, y: s.b.y - uy * size };
  return [
    { x: back.x - uy * size * spread, y: back.y + ux * size * spread },
    { x: back.x + uy * size * spread, y: back.y - ux * size * spread },
  ];
}

let measurer: CanvasRenderingContext2D | null = null;
/** How wide words are, in the size `w`. */
function measure(text: string, w: number): number {
  measurer ??= document.createElement("canvas").getContext("2d");
  if (!measurer) return text.length * w;
  measurer.font = `600 ${w}px ${FONT}`;
  return measurer.measureText(text).width;
}

/** A box or an arrow: numbered, with something said about it. */
const numbered = (s: Shape): s is Shape & { tool: "rect" | "arrow" } => s.tool === "rect" || s.tool === "arrow";
/** The numbered marks' numbers, in the order they were drawn (one removed, those after it move up). */
function numbersOf(shapes: Shape[]): Map<number, number> {
  return new Map(shapes.filter(numbered).map((s, i) => [s.id, i + 1]));
}
/**
 * Where a numbered mark's pin points (a box's top-left corner, an arrow's tail), kept in the image whole: the pin, 24
 * by 24 in the size its mark's line was drawn at, sits up and to the right of its point.
 */
function pinPoint(s: Shape & { tool: "rect" | "arrow" }, natural: { w: number; h: number }): P {
  const k = s.w / LINE, p = s.tool === "rect" ? (({ x, y }) => ({ x, y }))(boxOf(s)) : s.a;
  return { x: Math.min(Math.max(p.x, 2 * k), natural.w - 22 * k), y: Math.min(Math.max(p.y, 22 * k), natural.h - 2 * k) };
}

/** The box a shape takes. */
function boxOf(s: Shape): Box {
  if (s.tool === "text") return { x: s.at.x, y: s.at.y, w: measure(s.text, s.w), h: s.w * LINE_HEIGHT };
  const points = s.tool === "pen" ? s.points : [s.a, s.b];
  const xs = points.map((p) => p.x), ys = points.map((p) => p.y);
  const x = Math.min(...xs), y = Math.min(...ys);
  return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
}

/** A shape moved by (dx, dy). */
function moved(s: Shape, dx: number, dy: number): Shape {
  const m = (p: P) => ({ x: p.x + dx, y: p.y + dy });
  if (s.tool === "text") return { ...s, at: m(s.at) };
  if (s.tool === "pen") return { ...s, points: s.points.map(m) };
  return { ...s, a: m(s.a), b: m(s.b) };
}

/** A shape stretched from `anchor` by (sx, sy) (words: evenly, by sx). */
function scaled(s: Shape, anchor: P, sx: number, sy: number): Shape {
  const m = (p: P) => ({ x: anchor.x + (p.x - anchor.x) * sx, y: anchor.y + (p.y - anchor.y) * sy });
  if (s.tool === "text") {
    const k = Math.max(0.2, Math.abs(sx));
    return { ...s, w: s.w * k, at: { x: anchor.x + (s.at.x - anchor.x) * k, y: anchor.y + (s.at.y - anchor.y) * k } };
  }
  if (s.tool === "pen") return { ...s, points: s.points.map(m) };
  return { ...s, a: m(s.a), b: m(s.b) };
}

/** A handle of a picked shape: a corner of its box (its opposite corner stays), or an end of an arrow. */
type Handle = { corner: [0 | 1, 0 | 1] } | { end: "a" | "b" };
function handles(s: Shape): { handle: Handle; at: P; cursor: string }[] {
  if (s.tool === "arrow") return [{ handle: { end: "a" }, at: s.a, cursor: "move" }, { handle: { end: "b" }, at: s.b, cursor: "move" }];
  const b = boxOf(s);
  const corners: [0 | 1, 0 | 1][] = s.tool === "text" ? [[1, 1]] : [[0, 0], [1, 0], [0, 1], [1, 1]];
  return corners.map(([cx, cy]) => ({
    handle: { corner: [cx, cy] }, at: { x: b.x + cx * b.w, y: b.y + cy * b.h }, cursor: cx === cy ? "nwse-resize" : "nesw-resize",
  }));
}

/** The image `url` (of `natural` size) with its marks drawn on it, as a PNG. */
async function render(url: string, natural: { w: number; h: number }, shapes: Shape[]): Promise<Blob> {
  const img = new Image();
  img.src = url;
  await img.decode();
  const canvas = document.createElement("canvas");
  canvas.width = natural.w;
  canvas.height = natural.h;
  const g = canvas.getContext("2d")!;
  g.drawImage(img, 0, 0, natural.w, natural.h);
  g.lineCap = "round";
  g.lineJoin = "round";
  for (const s of shapes) {
    if (s.tool === "text") {
      g.font = `600 ${s.w}px ${FONT}`;
      g.lineWidth = s.w * 0.22;
      g.strokeStyle = haloOf(s.color);
      g.fillStyle = s.color;
      g.strokeText(s.text, s.at.x, s.at.y + s.w * BASELINE);
      g.fillText(s.text, s.at.x, s.at.y + s.w * BASELINE);
    } else {
      g.strokeStyle = s.color;
      g.lineWidth = s.w;
      g.stroke(new Path2D(pathOf(s)));
    }
  }
  // The pins over them all, as they show while marking: the mark's colour, edged and numbered in its halo.
  for (const [id, n] of numbersOf(shapes)) {
    const s = shapes.find((x) => x.id === id) as Shape & { tool: "rect" | "arrow" };
    const k = s.w / LINE, p = pinPoint(s, natural), halo = haloOf(s.color);
    const x = p.x - 2 * k, y = p.y - 22 * k, size = 24 * k, edge = 2 * k;
    g.save();
    g.shadowColor = "rgba(0, 0, 0, .22)";
    g.shadowBlur = 6 * k;
    g.shadowOffsetY = 2 * k;
    g.fillStyle = halo;
    g.beginPath();
    g.roundRect(x, y, size, size, [12 * k, 12 * k, 12 * k, 3 * k]);
    g.fill();
    g.restore();
    g.fillStyle = s.color;
    g.beginPath();
    g.roundRect(x + edge, y + edge, size - 2 * edge, size - 2 * edge, [10 * k, 10 * k, 10 * k, 1.5 * k]);
    g.fill();
    g.fillStyle = halo;
    g.font = `650 ${11 * k}px ${FONT}`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText(String(n), x + size / 2, y + size / 2 + 0.5 * k);
  }
  return new Promise((done, fail) => canvas.toBlob((b) => (b ? done(b) : fail(new Error("没能画出图片"))), "image/png"));
}

/** What the zoom does with a pointer (FilePreview.tsx useZoom): two fingers on the marks pinch, as anywhere else. */
interface Pass { onPointerDown(e: React.PointerEvent): void; onPointerMove(e: React.PointerEvent): void; onPointerUp(e: React.PointerEvent): void }

/** Words being written: new ones, or those of the text `id` again. */
interface Writing { id: number | null; at: P; text: string; w: number; color: string }
/** A pointer at work: drawing a new shape, or moving or stretching the picked one (`before`: the shapes it started on). */
type Drag =
  | { kind: "draw"; shape: Shape }
  | { kind: "move" | "stretch"; id: number; from: P; orig: Shape; handle?: Handle | undefined; before: Shape[]; changed: boolean };

/**
 * Marking the image `url` (the whole of it, of `natural` size) shown at `scale`. Gives what goes in the top bar (its
 * button; while marking, what to do with the marks), the tools' bar at the bottom, and the sheet drawn over the image
 * (placed as the image is). `pass`: the zoom's own pointer handling, for pinching over the marks. `onDone`: its image
 * went into the chat's draft.
 */
export function useImageMarks({ url, name, natural, scale, pass, onDone }:
  { url: string | null; name: string; natural: { w: number; h: number } | null; scale: number; pass: Pass; onDone(): void }) {
  const draftKey = useContext(DraftKey);
  const [on, setOn] = useState(false);
  const [tool, setTool] = useState<Tool>("rect");
  const [color, setColor] = useState(css.INK);
  const [palette, setPalette] = useState(false);
  // The marks, and those before and after each change (undo, redo).
  const [doc, setDoc] = useState<{ shapes: Shape[]; past: Shape[][]; future: Shape[][] }>({ shapes: [], past: [], future: [] });
  const shapes = doc.shapes;
  const [picked, setPicked] = useState<number | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [writing, setWriting] = useState<Writing | null>(null);
  // What is said about each numbered mark (by its id; kept apart from the marks, so undoing a mark's move keeps them),
  // and the one whose bubble is open.
  const [comments, setComments] = useState<Map<number, string>>(new Map());
  const [note, setNote] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const svg = useRef<SVGSVGElement>(null);
  const nextId = useRef(1);
  const live = useRef({ doc, writing, picked, drag, note });
  live.current = { doc, writing, picked, drag, note };

  /** Changes the marks, as one step to undo. */
  const commit = useCallback((next: Shape[], before?: Shape[]) => {
    setDoc((d) => ({ shapes: next, past: [...d.past, before ?? d.shapes], future: [] }));
  }, []);
  const undo = useCallback(() => {
    setDoc((d) => d.past.length ? { shapes: d.past[d.past.length - 1]!, past: d.past.slice(0, -1), future: [d.shapes, ...d.future] } : d);
    setPicked(null);
    setNote(null);
  }, []);
  const redo = useCallback(() => {
    setDoc((d) => d.future.length ? { shapes: d.future[0]!, past: [...d.past, d.shapes], future: d.future.slice(1) } : d);
    setPicked(null);
    setNote(null);
  }, []);
  const remove = useCallback((id: number) => {
    commit(live.current.doc.shapes.filter((s) => s.id !== id));
    setPicked(null);
    setNote(null);
  }, [commit]);

  /** The words being written, put down (all of them gone: the text they were, removed). */
  const putDown = useCallback(() => {
    const w = live.current.writing;
    if (!w) return;
    setWriting(null);
    const text = w.text.trim(), all = live.current.doc.shapes;
    if (w.id !== null) {
      const was = all.find((s) => s.id === w.id);
      if (!was || was.tool !== "text" || was.text === text) return;
      commit(text ? all.map((s) => (s.id === w.id ? { ...was, text } : s)) : all.filter((s) => s.id !== w.id));
    } else if (text) commit([...all, { id: nextId.current++, tool: "text", at: w.at, text, w: w.w, color: w.color }]);
  }, [commit]);
  const edit = (s: Shape) => {
    if (s.tool !== "text") return;
    setPicked(null);
    setWriting({ id: s.id, at: s.at, text: s.text, w: s.w, color: s.color });
  };

  const leave = useCallback(() => {
    setOn(false); setDoc({ shapes: [], past: [], future: [] }); setPicked(null); setDrag(null); setWriting(null); setError(null); setPalette(false);
    setComments(new Map()); setNote(null);
  }, []);
  const pickTool = useCallback((t: Tool) => { putDown(); setTool(t); if (t !== "select") setPicked(null); }, [putDown]);
  /** A colour to draw in next; the picked mark (or the words being written) takes it at once. */
  const pickColor = useCallback((c: string) => {
    setColor(c);
    setPalette(false);
    const { picked: id, doc: d, writing: w } = live.current;
    if (w) setWriting({ ...w, color: c });
    else if (id !== null) commit(d.shapes.map((s) => (s.id === id ? { ...s, color: c } : s)));
  }, [commit]);

  // Keys while marking: Esc closes a mark's bubble (the keys typed in it are its own), puts down the words being written, lets go of the picked mark, else stops marking;
  // ⌘/Ctrl+Z undoes (with ⇧, redoes); Delete removes the picked mark; a tool's letter picks it. Heard before the
  // dialog's own Esc (which would close the image), and before the viewer's keys.
  useEffect(() => {
    if (!on) return;
    const onKey = (e: KeyboardEvent) => {
      const { writing: w, picked: id, note: open } = live.current;
      if (open !== null) {
        if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); setNote(null); }
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        if (w) putDown(); else if (palette) setPalette(false); else if (id !== null) setPicked(null); else leave();
      } else if (w) {
        return;
      } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) redo(); else undo();
      } else if ((e.key === "Delete" || e.key === "Backspace") && id !== null) {
        e.preventDefault();
        remove(id);
      } else if (!e.metaKey && !e.ctrlKey && !e.altKey) {
        const t = TOOLS.find((x) => x.key === e.key.toUpperCase());
        if (t) { e.preventDefault(); e.stopPropagation(); pickTool(t.tool); }
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [on, palette, putDown, leave, undo, redo, remove, pickTool]);

  /** A pointer's place on the image, in its own pixels. */
  const at = (e: { clientX: number; clientY: number }): P => {
    const r = svg.current!.getBoundingClientRect();
    return { x: ((e.clientX - r.left) / r.width) * natural!.w, y: ((e.clientY - r.top) / r.height) * natural!.h };
  };

  // Fingers on the sheet: one draws (or moves); a second one puts what it was doing back and pinches, as the zoom does.
  const touches = useRef(new Map<number, React.PointerEvent>());
  /** A pointer event as the zoom takes it, on the sheet (React's own is emptied once handled: the first finger's is kept). */
  const asZoom = (e: React.PointerEvent) => ({
    pointerId: e.pointerId, clientX: e.clientX, clientY: e.clientY, button: 0, type: e.type, currentTarget: svg.current,
  }) as unknown as React.PointerEvent;
  const pinching = useRef(false);
  const onTouchDown = (e: React.PointerEvent): boolean => {
    if (e.pointerType !== "touch") return false;
    touches.current.set(e.pointerId, asZoom(e));
    if (touches.current.size < 2 && !pinching.current) return false;
    if (!pinching.current) {
      pinching.current = true;
      const d = live.current.drag;
      if (d && d.kind !== "draw" && d.changed) setDoc((x) => ({ ...x, shapes: d.before }));
      setDrag(null);
      for (const [id, first] of touches.current) if (id !== e.pointerId) pass.onPointerDown(first);
    }
    pass.onPointerDown(asZoom(e));
    return true;
  };

  const onPointerDown = (e: React.PointerEvent) => {
    e.stopPropagation();
    if (!natural || (e.pointerType === "mouse" && e.button !== 0)) return;
    setPalette(false);
    if (onTouchDown(e)) return;
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
    if (live.current.writing) { putDown(); return; }
    if (live.current.note !== null) { setNote(null); return; }
    const p = at(e);
    if (tool === "select") { setPicked(null); return; }
    if (tool === "text") {
      const w = TEXT / scale;
      setWriting({ id: null, at: { x: p.x, y: p.y - w * 0.65 }, text: "", w, color });
      return;
    }
    const base = { id: nextId.current++, color, w: LINE / scale };
    setDrag({ kind: "draw", shape: tool === "pen" ? { ...base, tool, points: [p] } : { ...base, tool, a: p, b: p } });
  };
  const lastDown = useRef({ id: 0, at: 0 });
  /** A pointer down on a mark (`handle`: on one of the picked mark's handles). */
  const onMarkDown = (e: React.PointerEvent, s: Shape, handle?: Handle) => {
    if (tool !== "select" && !(tool === "text" && s.tool === "text")) return;
    e.stopPropagation();
    if (e.pointerType === "mouse" && e.button !== 0) return;
    setPalette(false);
    if (onTouchDown(e)) return;
    svg.current?.setPointerCapture(e.pointerId);
    setNote(null);
    // Words pressed twice (a double click or tap: the second press, as the pointer is held by the sheet) are written again.
    const now = performance.now(), again = lastDown.current.id === s.id && now - lastDown.current.at < 400;
    lastDown.current = { id: s.id, at: now };
    if (tool === "text" || (again && s.tool === "text" && !handle)) { putDown(); edit(s); return; }
    setPicked(s.id);
    setDrag({ kind: handle ? "stretch" : "move", id: s.id, from: at(e), orig: s, handle, before: live.current.doc.shapes, changed: false });
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (pinching.current) { if (touches.current.has(e.pointerId)) pass.onPointerMove(asZoom(e)); return; }
    const d = live.current.drag;
    if (!d) return;
    e.stopPropagation();
    const p = at(e);
    if (d.kind === "draw") {
      const s = d.shape;
      setDrag({ kind: "draw", shape: s.tool === "pen" ? { ...s, points: [...s.points, p] } : s.tool === "text" ? s : { ...s, b: p } });
      return;
    }
    let next: Shape;
    if (d.kind === "move") next = moved(d.orig, p.x - d.from.x, p.y - d.from.y);
    else if (d.handle && "end" in d.handle) next = d.orig.tool === "arrow" ? { ...d.orig, [d.handle.end]: p } : d.orig;
    else {
      const [cx, cy] = (d.handle as { corner: [0 | 1, 0 | 1] }).corner, b = boxOf(d.orig);
      const anchor = { x: b.x + (1 - cx) * b.w, y: b.y + (1 - cy) * b.h }, corner = { x: b.x + cx * b.w, y: b.y + cy * b.h };
      const ratio = (to: number, from: number, a: number) => (Math.abs(from - a) < 1e-6 ? 1 : (to - a) / (from - a));
      next = scaled(d.orig, anchor, ratio(p.x, corner.x, anchor.x), ratio(p.y, corner.y, anchor.y));
    }
    setDoc((x) => ({ ...x, shapes: x.shapes.map((s) => (s.id === d.id ? next : s)) }));
    if (!d.changed) setDrag({ ...d, changed: true });
  };
  const onPointerUp = (e: React.PointerEvent) => {
    e.stopPropagation();
    if (pinching.current) {
      if (touches.current.has(e.pointerId)) pass.onPointerUp(asZoom(e));
      touches.current.delete(e.pointerId);
      if (!touches.current.size) pinching.current = false;
      return;
    }
    touches.current.delete(e.pointerId);
    const d = live.current.drag;
    setDrag(null);
    if (!d) return;
    if (d.kind === "draw") {
      // A click, not a drag: nothing drawn.
      const s = d.shape, first = s.tool === "pen" ? s.points[0]! : s.tool === "text" ? s.at : s.a;
      const points = s.tool === "pen" ? s.points : s.tool === "text" ? [] : [s.b];
      if (points.some((q) => Math.hypot(q.x - first.x, q.y - first.y) > 4 / scale)) {
        commit([...live.current.doc.shapes, s]);
        // A box or an arrow, drawn: what to say about it, at once.
        if (numbered(s)) setNote(s.id);
      }
    } else if (d.changed) {
      setDoc((x) => ({ shapes: x.shapes, past: [...x.past, d.before], future: [] }));
    }
  };

  const finish = async (how: "draft" | "download") => {
    if (!url || !natural) return;
    setBusy(true);
    setError(null);
    try {
      // The words still being written count, as they show.
      const w = live.current.writing, text = w?.text.trim();
      let all = live.current.doc.shapes;
      if (w && text) {
        all = w.id !== null
          ? all.map((s) => (s.id === w.id && s.tool === "text" ? { ...s, text, color: w.color } : s))
          : [...all, { id: -1, tool: "text", at: w.at, text, w: w.w, color: w.color }];
      }
      putDown();
      setPicked(null);
      setNote(null);
      const png = await render(url, natural, all);
      const stamp = new Date().toTimeString().slice(0, 8).replaceAll(":", "");
      const fileName = `${name.replace(/\.[^.]+$/, "")}-标注-${stamp}.png`;
      if (how === "draft") {
        // A quote per numbered mark: where it is, for the agent (the first line is also what the composer shows), and what was said.
        const quotes: DraftQuote[] = [...numbersOf(all)].map(([id, n]) => {
          const s = all.find((x) => x.id === id)!, r = (v: number) => Math.round(v);
          const what = s.tool === "rect"
            ? (({ x, y, w, h }) => `框 · 左上角 (${r(x)}, ${r(y)})，${r(w)}×${r(h)}`)(boxOf(s))
            : s.tool === "arrow" ? `箭头 · 从 (${r(s.a.x)}, ${r(s.a.y)}) 指向 (${r(s.b.x)}, ${r(s.b.y)})` : "";
          return {
            id: `image-${stamp}-${n}-${Math.random().toString(36).slice(2, 8)}`, author: `图片 ${name} 标注 ${n}`, role: "image",
            text: `${what}\n在图片 ${fileName}（${natural.w}×${natural.h}，原图 ${name}）上，编号 ${n}`, comment: comments.get(id)?.trim() ?? "",
          };
        });
        if (!draftKey || !offerToDraft(draftKey, { files: [new File([png], fileName, { type: "image/png" })], quotes })) {
          throw new Error("这个对话现在不能发消息");
        }
        leave();
        onDone();
      } else {
        const link = document.createElement("a");
        link.href = URL.createObjectURL(png);
        link.download = fileName;
        link.click();
        setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  // The bars' buttons are made again only when what they show changes (the viewer puts the top bar's in place as they
  // change); what they do is always the latest.
  const act = useRef({ finish, leave, undo, redo, pickTool, pickColor, remove, setPalette });
  act.current = { finish, leave, undo, redo, pickTool, pickColor, remove, setPalette };
  const any = shapes.length > 0 || !!writing?.text.trim();
  const canDraft = draftKey !== undefined;
  const bar = useMemo(() => {
    const a = () => act.current;
    if (!on) {
      return url ? (
        <Tip label="标注图片"><button type="button" className={pagesCss.iconBtn} aria-label="标注图片" onClick={() => { setOn(true); setError(null); }}>
          <Edit size={18} />
        </button></Tip>
      ) : null;
    }
    return (
      <span className={css.actions}>
        {error && <span className={css.error}>{error}</span>}
        <button type="button" className={css.cancel} onClick={() => a().leave()}>取消</button>
        <Tip label="下载标注后的图片"><button type="button" className={pagesCss.iconBtn} aria-label="下载标注后的图片" disabled={busy || !any}
          onClick={() => void a().finish("download")}><Download size={18} /></button></Tip>
        {canDraft && (
          <button type="button" className={css.done} disabled={busy || !any} onClick={() => void a().finish("draft")}>
            <Send size={12} strokeWidth={2} />{busy ? "正在生成…" : "放进对话"}
          </button>
        )}
      </span>
    );
  }, [on, url, any, busy, error, canDraft]);

  const pickedShape = picked === null ? undefined : shapes.find((s) => s.id === picked);
  const shownColor = writing?.color ?? pickedShape?.color ?? color;
  const tools = on ? (
    <div className={css.toolbar} data-floats onPointerDown={(e) => e.stopPropagation()} onDoubleClick={(e) => e.stopPropagation()}>
      {TOOLS.map((t) => (
        <Tip key={t.tool} label={`${t.label}（${t.key}）`}><button type="button" className={pagesCss.iconBtn} aria-label={t.label}
          aria-pressed={tool === t.tool} onClick={() => pickTool(t.tool)}>{t.icon}</button></Tip>
      ))}
      <span className={css.gap} aria-hidden="true" />
      <div className={css.swatchWrap}>
        <Tip label="颜色"><button type="button" className={pagesCss.iconBtn} aria-label="颜色" aria-expanded={palette} onClick={() => setPalette(!palette)}>
          <span className={css.swatch} style={{ background: shownColor }} />
        </button></Tip>
        {palette && (
          <div className={css.palette} role="listbox" aria-label="颜色">
            {COLORS.map((c) => (
              <button key={c.color} type="button" role="option" aria-selected={c.color === shownColor} aria-label={c.name} className={css.paletteItem}
                onClick={() => pickColor(c.color)}><span className={css.swatch} style={{ background: c.color }} /></button>
            ))}
          </div>
        )}
      </div>
      {pickedShape && (
        <Tip label="删除（Delete）"><button type="button" className={pagesCss.iconBtn} aria-label="删除" onClick={() => remove(pickedShape.id)}>
          <Trash size={18} />
        </button></Tip>
      )}
      <span className={css.gap} aria-hidden="true" />
      <Tip label="撤销（⌘Z）"><button type="button" className={pagesCss.iconBtn} aria-label="撤销" disabled={!doc.past.length} onClick={undo}>
        <Retry size={18} />
      </button></Tip>
      <Tip label="重做（⌘⇧Z）"><button type="button" className={pagesCss.iconBtn} aria-label="重做" disabled={!doc.future.length} onClick={redo}>
        <Redo size={18} />
      </button></Tip>
    </div>
  ) : null;

  const drawn = drag?.kind === "draw" ? [...shapes, drag.shape] : shapes;
  const reach = REACH / scale;
  const numbers = numbersOf(shapes);
  /** How much room the window has right of a point on the image (for which side a bubble goes). */
  const roomRight = (p: P) => {
    const r = svg.current?.getBoundingClientRect();
    return r && natural ? window.innerWidth - (r.left + (p.x / natural.w) * r.width) : Infinity;
  };
  // The numbered marks' pins, over the sheet and placed as it is, each drawn at its own size whatever the zoom: its
  // number, and what is said about it beside it (being written: open, in a bubble).
  const pins = (place: CSSProperties) => natural && numbers.size > 0 ? (
    <div className={css.pins} style={place}>
      {shapes.map((s) => {
        const n = numbers.get(s.id);
        if (n === undefined || !numbered(s)) return null;
        const p = pinPoint(s, natural), open = note === s.id, comment = comments.get(s.id) ?? "", halo = haloOf(s.color);
        const right = roomRight(p) >= (open ? 320 : 120);
        return (
          <div key={s.id} className={css.pinAt} style={{ left: p.x, top: p.y, transform: `scale(${1 / scale})` }}
            onPointerDown={(e) => e.stopPropagation()} onDoubleClick={(e) => e.stopPropagation()}>
            <Tip label={open ? undefined : comment || "写点什么"}><button type="button" className={marksCss.pin} data-open={open || undefined}
              style={{ left: 0, top: 0, background: s.color, borderColor: halo, color: halo }} aria-label={`标注 ${n}`}
              onClick={() => { putDown(); setPicked(null); setNote(open ? null : s.id); }}>{n}</button></Tip>
            {open
              ? <div className={css.note} style={right ? { left: 28, top: -28 } : { right: 8, top: -28 }}>
                  <input className={marksCss.noteInput} autoFocus value={comment} placeholder="对这处说点什么" aria-label={`标注 ${n} 的说明`}
                    onChange={(e) => { const v = e.target.value; setComments((all) => new Map(all).set(s.id, v)); }}
                    // Keys typed here are the comment's (not the viewer's zoom or steps).
                    onKeyDown={(e) => { e.stopPropagation(); if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); setNote(null); } }} />
                  <span className={marksCss.noteKey} aria-hidden="true">↵</span>
                  <Tip label="删掉这处标注"><button type="button" className={marksCss.noteRemove} aria-label="删掉这处标注" onClick={() => remove(s.id)}>
                    <Trash size={14} strokeWidth={1.75} />
                  </button></Tip>
                </div>
              : comment.trim() && <button type="button" className={css.said} style={right ? { left: 28, top: -23, maxWidth: 260 } : { right: 6, top: -23, maxWidth: 260 }}
                  onClick={() => { putDown(); setPicked(null); setNote(s.id); }}>{comment}</button>}
          </div>
        );
      })}
    </div>
  ) : null;
  const sheet = (place: CSSProperties | null) => natural && place && on ? (<>
    <svg ref={svg} className={css.sheet} data-tool={tool} style={place} viewBox={`0 0 ${natural.w} ${natural.h}`}
      onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerCancel={onPointerUp}
      onDoubleClick={(e) => e.stopPropagation()}>
      <g strokeLinecap="round" strokeLinejoin="round">
        {drawn.map((s) => s.id === writing?.id ? null : s.tool === "text"
          ? <text key={s.id} x={s.at.x} y={s.at.y + s.w * BASELINE} fill={s.color} stroke={haloOf(s.color)} strokeWidth={s.w * 0.22} paintOrder="stroke"
              style={{ font: `600 ${s.w}px ${FONT}` }}>{s.text}</text>
          : <path key={s.id} d={pathOf(s)} fill="none" stroke={s.color} strokeWidth={s.w} />)}
      </g>
      {/* What the pointer picks marks by: wider than their lines, the whole box of words. */}
      {(tool === "select" || tool === "text") && (
        <g className={css.hits}>
          {shapes.map((s) => s.id === writing?.id || (tool === "text" && s.tool !== "text") ? null : s.tool === "text"
            ? <rect key={s.id} {...(({ x, y, w, h }) => ({ x: x - reach / 2, y: y - reach / 2, width: w + reach, height: h + reach }))(boxOf(s))}
                fill="transparent" onPointerDown={(e) => onMarkDown(e, s)} />
            : <path key={s.id} d={pathOf(s)} fill="none" stroke="transparent" strokeWidth={s.w + reach * 2} onPointerDown={(e) => onMarkDown(e, s)} />)}
        </g>
      )}
      {pickedShape && tool === "select" && (
        <g>
          {pickedShape.tool !== "arrow" && (({ x, y, w, h }) => (
            <rect className={css.pickedBox} x={x - reach / 2} y={y - reach / 2} width={w + reach} height={h + reach}
              strokeWidth={1 / scale} strokeDasharray={`${4 / scale} ${3 / scale}`} />
          ))(boxOf(pickedShape))}
          {handles(pickedShape).map(({ handle, at: h, cursor }, i) => (
            <circle key={i} className={css.handle} cx={h.x + ("corner" in handle ? (handle.corner[0] ? 1 : -1) * reach / 2 : 0)}
              cy={h.y + ("corner" in handle ? (handle.corner[1] ? 1 : -1) * reach / 2 : 0)} r={5 / scale} strokeWidth={1.5 / scale}
              style={{ cursor }} onPointerDown={(e) => onMarkDown(e, pickedShape, handle)} />
          ))}
        </g>
      )}
      {writing && (
        <foreignObject x={writing.at.x} y={writing.at.y} width={Math.max(measure(writing.text, writing.w) + writing.w * 2, writing.w * 6)}
          height={writing.w * LINE_HEIGHT}>
          <input className={css.typing} autoFocus value={writing.text} placeholder="写点什么" aria-label="标注文字"
            style={{ fontSize: writing.w, fontFamily: FONT, lineHeight: `${writing.w * LINE_HEIGHT}px`, color: writing.color, caretColor: writing.color,
              ["--halo" as string]: haloOf(writing.color) }}
            onPointerDown={(e) => e.stopPropagation()}
            onChange={(e) => setWriting((w) => (w ? { ...w, text: e.target.value } : w))}
            // Keys typed here are the words' (not the viewer's zoom or steps).
            onKeyDown={(e) => {
              e.stopPropagation();
              if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); putDown(); }
            }} />
        </foreignObject>
      )}
    </svg>
    {pins(place)}
  </>) : null;

  return { on, bar, tools, sheet };
}
