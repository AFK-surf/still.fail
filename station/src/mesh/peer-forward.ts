// A port of another station forwarded to this machine, as `ssh -L` does (docs/station-peers.md "Forwarded ports"): a
// listener on 127.0.0.1:<local> here, each connection to it carried as it is (bytes both ways, at the pace the slower
// side takes them, either side's end passed on) over the mesh to localhost:<port> on that station. Unlike /peer's
// path, nothing about the traffic changes (paths, Host, WebSockets, any protocol), so web pages, dev servers and
// databases work as they do there. Each forward is the session's that opened it (peer_forward, tools/forward.ts): it
// closes when that session is archived or deleted, when the job it was tied to ends, after a while with no connection,
// or when the station stops (none outlives the process). Connections go on peer-http.ts's protocol (`tcp: true`),
// admitted and refused there as /peer requests are.
import { type Socket, connect, createServer, type Server } from "node:net";
import type { Clock } from "effect";
import { Fibers, wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Stream } from "./native.ts";

/// A forward with no connection for this long is closed.
export const IDLE_MS = 30 * 60_000;
/// After its station could not be reached, connections to a forward are closed at once for this long, not each left
/// waiting for the mesh to give up again.
export const DOWN_MS = 10_000;
/// How long a listing waits to hear whether a forward's station is there.
const PROBE_MS = 5_000;
/// How long a service here has to take a forwarded connection.
const REACH_MS = 10_000;
/// How long a look at whether something here listens on a port waits.
const LOOK_MS = 1_000;

/// Until `socket` can take more, or is gone.
function drained(socket: Socket): Promise<void> {
  return new Promise((resolve) => {
    const done = () => {
      socket.off("drain", done);
      socket.off("close", done);
      resolve();
    };
    socket.on("drain", done);
    socket.on("close", done);
  });
}

/// Ends a connection that failed or could not be carried: reset (RST), so the program at its other end hears it was cut
/// off, not that it ended (an end alone is a half-close: a program that keeps its side open would wait on).
export function abort(socket: Socket) {
  if (socket.destroyed) return;
  try {
    socket.resetAndDestroy();
  } catch {
    socket.destroy();
  }
}

/// Carries a TCP connection's bytes over a mesh stream and back until both sides have ended: what the socket sends is
/// written as fast as the stream takes it (the socket paused meanwhile), what the stream brings is read only as fast as
/// the socket takes it. Either side's end (a half-close) is passed on to the other, the rest still flowing the other
/// way; a failure on either side (a reset, a socket error, the socket closed before the stream's end went to it) resets
/// both. `carry`: what came on the stream past its head. The socket is half-open
/// (`allowHalfOpen`) and may be paused; it is resumed here.
export function pipeTcp(socket: Socket, stream: Stream, carry: Buffer = Buffer.alloc(0)): Promise<void> {
  return new Promise((resolve) => {
    let over = false;
    // The stream's end, given to the socket.
    let delivered = false;
    // The socket's end, being given to the stream (once what it sent before is written).
    let finishing: Promise<void> | null = null;
    let writing: Promise<void> = Promise.resolve();
    const fail = () => {
      if (over) return;
      over = true;
      abort(socket);
      void stream.reset(0).catch(() => {});
      resolve();
    };
    // Gone before it came here (reset while its stream was being answered).
    if (socket.destroyed) return fail();
    socket.on("error", fail);
    socket.on("close", () => {
      if (over) return;
      if (finishing === null || !delivered) return fail();
      finishing.then(() => {
        over = true;
        resolve();
      }, fail);
    });
    socket.on("data", (chunk: Buffer) => {
      socket.pause();
      writing = stream.write(chunk).then(() => {
        if (!over) socket.resume();
      });
      writing.catch(fail);
    });
    socket.on("end", () => {
      finishing = writing.then(() => stream.finish());
      finishing.catch(fail);
    });
    void (async () => {
      try {
        if (carry.length > 0 && !socket.write(carry)) await drained(socket);
        for (let more = await stream.read(); more !== null; more = await stream.read()) {
          if (over || socket.destroyed) return;
          if (!socket.write(more)) await drained(socket);
        }
        if (over || socket.destroyed) return;
        delivered = true;
        socket.end();
      } catch {
        fail();
      }
    })();
    socket.resume();
  });
}

