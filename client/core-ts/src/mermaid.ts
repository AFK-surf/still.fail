// A ```mermaid block's chart, made here for every client as formulas are (math.ts): mermaid lays it out in a document
// of its own (mermaidDom.ts: no browser, the words measured as the app sets them) and gives an SVG the app draws
// itself (mbui's SVG renderer), in the app's colours. Its words are SVG text, not HTML (`htmlLabels: false`): a chart
// that would still carry HTML (a foreignObject) is refused, and a client shows it another way.
// mermaid, and the document it lays charts out in, are loaded the first time a chart is asked for, not as the core starts:
// in a browser or Node from its package (mermaid-lib.ts); in Hermes, whose script has it not (mermaid-lib-hermes.ts:
// `#mermaid-lib`'s `hermes` condition), given by the app (provideMermaid).
import { loadMermaid } from "#mermaid-lib";

// deno-lint-ignore no-explicit-any
type J = any;

/// The colours a chart is drawn in (the app's theme), each `#rrggbb`, and whether the theme is dark.
export type MermaidLook = {
  dark: boolean;
  /// the page under it, a node's fill and its border, the words, lines, and the softer fills (accent, muted)
  background: string;
  card: string;
  border: string;
  text: string;
  line: string;
  accent: string;
  muted: string;
  brand: string;
};
export const LOOK_COLOURS = ["background", "card", "border", "text", "line", "accent", "muted", "brand"] as const;

/// The face named in a chart's styles: the app draws it in Inter, and Chinese and Japanese in 思源黑体.
export const MERMAID_FACE = "Inter, 'Noto Sans SC', sans-serif";

export class MermaidRefused extends Error {}
/// No mermaid here: the core has not been given it (`mermaid.load`).
export class MermaidAbsent extends Error {}

/// A chart: its SVG, and its width and height as it is written (its viewBox's).
export type MermaidMade = { svg: string; width: number; height: number };

const kept = new Map<string, MermaidMade | { refused: string }>();
const KEPT = 64;
let window: { window: J; document: J } | undefined;
/// how wide a chart that fills its width fills (what the document's elements say of their own width)
let filling = 800;
let wordsPx = 14;
let loaded: Promise<J> | undefined;
let queue: Promise<unknown> = Promise.resolve();

let ready: Promise<void> | undefined;
/// The document mermaid lays charts out in, and the globals it and the libraries it brings read.
function documentReady(): Promise<void> {
  ready ??= (async () => {
    const dom = await import("./mermaidDom.ts");
    wordsPx = dom.WORDS_PX;
    window ??= dom.mermaidWindow(() => filling);
    const g = globalThis as J;
    g.window ??= window.window;
    g.document ??= window.document;
    for (const name of ["Element", "HTMLElement", "SVGElement", "Node", "DOMParser", "CSSStyleSheet"]) g[name] ??= window.window[name];
    g.navigator ??= window.window.navigator;
  })();
  return ready;
}

function load(): Promise<J> {
  loaded ??= (async () => {
    await documentReady();
    const mermaid = await loadMermaid();
    if (!mermaid) throw new MermaidAbsent("no mermaid in this core yet (mermaid.load)");
    return mermaid;
  })();
  // (not given it yet: looked for again once it is)
  loaded.catch(() => (loaded = undefined));
  return loaded;
}

/// mermaid as the app carries it (scripts/mermaid-bundle.ts: a script setting globalThis.mermaid, as Hermes's bytecode
/// for the app's core), run here: a core whose own script has no mermaid (Hermes's) is given it the first time a chart
/// is drawn. Bytecode is run by the engine (`__native.evaluate`), as the core's own is: source compiled here would be
/// slow (its first chart 1.4 s in Hermes, not 0.2).
export async function provideMermaid(bytes: Uint8Array): Promise<void> {
  await documentReady();
  const native = (globalThis as J).__native;
  if (typeof native?.evaluate === "function") native.evaluate(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), "mermaid.hbc");
  else (0, eval)(new TextDecoder().decode(bytes));
  loaded = undefined;
}

function config(look: MermaidLook): J {
  return {
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    htmlLabels: false,
    flowchart: { htmlLabels: false },
    // (a journey's task words as SVG text: its default puts them in HTML)
    journey: { textPlacement: "tspan" },
    fontFamily: MERMAID_FACE,
    themeVariables: {
      darkMode: look.dark, fontSize: `${wordsPx}px`, fontFamily: MERMAID_FACE,
      background: look.background, primaryColor: look.card, primaryTextColor: look.text, primaryBorderColor: look.border,
      secondaryColor: look.accent, tertiaryColor: look.muted, lineColor: look.line, textColor: look.text,
      noteBkgColor: look.accent, noteTextColor: look.text, noteBorderColor: look.brand,
      actorBkg: look.card, actorBorder: look.border, actorTextColor: look.text, signalColor: look.text, signalTextColor: look.text,
    },
  };
}

let charts = 0;
/// Chart `code` as SVG in `look`, `px` wide where it fills its width (a gantt). Refused (MermaidRefused) where mermaid
/// does not read it or would draw part of it as HTML.
export function mermaidChart(code: string, look: MermaidLook, px: number): Promise<MermaidMade> {
  const key = `${px}\n${LOOK_COLOURS.map((c) => look[c]).join(",")}${look.dark ? "d" : "l"}\n${code}`;
  const hit = kept.get(key);
  if (hit) {
    kept.delete(key);
    kept.set(key, hit);
    return "svg" in hit ? Promise.resolve(hit) : Promise.reject(new MermaidRefused(hit.refused));
  }
  // one at a time: mermaid keeps its settings, and a chart's diagram, between the steps of a render
  const made = queue.then(async () => {
    const mermaid = await load();
    filling = px;
    mermaid.initialize(config(look));
    let svg: string;
    try {
      svg = (await mermaid.render(`chart${++charts}`, code)).svg;
    } catch (e) {
      throw new MermaidRefused(e instanceof Error ? e.message : String(e));
    } finally {
      // what a failed render leaves in the document
      for (const el of window!.document.body.querySelectorAll(`[id^="dchart"]`)) el.remove();
    }
    if (svg.includes("<foreignObject")) throw new MermaidRefused("HTML in the chart");
    const [, , width = 0, height = 0] = (/viewBox="([^"]*)"/.exec(svg)?.[1] ?? "").trim().split(/[\s,]+/).map(Number);
    if (!(width > 0 && height > 0)) throw new MermaidRefused("a chart of no size");
    return { svg, width, height };
  });
  queue = made.catch(() => undefined);
  return made.then(
    (chart) => (keep(key, chart), chart),
    (e) => {
      if (e instanceof MermaidRefused) keep(key, { refused: e.message });
      throw e;
    },
  );
}

function keep(key: string, v: MermaidMade | { refused: string }) {
  kept.set(key, v);
  for (const old of kept.keys()) {
    if (kept.size <= KEPT) break;
    kept.delete(old);
  }
}
