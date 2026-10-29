// Phones lent to this station's agents (docs/adb-share.md; the Rust station's adb.rs): a phone offers its adbd over its
// member link, and the station reaches it at `127.0.0.1:<port>`, a listener of its own whose every TCP connection is a
// stream it opens on the phone's connection (the phone's core takes it on to adbd). `adb connect` as the offer comes,
// `adb disconnect` as it goes; `adb pair` through the phone's pairing port when its person types the code. The agents
// read who lent what with the `adb_devices` tool (`Shares.list`, given to adb/tool.ts `adbTools`).
//
// Wire (unchanged from the Rust station; the phone's core is released): a request stream whose head line has an
// `"adb"` object. `op: "share"` is an offer, answered `{status: 200, headers: {content-type: application/x-ndjson}}`
// and then a `{serial, adb, message}` line each time how adb holds the phone changes, for as long as the stream lasts;
// `op: "pair" | "grant"` is an ask, answered with a status and `{message}`. Tunnels are streams the station opens on the
// offer's connection: `{"tunnel": "connect" | "pair"}`, the phone's `{ok: true}` (or `{error}`), then bytes both ways.
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, statSync } from "node:fs";
import net from "node:net";
import { delimiter, join } from "node:path";
import { Clock, Effect, Exit, FiberSet, Scope } from "effect";
import { langOfCore } from "../api/request.ts";
import { wall } from "../ops/fibers.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import type { Viewer } from "../mesh/credential.ts";
import type { Connection, Stream } from "../mesh/native.ts";
import { Reader, writeLine } from "../mesh/serve.ts";
import type { GrantServers } from "./servers.ts";

type Json = any;

/// Where a phone's port is looked for first: the same phone gets the same one while it is free, so what an agent
/// wrote down of it (`adb -s 127.0.0.1:37xxx`) holds across offers.
export const PORTS = { start: 37000, end: 38000 };
/// How long the phone has to take a tunnel stream and reach its adbd.
const TUNNEL_OPEN = 10_000;
/// How long adb has to answer: a look at its state, and what reaches the phone (`connect`, `pair`, `shell`).
const ADB_QUICK = 5_000;
const ADB_TIMEOUT = 30_000;
/// How long a phone whose offer ended is kept for another offer of it (the pairing port opened, a new link): its port
/// and what adb holds of it stay.
export const GRACE = 5_000;
/// How long a connected phone's state is looked at before it is taken as it is (adb says `offline` a moment first).
export const SETTLE = 6_000;
/// How long after adb failed to get in it is tried again, doubled each time it fails again (up to `RETRY_MOST`): what
/// failed may pass (the phone's link moving, adbd starting), and nobody has to share again for it.
export const RETRY = 2_000;
export const RETRY_MOST = 60_000;

export type AdbState = { serial: string; adb: string; message: string };

export type SharesOptions = {
  /// Whether the station was removed from its workspace, and who hears when that changes (cloud/state.ts `Cloud`):
  /// offers end then, without GRACE.
  cloud?: { removed(): boolean; listen(f: () => void): () => void };
  /// Where adb is (default: `adbPath`, looked for anew each time as the Rust station does).
  adb?: () => string | null;
  /// The clock GRACE and SETTLE are waited out on (a TestClock in tests).
  clock?: Clock.Clock;
  /// How long adb is given, on the machine's time: to answer (`quick`), to connect or pair (`long`). Null: as long as
  /// it takes (a test's fake adb, which always answers, so what it says never turns on how fast the machine is).
  limits?: { quick: number | null; long: number | null };
  /// The grants live now of a phone's owner (by email) on this station (adb/grants.ts), and their adb servers: a phone
  /// with any is connected in those servers alone, and its port takes their connections alone. One with none (an app
  /// from before grants, lending with its switch) is connected in the station's own server, as before.
  granted?: (email: string) => string[];
  servers?: GrantServers;
};

let nextOffer = 1;

