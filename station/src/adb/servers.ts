// An adb server of each grant's own (docs/adb-share.md, 2026-10-29): a phone granted to a chat is connected in that
// grant's server alone, its port given to that chat's agent (phone_use), and the phone's listener takes connections
// from those servers' processes alone (`allowed`). An agent of another chat, though it knows the ports, reaches neither:
// the phone is not in the station's own server (5037), and a connection of its to the phone's port is turned away.
import { type ChildProcess, spawn } from "node:child_process";
import { readFile, rename, writeFile } from "node:fs/promises";
import net from "node:net";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";

export type Server = { port: number; child: ChildProcess };

/// A free port on 127.0.0.1 (another process may take it before the server does: it is tried again then).
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.once("error", reject);
    s.listen({ host: "127.0.0.1", port: 0 }, () => {
      const port = (s.address() as net.AddressInfo).port;
      s.close(() => resolve(port));
    });
  });
}

/// A server started here, as written down (`record`): its process, and when that started (another process given its pid
/// later is not it).
type Kept = { pid: number; port: number; started: number | null };

export class GrantServers {
  readonly #adb: () => string | null;
  readonly #servers = new Map<string, Promise<Server | null>>();
  /// Where the servers started are written down (null: nowhere, as in tests), for the next station process to stop what
  /// this one left: they are this process's children, and one that ends without stopping them (killed, a handover that
  /// did not finish) can leave them running.
  readonly #record: string | null;
  readonly #kept = new Map<number, Kept>();
  #writing: Promise<void> = Promise.resolve();

  constructor(adb: () => string | null, record: string | null = null) {
    this.#adb = adb;
    this.#record = record;
  }

  /// Stops the servers a station process before left running (once it is gone: `previousGone`), as written down.
  async reap(previousGone: Promise<void> = Promise.resolve()): Promise<number> {
    if (this.#record === null) return 0;
    await previousGone;
    let left: Kept[] = [];
    try {
      left = JSON.parse(await readFile(this.#record, "utf8"));
    } catch {}
    let stopped = 0;
    for (const k of Array.isArray(left) ? left : []) {
      if (!Number.isSafeInteger(k?.pid) || this.#kept.has(k.pid)) continue;
      const started = platform.startTimeOf(k.pid);
      // Not that process any more (gone, or its pid another's).
      if (started === null || (k.started !== null && Math.abs(started - k.started) > 2000)) continue;
      try {
        process.kill(k.pid, "SIGTERM");
        stopped++;
      } catch {}
    }
    if (stopped > 0) log.info("adb", "the grants' adb servers a station before left stopped", { n: stopped });
    await this.#write();
    return stopped;
  }

  /// One write at a time, each of what is kept as it begins: two servers that ended at once (as a station hands over)
  /// wrote through the same temporary file, and the second's rename, finding none, ended the process (ccvm 2026-11-04).
  #write(): Promise<void> {
    const record = this.#record;
    if (record === null) return Promise.resolve();
    this.#writing = this.#writing.then(async () => {
      const temp = `${record}.${process.pid}.tmp`;
      try {
        await writeFile(temp, JSON.stringify([...this.#kept.values()]));
        await rename(temp, record);
      } catch (error) {
        log.warn("adb", "the grants' adb servers were not written down", { error: (error as Error).message });
      }
    });
    return this.#writing;
  }

  /// Grant `id`'s server, started if it is not running (`adb -P <port> server nodaemon`: its own process, held here).
  ensure(id: string): Promise<Server | null> {
    let s = this.#servers.get(id);
    if (s === undefined) {
      s = this.#start(id);
      this.#servers.set(id, s);
    }
    return s;
  }

  async #start(id: string): Promise<Server | null> {
    const adb = this.#adb();
    if (adb === null) return null;
    for (let i = 0; i < 3; i++) {
      const port = await freePort();
      const r = platform.runnable(adb, ["-P", String(port), "server", "nodaemon"], process.env);
      const child = spawn(r.file, r.args, { stdio: "ignore", windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments });
      const up = await new Promise<boolean>((resolve) => {
        child.once("exit", () => resolve(false));
        child.once("error", () => resolve(false));
        // Up once it takes a connection on its port.
        const tries = { n: 0 };
        const poke = () => {
          const c = net.connect({ host: "127.0.0.1", port }, () => {
            c.destroy();
            resolve(true);
          });
          c.once("error", () => {
            c.destroy();
            if (++tries.n < 50) wall.after(100, poke);
            else resolve(false);
          });
        };
        poke();
      });
      if (up) {
        const pid = child.pid;
        if (pid !== undefined) {
          this.#kept.set(pid, { pid, port, started: platform.startTimeOf(pid) });
          void this.#write();
        }
        child.once("exit", () => {
          if (pid !== undefined && this.#kept.delete(pid)) void this.#write();
          // Gone (killed, crashed): started anew when next wanted.
          if (this.#servers.get(id) !== undefined) this.#servers.delete(id);
        });
        log.info("adb", "a grant's adb server started", { grant: id, port, pid: child.pid });
        return { port, child };
      }
      child.kill("SIGKILL");
    }
    log.warn("adb", "a grant's adb server did not start", { grant: id });
    this.#servers.delete(id);
    return null;
  }

  /// Grant `id`'s server stopped (the grant ended).
  async stop(id: string): Promise<void> {
    const s = await this.#servers.get(id);
    this.#servers.delete(id);
    s?.child.kill("SIGTERM");
  }

  /// The grants whose servers run (or start).
  ids(): string[] {
    return [...this.#servers.keys()];
  }

  /// Which grant's server is at the other end of `socket` (a loopback connection to a phone's port), if any.
  async owner(socket: net.Socket, ids: string[]): Promise<string | null> {
    const pids = new Map<number, string>();
    for (const id of ids) {
      const s = await this.#servers.get(id);
      if (s?.child.pid !== undefined) pids.set(s.child.pid, id);
    }
    if (pids.size === 0 || socket.remotePort === undefined) return null;
    const holders = await platform.tcpPortPids(socket.remotePort);
    for (const p of holders) {
      const id = pids.get(p);
      if (id !== undefined) return id;
    }
    return null;
  }

  async close(): Promise<void> {
    await Promise.all(this.ids().map((id) => this.stop(id)));
  }
}
