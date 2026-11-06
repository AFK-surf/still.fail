// This phone's adb, lent to a station's agents (adb.rs; docs/adb-share.md): the `adbShare` topic and the `adb.*`
// calls. While it is offered (until stopped or its hour is up) a stream on the station's link says so, opened again on
// each link that takes the place of one, and every stream the station opens on that link is a tunnel to the phone's
// own adbd. The offers kept in memory only: a core started anew offers again as its app asks (the grants it lends
// for kept on the device: GRANTS_KEY). Only a host with TCP reaches adbd.
import { Deferred, Effect, Fiber, Scope, Semaphore } from "effect";
import type { AdbCall, Offer } from "./adb-parse.ts";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { current, t } from "./i18n.ts";
import type { IrohStream } from "./iroh.ts";
import { canonical } from "./lock.ts";
import type { CredentialSource, Link, Mesh } from "./mesh.ts";
import type { Runner } from "./runtime.ts";
import { PersonalLock, grantHolds } from "./personal-lock.ts";
import { StationAddr } from "./station/addr.ts";
import { Retold } from "./station/retold.ts";
import { LANG_HEADER } from "./station/requests.ts";
import type { RequestHead } from "./station/wire.ts";
import type { Store } from "./store.ts";
import { fromUtf8, hex, parseJson, sha256, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The identity used both to show a chat once and to take back everything behind its row.
function grantChat(g: J): string {
  return typeof g.chat === "string" && g.chat !== "" ? g.chat : typeof g.session === "string" && g.session !== "" ? g.session : g.id;
}

const RETRY_MS = 1_000;
/// An unresponsive station must not hold up every later read of its grants indefinitely.
const GRANTS_READ_MS = 60_000;
// The checked expiry on a transient row: reuse it for lending without verifying the same signature twice.
const SIGNED_UNTIL = Symbol("signed grant expiry");
/// The grants taken back here: a station that goes on saying one lends nothing.
export const REVOKED_KEY = "adb-revoked";
// Kept in the same atomic value as the old id→expiry map. Old clients ignore this field and cannot enforce it.
const REVOKED_CHATS = "\u0000stillfail-chats-v1";
/// Terminal requests reported by a station, scoped to that station and kept separately from local chat take-backs.
const REVOKED_REMOTE = "\u0000stillfail-remote-ends-v1";

const stationScope = (station: string) => JSON.stringify([station]);
const chatScope = (station: string, chat: string) => JSON.stringify([station, chat]);

/// A local approval is of these exact signed bytes, never of an id or a station-supplied timestamp alone.
function signedFingerprint(signed: J): string | null {
  if (!signed?.body || typeof signed?.sig?.key !== "string" || typeof signed?.sig?.sig !== "string") return null;
  try {
    return hex(sha256(utf8(canonical({ body: signed.body, sig: { key: signed.sig.key, sig: signed.sig.sig } }))));
  } catch {
    return null;
  }
}

/// What was displayed for an explicit local approval, so an update between drawing the row and tapping it cannot
/// silently change the grant being approved.
function approvalProof(g: J): string | null {
  try {
    return hex(sha256(utf8(canonical({ station: g.station, id: g.id, session: g.session, chat: g.chat, scope: g.scope, exp: g.exp, reason: typeof g.reason === "string" ? g.reason : "", title: typeof g.chatTitle === "string" ? g.chatTitle : "", signed: signedFingerprint(g.signed) }))));
  } catch {
    return null;
  }
}

/// Where this person's chats' grants of their phone are kept on the device, as the stations last said them: a core
/// started anew (the app's process gone and back, the phone started again) lends it to them at once, not only once
/// each station is reached again.
export const GRANTS_KEY = "adb-grants";
// A terminal request is also kept in the grant cache. The row alone does not lend on older clients, which do not
// understand its terminal meaning and can still accept a later replay.
const GRANT_REMOTE_END = "\u0000stillfail-remote-end-v1";
/// Where this phone's 共享调试 switch is kept (2026-10-30, user: 「全局的 adb 开关，默认关闭，开启后永远开启，不会因为更新或者重启关掉」):
/// off, it lends to no chat whatever is granted; on, until turned off here. None kept (a core from before it): on where a
/// grant was live, as it lent then.
export const ON_KEY = "adb-on";
const RETRY_MAX_MS = 30_000;

type Ended = { changed: true } | { expired: true } | { refused: string } | { lost: string | null; pause: boolean };

export type AdbEnv = {
  host: Host;
  /// The unwrapped host: overlapping cores on it share the same local revocations.
  revocationsHost?: Host;
  runner: Runner;
  store: Store;
  mesh: () => Effect.Effect<Mesh, CoreError>;
  credentials: (workspace: string) => CredentialSource;
  /// The relays a workspace has of its own, the ways it turned off (`Mesh.link`).
  relays: (workspace: string) => string[];
  off?: (workspace: string) => string[];
  /// Whether this device has an adb to lend: a phone's own adbd, which only an Android device runs (as it said it is:
  /// `client.device`), reached over TCP; a Mac's or a PC's core reaches TCP too, and has none.
  lends: () => boolean;
  /// The person's own lock (personal-lock.ts): whose a workspace's grants are, who this device speaks for, and how it
  /// joins (views/pair.ts).
  personal: PersonalLock;
  subOf: (workspace: string) => string | null;
  /// The accounts signed in here: each has a lock of its own.
  subs: () => { sub: string; email: string }[];
  pair: { begin(subs: string[]): Effect.Effect<unknown, CoreError>; code(typed: string): Effect.Effect<unknown, CoreError>; cancel(): void; state(sub: string): J };
};

function head(): RequestHead {
  return { method: "POST", path: "/admin/api/adb", headers: [[LANG_HEADER, current()]] };
}

function message(said: string): string | null {
  const v = parseJson(utf8(said)) as J;
  return typeof v?.message === "string" ? v.message : null;
}

/// One line off a stream; what followed stays in `carry`.
function readLine(stream: IrohStream, carry: { bytes: Uint8Array }): Effect.Effect<string | null, CoreError> {
  return Effect.gen(function* () {
    for (;;) {
      const at = carry.bytes.indexOf(10);
      if (at >= 0) {
        const line = fromUtf8(carry.bytes.subarray(0, at));
        carry.bytes = carry.bytes.slice(at + 1);
        return line;
      }
      const chunk = yield* Effect.mapError(stream.read(), (e) => CoreError.plainly("mesh", e, t("core-logic.mesh.cut")));
      if (chunk === null) return null;
      const next = new Uint8Array(carry.bytes.length + chunk.length);
      next.set(carry.bytes, 0);
      next.set(chunk, carry.bytes.length);
      carry.bytes = next;
    }
  });
}

/// This phone lent to one station: its offer, the stream saying it, the tunnels the station opens.
class Lend {
  readonly #env: AdbEnv;
  /// A grant-backed lending's fallback deadline is not a grant's expiry and is not shown.
  readonly #grantBased: boolean;
  #offer: Offer | null = null;
  #until = 0;
  #run = 0;
  #phase: "connecting" | "offered" | null = null;
  #station: J = null;
  #problem: string | null = null;
  #tunnels = 0;
  /// The connect port a tunnel last found nothing listening on: the app looks for adbd's ports anew as it hears of it.
  #refused: number | null = null;
  /// The offer's keeper, and its tunnels' scope: closed as the offer stops or moves to another station.
  #keeper: Fiber.Fiber<unknown, unknown> | null = null;
  #tunnelScope: Scope.Closeable | null = null;
  /// The links tunnels are taken on now (each in the tunnels' scope, until it closes).
  readonly #accepting = new Set<Link>();
  #changed: Deferred.Deferred<void> = Deferred.makeUnsafe<void>();

  constructor(env: AdbEnv, grantBased = false) {
    this.#env = env;
    this.#grantBased = grantBased;
  }

  run(call: AdbCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "share":
        if (!this.#env.lends()) return Effect.fail(new CoreError("unsupported", t("core-misc.adb.unsupported")));
        return Effect.sync(() => {
          this.#share(call.offer);
          return null;
        });
      case "stop":
        return Effect.sync(() => {
          this.#stop(null);
          return null;
        });
      case "pair": {
        const code = [...call.code].filter((c) => c >= "0" && c <= "9").join("");
        if (code.length !== 6) return Effect.fail(CoreError.invalid(t("core-misc.adb.pair_code")));
        return this.#ask({ op: "pair", code });
      }
      case "grant":
        return this.#ask({ op: "grant" });
      default:
        return Effect.fail(CoreError.invalid("adb: not a call of one lending"));
    }
  }

  /// The `adbShare` topic.
  value(): J {
    const said = (field: string) => (typeof this.#station?.[field] === "string" && this.#station[field] !== "" ? (this.#station[field] as string) : null);
    const phase = this.#offer === null ? "off" : this.#phase === "offered" ? "offered" : "connecting";
    return {
      sharing: this.#offer !== null,
      station: this.#offer?.station ?? null,
      phase,
      serial: this.#offer !== null ? said("serial") : null,
      adb: phase === "offered" ? said("adb") : null,
      message: this.#problem ?? (phase === "offered" ? said("message") : null),
      until: this.#offer !== null && !this.#grantBased ? Math.trunc(this.#until) : null,
      tunnels: this.#tunnels,
      connectPort: this.#offer?.connect ?? null,
      pairPort: this.#offer?.pair ?? null,
      refusedPort: this.#offer !== null && this.#refused === this.#offer.connect ? this.#refused : null,
      // The chats whose own screens are up on the phone (the station's displays.ts), for the notification.
      screens: this.#offer !== null && Array.isArray(this.#station?.screens) ? (this.#station.screens as unknown[]).filter((t): t is string => typeof t === "string") : [],
    };
  }

  /// A link to a station's 共享调试 as a message shows it (the `adbCard` topic): what it is, and in a line how this
  /// phone's adb stands with that station (a legacy timed offer's minutes left, if any).
  card(station: string): J {
    const title = t("core-views.adb.card.title");
    const sharing = this.#offer !== null && this.#offer.station === station;
    if (!this.#env.lends()) return { title, line: t("core-misc.adb.unsupported"), sharing: false, lendable: false };
    if (this.#offer === null) return { title, line: t("core-views.adb.card.off"), sharing, lendable: true };
    if (!sharing) return { title, line: t("core-views.adb.card.elsewhere"), sharing, lendable: true };
    const view = this.value();
    const minutes = Math.max(0, Math.floor((this.#until - this.#env.host.nowMs()) / 60_000));
    const line = view.phase !== "offered"
      ? (view.message ?? t("core-views.adb.card.connecting"))
      : view.adb === "connected"
        ? (this.#grantBased ? t("core-views.adb.card.shared") : t("core-views.adb.card.connected", { n: minutes }))
        : view.adb === "unpaired"
          ? t("core-views.adb.card.unpaired")
          : view.adb === "off"
            ? t("core-views.adb.card.wireless_off")
            : view.adb === "missing"
              ? t("core-views.adb.card.missing")
              : (view.message ?? (view.adb === "connecting" || view.adb === null ? t("core-views.adb.card.attaching") : t("core-views.adb.card.failed")));
    return { title, line, sharing, lendable: true };
  }

  /// What the cards say, again: the device said what it is (`client.device`), and with it whether it lends.
  deviceTold(): void {
    this.#env.store.invalidateAll((topic) => topic.topic === "adbCard");
  }

  #shown(): void {
    this.#env.store.invalidate({ topic: "adbShare" });
    this.#env.store.invalidateAll((topic) => topic.topic === "adbCard");
  }

  #tellChanged(): void {
    Deferred.doneUnsafe(this.#changed, Effect.void);
    this.#changed = Deferred.makeUnsafe<void>();
  }

  #closeTunnels(): void {
    if (this.#tunnelScope) {
      const scope = this.#tunnelScope;
      this.#tunnelScope = null;
      this.#env.runner.fork(Scope.close(scope, { _tag: "Success", value: undefined } as never));
    }
  }

  #share(offer: Offer): void {
    // The same offer again (the app lends at the tap, its service offers once it has started): nothing to make anew.
    const now = this.#offer;
    if (now !== null && (Object.keys(offer) as (keyof Offer)[]).every((k) => offer[k] === now[k])) return;
    if (this.#offer === null || this.#offer.station !== offer.station) {
      this.#station = null;
      this.#closeTunnels();
      this.#until = this.#env.host.nowMs() + offer.minutes * 60_000;
    }
    if (offer.connect !== this.#refused) this.#refused = null;
    this.#offer = offer;
    const run = ++this.#run;
    this.#problem = null;
    this.#phase = "connecting";
    this.#tellChanged();
    this.#shown();
    this.#keeper = this.#env.runner.fork(this.#keep(run)) as Fiber.Fiber<unknown, unknown>;
  }

  /// Offered again at once (this phone paired with its own adbd): the station connects anew now, not as its retry comes.
  again(): void {
    if (this.#offer === null) return;
    const run = ++this.#run;
    this.#problem = null;
    this.#phase = "connecting";
    this.#tellChanged();
    this.#shown();
    this.#keeper = this.#env.runner.fork(this.#keep(run)) as Fiber.Fiber<unknown, unknown>;
  }

  /// The ports of what it offers now (null: it offers nothing).
  ports(): Offer | null {
    return this.#offer;
  }

  #stop(why: string | null): void {
    this.#offer = null;
    this.#run++;
    this.#phase = null;
    this.#station = null;
    this.#problem = why;
    this.#tellChanged();
    this.#closeTunnels();
    this.#shown();
  }

  #current(run: number): Offer | null {
    return this.#run === run ? this.#offer : null;
  }

  #keep(run: number): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      let pause = RETRY_MS;
      for (;;) {
        const offer = this.#current(run);
        if (offer === null) return;
        const ended = yield* Effect.scoped(this.#offerOnce(run, offer));
        if (this.#current(run) === null) return;
        if ("changed" in ended) return;
        if ("expired" in ended) return this.#stop(t("core-misc.adb.expired"));
        if ("refused" in ended) return this.#stop(ended.refused);
        this.#phase = "connecting";
        this.#problem = ended.lost;
        this.#shown();
        if (ended.pause) {
          yield* Effect.sleep(pause);
          pause = Math.min(pause * 2, RETRY_MAX_MS);
        } else pause = RETRY_MS;
      }
    });
  }

  #link(station: string): Effect.Effect<[Mesh, Link], CoreError> {
    return Effect.gen({ self: this }, function* () {
      const addr = StationAddr.parse(station);
      const mesh = yield* this.#env.mesh();
      const link = yield* mesh.link(addr.toString(), this.#env.credentials(addr.workspace), this.#env.relays(addr.workspace), this.#env.off?.(addr.workspace));
      return [mesh, link] as [Mesh, Link];
    });
  }

  /// One stream of the offer on the station's link now, and the tunnels the station opens on that link meanwhile.
  #offerOnce(run: number, offer: Offer): Effect.Effect<Ended, never, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const changed = this.#changed;
      const opened = yield* Effect.result(this.#link(offer.station));
      if (opened._tag === "Failure") return { lost: opened.failure.message, pause: true } as Ended;
      const [mesh, link] = opened.success;
      // `connect`: the station connects anew as adbd's port changes (adbd turned off and on, its port with it).
      const ask = { op: "share", phone: mesh.deviceId(), device: offer.device, android: offer.android, package: offer.package, adbd: offer.connect !== null, pair: offer.pair !== null && this.#env.host.adb === undefined, connect: offer.connect };
      const replied = yield* Effect.result(link.adb(head(), ask));
      if (replied._tag === "Failure") return { lost: replied.failure.message, pause: true } as Ended;
      const reply = replied.success;
      // Dropped with the offer: the station sees it stop.
      yield* Effect.addFinalizer(() => Effect.sync(() => reply.cancel()));
      if (reply.status === 404 || reply.status === 405) return { refused: t("core-misc.adb.station_too_old") } as Ended;
      if (reply.status !== 200) {
        const parts: Uint8Array[] = [];
        for (;;) {
          const chunk = yield* Effect.orElseSucceed(reply.body.take, () => null);
          if (chunk === null) break;
          parts.push(chunk);
        }
        const said = fromUtf8(new Uint8Array(parts.flatMap((p) => [...p])));
        return { lost: message(said) ?? t("core-misc.adb.not_accepted"), pause: true } as Ended;
      }
      if (this.#current(run) === null) return { changed: true } as Ended;
      this.#phase = "offered";
      this.#problem = null;
      this.#shown();
      if (this.#tunnelScope === null) this.#tunnelScope = yield* Scope.make();
      const tunnels = this.#tunnelScope;
      const self = this;
      const hears = Effect.gen(function* () {
        let carry = new Uint8Array();
        for (;;) {
          const chunk = yield* Effect.orElseSucceed(reply.body.take, () => null);
          if (chunk === null) break;
          const next = new Uint8Array(carry.length + chunk.length);
          next.set(carry, 0);
          next.set(chunk, carry.length);
          carry = next;
          for (;;) {
            const at = carry.indexOf(10);
            if (at < 0) break;
            const said = parseJson(carry.subarray(0, at));
            carry = carry.slice(at + 1);
            if (said !== undefined && self.#current(run) !== null) {
              self.#station = said;
              self.#shown();
            }
          }
        }
        return { lost: t("core-misc.adb.station_ended"), pause: true } as Ended;
      });
      // The station opens its tunnels on the link its latest offer came on, and it hears of an offer on another link only
      // once that one is made: tunnels are taken on every link an offer went on for as long as it lasts (or the offer
      // stops), not only while it is the one offered on (2026-10-17: one opened as the link was replaced went unanswered).
      if (!this.#accepting.has(link)) {
        this.#accepting.add(link);
        const accepting = Effect.gen(function* () {
          for (;;) {
            const stream = yield* link.accept();
            if (stream === null) break;
            self.#env.runner.fork(Effect.provideService(self.#tunnel(stream), Scope.Scope, tunnels));
          }
        }).pipe(Effect.ensuring(Effect.sync(() => this.#accepting.delete(link))));
        const fiber = this.#env.runner.fork(accepting) as Fiber.Fiber<unknown, unknown>;
        yield* Scope.addFinalizer(tunnels, Fiber.interrupt(fiber));
      }
      const gone = Effect.map(link.conn.closed(), () => ({ lost: link.closed() ?? t("core-misc.adb.link_lost"), pause: true }) as Ended);
      const replaced = Effect.as(mesh.replaced(StationAddr.parse(offer.station).toString(), link), { lost: null, pause: false } as Ended);
      const stopped = Effect.as(Deferred.await(changed), { changed: true } as Ended);
      const left = Math.max(this.#until - this.#env.host.nowMs(), 0);
      const expired = Effect.as(Effect.sleep(left), { expired: true } as Ended);
      const ended = yield* Effect.raceAllFirst([hears, gone, replaced, stopped, expired]);
      if (!("changed" in ended) && this.#env.host.nowMs() >= this.#until) return { expired: true } as Ended;
      return ended;
    });
  }

  /// One tunnel the station opened: to adbd's port it names, then its bytes both ways. Served by the offer as it is when
  /// its head comes, not the one it came on: the phone offers again as its ports change (twice within 1.5 s,
  /// 2026-10-17), and one opened in between was turned down as 已停止共享.
  #tunnel(stream: IrohStream): Effect.Effect<void, never, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const refuse = (why: string) => Effect.ignore(Effect.andThen(stream.write(utf8(`${JSON.stringify({ error: why })}\n`)), stream.finish()), { log: "Unhandled", message: "debugging refused" });
      const carry = { bytes: new Uint8Array() };
      const line = yield* Effect.orElseSucceed(readLine(stream, carry), () => null);
      if (line === null) return;
      const kind = (parseJson(utf8(line)) as J)?.tunnel;
      const offer = this.#offer;
      if (offer === null) return yield* refuse("已停止共享");
      const port = kind === "connect" ? offer.connect : kind === "pair" ? offer.pair : null;
      if (port === null) return yield* refuse(kind === "connect" ? "手机未开启无线调试" : kind === "pair" ? "手机未打开配对窗口" : "无法识别的通道");
      // This device's own adb session where its host has one (the shell's adb.rs): the station's adb carried on the one
      // session the phone holds to adbd, under the phone's own key, so a station is never paired and a station restarted
      // leaves adbd's session be. Elsewhere, adbd's port itself.
      const own = kind === "connect" ? this.#env.host.adb : undefined;
      const tcp = yield* Effect.result(own !== undefined ? Effect.andThen(own.hold(port), own.open()) : this.#env.host.tcp!(port));
      if (tcp._tag === "Failure") {
        if (own !== undefined && tcp.failure.message === "unpaired")
          return yield* Effect.ignore(Effect.andThen(stream.write(utf8(`${JSON.stringify({ error: t("core-misc.adb.unpaired"), unpaired: true })}\n`)), stream.finish()), { log: "Unhandled", message: "debugging refused" });
        // Nothing at the port the app found (adbd gone from it): said, so that it looks for the port again.
        if (kind === "connect" && this.#offer === offer && this.#refused !== port) {
          this.#refused = port;
          this.#shown();
        }
        return yield* refuse(`无法连接手机上的 adb：${tcp.failure.message}`);
      }
      const conn = tcp.success;
      const ok = yield* Effect.result(stream.write(utf8(`${JSON.stringify({ ok: true })}\n`)));
      if (ok._tag === "Failure") return;
      this.#tunnels++;
      this.#shown();
      const up = Effect.gen(function* () {
        for (;;) {
          const chunk = yield* Effect.orElseSucceed(conn.read.take, () => null);
          if (chunk === null) break;
          const w = yield* Effect.result(stream.write(chunk));
          if (w._tag === "Failure") break;
        }
        yield* Effect.ignore(stream.finish(), { log: "Unhandled", message: "debugging stream finished" });
      });
      const down = Effect.gen(function* () {
        if (carry.bytes.length > 0) yield* Effect.ignore(conn.write(carry.bytes), { log: "Unhandled", message: "debugging bytes passed on" });
        for (;;) {
          const chunk = yield* Effect.orElseSucceed(stream.read(), () => null);
          if (chunk === null) break;
          const w = yield* Effect.result(conn.write(chunk));
          if (w._tag === "Failure") break;
        }
        conn.end();
      });
      yield* Effect.all([up, down], { concurrency: "unbounded", discard: true }).pipe(
        Effect.ensuring(
          Effect.sync(() => {
            this.#tunnels = Math.max(this.#tunnels - 1, 0);
            this.#shown();
          }),
        ),
      );
    });
  }

  /// An ask about the offer (`pair`, `grant`) on the station's link now.
  #ask(ask: J): Effect.Effect<unknown, CoreError> {
    const offer = this.#offer;
    if (offer === null) return Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing")));
    return this.askAt(offer.station, ask);
  }

  /// An ask of station `station` on its link now: what it answered (JSON), or its words as the error.
  askAt(station: string, ask: J, beforeSend?: () => CoreError | null): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const [mesh, link] = yield* this.#link(station);
      const refused = beforeSend?.();
      if (refused) return yield* Effect.fail(refused);
      const reply = yield* link.adb(head(), { ...ask, phone: mesh.deviceId() }, beforeSend);
      const parts: Uint8Array[] = [];
      for (;;) {
        const chunk = yield* Effect.mapError(reply.body.take, (e) => CoreError.plainly("mesh", e, t("core-logic.mesh.cut")));
        if (chunk === null) break;
        parts.push(chunk);
      }
      const body = fromUtf8(new Uint8Array(parts.flatMap((p) => [...p])));
      const said = message(body) ?? "";
      if (reply.status === 200) return { message: said, ...((parseJson(utf8(body)) as J) ?? {}) };
      return yield* Effect.fail(CoreError.invalid(said === "" ? t("core-misc.adb.failed", { status: reply.status }) : said));
    });
  }
}

type Revocations = {
  ids: Set<string>;
  remoteEnds: Set<string>;
  /// Scopes taken back on this phone, and only exact signatures explicitly approved again here.
  chats: Map<string, Map<string, number>>;
  /// A revoke made before loading must not be overwritten by an older saved scope.
  chatsTouched: Set<string>;
  loaded: boolean;
  dirty: boolean;
  version: number;
  error: CoreError | null;
  writer: ReturnType<typeof Semaphore.makeUnsafe>;
  /// One host may have overlapping cores; all grant snapshots use the same write order.
  grantWriter: ReturnType<typeof Semaphore.makeUnsafe>;
  /// Whole reads from the same station must be applied in the order they were asked, across overlapping cores.
  grantReaders: Map<string, ReturnType<typeof Semaphore.makeUnsafe>>;
  grantVersion: number;
  grantLoaded: boolean;
  grantDirty: boolean;
  grantError: CoreError | null;
  grantTouched: Map<string, Set<string>>;
  grants: Map<string, Map<string, J>>;
  retold: Retold;
  listeners: Set<() => void>;
};

// Separate cores can overlap while one closes. Share both the write order and the in-memory deny list on one host.
const revocationsByHost = new WeakMap<Host, Revocations>();
function revocationsOf(host: Host): Revocations {
  let state = revocationsByHost.get(host);
  if (!state) {
    state = { ids: new Set(), remoteEnds: new Set(), chats: new Map(), chatsTouched: new Set(), loaded: false, dirty: false, version: 0, error: null, writer: Semaphore.makeUnsafe(1), grantWriter: Semaphore.makeUnsafe(1), grantReaders: new Map(), grantVersion: 0, grantLoaded: false, grantDirty: false, grantError: null, grantTouched: new Map(), grants: new Map(), retold: new Retold(), listeners: new Set() };
    revocationsByHost.set(host, state);
  }
  return state;
}

/// This phone's adb (docs/adb-share.md): while its switch is on (`adb.on`), lent to each station a chat's grant of it is live on (`wanted`), with the ports
/// its app found (`adb.ports`); and, from an app before grants, to the one station its switch lent it to (`adb.share`).
/// The grants, every station's, as each says them; decided and taken back here (`adb.decide`, `adb.revoke`).
export class Adb {
  /// How a grant is checked (a test of the lending itself takes every grant as the station says it).
  check: typeof grantHolds = grantHolds;
  readonly #env: AdbEnv;
  readonly #legacy: Lend;
  readonly #lends = new Map<string, Lend>();
  #ports: Omit<Offer, "station" | "minutes"> | null = null;
  /// This person's chats' grants of their phone (and requests waiting), by station address and id.
  readonly #grants: Map<string, Map<string, J>>;
  readonly #retold: Retold;
  /// Their 默认最长授权 as last set here or said by a station.
  #lasts: "hour" | "chat" = "chat";
  /// Whether the grants kept on the device were read (`adbShare` `known`): before, none known is not none granted.
  #known = false;
  #switchRead = false;
  /// This phone's 共享调试 switch (ON_KEY): it lends only while on.
  #on = false;
  #switched = false;
  #defaultOn = false;
  readonly #revocations: Revocations;
  /// The stations from before signatures.
  readonly #old = new Set<string>();
  /// What wakes #sync as the next grant ends by what was signed for it (a station that does not say so lends no longer).
  #stopWake: (() => void) | null = null;

  constructor(env: AdbEnv) {
    this.#env = env;
    this.#legacy = new Lend(env);
    const host = env.revocationsHost ?? env.host;
    this.#revocations = revocationsOf(host);
    this.#grants = this.#revocations.grants;
    this.#retold = this.#revocations.retold;
    const changed = () => this.#revocationsChanged();
    this.#revocations.listeners.add(changed);
    env.runner.fork(Effect.ensuring(Effect.never, Effect.sync(() => {
      this.#revocations.listeners.delete(changed);
      // A call can outlive the core's root scope. Keep its writer and pending denials shared with a new core on this
      // host until the host itself is collected, even after the last listener leaves.
    })));
    env.runner.fork(Effect.ignore(this.#ensureRevocations(), { log: "Unhandled", message: "debugging grants taken back read" }));
    env.runner.fork(Effect.ignore(this.#ensureGrants(), { log: "Unhandled", message: "debugging grants read" }));
    env.runner.fork(
      Effect.ensuring(
        Effect.map(Effect.orElseSucceed(env.host.storageGet(ON_KEY), () => null), (on) => {
          const said = on === null ? null : parseJson(on);
          // (switched before it was read: as switched)
          if (this.#switched) return;
          if (typeof said === "boolean") this.#on = said;
          else {
            // (a core from before the switch: on where a grant lent the phone, so an update does not end its lending)
            this.#defaultOn = true;
          }
        }),
        Effect.sync(() => {
          this.#switchRead = true;
          this.#revocationsChanged();
        }),
      ),
    );
  }

  #revocationsChanged(): void {
    this.#known = this.#switchRead && this.#revocations.grantLoaded;
    if (this.#known && this.#defaultOn && !this.#switched && this.#revocations.grantError === null && this.#revocations.loaded && !this.#revocations.dirty) {
      this.#defaultOn = false;
      this.#on = this.wanted().length > 0;
      this.#keepOn();
    }
    this.#sync();
  }

  #tellRevocations(): void {
    for (const changed of this.#revocations.listeners) changed();
  }

  #loadRevocations(): Effect.Effect<void, CoreError> {
    const state = this.#revocations;
    return state.writer.withPermits(1)(Effect.gen({ self: this }, function* () {
      if (state.loaded) return;
      const read = yield* Effect.result(Effect.mapError(this.#env.host.storageGet(REVOKED_KEY), asCoreError));
      if (read._tag === "Failure") {
        state.error = read.failure;
        this.#tellRevocations();
        return yield* Effect.fail(read.failure);
      }
      const kept = read.success === null ? {} : parseJson(read.success);
      const malformed = () => {
        const error = new CoreError("adb_revocations_unreadable", t("core-misc.adb.revocationsUnreadable"));
        state.error = error;
        this.#tellRevocations();
        return error;
      };
      if (kept === null || typeof kept !== "object" || Array.isArray(kept)) return yield* Effect.fail(malformed());
      const scopes = (kept as J)[REVOKED_CHATS];
      if (scopes !== undefined && (scopes === null || typeof scopes !== "object" || Array.isArray(scopes))) return yield* Effect.fail(malformed());
      const remote = (kept as J)[REVOKED_REMOTE];
      if (remote !== undefined && (remote === null || typeof remote !== "object" || Array.isArray(remote))) return yield* Effect.fail(malformed());
      for (const [id, until] of Object.entries(kept)) {
        if (id !== REVOKED_CHATS && id !== REVOKED_REMOTE && (!Number.isSafeInteger(until) || (until as number) < 0)) return yield* Effect.fail(malformed());
      }
      const loadedChats = new Map<string, Map<string, number>>();
      for (const [scope, allows] of Object.entries(scopes ?? {})) {
        let parts: unknown;
        try { parts = JSON.parse(scope); } catch { return yield* Effect.fail(malformed()); }
        if (!Array.isArray(parts) || (parts.length !== 1 && parts.length !== 2) || parts.some((p) => typeof p !== "string" || p === "") ||
            JSON.stringify(parts) !== scope || allows === null || typeof allows !== "object" || Array.isArray(allows) ||
            Object.entries(allows).some(([h, until]) => !/^[0-9a-f]{64}$/.test(h) || !Number.isSafeInteger(until) || (until as number) < 0)) {
          return yield* Effect.fail(malformed());
        }
        loadedChats.set(scope, new Map(Object.entries(allows as Record<string, number>)));
      }
      for (const [scope, until] of Object.entries(remote ?? {})) {
        let parts: unknown;
        try { parts = JSON.parse(scope); } catch { return yield* Effect.fail(malformed()); }
        if (!Array.isArray(parts) || parts.length !== 2 || parts.some((p) => typeof p !== "string" || p === "") ||
            JSON.stringify(parts) !== scope || !Number.isSafeInteger(until) || (until as number) < 0) return yield* Effect.fail(malformed());
      }
      // Old clients stored the station's expiry. Its value cannot prove when every signed grant of this id ends.
      for (const id of Object.keys(kept)) if (id !== REVOKED_CHATS && id !== REVOKED_REMOTE) state.ids.add(id);
      for (const scope of Object.keys(remote ?? {})) state.remoteEnds.add(scope);
      for (const [scope, allows] of loadedChats) if (!state.chatsTouched.has(scope)) state.chats.set(scope, allows);
      state.chatsTouched.clear();
      state.loaded = true;
      state.error = null;
      this.#tellRevocations();
    }));
  }

  #saveRevocations(): Effect.Effect<void, CoreError> {
    const state = this.#revocations;
    return state.writer.withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (!state.dirty) return;
      const version = state.version;
      // Older clients understand numbers; retaining ids indefinitely also covers older signed grants without issue time.
      const kept: Record<string, unknown> = Object.fromEntries([...state.ids].map((id) => [id, Number.MAX_SAFE_INTEGER]));
      if (state.chats.size > 0) kept[REVOKED_CHATS] = Object.fromEntries([...state.chats].map(([scope, allows]) => [scope, Object.fromEntries(allows)]));
      if (state.remoteEnds.size > 0) kept[REVOKED_REMOTE] = Object.fromEntries([...state.remoteEnds].map((scope) => [scope, Number.MAX_SAFE_INTEGER]));
      const saved = yield* Effect.result(Effect.mapError(this.#env.host.storageSet(REVOKED_KEY, utf8(JSON.stringify(kept))), asCoreError));
      if (saved._tag === "Failure") {
        state.error = saved.failure;
        this.#tellRevocations();
        return yield* Effect.fail(saved.failure);
      }
      if (version === state.version) state.dirty = false;
      state.error = null;
      this.#tellRevocations();
    })));
  }

  #ensureRevocations(): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.#loadRevocations();
      while (this.#revocations.dirty) yield* this.#saveRevocations();
    });
  }

  /// A failed or corrupt cache read is not an empty cache. A station's whole reply must wait until its old grants are
  /// known, so a missing one can be remembered as ended before a stale copy can be restored offline.
  #loadGrants(): Effect.Effect<void, CoreError> {
    const state = this.#revocations;
    return state.grantWriter.withPermits(1)(Effect.gen({ self: this }, function* () {
      if (state.grantLoaded) return;
      const read = yield* Effect.result(Effect.mapError(this.#env.host.storageGet(GRANTS_KEY), asCoreError));
      const fail = (error: CoreError) => {
        state.grantError = error;
        this.#tellRevocations();
        return error;
      };
      if (read._tag === "Failure") return yield* Effect.fail(fail(read.failure));
      const kept = read.success === null ? {} : parseJson(read.success);
      const bad = kept === null || typeof kept !== "object" || Array.isArray(kept) ||
        Object.entries(kept).some(([station, list]) => station === "" || !Array.isArray(list) || list.some((g: J) =>
          g === null || typeof g !== "object" || Array.isArray(g) || typeof g.id !== "string" || g.id === "" || (g.status !== "pending" && g.status !== "granted")));
      if (bad) return yield* Effect.fail(fail(new CoreError("adb_grants_unreadable", t("core-misc.adb.revocationsUnreadable"))));
      for (const [station, list] of Object.entries(kept as Record<string, J[]>)) {
        const at = this.#grants.get(station) ?? new Map<string, J>();
        const touched = state.grantTouched.get(station);
        for (const g of list) {
          // A terminal marker is local state, not a grant, and must win even over an event heard during this read.
          if (g[GRANT_REMOTE_END] === true) this.#rememberRemoteEnd(station, g.id);
          else if (!touched?.has(g.id) && !at.has(g.id)) at.set(g.id, g);
        }
        this.#grants.set(station, at);
      }
      state.grantTouched.clear();
      state.grantLoaded = true;
      state.grantError = null;
      this.#tellRevocations();
    }));
  }

  #saveGrants(): Effect.Effect<void, CoreError> {
    const state = this.#revocations;
    return state.grantWriter.withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (!state.grantDirty) return;
      const version = state.grantVersion;
      const out: Record<string, J[]> = {};
      const kept = new Map<string, Set<string>>();
      for (const g of this.#allGrants()) {
        const station = g.station as string;
        // A station cannot turn a live row into a local terminal marker by adding our reserved field.
        (out[station] ??= []).push(Object.fromEntries(Object.entries(g).filter(([k]) => k !== "station" && k !== GRANT_REMOTE_END)));
        const ids = kept.get(station) ?? new Set<string>();
        ids.add(g.id);
        kept.set(station, ids);
      }
      // An expired or unverifiable row is not lendable, but it is still a request this phone has seen. The station
      // may have reported a shorter expiry or replaced an earlier valid signature; forgetting its id would make a
      // later complete list miss the take-back. Keep only its identity until the station says it ended or omits it.
      for (const [station, grants] of this.#grants) for (const id of grants.keys()) {
        if (!kept.get(station)?.has(id) && !this.#remoteEnded(station, id)) {
          (out[station] ??= []).push({ id, status: "granted", exp: 0 });
        }
      }
      // A denial and a cache snapshot are independent writes. Keep terminal identities in both so that either one
      // saved before a process ends prevents the other from reviving an already observed take-back after restart.
      for (const scope of state.remoteEnds) {
        const [station, id] = JSON.parse(scope) as [string, string];
        (out[station] ??= []).push({ id, status: "granted", exp: 0, [GRANT_REMOTE_END]: true });
      }
      const saved = yield* Effect.result(Effect.mapError(this.#env.host.storageSet(GRANTS_KEY, utf8(JSON.stringify(out))), asCoreError));
      if (saved._tag === "Failure") {
        state.grantError = saved.failure;
        this.#tellRevocations();
        return yield* Effect.fail(saved.failure);
      }
      if (version === state.grantVersion) state.grantDirty = false;
      state.grantError = null;
      this.#tellRevocations();
    })));
  }

  #ensureGrants(): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.#loadGrants();
      while (this.#revocations.grantDirty) yield* this.#saveGrants();
    });
  }

  /// The shared grant map is written in order even when two cores on this host overlap.
  #keep(): void {
    const state = this.#revocations;
    state.grantVersion++;
    state.grantDirty = true;
    this.#env.runner.fork(Effect.ignore(this.#ensureGrants(), { log: "Unhandled", message: "debugging grants kept" }));
  }

  /// A terminal event is remembered separately: even an older or failed grant-cache write cannot restore it.
  #rememberRemoteEnd(station: string, id: string): void {
    if (station === "" || id === "") return;
    const state = this.#revocations;
    const key = JSON.stringify([station, id]);
    if (state.remoteEnds.has(key)) return;
    state.remoteEnds.add(key);
    state.version++;
    state.dirty = true;
    this.#tellRevocations();
    this.#env.runner.fork(Effect.ignore(this.#ensureRevocations(), { log: "Unhandled", message: "remote debugging grant end kept" }));
  }

  #remoteEnded(station: string, id: string): boolean {
    return this.#revocations.remoteEnds.has(JSON.stringify([station, id]));
  }

  #keepOn(): void {
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(ON_KEY, utf8(JSON.stringify(this.#on))), { log: "Unhandled", message: "debugging switch kept" }));
  }

  run(call: AdbCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "share":
      case "stop":
        return this.#legacy.run(call);
      case "on":
        if (call.on && !this.#env.lends()) return Effect.fail(new CoreError("unsupported", t("core-misc.adb.unsupported")));
        return Effect.gen({ self: this }, function* () {
          if (call.on) {
            yield* this.#ensureRevocations();
            yield* this.#ensureGrants();
          }
          this.#on = call.on;
          this.#switched = true;
          this.#defaultOn = false;
          this.#keepOn();
          this.#sync();
          return null;
        });
      case "retryRevocations":
        return Effect.gen({ self: this }, function* () {
          yield* this.#ensureRevocations();
          yield* this.#ensureGrants();
          return null;
        });
      case "ports":
        // (taken whatever the app said it is so far: what lends waits for it to say it is a phone, `#sync`, `deviceTold`;
        // refused, a service started for kept grants before the app said so stopped and was not started again)
        return Effect.sync(() => {
          this.#ports = call.ports;
          this.#sync();
          return null;
        });
      case "pair": {
        const own = this.#env.host.adb;
        if (own !== undefined && this.#env.lends()) return this.#pairHere(own, call.code);
        const lend = this.#legacy.value().sharing ? this.#legacy : (call.station !== undefined ? this.#lends.get(call.station) : this.#focus());
        return lend === undefined ? Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing"))) : lend.run(call);
      }
      case "grant": {
        const lend = this.#legacy.value().sharing ? this.#legacy : (call.station !== undefined ? this.#lends.get(call.station) : this.#focus());
        return lend === undefined ? Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing"))) : lend.run(call);
      }
      case "decide":
        return Effect.gen({ self: this }, function* () {
          // Allowed on this device's own key, the person asked; refused needs none.
          const signed = call.scope === null ? undefined : yield* this.#signed(call.station, call.request, call.scope, call.chat);
          const current = this.#grants.get(call.station)?.get(call.request);
          const version = this.#revocations.version;
          const beforeSend = signed === undefined ? undefined : () => {
            const b = signed.body;
            const sub = this.#subAt(call.station);
            const same = current && this.#grants.get(call.station)?.get(call.request) === current && current.status === "pending" &&
              b?.station === call.station && b.request === call.request && b.session === current.session && b.chat === current.chat &&
              b.scope === call.scope && Number.isSafeInteger(b.exp) && b.exp > Math.floor(this.#env.host.nowMs() / 1000) &&
              sub !== null && b.sub === sub && this.#env.personal.ready(sub) && this.#env.personal.standing(sub) === "member" &&
              this.#revocations.loaded && !this.#revocations.dirty && this.#revocations.version === version &&
              !this.#locallyBlocked(call.station, { ...current, signed });
            return same ? null : new CoreError("personal_changed", t("core-misc.personal.changed"));
          };
          const refused = beforeSend?.();
          if (refused) return yield* Effect.fail(refused);
          const r = yield* this.#legacy.askAt(call.station, { op: "decide", request: call.request, scope: call.scope, ...(signed ? { signed } : {}) }, beforeSend);
          this.heard(call.station, (r as J)?.request);
          return null;
        });
      case "personalOpen":
        return this.#of(call.sub, (sub) => this.#env.personal.open(sub, t("core-misc.personal.reason.open")));
      case "personalJoin":
        return this.#of(call.sub, (sub) => Effect.gen({ self: this }, function* () {
          yield* Effect.forEach(this.#env.subs(), (a) => Effect.ignore(this.#env.personal.refresh(a.sub), { log: "Unhandled", message: "personal lock read" }), { discard: true });
          yield* this.#env.personal.refresh(sub);
          yield* this.#env.personal.makeKey();
          // Every account here the other device can let it in to, on the one code.
          const others = this.#env.personal.outside(this.#env.subs().map((a) => a.sub));
          return yield* this.#env.pair.begin(others.includes(sub) ? others : [sub, ...others]);
        }));
      case "personalCode":
        // A single code can join several accounts; say which were pinned and which must be tried again, without
        // sending the signed chains back to the view.
        return Effect.map(this.#env.pair.code(call.code), (answer) => {
          if (answer === null || typeof answer !== "object") return null;
          const result = answer as { workspaces?: unknown; failed?: unknown };
          return { workspaces: Array.isArray(result.workspaces) ? result.workspaces : [], failed: Array.isArray(result.failed) ? result.failed : [] };
        });
      case "personalCancel":
        return Effect.sync(() => (this.#env.pair.cancel(), null));
      case "personalRemove":
        return this.#of(call.sub, (sub) => this.#env.personal.removeDevice(sub, call.key, t("core-misc.personal.reason.remove")));
      case "personalForget":
        return this.#of(call.sub, (sub) => this.#env.personal.forget(sub, t("core-misc.personal.reason.forget")));
      case "personalRestart":
        return this.#of(call.sub, (sub) => this.#env.personal.restart(sub, t("core-misc.personal.reason.restart")));
      case "personalConfirm":
        return this.#confirm();
      case "approveHere":
        return this.#approveHere(call.station, call.request, call.proof);
      case "revoke": {
        // One list row represents the whole chat, including multiple agents' grants in that chat.
        const selected = this.#grants.get(call.station)?.get(call.request);
        const matching = selected === undefined ? [] : [...(this.#grants.get(call.station)?.values() ?? [])]
          .filter((g) => grantChat(g) === grantChat(selected))
          .map((g) => g.id as string);
        const live = selected === undefined ? [] : this.#allGrants()
          .filter((g) => g.station === call.station && grantChat(g) === grantChat(selected))
          .map((g) => g.id as string);
        // A station's expiry is not authoritative: even a row it currently says has ended can carry a longer signature.
        const ids = [...new Set([call.request, ...matching])];
        const remote = live.length > 0 ? live : [call.request];
        // Off this phone at once, whatever the station answers or goes on saying.
        for (const id of ids) if (id !== REVOKED_CHATS && id !== REVOKED_REMOTE) this.#revocations.ids.add(id);
        const chat = call.chat && selected?.chat === call.chat ? call.chat : null;
        // If the row changed after it was shown, or an older client did not identify the chat, conservatively cover
        // the whole station. Its next update must not be able to move a hidden grant outside the take-back.
        const scope = chat === null ? stationScope(call.station) : chatScope(call.station, chat);
        this.#revocations.chats.set(scope, new Map());
        this.#revocations.chatsTouched.add(scope);
        this.#revocations.version++;
        this.#revocations.dirty = true;
        this.#tellRevocations();
        return Effect.gen({ self: this }, function* () {
          // Do not report success or resume other grants until this device has durably recorded the revocation.
          yield* this.#ensureRevocations();
          yield* Effect.forEach(remote, (request) => Effect.map(this.#legacy.askAt(call.station, { op: "revoke", request }), (r) => {
            this.heard(call.station, (r as J)?.request);
          }), { discard: true });
          return null;
        });
      }
      case "lasts": {
        // at once here, then told to every station this person's grants are read from (the latest `at` wins there)
        this.#lasts = call.lasts;
        this.#env.store.invalidate({ topic: "adbShare" });
        const at = Math.floor(this.#env.host.nowMs());
        return Effect.as(
          Effect.forEach([...this.#grants.keys()], (station) => Effect.ignore(this.#legacy.askAt(station, { op: "lasts", lasts: call.lasts, at }), { log: "Unhandled", message: "debugging lasts told" }), { concurrency: "unbounded", discard: true }),
          null,
        );
      }
    }
  }

  personal(): PersonalLock {
    return this.#env.personal;
  }

  /// `run` as this account, one signed in here.
  #of<A>(sub: string, run: (sub: string) => Effect.Effect<A, CoreError>): Effect.Effect<A, CoreError> {
    return this.#env.subs().some((a) => a.sub === sub) ? run(sub) : Effect.fail(CoreError.invalid(t("core-misc.personal.noAccount")));
  }

  /// Whose a station's grants are: its workspace's account; not known yet (a phone just started), the only one here.
  #subAt(station: string): string | null {
    let workspace: string;
    try {
      workspace = StationAddr.parse(station).workspace;
    } catch {
      return null;
    }
    return this.#env.subOf(workspace) ?? this.#env.subs()[0]?.sub ?? null;
  }

  /// The grants from before they were signed: each account's signed at one go, the person asked once for each, and told
  /// to their stations.
  #confirm(): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.#ensureRevocations();
      yield* this.#ensureGrants();
      const waiting = this.#allGrants().filter((g) => this.#toConfirm(g));
      const bySub = new Map<string, J[]>();
      for (const g of waiting) {
        const sub = this.#subAt(g.station);
        if (sub !== null) bySub.set(sub, [...(bySub.get(sub) ?? []), g]);
      }
      for (const [sub, grants] of bySub) {
        const version = this.#revocations.version;
        const bodies = grants.map((g) => ({ station: g.station as string, request: g.id as string, session: g.session as string, chat: g.chat as string, scope: g.scope as "hour" | "chat", exp: g.exp as number }));
        const signed = yield* this.#env.personal.signGrants(sub, bodies, t("core-misc.personal.reason.confirm"));
        for (const [i, g] of grants.entries()) {
          yield* this.#ensureRevocations();
          const proof = approvalProof(g);
          const beforeSend = () => {
            const current = this.#allGrants().find((item) => item.station === g.station && item.id === g.id);
            return this.#revocations.version === version && this.#revocations.loaded && !this.#revocations.dirty &&
              current && this.#toConfirm(current) && proof !== null && approvalProof(current) === proof
              ? null : new CoreError("personal_changed", t("core-misc.personal.changed"));
          };
          const refused = beforeSend();
          if (refused) return yield* Effect.fail(refused);
          const r = yield* this.#legacy.askAt(g.station, { op: "sign", request: g.id, signed: signed[i] }, beforeSend);
          this.heard(g.station, (r as J)?.request);
        }
      }
      return null;
    });
  }

  /// A grant live but unsigned, on a station that can carry a signature, and an account whose lock this device is on.
  #toConfirm(g: J): boolean {
    if (!this.#revocations.loaded || this.#revocations.dirty || !this.#revocations.grantLoaded || this.#revocations.grantError !== null || g.status !== "granted" || g.signed != null || this.#revocations.ids.has(g.id) || this.#remoteEnded(g.station, g.id) || this.#scopesFor(g.station, g).length > 0 || this.#old.has(g.station)) return false;
    if ((g.scope !== "hour" && g.scope !== "chat") || !Number.isSafeInteger(g.exp) || g.exp <= Math.floor(this.#env.host.nowMs() / 1000)) return false;
    if (typeof g.session !== "string" || g.session === "" || typeof g.chat !== "string" || g.chat === "") return false;
    const sub = this.#subAt(g.station);
    return sub !== null && this.#env.personal.ready(sub) && this.#env.personal.standing(sub) === "member";
  }

  /// What this device signs to allow a chat a phone (docs/personal-lock.md).
  #signed(station: string, request: string, scope: "hour" | "chat", shownChat?: string): Effect.Effect<J, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.#ensureRevocations();
      yield* this.#ensureGrants();
      if (request === REVOKED_CHATS || request === REVOKED_REMOTE || this.#remoteEnded(station, request)) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      const version = this.#revocations.version;
      const sub = this.#subAt(station);
      if (sub === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noAccount")));
      if (this.#old.has(station)) return yield* Effect.fail(new CoreError("personal_old_station", t("core-misc.personal.oldStation")));
      if (this.#grants.get(station)?.get(request) === undefined) yield* this.readGrants(station);
      const g = this.#grants.get(station)?.get(request);
      if (g === undefined || this.#remoteEnded(station, request)) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      if (typeof g.session !== "string" || g.session === "" || typeof g.chat !== "string" || g.chat === "") return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      // A fresh answer can lift this phone's take-back for its exact signature. Bind that answer to the chat in
      // which the person saw the card, not to a row the station could swap before the tap. Older apps without the
      // chat identity may still refuse a request, but cannot implicitly lift a take-back on that station.
      if ((shownChat !== undefined && shownChat !== g.chat) ||
          (shownChat === undefined && this.#hasTakenBackAt(station)) ||
          (this.#scopesFor(station, g).length > 0 && g.status !== "pending")) {
        return yield* Effect.fail(new CoreError("adb_chat_changed", t("core-misc.adb.chatChanged")));
      }
      if (this.#revocations.ids.has(request) && this.#scopesFor(station, g).length === 0) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      const exp = Math.floor(this.#env.host.nowMs() / 1000) + (scope === "hour" ? 3600 : 30 * 86400);
      const signed = yield* this.#env.personal.signGrant(sub, { station, request, session: g.session, chat: g.chat, scope, exp, ...(shownChat !== undefined ? { chatBound: true as const } : {}) }, t("core-misc.personal.reason.grant"));
      yield* this.#ensureRevocations();
      if (this.#revocations.version !== version || this.#grants.get(station)?.get(request) !== g || exp <= Math.floor(this.#env.host.nowMs() / 1000)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      yield* this.#allowHere(station, g, signed, exp);
      return signed;
    });
  }

  /// Every applicable take-back must have explicitly accepted the exact grant again on this phone.
  #scopesFor(station: string, g: J): string[] {
    const scopes = new Set([stationScope(station)]);
    if (typeof g.chat === "string" && g.chat !== "") scopes.add(chatScope(station, g.chat));
    // Legacy signatures and bulk confirmations do not prove which chat the person saw. A station cannot evade a
    // take-back by presenting such a signature as a different chat: every take-back at this station applies to it.
    if (g.signed?.body?.chatBound !== true) {
      for (const scope of this.#revocations.chats.keys()) {
        const parts = JSON.parse(scope);
        if (parts[0] === station && parts.length === 2) scopes.add(scope);
      }
    }
    return [...scopes].filter((scope) => this.#revocations.chats.has(scope));
  }

  #hasTakenBackAt(station: string): boolean {
    for (const scope of this.#revocations.chats.keys()) if (JSON.parse(scope)[0] === station) return true;
    return false;
  }

  #allowedUntil(station: string, g: J): number | null {
    if (!this.#revocations.grantLoaded || this.#revocations.grantError !== null) return null;
    if (g.id === REVOKED_CHATS || g.id === REVOKED_REMOTE || this.#remoteEnded(station, g.id)) return null;
    const scopes = this.#scopesFor(station, g);
    if (scopes.length === 0) return this.#revocations.ids.has(g.id) ? null : Number.MAX_SAFE_INTEGER;
    const fingerprint = signedFingerprint(g.signed);
    if (fingerprint === null) return null;
    const limits = scopes.map((scope) => this.#revocations.chats.get(scope)!.get(fingerprint));
    if (limits.some((until) => until === undefined)) return null;
    return Math.min(...limits as number[]);
  }

  #locallyBlocked(station: string, g: J): boolean {
    const until = this.#allowedUntil(station, g);
    return until === null || until <= Math.floor(this.#env.host.nowMs() / 1000);
  }

  /// Record a locally approved signature before it can be sent or used. A later take-back clears these approvals.
  #allowHere(station: string, g: J, signed: J, until: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const scopes = this.#scopesFor(station, { ...g, signed });
      if (scopes.length === 0) return;
      const fingerprint = signedFingerprint(signed);
      if (fingerprint === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      for (const scope of scopes) this.#revocations.chats.get(scope)!.set(fingerprint, until);
      this.#revocations.version++;
      this.#revocations.dirty = true;
      this.#tellRevocations();
      yield* this.#ensureRevocations();
      if (scopes.some((scope) => this.#revocations.chats.get(scope)?.get(fingerprint) !== until)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
    });
  }

  /// Another device may have signed after a take-back, but old signatures have no trusted order. Ask here about this
  /// exact grant before allowing it; an already verified signed grant can be approved while its station is offline.
  #approveHere(station: string, request: string, proof: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.#env.lends() || !this.#env.host.secureAsk) return yield* Effect.fail(new CoreError("unsupported", t("core-misc.adb.unsupported")));
      yield* this.#ensureRevocations();
      yield* this.#ensureGrants();
      const version = this.#revocations.version;
      const g = this.#grants.get(station)?.get(request);
      const shown = this.#allGrants().find((item) => item.station === station && item.id === request);
      const sub = this.#subAt(station);
      const now = Math.floor(this.#env.host.nowMs() / 1000);
      if (!g || g.status !== "granted" || (g.scope !== "hour" && g.scope !== "chat") || !Number.isSafeInteger(g.exp) || g.exp <= now ||
          typeof g.session !== "string" || !g.session || typeof g.chat !== "string" || !g.chat || this.#scopesFor(station, g).length === 0 || sub === null ||
          !shown || approvalProof(shown) !== proof || !this.#locallyBlocked(station, shown)) {
        return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      }
      if (!this.#env.personal.ready(sub) || this.#env.personal.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      let signed = g.signed;
      if (signed == null) {
        if (this.#old.has(station)) return yield* Effect.fail(new CoreError("personal_old_station", t("core-misc.personal.oldStation")));
        const [made] = yield* this.#env.personal.signGrants(sub, [{ station, request, session: g.session, chat: g.chat, scope: g.scope, exp: g.exp }], t("core-misc.personal.reason.grant"));
        signed = made;
      } else {
        if ((this.#signedExpiry({ ...g, station }) ?? 0) <= now) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
        yield* Effect.mapError(this.#env.host.secureAsk(t("core-misc.personal.reason.grant")), asCoreError);
      }
      yield* this.#ensureRevocations();
      if (this.#revocations.version !== version || this.#grants.get(station)?.get(request) !== g ||
          !this.#env.personal.ready(sub) || this.#env.personal.standing(sub) !== "member") {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      if (!signed?.body || !Number.isSafeInteger(signed.body.exp) ||
          (g.signed != null && (this.#signedExpiry({ ...g, station }) ?? 0) <= Math.floor(this.#env.host.nowMs() / 1000))) {
        return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      }
      const until = Math.min(g.exp, signed.body.exp, now + (g.scope === "hour" ? 3600 : 30 * 86400));
      if (until <= Math.floor(this.#env.host.nowMs() / 1000)) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      yield* this.#allowHere(station, g, signed, until);
      if (g.signed == null) {
        const version = this.#revocations.version;
        const beforeSend = () => {
          const same = this.#revocations.loaded && !this.#revocations.dirty && this.#revocations.version === version &&
            this.#grants.get(station)?.get(request) === g && this.#env.personal.ready(sub) && this.#env.personal.standing(sub) === "member" &&
            until > Math.floor(this.#env.host.nowMs() / 1000) && !this.#locallyBlocked(station, { ...g, signed });
          return same ? null : new CoreError("personal_changed", t("core-misc.personal.changed"));
        };
        const refused = beforeSend();
        if (refused) return yield* Effect.fail(refused);
        const r = yield* this.#legacy.askAt(station, { op: "sign", request, signed }, beforeSend);
        this.heard(station, (r as J)?.request);
      }
      return null;
    });
  }

  /// Until when grant `g` holds on this phone (null: it lends nothing on it): signed by a device on the lock pinned here.
  #holds(g: J): number | null {
    if (!this.#revocations.loaded || this.#revocations.dirty || !this.#revocations.grantLoaded || this.#revocations.grantError !== null || g.status !== "granted" || this.#locallyBlocked(g.station, g)) return null;
    const allowed = this.#allowedUntil(g.station, g)!;
    if (Object.hasOwn(g, SIGNED_UNTIL)) {
      const until = g[SIGNED_UNTIL] === null ? null : Math.min(g[SIGNED_UNTIL], allowed);
      return until !== null && until > Math.floor(this.#env.host.nowMs() / 1000) ? until : null;
    }
    const sub = this.#subAt(g.station);
    const chain = sub === null || !this.#env.personal.ready(sub) ? null : this.#env.personal.chain(sub);
    const checked = sub === null || chain === null ? null : this.check(g, g.station, sub, chain.devices, Math.floor(this.#env.host.nowMs() / 1000));
    return checked === null ? null : Math.min(checked, allowed);
  }

  /// A verified signed expiry, including after it has passed: the station's copy cannot lengthen it on screen or disk.
  #signedExpiry(g: J): number | null {
    if (g.signed == null) return null;
    const sub = this.#subAt(g.station);
    const chain = sub === null || !this.#env.personal.ready(sub) ? null : this.#env.personal.chain(sub);
    return sub === null || chain === null ? null : this.check(g, g.station, sub, chain.devices, 0);
  }

  /// The lock pinned here read, and what it lets this phone lend for, as soon as it is known whose it is: a phone started
  /// anew lends before any station is reached.
  accountsKnown(): void {
    for (const { sub } of this.#env.subs()) this.#readPersonal(sub);
  }

  /// Reconsider active lending as soon as a personal lock starts or finishes a local write.
  personalChanged(): void { this.#sync(); }

  #readPersonal(sub: string): void {
    this.#env.runner.fork(Effect.ensuring(Effect.ignore(this.#env.personal.refresh(sub), { log: "Unhandled", message: "personal lock read" }), Effect.sync(() => this.#sync())));
  }

  /// This phone paired with its own adbd (docs/adb-share.md, 2026-10-31): once, whichever station's page or card asked,
  /// and every station it lends to offered again, so that each connects at once.
  #pairHere(own: NonNullable<AdbEnv["host"]["adb"]>, typed: string): Effect.Effect<unknown, CoreError> {
    const code = [...typed].filter((c) => c >= "0" && c <= "9").join("");
    if (code.length !== 6) return Effect.fail(CoreError.invalid(t("core-misc.adb.pair_code")));
    const lends = [this.#legacy, ...this.#lends.values()];
    const offered = lends.map((l) => l.ports()).find((o) => o !== null);
    const ports = this.#ports ?? offered ?? null;
    if (ports === null || ports.pair === null) return Effect.fail(CoreError.invalid(t("core-misc.adb.pairing_closed")));
    const pairing = ports.pair;
    return Effect.gen(function* () {
      yield* Effect.mapError(own.pair(pairing, code), (e) => CoreError.invalid(e.message === "wrong code" ? t("core-misc.adb.wrong_code") : t("core-misc.adb.pair_failed", { error: e.message })));
      if (ports.connect !== null) yield* Effect.ignore(own.hold(ports.connect), { log: "Unhandled", message: "debugging held" });
      for (const l of lends) l.again();
      return { message: t("core-misc.adb.paired") };
    });
  }

  /// A station said how a grant or request of this person's stands (its `adb-grant` event, or a decision's answer).
  heard(station: string, d: J): void {
    if (typeof d?.id !== "string" || d.id === "") return;
    this.#retold.told(station, "adb-grant", d);
    if (d.status !== "pending" && d.status !== "granted") this.#rememberRemoteEnd(station, d.id);
    this.#putGrant(station, d);
    this.#keep();
    this.#tellRevocations();
  }

  #putGrant(station: string, d: J): void {
    if (!this.#revocations.grantLoaded) {
      const touched = this.#revocations.grantTouched.get(station) ?? new Set<string>();
      touched.add(d.id);
      this.#revocations.grantTouched.set(station, touched);
    }
    const at = this.#grants.get(station) ?? new Map<string, J>();
    if (d.status === "pending" || d.status === "granted") at.set(d.id, d);
    else at.delete(d.id);
    this.#grants.set(station, at);
  }

  /// A station's grants read whole, as it is reached (one from before grants answers with none).
  readGrants(station: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      let reader = this.#revocations.grantReaders.get(station);
      if (!reader) {
        reader = Semaphore.makeUnsafe(1);
        this.#revocations.grantReaders.set(station, reader);
      }
      return reader.withPermits(1)(Effect.andThen(this.#loadGrants(), Effect.suspend(() => {
        if (!this.#revocations.loaded || this.#revocations.dirty) this.#env.runner.fork(Effect.ignore(this.#ensureRevocations(), { log: "Unhandled", message: "debugging grants taken back retry" }));
        const sub = this.#subAt(station);
        if (sub !== null) this.#readPersonal(sub);
        const read = this.#retold.asked();
        const ask = Effect.timeoutOrElse(this.#legacy.askAt(station, { op: "grants" }), {
          duration: GRANTS_READ_MS,
          orElse: () => Effect.fail(new CoreError("timeout", t("core-logic.mesh.timed_out"))),
        });
        return Effect.map(Effect.orElseSucceed(ask, () => null), (r) => {
          const list = Array.isArray((r as J)?.grants) ? ((r as J).grants as J[]) : null;
          // A malformed reply is not a complete empty list and cannot prove that a previously known grant ended.
          if (list === null || list.some((g) => typeof g?.id !== "string" || g.id === "" || (g.status !== "pending" && g.status !== "granted"))) return;
          if ((r as J)?.lasts === "hour" || (r as J)?.lasts === "chat") this.#lasts = (r as J).lasts;
          // (one from before signatures drops them: said on its cards, nothing allowed there would lend)
          if ((r as J)?.signs === true) this.#old.delete(station);
          else this.#old.add(station);
          const before = this.#grants.get(station) ?? new Map<string, J>();
          this.#grants.set(station, new Map(list.map((g) => [g.id as string, g])));
          // A change heard while the read was out is newer than the snapshot it brought.
          for (const { data } of this.#retold.since(read, station)) this.#putGrant(station, data as J);
          const after = this.#grants.get(station)!;
          for (const id of before.keys()) if (!after.has(id)) this.#rememberRemoteEnd(station, id);
          this.#keep();
          this.#tellRevocations();
        }).pipe(Effect.ensuring(Effect.sync(() => this.#retold.over(read))));
      })));
    });
  }

  /// The grants live now and the requests waiting, every station's: `{station, id, chat, reason, status, scope, exp}`.
  #allGrants(): J[] {
    const now = this.#env.host.nowMs() / 1000;
    const out: J[] = [];
    for (const [station, at] of this.#grants) {
      for (const g of at.values()) {
        if (this.#remoteEnded(station, g.id)) continue;
        const whole = { ...g, station };
        const signed = this.#signedExpiry(whole);
        const allowed = this.#revocations.loaded && !this.#revocations.dirty ? this.#allowedUntil(station, whole) : null;
        // A local approval can shorten what the signer allowed. Once it expires, show the grant again as needing a
        // fresh confirmation, rather than hiding the option to approve it.
        const cap = allowed !== null && allowed > now ? allowed : Number.MAX_SAFE_INTEGER;
        const until = signed === null ? null : Number.isSafeInteger(g.exp) ? Math.min(signed, g.exp, cap) : null;
        if (whole.signed != null) Object.defineProperty(whole, SIGNED_UNTIL, { value: until });
        if (signed !== null) whole.exp = until ?? 0;
        if (whole.status === "pending" || (whole.status === "granted" && (whole.exp ?? 0) > now)) out.push(whole);
      }
    }
    return out.sort((a, b) => (a.at ?? 0) - (b.at ?? 0));
  }

  /// One row per chat, most recently used first. All underlying grants stay kept and are taken back together.
  grants(): J[] {
    const out = new Map<string, J>();
    for (const whole of this.#allGrants()) {
      const { signed: _signed, ...shown } = whole;
      const sub = this.#subAt(whole.station);
      const standing = sub === null ? "member" : this.#env.personal.standing(sub);
      const localApproval = whole.status === "granted" && typeof whole.session === "string" && whole.session !== "" && typeof whole.chat === "string" && whole.chat !== "" &&
        this.#revocations.loaded && !this.#revocations.dirty && this.#revocations.grantLoaded && this.#revocations.grantError === null && this.#scopesFor(whole.station, whole).length > 0 && this.#locallyBlocked(whole.station, whole) &&
        (whole.signed == null || this.#signedExpiry(whole) !== null);
      const proof = localApproval ? approvalProof(whole) : null;
      const g = {
        ...shown,
        ...(sub !== null ? { sub } : {}),
        ...(whole.status === "granted" ? { held: this.#holds(whole) !== null, unsigned: whole.signed == null } : {}),
        ...(localApproval && proof !== null ? { localApproval: true, approvalProof: proof } : {}),
        ...(whole.status === "pending" && standing !== "member" ? { join: true } : {}),
        ...(this.#old.has(whole.station) ? { oldStation: true } : {}),
      };
      const key = JSON.stringify([g.station, grantChat(g)]);
      const before = out.get(key);
      const used = typeof g.lastUsedAt === "number" ? g.lastUsedAt : 0;
      const wasUsed = typeof before?.lastUsedAt === "number" ? before.lastUsedAt : 0;
      // If any grant of a chat still lends, the row must retain its take-back action even when another needs local
      // approval. Otherwise a newer blocked grant could hide the only control that stops the active one.
      if (before === undefined || (before.status !== "granted" && g.status === "granted") ||
          (before.status === g.status && g.held === true && before.held !== true) ||
          (before.status === g.status && (g.held === true) === (before.held === true) && (used > wasUsed || (used === wasUsed && (g.at ?? 0) > (before.at ?? 0))))) out.set(key, g);
    }
    return [...out.values()].sort((a, b) => (b.lastUsedAt ?? 0) - (a.lastUsedAt ?? 0) || (b.at ?? 0) - (a.at ?? 0));
  }

  /// The stations a grant lends this phone to now.
  wanted(): string[] {
    return [...new Set(this.#allGrants().filter((g) => this.#holds(g) !== null).map((g) => g.station as string))];
  }

  /// Each wanted station lent to (with the ports the app found), each no longer wanted let go.
  #sync(): void {
    const wanted = this.#ports === null || !this.#on || !this.#env.lends() ? [] : this.wanted();
    for (const [station, lend] of this.#lends)
      if (!wanted.includes(station)) {
        this.#env.runner.fork(Effect.ignore(lend.run({ kind: "stop" }), { log: "Unhandled", message: "debugging lend stopped" }));
        this.#lends.delete(station);
      }
    for (const station of wanted) {
      let lend = this.#lends.get(station);
      if (lend === undefined) {
        lend = new Lend(this.#env, true);
        this.#lends.set(station, lend);
      }
      // (lent for as long as a grant is: the grants end it, not its own clock)
      this.#env.runner.fork(Effect.ignore(lend.run({ kind: "share", offer: { ...this.#ports!, station, minutes: 30 * 24 * 60 } }), { log: "Unhandled", message: "debugging lend shared" }));
    }
    this.#env.store.invalidate({ topic: "adbShare" });
    this.#wakeAtEnd();
  }

  /// #sync once more as the first grant it lends on ends, by what was signed: no station need say so.
  #wakeAtEnd(): void {
    this.#stopWake?.();
    this.#stopWake = null;
    const ends = this.#allGrants().map((g) => this.#holds(g)).filter((e): e is number => e !== null);
    if (ends.length === 0) return;
    const wait = Math.max(0, Math.min(...ends) * 1000 + 1 - this.#env.host.nowMs());
    const f = this.#env.runner.fork(Effect.andThen(Effect.sleep(Math.min(wait, 2 ** 31 - 1)), Effect.sync(() => this.#sync())));
    this.#stopWake = () => void Effect.runFork(Fiber.interrupt(f));
  }

  /// The lending a person has something to do for, of those grants made: one whose station's adb waits to be paired
  /// with this phone, else the first. What the topic's own fields say, the pairing dialog's code goes to (its
  /// notification, AdbCodeReader: they name no station) and an ask naming none is of (2026-10-30: a phone lent to a
  /// second station was paired with the first, already paired, and the second never).
  #focus(): Lend | undefined {
    const lends = [...this.#lends.values()];
    return lends.find((l) => {
      const v = l.value();
      return v.phase === "offered" && v.adb === "unpaired";
    }) ?? lends[0];
  }

  /// The `adbShare` topic: the lending as the app's switch made it, or the one a grant made a person has something to do
  /// for (#focus), and every grant and lending.
  value(): J {
    const first = this.#legacy.value().sharing ? this.#legacy : (this.#focus() ?? this.#legacy);
    const lends = [...this.#lends.entries()].map(([station, l]) => {
      const v = l.value();
      return { station, phase: v.phase, adb: v.adb, serial: v.serial, message: v.message, tunnels: v.tunnels };
    });
    // Every station's chats with screens up, not only the first lending's.
    const screens = [...new Set([this.#legacy, ...this.#lends.values()].flatMap((l) => l.value().screens as string[]))];
    const personal = this.#env.subs().map(({ sub, email }) => ({ ...this.#env.personal.view(sub), email, pair: this.#env.pair.state(sub) }));
    const toConfirm = this.#allGrants().filter((g) => this.#toConfirm(g)).length;
    return { ...first.value(), on: this.#on, grants: this.grants(), wanted: this.wanted(), known: this.#known && this.#revocations.grantError === null && this.#revocations.loaded && !this.#revocations.dirty, revocationsError: this.#revocations.error !== null || this.#revocations.grantError !== null, lends, lasts: this.#lasts, screens, personal, toConfirm };
  }

  card(station: string): J {
    return (this.#lends.get(station) ?? this.#legacy).card(station);
  }

  deviceTold(): void {
    this.#legacy.deviceTold();
    this.#sync();
  }
}