/// One phone, as its latest offer has it.
export class Share {
  readonly port: number;
  readonly owner: Viewer;
  /// What the phone says it is: `device`, `android`, `package`; `adbd` (Wireless debugging is on) and `pair` (its
  /// pairing port is open); `connect`, adbd's port on the phone (null from a phone before it said it).
  info: { device: string; android: string; package: string; adbd: boolean; pair: boolean; connect: number | null };
  /// The connection its latest offer came on: where its tunnels go.
  conn: Connection;
  /// The language its latest offer asked in: what the phone is told of it is said in it.
  lang: Lang;
  /// Which offer it is: one that ended after another came does not take the phone away.
  offer: number;
  /// How the station's adb holds the phone, as the offer's stream is told; `version` counts its changes.
  state: AdbState;
  version = 0;
  /// Why the phone last turned a tunnel down (its adbd not there, say): what adb not getting in is put down to.
  refused: string | null = null;
  private refusalWaiters: (() => void)[] = [];
  /// The `adb connect` under way, if one is; `again`: an offer came meanwhile, so it is done once more after.
  connecting: Promise<void> | null = null;
  again = false;
  /// How many times in a row adb failed to get in: the next try waits `RETRY` doubled as many times.
  failures = 0;
  /// How many of its offers' streams are open: tried again only while one is (not in GRACE).
  streams = 0;
  readonly server: net.Server;
  private waiters: (() => void)[] = [];

  constructor(server: net.Server, owner: Viewer, info: Share["info"], conn: Connection, lang: Lang, offer: number) {
    this.server = server;
    this.port = (server.address() as net.AddressInfo).port;
    this.owner = owner;
    this.info = info;
    this.conn = conn;
    this.lang = lang;
    this.offer = offer;
    this.state = { serial: this.serial(), adb: "connecting", message: "" };
  }

  serial(): string {
    return `127.0.0.1:${this.port}`;
  }

  set(adb: string, message = "") {
    this.state = { serial: this.serial(), adb, message: message.trim() };
    this.version++;
    const waiters = this.waiters;
    this.waiters = [];
    for (const f of waiters) f();
  }

  /// The phone turned a tunnel down, saying why.
  refuse(why: string) {
    this.refused = why;
    for (const f of this.refusalWaiters.splice(0)) f();
  }

  /// Resolves once a tunnel is turned down (at once if one was since `refused` was cleared).
  refusal(): Promise<void> {
    if (this.refused !== null) return Promise.resolve();
    return new Promise((resolve) => this.refusalWaiters.push(resolve));
  }

  /// Resolves at the next `set`.
  changed(): Promise<"changed"> {
    return new Promise((resolve) => this.waiters.push(() => resolve("changed")));
  }

  /// What the agents are told of it (`adb_devices`).
  listed(): Json {
    return {
      serial: this.serial(),
      device: this.info.device,
      android: this.info.android,
      owner: { name: this.owner.name, email: this.owner.email },
      adb: this.state.adb,
      message: this.state.message,
    };
  }
}

/// The phones offered now, by whose and which (`key`).
export class Shares {
  readonly byKey = new Map<string, Share>();
  /// When each person's phone was last offered no longer, and why (`stopped`: the phone ended it; else its link went):
  /// what phone_use says of a granted phone not lent now.
  readonly gone = new Map<string, { at: number; ended: string }>();
  readonly options: SharesOptions;
  readonly limits: { quick: number | null; long: number | null };
  private stopping = false;
  private stopWaiters: (() => void)[] = [];
  /// Its waits, on its clock; they end as it closes.
  private scope: Scope.Closeable;
  readonly run: <A>(effect: Effect.Effect<A>) => Promise<A>;

  constructor(options: SharesOptions = {}) {
    this.options = options;
    this.limits = options.limits ?? { quick: ADB_QUICK, long: ADB_TIMEOUT };
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, any, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
  }

  /// The phones offered now, for the `adb_devices` tool: `{serial, device, android, owner: {name, email}, adb, message}`.
  list(): Json[] {
    return [...this.byKey.values()].map((s) => s.listed());
  }

  adb(): string | null {
    return (this.options.adb ?? adbPath)();
  }

  /// The station stopping or handing over: listeners closed, offers ended without telling adb (the next station takes
  /// the phones on at the same ports as their offers come again).
  async close() {
    this.stopping = true;
    for (const f of this.stopWaiters.splice(0)) f();
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
    const servers = [...this.byKey.values()].map((s) => s.server);
    this.byKey.clear();
    await Promise.all(servers.map((s) => new Promise<void>((resolve) => s.close(() => resolve()))));
  }

