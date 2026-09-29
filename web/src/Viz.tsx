// An inline visualization: an HTML file an agent attached and placed in its message's text (`[title](figure.html)` on
// a line of its own), drawn there in a sandboxed frame instead of shown as a card; the ember-viz skill says how agents
// make one. After Codex's Visualize: only a file placed so is drawn, never a code block, so nothing half written is.
// The frame runs the file's scripts but has no origin of the page's: it cannot reach the page, its storage or the
// station, and its CSP lets it load scripts and styles from a few public CDNs only, with no requests of its own. The
// page hands it ember's tokens for the theme it shows (viz/ember-viz.css maps them to the names agents write against),
// sizes it to its content, keeps what the widget asks to keep (widgetState), and puts what it asks to send
// (sendFollowUpMessage, on a click) in the chat's composer for the person to send.
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
const MAX_STATE = 16 * 1024;
const STATE_PREFIX = "ember.viz.";

function scheme(): "light" | "dark" {
  return getComputedStyle(document.documentElement).colorScheme.includes("dark") ? "dark" : "light";
}

function tokens(): Record<string, string> {
  const style = getComputedStyle(document.documentElement);
  return Object.fromEntries(TOKENS.map((name) => [`--e-${name}`, style.getPropertyValue(`--${name}`).trim()]).filter(([, v]) => v));
}

/** What a widget kept, on this device (Codex keeps it with the message; here it is the browser's, for now). */
function readState(key: string): unknown {
  try { return JSON.parse(localStorage.getItem(STATE_PREFIX + key) ?? "null"); } catch { return null; }
}

/** JSON for inside a <script> element: nothing in it can end the element. */
const scriptJson = (value: unknown) => JSON.stringify(value).replace(/</g, "\\u003c");

/** The frame's document: the file in the stylesheet, the bridge (and what the widget kept) ahead of it, the theme as the page shows it now. */
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

/** `stateKey`: whose widget this is (the station, session and file), for what it keeps. */
export function Viz({ html, name, stateKey }: { html: string; name: string; stateKey: string }) {
  const [showSource, setShowSource] = useState(false);
  const [height, setHeight] = useState(0);
  const frame = useRef<HTMLIFrameElement>(null);
  const draftKey = useContext(DraftKey);
  const toast = useToast();
  // Made once per file: a new document would reload the frame and lose what it holds (its state, a chart drawn).
  const srcDoc = useMemo(() => documentOf(html, readState(stateKey)), [html, stateKey]);
  const latest = useRef({ draftKey, toast, stateKey });
  latest.current = { draftKey, toast, stateKey };

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as { emberViz?: boolean; type?: string; [k: string]: unknown } | null;
      if (event.source !== frame.current?.contentWindow || !data?.emberViz) return;
      const { draftKey, toast, stateKey } = latest.current;
      if (data.type === "height" && typeof data.height === "number") setHeight(Math.min(MAX_HEIGHT, data.height));
      if (data.type === "state") {
        const json = JSON.stringify(data.state ?? null);
        if (json.length <= MAX_STATE) localStorage.setItem(STATE_PREFIX + stateKey, json);
      }
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

  return (
    <div className={css.viz}>
      {showSource
        ? <Code text={html} language="html" />
        : <iframe ref={frame} className={css.vizFrame} sandbox="allow-scripts" srcDoc={srcDoc} title={name} style={{ height: height || 120 }} />}
      <div className={css.vizBar}>
        <button type="button" className={css.vizToggle} onClick={() => setShowSource(!showSource)} aria-pressed={showSource}>
          {showSource ? "看预览" : "看源码"}
        </button>
      </div>
    </div>
  );
}
