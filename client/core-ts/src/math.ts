// TeX is parsed and laid out in the core, including native cores running in Hermes. MathJax's LiteDOM is only a
// transient layout tree: no DOM, HTML, WebView, remote font or executable markup reaches a client. The bundled TeX
// font supplies the glyph outlines; the result is the same small drawing on every platform.
import { mathjax } from "@mathjax/src/js/mathjax.js";
import { TeX } from "@mathjax/src/js/input/tex.js";
import { SVG } from "@mathjax/src/js/output/svg.js";
import { liteAdaptor } from "@mathjax/src/js/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "@mathjax/src/js/handlers/html.js";
import { MathJaxTexFont } from "@mathjax/mathjax-tex-font/js/svg.js";
import "@mathjax/src/js/input/tex/base/BaseConfiguration.js";
import "@mathjax/src/js/input/tex/ams/AmsConfiguration.js";
import "@mathjax/src/js/input/tex/newcommand/NewcommandConfiguration.js";
import "@mathjax/src/js/input/tex/boldsymbol/BoldsymbolConfiguration.js";
import { mathGlyphId, type MathDrawing } from "./mathDrawing.ts";

type Element = { kind: string; attributes?: Record<string, string>; children?: Element[]; value?: string };
type Move = [sx: number, sy: number, x: number, y: number];
const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
let output: SVG<unknown, unknown, unknown> | undefined;

// Both successful and refused formulas are kept, charged for their drawing, not just the much shorter TeX.
const kept = new Map<string, { drawing: MathDrawing | null; cost: number }>();
const budget = 2_000_000;
let used = 0;

export function mathDrawing(source: string, display: boolean): MathDrawing | null {
  const key = `${display ? "d" : "i"}${source}`;
  const hit = kept.get(key);
  if (hit) { kept.delete(key); kept.set(key, hit); return hit.drawing; }
  let drawing: MathDrawing | null = null;
  if (source.length <= 8192) {
    try { drawing = typeset(source, display); } catch { /* Invalid or unsupported TeX stays readable as its source. */ }
  }
  const cost = source.length + (drawing ? JSON.stringify(drawing).length : 0);
  if (cost <= budget) {
    kept.set(key, { drawing, cost });
    used += cost;
    for (const [old, entry] of kept) {
      if (used <= budget) break;
      kept.delete(old); used -= entry.cost;
    }
  }
  return drawing;
}

function typeset(source: string, display: boolean): MathDrawing {
  // A fresh input jax isolates \def/\newcommand and equation labels to this formula. reset() alone retains macros.
  const input = new TeX({
    packages: ["base", "ams", "newcommand", "boldsymbol"], maxBuffer: 8192, maxMacros: 1000,
    formatError(_jax: unknown, error: Error) { throw error; },
  });
  output ??= new SVG({ fontData: MathJaxTexFont, fontCache: "local", linebreaks: { inline: false }, displayOverflow: "overflow" });
  const doc = mathjax.document("", { InputJax: input, OutputJax: output });
  try {
    const container = doc.convert(source, { display, em: 16, ex: 8, containerWidth: 100000 }) as Element;
    const svg = container.children?.find((n) => n.kind === "svg");
    if (!svg) throw new Error("No formula drawing");
    const [x = 0, y = 0, width = 0, height = 0] = numbers(svg.attributes?.viewBox ?? "");
    if (!(width >= 0 && height > 0 && width <= 1_000_000 && height <= 100_000)) throw new Error("Formula too large");
    const result: MathDrawing = { font: "tex-4.1.3", width, height, baseline: -y, draw: [], rects: [], text: [] };
    const defs = new Map<string, string>();
    const collect = (node: Element) => {
      const attrs = node.attributes ?? {};
      if (node.kind === "path" && attrs.id) defs.set(attrs.id, attrs.d ?? "");
      for (const child of node.children ?? []) collect(child);
    };
    collect(svg);
    const path = (d: string, move: Move) => {
      if (!d) return;
      result.draw.push([mathGlyphId(d), ...move]);
      if (result.draw.length > 4096) throw new Error("Formula too complex");
    };
    const walk = (node: Element, parent: Move) => {
      if (node.kind === "defs") return;
      const attrs = node.attributes ?? {};
      const move = moved(parent, attrs.transform ?? "");
      switch (node.kind) {
        case "use": {
          const d = defs.get((attrs["xlink:href"] ?? attrs.href ?? "").slice(1));
          if (d === undefined) throw new Error("Missing formula glyph");
          path(d, move); return;
        }
        case "path": path(attrs.d ?? "", move); return;
        case "rect": {
          const x = finite(attrs.x ?? "0"), y = finite(attrs.y ?? "0");
          const w = finite(attrs.width ?? "0"), h = finite(attrs.height ?? "0");
          const [sx, sy, tx, ty] = move;
          result.rects.push([tx + sx * x + Math.min(0, sx * w), ty + sy * y + Math.min(0, sy * h), Math.abs(sx * w), Math.abs(sy * h)]);
          return;
        }
        case "text": {
          const words = (node.children ?? []).map((n) => n.value ?? "").join("");
          // Native text uses a font at this scale, not a stretched bitmap. Reject a future engine shape that
          // asks for stretched/reflected text rather than letting the clients disagree about its placement.
          if (move[0] <= 0 || move[0] !== move[1]) throw new Error("Unsupported formula text transform");
          if (words) result.text.push([words, ...move]);
          return;
        }
        case "g": case "svg": break;
        default: throw new Error(`Unsupported formula shape: ${node.kind}`);
      }
      for (const child of node.children ?? []) walk(child, move);
    };
    walk(svg, [1, 1, -x, -y]);
    return result;
  } finally { doc.clear(); }
}

const finite = (word: string): number => { const n = Number(word); if (!Number.isFinite(n)) throw new Error("Invalid formula dimension"); return n; };
const numbers = (words: string) => words.trim().split(/[\s,]+/).map(finite);

// The bundled math font places outlines using translation and scale only. Refuse any new shape/transform instead
// of silently losing part of a formula if the engine is changed; source is still carried beside the drawing.
function moved(parent: Move, transform: string): Move {
  let [sx, sy, x, y] = parent;
  let rest = transform.trim();
  while (rest) {
    const match = /^(translate|scale)\(([^)]*)\)\s*/.exec(rest);
    if (!match) throw new Error("Unsupported formula transform");
    const n = numbers(match[2]!);
    if (match[1] === "translate") { x += sx * n[0]!; y += sy * (n[1] ?? 0); }
    else { sx *= n[0]!; sy *= n[1] ?? n[0]!; }
    rest = rest.slice(match[0].length);
  }
  return [sx, sy, x, y].map((n) => Math.round(n * 10000) / 10000) as Move;
}