  /// Resolves "stopping" once `close` is called.
  stopped(): Promise<"stopping"> {
    if (this.stopping) return Promise.resolve("stopping");
    return new Promise((resolve) => this.stopWaiters.push(() => resolve("stopping")));
  }

  get isStopping() {
    return this.stopping;
  }

  /// `email`'s grants changed: their phones connected anew in the servers they are to be in now.
  regrant(email: string) {
    for (const share of this.byKey.values()) {
      if (share.owner.email.toLowerCase() !== email.toLowerCase() || share.streams === 0) continue;
      share.failures = 0;
      void connect(this, share).catch(() => {});
    }
  }
}

/// Which phone of whose an offer or ask is about: the phone's device key as it says (`phone`; its link may be on one
/// of its other keys, one per relay), else the connection's.
export function key(viewer: Viewer, conn: Connection, ask: Json): string {
  const phone = typeof ask?.phone === "string" && /^[0-9a-fA-F]{64}$/.test(ask.phone) ? ask.phone : null;
  return `${viewer.sub}/${phone ?? conn.remoteId()}`;
}

/// A stream whose head says `"adb"` (serve.ts dispatches it after the path check, before a socket's): an offer, held
/// as long as the stream is, or an ask about the phone's offer. The phone finished its send side; nothing is read.
export async function answerAdb(shares: Shares, conn: Connection, viewer: Viewer, head: Json, stream: Stream, _reader?: Reader): Promise<void> {
  const ask = head.adb ?? {};
  const device = key(viewer, conn, ask);
  const headers: Record<string, string> = {};
  for (const [k, v] of Object.entries(head.headers ?? {})) if (typeof v === "string") headers[k] = v;
  const asked = langOfCore(headers);
  const reply = async (status: number, message: string) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(JSON.stringify({ message })));
    await stream.finish();
  };
  const op = ask.op;
  if (op === "share") return offer(shares, conn, viewer, device, ask, asked, stream);
  if (op === "pair" || op === "grant") {
    const share = shares.byKey.get(device);
    if (!share) return reply(409, tr(asked, "station.adb.notSharing"));
    let done: { ok: true; message: string } | { ok: false; error: string };
    try {
      const message = op === "pair" ? await pair(shares, share, typeof ask.code === "string" ? ask.code : "", asked) : await grant(shares, share, asked);
      done = { ok: true, message };
    } catch (e) {
      done = { ok: false, error: (e as Error).message };
    }
    log.info("adb", "adb asked", { email: viewer.email, op, done: done.ok ? done.message : `error: ${done.error}` });
    return done.ok ? reply(200, done.message) : reply(422, done.error);
  }
  return reply(400, tr(asked, "station.adb.unknownAsk"));
}

