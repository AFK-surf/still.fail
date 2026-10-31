// A station's screens, seen and driven from a client (docs/remote-screens.md): the `screens` topic (what the sync holds
// of each station's `GET /screens` and its `screens` events, station/sync.ts) and the `screen.*` calls. A view is a
// stream to the station (screen-frames.ts); its frames go to the UI as they come, their bytes beside the JSON
// (protocol.ts), and the UI acknowledges each one it decoded, which is what lets the station send the next: a slow link
// or a slow decoder lowers the frame rate rather than queueing. What the page draws of the view (its phase, 只看/控制,
// who else is on it) is said whole as `{state}` each time it changes; the page only draws it. The link dropping opens
// the view again; switching 只看/控制 opens it again with the other, and another size, 画质 or 帧率 asked (`screen.bounds`)
// with that, the stream before kept until the new one has opened (a Windows desktop puts its display's scale back once its
// last view ends). While it drives the screen, the screen's clipboard
// goes both ways (`screen.clipboard` sets it and pastes; a copy made on it comes as `{clipboard}`), and where a file
// dropped into it goes (`drop`) is in its state, for the page to upload it with the drive's upload. Zoomed in, the page
// says what part of the screen it shows (`screen.look`): once it has stayed so a moment, the station sends that part
// alone, as large as the page shows it, each config saying which part (the page draws it there, over the whole).
import { Deferred, Effect, Exit, Option, Queue, Scope } from "effect";
import type { Inner, Progress } from "./core.ts";
import { handlers } from "./core/execute.ts";
import { CoreError, asCoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import { unavailable } from "./permissions.ts";
import { CLIP_PNG_MAX, CLIP_TEXT_MAX, type ClipType, FrameReader, type Region, ackFrame, clipboardFrame, inputFrame, keyframeFrame, lookFrame } from "./screen-frames.ts";
import { StationAddr } from "./station/addr.ts";
import { SCREEN_FPS, type ScreenAsk, type ScreenFps, type ScreenQuality, type WireSocket } from "./station/wire.ts";
import type { ClientId, RequestId } from "./protocol.ts";
import type { SpanContext } from "./trace.ts";
import { fromUtf8, get, isObject, utf8 } from "./util.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The codecs a view may ask for; one asking none takes those every client decodes (H.265 only where the UI said it does).
export const CODECS = ["h265", "h264", "jpeg"];
const DEFAULT_CODECS = ["h264", "jpeg"];
export const MAX_WIDTH = 1920;
export const MAX_HEIGHT = 1080;
/// The largest frame a client may ask for (an 8K screen's).
const LIMIT = 7680;
/// A view whose stream went is opened again after these waits, one after another; then it has failed.
export const REOPEN_MS = [500, 1_000, 2_000, 4_000, 8_000, 15_000, 30_000];
/// How long a part of the screen looked at stays before the station is asked for it (a pinch, a pan, settled).
export const LOOK_MS = 200;
/// A part this much of the screen or more, both ways, is the whole of it.
const LOOK_WHOLE = 0.98;
/// What a key's names and a text may hold.
const KEY_MAX = 64;
const TEXT_MAX = 16_384;
/// The most a login's account or password filled from this device's password manager may be.
const FILL_MAX = 1024;
/// The most each part of a passkey's answer may be, base64url.
const PASSKEY_MAX = 8192;

export type ScreenCall =
  /// `ask.control` as asked; `auto` (none asked): control unless someone else drives it as it opens.
  | { kind: "view"; station: string; screen: string; view: string; ask: ScreenAsk; auto: boolean }
  | { kind: "ack"; view: string; ts: number }
  | { kind: "keyframe"; view: string }
  | { kind: "input"; view: string; input: J }
  | { kind: "control"; view: string; control: boolean }
  /// The size the view's pictures are asked to fit in from now on, and the 画质 and 帧率 asked (another chosen; none: 自动).
  | { kind: "bounds"; view: string; maxWidth: number; maxHeight: number; quality: ScreenQuality | null; fps: ScreenFps | null }
  /// The part of the screen the page shows (null: the whole), in `width`×`height` of this device's pixels.
  | { kind: "look"; view: string; region: Region | null; width: number; height: number }
  /// The screen's clipboard set to text or a PNG (its bytes), then pasted where its focus is unless `paste` is false.
  | { kind: "clipboard"; view: string; type: ClipType; data: Uint8Array; paste: boolean };

/// A PNG's first bytes.
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: number) => Math.min(1, Math.max(0, v));

function text(params: unknown, field: string): string {
  const v = get(params, field);
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
}

/// A 画质 said (`quality`), or null (自动, or not one).
function qualityOf(q: unknown): ScreenQuality | null {
  return q === "smooth" || q === "hd" || q === "original" ? q : null;
}

/// A 帧率 said (`fps`: 120, 90, 60, 30 or 15), or null (自动, or not one).
function fpsOf(v: unknown): ScreenFps | null {
  return SCREEN_FPS.includes(v as ScreenFps) ? (v as ScreenFps) : null;
}

