// This phone's adb, lent to a station's agents (adb.rs; docs/adb-share.md): the `adbShare` topic and the `adb.*`
// calls. While it is offered (until stopped or its hour is up) a stream on the station's link says so, opened again on
// each link that takes the place of one, and every stream the station opens on that link is a tunnel to the phone's
// own adbd. The offers kept in memory only: a core started anew offers again as its app asks (the grants it lends
// for kept on the device: GRANTS_KEY). Only a host with TCP reaches adbd.
import { Deferred, Effect, Fiber, Scope } from "effect";
import type { AdbCall, Offer } from "./adb-parse.ts";
import { CoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { current, t } from "./i18n.ts";
import type { IrohStream } from "./iroh.ts";
import type { CredentialSource, Link, Mesh } from "./mesh.ts";
import type { Runner } from "./runtime.ts";
import { StationAddr } from "./station/addr.ts";
import { LANG_HEADER } from "./station/requests.ts";
import type { RequestHead } from "./station/wire.ts";
import type { Store } from "./store.ts";
import { fromUtf8, parseJson, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const RETRY_MS = 1_000;
/// Where this person's chats' grants of their phone are kept on the device, as the stations last said them: a core
/// started anew (the app's process gone and back, the phone started again) lends it to them at once, not only once
/// each station is reached again.
export const GRANTS_KEY = "adb-grants";
const RETRY_MAX_MS = 30_000;

type Ended = { changed: true } | { expired: true } | { refused: string } | { lost: string | null; pause: boolean };

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
      const chunk = yield* Effect.mapError(stream.read(), (e) => new CoreError("mesh", e.message));
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

  constructor(env: AdbEnv) {
    this.#env = env;
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
      until: this.#offer !== null ? Math.trunc(this.#until) : null,
      tunnels: this.#tunnels,
      connectPort: this.#offer?.connect ?? null,
      pairPort: this.#offer?.pair ?? null,
      refusedPort: this.#offer !== null && this.#refused === this.#offer.connect ? this.#refused : null,
    };
  }

  /// A link to a station's 共享调试 as a message shows it (the `adbCard` topic): what it is, and in a line how this
  /// phone's adb stands with that station (its minutes left, sent again each minute as every shown time is).
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
        ? t("core-views.adb.card.connected", { n: minutes })
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
      const ask = { op: "share", phone: mesh.deviceId(), device: offer.device, android: offer.android, package: offer.package, adbd: offer.connect !== null, pair: offer.pair !== null, connect: offer.connect };
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
      const tcp = yield* Effect.result(this.#env.host.tcp!(port));
      if (tcp._tag === "Failure") {
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
  askAt(station: string, ask: J): Effect.Effect<unknown, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const [mesh, link] = yield* this.#link(station);
      const reply = yield* link.adb(head(), { ...ask, phone: mesh.deviceId() });
      const parts: Uint8Array[] = [];
      for (;;) {
        const chunk = yield* Effect.mapError(reply.body.take, (e) => new CoreError("mesh", e.message));
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

/// This phone's adb (docs/adb-share.md): lent to each station a chat's grant of it is live on (`wanted`), with the ports
/// its app found (`adb.ports`); and, from an app before grants, to the one station its switch lent it to (`adb.share`).
/// The grants, every station's, as each says them; decided and taken back here (`adb.decide`, `adb.revoke`).
export class Adb {
  readonly #env: AdbEnv;
  readonly #legacy: Lend;
  readonly #lends = new Map<string, Lend>();
  #ports: Omit<Offer, "station" | "minutes"> | null = null;
  /// This person's chats' grants of their phone (and requests waiting), by station address and id.
  readonly #grants = new Map<string, Map<string, J>>();
  /// Their 默认最长授权 as last set here or said by a station.
  #lasts: "hour" | "chat" = "chat";
  /// Whether the grants kept on the device were read (`adbShare` `known`): before, none known is not none granted.
  #known = false;

  constructor(env: AdbEnv) {
    this.#env = env;
    this.#legacy = new Lend(env);
    env.runner.fork(
      Effect.ensuring(
        Effect.map(Effect.orElseSucceed(env.host.storageGet(GRANTS_KEY), () => null), (bytes) => {
          const kept = bytes === null ? null : (parseJson(bytes) as J);
          if (kept === null || typeof kept !== "object") return;
          // (what a station said since it started, read whole or heard, wins over what was kept)
          for (const [station, list] of Object.entries(kept))
            if (!this.#grants.has(station) && Array.isArray(list)) this.#grants.set(station, new Map((list as J[]).filter((g) => typeof g?.id === "string").map((g) => [g.id as string, g])));
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
    for (const g of this.grants()) (out[g.station as string] ??= []).push(Object.fromEntries(Object.entries(g).filter(([k]) => k !== "station")));
    this.#env.runner.fork(Effect.ignore(this.#env.host.storageSet(GRANTS_KEY, utf8(JSON.stringify(out))), { log: "Unhandled", message: "debugging grants kept" }));
  }

  run(call: AdbCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "share":
      case "stop":
        return this.#legacy.run(call);
      case "ports":
        // (taken whatever the app said it is so far: what lends waits for it to say it is a phone, `#sync`, `deviceTold`;
        // refused, a service started for kept grants before the app said so stopped and was not started again)
        return Effect.sync(() => {
          this.#ports = call.ports;
          this.#sync();
          return null;
        });
      case "pair":
      case "grant": {
        const lend = this.#legacy.value().sharing ? this.#legacy : (call.station !== undefined ? this.#lends.get(call.station) : [...this.#lends.values()][0]);
        return lend === undefined ? Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing"))) : lend.run(call);
      }
      case "decide":
        return Effect.map(this.#legacy.askAt(call.station, { op: "decide", request: call.request, scope: call.scope }), (r) => {
          this.heard(call.station, (r as J)?.request);
          return null;
        });
      case "revoke":
        return Effect.map(this.#legacy.askAt(call.station, { op: "revoke", request: call.request }), (r) => {
          this.heard(call.station, (r as J)?.request);
          return null;
        });
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

  /// A station said how a grant or request of this person's stands (its `adb-grant` event, or a decision's answer).
  heard(station: string, d: J): void {
    if (typeof d?.id !== "string") return;
    const at = this.#grants.get(station) ?? new Map<string, J>();
    if (d.status === "pending" || d.status === "granted") at.set(d.id, d);
    else at.delete(d.id);
    this.#grants.set(station, at);
    this.#keep();
    this.#sync();
  }

  /// A station's grants read whole, as it is reached (one from before grants answers with none).
  readGrants(station: string): Effect.Effect<void, CoreError> {
    return Effect.map(Effect.orElseSucceed(this.#legacy.askAt(station, { op: "grants" }), () => null), (r) => {
      const list = Array.isArray((r as J)?.grants) ? ((r as J).grants as J[]) : null;
      if (list === null) return;
      if ((r as J)?.lasts === "hour" || (r as J)?.lasts === "chat") this.#lasts = (r as J).lasts;
      this.#grants.set(station, new Map(list.filter((g) => typeof g?.id === "string").map((g) => [g.id as string, g])));
      this.#keep();
      this.#sync();
    });
  }

  /// The grants live now and the requests waiting, every station's: `{station, id, chat, reason, status, scope, exp}`.
  grants(): J[] {
    const now = this.#env.host.nowMs() / 1000;
    const out: J[] = [];
    for (const [station, at] of this.#grants)
      for (const g of at.values()) if (g.status === "pending" || (g.status === "granted" && (g.exp ?? 0) > now)) out.push({ ...g, station });
    return out.sort((a, b) => (a.at ?? 0) - (b.at ?? 0));
  }

  /// The stations a grant lends this phone to now.
  wanted(): string[] {
    return [...new Set(this.grants().filter((g) => g.status === "granted").map((g) => g.station as string))];
  }

  /// Each wanted station lent to (with the ports the app found), each no longer wanted let go.
  #sync(): void {
    const wanted = this.#ports === null || !this.#env.lends() ? [] : this.wanted();
    for (const [station, lend] of this.#lends)
      if (!wanted.includes(station)) {
        this.#env.runner.fork(Effect.ignore(lend.run({ kind: "stop" }), { log: "Unhandled", message: "debugging lend stopped" }));
        this.#lends.delete(station);
      }
    for (const station of wanted) {
      let lend = this.#lends.get(station);
      if (lend === undefined) {
        lend = new Lend(this.#env);
        this.#lends.set(station, lend);
      }
      // (lent for as long as a grant is: the grants end it, not its own clock)
      this.#env.runner.fork(Effect.ignore(lend.run({ kind: "share", offer: { ...this.#ports!, station, minutes: 30 * 24 * 60 } }), { log: "Unhandled", message: "debugging lend shared" }));
    }
    this.#env.store.invalidate({ topic: "adbShare" });
  }

  /// The `adbShare` topic: the lending as the app's switch made it, or the first a grant made, and every grant.
  value(): J {
    const first = this.#legacy.value().sharing ? this.#legacy : ([...this.#lends.values()][0] ?? this.#legacy);
    const lends = [...this.#lends.entries()].map(([station, l]) => {
      const v = l.value();
      return { station, phase: v.phase, adb: v.adb, serial: v.serial, message: v.message, tunnels: v.tunnels };
    });
    return { ...first.value(), grants: this.grants(), wanted: this.wanted(), known: this.#known, lends, lasts: this.#lasts };
  }

  card(station: string): J {
    return (this.#lends.get(station) ?? this.#legacy).card(station);
  }

  deviceTold(): void {
    this.#legacy.deviceTold();
    this.#sync();
  }
}
