// This device's iroh endpoint and its links to stations (mesh.rs), over the iroh a host gives (iroh.ts). One endpoint
// per core, its key the device key (storage `device`). A link is to a station's address, `<workspace>/<station>`: a
// station in several workspaces has a link in each (docs/multi-workspace.md), dialled to the same station id. A link is
// opened with this device's member credential for its address's workspace and presents it again every RENEW_MS on its
// control stream; a closed link is opened again on the next request. Wire format (station/src/mesh/serve.ts): ALPN `stillfail/admin/1` (or `ember/admin/1`); the first bi-stream
// carries `{"credential": …}` lines, each further bi-stream one request: a JSON head line `{method, path, headers}`
// then the body; the reply a JSON head line `{status, headers}` then the body, streamed.
//
// All of it runs as fibers (rule 1): an opening is a Deferred everyone asking for the same address meanwhile waits on, a
// link's renewal and its first answer are fibers in the core's scope, a race and a hedge are fibers started as the UI
// comes back, measuring and the day's tally are fibers on the clock.
import { Clock, Deferred, Effect, Fiber, type Result, Semaphore } from "effect";
import type { Credential } from "./cloud.ts";
import type { Inner } from "./core.ts";
import { CoreError, asCoreError, failedIn } from "./error.ts";
import type { Host, Pull } from "./host.ts";
import { t } from "./i18n.ts";
import type { CloseReason, Iroh, IrohConnection, IrohEndpoint, IrohStream } from "./iroh.ts";
import * as format from "./format.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { RECHECKING } from "./station/words.ts";
import { StationAddr, stationId } from "./station/addr.ts";
import { IDEMPOTENCY_KEY, IDEMPOTENT, READS } from "./station/requests.ts";
import type { LinkNet, RequestHead, ScreenAsk, SocketOut, StationWire, WireReply, WireSocket } from "./station/wire.ts";
import { RELAY } from "./status.ts";
import { Kind, route, type SpanContext, type Tracer } from "./trace.ts";
import { fromUtf8, hex, parseJson, sha256, toJsonBytes, utf8 } from "./util.ts";
import { type LockClaim, lockClaim } from "./lock.ts";
import { PAIR_ALPN } from "./pair.ts";
import { hooks } from "./core/execute.ts";
import type { Wakes } from "./wake.ts";

// deno-lint-ignore no-explicit-any
type J = any;

export const DEVICE_KEY = "device";
export const ALPN = utf8("stillfail/admin/1");
export const FORMER_ALPN = utf8("ember/admin/1");
export const RENEW_MS = 5 * 60_000;
export const CONNECT_TIMEOUT_MS = 10_000;
/// How long a dial waits for its endpoint to get onto a relay before its CONNECT_TIMEOUT_MS counts all the same
/// (`onARelay`), and how often it looks.
export const ONTO_MAX_MS = 30_000;
const ONTO_RECHECK_MS = 250;
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
/// How often the main endpoint dials a station again whose link on it is gone, while the station was reached direct
/// within DIRECT_RECALL_MS: only it can go direct (each relay's own endpoint is on that relay alone), and waiting out
/// EXPLORE_MS kept a phone on the station's LAN on a relay for minutes after a link of it went quiet (2026-10-17).
export const REDIAL_MAIN_MS = 30_000;
export const DIRECT_RECALL_MS = 10 * 60_000;
/// The `pinned` of a link on the endpoint that dials a station by its LAN addresses alone (docs/mesh-lan.md): no relay,
/// no hole punching. A path iroh punched through to a station on the LAN stopped answering seconds after it opened, and
/// requests on it waited out iroh's 15 s before going back to a relay (studio and a phone, 2026-10-17); a connection
/// dialled by address kept working.
export const LAN = "lan";
/// The `pinned` of a link on the endpoint that dials a station at its Tailscale addresses alone (docs/mesh-lan.md,
/// Tailscale): as the LAN endpoint, no relay and no hole punching, Tailscale carrying it however it does (straight, or
/// through relays of its own when it could not punch through). So it is not taken over the others as a LAN way is: it
/// is compared by how it answers, as a relay's way is.
export const TAILNET = "tailnet";
/// The ways dialled at addresses the station said, each on an endpoint of its own.
export const AT_ADDRESSES = [LAN, TAILNET] as const;
export type AtAddresses = (typeof AT_ADDRESSES)[number];
/// What a workspace turns off (its `ways_off`) to keep its devices off a path iroh punches through: the main endpoint's.
export const DIRECT = "direct";
/// Where each station said a device dials it straight (by address: `{lan, tailnet}`), kept: a run dials them at once,
/// before any relay brought the station's answer (one whose relays cannot be reached is reached on them alone).
export const SAID_KEY = "station-addresses";
/// A way direct (on the LAN endpoint, or the main endpoint's punched path) lost within MIN_STAY_MS of the requests moving
/// to it, FLAKY_LOSSES times in a row: no way direct is moved to for DIRECT_HOLD_MS, twice as long each time it happens
/// again, up to DIRECT_HOLD_MAX_MS, unless no other way is up. A phone on studio's LAN moved to it and back to a relay
/// every minute or so, each time its requests waiting out DEAD_PINGS pings on the way gone quiet (2026-10-18).
const FLAKY_LOSSES = 2;
export const DIRECT_HOLD_MS = 2 * 60_000;
export const DIRECT_HOLD_MAX_MS = 30 * 60_000;
/// While a way on the LAN endpoint answered within this long, the requests keep off the main endpoint unless no other
/// way is up: the LAN way is enough, and the main endpoint's link would only punch one more path to the station
/// (docs/mesh-lan.md).
export const LAN_RECALL_MS = DIRECT_RECALL_MS;
/// The least a read waits for its answer on its way before it is asked on the next best way as well.
export const HEDGE_FLOOR_MS = 1_000;
/// How often a read gone slow looks again for another way to be asked on, while there is none.
const HEDGE_RECHECK_MS = 250;
/// How much of a request's body goes on a stream at a time when how far it has gone is told of (a part is 4 MB).
export const BODY_STEP = 64 * 1024;
export const NET_DAY_KEY = "net-day";
export const TALLY_EVERY_MS = 60_000;
export const SPEED_KEY = "relay-speed";
/// A reply this long or longer tells how fast a way is; a shorter one is mostly its round trip.
export const SPEED_MIN_BYTES = 512 * 1024;
/// What a way's speed is weighed with its round trip by: the time a larger reply (a page of history, an image) takes.
export const TYPICAL_BYTES = 256 * 1024;
/// How long the speed seen on a way counts; then it is found out again, from the replies that come through it.
export const SPEED_KEPT_MS = 6 * 3600_000;
/// How long the fastest a way was seen at holds against slower replies after it (one slower that came beside others on
/// the way, or as the station read slowly); past it, a slower reply says how fast the way is now: it got slower (a
/// line more crowded, a hop further), and is no longer taken to be as fast as it once was.
export const SPEED_FRESH_MS = 10 * 60_000;
/// How often a way's speed is told to telemetry (`mesh.speed`) at most, for each station and relay: how fast each
/// relay brings replies to devices, beside the network the device is on (the cloud adds it, docs/telemetry.md), is how
/// the relays are compared; one a minute is enough for that, and a video's every part would be far too many.
export const SPEED_SAID_MS = 60_000;
/// A reply head is a line of JSON; anything longer is not a station talking.
const MAX_HEAD = 64 * 1024;
/// How many links in a row a read is asked again on when each is found gone under it.
const LOST_TRIES = 3;
/// How long a write gone unanswered is asked again with its key (station.rs RECHECK_MS).
export const RECHECK_MS = 5 * 60 * 1000;

const noAnswer = () => t("core-logic.mesh.no_answer");
const meshError = (message: string) => new CoreError("mesh", message);
/// A connection that failed under the transport (refused, reset, lost on the way): said to people as where it failed
/// (`unreached` dialling, `cut` once it was up), what the transport said kept as its `cause` for telemetry, not shown.
const transportError = (key: "core-logic.mesh.unreached" | "core-logic.mesh.cut") => (e: { message: string }) => {
  const error = meshError(t(key));
  error.cause = e.message;
  return error;
};
const unreached = transportError("core-logic.mesh.unreached");
const cut = transportError("core-logic.mesh.cut");

/// This device's credential for a workspace, for the device's endpoint id; `fresh` asks for a new one.
export type CredentialSource = (device: string, fresh: boolean) => Effect.Effect<Credential, CoreError>;

/// The ways to a station as last measured.
export type Measured = { measuring: boolean; relays: [string, number | null][]; moved: string | null };

type Day = { day: number; rx: number; tx: number };
/// Where a station said a device dials it straight, each kind of way's addresses (`ip:port`).
type Said = Record<AtAddresses, string[]>;
/// A kind of way's key for a station address, in the maps of dials at addresses.
const atKey = (kind: AtAddresses, addr: string) => `${kind} ${addr}`;
/// How fast a way to a station was seen bringing a reply (bytes a second; the fastest within SPEED_FRESH_MS of it), and
/// when.
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
  /// Its link's paths as the last tick saw them (`Link.paths`), and which they were (`Link.pathShape`): `Mesh.#watchPaths`.
  saw: string | null = null;
  shape: string | null = null;

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

  /// Where it goes: its relay (as a key), "lan" (the LAN endpoint's), "tailnet" (the Tailscale endpoint's), or
  /// "direct" (a path iroh punched).
  key(): string {
    if (this.link.pinned === LAN || this.link.pinned === TAILNET) return this.link.pinned;
    const via = this.link.via();
    if (via !== null) return relayKey(via);
    if (this.link.path() === "direct") return "direct";
    return this.link.pinned !== null ? relayKey(this.link.pinned) : "main";
  }
}

/// Why a station takes none of the workspace's members for a security mode (its hello's `lock_station` `why`): the lock
/// it joined with not brought yet, this workspace locked after it joined, or its own workspace locked and this one not.
function lockStationWords(why: unknown, reason: string): string {
  if (why === "pending" || why === "unpinned" || why === "home") return t(`core-logic.mesh.lock_station.${why}`);
  return t("core-logic.mesh.credential_refused_why", { reason });
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
  return t("core-logic.mesh.cut");
}

/// Reads lines off a stream, keeping what followed.
export class Lines {
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
        const chunk = yield* Effect.mapError(this.#stream.read(), cut);
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

  /// `lock`: the device's claim for this endpoint (lock.ts), said in the first line, for a station with a workspace lock.
  /// `traceparent`: the dial's (`mesh.connect`), which the station says with the connection on its log, so the two
  /// records of one connection are found together.
  send(credential: string, lock?: LockClaim, traceparent?: string): Effect.Effect<void, CoreError> {
    const line = utf8(`${JSON.stringify({ credential, protocol: 2, ...(lock ? { lock } : {}), ...(traceparent ? { traceparent } : {}) })}\n`);
    return Effect.mapError(this.stream.write(line), cut);
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
        // A station with a workspace lock that does not know this device yet: it waits to be confirmed (lock.ts).
        if (answer.code === "lock_unconfirmed") return yield* Effect.fail(new LockUnconfirmed(t("core-logic.mesh.lock_unconfirmed", { reason }), answer.lock ?? null));
        // A station that takes none of this workspace's members for a security mode, its own or this workspace's not
        // brought to it yet (station/src/cloud/state.ts `leftOut`): why, as it said.
        if (answer.code === "lock_station") return yield* Effect.fail(new CoreError("lock_station", lockStationWords(answer.why, reason)));
        return yield* Effect.fail(new CoreError("credential_refused", t("core-logic.mesh.credential_refused_why", { reason })));
      }
      return answer;
    });
  }

  exchange(credential: string): Effect.Effect<J, CoreError> {
    return Effect.andThen(this.send(credential), this.answer());
  }
}

/// A station's refusal of this device for its workspace lock, with how far its own lock goes (`lock`, as it said).
export class LockUnconfirmed extends CoreError {
  readonly lock: unknown;
  constructor(message: string, lock: unknown) {
    super("lock_unconfirmed", message);
    this.lock = lock;
  }
}

