// A web service an agent started (a dev server, a report it serves), full screen over its chat: found by its job, known
// by its name (never its port), as web mobile's is (web/src/mobile/Preview.tsx over web/src/Preview.tsx). Its bar goes
// back, forward, reloads and says where it is (typed to go elsewhere); the page may be laid out at a size of its own
// (a phone's, a desktop's) on a canvas, moved and zoomed (PreviewStage.tsx), its sizes in a toolbar under the page, not
// over it; and it can be marked for the chat's agent (annotate/Marks.tsx): what is picked on the page, a word about
// each, then into the chat's draft with a screenshot per mark. The WebView's requests, sockets and marks go through
// PreviewWeb.tsx. The job is its chat's, kept as the chat changes (a restart is said over the page, which loads again
// once the service is back).
import * as Haptics from "expo-haptics";
import { useEffect, useMemo, useReducer, useRef, useState, type ReactNode } from "react";
import { BackHandler, Image, Keyboard, Linking, PixelRatio, Platform, Pressable, ScrollView, StyleSheet, TextInput, View, type ViewStyle } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Path, Rect, Text as SvgText } from "react-native-svg";
import { captureRef } from "react-native-view-shot";
import { WebView } from "react-native-webview";
import type { Attachment, Job } from "../../../../web/src/core/shapes.ts";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import { app, SheetSpec, type AppState } from "../AppState";
import { Topics } from "../data/Topics";
import { fromBase64 } from "../data/Calls";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { lerpColor, useC, withAlpha } from "../ui/Theme";
import { rememberStationName } from "../ui/ChatInk";
import { NavBar } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { WaitLine } from "../ui/Waiting";
import { VizKeeper, vizServed, type JsonElement } from "../ui/Viz";
import { DraftQuote, upload, type Draft, type Picked } from "./Composer";
import { JobDot, Tone } from "./Jobs";
import { keepViz, rememberViz } from "./VizFiles";
import type { Picture } from "./ChatFiles";
import { Watched, useWatched } from "../ui/Watched";
import { PreviewLoad } from "./PreviewLoad";
import { PAGE_SCRIPT } from "./PreviewPage";
import { PREVIEW_HOST, PreviewClient, PreviewLink, nativeShim, pageScript, pathOf, returned, type PreviewResponse } from "./PreviewWeb";

/** Draws again whenever `x` says it changed (Compose reading its snapshot state). */
function useChanges(x: { subscribe(l: () => void): () => void } | null) {
  const [, bump] = useReducer((n: number) => n + 1, 0);
  useEffect(() => (x ? x.subscribe(bump) : undefined), [x]);
}

