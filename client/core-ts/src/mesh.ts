// This device's iroh endpoint and its links to stations (mesh.rs), over the iroh a host gives (iroh.ts). One endpoint
// per core, its key the device key (storage `device`). A link is opened with this device's member credential for the
// station's workspace and presents it again every RENEW_MS on its control stream; a closed link is opened again on the
// next request. Wire format (station/src/mesh/serve.ts): ALPN `stillfail/admin/1` (or `ember/admin/1`); the first bi-stream
// carries `{"credential": …}` lines, each further bi-stream one request: a JSON head line `{method, path, headers}`
// then the body; the reply a JSON head line `{status, headers}` then the body, streamed.
//
// All of it runs as fibers (rule 1): an opening is a Deferred everyone asking for the station meanwhile waits on, a
// link's renewal and its first answer are fibers in the core's scope, a race and a hedge are fibers started as the UI
// comes back, measuring and the day's tally are fibers on the clock.
import { Clock, Deferred, Effect, Fiber, Semaphore } from "effect";
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
/// How often each way to a station is pinged (its credential presented again on it, answered by the station itself).
export const TICK_MS = 5_000;
/// A ping not answered by then counts as having taken this long, and as missed.
export const PING_TIMEOUT_MS = 3_000;
/// The ways kept open to a station: the one its requests go on, and the best of the others.
export const KEEP_WAYS = 2;
/// How often the ways not kept open are dialled again, to see whether one became better.
export const EXPLORE_MS = 5 * 60_000;
/// Pings a way needs answered before it is compared with another.
export const MIN_SAMPLES = 3;
/// Ticks in a row a way must be clearly better than the one requests go on before they move to it.
const BETTER_TICKS = 6;
/// How long requests stay on a way they moved to before they may move again (unless it is gone): a move restarts the
/// event stream and asks the reads under way again, and moving every few minutes between two ways near each other made
/// things worse than staying (2026-10-08).
export const MIN_STAY_MS = 3 * 60_000;
/// Pings in a row a way may miss before it is let go.
const DEAD_PINGS = 3;
/// The least a read waits for its answer on its way before it is asked on the next best way as well.
export const HEDGE_FLOOR_MS = 1_000;
/// How often a read gone slow looks again for another way to be asked on, while there is none.
const HEDGE_RECHECK_MS = 250;
export const NET_DAY_KEY = "net-day";
export const TALLY_EVERY_MS = 60_000;
export const SPEED_KEY = "relay-speed";
/// A reply this long or longer tells how fast a way is; a shorter one is mostly its round trip.
export const SPEED_MIN_BYTES = 512 * 1024;
/// What a way's speed is weighed with its round trip by: the time a larger reply (a page of history, an image) takes.
export const TYPICAL_BYTES = 256 * 1024;
/// How long the speed seen on a way counts; then it is found out again, from the replies that come through it.
export const SPEED_KEPT_MS = 6 * 3600_000;
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
/// The fastest a way to a station was seen bringing a reply (bytes a second), and when that was first seen.
type Speed = { bps: number; at: number };

/// A relay as a key: its URL as written out again, so `https://r` and `https://r/` are one.
function relayKey(relay: string): string {
  try {
    return new URL(relay).href;
  } catch {
    return relay;
  }
}

