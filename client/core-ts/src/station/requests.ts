// Requests to a station's admin API over its wire (station/transport.rs): each a span of the trace it is made in, with
// what it is waited on as (status.ts), its write key, its language; files, uploads and previews.
import { Effect, Scope } from "effect";
import { Decompress } from "fzstd";
import type { Inner } from "../core.ts";
import { CoreError, HostError, asCoreError } from "../error.ts";
import type { Pull } from "../host.ts";
import { current, t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { stationWhat } from "../status.ts";
import { Kind, route, type Span, type SpanContext } from "../trace.ts";
import { get, hex, isObject, parseJson, toJsonBytes } from "../util.ts";
import type { StationAddr } from "./addr.ts";
import { concat, readAll, replyHeader, type RequestHead, type StationWire, type WireReply, type WireSocket } from "./wire.ts";

export const IDEMPOTENCY_KEY = "idempotency-key";
/// A request that only reads though it is no GET (POST /changed/<list>, what is held in its body): asked again on
/// another way as a GET is (mesh.ts `mayRepeat`).
export const READS = "stillfail-reads";
export const IDEMPOTENT = "stillfail-idempotent";
export const LANG_HEADER = "stillfail-lang";
export const EVENT_STREAM = "text/event-stream";
/// An events stream's answer when the station told first what came after the `since` it was asked (station/src/api/
/// events.ts RESUMED): nothing is read again.
export const RESUMED = "stillfail-resumed";
/// What every request asks its answer compressed as (`accept-encoding`), but a preview's (its page reads what the service
/// sent): zstd, an event stream flushed after each event and compressed against the last megabyte of it (station/src/mesh/
/// compress.ts). On a slow link the bytes are the wait: JSON goes to a fifth or less, an events stream to a tenth. A
/// station from before sends every answer as it is.
export const ZSTD = "zstd";
/// The most a station from before uploads in parts takes in one (station/src/api/routes/hub.ts MAX_UPLOAD).
export const UPLOAD_WHOLE_MAX = 50 * 1024 * 1024;
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
  if (reply.relay) span.set("stillfail.via", reply.relay);
  if (reply.status >= 500) span.fail();
}

const empty = new Uint8Array();

/// A reply's body as the station wrote it: decompressed as it comes when it came compressed (fzstd, the same on every
/// host), each piece as soon as it is whole (an event stream's, event by event).
function plain(reply: WireReply): Pull<Uint8Array> {
  if (replyHeader(reply, "content-encoding") !== ZSTD) return reply.body;
  const out: Uint8Array[] = [];
  const decompress = new Decompress((data) => {
    if (data.length > 0) out.push(data);
  });
  let ended = false;
  const take: Effect.Effect<Uint8Array | null, HostError> = Effect.gen(function* () {
    for (;;) {
      if (out.length > 0) return out.length === 1 ? out.shift()! : concat(out.splice(0));
      if (ended) return null;
      const chunk = yield* reply.body.take;
      ended = chunk === null;
      try {
        decompress.push(chunk ?? empty, ended);
      } catch (error) {
        // Cut off short of its end (a stream let go of): what came is all there is.
        if (ended) continue;
        return yield* Effect.fail(new HostError(t("core-logic.mesh.read_failed", { error: (error as Error).message })));
      }
    }
  });
  return { take };
}

