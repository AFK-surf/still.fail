// What the still.fail core does with the device's mesh (mesh.ts, which knows none of it; station/wire.rs `MeshWire`):
// each request to a station on the link to its address, a read asked again on the link put in its place and on another
// way when its own is slow, a write gone unanswered asked again with its key; the cloud's credentials as the mesh
// presents them, the device's claim for a workspace's lock said with them (lock.ts); a station's refusals for that
// lock; what an app's main endpoint takes (a trusted device met face to face); a station's protocol and what the
// mesh is made with for it (`STATION_MESH`); the core's own mesh, brought up on first use.
import { Deferred, Effect, Fiber, type Result } from "effect";
import type { Credential } from "../cloud.ts";
import type { Inner } from "../core.ts";
import { hooks } from "../core/execute.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import type { Iroh } from "../iroh.ts";
import { claimBy } from "../lock.ts";
import { type CredentialSource, type Link, Mesh, type MeshEnv, type Presented, type Reply, relayHost } from "../mesh.ts";
import { PAIR_ALPN } from "../pair.ts";
import * as prefs from "../prefs.ts";
import { RELAY, type Place, type Status } from "../status.ts";
import { route } from "../route.ts";
import { utf8 } from "../util.ts";
import type { StationAddr } from "./addr.ts";
import { IDEMPOTENCY_KEY, IDEMPOTENT, READS } from "./requests.ts";
import type { LinkNet, RequestHead, ScreenAsk, StationWire, WireReply, WireSocket } from "./wire.ts";
import { RECHECKING } from "./words.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The protocol a station takes a device's links on (station/src/mesh/serve.ts `ALPN`).
export const ALPN = utf8("stillfail/admin/1");

/// What a mesh to stations is made with, whatever it runs on (`meshEnv`, and a test's own mesh): their protocol; what
/// each line of a link's control stream says after its credential (`protocol`: 2, the hello a station has always been
/// sent); its peers looked up on the LAN and in the DHT (under still.fail's names: client/shell, station/native/mesh);
/// the key what stations said of their addresses is kept under on the device.
export const STATION_MESH = { alpn: ALPN, says: { protocol: 2 }, lookup: true, addressesKey: "station-addresses" } satisfies Partial<MeshEnv>;

/// How often a read gone slow looks again for another way to be asked on, while there is none.
const HEDGE_RECHECK_MS = 250;
/// How many links in a row a read is asked again on when each is found gone under it.
const LOST_TRIES = 3;
/// How long a write gone unanswered is asked again with its key.
export const RECHECK_MS = 5 * 60 * 1000;

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
  status: (workspace: string) => Status;
  /// The workspace lock (views/lock.ts): a station refused this device for it (`theirs`: how far its own lock goes, as
  /// it said; `told`: the chains of the person's own lock it keeps and the last entries of its lock, as it told them);
  /// why a station is not asked now.
  lockRefused?: (workspace: string, station: string, theirs: unknown, told?: { person?: unknown; entries?: unknown; out?: unknown; left?: unknown }) => CoreError | null;
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
    const refusedFor = (e: CoreError) => (e.code === "lock_unconfirmed" ? (env.lockRefused?.(workspace, id, e instanceof LockUnconfirmed ? e.lock : null, e instanceof LockUnconfirmed ? { person: e.person, entries: e.entries, out: e.out, left: e.left } : undefined) ?? e) : e);
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
      // Why the station ended the connection it came on, as its close said (shell, iroh-wasm and node-iroh give it).
      const ended = () => {
        const r = l.conn.closeReason();
        return r !== null && r.kind === "application" ? r.reason : null;
      };
      return { status: reply.status, headers: reply.headers, body: timed, via: l.path(), relay: relay !== null ? relayHost(relay) : null, ended };
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
      // (its own main id: the link it goes over may be one made for a LAN or a relay, under another; its sound as Opus
      // where what taps the view decodes it, a twentieth of PCM's bytes)
      const [reply, send] = yield* link.duplex(head, { screen: { ...screen, ...(screen.audio && mesh.decodesOpus() ? { opus: true } : {}), self: mesh.deviceId() } });
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
function waiting<A>(status: Status, place: Place, what: string, effect: Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
  return Effect.suspend(() => {
    const w = status.begin(place, what, true);
    return effect.pipe(Effect.ensuring(Effect.sync(() => w.end())));
  });
}

/// Why a station takes none of the workspace's members for a security mode (its hello's `lock_station` `why`): the lock
/// it joined with not brought yet, this workspace locked after it joined, or its own workspace locked and this one not.
function lockStationWords(why: unknown, reason: string): string {
  if (why === "pending" || why === "unpinned" || why === "home") return t(`core-logic.mesh.lock_station.${why}`);
  return t("core-logic.mesh.credential_refused_why", { reason });
}

/// A station's refusal of this device for its workspace lock, with how far its own lock goes (`lock`, as it said) and
/// the chains of the person's own lock it keeps (`person`: a device not on it yet finds who may let it in), and the last
/// entries of its lock (`entries`: one taken out of it hears so).
export class LockUnconfirmed extends CoreError {
  readonly lock: unknown;
  readonly person: unknown;
  readonly entries: unknown;
  /// Where the workspace's chain moved: what took this device out (the removal, its `prev` chain, the log entries that
  /// commit to them; station/src/mesh/serve.ts `toldOut`), taken by the rules as any bodies and logs are.
  readonly out: unknown;
  /// Where the workspace's chain moved and the state in force there does not name this device: whom to ask
  /// (station/src/mesh/serve.ts `leftOf`), a hint.
  readonly left: unknown;
  constructor(message: string, lock: unknown, person?: unknown, entries?: unknown, out?: unknown, left?: unknown) {
    super("lock_unconfirmed", message);
    this.lock = lock;
    this.person = person;
    this.entries = entries;
    this.out = out;
    this.left = left;
  }
}