/// One try at localhost:`port` at `host`.
function reachAt(host: string, port: number): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = connect({ host, port, allowHalfOpen: true });
    const stop = wall.after(REACH_MS, () => {
      socket.destroy();
      reject(new Error(`[${host}]:${port} took no connection within ${REACH_MS / 1000} s`));
    });
    const failed = (error: Error) => {
      stop();
      reject(error);
    };
    socket.once("error", failed);
    socket.once("connect", () => {
      stop();
      socket.off("error", failed);
      // Until its pump hears them (pipeTcp): one going meanwhile is found destroyed there.
      socket.on("error", () => {});
      socket.pause();
      resolve(socket);
    });
  });
}

/// A connection to `port` on this machine as a local program makes one to localhost: 127.0.0.1, then [::1] (a service
/// may listen on either alone: some only on [::1], as wrangler and others do, some only on 127.0.0.1). Paused,
/// half-open.
export async function reachLocal(port: number): Promise<Socket> {
  try {
    return await reachAt("127.0.0.1", port);
  } catch (v4) {
    try {
      return await reachAt("::1", port);
    } catch (v6) {
      throw new Error(`127.0.0.1: ${(v4 as Error).message}; [::1]: ${(v6 as Error).message}`);
    }
  }
}

/// Whether something on this machine takes connections on `port` at `host`.
function listening(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host, port });
    const done = (yes: boolean) => {
      stop();
      socket.destroy();
      resolve(yes);
    };
    const stop = wall.after(LOOK_MS, () => done(false));
    socket.once("connect", () => done(true));
    socket.once("error", () => done(false));
  });
}

/// A listener on 127.0.0.1:`port` (0: any free one), or null when that port is not to be had: something here listens on
/// it already, at 127.0.0.1 or [::1] (where `localhost` may go first), or it cannot be bound. `ours`: a forward's here
/// already (not knocked on to find out).
async function listenAt(port: number, take: (socket: Socket) => void, ours: boolean): Promise<Server | null> {
  if (ours) return null;
  if (port !== 0 && ((await listening("127.0.0.1", port)) || (await listening("::1", port)))) return null;
  const server = createServer({ allowHalfOpen: true, pauseOnConnect: true }, take);
  return new Promise((resolve) => {
    server.once("error", () => resolve(null));
    server.listen({ host: "127.0.0.1", port, exclusive: true }, () => {
      server.removeAllListeners("error");
      server.on("error", (error) => log.warn("mesh", "a forwarded port's listener failed", { error: error.message }));
      resolve(server);
    });
  });
}

/// The way to other stations' ports (peer-http.ts `PeerHttp.tunnel`).
export type Tunnels = {
  tunnel(station: string, port: number, probe?: boolean): Promise<{ stream: Stream; carry: Buffer } | null>;
};

/// A job's state as a forward tied to it needs it (the store's record).
export type JobState = { session: string; state: string; port: number | null };

export type ForwardsOptions = {
  /// The mesh's way to the other stations, once it is up.
  route: () => Tunnels | null;
  /// The station names a station by, given its id or name (for what a forward shows), and its id.
  resolve: (station: string) => { id: string; name: string };
  /// Jobs, for forwards tied to one: a job's record (null: none), and its changes (the ids of those that changed).
  jobs?: { job(id: string): JobState | null; changes(changed: (id: string) => void): () => void };
  clock?: Clock.Clock;
  idleMs?: number;
  downMs?: number;
};

type Forward = {
  session: string;
  /// The station's id, and its name when it was opened.
  id: string;
  name: string;
  port: number;
  local: number;
  job: string | null;
  server: Server;
  sockets: Set<Socket>;
  /// Connections it has carried, and when its last one ended (or it opened).
  served: number;
  quietSince: number;
  idle: (() => void) | null;
  /// Its station not reached: until when connections are closed at once, and why.
  down: { until: number; why: string } | null;
  /// Why its last connection failed, if it did.
  failed: string | null;
};

/// What a forward is, as its session sees it.
export type ForwardView = {
  local: string;
  url: string;
  station: string;
  port: number;
  connections: number;
  served: number;
  job?: string;
  /// How a listing found its station: "online", or why not.
  station_state?: string;
  last_error?: string;
  idle_minutes?: number;
};

