// A chat's Farview tab drawn by the app itself (station/src/browser/module.ts, the `farview` stream): the station
// carries the stream to the tab's host as it is, bytes both ways, Farview's own protocol (its farview/client package
// reads it and draws). `farview.view` holds the stream and gives the app what comes, its bytes beside the JSON
// (`{data}`), and `{state}` as it changes: `live` with how many times it opened (each open is a new conversation
// with the host: the app's session made anew, its Hello said again), `reconnecting`, or what ended it. What the app
// says goes by `farview.send`, its bytes beside the call. A stream that drops is opened again as a terminal's is.
import { Effect, Queue } from "effect";
import type { Inner, Progress } from "./core.ts";
import { handlers } from "./core/execute.ts";
import { CoreError, asCoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { StationAddr } from "./station/addr.ts";
import type { WireSocket } from "./station/wire.ts";
import type { ClientId, RequestId } from "./protocol.ts";
import { REOPEN_MS } from "./terminals.ts";
import type { SpanContext } from "./trace.ts";
import { get } from "./util.ts";

export type FarviewCall =
  /// `screen`: the tab's screen id as the screens' list has it (`browser:fv_…`, one listed with `farview`).
  | { kind: "view"; station: string; screen: string; view: string }
  | { kind: "send"; view: string; data: Uint8Array };

function text(params: unknown, field: string): string {
  const v = get(params, field);
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
  return v;
}

/// `bytes`: what `farview.send` carries beside its JSON.
export function parseFarview(name: string, params: unknown, bytes?: Uint8Array): FarviewCall | null {
  switch (name) {
    case "farview.view": {
      const station = text(params, "station");
      StationAddr.parse(station);
      return { kind: "view", station, screen: text(params, "screen"), view: text(params, "view") };
    }
    case "farview.send":
      if (bytes === undefined || bytes.length === 0) throw CoreError.invalid(t("core-misc.params.missing", { field: "bytes" }));
      return { kind: "send", view: text(params, "view"), data: bytes };
    default:
      return null;
  }
}

const opened = new WeakMap<Inner, Map<string, (data: Uint8Array) => void>>();
const key = (client: ClientId, view: string) => `${client}\u0000${view}`;
function openIn(inner: Inner): Map<string, (data: Uint8Array) => void> {
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

export function install(): void {
  handlers.farview = (inner, call, progress, at, ctx) => {
    const c = (call as Extract<import("./core/calls.ts").Call, { kind: "farview" }>).call;
    if (c.kind === "view") return view(inner, c, progress, at, ctx);
    const send = openIn(inner).get(key(at[0], c.view));
    if (!send) return Effect.fail(new CoreError("not_found", t("core-misc.farview.closed")));
    send(c.data);
    return Effect.succeed(null);
  };
}

function view(inner: Inner, c: Extract<FarviewCall, { kind: "view" }>, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<unknown, CoreError> {
  const name = key(at[0], c.view);
  const open = openIn(inner);
  if (open.has(name)) return Effect.fail(CoreError.invalid(t("core-misc.farview.open")));
  return Effect.gen(function* () {
    const addr = yield* Effect.try({ try: () => StationAddr.parse(c.station), catch: asCoreError });
    let out: Queue.Queue<Uint8Array> | null = null;
    // What is said while no stream is open belongs to a conversation gone: the next open begins anew.
    open.set(name, (data) => {
      if (out !== null) Queue.offerUnsafe(out, data);
    });
    yield* Effect.addFinalizer(() => Effect.sync(() => open.delete(name)));
    progress({ state: { phase: "connecting" } });
    let opens = 0;

    /// One stream: opened, read until it ends, or failed.
    const attempt = Effect.scoped(
      Effect.gen(function* () {
        const got = yield* Effect.result(inner.stations.requests.farviewView(addr, c.screen, ctx));
        if (got._tag === "Failure") return { failed: got.failure } as const;
        const socket: WireSocket = got.success;
        const queue = yield* Queue.unbounded<Uint8Array>();
        out = queue;
        yield* Effect.addFinalizer(() => Effect.sync(() => (out = out === queue ? null : out)));
        const drain: Effect.Effect<void, CoreError> = Effect.suspend(() => Effect.flatMap(Queue.take(queue), (bytes) => Effect.andThen(socket.send.write(bytes), drain)));
        yield* Effect.forkScoped(Effect.ignore(drain));
        opens++;
        progress({ state: { phase: "live", opens } });
        for (;;) {
          const next = yield* Effect.result(socket.reply.body.take);
          if (next._tag === "Failure" || next.success === null) return { dropped: true } as const;
          progress({ data: true }, next.success);
        }
      }),
    );

    let misses = 0;
    for (;;) {
      const r = yield* attempt;
      if ("dropped" in r) misses = 0;
      else {
        const v = verdict(r.failed);
        if (v !== null) {
          progress({ state: v });
          return null;
        }
        if (misses >= REOPEN_MS.length) {
          progress({ state: { phase: "failed", message: r.failed.message } });
          return null;
        }
      }
      progress({ state: { phase: "reconnecting" } });
      yield* Effect.sleep(REOPEN_MS[Math.min(misses, REOPEN_MS.length - 1)]!);
      misses++;
    }
  }).pipe(Effect.scoped);
}

