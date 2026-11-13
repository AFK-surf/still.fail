// This phone's adb, lent to a station's agents (adb.rs): the `adbShare` topic and the `adb.*`
// calls. While it is offered (until stopped or its hour is up) a stream on the station's link says so, opened again on
// each link that takes the place of one, and every stream the station opens on that link is a tunnel to the phone's
// own adbd. The offers kept in memory only: a core started anew offers again as its app asks (the grants it lends
// for kept on the device: GRANTS_KEY). Only a host with TCP reaches adbd.
import { Marks } from "./reactive.ts";
import { Deferred, Effect, Fiber, Scope } from "effect";
import { type AdbCall, type Offer, type PhoneScope, SCOPE_SECONDS } from "./adb-parse.ts";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { current, t } from "./i18n.ts";
import type { IrohStream } from "./iroh.ts";
import type { CredentialSource, Link, Mesh } from "./mesh.ts";
import type { Runner } from "./runtime.ts";
import { PersonalLock, grantHolds } from "./personal-lock.ts";
import { StationAddr } from "./station/addr.ts";
import { Retold } from "./station/retold.ts";
import { LANG_HEADER } from "./station/requests.ts";
import type { RequestHead } from "./station/wire.ts";
import type { Store } from "./store.ts";
import { fromUtf8, parseJson, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The identity used both to show a chat once and to take back everything behind its row.
function grantChat(g: J): string {
  return typeof g.chat === "string" && g.chat !== "" ? g.chat : typeof g.session === "string" && g.session !== "" ? g.session : g.id;
}

const RETRY_MS = 1_000;
/// How much of a file the station sends is asked at once (as a chat's file's download asks: views/downloads.ts).
const FETCH_PART = 4 * 1024 * 1024;
/// The grants taken back here (id → when they would have ended): a station that goes on saying one lends nothing.
export const REVOKED_KEY = "adb-revoked";

/// Where this person's chats' grants of their phone are kept on the device, as the stations last said them: a core
/// started anew (the app's process gone and back, the phone started again) lends it to them at once, not only once
/// each station is reached again.
export const GRANTS_KEY = "adb-grants";
/// Where this phone's 共享调试 switch is kept (2026-10-30, user: 「全局的 adb 开关，默认关闭，开启后永远开启，不会因为更新或者重启关掉」):
/// off, it lends to no chat whatever is granted; on, until turned off here. None kept (a core from before it): on where a
/// grant was live, as it lent then.
export const ON_KEY = "adb-on";
const RETRY_MAX_MS = 30_000;

type Ended = { changed: true } | { expired: true } | { refused: string } | { lost: string | null; pause: boolean };

/// What reads the lending (the `adbShare` and `adbCard` topics) is made again as it changes (reactive.ts), by the
/// store its topics are in.
const seens = new WeakMap<Store, Marks>();
function seenOf(store: Store): Marks {
  let seen = seens.get(store);
  if (!seen) seens.set(store, (seen = new Marks()));
  return seen;
}

export type AdbEnv = {
  host: Host;
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
  /// A part of a file sent in a chat of `station` (its session `key`, `name` in its uploads), as a chat's file is
  /// downloaded (station/requests.ts `filePart`): what `#fetch` brings a file the station sends this phone with.
  part?: (station: StationAddr, key: string, name: string, offset: number, length: number) => Effect.Effect<{ total: number; bytes: Uint8Array }, CoreError>;
  /// The person's own lock (personal-lock.ts): whose a workspace's grants are, who this device speaks for, and how it
  /// joins (views/pair.ts).
  personal: PersonalLock;
  /// A device taken off the person's lock here (`removal`, by its id there), then out of the workspaces' locks where
  /// they bound it (views/lock.ts `takeOffBound`, `withBound`): the removal's own answer. None, the removal alone.
  tookOff?: <A, E>(sub: string, id: string, removal: Effect.Effect<A, E>) => Effect.Effect<A, E>;
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
    seenOf(this.#env.store).touch();
  }

  #shown(): void {
    seenOf(this.#env.store).touch();
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
      const replied = yield* Effect.result(link.ask(head(), { adb: ask }));
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
      const asked = parseJson(utf8(line)) as J;
      const kind = asked?.tunnel;
      const offer = this.#offer;
      if (offer === null) return yield* refuse("已停止共享");
      if (asked?.fetch !== undefined) return yield* this.#fetch(stream, offer.station, asked.fetch);
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

  /// A file the station sends this phone (its agent's `phone_send`): `{fetch: {key, name, size}}`, fetched a part at a
  /// time as a chat's file is downloaded and written where adb's shell reads it, going on from what an earlier fetch of
  /// it left. Answered `{at}` after each part, then `{path}`, or `{error, at}`.
  #fetch(stream: IrohStream, station: string, fetch: J): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const say = (said: J) => Effect.ignore(stream.write(utf8(`${JSON.stringify(said)}\n`)), { log: "Unhandled", message: "fetch said" });
      const end = Effect.ignore(stream.finish(), { log: "Unhandled", message: "fetch finished" });
      const stage = this.#env.host.stage?.bind(this.#env.host);
      const part = this.#env.part;
      const { key, name, size } = fetch ?? {};
      if (stage === undefined || part === undefined) return yield* Effect.andThen(say({ error: "unsupported" }), end);
      if (typeof key !== "string" || typeof name !== "string" || !/^[^/\\]+$/.test(name) || name === "." || name === ".." || !Number.isSafeInteger(size) || size < 0)
        return yield* Effect.andThen(say({ error: "invalid fetch" }), end);
      const addr = StationAddr.parse(station);
      const failed = (at: number) => (e: { message: string }) => Effect.andThen(say({ error: e.message, at }), end);
      const had = yield* Effect.result(stage(name, -1, new Uint8Array()));
      if (had._tag === "Failure") return yield* failed(0)(had.failure);
      // (one longer than the file is another's: begun anew)
      let at = had.success.size <= size ? had.success.size : 0;
      let path = had.success.path;
      if (at === 0) {
        const begun = yield* Effect.result(stage(name, 0, new Uint8Array()));
        if (begun._tag === "Failure") return yield* failed(0)(begun.failure);
      }
      while (at < size) {
        const got = yield* Effect.result(part(addr, key, name, at, FETCH_PART));
        if (got._tag === "Failure") return yield* failed(at)(got.failure);
        const { total, bytes } = got.success;
        if (total !== size || bytes.length === 0) return yield* failed(at)({ message: `the station has ${total} bytes of it, not ${size}` });
        const wrote = yield* Effect.result(stage(name, at, bytes));
        if (wrote._tag === "Failure") return yield* failed(at)(wrote.failure);
        at += bytes.length;
        path = wrote.success.path;
        yield* say({ at });
      }
      yield* say({ path });
      yield* end;
    });
  }

  /// An ask about the offer (`pair`, `grant`) on the station's link now.
  #ask(ask: J): Effect.Effect<unknown, CoreError> {
    const offer = this.#offer;
    if (offer === null) return Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing")));
    return this.askAt(offer.station, ask);
  }

  /// An ask of station `station` on its link now: what it answered (JSON), or its words as the error.
  askAt(station: string, ask: J): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const [mesh, link] = yield* this.#link(station);
      const reply = yield* link.ask(head(), { adb: { ...ask, phone: mesh.deviceId() } });
      const parts: Uint8Array[] = [];
      for (;;) {
        const chunk = yield* Effect.mapError(reply.body.take, (e) => CoreError.plainly("mesh", e, t("core-logic.mesh.cut")));
        if (chunk === null) break;
        parts.push(chunk);
      }
      const body = fromUtf8(new Uint8Array(parts.flatMap((p) => [...p])));
      const said = message(body) ?? "";
      if (reply.status === 200) return { message: said, ...((parseJson(utf8(body)) as J) ?? {}) };
      // (the station's code where it gives one, which an app goes by: `adb_grant_refused`, station/src/adb/link.ts)
      const code = (parseJson(utf8(body)) as J)?.code;
      const words = said === "" ? t("core-misc.adb.failed", { status: reply.status }) : said;
      return yield* Effect.fail(typeof code === "string" && code !== "" ? new CoreError(code, words) : CoreError.invalid(words));
    });
  }
}