/// The `screen.*` calls by name; null for any other.
/// `bytes`: what the call carries beside its JSON (a picture for the clipboard, `png: true`).
export function parseScreen(name: string, params: unknown, bytes?: Uint8Array): ScreenCall | null {
  switch (name) {
    case "screen.view": {
      const station = text(params, "station");
      StationAddr.parse(station);
      const codecs = Array.isArray(get(params, "codecs")) ? (get(params, "codecs") as unknown[]).filter((c): c is string => typeof c === "string" && CODECS.includes(c)) : DEFAULT_CODECS;
      if (codecs.length === 0) throw CoreError.invalid(t("core-misc.screen.noCodec"));
      const size = (field: string, otherwise: number) => {
        const v = get(params, field);
        return finite(v) && v >= 1 ? Math.min(Math.round(v), LIMIT) : otherwise;
      };
      const control = get(params, "control");
      // A preview (a link's card in a chat): only looking, whoever drives it.
      const peek = get(params, "peek") === true;
      // The stage a phone shows it on: a tab of the station's browser laid out for it (none for a preview).
      const f = get(params, "fit");
      const [w, h, scale] = [get(f, "width"), get(f, "height"), get(f, "scale")];
      const fit = !peek && finite(w) && finite(h) && finite(scale) && w > 0 && h > 0 && scale > 0 ? { width: Math.round(w), height: Math.round(h), scale } : null;
      // The 画质 chosen (none: 自动): how high the station lets the bit rate go; the 帧率 (none: 自动): how many frames
      // a second at most.
      const quality = peek ? null : qualityOf(get(params, "quality"));
      const fps = peek ? null : fpsOf(get(params, "fps"));
      // The UI shows a video tagged Display P3 as such: the station may send wider colours than sRGB's.
      const p3 = get(params, "gamut") === "p3";
      return {
        kind: "view",
        station,
        screen: text(params, "screen"),
        view: text(params, "view"),
        ask: { maxWidth: size("maxWidth", MAX_WIDTH), maxHeight: size("maxHeight", MAX_HEIGHT), codecs, control: control !== false && !peek, ...(peek ? { peek: true } : {}), ...(get(params, "audio") === "pcm_s16le" && !peek ? { audio: "pcm_s16le" as const } : {}), ...(quality ? { quality } : {}), ...(fps ? { fps } : {}), ...(fit ? { fit } : {}), ...(p3 ? { gamut: "p3" as const } : {}) },
        auto: !peek && typeof control !== "boolean",
      };
    }
    case "screen.ack": {
      const ts = get(params, "ts");
      if (!finite(ts) || ts < 0) throw CoreError.invalid(t("core-misc.params.missing", { field: "ts" }));
      return { kind: "ack", view: text(params, "view"), ts };
    }
    case "screen.keyframe":
      return { kind: "keyframe", view: text(params, "view") };
    case "screen.input":
      return { kind: "input", view: text(params, "view"), input: checkInput(get(params, "input")) };
    case "screen.clipboard": {
      const view = text(params, "view");
      const paste = get(params, "paste") !== false;
      const said = get(params, "text");
      if (typeof said === "string") {
        if (said === "") throw CoreError.invalid(t("core-misc.params.missing", { field: "text" }));
        const data = utf8(said);
        if (data.length > CLIP_TEXT_MAX) throw CoreError.invalid(t("core-misc.screen.clipTooLarge"));
        return { kind: "clipboard", view, type: "text", data, paste };
      }
      const data = get(params, "png") === true ? (bytes ?? null) : null;
      if (data === null || data.length === 0) throw CoreError.invalid(t("core-misc.params.missing", { field: "text" }));
      if (data.length > CLIP_PNG_MAX) throw CoreError.invalid(t("core-misc.screen.clipTooLarge"));
      if (!PNG_SIGNATURE.every((b, i) => data[i] === b)) throw CoreError.invalid(t("core-misc.screen.notPng"));
      return { kind: "clipboard", view, type: "png", data, paste };
    }
    case "screen.look": {
      const view = text(params, "view");
      const r = get(params, "region");
      const n = (k: string) => (finite(get(r, k)) ? (get(r, k) as number) : NaN);
      const [x, y, w, h] = [n("x"), n("y"), n("w"), n("h")];
      const px = (k: string) => (finite(get(params, k)) ? Math.min(LIMIT, Math.max(16, Math.round(get(params, k) as number))) : 0);
      // Within the screen; about all of it is the whole.
      const cw = Math.min(1, w), ch = Math.min(1, h);
      if (!(cw > 0 && ch > 0) || (cw >= LOOK_WHOLE && ch >= LOOK_WHOLE) || px("width") === 0 || px("height") === 0) return { kind: "look", view, region: null, width: 0, height: 0 };
      const at = (v: number, size: number) => Math.min(1 - size, Math.max(0, finite(v) ? v : 0));
      const r4 = (v: number) => Math.round(v * 10_000) / 10_000;
      return { kind: "look", view, region: { x: r4(at(x, cw)), y: r4(at(y, ch)), w: r4(cw), h: r4(ch) }, width: px("width"), height: px("height") };
    }
    case "screen.control": {
      const control = get(params, "control");
      if (typeof control !== "boolean") throw CoreError.invalid(t("core-misc.params.missing", { field: "control" }));
      return { kind: "control", view: text(params, "view"), control };
    }
    case "screen.bounds": {
      const size = (field: string) => {
        const v = get(params, field);
        if (!finite(v) || v < 1) throw CoreError.invalid(t("core-misc.params.missing", { field }));
        return Math.min(Math.round(v), LIMIT);
      };
      return { kind: "bounds", view: text(params, "view"), maxWidth: size("maxWidth"), maxHeight: size("maxHeight"), quality: qualityOf(get(params, "quality")), fps: fpsOf(get(params, "fps")) };
    }
    default:
      return null;
  }
}

/// A person's input as the station takes it (station/src/screens/source.ts `ScreenInput`), or why it is none.
/// A display's scale as a station says it (`state.scale`), checked: null when it is not one.
function scaleOf(v: unknown): { percent: number; recommended: number; steps: number[] } | null {
  const pct = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n) && n >= 100 && n <= 500;
  if (!isObject(v) || !pct(v.percent) || !pct(v.recommended) || !Array.isArray(v.steps) || v.steps.length === 0 || !v.steps.every(pct)) return null;
  return { percent: v.percent, recommended: v.recommended, steps: [...v.steps] };
}

/// A display's resolution as a station says it (`state.resolution`), checked: null when it is not one.
type Size = { width: number; height: number };
function resolutionOf(v: unknown): { width: number; height: number; modes: Size[] } | null {
  const px = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n) && n > 0 && n <= 16384;
  const size = (m: unknown): m is Size => isObject(m) && px(m.width) && px(m.height);
  if (!isObject(v) || !size(v)) return null;
  const modes = (v as { modes?: unknown }).modes;
  if (!Array.isArray(modes) || modes.length === 0 || !modes.every(size)) return null;
  return { width: v.width, height: v.height, modes: modes.map((m: Size) => ({ width: m.width, height: m.height })) };
}

