// This device's iroh endpoint and its links to stations (mesh.rs), over the iroh a host gives (iroh.ts). One endpoint
// per core, its key the device key (storage `device`). A link is opened with this device's member credential for the
// station's workspace and presents it again every RENEW_MS on its control stream; a closed link is opened again on the
// next request. Wire format (mesh/station): ALPN `stillfail/admin/1` (or `ember/admin/1`); the first bi-stream
// carries `{"credential": …}` lines, each further bi-stream one request: a JSON head line `{method, path, headers}`
// then the body; the reply a JSON head line `{status, headers}` then the body, streamed.
//
// All of it runs as fibers (rule 1): an opening is a Deferred everyone asking for the station meanwhile waits on, a
// link's renewal and its first answer are fibers in the core's scope, a race and a hedge are fibers started as the UI
// comes back, measuring and the day's tally are fibers on the clock.
import { Deferred, Effect, Fiber, Semaphore } from "effect";
import type { Credential } from "./cloud.ts";
import type { Inner } from "./core.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host, Pull } from "./host.ts";
import { t } from "./i18n.ts";
import type { CloseReason, Iroh, IrohConnection, IrohEndpoint, IrohStream } from "./iroh.ts";
import * as format from "./format.ts";
import type { Runner } from "./runtime.ts";
import { RECHECKING } from "./station/words.ts";
import { StationAddr } from "./station/addr.ts";
import { IDEMPOTENCY_KEY, IDEMPOTENT } from "./station/requests.ts";
import type { LinkNet, RequestHead, SocketOut, StationWire, WireReply, WireSocket } from "./station/wire.ts";
import { RELAY } from "./status.ts";
import { Kind, type Tracer } from "./trace.ts";
import { fromUtf8, hex, parseJson, sha256, toJsonBytes, utf8 } from "./util.ts";
import type { Wakes } from "./wake.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export const DEVICE_KEY = "device";
export const ALPN = utf8("stillfail/admin/1");
export const FORMER_ALPN = utf8("ember/admin/1");
export const RENEW_MS = 5 * 60_000;
export const CONNECT_TIMEOUT_MS = 10_000;
export const PROBE_MS = 5_000;
export const RETIRE_MS = 10_000;
export const REBIND_MS = 5_000;
export const MEASURE_AFTER_MS = 3_000;
export const MEASURE_EVERY_MS = 4 * 60_000;
const MEASURE_TIMEOUT_MS = 15_000;
const MEASURE_WARMUP = 3;
const MEASURE_SAMPLES = 5;
export const NET_DAY_KEY = "net-day";
export const TALLY_EVERY_MS = 60_000;
const QUICKER_MS = 30;
const QUICKER_SHARE = 0.2;
/// A reply head is a line of JSON; anything longer is not a station talking.
const MAX_HEAD = 64 * 1024;
/// How long a write gone unanswered is asked again with its key (station.rs RECHECK_MS).
export const RECHECK_MS = 5 * 60 * 1000;

const noAnswer = () => t("core-logic.mesh.no_answer");
const meshError = (message: string) => new CoreError("mesh", message);

/// This device's credential for a station's workspace, for its id; `fresh` asks for a new one.
export type CredentialSource = (device: string, fresh: boolean) => Effect.Effect<Credential, CoreError>;

/// The ways to a station as last measured.
export type Measured = { measuring: boolean; relays: [string, number | null][]; moved: string | null };

type Day = { day: number; rx: number; tx: number };

function relayHost(relay: string): string {
  try {
    return new URL(relay).hostname || relay;
  } catch {
    return relay;
  }
}

function sameRelay(a: string | null, b: string): boolean {
  if (a === null) return false;
  try {
    return new URL(a).href === new URL(b).href;
  } catch {
    return a === b;
  }
}

/// The key of the endpoint on one relay alone: the device key's, made over for that relay.
export function pinnedKey(secret: Uint8Array, relay: string): Uint8Array {
  const prefix = utf8("stillfail/relay-endpoint/1\0");
  const r = utf8(relay);
  const all = new Uint8Array(prefix.length + secret.length + r.length);
  all.set(prefix, 0);
  all.set(secret, prefix.length);
  all.set(r, prefix.length + secret.length);
  return sha256(all);
}

/// The relay to move a link to, of those measured: the quickest, if the link is not already through it and it is
/// quicker than the link's round trip by both QUICKER_MS and QUICKER_SHARE.
export function quicker(rttMs: number | null, via: string | null, measured: [string, number | null][]): string | null {
  let best: [string, number] | null = null;
  for (const [relay, ms] of measured) if (ms !== null && (best === null || ms < best[1])) best = [relay, ms];
  if (best === null) return null;
  if (via !== null && sameRelay(via, best[0])) return null;
  const fresh = measured.find(([relay]) => sameRelay(via, relay))?.[1] ?? null;
  const now = fresh ?? rttMs;
  if (now === null) return null;
  return best[1] + QUICKER_MS <= now && best[1] <= now * (1 - QUICKER_SHARE) ? best[0] : null;
}

function closeMessage(reason: CloseReason): string {
  if (reason.kind === "application") {
    switch (reason.reason) {
      case "credential_refused":
        return t("core-logic.mesh.credential_refused");
      case "credential_revoked":
        return t("core-logic.mesh.credential_revoked");
      case "credential_expired":
        return t("core-logic.mesh.credential_expired");
      case "station_removed":
        return t("core-logic.mesh.station_removed");
      default:
        return t("core-logic.mesh.closed_by_station", { reason: reason.reason });
    }
  }
  if (reason.kind === "local") return t("core-logic.mesh.closed");
  if (reason.kind === "timeout") return t("core-logic.mesh.timed_out");
  return t("core-logic.mesh.lost", { error: reason.reason });
}

/// Reads lines off a stream, keeping what followed.
class Lines {
  readonly #stream: IrohStream;
  carry: Uint8Array = new Uint8Array();

  constructor(stream: IrohStream) {
    this.#stream = stream;
  }