/// A station's answer to a path it has no route for (`no route GET /…`): a station from before that route.
function isNoRoute(body: Uint8Array): boolean {
  const e = get(parseJson(body), "error");
  return typeof e === "string" && e.startsWith("no route ");
}

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
    if (!path.startsWith("/preview/") && !headers.some(([k]) => k.toLowerCase() === "accept-encoding")) h.push(["accept-encoding", ZSTD]);
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
            // What came over the link is counted (and said in the span); what it says, decompressed.
            let came = 0;
            const counted = { ...reply, body: { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && ((came += chunk.length), waiting ? waiting.received(chunk.length) : status.received(null, chunk.length)))) } };
            const bytes = yield* readAll(plain(counted));
            span.set("http.response.body.size", came);
            if (came !== bytes.length) span.set("stillfail.body.decompressed", bytes.length);
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
  call(station: StationAddr, method: string, path: string, body: unknown, options: { quiet?: boolean; ctx?: SpanContext | null; headers?: [string, string][] } = {}): Effect.Effect<unknown, CoreError> {
    const bytes = body === undefined || body === null ? empty : toJsonBytes(body);
    const headers: [string, string][] = body === undefined || body === null ? [] : [["content-type", "application/json"]];
    if (options.headers) headers.push(...options.headers);
    return Effect.flatMap(this.exchange(station, method, path, headers, bytes, options.quiet ?? false, options.ctx ?? null), (r) => {
      // Like the web's `response.json().catch(() => ({}))`.
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      return r.status >= 200 && r.status < 300 ? Effect.succeed(data as unknown) : Effect.fail(httpError(r.status, data));
    });
  }

  /// Several reads in one request (POST /batch `{ gets }`): each one's status and answer, in their order, compressed as
  /// one. A station from before batches has no such route (`no route …`).
  batch(station: StationAddr, gets: string[], ctx: SpanContext | null): Effect.Effect<{ status: number; body: unknown }[], CoreError> {
    return Effect.flatMap(this.call(station, "POST", "/batch", { gets }, { quiet: true, ctx, headers: [[READS, "1"]] }), (answer) => {
      const answers = get(answer, "answers");
      if (!Array.isArray(answers) || answers.length !== gets.length) return Effect.fail(new CoreError("bad_response", t("station.core.badBatch")));
      return Effect.succeed(answers.map((a) => ({ status: typeof get(a, "status") === "number" ? (get(a, "status") as number) : 500, body: get(a, "body") })));
    });
  }

  /// Opens an event stream (in the caller's scope); a non-2xx answer is an error. Its span ends once it is open.
  stream(station: StationAddr, path: string, ctx: SpanContext | null): Effect.Effect<WireReply & { came?: { bytes: number } }, CoreError, Scope.Scope> {
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
        const bytes = yield* Effect.orElseSucceed(readAll(plain(reply)), () => empty);
        const data = parseJson(bytes);
        return yield* Effect.fail(httpError(reply.status, data === undefined ? {} : data));
      }
      // What comes on it is no longer waited on, only counted (as it came over the link: `came`), and decompressed.
      const came = { bytes: 0 };
      const body = { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && (status.received(null, chunk.length), (came.bytes += chunk.length)))) };
      return { ...reply, body: plain({ ...reply, body }), came };
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

  /// POST /uploads/parts?id=&name=&size=&offset= with a part's bytes: `{ have }`, how much of the file the station has
  /// (the next part starts there), and `file` once it is whole. A broken connection is the wire's to ask again over
  /// (the same key, the same offset). A station from before parts (it does not know the route) gets the file whole in
  /// one upload once all of it is here, as long as that takes it (UPLOAD_WHOLE_MAX).
  uploadPart(station: StationAddr, q: { id: string; name: string; size: number; offset: number }, bytes: Uint8Array, ctx: SpanContext | null): Effect.Effect<{ have: number; file?: unknown }, CoreError> {
    const path = `/uploads/parts?id=${encode(q.id)}&name=${encode(q.name)}&size=${q.size}&offset=${q.offset}`;
    return Effect.flatMap(this.exchange(station, "POST", path, [["content-type", "application/octet-stream"]], bytes, false, ctx), (r) => {
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      if (r.status === 404 || r.status === 405) return this.#wholeUpload(station, q, bytes, ctx);
      if (r.status < 200 || r.status >= 300) return Effect.fail(httpError(r.status, data));
      const have = get(data, "have");
      const file = get(data, "file");
      return Effect.succeed({ have: typeof have === "number" ? have : q.offset + bytes.length, ...(file !== undefined ? { file } : {}) });
    });
  }

  /// Parts kept here for a station from before parts, by station and id, until the file is whole.
  readonly #wholes = new Map<string, { parts: Uint8Array[]; have: number }>();

  #wholeUpload(station: StationAddr, q: { id: string; name: string; size: number; offset: number }, bytes: Uint8Array, ctx: SpanContext | null): Effect.Effect<{ have: number; file?: unknown }, CoreError> {
    if (q.size > UPLOAD_WHOLE_MAX) return Effect.fail(new CoreError("http_413", t("station.core.uploadOldStation"), 413));
    const key = `${station.toString()}\0${q.id}`;
    let held = this.#wholes.get(key);
    if (held === undefined || q.offset === 0) this.#wholes.set(key, (held = { parts: [], have: 0 }));
    if (q.offset !== held.have) return Effect.succeed({ have: held.have });
    held.parts.push(bytes);
    held.have += bytes.length;
    if (held.have < q.size) return Effect.succeed({ have: held.have });
    const whole = new Uint8Array(held.have);
    let at = 0;
    for (const part of held.parts) {
      whole.set(part, at);
      at += part.length;
    }
    this.#wholes.delete(key);
    return Effect.map(this.upload(station, q.name, whole, ctx), (file) => ({ have: q.size, file }));
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
            const counted = { ...reply, body: { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && waiting.received(chunk.length))) } };
            const bytes = yield* readAll(plain(counted), (chunk) => {
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

  /// GET /sessions/:key/parts?name=&offset=&length=: a part of a file and its whole size, for a big one fetched a part at
  /// a time (onto the disk) rather than whole. `unsupported` from a station from before parts (it has no such route).
  filePart(station: StationAddr, key: string, name: string, offset: number, length: number, ctx: SpanContext | null): Effect.Effect<{ type: string; total: number; bytes: Uint8Array }, CoreError> {
    const path = `/sessions/${encode(key)}/parts?name=${encode(name)}&offset=${offset}&length=${length}`;
    return Effect.flatMap(this.exchange(station, "GET", path, [], empty, false, ctx), (r) => {
      if (r.status === 404 && isNoRoute(r.body)) return Effect.fail(new CoreError("unsupported", t("station.core.fileOldStation"), 404));
      if (r.status !== 200) {
        const data = parseJson(r.body);
        return Effect.fail(r.status === 404 ? new CoreError("http_404", t("station.core.fileUnreadable"), 404) : httpError(r.status, data === undefined ? {} : data));
      }
      const header = (name: string) => r.headers.find(([k]) => k.toLowerCase() === name)?.[1];
      const total = Number(header("stillfail-total"));
      return Effect.succeed({ type: header("content-type") ?? "", total: Number.isSafeInteger(total) ? total : offset + r.body.length, bytes: r.body });
    });
  }

  /// GET /sessions/:key/poster?name=: a video's poster (a JPEG), or null when the station has none (it cannot make one,
  /// or is from before posters).
  poster(station: StationAddr, key: string, name: string, ctx: SpanContext | null): Effect.Effect<Uint8Array | null, CoreError> {
    const path = `/sessions/${encode(key)}/poster?name=${encode(name)}`;
    return Effect.flatMap(this.exchange(station, "GET", path, [], empty, true, ctx), (r) => {
      if (r.status === 200) return Effect.succeed(r.body);
      if (r.status === 404) return Effect.succeed(null);
      const data = parseJson(r.body);
      return Effect.fail(httpError(r.status, data === undefined ? {} : data));
    });
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