export function checkInput(input: unknown): J {
  const bad = () => CoreError.invalid(t("core-misc.screen.badInput"));
  if (!isObject(input)) throw bad();
  const at = () => {
    if (!finite(input.x) || !finite(input.y)) throw bad();
    return { x: unit(input.x), y: unit(input.y) };
  };
  switch (input.t) {
    case "pointer": {
      if (input.kind !== "down" && input.kind !== "up" && input.kind !== "move") throw bad();
      const buttons = finite(input.buttons) && input.buttons >= 0 ? Math.floor(input.buttons) & 31 : 0;
      return { t: "pointer", kind: input.kind, ...at(), buttons };
    }
    case "wheel":
      if (!finite(input.dx) || !finite(input.dy)) throw bad();
      return { t: "wheel", ...at(), dx: input.dx, dy: input.dy };
    case "key": {
      if (input.kind !== "down" && input.kind !== "up") throw bad();
      if (typeof input.key !== "string" || input.key === "" || input.key.length > KEY_MAX) throw bad();
      const code = typeof input.code === "string" && input.code.length <= KEY_MAX ? input.code : "";
      const mods = finite(input.mods) && input.mods >= 0 ? Math.floor(input.mods) & 15 : 0;
      return { t: "key", kind: input.kind, key: input.key, code, mods };
    }
    case "text":
      if (typeof input.text !== "string" || input.text === "" || input.text.length > TEXT_MAX) throw bad();
      return { t: "text", text: input.text };
    // The display's scale, one of its steps (a screen whose state says `scale`).
    case "scale":
      if (!finite(input.percent) || !Number.isInteger(input.percent) || input.percent < 100 || input.percent > 500) throw bad();
      return { t: "scale", percent: input.percent };
    // The display's resolution, one of its modes (a screen whose state says `resolution`).
    case "resolution": {
      const px = (n: unknown) => finite(n) && Number.isInteger(n) && n >= 640 && n <= 16384;
      if (!px(input.width) || !px(input.height)) throw bad();
      return { t: "resolution", width: input.width, height: input.height };
    }
    // A login form filled from this device's password manager, for the site the view's state said (`login`).
    case "fill": {
      const word = (v: unknown) => v === undefined || (typeof v === "string" && v.length <= FILL_MAX);
      if (typeof input.host !== "string" || input.host === "" || input.host.length > 253 || !word(input.username) || !word(input.password)) throw bad();
      if (input.username === undefined && input.password === undefined) throw bad();
      return { t: "fill", host: input.host, ...(input.username !== undefined ? { username: input.username } : {}), ...(input.password !== undefined ? { password: input.password } : {}) };
    }
    // A page's passkey sign-in answered from this device (`passkey` of the view's state): what it signed, base64url, or
    // why it signed nothing.
    case "passkey": {
      const b64 = (v: unknown) => typeof v === "string" && v !== "" && v.length <= PASSKEY_MAX && /^[A-Za-z0-9_-]+$/.test(v);
      if (typeof input.id !== "string" || input.id === "" || input.id.length > 32) throw bad();
      if (input.error !== undefined) {
        if (typeof input.error !== "string" || !/^[A-Za-z]{1,40}$/.test(input.error)) throw bad();
        return { t: "passkey", id: input.id, error: input.error };
      }
      if (!b64(input.credential) || !b64(input.authenticatorData) || !b64(input.signature) || (input.userHandle !== undefined && !b64(input.userHandle))) throw bad();
      return { t: "passkey", id: input.id, credential: input.credential, authenticatorData: input.authenticatorData, signature: input.signature, ...(input.userHandle !== undefined ? { userHandle: input.userHandle } : {}) };
    }
    // A file dropped into the view, shown in the machine's file manager (a screen whose `drop` says `reveal`).
    case "reveal":
      if (typeof input.path !== "string" || input.path === "" || input.path.length > 4096) throw bad();
      return { t: "reveal", path: input.path };
    default:
      throw bad();
  }
}

// ── the `screens` topic ──

/// What the sync holds of a station's screens (station/sync.ts): its list as last said, or that it has none to say
/// (a station from before screens).
export type Held = { screens: J[]; outdated: boolean };

/// The viewer's role in the station's workspace allows driving its screens (a read-only member only sees).
export function mayDrive(inner: Inner, station: string): boolean {
  return get(inner.data.shared({ topic: "workspace", workspace: ofAddress(station) }), "role") !== "viewer";
}

/// The viewer's own names (as the station may name them among those on a screen): the account's name and email.
function myNames(inner: Inner, station: string): string[] {
  const sub = inner.workspaces.owner(ofAddress(station));
  const account = sub === null ? undefined : inner.accounts.list().find((a) => a.sub === sub);
  return [account?.name, account?.email].filter((n): n is string => typeof n === "string" && n !== "").map((n) => n.toLowerCase());
}

/// The names on a screen but the viewer's own (one of them: the viewer may be on it twice, in two windows).
export function othersOf(names: string[], mine: string[]): string[] {
  let skipped = false;
  const out: string[] = [];
  for (const name of names) {
    if (!skipped && mine.includes(name.toLowerCase())) {
      skipped = true;
      continue;
    }
    if (!out.includes(name)) out.push(name);
  }
  return out;
}

function names(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((n): n is string => typeof n === "string" && n !== "") : [];
}

/// The prefix an agent's view has among a screen's people (station/src/tools/computer.ts: `agent: <chat title>`).
const AGENT = "agent: ";

/// The station machine's own display among its screens (station/src/screens/desktop.ts, win-desktop.ts).
const DESKTOP = "desktop";

/// A name among a screen's people as the viewer reads it: an agent's by its chat.
export function personShown(name: string): string {
  return name.startsWith(AGENT) ? t("core-views.screen.agent", { title: name.slice(AGENT.length).trim() }) : name;
}