  /// One newline-terminated line; null at the stream's end.
  next(): Effect.Effect<string | null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        const at = this.carry.indexOf(10);
        if (at >= 0) {
          const line = fromUtf8(this.carry.subarray(0, at));
          this.carry = this.carry.slice(at + 1);
          return line;
        }
        if (this.carry.length > MAX_HEAD) return yield* Effect.fail(meshError(t("core-logic.mesh.head_too_long")));
        const chunk = yield* Effect.mapError(this.#stream.read(), (e) => meshError(t("core-logic.mesh.read_failed", { error: e.message })));
        if (chunk === null) {
          if (this.carry.length === 0) return null;
          return yield* Effect.fail(meshError(t("core-logic.mesh.reply_cut")));
        }
        const next = new Uint8Array(this.carry.length + chunk.length);
        next.set(this.carry, 0);
        next.set(chunk, this.carry.length);
        this.carry = next;
      }
    });
  }
}

/// The control stream: credential lines out, answers back.
class Control {
  readonly stream: IrohStream;
  readonly lines: Lines;
  constructor(stream: IrohStream) {
    this.stream = stream;
    this.lines = new Lines(stream);
  }

  send(credential: string): Effect.Effect<void, CoreError> {
    const line = utf8(`${JSON.stringify({ credential, protocol: 2 })}\n`);
    return Effect.mapError(this.stream.write(line), (e) => meshError(t("core-logic.mesh.credential_unsent", { error: e.message })));
  }

  /// The station's answer to the credential last sent; fails if it refused.
  answer(): Effect.Effect<J, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const line = yield* this.lines.next();
      if (line === null) return yield* Effect.fail(meshError(t("core-logic.mesh.credential_closed")));
      let answer: J;
      try {
        answer = JSON.parse(line);
      } catch (e) {
        return yield* Effect.fail(meshError(t("core-logic.mesh.credential_unreadable", { error: String(e) })));
      }
      if (answer !== null && typeof answer === "object" && "error" in answer) {
        const reason = typeof answer.error === "string" ? answer.error : JSON.stringify(answer.error);
        if (answer.code === "client_upgrade_required") return yield* Effect.fail(new CoreError("client_upgrade_required", reason));
        return yield* Effect.fail(new CoreError("credential_refused", t("core-logic.mesh.credential_refused_why", { reason })));
      }
      return answer;
    });
  }

  exchange(credential: string): Effect.Effect<J, CoreError> {
    return Effect.andThen(this.send(credential), this.answer());
  }
}

/// A station's reply: its head, and its body as it comes (what came with the head line first).
export type Reply = {
  status: number;
  headers: [string, string][];
  body: Pull<Uint8Array>;
  /// Lets go of it: the stream is stopped both ways (what is not read any more, the station stops sending).
  cancel(): void;
};

function headersOf(v: J): [string, string][] {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return [];
  return Object.entries(v).map(([k, x]) => [k, typeof x === "string" ? x : JSON.stringify(x)]);
}

export class Link {
  readonly conn: IrohConnection;
  readonly #control: Control;
  readonly #lock = Semaphore.makeUnsafe(1);
  renewalFailed = false;
  /// The station's refusal of the first credential, once it answered.
  refused: CoreError | null = null;
  credential: string;
  readonly credentials: CredentialSource;
  /// The relay whose own endpoint it is on; null on the main one.
  readonly pinned: string | null;
  counted: [number, number] = [0, 0];

  constructor(conn: IrohConnection, control: Control, credential: string, credentials: CredentialSource, pinned: string | null) {
    this.conn = conn;
    this.#control = control;
    this.credential = credential;
    this.credentials = credentials;
    this.pinned = pinned;
  }

  /// What its control stream is asked, one exchange at a time.
  controlled<A>(f: (c: Control) => Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
    return this.#lock.withPermits(1)(f(this.#control));
  }

