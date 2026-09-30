// Inline visualizations: an HTML file an agent attached and placed in its message's text (`[title](figure.html)` on a
// line of its own), drawn there in a sandboxed frame instead of shown as a card; the ember-viz skill says how agents
// make one. After Codex's Visualize: only a file placed so is drawn, never an html code block, so nothing half written
// is. A ```mermaid block is drawn the same way, by mermaid loaded into a frame of its own.
//
// The frame runs the file's scripts but has no origin of the page's: it cannot reach the page, its storage or the
// station, and its CSP lets it load scripts and styles from a few public CDNs only, with no requests of its own. The
// page hands it ember's tokens for the theme it shows (viz/ember-viz.css maps them to the names agents write against),
// sizes it to its content (on its own, beside the chat, it is a web service's preview: Preview.tsx), keeps what the widget asks to keep (widgetState, on the station, whose model part reaches
// the agent with the next message), and puts what it asks to send (sendFollowUpMessage, on a click) in the chat's
// composer for the person to send.
import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import bridge from "./viz/bridge.js?raw";
import stylesheet from "./viz/ember-viz.css?raw";
import { useApi, type Attachment } from "./api.ts";
import { FilePreview, useFileText } from "./FilePreview.tsx";
import { Expand, PanelOpen } from "./icons.tsx";
import { Code } from "./Prose.tsx";
import { DraftKey, offerToDraft } from "./draft.ts";
import { useToast } from "./toast.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./Viz.css.ts";

/**
 * Where a visualization opens on its own, beside its chat: the chat page's side panel (a tab of its own) on a wide
 * screen, a page over the chat on a narrow one. None: the chat is shown where nothing can open it.
 */
export const OpenFile = createContext<((sessionKey: string, file: Attachment) => void) | null>(null);

/** ember's tokens a frame is given, as --e-<name> (tokens.css.ts names them). */
const TOKENS = [
  "canvas", "raised", "text", "muted", "subtle", "line", "line-strong", "hover", "selected", "paper", "accent",
  "accent-text", "accent-bg", "blue", "blue-bg", "code-inline", "green", "green-bg", "amber", "amber-bg", "red",
  "red-bg", "neutral-bg", "shadow", "primary", "primary-hover", "on-primary", "field-hover", "field-focus", "r-field",
  "r-card", "corner-shape",
] as const;

const CDNS = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com";
const CSP = [
  "default-src 'none'",
  `script-src 'unsafe-inline' 'unsafe-eval' ${CDNS}`,
  `style-src 'unsafe-inline' ${CDNS} https://fonts.googleapis.com`,
  `font-src data: ${CDNS} https://fonts.gstatic.com`,
  "img-src data: blob:",
  "media-src data: blob:",
  "connect-src 'none'",
].join("; ");

/**
 * A fragment's frame is as tall as its content, however tall. Content sized to its window (100vh, min-height:100%)
 * grows with each height it is given: grown a little each time this many times running, it is held where it got to.
 */
const RUNAWAY = 60;
/** A frame's height before its content says (and what its place holds while the file comes), when none was kept. */
const FIRST_HEIGHT = 120;

// The height each visualization last had (the latest 300), by its file (`session\npath`) or a mermaid block's source:
// shown again, its place and its frame start that tall, so the chat does not jump as it loads.
const HEIGHTS = "stillfail.vizHeights";
let heights: Record<string, number> | undefined;
function keptHeights(): Record<string, number> {
  if (!heights) {
    try {
      heights = JSON.parse(localStorage.getItem(HEIGHTS) ?? "{}") as Record<string, number>;
    } catch {
      heights = {};
    }
  }
  return heights;
}
const keptHeight = (key: string) => keptHeights()[key];
function keepHeight(key: string, height: number) {
  const all = keptHeights();
  if (all[key] === height) return;
  delete all[key];
  all[key] = height;
  const keys = Object.keys(all);
  for (const old of keys.slice(0, Math.max(0, keys.length - 300))) delete all[old];
  try {
    localStorage.setItem(HEIGHTS, JSON.stringify(all));
  } catch {
    // kept for this page only
  }
}
const fileHeightKey = (sessionKey: string, file: Attachment) => `${sessionKey}\n${file.path}`;
/** A mermaid block's key: its source, hashed (FNV-1a), not kept whole. */
function mermaidHeightKey(code: string) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < code.length; i++) hash = Math.imul(hash ^ code.charCodeAt(i), 0x01000193);
  return `mermaid\n${(hash >>> 0).toString(36)}:${code.length}`;
}
/** What a widget may keep, as Codex's Visualize allows. */
export const MAX_STATE = 16 * 1024;