/// An offer: the phone in `shares` (its listener up), adb told, and how adb holds it said down the stream until the
/// phone stops it, its connection goes, or the station is removed. A later offer from the phone takes this one's place.
async function offer(shares: Shares, conn: Connection, viewer: Viewer, device: string, ask: Json, asked: Lang, stream: Stream) {
  const info = {
    device: text(ask.device, 80),
    android: text(ask.android, 20),
    package: typeof ask.package === "string" && isPackage(ask.package) ? ask.package : "",
    adbd: typeof ask.adbd === "boolean" ? ask.adbd : true,
    pair: typeof ask.pair === "boolean" ? ask.pair : false,
    connect: typeof ask.connect === "number" && Number.isInteger(ask.connect) && ask.connect > 0 && ask.connect < 65536 ? ask.connect : null,
  };
  const number = nextOffer++;
  let share = shares.byKey.get(device);
  // What adb is asked again on: only what changes how it reaches the phone. Offers come again and again as the phone's
  // link moves (relay, LAN, main endpoint: twenty in five minutes, 2026-10-17), and adb, once it has the phone, reaches
  // it again through the new link by itself; connecting anew each time held the page at 正在连接 adb for up to 100 s.
  const before = share?.info;
  if (share) {
    share.info = info;
    share.conn = conn;
    share.lang = asked;
    share.offer = number;
  } else {
    const server = await bind(device);
    share = new Share(server, viewer, info, conn, asked, number);
    // Another offer of the same phone may have come while this one bound its port: the first in keeps it.
    const raced = shares.byKey.get(device);
    if (raced || shares.isStopping) {
      server.close();
      if (shares.isStopping) return void stream.reset(0).catch(() => {});
      share = raced!;
      share.info = info;
      share.conn = conn;
      share.lang = asked;
      share.offer = number;
    } else {
      listen(shares, share);
      shares.byKey.set(device, share);
      log.info("adb", "phone offered for adb", { email: viewer.email, port: share.port });
    }
  }
  await writeLine(stream, { status: 200, headers: { "content-type": "application/x-ndjson" } });
  log.info("adb", "adb offer", { offer: number, ...about(conn), main: conn.remoteId() === ask.phone, adbd: info.adbd, pair: info.pair, connect: info.connect });
  // adbd's port changing (Wireless debugging turned off and on) is said by phones from 2026-10-26 on.
  const moved = before !== undefined && before.connect !== null && info.connect !== null && before.connect !== info.connect;
  if (before === undefined || before.adbd !== info.adbd || moved || share.state.adb === "failed" || share.state.adb === "missing") {
    share.failures = 0;
    void connect(shares, share).catch(() => {});
  }

  share.streams++;
  let unlisten = () => {};
  const removed = new Promise<"removed">((resolve) => {
    const cloud = shares.options.cloud;
    if (!cloud) return;
    if (cloud.removed()) return resolve("removed");
    unlisten = cloud.listen(() => cloud.removed() && resolve("removed"));
  });
  const ends = Promise.race([
    stream.stopped().then(() => "stopped" as const),
    conn.closed().then(() => "closed" as const),
    removed,
    shares.stopped(),
  ]);
  let ended: string;
  let seen = -1;
  for (;;) {
    if (share.version !== seen) {
      seen = share.version;
      try {
        await writeLine(stream, share.state);
      } catch {
        ended = "stream";
        break;
      }
      // Changed again while it was written: said at once.
      if (share.version !== seen) continue;
    }
    const next = await Promise.race([share.changed(), ends]);
    if (next !== "changed") {
      ended = next;
      break;
    }
  }
  unlisten();
  share.streams--;
  if (ended === "stopping") return;
  // Only the latest offer takes the phone away (one that came on another link has it now), and only if no other comes
  // a moment after.
  // (`close` ends the wait.)
  if (ended !== "removed") await shares.run(Effect.sleep(GRACE)).catch(() => {});
  if (!shares.isStopping && share.offer === number && shares.byKey.get(device) === share) {
    shares.byKey.delete(device);
    share.server.close();
    log.info("adb", "phone no longer offered for adb", { email: viewer.email, port: share.port, ended });
    shares.gone.set(viewer.email.toLowerCase(), { at: wall.now(), ended: String(ended) });
    const adb = shares.adb();
    if (adb) for (const server of (await serversOf(shares, share)) ?? [[]]) await run(adb, [...server, "disconnect", share.serial()], shares.limits.quick).catch(() => {});
  }
  await stream.finish().catch(() => {});
}

/// Each TCP connection to the phone's port, a tunnel on its offer's connection.
function listen(shares: Shares, share: Share) {
  share.server.on("connection", (socket) => {
    const conn = share.conn;
    const ids = shares.options.granted?.(share.owner.email) ?? [];
    if (ids.length > 0 && shares.options.servers) {
      // Granted to chats: only their adb servers are let in (another chat's agent, knowing the port, is not).
      void shares.options.servers.allowed(socket, ids).then((ok) => {
        if (!ok) {
          log.info("adb", "a connection to a granted phone's port from no grant's adb server turned away", { port: share.port });
          return void socket.destroy();
        }
        tunnel(conn, "connect", socket).catch((error) => {
          log.info("adb", "adb tunnel ended", { error: (error as Error).message, offer: share.offer, ...about(conn) });
          share.refuse((error as Error).message);
        });
      });
      return;
    }
    tunnel(conn, "connect", socket).catch((error) => {
      log.info("adb", "adb tunnel ended", { error: (error as Error).message, offer: share.offer, ...about(conn) });
      share.refuse((error as Error).message);
    });
  });
}