  #open(head: J, finish: boolean, body: Uint8Array | null): Effect.Effect<[IrohStream, Lines, J], CoreError> {
    const sent = (e: { message: string }) => meshError(t("core-logic.mesh.request_unsent", { error: e.message }));
    return Effect.gen({ self: this }, function* () {
      const stream = yield* Effect.mapError(this.conn.openBi(), sent);
      yield* Effect.mapError(stream.write(utf8(`${JSON.stringify(head)}\n`)), sent);
      if (body !== null && body.length > 0) yield* Effect.mapError(stream.write(body), sent);
      if (finish) yield* Effect.mapError(stream.finish(), sent);
      const lines = new Lines(stream);
      const line = yield* lines.next();
      if (line === null) return yield* Effect.fail(meshError(t("core-logic.mesh.no_reply")));
      let reply: J;
      try {
        reply = JSON.parse(line);
      } catch (e) {
        return yield* Effect.fail(meshError(t("core-logic.mesh.reply_unreadable", { error: String(e) })));
      }
      const status = reply?.status;
      if (typeof status !== "number" || !Number.isInteger(status) || status < 0 || status > 65535) return yield* Effect.fail(meshError(t("core-logic.mesh.reply_no_status")));
      return [stream, lines, reply] as [IrohStream, Lines, J];
    });
  }

  static #body(stream: IrohStream, lines: Lines): Pull<Uint8Array> {
    let carry: Uint8Array | null = lines.carry.length > 0 ? lines.carry : null;
    let done = false;
    return {
      take: Effect.suspend(() => {
        if (carry !== null) {
          const c = carry;
          carry = null;
          return Effect.succeed(c);
        }
        if (done) return Effect.succeed(null);
        return Effect.map(
          Effect.tapError(stream.read(), () => Effect.sync(() => (done = true))),
          (chunk) => {
            if (chunk === null) done = true;
            return chunk;
          },
        );
      }),
    };
  }

  /// One request on its own stream.
  request(head: RequestHead, body: Uint8Array): Effect.Effect<Reply, CoreError> {
    const wire = { method: head.method, path: head.path, headers: Object.fromEntries(head.headers) };
    return Effect.mapError(
      Effect.map(this.#open(wire, true, body), ([stream, lines, reply]) => ({ status: reply.status, headers: headersOf(reply.headers), body: Link.#body(stream, lines), cancel: () => stream.reset(0) })),
      (e) => this.refused ?? e,
    );
  }

  /// A preview page's WebSocket on its own stream: the stream stays open both ways.
  socket(head: RequestHead): Effect.Effect<[Reply, SocketOut], CoreError> {
    const wire = { method: head.method, path: head.path, headers: Object.fromEntries(head.headers), socket: true };
    return Effect.map(this.#open(wire, false, null), ([stream, lines, reply]) => {
      const out: SocketOut = {
        write: (bytes) => Effect.mapError(stream.write(bytes), (e) => meshError(t("core-logic.mesh.unsent", { error: e.message }))),
        finish: () => void Effect.runFork(Effect.ignore(stream.finish())),
      };
      return [{ status: reply.status, headers: headersOf(reply.headers), body: Link.#body(stream, lines), cancel: () => stream.reset(0) }, out] as [Reply, SocketOut];
    });
  }

  /// This phone's adb offered to the station, or asked about (adb.ts).
  adb(head: RequestHead, ask: J): Effect.Effect<Reply, CoreError> {
    const wire = { method: head.method, path: head.path, headers: Object.fromEntries(head.headers), adb: ask };
    return Effect.map(this.#open(wire, true, null), ([stream, lines, reply]) => ({ status: reply.status, headers: headersOf(reply.headers), body: Link.#body(stream, lines), cancel: () => stream.reset(0) }));
  }

  /// The next stream the station opens on the link; null once it closed.
  accept(): Effect.Effect<IrohStream | null> {
    return this.conn.acceptBi();
  }

  closed(): string | null {
    const r = this.conn.closeReason();
    return r === null ? null : closeMessage(r);
  }

  close(): void {
    this.conn.close(0, "closed");
  }

  path(): string | null {
    const p = this.conn.paths().find((x) => x.selected);
    return p === undefined ? null : p.relay !== null ? "relay" : "direct";
  }

  via(): string | null {
    return this.conn.paths().find((x) => x.selected)?.relay ?? null;
  }

  net(): LinkNet {
    const selected = this.conn.paths().find((p) => p.selected);
    const stats = this.conn.stats();
    return {
      path: selected === undefined ? null : selected.relay !== null ? "relay" : "direct",
      relay: selected?.relay ? relayHost(selected.relay) : null,
      rttMs: selected !== undefined ? selected.rttMs : null,
      measured: null,
      today: null,
      rxBytes: stats.rxBytes,
      txBytes: stats.txBytes,
      txPackets: stats.txPackets,
      lostPackets: stats.lostPackets,
    };
  }

  /// What went over it, both ways, since this was last asked.
  uncounted(): [number, number] {
    const stats = this.conn.stats();
    const [wasRx, wasTx] = this.counted;
    this.counted = [stats.rxBytes, stats.txBytes];
    return [Math.max(stats.rxBytes - wasRx, 0), Math.max(stats.txBytes - wasTx, 0)];
  }

  /// Whether the station answers on it within PROBE_MS: the credential presented again.
  answers(): Effect.Effect<boolean> {
    const exchange = Effect.map(Effect.result(this.controlled((c) => c.exchange(this.credential))), (r) => r._tag === "Success");
    return Effect.raceFirst(exchange, Effect.as(Effect.sleep(PROBE_MS), false));
  }

  usable(): boolean {
    return this.conn.closeReason() === null && !this.renewalFailed;
  }
}

/// An opening shared by everyone who asks for the same station meanwhile.
type Opening = { done: Deferred.Deferred<Link, CoreError>; result: { ok: Link } | { err: CoreError } | null };

/// A link tried beside an opening still under way (`hedge`).
type Hedge = { serial: number; credentials: CredentialSource; tx: Deferred.Deferred<Link, CoreError> | null };

export type MeshEnv = { host: Host; runner: Runner; tracer: Tracer; iroh: Iroh; wakes: Wakes };

export class Mesh {
  readonly #env: MeshEnv;
  readonly relays: string[];
  #endpoint: IrohEndpoint;
  #secret: Uint8Array;
  readonly #links = new Map<string, Opening>();
  #changed: Deferred.Deferred<void>[] = [];
  readonly #racing = new Set<string>();
  #stuck = false;
  #reboundAt = -Infinity;
  readonly #known: import("./iroh.ts").IrohAddr[] = [];
  readonly #hedges = new Map<string, Hedge>();
  #serials = 0;
  readonly #pinned = new Map<string, Deferred.Deferred<IrohEndpoint | null>>();
  readonly #measuring = new Set<string>();
  #probing = 0;
  readonly #measured = new Map<string, Measured>();
  #days: Record<string, Day>;
  #daysChanged = false;

  private constructor(env: MeshEnv, relays: string[], endpoint: IrohEndpoint, secret: Uint8Array, days: Record<string, Day>) {
    this.#env = env;
    this.relays = relays;
    this.#endpoint = endpoint;
    this.#secret = secret;
    this.#days = days;
  }

  /// Binds the endpoint with the stored device key (made and stored the first time). No relays binds without one.
  static make(env: MeshEnv, relays: string[]): Effect.Effect<Mesh, CoreError> {
    return Effect.gen(function* () {
      const host = env.host;
      const stored = yield* Effect.mapError(host.storageGet(DEVICE_KEY), asCoreError);
      let secret: Uint8Array;
      if (stored !== null && stored.length === 32) secret = stored;
      else {
        secret = new Uint8Array(32);
        host.randomBytes(secret);
        yield* Effect.mapError(host.storageSet(DEVICE_KEY, secret), asCoreError);
      }
      const daysRaw = parseJson(yield* Effect.orElseSucceed(host.storageGet(NET_DAY_KEY), () => null)) as J;
      const days: Record<string, Day> = daysRaw !== null && typeof daysRaw === "object" && !Array.isArray(daysRaw) ? daysRaw : {};
      const endpoint = yield* Mesh.#bind(env.iroh, secret, relays);
      const mesh = new Mesh(env, relays, endpoint, secret, days);
      env.runner.fork(mesh.#watch());
      env.runner.fork(mesh.#tally());
      return mesh;
    });
  }

  static #bind(iroh: Iroh, secret: Uint8Array, relays: string[], relayOnly = false): Effect.Effect<IrohEndpoint, CoreError> {
    return Effect.mapError(iroh.bind({ secretKey: secret, relayUrls: relays, lookup: !relayOnly && relays.length > 0, relayOnly }), (e) => meshError(t("core-logic.mesh.bind_failed", { error: e.message })));
  }

  #openLinks(): [string, Link][] {
    const out: [string, Link][] = [];
    for (const [id, o] of this.#links) if (o.result && "ok" in o.result && o.result.ok.usable()) out.push([id, o.result.ok]);
    return out;
  }

  /// The station's link now, if one is open.
  current(stationId: string): Link | null {
    const o = this.#links.get(stationId);
    return o?.result && "ok" in o.result ? o.result.ok : null;
  }

  /// What the station's links carried on this device today, both ways.
  today(stationId: string): [number, number] {
    const link = this.current(stationId);
    if (link) this.#count(stationId, link);
    const d = this.#days[stationId];
    return d && d.day === this.#localDay() ? [d.rx, d.tx] : [0, 0];
  }

  #count(stationId: string, link: Link): void {
    const [rx, tx] = link.uncounted();
    if (rx === 0 && tx === 0) return;
    const today = this.#localDay();
    let d = this.#days[stationId];
    if (!d || d.day !== today) {
      d = { day: today, rx: 0, tx: 0 };
      this.#days[stationId] = d;
    }
    d.rx += rx;
    d.tx += tx;
    this.#daysChanged = true;
  }

  #keepDays(): void {
    if (!this.#daysChanged) return;
    this.#daysChanged = false;
    const today = this.#localDay();
    for (const [id, d] of Object.entries(this.#days)) if (d.day !== today) delete this.#days[id];
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(NET_DAY_KEY, toJsonBytes(this.#days))));
  }

  #localDay(): number {
    const now = this.#env.host.nowMs();
    return format.localDay(now, this.#env.host.utcOffsetMin(now));
  }

  #isCurrent(stationId: string, link: Link): boolean {
    return this.current(stationId) === link;
  }

  #dropIf(stationId: string, link: Link): void {
    if (this.#isCurrent(stationId, link)) this.dropLink(stationId);
  }

  #notify(): void {
    const waiting = this.#changed;
    this.#changed = [];
    for (const d of waiting) Deferred.doneUnsafe(d, Effect.void);
  }

  /// Succeeds once `link` is no longer the station's link (another put in its place, or it was dropped).
  replaced(stationId: string, link: Link): Effect.Effect<void> {
    return Effect.suspend(() => {
      const loop: Effect.Effect<void> = Effect.suspend(() => {
        if (!this.#isCurrent(stationId, link)) return Effect.void;
        const d = Deferred.makeUnsafe<void>();
        this.#changed.push(d);
        return Effect.andThen(Deferred.await(d), loop);
      });
      return loop;
    });
  }

  /// Puts `next` in place of `old` (if `old` still is), and closes `old` after RETIRE_MS.
  #switch(stationId: string, old: Link, next: Link): void {
    if (!this.#isCurrent(stationId, old)) {
      next.close();
      return;
    }
    const done = Deferred.makeUnsafe<Link, CoreError>();
    Deferred.doneUnsafe(done, Effect.succeed(next));
    this.#links.set(stationId, { done, result: { ok: next } });
    this.#notify();
    this.#env.runner.fork(
      Effect.andThen(
        Effect.sleep(RETIRE_MS),
        Effect.sync(() => {
          old.conn.close(0, "replaced");
          this.#count(stationId, old);
        }),
      ),
    );
  }

  deviceId(): string {
    return this.#endpoint.id();
  }

  /// This device's clock.
  now(): number {
    return this.#env.host.nowMs();
  }

  endpoint(): IrohEndpoint {
    return this.#endpoint;
  }

  /// Tells this endpoint, and each bound after it, where a station is (no relay: tests, a LAN).
  addAddr(addr: import("./iroh.ts").IrohAddr): void {
    this.#endpoint.addAddr(addr);
    this.#known.push(addr);
  }

  #anyOpen(): boolean {
    return this.#openLinks().length > 0;
  }

  /// The endpoint bound anew with the same key, the old one closed: at most once in REBIND_MS.
  #rebind(): Effect.Effect<IrohEndpoint> {
    return Effect.gen({ self: this }, function* () {
      const now = this.#env.host.nowMs();
      if (now - this.#reboundAt < REBIND_MS) return this.#endpoint;
      this.#reboundAt = now;
      const bound = yield* Effect.result(Mesh.#bind(this.#env.iroh, this.#secret, this.relays));
      if (bound._tag === "Failure") return this.#endpoint;
      const endpoint = bound.success;
      for (const addr of this.#known) endpoint.addAddr(addr);
      const old = this.#endpoint;
      this.#endpoint = endpoint;
      this.#stuck = false;
      this.#env.runner.fork(old.close());
      return endpoint;
    });
  }

  /// The link to a station, opening it (or opening again a closed one) with a credential from `credentials`.
  link(stationId: string, credentials: CredentialSource): Effect.Effect<Link, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const existing = this.#links.get(stationId);
      let fresh = false;
      if (existing) {
        if (existing.result === null) return yield* Deferred.await(existing.done);
        if ("ok" in existing.result) {
          if (existing.result.ok.usable()) return existing.result.ok;
          fresh = existing.result.ok.refused !== null;
        } else fresh = existing.result.err.code === "credential_refused";
      }
      const span = this.#env.tracer.span("mesh.connect", Kind.Internal);
      span.set("stillfail.station", stationId);
      let endpoint = this.#endpoint;
      if (this.#stuck && !this.#anyOpen()) {
        span.set("stillfail.rebound", true);
        endpoint = yield* this.#rebind();
      }
      span.set("stillfail.relay", relayStatus(endpoint));
      const serial = ++this.#serials;
      const hedged = Deferred.makeUnsafe<Link, CoreError>();
      this.#hedges.set(stationId, { serial, credentials, tx: hedged });
      const opening: Opening = { done: Deferred.makeUnsafe<Link, CoreError>(), result: null };
      const before = this.#links.get(stationId);
      this.#links.set(stationId, opening);
      if (before?.result && "ok" in before.result) this.#count(stationId, before.result.ok);
      this.#notify();
      const first = open(this.#env, endpoint, this.relays, stationId, credentials, fresh, null, span.context);
      const self = this;
      const run = Effect.gen(function* () {
        const raced = yield* Effect.raceFirst(
          Effect.map(Effect.result(first), (r) => ({ first: r }) as const),
          Effect.map(Effect.result(Deferred.await(hedged)), (r) => ({ hedged: r }) as const),
        );
        let link: { _tag: "Success"; success: Link } | { _tag: "Failure"; failure: CoreError };
        if ("first" in raced) {
          if (raced.first._tag === "Success") link = raced.first;
          else {
            // Failed: the link tried beside it, if one was.
            const h = self.#hedges.get(stationId);
            const tried = h !== undefined && h.serial === serial && h.tx === null;
            if (tried) {
              const other = yield* Effect.result(Deferred.await(hedged));
              link = other._tag === "Success" ? other : raced.first;
            } else link = raced.first;
          }
        } else if (raced.hedged._tag === "Success") {
          span.set("stillfail.hedged", true);
          link = raced.hedged;
        } else link = yield* Effect.result(first);
        if (self.#hedges.get(stationId)?.serial === serial) self.#hedges.delete(stationId);
        if (link._tag === "Success") {
          self.#stuck = false;
          const path = link.success.path();
          if (path !== null) span.set("stillfail.path", path);
        } else {
          if (link.failure.message === noAnswer()) self.#stuck = true;
          span.fail();
          span.set("error.type", link.failure.code);
          span.set("stillfail.relay", relayStatus(endpoint));
        }
        span.end();
        opening.result = link._tag === "Success" ? { ok: link.success } : { err: link.failure };
        Deferred.doneUnsafe(opening.done, link._tag === "Success" ? Effect.succeed(link.success) : Effect.fail(link.failure));
      });
      this.#env.runner.fork(run);
      const link = yield* Deferred.await(opening.done);
      this.#measureSoon(stationId);
      return link;
    });
  }

  /// Closes the link to a station, if one is open or opening: taken for gone.
  dropLink(stationId: string): void {
    const opening = this.#links.get(stationId);
    this.#links.delete(stationId);
    this.#notify();
    if (opening?.result && "ok" in opening.result) {
      opening.result.ok.conn.close(0, "woke");
      this.#count(stationId, opening.result.ok);
    }
  }

  /// Takes over the device key a page kept before the core existed (32 bytes): stored, the endpoint bound anew with
  /// it, open links closed. The same key again changes nothing.
  migrate(secret: Uint8Array): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (secret.length !== 32) return yield* Effect.fail(CoreError.invalid(t("core-logic.mesh.bad_device_key")));
      const stored = yield* Effect.mapError(this.#env.host.storageGet(DEVICE_KEY), asCoreError);
      if (stored !== null && hex(stored) === hex(secret)) return;
      const endpoint = yield* Mesh.#bind(this.#env.iroh, secret, this.relays);
      yield* Effect.mapError(this.#env.host.storageSet(DEVICE_KEY, secret), asCoreError);
      this.#secret = secret;
      const old = this.#endpoint;
      this.#endpoint = endpoint;
      for (const [, p] of [...this.#pinned]) {
        const e = yield* Deferred.await(p);
        if (e) this.#env.runner.fork(e.close());
      }
      this.#pinned.clear();
      const links = [...this.#links];
      this.#links.clear();
      this.#notify();
      for (const [id, o] of links) {
        if (o.result && "ok" in o.result) {
          o.result.ok.conn.close(0, "device key replaced");
          this.#count(id, o.result.ok);
        }
      }
      this.#env.runner.fork(old.close());
    });
  }

  #measureSoon(stationId: string): void {
    if (this.relays.length < 2 || this.#measuring.has(stationId)) return;
    this.#measuring.add(stationId);
    this.#env.runner.fork(this.#measure(stationId));
  }

  measured(stationId: string): Measured | null {
    return this.#measured.get(stationId) ?? null;
  }

  /// Measures the ways to a station now, as a person asks.
  remeasure(stationId: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      if (this.measured(stationId)?.measuring) return Effect.void;
      const link = this.current(stationId);
      if (link === null || !link.usable()) return Effect.fail(meshError(t("core-logic.mesh.not_connected")));
      return this.#quickest(stationId, link);
    });
  }

  #pinnedEndpoint(relay: string): Effect.Effect<IrohEndpoint | null> {
    return Effect.gen({ self: this }, function* () {
      const existing = this.#pinned.get(relay);
      if (existing) return yield* Deferred.await(existing);
      const d = Deferred.makeUnsafe<IrohEndpoint | null>();
      this.#pinned.set(relay, d);
      const bound = yield* Effect.result(Mesh.#bind(this.#env.iroh, pinnedKey(this.#secret, relay), [relay]));
      const endpoint = bound._tag === "Success" ? bound.success : null;
      Deferred.doneUnsafe(d, Effect.succeed(endpoint));
      if (endpoint === null) this.#pinned.delete(relay);
      return endpoint;
    });
  }

  /// A relay-only connection, warmed up before sampling QUIC's round trip estimate.
  #probe(relay: string, stationId: string): Effect.Effect<number | null> {
    return Effect.gen({ self: this }, function* () {
      const secret = pinnedKey(pinnedKey(this.#secret, relay), stationId);
      const bound = yield* Effect.result(Mesh.#bind(this.#env.iroh, secret, [relay], true));
      if (bound._tag === "Failure") return null;
      const endpoint = bound.success;
      const exchange = Effect.gen(function* () {
        const conn = yield* Effect.result(endpoint.connect({ id: stationId, relays: [relay] }, ALPN, [FORMER_ALPN]));
        if (conn._tag === "Failure") return null;
        const rtt = yield* sampleRelayRtt(conn.success, relay);
        conn.success.close(0, "measured");
        return rtt;
      });
      const rtt = yield* Effect.raceFirst(exchange, Effect.as(Effect.sleep(MEASURE_TIMEOUT_MS), null));
      yield* endpoint.close();
      return rtt;
    });
  }

  /// Measures the way to the station through each relay and, if one is clearly quicker than the way `link` goes,
  /// opens a link on that relay's own endpoint and puts it in `link`'s place.
  #quickest(stationId: string, link: Link): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.measured(stationId)?.measuring) return;
      const span = this.#env.tracer.span("mesh.measure", Kind.Internal);
      span.set("stillfail.station", stationId);
      const net = link.net();
      const via = link.via();
      if (net.rttMs !== null) span.set("stillfail.rtt", Math.round(net.rttMs));
      if (via !== null) span.set("stillfail.via", relayHost(via));
      const entry = this.#measured.get(stationId) ?? { measuring: false, relays: [], moved: null };
      entry.measuring = true;
      this.#measured.set(stationId, entry);
      this.#probing++;
      const measured = yield* Effect.all(
        this.relays.map((relay) => Effect.map(this.#probe(relay, stationId), (ms) => [relay, ms] as [string, number | null])),
        { concurrency: "unbounded" },
      );
      this.#probing--;
      const shown: Measured = { measuring: false, relays: measured.map(([r, ms]) => [relayHost(r), ms]), moved: null };
      for (const [relay, ms] of measured) span.set(`stillfail.rtt.${relayHost(relay)}`, ms !== null ? Math.round(ms) : "none");
      const relay = link.path() === "relay" && this.#isCurrent(stationId, link) ? quicker(net.rttMs, via, measured) : null;
      if (relay !== null) {
        const endpoint = yield* this.#pinnedEndpoint(relay);
        if (endpoint !== null) {
          span.set("stillfail.moved", relayHost(relay));
          const opened = yield* Effect.result(open(this.#env, endpoint, [relay], stationId, link.credentials, false, relay, span.context));
          if (opened._tag === "Success") {
            const next = opened.success;
            if (this.#isCurrent(stationId, link) && link.path() === "relay") {
              const v = next.via();
              shown.moved = v !== null ? relayHost(v) : null;
              this.#switch(stationId, link, next);
            } else next.close();
          } else {
            span.fail();
            span.set("error.type", opened.failure.code);
          }
        }
      }
      span.end();
      this.#measured.set(stationId, shown);
      this.#env.runner.fork(Effect.andThen(Effect.sleep(RETIRE_MS), Effect.suspend(() => this.#letGo())));
    });
  }

  /// Closes the pinned endpoints no open link is on, unless something is being measured on them.
  #letGo(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#probing > 0) return;
      const used = new Set(this.#openLinks().flatMap(([, l]) => (l.pinned !== null ? [l.pinned] : [])));
      for (const [relay, d] of [...this.#pinned]) {
        if (used.has(relay)) continue;
        this.#pinned.delete(relay);
        const e = yield* Deferred.await(d);
        if (e) this.#env.runner.fork(e.close());
      }
    });
  }

  /// Keeps a station's link on the quickest way there, for as long as it has one.
  #measure(stationId: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      yield* Effect.sleep(MEASURE_AFTER_MS);
      for (;;) {
        const link = this.current(stationId);
        if (link === null || !link.usable()) {
          this.#measuring.delete(stationId);
          return;
        }
        if (link.path() === "relay") yield* this.#quickest(stationId, link);
        yield* Effect.sleep(MEASURE_EVERY_MS);
      }
    });
  }

  /// As the UI comes back or the network changes: iroh is told, each open link races a new one, each link still
  /// opening has another tried beside it.
  #watch(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        const wake = yield* this.#env.wakes.next;
        if (!wake.suspectsConnections()) continue;
        this.#env.runner.fork(this.#endpoint.networkChange());
        for (const [id, link] of this.#openLinks()) {
          if (this.#racing.has(id)) continue;
          this.#racing.add(id);
          this.#env.runner.fork(this.#race(id, link));
        }
        for (const [id, h] of this.#hedges) {
          if (h.tx === null) continue;
          const tx = h.tx;
          h.tx = null;
          this.#env.runner.fork(this.#hedge(id, h.credentials, tx));
        }
      }
    });
  }

  #tally(): Effect.Effect<void> {
    return Effect.forever(
      Effect.andThen(
        Effect.sleep(TALLY_EVERY_MS),
        Effect.sync(() => {
          for (const [id, o] of this.#links) if (o.result && "ok" in o.result) this.#count(id, o.result.ok);
          this.#keepDays();
        }),
      ),
    );
  }

  /// A link tried beside an opening still under way: on an endpoint bound anew if nothing is open on this one.
  #hedge(id: string, credentials: CredentialSource, tx: Deferred.Deferred<Link, CoreError>): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const endpoint = this.#anyOpen() ? this.#endpoint : yield* this.#rebind();
      const span = this.#env.tracer.span("mesh.hedge", Kind.Internal);
      span.set("stillfail.station", id);
      span.set("stillfail.relay", relayStatus(endpoint));
      const opened = yield* Effect.result(open(this.#env, endpoint, this.relays, id, credentials, false, null, span.context));
      if (opened._tag === "Failure") span.fail();
      span.end();
      const taken = Deferred.doneUnsafe(tx, opened._tag === "Success" ? Effect.succeed(opened.success) : Effect.fail(opened.failure));
      if (!taken && opened._tag === "Success") opened.success.close();
    });
  }

  /// A link suspect against a new one opened beside it at once: whichever answers first.
  #race(id: string, old: Link): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const span = this.#env.tracer.span("mesh.race", Kind.Internal);
      span.set("stillfail.station", id);
      const fresh = Effect.result(open(this.#env, this.#endpoint, this.relays, id, old.credentials, false, null, span.context));
      const freshFiber = yield* Effect.forkChild(fresh);
      const probeFiber = yield* Effect.forkChild(old.answers());
      const first = yield* Effect.raceFirst(
        Effect.map(Fiber.join(probeFiber), (answered) => ({ probe: answered }) as const),
        Effect.map(Fiber.join(freshFiber), (opened) => ({ fresh: opened }) as const),
      );
      let won: "old" | "neither" | Link;
      if ("probe" in first) {
        if (first.probe) won = "old";
        else {
          const opened = yield* Fiber.join(freshFiber);
          won = opened._tag === "Success" ? opened.success : "neither";
        }
      } else if (first.fresh._tag === "Success") won = first.fresh.success;
      else won = (yield* Fiber.join(probeFiber)) ? "old" : "neither";
      // The other, still going, is let be: a link it opens late is let go.
      if (won === "old") {
        const late = yield* Effect.forkChild(Effect.map(Fiber.join(freshFiber), (r) => (r._tag === "Success" ? r.success.close() : undefined)));
        void late;
      }
      this.#racing.delete(id);
      span.set("stillfail.race", won === "old" ? "old" : won === "neither" ? "neither" : "new");
      span.end();
      if (won === "neither") this.#dropIf(id, old);
      else if (won !== "old") this.#switch(id, old, won);
    });
  }

  close(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (const [, o] of this.#links) if (o.result && "ok" in o.result) o.result.ok.close();
      this.#links.clear();
      yield* this.#endpoint.close();
    });
  }
}

