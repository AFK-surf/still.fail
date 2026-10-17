// Inline visualizations (web/src/Viz.tsx): an HTML file an agent attached and placed in its message's text
// (`[title](figure.html)` on a line of its own), drawn there in a WebView instead of shown as a card; a ```mermaid block
// is drawn the same way, by mermaid (from the CDN the web loads it from) in a page of its own.
//
// The page is the web's: its stylesheet and bridge (web/src/viz/ember-viz.css, bridge.js, as VizAssets.ts has them), the
// web's tokens for the theme shown (as --e-*), the same CSP (scripts and styles from a few public CDNs, no requests
// of its own). It is as tall as its content (the bridge says), keeps what the widget asks to keep (widget.setState,
// on the station, given back by widget.state as it loads), and puts what it asks to send (sendFollowUpMessage, on a
// tap) in the chat's composer for the person to send (LocalFollowUp). (The Android app's ui/Viz.kt.)
import { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import { Linking, Modal, Pressable, Text, View, useWindowDimensions, type StyleProp, type ViewStyle } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { WebView, type WebViewMessageEvent } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import { app } from "../AppState";
import { t } from "../i18n";
import { Icon, Icons } from "./Icon";
import { CodeBlock } from "./Markdown";
import { Smooth } from "./Smooth";
import { useC, withAlpha } from "./Theme";
import { bridge, stylesheet } from "./VizAssets";

/** What a page says it keeps: any JSON. */
export type JsonElement = unknown;

/**
 * Where words a visualization asks to send go: the chat's composer (answers whether it took them). None: the chat
 * shown cannot send, and the widget is told so.
 */
export const LocalFollowUp = createContext<((words: string) => boolean) | null>(null);

/** Past this the page scrolls within itself. */
const MAX_HEIGHT = 1200;
/** What a widget may keep, as Codex's Visualize allows. */
const MAX_STATE = 16 * 1024;

/** The web's tokens a page is given, as --e-<name> (web/src/styles/global.css.ts, as its root has them). */
const LIGHT_TOKENS: Record<string, string> = {
  canvas: "oklch(100% 0 0)", raised: "#e4e4e8", text: "oklch(27% .009 255)", muted: "oklch(52% .012 255)",
  subtle: "oklch(57% .01 255)", line: "oklch(91% .005 85)", "line-strong": "oklch(82% .008 255)",
  hover: "oklch(25% .02 85 / .065)", selected: "oklch(93% .009 85)", paper: "oklch(96.3% .012 88)",
  accent: "oklch(68% .175 39)", "accent-text": "oklch(48% .155 38)", "accent-bg": "oklch(96.5% .025 45)",
  blue: "oklch(49% .18 260)", "blue-bg": "oklch(96% .02 260)", "code-inline": "#7C3FA0", green: "oklch(46% .11 158)",
  "green-bg": "oklch(96% .02 158)", amber: "oklch(48% .10 73)", "amber-bg": "oklch(97% .028 85)", red: "oklch(48% .15 22)",
  "red-bg": "oklch(97% .02 22)", "neutral-bg": "oklch(95% .004 255)", shadow: "oklch(20% .01 255 / .10)", primary: "#24272b",
  "primary-hover": "#41464c", "on-primary": "#fff", "field-hover": "#9a9ea3", "field-focus": "#646970",
  "r-field": "12px", "r-card": "20px", "corner-shape": "round",
};
const DARK_TOKENS: Record<string, string> = {
  ...LIGHT_TOKENS,
  canvas: "#1f2023", raised: "#2a2c31", text: "#e9e9ea", muted: "#a3a5a9", subtle: "#8c8f94", line: "#2d2e32",
  "line-strong": "#3d3f44", hover: "rgb(255 255 255 / .05)", selected: "#323338", paper: "#26272b",
  accent: "oklch(72% .16 42)", "accent-text": "oklch(78% .13 45)", "accent-bg": "oklch(30% .05 40)", blue: "oklch(75% .12 260)",
  "code-inline": "#C9A2E6", "blue-bg": "oklch(30% .05 260)", green: "oklch(76% .12 158)", "green-bg": "oklch(30% .04 158)",
  amber: "oklch(80% .12 80)", "amber-bg": "oklch(32% .05 80)", red: "oklch(74% .14 22)", "red-bg": "oklch(30% .05 22)",
  "neutral-bg": "#2a2b2f", shadow: "oklch(0% 0 0 / .45)", primary: "#eceded", "primary-hover": "#d3d4d6", "on-primary": "#1f2023",
  "field-hover": "#5d6066", "field-focus": "#8a8d93",
};

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

function tokens(dark: boolean): [string, string][] {
  return Object.entries(dark ? DARK_TOKENS : LIGHT_TOKENS).map(([k, v]) => [`--e-${k}`, v]);
}

const tokensJson = (dark: boolean) => JSON.stringify(Object.fromEntries(tokens(dark)));

/**
 * What the bridge says to its page (it posts to its parent, which in a WebView of its own is itself), handed to the
 * app: its height, what it keeps, a failure, words to send.
 */
const RELAY = `addEventListener("message",function(e){if(e.source===window&&e.data&&e.data.emberViz&&e.data.type!=="theme"){try{window.ReactNativeWebView.postMessage(JSON.stringify(e.data))}catch(_){}}});`;

/** The page: the content in the stylesheet, the bridge (and what the widget kept) ahead of it, the theme as the app shows it now. */
function documentOf(html: string, state: JsonElement | null | undefined, dark: boolean): string {
  const vars = tokens(dark).map(([k, v]) => `${k}:${v.replace(/[<>]/g, "")}`).join(";");
  const theme = dark ? "dark" : "light";
  const kept = JSON.stringify({ widgetState: state ?? null }).replace(/</g, "\\u003c");
  return `<!doctype html><html data-theme="${theme}"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1">` +
    `<meta http-equiv="Content-Security-Policy" content="${CSP}">` +
    `<style>:root{color-scheme:${theme};${vars}}</style><style>${stylesheet}</style>` +
    `<script type="application/json" id="ember-viz-state">${kept}</script>` +
    `<script>${RELAY}</script><script>${bridge}</script></head><body>${html}</body></html>`;
}

/** Where the first of these tags ends in `html`, or null. */
function afterTag(html: string, ...tags: RegExp[]): number | null {
  for (const tag of tags) {
    const m = tag.exec(html);
    if (m) return m.index + m[0].length;
  }
  return null;
}

/**
 * A whole page's document (a file that is not a fragment: a player, an app, a page made to fill a window), drawn as
 * written, not in the stylesheet: only the sandbox's CSP and the bridge (with the relay to the app) go into its head,
 * after its doctype, html or head tag so it keeps its mode (web Viz.tsx → pageDocument).
 */
function pageDocument(html: string): string {
  const head = `<meta http-equiv="Content-Security-Policy" content="${CSP}"><script>${RELAY}</script><script>${bridge}</script>`;
  const at = afterTag(html, /<head[^>]*>/i, /<html[^>]*>/i, /<!doctype[^>]*>/i);
  return at != null ? html.substring(0, at) + head + html.substring(at) : head + html;
}

/** Whether an HTML file is a fragment (as the viz skill has agents write them), to be drawn in the stylesheet. */
export function isFragment(html: string): boolean {
  return !/<!doctype|<html[\s>]/i.test(html.substring(0, 2048));
}

/** A string's hash as the JVM's String.hashCode makes it (the Kotlin's key for a page's height). */
function hashCode(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  return h;
}

/** Heights pages were last drawn at, so one drawn again (scrolled back to) takes its room at once. */
const heights = new Map<number, number>();

/** Opens a link of a page as the app opens links (still.fail's own in the app, the rest by the system); said when it cannot. */
function follow(url: string) {
  app.follow(url, () => { void Linking.openURL(url).catch(() => { app.note(t("android-misc.link.cantOpen")); }); });
}

/**
 * The page itself, in a WebView. `fill`: it takes the room it is given (a page of its own) rather than its
 * content's height. `onState` keeps what the widget keeps next; `onError` hears a failure it reports.
 */
export function VizFrame({ html, state = null, fill = false, modifier, onState, onError }: {
  html: string; state?: JsonElement | null; fill?: boolean; modifier?: StyleProp<ViewStyle>;
  onState?: ((state: JsonElement) => void) | null; onError?: ((message: string) => void) | null;
}) {
  const C = useC();
  const dark = C.dark;
  const followUp = useContext(LocalFollowUp);
  const latest = useRef({ onState, onError, followUp });
  latest.current = { onState, onError, followUp };
  const id = useMemo(() => hashCode(html), [html]);
  const [height, setHeight] = useState(() => heights.get(id) ?? 0);
  useEffect(() => { setHeight(heights.get(id) ?? 0); }, [id]);
  // Made once per content: a new page would lose what it holds (its state, a chart drawn). The theme is told to it as it changes.
  // A whole page sizes itself to its window (height:100%, a stage scaled to fit), so it has no height of its own to be
  // sized to: in a message it gets a screen-shaped window instead (web: a 16:9 window of the message's width, at most
  // 80% of the screen's height, its corners the card's, on the paper).
  const page = useMemo(() => !isFragment(html), [html]);
  // eslint-disable-next-line react-hooks/exhaustive-deps -- made once per content, in the theme it first shows
  const doc = useMemo(() => (page ? pageDocument(html) : documentOf(html, state, dark)), [html]);
  const web = useRef<WebView>(null);
  // The theme the page was made in (a fragment's document carries it): told only when it changes, as a page told it
  // as it loads draws again (a chart redrawn, a mermaid chart made twice).
  const told = useRef(dark);
  useEffect(() => { told.current = dark; }, [html]);
  useEffect(() => {
    if (dark === told.current) return;
    told.current = dark;
    web.current?.injectJavaScript(`postMessage({emberViz:true,type:"theme",tokens:${tokensJson(dark)},scheme:"${dark ? "dark" : "light"}"},"*");true;`);
  }, [dark]);
  // Shown once the page has drawn itself (a fragment at the height it says), not while the WebView is still blank or
  // drawn at the height it had before: what is under it shows meanwhile, then the page at once.
  const [shown, setShown] = useState(false);
  const revealed = useRef(false);
  useEffect(() => { revealed.current = false; setShown(false); }, [html]);
  /** Shows the page once what it has now is drawn (its height applied first: the next layout, then the page's own frame), once. */
  const reveal = () => {
    if (revealed.current) return;
    revealed.current = true;
    // NATIVE: WebView.postVisualStateCallback (shown once the page's frame with its new height is drawn) is not in
    // react-native-webview; two frames stand in for it (the height laid out, then the page drawn at it).
    requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)));
  };
  const onMessage = (e: WebViewMessageEvent) => {
    let m: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(e.nativeEvent.data);
      if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) return;
      m = parsed as Record<string, unknown>;
    } catch { return; }
    const { onState: keep, onError: failed, followUp: send } = latest.current;
    // The page says what it likes: a field that is not what it should be is let go.
    try {
      switch (m.type) {
        case "height": {
          if (page) break;
          const h = typeof m.height === "number" ? m.height : typeof m.height === "string" ? Number(m.height) : NaN;
          if (!Number.isFinite(h)) break;
          const tall = Math.min(MAX_HEIGHT, Math.ceil(h));
          heights.set(id, tall);
          setHeight(tall);
          reveal();
          break;
        }
        case "state": {
          const s = m.state ?? null;
          if (JSON.stringify(s).length <= MAX_STATE) keep?.(s);
          break;
        }
        case "failed": if (typeof m.message === "string") failed?.(m.message); break;
        case "followup": {
          const words = typeof m.prompt === "string" ? m.prompt.trim() : "";
          if (words.length > 0) app.note(send?.(words.substring(0, 4000)) === true ? t("android-misc.viz.followupDrafted") : t("android-misc.viz.cantSend"));
          break;
        }
      }
    } catch { /* let go */ }
  };
  // Links in a page leave it for the browser (or still.fail's own, the app); the page itself stays.
  const onShouldStartLoadWithRequest = (r: ShouldStartLoadRequest) => {
    const url = r.url;
    if (url === "about:blank" || url.startsWith("data:")) return true;
    if (r.isTopFrame !== false && (url.startsWith("http://") || url.startsWith("https://"))) setTimeout(() => follow(url), 0);
    return false;
  };
  const most = useWindowDimensions().height * 0.8;
  const [width, setWidth] = useState<number | null>(null);
  const view = (
    <WebView
      ref={web}
      source={{ html: doc }}
      originWhitelist={["*"]}
      javaScriptEnabled
      domStorageEnabled={false}
      allowFileAccess={false}
      // NATIVE: WebSettings.allowContentAccess = false and offscreenPreRaster = true are not props of
      // react-native-webview. The second keeps all of the page drawn, not only what was last in view: the chat's list
      // is the source of its frosted bars, which draw it a second time, clipped to the bar; drawn so, the page dropped
      // the rest and showed blank for a frame each time the bars were drawn again (a caret blinking, an agent at work).
      // Drawn once a frame, into a layer of its own, which the list and each pane of glass over it then draw: the
      // system WebView (154 at least) ends the app when one WebView is drawn four times before the frame is sent (its
      // queue of draws grows and drops one, CHECK(state.draw_context) in aw_vulkan_context_provider.cc), and a tall page
      // under the bar, the composer and the bottom bar's glass and ball is.
      androidLayerType="hardware"
      showsVerticalScrollIndicator={fill}
      showsHorizontalScrollIndicator={false}
      overScrollMode="never"
      // In a list, an upright drag on the page moves the list, as it would over anything else in the message: the page
      // keeps taps and sideways drags (its own controls, a chart's slider). Here the list's own native scrolling takes
      // it, fling included: with nested scrolling off the WebView leaves an upright drag to the list it is in.
      nestedScrollEnabled={false}
      // A whole page (or a fragment that never says its height) is shown once it has loaded and drawn.
      onLoadEnd={reveal}
      onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
      onMessage={onMessage}
      style={{ flex: 1, backgroundColor: "transparent", opacity: shown ? 1 : 0 }}
      containerStyle={{ backgroundColor: "transparent" }}
    />
  );
  if (fill) return <View style={modifier}>{view}</View>;
  if (page) {
    const h = width == null ? 0 : Math.min(Math.trunc((width * 9) / 16), most);
    return (
      <View style={[modifier, { alignSelf: "stretch" }]} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
        <Smooth radius={20} style={{ height: h, backgroundColor: dark ? "#26272B" : "#F6F2EA" }}>{width != null && view}</Smooth>
      </View>
    );
  }
  return <View style={[modifier, { alignSelf: "stretch", height: height > 0 ? height : 120 }]}>{view}</View>;
}

