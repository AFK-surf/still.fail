// Tasks on other stations of the workspace (the Rust station's remote.rs). Workspace peers call named operations over an
// authenticated station transport (`stillfail/station/1`, the mesh layer's); shell tasks are one service on it, never an
// admin API proxy. Any station of the workspace may run them (the transport checks the roster), as its agents may open a
// chat here whose agent runs the same commands: shell execution as the station's OS user, not a sandbox. A source session's
// tasks share one working directory on the target (remote/sessions/<id>/work). The source asks for it to be removed
// when the session is archived or deleted; the target removes it itself after IDLE_MS unused.
//
// The records are the Rust's files, written the same way (remote/incoming/<id>/task.json, sessions/<id>/session.json,
// outgoing/<id>.json, used/<id>.json), so either station reads what the other wrote. What asks other machines (a
// task's state every 5 s, a closed session's stations every 60 s) and the hourly sweep are Effect schedules; nothing
// here polls local state.
import { createHash, randomBytes } from "node:crypto";
import {
  appendFileSync, closeSync, constants, existsSync, fstatSync, fsyncSync, ftruncateSync, linkSync, lstatSync, mkdirSync, openSync, readFileSync,
  readSync, readdirSync, readlinkSync, renameSync, rmSync, statSync, writeFileSync, writeSync,
} from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { relativeParts } from "../ops/paths.ts";
import { platform } from "../platform/index.ts";
import { isDeepStrictEqual } from "node:util";
import { Clock, Duration, Effect, Exit, FiberSet, Schedule, Scope } from "effect";
import { log } from "../ops/log.ts";
import { type Json, type Store } from "../store/store.ts";
import { type Jobs, jobJson, tail } from "./jobs.ts";
import { LINK, type Synced, actual, apply, listed, page, patchOf, planPart, putBlobs, readManifest, syncDir, writeManifest } from "./dirsync.ts";

/// The answer of a peer that refused a request (its `{"error": …}`): final, unlike a request that did not get through.
export class Refused extends Error {}
/// A request that did not get through (asked again later).
class Unreached extends Error {}

/// A request to another station of the workspace over the station transport: its result, a Refused when that station
/// answered with an error, any other error when it could not be asked (or the answer did not come). `workspace` is the
/// request's (null for `peers` and `describe`, which the transport answers or checks against its own). Station "" with
/// method `peers` is the transport's roster: {workspace, stations, current}.
export type PeerCall = (station: string, workspace: string | null, request: Json) => Promise<Json>;
/// Takes a message a session of another station sent here (the hub's from_peer): from which station, the request.
/// `workspace`: which of this station's workspaces the request was made in, when the transport knows it.
export type Inbox = (peer: string, request: Json, workspace?: string) => Promise<Json>;
/// Tells a session's agent something; a throw (or rejection) is "not told" (it is told again later).
export type RemoteNotify = (session: string, text: string) => void | Promise<void>;

export const CHUNK = 256 * 1024;
const MAX_FILE = 1024 * 1024 * 1024;
/// The changed files a patch is made of, at most (the rest is named, not in it).
const PATCH_MAX = 64 * 1024 * 1024;
/// A source session's directory unused this long is removed by the target, in case its source never says so.
export const IDLE_MS = 14 * 24 * 3600 * 1000;
/// A source keeps asking an unreachable target to remove a closed session's directory this long.
const CLOSE_FOR_MS = 30 * 24 * 3600 * 1000;
/// How often a source asks about a task it follows, a closed session's stations, and a target sweeps.
const WATCH_EVERY = "5 seconds";
const CLOSE_EVERY = "60 seconds";
const SWEEP_EVERY = "1 hour";

export type RemoteOptions = {
  /// The data directory: remote/ and mesh/cloud.json in it.
  data: string;
  store: Store;
  jobs: Jobs;
  notify: RemoteNotify;
  /// The clock its schedules run on (a TestClock in tests).
  clock?: Clock.Clock;
  /// How long a request made before the mesh is up waits for it (MESH_WAIT_MS; tests shorten it).
  meshWaitMs?: number;
};

/// A request asked before the transport is attached (a chat taken up as the station starts, its subscription borrowed
/// from another station) waits for it this long: the mesh is up within a second, or ~15 s when it waits for a relay
/// (mesh/mesh.ts), before it is attached.
export const MESH_WAIT_MS = 30_000;

const text = (v: Json, key: string): string => (v !== null && typeof v === "object" && typeof v[key] === "string" ? v[key] : "");
const field = (v: Json, key: string): Json => (v !== null && typeof v === "object" && !Array.isArray(v) && key in v ? v[key] : null);
const bytes = (s: string) => Buffer.byteLength(s);
/// serde_json's as_u64.
const asU64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

/// The name a source session, task or record goes by: sha256 of its parts as compact JSON (as serde writes them).
export function hash(v: Json): string {
  return createHash("sha256").update(JSON.stringify(v)).digest("hex");
}

export function readJson(path: string): Json {
  return JSON.parse(readFileSync(path, "utf8"));
}

/// Path::with_extension: the file name's extension replaced (or added).
function withExtension(path: string, ext: string): string {
  const name = basename(path);
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  return join(dirname(path), `${stem}.${ext}`);
}