function relayStatus(endpoint: IrohEndpoint): string {
  const status = endpoint.relayStatus();
  if (status.length === 0) return "none";
  return status.map((s) => `${s.url} ${s.connected ? "up" : "down"}`).join(", ");
}

/// Sends a byte on a one-way stream and waits for its acknowledgement, then reads QUIC's round trip estimate.
function sampleRelayRtt(conn: IrohConnection, relay: string): Effect.Effect<number | null> {
  return Effect.gen(function* () {
    const samples: number[] = [];
    for (let i = 0; i < MEASURE_WARMUP + MEASURE_SAMPLES; i++) {
      const sent = yield* Effect.result(
        Effect.gen(function* () {
          const s = yield* conn.openUni();
          yield* s.write(new Uint8Array([0]));
          yield* s.finish();
          return yield* s.stopped();
        }),
      );
      if (sent._tag === "Failure" || sent.success !== null) return null;
      const path = conn.paths().find((p) => p.selected);
      if (path === undefined || !sameRelay(path.relay, relay)) return null;
      if (i >= MEASURE_WARMUP) samples.push(path.rttMs);
    }
    samples.sort((a, b) => a - b);
    return samples[Math.floor(MEASURE_SAMPLES / 2)];
  });
}

/// Connects, presents the first credential, and starts renewing it. The credential is asked for while the
/// connection is being made; the link is handed out as soon as the credential is sent (the station reads it before any
/// request stream). A refusal closes the connection; the requests on it fail, and the next `link` starts over.
function open(
  env: MeshEnv,
  endpoint: IrohEndpoint,
  relays: string[],
  stationId: string,
  credentials: CredentialSource,
  fresh: boolean,
  pinned: string | null,
  _ctx: unknown,
): Effect.Effect<Link, CoreError> {
  return Effect.gen(function* () {
    if (!/^[0-9a-f]{64}$/.test(stationId)) return yield* Effect.fail(CoreError.invalid(t("core-logic.mesh.bad_station_id", { id: stationId })));
    const device = endpoint.id();
    const connecting = Effect.raceFirst(
      Effect.mapError(endpoint.connect({ id: stationId, relays }, ALPN, [FORMER_ALPN]), (e) => meshError(t("core-logic.mesh.unreachable", { error: e.message }))),
      Effect.andThen(Effect.sleep(CONNECT_TIMEOUT_MS), Effect.fail(meshError(noAnswer()))),
    );
    const [credential, conn] = yield* Effect.all([Effect.result(credentials(device, fresh)), connecting], { concurrency: "unbounded" });
    if (credential._tag === "Failure") {
      conn.close(0, "no credential");
      return yield* Effect.fail(credential.failure);
    }
    const stream = yield* Effect.mapError(conn.openBi(), (e) => meshError(t("core-logic.mesh.unreachable", { error: e.message })));
    const control = new Control(stream);
    yield* control.send(credential.success.credential);
    const link = new Link(conn, control, credential.success.credential, credentials, pinned);
    // The station's answer to the first credential, while requests already go: a refusal closes the link.
    env.runner.fork(
      Effect.gen(function* () {
        const answer = yield* Effect.result(link.controlled((c) => c.answer()));
        if (answer._tag === "Failure") {
          link.renewalFailed = true;
          link.refused = answer.failure;
          conn.close(0, "credential refused");
        }
      }),
    );
    env.runner.fork(renew(link, credentials, device));
    return link;
  });
}