function listed(names: string[]): string {
  return names.length <= 2 ? names.join(t("core-views.screen.and")) : t("core-views.screen.many", { names: names.slice(0, 2).join(t("core-views.screen.and")), more: names.length - 2 });
}

/// The kinds of screen a station lists (one it names otherwise, from a newer station, is shown as its display).
type Kind = "desktop" | "browser" | "simulator";
const kindOf = (v: unknown): Kind => (v === "browser" || v === "simulator" ? v : "desktop");
const kindWords = (kind: Kind) => t(`core-views.screen.kind.${kind}`);

/// What a screen is, in words: its kind, its size, the chat that opened it, who is on it.
function itemLine(item: J): string {
  const parts = [kindWords(item.kind)];
  if (item.width > 0 && item.height > 0) parts.push(`${item.width}×${item.height}`);
  if (item.chat) parts.push(t("core-views.screen.openedBy", { title: item.chat.title }));
  const on = names(item.viewers);
  if (on.length > 0) parts.push(t("core-views.screen.on", { names: listed(on) }));
  return parts.join(" · ");
}

/// What a screen's station lacks for it, in a line for its row: what cannot be done now (the station's message, which
/// also says where it is granted, is for its view); null when nothing is.
function lacking(access: J): string | null {
  const missing = [...(access.capture ? [] : ["capture"]), ...(access.control ? [] : ["control"])];
  return missing.length > 0 ? unavailable(missing) : null;
}

/// The chat a session is in among the viewer's chats of the station (its `chatRows`): the session's own chat over one it
/// only takes part in; null when the viewer has none with it (archived, another workspace's, not read yet).
export function chatOf(inner: Inner, station: string, session: string): { id: string; title: string; link: string } | null {
  const rows = inner.data.shared({ topic: "chatRows", station });
  if (!Array.isArray(rows)) return null;
  const has = (row: J) => Array.isArray(get(row, "agents")) && (get(row, "agents") as J[]).some((a) => get(a, "key") === session);
  const row = rows.find((r) => get(r, "session") === session) ?? rows.find(has);
  const id = get(row, "id");
  if (typeof id !== "string" || id === "") return null;
  const title = typeof get(row, "title") === "string" && get(row, "title") !== "" ? (get(row, "title") as string) : t("core-views.screen.someChat");
  const addr = StationAddr.parse(station);
  return { id, title, link: `/w/${encode(addr.workspace)}/s/${encode(addr.station)}/chats/${encode(id)}` };
}

/// A screen's page in the app, as an agent's `screen` tool links it.
export function screenPath(station: string, id: string): string {
  const addr = StationAddr.parse(station);
  return `/w/${encode(addr.workspace)}/s/${encode(addr.station)}/screen/${encode(id)}`;
}

/// The `screens` topic's value: what is held (none while the station is down: `online` false).
export function screensView(inner: Inner, station: string, held: Held | undefined, online: boolean): J {
  const control = mayDrive(inner, station);
  if (held?.outdated) return { screens: [], outdated: true, control, known: true, note: t("core-views.screen.outdated") };
  if (held === undefined || !online) return { screens: [], outdated: false, control, known: held !== undefined };
  const screens = held.screens.flatMap((s) => {
    const id = get(s, "id");
    if (typeof id !== "string" || id === "") return [];
    const kind = kindOf(get(s, "kind"));
    const size = (v: unknown) => (finite(v) ? Math.max(0, Math.round(v)) : 0);
    const width = size(get(s, "width"));
    const height = size(get(s, "height"));
    const title = typeof get(s, "title") === "string" && get(s, "title") !== "" ? (get(s, "title") as string) : kindWords(kind);
    const by = get(s, "openedBy");
    const chat = typeof by === "string" && by !== "" ? chatOf(inner, station, by) : null;
    const controlledBy = names(get(s, "controlledBy"));
    const item = {
      id, kind, title, width, height, viewers: names(get(s, "viewers")), controlledBy, ...(get(s, "peek") === true ? { peek: true } : {}),
      // An agent drives it now (its view among the screen's people, AGENT).
      ...(controlledBy.some((n) => n.startsWith(AGENT)) ? { agent: true } : {}),
      // Closed from here by a member who may drive it (a read-only one only looks).
      ...(get(s, "closable") === true && control ? { closable: true } : {}),
      ...(chat ? { chat } : {}),
    };
    const access = accessOf(get(s, "access"));
    const clipboard = clipTypesOf(get(s, "clipboard"));
    const drop = dropOf(get(s, "drop"));
    return [{ ...item, ...(access ? { access } : {}), ...(clipboard.length ? { clipboard } : {}), ...(drop ? { drop } : {}), line: (access && lacking(access)) ?? itemLine(item), link: screenPath(station, id) }];
  });
  // The machine's own display (`desktop`) first: what a chat's screen button opens, at the head of every list of them.
  screens.sort((a, b) => Number(b.id === DESKTOP) - Number(a.id === DESKTOP));
  return { screens, outdated: false, control, known: true };
}

/// What a link to one of a station's screens shows in a message (the `screenCard` topic): the screen as its station's
/// list has it; one the list no longer has, as gone; one of a station not reached, as what its id says it is.
export function screenCard(inner: Inner, station: string, id: string, held: Held | undefined, online: boolean): J {
  const listed = screensView(inner, station, held, online).screens.find((s: J) => s.id === id);
  if (listed) return { kind: listed.kind, title: listed.title, line: listed.line, link: listed.link, gone: false, peek: listed.peek === true, width: listed.width, height: listed.height };
  const kind = kindOf(id.split(":")[0]);
  const gone = held !== undefined && !held.outdated && online;
  const line = gone ? t("core-views.screen.gone") : held?.outdated ? t("core-views.screen.outdated") : t("core-views.screen.remote");
  return { kind, title: kindWords(kind), line, link: screenPath(station, id), gone, peek: false, width: 0, height: 0 };
}

/// The clipboard types a station says a screen carries (`clipboard`): ours only.
export function clipTypesOf(v: unknown): ClipType[] {
  return Array.isArray(v) ? (["text", "png"] as const).filter((c) => v.includes(c)) : [];
}