/// Which of the phone's connections it is and the ways it has, for the log: a tunnel goes on its offer's.
/// Never fails: what is not known is left out.
function about(conn: Connection): Record<string, string> {
  try {
    const ways = (conn.paths?.() ?? []).map((p) => `${p.selected ? "*" : ""}${p.relay ?? p.ip ?? "?"} ${Math.round(p.rttMs)}ms ${p.txPackets}/${p.lostPackets}`);
    return { device: conn.remoteId().slice(0, 12), via: conn.via?.() ?? "none", ways: ways.join("; ") };
  } catch {
    return {};
  }
}

/// A port of the phone's own: its usual one if free, else any.
export async function bind(device: string): Promise<net.Server> {
  const hash = createHash("sha256").update(device).digest();
  const usual = PORTS.start + (((hash[0] << 8) | hash[1]) % (PORTS.end - PORTS.start));
  // An offer from before (the station handed over to a new one) may hold it a moment yet: tried 5 times, each miss
  // waited 500 ms after.
  const usualOne = Effect.tryPromise(() => listenOn(usual)).pipe(
    Effect.tapError(() => Effect.sleep(500)),
    Effect.retry({ times: 4 }),
    Effect.orElseSucceed(() => null),
  );
  return (await Effect.runPromise(usualOne)) ?? listenOn(0);
}

function listenOn(port: number): Promise<net.Server> {
  return new Promise((resolve, reject) => {
    const server = net.createServer({ pauseOnConnect: true });
    server.once("error", reject);
    server.listen({ host: "127.0.0.1", port, exclusive: true }, () => {
      server.off("error", reject);
      server.on("error", (error) => log.info("adb", "adb listener failed", { error: error.message }));
      resolve(server);
    });
  });
}

/// A stream to the phone for `socket`: `{"tunnel": kind}`, the phone's answer once it reached adbd (or why not), then
/// the bytes both ways until either side ends. `signal` ends it at once (the pairing done).
export async function tunnel(conn: Connection, kind: string, socket: net.Socket, signal?: AbortSignal): Promise<void> {
  socket.on("error", () => {});
  let stream: Stream | null = null;
  const abort = () => {
    socket.destroy();
    void stream?.reset(0).catch(() => {});
  };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    stream = await wall.within(TUNNEL_OPEN, conn.openBi(), "the phone did not take the tunnel");
    if (signal?.aborted) return abort();
    await writeLine(stream, { tunnel: kind });
    const reader = new Reader(stream);
    const answer = await wall.within(TUNNEL_OPEN, reader.line(), "the phone did not answer");
    if (answer === null) throw new Error("the phone closed the tunnel");
    if (typeof answer.error === "string") throw new Error(`the phone did not reach adb: ${answer.error}`);
    const s = stream;
    const up = (async () => {
      try {
        for await (const chunk of socket) await s.write(chunk as Buffer);
      } finally {
        await s.finish().catch(() => {});
      }
    })();
    const down = (async () => {
      if (reader.carry.length > 0) await toSocket(socket, reader.carry);
      for (let more = await s.read(); more; more = await s.read()) await toSocket(socket, more);
      socket.end();
    })();
    const [a, b] = await Promise.allSettled([up, down]);
    for (const r of [a, b]) if (r.status === "rejected") throw r.reason;
  } catch (error) {
    // Why is known (to its offer) before adb hears the socket end: its stream's reset is not waited for.
    socket.destroy();
    void stream?.reset(0).catch(() => {});
    throw error;
  } finally {
    signal?.removeEventListener("abort", abort);
  }
}

/// Written to the socket, waiting while it is full (or failing once it is gone).
function toSocket(socket: net.Socket, bytes: Buffer): Promise<void> {
  if (socket.destroyed) return Promise.reject(new Error("the adb connection closed"));
  if (socket.write(bytes)) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const done = (error?: Error) => {
      socket.off("drain", drained);
      socket.off("close", closed);
      error ? reject(error) : resolve();
    };
    const drained = () => done();
    const closed = () => done(new Error("the adb connection closed"));
    socket.once("drain", drained);
    socket.once("close", closed);
  });
}

