// The station calls (core/execute.rs, the station's part): operations, a chat's pages and place, what is read,
// files, uploads and previews.
import { Deferred, Effect, Scope } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { base64 } from "../util.ts";
import { StationAddr } from "./addr.ts";
import { readAll, replyHeader, takeFrames, encodeFrame, type Frame } from "./wire.ts";

const parse = (station: string) => Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });

/// Preview sockets open, by client and the name its UI gave each: where `preview.socket.send` puts the page's messages.
const sockets = new Map<string, (frame: Frame) => void>();

export function install(): void {
  handlers.op = (inner, call, _progress, _at, ctx) => {
    const c = call as Extract<Call, { kind: "op" }>;
    return Effect.andThen(parse((c.op.target as { station: string }).station), inner.stations.perform(c.op, ctx));
  };
  handlers.chatOlder = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatOlder" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.older(c.station, c.thread), (more) => ({ more })));
  };
  handlers.chatNewer = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatNewer" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.newer(c.station, c.thread), (more) => ({ more })));
  };
  handlers.chatLatest = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatLatest" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stationTopics.latest(c.station, c.thread), null));
  };
  handlers.chatPlace = (inner, call) => {
    const c = call as Extract<Call, { kind: "chatPlace" }>;
    inner.stationTopics.place(c.station, c.thread, c.seq, c.offset);
    return Effect.succeed(null);
  };
  handlers.historyOlder = (inner, call) => {
    const c = call as Extract<Call, { kind: "historyOlder" }>;
    return Effect.andThen(parse(c.station), Effect.map(inner.stationTopics.historyOlder(c.station, c.key), (more) => ({ more })));
  };
  handlers.chatRead = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "chatRead" }>;
    return Effect.andThen(parse(c.station), Effect.as(inner.stations.read(c.station, c.thread, c.seq, ctx), null));
  };
  handlers.stationMeasure = (inner, call) => {
    const c = call as Extract<Call, { kind: "stationMeasure" }>;
    return Effect.flatMap(parse(c.station), (addr) => Effect.as(inner.stations.wire.measure ? inner.stations.wire.measure(addr) : Effect.fail(new CoreError("unsupported", t("station.core.oneWay"))), null));
  };
  handlers.stationUpload = (inner, call, _p, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationUpload" }>;
    return inner.stations.upload(c.station, c.name, c.bytes, ctx);
  };
  handlers.stationFile = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationFile" }>;
    return Effect.flatMap(parse(c.station), (addr) =>
      Effect.map(
        inner.stations.requests.file(addr, c.key, c.name, c.thumb, (loaded, total) => c.progress && progress({ loaded, total }), ctx),
        ([type, bytes]) => ({ type, bytes: base64(bytes) }),
      ),
    );
  };
  handlers.stationPreview = (inner, call, progress, _a, ctx) => {
    const c = call as Extract<Call, { kind: "stationPreview" }>;
    return Effect.flatMap(parse(c.station), (addr) => {
      if (!c.stream) return Effect.map(inner.stations.requests.preview(addr, c.port, c.method, c.path, c.headers, c.body, ctx), (r) => ({ status: r.status, headers: r.headers, body: base64(r.body) }));
      // As it comes: its head, then each piece of its body; null at its end. Cancelling the call stops it.
      return Effect.scoped(
        Effect.gen(function* () {
          const reply = yield* inner.stations.requests.previewStream(addr, c.port, c.method, c.path, c.headers, c.body, ctx);
          progress({ head: { status: reply.status, headers: reply.headers } });
          for (;;) {
            const chunk = yield* Effect.mapError(reply.body.take, asCoreError);
            if (chunk === null) return null;
            progress({ chunk: base64(chunk) });
          }
        }),
      );
    });
  };
  handlers.previewSocket = (inner, call, progress, at, ctx) => {
    const c = call as Extract<Call, { kind: "previewSocket" }>;
    const name = `${at[0]}\u0000${c.socket}`;
    if (sockets.has(name)) return Effect.fail(CoreError.invalid(t("core-misc.call.socket_open")));
    return Effect.scoped(
      Effect.gen(function* () {
        // Named before it opens: what the page sends meanwhile waits, and goes once it is open.
        const held: Frame[] = [];
        let send: ((frame: Frame) => void) | null = null;
        let closing: [number, string] | null = null;
        // The page's close before it opened: the open is let go (an older station takes the socket for a request and
        // never answers).
        const closedFirst = Deferred.makeUnsafe<[number, string]>();
        sockets.set(name, (frame) => {
          if (send) return send(frame);
          if ("close" in frame) Deferred.doneUnsafe(closedFirst, Effect.succeed(frame.close));
          else held.push(frame);
        });
        yield* Effect.addFinalizer(() => Effect.sync(() => sockets.delete(name)));
        const addr = yield* parse(c.station);
        const opened = yield* Effect.raceFirst(
          Effect.map(inner.stations.requests.previewSocket(addr, c.port, c.path, c.headers, ctx), (socket) => ({ socket }) as const),
          Effect.map(Deferred.await(closedFirst), (close) => ({ close }) as const),
        );
        if ("close" in opened) return { code: opened.close[0], reason: opened.close[1] };
        const socket = opened.socket;
        progress({ open: { protocol: replyHeader(socket.reply, "sec-websocket-protocol") ?? "" } });
        const out = socket.send;
        send = (frame) => {
          if ("close" in frame) closing = frame.close;
          inner.runner.fork(Effect.ignore(out.write(encodeFrame(frame))));
        };
        for (const f of held.splice(0)) send(f);
        let buf: Uint8Array = new Uint8Array();
        for (;;) {
          const chunk = yield* Effect.result(Effect.mapError(socket.reply.body.take, asCoreError));
          if (chunk._tag === "Failure" || chunk.success === null) {
            const [code, reason] = closing ?? [1006, ""];
            return { code, reason };
          }
          const joined = new Uint8Array(buf.length + chunk.success.length);
          joined.set(buf);
          joined.set(chunk.success, buf.length);
          const [frames, rest] = takeFrames(joined);
          buf = rest;
          for (const frame of frames) {
            if ("text" in frame) progress({ text: frame.text });
            else if ("binary" in frame) progress({ binary: base64(frame.binary) });
            else return { code: frame.close[0], reason: frame.close[1] };
          }
        }
      }),
    );
  };
  handlers.previewSocketSend = (_inner, call, _p, at) => {
    const c = call as Extract<Call, { kind: "previewSocketSend" }>;
    const send = sockets.get(`${at[0]}\u0000${c.socket}`);
    if (!send) return Effect.fail(new CoreError("not_found", t("core-misc.call.socket_closed")));
    send(c.frame as Frame);
    return Effect.succeed(null);
  };
}

export { readAll, Scope };
export type { Inner };