/// Where a station puts a file dropped into a screen's view (`drop`); null when it takes none (one from before files).
export function dropOf(v: unknown): { folder: string; reveal: boolean } | null {
  return isObject(v) && typeof v.folder === "string" && v.folder !== "" ? { folder: v.folder, reveal: v.reveal === true } : null;
}

/// What a station says it lacks for a screen (its `access`), as the clients show it; null when nothing is said.
export function accessOf(v: unknown): J | null {
  if (!isObject(v)) return null;
  const out: J = { capture: v.capture !== false, control: v.control !== false };
  for (const k of ["message", "app", "path"]) if (typeof v[k] === "string" && v[k] !== "") out[k] = v[k];
  return out;
}

// ── views ──

/// A view open now, by its client and the name its UI gave it.
type Open = {
  station: string;
  screen: string;
  ack(ts: number): void;
  keyframe(): void;
  input(input: J): void;
  control(on: boolean): void;
  bounds(maxWidth: number, maxHeight: number, quality: ScreenQuality | null, fps: ScreenFps | null): void;
  look(region: Region | null, width: number, height: number): void;
  /// Fails (why, in words) while the view does not drive the screen, or the screen carries no such clipboard.
  clipboard(type: ClipType, data: Uint8Array, paste: boolean): CoreError | null;
  /// The station's list changed: who is on it may have.
  listed(): void;
};

const opened = new WeakMap<Inner, Map<string, Open>>();
const key = (client: ClientId, view: string) => `${client}\u0000${view}`;

/// A core's views open now (each core its own: a process may run several, as tests do).
function openIn(inner: Inner): Map<string, Open> {
  let views = opened.get(inner);
  if (!views) {
    views = new Map();
    opened.set(inner, views);
  }
  return views;
}

/// The station's list of screens changed: the views of its screens hear (who is on them).
export function screensChanged(inner: Inner, station: string): void {
  for (const view of openIn(inner).values()) if (view.station === station) view.listed();
}

/// Whether two asks are of the same size, 画质 and 帧率 (what `screen.bounds` changes).
function sameAsk(a: ScreenAsk, b: ScreenAsk): boolean {
  return a.maxWidth === b.maxWidth && a.maxHeight === b.maxHeight && a.quality === b.quality && a.fps === b.fps;
}

/// A view's next stream, opened before the one it takes the place of closed: its socket, the scope it closes with, and
/// what it was asked.
type Next = { socket: WireSocket; scope: Scope.Closeable; asked: ScreenAsk };

/// How a view's stream ended (`gone`: its screen went, a tab closed; `dropped`: the stream went, `seen` whether a frame
/// came on it first), or why it could not open.
type Outcome = { ended: string | null; gone?: true } | { reopen: Next } | { dropped: true; seen: boolean } | { failed: CoreError };

/// What a failure to open a view says the view is now: done for good (a phase), or worth trying again (null). The
/// station's statuses (docs/remote-screens.md): 404 no such screen, 400/415 no codec in common, 501 not supported here,
/// 503 not now (no grant, the capture failed), 403 not this member's.
function verdict(error: CoreError, outdated: boolean): { phase: string; message: string } | null {
  if (error.status === 404) {
    if (outdated || error.message.startsWith("no route ")) return { phase: "outdated", message: t("core-views.screen.outdated") };
    return { phase: "gone", message: t("core-views.screen.gone") };
  }
  if (error.status === 401 || error.status === 403 || error.status === 501 || error.status === 503) return { phase: "denied", message: error.message || t("core-views.screen.denied") };
  if (error.status !== undefined && error.status >= 400) return { phase: "failed", message: error.message };
  if (error.code === "unsupported" || error.code === "invalid_params" || error.code === "gone") return { phase: "failed", message: error.message };
  return null;
}

export function install(): void {
  handlers.screen = (inner, call, progress, at, ctx) => {
    const c = (call as Extract<import("./core/calls.ts").Call, { kind: "screen" }>).call;
    if (c.kind === "view") return view(inner, c, progress, at, ctx);
    const target = openIn(inner).get(key(at[0], c.view));
    // A frame acknowledged, a key frame asked or a part looked at, after the view went: nothing to do.
    if (!target) return c.kind === "ack" || c.kind === "keyframe" || c.kind === "look" ? Effect.succeed(null) : Effect.fail(new CoreError("not_found", t("core-misc.screen.closed")));
    switch (c.kind) {
      case "ack":
        target.ack(c.ts);
        break;
      case "keyframe":
        target.keyframe();
        break;
      case "input":
        target.input(c.input);
        break;
      case "control":
        target.control(c.control);
        break;
      case "bounds":
        target.bounds(c.maxWidth, c.maxHeight, c.quality, c.fps);
        break;
      case "look":
        target.look(c.region, c.width, c.height);
        break;
      case "clipboard": {
        const refused = target.clipboard(c.type, c.data, c.paste);
        if (refused) return Effect.fail(refused);
        break;
      }
    }
    return Effect.succeed(null);
  };
}