/** A visualization over the whole screen: the page as tall as the screen, its name and a close over it. */
export function VizFull({ name, html, state, keep, onClose }: { name: string; html: string; state: JsonElement | null | undefined; keep: (state: JsonElement) => void; onClose: () => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <Modal visible animationType="none" transparent={false} statusBarTranslucent navigationBarTranslucent onRequestClose={onClose}>
      <View style={{ flex: 1, backgroundColor: C.bg, paddingTop: insets.top, paddingBottom: insets.bottom, paddingLeft: insets.left, paddingRight: insets.right }}>
        <View style={{ flex: 1 }}>
          <View style={{ alignSelf: "stretch", height: 48, paddingLeft: 18, paddingRight: 8, flexDirection: "row", alignItems: "center" }}>
            <Text numberOfLines={1} style={{ fontSize: 15, lineHeight: 21, color: C.ink, flex: 1, minWidth: 0, includeFontPadding: false }}>{name}</Text>
            <Pressable onPress={onClose} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
              <Icon icon={Icons.Close} size={18} color={C.ink} />
            </Pressable>
          </View>
          <VizFrame html={html} state={state} fill modifier={{ alignSelf: "stretch", flex: 1, marginHorizontal: 12 }} onState={keep} />
        </View>
      </View>
    </Modal>
  );
}

const MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";

/** A mermaid chart's page: the source, drawn by mermaid in the web's colours, drawn again when the theme changes (web/src/Viz.tsx). */
function mermaidDocument(code: string): string {
  return `<pre class="mermaid-src" hidden>${code.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</pre><div id="chart" style="display:flex;justify-content:center"></div>
<script type="module">
  const post = (m) => parent.postMessage({ emberViz: true, ...m }, "*");
  const source = document.querySelector(".mermaid-src").textContent;
  let mermaid;
  try { mermaid = (await import("${MERMAID}")).default; } catch (e) { post({ type: "failed", message: ${JSON.stringify(t("android-misc.viz.mermaidFailed"))} }); }
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

/** Charts that would not draw (mermaid not reachable, or the source does not parse): shown as code from then on. */
const unmade = new Set<string>();

/** A ```mermaid block: drawn as a chart; shown as code while it will not draw. */
export function Mermaid({ code }: { code: string }) {
  const [failed, setFailed] = useState(() => unmade.has(code));
  useEffect(() => { setFailed(unmade.has(code)); }, [code]);
  const html = useMemo(() => mermaidDocument(code), [code]);
  if (failed) return <CodeBlock code={code} language="mermaid" />;
  return <View style={{ alignSelf: "stretch" }}><VizFrame html={html} onError={() => { unmade.add(code); setFailed(true); }} /></View>;
}

/**
 * A visualization's document as a page of the preview serves it (web Preview.tsx FileFrame → vizDocument): the file in
 * the stylesheet with what its widget kept (a whole page as written), and `script` (the preview's own page script)
 * inline ahead of the rest, as the page's CSP lets no script of the page's host in. (Kotlin's `context`, for the
 * assets, is not needed here: VizAssets.ts has them.)
 */
export function vizServed(html: string, state: JsonElement | null | undefined, dark: boolean, script: string): string {
  const doc = isFragment(html) ? documentOf(html, state, dark) : pageDocument(html);
  const tag = "<script>" + script.replace(/<\/script/g, "<\\/script") + "</script>";
  const at = afterTag(doc, /<head[^>]*>/i, /<html[^>]*>/i);
  return at != null ? doc.substring(0, at) + tag + doc.substring(at) : tag + doc;
}

/**
 * What a visualization's page says to the app (its bridge's relay, a WebView's onMessage): here only what its widget
 * keeps. The preview's WebView hands each message's data to `post`.
 */
export class VizKeeper {
  constructor(private readonly keep: (state: JsonElement) => void) {}
  post(json: string): void {
    let m: unknown;
    try { m = JSON.parse(json); } catch { return; }
    if (m == null || typeof m !== "object" || (m as { type?: unknown }).type !== "state") return;
    const state = (m as { state?: unknown }).state ?? null;
    if (JSON.stringify(state).length <= MAX_STATE) this.keep(state);
  }
}