function scheme(): "light" | "dark" {
  return getComputedStyle(document.documentElement).colorScheme.includes("dark") ? "dark" : "light";
}

function tokens(): Record<string, string> {
  const style = getComputedStyle(document.documentElement);
  return Object.fromEntries(TOKENS.map((name) => [`--e-${name}`, style.getPropertyValue(`--${name}`).trim()]).filter(([, v]) => v));
}

/** JSON for inside a <script> element: nothing in it can end the element. */
const scriptJson = (value: unknown) => JSON.stringify(value).replace(/</g, "\\u003c");

/** The frame's document: the content in the stylesheet, the bridge (and what the widget kept) ahead of it, the theme as the page shows it now. */
function documentOf(html: string, state: unknown): string {
  const vars = Object.entries(tokens()).map(([k, v]) => `${k}:${v.replace(/[<>]/g, "")}`).join(";");
  const theme = scheme();
  return `<!doctype html><html data-theme="${theme}"><head><meta charset="utf-8">`
    + `<meta http-equiv="Content-Security-Policy" content="${CSP}">`
    + `<style>:root{color-scheme:${theme};${vars}}</style><style>${stylesheet}</style>`
    + `<script type="application/json" id="ember-viz-state">${scriptJson({ widgetState: state })}</script>`
    + `<script>${bridge}</script></head><body>${html}</body></html>`;
}

/**
 * A whole page's document (a file that is not a fragment: a player, an app, a page made to fill a window), drawn as
 * written, not in the stylesheet: only the sandbox's CSP and the bridge go into its head, after its doctype so it
 * keeps its mode.
 */
function pageDocument(html: string): string {
  const head = `<meta http-equiv="Content-Security-Policy" content="${CSP}"><script>${bridge}</script>`;
  const at = /<head[^>]*>/i.exec(html) ?? /<html[^>]*>/i.exec(html) ?? /<!doctype[^>]*>/i.exec(html);
  return at ? html.slice(0, at.index + at[0].length) + head + html.slice(at.index + at[0].length) : head + html;
}

/** Whether an HTML file is a fragment (as the ember-viz skill has agents write them), to be drawn in the stylesheet. */
export function isFragment(html: string): boolean {
  return !/<!doctype|<html[\s>]/i.test(html.slice(0, 2048));
}

/** A fragment's document as a frame of its own shows it (a preview of the file): the stylesheet, the theme now, what it kept. */
export function vizDocument(html: string, state: unknown = null): string {
  return documentOf(html, state);
}

/** Calls back when the page's theme changes: its own choice (data-theme) or the system's. */
function useThemeChange(onChange: () => void) {
  const latest = useRef(onChange);
  latest.current = onChange;
  useEffect(() => {
    const fire = () => latest.current();
    const observer = new MutationObserver(fire);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    const media = matchMedia("(prefers-color-scheme: dark)");
    media.addEventListener("change", fire);
    return () => { observer.disconnect(); media.removeEventListener("change", fire); };
  }, []);
}

/**
 * What a visualization's page says to the page (viz/bridge.js), from one of the windows `wins` gives (checked against
 * them, and `origin` when known): its height, what it keeps, a failure it reports, words to put in the composer (a click in it);
 * and the page's theme, told to it as it changes.
 */
