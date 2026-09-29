// An inline visualization: an ```html block of a message, drawn in place in a sandboxed frame instead of shown as
// code (skills/ember-viz.md says how agents write one). The frame runs the block's scripts but has no origin of the
// page's: it cannot reach the page, its storage or the station, and its CSP lets it load scripts and styles from a
// few public CDNs only, with no requests of its own. The page hands it ember's tokens for the theme it shows
// (viz/ember-viz.css maps them to the names agents write against) and sizes it to its content.
import { useEffect, useMemo, useRef, useState } from "react";
import bridge from "./viz/bridge.js?raw";
import stylesheet from "./viz/ember-viz.css?raw";
import { Code } from "./Prose.tsx";
import * as css from "./Viz.css.ts";

/** ember's tokens a frame is given, as --e-<name> (tokens.css.ts names them). */
const TOKENS = [
  "font-body", "font-mono", "canvas", "raised", "text", "muted", "subtle", "line", "line-strong", "hover", "selected",
  "paper", "accent", "accent-text", "accent-bg", "blue", "blue-bg", "code-inline", "green", "green-bg", "amber",
  "amber-bg", "red", "red-bg", "neutral-bg", "shadow", "primary", "primary-hover", "on-primary", "field-hover",
  "field-focus", "r-field", "r-card", "corner-shape",
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

function scheme(): "light" | "dark" {
  return getComputedStyle(document.documentElement).colorScheme.includes("dark") ? "dark" : "light";
}

function tokens(): Record<string, string> {
  const style = getComputedStyle(document.documentElement);
  return Object.fromEntries(TOKENS.map((name) => [`--e-${name}`, style.getPropertyValue(`--${name}`).trim()]).filter(([, v]) => v));
}

/** The frame's document: the block's HTML in the stylesheet, the bridge ahead of it, the theme as the page shows it now. */
function documentOf(html: string): string {
  const now = tokens();
  const vars = Object.entries(now).map(([k, v]) => `${k}:${v.replace(/[<>]/g, "")}`).join(";");
  const theme = scheme();
  return `<!doctype html><html data-theme="${theme}"><head><meta charset="utf-8">`
    + `<meta http-equiv="Content-Security-Policy" content="${CSP}">`
    + `<style>:root{color-scheme:${theme};${vars}}</style><style>${stylesheet}</style><script>${bridge}</script></head><body>${html}</body></html>`;
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

export function Viz({ html }: { html: string }) {
  const [showSource, setShowSource] = useState(false);
  const [height, setHeight] = useState(0);
  const frame = useRef<HTMLIFrameElement>(null);
  // Made once per block: a new document would reload the frame and lose what it holds (its state, a chart drawn).
  const srcDoc = useMemo(() => documentOf(html), [html]);

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.source !== frame.current?.contentWindow || !event.data?.emberViz) return;
      if (event.data.type === "height" && typeof event.data.height === "number") setHeight(Math.min(MAX_HEIGHT, event.data.height));
    };
    addEventListener("message", onMessage);
    return () => removeEventListener("message", onMessage);
  }, []);

  useThemeChange(() => frame.current?.contentWindow?.postMessage({ emberViz: true, type: "theme", tokens: tokens(), scheme: scheme() }, "*"));

  return (
    <div className={css.viz}>
      {showSource
        ? <Code text={html} language="html" />
        : <iframe ref={frame} className={css.vizFrame} sandbox="allow-scripts" srcDoc={srcDoc} title="可视化" style={{ height: height || 120 }} />}
      <div className={css.vizBar}>
        <button type="button" className={css.vizToggle} onClick={() => setShowSource(!showSource)} aria-pressed={showSource}>
          {showSource ? "看预览" : "看源码"}
        </button>
      </div>
    </div>
  );
}
