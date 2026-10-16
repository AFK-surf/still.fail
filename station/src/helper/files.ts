// The drive's folders macOS keeps from a station launchd runs (Documents, Desktop, Downloads, disks; drive/fs.ts
// `protectedTop`), reached through still.fail Helper (native/helper's Files.swift), which holds the grants for them:
// the drive's operations as the helper's `files.*` requests, each on a connection of its own, told the roots it may
// reach and what it may not (the drive has checked the paths already; the helper checks them again). A file's bytes go
// over that connection as they are read or written, never a whole file at once: a read answers its head line, then
// the bytes; a write is answered once the file is open, then the station sends the bytes, then it answers again.
//
// Without the grant the helper refuses (`grant`) and touches nothing (macOS would put up its prompt and hold the call
// until a person answers): the drive puts the helper's window up on this Mac for it (`ask`), once an attempt. What is
// known of each folder's grant is kept (`known`), looked at in the background where it is not (`check`), and looked at
// again when the helper says a grant changed or comes back; the drive's roots are told again (`changed`) when it is
// not what it was.
import { open, unlink } from "node:fs/promises";
import type net from "node:net";
import { join } from "node:path";
import type { Access, Fs, Grant, Listed, Stat, Write, Written } from "../drive/fs.ts";
import { wall } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { HelperApp } from "./app.ts";

/// What a write sends at a time (the socket takes it as it can).
const CHUNK = 256 * 1024;
/// The window asked for the same grant this recently is not asked again (a page reads a folder and its parent at once).
const AGAIN_MS = 5_000;

/// The helper's window's words for the drive's folders, in `lang` (Permissions.swift).
export function filesWords(lang: Lang): Record<string, string> {
  const w = (key: string) => tr(lang, `station.helper.window.${key}`);
  return {
    title: w("filesTitle"),
    subtitle: w("filesSubtitle"),
    documents: w("documents"),
    documentsWhy: w("documentsWhy"),
    desktop: w("desktop"),
    desktopWhy: w("desktopWhy"),
    downloads: w("downloads"),
    downloadsWhy: w("downloadsWhy"),
    removable: w("removable"),
    removableWhy: w("removableWhy"),
    network: w("network"),
    networkWhy: w("networkWhy"),
    deniedWhy: w("deniedWhy"),
    allow: w("allow"),
    done: w("done"),
  };
}

type Refusal = Error & { code?: string; grant?: Grant; state?: Access["state"]; top?: string; pid?: number };

export class HelperFiles {
  readonly #helper: HelperApp;
  readonly #changed: () => void;
  readonly #lang: () => Lang;
  /// Each protected folder (its top) the drive met, with its grant; each grant's state, as last known.
  readonly #grantOf = new Map<string, Grant>();
  readonly #states = new Map<Grant, Access["state"]>();
  readonly #checking = new Set<string>();
  readonly #asked = new Map<Grant, number>();

  constructor(options: { helper: HelperApp; changed: () => void; lang?: () => Lang }) {
    this.#helper = options.helper;
    this.#changed = options.changed;
    this.#lang = options.lang ?? stationLang;
    // A grant changed (its window saw it), or the helper came back: what is known is looked at again.
    options.helper.listen((event) => {
      if (event.event === "grants") this.#again();
    });
    options.helper.onBack(() => this.#again());
  }

  known(top: string): Access | undefined {
    const grant = this.#grantOf.get(top);
    const state = grant === undefined ? undefined : this.#states.get(grant);
    return grant === undefined || state === undefined ? undefined : { grant, state };
  }

  check(tops: string[]): void {
    const asking = tops.filter((t) => !this.#checking.has(t));
    if (asking.length === 0) return;
    for (const t of asking) this.#checking.add(t);
    void this.#look(asking).finally(() => {
      for (const t of asking) this.#checking.delete(t);
    });
  }