/// This phone's adb: while its switch is on (`adb.on`), lent to each station a chat's grant of it is live on (`wanted`), with the ports
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
  readonly #grants = new Map<string, Map<string, J>>();
  readonly #retold = new Retold();
  /// Whether the grants kept on the device were read (`adbShare` `known`): before, none known is not none granted.
  #known = false;
  /// This phone's 共享调试 switch (ON_KEY): it lends only while on.
  #on = false;
  #switched = false;
  readonly #revoked = new Map<string, number>();
  /// The stations from before signatures.
  readonly #old = new Set<string>();
  /// What wakes #sync as the next grant ends by what was signed for it (a station that does not say so lends no longer).
  #stopWake: (() => void) | null = null;

  constructor(env: AdbEnv) {
    this.#env = env;
    this.#legacy = new Lend(env);
    env.runner.fork(Effect.ignore(Effect.map(env.host.storageGet(REVOKED_KEY), (bytes) => {
      const kept = bytes === null ? null : (parseJson(bytes) as J);
      if (kept !== null && typeof kept === "object") for (const [id, until] of Object.entries(kept)) if (typeof until === "number") this.#revoked.set(id, until);
      this.#sync();
    }), { log: "Unhandled", message: "debugging grants taken back read" }));
    env.runner.fork(
      Effect.ensuring(
        Effect.map(Effect.all([Effect.orElseSucceed(env.host.storageGet(GRANTS_KEY), () => null), Effect.orElseSucceed(env.host.storageGet(ON_KEY), () => null)]), ([bytes, on]) => {
          const kept = bytes === null ? null : (parseJson(bytes) as J);
          if (kept !== null && typeof kept === "object")
            // (what a station said since it started, read whole or heard, wins over what was kept)
            for (const [station, list] of Object.entries(kept))
              if (!this.#grants.has(station) && Array.isArray(list)) this.#grants.set(station, new Map((list as J[]).filter((g) => typeof g?.id === "string").map((g) => [g.id as string, g])));
          const said = on === null ? null : parseJson(on);
          // (switched before it was read: as switched)
          if (this.#switched) return;
          if (typeof said === "boolean") this.#on = said;
          else {
            // (a core from before the switch: on where a grant lent the phone, so an update does not end its lending)
            this.#on = this.wanted().length > 0;
            this.#keepOn();
          }
        }),
        Effect.sync(() => {
          this.#known = true;
          this.#sync();
        }),
      ),
    );
  }

  /// The grants as they stand kept on the device (the live ones and the requests waiting: those ended let go).
  #keep(): void {
    const out: Record<string, J[]> = {};
    for (const g of this.#allGrants()) (out[g.station as string] ??= []).push(Object.fromEntries(Object.entries(g).filter(([k]) => k !== "station")));
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(GRANTS_KEY, utf8(JSON.stringify(out))), { log: "Unhandled", message: "debugging grants kept" }));
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
        return Effect.sync(() => {
          this.#on = call.on;
          this.#switched = true;
          this.#keepOn();
          this.#sync();
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
          const signed = call.scope === null ? undefined : yield* this.#signed(call.station, call.request, call.scope);
          const r = yield* this.#legacy.askAt(call.station, { op: "decide", request: call.request, scope: call.scope, ...(signed ? { signed } : {}) });
          this.heard(call.station, (r as J)?.request);
          return null;
        });
      case "personalOpen":
        return this.#of(call.sub, (sub) => this.#env.personal.open(sub, t("core-misc.personal.reason.open")));
      case "personalJoin":
        return this.#of(call.sub, (sub) => Effect.gen({ self: this }, function* () {
          // (one wait for the call's reads: past it, the locks as pinned here, the reads going on behind)
          const within = this.#env.personal.asked();
          yield* Effect.forEach(this.#env.subs(), (a) => Effect.ignore(this.#env.personal.refresh(a.sub, undefined, within), { log: "Unhandled", message: "personal lock read" }), { discard: true });
          yield* this.#env.personal.refresh(sub, undefined, within);
          yield* this.#env.personal.makeKey();
          // Every account here the other device can let it in to, on the one code.
          const others = this.#env.personal.outside(this.#env.subs().map((a) => a.sub));
          return yield* this.#env.pair.begin(others.includes(sub) ? others : [sub, ...others]);
        }));
      case "personalCode":
        return Effect.as(this.#env.pair.code(call.code), null);
      case "personalCancel":
        return Effect.sync(() => (this.#env.pair.cancel(), null));
      case "personalRemove":
        return this.#of(call.sub, (sub) => Effect.suspend(() => {
          const personal = this.#env.personal;
          const removal = personal.removeDevice(sub, call.key, t("core-misc.personal.reason.remove"));
          // (by the id the person's lock says for that key before it is taken off; not where this device takes itself
          // off: it signs for them in no workspace's lock after)
          const id = personal.chain(sub)?.devices.get(call.key)?.id;
          const itself = personal.view(sub).devices.some((d: { key: string; me: boolean }) => d.key === call.key && d.me);
          return id === undefined || itself || this.#env.tookOff === undefined ? removal : this.#env.tookOff(sub, id, removal);
        }));
      // A failed pending change to their lock, read: dropped.
      case "personalPendingDismiss":
        return this.#of(call.sub, (sub) => Effect.sync(() => (this.#env.personal.dismissPending(sub, call.id), null)));
      case "personalForget":
        return this.#of(call.sub, (sub) => this.#env.personal.forget(sub, t("core-misc.personal.reason.forget")));
      case "personalRestart":
        return this.#of(call.sub, (sub) => this.#env.personal.restart(sub, t("core-misc.personal.reason.restart")));
      case "personalConfirm":
        return this.#confirm();
      case "revoke": {
        // One list row represents the whole chat, including multiple agents' grants in that chat.
        const selected = this.#grants.get(call.station)?.get(call.request);
        const matching = selected === undefined ? [] : this.#allGrants()
          .filter((g) => g.station === call.station && grantChat(g) === grantChat(selected))
          .map((g) => g.id as string);
        const ids = matching.length > 0 ? matching : [call.request];
        // Off this phone at once, whatever the station answers or goes on saying.
        for (const id of ids) this.#revoked.set(id, this.#grants.get(call.station)?.get(id)?.exp ?? Math.floor(this.#env.host.nowMs() / 1000) + 30 * 86400);
        this.#keepRevoked();
        this.#sync();
        return Effect.as(Effect.forEach(ids, (request) => Effect.map(this.#legacy.askAt(call.station, { op: "revoke", request }), (r) => {
          this.heard(call.station, (r as J)?.request);
        }), { discard: true }), null);
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
      const waiting = this.#allGrants().filter((g) => this.#toConfirm(g));
      const bySub = new Map<string, J[]>();
      for (const g of waiting) {
        const sub = this.#subAt(g.station);
        if (sub !== null) bySub.set(sub, [...(bySub.get(sub) ?? []), g]);
      }
      for (const [sub, grants] of bySub) {
        const bodies = grants.map((g) => ({ station: g.station as string, request: g.id as string, session: g.session as string, chat: g.chat as string, scope: g.scope as PhoneScope, exp: g.exp as number }));
        const signed = yield* this.#env.personal.signGrants(sub, bodies, t("core-misc.personal.reason.confirm"));
        for (const [i, g] of grants.entries()) {
          const r = yield* this.#legacy.askAt(g.station, { op: "sign", request: g.id, signed: signed[i] });
          this.heard(g.station, (r as J)?.request);
        }
      }
      return null;
    });
  }

  /// A grant live but unsigned, on a station that can carry a signature, and an account whose lock this device is on.
  #toConfirm(g: J): boolean {
    if (g.status !== "granted" || g.signed != null || this.#revoked.has(g.id) || this.#old.has(g.station)) return false;
    const sub = this.#subAt(g.station);
    return sub !== null && this.#env.personal.standing(sub) === "member";
  }

  /// What this device signs to allow a chat a phone.
  #signed(station: string, request: string, scope: PhoneScope): Effect.Effect<J, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const sub = this.#subAt(station);
      if (sub === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noAccount")));
      if (this.#old.has(station)) return yield* Effect.fail(new CoreError("personal_old_station", t("core-misc.personal.oldStation")));
      if (this.#grants.get(station)?.get(request) === undefined) yield* this.readGrants(station);
      const g = this.#grants.get(station)?.get(request);
      if (g === undefined) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      const exp = Math.floor(this.#env.host.nowMs() / 1000) + SCOPE_SECONDS[scope];
      return yield* this.#env.personal.signGrant(sub, { station, request, session: g.session, chat: g.chat, scope, exp }, t("core-misc.personal.reason.grant"));
    });
  }

  /// Until when grant `g` holds on this phone (null: it lends nothing on it): signed by a device on the lock pinned here.
  #holds(g: J): number | null {
    if (g.status !== "granted" || this.#revoked.has(g.id)) return null;
    const sub = this.#subAt(g.station);
    const chain = sub === null ? null : this.#env.personal.chain(sub);
    return sub === null || chain === null ? null : this.check(g, g.station, sub, chain.devices, Math.floor(this.#env.host.nowMs() / 1000));
  }

  /// The lock pinned here read, and what it lets this phone lend for, as soon as it is known whose it is: a phone started
  /// anew lends before any station is reached.
  accountsKnown(): void {
    for (const { sub } of this.#env.subs()) this.#readPersonal(sub);
  }

  /// (`at`: as that station is reached, read of it alone)
  #readPersonal(sub: string, at?: string): void {
    this.#env.runner.fork(Effect.ensuring(Effect.ignore(this.#env.personal.refresh(sub, at), { log: "Unhandled", message: "personal lock read" }), Effect.sync(() => this.#sync())));
  }

  #keepRevoked(): void {
    const now = this.#env.host.nowMs() / 1000;
    for (const [id, until] of this.#revoked) if (until <= now) this.#revoked.delete(id);
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(REVOKED_KEY, utf8(JSON.stringify(Object.fromEntries(this.#revoked)))), { log: "Unhandled", message: "debugging grants taken back kept" }));
  }

  /// This phone paired with its own adbd (2026-10-31): once, whichever station's page or card asked,
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
    if (typeof d?.id !== "string") return;
    this.#retold.told(station, "adb-grant", d);
    this.#putGrant(station, d);
    this.#keep();
    this.#sync();
  }

  #putGrant(station: string, d: J): void {
    const at = this.#grants.get(station) ?? new Map<string, J>();
    if (d.status === "pending" || d.status === "granted") at.set(d.id, d);
    else at.delete(d.id);
    this.#grants.set(station, at);
  }

  /// A station's grants read whole, as it is reached (one from before grants answers with none).
  readGrants(station: string): Effect.Effect<void, CoreError> {
    return Effect.suspend(() => {
      const sub = this.#subAt(station);
      if (sub !== null) this.#readPersonal(sub, station);
      const read = this.#retold.asked();
      return Effect.map(Effect.orElseSucceed(this.#legacy.askAt(station, { op: "grants" }), () => null), (r) => {
        const list = Array.isArray((r as J)?.grants) ? ((r as J).grants as J[]) : null;
        if (list === null) return;
        // (one from before signatures drops them: said on its cards, nothing allowed there would lend)
        if ((r as J)?.signs === true) this.#old.delete(station);
        else this.#old.add(station);
        this.#grants.set(station, new Map(list.filter((g) => typeof g?.id === "string").map((g) => [g.id as string, g])));
        // A change heard while the read was out is newer than the snapshot it brought.
        for (const { data } of this.#retold.since(read, station)) this.#putGrant(station, data as J);
        this.#keep();
        this.#sync();
      }).pipe(Effect.ensuring(Effect.sync(() => this.#retold.over(read))));
    });
  }

  /// The grants live now and the requests waiting, every station's: `{station, id, chat, reason, status, scope, exp}`.
  #allGrants(): J[] {
    const now = this.#env.host.nowMs() / 1000;
    const out: J[] = [];
    for (const [station, at] of this.#grants)
      for (const g of at.values()) if (g.status === "pending" || (g.status === "granted" && (g.exp ?? 0) > now)) out.push({ ...g, station });
    return out.sort((a, b) => (a.at ?? 0) - (b.at ?? 0));
  }

  /// One row per chat, most recently used first. All underlying grants stay kept and are taken back together.
  grants(): J[] {
    const out = new Map<string, J>();
    for (const whole of this.#allGrants()) {
      const { signed: _signed, ...shown } = whole;
      const sub = this.#subAt(whole.station);
      const standing = sub === null ? "member" : this.#env.personal.standing(sub);
      const g = {
        ...shown,
        ...(sub !== null ? { sub } : {}),
        ...(whole.status === "granted" ? { held: this.#holds(whole) !== null, unsigned: whole.signed == null } : {}),
        // (no lock yet is no step: allowing it begins the lock by itself, PersonalLock.signGrant)
        ...(whole.status === "pending" && (standing === "outside" || standing === "replaced") ? { join: true } : {}),
        ...(this.#old.has(whole.station) ? { oldStation: true } : {}),
      };
      const key = JSON.stringify([g.station, grantChat(g)]);
      const before = out.get(key);
      const used = typeof g.lastUsedAt === "number" ? g.lastUsedAt : 0;
      const wasUsed = typeof before?.lastUsedAt === "number" ? before.lastUsedAt : 0;
      if (before === undefined || (before.status !== "granted" && g.status === "granted") || (before.status === g.status && (used > wasUsed || (used === wasUsed && (g.at ?? 0) > (before.at ?? 0))))) out.set(key, g);
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
    seenOf(this.#env.store).touch();
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
  /// notification: it names no station) and an ask naming none is of (2026-10-30: a phone lent to a
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
    seenOf(this.#env.store).read();
    const first = this.#legacy.value().sharing ? this.#legacy : (this.#focus() ?? this.#legacy);
    const lends = [...this.#lends.entries()].map(([station, l]) => {
      const v = l.value();
      return { station, phase: v.phase, adb: v.adb, serial: v.serial, message: v.message, tunnels: v.tunnels };
    });
    // Every station's chats with screens up, not only the first lending's.
    const screens = [...new Set([this.#legacy, ...this.#lends.values()].flatMap((l) => l.value().screens as string[]))];
    const personal = this.#env.subs().map(({ sub, email }) => ({ ...this.#env.personal.view(sub), email, pair: this.#env.pair.state(sub) }));
    const toConfirm = this.#allGrants().filter((g) => this.#toConfirm(g)).length;
    return { ...first.value(), on: this.#on, grants: this.grants(), wanted: this.wanted(), known: this.#known, lends, screens, personal, toConfirm };
  }

  card(station: string): J {
    seenOf(this.#env.store).read();
    return (this.#lends.get(station) ?? this.#legacy).card(station);
  }

  /// What the lending shows changed elsewhere (a pairing, a personal lock): what shows it is made again.
  touched(): void {
    seenOf(this.#env.store).touch();
  }

  deviceTold(): void {
    this.#legacy.deviceTold();
    this.#sync();
  }
}