/** What changes and is drawn from (Compose's mutableStateOf holders): `changed` says so. */
class Held {
  readonly #listeners = new Set<() => void>();
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  changed() { for (const l of this.#listeners) l(); }
}

/** How far the keyboard has come up. */
function useIme(): number {
  const [h, setH] = useState(0);
  useEffect(() => {
    const show = Keyboard.addListener("keyboardDidShow", (e) => setH(e.endCoordinates.height));
    const hide = Keyboard.addListener("keyboardDidHide", () => setH(0));
    return () => { show.remove(); hide.remove(); };
  }, []);
  return h;
}

/** `service`: its job's id. */
export function PreviewScreen({ station, service }: { station: string; service: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const ime = useIme();
  // Kept current by the core (its events, or read again from a station too old to send them).
  const found = useTopic<Job>(Topics.job(station, service));
  const job = found.value;
  const error = found.error?.message ?? null;
  const session = job?.session ?? null;
  const port = job?.port ?? null;
  const up = port != null && job?.open === true;
  const name = rememberStationName(station);
  let body: ReactNode;
  if (error !== null && !job) body = <PreviewNote text={t("android-chat.preview.notFound", { error })} />;
  else if (!job) body = <PreviewWait text={t("common.reading")} />;
  else if (!up) body = <PreviewNote text={t("android-chat.preview.stopped", { name: job.name })} />;
  else body = <ServicePage station={station} service={service} port={port!} name={job.name} restarting={job.state === "exited"} restarts={job.restarts ?? 0} session={session} />;
  return (
    <View style={{ flex: 1, paddingBottom: Math.max(ime, insets.bottom) }}>
      <NavBar back={t("android-chat.preview.back")} onBack={() => app.pop()} title={job?.name ?? t("android-chat.preview.service")} sub={() => <T size={11} color={C.muted} numberOfLines={1}>{name}</T>} />
      {body}
    </View>
  );
}

/**
 * A visualization an agent posted, as a page of its own (web mobile's Preview.tsx for a `file:` service): the file
 * served to the preview's page from here, with what its widget kept (and keeps from now on); its bar has only its name.
 */
export function PreviewFileScreen({ station, session, path, name }: { station: string; session: string; path: string; name: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const ime = useIme();
  const file = useMemo<Attachment>(() => ({ name, path, size: 0 }), [path, name]);
  const loaded = rememberViz(station, session, file);
  const stationName = rememberStationName(station);
  const kept = useRef<{ of: unknown; state: unknown }>({ of: null, state: null });
  let body: ReactNode;
  if (loaded.kind === "Failed") body = <PreviewNote text={t("android-chat.preview.unreadable", { name })} />;
  else if (loaded.kind === "Waiting") body = <PreviewWait text={t("common.opening")} />;
  else {
    const l = loaded;
    if (kept.current.of !== l) kept.current = { of: l, state: l.state };
    const page = new FilePage(l.html, () => kept.current.state, (s) => {
      kept.current.state = s;
      keepViz(station, session, path, s as JsonElement);
    });
    body = <ServicePage station={station} service={`file:${session}\n${path}`} port={0} name={name} restarting={false} restarts={0} session={session} file={page} />;
  }
  return (
    <View style={{ flex: 1, paddingBottom: Math.max(ime, insets.bottom) }}>
      <NavBar back={t("android-chat.preview.back")} onBack={() => app.pop()} title={name} sub={() => <T size={11} color={C.muted} numberOfLines={1}>{stationName}</T>} />
      {body}
    </View>
  );
}

/** A visualization's page for ServicePage: its file, what its widget keeps now, and keeping what it keeps next. */
class FilePage {
  constructor(readonly html: string, readonly state: () => unknown, readonly keep: (s: unknown) => void) {}
}

function PreviewNote({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} align="center" style={{ width: "100%", paddingHorizontal: 20, paddingVertical: 8 }}>{text}</T>;
}

/** What the page waits on, where its note would be (not a blank page). */
function PreviewWait({ text }: { text: string }) {
  return <View style={{ width: "100%", paddingHorizontal: 20, paddingVertical: 8, alignItems: "center" }}><WaitLine text={text} /></View>;
}

// ── the page's size (web/src/viewport.ts) ──────────────────────────────

/** A window `width` wide and `height` high (null: as high as the preview leaves it, at its scale). */
interface Viewport { width: number; height: number | null }

class Preset {
  constructor(readonly key: string, readonly width: number, readonly height: number) {}
  get name() { return t(`android-chat.preview.preset.${this.key}`); }
}
const PRESETS = [new Preset("phone", 390, 844), new Preset("tablet", 820, 1180), new Preset("laptop", 1280, 800), new Preset("desktop", 1440, 900)];
const LIMIT_MIN = 240;
const LIMIT_MAX = 3840;
const clampSize = (n: number) => Math.min(LIMIT_MAX, Math.max(LIMIT_MIN, n));

function presetOf(v: Viewport | null): string | null {
  if (v?.height == null) return null;
  return PRESETS.find((p) => (p.width === v.width && p.height === v.height) || (p.width === v.height && p.height === v.width))?.name ?? null;
}

/** `390 × 844`, with `×` a little apart. */
const dims = (w: number, h: number | null) => `${w} × ${h !== null ? String(h) : t("android-chat.preview.auto")}`;

/** Kept per service, on this device. */
const viewportKey = (station: string, service: string) => `previewViewport.${station}\n${service}`;
function viewportOf(app: AppState, key: string): Viewport | null {
  const kept = app.strings(key);
  const w = kept[0] !== undefined ? parseInt(kept[0], 10) : NaN;
  if (!Number.isFinite(w)) return null;
  const h = kept[1] !== undefined ? parseInt(kept[1], 10) : NaN;
  return { width: clampSize(w), height: Number.isFinite(h) ? clampSize(h) : null };
}
const keepViewport = (app: AppState, key: string, v: Viewport | null) => app.setStrings(key, v === null ? [] : [String(v.width), ...(v.height !== null ? [String(v.height)] : [])]);

const FOLDED = "previewToolbarFolded";

// ── the page: its bar, its stage, its toolbar ──────────────────────────

/** A mark: what was picked on the page (annotate/frame.ts's Picked), and what is said about it. */
interface Box4 { x: number; y: number; width: number; height: number }
interface Size2 { width: number; height: number }
interface PagePick {
  n: number; path: string; viewport: Size2; label: string; kind: string; selector: string;
  text: string; rect: Box4; page: Box4; component?: string | null;
}
class Mark { comment = ""; constructor(readonly picked: PagePick) {} }

/** A page's state that outlives its renders: where it is, its marks. */
class PageState extends Held {
  at: string | null = null;
  canBack = false;
  canForward = false;
  marking = false;
  marks: Mark[] = [];
  /** Where each mark is in the page's viewport, as the page last said; the viewport's width in CSS pixels. */
  at2 = new Map<number, Box4>();
  cssWidth = 0;
  editing: number | null = null;
  busy = false;
  error: string | null = null;
  set(change: (s: this) => void) { change(this); this.changed(); }
}

const isBox = (o: unknown): o is Box4 => !!o && typeof o === "object" && ["x", "y", "width", "height"].every((k) => typeof (o as Record<string, unknown>)[k] === "number");
function pickOf(o: unknown): PagePick | null {
  if (!o || typeof o !== "object") return null;
  const p = o as Record<string, unknown>;
  const v = p.viewport as Record<string, unknown> | undefined;
  if (typeof p.n !== "number" || typeof p.path !== "string" || !v || typeof v.width !== "number" || typeof v.height !== "number" || typeof p.label !== "string"
    || typeof p.kind !== "string" || typeof p.selector !== "string" || typeof p.text !== "string" || !isBox(p.rect) || !isBox(p.page)) return null;
  return p as unknown as PagePick;
}

/** The service's page under its bar; `restarting`: it ended and the station starts it again (`restarts` so far). */
function ServicePage({ station, service, port, name, restarting, restarts, session, file = null }: {
  station: string; service: string; port: number; name: string; restarting: boolean; restarts: number; session: string | null; file?: FilePage | null;
}) {
  const C = useC();
  const state = useMemo(() => new PageState(), []);
  useChanges(state);
  const link = useMemo(() => new PreviewLink(core(), station, port, PAGE_SCRIPT), [station, port]);
  useEffect(() => () => link.close(), [link]);
  // A visualization: its page is served from here (reloaded, with what it kept since), anything else it asks is not
  // there (as the web's FileFrame answers).
  const dark = C.dark;
  const enc = (s: string) => { const out: number[] = []; for (const ch of unescape(encodeURIComponent(s))) out.push(ch.charCodeAt(0)); return new Uint8Array(out); };
  const body = (bytes: Uint8Array) => { let given = false; return { read: async () => (given ? null : ((given = true), bytes)), close: () => undefined }; };
  if (file !== null) link.serve = (method, path): PreviewResponse => {
    const served = method === "GET" && !/\.[a-z0-9]+$/i.test(path.split("?")[0]!);
    if (!served) return { mime: "text/plain", charset: "utf-8", status: 404, reason: "Not Found", headers: {}, body: body(enc("Not found")) };
    const doc = vizServed(file.html, file.state(), dark, pageScript(PAGE_SCRIPT));
    return { mime: "text/html", charset: "utf-8", status: 200, reason: "OK", headers: { "Cache-Control": "no-store" }, body: body(enc(doc)) };
  };
  link.onViz = file !== null ? (json) => new VizKeeper((s: unknown) => file.keep(s)).post(json) : null;
  const webRef = useRef<WebView>(null);
  const shotRef = useRef<View>(null);
  const [doc, setDoc] = useState<{ html: string; baseUrl: string } | null>(null);
  const markingRef = useRef(state.marking);
  markingRef.current = state.marking;
  const js = (code: string) => { link.web?.injectJavaScript(code); };
  const client = useMemo(() => new PreviewClient(
    link,
    (at, canBack, canForward) => state.set((s) => { s.at = at; s.canBack = canBack; s.canForward = canForward; }),
    // Another page: the marks of the one before are gone (picking goes on).
    () => state.set((s) => { s.marks = []; s.at2.clear(); s.editing = null; }),
    () => { if (markingRef.current) js("__stillfailMarks&&__stillfailMarks.on(true)"); },
    (url) => app.openLink(url, false, null, () => { Linking.openURL(url).catch(() => { app.toast = t("android-chat.link.failed"); }); }),
    setDoc,
  ), [link]);
  const [size, setSize] = useState({ width: 0, height: 0 });
  link.web = {
    injectJavaScript: (code) => webRef.current?.injectJavaScript(code.endsWith("true;") ? code : `${code};true;`),
    reload: () => client.reload(),
    goBack: () => client.goBack(),
    goForward: () => client.goForward(),
    loadUrl: (url) => { void client.load(pathOf(url)); },
    width: size.width,
    height: size.height,
  };
  link.shot = async () => {
    const view = shotRef.current;
    if (!view || size.width === 0 || size.height === 0) return null;
    try {
      const uri = await captureRef(view, { format: "png", quality: 1, result: "tmpfile" });
      const got = await Image.getSize(uri);
      return { uri, width: got.width, height: got.height };
    } catch {
      return null;
    }
  };
  useEffect(() => { void client.load("/"); }, [client]);
  // The system's back steps the page back first; at its first page it leaves.
  useEffect(() => {
    if (!state.canBack) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { link.web?.goBack(); return true; });
    return () => sub.remove();
  }, [state.canBack]);
  // Up again after a restart: the page loads anew.
  const was = useRef(restarting);
  useEffect(() => {
    if (was.current && !restarting) link.web?.reload();
    was.current = restarting;
  }, [restarting]);
  const key = viewportKey(station, service);
  const [viewport, setViewportState] = useState<Viewport | null>(() => viewportOf(app, key));
  const setViewport = (v: Viewport | null) => { const c = v ? { width: clampSize(v.width), height: v.height !== null ? clampSize(v.height) : null } : null; setViewportState(c); keepViewport(app, key, c); };
  const [folded, setFolded] = useState(() => app.flag(FOLDED, false));
  const fold = (v: boolean) => { setFolded(v); app.setFlag(FOLDED, v); };
  const stage = useMemo(() => new StageState(), []);
  useChanges(stage);
  const turn = () => {
    const v = viewport;
    if (v?.height != null) { stage.setView(null); setViewport({ width: v.height, height: v.width }); }
  };
  // What the page's marking says.
  link.onMarked = (said) => {
    // The page's script says it (a page of the service may say anything there): what does not read is let go.
    try {
      switch (said.event) {
        case "picked": {
          const picked = pickOf(said.mark);
          if (picked) state.set((s) => {
            s.marks = [...s.marks, new Mark(picked)];
            s.at2.set(picked.n, picked.rect);
            s.cssWidth = picked.viewport.width;
            s.editing = picked.n;
            s.error = null;
          });
          break;
        }
        case "focus": state.set((s) => { s.editing = typeof said.n === "number" ? Math.trunc(said.n) : null; }); break;
        case "at": {
          const boxes = new Map<number, Box4>();
          if (Array.isArray(said.at)) for (const b of said.at as unknown[]) {
            const o = b as Record<string, unknown>;
            if (!o || typeof o !== "object" || typeof o.n !== "number" || !isBox(o)) continue;
            boxes.set(Math.trunc(o.n), { x: o.x as number, y: o.y as number, width: o.width as number, height: o.height as number });
          }
          state.set((s) => {
            const w = Number(said.width);
            if (Number.isFinite(w)) s.cssWidth = w;
            for (const k of [...s.at2.keys()]) if (!boxes.has(k)) s.at2.delete(k);
            for (const [k, v] of boxes) s.at2.set(k, v);
          });
          break;
        }
      }
    } catch {
      // let go
    }
  };
  const markable = session !== null;
  const leave = () => {
    state.set((s) => { s.marks = []; s.at2.clear(); s.editing = null; s.error = null; s.marking = false; });
    js("__stillfailMarks&&(__stillfailMarks.clear(),__stillfailMarks.on(false))");
  };
  const darkroom = useRef<Darkroom | null>(null);
  const [developing, setDeveloping] = useState<Developing | null>(null);
  darkroom.current = { develop: (d) => setDeveloping(d) };
  const shim = useMemo(() => nativeShim(file !== null) + "\n" + pageScript(PAGE_SCRIPT) + "\ntrue;", [file !== null]);
  return (
    <View style={{ flex: 1 }}>
      <PreviewBar
        name={name} at={state.at} loading={file === null ? () => <PreviewLoad station={station} port={port} /> : null} go={(path) => link.web?.loadUrl(`https://${PREVIEW_HOST}${path}`)} reload={() => link.web?.reload()}
        back={() => link.web?.goBack()} forward={() => link.web?.goForward()} canBack={state.canBack} canForward={state.canForward}
        size={folded ? () => <SizeButton viewport={viewport} onClick={() => fold(false)} /> : null} fixed={file !== null}
        extra={markable ? () => (
          <BarIcon icon={Icons.Edit} enabled pressed={state.marking} onClick={() => {
            const on = !state.marking;
            state.set((s) => { s.marking = on; });
            js(`__stillfailMarks&&__stillfailMarks.on(${on})`);
          }} />
        ) : null}
        instead={markable && (state.marking || state.marks.length > 0) ? () => (
          <MarkMode state={state} leave={leave} send={() => { void putIntoChat(app, link, state, station, session!, name, leave, darkroom.current!); }} />
        ) : null}
      />
      <Stage stage={stage} viewport={viewport} moving={stage.moving} onFit={() => stage.setView(null)}>
        {(placed) => (
          <>
            <View ref={shotRef} collapsable={false} style={place(placed)} onLayout={(e) => setSize({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
              {doc ? (
                <WebView
                  ref={webRef}
                  style={{ flex: 1, backgroundColor: "#FFFFFF" }}
                  originWhitelist={["*"]}
                  source={{ html: doc.html, baseUrl: doc.baseUrl }}
                  javaScriptEnabled
                  domStorageEnabled
                  injectedJavaScriptBeforeContentLoaded={shim}
                  injectedJavaScriptBeforeContentLoadedForMainFrameOnly
                  onMessage={(e) => link.said(e.nativeEvent.data)}
                  onShouldStartLoadWithRequest={client.onShouldStart}
                  onNavigationStateChange={client.onNavigationStateChange}
                  onLoadEnd={client.onLoadEnd}
                  setSupportMultipleWindows={false}
                />
              ) : <View style={{ flex: 1, backgroundColor: "#FFFFFF" }} />}
            </View>
            {markable && state.marks.length > 0 ? <MarksOver state={state} placed={placed} js={js} /> : null}
            {restarting ? <View pointerEvents="none" style={{ position: "absolute", left: 0, right: 0, bottom: 18, alignItems: "center" }}><Restart name={name} restarts={restarts} /></View> : null}
            {developing ? <DarkroomView d={developing} onDone={() => setDeveloping(null)} /> : null}
          </>
        )}
      </Stage>
      {!folded ? (
        <Dock sized={viewport !== null}>
          <Toolbar stage={stage} viewport={viewport} set={setViewport} turn={turn} fold={() => fold(true)} custom={() => openViewportSheet(app, viewport, setViewport, turn)} />
        </Dock>
      ) : null}
    </View>
  );
}

// ── the bar ────────────────────────────────────────────────────────────

/** Back, forward, reload, where it is (its name, then its path, typed to go elsewhere), then its size and marking. */
function PreviewBar({ name, at, go, reload, back, forward, canBack, canForward, loading = null, size, extra, instead, fixed = false }: {
  name: string; at: string | null; go: (path: string) => void; reload: () => void; back: () => void; forward: () => void; canBack: boolean; canForward: boolean;
  loading?: (() => ReactNode) | null; size: (() => ReactNode) | null; extra: (() => ReactNode) | null; instead: (() => ReactNode) | null; fixed?: boolean;
}) {
  const C = useC();
  const [typed, setTyped] = useState(at ?? "/");
  const [editing, setEditing] = useState(false);
  const field = useRef<TextInput>(null);
  // Where it went is what the bar says, unless someone is typing there.
  useEffect(() => { if (at !== null && !editing) setTyped(at); }, [at, editing]);
  return (
    <View style={{ width: "100%", paddingLeft: 14, paddingRight: 10, paddingTop: 4, paddingBottom: 6, flexDirection: "row", alignItems: "center", gap: 2 }}>
      <BarIcon icon={Icons.ArrowLeft} enabled={canBack} onClick={back} />
      <BarIcon icon={Icons.ArrowRight} enabled={canForward} onClick={forward} />
      <BarIcon icon={Icons.Refresh} enabled onClick={reload} />
      {loading?.()}
      {instead !== null ? <View style={{ flex: 1, paddingHorizontal: 4 }}>{instead()}</View> : (
        <View style={{ flex: 1, paddingHorizontal: 4 }}>
          <Smooth radius={15} stroke={editing ? { width: 1.5, color: withAlpha(C.accent, 0.5) } : undefined} style={{ height: 30, backgroundColor: editing ? C.surface : C.chip }}>
            <View style={{ height: 30, paddingHorizontal: 12, flexDirection: "row", alignItems: "center", gap: 6 }}>
              <Icon icon={Icons.Web} size={14} color={C.muted} />
              <T size={13} weight="500" color={C.ink} numberOfLines={1} style={fixed ? { flexShrink: 1 } : undefined}>{name}</T>
              {/* Nowhere else to go (a visualization): the address is only its name. */}
              {!fixed ? (
                <TextInput
                  ref={field}
                  value={typed}
                  onChangeText={setTyped}
                  multiline={false}
                  numberOfLines={1}
                  style={{ flex: 1, fontSize: 16, color: editing ? C.ink : C.muted, padding: 0, includeFontPadding: false }}
                  selectionColor={C.accent}
                  cursorColor={C.accent}
                  keyboardType="url"
                  autoCapitalize="none"
                  autoCorrect={false}
                  returnKeyType="go"
                  onFocus={() => setEditing(true)}
                  onBlur={() => setEditing(false)}
                  onSubmitEditing={() => { go(typed.startsWith("/") ? typed : `/${typed}`); field.current?.blur(); }}
                />
              ) : null}
            </View>
          </Smooth>
        </View>
      )}
      {size?.()}
      {extra?.()}
    </View>
  );
}

function BarIcon({ icon, enabled, pressed = false, onClick }: { icon: IconPaths; enabled: boolean; pressed?: boolean; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable disabled={!enabled} onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
      style={{ width: 28, height: 28, borderRadius: 14, overflow: "hidden", backgroundColor: pressed ? withAlpha(C.accent, 0.14) : "transparent", alignItems: "center", justifyContent: "center" }}>
      <View style={{ opacity: enabled ? 1 : 0.35 }}><Icon icon={icon} size={14} color={pressed ? C.accentInk : C.ink} /></View>
    </Pressable>
  );
}

/** The bar's size button, once the toolbar was folded away: it opens it again. */
function SizeButton({ viewport, onClick }: { viewport: Viewport | null; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={14} style={{ height: 28, backgroundColor: viewport !== null ? C.chip : "transparent" }}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
        style={{ height: 28, paddingHorizontal: viewport !== null ? 9 : 7, flexDirection: "row", alignItems: "center", gap: 5 }}>
        <Icon icon={Icons.Devices} size={14} color={C.ink} />
        {viewport !== null ? <T size={12} color={C.ink} numberOfLines={1}>{dims(viewport.width, viewport.height)}</T> : null}
      </Pressable>
    </Smooth>
  );
}

/** Over the page while its service starts again; once it is up the page loads anew. */
function Restart({ name, restarts }: { name: string; restarts: number }) {
  const C = useC();
  return (
    <View style={{ borderRadius: 999, elevation: 8, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 8, backgroundColor: C.surface, paddingLeft: 16, paddingRight: 18, paddingTop: 10, paddingBottom: 10, flexDirection: "row", alignItems: "center", gap: 12 }}>
      <JobDot tone={Tone.Restart} />
      <View>
        <T size={13} weight="600" color={C.ink}>{t("android-chat.preview.restarting", { name })}</T>
        <T size={12} color={C.muted}>{restarts > 0 ? t("android-chat.preview.restarts", { n: restarts }) : t("android-chat.preview.reloads")}</T>
      </View>
    </View>
  );
}

// ── the stage (PreviewStage.tsx) ───────────────────────────────────────

/** Where the page is drawn in the stage: its top-left, its scale, the size it is laid out at, its corner. */
interface Placed { x: number; y: number; scale: number; width: number; height: number; corner: number }
interface ViewAt { x: number; y: number; scale: number }
interface Point { x: number; y: number }

class StageState extends Held {
  /** Moved or zoomed by hand (null: fitted). */
  view: ViewAt | null = null;
  moving = false;
  placed: Placed | null = null;
  room = { width: 0, height: 0 };
  pad = { x: 0, y: 0 };
  setView(v: ViewAt | null) { this.view = v; this.changed(); }
  setMoving(on: boolean) { this.moving = on; this.changed(); }
  zoom(factor: number, about: Point | null = null) {
    const p = this.placed;
    if (!p) return;
    const scale = Math.min(4, Math.max(0.05, p.scale * factor));
    const at = about ?? { x: this.pad.x + this.room.width / 2, y: this.pad.y + this.room.height / 2 };
    this.setView({ x: at.x - ((at.x - p.x) * scale) / p.scale, y: at.y - ((at.y - p.y) * scale) / p.scale, scale });
  }
}

/** Two fingers gone from `was` to `at`: the page (drawn as `from` when they came down) zoomed by how far apart they went. */
function pinch(from: ViewAt, was: Point[], at: Point[]): ViewAt {
  const mid = (ps: Point[]) => ({ x: (ps[0]!.x + ps[1]!.x) / 2, y: (ps[0]!.y + ps[1]!.y) / 2 });
  const apart = (ps: Point[]) => Math.max(1, Math.hypot(ps[0]!.x - ps[1]!.x, ps[0]!.y - ps[1]!.y));
  const m0 = mid(was); const m1 = mid(at);
  const scale = Math.min(4, Math.max(0.05, (from.scale * apart(at)) / apart(was)));
  return { x: m1.x - ((m0.x - from.x) * scale) / from.scale, y: m1.y - ((m0.y - from.y) * scale) / from.scale, scale };
}

/** The page's corners, as its screen's: a phone's round, a tablet's less, a desktop's all but square. */
const cornerOf = (width: number, scale: number) => (width <= 600 ? 44 : width < 1024 ? 24 : 5 / scale);

/**
 * All of the preview, or — laid out at a size of its own — a canvas with the page on it: fitted and centred at first;
 * then the ground dragged (or, in the toolbar's moving mode, the page), two fingers anywhere zoom and move it, a double
 * tap on the ground fits it again. `children` gets where the page is (null: all of it).
 */
function Stage({ stage, viewport, moving, onFit, children }: { stage: StageState; viewport: Viewport | null; moving: boolean; onFit: () => void; children: (placed: Placed | null) => ReactNode }) {
  const C = useC();
  const ground = lerpColor(C.surface, C.chip, 0.55);
  // A size chosen (or turned) is fitted anew.
  useEffect(() => { stage.setView(null); }, [viewport?.width, viewport?.height]);
  const [box, setBox] = useState({ width: 0, height: 0 });
  const pad = viewport !== null ? 16 : 0;
  const roomW = box.width - 2 * pad;
  const roomH = box.height - 2 * pad;
  let placed: Placed | null = null;
  if (viewport !== null && roomW > 0 && roomH > 0) {
    const w = viewport.width;
    const fitted = Math.max(0.05, Math.floor(Math.min(1, roomW / w, viewport.height !== null ? roomH / viewport.height : 1) * 1000) / 1000);
    const free = stage.view;
    const scale = free?.scale ?? fitted;
    const h = viewport.height ?? Math.max(LIMIT_MIN, Math.floor(roomH / fitted));
    placed = {
      x: free?.x ?? Math.round(pad + Math.max(0, (roomW - w * scale) / 2)),
      y: free?.y ?? Math.round(pad + Math.max(0, (roomH - h * scale) / 2)),
      scale, width: w, height: h, corner: cornerOf(viewport.width, scale),
    };
  }
  stage.placed = placed;
  stage.room = { width: roomW, height: roomH };
  stage.pad = { x: pad, y: pad };
  const canvas = placed !== null;
  const fit = useRef(onFit);
  fit.current = onFit;
  const g = useRef({ grabbing: false, onPage: false, from: { x: 0, y: 0, scale: 1 } as ViewAt, was: [] as Point[], travelled: 0, began: 0, lastTap: 0, count: 0 });
  const gesture = useMemo(() => Gesture.Manual().runOnJS(true).enabled(canvas)
    .onTouchesDown((e, manager) => {
      const s = g.current;
      const at = e.allTouches.map((p) => ({ x: p.x, y: p.y }));
      if (s.count === 0) {
        const p0 = stage.placed;
        if (!p0) { manager.fail(); return; }
        const d = at[0]!;
        s.onPage = d.x >= p0.x && d.x <= p0.x + p0.width * p0.scale && d.y >= p0.y && d.y <= p0.y + p0.height * p0.scale;
        s.grabbing = stage.moving || !s.onPage;
        s.from = { x: p0.x, y: p0.y, scale: p0.scale };
        s.was = at;
        s.travelled = 0;
        s.began = Date.now();
        if (s.grabbing) manager.activate();
      } else {
        if (!s.grabbing && at.length >= 2) { s.grabbing = true; manager.activate(); }
        // A finger came: from where the page is now.
        const p = stage.placed;
        if (p) { s.from = { x: p.x, y: p.y, scale: p.scale }; s.was = at; }
      }
      s.count = at.length;
    })
    .onTouchesMove((e) => {
      const s = g.current;
      if (!s.grabbing) return;
      const at = e.allTouches.map((p) => ({ x: p.x, y: p.y }));
      if (at.length !== s.was.length) {
        const p = stage.placed;
        if (!p) return;
        s.from = { x: p.x, y: p.y, scale: p.scale }; s.was = at;
      } else if (at.length === 1) {
        s.travelled += Math.hypot(at[0]!.x - s.was[0]!.x, at[0]!.y - s.was[0]!.y);
        stage.setView({ x: s.from.x + at[0]!.x - s.was[0]!.x, y: s.from.y + at[0]!.y - s.was[0]!.y, scale: s.from.scale });
      } else stage.setView(pinch(s.from, s.was.slice(0, 2), at.slice(0, 2)));
    })
    .onTouchesUp((e, manager) => {
      const s = g.current;
      const left = e.allTouches.filter((p) => !e.changedTouches.some((c) => c.id === p.id));
      s.count = left.length;
      if (left.length > 0) {
        // A finger went: from where the page is now.
        const p = stage.placed;
        if (p) { s.from = { x: p.x, y: p.y, scale: p.scale }; s.was = left.map((p2) => ({ x: p2.x, y: p2.y })); }
        return;
      }
      // A double tap on the ground fits it again.
      if (!s.onPage && s.travelled < 12 && Date.now() - s.began < 300) {
        const now = Date.now();
        if (now - s.lastTap < 350) { fit.current(); s.lastTap = 0; } else s.lastTap = now;
      }
      if (s.grabbing) manager.end(); else manager.fail();
    })
    .onTouchesCancelled((_, manager) => { g.current.count = 0; manager.fail(); }), [canvas, moving]);
  return (
    <View style={{ flex: 1, width: "100%", overflow: "hidden", backgroundColor: viewport !== null ? ground : C.surface }} onLayout={(e) => setBox({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}>
      <GestureDetector gesture={gesture}>
        <View style={StyleSheet.absoluteFill} collapsable={false}>
          {/* Its slight shadow and its screen's corners are the page's view's own (place()). */}
          {children(placed)}
        </View>
      </GestureDetector>
    </View>
  );
}

/** Where the page's view is: all of the stage, or its own size at its place and scale, its screen's corners and shadow. */
function place(placed: Placed | null): ViewStyle {
  if (!placed) return StyleSheet.absoluteFillObject;
  return {
    position: "absolute", left: 0, top: 0, width: Math.round(placed.width), height: Math.round(placed.height),
    transformOrigin: "0 0",
    transform: [{ translateX: placed.x }, { translateY: placed.y }, { scale: placed.scale }],
    borderRadius: placed.corner, overflow: "hidden", elevation: 6, backgroundColor: "#FFFFFF",
  };
}

// ── the toolbar under the page (PreviewStage.tsx's Toolbar) ────────────

/** The toolbar's place, under the stage, on its ground. */
function Dock({ sized, children }: { sized: boolean; children: ReactNode }) {
  const C = useC();
  return <View style={{ width: "100%", backgroundColor: sized ? lerpColor(C.surface, C.chip, 0.55) : C.surface, paddingLeft: 10, paddingRight: 10, paddingBottom: 10 }}>{children}</View>;
}

/**
 * A floating capsule: the sizes (the one chosen marked; "自定义" opens them all in a sheet), turning, moving the page by
 * a finger, and fitting it again once moved. Held down, it folds away (the bar's size button opens it again).
 */
function Toolbar({ stage, viewport, set, turn, fold, custom }: { stage: StageState; viewport: Viewport | null; set: (v: Viewport | null) => void; turn: () => void; fold: () => void; custom: () => void }) {
  const C = useC();
  const choose = (v: Viewport | null) => { stage.setMoving(false); set(v); };
  const preset = presetOf(viewport);
  const isCustom = viewport !== null && preset === null;
  const glass = C.dark ? withAlpha(C.surface2, 0.84) : withAlpha(C.surface, 0.72);
  // Held half a second without moving: folded away, and what it was held on is not tapped.
  const held = useRef(false);
  const guard = (run: () => void) => () => { if (held.current) { held.current = false; return; } run(); };
  const hold = useMemo(() => Gesture.LongPress().runOnJS(true).minDuration(500).maxDistance(8).shouldCancelWhenOutside(false)
    .onBegin(() => { held.current = false; })
    .onStart(() => {
      held.current = true;
      if (Platform.OS === "android") void Haptics.performAndroidHapticsAsync(Haptics.AndroidHaptics.Long_Press);
      else void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      stage.setMoving(false);
      fold();
    }), [fold]);
  return (
    <GestureDetector gesture={hold}>
      <View style={{ width: "100%", height: 48, borderRadius: 24, elevation: 4, shadowColor: "#000", shadowOpacity: 0.12, shadowRadius: 4, backgroundColor: glass, paddingHorizontal: 6, flexDirection: "row", alignItems: "center", gap: 4 }}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flex: 1 }} contentContainerStyle={{ gap: 2, alignItems: "center" }}>
          <Chip label={t("android-chat.preview.fit")} on={viewport === null} onClick={guard(() => choose(null))} />
          {PRESETS.map((p) => <Chip key={p.key} label={p.name} on={preset === p.name} onClick={guard(() => choose(preset === p.name ? viewport : { width: p.width, height: p.height }))} />)}
          <Chip label={isCustom ? dims(viewport!.width, viewport!.height) : t("android-chat.preview.custom")} on={isCustom} onClick={guard(custom)} />
        </ScrollView>
        {viewport !== null ? (
          <View style={{ paddingLeft: 4, flexDirection: "row", gap: 2, alignItems: "center" }}>
            {viewport.height !== null ? <Tool icon={Icons.Landscape} on={false} onClick={guard(turn)} /> : null}
            <Tool icon={Icons.Move} on={stage.moving} onClick={guard(() => stage.setMoving(!stage.moving))} />
            {stage.view !== null ? (
              <Pressable onPress={guard(() => { stage.setView(null); stage.setMoving(false); })} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
                style={{ height: 36, borderRadius: 18, overflow: "hidden", backgroundColor: C.surface, paddingHorizontal: 12, alignItems: "center", justifyContent: "center" }}>
                <T size={13} weight="500" color={C.ink} numberOfLines={1}>{t("android-chat.preview.fitView")}</T>
              </Pressable>
            ) : null}
          </View>
        ) : null}
      </View>
    </GestureDetector>
  );
}

function Chip({ label, on, onClick }: { label: string; on: boolean; onClick: () => void }) {
  const C = useC();
  return (
    <View style={on ? { borderRadius: 18, elevation: 1, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 1, backgroundColor: C.dark ? C.bg : C.surface } : undefined}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
        style={{ height: 36, borderRadius: 18, overflow: "hidden", paddingHorizontal: 13, alignItems: "center", justifyContent: "center" }}>
        <T size={13} weight={on ? "600" : "400"} color={on ? C.ink : C.muted} numberOfLines={1}>{label}</T>
      </Pressable>
    </View>
  );
}

function Tool({ icon, on, onClick }: { icon: IconPaths; on: boolean; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
      style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", backgroundColor: on ? C.accent : "transparent", alignItems: "center", justifyContent: "center" }}>
      <Icon icon={icon} size={18} color={on ? "#FFFFFF" : C.ink} />
    </Pressable>
  );
}

/** All the sizes in a sheet (the toolbar's "自定义"): as big as the preview, the presets, any size typed, turned. */
function openViewportSheet(app: AppState, first: Viewport | null, set: (v: Viewport | null) => void, turn: () => void) {
  app.sheet = new SheetSpec(0.62, false, null, null, false, () => <ViewportSheet app={app} first={first} set={set} turn={turn} />);
}

function ViewportSheet({ app, first, set, turn }: { app: AppState; first: Viewport | null; set: (v: Viewport | null) => void; turn: () => void }) {
  const [viewport, setViewport] = useState(first);
  const put = (v: Viewport | null) => { setViewport(v); set(v); };
  const choose = (v: Viewport | null) => { put(v); app.sheet = null; };
  const preset = presetOf(viewport);
  return (
    <View>
      <SheetGrab />
      <SheetHead title={t("android-chat.preview.size.title")} />
      <View style={{ paddingLeft: 10, paddingRight: 10, paddingBottom: 24 }}>
        <SizeOption checked={viewport === null} name={t("android-chat.preview.fit")} note={t("android-chat.preview.fit.note")} onClick={() => choose(null)} />
        {PRESETS.map((p) => <SizeOption key={p.key} checked={preset === p.name} name={p.name} note={dims(p.width, p.height)} onClick={() => choose(preset === p.name ? viewport : { width: p.width, height: p.height })} />)}
        <View style={{ height: 10 }} />
        <CustomSize viewport={viewport} set={put} turn={() => {
          const v = viewport;
          if (v?.height != null) { setViewport({ width: v.height, height: v.width }); turn(); }
        }} />
      </View>
    </View>
  );
}

function SizeOption({ checked, name, note, onClick }: { checked: boolean; name: string; note: string; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={12} style={{ width: "100%" }}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }} style={{ height: 48, paddingHorizontal: 10, flexDirection: "row", alignItems: "center", gap: 10 }}>
        <View style={{ width: 18, alignItems: "center" }}>{checked ? <Icon icon={Icons.Check} size={16} color={C.accent} /> : null}</View>
        <T size={15} color={C.ink} weight={checked ? "500" : "400"} style={{ flex: 1 }}>{name}</T>
        <T size={13} color={C.muted}>{note}</T>
      </Pressable>
    </Smooth>
  );
}

/** Any size, typed: the width, and the height (empty: as high as the preview leaves it); turned by the button. */
function CustomSize({ viewport, set, turn }: { viewport: Viewport | null; set: (v: Viewport | null) => void; turn: () => void }) {
  const C = useC();
  const [w, setW] = useState(viewport?.width?.toString() ?? "");
  const [h, setH] = useState(viewport?.height?.toString() ?? "");
  const [typing, setTyping] = useState(false);
  useEffect(() => { if (!typing) { setW(viewport?.width?.toString() ?? ""); setH(viewport?.height?.toString() ?? ""); } }, [viewport?.width, viewport?.height, typing]);
  const typed = useRef({ w, h });
  typed.current = { w, h };
  const commit = () => {
    const width = /^\d+$/.test(typed.current.w) ? parseInt(typed.current.w, 10) : null;
    const blank = typed.current.h.trim().length === 0;
    const height = blank ? null : /^\d+$/.test(typed.current.h) ? parseInt(typed.current.h, 10) : null;
    if (width !== null && (blank || height !== null) && !(viewport !== null && width === viewport.width && height === viewport.height)) set({ width, height });
  };
  const field = (value: string, change: (s: string) => void, hint: string) => (
    <Smooth radius={10} style={{ width: 72, height: 36, backgroundColor: C.chip }}>
      <View style={{ height: 36, paddingHorizontal: 10, justifyContent: "center" }}>
        {value.length === 0 ? <T size={15} color={C.subtle} style={{ position: "absolute", left: 10 }}>{hint}</T> : null}
        <TextInput
          value={value}
          onChangeText={(s) => change(s.replace(/\D/g, "").substring(0, 4))}
          keyboardType="number-pad"
          returnKeyType="done"
          style={{ fontSize: 15, color: C.ink, padding: 0, textAlign: "left", includeFontPadding: false }}
          selectionColor={C.accent}
          cursorColor={C.accent}
          onFocus={() => setTyping(true)}
          onBlur={() => { if (typing) { setTyping(false); commit(); } }}
          onSubmitEditing={() => { commit(); Keyboard.dismiss(); }}
        />
      </View>
    </Smooth>
  );
  const turnable = viewport?.height != null;
  return (
    <View style={{ width: "100%", paddingHorizontal: 10, flexDirection: "row", alignItems: "center", gap: 8 }}>
      <T size={15} color={C.ink} style={{ flex: 1 }}>{t("android-chat.preview.custom")}</T>
      {field(w, setW, t("android-chat.preview.width"))}
      <T size={14} color={C.muted}>×</T>
      {field(h, setH, t("android-chat.preview.auto"))}
      <Pressable disabled={!turnable} onPress={turn} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
        style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
        <View style={{ opacity: turnable ? 1 : 0.35 }}><Icon icon={Icons.Landscape} size={18} color={C.ink} /></View>
      </Pressable>
    </View>
  );
}

// ── marking the page (annotate/Marks.tsx) ──────────────────────────────

/** In the address's place while marking: what to do or how many, then putting them into the chat. */
function MarkMode({ state, leave, send }: { state: PageState; leave: () => void; send: () => void }) {
  const C = useC();
  const n = state.marks.length;
  const error = state.error;
  const able = !state.busy && n > 0;
  const ground = able ? C.ink : withAlpha(C.ink, 0.4);
  const ink = C.dark ? C.bg : "#FFFFFF";
  return (
    <Smooth radius={15} style={{ width: "100%", height: 30, backgroundColor: lerpColor(C.chip, C.accent, 0.1) }}>
      <View style={{ height: 30, paddingLeft: 12, paddingRight: 3, flexDirection: "row", alignItems: "center", gap: 8 }}>
        <View style={{ width: state.marking ? 13 : 7, height: state.marking ? 13 : 7, borderRadius: 7, backgroundColor: state.marking ? withAlpha(C.accent, 0.22) : "transparent", alignItems: "center", justifyContent: "center" }}>
          <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: state.marking ? C.accent : C.muted }} />
        </View>
        {error !== null ? <T size={13} color={C.red} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{error}</T> : (
          <View style={{ flex: 1, minWidth: 0, flexDirection: "row", gap: 8 }}>
            <T size={13} weight="500" color={C.ink} numberOfLines={1} style={{ flexShrink: 0 }}>{n > 0 ? t("android-chat.preview.marked", { n }) : t("android-chat.preview.pick")}</T>
            {state.marking && n > 0 ? <T size={13} color={C.muted} numberOfLines={1} style={{ flexShrink: 1 }}>{t("android-chat.preview.pickMore")}</T> : null}
          </View>
        )}
        <Pressable disabled={state.busy} onPress={leave} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
          style={{ width: 24, height: 24, borderRadius: 12, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
          <Icon icon={Icons.Close} size={12} color={C.muted} />
        </Pressable>
        <Smooth radius={12} style={{ height: 24, backgroundColor: ground }}>
          <Pressable disabled={!able} onPress={send} android_ripple={{ color: withAlpha(ink, 0.2), borderless: false }}
            style={{ height: 24, paddingHorizontal: 10, flexDirection: "row", alignItems: "center", gap: 5 }}>
            <Icon icon={Icons.Send} size={12} color={ink} />
            <T size={12} weight="500" color={ink} numberOfLines={1}>{state.busy ? t("android-chat.preview.shooting") : t("android-chat.preview.put")}</T>
          </Pressable>
        </Smooth>
      </View>
    </Smooth>
  );
}

/** The marks over the page, where it is drawn: each a numbered pin on its element's corner, what is said beside it. */
function MarksOver({ state, placed, js }: { state: PageState; placed: Placed | null; js: (code: string) => void }) {
  const C = useC();
  const [stageW, setStageW] = useState(0);
  const originX = placed?.x ?? 0;
  const originY = placed?.y ?? 0;
  const viewW = placed?.width ?? stageW;
  const scale = placed?.scale ?? 1;
  // CSS pixels to the stage's: the page's own ratio, then the stage's scale.
  const k = state.cssWidth > 0 ? (viewW / state.cssWidth) * scale : scale;
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="box-none" onLayout={(e) => setStageW(e.nativeEvent.layout.width)}>
      {state.marks.map((m) => {
        const b = state.at2.get(m.picked.n) ?? m.picked.rect;
        const x = originX + b.x * k; const y = originY + b.y * k;
        const w = b.width * k; const h = b.height * k;
        const open = state.editing === m.picked.n;
        // The pin's point on the element's top-left corner (kept in sight at the page's edges).
        const pinX = Math.max(2, x); const pinY = Math.max(24, y);
        const right = stageW - pinX - 36 >= Math.min(220, pinX - 14);
        const maxW = right ? stageW - pinX - 36 : pinX - 14;
        return (
          <View key={m.picked.n} style={StyleSheet.absoluteFill} pointerEvents="box-none">
            <Smooth radius={4} stroke={{ width: open ? 2 : 1.5, color: open ? C.accent : withAlpha(C.accent, 0.55) }} pointerEvents="none"
              style={{ position: "absolute", left: Math.round(x), top: Math.round(y), width: w, height: h, backgroundColor: open ? withAlpha(C.accent, 0.08) : "transparent" }} />
            <View style={{ position: "absolute", left: Math.round(pinX - 2), top: Math.round(pinY - 22), width: 24, height: 24, elevation: 3, shadowColor: "#000", shadowOpacity: 0.25, shadowRadius: 3, borderRadius: 12 }}>
              <Smooth radius={[12, 12, 12, 3]} style={{ width: 24, height: 24, backgroundColor: "#FFFFFF", padding: 2 }}>
                <Smooth radius={[12, 12, 12, 3]} style={{ flex: 1, backgroundColor: C.accent }}>
                  <Pressable onPress={() => state.set((s) => { s.editing = open ? null : m.picked.n; })} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
                    <T size={11} weight="700" color="#FFFFFF">{`${m.picked.n}`}</T>
                  </Pressable>
                </Smooth>
              </Smooth>
            </View>
            {open ? (
              <Note mark={m} x={pinX} y={pinY} stageW={stageW} onChange={() => state.changed()} onDone={() => state.set((s) => { s.editing = null; })} onRemove={() => {
                state.set((s) => { s.marks = s.marks.filter((o) => o !== m); s.at2.delete(m.picked.n); s.editing = null; });
                js(`__stillfailMarks&&__stillfailMarks.remove(${m.picked.n})`);
              }} />
            ) : m.comment.length > 0 ? (
              // Beside the pin, on its left when the right has too little room.
              <View style={[{ position: "absolute", top: Math.round(pinY - 23), maxWidth: Math.max(40, maxW), alignItems: right ? "flex-start" : "flex-end" },
                right ? { left: Math.round(pinX + 28) } : { left: 0, width: pinX - 6 }]}>
                <View style={{ height: 26, borderRadius: 13 * 1.25, elevation: 3, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 3 }}>
                  <Smooth radius={13} style={{ height: 26, backgroundColor: bubble(C) }}>
                    <Pressable onPress={() => state.set((s) => { s.editing = m.picked.n; })} style={{ height: 26, paddingHorizontal: 10, paddingVertical: 5, justifyContent: "center" }}>
                      <T size={12} color={C.ink} numberOfLines={1}>{m.comment}</T>
                    </Pressable>
                  </Smooth>
                </View>
              </View>
            ) : null}
          </View>
        );
      })}
    </View>
  );
}

/** Frosted, as still.fail's own floating things are (over a page, which cannot be blurred here: thick). */
const bubble = (C: ReturnType<typeof useC>) => (C.dark ? withAlpha(C.surface2, 0.94) : withAlpha(C.surface, 0.94));

/** What is said about one mark, in a bubble beside its pin. */
function Note({ mark, x, y, stageW, onChange, onDone, onRemove }: { mark: Mark; x: number; y: number; stageW: number; onChange: () => void; onDone: () => void; onRemove: () => void }) {
  const C = useC();
  const width = Math.min(280, stageW - 16);
  const left = Math.min(Math.max(8, stageW - width - 8), Math.max(8, x + 28));
  const top = Math.max(8, y - 28);
  return (
    <View style={{ position: "absolute", left: Math.round(left), top: Math.round(top), width, height: 36, borderRadius: 18 * 1.25, elevation: 6, shadowColor: "#000", shadowOpacity: 0.2, shadowRadius: 6 }}>
      <Smooth radius={18} style={{ width, height: 36, backgroundColor: bubble(C) }}>
        <View style={{ height: 36, paddingLeft: 12, paddingRight: 4, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <View style={{ flex: 1, justifyContent: "center" }}>
            {mark.comment.length === 0 ? <T size={13} color={C.muted} numberOfLines={1} style={{ position: "absolute", left: 0 }}>{t("android-chat.preview.mark.comment", { kind: mark.picked.kind })}</T> : null}
            <TextInput
              autoFocus
              value={mark.comment}
              onChangeText={(s) => { mark.comment = s; onChange(); }}
              returnKeyType="done"
              onSubmitEditing={onDone}
              style={{ fontSize: 13, color: C.ink, padding: 0, includeFontPadding: false }}
              selectionColor={C.accent}
              cursorColor={C.accent}
            />
          </View>
          <Pressable onPress={onRemove} android_ripple={{ color: withAlpha(C.ink, 0.1), borderless: false }}
            style={{ width: 28, height: 28, borderRadius: 14, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
            <Icon icon={Icons.Trash} size={14} color={C.muted} />
          </Pressable>
        </View>
      </Smooth>
    </View>
  );
}

/**
 * Where a mark is, as the agent reads it with its screenshot `shot` (the file's name). The first line is also what
 * the composer shows.
 */
function where(p: PagePick, shot: string): string {
  return [
    p.text.length > 0 ? t("android-chat.preview.where.text", { kind: p.kind, text: p.text }) : p.kind,
    t("android-chat.preview.where.element", { label: p.label, selector: p.selector }),
    t("android-chat.preview.where.page", { path: p.path, width: p.viewport.width, height: p.viewport.height, shot }),
    p.component != null ? t("android-chat.preview.where.component", { name: p.component }) : null,
  ].filter((s): s is string => s !== null).join("\n");
}

const delay = (ms: number) => new Promise<void>((done) => setTimeout(done, ms));
const boxOf = (o: Record<string, unknown>): Box4 => ({ x: Number(o.x), y: Number(o.y), width: Number(o.width), height: Number(o.height) });

/**
 * Puts the marks into the chat's draft: one screenshot each, of what the window shows with only that mark drawn on it
 * (a mark scrolled out of sight gets the window's worth of page around it), and a quote each saying where it is.
 */
async function putIntoChat(app: AppState, link: PreviewLink, state: PageState, station: string, session: string, name: string, leave: () => void, darkroom: Darkroom) {
  const web = link.web;
  if (!web) return;
  if (state.marks.length === 0) return;
  state.set((s) => { s.busy = true; s.error = null; s.editing = null; });
  try {
    const d = new Date();
    const stamp = [d.getHours(), d.getMinutes(), d.getSeconds()].map((n) => String(n).padStart(2, "0")).join("");
    const y0 = Number(returned(await link.eval("scrollY")) ?? 0) || 0;
    // What the window shows now, taken once for every mark in sight.
    let now: Shot | null = null;
    const pictures: Picked[] = [];
    const quotes: OfferQuote[] = [];
    for (const m of [...state.marks]) {
      let place = returned(await link.eval(`__stillfailMarks.place(${m.picked.n},false)`)) as Record<string, unknown> | null;
      if (!place || typeof place !== "object") throw new Error(t("android-chat.preview.mark.gone", { n: m.picked.n }));
      const cssW = Number(place.width);
      // The window's pixels to the page's CSS pixel.
      const ratio = (web.width * PixelRatio.get()) / cssW;
      const b0 = boxOf(place);
      const inSight = b0.y + b0.height > 0 && b0.y * ratio < web.height * PixelRatio.get();
      let shot: Shot | null;
      if (inSight) shot = now ?? (now = await link.shot());
      else {
        place = (returned(await link.eval(`__stillfailMarks.place(${m.picked.n},true)`)) as Record<string, unknown> | null) ?? place;
        await delay(160);
        shot = await link.shot();
        await link.eval(`__stillfailMarks.back(${y0})`);
      }
      if (!shot) throw new Error(t("android-chat.preview.shot.failed"));
      const b = boxOf(place);
      const r = shot.width / cssW;
      const drawn = await drawMark(darkroom, shot, m.picked.n, b.x * r, b.y * r, b.width * r, b.height * r, r);
      const file = t("android-chat.preview.mark.file", { name, n: m.picked.n, stamp });
      pictures.push({ ...drawn, name: file } as Picked);
      quotes.push(new OfferQuote(t("android-chat.preview.mark.quote", { name, n: m.picked.n }), where(m.picked, file), m.comment.trim(), file));
    }
    DraftOffers.add(new MarkOffer(station, session, pictures, quotes));
    app.toast = t("android-chat.preview.put.done");
    leave();
  } catch (e) {
    state.set((s) => { s.error = t("android-chat.preview.put.failed", { error: e instanceof Error ? e.message : String(e) }); });
  } finally {
    state.set((s) => { s.busy = false; });
  }
}

type Shot = { uri: string; width: number; height: number };

/** A picture with one mark drawn on it, made by the darkroom below (no canvas to draw on here: a view drawn, then taken). */
interface Developing { shot: Shot; n: number; x: number; y: number; w: number; h: number; ratio: number; done: (got: { bytes: Uint8Array; width: number; height: number; preview: Picture | null } | Error) => void }
interface Darkroom { develop(d: Developing): void }

/** A picture with one mark drawn on it, as the page shows marks: its outline, its number in a pin on its corner. */
function drawMark(darkroom: Darkroom, shot: Shot, n: number, x: number, y: number, w: number, h: number, ratio: number): Promise<{ name: string; bytes: Uint8Array; width: number; height: number; preview: Picture | null }> {
  return new Promise((resolve, reject) => {
    darkroom.develop({ shot, n, x, y, w, h, ratio, done: (got) => (got instanceof Error ? reject(got) : resolve({ name: "", ...got })) });
  });
}

/**
 * Where a marked screenshot is drawn: out of sight, at its own pixels (at most two to the page's CSS pixel), then taken
 * as a PNG, and as a picture 160 wide for the composer.
 */
function DarkroomView({ d, onDone }: { d: Developing; onDone: () => void }) {
  const ref = useRef<View>(null);
  const [loaded, setLoaded] = useState(false);
  // At most two pixels to the page's CSS pixel.
  const k = Math.min(1, 2 / d.ratio);
  const outW = Math.max(1, Math.round(d.shot.width * k));
  const outH = Math.max(1, Math.round(d.shot.height * k));
  // The view's own units (dp) for the picture's pixels.
  const pr = PixelRatio.get();
  const u = d.ratio;
  const mark = "#EF6A3C";
  const px = Math.max(2 * u, d.x) - 2 * u;
  const py = Math.max(24 * u, d.y) - 22 * u;
  const pin = (l: number, tp: number, side: number, r: number) => {
    const c = 3 * u;
    return `M${l + r},${tp} H${l + side - r} A${r},${r} 0 0 1 ${l + side},${tp + r} V${tp + side - r} A${r},${r} 0 0 1 ${l + side - r},${tp + side} H${l + c} A${c},${c} 0 0 1 ${l},${tp + side - c} V${tp + r} A${r},${r} 0 0 1 ${l + r},${tp} Z`;
  };
  useEffect(() => {
    if (!loaded) return;
    let gone = false;
    (async () => {
      try {
        await new Promise((r) => requestAnimationFrame(() => r(null)));
        const view = ref.current;
        if (!view) throw new Error(t("android-chat.preview.shot.failed"));
        // The sizes in pixels, as view-shot scales the taken bitmap to them.
        const b64 = await captureRef(view, { format: "png", quality: 1, result: "base64", width: outW, height: outH });
        const thumbH = Math.max(1, Math.round((160 * outH) / outW));
        const thumb = await captureRef(view, { format: "png", quality: 1, result: "tmpfile", width: 160, height: thumbH });
        if (!gone) d.done({ bytes: fromBase64(b64), width: outW, height: outH, preview: { uri: thumb, width: 160, height: thumbH } });
      } catch (e) {
        if (!gone) d.done(e instanceof Error ? e : new Error(String(e)));
      } finally {
        if (!gone) onDone();
      }
    })();
    return () => { gone = true; };
  }, [loaded]);
  return (
    <View pointerEvents="none" style={{ position: "absolute", left: -100000, top: 0 }}>
      <View ref={ref} collapsable={false} style={{ width: outW / pr, height: outH / pr }}>
        <Image source={{ uri: d.shot.uri }} onLoad={() => setLoaded(true)} style={{ width: outW / pr, height: outH / pr }} />
        <Svg width={outW / pr} height={outH / pr} viewBox={`0 0 ${d.shot.width} ${d.shot.height}`} style={StyleSheet.absoluteFill}>
          <Rect x={d.x} y={d.y} width={d.w} height={d.h} rx={3 * u} ry={3 * u} stroke={mark} strokeWidth={2 * u} fill="none" />
          {/* The pin's soft shadow (the Kotlin's shadow layer: 6, down 1, a quarter black). */}
          <Path d={pin(px, py + u, 24 * u, 12 * u)} fill="#000000" fillOpacity={0.12} />
          <Path d={pin(px, py, 24 * u, 12 * u)} fill="#FFFFFF" />
          <Path d={pin(px + 2 * u, py + 2 * u, 20 * u, 10 * u)} fill={mark} />
          <SvgText x={px + 12 * u} y={py + 12 * u + 4.2 * u} fontSize={12 * u} fontWeight="700" fill="#FFFFFF" textAnchor="middle">{`${d.n}`}</SvgText>
        </Svg>
      </View>
    </View>
  );
}

// ── into the chat's draft (web/src/draft.ts offerToDraft) ──────────────

/** A quote a mark puts into the draft, with the screenshot's file name it goes with (none: an image's mark, ImageMarks.tsx), and whose it is. */
export class OfferQuote {
  constructor(readonly author: string, readonly text: string, readonly comment: string, readonly file: string | null, readonly role = "page") {}
}

/** What a preview's marks put into the draft of the chat whose agent is `session`: screenshots and quotes. */
export class MarkOffer {
  constructor(readonly station: string, readonly session: string, readonly pictures: Picked[], readonly quotes: OfferQuote[]) {}
}

/** Offers waiting for their chat's composer (the chat's page takes them as it shows: TakeDraftOffers). */
export const DraftOffers = {
  waiting: new Watched<readonly MarkOffer[]>([]),
  add(offer: MarkOffer) { DraftOffers.waiting.value = [...DraftOffers.waiting.value, offer]; },
  removeAll(offers: readonly MarkOffer[]) { DraftOffers.waiting.value = DraftOffers.waiting.value.filter((o) => !offers.includes(o)); },
};

let nano = 0;
const nanoTime = () => Date.now() * 1_000_000 + (nano = (nano + 1) % 1_000_000);

/** Takes what a preview offered to this chat's draft (its agents' `sessions`): the files go up, the quotes go in. */
export function TakeDraftOffers({ station, sessions, draft }: { station: string; sessions: string[]; draft: Draft }) {
  const waiting = useWatched(DraftOffers.waiting);
  useEffect(() => {
    const mine = waiting.filter((o) => o.station === station && sessions.includes(o.session));
    if (mine.length === 0) return;
    DraftOffers.removeAll(mine);
    for (const offer of mine) {
      for (const p of offer.pictures) upload(app, draft, station, p, app.scope);
      for (const q of offer.quotes) {
        const quote = new DraftQuote(nanoTime(), q.author, q.text, null, q.role, q.file);
        quote.comment = q.comment;
        draft.quotes.push(quote);
      }
    }
  }, [waiting.length, sessions.join("\n")]);
  return null;
}
