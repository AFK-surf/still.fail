// A station's screens, seen and driven from a client (docs/remote-screens.md): the `screens` topic (what the sync holds
// of each station's `GET /screens` and its `screens` events, station/sync.ts) and the `screen.*` calls. A view is a
// stream to the station (screen-frames.ts); its frames go to the UI as they come, their bytes beside the JSON
// (protocol.ts), and the UI acknowledges each one it decoded, which is what lets the station send the next: a slow link
// or a slow decoder lowers the frame rate rather than queueing. What the page draws of the view (its phase, 只看/控制,
// who else is on it) is said whole as `{state}` each time it changes; the page only draws it. The link dropping opens
// the view again; switching 只看/控制 opens it again with the other.
import { Deferred, Effect, Queue } from "effect";
import type { Inner, Progress } from "./core.ts";
import { handlers } from "./core/execute.ts";
import { CoreError, asCoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import { FrameReader, ackFrame, inputFrame, keyframeFrame } from "./screen-frames.ts";
import { StationAddr } from "./station/addr.ts";
import type { ScreenAsk, WireSocket } from "./station/wire.ts";
import type { ClientId, RequestId } from "./protocol.ts";
import type { SpanContext } from "./trace.ts";
import { get, isObject } from "./util.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export const CODECS = ["h264", "jpeg"];
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
  | { kind: "view"; station: string; screen: string; view: string; ask: ScreenAsk }
  | { kind: "ack"; view: string; ts: number }
  | { kind: "keyframe"; view: string }
  | { kind: "input"; view: string; input: J }
  | { kind: "control"; view: string; control: boolean };

const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const unit = (v: number) => Math.min(1, Math.max(0, v));

function text(params: unknown, field: string): string {
  const v = get(params, field);
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
}

/// The `screen.*` calls by name; null for any other.
export function parseScreen(name: string, params: unknown): ScreenCall | null {
  switch (name) {
    case "screen.view": {
      const station = text(params, "station");
      StationAddr.parse(station);
      const codecs = Array.isArray(get(params, "codecs")) ? (get(params, "codecs") as unknown[]).filter((c): c is string => typeof c === "string" && CODECS.includes(c)) : CODECS;
      if (codecs.length === 0) throw CoreError.invalid(t("core-misc.screen.noCodec"));
      const size = (field: string, otherwise: number) => {
        const v = get(params, field);
        return finite(v) && v >= 1 ? Math.min(Math.round(v), LIMIT) : otherwise;
      };
      const control = get(params, "control");
      return {
        kind: "view",
        station,
        screen: text(params, "screen"),
        view: text(params, "view"),
        ask: { maxWidth: size("maxWidth", MAX_WIDTH), maxHeight: size("maxHeight", MAX_HEIGHT), codecs, control: control !== false },
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

function listed(names: string[]): string {
  return names.length <= 2 ? names.join(t("core-views.screen.and")) : t("core-views.screen.many", { names: names.slice(0, 2).join(t("core-views.screen.and")), more: names.length - 2 });
}

/// What a screen is, in words: its kind, its size, who is on it.
function itemLine(item: J): string {
  const parts = [item.kind === "browser" ? t("core-views.screen.kind.browser") : t("core-views.screen.kind.desktop")];
  if (item.width > 0 && item.height > 0) parts.push(`${item.width}×${item.height}`);
  const on = names(item.viewers);
  if (on.length > 0) parts.push(t("core-views.screen.on", { names: listed(on) }));
  return parts.join(" · ");
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
    const item = { id, kind, title, width, height, viewers: names(get(s, "viewers")) };
    return [{ ...item, line: itemLine(item), link: screenPath(station, id) }];
  });
  return { screens, outdated: false, control, known: true };
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

/// What a failure to open a view says the view is now: done for good (a phase), or worth trying again (null).
function verdict(error: CoreError, outdated: boolean): { phase: string; message: string } | null {
  if (error.status === 404) {
    if (outdated || error.message.startsWith("no route ")) return { phase: "outdated", message: t("core-views.screen.outdated") };
    return { phase: "gone", message: t("core-views.screen.gone") };
  }
  if (error.status === 401 || error.status === 403) return { phase: "denied", message: error.message || t("core-views.screen.denied") };
  if (error.status !== undefined && error.status >= 400 && error.status < 500) return { phase: "denied", message: error.message || t("core-views.screen.denied") };
  if (error.status !== undefined && error.status >= 500) return { phase: "failed", message: error.message };
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
    let controlledBy: string[] = [];
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
      const others = othersOf([...controlledBy, ...names(get(item, "viewers"))], mine);
      state.others = others;
      const mode = state.control ? t("core-views.screen.control") : t("core-views.screen.watch");
      state.line = others.length > 0 ? `${mode} · ${t("core-views.screen.alsoOn", { names: listed(others) })}` : mode;
      progress({ state: { ...state, others: [...others] } });
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
              } else if ("state" in frame) {
                const s = frame.state;
                if (!isObject(s)) continue;
                if (isObject(s.cursor) && finite(s.cursor.x) && finite(s.cursor.y)) state.cursor = { x: unit(s.cursor.x), y: unit(s.cursor.y), ...(typeof s.cursor.shape === "string" ? { shape: s.cursor.shape } : {}) };
                else if (s.cursor === null) delete state.cursor;
                if (typeof s.title === "string" && s.title !== "") state.title = s.title;
                if (Array.isArray(s.controlledBy)) controlledBy = names(s.controlledBy);
                if (s.ended !== undefined && s.ended !== null && s.ended !== false) return { ended: typeof s.ended === "string" && s.ended !== "" ? s.ended : null } as Outcome;
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
