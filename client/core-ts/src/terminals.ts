// A station's terminals, from a client (station/src/terminals/): the `terminals` topic (what the sync holds of each
// station's GET /terminals and its `terminals` events, station/sync.ts) and the `terminal.*` calls. A view is a stream
// to the station; what comes on it goes to the UI as it comes, its bytes beside the JSON (protocol.ts): `{screen}` (VT
// that makes the screen as it is, written into a terminal of its size made anew), `{out}` (what the program wrote since),
// and `{state}` whole each time it changes (its phase, whether this view types, who does, who looks, its size, its exit).
// The UI's terminal (libghostty-vt, the host's) is fed those bytes; what is typed into it, as it encodes it, goes back
// (`terminal.input`). The link dropping opens the view again on the same terminal and the station gives the screen
// anew: nothing is lost that the screen shows. `terminal.resize` is the typing view's new size; `terminal.take` opens
// it again taking it (接管).
import { Deferred, Effect, Queue } from "effect";
import type { Inner, Progress } from "./core.ts";
import { handlers } from "./core/execute.ts";
import { CoreError, asCoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { mayDrive } from "./screens.ts";
import { StationAddr } from "./station/addr.ts";
import type { TerminalAsk, WireSocket } from "./station/wire.ts";
import type { ClientId, RequestId } from "./protocol.ts";
import type { SpanContext } from "./trace.ts";
import { get, isObject, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The frames' kinds (station/src/terminals/terminals.ts `KIND`).
export const KIND = { screen: 1, out: 2, state: 3, input: 16, resize: 17 } as const;
/// A terminal's size, in cells, as the station takes it.
export const SIZE = { cols: [2, 1000], rows: [1, 500] } as const;
/// What one `input` frame carries at most (the station's MAX_IN); more is sent in several.
const INPUT_MAX = 64 * 1024;
/// A view whose stream went is opened again after these waits, one after another; then it has failed.
export const REOPEN_MS = [500, 1_000, 2_000, 4_000, 8_000, 15_000, 30_000];

export type TerminalCall =
  /// `terminal`: its id, or `new` (one opened for this view: its id comes in the first state).
  | { kind: "view"; station: string; terminal: string; view: string; ask: TerminalAsk }
  | { kind: "input"; view: string; data: Uint8Array }
  | { kind: "resize"; view: string; cols: number; rows: number }
  /// 接管: the view types from now on, taking it from whoever did.
  | { kind: "take"; view: string };

const within = (v: unknown, [lo, hi]: readonly [number, number]): v is number => typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;

function text(params: unknown, field: string): string {
  const v = get(params, field);
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
}

function size(params: unknown): { cols: number; rows: number } {
  const cols = get(params, "cols"), rows = get(params, "rows");
  if (!within(cols, SIZE.cols)) throw CoreError.invalid(t("core-misc.params.missing", { field: "cols" }));
  if (!within(rows, SIZE.rows)) throw CoreError.invalid(t("core-misc.params.missing", { field: "rows" }));
  return { cols, rows };
}

/// `bytes`: what the call carries beside its JSON (what is typed, where it is not `text`).
export function parseTerminal(name: string, params: unknown, bytes?: Uint8Array): TerminalCall | null {
  switch (name) {
    case "terminal.view": {
      const station = text(params, "station");
      StationAddr.parse(station);
      const words = (field: string) => {
        const v = get(params, field);
        return typeof v === "string" && v !== "" && v.length <= 4096 ? v : undefined;
      };
      const cwd = words("cwd"), chat = words("chat");
      return {
        kind: "view",
        station,
        terminal: text(params, "terminal"),
        view: text(params, "view"),
        ask: { ...size(params), control: get(params, "control") !== false, ...(get(params, "taken") === true ? { taken: true } : {}), ...(cwd ? { cwd } : {}), ...(chat ? { chat } : {}) },
      };
    }
    case "terminal.input": {
      const said = get(params, "text");
      const data = bytes ?? (typeof said === "string" ? utf8(said) : null);
      if (data === null || data.length === 0) throw CoreError.invalid(t("core-misc.params.missing", { field: "text" }));
      return { kind: "input", view: text(params, "view"), data };
    }
    case "terminal.resize":
      return { kind: "resize", view: text(params, "view"), ...size(params) };
    case "terminal.take":
      return { kind: "take", view: text(params, "view") };
    default:
      return null;
  }
}

/// A frame: its kind byte, its payload's length (4 bytes, big-endian), the payload.
export function frame(kind: number, payload: Uint8Array): Uint8Array {
  const out = new Uint8Array(5 + payload.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, payload.length);
  out.set(payload, 5);
  return out;
}

/// The station's frames, as its stream's pieces come.
export class FrameReader {
  #carry: Uint8Array = new Uint8Array(0);
  push(bytes: Uint8Array) {
    if (this.#carry.length === 0) this.#carry = bytes;
    else {
      const both = new Uint8Array(this.#carry.length + bytes.length);
      both.set(this.#carry);
      both.set(bytes, this.#carry.length);
      this.#carry = both;
    }
  }
  /// The next whole frame, or null till more comes.
  next(): { kind: number; payload: Uint8Array } | null {
    if (this.#carry.length < 5) return null;
    const n = new DataView(this.#carry.buffer, this.#carry.byteOffset, this.#carry.byteLength).getUint32(1);
    if (this.#carry.length < 5 + n) return null;
    const kind = this.#carry[0]!;
    const payload = this.#carry.subarray(5, 5 + n);
    this.#carry = this.#carry.subarray(5 + n);
    return { kind, payload };
  }
}

type Open = {
  station: string;
  input(data: Uint8Array): void;
  resize(cols: number, rows: number): void;
  take(): void;
};

const opened = new WeakMap<Inner, Map<string, Open>>();
const key = (client: ClientId, view: string) => `${client}\u0000${view}`;
function openIn(inner: Inner): Map<string, Open> {
  let views = opened.get(inner);
  if (!views) opened.set(inner, (views = new Map()));
  return views;
}

/// What a failure to open says the view is now: done for good (a phase), or worth trying again (null).
function verdict(error: CoreError): { phase: string; message: string } | null {
  if (error.status === 404) return { phase: error.message.startsWith("no route ") ? "outdated" : "gone", message: error.message };
  if (error.status !== undefined && error.status >= 400) return { phase: error.status === 403 ? "denied" : "failed", message: error.message };
  if (error.code === "unsupported" || error.code === "invalid_params") return { phase: "failed", message: error.message };
  return null;
}

/// The `terminals` topic: the station's terminals as it said them last (kept: there as the app opens again while it is
/// reached anew), and whether the viewer may open one and type.
export function terminalsView(inner: Inner, station: string, held: { terminals: unknown[]; outdated: boolean } | undefined): J {
  const terminals = (held?.terminals ?? []).flatMap((v) => {
    if (!isObject(v) || typeof v.id !== "string" || typeof v.by !== "string" || typeof v.cwd !== "string") return [];
    const looking = Array.isArray(v.looking) ? v.looking.filter((n: unknown): n is string => typeof n === "string") : [];
    return [{ id: v.id, by: v.by, at: typeof v.at === "number" ? v.at : 0, cwd: v.cwd, ...(typeof v.chat === "string" ? { chat: v.chat } : {}), ...(typeof v.typing === "string" ? { typing: v.typing } : {}), looking, ...("ended" in v ? { ended: true } : {}) }];
  });
  return { terminals, outdated: held?.outdated === true, open: mayDrive(inner, station), known: held !== undefined };
}

export function install(): void {
  handlers.terminal = (inner, call, progress, at, ctx) => {
    const c = (call as Extract<import("./core/calls.ts").Call, { kind: "terminal" }>).call;
    if (c.kind === "view") return view(inner, c, progress, at, ctx);
    const target = openIn(inner).get(key(at[0], c.view));
    if (!target) return Effect.fail(new CoreError("not_found", t("core-misc.terminal.closed")));
    if (c.kind === "input") target.input(c.data);
    else if (c.kind === "resize") target.resize(c.cols, c.rows);
    else target.take();
    return Effect.succeed(null);
  };
}

function view(inner: Inner, c: Extract<TerminalCall, { kind: "view" }>, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  const name = key(at[0], c.view);
  const open = openIn(inner);
  if (open.has(name)) return Effect.fail(CoreError.invalid(t("core-misc.terminal.open")));
  return Effect.gen(function* () {
    const addr = yield* Effect.try({ try: () => StationAddr.parse(c.station), catch: asCoreError });
    const station = addr.toString();
    /// What the page is told, as it is now.
    const state: J = { phase: "connecting", id: c.terminal === "new" ? "" : c.terminal, types: false, typing: null, looking: [], cols: c.ask.cols, rows: c.ask.rows };
    const tell = () => progress({ state: { ...state, looking: [...state.looking] } });
    // The terminal it is on (a new one's id once the station said it), and what it asks as it opens again.
    let id = c.terminal;
    let ask: TerminalAsk = c.ask;
    let out: Queue.Queue<Uint8Array> | null = null;
    let again: Deferred.Deferred<void> | null = null;
    const write = (bytes: Uint8Array) => {
      if (out !== null) Queue.offerUnsafe(out, bytes);
    };
    open.set(name, {
      station,
      input: (data) => {
        if (!state.types) return;
        for (let i = 0; i < data.length; i += INPUT_MAX) write(frame(KIND.input, data.subarray(i, i + INPUT_MAX)));
      },
      resize: (cols, rows) => {
        ask = { ...ask, cols, rows };
        if (state.types) write(frame(KIND.resize, utf8(JSON.stringify({ cols, rows }))));
      },
      // Opened again asking to take it; asked once (its reopens after it ask as any).
      take: () => {
        ask = { ...ask, control: true, taken: true };
        if (again !== null) Deferred.doneUnsafe(again, Effect.void);
      },
    });
    yield* Effect.addFinalizer(() => Effect.sync(() => open.delete(name)));
    tell();

    /// One stream: opened, read until it ends, is to be opened again, or fails.
    const attempt = Effect.scoped(
      Effect.gen(function* () {
        const opened = yield* Effect.result(inner.stations.requests.terminalView(addr, id, ask, ctx));
        if (opened._tag === "Failure") return { failed: opened.failure } as const;
        const socket: WireSocket = opened.success;
        // A new one is opened once: its reopens are of the terminal it made.
        if (id === "new") ask = { cols: ask.cols, rows: ask.rows, control: ask.control };
        else if (ask.taken) ask = { ...ask, taken: undefined };
        const queue = yield* Queue.unbounded<Uint8Array>();
        out = queue;
        yield* Effect.addFinalizer(() => Effect.sync(() => (out = out === queue ? null : out)));
        yield* Effect.forkScoped(Effect.ignore(Effect.forever(Effect.flatMap(Queue.take(queue), (bytes) => socket.send.write(bytes)))));
        const reopen = Deferred.makeUnsafe<void>();
        again = reopen;
        state.phase = "live";
        delete state.message;
        tell();
        const reader = new FrameReader();
        for (;;) {
          const next = yield* Effect.raceFirst(
            Effect.map(Effect.result(socket.reply.body.take), (r) => ({ r }) as const),
            Effect.as(Deferred.await(reopen), { reopen: true } as const),
          );
          if ("reopen" in next) return { reopen: true } as const;
          if (next.r._tag === "Failure" || next.r.success === null) return { dropped: true } as const;
          reader.push(next.r.success);
          for (let f = reader.next(); f !== null; f = reader.next()) {
            if (f.kind === KIND.screen) progress({ screen: true }, f.payload);
            else if (f.kind === KIND.out) progress({ out: true }, f.payload);
            else if (f.kind === KIND.state) {
              let s: J;
              try {
                s = JSON.parse(new TextDecoder().decode(f.payload));
              } catch {
                return { failed: new CoreError("garbled", t("core-misc.terminal.garbled")) } as const;
              }
              if (!isObject(s)) continue;
              if (typeof s.id === "string" && s.id !== "") id = state.id = s.id;
              state.types = s.types === true;
              state.typing = typeof s.typing === "string" ? s.typing : null;
              state.looking = Array.isArray(s.looking) ? s.looking.filter((n: unknown) => typeof n === "string") : [];
              if (within(s.cols, SIZE.cols) && within(s.rows, SIZE.rows)) [state.cols, state.rows] = [s.cols, s.rows];
              if (typeof s.cwd === "string") state.cwd = s.cwd;
              if ("ended" in s) {
                state.phase = "ended";
                state.ended = isObject(s.ended) ? { code: typeof s.ended.code === "number" ? s.ended.code : null, signal: typeof s.ended.signal === "string" ? s.ended.signal : null } : null;
              }
              tell();
            }
          }
        }
      }),
    );

    let misses = 0;
    for (;;) {
      const r = yield* attempt;
      if ("reopen" in r) continue;
      if ("dropped" in r) {
        if (state.phase === "ended") return null;
        misses = 0;
      } else {
        const v = verdict(r.failed);
        if (v !== null) {
          state.phase = v.phase;
          state.message = v.message;
          tell();
          return null;
        }
        if (misses >= REOPEN_MS.length) {
          state.phase = "failed";
          state.message = r.failed.message;
          tell();
          return null;
        }
      }
      state.phase = "reconnecting";
      tell();
      yield* Effect.sleep(REOPEN_MS[Math.min(misses, REOPEN_MS.length - 1)]!);
      misses++;
    }
  }).pipe(Effect.scoped);
}
