// Requests to a station's admin API over its wire (station/transport.rs): each a span of the trace it is made in, with
// what it is waited on as (status.ts), its write key, its language; files, uploads and previews.
import { RUNTIMES } from "../format.ts";
import { Effect, Scope } from "effect";
import { Decompress } from "fzstd";
import type { Inner } from "../core.ts";
import { CoreError, HostError, asCoreError, failedIn } from "../error.ts";
import { FileSource } from "../file-source.ts";
import type { Host, Pull, Unzstd } from "../host.ts";
import { current, t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { stationWhat } from "../status.ts";
import { Kind, route, type Span, type SpanContext } from "../trace.ts";
import { fromBase64, get, hex, isObject, parseJson, toJsonBytes } from "../util.ts";
import type { StationAddr } from "./addr.ts";
import { concat, readAll, replyHeader, type RequestHead, type ScreenAsk, type StationWire, type WireReply, type WireSocket } from "./wire.ts";
import { timed } from "../spent.ts";

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
/// A stream's answer when it follows the sessions at work itself (api/events.ts FOLLOWS): `running`.
export const FOLLOWS = "stillfail-follows";
/// What every request asks its answer compressed as (`accept-encoding`), but a preview's (its page reads what the service
/// sent): zstd, an event stream flushed after each event and compressed against the last megabyte of it (station/src/mesh/
/// compress.ts). On a slow link the bytes are the wait: JSON goes to a fifth or less, an events stream to a tenth. A
/// station from before sends every answer as it is.
export const ZSTD = "zstd";
/// The most a station from before uploads in parts takes in one (station/src/api/routes/hub.ts MAX_UPLOAD).
export const UPLOAD_WHOLE_MAX = 50 * 1024 * 1024;
/// How long a preview's WebSocket may take to open.
export const SOCKET_OPEN_MS = 30_000;
/// JSON reads may be slow, but cannot own a scheduler slot forever without receiving bytes.
export const JSON_IDLE_MS = 60_000;
const within = <A, E, R>(work: Effect.Effect<A, E, R>, ms: number) => ms > 0
  ? Effect.timeoutOrElse(work, { duration: ms, orElse: () => Effect.fail(new CoreError("timeout", t("core-logic.mesh.timed_out"))) })
  : work;

/// A station's non-2xx answer as an error.
/// A station's refusal: its `code` where it says one (the vault's, `vault_needs_lock`…), else `http_<status>`.
export function httpError(status: number, data: unknown): CoreError {
  const e = get(data, "error");
  const code = get(data, "code");
  return new CoreError(typeof code === "string" && /^[a-z][a-z0-9_]*$/.test(code) ? code : `http_${status}`, typeof e === "string" ? e : t("station.core.requestFailed", { status }), status);
}

export const failed = failedIn;

export function answered(span: Span, reply: WireReply): void {
  span.set("http.response.status_code", reply.status);
  if (reply.via) span.set("stillfail.path", reply.via);
  if (reply.relay) span.set("stillfail.via", reply.relay);
  if (reply.status >= 500) span.fail();
}

const empty = new Uint8Array();
/// How often a part on its way says how much of it has come (a part is 4 MB).
const PART_STEP = 64 * 1024;

/// A reply's body as the station wrote it: decompressed as it comes when it came compressed, each piece as soon as it
/// is whole (an event stream's, event by event); by the host where it has a way of its own (a native app's shell:
/// Host.unzstd, for as long as the scope is open), else here (fzstd, the same on every host).
function plain(host: Host, reply: WireReply, partial = true): Effect.Effect<Pull<Uint8Array>, never, Scope.Scope> {
  if (replyHeader(reply, "content-encoding") !== ZSTD) return Effect.succeed(reply.body);
  if (!host.unzstd) return Effect.succeed(plainHere(reply, partial));
  // (a shell from before it: here)
  return Effect.orElseSucceed(
    Effect.map(host.unzstd(), (z) => plainBy(z, reply, partial)),
    () => plainHere(reply, partial),
  );
}

/// What the station wrote, taken apart here (fzstd).
function plainHere(reply: WireReply, partial: boolean): Pull<Uint8Array> {
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
        // Live streams can end between flushed blocks; a finite JSON reply must end its frame.
        if (ended && partial) continue;
        return yield* Effect.fail(new HostError(t("core-logic.mesh.read_failed", { error: (error as Error).message })));
      }
    }
  });
  return { take };
}