/// This station's forwarded ports, each its session's.
export class Forwards {
  private route: () => Tunnels | null;
  private resolve: (station: string) => { id: string; name: string };
  private fibers: Fibers;
  private idleMs: number;
  private downMs: number;
  private byLocal = new Map<number, Forward>();
  private unlistenJobs: () => void;
  private jobs: ForwardsOptions["jobs"];
  private closed = false;

  constructor(options: ForwardsOptions) {
    this.route = options.route;
    this.resolve = options.resolve;
    this.fibers = new Fibers("forwards", options.clock);
    this.idleMs = options.idleMs ?? IDLE_MS;
    this.downMs = options.downMs ?? DOWN_MS;
    this.jobs = options.jobs;
    this.unlistenJobs = options.jobs?.changes((id) => {
      for (const f of [...this.byLocal.values()]) if (f.job === id && this.jobOver(id)) this.shut(f, "its job ended");
    }) ?? (() => {});
  }

  /// Whether job `id` is over: stopped, failed, gone, or a command that exited (a service that exited is started
  /// again).
  private jobOver(id: string): boolean {
    const job = this.jobs?.job(id) ?? null;
    return job === null || job.state === "stopped" || job.state === "failed" || (job.state === "exited" && job.port === null);
  }

  private view(f: Forward): ForwardView {
    const v: ForwardView = { local: `127.0.0.1:${f.local}`, url: `http://127.0.0.1:${f.local}/`, station: f.name, port: f.port, connections: f.sockets.size, served: f.served };
    if (f.job !== null) v.job = f.job;
    return v;
  }

  /// The mesh's way, or why there is none.
  private way(): Tunnels {
    const route = this.route();
    if (route === null) throw new Error("this station is not on the mesh yet; try again shortly");
    return route;
  }

  /// Forwards port `port` of `station` (its name or id) to 127.0.0.1 here for `session`: at the same port when it is
  /// free here, else at `local` when given (an error when that one is taken), else any free one. That station is asked
  /// first whether it takes forwards to that port. `job`: one of the session's jobs it closes with. A forward the
  /// session has already to that station's port is given again.
  async open(session: string, station: string, port: number, local?: number, job?: string): Promise<ForwardView & { note?: string }> {
    if (this.closed) throw new Error("the station is stopping");
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("port: 1 to 65535");
    if (local !== undefined && (!Number.isInteger(local) || local < 1 || local > 65535)) throw new Error("local_port: 1 to 65535");
    if (job !== undefined) {
      const j = this.jobs?.job(job) ?? null;
      if (j === null || j.session !== session) throw new Error(`no job ${job} of this session: job_list names them`);
      if (this.jobOver(job)) throw new Error(`job ${job} has ended`);
    }
    const route = this.way();
    const { id, name } = this.resolve(station);
    const had = [...this.byLocal.values()].find((f) => f.session === session && f.id === id && f.port === port && f.job === (job ?? null) && (local === undefined || f.local === local));
    if (had !== undefined) return { ...this.view(had), note: "already forwarded" };
    // That station takes it (it is new enough, the port is not its own, it has this one in its workspace): asked once
    // now, so what would fail every connection fails here.
    await route.tunnel(id, port, true);
    const f: Forward = { session, id, name, port, local: 0, job: job ?? null, server: null as unknown as Server, sockets: new Set(), served: 0, quietSince: this.fibers.now(), idle: null, down: null, failed: null };
    const take = (socket: Socket) => this.connection(f, socket);
    let note: string | undefined;
    let server = await listenAt(local ?? port, take, this.byLocal.has(local ?? port));
    if (server === null && local !== undefined) throw new Error(`127.0.0.1:${local} is taken here (something listens on it, at 127.0.0.1 or [::1]); give another local_port, or none`);
    if (server === null) {
      server = await listenAt(0, take, false);
      if (server === null) throw new Error("no port could be had on 127.0.0.1");
    }
    f.server = server;
    f.local = (server.address() as { port: number }).port;
    if (local === undefined && f.local !== port) note = `port ${port} is taken here, so it is at ${f.local}`;
    if (this.closed || (job !== undefined && this.jobOver(job))) {
      server.close();
      throw new Error(this.closed ? "the station is stopping" : `job ${job} has ended`);
    }
    this.byLocal.set(f.local, f);
    this.quiet(f);
    log.info("mesh", "a port forwarded", { session, station: id, port, local: f.local });
    return note === undefined ? this.view(f) : { ...this.view(f), note };
  }