  /// What the helper says of `tops` now, kept; told when it is not what was known.
  async #look(tops: string[]): Promise<void> {
    try {
      const answer = await this.#helper.request({ op: "files.access", paths: tops });
      let changed = false;
      for (const a of answer.access ?? []) {
        if (typeof a.grant !== "string") continue;
        this.#grantOf.set(a.path, a.grant);
        changed = this.#learn(a.grant, a.state) || changed;
      }
      if (changed) this.#changed();
    } catch (error) {
      log.warn("drive", "still.fail Helper did not say what it may open", { error: (error as Error).message });
    }
  }

  /// A grant's state as now known; whether that changed it.
  #learn(grant: Grant, state: Access["state"]): boolean {
    if (this.#states.get(grant) === state) return false;
    this.#states.set(grant, state);
    return true;
  }

  /// A request done at `path`: the grant of the protected folder it is in is given.
  #confirm(path: string) {
    const lower = path.toLowerCase();
    for (const [top, grant] of this.#grantOf) {
      const t = top.toLowerCase();
      if ((lower === t || lower.startsWith(`${t}/`)) && this.#learn(grant, "granted")) this.#changed();
    }
  }

  #again() {
    if (this.#grantOf.size > 0) void this.#look([...this.#grantOf.keys()]);
  }

  async ask(grant: Grant, top: string): Promise<boolean> {
    this.#grantOf.set(top, grant);
    const status = await this.#helper.request({ op: "status" }).catch(() => null);
    // Up already asking for it: left as it is (not brought up again and again by a page reading).
    if (status?.asking === true && Array.isArray(status.asked) && status.asked.includes(grant)) return true;
    const last = this.#asked.get(grant) ?? -Infinity;
    if (wall.now() - last < AGAIN_MS) return true;
    this.#asked.set(grant, wall.now());
    try {
      await this.#helper.request({ op: "permissions.show", words: filesWords(this.#lang()), grants: [grant], paths: { [grant]: top } });
      return true;
    } catch (error) {
      log.warn("drive", "still.fail Helper's window did not show", { error: (error as Error).message });
      return false;
    }
  }

  fs(scope: { roots: string[]; protect: string[] }): Fs {
    return new HelperFs(this, scope);
  }

  /// One request, its answer; a grant refused or given learnt on the way. `restart`: the helper starts again to have a
  /// grant given since it started, and is asked once more.
  async request(op: Record<string, unknown>): Promise<any> {
    return this.#learning(op, () => this.#helper.request(op));
  }

  /// A connection for a stream: its head line read (a refusal thrown), the rest the caller's.
  async stream(op: Record<string, unknown>): Promise<{ head: any; socket: net.Socket; rest: Buffer }> {
    return this.#learning(op, async () => {
      const socket = await this.#helper.connect(op);
      return { ...(await lineOf(socket)), socket };
    });
  }

  async #learning<T>(op: Record<string, unknown>, ask: () => Promise<T>): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        const answer = await ask();
        // Done in a protected folder: its grant is there (its roots told so at once, not only when the window says).
        const path = typeof op.path === "string" ? op.path : typeof op.from === "string" ? op.from : null;
        if (path !== null) this.#confirm(path);
        return answer;
      } catch (e) {
        const r = e as Refusal;
        if (r.code === "restart" && attempt === 0 && typeof r.pid === "number") {
          await this.#helper.restarted(r.pid);
          continue;
        }
        if (r.code === "grant" && r.grant && r.state) {
          if (r.top) this.#grantOf.set(r.top, r.grant);
          if (this.#learn(r.grant, r.state)) this.#changed();
        }
        throw e;
      }
    }
  }
}

/// A connection's first line (a refusal thrown), and what came after it; the socket paused, nobody listening.
function lineOf(socket: net.Socket, carry: Buffer = Buffer.alloc(0)): Promise<{ head: any; rest: Buffer }> {
  return new Promise((resolve, reject) => {
    let got = carry;
    const done = () => {
      socket.off("data", data);
      socket.off("close", closed);
      socket.off("error", failed);
      socket.pause();
    };
    const take = () => {
      const at = got.indexOf(10);
      if (at < 0) return false;
      done();
      let head;
      try {
        head = JSON.parse(got.subarray(0, at).toString("utf8"));
      } catch (e) {
        socket.destroy();
        reject(e as Error);
        return true;
      }
      if (typeof head?.error === "string") {
        socket.destroy();
        reject(Object.assign(new Error(head.error), head));
      } else resolve({ head, rest: got.subarray(at + 1) });
      return true;
    };
    const data = (chunk: Buffer) => {
      got = Buffer.concat([got, chunk]);
      take();
    };
    const closed = () => {
      done();
      reject(ended());
    };
    const failed = () => {};
    if (take()) return;
    socket.on("data", data);
    socket.on("close", closed);
    socket.on("error", failed);
    socket.resume();
  });
}

/// The helper went before it said all it had to (it ended, it was restarted): the drive's `io`.
const ended = () => Object.assign(new Error("still.fail Helper ended before it answered"), { code: "EIO" });

/// The rest of a stream (`rest`, then all that comes) given to `take` as it comes, the socket held while `take` works;
/// resolved at its end with how much came.
function drain(socket: net.Socket, rest: Buffer, take: (chunk: Buffer) => Promise<void> | void): Promise<number> {
  return new Promise((resolve, reject) => {
    let got = 0;
    let chain = Promise.resolve();
    let failed: unknown = null;
    const put = (chunk: Buffer) => {
      got += chunk.length;
      chain = chain.then(() => (failed === null ? take(chunk) : undefined)).catch((e) => {
        failed ??= e;
        socket.destroy();
      });
    };
    if (rest.length > 0) put(rest);
    socket.on("data", (chunk: Buffer) => {
      socket.pause();
      put(chunk);
      void chain.then(() => socket.resume());
    });
    socket.on("error", () => {});
    socket.on("close", () => void chain.then(() => (failed !== null ? reject(failed) : resolve(got))));
    socket.resume();
  });
}