export function useVizMessages(wins: () => Window[], { origin = "*", draftKey: given, onHeight, onState, onError }: {
  origin?: string; draftKey?: string | undefined; onHeight?: (height: number) => void; onState?: (state: unknown) => void; onError?: (message: string) => void;
}) {
  // The chat's draft, where its words go: the page's around it, else as given (a preview kept outside its chat).
  const draftKey = useContext(DraftKey) ?? given;
  const toast = useToast();
  const latest = useRef({ wins, origin, draftKey, toast, onHeight, onState, onError });
  latest.current = { wins, origin, draftKey, toast, onHeight, onState, onError };
  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as { emberViz?: boolean; type?: string; [k: string]: unknown } | null;
      const { wins, origin, draftKey, toast, onHeight, onState, onError } = latest.current;
      if (!data?.emberViz || !wins().includes(event.source as Window) || (origin !== "*" && event.origin !== origin)) return;
      if (data.type === "height" && typeof data.height === "number") onHeight?.(data.height);
      if (data.type === "state" && JSON.stringify(data.state ?? null).length <= MAX_STATE) onState?.(data.state ?? null);
      if (data.type === "failed" && typeof data.message === "string") onError?.(data.message);
      // A click in the widget asks to send words: they go in the composer, for the person to send (or not).
      if (data.type === "followup" && typeof data.prompt === "string" && data.prompt.trim()) {
        const offered = draftKey !== undefined && offerToDraft(draftKey, { files: [], quotes: [], text: data.prompt.trim().slice(0, 4000) });
        toast(offered ? "已放进输入框，确认后发送" : "这个对话现在不能发消息");
      }
    };
    addEventListener("message", onMessage);
    return () => removeEventListener("message", onMessage);
  }, []);
  useThemeChange(() => { for (const win of latest.current.wins()) win.postMessage({ emberViz: true, type: "theme", tokens: tokens(), scheme: scheme() }, latest.current.origin); });
}

/**
 * The sandboxed frame itself. `state`: what the widget kept, given to it as it loads; `onState` keeps what it keeps
 * next; `onError` hears a failure the content reports (a mermaid chart that would not parse).
 */
function Frame({ html, title, heightKey, state = null, onState, onError }: {
  html: string; title: string; heightKey: string; state?: unknown; onState?: (state: unknown) => void; onError?: (message: string) => void;
}) {
  const [height, setHeight] = useState(() => keptHeight(heightKey) ?? FIRST_HEIGHT);
  const frame = useRef<HTMLIFrameElement>(null);
  // A whole page sizes itself to its window (height:100%, a stage scaled to fit), so it has no height of its own to
  // be sized to: it gets a screen-shaped window instead (2026-09-30 a 1920×1080 player drawn 120 px tall, its
  // controls over all of it).
  const page = !isFragment(html);
  // Made once per content: a new document would reload the frame and lose what it holds (its state, a chart drawn).
  // The state is only what it starts with.
  const srcDoc = useMemo(() => (page ? pageDocument(html) : documentOf(html, state)), [html]); // eslint-disable-line react-hooks/exhaustive-deps
  const grown = useRef({ height: 0, times: 0 });
  const onHeight = (h: number) => {
    if (page || h <= 0) return;
    const last = grown.current;
    // Held, it stays so until its content is shorter than where it was held.
    if (last.times > RUNAWAY && h >= last.height) return;
    last.times = last.height > 0 && h > last.height && h - last.height <= 64 ? last.times + 1 : 0;
    if (last.times > RUNAWAY) return;
    last.height = h;
    setHeight(h);
    // Only a height it did not creep to is kept: one kept mid-run would start the next load's run further on.
    if (last.times === 0) keepHeight(heightKey, h);
  };
  useVizMessages(() => (frame.current?.contentWindow ? [frame.current.contentWindow] : []), { onHeight, ...(onState ? { onState } : {}), ...(onError ? { onError } : {}) });
  return <iframe ref={frame} className={page ? css.vizPage : css.vizFrame} sandbox="allow-scripts" srcDoc={srcDoc} title={title} style={page ? undefined : { height }} />;
}

/**
 * A visualization's file and what its widget kept (on the station, by the session that sent it and its path), loaded
 * together: it starts with both. Null while they come; `failed` when the file cannot be read.
 */
export function useVizFile(sessionKey: string, file: Attachment) {
  const api = useApi();
  const loaded = useFileText(sessionKey, file);
  const [state, setState] = useState<{ value: unknown } | null>(null);
  useEffect(() => {
    let current = true;
    // What the station cannot say (an older one) is nothing kept.
    void api.widgetState(sessionKey, file.path).then((r) => r.state, () => null).then((value) => { if (current) setState({ value }); });
    return () => { current = false; };
  }, [api, sessionKey, file.path]);
  const keep = (value: unknown) => void api.setWidgetState(sessionKey, file.path, value).catch(() => {});
  if (loaded.state === "error") return { failed: true as const };
  if (loaded.state !== "ready" || !state) return null;
  return { failed: false as const, html: loaded.text, state: state.value, keep };
}

/**
 * A placed HTML file, drawn in its message, with ways to open it on its own: beside the chat (OpenFile), over the
 * whole window (the file's preview, which also downloads it). `failed`: what shows instead when the file cannot be read
 * (its card).
 */