/// A station's refusal of a link's first line for a workspace's lock, as the mesh asks what a refusal is
/// (`MeshEnv.refusal`): by its answer's `code`; null for any other (the credential's, which the mesh says).
export function refusedForLock(answer: J, reason: string): CoreError | null {
  // A station with a workspace lock that does not know this device yet: it waits to be confirmed (lock.ts).
  if (answer.code === "lock_unconfirmed") return new LockUnconfirmed(t("core-logic.mesh.lock_unconfirmed", { reason }), answer.lock ?? null, answer.person, answer.entries, answer.out, answer.left);
  // A station that takes none of this workspace's members for a security mode, its own or this workspace's not
  // brought to it yet (station/src/cloud/state.ts `leftOut`): why, as it said.
  if (answer.code === "lock_station") return new CoreError("lock_station", lockStationWords(answer.why, reason));
  return null;
}

/// The cloud's credential as the mesh presents it (`Presented`): its `lock`, the device's claim, said with it in the
/// link's first line.
export function presented(c: Credential): Presented {
  return { credential: c.credential, also: c.lock ? { lock: c.lock } : null };
}

/// Each workspace's credentials for the mesh: still.fail cloud's (kept on the device), asked with this device's claim
/// for the endpoint (lock.ts `claimBy`, signed by the mesh that is up: `mesh`).
export function credentialsFor(inner: Inner, mesh: () => Mesh | null): (workspace: string) => CredentialSource {
  return (workspace) => (device, fresh) => {
    const up = mesh();
    return Effect.map(inner.cloudSync.credential(workspace, device, fresh, up?.deviceId() ?? null, up ? claimBy(up, workspace, device) : null), presented);
  };
}

/// What an app's main endpoint takes (a trusted device met face to face: views/pair.ts `hooks.lockPair`); a page's
/// nothing (it approves no one).
function takes(inner: Inner): Pick<MeshEnv, "takes" | "incoming"> {
  if (!inner.host.appKeys) return {};
  return { takes: [PAIR_ALPN], incoming: (connection, alpn) => (alpn.length === PAIR_ALPN.length && alpn.every((b, i) => b === PAIR_ALPN[i]) ? hooks.lockPair?.(inner, connection) : connection.close(0, "no such protocol")) };
}

/// What the core gives its mesh (`Mesh.make`): the host and what runs it, a station's protocol (`STATION_MESH`), what
/// an app's endpoint takes, and what a station refuses a link for besides its credential (a workspace's lock: without
/// it a device waiting to be confirmed is told its credential was refused, and asks the cloud for another at each try).
export function meshEnv(inner: Inner, iroh: Iroh): MeshEnv {
  return { host: inner.host, runner: inner.runner, tracer: inner.tracer, iroh, wakes: inner.wakes, ...STATION_MESH, dht: () => prefs.dhtOn(inner.data), ...takes(inner), refusal: refusedForLock };
}

/// The core's mesh: brought up on first use with the relays any account's `/v1/me` names, the credentials from
/// still.fail cloud (kept on the device).
export function meshWire(inner: Inner): StationWire {
  let mesh: Deferred.Deferred<Mesh, CoreError> | null = null;
  let up: Mesh | null = null;
  const get = (): Effect.Effect<Mesh, CoreError> =>
    Effect.suspend(() => {
      const iroh = inner.iroh;
      if (iroh === null) return Effect.fail(CoreError.plainly("mesh", "no iroh on this host", t("core-logic.mesh.bind_failed")));
      if (mesh !== null) return Deferred.await(mesh);
      const d = Deferred.makeUnsafe<Mesh, CoreError>();
      mesh = d;
      inner.runner.fork(
        Effect.gen(function* () {
          const made = yield* Effect.result(
            Effect.flatMap(inner.cloudSync.relaysNow(), (relays) => Mesh.make(meshEnv(inner, iroh), relays, inner.cloudSync.entriesNow(), inner.cloudSync.entryTargetsNow())),
          );
          if (made._tag === "Success") {
            up = made.success;
            // This run's `/v1/me` may have come while it came up on the relays kept from the last.
            const told = inner.cloudSync.relays;
            if (told !== null) up.retune(told, inner.cloudSync.entriesNow(), inner.cloudSync.entryTargetsNow());
          } else mesh = null;
          Deferred.doneUnsafe(d, made._tag === "Success" ? Effect.succeed(made.success) : Effect.fail(made.failure));
        }),
      );
      return Deferred.await(d);
    });
  inner.mesh = get;
  inner.meshNow = () => up;
  inner.cloudSync.onRelays = (relays, entries, targets) => up?.retune(relays, entries, targets);
  return new MeshWire({
    mesh: get,
    meshNow: () => up,
    credentials: credentialsFor(inner, () => up),
    relays: (workspace) => inner.cloudSync.workspaceRelays(workspace),
    off: (workspace) => inner.cloudSync.workspaceOff(workspace),
    status: (workspace) => inner.workspaces.of(workspace).status,
    lockRefused: (workspace, station, theirs, told) => hooks.lockRefused?.(inner, workspace, station, theirs, told) ?? null,
    lockWaiting: (workspace, station) => hooks.lockWaiting?.(inner, workspace, station) ?? null,
  });
}
