// A station's screens, seen and driven from a client (docs/remote-screens.md): the `screens` topic (what the sync holds
// of each station's `GET /screens` and its `screens` events, station/sync.ts) and the `screen.*` calls. A view is a
// stream to the station (screen-frames.ts); its frames go to the UI as they come, their bytes beside the JSON
// (protocol.ts), and the UI acknowledges each one it decoded, which is what lets the station send the next: a slow link
// or a slow decoder lowers the frame rate rather than queueing. What the page draws of the view (its phase, 只看/控制,
// who else is on it) is said whole as `{state}` each time it changes; the page only draws it. The link dropping opens
// the view again; switching 只看/控制 opens it again with the other. While it drives the screen, the screen's clipboard
// goes both ways (`screen.clipboard` sets it and pastes; a copy made on it comes as `{clipboard}`), and where a file
// dropped into it goes (`drop`) is in its state, for the page to upload it with the drive's upload.
import { Deferred, Effect, Queue } from "effect";
import type { Inner, Progress } from "./core.ts";
import { handlers } from "./core/execute.ts";
import { CoreError, asCoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import { CLIP_PNG_MAX, CLIP_TEXT_MAX, type ClipType, FrameReader, ackFrame, clipboardFrame, inputFrame, keyframeFrame } from "./screen-frames.ts";
import { StationAddr } from "./station/addr.ts";
import type { ScreenAsk, WireSocket } from "./station/wire.ts";
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
/// What a key's names and a text may hold.
const KEY_MAX = 64;
const TEXT_MAX = 16_384;

export type ScreenCall =
  /// `ask.control` as asked; `auto` (none asked): control unless someone else drives it as it opens.
  | { kind: "view"; station: string; screen: string; view: string; ask: ScreenAsk; auto: boolean }
  | { kind: "ack"; view: string; ts: number }
  | { kind: "keyframe"; view: string }
  | { kind: "input"; view: string; input: J }
  | { kind: "control"; view: string; control: boolean }
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
      return {
        kind: "view",
        station,
        screen: text(params, "screen"),
        view: text(params, "view"),
        ask: { maxWidth: size("maxWidth", MAX_WIDTH), maxHeight: size("maxHeight", MAX_HEIGHT), codecs, control: control !== false && !peek, ...(peek ? { peek: true } : {}) },
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
    case "screen.control": {
      const control = get(params, "control");
      if (typeof control !== "boolean") throw CoreError.invalid(t("core-misc.params.missing", { field: "control" }));
      return { kind: "control", view: text(params, "view"), control };
    }
    default:
      return null;
  }
}

/// A person's input as the station takes it (station/src/screens/source.ts `ScreenInput`), or why it is none.
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

/// A name among a screen's people as the viewer reads it: an agent's by its chat.
export function personShown(name: string): string {
  return name.startsWith(AGENT) ? t("core-views.screen.agent", { title: name.slice(AGENT.length).trim() }) : name;
}

function listed(names: string[]): string {
  return names.length <= 2 ? names.join(t("core-views.screen.and")) : t("core-views.screen.many", { names: names.slice(0, 2).join(t("core-views.screen.and")), more: names.length - 2 });
}