/// `adb connect` to the phone, one at a time: offers come a few at once as the phone finds its ports (three within 60 ms,
/// 2026-10-17), and each connect begins by disconnecting, so side by side they undid each other. One that comes while
/// another is under way has it done once more after, with what the phone said last.
function connect(shares: Shares, share: Share): Promise<void> {
  if (share.connecting !== null) {
    share.again = true;
    return share.connecting;
  }
  const started = wall.now();
  share.connecting = (async () => {
    try {
      do {
        share.again = false;
        await connectOnce(shares, share);
      } while (share.again && !shares.isStopping);
    } finally {
      share.connecting = null;
      log.info("adb", "adb holds the phone", { adb: share.state.adb, ms: wall.now() - started });
    }
    if (share.state.adb === "failed") again(shares, share);
    else share.failures = 0;
  })();
  return share.connecting;
}

/// adb tried again once `RETRY` (doubled for each failure before) is over, while an offer of the phone's stream is open
/// and nothing else took adb on to it meanwhile (another offer, a pairing).
function again(shares: Shares, share: Share) {
  const wait = Math.min(RETRY * 2 ** share.failures, RETRY_MOST);
  share.failures++;
  const version = share.version;
  void shares
    .run(Effect.sleep(wait))
    .then(() => {
      if (shares.isStopping || share.streams === 0 || share.version !== version || share.connecting !== null) return;
      return connect(shares, share);
    })
    .catch(() => {});
}

/// The adb servers the phone is connected in: its grants' (`-P <port>` each), else the station's own (nothing given);
/// null when a grant's would not start.
export async function serversOf(shares: Shares, share: Share): Promise<string[][] | null> {
  const ids = shares.options.granted?.(share.owner.email) ?? [];
  if (ids.length === 0 || !shares.options.servers) return [[]];
  const out: string[][] = [];
  for (const id of ids) {
    const s = await shares.options.servers.ensure(id);
    if (s !== null) out.push(["-P", String(s.port)]);
  }
  return out.length > 0 ? out : null;
}

/// `adb connect` to the phone in each server it is to be in (and out of the station's own once granted to chats), and
/// how adb holds it then, as the first has it.
async function connectOnce(shares: Shares, share: Share) {
  const adb = shares.adb();
  const servers = await serversOf(shares, share);
  if (adb !== null && servers !== null && servers[0]!.length > 0) await run(adb, ["disconnect", share.serial()], shares.limits.quick).catch(() => {});
  if (servers === null) return share.set("failed", "a grant's adb server did not start");
  let first: AdbState | null = null;
  for (const server of servers) {
    await connectIn(shares, share, server);
    first ??= share.state;
  }
  if (first !== null && first.adb !== share.state.adb) share.set(first.adb, first.message);
}

/// `adb connect` to the phone in one adb server (`server`: its `-P <port>`, or none for the station's own), unless it
/// holds it already, and how it holds it then.
async function connectIn(shares: Shares, share: Share, server: string[]) {
  const run = (bin: string, args: string[], timeout: number | null) => runAdb(bin, [...server, ...args], timeout);
  const speaks = share.lang;
  const adb = shares.adb();
  if (adb === null) return share.set("missing", tr(speaks, "station.adb.install"));
  const serial = share.serial();
  // Nothing to reach: adb is not left trying to (it would, a few times a second).
  if (share.info.adbd === false) {
    await run(adb, ["disconnect", serial], shares.limits.quick).catch(() => {});
    return share.set("off", tr(speaks, "station.adb.wirelessOff"));
  }
  const state = () => run(adb, ["-s", serial, "get-state"], shares.limits.quick).catch(() => "");
  // Held already (another offer: the pairing port opened, a new link): it stays so.
  if ((await state()) === "device") {
    keepLending(shares, share, server);
    return share.set("connected");
  }
  share.set("connecting");
  share.refused = null;
  // What adb kept of a tunnel gone (the phone's adbd on another port now) goes first.
  await run(adb, ["disconnect", serial], shares.limits.quick).catch(() => {});
  try {
    await run(adb, ["connect", serial], shares.limits.long);
  } catch (error) {
    return share.set("failed", (error as Error).message);
  }
  // adb says `connected to …` for a TLS port it is not paired with too; only its state says whether it got in: looked
  // at every 500 ms until it is `device`, the phone turned its tunnel down (nothing listens there: no use waiting), or
  // SETTLE is over.
  const now = await shares.run(
    Effect.gen(function* () {
      const started = yield* Clock.currentTimeMillis;
      for (;;) {
        const now = yield* Effect.promise(state);
        if (now === "device" || share.refused !== null || (yield* Clock.currentTimeMillis) - started >= SETTLE) return now;
        yield* Effect.raceFirst(Effect.sleep(500), Effect.promise(() => share.refusal()));
      }
    }),
  );
  const refused = share.refused;
  share.refused = null;
  if (now === "device") {
    keepLending(shares, share, server);
    share.set("connected");
  } else if (now === "unauthorized") share.set("unauthorized", tr(speaks, "station.adb.allowPrompt"));
  else if (refused !== null) {
    // adb would go on dialling it a few times a second (260 refusals in 12 s): let go until the next offer.
    await run(adb, ["disconnect", serial], shares.limits.quick).catch(() => {});
    share.set("failed", refused);
  } else share.set("unpaired", tr(speaks, "station.adb.unpaired"));
}