/// Presents a fresh credential every RENEW_MS until the link closes; one not had or refused leaves the link to run
/// out, and the next `link` opens another.
function renew(link: Link, credentials: CredentialSource, device: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    for (;;) {
      const closed = yield* Effect.raceFirst(Effect.as(Effect.sleep(RENEW_MS), false), Effect.as(link.conn.closed(), true));
      if (closed) return;
      const renewed = yield* Effect.result(
        Effect.flatMap(credentials(device, false), (c) =>
          Effect.map(
            link.controlled((control) => control.exchange(c.credential)),
            () => {
              link.credential = c.credential;
            },
          ),
        ),
      );
      if (renewed._tag === "Failure") {
        link.renewalFailed = true;
        return;
      }
    }
  });
}

// ── the wire over mesh links (station/wire.rs `MeshWire`) ──

export function unconfirmed(why: CoreError): CoreError {
  return new CoreError("unconfirmed", t("station.core.unconfirmed", { why: why.message }));
}

function mayRepeat(head: RequestHead, idempotent: boolean): boolean {
  return head.method.toUpperCase() === "GET" || (idempotent && head.headers.some(([k]) => k.toLowerCase() === IDEMPOTENCY_KEY));
}

/// What the wire needs of the core: the mesh (brought up on first use), each workspace's credentials and waits.
export type MeshWireEnv = {
  mesh: () => Effect.Effect<Mesh, CoreError>;
  /// The mesh if it is up already.
  meshNow: () => Mesh | null;
  credentials: (workspace: string) => CredentialSource;
  status: (workspace: string) => import("./status.ts").Status;
};