/// A station's reply: its head, and its body as it comes (what came with the head line first).
export type Reply = {
  status: number;
  headers: [string, string][];
  body: Pull<Uint8Array>;
  /// Lets go of it: the stream is stopped both ways (what is not read any more, the station stops sending).
  cancel(): void;
  /// A screen view's body read by the host from here (IrohStream.tap), before any of it was taken; false where it is
  /// not (the host's has none, or it was read already).
  tap?: (call: number) => Effect.Effect<boolean>;
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
  /// The relay whose own endpoint it is on (LAN, TAILNET: the one dialling stations at their addresses on their LAN, on
  /// their tailnet); null on the main one.
  readonly pinned: string | null;
  counted: [number, number] = [0, 0];
  /// Where the station said a device on its LAN, on its tailnet, dials it (`ip:port`), in its answer to the first
  /// credential.
  lan: string[] = [];
  tailnet: string[] = [];
  /// Done once the station answered the first credential (refused or not).
  readonly answered = Deferred.makeUnsafe<void>();
  /// How its opening went (`open`): ms from its start until the endpoint was on a relay, the connection was made, and
  /// the credential was had; the first credential went as the later of the last two came.
  opened: { onto: number; dialled: number; credential: number } | null = null;

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

  /// A request's stream, its head and body sent and its reply's head read. Given up before that head (its asker gone, a
  /// read let go of; or failed), the stream goes at once: the station stops what it is sending on it, which no one
  /// would read.
  #open(head: J, finish: boolean, body: Uint8Array | null, wrote?: (sent: number) => void): Effect.Effect<[IrohStream, Lines, J], CoreError> {
    let opened: IrohStream | null = null;
    return Effect.gen({ self: this }, function* () {
      const stream = (opened = yield* Effect.mapError(this.conn.openBi(), cut));
      yield* Effect.mapError(stream.write(utf8(`${JSON.stringify(head)}\n`)), cut);
      // A body that is told of goes a step at a time, each said as the stream takes it (as far as the link lets it).
      if (body !== null && body.length > 0 && wrote) {
        for (let at = 0; at < body.length; at += BODY_STEP) {
          const end = Math.min(at + BODY_STEP, body.length);
          yield* Effect.mapError(stream.write(body.subarray(at, end)), cut);
          wrote(end);
        }
      } else if (body !== null && body.length > 0) yield* Effect.mapError(stream.write(body), cut);
      if (finish) yield* Effect.mapError(stream.finish(), cut);
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
    }).pipe(Effect.onExit((exit) => (exit._tag === "Success" ? Effect.void : Effect.sync(() => opened?.reset(0)))));
  }

  static #body(stream: IrohStream, lines: Lines): Pull<Uint8Array> & { claim(): Uint8Array | null; restore(prefix: Uint8Array): void } {
    let carry: Uint8Array | null = lines.carry.length > 0 ? lines.carry : null;
    let done = false;
    let started = false;
    return {
      // what came past the reply, none of it taken yet (null once it was): the host's to read from (IrohStream.tap)
      claim: () => {
        if (started) return null;
        const c = carry ?? new Uint8Array(0);
        carry = null;
        return c;
      },
      restore: (prefix) => {
        carry = prefix.length > 0 ? prefix : null;
      },
      take: Effect.suspend(() => {
        started = true;
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

  /// One request on its own stream; `wrote`: how much of its body has gone, as it goes.
  request(head: RequestHead, body: Uint8Array, wrote?: (sent: number) => void): Effect.Effect<Reply, CoreError> {
    const wire = { method: head.method, path: head.path, headers: Object.fromEntries(head.headers) };
    return Effect.mapError(
      Effect.map(this.#open(wire, true, body, wrote), ([stream, lines, reply]) => ({ status: reply.status, headers: headersOf(reply.headers), body: Link.#body(stream, lines), cancel: () => stream.reset(0) })),
      (e) => this.refused ?? e,
    );
  }

  /// A preview page's WebSocket on its own stream: the stream stays open both ways.
  socket(head: RequestHead): Effect.Effect<[Reply, SocketOut], CoreError> {
    return this.#duplex({ method: head.method, path: head.path, headers: Object.fromEntries(head.headers), socket: true });
  }

  /// A view of one of the station's screens (docs/remote-screens.md): its head line carries `screen`, and the stream
  /// stays open both ways for the frames.
  screen(head: RequestHead, screen: J): Effect.Effect<[Reply, SocketOut], CoreError> {
    return this.#duplex({ method: head.method, path: head.path, headers: Object.fromEntries(head.headers), screen });
  }

  #duplex(wire: J): Effect.Effect<[Reply, SocketOut], CoreError> {
    return Effect.map(this.#open(wire, false, null), ([stream, lines, reply]) => {
      const out: SocketOut = {
        write: (bytes) => Effect.mapError(stream.write(bytes), cut),
        finish: () => void Effect.runFork(Effect.ignore(stream.finish())),
      };
      const body = Link.#body(stream, lines);
      const tapping = stream.tap;
      // (what came past the reply goes to the host with it, so it reads the frames from their start)
      const tap =
        tapping === undefined
          ? undefined
          : (call: number) =>
              Effect.suspend(() => {
                const prefix = body.claim();
                if (prefix === null) return Effect.succeed(false);
                return Effect.map(Effect.orElseSucceed(tapping.call(stream, call, prefix), () => false), (tapped) => {
                  if (!tapped) body.restore(prefix);
                  return tapped;
                });
              });
      return [{ status: reply.status, headers: headersOf(reply.headers), body, cancel: () => stream.reset(0), tap }, out] as [Reply, SocketOut];
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

  /// Every way iroh has for it, as a span says them: `*` the one chosen, then where it goes (a relay's host, or a direct
  /// way's address), its round trip, the packets sent and lost on it. What a phone's direct way was, and how it went,
  /// as requests moved off it (2026-10-17: gone 20–30 s after it was taken, on a phone alone).
  paths(): string {
    return this.conn
      .paths()
      .map((p) => `${p.selected ? "*" : ""}${p.relay !== null ? relayHost(p.relay) : (p.ip ?? "direct")} ${p.rttMs === null ? "?" : `${Math.round(p.rttMs)}ms`} ${p.txPackets}/${p.lostPackets}`)
      .join("; ");
  }

  /// Which ways iroh has for it, where each goes and the one chosen, without their counts: what changes as one opens, goes
  /// or is chosen.
  pathShape(): string {
    return this.conn
      .paths()
      .map((p) => `${p.selected ? "*" : ""}${p.id}@${p.relay ?? p.ip ?? "direct"}`)
      .join(",");
  }

  net(): LinkNet {
    const selected = this.conn.paths().find((p) => p.selected);
    const stats = this.conn.stats();
    return {
      path: selected === undefined ? null : selected.relay !== null ? "relay" : this.pinned === TAILNET ? TAILNET : "direct",
      relay: selected?.relay ? relayHost(selected.relay) : null,
      rttMs: selected !== undefined ? selected.rttMs : null,
      measured: null,
      today: null,
      rxBytes: stats.rxBytes,
      txBytes: stats.txBytes,
      // The way in use alone: the connection's own counts take in every way iroh tried and dropped, which made a
      // quiet direct link look like it lost a third of its packets.
      packets: selected === undefined ? null : { path: selected.id, sent: selected.txPackets, lost: selected.lostPackets },
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

/// An opening shared by everyone who asks for the same station address meanwhile.
type Opening = { done: Deferred.Deferred<Link, CoreError>; result: { ok: Link } | { err: CoreError; unanswered: boolean } | null };

/// A link tried beside an opening still under way (`hedge`).
type Hedge = { serial: number; credentials: CredentialSource; tx: Deferred.Deferred<Link, CoreError> | null };

/// `takes`: the protocols the main endpoint takes connections on, and `incoming` what is done with each (an app, as a
/// trusted device a new one meets face to face: views/pair.ts).
export type MeshEnv = { host: Host; runner: Runner; tracer: Tracer; iroh: Iroh; wakes: Wakes; takes?: Uint8Array[]; incoming?: (connection: IrohConnection, alpn: Uint8Array) => void };

/// The links are kept by station address (`"<workspace>/<station>"`, station/addr.ts; a bare station id stands for
/// itself): a station in two workspaces has a link in each, opened with that workspace's credential, renewed, dropped and
/// opened again on its own; both are dialled to the same endpoint, the station's id. What is the network's alone is kept
/// by station id and shared: how fast replies came through a relay (`speed`), what went over the links today (`today`).
export class Mesh {
  readonly #env: MeshEnv;
  relays: string[];
  /// Ways into a relay through another relay's machine (cloud relays.ts `relay_entries`): each dialled on an endpoint
  /// of its own and through it alone, never on the main endpoint. An entry is a relay already reached under another URL:
  /// on both, one key is on that relay twice, the connection made last taking the other's place, back and forth
  /// (2026-10-08: with the entries among their relays, phones' connects to any station failed one in five).
  entries: string[];
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
  /// By address: the ways open to it (the link requests go on among them), each pinged every TICK_MS while it has any.
  readonly #ways = new Map<string, Way[]>();
  readonly #steering = new Set<string>();
  /// Ways let go, closed RETIRE_MS later (what is still coming on them comes meanwhile).
  readonly #retiring = new Set<Link>();
  readonly #exploring = new Set<string>();
  readonly #exploredAt = new Map<string, number>();
  /// By address: when a way to it was last seen going direct, and when the main endpoint last dialled it again.
  readonly #directAt = new Map<string, number>();
  readonly #mainDialledAt = new Map<string, number>();
  /// By address: where the station last said a device dials it straight (kept: SAID_KEY). By kind and address
  /// (`atKey`): the addresses last dialled on that kind's endpoint, when, and whether a dial is under way.
  readonly #said: Record<string, Said>;
  readonly #tried = new Map<string, string>();
  readonly #atDialledAt = new Map<string, number>();
  readonly #atDialling = new Set<string>();
  /// Dials under way on pinned endpoints (their endpoints are not let go meanwhile).
  #dialing = 0;
  /// By address: the relay requests last moved to (its host), and how many times they moved.
  readonly #moved = new Map<string, string>();
  readonly #moves = new Map<string, number>();
  readonly #movedAt = new Map<string, number>();
  /// By address: whether the way requests last moved to went direct; how many ways direct were lost in a row soon after
  /// they were moved to, and until when no way direct is moved to (FLAKY_LOSSES).
  readonly #movedDirect = new Map<string, boolean>();
  readonly #directLosses = new Map<string, number>();
  readonly #directHeldUntil = new Map<string, number>();
  /// By address: when a way on the LAN endpoint last answered its ping (LAN_RECALL_MS); whether one on the Tailscale
  /// endpoint did since the network last changed (it is dialled again then, as the relays are: `#dialAtIf`).
  readonly #lanAt = new Map<string, number>();
  readonly #tailnetAnswered = new Set<string>();
  /// By address: whether a way to it answers its pings, as the last tick found (`healthy`), and who waits for that to
  /// change (`healthChange`).
  readonly #health = new Map<string, boolean>();
  readonly #healthWaiting = new Map<string, Deferred.Deferred<boolean>[]>();
  #closed = false;
  /// By address: the relays its workspace has of its own, and the ways it turned off (its `ways_off`: relays, kinds of
  /// way), as the last `link` to it said.
  readonly #theirs = new Map<string, string[]>();
  readonly #off = new Map<string, string[]>();
  /// By station id: what its links carried today.
  #days: Record<string, Day>;
  #daysChanged = false;
  /// By station id, then relay (`relayKey`): how fast replies came that way.
  readonly #speeds: Record<string, Record<string, Speed>>;
  /// By station id and relay: what replies brought that way in this run (`timed`).
  readonly #came = new Map<string, number>();
  /// When each station's way through each relay last had its speed told (`mesh.speed`), by `#came`'s keys.
  readonly #speedSaid = new Map<string, number>();

  private constructor(env: MeshEnv, relays: string[], entries: string[], endpoint: IrohEndpoint, secret: Uint8Array, days: Record<string, Day>, speeds: Record<string, Record<string, Speed>>, said: Record<string, Said>) {
    this.#env = env;
    this.relays = relays;
    this.entries = entries;
    this.#endpoint = endpoint;
    this.#secret = secret;
    this.#days = days;
    this.#speeds = speeds;
    this.#said = said;
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
      const said = saidOf(parseJson(yield* Effect.orElseSucceed(host.storageGet(SAID_KEY), () => null)));
      const endpoint = yield* Mesh.#bind(env.iroh, secret, relays, false, env.takes);
      const mesh = new Mesh(env, relays, entries.filter((e) => !relays.some((r) => sameRelay(r, e))), endpoint, secret, days, speeds, said);
      env.runner.fork(mesh.#accepting(endpoint));
      env.runner.fork(mesh.#watch());
      env.runner.fork(mesh.#tally());
      return mesh;
    });
  }

  static #bind(iroh: Iroh, secret: Uint8Array, relays: string[], relayOnly = false, alpns: Uint8Array[] = []): Effect.Effect<IrohEndpoint, CoreError> {
    return Effect.mapError(iroh.bind({ secretKey: secret, relayUrls: relays, lookup: !relayOnly && relays.length > 0, relayOnly, ...(alpns.length > 0 ? { alpns } : {}) }), (e) => meshError(t("core-logic.mesh.bind_failed", { error: e.message })));
  }

  /// The connections the main endpoint takes (`MeshEnv.takes`), each handed on, until it is closed (bound anew).
  #accepting(endpoint: IrohEndpoint): Effect.Effect<void> {
    const env = this.#env;
    const accept = endpoint.accept;
    if (!accept || !env.incoming || (env.takes ?? []).length === 0) return Effect.void;
    return Effect.gen(function* () {
      for (;;) {
        const taken = yield* accept.call(endpoint);
        if (taken === null) return;
        env.incoming!(taken.connection, taken.alpn);
      }
    });
  }

  #openLinks(): [string, Link][] {
    const out: [string, Link][] = [];
    for (const [addr, o] of this.#links) if (o.result && "ok" in o.result && o.result.ok.usable()) out.push([addr, o.result.ok]);
    return out;
  }

  /// The station's link now, if one is open.
  current(addr: string): Link | null {
    const o = this.#links.get(addr);
    return o?.result && "ok" in o.result ? o.result.ok : null;
  }

  /// Where the station said it is on its LAN (docs/mesh-lan.md), none until it did.
  lan(addr: string): string[] {
    return this.#said[addr]?.lan ?? [];
  }

  /// What the station's links carried on this device today, both ways (in every workspace it is reached in).
  today(addr: string): [number, number] {
    const id = stationId(addr);
    for (const [a, o] of this.#links) if (stationId(a) === id && o.result && "ok" in o.result) this.#count(a, o.result.ok);
    const d = this.#days[id];
    return d && d.day === this.#localDay() ? [d.rx, d.tx] : [0, 0];
  }

  #count(addr: string, link: Link): void {
    const [rx, tx] = link.uncounted();
    if (rx === 0 && tx === 0) return;
    const today = this.#localDay();
    const id = stationId(addr);
    let d = this.#days[id];
    if (!d || d.day !== today) {
      d = { day: today, rx: 0, tx: 0 };
      this.#days[id] = d;
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
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(NET_DAY_KEY, toJsonBytes(this.#days)), { log: "Unhandled", message: "net days kept" }));
  }

  /// How fast replies from a station came through a relay lately (bytes a second); null if none long enough did.
  speed(addr: string, relay: string): number | null {
    const s = this.#speeds[stationId(addr)]?.[relayKey(relay)];
    return s !== undefined && this.#env.host.nowMs() - s.at < SPEED_KEPT_MS ? s.bps : null;
  }

  /// `bytes` from a station came through `relay` in `ms`. The fastest seen lately counts (SPEED_FRESH_MS): a reply also
  /// comes slower than its way could bring it (the station reading slowly); one seen before that is not kept against how
  /// the way brings replies now. The way the requests go on found slower than it was taken to be: they are moved at once
  /// if another is clearly better now (`#choose`), not after minutes more on it.
  noteSpeed(addr: string, relay: string, bytes: number, ms: number): void {
    if (bytes < SPEED_MIN_BYTES || ms <= 0) return;
    const bps = (bytes / ms) * 1000;
    const now = this.#env.host.nowMs();
    this.#saySpeed(addr, relay, bytes, ms, now);
    const of = (this.#speeds[stationId(addr)] ??= {});
    const key = relayKey(relay);
    const was = of[key];
    if (was !== undefined && now - was.at < SPEED_FRESH_MS && was.bps >= bps) return;
    const slower = this.speed(addr, relay) === null || bps < this.speed(addr, relay)!;
    of[key] = { bps, at: now };
    for (const [id, relays] of Object.entries(this.#speeds)) {
      for (const [r, s] of Object.entries(relays)) if (now - s.at >= SPEED_KEPT_MS) delete relays[r];
      if (Object.keys(relays).length === 0) delete this.#speeds[id];
    }
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(SPEED_KEY, toJsonBytes(this.#speeds)), { log: "Unhandled", message: "speeds kept" }));
    const via = this.current(addr)?.via() ?? null;
    if (slower && via !== null && relayKey(via) === key) this.#choose(addr, "slow");
  }

  /// A reply's speed through a relay, told to telemetry (`mesh.speed`, docs/telemetry.md), at most once every
  /// SPEED_SAID_MS for each station and relay: every one seen, slower ones too, not only the fastest that `noteSpeed`
  /// keeps, so the relays' speeds are seen as devices get them, network by network.
  #saySpeed(addr: string, relay: string, bytes: number, ms: number, now: number): void {
    const said = `${stationId(addr)} ${relayKey(relay)}`;
    if (now - (this.#speedSaid.get(said) ?? -Infinity) < SPEED_SAID_MS) return;
    this.#speedSaid.set(said, now);
    const way = this.#live(addr).find((w) => w.key() === relayKey(relay));
    const span = this.#env.tracer.span("mesh.speed", Kind.Internal);
    span.set("stillfail.station", stationId(addr));
    span.set("stillfail.via", relayHost(relay));
    span.set("stillfail.bytes", bytes);
    span.set("stillfail.ms", Math.round(ms));
    span.set("stillfail.bps", Math.round((bytes / ms) * 1000));
    if (way !== undefined) {
      span.set("stillfail.current", way.link === this.current(addr));
      span.set("stillfail.paths", way.link.paths());
    }
    span.end();
  }

  /// The speeds seen on every way let go (the device on another network now).
  #forgetSpeeds(): void {
    if (Object.keys(this.#speeds).length === 0) return;
    for (const id of Object.keys(this.#speeds)) delete this.#speeds[id];
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(SPEED_KEY, toJsonBytes(this.#speeds)), { log: "Unhandled", message: "speeds kept" }));
  }

  /// A reply's body, timed as it is read: once it has brought SPEED_MIN_BYTES, and again as it ends, how fast its way
  /// brought bytes meanwhile is noted for the relay it came through: all that came through it from the station since
  /// this one began coming, not this one's alone. Replies side by side share the line, and each alone said a part of how
  /// fast it is: a phone's way to ccvm through Beijing's relay, held at a third of its speed, lost to ways never tried,
  /// each bringing its videos at 35 KB/s (2026-10-28). Told as it is under way, not after: a way found slow by a reply of
  /// megabytes is left at once (`noteSpeed`), not after it took minutes to come.
  timed(addr: string, relay: string, body: Pull<Uint8Array>): Pull<Uint8Array> {
    const key = `${stationId(addr)} ${relayKey(relay)}`;
    let first: number | null = null;
    let from = 0;
    let own = 0;
    let told = false;
    return {
      take: Effect.flatMap(body.take, (chunk) =>
        Effect.map(Clock.currentTimeMillis, (now) => {
          const came = (this.#came.get(key) ?? 0) + (chunk?.length ?? 0);
          this.#came.set(key, came);
          if (first === null) {
            if (chunk !== null) [first, from] = [now, came];
            return chunk;
          }
          own += chunk?.length ?? 0;
          if (own >= SPEED_MIN_BYTES && (chunk === null || !told)) {
            told = true;
            this.noteSpeed(addr, relay, came - from, now - first);
          }
          return chunk;
        }),
      ),
    };
  }

  #localDay(): number {
    const now = this.#env.host.nowMs();
    return format.localDay(now, this.#env.host.utcOffsetMin(now));
  }

  #isCurrent(addr: string, link: Link): boolean {
    return this.current(addr) === link;
  }

  #dropIf(addr: string, link: Link): void {
    if (this.#isCurrent(addr, link)) this.dropLink(addr);
  }

  #notify(): void {
    const waiting = this.#changed;
    this.#changed = [];
    for (const d of waiting) Deferred.doneUnsafe(d, Effect.void);
  }

  /// Succeeds once `link` is no longer the station's link (another put in its place, or it was dropped).
  replaced(addr: string, link: Link): Effect.Effect<void> {
    return Effect.suspend(() => {
      const loop: Effect.Effect<void> = Effect.suspend(() => {
        if (!this.#isCurrent(addr, link)) return Effect.void;
        const d = Deferred.makeUnsafe<void>();
        this.#changed.push(d);
        return Effect.andThen(Deferred.await(d), loop);
      });
      return loop;
    });
  }

  /// Puts `next` in place of `old` (if `old` still is), and retires `old`: no more a way to go back to (its link lost
  /// meanwhile, requests went back on it and it was closed under them, 2026-10-15), closed RETIRE_MS later.
  #switch(addr: string, old: Link, next: Link): void {
    if (!this.#isCurrent(addr, old)) {
      next.close();
      return;
    }
    this.#adopt(addr, next);
    const done = Deferred.makeUnsafe<Link, CoreError>();
    Deferred.doneUnsafe(done, Effect.succeed(next));
    this.#links.set(addr, { done, result: { ok: next } });
    this.#notify();
    this.#retire(addr, (this.#ways.get(addr) ?? []).find((w) => w.link === old) ?? new Way(old));
  }

  deviceId(): string {
    return this.#endpoint.id();
  }

  /// This device's word, with its key, that `endpoint` (its main endpoint's or one made over for a relay) is its own
  /// in workspace `ws`: what a station with a workspace lock knows it by (lock.ts).
  lockClaim(ws: string, endpoint: string): LockClaim {
    return lockClaim(this.#secret, ws, endpoint, this.#env.host);
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

  /// The endpoint bound anew with the same key, the old one closed: at most once in REBIND_MS (`always`: whenever).
  #rebind(always = false): Effect.Effect<IrohEndpoint> {
    return Effect.gen({ self: this }, function* () {
      const now = this.#env.host.nowMs();
      if (!always && now - this.#reboundAt < REBIND_MS) return this.#endpoint;
      this.#reboundAt = now;
      const bound = yield* Effect.result(Mesh.#bind(this.#env.iroh, this.#secret, this.relays, false, this.#env.takes));
      if (bound._tag === "Failure") return this.#endpoint;
      const endpoint = bound.success;
      this.#env.runner.fork(this.#accepting(endpoint));
      for (const addr of this.#known) endpoint.addAddr(addr);
      const old = this.#endpoint;
      this.#endpoint = endpoint;
      this.#stuck = false;
      this.#env.runner.fork(old.close());
      return endpoint;
    });
  }

  /// Told the relays and entries anew: the first `/v1/me` of a run, after the mesh came up on those it kept from the last
  /// (a cloud from before `relay_entries` had the entries among the relays). Dialled as told from now on; the endpoint
  /// is bound anew on the new relays if its were others, the links on it closed (an entry among its relays would keep it
  /// on that entry's relay twice).
  retune(relays: string[], entries: string[]): void {
    const same = (a: string[], b: string[]) => a.length === b.length && a.every((r, i) => sameRelay(r, b[i]!));
    const fresh = entries.filter((e) => !relays.some((r) => sameRelay(r, e)));
    if (this.#closed || (same(this.relays, relays) && same(this.entries, fresh))) return;
    const rebind = !same(this.relays, relays);
    this.relays = relays;
    this.entries = fresh;
    if (rebind) this.#env.runner.fork(Effect.asVoid(this.#rebind(true)));
  }

  /// The relays a station is dialled and measured on: still.fail's, then its workspace's own. The endpoint stays bound
  /// to still.fail's alone (one that does not answer there would leave it with no home); another relay is reached as
  /// the station's, or on its own endpoint once measured quicker.
  relaysFor(addr: string): string[] {
    const theirs = this.#theirs.get(addr) ?? [];
    return [...this.relays, ...theirs.filter((r) => !this.relays.some((o) => sameRelay(o, r)))].filter((r) => !this.#isOff(addr, r));
  }

  /// Every way a station is dialled through: its relays (`relaysFor`), then the entries (`entries`). Not the entries
  /// while its workspace turned any of still.fail's relays off: an entry goes through two of their machines, and which
  /// is not known here.
  #waysFor(addr: string): string[] {
    const relays = this.relaysFor(addr);
    if (this.relays.some((r) => this.#isOff(addr, r))) return relays;
    return [...relays, ...this.entries.filter((e) => !relays.some((r) => sameRelay(r, e)))];
  }

  /// Whether the station's workspace turned `way` off (a relay, or a kind of way: LAN, TAILNET, DIRECT).
  #isOff(addr: string, way: string): boolean {
    return (this.#off.get(addr) ?? []).some((o) => o === way || sameRelay(o, way));
  }

  /// Whether the station is dialled on the main endpoint: not while its workspace turned off any relay it is at home on
  /// (still.fail's; which one it is on is iroh's to choose, and the station's answers come there) or the paths iroh
  /// punches through, which the main endpoint alone goes on. Each relay left is reached on its own endpoint then.
  #mainOn(addr: string): boolean {
    return !this.#isOff(addr, DIRECT) && !this.relays.some((r) => this.#isOff(addr, r));
  }

  /// Whether a way open to the station goes a way its workspace turned off.
  #wayOff(addr: string, link: Link): boolean {
    const pinned = link.pinned;
    if (pinned === null) return !this.#mainOn(addr);
    if (pinned === LAN || pinned === TAILNET) return this.#isOff(addr, pinned);
    return !this.#waysFor(addr).some((r) => sameRelay(r, pinned));
  }

  /// Told the ways the station's workspace turned off: each way open to it that goes one of them is closed (the requests
  /// on it, if any, go on another: `link`).
  #turnOff(addr: string, off: readonly string[]): void {
    const was = this.#off.get(addr) ?? [];
    if (was.length === off.length && was.every((o, i) => o === off[i])) return;
    if (off.length > 0) this.#off.set(addr, [...off]);
    else this.#off.delete(addr);
    for (const w of this.#ways.get(addr) ?? []) if (this.#wayOff(addr, w.link)) w.link.close();
    const cur = this.current(addr);
    if (cur !== null && this.#wayOff(addr, cur)) cur.close();
    // (a way turned on again is one more to choose between)
    this.#steerIf(addr);
  }

  /// The link to a station at `addr`, opening it (or opening again a closed one) with a credential from `credentials`,
  /// its workspace's; `theirs`: the relays its workspace has of its own; `off`: the ways it turned off (relays, kinds of
  /// way), none gone that way. The same station at another address (in another workspace) has a link of its own.
  /// `asker`: what waits on it (a request's method and route, `events`, `screen`; `again` when the mesh opens it
  /// itself), said on the dial's span: whether someone was waiting on a slow dial, or it came about in the background.
  link(addr: string, credentials: CredentialSource, theirs?: readonly string[], off?: readonly string[], asker?: string): Effect.Effect<Link, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (theirs !== undefined) this.#theirs.set(addr, [...theirs]);
      if (off !== undefined) this.#turnOff(addr, off);
      const existing = this.#links.get(addr);
      let fresh = false;
      if (existing) {
        if (existing.result === null) {
          // Being opened: as that dial ends, unless it gave up for no answer before this waited CONNECT_TIMEOUT_MS on
          // it. Begun earlier (while the network was down, perhaps), that says nothing of now: dialled again (side run
          // seed 39248349, 2026-10-30: a read asked as its relay came back was told no answer came, the device not
          // having dialled since).
          const asked = this.now();
          const joined = yield* Effect.result(Deferred.await(existing.done));
          if (joined._tag === "Success") return joined.success;
          const ended = existing.result as Opening["result"];
          const unanswered = ended !== null && "err" in ended && ended.unanswered;
          if (!unanswered || this.now() - asked >= CONNECT_TIMEOUT_MS) return yield* Effect.fail(joined.failure);
          return yield* this.link(addr, credentials, theirs, off, asker);
        }
        if ("ok" in existing.result) {
          if (existing.result.ok.usable()) return existing.result.ok;
          // Refused for the workspace lock, the credential was fine: no new one asked of the cloud each time.
          fresh = existing.result.ok.refused !== null && existing.result.ok.refused.code !== "lock_unconfirmed" && existing.result.ok.refused.code !== "lock_station";
        } else fresh = existing.result.err.code === "credential_refused";
      }
      // Gone, with another way still open: requests go on that one at once.
      if (!fresh && existing !== undefined) {
        const standby = this.#best(addr, this.#takeable(addr, this.#live(addr).filter((w) => w.missed === 0)));
        if (standby !== null) {
          this.#promote(addr, standby, "lost");
          return standby.link;
        }
      }
      const span = this.#env.tracer.span("mesh.connect", Kind.Internal);
      span.set("stillfail.station", stationId(addr));
      if (asker !== undefined) span.set("stillfail.asker", asker);
      let endpoint = this.#endpoint;
      if (this.#stuck && !this.#anyOpen()) {
        span.set("stillfail.rebound", true);
        endpoint = yield* this.#rebind();
      }
      span.set("stillfail.relay", relayStatus(endpoint));
      const serial = ++this.#serials;
      const hedged = Deferred.makeUnsafe<Link, CoreError>();
      this.#hedges.set(addr, { serial, credentials, tx: hedged });
      const opening: Opening = { done: Deferred.makeUnsafe<Link, CoreError>(), result: null };
      const before = this.#links.get(addr);
      this.#links.set(addr, opening);
      if (before?.result && "ok" in before.result) this.#count(addr, before.result.ok);
      this.#notify();
      const first = this.#dialAll(addr, endpoint, credentials, fresh, span.context);
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
            const h = self.#hedges.get(addr);
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
        if (self.#hedges.get(addr)?.serial === serial) self.#hedges.delete(addr);
        // (asked before `failedIn` says it with the time it failed at)
        const unanswered = link._tag === "Failure" && link.failure.message === noAnswer();
        if (link._tag === "Success") {
          self.#stuck = false;
          const path = link.success.path();
          if (path !== null) span.set("stillfail.path", path);
          const via = link.success.via();
          if (via !== null) span.set("stillfail.via", relayHost(via));
          // Where its time went: getting onto a relay, the handshake, the credential; and each way's round trip and
          // packets sent and lost by then (a handshake many round trips long, or lost and sent again).
          const opened = link.success.opened;
          if (opened !== null) {
            span.set("stillfail.onto_ms", opened.onto);
            span.set("stillfail.dialled_ms", opened.dialled);
            span.set("stillfail.credential_ms", opened.credential);
          }
          span.set("stillfail.paths", link.success.paths());
        } else {
          if (unanswered) self.#stuck = true;
          failedIn(span, link.failure);
          span.set("stillfail.relay", relayStatus(endpoint));
          // What a dial that failed was given and had beside it: the addresses it was told the station is reached straight
          // at, and the ways of this device's other links to the same station (in another workspace), open on the same
          // endpoint. 2026-10-29: a Mac's dials to its station failed for half an hour, both workspaces' at once, the
          // spans saying nothing of either.
          const straight = self.#straightAt(addr);
          if (straight.length > 0) span.set("stillfail.ips", straight.join(", "));
          const beside = self.#besideOf(addr);
          if (beside !== "") span.set("stillfail.beside", beside);
        }
        span.end();
        opening.result = link._tag === "Success" ? { ok: link.success } : { err: link.failure, unanswered };
        if (link._tag === "Success") self.#adopt(addr, link.success);
        Deferred.doneUnsafe(opening.done, link._tag === "Success" ? Effect.succeed(link.success) : Effect.fail(link.failure));
      });
      this.#env.runner.fork(run);
      return yield* Deferred.await(opening.done);
    });
  }

  /// Closes the link to a station at `addr`, if one is open or opening: taken for gone. Its links at other addresses
  /// (in other workspaces) stay.
  dropLink(addr: string): void {
    const opening = this.#links.get(addr);
    this.#links.delete(addr);
    this.#notify();
    if (opening?.result && "ok" in opening.result) {
      opening.result.ok.conn.close(0, "woke");
      this.#count(addr, opening.result.ok);
    }
    for (const w of this.#ways.get(addr) ?? []) w.link.conn.close(0, "woke");
    this.#ways.delete(addr);
    this.#tellHealth(addr);
  }

  /// Takes over the device key a page kept before the core existed (32 bytes): stored, the endpoint bound anew with
  /// it, open links closed. The same key again changes nothing.
  migrate(secret: Uint8Array): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (secret.length !== 32) return yield* Effect.fail(CoreError.invalid(t("core-logic.mesh.bad_device_key")));
      const stored = yield* Effect.mapError(this.#env.host.storageGet(DEVICE_KEY), asCoreError);
      if (stored !== null && hex(stored) === hex(secret)) return;
      const endpoint = yield* Mesh.#bind(this.#env.iroh, secret, this.relays, false, this.#env.takes);
      this.#env.runner.fork(this.#accepting(endpoint));
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
  #live(addr: string): Way[] {
    const all = this.#ways.get(addr);
    if (all === undefined) return [];
    const live = all.filter((w) => w.link.usable());
    for (const w of all) if (!live.includes(w)) w.link.close();
    if (live.length > 0) this.#ways.set(addr, live);
    else this.#ways.delete(addr);
    return live;
  }

  /// A way as compared with another (`clearlyBetter`).
  #score(addr: string, way: Way): Score {
    const via = way.link.via();
    return { score: cost(way.srtt, via !== null ? this.speed(addr, via) : null) + 2 * way.dev, dev: way.dev };
  }

  /// Of `ways`, the one scoring best (pinged at least once; none pinged yet: the first).
  #best(addr: string, ways: Way[]): Way | null {
    let best: Way | null = null;
    for (const w of ways) {
      if (best === null) best = w;
      else if (w.samples > 0 && (best.samples === 0 || this.#score(addr, w).score < this.#score(addr, best).score)) best = w;
    }
    return best;
  }

  /// Dials the station every way at once: on the main endpoint (through any relay, or direct), and on each relay's own
  /// endpoint through that relay alone. The first through is the link; the others, as they come through, are ways to it
  /// as well (`#adopt`). Fails once all have, as the main endpoint's dial failed. A phone whose own relay could not
  /// reach the station (Beijing's, bft in Tokyo, 2026-10-08) waited out CONNECT_TIMEOUT_MS on it time after time.
  #dialAll(addr: string, endpoint: IrohEndpoint, credentials: CredentialSource, fresh: boolean, ctx: SpanContext | undefined): Effect.Effect<Link, CoreError> {
    return Effect.suspend(() => {
      this.#exploredAt.set(addr, this.now());
      const relays = this.relaysFor(addr);
      // On the main endpoint, one connection: a path through every relay the station is on (the endpoint is home on
      // all of them), to the addresses it said it is reached straight at, and those iroh punches through; iroh moves
      // its packets between them, and nothing on it ends as they change. The other endpoints only while its workspace
      // turned the main endpoint's ways off (`#mainOn`).
      if (this.#mainOn(addr)) return open(this.#env, endpoint, relays, stationId(addr), credentials, fresh, null, ctx, this.#straightAt(addr));
      const main: Effect.Effect<Link, CoreError>[] = [];
      const pinned = this.#pinnable(addr).map((r) => this.#dialPinned(addr, r, credentials, fresh, ctx));
      // Where the station said (in a run before, perhaps) it is reached straight: dialled beside the relays, not after
      // one of them brought its answer again.
      const at = AT_ADDRESSES.flatMap((kind) => this.#dialAt(addr, kind, credentials, fresh) ?? []);
      const all = [...main, ...pinned, ...at];
      if (all.length === 0) return Effect.fail(meshError(t("core-logic.mesh.all_off")));
      const self = this;
      const won = Deferred.makeUnsafe<Link, CoreError>();
      let left = all.length;
      let mainFailure: CoreError | null = null;
      all.forEach((attempt, i) =>
        this.#env.runner.fork(
          Effect.gen(function* () {
            const r = yield* Effect.result(attempt);
            if (r._tag === "Success") {
              if (!Deferred.doneUnsafe(won, Effect.succeed(r.success))) self.#adopt(addr, r.success);
              return;
            }
            if (i === 0 && main.length > 0) mainFailure = r.failure;
            if (--left === 0) Deferred.doneUnsafe(won, Effect.fail(mainFailure ?? r.failure));
          }),
        ),
      );
      return Deferred.await(won);
    });
  }

  /// This device's open links to the station at `addr` under its other addresses (another workspace's), as a span says
  /// them: each one's workspace and ways (`Link.paths`); "" with none.
  #besideOf(addr: string): string {
    const id = stationId(addr);
    const out: string[] = [];
    for (const [a, o] of this.#links) if (a !== addr && stationId(a) === id && o.result && "ok" in o.result && o.result.ok.closed() === null) out.push(`${a.slice(0, a.length - id.length - 1)}: ${o.result.ok.paths()}`);
    return out.join(" | ");
  }

  /// Where the station last said a device dials it straight (its LAN, its tailnet), but the kinds its workspace turned off.
  #straightAt(addr: string): string[] {
    return AT_ADDRESSES.flatMap((kind) => (this.#isOff(addr, kind) ? [] : (this.#said[addr]?.[kind] ?? [])));
  }

  /// The ways a station is dialled on each on an endpoint of its own: every relay and entry but still.fail's own relay
  /// (the first, on Cloudflare), which the main endpoint reaches already. It holds few connections, each a cost: one
  /// more a device filled it (2026-10-08: 429 to bft's keeper and to devices). None while there is one way or none.
  /// Off the main endpoint (`#mainOn`), every relay left is, still.fail's own too.
  #pinnable(addr: string): string[] {
    const ways = this.#waysFor(addr);
    if (!this.#mainOn(addr)) return ways;
    if (ways.length < 2) return [];
    const own = this.relays[0];
    return ways.filter((r) => own === undefined || !sameRelay(own, r));
  }

  /// A link through `relay` alone, on that relay's own endpoint (`#pinnedEndpoint`).
  #dialPinned(addr: string, relay: string, credentials: CredentialSource, fresh: boolean, ctx: SpanContext | undefined): Effect.Effect<Link, CoreError> {
    return Effect.suspend(() => {
      this.#dialing++;
      return Effect.flatMap(this.#pinnedEndpoint(relay), (endpoint) =>
        endpoint === null ? Effect.fail(unreached({ message: `no endpoint for ${relayHost(relay)}` })) : open(this.#env, endpoint, [relay], stationId(addr), credentials, fresh, relay, ctx),
      ).pipe(Effect.ensuring(Effect.sync(() => this.#dialing--)));
    });
  }

  /// The station said where a device dials it straight (`link.lan`, `link.tailnet`, its answer to a link's
  /// credential): kept, and dialled there if new.
  #heard(addr: string, link: Link): void {
    // (refused, it said nothing of where it is: what was kept stays)
    if (link.refused !== null) return;
    const said: Said = { lan: link.lan, tailnet: link.tailnet };
    const was = this.#said[addr];
    const same = (kind: AtAddresses) => (was?.[kind] ?? []).join(" ") === said[kind].join(" ");
    if (!AT_ADDRESSES.every(same)) {
      for (const kind of AT_ADDRESSES) if (!same(kind)) this.#tried.delete(atKey(kind, addr));
      if (said.lan.length > 0 || said.tailnet.length > 0) this.#said[addr] = said;
      else delete this.#said[addr];
      this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(SAID_KEY, toJsonBytes(this.#said)), { log: "Unhandled", message: "said kept" }));
    }
    // On the main endpoint the addresses are iroh's to try on the connection open (paths of it), not dialled apart.
    if (this.#mainOn(addr)) {
      const ips = this.#straightAt(addr);
      if (ips.length > 0) this.#endpoint.addAddr({ id: stationId(addr), relays: this.relaysFor(addr), ips });
      return;
    }
    for (const kind of AT_ADDRESSES) this.#dialAtIf(addr, kind, link.credentials);
  }

  /// Dials the station at its addresses of `kind` on that kind's endpoint, unless a way to it is on that endpoint
  /// already: once for each set of addresses it says (a device off its LAN, its tailnet, tries them once, then not
  /// again until they change or the network does). Again on the LAN every REDIAL_MAIN_MS while it was reached direct
  /// within DIRECT_RECALL_MS; on the tailnet every EXPLORE_MS once it answered there since the network changed, as the
  /// relays are (a way let go as no better than the others may be better later).
  #dialAtIf(addr: string, kind: AtAddresses, credentials: CredentialSource): void {
    const at = this.#said[addr]?.[kind] ?? [];
    if (this.#closed || !this.#links.has(addr) || at.length === 0) return;
    const now = this.now();
    if (this.#tried.get(atKey(kind, addr)) === at.join(" ")) {
      const last = this.#atDialledAt.get(atKey(kind, addr)) ?? -Infinity;
      const again = kind === LAN ? now - (this.#directAt.get(addr) ?? -Infinity) < DIRECT_RECALL_MS && now - last >= REDIAL_MAIN_MS : this.#tailnetAnswered.has(addr) && now - last >= EXPLORE_MS;
      if (!again) return;
    }
    const dial = this.#dialAt(addr, kind, credentials, false);
    if (dial !== null) this.#env.runner.fork(Effect.ignore(Effect.map(dial, (link) => this.#adopt(addr, link)), { log: "Unhandled", message: "link dialled" }));
  }

  /// A dial of the station at its addresses of `kind`, on that kind's endpoint (`pinned` LAN or TAILNET): null when it
  /// said none, its workspace turned that kind off, one is under way or a way to it is on that endpoint already. Counted
  /// as under way from now: the caller runs it at once (`#dialAtIf` adopts what comes through; `#dialAll` races it).
  #dialAt(addr: string, kind: AtAddresses, credentials: CredentialSource, fresh: boolean): Effect.Effect<Link, CoreError> | null {
    const at = this.#said[addr]?.[kind] ?? [];
    const key = atKey(kind, addr);
    if (at.length === 0 || this.#isOff(addr, kind) || this.#atDialling.has(key) || this.#live(addr).some((w) => w.link.pinned === kind)) return null;
    this.#tried.set(key, at.join(" "));
    this.#atDialledAt.set(key, this.now());
    this.#atDialling.add(key);
    this.#dialing++;
    return Effect.flatMap(this.#pinnedEndpoint(kind), (endpoint) =>
      endpoint === null ? Effect.fail(unreached({ message: `no ${kind} endpoint` })) : open(this.#env, endpoint, [], stationId(addr), credentials, fresh, kind, undefined, at),
    ).pipe(
      Effect.ensuring(
        Effect.sync(() => {
          this.#dialing--;
          this.#atDialling.delete(key);
        }),
      ),
    );
  }

  /// `link` is a way to the station as well, if it is still wanted; pinged from now on.
  #adopt(addr: string, link: Link): void {
    // (one dialled before its workspace turned that way off)
    if (this.#closed || !this.#links.has(addr) || this.#wayOff(addr, link)) {
      link.close();
      return;
    }
    const ways = this.#live(addr);
    if (ways.some((w) => w.link === link)) return;
    this.#ways.set(addr, [...ways, new Way(link)]);
    // A way just opened answers: not taken for unanswered as the ways before it were.
    this.#tellHealth(addr);
    if (link.pinned !== LAN && link.pinned !== TAILNET) this.#env.runner.fork(Effect.andThen(Deferred.await(link.answered), Effect.sync(() => this.#heard(addr, link))));
    this.#steerIf(addr);
  }

  /// Steers the station's ways (`#steer`) unless they are steered already, or there is but one way there: no relays or
  /// one, and none at an address it said (or turned off): nothing to choose between.
  #steerIf(addr: string): void {
    if (this.#steering.has(addr) || this.#live(addr).length === 0) return;
    const at = AT_ADDRESSES.filter((kind) => (this.#said[addr]?.[kind] ?? []).length > 0 && !this.#isOff(addr, kind)).length;
    if (this.#waysFor(addr).length + at < 2 && this.#live(addr).length < 2) return;
    this.#steering.add(addr);
    this.#env.runner.fork(this.#steer(addr));
  }

  /// Requests to the station go on `way` from now on; the link they went on stays open as another way.
  #promote(addr: string, way: Way, why: string): void {
    const before = this.current(addr);
    if (before === way.link) return;
    const span = this.#env.tracer.span("mesh.route", Kind.Internal);
    span.set("stillfail.station", stationId(addr));
    span.set("stillfail.why", why);
    const was = before !== null ? this.#live(addr).find((w) => w.link === before) : undefined;
    if (was !== undefined) {
      span.set("stillfail.from", was.key());
      span.set("stillfail.from.score", Math.round(this.#score(addr, was).score));
      span.set("stillfail.from.missed", was.missed);
      span.set("stillfail.from.paths", was.link.paths());
    }
    span.set("stillfail.to", way.key());
    span.set("stillfail.to.score", Math.round(this.#score(addr, way).score));
    span.set("stillfail.to.paths", way.link.paths());
    if (why === "lost" && this.#movedDirect.get(addr) === true) {
      const held = this.#lostDirect(addr, this.now() - (this.#movedAt.get(addr) ?? -Infinity));
      if (held !== null) span.set("stillfail.direct_held_ms", held);
    }
    span.end();
    this.#movedDirect.set(addr, this.#isDirect(way));
    const done = Deferred.makeUnsafe<Link, CoreError>();
    Deferred.doneUnsafe(done, Effect.succeed(way.link));
    this.#links.set(addr, { done, result: { ok: way.link } });
    if (before !== null) this.#count(addr, before);
    const via = way.link.via();
    this.#moved.set(addr, via !== null ? relayHost(via) : "direct");
    this.#moves.set(addr, this.moves(addr) + 1);
    this.#movedAt.set(addr, this.now());
    for (const w of this.#live(addr)) w.better = 0;
    this.#notify();
  }

  /// How many times requests to the station moved from one way to another.
  moves(addr: string): number {
    return this.#moves.get(addr) ?? 0;
  }

  /// The ways open to the station, the link requests go on among them.
  ways(addr: string): Way[] {
    return this.#live(addr);
  }

  /// Whether a way to the station is up: one open that answered its last ping (one not pinged yet: its handshake did).
  standing(addr: string): boolean {
    return this.#links.has(addr) && this.#live(addr).some((w) => w.missed === 0);
  }

  /// Whether a way to the station answers its pings: one open that has not missed DEAD_PINGS in a row (none open: no).
  healthy(addr: string): boolean {
    return this.#links.has(addr) && this.#live(addr).some((w) => w.missed < DEAD_PINGS);
  }

  /// Succeeds with whether a way to the station answers its pings once that is no longer `was`, as the ticks find it.
  healthChange(addr: string, was: boolean): Effect.Effect<boolean> {
    return Effect.suspend(() => {
      const now = this.#health.get(addr) ?? this.healthy(addr);
      if (now !== was) return Effect.succeed(now);
      const d = Deferred.makeUnsafe<boolean>();
      this.#healthWaiting.set(addr, [...(this.#healthWaiting.get(addr) ?? []), d]);
      return Deferred.await(d);
    });
  }

  /// After a tick: how its pings went, told to those waiting where it changed.
  #tellHealth(addr: string): void {
    const now = this.healthy(addr);
    if (this.#health.get(addr) === now) return;
    this.#health.set(addr, now);
    const waiting = this.#healthWaiting.get(addr) ?? [];
    this.#healthWaiting.delete(addr);
    for (const d of waiting) Deferred.doneUnsafe(d, Effect.succeed(now));
  }

  /// Pings a way: its credential presented again on it, answered by the station. Not answered within PING_TIMEOUT_MS,
  /// it counts as that long, and as missed; one still not answered is not sent again over it meanwhile. One answered
  /// later still is an answer: the way is not missing (only slow), and what it took is noted. A way whose round trip
  /// passes PING_TIMEOUT_MS missed every ping else, and its one connection was let go as dead at the third and dialled
  /// anew, again and again, each dial not done in CONNECT_TIMEOUT_MS (2026-10-29: a station 2–3 s away through every
  /// relay, unreached).
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
      let late = false;
      this.#env.runner.fork(
        Effect.gen(function* () {
          const started = yield* Clock.currentTimeMillis;
          const r = yield* Effect.result(link.controlled((c) => c.exchange(link.credential)));
          const took = (yield* Clock.currentTimeMillis) - started;
          way.pinging = false;
          if (late && r._tag === "Success") {
            way.missed = 0;
            way.note(took);
          }
          Deferred.doneUnsafe(answered, Effect.succeed(r._tag === "Success" ? took : null));
        }),
      );
      return Effect.map(Effect.raceFirst(Deferred.await(answered), Effect.as(Effect.sleep(PING_TIMEOUT_MS), null)), (ms) => {
        if (ms === null) {
          late = true;
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
  #sample(addr: string): Effect.Effect<void> {
    return Effect.asVoid(Effect.all(this.#live(addr).map((w) => this.#ping(w)), { concurrency: "unbounded" }));
  }

  /// Moves the station's requests to the best way if it is clearly better than theirs (`clearlyBetter`) BETTER_TICKS
  /// times in a row, or at once (`now`, why: "asked" as a person asks, "slow" as theirs was found to bring replies
  /// slowly); to the best way left at once if theirs is gone or missed DEAD_PINGS pings.
  #choose(addr: string, now: "asked" | "slow" | null): void {
    const cur = this.current(addr);
    if (cur === null && this.#links.get(addr)?.result === null) return;
    const ways = this.#live(addr);
    const up = ways.filter((w) => w.missed < DEAD_PINGS);
    const mine = ways.find((w) => w.link === cur);
    if (cur === null || !cur.usable() || mine === undefined || mine.missed >= DEAD_PINGS) {
      const best = this.#best(addr, this.#takeable(addr, up.filter((w) => w.link !== cur)));
      if (best !== null) this.#promote(addr, best, "lost");
      else if (cur !== null && mine !== undefined && mine.missed >= DEAD_PINGS && this.#mainOn(addr)) {
        // Its one connection: the station has not answered on it DEAD_PINGS times (iroh keeps the connection up across
        // its paths, so this is the station, not the way): let go, and the station dialled anew.
        const credentials = cur.credentials;
        this.dropLink(addr);
        this.#env.runner.fork(Effect.ignore(this.link(addr, credentials, undefined, undefined, "again"), { log: "Unhandled", message: "link opened" }));
      }
      return;
    }
    const held = this.#directHeld(addr);
    // A way gone direct and answering clearly quicker is taken at once: the station is on the LAN (or a hole was punched
    // to it), where a relay only adds its round trip. A phone that came back to the app on its station's LAN went on
    // through a relay as that link came through first, and stayed there for minutes (BETTER_TICKS, MIN_STAY_MS) while
    // the direct way waited its turn (2026-10-17).
    if (!held && mine.samples > 0 && mine.link.pinned !== LAN) {
      // One on the LAN endpoint is taken over the main endpoint's punched path as well: that one stopped answering seconds
      // after it opened (docs/mesh-lan.md).
      const lan = up.find((w) => w.link !== cur && w.link.pinned === LAN && w.samples > 0 && w.missed === 0);
      if (lan !== undefined && (mine.key() === "direct" || clearlyBetter(this.#score(addr, mine), this.#score(addr, lan)))) {
        this.#promote(addr, lan, "lan");
        return;
      }
      const direct = mine.key() === "direct" ? null : this.#best(addr, up.filter((w) => w.link !== cur && w.samples > 0 && w.missed === 0 && w.key() === "direct" && !this.#avoided(addr, w)));
      if (direct !== null && clearlyBetter(this.#score(addr, mine), this.#score(addr, direct))) {
        this.#promote(addr, direct, "direct");
        return;
      }
    }
    if (mine.samples < MIN_SAMPLES) return;
    if (now === null && this.now() - (this.#movedAt.get(addr) ?? -Infinity) < MIN_STAY_MS) return;
    const best = this.#best(addr, up.filter((w) => w.link !== cur && w.samples >= MIN_SAMPLES && !this.#avoided(addr, w)));
    for (const w of ways) if (w !== best) w.better = 0;
    if (best === null) return;
    if (!clearlyBetter(this.#score(addr, mine), this.#score(addr, best))) {
      best.better = 0;
      return;
    }
    best.better++;
    if (now !== null || best.better >= BETTER_TICKS) this.#promote(addr, best, now ?? "better");
  }

  /// Whether `way` goes direct: on the LAN endpoint, or on a path iroh punched.
  #isDirect(way: Way): boolean {
    return way.link.pinned === LAN || way.key() === "direct";
  }

  /// Whether no way direct is moved to now (FLAKY_LOSSES).
  #directHeld(addr: string): boolean {
    return this.now() < (this.#directHeldUntil.get(addr) ?? -Infinity);
  }

  /// Whether the requests keep off `way` while another is up: a way direct while those are held off (FLAKY_LOSSES), the
  /// main endpoint's while the station was reached on the LAN endpoint lately (LAN_RECALL_MS).
  #avoided(addr: string, way: Way): boolean {
    if (this.#directHeld(addr) && this.#isDirect(way)) return true;
    return way.link.pinned === null && this.now() - (this.#lanAt.get(addr) ?? -Infinity) < LAN_RECALL_MS;
  }

  /// Of `ways`, those requests may move to: those not avoided (`#avoided`; all, if every one is).
  #takeable(addr: string, ways: Way[]): Way[] {
    const others = ways.filter((w) => !this.#avoided(addr, w));
    return others.length > 0 ? others : ways;
  }

  /// The way direct the requests went on was lost, `stayed` after they moved to it: one lost soon after, FLAKY_LOSSES
  /// times in a row, holds ways direct off a while (how long, or null); one that stayed MIN_STAY_MS starts the count anew.
  #lostDirect(addr: string, stayed: number): number | null {
    if (stayed >= MIN_STAY_MS) {
      this.#directLosses.delete(addr);
      return null;
    }
    const n = (this.#directLosses.get(addr) ?? 0) + 1;
    this.#directLosses.set(addr, n);
    if (n < FLAKY_LOSSES) return null;
    const hold = Math.min(DIRECT_HOLD_MS * 2 ** (n - FLAKY_LOSSES), DIRECT_HOLD_MAX_MS);
    this.#directHeldUntil.set(addr, this.now() + hold);
    return hold;
  }

  /// No more requests go on `way`; it is closed RETIRE_MS later, unless they went back to it meanwhile (replies under way
  /// on it come meanwhile: a large one, a read that just moved off it).
  #retire(addr: string, way: Way): void {
    this.#ways.set(
      addr,
      (this.#ways.get(addr) ?? []).filter((w) => w !== way),
    );
    this.#retiring.add(way.link);
    this.#env.runner.fork(
      Effect.andThen(
        Effect.sleep(RETIRE_MS),
        Effect.sync(() => {
          this.#retiring.delete(way.link);
          if (this.#isCurrent(addr, way.link)) return;
          way.link.close();
          this.#count(addr, way.link);
          this.#env.runner.fork(this.#letGo());
        }),
      ),
    );
  }

  /// Lets go of the ways not worth keeping: one that missed DEAD_PINGS pings, one of two going the same way, and past
  /// KEEP_WAYS the worst of those pinged MIN_SAMPLES times (never the one requests go on).
  #prune(addr: string): void {
    const cur = this.current(addr);
    for (const w of this.#live(addr)) if (w.link !== cur && w.missed >= DEAD_PINGS) this.#retire(addr, w);
    const byKey = new Map<string, Way>();
    for (const w of this.#live(addr)) {
      // Not before it was pinged MIN_SAMPLES times: a link on the main endpoint goes through a relay at first, and direct
      // once a hole is punched; let go as the twin of that relay's own, it never went direct (2026-10-17).
      if (w.link !== cur && w.samples < MIN_SAMPLES) continue;
      const k = w.key();
      const other = byKey.get(k);
      if (other === undefined) {
        byKey.set(k, w);
        continue;
      }
      const keep = other.link === cur ? other : w.link === cur ? w : this.#score(addr, w).score < this.#score(addr, other).score ? w : other;
      this.#retire(addr, keep === w ? other : w);
      byKey.set(k, keep);
    }
    // Those the requests keep off last: the way kept beside theirs is one they would move to (a relay's, not the main
    // endpoint's, while the LAN endpoint's is lost).
    const others = this.#live(addr)
      .filter((w) => w.link !== cur && w.samples >= MIN_SAMPLES)
      .sort((a, b) => Number(this.#avoided(addr, a)) - Number(this.#avoided(addr, b)) || this.#score(addr, a).score - this.#score(addr, b).score);
    for (const w of others.slice(Math.max(0, KEEP_WAYS - 1))) this.#retire(addr, w);
  }

  /// Dials the station on the ways not open to it (the main endpoint, each relay's own; `mainOnly`: the main endpoint
  /// alone), each come through a way.
  #explore(addr: string, credentials: CredentialSource, mainOnly = false): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      if (this.#exploring.has(addr)) return;
      this.#exploring.add(addr);
      this.#mainDialledAt.set(addr, this.now());
      if (!mainOnly) this.#exploredAt.set(addr, this.now());
      const have = new Set(this.#live(addr).map((w) => w.link.pinned ?? "main"));
      const relays = this.relaysFor(addr);
      const tries: Effect.Effect<Link, CoreError>[] = [];
      // Not while the LAN endpoint reaches it: the requests keep off the main endpoint then (LAN_RECALL_MS).
      const onLan = this.now() - (this.#lanAt.get(addr) ?? -Infinity) < LAN_RECALL_MS;
      if (!have.has("main") && !onLan && this.#mainOn(addr)) tries.push(open(this.#env, this.#endpoint, relays, stationId(addr), credentials, false, null, undefined));
      if (!mainOnly) for (const r of this.#pinnable(addr)) if (!have.has(r)) tries.push(this.#dialPinned(addr, r, credentials, false, undefined));
      yield* Effect.all(
        tries.map((attempt) => Effect.map(Effect.result(attempt), (r) => (r._tag === "Success" ? this.#adopt(addr, r.success) : undefined))),
        { concurrency: "unbounded" },
      );
      this.#exploring.delete(addr);
    });
  }

  /// While the station has a way open: every TICK_MS each pinged, the requests moved to the best (`#choose`), the
  /// ways not worth keeping let go (`#prune`), and every EXPLORE_MS the others dialled again (`#explore`); the main
  /// endpoint's link, gone from a station reached direct within DIRECT_RECALL_MS, every REDIAL_MAIN_MS.
  #steer(addr: string): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      for (;;) {
        yield* laterSleep(TICK_MS);
        if (this.#closed || !this.#links.has(addr)) break;
        const cur = this.current(addr);
        if (this.#live(addr).length === 0 && (cur === null || !cur.usable())) break;
        yield* this.#sample(addr);
        this.#tellHealth(addr);
        for (const w of this.#live(addr)) this.#watchPaths(addr, w);
        this.#choose(addr, null);
        this.#prune(addr);
        // The way direct requests moved to stayed: one lost after this is not lost soon after.
        if (this.#movedDirect.get(addr) === true && this.now() - (this.#movedAt.get(addr) ?? Infinity) >= MIN_STAY_MS) this.#directLosses.delete(addr);
        const live = this.#live(addr);
        if (live.some((w) => this.#isDirect(w))) this.#directAt.set(addr, this.now());
        if (live.some((w) => w.link.pinned === LAN && w.missed === 0 && w.samples > 0)) this.#lanAt.set(addr, this.now());
        if (live.some((w) => w.link.pinned === TAILNET && w.missed === 0 && w.samples > 0)) this.#tailnetAnswered.add(addr);
        const credentials = (this.current(addr) ?? live[0]?.link)?.credentials;
        // One connection on the main endpoint: no other ways to dial, compare or move to (iroh moves its packets).
        if (credentials === undefined || this.#mainOn(addr)) continue;
        for (const kind of AT_ADDRESSES) this.#dialAtIf(addr, kind, credentials);
        if (this.now() - (this.#exploredAt.get(addr) ?? 0) >= EXPLORE_MS) this.#env.runner.fork(this.#explore(addr, credentials));
        else if (
          this.#mainOn(addr) &&
          !live.some((w) => w.link.pinned === null) &&
          this.now() - (this.#directAt.get(addr) ?? -Infinity) < DIRECT_RECALL_MS &&
          // Not for the punched path while the LAN endpoint reaches it: the requests keep off that (LAN_RECALL_MS).
          this.now() - (this.#lanAt.get(addr) ?? -Infinity) >= LAN_RECALL_MS &&
          this.now() - (this.#mainDialledAt.get(addr) ?? -Infinity) >= REDIAL_MAIN_MS
        )
          this.#env.runner.fork(this.#explore(addr, credentials, true));
      }
      this.#steering.delete(addr);
    });
  }

  /// 2026-10-17: a phone's punched paths went quiet seconds after they opened, which no Mac on the LAN did again
  /// (docs/mesh-lan.md). Each tick, a `mesh.path` span says a way's paths changed (one opened, one went, another chosen)
  /// (or first seen, direct) or that it missed its first ping in a row: its paths now and as the tick before saw them,
  /// round trips and counts.
  #watchPaths(addr: string, w: Way): void {
    const shape = w.link.pathShape();
    const paths = w.link.paths();
    // First seen, a way is told if it is direct already (iroh punches within a second, well before a tick).
    const changed = w.shape === null ? w.link.path() === "direct" : shape !== w.shape;
    const missed = w.missed === 1;
    if (changed || missed) {
      const span = this.#env.tracer.span("mesh.path", Kind.Internal);
      span.set("stillfail.station", stationId(addr));
      span.set("stillfail.way", w.key());
      span.set("stillfail.why", changed && missed ? "paths missed" : changed ? "paths" : "missed");
      span.set("stillfail.current", w.link === this.current(addr));
      span.set("stillfail.paths", paths);
      if (w.saw !== null) span.set("stillfail.before.paths", w.saw);
      span.end();
    }
    w.shape = shape;
    w.saw = paths;
  }

  /// The way a read slow on `link` is asked on as well: the best other way open, going another way than `link` (not the
  /// main endpoint through the same relay), whose last ping was answered (one not pinged yet: its handshake was).
  standby(addr: string, link: Link): Link | null {
    const ways = this.#live(addr);
    const key = ways.find((w) => w.link === link)?.key() ?? null;
    return this.#best(addr, ways.filter((w) => w.link !== link && w.missed === 0 && w.key() !== key))?.link ?? null;
  }

  /// How long a read on `link` waits for its answer before it is asked on another way as well: what its way is expected
  /// to take at worst, and twice its deviation more; HEDGE_FLOOR_MS at least (the station's own time to answer).
  hedgeAfter(addr: string, link: Link): number {
    const w = this.#live(addr).find((x) => x.link === link);
    if (w === undefined || w.samples === 0) return HEDGE_FLOOR_MS;
    const s = this.#score(addr, w);
    return Math.max(HEDGE_FLOOR_MS, s.score + 2 * s.dev);
  }

  /// A read asked on `slow` and then on another way as well was answered on the other first, `ms` after it was asked on
  /// `slow`: that long counts as a ping of `slow` (the requests move as the pings decide, not on one read).
  outran(addr: string, slow: Link, ms: number): void {
    this.#live(addr).find((x) => x.link === slow)?.note(ms);
  }

  /// Every way to the station as pinged: the round trip of each way open (its relay's host, "tailnet" or "direct"), then each
  /// relay with no way open on it now (not reached, or let go: no figure).
  measured(addr: string): Measured | null {
    const ways = this.#live(addr).filter((w) => w.samples > 0);
    const measuring = this.#exploring.has(addr);
    if (ways.length === 0 && !measuring) return null;
    const relays: [string, number | null][] = [];
    const seen = new Set<string>();
    for (const w of [...ways].sort((a, b) => a.srtt - b.srtt)) {
      const key = w.key() === LAN ? "direct" : w.key();
      if (seen.has(key)) continue;
      seen.add(key);
      const via = w.link.via();
      relays.push([via !== null ? relayHost(via) : key === TAILNET ? TAILNET : "direct", Math.round(w.srtt)]);
    }
    for (const r of this.#waysFor(addr)) if (!seen.has(relayKey(r))) relays.push([relayHost(r), null]);
    return { measuring, relays, moved: this.#moved.get(addr) ?? null };
  }

  /// The ways to a station dialled and pinged now, as a person asks; the requests moved to the best if it is clearly
  /// better.
  remeasure(addr: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const link = this.current(addr);
      if (link === null || !link.usable()) return yield* Effect.fail(meshError(t("core-logic.mesh.not_connected")));
      yield* this.#explore(addr, link.credentials);
      for (let i = 0; i <= MIN_SAMPLES; i++) yield* this.#sample(addr);
      this.#choose(addr, "asked");
      this.#prune(addr);
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
      // The LAN endpoint, the Tailscale one: on no relay, so each looks nothing up and punches no hole; it dials
      // addresses alone.
      const bound = yield* Effect.result(relay === LAN || relay === TAILNET ? Mesh.#bind(this.#env.iroh, pinnedKey(this.#secret, relay), []) : Mesh.#bind(this.#env.iroh, pinnedKey(this.#secret, relay), [relay], true));
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
        // On another network, the speeds seen on the last say nothing of how fast each way is from here (a laptop taken
        // from home would keep the relay it was fast through there, however slowly it brings replies now): found anew.
        if (wake.network) this.#forgetSpeeds();
        // On another network now, perhaps the station's: its LAN addresses are worth a try again.
        this.#tried.clear();
        // (and its tailnet: dialled again on it only once it answered there again)
        this.#tailnetAnswered.clear();
        for (const [addr, link] of this.#openLinks()) {
          if (this.#racing.has(addr)) continue;
          this.#racing.add(addr);
          this.#env.runner.fork(this.#race(addr, link));
        }
        for (const [addr, h] of this.#hedges) {
          if (h.tx === null) continue;
          const tx = h.tx;
          h.tx = null;
          this.#env.runner.fork(this.#hedge(addr, h.credentials, tx));
        }
      }
    });
  }

  #tally(): Effect.Effect<void> {
    return Effect.forever(
      Effect.andThen(
        laterSleep(TALLY_EVERY_MS),
        Effect.sync(() => {
          for (const [addr, o] of this.#links) if (o.result && "ok" in o.result) this.#count(addr, o.result.ok);
          this.#keepDays();
        }),
      ),
    );
  }

  /// A link tried beside an opening still under way: on an endpoint bound anew if nothing is open on this one.
  #hedge(addr: string, credentials: CredentialSource, tx: Deferred.Deferred<Link, CoreError>): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const endpoint = this.#anyOpen() ? this.#endpoint : yield* this.#rebind();
      const span = this.#env.tracer.span("mesh.hedge", Kind.Internal);
      span.set("stillfail.station", stationId(addr));
      span.set("stillfail.relay", relayStatus(endpoint));
      const opened = yield* Effect.result(this.#dialAll(addr, endpoint, credentials, false, span.context));
      if (opened._tag === "Failure") span.fail();
      span.end();
      const taken = Deferred.doneUnsafe(tx, opened._tag === "Success" ? Effect.succeed(opened.success) : Effect.fail(opened.failure));
      if (!taken && opened._tag === "Success") opened.success.close();
    });
  }

  /// A link suspect against a new one opened beside it at once: whichever answers first.
  #race(addr: string, old: Link): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const span = this.#env.tracer.span("mesh.race", Kind.Internal);
      span.set("stillfail.station", stationId(addr));
      const fresh = Effect.result(this.#dialAll(addr, this.#endpoint, old.credentials, false, span.context));
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
      this.#racing.delete(addr);
      span.set("stillfail.race", won === "old" ? "old" : won === "neither" ? "neither" : "new");
      span.end();
      if (won === "neither") this.#dropIf(addr, old);
      else if (won !== "old") this.#switch(addr, old, won);
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

/// What was kept of where stations said they are reached straight (SAID_KEY), each kind's addresses as strings.
function saidOf(kept: J): Record<string, Said> {
  if (kept === null || typeof kept !== "object" || Array.isArray(kept)) return {};
  const strings = (v: J) => (Array.isArray(v) ? v.filter((a): a is string => typeof a === "string") : []);
  return Object.fromEntries(Object.entries(kept as Record<string, J>).map(([addr, v]) => [addr, { lan: strings(v?.lan), tailnet: strings(v?.tailnet) }]));
}

function relayStatus(endpoint: IrohEndpoint): string {
  const status = endpoint.relayStatus();
  if (status.length === 0) return "none";
  return status.map((s) => `${s.url} ${s.connected ? "up" : "down"}`).join(", ");
}

/// Once the endpoint is on one of its relays (at once with none, or dialled at addresses too): what a dial's
/// CONNECT_TIMEOUT_MS counts from. Getting onto a relay takes several round trips to it (TCP, TLS, the relay's own), a
/// dozen seconds on a phone 2–4 s from every relay, back from the background (nomofu, 2026-10-30): counted in the dial's
/// time, every dial ended as it was about to be answered, and the next bound the endpoint anew (`#stuck`), to get onto
/// the relays from the start again. Not on one in ONTO_MAX_MS: counted from then.
function onARelay(endpoint: IrohEndpoint, direct: boolean): Effect.Effect<void> {
  const on = () => {
    const status = endpoint.relayStatus();
    return direct || status.length === 0 || status.some((s) => s.connected);
  };
  return Effect.gen(function* () {
    for (let waited = 0; waited < ONTO_MAX_MS && !on(); waited += ONTO_RECHECK_MS) yield* Effect.sleep(ONTO_RECHECK_MS);
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
  ctx: SpanContext | undefined,
  ips: string[] = [],
): Effect.Effect<Link, CoreError> {
  return Effect.suspend(() => {
    const began = env.host.nowMs();
    const opened = { onto: 0, dialled: 0, credential: 0 };
    const since = () => Math.round(env.host.nowMs() - began);
    let abandoned = false;
    let connection: IrohConnection | null = null;
    const establish = Effect.gen(function* () {
      if (!/^[0-9a-f]{64}$/.test(stationId)) return yield* Effect.fail(CoreError.invalid(t("core-logic.mesh.bad_station_id", { id: stationId })));
      const device = endpoint.id();
      // A host may finish its native handshake after its caller is interrupted. Keep taking that answer, and close
      // it if this opening has ended. Until the Link is handed out, this opening owns the connection.
      const dialled = Deferred.makeUnsafe<IrohConnection, CoreError>();
      env.runner.fork(
        Effect.gen(function* () {
          const r = yield* Effect.result(endpoint.connect(ips.length > 0 ? { id: stationId, relays, ips } : { id: stationId, relays }, ALPN, [FORMER_ALPN]));
          opened.dialled = since();
          if (r._tag === "Success") {
            if (abandoned) {
              r.success.close(0, "opening ended");
              return;
            }
            connection = r.success;
          }
          Deferred.doneUnsafe(dialled, r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(unreached(r.failure)));
        }),
      );
      const had = Effect.ensuring(
        credentials(device, fresh),
        Effect.sync(() => {
          opened.credential = since();
        }),
      );
      const [credential, conn] = yield* Effect.all([had, Deferred.await(dialled)], { concurrency: "unbounded" });
      const stream = yield* Effect.mapError(conn.openBi(), unreached);
      const control = new Control(stream);
      yield* control.send(credential.credential, credential.lock, ctx?.traceparent());
      const link = new Link(conn, control, credential.credential, credentials, pinned);
      link.opened = opened;
      // The station's answer to the first credential, while requests already go: a refusal closes the link.
      env.runner.fork(
        Effect.gen(function* () {
          const answer = yield* Effect.result(link.controlled((c) => c.answer()));
          if (answer._tag === "Failure") {
            link.renewalFailed = true;
            link.refused = answer.failure;
            conn.close(0, "credential refused");
          } else {
            const addrs = (said: J) => (Array.isArray(said) ? said.filter((a): a is string => typeof a === "string" && /^\d{1,3}(\.\d{1,3}){3}:\d{1,5}$/.test(a)).slice(0, 8) : []);
            link.lan = addrs((answer.success as J)?.lan);
            link.tailnet = addrs((answer.success as J)?.tailnet);
          }
          Deferred.doneUnsafe(link.answered, Effect.void);
        }),
      );
      env.runner.fork(renew(link, credentials, device));
      return link;
    });
    // The same budget as a dial had, still counted after getting onto a relay. It covers the whole opening, even
    // when the handshake succeeds but the old credential request or the first stream/write never answers.
    const deadline = Effect.gen(function* () {
      yield* onARelay(endpoint, ips.length > 0);
      opened.onto = since();
      yield* Effect.sleep(CONNECT_TIMEOUT_MS);
      return yield* Effect.fail(meshError(noAnswer()));
    });
    return Effect.raceFirst(establish, deadline).pipe(Effect.onExit((exit) => Effect.sync(() => {
      if (exit._tag === "Failure") {
        abandoned = true;
        connection?.close(0, "opening ended");
      }
    })));
  });
}

/// Presents a fresh credential every RENEW_MS until the link closes; one not had or refused leaves the link to run
/// out, and the next `link` opens another.
function renew(link: Link, credentials: CredentialSource, device: string): Effect.Effect<void> {
  return Effect.gen(function* () {
    for (;;) {
      const closed = yield* Effect.raceFirst(Effect.as(laterSleep(RENEW_MS), false), Effect.as(link.conn.closed(), true));
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
  return head.method.toUpperCase() === "GET" || onlyReads(head) || (idempotent && head.headers.some(([k]) => k.toLowerCase() === IDEMPOTENCY_KEY));
}

/// A request that only reads though it is no GET (requests.ts READS).
function onlyReads(head: RequestHead): boolean {
  return head.headers.some(([k]) => k.toLowerCase() === READS);
}

/// What the wire needs of the core: the mesh (brought up on first use), each workspace's credentials and waits.
export type MeshWireEnv = {
  mesh: () => Effect.Effect<Mesh, CoreError>;
  /// The mesh if it is up already.
  meshNow: () => Mesh | null;
  credentials: (workspace: string) => CredentialSource;
  /// The relays a workspace has of its own, the ways it turned off (`Mesh.link`).
  relays: (workspace: string) => string[];
  off?: (workspace: string) => string[];
  status: (workspace: string) => import("./status.ts").Status;
  /// The workspace lock (views/lock.ts): a station refused this device for it (`theirs`: how far its own lock goes, as
  /// it said); why a station is not asked now.
  lockRefused?: (workspace: string, station: string, theirs: unknown) => CoreError | null;
  lockWaiting?: (workspace: string, station: string) => CoreError | null;
};

/// Each request goes on the link to its station's address (`Mesh.link`): its workspace's.
export class MeshWire implements StationWire {
  readonly #env: MeshWireEnv;
  /// The addresses whose stations said they keep writes to once.
  readonly #idempotent = new Set<string>();

  constructor(env: MeshWireEnv) {
    this.#env = env;
  }

  request(station: StationAddr, head: RequestHead, body: Uint8Array, wrote?: (sent: number) => void): Effect.Effect<WireReply, CoreError, import("effect").Scope.Scope> {
    const env = this.#env;
    const idempotent = this.#idempotent;
    const workspace = station.workspace;
    const id = station.station;
    const key = station.toString();
    const address = { station: key };
    // A station that refused this device for the workspace lock is not asked again until the lock moves on.
    const waits = env.lockWaiting?.(workspace, id);
    if (waits) return Effect.fail(waits);
    // Refused for it: noted (this device asks to be confirmed), and said as the lock has it (which workspace, where).
    const refusedFor = (e: CoreError) => (e.code === "lock_unconfirmed" ? (env.lockRefused?.(workspace, id, e instanceof LockUnconfirmed ? e.lock : null) ?? e) : e);
    return Effect.mapError(Effect.gen(function* () {
      const status = env.status(workspace);
      const credentials = env.credentials(workspace);
      const theirs = env.relays(workspace);
      const off = env.off?.(workspace);
      const asker = `${head.method.toUpperCase()} ${route(head.path)}`;
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, address, t("station.core.connecting"), mesh.link(key, credentials, theirs, off, asker));
      const repeats = mayRepeat(head, idempotent.has(key));
      const write = !["GET", "HEAD"].includes(head.method.toUpperCase()) && !onlyReads(head);
      // Asked on more than one way (or again), the body is told of as far as the furthest has gone.
      let furthest = 0;
      const told = wrote && ((n: number) => { if (n > furthest) wrote((furthest = n)); });
      const ask = (l: Link) => Effect.map(l.request(head, body, told), (reply) => [l, reply] as [Link, Reply]);
      let answered: [Link, Reply];
      if (repeats) {
        // Asked on its link; on another way as well if not answered within what its way is expected to take
        // (`hedgeAfter`), or on the link put in its place if its link is replaced meanwhile: the first answer taken.
        const started = mesh.now();
        const asked = yield* Effect.forkChild(Effect.result(ask(link)));
        // An answer come too late to be taken: its stream let go (the station stops sending what no one reads).
        const late = ([, reply]: [Link, Reply]) => reply.cancel();
        // The other way, as there is one by then (the ways dialled with the link may come through after it).
        const slow = Effect.gen(function* () {
          yield* Effect.sleep(mesh.hedgeAfter(key, link));
          for (;;) {
            const standby = mesh.standby(key, link);
            if (standby !== null) return { slow: standby } as const;
            yield* Effect.sleep(HEDGE_RECHECK_MS);
          }
        });
        const first = yield* Effect.raceAllFirst([Effect.map(Fiber.join(asked), (r) => ({ asked: r }) as const), Effect.as(mesh.replaced(key, link), { replaced: true } as const), slow]);
        if ("asked" in first) {
          const r = first.asked;
          if (r._tag === "Success") answered = r.success;
          else if (r.failure.code === "mesh" && write) {
            // A write gone and not answered: asked again with its key whenever its station is back, a while.
            const w = status.begin(address, RECHECKING(), true);
            let pause = 1_000;
            answered = yield* Effect.gen(function* () {
              for (;;) {
                const again = yield* Effect.result(Effect.flatMap(mesh.link(key, credentials, theirs, off, asker), ask));
                if (again._tag === "Success") return again.success;
                if (again.failure.code !== "mesh") return yield* Effect.fail(again.failure);
                if (mesh.now() - started >= RECHECK_MS) return yield* Effect.fail(unconfirmed(again.failure));
                yield* Effect.sleep(pause);
                pause = Math.min(pause * 2, 15_000);
              }
            }).pipe(Effect.ensuring(Effect.sync(() => w.end())));
          } else if (r.failure.code === "mesh") {
            // Its link went: asked again on the one in its place, and again while each it is asked on is found gone too
            // (a station restarting drops all its connections at once; a way not told so yet is taken next, side run
            // seed 143365259, 2026-10-17), a few times.
            answered = yield* Effect.gen(function* () {
              for (let tries = 1; ; tries++) {
                const l = yield* waiting(status, address, t("station.core.connecting"), mesh.link(key, credentials, theirs, off, asker));
                const again = yield* Effect.result(ask(l));
                if (again._tag === "Success") return again.success;
                if (again.failure.code !== "mesh" || l.closed() === null || tries >= LOST_TRIES) return yield* Effect.fail(again.failure);
              }
            });
          } else return yield* Effect.fail(r.failure);
        } else if ("replaced" in first) {
          // Replaced while under way: asked again on the new one at once, the first answer taken.
          const again = Effect.flatMap(mesh.link(key, credentials, theirs, off, asker), ask);
          answered = yield* firstAnswer(asked, again, late);
        } else {
          // Slow on its way: asked on the next best as well. Answered there first, its way is told how long it kept it.
          answered = yield* firstAnswer(asked, ask(first.slow), late);
          if (answered[0] !== link) mesh.outran(key, link, mesh.now() - started);
        }
      } else {
        const r = yield* Effect.result(ask(link));
        if (r._tag === "Failure") return yield* Effect.fail(write && r.failure.code === "mesh" ? unconfirmed(r.failure) : r.failure);
        answered = r.success;
      }
      const [l, reply] = answered;
      // Its stream goes with the scope it was asked in.
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      if (reply.headers.some(([k]) => k.toLowerCase() === IDEMPOTENT)) idempotent.add(key);
      const relay = l.path() === "relay" ? l.via() : null;
      // How fast it comes tells how fast that way is; not an event stream's, which comes as things happen.
      const streams = head.headers.some(([k, v]) => k.toLowerCase() === "accept" && v.includes("text/event-stream"));
      const timed = relay !== null && !streams ? mesh.timed(key, relay, reply.body) : reply.body;
      return { status: reply.status, headers: reply.headers, body: timed, via: l.path(), relay: relay !== null ? relayHost(relay) : null };
    }), refusedFor);
  }

  reset(station: StationAddr): void {
    this.#env.meshNow()?.dropLink(station.toString());
  }

  races(): boolean {
    return true;
  }

  replaced(station: StationAddr): Effect.Effect<void> {
    const mesh = this.#env.meshNow();
    const link = mesh?.current(station.toString()) ?? null;
    if (mesh === null || link === null) return Effect.never;
    return mesh.replaced(station.toString(), link);
  }

  standing(station: StationAddr): boolean {
    return this.#env.meshNow()?.standing(station.toString()) ?? false;
  }

  healthChange(station: StationAddr, was: boolean): Effect.Effect<boolean> {
    const mesh = this.#env.meshNow();
    return mesh === null ? Effect.never : mesh.healthChange(station.toString(), was);
  }

  net(station: StationAddr): LinkNet | null {
    const mesh = this.#env.meshNow();
    const key = station.toString();
    const link = mesh?.current(key) ?? null;
    if (mesh === null || link === null) return null;
    return { ...link.net(), measured: mesh.measured(key), today: mesh.today(key), lan: mesh.lan(key) };
  }

  measure(station: StationAddr): Effect.Effect<void, CoreError> {
    return Effect.flatMap(this.#env.mesh(), (mesh) => mesh.remeasure(station.toString()));
  }

  socket(station: StationAddr, head: RequestHead): Effect.Effect<WireSocket, CoreError, import("effect").Scope.Scope> {
    const env = this.#env;
    return Effect.gen(function* () {
      const status = env.status(station.workspace);
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, { station: station.toString() }, t("station.core.connecting"), mesh.link(station.toString(), env.credentials(station.workspace), env.relays(station.workspace), env.off?.(station.workspace), `${head.method.toUpperCase()} ${route(head.path)}`));
      const [reply, send] = yield* link.socket(head);
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      return { reply: { status: reply.status, headers: reply.headers, body: reply.body, via: link.path() }, send };
    });
  }

  screen(station: StationAddr, head: RequestHead, screen: ScreenAsk): Effect.Effect<WireSocket, CoreError, import("effect").Scope.Scope> {
    const env = this.#env;
    return Effect.gen(function* () {
      const status = env.status(station.workspace);
      const mesh = yield* waiting(status, RELAY, t("station.core.connecting"), env.mesh());
      const link = yield* waiting(status, { station: station.toString() }, t("station.core.connecting"), mesh.link(station.toString(), env.credentials(station.workspace), env.relays(station.workspace), env.off?.(station.workspace), "screen"));
      const [reply, send] = yield* link.screen(head, screen);
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      return { reply: { status: reply.status, headers: reply.headers, body: reply.body, via: link.path() }, send, tap: reply.tap };
    });
  }
}

/// Whichever answers of an attempt under way (`asked`) and another (`b`); one that fails leaves it to the other. Once
/// one is taken the other is stopped, and an answer it had meanwhile goes to `release`: no one reads it.
function firstAnswer<A>(asked: Fiber.Fiber<Result.Result<A, CoreError>>, b: Effect.Effect<A, CoreError>, release: (answer: A) => void): Effect.Effect<A, CoreError> {
  return Effect.gen(function* () {
    const fb = yield* Effect.forkChild(Effect.result(b));
    const [other, r] = yield* Effect.raceFirst(Effect.map(Fiber.join(asked), (r) => [fb, r] as const), Effect.map(Fiber.join(fb), (r) => [asked, r] as const));
    if (r._tag === "Success") {
      yield* Fiber.interrupt(other);
      const late = yield* Effect.exit(Fiber.join(other));
      if (late._tag === "Success" && late.value._tag === "Success") release(late.value.success);
      return r.success;
    }
    const left = yield* Fiber.join(other);
    if (left._tag === "Success") return left.success;
    return yield* Effect.fail(left.failure);
  });
}

/// An effect said to be waited on (status.ts) while it runs.
function waiting<A>(status: import("./status.ts").Status, place: import("./status.ts").Place, what: string, effect: Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
  return Effect.suspend(() => {
    const w = status.begin(place, what, true);
    return effect.pipe(Effect.ensuring(Effect.sync(() => w.end())));
  });
}

/// What an app's main endpoint takes (a trusted device met face to face: views/pair.ts `hooks.lockPair`); a page's
/// nothing (it approves no one).
function takes(inner: Inner): Pick<MeshEnv, "takes" | "incoming"> {
  if (!inner.host.appKeys) return {};
  return { takes: [PAIR_ALPN], incoming: (connection, alpn) => (alpn.length === PAIR_ALPN.length && alpn.every((b, i) => b === PAIR_ALPN[i]) ? hooks.lockPair?.(inner, connection) : connection.close(0, "no such protocol")) };
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
            Effect.flatMap(inner.cloudSync.relaysNow(), (relays) => Mesh.make({ host: inner.host, runner: inner.runner, tracer: inner.tracer, iroh, wakes: inner.wakes, ...takes(inner) }, relays, inner.cloudSync.entriesNow())),
          );
          if (made._tag === "Success") {
            up = made.success;
            // This run's `/v1/me` may have come while it came up on the relays kept from the last.
            const told = inner.cloudSync.relays;
            if (told !== null) up.retune(told, inner.cloudSync.entriesNow());
          } else mesh = null;
          Deferred.doneUnsafe(d, made._tag === "Success" ? Effect.succeed(made.success) : Effect.fail(made.failure));
        }),
      );
      return Deferred.await(d);
    });
  inner.mesh = get;
  inner.meshNow = () => up;
  inner.cloudSync.onRelays = (relays, entries) => up?.retune(relays, entries);
  return new MeshWire({
    mesh: get,
    meshNow: () => up,
    credentials: (workspace) => (device, fresh) => inner.cloudSync.credential(workspace, device, fresh, up?.deviceId() ?? null, up?.lockClaim(workspace, device) ?? null),
    relays: (workspace) => inner.cloudSync.workspaceRelays(workspace),
    off: (workspace) => inner.cloudSync.workspaceOff(workspace),
    status: (workspace) => inner.workspaces.of(workspace).status,
    lockRefused: (workspace, station, theirs) => hooks.lockRefused?.(inner, workspace, station, theirs) ?? null,
    lockWaiting: (workspace, station) => hooks.lockWaiting?.(inner, workspace, station) ?? null,
  });
}