/// `adb pair` through the phone's pairing port (open while its 使用配对码配对设备 dialog is), then connected anew.
async function pair(shares: Shares, share: Share, typed: string, lang: Lang): Promise<string> {
  const code = [...typed].filter((c) => c >= "0" && c <= "9").join("");
  if (code.length !== 6) throw new Error(tr(lang, "station.adb.codeDigits"));
  if (share.info.pair !== true) throw new Error(tr(lang, "station.adb.pairingClosed"));
  const adb = shares.adb();
  if (adb === null) throw new Error(tr(lang, "station.adb.noAdb"));
  // A port for this pairing alone, its one connection the phone's pairing port.
  const server = await listenOn(0);
  const port = (server.address() as net.AddressInfo).port;
  const conn = share.conn;
  const done = new AbortController();
  const timer = shares.limits.long === null ? () => {} : wall.after(shares.limits.long, () => server.close());
  let tunnelled: Promise<void> = Promise.resolve();
  server.once("connection", (socket) => {
    timer();
    server.close();
    tunnelled = tunnel(conn, "pair", socket, done.signal).catch((error) => log.info("adb", "adb pairing tunnel ended", { error: (error as Error).message, ...about(conn) }));
  });
  let said: string;
  try {
    said = await run(adb, ["pair", `127.0.0.1:${port}`, code], shares.limits.long);
  } finally {
    timer();
    server.close();
    // Not ended with adb: what it wrote last (its peer info, the station's key) is still on its way to the phone, which
    // keeps the key only once it has it (2026-10-26: reset at once, the phone 150 ms off through a relay never had it;
    // adb said paired, the phone listed nothing). The tunnel ends as both sides finish; reset only if the phone holds
    // it open past TUNNEL_OPEN.
    const late = wall.after(TUNNEL_OPEN, () => done.abort());
    void tunnelled.finally(late);
  }
  if (!said.includes("Successfully paired")) throw new Error(tr(lang, "station.adb.pairFailed", { said }));
  void connect(shares, share).catch(() => {});
  return tr(lang, "station.adb.paired");
}

/// As the station's adb comes to hold the phone, what keeps it lending with no one at it, done through that adb (in
/// `server`), the phone's person having lent it (each time: what an app installed anew lost, given again): the app may turn Wireless debugging on itself
/// (`WRITE_SECURE_SETTINGS`: after the phone starts again, or as its Wi-Fi changes, Android turns it off), and Android's
/// idling leaves the app's connection be (`deviceidle whitelist`: a phone left aside put the app's network to sleep,
/// its tunnels not taken). What the phone refuses (MIUI and ColorOS refuse the shell's grant until a switch of
/// Developer options is on) is logged, not said: the person turns it on from 共享调试 (grant).
function keepLending(shares: Shares, share: Share, server: string[]): void {
  const pkg = share.info.package;
  const adb = shares.adb();
  if (!pkg || !isPackage(pkg) || adb === null) return;
  const asks = [
    ["shell", "pm", "grant", pkg, "android.permission.WRITE_SECURE_SETTINGS"],
    ["shell", "cmd", "deviceidle", "whitelist", `+${pkg}`],
  ];
  void (async () => {
    for (const ask of asks) {
      const said = await run(adb, [...server, "-s", share.serial(), ...ask], shares.limits.long).catch((error: Error) => error.message);
      log.info("adb", "adb kept the phone lending", { ask: ask.slice(1, 3).join(" "), said: said.split("\n")[0]!.trim().slice(0, 160), ...about(share.conn) });
    }
  })();
}