export class MeshWire implements StationWire {
  readonly #env: MeshWireEnv;
  readonly #idempotent = new Set<string>();

  constructor(env: MeshWireEnv) {
    this.#env = env;
  }

  request(station: StationAddr, head: RequestHead, body: Uint8Array): Effect.Effect<WireReply, CoreError, import("effect").Scope.Scope> {
    const env = this.#env;
    const idempotent = this.#idempotent;
    const workspace = station.workspace;
    const id = station.station;
    const address = { station: station.toString() };
    return Effect.gen(function* () {
      const status = env.status(workspace);
      const credentials = env.credentials(workspace);
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, address, t("station.core.connecting"), mesh.link(id, credentials));
      const repeats = mayRepeat(head, idempotent.has(id));
      const write = !["GET", "HEAD"].includes(head.method.toUpperCase());
      const ask = (l: Link) => Effect.map(l.request(head, body), (reply) => [l, reply] as [Link, Reply]);
      let answered: [Link, Reply];
      if (repeats) {
        const first = yield* Effect.raceFirst(
          Effect.map(Effect.result(ask(link)), (r) => ({ asked: r }) as const),
          Effect.as(mesh.replaced(id, link), { replaced: true } as const),
        );
        if ("asked" in first) {
          const r = first.asked;
          if (r._tag === "Success") answered = r.success;
          else if (r.failure.code === "mesh" && write) {
            // A write gone and not answered: asked again with its key whenever its station is back, a while.
            const w = status.begin(address, RECHECKING(), true);
            const started = mesh.now();
            let pause = 1_000;
            answered = yield* Effect.gen(function* () {
              for (;;) {
                const again = yield* Effect.result(Effect.flatMap(mesh.link(id, credentials), ask));
                if (again._tag === "Success") return again.success;
                if (again.failure.code !== "mesh") return yield* Effect.fail(again.failure);
                if (mesh.now() - started >= RECHECK_MS) return yield* Effect.fail(unconfirmed(again.failure));
                yield* Effect.sleep(pause);
                pause = Math.min(pause * 2, 15_000);
              }
            }).pipe(Effect.ensuring(Effect.sync(() => w.end())));
          } else if (r.failure.code === "mesh") {
            const l = yield* waiting(status, address, t("station.core.connecting"), mesh.link(id, credentials));
            answered = yield* ask(l);
          } else return yield* Effect.fail(r.failure);
        } else {
          // Replaced while under way: asked again on the new one at once, the first answer taken.
          const again = Effect.flatMap(mesh.link(id, credentials), ask);
          answered = yield* firstAnswer(ask(link), again);
        }
      } else {
        const r = yield* Effect.result(ask(link));
        if (r._tag === "Failure") return yield* Effect.fail(write && r.failure.code === "mesh" ? unconfirmed(r.failure) : r.failure);
        answered = r.success;
      }
      const [l, reply] = answered;
      // Its stream goes with the scope it was asked in.
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      if (reply.headers.some(([k]) => k.toLowerCase() === IDEMPOTENT)) idempotent.add(id);
      return { status: reply.status, headers: reply.headers, body: reply.body, via: l.path() };
    });
  }

  reset(station: StationAddr): void {
    this.#env.meshNow()?.dropLink(station.station);
  }

  races(): boolean {
    return true;
  }

  replaced(station: StationAddr): Effect.Effect<void> {
    const mesh = this.#env.meshNow();
    const link = mesh?.current(station.station) ?? null;
    if (mesh === null || link === null) return Effect.never;
    return mesh.replaced(station.station, link);
  }

  net(station: StationAddr): LinkNet | null {
    const mesh = this.#env.meshNow();
    const link = mesh?.current(station.station) ?? null;
    if (mesh === null || link === null) return null;
    return { ...link.net(), measured: mesh.measured(station.station), today: mesh.today(station.station) };
  }

  measure(station: StationAddr): Effect.Effect<void, CoreError> {
    return Effect.flatMap(this.#env.mesh(), (mesh) => mesh.remeasure(station.station));
  }

  socket(station: StationAddr, head: RequestHead): Effect.Effect<WireSocket, CoreError, import("effect").Scope.Scope> {
    const env = this.#env;
    return Effect.gen(function* () {
      const status = env.status(station.workspace);
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, { station: station.toString() }, t("station.core.connecting"), mesh.link(station.station, env.credentials(station.workspace)));
      const [reply, send] = yield* link.socket(head);
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      return { reply: { status: reply.status, headers: reply.headers, body: reply.body, via: link.path() }, send };
    });
  }
}

