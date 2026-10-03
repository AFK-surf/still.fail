// Requests to a station's admin API over its wire (station/transport.rs): each a span of the trace it is made in, with
// what it is waited on as (status.ts), its write key, its language; files, uploads and previews.
import { Effect, Scope } from "effect";
import type { Inner } from "../core.ts";
import { CoreError, asCoreError } from "../error.ts";
import { current, t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { stationWhat } from "../status.ts";
import { Kind, route, type Span, type SpanContext } from "../trace.ts";
import { get, hex, isObject, parseJson, toJsonBytes } from "../util.ts";
import type { StationAddr } from "./addr.ts";
import { readAll, replyHeader, type RequestHead, type StationWire, type WireReply, type WireSocket } from "./wire.ts";

export const IDEMPOTENCY_KEY = "idempotency-key";
export const IDEMPOTENT = "stillfail-idempotent";
export const LANG_HEADER = "stillfail-lang";
export const EVENT_STREAM = "text/event-stream";
/// How long a preview's WebSocket may take to open.
export const SOCKET_OPEN_MS = 30_000;

/// A station's non-2xx answer as an error.
export function httpError(status: number, data: unknown): CoreError {
  const e = get(data, "error");
  return new CoreError(`http_${status}`, typeof e === "string" ? e : t("station.core.requestFailed", { status }), status);
}

export function failed(span: Span, error: CoreError): void {
  span.fail();
  span.set("error.type", error.code);
}

export function answered(span: Span, reply: WireReply): void {
  span.set("http.response.status_code", reply.status);
  if (reply.via) span.set("stillfail.path", reply.via);
  if (reply.status >= 500) span.fail();
}

const empty = new Uint8Array();

export class Requests {
  readonly #core: Inner;
  readonly wire: StationWire;

  constructor(core: Inner, wire: StationWire) {
    this.#core = core;
    this.wire = wire;
  }

  #status(station: StationAddr) {
    return this.#core.workspaces.ofStation(station.toString()).status;
  }

  /// A request's head and span: its `traceparent`, its language, a write's key.
  #head(station: StationAddr, method: string, path: string, headers: [string, string][], bodySize: number, ctx: SpanContext | null): [Span, RequestHead] {
    const full = `/admin/api${path}`;
    const span = this.#core.tracer.span(`${method} ${route(full)}`, Kind.Client, ctx);
    span.set("http.request.method", method);
    span.set("url.path", route(full));
    span.set("stillfail.station", station.station);
    if (bodySize > 0) span.set("http.request.body.size", bodySize);
    const h: [string, string][] = [...headers, ["traceparent", span.context.traceparent()], [LANG_HEADER, current()]];
    // A write carries a key of its own: a station that keeps writes to once does it once however often it arrives.
    const m = method.toUpperCase();
    if (m !== "GET" && m !== "HEAD" && !h.some(([k]) => k.toLowerCase() === IDEMPOTENCY_KEY)) {
      const key = new Uint8Array(16);
      this.#core.host.randomBytes(key);
      h.push([IDEMPOTENCY_KEY, hex(key)]);
    }
    return [span, { method, path: full, headers: h }];
  }

  /// One whole request: its status, its reply's head, its body. `quiet`: in the background, not said to be waited on.
  exchange(station: StationAddr, method: string, path: string, headers: [string, string][], body: Uint8Array, quiet: boolean, ctx: SpanContext | null): Effect.Effect<{ status: number; headers: [string, string][]; body: Uint8Array }, CoreError> {
    return Effect.scoped(
      Effect.gen({ self: this }, function* () {
        const status = this.#status(station);
        const waiting = quiet ? null : status.begin({ station: station.toString() }, stationWhat(method, path), false);
        const [span, head] = this.#head(station, method, path, headers, body.length, ctx);
        const result = yield* Effect.result(
          Effect.gen({ self: this }, function* () {
            const reply = yield* this.wire.request(station, head, body);
            answered(span, reply);
            const bytes = yield* readAll(reply.body, (chunk) => (waiting ? waiting.received(chunk.length) : status.received(null, chunk.length)));
            span.set("http.response.body.size", bytes.length);
            return { status: reply.status, headers: reply.headers, body: bytes };
          }).pipe(Effect.ensuring(Effect.sync(() => waiting?.end()))),
        );
        if (result._tag === "Failure") {
          failed(span, result.failure);
          span.end();
          return yield* Effect.fail(result.failure);
        }
        span.end();
        return result.success;
      }),
    );
  }

  /// A JSON request; a non-2xx answer is an error.
  call(station: StationAddr, method: string, path: string, body: unknown, options: { quiet?: boolean; ctx?: SpanContext | null } = {}): Effect.Effect<unknown, CoreError> {
    const bytes = body === undefined || body === null ? empty : toJsonBytes(body);
    const headers: [string, string][] = body === undefined || body === null ? [] : [["content-type", "application/json"]];
    return Effect.flatMap(this.exchange(station, method, path, headers, bytes, options.quiet ?? false, options.ctx ?? null), (r) => {
      // Like the web's `response.json().catch(() => ({}))`.
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      return r.status >= 200 && r.status < 300 ? Effect.succeed(data as unknown) : Effect.fail(httpError(r.status, data));
    });
  }

  /// Opens an event stream (in the caller's scope); a non-2xx answer is an error. Its span ends once it is open.
  stream(station: StationAddr, path: string, ctx: SpanContext | null): Effect.Effect<WireReply, CoreError, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const status = this.#status(station);
      const waiting = status.begin({ station: station.toString() }, stationWhat("GET", path), false);
      const [span, head] = this.#head(station, "GET", path, [["accept", EVENT_STREAM]], 0, ctx);
      span.set("stillfail.stream", true);
      const opened = yield* Effect.result(this.wire.request(station, head, empty).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))));
      if (opened._tag === "Failure") {
        failed(span, opened.failure);
        span.end();
        return yield* Effect.fail(opened.failure);
      }
      const reply = opened.success;
      answered(span, reply);
      span.end();
      if (reply.status < 200 || reply.status >= 300) {
        const bytes = yield* Effect.orElseSucceed(readAll(reply.body), () => empty);
        const data = parseJson(bytes);
        return yield* Effect.fail(httpError(reply.status, data === undefined ? {} : data));
      }
      // What comes on it is no longer waited on, only counted.
      const body = { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && status.received(null, chunk.length))) };
      return { ...reply, body };
    });
  }

  /// POST /uploads?name= with the raw bytes: the file waits on the station, in no chat, until a message sends it.
  upload(station: StationAddr, name: string, bytes: Uint8Array, ctx: SpanContext | null): Effect.Effect<unknown, CoreError> {
    return Effect.flatMap(this.exchange(station, "POST", `/uploads?name=${encode(name)}`, [["content-type", "application/octet-stream"]], bytes, false, ctx), (r) => {
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      return r.status >= 200 && r.status < 300 ? Effect.succeed(data as unknown) : Effect.fail(httpError(r.status, data));
    });
  }

  /// GET /sessions/:key/files?name=(&thumb=1): [content type, bytes]; `progress` hears the bytes so far and the whole
  /// size (when the station gives it), now and then.
  file(station: StationAddr, key: string, name: string, thumb: boolean, progress: (loaded: number, total: number | null) => void, ctx: SpanContext | null): Effect.Effect<[string, Uint8Array], CoreError> {
    return Effect.scoped(
      Effect.gen({ self: this }, function* () {
        const path = `/sessions/${encode(key)}/files?name=${encode(name)}${thumb ? "&thumb=1" : ""}`;
        const status = this.#status(station);
        const waiting = status.begin({ station: station.toString() }, stationWhat("GET", path), false);
        const [span, head] = this.#head(station, "GET", path, [], 0, ctx);
        const result = yield* Effect.result(
          Effect.gen({ self: this }, function* () {
            const reply = yield* this.wire.request(station, head, empty);
            answered(span, reply);
            if (reply.status !== 200) return yield* Effect.fail(new CoreError(`http_${reply.status}`, t("station.core.fileUnreadable"), reply.status));
            const kind = replyHeader(reply, "content-type") ?? "";
            const length = Number(replyHeader(reply, "content-length")?.trim());
            const total = Number.isInteger(length) && length >= 0 ? length : null;
            const step = total === null ? 256 * 1024 : Math.max(Math.floor(total / 100), 64 * 1024);
            progress(0, total);
            let loaded = 0;
            let told = 0;
            const bytes = yield* readAll(reply.body, (chunk) => {
              waiting.received(chunk.length);
              loaded += chunk.length;
              if (loaded - told >= step) {
                progress(loaded, total);
                told = loaded;
              }
            });
            span.set("http.response.body.size", bytes.length);
            return [kind, bytes] as [string, Uint8Array];
          }).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))),
        );
        if (result._tag === "Failure") failed(span, result.failure);
        span.end();
        if (result._tag === "Failure") return yield* Effect.fail(result.failure);
        return result.success;
      }),
    );
  }

  /// A request to a web service on the station's machine (`/preview/<port>`), passed through as it is.
  preview(station: StationAddr, port: number, method: string, path: string, headers: [string, string][], body: Uint8Array, ctx: SpanContext | null) {
    return this.exchange(station, method, `/preview/${port}${path.startsWith("/") ? path : `/${path}`}`, headers, body, false, ctx);
  }

  /// A preview request whose answer is handed on as it comes: its head once it is there, then its body (open while the
  /// caller's scope is).
  previewStream(station: StationAddr, port: number, method: string, path: string, headers: [string, string][], body: Uint8Array, ctx: SpanContext | null): Effect.Effect<WireReply, CoreError, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const full = `/preview/${port}${path.startsWith("/") ? path : `/${path}`}`;
      const status = this.#status(station);
      const waiting = status.begin({ station: station.toString() }, stationWhat(method, full), false);
      const [span, head] = this.#head(station, method, full, headers, body.length, ctx);
      span.set("stillfail.stream", true);
      const opened = yield* Effect.result(this.wire.request(station, head, body).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))));
      if (opened._tag === "Failure") {
        failed(span, opened.failure);
        span.end();
        return yield* Effect.fail(opened.failure);
      }
      answered(span, opened.success);
      span.end();
      const reply = opened.success;
      return { ...reply, body: { take: Effect.tap(reply.body.take, (c) => Effect.sync(() => c && status.received(null, c.length))) } };
    });
  }

  /// A preview page's WebSocket to `path` of the service at `port`: open once the station answers 101.
  previewSocket(station: StationAddr, port: number, path: string, headers: [string, string][], ctx: SpanContext | null): Effect.Effect<WireSocket, CoreError, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const full = `/admin/api/preview/${port}${path.startsWith("/") ? path : `/${path}`}`;
      const waiting = this.#status(station).begin({ station: station.toString() }, t("station.core.openingPreviewSocket"), false);
      const span = this.#core.tracer.span(`SOCKET ${route(full)}`, Kind.Client, ctx);
      span.set("url.path", route(full));
      span.set("stillfail.stream", true);
      const head: RequestHead = { method: "GET", path: full, headers: [...headers, ["traceparent", span.context.traceparent()], [LANG_HEADER, current()]] };
      const opening = this.wire.socket ? this.wire.socket(station, head) : Effect.fail(new CoreError("unsupported", t("station.core.previewNoSocket")));
      const opened = yield* Effect.result(
        Effect.raceFirst(
          opening,
          Effect.sleep(SOCKET_OPEN_MS).pipe(Effect.andThen(Effect.fail(new CoreError("timeout", t("station.core.previewSocketTimeout"))))),
        ).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))),
      );
      if (opened._tag === "Failure") {
        failed(span, opened.failure);
        span.end();
        return yield* Effect.fail(opened.failure);
      }
      const socket = opened.success;
      answered(span, socket.reply);
      span.end();
      if (socket.reply.status !== 101) {
        const bytes = yield* Effect.orElseSucceed(readAll(socket.reply.body), () => empty);
        const data = parseJson(bytes);
        return yield* Effect.fail(httpError(socket.reply.status, data === undefined ? {} : data));
      }
      return socket;
    });
  }
}

export { asCoreError, isObject, Scope };