const statOf = (a: any): Stat => ({ dir: a.dir === true, file: a.file === true, link: a.link === true, size: Number(a.size) || 0, mtimeMs: Number(a.mtime) || 0 });

/// The drive's operations as still.fail Helper's requests, in one scope.
class HelperFs implements Fs {
  readonly helper = true;
  readonly #files: HelperFiles;
  readonly #scope: { roots: string[]; protect: string[] };

  constructor(files: HelperFiles, scope: { roots: string[]; protect: string[] }) {
    this.#files = files;
    this.#scope = scope;
  }

  #ask(op: string, fields: Record<string, unknown>): Promise<any> {
    return this.#files.request({ op, ...fields, ...this.#scope });
  }

  async list(dir: string, most: number): Promise<{ entries: Listed[]; more: boolean }> {
    const a = await this.#ask("files.list", { path: dir, most });
    const entries = (a.entries ?? []).map((e: any): Listed => ({ name: e.name, link: e.link === true, real: e.real ?? join(dir, e.name), stat: e.gone ? null : statOf(e) }));
    return { entries, more: a.more === true };
  }

  async names(dir: string): Promise<string[]> {
    return (await this.#ask("files.names", { path: dir })).names ?? [];
  }

  async stat(path: string): Promise<Stat> {
    return statOf(await this.#ask("files.stat", { path, follow: true }));
  }

  async lstat(path: string): Promise<Stat> {
    return statOf(await this.#ask("files.stat", { path, follow: false }));
  }

  async real(path: string): Promise<string> {
    return (await this.#ask("files.real", { path })).path;
  }

  async read(path: string, offset: number, length: number): Promise<{ bytes: Buffer; size: number; mtimeMs: number }> {
    const { head, socket, rest } = await this.#files.stream({ op: "files.read", path, offset, length, ...this.#scope });
    const want = Number(head.length) || 0;
    const bytes = Buffer.alloc(want);
    let at = 0;
    await drain(socket, rest, (chunk) => {
      at += chunk.copy(bytes, at);
    });
    if (at < want) throw ended();
    return { bytes, size: Number(head.size) || 0, mtimeMs: Number(head.mtime) || 0 };
  }

  async readAll(path: string): Promise<Buffer> {
    const s = await this.stat(path);
    return (await this.read(path, 0, s.size)).bytes;
  }

  async copyTo(path: string, to: string): Promise<void> {
    const out = await open(to, "wx");
    try {
      const s = await this.stat(path);
      const { head, socket, rest } = await this.#files.stream({ op: "files.read", path, offset: 0, length: s.size, ...this.#scope });
      const got = await drain(socket, rest, async (chunk) => {
        let done = 0;
        while (done < chunk.length) done += (await out.write(chunk, done, chunk.length - done)).bytesWritten;
      });
      if (got < (Number(head.length) || 0)) throw ended();
      await out.close();
    } catch (e) {
      await out.close().catch(() => {});
      await unlink(to).catch(() => {});
      throw e;
    }
  }

  async write(path: string, w: Write): Promise<Written> {
    const fields = { path, offset: w.offset, length: w.data.length, create: w.create, ...(w.truncate !== undefined ? { truncate: w.truncate } : {}), ...(w.sync ? { sync: true } : {}) };
    const { head, socket } = await this.#files.stream({ op: "files.write", ...fields, ...this.#scope });
    // Smaller than asked: nothing written (the helper sees the connection end before any byte).
    if (w.atLeast !== undefined && Number(head.size) < w.atLeast) {
      socket.destroy();
      return { size: Number(head.size), short: true };
    }
    const answer = lineOf(socket);
    socket.on("error", () => {});
    for (let at = 0; at < w.data.length; at += CHUNK) {
      if (socket.destroyed) break;
      if (!socket.write(w.data.subarray(at, at + CHUNK))) await new Promise((resolve) => (socket.once("drain", resolve), socket.once("close", resolve)));
    }
    const { head: done } = await answer;
    socket.destroy();
    return { size: Number(done.size) };
  }

  async rename(from: string, to: string): Promise<void> {
    await this.#ask("files.rename", { from, to });
  }

  async mkdir(path: string, recursive: boolean): Promise<void> {
    await this.#ask("files.mkdir", { path, recursive });
  }

  async remove(path: string): Promise<void> {
    await this.#ask("files.remove", { path });
  }

  async trash(path: string): Promise<string | null> {
    return (await this.#ask("files.trash", { path })).to ?? null;
  }

  async unlink(path: string): Promise<void> {
    await this.#ask("files.unlink", { path });
  }
}