  /// One connection to a forward: carried to its station's port, or closed when it cannot be.
  private connection(f: Forward, socket: Socket) {
    if (!this.byLocal.has(f.local)) return abort(socket);
    f.sockets.add(socket);
    f.served++;
    f.idle?.();
    f.idle = null;
    socket.on("error", () => {});
    socket.once("close", () => {
      f.sockets.delete(socket);
      if (f.sockets.size === 0 && this.byLocal.get(f.local) === f) this.quiet(f);
    });
    const now = this.fibers.now();
    if (f.down !== null && now < f.down.until) return abort(socket);
    const route = this.route();
    if (route === null) {
      f.failed = "this station is not on the mesh";
      return abort(socket);
    }
    route.tunnel(f.id, f.port).then(
      (tunnel) => {
        f.down = null;
        if (tunnel === null) return abort(socket);
        if (socket.destroyed || this.byLocal.get(f.local) !== f) return void tunnel.stream.reset(0).catch(() => {});
        void pipeTcp(socket, tunnel.stream, tunnel.carry);
      },
      (error) => {
        const why = (error as Error).message;
        f.failed = why;
        if ((error as { unreachable?: boolean }).unreachable === true) f.down = { until: this.fibers.now() + this.downMs, why };
        abort(socket);
      },
    );
  }

  /// No connection now: closed if none comes for a while.
  private quiet(f: Forward) {
    f.quietSince = this.fibers.now();
    f.idle?.();
    f.idle = this.fibers.after(this.idleMs, () => {
      if (f.sockets.size === 0) this.shut(f, "idle");
    });
  }

  private shut(f: Forward, why: string) {
    if (this.byLocal.get(f.local) !== f) return;
    this.byLocal.delete(f.local);
    f.idle?.();
    f.idle = null;
    f.server.close();
    for (const socket of f.sockets) abort(socket);
    log.info("mesh", "a forwarded port closed", { session: f.session, station: f.id, port: f.port, local: f.local, why });
  }

  /// The session's forwards, each with whether its station answers now.
  async list(session: string): Promise<ForwardView[]> {
    const mine = [...this.byLocal.values()].filter((f) => f.session === session).sort((a, b) => a.local - b.local);
    const route = this.route();
    return Promise.all(
      mine.map(async (f) => {
        const v = this.view(f);
        if (route === null) v.station_state = "unknown: this station is not on the mesh";
        else {
          try {
            await wall.within(PROBE_MS, route.tunnel(f.id, f.port, true), `offline: no answer within ${PROBE_MS / 1000} s`);
            v.station_state = "online";
            f.down = null;
          } catch (error) {
            const why = (error as Error).message;
            v.station_state = (error as { unreachable?: boolean }).unreachable === true && !why.startsWith("offline") ? `offline: ${why}` : why;
          }
        }
        if (f.failed !== null) v.last_error = f.failed;
        if (f.sockets.size === 0) v.idle_minutes = Math.floor((this.fibers.now() - f.quietSince) / 60_000);
        return v;
      }),
    );
  }

  /// Closes the session's forward at 127.0.0.1:`local`; what it was.
  remove(session: string, local: number): ForwardView {
    const f = this.byLocal.get(local);
    if (f === undefined || f.session !== session) throw new Error(`no forward of this session at 127.0.0.1:${local}: peer_forward {} lists them`);
    const v = this.view(f);
    this.shut(f, "closed");
    return v;
  }

  /// The forwards of a session that is archived or deleted.
  closeSession(session: string) {
    for (const f of [...this.byLocal.values()]) if (f.session === session) this.shut(f, "its session ended");
  }

  /// Whether 127.0.0.1:`port` is a forward's (other stations are refused it: peer-http.ts `HereLocal`).
  forwarded(port: number): boolean {
    return this.byLocal.has(port);
  }

  /// How many forwards there are (`session`: of that session).
  count(session?: string): number {
    return [...this.byLocal.values()].filter((f) => session === undefined || f.session === session).length;
  }

  /// All of them (the station stops: none outlives it).
  async close(): Promise<void> {
    this.closed = true;
    this.unlistenJobs();
    for (const f of [...this.byLocal.values()]) this.shut(f, "the station stopped");
    await this.fibers.close();
  }
}