/// What the station wrote, taken apart by the host (`z`), a piece at a time as it comes.
function plainBy(z: Unzstd, reply: WireReply, partial: boolean): Pull<Uint8Array> {
  let ended = false;
  let whole = true;
  const take: Effect.Effect<Uint8Array | null, HostError> = Effect.gen(function* () {
    for (;;) {
      if (ended) return null;
      const chunk = yield* reply.body.take;
      if (chunk === null) {
        ended = true;
        // Live streams can end between flushed blocks; a finite JSON reply must end its frame.
        if (!whole && !partial) return yield* Effect.fail(new HostError(t("core-logic.mesh.cut")));
        return null;
      }
      if (chunk.length === 0) continue;
      const made = yield* z.push(chunk);
      whole = made.whole;
      if (made.bytes.length > 0) return made.bytes;
    }
  });
  return { take };
}

/// A reply head's header `name` (lower case), if it has it.
function headerOf(headers: [string, string][], name: string): string | undefined {
  return headers.find(([k]) => k.toLowerCase() === name)?.[1];
}

/// A station's answer to a path it has no route for (`no route GET /…`): a station from before that route.
function isNoRoute(body: Uint8Array): boolean {
  const e = get(parseJson(body), "error");
  return typeof e === "string" && e.startsWith("no route ");
}

/// The most of a file read whole here to name its content (where its host does not name it: the web's, the desktop's),
/// read a part at a time as it goes up.
const NAMED_MAX = 64 * 1024 * 1024;
const NAMED_PART = 4 * 1024 * 1024;