/// A relay as people see it named (views.ts relayName): its host, with its port when that is not the default one, so an
/// entry on a relay's machine (`https://39.105.157.122:8443`) is not taken for that relay.
function relayHost(relay: string): string {
  try {
    return new URL(relay).host || relay;
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

/// What a way costs, in ms: its round trip, and what a TYPICAL_BYTES reply takes to come through it at the speed it was
/// seen at (nothing while that is not known: it is found out once requests go that way).
export function cost(ms: number, bps: number | null): number {
  return bps !== null && bps > 0 ? ms + (TYPICAL_BYTES / bps) * 1000 : ms;
}

/// A way as compared with another: what a request is expected to take on it at worst, its round trip and what a
/// TYPICAL_BYTES reply takes to come (`cost`) and twice how much its round trips vary; and how much they vary.
export type Score = { score: number; dev: number };

/// What a way must be quicker by, at least, for requests to move to it: a move re-asks the reads under way and starts
/// the event stream again, worth it only for a gain a person could notice.
export const MOVE_GAIN = 0.3;

/// Whether `other` is clearly better than `cur`: expected quicker by MOVE_GAIN at least, and by more than what the two
/// vary by (half their deviations together), so two ways as good as each other are not swapped back and forth. A way
/// gone erratic scores worse at once by its deviation alone.
export function clearlyBetter(cur: Score, other: Score): boolean {
  return other.score <= cur.score * (1 - MOVE_GAIN) && other.score + (cur.dev + other.dev) / 2 < cur.score;
}

/// One way to a station: a link (on the main endpoint, or on one pinned to a relay) and how it has been answering: its
/// pings' round trips smoothed as TCP smooths its own (RFC 6298: the mean an eighth each time, the mean deviation a
/// quarter).
/// A ping is the link's credential presented again on its control stream, answered by the station: the whole way
/// there and back, the station included, on the connection requests go on. Not QUIC's own estimate, which starts from
/// the handshake (getting onto the relay included) and moves an eighth a keep-alive (2026-10-05).
export class Way {
  readonly link: Link;
  samples = 0;
  srtt = 0;
  dev = 0;
  /// Ticks in a row it was clearly better than the way requests go on.
  better = 0;
  /// Pings in a row not answered.
  missed = 0;
  /// A ping of it is under way (one not answered yet is not sent again over it).
  pinging = false;
  /// Its first ping answered: not counted, it carried the link's own start (its first streams, the station taking the
  /// credential), and smoothed an eighth at a time it kept a way just dialled looking slower than it is.
  warm = false;

  constructor(link: Link) {
    this.link = link;
  }

  note(ms: number): void {
    // Its deviation from nothing at first, not half the first round trip as RFC 6298 starts it (that is for a timeout,
    // kept long to be safe): a way just dialled scored twice its round trip and lost to one no quicker for minutes.
    if (this.samples === 0) {
      this.srtt = ms;
      this.dev = 0;
    } else {
      this.dev = 0.75 * this.dev + 0.25 * Math.abs(ms - this.srtt);
      this.srtt = 0.875 * this.srtt + 0.125 * ms;
    }
    this.samples++;
  }

  /// Where it goes: its relay (as a key), or "direct".
  key(): string {
    const via = this.link.via();
    if (via !== null) return relayKey(via);
    if (this.link.path() === "direct") return "direct";
    return this.link.pinned !== null ? relayKey(this.link.pinned) : "main";
  }
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
  /// Ways into a relay through another relay's machine (cloud relays.ts `relay_entries`): each dialled on an endpoint
  /// of its own and through it alone, never on the main endpoint. An entry is a relay already reached under another URL:
  /// on both, one key is on that relay twice, the connection made last taking the other's place, back and forth
  /// (2026-10-08: with the entries among their relays, phones' connects to any station failed one in five).
  readonly entries: string[];
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
  /// By station: the ways open to it (the link requests go on among them), each pinged every TICK_MS while it has any.
  readonly #ways = new Map<string, Way[]>();
  readonly #steering = new Set<string>();
  /// Ways let go, closed RETIRE_MS later (what is still coming on them comes meanwhile).
  readonly #retiring = new Set<Link>();
  readonly #exploring = new Set<string>();
  readonly #exploredAt = new Map<string, number>();
  /// Dials under way on pinned endpoints (their endpoints are not let go meanwhile).
  #dialing = 0;
  /// By station: the relay requests last moved to (its host), and how many times they moved.
  readonly #moved = new Map<string, string>();
  readonly #moves = new Map<string, number>();
  readonly #movedAt = new Map<string, number>();
  #closed = false;
  /// The relays a station's workspace has of its own, as the last `link` to it said.
  readonly #theirs = new Map<string, string[]>();
  #days: Record<string, Day>;
  #daysChanged = false;
  /// By station, then relay (`relayKey`): how fast replies came that way.
  readonly #speeds: Record<string, Record<string, Speed>>;

  private constructor(env: MeshEnv, relays: string[], entries: string[], endpoint: IrohEndpoint, secret: Uint8Array, days: Record<string, Day>, speeds: Record<string, Record<string, Speed>>) {
    this.#env = env;
    this.relays = relays;
    this.entries = entries;
    this.#endpoint = endpoint;
    this.#secret = secret;
    this.#days = days;
    this.#speeds = speeds;
  }

  /// Binds the endpoint with the stored device key (made and stored the first time). No relays binds without one.
  static make(env: MeshEnv, relays: string[], entries: string[] = []): Effect.Effect<Mesh, CoreError> {
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
      const speedsRaw = parseJson(yield* Effect.orElseSucceed(host.storageGet(SPEED_KEY), () => null)) as J;
      const speeds: Record<string, Record<string, Speed>> = speedsRaw !== null && typeof speedsRaw === "object" && !Array.isArray(speedsRaw) ? speedsRaw : {};
      const endpoint = yield* Mesh.#bind(env.iroh, secret, relays);
      const mesh = new Mesh(env, relays, entries.filter((e) => !relays.some((r) => sameRelay(r, e))), endpoint, secret, days, speeds);
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

  /// How fast replies from a station came through a relay lately (bytes a second); null if none long enough did.
  speed(stationId: string, relay: string): number | null {
    const s = this.#speeds[stationId]?.[relayKey(relay)];
    return s !== undefined && this.#env.host.nowMs() - s.at < SPEED_KEPT_MS ? s.bps : null;
  }

  /// A reply of `bytes` from a station came through `relay` in `ms` (from its first bytes to its end). The fastest seen
  /// counts: a reply also comes slower than its way could bring it (others at once, the station reading slowly).
  noteSpeed(stationId: string, relay: string, bytes: number, ms: number): void {
    if (bytes < SPEED_MIN_BYTES || ms <= 0) return;
    const bps = (bytes / ms) * 1000;
    const now = this.#env.host.nowMs();
    const of = (this.#speeds[stationId] ??= {});
    const key = relayKey(relay);
    const was = of[key];
    if (was !== undefined && now - was.at < SPEED_KEPT_MS && was.bps >= bps) return;
    of[key] = { bps, at: was !== undefined && now - was.at < SPEED_KEPT_MS ? was.at : now };
    for (const [id, relays] of Object.entries(this.#speeds)) {
      for (const [r, s] of Object.entries(relays)) if (now - s.at >= SPEED_KEPT_MS) delete relays[r];
      if (Object.keys(relays).length === 0) delete this.#speeds[id];
    }
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(SPEED_KEY, toJsonBytes(this.#speeds))));
  }

  /// A reply's body, timed as it is read: when it ends, how fast it came is noted for the relay it came through.
  timed(stationId: string, relay: string, body: Pull<Uint8Array>): Pull<Uint8Array> {
    let first: number | null = null;
    let bytes = 0;
    return {
      take: Effect.flatMap(body.take, (chunk) =>
        Effect.map(Clock.currentTimeMillis, (now) => {
          if (chunk === null) {
            if (first !== null) this.noteSpeed(stationId, relay, bytes, now - first);
          } else if (first === null) first = now;
          else bytes += chunk.length;
          return chunk;
        }),
      ),
    };
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
    this.#adopt(stationId, next);
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

  /// The relays a station is dialled and measured on: still.fail's, then its workspace's own. The endpoint stays bound
  /// to still.fail's alone (one that does not answer there would leave it with no home); another relay is reached as
  /// the station's, or on its own endpoint once measured quicker.
  relaysFor(stationId: string): string[] {
    const theirs = this.#theirs.get(stationId) ?? [];
    return [...this.relays, ...theirs.filter((r) => !this.relays.some((o) => sameRelay(o, r)))];
  }

  /// Every way a station is dialled through: its relays (`relaysFor`), then the entries (`entries`).
  #waysFor(stationId: string): string[] {
    const relays = this.relaysFor(stationId);
    return [...relays, ...this.entries.filter((e) => !relays.some((r) => sameRelay(r, e)))];
  }

  /// The link to a station, opening it (or opening again a closed one) with a credential from `credentials`; `theirs`:
  /// the relays its workspace has of its own.
  link(stationId: string, credentials: CredentialSource, theirs?: readonly string[]): Effect.Effect<Link, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (theirs !== undefined) this.#theirs.set(stationId, [...theirs]);
      const existing = this.#links.get(stationId);
      let fresh = false;
      if (existing) {
        if (existing.result === null) return yield* Deferred.await(existing.done);
        if ("ok" in existing.result) {
          if (existing.result.ok.usable()) return existing.result.ok;
          fresh = existing.result.ok.refused !== null;
        } else fresh = existing.result.err.code === "credential_refused";
      }
      // Gone, with another way still open: requests go on that one at once.
      if (!fresh && existing !== undefined) {
        const standby = this.#best(stationId, this.#live(stationId).filter((w) => w.missed === 0));
        if (standby !== null) {
          this.#promote(stationId, standby, "lost");
          return standby.link;
        }
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
      const first = this.#dialAll(stationId, endpoint, credentials, fresh, span.context);
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
          const via = link.success.via();
          if (via !== null) span.set("stillfail.via", relayHost(via));
        } else {
          if (link.failure.message === noAnswer()) self.#stuck = true;
          span.fail();
          span.set("error.type", link.failure.code);
          span.set("stillfail.relay", relayStatus(endpoint));
        }
        span.end();
        opening.result = link._tag === "Success" ? { ok: link.success } : { err: link.failure };
        if (link._tag === "Success") self.#adopt(stationId, link.success);
        Deferred.doneUnsafe(opening.done, link._tag === "Success" ? Effect.succeed(link.success) : Effect.fail(link.failure));
      });
      this.#env.runner.fork(run);
      return yield* Deferred.await(opening.done);
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
    for (const w of this.#ways.get(stationId) ?? []) w.link.conn.close(0, "woke");
    this.#ways.delete(stationId);
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
      for (const ways of this.#ways.values()) for (const w of ways) w.link.conn.close(0, "device key replaced");
      this.#ways.clear();
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

  /// The ways open to a station that are still up.
  #live(stationId: string): Way[] {
    const all = this.#ways.get(stationId);
    if (all === undefined) return [];
    const live = all.filter((w) => w.link.usable());
    for (const w of all) if (!live.includes(w)) w.link.close();
    if (live.length > 0) this.#ways.set(stationId, live);
    else this.#ways.delete(stationId);
    return live;
  }

  /// A way as compared with another (`clearlyBetter`).
  #score(stationId: string, way: Way): Score {
    const via = way.link.via();
    return { score: cost(way.srtt, via !== null ? this.speed(stationId, via) : null) + 2 * way.dev, dev: way.dev };
  }

  /// Of `ways`, the one scoring best (pinged at least once; none pinged yet: the first).
  #best(stationId: string, ways: Way[]): Way | null {
    let best: Way | null = null;
    for (const w of ways) {
      if (best === null) best = w;
      else if (w.samples > 0 && (best.samples === 0 || this.#score(stationId, w).score < this.#score(stationId, best).score)) best = w;
    }
    return best;
  }

  /// Dials the station every way at once: on the main endpoint (through any relay, or direct), and on each relay's own
  /// endpoint through that relay alone. The first through is the link; the others, as they come through, are ways to it
  /// as well (`#adopt`). Fails once all have, as the main endpoint's dial failed. A phone whose own relay could not
  /// reach the station (Beijing's, bft in Tokyo, 2026-10-08) waited out CONNECT_TIMEOUT_MS on it time after time.
  #dialAll(stationId: string, endpoint: IrohEndpoint, credentials: CredentialSource, fresh: boolean, ctx: unknown): Effect.Effect<Link, CoreError> {
    return Effect.suspend(() => {
      this.#exploredAt.set(stationId, this.now());
      const relays = this.relaysFor(stationId);
      const main = open(this.#env, endpoint, relays, stationId, credentials, fresh, null, ctx);
      const pinned = this.#pinnable(stationId).map((r) => this.#dialPinned(stationId, r, credentials, fresh, ctx));
      const self = this;
      const won = Deferred.makeUnsafe<Link, CoreError>();
      let left = 1 + pinned.length;
      let mainFailure: CoreError | null = null;
      [main, ...pinned].forEach((attempt, i) =>
        this.#env.runner.fork(
          Effect.gen(function* () {
            const r = yield* Effect.result(attempt);
            if (r._tag === "Success") {
              if (!Deferred.doneUnsafe(won, Effect.succeed(r.success))) self.#adopt(stationId, r.success);
              return;
            }
            if (i === 0) mainFailure = r.failure;
            if (--left === 0) Deferred.doneUnsafe(won, Effect.fail(mainFailure ?? r.failure));
          }),
        ),
      );
      return Deferred.await(won);
    });
  }

  /// The ways a station is dialled on each on an endpoint of its own: every relay and entry but still.fail's own relay
  /// (the first, on Cloudflare), which the main endpoint reaches already. It holds few connections, each a cost: one
  /// more a device filled it (2026-10-08: 429 to bft's keeper and to devices). None while there is one way or none.
  #pinnable(stationId: string): string[] {
    const ways = this.#waysFor(stationId);
    if (ways.length < 2) return [];
    const own = this.relays[0];
    return ways.filter((r) => own === undefined || !sameRelay(own, r));
  }

  /// A link through `relay` alone, on that relay's own endpoint (`#pinnedEndpoint`).
  #dialPinned(stationId: string, relay: string, credentials: CredentialSource, fresh: boolean, ctx: unknown): Effect.Effect<Link, CoreError> {
    return Effect.suspend(() => {
      this.#dialing++;
      return Effect.flatMap(this.#pinnedEndpoint(relay), (endpoint) =>
        endpoint === null ? Effect.fail(meshError(t("core-logic.mesh.unreachable", { error: relayHost(relay) }))) : open(this.#env, endpoint, [relay], stationId, credentials, fresh, relay, ctx),
      ).pipe(Effect.ensuring(Effect.sync(() => this.#dialing--)));
    });
  }

  /// `link` is a way to the station as well, if it is still wanted; pinged from now on.
  #adopt(stationId: string, link: Link): void {
    if (this.#closed || !this.#links.has(stationId)) {
      link.close();
      return;
    }
    const ways = this.#live(stationId);
    if (ways.some((w) => w.link === link)) return;
    this.#ways.set(stationId, [...ways, new Way(link)]);
    // One way there is all it has (no relays, or one): nothing to choose between.
    if (!this.#steering.has(stationId) && this.#waysFor(stationId).length >= 2) {
      this.#steering.add(stationId);
      this.#env.runner.fork(this.#steer(stationId));
    }
  }

  /// Requests to the station go on `way` from now on; the link they went on stays open as another way.
  #promote(stationId: string, way: Way, why: string): void {
    const before = this.current(stationId);
    if (before === way.link) return;
    const span = this.#env.tracer.span("mesh.route", Kind.Internal);
    span.set("stillfail.station", stationId);
    span.set("stillfail.why", why);
    const was = before !== null ? this.#live(stationId).find((w) => w.link === before) : undefined;
    if (was !== undefined) {
      span.set("stillfail.from", was.key());
      span.set("stillfail.from.score", Math.round(this.#score(stationId, was).score));
    }
    span.set("stillfail.to", way.key());
    span.set("stillfail.to.score", Math.round(this.#score(stationId, way).score));
    span.end();
    const done = Deferred.makeUnsafe<Link, CoreError>();
    Deferred.doneUnsafe(done, Effect.succeed(way.link));
    this.#links.set(stationId, { done, result: { ok: way.link } });
    if (before !== null) this.#count(stationId, before);
    const via = way.link.via();
    this.#moved.set(stationId, via !== null ? relayHost(via) : "direct");
    this.#moves.set(stationId, this.moves(stationId) + 1);
    this.#movedAt.set(stationId, this.now());
    for (const w of this.#live(stationId)) w.better = 0;
    this.#notify();
  }

  /// How many times requests to the station moved from one way to another.
  moves(stationId: string): number {
    return this.#moves.get(stationId) ?? 0;
  }

  /// The ways open to the station, the link requests go on among them.
  ways(stationId: string): Way[] {
    return this.#live(stationId);
  }

  /// Pings a way: its credential presented again on it, answered by the station. Not answered within PING_TIMEOUT_MS,
  /// it counts as that long, and as missed; one still not answered is not sent again over it meanwhile.
  #ping(way: Way): Effect.Effect<void> {
    return Effect.suspend(() => {
      if (way.pinging) {
        way.missed++;
        way.note(PING_TIMEOUT_MS);
        return Effect.void;
      }
      way.pinging = true;
      const link = way.link;
      const answered = Deferred.makeUnsafe<number | null>();
      this.#env.runner.fork(
        Effect.gen(function* () {
          const started = yield* Clock.currentTimeMillis;
          const r = yield* Effect.result(link.controlled((c) => c.exchange(link.credential)));
          const took = (yield* Clock.currentTimeMillis) - started;
          way.pinging = false;
          Deferred.doneUnsafe(answered, Effect.succeed(r._tag === "Success" ? took : null));
        }),
      );
      return Effect.map(Effect.raceFirst(Deferred.await(answered), Effect.as(Effect.sleep(PING_TIMEOUT_MS), null)), (ms) => {
        if (ms === null) {
          way.missed++;
          way.note(PING_TIMEOUT_MS);
        } else {
          way.missed = 0;
          if (way.warm) way.note(ms);
          way.warm = true;
        }
      });
    });
  }

  /// Every way to the station pinged at once.
  #sample(stationId: string): Effect.Effect<void> {
    return Effect.asVoid(Effect.all(this.#live(stationId).map((w) => this.#ping(w)), { concurrency: "unbounded" }));
  }

  /// Moves the station's requests to the best way if it is clearly better than theirs (`clearlyBetter`) BETTER_TICKS
  /// times in a row, or at once (`now`: as a person asks, as a read was answered on another way first); to the best
  /// way left at once if theirs is gone or missed DEAD_PINGS pings.
  #choose(stationId: string, now: boolean): void {
    const cur = this.current(stationId);
    if (cur === null && this.#links.get(stationId)?.result === null) return;
    const ways = this.#live(stationId);
    const up = ways.filter((w) => w.missed < DEAD_PINGS);
    const mine = ways.find((w) => w.link === cur);
    if (cur === null || !cur.usable() || mine === undefined || mine.missed >= DEAD_PINGS) {
      const best = this.#best(stationId, up.filter((w) => w.link !== cur));
      if (best !== null) this.#promote(stationId, best, "lost");
      return;
    }
    if (mine.samples < MIN_SAMPLES) return;
    if (!now && this.now() - (this.#movedAt.get(stationId) ?? -Infinity) < MIN_STAY_MS) return;
    const best = this.#best(stationId, up.filter((w) => w.link !== cur && w.samples >= MIN_SAMPLES));
    for (const w of ways) if (w !== best) w.better = 0;
    if (best === null) return;
    if (!clearlyBetter(this.#score(stationId, mine), this.#score(stationId, best))) {
      best.better = 0;
      return;
    }
    best.better++;
    if (now || best.better >= BETTER_TICKS) this.#promote(stationId, best, now ? "asked" : "better");
  }

  /// No more requests go on `way`; it is closed RETIRE_MS later, unless they went back to it meanwhile (replies under way
  /// on it come meanwhile: a large one, a read that just moved off it).
  #retire(stationId: string, way: Way): void {
    this.#ways.set(
      stationId,
      (this.#ways.get(stationId) ?? []).filter((w) => w !== way),
    );
    this.#retiring.add(way.link);
    this.#env.runner.fork(
      Effect.andThen(
        Effect.sleep(RETIRE_MS),
        Effect.sync(() => {
          this.#retiring.delete(way.link);
          if (this.#isCurrent(stationId, way.link)) return;
          way.link.close();
          this.#count(stationId, way.link);
          this.#env.runner.fork(this.#letGo());
        }),
      ),
    );
  }

  /// Lets go of the ways not worth keeping: one that missed DEAD_PINGS pings, one of two going the same way, and past
  /// KEEP_WAYS the worst of those pinged MIN_SAMPLES times (never the one requests go on).
  #prune(stationId: string): void {
    const cur = this.current(stationId);
    for (const w of this.#live(stationId)) if (w.link !== cur && w.missed >= DEAD_PINGS) this.#retire(stationId, w);
    const byKey = new Map<string, Way>();
    for (const w of this.#live(stationId)) {
      const k = w.key();
      const other = byKey.get(k);
      if (other === undefined) {
        byKey.set(k, w);
        continue;
      }
      const keep = other.link === cur ? other : w.link === cur ? w : this.#score(stationId, w).score < this.#score(stationId, other).score ? w : other;
      this.#retire(stationId, keep === w ? other : w);
      byKey.set(k, keep);
    }
    const others = this.#live(stationId)
      .filter((w) => w.link !== cur && w.samples >= MIN_SAMPLES)
      .sort((a, b) => this.#score(stationId, a).score - this.#score(stationId, b).score);
    for (const w of others.slice(Math.max(0, KEEP_WAYS - 1))) this.#retire(stationId, w);
  }

  /// Dials the station on the ways not open to it (the main endpoint, each relay's own), each come through a way.
  #explore(stationId: string, credentials: CredentialSource): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#exploring.has(stationId)) return;
      this.#exploring.add(stationId);
      this.#exploredAt.set(stationId, this.now());
      const have = new Set(this.#live(stationId).map((w) => w.link.pinned ?? "main"));
      const relays = this.relaysFor(stationId);
      const tries: Effect.Effect<Link, CoreError>[] = [];
      if (!have.has("main")) tries.push(open(this.#env, this.#endpoint, relays, stationId, credentials, false, null, undefined));
      for (const r of this.#pinnable(stationId)) if (!have.has(r)) tries.push(this.#dialPinned(stationId, r, credentials, false, undefined));
      yield* Effect.all(
        tries.map((attempt) => Effect.map(Effect.result(attempt), (r) => (r._tag === "Success" ? this.#adopt(stationId, r.success) : undefined))),
        { concurrency: "unbounded" },
      );
      this.#exploring.delete(stationId);
    });
  }

  /// While the station has a way open: every TICK_MS each pinged, the requests moved to the best (`#choose`), the
  /// ways not worth keeping let go (`#prune`), and every EXPLORE_MS the others dialled again (`#explore`).
  #steer(stationId: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        yield* Effect.sleep(TICK_MS);
        if (this.#closed || !this.#links.has(stationId)) break;
        const cur = this.current(stationId);
        if (this.#live(stationId).length === 0 && (cur === null || !cur.usable())) break;
        yield* this.#sample(stationId);
        this.#choose(stationId, false);
        this.#prune(stationId);
        const credentials = (this.current(stationId) ?? this.#live(stationId)[0]?.link)?.credentials;
        if (credentials !== undefined && this.now() - (this.#exploredAt.get(stationId) ?? 0) >= EXPLORE_MS) this.#env.runner.fork(this.#explore(stationId, credentials));
      }
      this.#steering.delete(stationId);
    });
  }

  /// The way a read slow on `link` is asked on as well: the best other way open, going another way than `link` (not the
  /// main endpoint through the same relay), whose last ping was answered (one not pinged yet: its handshake was).
  standby(stationId: string, link: Link): Link | null {
    const ways = this.#live(stationId);
    const key = ways.find((w) => w.link === link)?.key() ?? null;
    return this.#best(stationId, ways.filter((w) => w.link !== link && w.missed === 0 && w.key() !== key))?.link ?? null;
  }

  /// How long a read on `link` waits for its answer before it is asked on another way as well: what its way is expected
  /// to take at worst, and twice its deviation more; HEDGE_FLOOR_MS at least (the station's own time to answer).
  hedgeAfter(stationId: string, link: Link): number {
    const w = this.#live(stationId).find((x) => x.link === link);
    if (w === undefined || w.samples === 0) return HEDGE_FLOOR_MS;
    const s = this.#score(stationId, w);
    return Math.max(HEDGE_FLOOR_MS, s.score + 2 * s.dev);
  }

  /// A read asked on `slow` and then on another way as well was answered on the other first, `ms` after it was asked on
  /// `slow`: that long counts as a ping of `slow` (the requests move as the pings decide, not on one read).
  outran(stationId: string, slow: Link, ms: number): void {
    this.#live(stationId).find((x) => x.link === slow)?.note(ms);
  }

  /// Every way to the station as pinged: the round trip of each way open (its relay's host, or "direct"), then each
  /// relay with no way open on it now (not reached, or let go: no figure).
  measured(stationId: string): Measured | null {
    const ways = this.#live(stationId).filter((w) => w.samples > 0);
    const measuring = this.#exploring.has(stationId);
    if (ways.length === 0 && !measuring) return null;
    const relays: [string, number | null][] = [];
    const seen = new Set<string>();
    for (const w of [...ways].sort((a, b) => a.srtt - b.srtt)) {
      const key = w.key();
      if (seen.has(key)) continue;
      seen.add(key);
      const via = w.link.via();
      relays.push([via !== null ? relayHost(via) : "direct", Math.round(w.srtt)]);
    }
    for (const r of this.#waysFor(stationId)) if (!seen.has(relayKey(r))) relays.push([relayHost(r), null]);
    return { measuring, relays, moved: this.#moved.get(stationId) ?? null };
  }

  /// The ways to a station dialled and pinged now, as a person asks; the requests moved to the best if it is clearly
  /// better.
  remeasure(stationId: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.current(stationId);
      if (link === null || !link.usable()) return yield* Effect.fail(meshError(t("core-logic.mesh.not_connected")));
      yield* this.#explore(stationId, link.credentials);
      for (let i = 0; i <= MIN_SAMPLES; i++) yield* this.#sample(stationId);
      this.#choose(stationId, true);
      this.#prune(stationId);
    });
  }

  /// The endpoint on `relay` alone: relay-only, no lookups, no IP transports. With lookups it found where a station was
  /// at home and went onto that relay too, and with an entry that was the same relay under two URLs, one key on it twice
  /// (2026-10-08); with IP transports, a way said to go through a relay went direct.
  #pinnedEndpoint(relay: string): Effect.Effect<IrohEndpoint | null> {
    return Effect.gen({ self: this }, function* () {
      const existing = this.#pinned.get(relay);
      if (existing) return yield* Deferred.await(existing);
      const d = Deferred.makeUnsafe<IrohEndpoint | null>();
      this.#pinned.set(relay, d);
      const bound = yield* Effect.result(Mesh.#bind(this.#env.iroh, pinnedKey(this.#secret, relay), [relay], true));
      const endpoint = bound._tag === "Success" ? bound.success : null;
      Deferred.doneUnsafe(d, Effect.succeed(endpoint));
      if (endpoint === null) this.#pinned.delete(relay);
      return endpoint;
    });
  }

  /// Closes the pinned endpoints no way is on, unless something is being dialled meanwhile.
  #letGo(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#dialing > 0) return;
      const used = new Set<string>();
      for (const ways of this.#ways.values()) for (const w of ways) if (w.link.pinned !== null && w.link.usable()) used.add(w.link.pinned);
      for (const [, l] of this.#openLinks()) if (l.pinned !== null) used.add(l.pinned);
      for (const l of this.#retiring) if (l.pinned !== null && l.usable()) used.add(l.pinned);
      for (const [relay, d] of [...this.#pinned]) {
        if (used.has(relay)) continue;
        this.#pinned.delete(relay);
        const e = yield* Deferred.await(d);
        if (e) this.#env.runner.fork(e.close());
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
      const opened = yield* Effect.result(this.#dialAll(id, endpoint, credentials, false, span.context));
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
      const fresh = Effect.result(this.#dialAll(id, this.#endpoint, old.credentials, false, span.context));
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
      this.#closed = true;
      for (const [, o] of this.#links) if (o.result && "ok" in o.result) o.result.ok.close();
      this.#links.clear();
      for (const ways of this.#ways.values()) for (const w of ways) w.link.close();
      this.#ways.clear();
      for (const l of this.#retiring) l.close();
      this.#retiring.clear();
      for (const [, d] of [...this.#pinned]) {
        const e = yield* Deferred.await(d);
        if (e) yield* e.close();
      }
      this.#pinned.clear();
      yield* this.#endpoint.close();
    });
  }
}

function relayStatus(endpoint: IrohEndpoint): string {
  const status = endpoint.relayStatus();
  if (status.length === 0) return "none";
  return status.map((s) => `${s.url} ${s.connected ? "up" : "down"}`).join(", ");
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
    // Dialled on its own, so a connection made after CONNECT_TIMEOUT_MS is closed rather than left open, unused.
    const dialled = Deferred.makeUnsafe<IrohConnection, CoreError>();
    let late = false;
    env.runner.fork(
      Effect.gen(function* () {
        const r = yield* Effect.result(endpoint.connect({ id: stationId, relays }, ALPN, [FORMER_ALPN]));
        if (r._tag === "Success" && late) r.success.close(0, "too late");
        else Deferred.doneUnsafe(dialled, r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(meshError(t("core-logic.mesh.unreachable", { error: r.failure.message }))));
      }),
    );
    const connecting = Effect.raceFirst(
      Deferred.await(dialled),
      Effect.andThen(
        Effect.sleep(CONNECT_TIMEOUT_MS),
        Effect.suspend(() => {
          late = true;
          return Effect.fail(meshError(noAnswer()));
        }),
      ),
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
  /// The relays a workspace has of its own (`Mesh.link`).
  relays: (workspace: string) => string[];
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
      const theirs = env.relays(workspace);
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, address, t("station.core.connecting"), mesh.link(id, credentials, theirs));
      const repeats = mayRepeat(head, idempotent.has(id));
      const write = !["GET", "HEAD"].includes(head.method.toUpperCase());
      const ask = (l: Link) => Effect.map(l.request(head, body), (reply) => [l, reply] as [Link, Reply]);
      let answered: [Link, Reply];
      if (repeats) {
        // Asked on its link; on another way as well if not answered within what its way is expected to take
        // (`hedgeAfter`), or on the link put in its place if its link is replaced meanwhile: the first answer taken.
        const started = mesh.now();
        const asked = yield* Effect.forkChild(Effect.result(ask(link)));
        const answer = Effect.flatMap(Fiber.join(asked), (r) => (r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(r.failure)));
        // The other way, as there is one by then (the ways dialled with the link may come through after it).
        const slow = Effect.gen(function* () {
          yield* Effect.sleep(mesh.hedgeAfter(id, link));
          for (;;) {
            const standby = mesh.standby(id, link);
            if (standby !== null) return { slow: standby } as const;
            yield* Effect.sleep(HEDGE_RECHECK_MS);
          }
        });
        const first = yield* Effect.raceAllFirst([Effect.map(Fiber.join(asked), (r) => ({ asked: r }) as const), Effect.as(mesh.replaced(id, link), { replaced: true } as const), slow]);
        if ("asked" in first) {
          const r = first.asked;
          if (r._tag === "Success") answered = r.success;
          else if (r.failure.code === "mesh" && write) {
            // A write gone and not answered: asked again with its key whenever its station is back, a while.
            const w = status.begin(address, RECHECKING(), true);
            let pause = 1_000;
            answered = yield* Effect.gen(function* () {
              for (;;) {
                const again = yield* Effect.result(Effect.flatMap(mesh.link(id, credentials, theirs), ask));
                if (again._tag === "Success") return again.success;
                if (again.failure.code !== "mesh") return yield* Effect.fail(again.failure);
                if (mesh.now() - started >= RECHECK_MS) return yield* Effect.fail(unconfirmed(again.failure));
                yield* Effect.sleep(pause);
                pause = Math.min(pause * 2, 15_000);
              }
            }).pipe(Effect.ensuring(Effect.sync(() => w.end())));
          } else if (r.failure.code === "mesh") {
            const l = yield* waiting(status, address, t("station.core.connecting"), mesh.link(id, credentials, theirs));
            answered = yield* ask(l);
          } else return yield* Effect.fail(r.failure);
        } else if ("replaced" in first) {
          // Replaced while under way: asked again on the new one at once, the first answer taken.
          const again = Effect.flatMap(mesh.link(id, credentials, theirs), ask);
          answered = yield* firstAnswer(answer, again);
        } else {
          // Slow on its way: asked on the next best as well. Answered there first, its way is told how long it kept it.
          answered = yield* firstAnswer(answer, ask(first.slow));
          if (answered[0] !== link) mesh.outran(id, link, mesh.now() - started);
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
      const relay = l.path() === "relay" ? l.via() : null;
      // How fast it comes tells how fast that way is; not an event stream's, which comes as things happen.
      const streams = head.headers.some(([k, v]) => k.toLowerCase() === "accept" && v.includes("text/event-stream"));
      const timed = relay !== null && !streams ? mesh.timed(id, relay, reply.body) : reply.body;
      return { status: reply.status, headers: reply.headers, body: timed, via: l.path(), relay: relay !== null ? relayHost(relay) : null };
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
      const link = yield* waiting(status, { station: station.toString() }, t("station.core.connecting"), mesh.link(station.station, env.credentials(station.workspace), env.relays(station.workspace)));
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
          const made = yield* Effect.result(
            Effect.flatMap(inner.cloudSync.relaysNow(), (relays) => Mesh.make({ host: inner.host, runner: inner.runner, tracer: inner.tracer, iroh, wakes: inner.wakes }, relays, inner.cloudSync.entriesNow())),
          );
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
    relays: (workspace) => inner.cloudSync.workspaceRelays(workspace),
    status: (workspace) => inner.workspaces.of(workspace).status,
  });
}