/// Whichever of two attempts answers; one that fails leaves it to the other.
function firstAnswer<A>(a: Effect.Effect<A, CoreError>, b: Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
  return Effect.gen(function* () {
    const fa = yield* Effect.forkChild(Effect.result(a));
    const fb = yield* Effect.forkChild(Effect.result(b));
    const first = yield* Effect.raceFirst(Effect.map(Fiber.join(fa), (r) => ["a", r] as const), Effect.map(Fiber.join(fb), (r) => ["b", r] as const));
    if (first[1]._tag === "Success") return first[1].success;
    const other = yield* Fiber.join(first[0] === "a" ? fb : fa);
    if (other._tag === "Success") return other.success;
    return yield* Effect.fail(other.failure);
  });
}

/// An effect said to be waited on (status.ts) while it runs.
function waiting<A>(status: import("./status.ts").Status, place: import("./status.ts").Place, what: string, effect: Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
  return Effect.suspend(() => {
    const w = status.begin(place, what, true);
    return effect.pipe(Effect.ensuring(Effect.sync(() => w.end())));
  });
}

/// The core's mesh: brought up on first use with the relays any account's `/v1/me` names, the credentials from
/// still.fail cloud (kept on the device).
export function meshWire(inner: Inner): StationWire {
  let mesh: Deferred.Deferred<Mesh, CoreError> | null = null;
  let up: Mesh | null = null;
  const get = (): Effect.Effect<Mesh, CoreError> =>
    Effect.suspend(() => {
      const iroh = inner.iroh;
      if (iroh === null) return Effect.fail(new CoreError("mesh", t("core-logic.mesh.bind_failed", { error: "no iroh on this host" })));
      if (mesh !== null) return Deferred.await(mesh);
      const d = Deferred.makeUnsafe<Mesh, CoreError>();
      mesh = d;
      inner.runner.fork(
        Effect.gen(function* () {
          const made = yield* Effect.result(Effect.flatMap(inner.cloudSync.relaysNow(), (relays) => Mesh.make({ host: inner.host, runner: inner.runner, tracer: inner.tracer, iroh, wakes: inner.wakes }, relays)));
          if (made._tag === "Success") up = made.success;
          else mesh = null;
          Deferred.doneUnsafe(d, made._tag === "Success" ? Effect.succeed(made.success) : Effect.fail(made.failure));
        }),
      );
      return Deferred.await(d);
    });
  inner.mesh = get;
  inner.meshNow = () => up;
  return new MeshWire({
    mesh: get,
    meshNow: () => up,
    credentials: (workspace) => (device, fresh) => inner.cloudSync.credential(workspace, device, fresh, up?.deviceId() ?? null),
    status: (workspace) => inner.workspaces.of(workspace).status,
  });
}