/// Written whole or not at all: a private temporary file, synced, renamed over.
export function writeJson(path: string, value: Json): void {
  const temp = withExtension(path, `${randomBytes(8).toString("hex")}.tmp`);
  const fd = openSync(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
  try {
    writeSync(fd, Buffer.from(JSON.stringify(value)));
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  renameSync(temp, path);
}

const isLink = (path: string): boolean => {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
};

/// Relative paths only; transfers must not follow links planted by a task. Task commands themselves are trusted shell
/// execution, so separate working directories are organizational isolation, not an OS security boundary.
export function filePath(root: string, relative: string, create: boolean): string {
  if (lstatSync(root).isSymbolicLink()) throw new Error("transfer root is a symbolic link");
  // Path::components: a leading / is the root (and on Windows a drive, a UNC share or a stream: relativeParts), a
  // leading . is the current directory, a later . is no component.
  const given = relativeParts(relative);
  const parts: string[] = [];
  let bad = given === null;
  (given ?? []).forEach((part, i) => {
    if (part === "") return;
    if (part === ".") {
      if (i === 0) bad = true;
      return;
    }
    parts.push(part);
  });
  if (bad || parts.length === 0) throw new Error("file path must be relative, without . or ..");
  let out = root;
  for (const part of parts) {
    out = join(out, part);
    if (isLink(out)) throw new Error("file path contains a symbolic link");
  }
  if (create) mkdirSync(dirname(out), { recursive: true });
  return out;
}

/// STANDARD base64 as the Rust decodes it: padded, nothing else in it.
function fromBase64(data: string): Buffer {
  if (data.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(data)) throw new Error("Invalid input length or symbol");
  return Buffer.from(data, "base64");
}

/// The OS and architecture as Rust's std::env::consts name them.
const OS = platform.os;
const ARCH = ({ arm64: "aarch64", x64: "x86_64", ia32: "x86", arm: "arm" } as Record<string, string>)[process.arch] ?? process.arch;

export class Remote {
  readonly root: string;
  readonly store: Store;
  private data: string;
  private jobs: Jobs;
  private notify: RemoteNotify;
  private call: PeerCall | null = null;
  /// Settled once the transport is attached; requests made before wait on it (MESH_WAIT_MS).
  private attached: Promise<void>;
  private markAttached!: () => void;
  private meshWaitMs: number;
  private inbox: Inbox | null = null;
  private shares: Inbox | null = null;
  private xshare: { inside: Inbox; outside: Inbox } | null = null;
  /// Target-side requests, the sweep and withdrawals, one at a time.
  private serial: Promise<unknown> = Promise.resolve();
  /// The records followed now (outgoing tasks, closing sessions).
  private watching = new Set<string>();
  private scope: Scope.Closeable;
  private run: (effect: Effect.Effect<void>) => Promise<void>;

  constructor(options: RemoteOptions) {
    this.data = options.data;
    this.store = options.store;
    this.jobs = options.jobs;
    this.notify = options.notify;
    this.meshWaitMs = options.meshWaitMs ?? MESH_WAIT_MS;
    this.attached = new Promise((resolve) => (this.markAttached = resolve));
    this.root = join(options.data, "remote");
    for (const name of ["incoming", "outgoing", "sessions", "used", "prepared"]) mkdirSync(join(this.root, name), { recursive: true });
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
  }

  /// The transport is there: follow the tasks started from here and the sessions closing, sweep now and hourly.
  attach(call: PeerCall): void {
    this.call = call;
    this.markAttached();
    for (const name of this.list(join(this.root, "outgoing")).filter((n) => n.endsWith(".json"))) this.watch(join(this.root, "outgoing", name));
    for (const name of this.list(join(this.root, "used")).filter((n) => n.endsWith(".json"))) {
      const path = join(this.root, "used", name);
      try {
        if (field(readJson(path), "closing") === true) this.closer(path);
      } catch {}
    }
    void this.run(
      Effect.promise(() => this.sweep(this.store.now())).pipe(Effect.repeat(Schedule.spaced(SWEEP_EVERY)), Effect.asVoid),
    ).catch(() => undefined);
  }

  /// Its schedules end (the station stops).
  async close(): Promise<void> {
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }

  private list(dir: string): string[] {
    try {
      return readdirSync(dir);
    } catch {
      return [];
    }
  }

  private serially<T>(f: () => Promise<T>): Promise<T> {
    const result = this.serial.then(f, f);
    this.serial = result.catch(() => undefined);
    return result;
  }

  room(workspace: string, peer: string, session: string): string {
    return join(this.root, "sessions", hash([workspace, peer, session]));
  }

  /// Makes a source session's shared directory and notes when it was last used (at most once a minute).
  private seen(workspace: string, peer: string, session: string): string {
    const room = this.room(workspace, peer, session);
    mkdirSync(join(room, "work"), { recursive: true });
    const record = join(room, "session.json");
    const now = this.store.now();
    let fresh = false;
    try {
      fresh = now - (asI64(field(readJson(record), "seen")) ?? 0) < 60_000;
    } catch {}
    if (!fresh) writeJson(record, { workspace, station: peer, session, seen: now });
    return join(room, "work");
  }

  /// The directory in a session's that mirrors the source's `dir` (its last name; with a part of its hash when another
  /// directory of the source's has that name there already).
  private mirrorName(workspace: string, peer: string, session: string, dir: string): string {
    const last = dir.split(/[\\/]/).filter((p) => p !== "").at(-1) ?? "";
    let name = last.replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(0, 100);
    if (name === "" || name === "." || name === "..") name = "dir";
    const claimed = new Map<string, string>();
    for (const task of this.tasksOf(workspace, peer, session)) {
      try {
        const meta = readJson(join(task, "task.json"));
        if (typeof meta.mirror === "string") claimed.set(meta.mirror, text(field(meta, "spec"), "dir"));
      } catch {}
    }
    const mirrors = join(this.room(workspace, peer, session), "mirrors");
    for (const file of this.list(mirrors)) {
      const m = readManifest(join(mirrors, file));
      if (m !== null) claimed.set(m.name, m.dir);
    }
    const owner = claimed.get(name);
    return owner === undefined || owner === dir ? name : `${name}-${hash(dir).slice(0, 8)}`;
  }

  /// Task directories (incoming/<id>) of a source session.
  private tasksOf(workspace: string, peer: string, session: string): string[] {
    const incoming = join(this.root, "incoming");
    return this.list(incoming)
      .map((name) => join(incoming, name))
      .filter((dir) => {
        try {
          const m = readJson(join(dir, "task.json"));
          return text(m, "workspace") === workspace && text(m, "station") === peer && text(m, "session") === session;
        } catch {
          return false;
        }
      });
  }

  private jobOf(task: string): string {
    return `remote_${basename(task)}`;
  }

  private running(task: string): boolean {
    return this.store.getJob(this.jobOf(task))?.state === "running";
  }

  /// Stops a source session's tasks and removes their records and its shared directory. Callers hold `serial`.
  private async closeHere(workspace: string, peer: string, session: string): Promise<void> {
    for (const task of this.tasksOf(workspace, peer, session)) {
      if (this.running(task)) await this.jobs.stop(this.jobOf(task));
      rmSync(task, { recursive: true });
    }
    const room = this.room(workspace, peer, session);
    if (existsSync(room)) {
      rmSync(room, { recursive: true });
      log.info("remote", "remote session directory removed", { workspace, station: peer, session });
    }
  }

  /// The target's own cleanup: a source session's directory unused for IDLE_MS, with nothing running, goes; so do task
  /// directories from before shared session directories.
  sweep(now: number): Promise<void> {
    return this.serially(async () => {
      const sessions = join(this.root, "sessions");
      for (const name of this.list(sessions)) {
        let meta: Json;
        try {
          meta = readJson(join(sessions, name, "session.json"));
        } catch {
          continue;
        }
        if (now - (asI64(field(meta, "seen")) ?? now) < IDLE_MS) continue;
        const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
        if (this.tasksOf(workspace, peer, session).some((t) => this.running(t))) continue;
        try {
          await this.closeHere(workspace, peer, session);
        } catch (error) {
          log.warn("remote", "idle remote session directory not removed", { error: (error as Error).message });
        }
      }
      const incoming = join(this.root, "incoming");
      for (const name of this.list(incoming)) {
        const dir = join(incoming, name);
        const record = join(dir, "task.json");
        let meta: Json;
        try {
          meta = readJson(record);
        } catch {
          continue;
        }
        let modified = now;
        try {
          modified = Math.floor(statSync(record).mtimeMs);
        } catch {}
        if (field(meta, "layout") === "session" || now - modified < IDLE_MS || this.running(dir)) continue;
        rmSync(dir, { recursive: true, force: true });
      }
    });
  }

  usedPath(session: string): string {
    return join(this.root, "used", `${hash(session)}.json`);
  }

  /// The source remembers which stations a session ran tasks on, to ask them to clean up when it closes.
  recordUse(workspace: string, session: string, station: string): void {
    const path = this.usedPath(session);
    let v: Json;
    try {
      v = readJson(path);
    } catch {
      v = { session, workspace, stations: [] };
    }
    const known = Array.isArray(v.stations) && v.stations.some((s: Json) => s === station);
    if (known && v.closing !== true) return;
    if (!known) {
      if (!Array.isArray(v.stations)) throw new Error("bad record");
      v.stations.push(station);
    }
    // Used again after closing (shown again): close later from the start.
    v.closing = false;
    v.closed = [];
    v.workspace = workspace;
    writeJson(path, v);
  }

  /// A session was archived or deleted: its tasks on other stations stop and their directories are removed. Asked until
  /// each station has answered (CLOSE_FOR_MS at most), across restarts.
  closeSession(session: string): void {
    const path = this.usedPath(session);
    let v: Json;
    try {
      v = readJson(path);
    } catch {
      return;
    }
    v.closing = true;
    v.since = this.store.now();
    try {
      writeJson(path, v);
    } catch {
      return;
    }
    // Their directories are going away: stop following this session's tasks.
    const outgoing = join(this.root, "outgoing");
    for (const name of this.list(outgoing)) {
      const file = join(outgoing, name);
      try {
        const entry = readJson(file);
        if (text(entry, "session") === session && entry.delivered !== true) {
          entry.delivered = true;
          writeJson(file, entry);
        }
      } catch {}
    }
    for (const name of this.list(join(this.root, "prepared"))) {
      const file = join(this.root, "prepared", name);
      try {
        if (text(readJson(file), "session") === session) rmSync(file, { force: true });
      } catch {}
    }
    this.closer(path);
  }

  /// Asks each station a closing session used to remove its directory, every minute until all have answered.
  private closer(path: string): void {
    if (this.watching.has(path)) return;
    this.watching.add(path);
    const round = Effect.promise(async (): Promise<boolean> => {
      let v: Json;
      try {
        v = readJson(path);
      } catch {
        return true;
      }
      if (v.closing !== true) return true;
      const closed = Array.isArray(v.closed) ? v.closed : [];
      const pending: string[] = (Array.isArray(v.stations) ? v.stations : []).filter((s: Json) => !closed.includes(s) && typeof s === "string");
      if (pending.length === 0 || this.store.now() - (asI64(v.since) ?? 0) > CLOSE_FOR_MS) {
        try {
          if (readJson(path).closing === true) rmSync(path, { force: true });
        } catch {}
        return true;
      }
      for (const station of pending) {
        const request = { method: "session.close", workspace: field(v, "workspace"), session: field(v, "session") };
        // An answer, or a refusal (a station from before session directories, or one that no longer takes tasks from
        // here), is final; no connection is asked again.
        let done: boolean;
        try {
          await this.ask(station, request);
          done = true;
        } catch (error) {
          done = error instanceof Refused;
        }
        if (done) {
          try {
            const now = readJson(path);
            if (now.closing === true && Array.isArray(now.closed)) {
              now.closed.push(station);
              writeJson(path, now);
            }
          } catch {}
        }
      }
      return false;
    });
    void this.run(
      round.pipe(
        Effect.repeat({ schedule: Schedule.spaced(CLOSE_EVERY), until: (over) => over }),
        Effect.ensuring(Effect.sync(() => this.watching.delete(path))),
        Effect.asVoid,
      ),
    ).catch(() => undefined);
  }

  /// Where messages from other stations' sessions go (session.message): any station of the workspace may send them,
  /// trusted for tasks or not.
  setInbox(inbox: Inbox): void {
    this.inbox = inbox;
  }

  /// Where requests about what stations share go (share.*, share/index.ts): any station of the workspace may ask;
  /// what each share allows is checked there.
  setShares(shares: Inbox): void {
    this.shares = shares;
  }

  /// Where requests about chats shared across workspaces go (xshare.*, xshare/index.ts): `inside` those of this
  /// workspace's stations, `outside` every request of a station that is not of it (the transport lets those through
  /// only while there is one).
  setOutside(handlers: { inside: Inbox; outside: Inbox }): void {
    this.xshare = handlers;
  }

  /// Whether stations of other workspaces are heard at all.
  hearsOutside(): boolean {
    return this.xshare !== null;
  }

  /// A request of a station that is not of this workspace (the transport checked it names this workspace).
  async handleOutside(peer: string, request: Json, workspace?: string): Promise<Json> {
    const xshare = this.xshare;
    if (!xshare) throw new Error("station is starting");
    return xshare.outside(peer, request, workspace);
  }

  /// A request to another station of the workspace (session_send's messages, and this module's own).
  async ask(station: string, request: Json): Promise<Json> {
    if (!this.call) {
      const attached = this.attached;
      await this.run(Effect.race(Effect.promise(() => attached), Effect.sleep(Duration.millis(this.meshWaitMs)))).catch(() => undefined);
    }
    const call = this.call;
    if (!call) throw new Error("station mesh is not ready");
    const workspace = typeof request?.workspace === "string" ? request.workspace : null;
    return call(station, workspace, request);
  }

  /// Called only after the transport authenticates the source station and checks current workspace membership.
  async handle(workspace: string, peer: string, request: Json): Promise<Json> {
    const method = text(request, "method");
    if (method === "describe") {
      return { protocol: 1, os: OS, arch: ARCH, tasks: true, sessions: true, messages: true, reads: true, files: true, chats: true, sync: 1, fileChunkBytes: CHUNK, maxFileBytes: MAX_FILE };
    }
    if (method.startsWith("xshare.")) {
      const xshare = this.xshare;
      if (!xshare) throw new Error("station is starting");
      return xshare.inside(peer, request, workspace);
    }
    if (method.startsWith("share.")) {
      const shares = this.shares;
      if (!shares) throw new Error("station is starting");
      return shares(peer, request, workspace);
    }
    // A message (and the files it takes along), a chat read (and its attachments), a chat opened or how one went, not
    // execution: workspace membership (checked by the transport) is enough, as it is for the chats' pages.
    if (["session.message", "session.read", "session.file", "session.put", "session.create", "session.notice"].includes(method)) {
      const inbox = this.inbox;
      if (!inbox) throw new Error("station is starting");
      return inbox(peer, request, workspace);
    }
    return this.serially(() => this.task(workspace, peer, method, request));
  }

  private async task(workspace: string, peer: string, method: string, request: Json): Promise<Json> {
    const session = text(request, "session");
    if (method === "task.list") {
      if (session === "" || bytes(session) > 256) throw new Error("session is required");
      const tasks: Json[] = [];
      const incoming = join(this.root, "incoming");
      for (const name of readdirSync(incoming)) {
        let meta: Json;
        try {
          meta = readJson(join(incoming, name, "task.json"));
        } catch {
          continue;
        }
        if (text(meta, "workspace") !== workspace || text(meta, "station") !== peer || text(meta, "session") !== session) continue;
        const job = this.store.getJob(`remote_${name}`);
        tasks.push({ key: field(meta, "key"), spec: field(meta, "spec"), job: job ? jobJson(job) : null });
      }
      return { tasks };
    }
    if (method === "session.close") {
      if (session === "" || bytes(session) > 256) throw new Error("session is required");
      await this.closeHere(workspace, peer, session);
      return { closed: true };
    }
    const key = text(request, "key");
    if (session === "" || bytes(session) > 256 || key === "" || bytes(key) > 128) {
      throw new Error("session and task key are required (at most 256 / 128 bytes)");
    }
    const id = hash([workspace, peer, session, key]);
    const dir = join(this.root, "incoming", id);
    const record = join(dir, "task.json");
    const jobId = `remote_${id}`;
    const owner = `remote:${workspace}:${peer}:${session}`;
    if (method === "task.prepare") {
      const spec = field(request, "spec");
      if (text(spec, "command").trim() === "") throw new Error("command is required");
      const from = field(spec, "dir");
      if (from !== null && (typeof from !== "string" || from === "" || bytes(from) > 4096)) throw new Error("dir must be a path");
      let meta: Json;
      if (existsSync(record)) {
        meta = readJson(record);
        if (!isDeepStrictEqual(field(meta, "spec"), spec)) {
          throw new Error("task key already used with different inputs; choose a new key for new work");
        }
      } else {
        mkdirSync(dir, { recursive: true });
        meta = { spec, workspace, station: peer, session, key, layout: "session" };
        if (typeof from === "string") meta.mirror = this.mirrorName(workspace, peer, session, from);
        writeJson(record, meta);
      }
      this.seen(workspace, peer, session);
      return typeof meta.mirror === "string" ? { key, prepared: true, dir: meta.mirror } : { key, prepared: true };
    }
    let meta: Json;
    try {
      meta = readJson(record);
    } catch {
      throw new Error("unknown task");
    }
    const job = this.store.getJob(jobId);
    // Tasks prepared before shared session directories keep their own.
    const work =
      field(meta, "layout") === "session"
        ? method === "task.start" || method === "file.put" || method === "sync.begin"
          ? this.seen(workspace, peer, session)
          : join(this.room(workspace, peer, session), "work")
        : join(dir, "work");
    // A task with a directory runs in its mirror, a directory of the session's (docs/station-peers.md "Directories").
    const mirror = typeof meta.mirror === "string" ? meta.mirror : null;
    const room = this.room(workspace, peer, session);
    const manifestPath = mirror === null ? "" : join(room, "mirrors", `${mirror}.json`);
    const syncing = mirror === null ? "" : join(room, "sync", mirror);
    if (method.startsWith("sync.") && mirror === null) throw new Error("this task has no directory to sync");
    /// Another task of the session running in the same mirror (one at a time there).
    const busy = () =>
      this.tasksOf(workspace, peer, session).find((t) => t !== dir && this.running(t) && field(readJson(join(t, "task.json")), "mirror") === mirror);
    const refuseBusy = () => {
      const other = busy();
      if (other) throw new Error(`task ${text(readJson(join(other, "task.json")), "key")} is running in ${mirror} on this station; wait for it or stop it`);
    };
    /// The sync under way: its state, when `id` is its.
    const ongoing = (): Json => {
      let state: Json = null;
      try {
        state = readJson(join(syncing, "state.json"));
      } catch {}
      if (state === null || text(state, "id") !== text(request, "id") || text(state, "key") !== key) throw new Error("this sync is over or another one began; start again");
      return state;
    };
    switch (method) {
      case "task.start": {
        const uploads = field(meta, "uploads");
        if (uploads !== null && typeof uploads === "object" && !Array.isArray(uploads) && Object.values(uploads).some((v) => v !== true)) {
          throw new Error("input upload is incomplete; finish it before starting");
        }
        let cwd = work;
        if (mirror !== null && !job) {
          if (meta.synced !== true) throw new Error("this task's directory has not been synced; start it from a station that syncs directories");
          refuseBusy();
        }
        if (mirror !== null) cwd = filePath(work, mirror, false);
        const spec = field(meta, "spec");
        const started = this.jobs.startId(owner, text(spec, "name"), text(spec, "command"), cwd, null, false, jobId);
        return { key, job: jobJson(started) };
      }
      case "sync.begin": {
        if (job) return { key, started: true };
        refuseBusy();
        rmSync(syncing, { recursive: true, force: true });
        mkdirSync(syncing, { recursive: true });
        mkdirSync(join(room, "mirrors"), { recursive: true });
        const manifest = readManifest(manifestPath);
        const files = manifest === null ? {} : await actual(join(work, mirror!), manifest.files);
        const id = randomBytes(12).toString("hex");
        writeJson(join(syncing, "actual.json"), files);
        writeJson(join(syncing, "state.json"), { id, key, version: manifest?.version ?? 0 });
        return { key, id, dir: mirror, version: manifest?.version ?? 0 };
      }
      case "sync.manifest": {
        ongoing();
        const after = asU64(field(request, "after")) ?? 0;
        return page(listed(readJson(join(syncing, "actual.json"))), after);
      }
      case "sync.put": {
        ongoing();
        return { pieces: await putBlobs(join(syncing, "blobs"), field(request, "blobs"), fromBase64(text(request, "data"))) };
      }
      case "sync.commit": {
        const state = ongoing();
        const part = planPart(request);
        appendFileSync(join(syncing, "plan.jsonl"), `${JSON.stringify(part)}\n`);
        if (field(request, "final") !== true) return { key, planned: true };
        refuseBusy();
        const manifest = readManifest(manifestPath);
        const version = manifest?.version ?? 0;
        if (version !== field(state, "version")) throw new Error("the mirror changed while this sync went on; start again");
        const plan = { set: [] as [string, string, string][], remove: [] as string[] };
        for (const line of readFileSync(join(syncing, "plan.jsonl"), "utf8").split("\n")) {
          if (line === "") continue;
          const p = JSON.parse(line);
          plan.set.push(...p.set);
          plan.remove.push(...p.remove);
        }
        const files = readJson(join(syncing, "actual.json"));
        let done: { written: number; removed: number };
        try {
          done = apply(work, mirror!, join(syncing, "scratch"), join(syncing, "blobs"), files, plan);
        } finally {
          writeManifest(manifestPath, { dir: text(field(meta, "spec"), "dir"), name: mirror!, version: version + 1, files });
        }
        meta.synced = true;
        writeJson(record, meta);
        rmSync(syncing, { recursive: true, force: true });
        return { key, ...done, version: version + 1 };
      }
      case "sync.changes": {
        if (!job || job.state === "running") throw new Error("the task has not finished");
        const manifest = readManifest(manifestPath);
        const base = filePath(work, mirror!, false);
        const now = manifest === null ? {} : await actual(base, manifest.files);
        const changes: Json[] = [];
        let more = false;
        for (const [path, was] of Object.entries(manifest?.files ?? {}).sort(([a], [b]) => (a < b ? -1 : 1))) {
          const is = now[path];
          if (is && is[0] === was[0] && is[1] === was[1]) continue;
          if (changes.length === 1000) {
            more = true;
            break;
          }
          const change: Json = { path, old: was[0], mode: was[1], hash: is?.[0] ?? null, newMode: is?.[1] ?? null };
          if (is?.[1] === LINK) change.link = readlinkSync(join(base, ...path.split("/")));
          changes.push(change);
        }
        return { key, base: mirror, changes, more };
      }
      case "task.files": {
        if (job?.state === "running") throw new Error("wait for the task to finish before downloading artifacts");
        const paths = field(request, "paths");
        if (!Array.isArray(paths) || paths.length > 100 || !paths.every((p) => typeof p === "string")) throw new Error("paths are required (at most 100)");
        const cwd = mirror === null ? work : filePath(work, mirror, false);
        const files: [string, number | null][] = [];
        const visit = (rel: string) => {
          if (files.length >= 1000) throw new Error("more than 1000 files to bring back");
          let st;
          try {
            st = lstatSync(filePath(cwd, rel, false));
          } catch {
            files.push([rel, null]);
            return;
          }
          if (st.isFile()) files.push([rel, st.size]);
          else if (st.isDirectory()) for (const name of readdirSync(join(cwd, ...rel.split("/"))).sort()) visit(`${rel.replace(/\/+$/, "")}/${name}`);
        };
        for (const p of paths) visit(p);
        return { key, base: mirror ?? "", files };
      }
      case "task.get":
      case "task.log": {
        const lines = Math.min(Math.max(asU64(field(request, "lines")) ?? 50, 1), 1000);
        return { key, job: job ? jobJson(job) : null, log: job ? tail(job.log, lines) : null, notices: this.store.jobNotices(jobId, 20) };
      }
      case "task.stop": {
        if (!job) throw new Error("task has not started");
        return { key, job: jobJson(await this.jobs.stop(job.id)) };
      }
      case "file.put": {
        if (job) throw new Error("inputs are immutable after a task starts");
        const offset = asU64(field(request, "offset"));
        if (offset === null) throw new Error("offset is required");
        const data = fromBase64(text(request, "data"));
        if (data.length > CHUNK || offset + data.length > MAX_FILE) throw new Error("file limit exceeded");
        const name = text(request, "path");
        const path = filePath(work, name, true);
        if (meta.uploads === null || typeof meta.uploads !== "object" || Array.isArray(meta.uploads)) meta.uploads = {};
        meta.uploads[name] = false;
        writeJson(record, meta);
        const fd = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o666);
        try {
          const stat = fstatSync(fd);
          if (!stat.isFile()) throw new Error("only regular files can be transferred");
          if (offset > stat.size) throw new Error("file offset leaves a gap");
          for (let at = 0; at < data.length; ) at += writeSync(fd, data, at, data.length - at, offset + at);
          if (field(request, "final") === true) {
            ftruncateSync(fd, offset + data.length);
            fsyncSync(fd);
          }
        } finally {
          closeSync(fd);
        }
        if (field(request, "final") === true) {
          meta.uploads[name] = true;
          writeJson(record, meta);
        }
        return { bytes: data.length };
      }
      case "file.get": {
        if (job?.state === "running") throw new Error("wait for the task to finish before downloading artifacts");
        const path = filePath(work, text(request, "path"), false);
        const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
        try {
          const stat = fstatSync(fd);
          if (!stat.isFile()) throw new Error("only regular files can be transferred");
          const size = stat.size;
          if (size > MAX_FILE) throw new Error("file limit exceeded");
          const offset = asU64(field(request, "offset")) ?? 0;
          if (offset > size) throw new Error("offset past end");
          const buffer = Buffer.alloc(CHUNK);
          const n = readSync(fd, buffer, 0, CHUNK, offset);
          return { data: buffer.subarray(0, n).toString("base64"), size, eof: offset + n >= size };
        } finally {
          closeSync(fd);
        }
      }
      default:
        throw new Error(`unsupported peer method: ${method}`);
    }
  }

  /// Peers removed from a workspace (or the workspace left) have their tasks stopped, without touching any local jobs.
  /// `rosters`: each workspace the station is in now, with its other stations.
  revoke(rosters: { workspace: string; peers: string[] }[], membershipCurrent: boolean): Promise<void> {
    return this.serially(async () => {
      const incoming = join(this.root, "incoming");
      for (const name of this.list(incoming)) {
        let meta: Json;
        try {
          meta = readJson(join(incoming, name, "task.json"));
        } catch {
          continue;
        }
        const peer = text(meta, "station");
        if (!membershipCurrent || rosters.some((r) => text(meta, "workspace") === r.workspace && r.peers.includes(peer))) continue;
        const id = `remote_${name}`;
        if (this.store.getJob(id)?.state === "running") {
          try {
            await this.jobs.stop(id);
          } catch {}
        }
      }
    });
  }

  /// The workspace a session's tasks go in (mesh/cloud.json): its chat's, the home one for those from before; while the
  /// station is still in it (docs/multi-workspace.md).
  private workspace(own: string | null): string {
    const state = readJson(join(this.data, "mesh", "cloud.json"));
    if (field(state, "removed_at") !== null) throw new Error("station was removed from workspace");
    const home = text(state, "workspace");
    if (home === "") throw new Error("station has no workspace");
    const ws = own ?? home;
    const joined = field(state, "joined");
    if (ws !== home && !(Array.isArray(joined) && joined.some((j: Json) => text(j, "workspace") === ws))) throw new Error("station is no longer in this chat's workspace");
    return ws;
  }

  outgoing(workspace: string, session: string, station: string, key: string): string {
    return join(this.root, "outgoing", `${hash([workspace, session, station, key])}.json`);
  }

  /// Follows a task started from here: asks its station every 5 s until it is over, telling its session what it said on
  /// the way and how it ended. Across restarts (the record is a file).
  private watch(path: string): void {
    if (this.watching.has(path)) return;
    this.watching.add(path);
    const round = Effect.promise(async (): Promise<boolean> => {
      let entry: Json;
      try {
        entry = readJson(path);
      } catch {
        return true;
      }
      if (entry.delivered === true) return true;
      const request = { method: "task.get", workspace: field(entry, "workspace"), session: field(entry, "session"), key: field(entry, "key") };
      let result: Json;
      try {
        result = await this.ask(text(entry, "station"), request);
      } catch {
        return false;
      }
      const state = text(field(result, "job"), "state");
      const notices = field(result, "notices");
      const finished = state !== "" && state !== "running";
      // What the task was to bring back, and what it changed of its directory, comes before its end is told (once).
      if (finished && entry.brought === undefined && (Array.isArray(entry.back) || typeof entry.dir === "string")) {
        try {
          entry.brought = await this.bringBack(entry);
        } catch (error) {
          if (error instanceof Unreached) return false;
          entry.brought = { error: (error as Error).message };
        }
        try {
          writeJson(path, entry);
        } catch {}
      }
      if (finished && entry.brought !== undefined && result !== null && typeof result === "object") result.back = entry.brought;
      if (finished || (Array.isArray(notices) && notices.length > 0 && !isDeepStrictEqual(field(entry, "notices"), notices))) {
        const message = `Remote task ${text(entry, "key")} on ${text(entry, "station")}: ${JSON.stringify(result)}`;
        let told = true;
        try {
          await this.notify(text(entry, "session"), message);
        } catch {
          told = false;
        }
        if (told) {
          entry.notices = notices;
          entry.delivered = finished;
          try {
            writeJson(path, entry);
          } catch {}
        }
      }
      return finished && entry.delivered === true;
    });
    void this.run(
      round.pipe(
        Effect.repeat({ schedule: Schedule.spaced(WATCH_EVERY), until: (over) => over }),
        Effect.ensuring(Effect.sync(() => this.watching.delete(path))),
        Effect.asVoid,
      ),
    ).catch(() => undefined);
  }

  /// A file of a task's station (`request`'s path) to `path` here, in chunks; its size. An existing file is replaced
  /// only when `replace`.
  private async download(ask: (request: Json) => Promise<Json>, request: Json, path: string, replace: boolean): Promise<number> {
    if (!replace && existsSync(path)) throw new Error("local output already exists; choose another path");
    const temp = withExtension(path, `${randomBytes(8).toString("hex")}.part`);
    const fd = openSync(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o666);
    try {
      let size: number;
      try {
        let offset = 0;
        for (;;) {
          const answer = await ask({ ...request, method: "file.get", offset });
          const data = fromBase64(text(answer, "data"));
          if (data.length > CHUNK || offset + data.length > MAX_FILE) throw new Error("invalid file response");
          for (let at = 0; at < data.length; ) at += writeSync(fd, data, at, data.length - at);
          offset += data.length;
          if (field(answer, "eof") === true) {
            fsyncSync(fd);
            size = offset;
            break;
          }
          if (data.length === 0) throw new Error("file transfer made no progress");
        }
      } finally {
        closeSync(fd);
      }
      if (replace) renameSync(temp, path);
      else linkSync(temp, path);
      return size;
    } finally {
      rmSync(temp, { force: true });
    }
  }

  /// A file of a task's station in memory; null when it is bigger than `limit`.
  private async fetchFile(ask: (request: Json) => Promise<Json>, path: string, limit: number): Promise<Buffer | null> {
    const parts: Buffer[] = [];
    for (let offset = 0; ; ) {
      const answer = await ask({ method: "file.get", path, offset });
      if ((asU64(field(answer, "size")) ?? 0) > limit) return null;
      const data = fromBase64(text(answer, "data"));
      parts.push(data);
      offset += data.length;
      if (field(answer, "eof") === true) return Buffer.concat(parts);
      if (data.length === 0) throw new Error("file transfer made no progress");
    }
  }

  /// After a task ends: what it was to bring back (`back`, into station-back/<key> of its session's workspace), and,
  /// for a task with a directory, the synced files its command changed there, as a patch for the agent to apply or
  /// not (nothing here is overwritten). An Unreached when its station could not be asked (asked again next round).
  private async bringBack(entry: Json): Promise<Json> {
    const station = text(entry, "station");
    const key = text(entry, "key");
    const base = { workspace: field(entry, "workspace"), session: field(entry, "session"), key };
    const ask = (request: Json) =>
      this.ask(station, { ...base, ...request }).catch((error) => {
        throw error instanceof Refused ? error : new Unreached((error as Error).message);
      });
    const row = this.store.getSession(text(entry, "session"));
    if (!row) return { error: "the session is gone" };
    const dest = join(row.workspace, "station-back", key.replace(/[^\w.-]/g, "_").replace(/^\./, "_"));
    const out: Json = {};
    const back: string[] = Array.isArray(entry.back) ? entry.back : [];
    if (back.length > 0) {
      let files: [string, number | null][];
      let prefix = "";
      try {
        const found = await ask({ method: "task.files", paths: back });
        files = found.files;
        prefix = text(found, "base") === "" ? "" : `${text(found, "base")}/`;
      } catch (error) {
        // A station from before has no task.files: the paths are files.
        if (!(error instanceof Refused && /unsupported peer method/.test(error.message))) throw error;
        files = back.map((p) => [p, 0]);
      }
      mkdirSync(dest, { recursive: true });
      const got: string[] = [];
      const missing: string[] = [];
      for (const [p, size] of files) {
        if (size === null) {
          missing.push(`${p}: not there`);
          continue;
        }
        try {
          await this.download(ask, { path: prefix + p }, filePath(dest, p, true), true);
          got.push(p);
        } catch (error) {
          if (error instanceof Unreached) throw error;
          missing.push(`${p}: ${(error as Error).message}`);
        }
      }
      out.files = { dir: dest, count: got.length, files: got.slice(0, 50), missing };
    }
    if (typeof entry.dir === "string") {
      let found: Json;
      try {
        found = await ask({ method: "sync.changes" });
      } catch (error) {
        if (error instanceof Unreached) throw error;
        out.changed = { error: (error as Error).message };
        return out;
      }
      const changes: Json[] = Array.isArray(found?.changes) ? found.changes : [];
      if (changes.length > 0) {
        const items = [];
        const missing: string[] = [];
        let total = 0;
        for (const c of changes) {
          let after: Buffer | null = null;
          if (c.newMode === LINK) after = Buffer.from(String(c.link ?? ""));
          else if (c.hash !== null) {
            try {
              after = await this.fetchFile(ask, `${text(found, "base")}/${c.path}`, PATCH_MAX - total);
            } catch (error) {
              if (error instanceof Unreached) throw error;
            }
            if (after === null) {
              missing.push(c.path);
              continue;
            }
            total += after.length;
          }
          items.push({ path: String(c.path), old: String(c.old), mode: String(c.mode), after, afterMode: c.newMode ?? null });
        }
        const made = await patchOf(entry.dir, text(entry, "prefix"), join(this.root, `patch-${randomBytes(6).toString("hex")}`), items);
        const changed: Json = {
          count: changes.length,
          more: found.more === true,
          files: changes.slice(0, 50).map((c) => c.path),
          note: "the command changed these synced files on that station; nothing here was changed",
        };
        if (made !== null && made.patch !== "") {
          mkdirSync(dest, { recursive: true });
          const file = join(dest, "changes.patch");
          writeFileSync(file, made.patch);
          changed.patch = file;
          changed.apply = `review it, then git apply it in ${entry.dir} if wanted`;
        }
        const left = [...missing, ...(made?.missing ?? [])];
        if (left.length > 0) changed.notInPatch = left.slice(0, 50);
        out.changed = changed;
      }
    }
    return out;
  }

  /// What the station_* tools do, as `session`: among the stations of its workspace.
  async tool(tool: string, session: string, args: Json): Promise<Json> {
    const row = this.store.getSession(session);
    if (!row) throw new Error("unknown session");
    const station = text(args, "station");
    if (tool === "station_list") return this.ask(station, { method: station === "" ? "peers" : "describe", workspace: this.workspace(row.ws ?? null) });
    const key = text(args, "key");
    const listing = tool === "station_task" && field(args, "action") === "list";
    if (station === "" || (key === "" && !listing)) throw new Error("station and key are required (list needs only station)");
    const workspace = this.workspace(row.ws ?? null);
    if (!listing) this.recordUse(workspace, session, station);
    const request: Json = { workspace, session, key };
    if (tool === "station_task") {
      const action = text(args, "action");
      if (!["prepare", "start", "get", "log", "stop", "list"].includes(action)) throw new Error("unknown task action");
      request.method = `task.${action}`;
      request.lines = field(args, "lines");
      request.spec = { name: field(args, "name"), command: field(args, "command"), requestedBy: row.createdBy };
      // A task's directory and what it brings back, as this station has them (remote/prepared).
      const prepared = join(this.root, "prepared", `${hash([workspace, session, station, key])}.json`);
      if (action === "prepare") {
        const dir = field(args, "dir");
        const back = field(args, "back");
        if (dir !== null) {
          if (typeof dir !== "string" || !isAbsolute(dir)) throw new Error("dir must be an absolute path on this machine");
          let isDir = false;
          try {
            isDir = statSync(dir).isDirectory();
          } catch {}
          if (!isDir) throw new Error(`${dir} is not a directory`);
          // A station from before would take the task and run it without the files.
          const described = await this.ask(station, { method: "describe", workspace });
          if (field(described, "sync") === null) {
            throw new Error(`${station} is from before directory sync and would run the task without the files; update that station first, or upload inputs with station_file`);
          }
          request.spec.dir = resolve(dir);
        }
        if (back !== null) {
          const relative = (p: unknown) => typeof p === "string" && p !== "" && !isAbsolute(p) && p.split(/[\\/]/).every((part) => part !== "..");
          if (!Array.isArray(back) || back.length > 100 || !back.every(relative)) throw new Error("back must be paths relative to the task's directory (at most 100)");
          request.spec.back = back;
        }
        const answer = await this.ask(station, request);
        if (dir !== null || back !== null) writeJson(prepared, { workspace, session, station, key, dir: request.spec.dir ?? null, back: request.spec.back ?? null });
        return answer;
      }
      let synced: Synced | null = null;
      if (action === "start") {
        let local: Json = null;
        try {
          local = readJson(prepared);
        } catch {}
        if (typeof local?.dir === "string") {
          try {
            synced = await syncDir((method, more) => this.ask(station, { workspace, session, key, method, ...more }), local.dir, () => this.store.now());
          } catch (error) {
            const message = (error as Error).message;
            if (error instanceof Refused && /unsupported peer method/.test(message)) {
              throw new Error(`${station} cannot sync directories (it is from before); nothing was started. Update that station first`);
            }
            throw new Error(`${local.dir} was not synced to ${station}, so nothing was started: ${message}`);
          }
        }
        // Persist before sending: an uncertain start is still followed after a process restart.
        const path = this.outgoing(workspace, session, station, key);
        let refused = false;
        try {
          refused = readJson(path).refused === true;
        } catch {}
        if (!existsSync(path) || refused) {
          const more = local === null ? {} : { dir: local.dir ?? null, back: local.back ?? null, prefix: synced?.prefix ?? "" };
          writeJson(path, { workspace, session, station, key, delivered: false, ...more });
        }
        this.watch(path);
      }
      try {
        const answer = await this.ask(station, request);
        return synced === null ? answer : { ...answer, sync: synced };
      } catch (error) {
        if (action === "start" && error instanceof Refused) {
          const path = this.outgoing(workspace, session, station, key);
          try {
            const entry = readJson(path);
            entry.delivered = true;
            entry.refused = true;
            writeJson(path, entry);
          } catch {}
        }
        throw error;
      }
    }
    const root = row.workspace;
    const localArg = text(args, "local");
    let relative = localArg;
    if (isAbsolute(localArg)) {
      // Path::strip_prefix: whole components of the session's workspace (as the machine compares them); a `..` left in
      // it is filePath's to refuse.
      const within = platform.paths.relativeIn(root, localArg);
      if (within === null) throw new Error("local file must be inside this session workspace");
      relative = within;
    }
    const direction = text(args, "direction");
    const path = filePath(root, relative, direction === "download");
    request.path = field(args, "path");
    if (direction === "upload") {
      const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      try {
        const stat = fstatSync(fd);
        const size = stat.size;
        if (!stat.isFile() || size > MAX_FILE) throw new Error("input must be a regular file of at most 1 GiB");
        let offset = 0;
        for (;;) {
          const chunk = Buffer.alloc(CHUNK);
          const n = readSync(fd, chunk, 0, CHUNK, offset);
          request.method = "file.put";
          request.offset = offset;
          request.data = chunk.subarray(0, n).toString("base64");
          request.final = offset + n === size;
          await this.ask(station, { ...request });
          offset += n;
          if (offset === size) break;
          if (n === 0) throw new Error("input changed while reading");
        }
        return { uploaded: path, bytes: size };
      } finally {
        closeSync(fd);
      }
    }
    if (direction === "download") {
      const size = await this.download((r) => this.ask(station, r), request, path, false);
      return { downloaded: path, bytes: size };
    }
    throw new Error("direction must be upload or download");
  }
}

/// serde_json's as_i64.
function asI64(v: unknown): number | null {
  return typeof v === "number" && Number.isInteger(v) ? v : null;
}

/// The target side of the station transport (peer.rs `serve`): a request taken in, its answer as the wire has it
/// (`{"result": …}` or `{"error": "…"}`). The transport checks the peer and its workspace before.
export async function answerPeer(remote: Remote, workspace: string, peer: string, request: Json): Promise<Json> {
  try {
    return { result: await remote.handle(workspace, peer, request) };
  } catch (error) {
    return { error: (error as Error).message };
  }
}
