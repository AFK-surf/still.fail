// Inline visualizations: an HTML file an agent attached and placed in its message's text (`[title](figure.html)` on a
// line of its own), drawn there in a sandboxed frame instead of shown as a card; the ember-viz skill says how agents
// make one. After Codex's Visualize: only a file placed so is drawn, never an html code block, so nothing half written
// is. A ```mermaid block is drawn the same way, by mermaid loaded into a frame of its own.
//
// The frame runs the file's scripts but has no origin of the page's: it cannot reach the page, its storage or the
// station, and its CSP lets it load scripts and styles from a few public CDNs only, with no requests of its own. The
// page hands it ember's tokens for the theme it shows (viz/ember-viz.css maps them to the names agents write against),
// sizes it to its content, keeps what the widget asks to keep (widgetState, on the station, whose model part reaches
// the agent with the next message), and puts what it asks to send (sendFollowUpMessage, on a click) in the chat's
// composer for the person to send.
import { useContext, useEffect, useMemo, useRef, useState } from "react";
import bridge from "./viz/bridge.js?raw";
import stylesheet from "./viz/ember-viz.css?raw";
import { Code } from "./Prose.tsx";
import { DraftKey, offerToDraft } from "./draft.ts";
import { useToast } from "./toast.tsx";
import * as css from "./Viz.css.ts";

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

/** Past this the frame scrolls within itself. */
const MAX_HEIGHT = 1200;
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
 * The sandboxed frame itself. `state`: what the widget kept, given to it as it loads; `onState` keeps what it keeps
 * next; `onError` hears a failure the content reports (a mermaid chart that would not parse).
 */
function Frame({ html, title, state = null, onState, onError }: {
  html: string; title: string; state?: unknown; onState?: (state: unknown) => void; onError?: (message: string) => void;
}) {
  const [height, setHeight] = useState(0);
  const frame = useRef<HTMLIFrameElement>(null);
  const draftKey = useContext(DraftKey);
  const toast = useToast();
  // Made once per content: a new document would reload the frame and lose what it holds (its state, a chart drawn).
  // The state is only what it starts with.
  const srcDoc = useMemo(() => documentOf(html, state), [html]); // eslint-disable-line react-hooks/exhaustive-deps
  const latest = useRef({ draftKey, toast, onState, onError });
  latest.current = { draftKey, toast, onState, onError };

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as { emberViz?: boolean; type?: string; [k: string]: unknown } | null;
      if (event.source !== frame.current?.contentWindow || !data?.emberViz) return;
      const { draftKey, toast, onState, onError } = latest.current;
      if (data.type === "height" && typeof data.height === "number") setHeight(Math.min(MAX_HEIGHT, data.height));
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

  useThemeChange(() => frame.current?.contentWindow?.postMessage({ emberViz: true, type: "theme", tokens: tokens(), scheme: scheme() }, "*"));

  return <iframe ref={frame} className={css.vizFrame} sandbox="allow-scripts" srcDoc={srcDoc} title={title} style={{ height: height || 120 }} />;
}

/** A placed HTML file, drawn; `onOpen` opens the file itself (whole screen, its source, a download). */
export function Viz({ html, name, state, onState, onOpen }: {
  html: string; name: string; state: unknown; onState(state: unknown): void; onOpen(): void;
}) {
  return (
    <div className={css.viz}>
      <Frame html={html} title={name} state={state} onState={onState} />
      <div className={css.vizBar}>
        <button type="button" className={css.vizToggle} onClick={onOpen}>打开文件</button>
      </div>
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
  return <div className={css.viz}><Frame html={html} title="mermaid" onError={() => setFailed(true)} /></div>;
}