export function VizFile({ sessionKey, file, failed }: { sessionKey: string; file: Attachment; failed: ReactNode }) {
  const viz = useVizFile(sessionKey, file);
  const open = useContext(OpenFile);
  const [previewing, setPreviewing] = useState(false);
  if (viz?.failed) return failed;
  const heightKey = fileHeightKey(sessionKey, file);
  // While the file comes, its place is as tall as it will be (as it was last time), its bar's room included.
  if (!viz) return <div className={css.viz} aria-busy="true"><div className={css.vizWait} style={{ height: keptHeight(heightKey) ?? FIRST_HEIGHT }} /><div className={css.vizBar} /></div>;
  return (
    <div className={css.viz}>
      <Frame html={viz.html} title={file.name} heightKey={heightKey} state={viz.state} onState={viz.keep} />
      <div className={css.vizBar}>
        <Tip label="全屏打开"><button type="button" className={css.vizOpen} aria-label="全屏打开" onClick={() => setPreviewing(true)}>
          <Expand size={14} strokeWidth={1.75} />
        </button></Tip>
        {open && (
          <Tip label="在侧边打开"><button type="button" className={css.vizOpen} aria-label="在侧边打开" onClick={() => open(sessionKey, file)}>
            <PanelOpen size={14} strokeWidth={1.75} />
          </button></Tip>
        )}
      </div>
      <FilePreview open={previewing} onClose={() => setPreviewing(false)} sessionKey={sessionKey} file={file} />
    </div>
  );
}

const MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";

/** A mermaid chart's document: the source, drawn by mermaid in ember's colours, drawn again when the theme changes. */
function mermaidDocument(code: string): string {
  return `<pre class="mermaid-src" hidden>${code.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</pre><div id="chart" style="display:flex;justify-content:center"></div>
<script type="module">
  const post = (m) => parent.postMessage({ emberViz: true, ...m }, "*");
  const source = document.querySelector(".mermaid-src").textContent;
  let mermaid;
  try { mermaid = (await import("${MERMAID}")).default; } catch (e) { post({ type: "failed", message: "mermaid 没能加载" }); }
  // Mermaid reads hex and rgb only: ember's oklch tokens are resolved to rgb through a canvas pixel.
  const pixel = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  const rgb = (color) => { pixel.clearRect(0, 0, 1, 1); pixel.fillStyle = "#000"; pixel.fillStyle = color; pixel.fillRect(0, 0, 1, 1); const [r, g, b] = pixel.getImageData(0, 0, 1, 1).data; return "rgb(" + r + ", " + g + ", " + b + ")"; };
  const v = (name) => { const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim(); return name === "--font-sans" ? value : rgb(value); };
  let n = 0;
  async function draw() {
    if (!mermaid) return;
    try {
      mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "base", fontFamily: v("--font-sans"), themeVariables: {
        darkMode: document.documentElement.dataset.theme === "dark", fontSize: "14px",
        background: v("--background"), primaryColor: v("--card"), primaryTextColor: v("--foreground"), primaryBorderColor: v("--border-strong"),
        secondaryColor: v("--accent"), tertiaryColor: v("--muted"), lineColor: v("--muted-foreground"), textColor: v("--foreground"),
        noteBkgColor: v("--accent"), noteTextColor: v("--foreground"), noteBorderColor: v("--brand"),
        actorBkg: v("--card"), actorBorder: v("--border-strong"), actorTextColor: v("--foreground"), signalColor: v("--foreground"), signalTextColor: v("--foreground"),
      } });
      const { svg } = await mermaid.render("chart-" + ++n, source);
      document.getElementById("chart").innerHTML = svg;
    } catch (e) { post({ type: "failed", message: String(e?.message ?? e) }); }
  }
  addEventListener("ember-viz:theme", draw);
  draw();
</script>`;
}

/** A ```mermaid block: drawn as a chart; shown as code while it will not draw (mermaid not reachable, or the source does not parse). */
export function Mermaid({ code }: { code: string }) {
  const [failed, setFailed] = useState(false);
  const html = useMemo(() => mermaidDocument(code), [code]);
  if (failed) return <Code text={code} language="mermaid" />;
  return <div className={css.viz}><Frame html={html} title="mermaid" heightKey={mermaidHeightKey(code)} onError={() => setFailed(true)} /></div>;
}
