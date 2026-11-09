// A document for mermaid where there is no browser (Hermes, a worker, Node): linkedom's DOM, with the geometry mermaid
// asks of SVG elements to lay a chart out (getBBox, getComputedTextLength, getBoundingClientRect) worked out here, the
// words measured by Inter's advances (mermaid-widths.ts): the face the app draws a chart's words in. Chinese, Japanese
// and Korean are a square each (思源黑体's, the app's face for them); a character neither has, 0.6 of the size.
// A browser's way kept where mermaid's layout turns on it: a box of nothing (a text with no words, a rect not sized
// yet) adds nothing to its group's.
import { parseHTML } from "linkedom";
import { ASCENT, DESCENT, RANGES, UNITS, W400, W700 } from "./mermaid-widths.ts";

// deno-lint-ignore no-explicit-any
type J = any;
type Box = { x: number; y: number; width: number; height: number };
type Matrix = [number, number, number, number, number, number];

/// The size words are measured at where nothing says another (the chart's theme says it to mermaid's styles).
export const WORDS_PX = 14;

const square = (c: number) =>
  (c >= 0x2e80 && c <= 0x9fff) || (c >= 0xac00 && c <= 0xd7af) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0x20000 && c <= 0x3134f);

function advance(c: number, bold: boolean): number {
  const table = bold ? W700 : W400;
  for (let r = 0; r < RANGES.length; r++) {
    const [a, b] = RANGES[r]!;
    if (c < a || c > b) continue;
    const u = table[r]![c - a]!;
    if (u > 0) return u;
    break;
  }
  if (square(c)) return UNITS;
  // combining marks and the zero-width ones
  if ((c >= 0x300 && c <= 0x36f) || c === 0x200b || c === 0x200c || c === 0x200d || c === 0xfeff) return 0;
  return UNITS * 0.6;
}

/// How wide `words` are set at `px`, bold or not.
export function wordsWidth(words: string, px: number, bold: boolean): number {
  let units = 0;
  for (const ch of words) units += advance(ch.codePointAt(0)!, bold);
  return (units * px) / UNITS;
}