export class Requests {
  readonly #core: Inner;
  readonly wire: StationWire;
  /// Told of a station that answered a request whole and well (2xx): it is reached, whatever its stream found.
  onAnswered: (station: StationAddr) => void = () => {};

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
    if (!path.startsWith("/preview/")) h.push(["stillfail-runtimes", RUNTIMES.join(",")]);
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
  /// `heard`: how much of the body has come, now and then as it comes (every PART_STEP); `wrote`: how much of what is
  /// sent has gone, as it goes (a wire that sends it whole says nothing); `sink`: a 2xx answer's body handed over as it
  /// comes, in pieces of PART_STEP (the last smaller), not kept (the body given is empty); `onHead`: the reply's status
  /// and head as they come, before its body. `json`: validate finite compression/JSON and bound each idle wait.
  exchange(station: StationAddr, method: string, path: string, headers: [string, string][], body: Uint8Array, quiet: boolean, ctx: SpanContext | null, heard?: (loaded: number) => void, wrote?: (sent: number) => void, sink?: (piece: Uint8Array) => void, onHead?: (status: number, headers: [string, string][]) => void, json = false): Effect.Effect<{ status: number; headers: [string, string][]; body: Uint8Array; json?: unknown }, CoreError> {
    const idleMs = json ? JSON_IDLE_MS : 0;
    return Effect.scoped(
      Effect.gen({ self: this }, function* () {
        const status = this.#status(station);
        const waiting = quiet ? null : status.begin({ station: station.toString() }, stationWhat(method, path), false);
        const [span, head] = this.#head(station, method, path, headers, body.length, ctx);
        const result = yield* Effect.result(
          Effect.gen({ self: this }, function* () {
            const reply = yield* within(this.wire.request(station, head, body, wrote), idleMs);
            answered(span, reply);
            onHead?.(reply.status, reply.headers);
            // What came over the link is counted (and said in the span); what it says, decompressed.
            let came = 0;
            const counted = { ...reply, body: { take: Effect.tap(within(reply.body.take, idleMs), (chunk) => Effect.sync(() => chunk && ((came += chunk.length), waiting ? waiting.received(chunk.length) : status.received(null, chunk.length)))) } };
            let loaded = 0;
            let told = 0;
            // An error's body is read as any other's: what it says is the error.
            const give = reply.status >= 200 && reply.status < 300 ? sink : undefined;
            const held: Uint8Array[] = [];
            let heldBytes = 0;
            const hand = () => {
              if (heldBytes > 0) give?.(held.length === 1 ? held.pop()! : concat(held.splice(0)));
              held.length = 0;
              heldBytes = 0;
            };
            const bytes = yield* readAll(yield* plain(this.#core.host, counted, !json), (chunk) => {
              loaded += chunk.length;
              if (heard && loaded - told >= PART_STEP) heard((told = loaded));
              if (give) {
                held.push(chunk);
                if ((heldBytes += chunk.length) >= PART_STEP) hand();
              }
            }, give === undefined);
            hand();
            span.set("http.response.body.size", came);
            if (came !== loaded) span.set("stillfail.body.decompressed", loaded);
            const parsed = json ? timed("reply.parse", () => parseJson(bytes)) : undefined;
            if (json && parsed === undefined && reply.status >= 200 && reply.status < 300 && reply.status !== 204 && reply.status !== 205) {
              return yield* Effect.fail(new CoreError("bad_response", t("station.core.invalidReply")));
            }
            if (reply.status >= 200 && reply.status < 300) this.onAnswered(station);
            return { status: reply.status, headers: reply.headers, body: bytes, ...(json ? { json: parsed } : {}) };
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
    return Effect.flatMap(this.exchange(station, method, path, headers, bytes, options.quiet ?? false, options.ctx ?? null, undefined, undefined, undefined, undefined, true), (r) => {
      // Parsed inside the exchange: invalid JSON also fails its request span.
      const data = r.json === undefined ? {} : r.json;
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
        const bytes = yield* Effect.orElseSucceed(readAll(yield* plain(this.#core.host, reply)), () => empty);
        const data = parseJson(bytes);
        return yield* Effect.fail(httpError(reply.status, data === undefined ? {} : data));
      }
      // What comes on it is no longer waited on, only counted (as it came over the link: `came`), and decompressed.
      const came = { bytes: 0 };
      const body = { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && (status.received(null, chunk.length), (came.bytes += chunk.length)))) };
      return { ...reply, body: yield* plain(this.#core.host, { ...reply, body }), came };
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
  /// one upload once all of it is here, as long as that takes it (UPLOAD_WHOLE_MAX). `wrote`: the part's bytes gone so
  /// far, as they go.
  uploadPart(station: StationAddr, q: { id: string; name: string; size: number; offset: number; sha256?: string }, bytes: Uint8Array, ctx: SpanContext | null, wrote?: (sent: number) => void): Effect.Effect<{ have: number; file?: unknown }, CoreError> {
    const path = `/uploads/parts?id=${encode(q.id)}&name=${encode(q.name)}&size=${q.size}&offset=${q.offset}${q.sha256 ? `&sha256=${q.sha256}` : ""}`;
    return Effect.flatMap(this.exchange(station, "POST", path, [["content-type", "application/octet-stream"]], bytes, false, ctx, undefined, wrote), (r) => {
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      if (r.status === 404 || r.status === 405) return this.#wholeUpload(station, q, bytes, ctx);
      if (r.status < 200 || r.status >= 300) return Effect.fail(httpError(r.status, data));
      const have = get(data, "have");
      const file = get(data, "file");
      return Effect.succeed({ have: typeof have === "number" ? have : q.offset + bytes.length, ...(file !== undefined ? { file } : {}) });
    });
  }

  /// A file's content named (SHA-256, hex) before it goes up, so a station that has it already (sent before) copies its
  /// own and nothing goes: its host's name for it where it has one (a phone's), else read whole and named here when it is
  /// small enough and this can (crypto.subtle: not in Hermes). Null when it cannot be, or failed.
  async uploadName(blob: Blob | FileSource, size: number): Promise<string | null> {
    try {
      if (blob instanceof FileSource && blob.hash) return await blob.hash();
      const subtle = (globalThis as { crypto?: { subtle?: SubtleCrypto } }).crypto?.subtle;
      if (!subtle || size > NAMED_MAX) return null;
      const parts = await Promise.all(Array.from({ length: Math.ceil(size / NAMED_PART) }, (_, i) => blob.slice(i * NAMED_PART, Math.min(size, (i + 1) * NAMED_PART)).arrayBuffer()));
      const whole = new Uint8Array(size);
      let at = 0;
      for (const p of parts) { whole.set(new Uint8Array(p), at); at += p.byteLength; }
      return hex(new Uint8Array(await subtle.digest("SHA-256", whole)));
    } catch {
      return null;
    }
  }

  /// Before an upload's first part, what the file is (its content's SHA-256), with no bytes: a station that has it
  /// already (sent before) copies its own and answers the file; one that does not, or one from before this, does not.
  uploadHave(station: StationAddr, q: { id: string; name: string; size: number; sha256: string }, ctx: SpanContext | null): Effect.Effect<unknown | null, CoreError> {
    return Effect.map(this.uploadPart(station, { ...q, offset: 0 }, new Uint8Array(0), ctx), (told) => told.file ?? null);
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
            // (its size not said, every 64 KB too: a chat's picture is a few hundred KB, and 256 KB showed 0 B until it came)
            const step = total === null ? 64 * 1024 : Math.max(Math.floor(total / 100), 64 * 1024);
            progress(0, total);
            let loaded = 0;
            let told = 0;
            const counted = { ...reply, body: { take: Effect.tap(reply.body.take, (chunk) => Effect.sync(() => chunk && waiting.received(chunk.length))) } };
            const bytes = yield* readAll(yield* plain(this.#core.host, counted), (chunk) => {
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
  /// `heard`: the part's bytes so far, as they come; `sink`: its bytes handed over as they come, not kept (`bytes` empty);
  /// `said`: what the station says it is, as its answer begins (before its bytes). `quiet`: in the background, not said
  /// to be waited on.
  filePart(station: StationAddr, key: string, name: string, offset: number, length: number, ctx: SpanContext | null, heard?: (loaded: number) => void, sink?: (piece: Uint8Array) => void, said?: (head: { type: string; total: number }) => void, quiet = false): Effect.Effect<{ type: string; total: number; bytes: Uint8Array }, CoreError> {
    const path = `/sessions/${encode(key)}/parts?name=${encode(name)}&offset=${offset}&length=${length}`;
    const onHead = said && ((status: number, headers: [string, string][]) => {
      if (status !== 200) return;
      const total = Number(headerOf(headers, "stillfail-total"));
      if (Number.isSafeInteger(total)) said({ type: headerOf(headers, "content-type") ?? "", total });
    });
    return Effect.flatMap(this.exchange(station, "GET", path, [], empty, quiet, ctx, heard, undefined, sink, onHead), (r) => {
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

  /// GET /sessions/:key/open?path=&raw=1: a file a message names, whole, and what it is (`size`: its whole size). A
  /// station from before `raw` answers its JSON with the bytes in it as base64. With `range`, only that part of it (as
  /// the station's `stillfail-total` says its size); a station from before parts by path answers the whole (at most
  /// 16 MB), whose part is cut from it here.
  fileOpen(station: StationAddr, key: string, path: string, range: { offset: number; length: number } | null, ctx: SpanContext | null): Effect.Effect<{ name: string; path: string; type: string; size: number; bytes: Uint8Array }, CoreError> {
    const asked = `/sessions/${encode(key)}/open?path=${encode(path)}&raw=1${range === null ? "" : `&offset=${range.offset}&length=${range.length}`}`;
    return Effect.flatMap(this.exchange(station, "GET", asked, [], empty, false, ctx), (r) => {
      if (r.status !== 200) {
        const data = parseJson(r.body);
        return Effect.fail(httpError(r.status, data === undefined ? {} : data));
      }
      const header = (name: string) => r.headers.find(([k]) => k.toLowerCase() === name)?.[1];
      const total = Number(header("stillfail-total"));
      // (the whole, from a station that gives no parts: the part asked cut from it)
      const cut = (bytes: Uint8Array) =>
        range === null || Number.isSafeInteger(total) ? { size: Number.isSafeInteger(total) ? total : bytes.length, bytes } : { size: bytes.length, bytes: bytes.subarray(Math.min(range.offset, bytes.length), Math.min(range.offset + range.length, bytes.length)) };
      const named = header("stillfail-name");
      if (named !== undefined) {
        const decoded = (v: string | undefined) => { try { return decodeURIComponent(v ?? ""); } catch { return v ?? ""; } };
        return Effect.succeed({ name: decoded(named), path: decoded(header("stillfail-path")), type: header("content-type") ?? "", ...cut(r.body) });
      }
      const data = parseJson(r.body);
      const str = (k: string) => { const v = get(data, k); return typeof v === "string" ? v : ""; };
      return Effect.succeed({ name: str("name"), path: str("path"), type: str("type"), ...cut(fromBase64(str("bytes")) ?? new Uint8Array()) });
    });
  }

  /// GET /drive/read?root=&path=&offset=&length=: a part of a file of the station's drive, its whole size and time.
  /// `heard`, `sink`, `said`, `quiet`: as filePart's.
  driveRead(station: StationAddr, root: string, path: string, offset: number, length: number, ctx: SpanContext | null, heard?: (loaded: number) => void, sink?: (piece: Uint8Array) => void, said?: (head: { type: string; total: number; mtime: number | null }) => void, quiet = false): Effect.Effect<{ type: string; total: number; mtime: number | null; bytes: Uint8Array }, CoreError> {
    const asked = `/drive/read?root=${encode(root)}&path=${encode(path)}&offset=${offset}&length=${length}`;
    const onHead = said && ((status: number, headers: [string, string][]) => {
      if (status !== 200) return;
      const total = Number(headerOf(headers, "stillfail-total"));
      const mtime = Number(headerOf(headers, "stillfail-mtime"));
      if (Number.isSafeInteger(total)) said({ type: headerOf(headers, "content-type") ?? "", total, mtime: Number.isSafeInteger(mtime) ? mtime : null });
    });
    return Effect.flatMap(this.exchange(station, "GET", asked, [], empty, quiet, ctx, heard, undefined, sink, onHead), (r) => {
      if (r.status === 404 && isNoRoute(r.body)) return Effect.fail(new CoreError("unsupported", t("station.core.driveOldStation"), 404));
      if (r.status !== 200) {
        const data = parseJson(r.body);
        return Effect.fail(httpError(r.status, data === undefined ? {} : data));
      }
      const header = (name: string) => r.headers.find(([k]) => k.toLowerCase() === name)?.[1];
      const total = Number(header("stillfail-total"));
      const mtime = Number(header("stillfail-mtime"));
      return Effect.succeed({ type: header("content-type") ?? "", total: Number.isSafeInteger(total) ? total : offset + r.body.length, mtime: Number.isSafeInteger(mtime) ? mtime : null, bytes: r.body });
    });
  }

  /// PUT /drive/upload?root=&path=&id=&offset=&total=(&replace=1) with a part's bytes: `{ have, entry }`, how much of
  /// the file the station has and, once it is whole and in its place, its entry. A part that left a gap is refused
  /// with how much the station has (`have` on the error's answer: the next part starts there).
  driveUploadPart(station: StationAddr, q: { root: string; path: string; id: string; offset: number; total: number; replace: boolean }, bytes: Uint8Array, ctx: SpanContext | null): Effect.Effect<{ have: number; entry: unknown | null }, CoreError> {
    const asked = `/drive/upload?root=${encode(q.root)}&path=${encode(q.path)}&id=${encode(q.id)}&offset=${q.offset}&total=${q.total}${q.replace ? "&replace=1" : ""}`;
    return Effect.flatMap(this.exchange(station, "PUT", asked, [["content-type", "application/octet-stream"]], bytes, false, ctx), (r) => {
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      if (r.status === 409 && get(data, "code") === "upload_lost") {
        const have = get(data, "have");
        return Effect.succeed({ have: typeof have === "number" ? have : 0, entry: null });
      }
      if (r.status < 200 || r.status >= 300) return Effect.fail(httpError(r.status, data));
      const have = get(data, "have");
      const entry = get(data, "entry");
      return Effect.succeed({ have: typeof have === "number" ? have : q.offset + bytes.length, entry: entry === undefined ? null : entry });
    });
  }

  /// POST /drive/stage {root, path, zip?}: a file of the station's drive copied among the uploads (`zip`: a folder
  /// zipped there), waiting there as one sent up would (the same answer: `{name, path, size}`), for a message to send.
  driveStage(station: StationAddr, root: string, path: string, ctx: SpanContext | null, zip = false): Effect.Effect<unknown, CoreError> {
    const body = new TextEncoder().encode(JSON.stringify({ root, path, ...(zip ? { zip: true } : {}) }));
    return Effect.flatMap(this.exchange(station, "POST", "/drive/stage", [["content-type", "application/json"]], body, false, ctx), (r) => {
      const parsed = parseJson(r.body);
      const data = parsed === undefined ? {} : parsed;
      if (r.status === 404 && isNoRoute(r.body)) return Effect.fail(new CoreError("unsupported", t("station.core.driveOldStation"), 404));
      return r.status >= 200 && r.status < 300 ? Effect.succeed(data as unknown) : Effect.fail(httpError(r.status, data));
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

  /// A view of the station's screen `id` (docs/remote-screens.md): open once the station answers 200, its frames
  /// both ways then (screen-frames.ts). A station that refuses says why (`httpError`: 404 no such screen, or no such
  /// route on a station from before screens). A station from before screens that takes the stream for a request
  /// waits for a body never finished: the open is given up after SOCKET_OPEN_MS.
  screenView(station: StationAddr, id: string, ask: ScreenAsk, ctx: SpanContext | null): Effect.Effect<WireSocket, CoreError, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const full = `/admin/api/screens/${encode(id)}/view`;
      const waiting = this.#status(station).begin({ station: station.toString() }, t("core-misc.screen.opening"), false);
      const span = this.#core.tracer.span(`SCREEN ${route(full)}`, Kind.Client, ctx);
      span.set("url.path", route(full));
      span.set("stillfail.stream", true);
      const head: RequestHead = { method: "POST", path: full, headers: [["traceparent", span.context.traceparent()], [LANG_HEADER, current()]] };
      const opening = this.wire.screen ? this.wire.screen(station, head, ask) : Effect.fail(new CoreError("unsupported", t("core-misc.screen.noWire")));
      const opened = yield* Effect.result(
        Effect.raceFirst(
          opening,
          Effect.sleep(SOCKET_OPEN_MS).pipe(Effect.andThen(Effect.fail(new CoreError("timeout", t("core-misc.screen.timeout"))))),
        ).pipe(Effect.ensuring(Effect.sync(() => waiting.end()))),
      );
      if (opened._tag === "Failure") {
        failed(span, opened.failure);
        span.end();
        return yield* Effect.fail(opened.failure);
      }
      const view = opened.success;
      answered(span, view.reply);
      span.end();
      if (view.reply.status !== 200) {
        const bytes = yield* Effect.orElseSucceed(readAll(view.reply.body), () => empty);
        const data = parseJson(bytes);
        const error: CoreError & { access?: unknown } = httpError(view.reply.status, data === undefined ? {} : data);
        // What the station lacks for it (macOS's grants), said with a 503.
        if (isObject(get(data, "access"))) error.access = get(data, "access");
        return yield* Effect.fail(error);
      }
      return view;
    });
  }
}

export { asCoreError, isObject, Scope };
