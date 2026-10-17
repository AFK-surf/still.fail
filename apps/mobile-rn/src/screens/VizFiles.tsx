// A visualization sent as a file (an HTML page placed in a message): fetched from its station with what its widget
// kept, drawn in the message (ui/Viz.tsx draws the page), opened on its own, and what it keeps next sent back.
// (The Android app's screens/VizFiles.kt.)
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Pressable, View } from "react-native";
import Animated from "react-native-reanimated";
import type { Attachment } from "../../../../web/src/core/shapes.ts";
import { app } from "../AppState";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { webSubtle } from "../ui/Markdown";
import { Smooth } from "../ui/Smooth";
import { useC, withAlpha } from "../ui/Theme";
import { VizFrame, VizFull, type JsonElement } from "../ui/Viz";
import { WaitLine, breathing, rememberBreath } from "../ui/Waiting";

/** A visualization's page and what its widget kept (on the station, by the session that sent it and its path), loaded together. */
export type Loaded = { kind: "Waiting" } | { kind: "Failed" } | { kind: "Ready"; html: string; state: JsonElement | null };
const Waiting: Loaded = { kind: "Waiting" };
const Failed: Loaded = { kind: "Failed" };

/** A cache of the latest `size`, as android.util.LruCache. */
class Lru<V> {
  readonly #map = new Map<string, V>();
  constructor(private readonly size: number) {}
  has(k: string) { return this.#map.has(k); }
  get(k: string): V | undefined {
    if (!this.#map.has(k)) return undefined;
    const v = this.#map.get(k)!;
    this.#map.delete(k);
    this.#map.set(k, v);
    return v;
  }
  put(k: string, v: V) {
    this.#map.delete(k);
    this.#map.set(k, v);
    for (const old of this.#map.keys()) { if (this.#map.size <= this.size) break; this.#map.delete(old); }
  }
}

/** Pages fetched, by station, session and path: a file sent never changes. */
const pages = new Lru<string>(12);
/** What their widgets kept, as last read or kept here (null: nothing), so a page shown again is shown at once. */
const keptStates = new Lru<JsonElement | null>(64);

/** Keeps what a visualization's widget keeps next: here at once, on its station after. */
export function keepViz(station: string, key: string, path: string, state: JsonElement): void {
  keptStates.put(`${station}/${key}/${path}`, state);
  app.api(station).setWidgetState(key, path, state).catch(() => undefined);
}

/** UTF-8 bytes as text. */
function utf8(bytes: Uint8Array): string {
  const Decoder = (globalThis as { TextDecoder?: new (label?: string) => { decode(b: Uint8Array): string } }).TextDecoder;
  if (Decoder) return new Decoder("utf-8").decode(bytes);
  let out = "";
  for (let i = 0; i < bytes.length;) {
    const b = bytes[i]!;
    let cp: number;
    if (b < 0x80) { cp = b; i += 1; }
    else if (b < 0xe0) { cp = ((b & 0x1f) << 6) | (bytes[i + 1]! & 0x3f); i += 2; }
    else if (b < 0xf0) { cp = ((b & 0x0f) << 12) | ((bytes[i + 1]! & 0x3f) << 6) | (bytes[i + 2]! & 0x3f); i += 3; }
    else { cp = ((b & 0x07) << 18) | ((bytes[i + 1]! & 0x3f) << 12) | ((bytes[i + 2]! & 0x3f) << 6) | (bytes[i + 3]! & 0x3f); i += 4; }
    out += String.fromCodePoint(cp);
  }
  return out;
}

/**
 * A placed HTML file, drawn in its message, with ways to open it on its own under it (icons, as the web has them):
 * the whole screen, or a page of its own in the preview (web mobile's 在侧边打开). `failed`: what shows instead when the file cannot be read (its card).
 * `sessionKey` is the Kotlin's `key` (a prop React keeps for itself).
 */
export function VizFile({ station, sessionKey: session, file, failed }: { station: string; sessionKey: string; file: Attachment; failed: () => ReactNode }) {
  const C = useC();
  const loaded = rememberViz(station, session, file);
  const [full, setFull] = useState(false);
  const [kept, setKept] = useState<JsonElement | null>(loaded.kind === "Ready" ? loaded.state : null);
  useEffect(() => { if (loaded.kind === "Ready") setKept(loaded.state); }, [loaded]);
  const breath = rememberBreath();
  const breathe = breathing(breath);
  if (loaded.kind === "Failed") return <>{failed()}</>;
  // Its place, breathing as every wait's shapes, till the page comes.
  if (loaded.kind === "Waiting") {
    return (
      <Animated.View style={[{ alignSelf: "stretch", marginBottom: 8, height: 120 }, breathe]}>
        <Smooth radius={12} style={{ flex: 1, backgroundColor: C.bubble }} />
      </Animated.View>
    );
  }
  const keep = (s: JsonElement) => { setKept(s); keepViz(station, session, file.path, s); };
  const ripple = { color: withAlpha(C.ink, 0.12), borderless: false };
  return (
    <>
      <View style={{ alignSelf: "stretch", paddingBottom: 4 }}>
        <VizFrame html={loaded.html} state={loaded.state} onState={keep} />
        {/* Under the page, out of its way: the way to open it on its own, an icon in the chat's grey. */}
        <View style={{ alignSelf: "stretch", paddingTop: 2, height: 24, flexDirection: "row", justifyContent: "flex-end", gap: 2 }}>
          <Smooth radius={6} style={{ width: 22, height: 22 }}>
            <Pressable accessibilityLabel={t("android-misc.viz.fullscreen")} onPress={() => setFull(true)} android_ripple={ripple} style={{ width: 22, height: 22, alignItems: "center", justifyContent: "center" }}>
              <Icon icon={Icons.Expand} size={14} color={webSubtle(C)} />
            </Pressable>
          </Smooth>
          {/* 在侧边打开: on a phone, as web mobile has it, the file as a page of its own in the preview. */}
          <Smooth radius={6} style={{ width: 22, height: 22 }}>
            <Pressable
              accessibilityLabel={t("android-misc.viz.openAside")}
              onPress={() => app.push({ kind: "PreviewFile", station, session, path: file.path, name: file.name })}
              android_ripple={ripple}
              style={{ width: 22, height: 22, alignItems: "center", justifyContent: "center" }}
            >
              <Icon icon={Icons.PanelOpen} size={14} color={webSubtle(C)} />
            </Pressable>
          </Smooth>
        </View>
      </View>
      {full && <VizFull name={file.name} html={loaded.html} state={kept} keep={keep} onClose={() => setFull(false)} />}
    </>
  );
}

/** A visualization's page and what it kept, fetched once per file. */
export function rememberViz(station: string, key: string, file: Attachment): Loaded {
  const id = `${station}/${key}/${file.path}`;
  // Read before: at once, from here (a page scrolled back to, a chat opened again), not after asking its station again.
  const known = useMemo<Loaded | null>(() => {
    const html = pages.get(id);
    return html != null && keptStates.has(id) ? { kind: "Ready", html, state: keptStates.get(id) ?? null } : null;
  }, [id]);
  const [loaded, setLoaded] = useState<{ id: string; value: Loaded }>({ id, value: known ?? Waiting });
  useEffect(() => {
    if (known != null) { setLoaded({ id, value: known }); return; }
    setLoaded({ id, value: Waiting });
    let live = true;
    void (async () => {
      const api = app.api(station);
      const name = file.path.substring(file.path.lastIndexOf("/") + 1);
      let html: string | null = pages.get(id) ?? null;
      if (html == null) {
        try {
          html = utf8(await api.file(key, name));
          pages.put(id, html);
        } catch { html = null; }
      }
      // What the station cannot say (an older one) is nothing kept.
      let state: JsonElement | null | undefined;
      if (keptStates.has(id)) state = keptStates.get(id);
      else {
        try { state = await api.widgetState(key, file.path); } catch { state = undefined; }
      }
      if (state !== undefined) keptStates.put(id, state);
      if (live) setLoaded({ id, value: html == null ? Failed : { kind: "Ready", html, state: state ?? null } });
    })();
    return () => { live = false; };
  }, [id]);
  return loaded.id === id ? loaded.value : (known ?? Waiting);
}

/** A visualization opened on its own (a link to it within a sentence): the whole screen, once it is fetched. */
export function VizOpen({ station, sessionKey: session, file, onClose }: { station: string; sessionKey: string; file: Attachment; onClose: () => void }) {
  const l = rememberViz(station, session, file);
  const [kept, setKept] = useState<JsonElement | null>(l.kind === "Ready" ? l.state : null);
  useEffect(() => { if (l.kind === "Ready") setKept(l.state); }, [l]);
  useEffect(() => {
    if (l.kind !== "Failed") return;
    app.toast = t("android-misc.viz.cantRead");
    onClose();
  }, [l]);
  // Under the sentence whose link opened it, till it covers the screen.
  if (l.kind === "Waiting") return <WaitLine text={t("common.opening")} modifier={{ paddingVertical: 6 }} />;
  if (l.kind === "Failed") return null;
  return <VizFull name={file.name} html={l.html} state={kept} keep={(s) => { setKept(s); keepViz(station, session, file.path, s); }} onClose={onClose} />;
}