/// Lets the app turn Wireless debugging on itself from now on (`WRITE_SECURE_SETTINGS`), as its person asked.
async function grant(shares: Shares, share: Share, lang: Lang): Promise<string> {
  const pkg = share.info.package;
  if (!pkg) throw new Error(tr(lang, "station.adb.noPackage"));
  const adb = shares.adb();
  if (adb === null) throw new Error(tr(lang, "station.adb.noAdb"));
  const server = ((await serversOf(shares, share)) ?? [[]])[0]!;
  const said = await run(adb, [...server, "-s", share.serial(), "shell", "pm", "grant", pkg, "android.permission.WRITE_SECURE_SETTINGS"], shares.limits.long);
  // Quiet is granted. MIUI and ColorOS refuse the shell's grant (a SecurityException, a page of stack) until a switch in
  // Developer options is on: said as which one; anything else, by its first line.
  if (/GRANT_RUNTIME_PERMISSIONS/.test(said)) throw new Error(tr(lang, "station.adb.grantRefused"));
  if (said !== "") throw new Error(tr(lang, "station.adb.grantFailed", { said: said.split("\n")[0]!.trim() }));
  return tr(lang, "station.adb.granted");
}

/// The machine's adb: on `PATH`, else the Android SDK's (where Android Studio puts it, whose adb server is likely the
/// one running: another version's client would restart it), else a package manager's (launchd gives the station a
/// short `PATH`).
export function adbPath(): string | null {
  const env = process.env;
  // adb.exe on Windows, and the SDK where Android Studio puts it there (%LOCALAPPDATA%\Android\Sdk).
  const adb = platform.exe("adb");
  // On PATH as a shell finds it (on Windows, with PATHEXT's extensions).
  const onPath = platform.findCommand("adb", env)?.onPath;
  const candidates = [
    ...(onPath ? [onPath] : []),
    ...(env.PATH ?? "").split(delimiter).filter(Boolean).map((d) => join(d, adb)),
    ...[env.ANDROID_HOME, env.ANDROID_SDK_ROOT].filter((d): d is string => !!d).map((d) => join(d, "platform-tools", adb)),
    ...(env.HOME ? [join(env.HOME, "Library/Android/sdk/platform-tools/adb"), join(env.HOME, "Android/Sdk/platform-tools/adb")] : []),
    ...(env.LOCALAPPDATA ? [join(env.LOCALAPPDATA, "Android", "Sdk", "platform-tools", adb)] : []),
    "/opt/homebrew/bin/adb",
    "/usr/local/bin/adb",
    "/usr/bin/adb",
  ];
  return candidates.find((p) => existsSync(p) && statSync(p).isFile()) ?? null;
}

/// What adb says to `args` (out, then err), within `timeout`. Said whatever its exit; fails only if it could not be
/// started or did not answer in time.
export function run(adb: string, args: string[], timeout: number | null): Promise<string> {
  return new Promise((resolve, reject) => {
    // A .cmd (a shim) runs through its script or cmd: Node starts none by itself.
    const r = platform.runnable(adb, args, process.env);
    const child = spawn(r.file, r.args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    child.stdout.on("data", (b) => out.push(b));
    child.stderr.on("data", (b) => err.push(b));
    const timer =
      timeout === null
        ? () => {}
        : wall.after(timeout, () => {
            child.kill("SIGKILL");
            reject(new Error("adb did not answer in time"));
          });
    child.on("error", (error) => {
      timer();
      reject(error);
    });
    child.on("close", () => {
      timer();
      resolve((Buffer.concat(out).toString() + Buffer.concat(err).toString()).trim());
    });
  });
}

const runAdb = (adb: string, args: string[], timeout: number | null) => run(adb, args, timeout);

/// A word the phone says of itself, short and on one line.
export function text(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return [...value].filter((c) => !/\p{Cc}/u.test(c)).slice(0, max).join("");
}

/// An Android package name, as `pm grant` takes it: nothing a shell would read otherwise.
export function isPackage(name: string): boolean {
  return name.length > 0 && name.length <= 200 && /^[A-Za-z0-9._]+$/.test(name);
}


