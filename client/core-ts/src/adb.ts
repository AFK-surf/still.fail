// This phone's adb, lent to a station's agents (adb.rs; docs/adb-share.md): the `adbShare` topic and the `adb.*`
// calls. While it is offered (until stopped or its hour is up) a stream on the station's link says so, opened again on
// each link that takes the place of one, and every stream the station opens on that link is a tunnel to the phone's
// own adbd. Kept in memory only: a core started anew offers nothing. Only a host with TCP reaches adbd.
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
const RETRY_MAX_MS = 30_000;

type Ended = { changed: true } | { expired: true } | { refused: string } | { lost: string | null; pause: boolean };

export type AdbEnv = {
  host: Host;
  runner: Runner;
  store: Store;
  mesh: () => Effect.Effect<Mesh, CoreError>;
  credentials: (workspace: string) => CredentialSource;
  /// The relays a workspace has of its own (`Mesh.link`).
  relays: (workspace: string) => string[];
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

export class Adb {
  readonly #env: AdbEnv;
  #offer: Offer | null = null;
  #until = 0;
  #run = 0;
  #phase: "connecting" | "offered" | null = null;
  #station: J = null;
  #problem: string | null = null;
  #tunnels = 0;
  /// The offer's keeper, and its tunnels' scope: closed as the offer stops or moves to another station.
  #keeper: Fiber.Fiber<unknown, unknown> | null = null;
  #tunnelScope: Scope.Closeable | null = null;
  #changed: Deferred.Deferred<void> = Deferred.makeUnsafe<void>();

  constructor(env: AdbEnv) {
    this.#env = env;
  }

  run(call: AdbCall): Effect.Effect<unknown, CoreError> {
    switch (call.kind) {
      case "share":
        if (!this.#env.host.tcp) return Effect.fail(new CoreError("unsupported", t("core-misc.adb.unsupported")));
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
    };
  }

  #shown(): void {
    this.#env.store.invalidate({ topic: "adbShare" });
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
    if (this.#offer === null || this.#offer.station !== offer.station) {
      this.#station = null;
      this.#closeTunnels();
      this.#until = this.#env.host.nowMs() + offer.minutes * 60_000;
    }
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
      const link = yield* mesh.link(addr.station, this.#env.credentials(addr.workspace), this.#env.relays(addr.workspace));
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
      const ask = { op: "share", phone: mesh.deviceId(), device: offer.device, android: offer.android, package: offer.package, adbd: offer.connect !== null, pair: offer.pair !== null };
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
      const accepting = Effect.gen(function* () {
        for (;;) {
          const stream = yield* link.accept();
          if (stream === null) break;
          self.#env.runner.fork(Effect.provideService(self.#tunnel(run, stream), Scope.Scope, tunnels));
        }
        return { lost: link.closed() ?? t("core-misc.adb.link_lost"), pause: true } as Ended;
      });
      const replaced = Effect.as(mesh.replaced(StationAddr.parse(offer.station).station, link), { lost: null, pause: false } as Ended);
      const stopped = Effect.as(Deferred.await(changed), { changed: true } as Ended);
      const left = Math.max(this.#until - this.#env.host.nowMs(), 0);
      const expired = Effect.as(Effect.sleep(left), { expired: true } as Ended);
      const ended = yield* Effect.raceAllFirst([hears, accepting, replaced, stopped, expired]);
      if (!("changed" in ended) && this.#env.host.nowMs() >= this.#until) return { expired: true } as Ended;
      return ended;
    });
  }

  /// One tunnel the station opened: to adbd's port it names, then its bytes both ways.
  #tunnel(run: number, stream: IrohStream): Effect.Effect<void, never, Scope.Scope> {
    return Effect.gen({ self: this }, function* () {
      const refuse = (why: string) => Effect.ignore(Effect.andThen(stream.write(utf8(`${JSON.stringify({ error: why })}\n`)), stream.finish()));
      const carry = { bytes: new Uint8Array() };
      const line = yield* Effect.orElseSucceed(readLine(stream, carry), () => null);
      if (line === null) return;
      const kind = (parseJson(utf8(line)) as J)?.tunnel;
      const offer = this.#current(run);
      if (offer === null) return yield* refuse("已经停止共享");
      const port = kind === "connect" ? offer.connect : kind === "pair" ? offer.pair : null;
      if (port === null) return yield* refuse(kind === "connect" ? "手机上的无线调试没开" : kind === "pair" ? "手机上的配对窗口没开" : "不认识的通道");
      const tcp = yield* Effect.result(this.#env.host.tcp!(port));
      if (tcp._tag === "Failure") return yield* refuse(`连不上手机上的 adb：${tcp.failure.message}`);
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
        yield* Effect.ignore(stream.finish());
      });
      const down = Effect.gen(function* () {
        if (carry.bytes.length > 0) yield* Effect.ignore(conn.write(carry.bytes));
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
    return Effect.gen({ self: this }, function* () {
      const offer = this.#offer;
      if (offer === null) return yield* Effect.fail(CoreError.invalid(t("core-misc.adb.not_sharing")));
      const [mesh, link] = yield* this.#link(offer.station);
      const reply = yield* link.adb(head(), { ...ask, phone: mesh.deviceId() });
      const parts: Uint8Array[] = [];
      for (;;) {
        const chunk = yield* Effect.mapError(reply.body.take, (e) => new CoreError("mesh", e.message));
        if (chunk === null) break;
        parts.push(chunk);
      }
      const said = message(fromUtf8(new Uint8Array(parts.flatMap((p) => [...p])))) ?? "";
      if (reply.status === 200) return { message: said };
      return yield* Effect.fail(CoreError.invalid(said === "" ? t("core-misc.adb.failed", { status: reply.status }) : said));
    });
  }
}
