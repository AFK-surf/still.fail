// An adb server of each grant's own (2026-10-29): a phone granted to a chat is connected in that
// grant's server alone, its port given to that chat's agent (phone_use), and the phone's listener takes connections
// from those servers' processes alone (`allowed`). An agent of another chat, though it knows the ports, reaches neither:
// the phone is not in the station's own server (5037), a connection of its to the phone's port is turned away, and the
// server's own port is a door that lets the grant's session through alone (door.ts; none on Windows, where the machine's
// processes are not read: there the server serves on the port as it is).
import { type ChildProcess, spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { readFile, rename, rm, writeFile } from "node:fs/promises";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { type Admit, openDoor } from "./door.ts";

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
type Kept = { pid: number; port: number; started: number | null; dir?: string };

export class GrantServers {
  readonly #adb: () => string | null;
  readonly #servers = new Map<string, Promise<Server | null>>();
  /// Where the servers started are written down (null: nowhere, as in tests), for the next station process to stop what
  /// this one left: they are this process's children, and one that ends without stopping them (killed, a handover that
  /// did not finish) can leave them running.
  readonly #record: string | null;
  readonly #kept = new Map<number, Kept>();
  #writing: Promise<void> = Promise.resolve();
  /// Who may use a server (door.ts); none: its port is the server's own.
  readonly #admit: Admit | null;

  constructor(adb: () => string | null, record: string | null = null, admit: Admit | null = null) {
    this.#adb = adb;
    this.#record = record;
    this.#admit = admit;
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
      if (typeof k.dir === "string") await rm(k.dir, { recursive: true, force: true });
      const started = await platform.startTimeOf(k.pid);
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
      // Behind its door, on a socket of a directory of its own, named in its environment and not on its command line;
      // else on the port itself.
      const dir = this.#admit === null ? null : mkdtempSync(join(tmpdir(), "sf-adb-"));
      const path = dir === null ? null : join(dir, "s");
      const door = path === null ? null : await openDoor(id, path, (p) => platform.tcpPortPids(p), this.#admit!);
      const port = door?.port ?? (await freePort());
      const env = path === null ? process.env : { ...process.env, ADB_SERVER_SOCKET: `localfilesystem:${path}` };
      const r = platform.runnable(adb, path === null ? ["-P", String(port), "server", "nodaemon"] : ["server", "nodaemon"], env);
      const child = spawn(r.file, r.args, { env, stdio: "ignore", windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments });
      const closed = () => {
        door?.close();
        if (dir !== null) rmSync(dir, { recursive: true, force: true });
      };
      const up = await new Promise<boolean>((resolve) => {
        child.once("exit", () => resolve(false));
        child.once("error", () => resolve(false));
        // Up once it takes a connection on its socket or port.
        const tries = { n: 0 };
        const poke = () => {
          const c = net.connect(path === null ? { host: "127.0.0.1", port } : { path }, () => {
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
          this.#kept.set(pid, { pid, port, started: null, ...(dir === null ? {} : { dir }) });
          void this.#write();
          // When it started, for a station after this one to know it is still this process: asked, not waited on.
          void platform.startTimeOf(pid).then((started) => {
            const kept = this.#kept.get(pid);
            if (kept === undefined || started === null) return;
            kept.started = started;
            void this.#write();
          });
        }
        child.once("exit", () => {
          closed();
          if (pid !== undefined && this.#kept.delete(pid)) void this.#write();
          // Gone (killed, crashed): started anew when next wanted.
          if (this.#servers.get(id) !== undefined) this.#servers.delete(id);
        });
        log.info("adb", "a grant's adb server started", { grant: id, port, pid: child.pid });
        return { port, child };
      }
      child.kill("SIGKILL");
      closed();
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

  /// Done once what was asked written of the record so far is written: a test's wait. Nothing of the station waits on
  /// it, nor on a server's end, as it stops (`close`): a server that does not end at SIGTERM must not hold a station
  /// that stops or hands over, whose agents, events and store close after this, and a record left naming a server
  /// that has ended costs the next station one ps (`reap`).
  written(): Promise<void> {
    return this.#writing;
  }

  async close(): Promise<void> {
    await Promise.all(this.ids().map((id) => this.stop(id)));
  }
}