// ── what an element or its ancestors say of its words: its style, its attribute, its chart's style sheet ──
type Rule = { selector: string; spec: number; important: boolean; value: string; at: number };
/// The rules of a style sheet that say each of the properties measured, by property (later ones last).
const MEASURED = ["font-size", "font-weight", "text-anchor", "dominant-baseline", "alignment-baseline"];
const sheets = new Map<string, Map<string, Rule[]>>();
function sheetOf(css: string): Map<string, Rule[]> {
  let rules = sheets.get(css);
  if (rules) return rules;
  rules = new Map(MEASURED.map((p) => [p, []]));
  // (stylis's flat output: `selectors{declarations}`; an at-rule's block, a keyframes', skipped whole)
  let at = 0, i = 0;
  while (i < css.length) {
    const open = css.indexOf("{", i);
    if (open < 0) break;
    const head = css.slice(i, open).trim();
    if (head.startsWith("@")) {
      let depth = 0, j = open;
      for (; j < css.length; j++) {
        if (css[j] === "{") depth++;
        else if (css[j] === "}" && --depth === 0) break;
      }
      i = j + 1;
      continue;
    }
    const close = css.indexOf("}", open);
    if (close < 0) break;
    for (const part of css.slice(open + 1, close).split(";")) {
      const colon = part.indexOf(":");
      if (colon < 0) continue;
      const prop = part.slice(0, colon).trim().toLowerCase();
      const list = rules.get(prop);
      if (!list) continue;
      const important = /!\s*important/i.test(part);
      const value = part.slice(colon + 1).replace(/!\s*important/i, "").trim();
      for (const selector of head.split(",")) list.push({ selector: selector.trim(), spec: specificity(selector), important, value, at: at++ });
    }
    i = close + 1;
  }
  for (const list of rules.values()) list.sort((a, b) => Number(a.important) - Number(b.important) || a.spec - b.spec || a.at - b.at);
  sheets.set(css, rules);
  return rules;
}
function specificity(selector: string): number {
  const ids = (selector.match(/#[\w-]+/g) ?? []).length;
  const classes = (selector.match(/\.[\w-]+|\[[^\]]*\]|:(?!:)[\w-]+/g) ?? []).length;
  const types = (selector.replace(/#[\w-]+|\.[\w-]+|\[[^\]]*\]|:+[\w-]+(\([^)]*\))?/g, " ").match(/[a-zA-Z][\w-]*/g) ?? []).length;
  return ids * 10000 + classes * 100 + types;
}
/// The style sheets of the chart `el` is in (its svg's `style` elements).
function sheetsOf(el: J): Map<string, Rule[]>[] {
  let svg = el;
  while (svg && svg.localName !== "svg") svg = svg.parentNode;
  if (!svg) return [];
  return [...svg.querySelectorAll("style")].map((st: J) => sheetOf(st.textContent ?? ""));
}
function said(el: J, prop: string): string | null {
  const style: string | null = el.getAttribute?.("style") ?? null;
  if (style) {
    for (const part of style.split(";")) {
      const colon = part.indexOf(":");
      if (colon > 0 && part.slice(0, colon).trim().toLowerCase() === prop) return part.slice(colon + 1).replace(/!important/i, "").trim();
    }
  }
  let found: string | null = null;
  for (const sheet of sheetsOf(el)) {
    for (const rule of sheet.get(prop) ?? []) {
      try {
        if (el.matches(rule.selector)) found = rule.value;
      } catch {
        // a selector linkedom does not read matches nothing
      }
    }
  }
  return found ?? el.getAttribute?.(prop) ?? null;
}
function inherited(el: J, prop: string): string | null {
  for (let e = el; e && e.getAttribute; e = e.parentNode) {
    const v = said(e, prop);
    if (v && v !== "inherit") return v;
  }
  return null;
}
function length(v: string | null, em: number): number | null {
  if (v === null) return null;
  const m = /^(-?[\d.]+(?:e-?\d+)?)(px|em|rem|pt|%)?$/i.exec(v.trim());
  if (!m) return null;
  const n = parseFloat(m[1]!);
  switch (m[2]?.toLowerCase()) {
    case "em": return n * em;
    case "rem": return n * WORDS_PX;
    case "pt": return (n * 4) / 3;
    case "%": return (n / 100) * em;
    default: return n;
  }
}
const sizeOf = (el: J) => length(inherited(el, "font-size"), WORDS_PX) ?? WORDS_PX;
function boldOf(el: J): boolean {
  const v = inherited(el, "font-weight");
  if (!v) return false;
  if (v === "bold" || v === "bolder") return true;
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n >= 600;
}

// ── transforms ─────────────────────────────────────────────────────────
const ID: Matrix = [1, 0, 0, 1, 0, 0];
const times = (a: Matrix, b: Matrix): Matrix => [
  a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
];
function transformOf(el: J): Matrix {
  const t: string | null = el.getAttribute("transform");
  if (!t) return ID;
  let m = ID;
  for (const [, f, args] of t.matchAll(/(\w+)\s*\(([^)]*)\)/g)) {
    const a = args!.split(/[\s,]+/).filter(Boolean).map(Number);
    let n: Matrix = ID;
    if (f === "translate") n = [1, 0, 0, 1, a[0] || 0, a[1] || 0];
    else if (f === "scale") n = [a[0] ?? 1, 0, 0, a[1] ?? a[0] ?? 1, 0, 0];
    else if (f === "matrix" && a.length === 6) n = a as Matrix;
    else if (f === "rotate") {
      const r = ((a[0] || 0) * Math.PI) / 180, c = Math.cos(r), s = Math.sin(r);
      n = [c, s, -s, c, 0, 0];
      if (a.length >= 3) n = times(times([1, 0, 0, 1, a[1]!, a[2]!], n), [1, 0, 0, 1, -a[1]!, -a[2]!]);
    }
    m = times(m, n);
  }
  return m;
}
const span = (x0: number, y0: number, x1: number, y1: number): Box => ({ x: x0, y: y0, width: x1 - x0, height: y1 - y0 });
function union(a: Box | null, b: Box | null): Box | null {
  if (!a) return b;
  if (!b) return a;
  return span(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.max(a.x + a.width, b.x + b.width), Math.max(a.y + a.height, b.y + b.height));
}
function mapped(m: Matrix, b: Box | null): Box | null {
  if (!b || m === ID) return b;
  let out: Box | null = null;
  for (const [x, y] of [[b.x, b.y], [b.x + b.width, b.y], [b.x, b.y + b.height], [b.x + b.width, b.y + b.height]] as const) {
    const px = m[0] * x + m[2] * y + m[4], py = m[1] * x + m[3] * y + m[5];
    out = union(out, span(px, py, px, py));
  }
  return out;
}
const num = (el: J, name: string): number => {
  const v = parseFloat(el.getAttribute(name));
  return Number.isFinite(v) ? v : 0;
};

// ── a path's box: its points and control points (a little more than the curve where it bows in) ──
const COUNTS: Record<string, number> = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
function pathBox(d: string | null): Box | null {
  if (!d) return null;
  const tokens = d.match(/[a-zA-Z]|-?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/g) ?? [];
  let i = 0, cmd = "", x = 0, y = 0, sx = 0, sy = 0;
  let b: Box | null = null;
  const at = (px: number, py: number) => { b = union(b, span(px, py, px, py)); };
  while (i < tokens.length) {
    if (/[a-zA-Z]/.test(tokens[i]!)) cmd = tokens[i++]!;
    const C = cmd.toUpperCase(), rel = cmd !== C;
    if (C === "Z") { x = sx; y = sy; continue; }
    const count = COUNTS[C];
    if (count === undefined) break;
    const a: number[] = [];
    for (let k = 0; k < count; k++) a.push(parseFloat(tokens[i++] ?? ""));
    if (a.some((v) => !Number.isFinite(v))) break;
    const ox = rel ? x : 0, oy = rel ? y : 0;
    switch (C) {
      case "M": x = a[0]! + ox; y = a[1]! + oy; sx = x; sy = y; at(x, y); cmd = rel ? "l" : "L"; break;
      case "L": case "T": x = a[0]! + ox; y = a[1]! + oy; at(x, y); break;
      case "H": x = a[0]! + ox; at(x, y); break;
      case "V": y = a[0]! + oy; at(x, y); break;
      case "C": at(a[0]! + ox, a[1]! + oy); at(a[2]! + ox, a[3]! + oy); x = a[4]! + ox; y = a[5]! + oy; at(x, y); break;
      case "S": case "Q": at(a[0]! + ox, a[1]! + oy); x = a[2]! + ox; y = a[3]! + oy; at(x, y); break;
      case "A": x = a[5]! + ox; y = a[6]! + oy; at(x, y); break;
    }
  }
  return b;
}

// ── words: a text's own, or each of its tspans at its x/y/dy ───────────
function textBox(el: J): Box | null {
  const px = sizeOf(el);
  const anchor = inherited(el, "text-anchor") ?? "start";
  const baseline = inherited(el, "dominant-baseline") ?? inherited(el, "alignment-baseline");
  let b: Box | null = null;
  const line = (words: string, x: number, y: number, size: number, bold: boolean) => {
    const w = wordsWidth(words, size, bold);
    if (w === 0) return;
    const a = (ASCENT / UNITS) * size, d = (DESCENT / UNITS) * size;
    const x0 = x - (anchor === "middle" ? w / 2 : anchor === "end" ? w : 0);
    const top = baseline === "middle" || baseline === "central" ? y - (a + d) / 2 : baseline === "hanging" || baseline === "text-before-edge" ? y : y - a;
    b = union(b, span(x0, top, x0 + w, top + a + d));
  };
  let x = num(el, "x"), y = num(el, "y") + (length(el.getAttribute("dy"), px) ?? 0);
  const spans = [...el.childNodes].filter((c: J) => c.nodeType === 1 && c.localName === "tspan");
  if (!spans.length) {
    line(el.textContent ?? "", x, y, px, boldOf(el));
    return b;
  }
  for (const s of spans) {
    const size = sizeOf(s);
    if (s.hasAttribute("x")) x = num(s, "x");
    if (s.hasAttribute("y")) y = length(s.getAttribute("y"), size) ?? y;
    if (s.hasAttribute("dy")) y += length(s.getAttribute("dy"), size) ?? 0;
    const words: string = s.textContent ?? "";
    line(words, x, y, size, boldOf(s));
    if (!s.hasAttribute("x")) x += wordsWidth(words, size, boldOf(s));
  }
  return b;
}

const UNSEEN = new Set(["style", "defs", "marker", "title", "desc", "clipPath", "mask", "linearGradient", "radialGradient", "filter", "pattern", "symbol", "script"]);
function boxOf(el: J): Box | null {
  switch (el.localName) {
    case "rect": case "image": case "foreignObject": case "use":
      return span(num(el, "x"), num(el, "y"), num(el, "x") + num(el, "width"), num(el, "y") + num(el, "height"));
    case "circle": { const r = num(el, "r"); return span(num(el, "cx") - r, num(el, "cy") - r, num(el, "cx") + r, num(el, "cy") + r); }
    case "ellipse": { const rx = num(el, "rx"), ry = num(el, "ry"); return span(num(el, "cx") - rx, num(el, "cy") - ry, num(el, "cx") + rx, num(el, "cy") + ry); }
    case "line": return span(Math.min(num(el, "x1"), num(el, "x2")), Math.min(num(el, "y1"), num(el, "y2")), Math.max(num(el, "x1"), num(el, "x2")), Math.max(num(el, "y1"), num(el, "y2")));
    case "polygon": case "polyline": {
      const p = (el.getAttribute("points") ?? "").split(/[\s,]+/).filter(Boolean).map(Number);
      let b: Box | null = null;
      for (let i = 0; i + 1 < p.length; i += 2) b = union(b, span(p[i]!, p[i + 1]!, p[i]!, p[i + 1]!));
      return b;
    }
    case "path": return pathBox(el.getAttribute("d"));
    case "text": case "tspan": return textBox(el);
    default: {
      if (UNSEEN.has(el.localName)) return null;
      let b: Box | null = null;
      for (const c of el.childNodes) {
        if (c.nodeType !== 1 || c.getAttribute("display") === "none" || /display:\s*none/.test(c.getAttribute("style") ?? "")) continue;
        const cb = boxOf(c);
        if (!cb || (cb.width === 0 && cb.height === 0)) continue;
        b = union(b, mapped(transformOf(c), cb));
      }
      return b;
    }
  }
}

const rect = (b: Box | null) => {
  const r = b ?? { x: 0, y: 0, width: 0, height: 0 };
  return { ...r, left: r.x, top: r.y, right: r.x + r.width, bottom: r.y + r.height };
};

/// A window for mermaid, its charts `width` wide where they fill what holds them (a gantt). The window's globals are
/// set as mermaid and the libraries it brings read them (window, document, and DOM classes absent here).
export function mermaidWindow(width: () => number): { window: J; document: J } {
  // (the window's own frames: none ever comes. Cytoscape, a mindmap's layout, steps its animations on each frame for as
  // long as its instance lives, and mermaid never ends one: on a timer every 16 ms in the core, forever. Nothing here is
  // drawn on a screen, and its layout is made at once, not in frames.)
  const frames = { requestAnimationFrame: () => 0, cancelAnimationFrame: () => {} };
  const { window, document } = parseHTML("<!doctype html><html><head></head><body></body></html>", frames) as J;
  const E = window.Element.prototype;
  E.getBBox = function () { return rect(boxOf(this)); };
  E.getComputedTextLength = function () { return wordsWidth(this.textContent ?? "", sizeOf(this), boldOf(this)); };
  E.getBoundingClientRect = function () {
    let b = boxOf(this);
    for (let e = this; e && e.getAttribute && e.localName !== "svg"; e = e.parentNode) b = mapped(transformOf(e), b);
    return rect(b);
  };
  E.getTotalLength ??= function () { return 0; };
  E.getPointAtLength ??= function () { return { x: 0, y: 0 }; };
  for (const P of [E, window.HTMLElement.prototype]) Object.defineProperty(P, "offsetWidth", { get: width, configurable: true });
  // A canvas's 2d context, for what lays a chart out on one (cytoscape, a mindmap's): its words measured as above,
  // its drawing nothing (no canvas is ever shown).
  window.HTMLCanvasElement.prototype.getContext = function (kind: string) {
    if (kind !== "2d") return null;
    const ctx: J = {
      font: `${WORDS_PX}px sans-serif`,
      canvas: this,
      measureText(words: string) {
        const px = parseFloat(/(\d+(?:\.\d+)?)px/.exec(ctx.font)?.[1] ?? "") || WORDS_PX;
        const width = wordsWidth(words, px, /\bbold\b|\b[6-9]00\b/.test(ctx.font));
        return { width, actualBoundingBoxAscent: (ASCENT / UNITS) * px, actualBoundingBoxDescent: (DESCENT / UNITS) * px };
      },
      getImageData: (_x: number, _y: number, w: number, h: number) => ({ width: w, height: h, data: new Uint8ClampedArray(Math.max(0, w * h * 4)) }),
      createLinearGradient: () => ({ addColorStop() {} }),
      createRadialGradient: () => ({ addColorStop() {} }),
      createPattern: () => ({}),
      getTransform: () => ({ a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 }),
      isPointInPath: () => false,
    };
    return new Proxy(ctx, { get: (t, k) => (k in t ? t[k] : () => undefined) });
  };
  // What mermaid writes its own rules into, read back as text (no replaceSync: a themeCSS is taken as written).
  window.CSSStyleSheet = class CSSStyleSheet {
    cssRules: { cssText: string }[] = [];
    insertRule(text: string, at = 0) { this.cssRules.splice(at, 0, { cssText: text }); return at; }
  };
  // (a box's own room: none, as an element not shown has; cytoscape sizes a mindmap's hidden container so)
  for (const side of ["clientWidth", "clientHeight", "offsetHeight", "scrollWidth", "scrollHeight"]) {
    Object.defineProperty(window.HTMLElement.prototype, side, { get: () => 0, configurable: true });
  }
  window.getComputedStyle = (el: J) => ({
    getPropertyValue: (p: string) => inherited(el, p) ?? (/^(padding|border|margin)/.test(p) ? "0px" : ""),
  });
  return { window, document };
}