/// What a screen is, in words: its kind, its size, the chat that opened it, who is on it.
function itemLine(item: J): string {
  const parts = [item.kind === "browser" ? t("core-views.screen.kind.browser") : t("core-views.screen.kind.desktop")];
  if (item.width > 0 && item.height > 0) parts.push(`${item.width}×${item.height}`);
  if (item.chat) parts.push(t("core-views.screen.openedBy", { title: item.chat.title }));
  const on = names(item.viewers);
  if (on.length > 0) parts.push(t("core-views.screen.on", { names: listed(on) }));
  return parts.join(" · ");
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

/// The `screens` topic's value: what is held (none while the station is not reached).
export function screensView(inner: Inner, station: string, held: Held | undefined, online: boolean): J {
  const control = mayDrive(inner, station);
  if (held?.outdated) return { screens: [], outdated: true, control, known: true, note: t("core-views.screen.outdated") };
  if (held === undefined || !online) return { screens: [], outdated: false, control, known: held !== undefined };
  const screens = held.screens.flatMap((s) => {
    const id = get(s, "id");
    if (typeof id !== "string" || id === "") return [];
    const kind = get(s, "kind") === "browser" ? "browser" : "desktop";
    const size = (v: unknown) => (finite(v) ? Math.max(0, Math.round(v)) : 0);
    const width = size(get(s, "width"));
    const height = size(get(s, "height"));
    const title = typeof get(s, "title") === "string" && get(s, "title") !== "" ? (get(s, "title") as string) : kind === "browser" ? t("core-views.screen.kind.browser") : t("core-views.screen.kind.desktop");
    const by = get(s, "openedBy");
    const chat = typeof by === "string" && by !== "" ? chatOf(inner, station, by) : null;
    const item = {
      id, kind, title, width, height, viewers: names(get(s, "viewers")), controlledBy: names(get(s, "controlledBy")), ...(get(s, "peek") === true ? { peek: true } : {}),
      // Closed from here by a member who may drive it (a read-only one only looks).
      ...(get(s, "closable") === true && control ? { closable: true } : {}),
      ...(chat ? { chat } : {}),
    };
    const access = accessOf(get(s, "access"));
    const clipboard = clipTypesOf(get(s, "clipboard"));
    const drop = dropOf(get(s, "drop"));
    return [{ ...item, ...(access ? { access } : {}), ...(clipboard.length ? { clipboard } : {}), ...(drop ? { drop } : {}), line: access?.message ?? itemLine(item), link: screenPath(station, id) }];
  });
  return { screens, outdated: false, control, known: true };
}

/// What a link to one of a station's screens shows in a message (the `screenCard` topic): the screen as its station's
/// list has it; one the list no longer has, as gone; one of a station not reached, as what its id says it is.
export function screenCard(inner: Inner, station: string, id: string, held: Held | undefined, online: boolean): J {
  const listed = screensView(inner, station, held, online).screens.find((s: J) => s.id === id);
  if (listed) return { kind: listed.kind, title: listed.title, line: listed.line, link: listed.link, gone: false, peek: listed.peek === true, width: listed.width, height: listed.height };
  const kind = id.startsWith("browser:") ? "browser" : "desktop";
  const gone = held !== undefined && !held.outdated && online;
  const line = gone ? t("core-views.screen.gone") : held?.outdated ? t("core-views.screen.outdated") : t("core-views.screen.remote");
  return { kind, title: kind === "browser" ? t("core-views.screen.kind.browser") : t("core-views.screen.kind.desktop"), line, link: screenPath(station, id), gone, peek: false, width: 0, height: 0 };
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

/// How a view's stream ended (`dropped`: it went, `seen` whether a frame came on it first), or why it could not open.
type Outcome = { ended: string | null } | { reopen: true } | { dropped: true; seen: boolean } | { failed: CoreError };

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
    // A frame acknowledged, or a key frame asked, after the view went: nothing to do.
    if (!target) return c.kind === "ack" || c.kind === "keyframe" ? Effect.succeed(null) : Effect.fail(new CoreError("not_found", t("core-misc.screen.closed")));
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
    let driving: string[] | null = null;
    // Decided once the station's list is read (below) for a view opened with no `control` asked.
    let wanted = c.ask.control && may;
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
      progress({ state: { ...state, others: [...others], controllers: [...controllers], clipboard: [...clipboard], ...(drop ? { drop: { ...drop } } : {}) } });
    };
    const write = (bytes: Uint8Array) => {
      if (out !== null) Queue.offerUnsafe(out, bytes);
    };

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
      control: (on) => {
        const next = on && may;
        if (next === wanted) return;
        wanted = next;
        if (reopen !== null) Deferred.doneUnsafe(reopen, Effect.void);
      },
      listed: () => tell(),
    });
    yield* Effect.addFinalizer(() => Effect.sync(() => open.delete(name)));

    // A station whose screens are not known yet is asked first: one from before screens would take the view's stream
    // for a request and never answer it.
    if (inner.stations.screens(station) === undefined) yield* Effect.ignore(inner.stations.readScreens(station));
    if (inner.stations.screens(station)?.outdated) {
      state.phase = "outdated";
      state.message = t("core-views.screen.outdated");
      tell();
      return null;
    }
    // A view is opened only of a screen the station listed (docs/remote-screens.md): not listed as it was held, its
    // list is read again first.
    if (listedItem() === undefined) yield* Effect.ignore(inner.stations.readScreens(station));
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

    /// One stream: opened, its frames read until it ends, is to be opened again, or fails.
    const attempt = (control: boolean): Effect.Effect<Outcome> =>
      Effect.scoped(
        Effect.gen(function* () {
          const opened = yield* Effect.result(inner.stations.requests.screenView(addr, c.screen, { ...c.ask, control }, ctx));
          if (opened._tag === "Failure") return { failed: opened.failure } as Outcome;
          const socket: WireSocket = opened.success;
          const queue = yield* Queue.unbounded<Uint8Array>();
          out = queue;
          yield* Effect.addFinalizer(() => Effect.sync(() => (out = out === queue ? null : out)));
          // Its writer goes with the stream (the attempt's scope).
          yield* Effect.forkScoped(Effect.ignore(Effect.forever(Effect.flatMap(Queue.take(queue), (bytes) => socket.send.write(bytes)))));
          const again = Deferred.makeUnsafe<void>();
          reopen = again;
          state.control = control;
          if (state.phase !== "live" || state.message !== undefined) {
            state.phase = state.width !== undefined ? "live" : "connecting";
            delete state.message;
          }
          tell();
          const reader = new FrameReader();
          let seen = false;
          for (;;) {
            const next = yield* Effect.raceFirst(
              Effect.map(Effect.result(socket.reply.body.take), (r) => ({ r }) as const),
              Effect.as(Deferred.await(again), { reopen: true } as const),
            );
            if ("reopen" in next) return { reopen: true } as Outcome;
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
                const { codec, width, height, description } = frame.config;
                const changed = state.codec !== codec || state.width !== width || state.height !== height;
                state.codec = codec;
                state.width = width;
                state.height = height;
                progress({ config: { codec, width, height } }, description ?? undefined);
                if (changed) tell();
              } else if ("video" in frame) {
                seen = true;
                if (state.phase !== "live") {
                  state.phase = "live";
                  tell();
                }
                progress({ frame: { key: frame.video.key, ts: frame.video.ts } }, frame.video.data);
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
                // Whether this view's input is taken, as the station says (a read-only member's is not).
                if (typeof s.control === "boolean") state.control = s.control && control;
                const access = accessOf(s.access);
                if (access) state.access = access;
                if (Array.isArray(s.viewers)) onIt = names(s.viewers);
                if (Array.isArray(s.controlledBy)) driving = names(s.controlledBy);
                if (s.ended !== undefined && s.ended !== null && s.ended !== false) {
                  // The station stopping (an update, a restart): opened again once it is back.
                  if (s.ended === "stopping") return { dropped: true, seen } as Outcome;
                  return { ended: s.ended === "gone" ? t("core-views.screen.gone") : typeof s.ended === "string" && s.ended !== "" && s.ended !== "finished" ? s.ended : null } as Outcome;
                }
                tell();
              }
            }
          }
        }),
      );

    let misses = 0;
    for (;;) {
      const outcome = yield* attempt(wanted);
      if ("reopen" in outcome) continue;
      if ("ended" in outcome) {
        state.phase = "ended";
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