function view(inner: Inner, c: Extract<ScreenCall, { kind: "view" }>, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  const name = key(at[0], c.view);
  const open = openIn(inner);
  if (open.has(name)) return Effect.fail(CoreError.invalid(t("core-misc.screen.open")));
  return Effect.gen(function* () {
    const addr = yield* Effect.try({ try: () => StationAddr.parse(c.station), catch: asCoreError });
    const station = addr.toString();
    const may = mayDrive(inner, station);
    const mine = myNames(inner, station);
    /// What the page is told (ScreenViewState), as it is now.
    const state: J = { phase: "connecting", title: "", control: false, may, others: [], line: "" };
    // Who is on it as the view's own stream says (else as the station's list does).
    let onIt: string[] | null = null;
    // Its display's scale as the stream last said (a Windows station's desktop, to a view that drives it).
    let displayScale: { percent: number; recommended: number; steps: number[] } | null = null;
    let displaySize: { width: number; height: number; modes: Size[] } | null = null;
    let driving: string[] | null = null;
    // Decided once the station's list is read (below) for a view opened with no `control` asked.
    let wanted = c.ask.control && may;
    // What the station is asked for: as the view opened, its size, 画质 and 帧率 as last asked (`screen.bounds`).
    let bounds = c.ask;
    // The stream open now: where acks, key frames and input go (in order, one writer); null between streams.
    let out: Queue.Queue<Uint8Array> | null = null;
    let reopen: Deferred.Deferred<void> | null = null;

    const listedItem = (): J => {
      const held = inner.stations.screens(station);
      return held?.screens.find((s) => get(s, "id") === c.screen);
    };
    const tell = () => {
      const item = listedItem();
      if (state.title === "" && typeof get(item, "title") === "string") state.title = get(item, "title");
      if (state.kind === undefined && typeof get(item, "kind") === "string") state.kind = get(item, "kind");
      const others = othersOf(onIt ?? names(get(item, "viewers")), mine).map(personShown);
      // Who else drives it now: an agent at work, another person.
      const drivers = othersOf(driving ?? names(get(item, "controlledBy")), mine);
      const controllers = drivers.map(personShown);
      state.others = others;
      state.controllers = controllers;
      // Taking over is one tap while another drives it and this view only looks (and may drive).
      state.takeOver = !state.control && may && controllers.length > 0 && state.access?.control !== false;
      const mode = state.control ? t("core-views.screen.control") : t("core-views.screen.watch");
      const watching = others.filter((n) => !controllers.includes(n));
      const parts = [mode];
      if (!state.control && controllers.length > 0) parts.push(t("core-views.screen.driving", { names: listed(controllers) }));
      if (state.control) {
        // Driving it: an agent's input waits while a person drives (station/src/tools/computer.ts); another person's not.
        const agents = drivers.filter((n) => n.startsWith(AGENT)).map(personShown);
        const people = drivers.filter((n) => !n.startsWith(AGENT));
        if (agents.length > 0) parts.push(t("core-views.screen.paused", { names: listed(agents) }));
        if (people.length > 0) parts.push(t("core-views.screen.alsoDriving", { names: listed(people) }));
      }
      if (watching.length > 0) parts.push(t("core-views.screen.alsoOn", { names: listed(watching) }));
      state.line = parts.join(" · ");
      // What a person driving it has of its clipboard and of files dropped into it (none while only looking).
      const clipboard = state.control ? clipTypesOf(get(item, "clipboard")) : [];
      const drop = state.control ? dropOf(get(item, "drop")) : null;
      state.clipboard = clipboard;
      if (drop) state.drop = drop;
      else delete state.drop;
      const scale = state.control ? displayScale : null;
      if (scale) state.scale = scale;
      else delete state.scale;
      const resolution = state.control ? displaySize : null;
      if (resolution) state.resolution = resolution;
      else delete state.resolution;
      progress({
        state: {
          ...state,
          others: [...others],
          controllers: [...controllers],
          clipboard: [...clipboard],
          ...(drop ? { drop: { ...drop } } : {}),
          ...(scale ? { scale: { ...scale, steps: [...scale.steps] } } : {}),
          ...(resolution ? { resolution: { ...resolution, modes: resolution.modes.map((m) => ({ ...m })) } } : {}),
        },
      });
    };
    const write = (bytes: Uint8Array) => {
      if (out !== null) Queue.offerUnsafe(out, bytes);
    };
    // The part of the screen the page shows as it last said, and the part the station was asked for (null: the whole;
    // each stream starts with the whole). A look goes once it has stayed LOOK_MS, so a pinch or a pan asks once, as it
    // ends, not at each step of it.
    type Look = { region: Region | null; maxWidth: number; maxHeight: number };
    const whole: Look = { region: null, maxWidth: 0, maxHeight: 0 };
    let looking: Look = whole;
    let asked = JSON.stringify(whole);
    const looks = yield* Queue.unbounded<void>();
    const ask = () => {
      const now = JSON.stringify(looking);
      if (now === asked || out === null) return;
      asked = now;
      write(lookFrame(looking.region, looking.maxWidth, looking.maxHeight));
    };
    yield* Effect.forkScoped(
      Effect.forever(
        Effect.gen(function* () {
          yield* Queue.take(looks);
          // Settled: no other look for LOOK_MS.
          for (;;) {
            const more = yield* Effect.raceFirst(Effect.map(Queue.take(looks), () => Option.some(true)), Effect.as(Effect.sleep(LOOK_MS), Option.none<boolean>()));
            if (Option.isNone(more)) break;
          }
          ask();
        }),
      ),
    );

    open.set(name, {
      station,
      screen: c.screen,
      ack: (ts) => write(ackFrame(ts)),
      keyframe: () => write(keyframeFrame()),
      // Only while driving: what the view only looks at takes no input.
      input: (input) => {
        if (state.control) write(inputFrame(input));
      },
      clipboard: (type, data, paste) => {
        if (!state.control || out === null) return new CoreError("invalid_params", t("core-misc.screen.notDriving"));
        if (!clipTypesOf(get(listedItem(), "clipboard")).includes(type)) return new CoreError("unsupported", t("core-misc.screen.noClipboard"));
        write(clipboardFrame(type, data, paste));
        return null;
      },
      // Shown as large as the page shows it, no larger than the view asked for the whole screen.
      look: (region, width, height) => {
        looking = region === null ? whole : { region, maxWidth: Math.min(width, bounds.maxWidth), maxHeight: Math.min(height, bounds.maxHeight) };
        Queue.offerUnsafe(looks, undefined);
      },
      control: (on) => {
        const next = on && may;
        if (next === wanted) return;
        wanted = next;
        if (reopen !== null) Deferred.doneUnsafe(reopen, Effect.void);
      },
      bounds: (maxWidth, maxHeight, quality, fps) => {
        // (a preview's are none, as it opened)
        const next: ScreenAsk = { ...bounds, maxWidth, maxHeight };
        delete next.quality;
        delete next.fps;
        if (quality && !c.ask.peek) next.quality = quality;
        if (fps && !c.ask.peek) next.fps = fps;
        if (sameAsk(next, bounds)) return;
        bounds = next;
        if (reopen !== null) Deferred.doneUnsafe(reopen, Effect.void);
      },
      listed: () => tell(),
    });
    yield* Effect.addFinalizer(() => Effect.sync(() => open.delete(name)));

    // A station whose screens are not known yet is asked first: one from before screens would take the view's stream
    // for a request and never answer it.
    if (inner.stations.screens(station) === undefined) yield* Effect.ignore(inner.stations.readScreens(station), { log: "Unhandled", message: "screens read" });
    if (inner.stations.screens(station)?.outdated) {
      state.phase = "outdated";
      state.message = t("core-views.screen.outdated");
      tell();
      return null;
    }
    // A view is opened only of a screen the station listed (docs/remote-screens.md): not listed as it was held, its
    // list is read again first.
    if (listedItem() === undefined) yield* Effect.ignore(inner.stations.readScreens(station), { log: "Unhandled", message: "screens read" });
    if (listedItem() === undefined && inner.stations.screens(station) !== undefined) {
      state.phase = "gone";
      state.message = t("core-views.screen.gone");
      tell();
      return null;
    }
    // A preview only of a screen its station says can be previewed: one from before previews would take it for a view
    // (shown among those on it, its tab brought forward).
    if (c.ask.peek && get(listedItem(), "peek") !== true) {
      state.phase = "denied";
      state.message = t("core-views.screen.denied");
      tell();
      return null;
    }
    // Opened with no mode asked (a link, the station's page): only looking while someone else (an agent at work, a
    // person) drives it, so a person who opens it to watch does not hold the agent off; else driving. The viewer's own
    // views are not someone else, however many the list names: another window of theirs, or one of an app killed with
    // the view open, which the station still holds until it finds the connection gone.
    if (c.auto) wanted = may && names(get(listedItem(), "controlledBy")).every((n) => mine.includes(n.toLowerCase()));
    tell();

    /// One stream (`ready`: opened already, as the one before it ended): opened, its frames read until it ends, is to be
    /// opened again, or fails.
    const attempt = (ready: Next | null): Effect.Effect<Outcome> =>
      Effect.scoped(
        Effect.gen(function* () {
          let socket: WireSocket;
          let sent: ScreenAsk;
          if (ready !== null) {
            yield* Effect.addFinalizer(() => Scope.close(ready.scope, Exit.void));
            ({ socket, asked: sent } = ready);
          } else {
            sent = { ...bounds, control: wanted };
            const opened = yield* Effect.result(inner.stations.requests.screenView(addr, c.screen, sent, ctx));
            if (opened._tag === "Failure") return { failed: opened.failure } as Outcome;
            socket = opened.success;
          }
          const control = sent.control;
          const queue = yield* Queue.unbounded<Uint8Array>();
          out = queue;
          // A new stream frames the whole screen: the part looked at, asked of it at once.
          asked = JSON.stringify(whole);
          ask();
          yield* Effect.addFinalizer(() => Effect.sync(() => (out = out === queue ? null : out)));
          // Its writer goes with the stream (the attempt's scope).
          yield* Effect.forkScoped(Effect.ignore(Effect.forever(Effect.flatMap(Queue.take(queue), (bytes) => socket.send.write(bytes))), { log: "Unhandled", message: "screen input sent" }));
          const again = Deferred.makeUnsafe<void>();
          reopen = again;
          // Another mode or size asked while it opened: opened again with it.
          if (wanted !== control || !sameAsk(bounds, sent)) Deferred.doneUnsafe(again, Effect.void);
          state.control = control;
          if (state.phase !== "live" || state.message !== undefined) {
            state.phase = state.width !== undefined ? "live" : "connecting";
            delete state.message;
          }
          tell();
          // Its picture and sound read by the host and said to the app itself where it can (Apple's shell: no frame
          // through here), what it leaves here the config (its size, for the state) and a video frame's head after it.
          const tapped = socket.tap === undefined ? false : yield* socket.tap(at[1]);
          const reader = new FrameReader();
          let seen = false;
          for (;;) {
            const next = yield* Effect.raceFirst(
              Effect.map(Effect.result(socket.reply.body.take), (r) => ({ r }) as const),
              Effect.as(Deferred.await(again), { reopen: true } as const),
            );
            if ("reopen" in next) {
              // The next stream opened while this one stays: the station has a view of this client's all along.
              const scope = yield* Scope.make();
              const nextAsk = { ...bounds, control: wanted };
              const opened = yield* Effect.result(Scope.provide(inner.stations.requests.screenView(addr, c.screen, nextAsk, ctx), scope));
              if (opened._tag === "Failure") {
                yield* Scope.close(scope, Exit.void);
                return { failed: opened.failure } as Outcome;
              }
              return { reopen: { socket: opened.success, scope, asked: nextAsk } } as Outcome;
            }
            if (next.r._tag === "Failure" || next.r.success === null) return { dropped: true, seen } as Outcome;
            reader.push(next.r.success);
            for (;;) {
              let frame;
              try {
                frame = reader.next();
              } catch (e) {
                return { failed: new CoreError("screen", t("core-misc.screen.garbled", { error: (e as Error).message })) } as Outcome;
              }
              if (frame === null) break;
              if ("config" in frame) {
                const { codec, width, height, description, region } = frame.config;
                // The whole screen's size as its pictures have it (what the page lays it out by): a part's config
                // leaves it as the whole's last said (one before any: as large as that part's pixels make it).
                const [ww, wh] = region === null ? [width, height] : state.width === undefined ? [Math.round(width / region.w), Math.round(height / region.h)] : [state.width, state.height];
                const changed = state.codec !== codec || state.width !== ww || state.height !== wh;
                state.codec = codec;
                state.width = ww;
                state.height = wh;
                if (!tapped) progress({ config: { codec, width, height, ...(region ? { region } : {}) } }, description ?? undefined);
                if (changed) tell();
              } else if ("video" in frame) {
                seen = true;
                if (state.phase !== "live") {
                  state.phase = "live";
                  tell();
                }
                if (!tapped) progress({ frame: { key: frame.video.key, ts: frame.video.ts } }, frame.video.data);
              } else if ("audioConfig" in frame) {
                progress({ audioConfig: frame.audioConfig });
              } else if ("audio" in frame) {
                progress({ audio: { ts: frame.audio.ts } }, frame.audio.data);
              } else if ("clipboard" in frame) {
                // A copy made on the screen, for the page to put on this device's clipboard (only while driving it).
                if (!state.control) continue;
                const clip = frame.clipboard;
                if (clip.type === "text") {
                  if (clip.data.length > 0 && clip.data.length <= CLIP_TEXT_MAX) progress({ clipboard: { type: "text", text: fromUtf8(clip.data) } });
                } else if (clip.data.length > 0 && clip.data.length <= CLIP_PNG_MAX) progress({ clipboard: { type: "png", size: clip.data.length } }, clip.data);
              } else if ("state" in frame) {
                const s = frame.state;
                if (!isObject(s)) continue;
                if (isObject(s.cursor) && finite(s.cursor.x) && finite(s.cursor.y)) state.cursor = { x: unit(s.cursor.x), y: unit(s.cursor.y), ...(typeof s.cursor.shape === "string" ? { shape: s.cursor.shape } : {}) };
                else if (s.cursor === null) delete state.cursor;
                if (typeof s.title === "string" && s.title !== "") state.title = s.title;
                // The login field in focus, while driving it: this device's password manager may fill it (`fill`).
                if (s.login === null) delete state.login;
                else if (state.control && isObject(s.login) && typeof s.login.host === "string" && s.login.host !== "" && s.login.host.length <= 253 && (s.login.field === "username" || s.login.field === "password")) {
                  state.login = { host: s.login.host, field: s.login.field };
                }
                // A page's passkey sign-in, while driving it: this device's passkeys may answer it (`passkey`).
                if (s.passkey === null) delete state.passkey;
                else if (state.control && isObject(s.passkey)) {
                  const p = s.passkey;
                  const str = (v: unknown, max: number): v is string => typeof v === "string" && v !== "" && v.length <= max;
                  const allow = Array.isArray(p.allow) ? p.allow.filter((a: unknown) => str(a, 1366)).slice(0, 64) : [];
                  if (str(p.id, 32) && str(p.host, 253) && str(p.rpId, 253) && str(p.clientData, 4096)) {
                    state.passkey = { id: p.id, host: p.host, rpId: p.rpId, clientData: p.clientData, allow, userVerification: typeof p.userVerification === "string" ? p.userVerification : "preferred" };
                  }
                }
                // Whether this view's input is taken, as the station says (a read-only member's is not).
                if (typeof s.control === "boolean") state.control = s.control && control;
                if (!state.control) {
                  delete state.login;
                  delete state.passkey;
                }
                const access = accessOf(s.access);
                if (access) state.access = access;
                if (Array.isArray(s.viewers)) onIt = names(s.viewers);
                if (Array.isArray(s.controlledBy)) driving = names(s.controlledBy);
                const ms = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v) && v >= 0 && v < 600_000;
                if (isObject(s.latency) && ms(s.latency.frame) && ms(s.latency.before)) state.latency = { frame: Math.round(s.latency.frame), before: Math.round(s.latency.before) };
                if (isObject(s.video) && typeof s.video.capture === "string") {
                  state.video = {
                    capture: s.video.capture.slice(0, 80),
                    ...(typeof s.video.encoder === "string" ? { encoder: s.video.encoder.slice(0, 200) } : {}),
                    ...(typeof s.video.hardware === "boolean" ? { hardware: s.video.hardware } : {}),
                  };
                }
                const scale = scaleOf(s.scale);
                if (scale) displayScale = scale;
                const size = resolutionOf(s.resolution);
                if (size) displaySize = size;
                if (s.ended !== undefined && s.ended !== null && s.ended !== false) {
                  // The station stopping (an update, a restart): opened again once it is back.
                  if (s.ended === "stopping") return { dropped: true, seen } as Outcome;
                  if (s.ended === "gone") return { ended: t("core-views.screen.gone"), gone: true } as Outcome;
                  return { ended: typeof s.ended === "string" && s.ended !== "" && s.ended !== "finished" ? s.ended : null } as Outcome;
                }
                tell();
              }
            }
          }
        }),
      );

    let misses = 0;
    let ready: Next | null = null;
    // (one opened as the view ends: closed with it)
    yield* Effect.addFinalizer(() => (ready === null ? Effect.void : Scope.close(ready.scope, Exit.void)));
    for (;;) {
      const outcome: Outcome = yield* attempt(ready);
      ready = null;
      if ("reopen" in outcome) {
        ready = outcome.reopen;
        continue;
      }
      if ("ended" in outcome) {
        // Its screen gone (a tab closed) is over for good, as one no longer listed: nothing to open again.
        state.phase = outcome.gone ? "gone" : "ended";
        state.message = outcome.ended ?? t("core-views.screen.ended");
        delete state.cursor;
        tell();
        return null;
      }
      if ("failed" in outcome) {
        const final = verdict(outcome.failed, inner.stations.screens(station)?.outdated === true);
        if (final !== null) {
          state.phase = final.phase;
          state.message = final.message;
          const access = accessOf((outcome.failed as CoreError & { access?: unknown }).access);
          if (access) state.access = access;
          delete state.cursor;
          tell();
          return null;
        }
      } else if (outcome.seen) misses = 0;
      // The stream went, or could not be opened now: opened again after a while.
      if (misses >= REOPEN_MS.length) {
        state.phase = "failed";
        state.message = "failed" in outcome ? outcome.failed.message : t("core-views.screen.lost");
        tell();
        return null;
      }
      state.phase = "reconnecting";
      state.message = t("core-views.screen.reconnecting");
      tell();
      yield* Effect.sleep(REOPEN_MS[misses]!);
      misses++;
    }
  }).pipe(Effect.scoped);
}
