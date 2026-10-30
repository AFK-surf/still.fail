// Tasks on other stations of the workspace (the Rust station's remote.rs). Workspace peers call named operations over an
// authenticated station transport (`stillfail/station/1`, the mesh layer's); shell tasks are one service on it, never an
// admin API proxy. Any station of the workspace may run them (the transport checks the roster), as its agents may open a
// chat here whose agent runs the same commands: shell execution as the station's OS user, not a sandbox. A source session's
// tasks share one working directory on the target (remote/sessions/<id>/work). The source asks for it to be removed
// when the session is archived or deleted; the target removes it itself after IDLE_MS unused, and a directory mirrored
// in it (a task's `dir`) after MIRROR_IDLE_MS without a task, or sooner when the station's disk runs low (ops/disk.ts).
//
// The records are the Rust's files, written the same way (remote/incoming/<id>/task.json, sessions/<id>/session.json,
// outgoing/<id>.json, used/<id>.json), so either station reads what the other wrote. A task's station tells the one
// that started it when the task ends or says something (`task.changed`), and that one then asks it what (`task.get`):
// nothing asks about a task while nothing happens to it, but a task on a station from before that (asked every 5 s).
// What is retried (a request that did not get through, a closed session's stations every 60 s) and the hourly sweep
// are Effect schedules; nothing here polls local state.
import { createHash, randomBytes } from "node:crypto";
import {
  appendFileSync, closeSync, constants, existsSync, fstatSync, fsyncSync, ftruncateSync, lstatSync, mkdirSync, openSync, readFileSync,
  readSync, readdirSync, readlinkSync, renameSync, rmSync, statSync, writeFileSync, writeSync,
} from "node:fs";
import { link, mkdir, open, readFile, readdir, rename, rm } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { DISK_LOW_BYTES, diskFree } from "../ops/disk.ts";
import { portableComponent, relativeParts } from "../ops/paths.ts";
import { PlaceRefused, Places } from "../ops/places.ts";
import { platform } from "../platform/index.ts";
import { isDeepStrictEqual } from "node:util";
import { Clock, Duration, Effect, Exit, FiberSet, Schedule, Scope } from "effect";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { type Json, type Store } from "../store/store.ts";
import { type Jobs, jobJson, tail } from "./jobs.ts";
import { detailed, summary } from "./load.ts";
import { type Inbox, MESH_WAIT_MS, NoBytes, type PeerCall, PeerBus, Refused, bytesOf, withBytes } from "../mesh/bus.ts";
import { fileBytes, readBytes, stopBytes, writeBytes } from "../mesh/files.ts";
import { Bulk, LINK, PACKED, type Synced, actual, apply, listed, page, patchOf, planPart, putBlobs, readManifest, syncDir, writeManifest } from "./dirsync.ts";

// The requests between stations are the platform's bus (mesh/bus.ts); its types, here as they always were.
export { type Inbox, MESH_WAIT_MS, type PeerCall, Refused } from "../mesh/bus.ts";
/// A request that did not get through (asked again later).
class Unreached extends Error {}
/// What a task's station said of it in a round: its `task.get` answer, its refusal; null when it was not reached.
type Got = { result: Json } | { refused: string } | null;
/// What came of asking about a task (`settle`): it is over; nothing to do until its station says something; asked
/// again soon (not reached, or not told); asked again at `at` (not started there yet).
type Outcome = "over" | "wait" | "again" | { at: number };
/// Whether the task's station tells of it itself (`task.changed`).
const pushes = (got: Got): boolean => got !== null && "result" in got && field(got.result, "push") === true;
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
/// How often a source asks about a task on a station from before `task.changed`, a closed session's stations, and a
/// target sweeps.
const WATCH_EVERY = "5 seconds";
/// A request that did not get through (`task.changed` to the source, `task.get` after it) is asked again after 1 s,
/// then twice as long each time, at most a minute apart.
const AGAIN = Schedule.min([Schedule.exponential("1 second"), Schedule.spaced("1 minute")]);
const CLOSE_EVERY = "60 seconds";
const SWEEP_EVERY = "1 hour";
/// A task its station does not know, or has not started, this long after its start was asked for is no longer followed.
export const GIVE_UP_MS = 10 * 60_000;
/// A mirror (a task's `dir` on the target) no task of its session has run in or synced for this long goes, with what
/// its tasks made there; the next start syncs it anew. Chats made one for each worktree and kept them all: 204 of
/// one session's on Studio, a session's 78 holding 112G, the stations' disks full in hours (2026-10-20).
export const MIRROR_IDLE_MS = 24 * 3600 * 1000;
/// With the station's disk low (`relieve`), a mirror used within this stays.
export const MIRROR_RECENT_MS = 3600 * 1000;

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
  /// The station's requests to and from the others (mesh/bus.ts); one of its own when none is given (tests).
  bus?: PeerBus;
  /// How a task's `dir` is looked at (ops/places.ts): the station syncs it itself, so in a folder macOS protects it
  /// must reach it itself, looked at off its thread. Default: without still.fail Helper.
  places?: Places;
  /// The bytes free on the disk holding `path` (tests say how full it is). Default: statfs.
  diskFree?: (path: string) => number;
};

/// A start that syncs a directory answers within this, synced or not (the sync goes on): an agent's tool call is given
/// up on after a minute, and the agent asking again (the same key) began another sync over the first, which the target
/// then refused as over, again and again (2026-10-19). Asked again, the start takes up the sync under way.
export const SYNC_ANSWER_MS = 40_000;
/// A sync that ended while no start waited for it is what the next start of its task gets, this long after.
const SYNC_KEPT_MS = 10 * 60_000;

/// A directory's sync to a station, for one task: the start that began it, and later ones of the same task, wait on it.
type Syncing = { key: string; result: Promise<Synced | null>; endedAt: number | null };

/// The requests about tasks that only read what is here: answered as they come, never after another one (`lanes`).
const READS = new Set(["task.get", "task.gets", "task.log", "task.list"]);
/// The tasks a source asks about at once (`task.gets`), at most.
export const GETS_MAX = 200;

/// station_list asks every station of the workspace at once and lists one that has not answered within this as offline.
export const LIST_WAIT_MS = 2000;
/// A station asked how busy it is (`describe`'s `load`) says it does not know when measuring takes longer than this.
export const LOAD_WAIT_MS = 1000;

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

/// readJson off the station's thread (fs/promises): what is read again on a schedule, or all the records at once.
const readJsonSoon = async (path: string): Promise<Json> => JSON.parse(await readFile(path, "utf8"));

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
  /// The requests to and from the other stations: what this answers is said on it (`describe`, the tasks).
  readonly bus: PeerBus;
  private places: Places;
  /// How busy this station is, told to the others in `describe` (load.ts); none: `describe` says nothing of it.
  private load: (() => Promise<Json>) | null = null;
  /// Withdrawals (`revoke`), one at a time.
  private serial: Promise<unknown> = Promise.resolve();
  /// Each source session's requests that change something here, one after another; those of different sessions at
  /// once, and those that only read (READS) as they come. All of them in one line, a task's state asked by one chat
  /// waited behind another chat's sync of a big directory on a loaded station, past its caller's 30 s, and the callers
  /// asked again into the same line (2026-10-21, Studio for ccvm: a 1 KB file synced in 61 s).
  private lanes = new Map<string, Promise<unknown>>();
  /// The records followed now (outgoing tasks, closing sessions).
  private watching = new Set<string>();
  /// The outgoing tasks followed, by the station (and workspace) they are on: asked about together.
  private following = new Map<string, Set<string>>();
  /// The station is stopping: nothing more is followed.
  private stopped = false;
  /// Tasks asked about after their station said something (`check`), each with whether it said more meanwhile.
  private checking = new Map<string, boolean>();
  /// Tasks here whose source is being told they changed (`pushOut`), each with whether they changed again meanwhile.
  private pushing = new Map<string, boolean>();
  /// The station's bulk requests to the others (syncs' contents, files' chunks), one at a time (dirsync.ts).
  private bulk = new Bulk();
  /// The sync of each directory to each station of each session (by `hash([workspace, session, station, dir])`), the
  /// latest: one at a time, and a start asked again takes up its own task's.
  private syncs = new Map<string, Syncing>();
  private scope: Scope.Closeable;
  private run: (effect: Effect.Effect<void>) => Promise<void>;
  private diskFree: (path: string) => number;

  constructor(options: RemoteOptions) {
    this.data = options.data;
    this.store = options.store;
    this.jobs = options.jobs;
    this.notify = options.notify;
    this.places = options.places ?? new Places();
    this.diskFree = options.diskFree ?? diskFree;
    this.root = join(options.data, "remote");
    for (const name of ["incoming", "outgoing", "sessions", "used", "prepared"]) mkdirSync(join(this.root, name), { recursive: true });
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
    this.bus = options.bus ?? new PeerBus({ waitMs: options.meshWaitMs ?? MESH_WAIT_MS, sleep: (ms) => this.run(Effect.sleep(Duration.millis(ms))).catch(() => undefined) });
    // What this answers: how this station is and what it takes, and the tasks (whatever no other part answers).
    this.bus.on("describe", () => this.describe());
    this.bus.otherwise((peer, request, workspace) => {
      const ws = workspace ?? "";
      const method = text(request, "method");
      if (READS.has(method)) return this.task(ws, peer, method, request);
      return this.inLane(this.room(ws, peer, text(request, "session")), () => this.task(ws, peer, method, request));
    });
    // A task started from here changed on its station: asked about.
    this.bus.on("task.changed", (_peer, request, workspace) => this.changedThere(workspace ?? "", request));
    // A task here changed: its source is told.
    this.jobs.onRemote((job) => this.pushOut(job.id.slice("remote_".length)));
    this.bus.whenAttached(() => this.started());
  }

  /// The transport is there (the bus's, mesh/mesh.ts; a test's).
  attach(call: PeerCall): void {
    this.bus.attach(call);
  }

  /// Follows the tasks started from here and the sessions closing, tells the sources of tasks here what they missed;
  /// sweeps now and hourly.
  private started(): void {
    void this.resume().catch(() => undefined);
    void this.movePrepared().catch(() => undefined);
    void this.pushMissed().catch(() => undefined);
    void this.run(
      Effect.promise(() => this.sweep(this.store.now())).pipe(Effect.repeat(Schedule.spaced(SWEEP_EVERY)), Effect.asVoid),
    ).catch(() => undefined);
  }

  /// The tasks started from here not told yet followed again, and the sessions closing: their records read off the
  /// station's thread (every task's ever started from here is kept: 13,000 on ccvm, read at each start).
  private async resume(): Promise<void> {
    const read = async (dir: string, wanted: (v: Json) => boolean): Promise<string[]> => {
      const names = await readdir(join(this.root, dir)).catch(() => [] as string[]);
      const found: string[] = [];
      for (const name of names.filter((n) => n.endsWith(".json"))) {
        if (this.stopped) break;
        const path = join(this.root, dir, name);
        const v = await readJsonSoon(path).catch(() => null);
        if (v !== null && wanted(v)) found.push(path);
      }
      return found;
    };
    // All of them found before any is asked about: those on one station are asked about together, once (what they
    // said while this station was not running).
    const followed = await read("outgoing", (v) => v.delivered !== true);
    const closing = await read("used", (v) => field(v, "closing") === true);
    if (this.stopped) return;
    const groups = new Map<string, string[]>();
    for (const path of followed) {
      let entry: Json;
      try {
        entry = readJson(path);
      } catch {
        continue;
      }
      const group = JSON.stringify([text(entry, "station"), field(entry, "workspace")]);
      groups.set(group, [...(groups.get(group) ?? []), path]);
    }
    for (const [group, paths] of groups) {
      const [station, workspace] = JSON.parse(group);
      void this.round(station, workspace, paths, true, () => undefined)
        .then((outcomes) => outcomes.forEach(([path, outcome, got]) => this.after(path, outcome, got)))
        .catch(() => undefined);
    }
    for (const path of closing) this.closer(path);
  }

  /// The tasks here whose source was not told of their last change (it was not reached, or this station stopped
  /// before telling it): told now.
  private async pushMissed(): Promise<void> {
    const names = await readdir(join(this.root, "incoming")).catch(() => [] as string[]);
    for (const name of names) {
      if (this.stopped) return;
      const meta = await readJsonSoon(join(this.root, "incoming", name, "task.json")).catch(() => null);
      if (meta !== null && text(meta, "push") !== "" && field(meta, "pushed") !== this.said(name)) this.pushOut(name);
    }
  }

  /// What the task here with this id has come to: its job's state and what it said, hashed (null before it started).
  private said(id: string): string | null {
    const jobId = `remote_${id}`;
    const job = this.store.getJob(jobId);
    return job ? hash([job.state, job.endedAt, this.store.jobNotices(jobId, 20) as unknown as Json]) : null;
  }

  /// Tells the station a task here came from that it changed (`task.changed`, which asks then); asked again until it
  /// is reached. Its last change told is kept in its record (`pushed`).
  private pushOut(id: string): void {
    if (this.stopped) return;
    if (this.pushing.has(id)) {
      this.pushing.set(id, true);
      return;
    }
    this.pushing.set(id, false);
    const record = join(this.root, "incoming", id, "task.json");
    const once = Effect.promise(async (): Promise<boolean> => {
      this.pushing.set(id, false);
      let meta: Json;
      try {
        meta = await readJsonSoon(record);
      } catch {
        return true;
      }
      const ref = text(meta, "push");
      const said = this.said(id);
      if (ref === "" || said === null || field(meta, "pushed") === said) return true;
      try {
        await this.ask(text(meta, "station"), { method: "task.changed", workspace: field(meta, "workspace"), ref });
      } catch (error) {
        // A refusal is final (the source no longer has the task); anything else is asked again.
        if (!(error instanceof Refused)) return false;
      }
      try {
        const now = readJson(record);
        now.pushed = said;
        writeJson(record, now);
      } catch {}
      return true;
    });
    void this.run(
      once.pipe(
        Effect.repeat({ schedule: AGAIN, until: (over) => over || this.stopped }),
        Effect.ensuring(Effect.sync(() => {
          const again = this.pushing.get(id) === true;
          this.pushing.delete(id);
          if (again) this.pushOut(id);
        })),
        Effect.asVoid,
      ),
    ).catch(() => undefined);
  }

  /// `task.changed`: the station of a task started from here says it changed; asked what, after the answer.
  private async changedThere(workspace: string, request: Json): Promise<Json> {
    const ref = text(request, "ref");
    if (!/^[0-9a-f]{64}$/.test(ref)) throw new Error("ref is required");
    const path = join(this.root, "outgoing", `${ref}.json`);
    let entry: Json;
    try {
      entry = readJson(path);
    } catch {
      throw new Error("unknown task");
    }
    // Only what the task's own station says is taken (`check` asks that one), so this need not be from it.
    if (text(entry, "workspace") !== workspace) throw new Error("unknown task");
    this.check(path);
    return { taken: true };
  }

  /// Its schedules end (the station stops).
  async close(): Promise<void> {
    this.stopped = true;
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

  /// `f` after what was asked before it in `lane` (a source session's: its room).
  private inLane<T>(lane: string, f: () => Promise<T>): Promise<T> {
    const result = (this.lanes.get(lane) ?? Promise.resolve()).then(f, f);
    const tail = result.then(
      () => undefined,
      () => undefined,
    );
    this.lanes.set(lane, tail);
    void tail.then(() => {
      if (this.lanes.get(lane) === tail) this.lanes.delete(lane);
    });
    return result;
  }

  room(workspace: string, peer: string, session: string): string {
    return join(this.root, "sessions", hash([workspace, peer, session]));
  }

  /// A source session's shared directory, made and noted as used (a command run there with a secret of the vault:
  /// vault/secrets.ts `heard`).
  work(workspace: string, peer: string, session: string): string {
    return this.seen(workspace, peer, session);
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

  /// What a task waiting in the queue is told of it: its place and why it waits (none for one not waiting).
  private queued(jobId: string): Json {
    const q = this.jobs.queueOf(jobId);
    if (q === null) return {};
    const why =
      q.why === "memory" ? "the machine's memory is under pressure"
      : q.why === "screen" ? `another task that uses the screen runs${q.holder !== undefined ? ` (${q.holder})` : ""}`
      : q.why === "person" ? "a person is using this machine's screen (its input not idle): no task is given it meanwhile"
      : "the machine is busy";
    return { queue: { place: q.place, why: q.why, ...(q.holder !== undefined ? { holder: q.holder } : {}), note: `Waiting in this station's queue (${q.place === 1 ? "next" : `number ${q.place}`}): ${why}. It starts by itself when there is room; you are told when it ends, as for any task.` } };
  }

  private running(task: string): boolean {
    return this.store.getJob(this.jobOf(task))?.state === "running";
  }

  /// Stops a source session's tasks and removes their records and its shared directory. Callers are in its lane.
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
  async sweep(now: number): Promise<void> {
    const sessions = join(this.root, "sessions");
    for (const name of this.list(sessions)) {
      let meta: Json;
      try {
        meta = readJson(join(sessions, name, "session.json"));
      } catch {
        continue;
      }
      const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
      await this.inLane(this.room(workspace, peer, session), async () => {
        // Asked again in its lane: used meanwhile, it stays.
        let seen: number;
        try {
          seen = asI64(field(readJson(join(sessions, name, "session.json")), "seen")) ?? now;
        } catch {
          return;
        }
        if (now - seen >= IDLE_MS && !this.tasksOf(workspace, peer, session).some((t) => this.running(t))) {
          try {
            await this.closeHere(workspace, peer, session);
          } catch (error) {
            log.warn("remote", "idle remote session directory not removed", { error: (error as Error).message });
          }
          return;
        }
        for (const m of this.mirrorsOf(workspace, peer, session, now)) {
          if (!m.busy && now - m.used >= MIRROR_IDLE_MS) this.dropMirror(workspace, peer, session, m.name, "unused");
        }
      });
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
  }

  /// A session's mirrors on this station: when a task last ran in or synced each (one from before this is taken as
  /// used now), and whether one runs there or syncs to it now (those are marked used now).
  private mirrorsOf(workspace: string, peer: string, session: string, now: number): { name: string; used: number; busy: boolean }[] {
    const room = this.room(workspace, peer, session);
    const record = join(room, "mirrors-used.json");
    let used: Json = {};
    try {
      used = readJson(record);
    } catch {}
    // A task that ended counts as a use then: what it made is brought back after.
    const running = new Set<string>();
    const ended = new Map<string, number>();
    for (const task of this.tasksOf(workspace, peer, session)) {
      let mirror: Json = null;
      try {
        mirror = field(readJson(join(task, "task.json")), "mirror");
      } catch {}
      if (typeof mirror !== "string") continue;
      const job = this.store.getJob(this.jobOf(task));
      if (job?.state === "running") running.add(mirror);
      else if (job?.endedAt) ended.set(mirror, Math.max(ended.get(mirror) ?? 0, job.endedAt));
    }
    const found: { name: string; used: number; busy: boolean }[] = [];
    let changed = false;
    for (const file of this.list(join(room, "mirrors"))) {
      if (!file.endsWith(".json")) continue;
      const name = file.slice(0, -".json".length);
      const busy = running.has(name) || this.syncing(join(room, "sync", name), now);
      let at = asI64(field(used, name));
      if (at === null || busy) {
        at = now;
        used[name] = now;
        changed = true;
      }
      found.push({ name, used: Math.max(at, ended.get(name) ?? 0), busy });
    }
    if (changed) writeJson(record, used);
    return found;
  }

  /// A sync to a mirror is under way: its directory there, it or what is in it touched within MIRROR_RECENT_MS (one
  /// given up on is not).
  private syncing(dir: string, now: number): boolean {
    let latest = 0;
    for (const path of [dir, ...this.list(dir).map((name) => join(dir, name))]) {
      try {
        latest = Math.max(latest, statSync(path).mtimeMs);
      } catch {}
    }
    return now - latest < MIRROR_RECENT_MS;
  }

  /// A task ran in or synced `mirror` now. Callers are in the session's lane.
  private usedMirror(workspace: string, peer: string, session: string, mirror: string): void {
    const record = join(this.room(workspace, peer, session), "mirrors-used.json");
    let used: Json = {};
    try {
      used = readJson(record);
    } catch {}
    used[mirror] = this.store.now();
    writeJson(record, used);
  }

  /// Removes a mirror and what its tasks made in it; its tasks that have not started sync again first. Callers are
  /// in the session's lane.
  private dropMirror(workspace: string, peer: string, session: string, mirror: string, why: string): void {
    const room = this.room(workspace, peer, session);
    try {
      rmSync(join(room, "work", mirror), { recursive: true, force: true });
      rmSync(join(room, "sync", mirror), { recursive: true, force: true });
      rmSync(join(room, "mirrors", `${mirror}.json`), { force: true });
      const record = join(room, "mirrors-used.json");
      try {
        const used = readJson(record);
        delete used[mirror];
        writeJson(record, used);
      } catch {}
      for (const task of this.tasksOf(workspace, peer, session)) {
        const path = join(task, "task.json");
        const meta = readJson(path);
        if (meta.mirror === mirror && meta.synced === true) {
          meta.synced = false;
          writeJson(path, meta);
        }
      }
      log.info("remote", "remote mirror removed", { workspace, station: peer, session, mirror, why });
    } catch (error) {
      log.warn("remote", "remote mirror not removed", { mirror, error: (error as Error).message });
    }
  }

  /// The disk of the station's data has less than DISK_LOW_BYTES free (looked at by the station, ops/disk.ts): mirrors
  /// go, the longest unused first, until there is that much again. One a task runs in or syncs to, or used within
  /// MIRROR_RECENT_MS, stays.
  async relieve(now: number): Promise<void> {
    const free = () => {
      try {
        return this.diskFree(this.root);
      } catch {
        return Number.POSITIVE_INFINITY;
      }
    };
    if (free() >= DISK_LOW_BYTES) return;
    const sessions = join(this.root, "sessions");
    const candidates: { workspace: string; peer: string; session: string; name: string; used: number }[] = [];
    for (const name of this.list(sessions)) {
      let meta: Json;
      try {
        meta = readJson(join(sessions, name, "session.json"));
      } catch {
        continue;
      }
      const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
      await this.inLane(this.room(workspace, peer, session), async () => {
        for (const m of this.mirrorsOf(workspace, peer, session, now)) {
          if (!m.busy && now - m.used >= MIRROR_RECENT_MS) candidates.push({ workspace, peer, session, name: m.name, used: m.used });
        }
      });
    }
    candidates.sort((a, b) => a.used - b.used);
    for (const c of candidates) {
      if (free() >= DISK_LOW_BYTES) return;
      // Asked again in its lane: used since, it stays.
      await this.inLane(this.room(c.workspace, c.peer, c.session), async () => {
        const m = this.mirrorsOf(c.workspace, c.peer, c.session, now).find((x) => x.name === c.name);
        if (m && !m.busy && now - m.used >= MIRROR_RECENT_MS) this.dropMirror(c.workspace, c.peer, c.session, c.name, "disk low");
      });
    }
  }

  /// A session's prepared tasks' directories and what they bring back, as this station has them: one directory per
  /// session, so closing one removes its own without reading the others' (2,875 on ccvm, each read on the station's
  /// thread at every close, 24 seconds held while memory was short).
  private preparedDir(session: string): string {
    return join(this.root, "prepared", hash(session));
  }

  /// Prepared records from before they were kept by session (remote/prepared/<hash>.json) moved into their session's,
  /// read off the thread.
  private async movePrepared(): Promise<void> {
    const dir = join(this.root, "prepared");
    for (const name of await readdir(dir).catch(() => [] as string[])) {
      if (this.stopped) return;
      if (!name.endsWith(".json")) continue;
      const file = join(dir, name);
      const v = await readJsonSoon(file).catch(() => null);
      const session = text(v, "session");
      if (session === "") {
        await rm(file, { force: true }).catch(() => undefined);
        continue;
      }
      await mkdir(this.preparedDir(session), { recursive: true }).catch(() => undefined);
      await rename(file, join(this.preparedDir(session), name)).catch(() => undefined);
    }
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
    // Their directories are going away: stop following this session's tasks. Every record is read to find them, off
    // the thread; one of theirs read again as it is changed (meanwhile written by its follower).
    const outgoing = join(this.root, "outgoing");
    void (async () => {
      for (const name of await readdir(outgoing).catch(() => [] as string[])) {
        const file = join(outgoing, name);
        try {
          const seen = await readJsonSoon(file);
          if (text(seen, "session") !== session || seen.delivered === true) continue;
          const entry = readJson(file);
          if (entry.delivered === true) continue;
          entry.delivered = true;
          writeJson(file, entry);
        } catch {}
      }
    })();
    // Its prepared tasks are in a directory of their own: removed whole, off the thread.
    void rm(this.preparedDir(session), { recursive: true, force: true }).catch(() => undefined);
    this.closer(path);
  }

  /// Asks each station a closing session used to remove its directory, every minute until all have answered.
  private closer(path: string): void {
    if (this.watching.has(path)) return;
    this.watching.add(path);
    const round = Effect.promise(async (): Promise<boolean> => {
      let v: Json;
      try {
        v = await readJsonSoon(path);
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
    this.bus.on(["session.message", "session.read", "session.file", "session.put", "session.create", "session.notice"], inbox);
  }

  /// Where requests about what stations share go (share.*, share/index.ts): any station of the workspace may ask;
  /// what each share allows is checked there.
  setShares(shares: Inbox): void {
    this.bus.on("share.", shares);
  }

  /// Where requests about chats shared across workspaces go (xshare.*, xshare/index.ts): `inside` those of this
  /// workspace's stations, `outside` every request of a station that is not of it (the transport lets those through
  /// only while there is one).
  setOutside(handlers: { inside: Inbox; outside: Inbox }): void {
    this.bus.on("xshare.", handlers.inside);
    this.bus.outside(handlers.outside);
  }

  /// How this station's load is measured (load.ts `measure`), for `describe`.
  setLoad(load: () => Promise<Json>): void {
    this.load = load;
  }

  /// `what`, or null when it has not settled within `ms` on the clock (it goes on); its rejection as `error`.
  private async bounded<T>(what: Promise<T>, ms: number): Promise<{ ok: T } | { error: Error } | null> {
    let out: { ok: T } | { error: Error } | null = null;
    const settled = what.then(
      (ok) => void (out = { ok }),
      (error) => void (out = { error: error instanceof Error ? error : new Error(String(error)) }),
    );
    await this.run(Effect.race(Effect.promise(() => settled), Effect.sleep(Duration.millis(ms)))).catch(() => undefined);
    return out;
  }

  /// `describe`'s answer: what this station takes, and how busy it is (`load`, LOAD_WAIT_MS at most).
  private async describe(): Promise<Json> {
    const answer: Json = { protocol: 1, os: OS, arch: ARCH, tasks: true, sessions: true, messages: true, reads: true, files: true, chats: true, sync: 1, fileChunkBytes: CHUNK, maxFileBytes: MAX_FILE };
    if (this.load !== null) {
      const load = await this.bounded(this.load(), LOAD_WAIT_MS);
      answer.load = load === null ? { unavailable: `not measured within ${LOAD_WAIT_MS / 1000} s` } : "ok" in load ? load.ok : { unavailable: load.error.message };
    }
    return answer;
  }

  /// station_list: the stations of `workspace`, each asked how busy it is at once (this one answers itself); one that
  /// has not answered within LIST_WAIT_MS is listed as offline, one that refused says why.
  private async listStations(workspace: string): Promise<Json> {
    const roster = await this.ask("", { method: "peers", workspace });
    const own = this.ownId();
    const stations = Array.isArray(roster?.stations) ? roster.stations : [];
    const listed = await Promise.all(
      stations.map(async (entry: Json) => {
        const id = text(entry, "id");
        if (id === "") return entry;
        if (id === own) return { ...entry, here: true, load: summary((await this.describe()).load ?? null) };
        const got = await this.bounded(this.ask(id, { method: "describe", workspace }), LIST_WAIT_MS);
        if (got === null) return { ...entry, offline: `did not answer within ${LIST_WAIT_MS / 1000} s` };
        if ("error" in got) return got.error instanceof Refused ? { ...entry, refused: got.error.message } : { ...entry, offline: got.error.message };
        return { ...entry, load: summary(field(got.ok, "load")) };
      }),
    );
    return { ...roster, stations: listed };
  }

  /// The id of the station an agent names: station_list shows each by its name and its id, and either is taken. A name
  /// no station of the workspace has (a station of another workspace this one shares chats with is named by its id)
  /// goes on as given, to be refused or reached as an id.
  private async stationNamed(workspace: string, named: string): Promise<string> {
    if (named === "") return named;
    let stations: Json[] = [];
    try {
      const roster = await this.ask("", { method: "peers", workspace });
      if (Array.isArray(roster?.stations)) stations = roster.stations;
    } catch {
      return named;
    }
    if (stations.some((s) => text(s, "id") === named)) return named;
    const same = stations.filter((s) => text(s, "name").toLowerCase() === named.toLowerCase());
    if (same.length > 1) throw new Error(`${same.length} stations are named ${named}; give the id station_list shows for the one meant`);
    return same.length === 1 ? text(same[0], "id") : named;
  }

  /// This station's id (mesh/cloud.json), "" when it has none.
  private ownId(): string {
    try {
      return text(readJson(join(this.data, "mesh", "cloud.json")), "station");
    } catch {
      return "";
    }
  }

  /// Whether stations of other workspaces are heard at all.
  hearsOutside(): boolean {
    return this.bus.hearsOutside();
  }

  /// A request of a station that is not of this workspace (the transport checked it names this workspace).
  handleOutside(peer: string, request: Json, workspace?: string): Promise<Json> {
    return this.bus.handleOutside(peer, request, workspace);
  }

  /// A request to another station of the workspace (session_send's messages, and this module's own).
  ask(station: string, request: Json): Promise<Json> {
    return this.bus.ask(station, request);
  }

  /// Called only after the transport authenticates the source station and checks current workspace membership.
  handle(workspace: string, peer: string, request: Json): Promise<Json> {
    return this.bus.handle(workspace, peer, request);
  }

  private async task(workspace: string, peer: string, method: string, request: Json): Promise<Json> {
    if (method === "task.gets") {
      // What `task.get` says of each, in one request (a source follows all its tasks here at once: `follow`).
      const asked = field(request, "tasks");
      if (!Array.isArray(asked) || asked.length > GETS_MAX) throw new Error(`tasks are required (at most ${GETS_MAX})`);
      const tasks: Json[] = [];
      for (const one of asked) {
        const [session, key] = [field(one, "session"), field(one, "key")];
        try {
          tasks.push({ session, key, result: await this.task(workspace, peer, "task.get", { session, key }) });
        } catch (error) {
          tasks.push({ session, key, error: (error as Error).message });
        }
      }
      return { tasks };
    }
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
        if (mirror !== null) {
          cwd = filePath(work, mirror, false);
          this.usedMirror(workspace, peer, session, mirror);
        }
        const spec = field(meta, "spec");
        // Through the station's queue (jobs/admit.ts): started now if there is room, else when there is.
        const started = this.jobs.startId(owner, text(spec, "name"), text(spec, "command"), cwd, null, false, jobId, false, { screen: field(spec, "screen") === true });
        // Where its source wants to be told of it (`pushOut`): from its first start, as it is then (a start asked again
        // keeps what was told).
        const push = text(request, "push");
        if (/^[0-9a-f]{64}$/.test(push) && meta.push !== push) {
          meta.push = push;
          meta.pushed = this.said(id);
          writeJson(record, meta);
        }
        return { key, job: jobJson(started), ...this.queued(started.id), ...(meta.push ? { push: true } : {}) };
      }
      case "sync.begin": {
        if (job) return { key, started: true };
        refuseBusy();
        rmSync(syncing, { recursive: true, force: true });
        mkdirSync(syncing, { recursive: true });
        mkdirSync(join(room, "mirrors"), { recursive: true });
        this.usedMirror(workspace, peer, session, mirror!);
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
        // The packed pieces after the request; from a station from before, base64 in it.
        const packed = bytesOf(request);
        return { pieces: await putBlobs(join(syncing, "blobs"), field(request, "blobs"), packed !== null ? await readBytes(packed, PACKED) : fromBase64(text(request, "data"))) };
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
        this.usedMirror(workspace, peer, session, mirror!);
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
        const push = typeof meta.push === "string" ? { push: true } : {};
        return { key, job: job ? jobJson(job) : null, log: job ? tail(job.log, lines) : null, notices: this.store.jobNotices(jobId, 20), ...this.queued(jobId), ...push };
      }
      case "task.stop": {
        if (!job) throw new Error("task has not started");
        return { key, job: jobJson(await this.jobs.stop(job.id)) };
      }
      case "file.put": {
        if (job) throw new Error("inputs are immutable after a task starts");
        const incoming = bytesOf(request);
        if (incoming !== null) {
          // The whole file after the request (`size` of it), written as it comes; a station from before sends chunks.
          const size = asU64(field(request, "size"));
          if (size === null || size > MAX_FILE) throw new Error("file limit exceeded");
          const name = text(request, "path");
          const path = filePath(work, name, true);
          if (meta.uploads === null || typeof meta.uploads !== "object" || Array.isArray(meta.uploads)) meta.uploads = {};
          meta.uploads[name] = false;
          writeJson(record, meta);
          const file = await open(path, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o666);
          try {
            if (!(await file.stat()).isFile()) throw new Error("only regular files can be transferred");
            if ((await writeBytes(file, incoming, 0, size)) !== size) throw new Error("the file did not all come");
            await file.truncate(size);
            await file.sync();
          } finally {
            await file.close();
          }
          meta.uploads[name] = true;
          writeJson(record, meta);
          return { bytes: size };
        }
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
          // All of it from there, after the answer; a station from before asks for chunks.
          if (field(request, "whole") === true) return withBytes({ size }, fileBytes(path, offset, size));
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

  /// Follows a task on a station from before `task.changed`: asks it every 5 s until it is over, telling its session
  /// what it said on the way and how it ended. The tasks followed on one station are asked about in one request
  /// (`task.gets`; one each of a station from before it). Across restarts (the record is a file).
  private watch(path: string): void {
    if (this.watching.has(path) || this.stopped) return;
    let entry: Json;
    try {
      entry = readJson(path);
    } catch {
      return;
    }
    if (entry.delivered === true) return;
    this.watching.add(path);
    const station = text(entry, "station");
    const workspace = field(entry, "workspace");
    const group = JSON.stringify([station, workspace]);
    const paths = this.following.get(group);
    if (paths !== undefined) {
      paths.add(path);
      return;
    }
    this.follow(group, station, workspace, new Set([path]));
  }

  /// Asks `station` about the tasks of `paths` every WATCH_EVERY (the first time WATCH_EVERY after it was last asked)
  /// until none is left to follow: over, or its station says it tells of it itself.
  private follow(group: string, station: string, workspace: Json, paths: Set<string>): void {
    this.following.set(group, paths);
    let batched = true;
    const round = Effect.promise(async (): Promise<boolean> => {
      const asked = [...paths];
      const outcomes = await this.round(station, workspace, asked, batched, () => (batched = false));
      for (const [path, outcome, got] of outcomes) {
        if (outcome === "over" || (outcome === "wait" && pushes(got))) {
          paths.delete(path);
          this.watching.delete(path);
        }
      }
      // Delivered meanwhile, or its record gone: not asked about.
      for (const path of asked) {
        if (outcomes.some(([p]) => p === path)) continue;
        paths.delete(path);
        this.watching.delete(path);
      }
      return paths.size === 0;
    });
    void this.run(
      Effect.sleep(WATCH_EVERY).pipe(
        Effect.andThen(round),
        Effect.repeat({ schedule: Schedule.spaced(WATCH_EVERY), until: (over) => over }),
        Effect.ensuring(Effect.sync(() => {
          if (this.following.get(group) === paths) this.following.delete(group);
          // Followed after the last round had found none left: followed anew.
          for (const path of [...paths]) {
            this.watching.delete(path);
            this.watch(path);
          }
        })),
        Effect.asVoid,
      ),
    ).catch(() => undefined);
  }

  /// Asks `station` once about the tasks of `paths` (those still to be told), what it says settled: each one's outcome.
  private async round(station: string, workspace: Json, paths: string[], batched: boolean, unbatch: () => void): Promise<[string, Outcome, Got][]> {
    const entries: [string, Json][] = [];
    for (const path of paths) {
      let entry: Json = null;
      try {
        entry = await readJsonSoon(path);
      } catch {}
      if (entry !== null && entry.delivered !== true) entries.push([path, entry]);
    }
    if (entries.length === 0) return [];
    const got = await this.states(station, workspace, entries.map(([, e]) => e), batched, unbatch);
    return Promise.all(entries.map(async ([path, entry], i): Promise<[string, Outcome, Got]> => [path, await this.settle(path, entry, got[i]), got[i]]));
  }

  /// What follows an outcome: asked again soon or later, followed every 5 s on a station from before `task.changed`,
  /// or nothing until its station says something.
  private after(path: string, outcome: Outcome, got: Got): void {
    if (outcome === "again") this.check(path);
    else if (typeof outcome === "object") this.later(path, outcome.at);
    else if (outcome === "wait" && !pushes(got)) this.watch(path);
  }

  /// Asks the station of the task started from here (`path`) about it now, and again (AGAIN) until it is reached and
  /// what it said is told.
  private check(path: string): void {
    if (this.stopped) return;
    if (this.checking.has(path)) {
      this.checking.set(path, true);
      return;
    }
    this.checking.set(path, false);
    let last: [Outcome, Got] = ["over", null];
    const once = Effect.promise(async (): Promise<boolean> => {
      this.checking.set(path, false);
      let entry: Json;
      try {
        entry = await readJsonSoon(path);
      } catch {
        return true;
      }
      const [one] = await this.round(text(entry, "station"), field(entry, "workspace"), [path], true, () => undefined);
      last = one === undefined ? ["over", null] : [one[1], one[2]];
      return last[0] !== "again";
    });
    void this.run(
      once.pipe(
        Effect.repeat({ schedule: AGAIN, until: (over) => over || this.stopped }),
        Effect.ensuring(Effect.sync(() => {
          const again = this.checking.get(path) === true;
          this.checking.delete(path);
          if (again) this.check(path);
          else this.after(path, last[0] === "again" ? "wait" : last[0], last[1]);
        })),
        Effect.asVoid,
      ),
    ).catch(() => undefined);
  }

  /// Asks about the task started from here (`path`) at `at`: one its station has not started, or does not know.
  private later(path: string, at: number): void {
    if (this.stopped) return;
    void this.run(Effect.sleep(Duration.millis(Math.max(0, at - this.store.now()))).pipe(Effect.andThen(Effect.sync(() => this.check(path))))).catch(() => undefined);
  }

  /// What `station` says of each of `entries`' tasks: its `task.get` answer, or its refusal, or null when it was not
  /// reached. In one request while `batched`; `unbatch` when the station is from before that (it refuses it).
  private async states(station: string, workspace: Json, entries: Json[], batched: boolean, unbatch: () => void): Promise<Got[]> {
    const ref = (e: Json) => ({ session: field(e, "session"), key: field(e, "key") });
    if (batched) {
      try {
        const out: Got[] = [];
        for (let i = 0; i < entries.length; i += GETS_MAX) {
          const part = entries.slice(i, i + GETS_MAX);
          const answer = await this.ask(station, { method: "task.gets", workspace, tasks: part.map(ref) });
          const tasks = field(answer, "tasks");
          if (!Array.isArray(tasks) || tasks.length !== part.length) throw new Refused("task.gets is not answered there");
          for (const t of tasks) out.push(typeof field(t, "error") === "string" ? { refused: text(t, "error") } : { result: field(t, "result") });
        }
        return out;
      } catch (error) {
        if (!(error instanceof Refused)) return entries.map(() => null);
        unbatch();
      }
    }
    return Promise.all(
      entries.map(async (e): Promise<Got> => {
        try {
          return { result: await this.ask(station, { method: "task.get", workspace, ...ref(e) }) };
        } catch (error) {
          return error instanceof Refused ? { refused: error.message } : null;
        }
      }),
    );
  }

  /// One round's answer about the task of `entry` (the record at `path`): what it said on the way and how it ended told
  /// its session; what comes of it (`Outcome`).
  private async settle(path: string, entry: Json, got: Got): Promise<Outcome> {
    if (got === null) return "again";
    const now = this.store.now();
    if (typeof entry.since !== "number") {
      entry.since = now;
      try {
        writeJson(path, entry);
      } catch {}
    }
    const result = "result" in got ? got.result : null;
    // Never started there (its prepare or start did not get through, and the agent went on with another key): followed
    // for good, every 5 s, by the dozen on a loaded station (2026-10-21, ccvm's 90 to Studio). Given up on, said once.
    const unknown = "refused" in got && /unknown task/.test(got.refused);
    if (unknown || (result !== null && field(result, "job") === null)) {
      if (now - entry.since < GIVE_UP_MS) return { at: entry.since + GIVE_UP_MS };
      const why = unknown ? "that station does not know it" : "it is prepared there but was never started";
      const message = `Remote task ${text(entry, "key")} on ${text(entry, "station")}: ${why} ${GIVE_UP_MS / 60_000} minutes after its start was asked for, and is no longer followed. Ask with get, or prepare and start it again.`;
      try {
        await this.notify(text(entry, "session"), message);
      } catch {
        return "again";
      }
      entry.delivered = true;
      entry.lost = true;
      try {
        writeJson(path, entry);
      } catch {}
      return "over";
    }
    if (result === null) return "again";
    const state = text(field(result, "job"), "state");
    const notices = field(result, "notices");
    const finished = state !== "" && state !== "running";
    // What the task was to bring back, and what it changed of its directory, comes before its end is told (once).
    if (finished && entry.brought === undefined && (Array.isArray(entry.back) || typeof entry.dir === "string")) {
      try {
        entry.brought = await this.bringBack(entry);
      } catch (error) {
        if (error instanceof Unreached) return "again";
        entry.brought = { error: (error as Error).message };
      }
      try {
        writeJson(path, entry);
      } catch {}
    }
    if (finished && entry.brought !== undefined && typeof result === "object") result.back = entry.brought;
    if (finished || (Array.isArray(notices) && notices.length > 0 && !isDeepStrictEqual(field(entry, "notices"), notices))) {
      const message = `Remote task ${text(entry, "key")} on ${text(entry, "station")}: ${JSON.stringify(result)}`;
      let told = true;
      try {
        await this.notify(text(entry, "session"), message);
      } catch {
        told = false;
      }
      if (!told) return "again";
      entry.notices = notices;
      entry.delivered = finished;
      try {
        writeJson(path, entry);
      } catch {}
    }
    return finished ? "over" : "wait";
  }

  /// A file of a task's station (`request`'s path) to `path` here, whole after one answer (a station from before answers
  /// a chunk, and is asked for each); its size. An existing file is replaced only when `replace`.
  private async download(ask: (request: Json) => Promise<Json>, request: Json, path: string, replace: boolean): Promise<number> {
    if (!replace && existsSync(path)) throw new Error("local output already exists; choose another path");
    const temp = withExtension(path, `${randomBytes(8).toString("hex")}.part`);
    // Written off the station's thread: each chunk, and the whole flushed to the disk (a task's files brought back held
    // it 3 s so on a machine short of memory, 2026-10-25).
    const file = await open(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o666);
    try {
      let size: number;
      try {
        let offset = 0;
        for (;;) {
          const answer = await this.bulk.run(async () => {
            const got = await ask({ ...request, method: "file.get", offset, whole: true });
            const bytes = bytesOf(got);
            if (bytes !== null) offset += await writeBytes(file, bytes, offset, MAX_FILE);
            return got;
          });
          if (bytesOf(answer) !== null) {
            if (offset !== asU64(field(answer, "size"))) throw new Error("the file did not all come");
            await file.sync();
            size = offset;
            break;
          }
          const data = fromBase64(text(answer, "data"));
          if (data.length > CHUNK || offset + data.length > MAX_FILE) throw new Error("invalid file response");
          for (let at = 0; at < data.length; ) at += (await file.write(data, at, data.length - at)).bytesWritten;
          offset += data.length;
          if (field(answer, "eof") === true) {
            await file.sync();
            size = offset;
            break;
          }
          if (data.length === 0) throw new Error("file transfer made no progress");
        }
      } finally {
        await file.close();
      }
      if (replace) await rename(temp, path);
      else await link(temp, path);
      return size;
    } finally {
      await rm(temp, { force: true });
    }
  }

  /// A file of a task's station in memory; null when it is bigger than `limit`.
  private async fetchFile(ask: (request: Json) => Promise<Json>, path: string, limit: number): Promise<Buffer | null> {
    const parts: Buffer[] = [];
    for (let offset = 0; ; ) {
      const got = await this.bulk.run(async () => {
        const answer = await ask({ method: "file.get", path, offset, whole: true });
        const bytes = bytesOf(answer);
        const size = asU64(field(answer, "size")) ?? 0;
        if (size > limit) {
          if (bytes !== null) await stopBytes(bytes);
          return null;
        }
        if (bytes === null) return { data: fromBase64(text(answer, "data")), eof: field(answer, "eof") === true };
        const data = await readBytes(bytes, limit);
        if (offset + data.length !== size) throw new Error("the file did not all come");
        return { data, eof: true };
      });
      if (got === null) return null;
      parts.push(got.data);
      offset += got.data.length;
      if (got.eof) return Buffer.concat(parts);
      if (got.data.length === 0) throw new Error("file transfer made no progress");
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
    const dest = join(row.workspace, "station-back", portableComponent(key));
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

  /// The sync of a directory to a station (`id`) for task `key`: the one under way, or ended and not yet taken, when it
  /// is that task's; otherwise a new one, begun once the one before it (another task's) has ended.
  private syncOf(id: string, key: string, sync: () => Promise<Synced | null>): Syncing {
    const was = this.syncs.get(id);
    if (was !== undefined && was.key === key && (was.endedAt === null || this.store.now() - was.endedAt < SYNC_KEPT_MS)) return was;
    const before = was === undefined ? Promise.resolve() : was.result.then(() => undefined, () => undefined);
    const now: Syncing = { key, result: before.then(sync), endedAt: null };
    const ended = () => void (now.endedAt = this.store.now());
    now.result.then(ended, ended);
    this.syncs.set(id, now);
    return now;
  }

  /// What the station_* tools do, as `session`: among the stations of its workspace.
  async tool(tool: string, session: string, args: Json): Promise<Json> {
    const row = this.store.getSession(session);
    if (!row) throw new Error("unknown session");
    const workspace = this.workspace(row.ws ?? null);
    const station = await this.stationNamed(workspace, text(args, "station"));
    if (tool === "station_list") {
      if (station === "") return this.listStations(workspace);
      return detailed(station === this.ownId() ? await this.describe() : await this.ask(station, { method: "describe", workspace }));
    }
    const key = text(args, "key");
    const listing = tool === "station_task" && field(args, "action") === "list";
    if (station === "" || (key === "" && !listing)) throw new Error("station and key are required (list needs only station)");
    if (!listing) this.recordUse(workspace, session, station);
    const request: Json = { workspace, session, key };
    if (tool === "station_task") {
      const action = text(args, "action");
      if (!["prepare", "start", "get", "log", "stop", "list"].includes(action)) throw new Error("unknown task action");
      request.method = `task.${action}`;
      request.lines = field(args, "lines");
      request.spec = { name: field(args, "name"), command: field(args, "command"), requestedBy: row.createdBy };
      // Said only when so: a task prepared before keeps the same inputs.
      if (field(args, "screen") === true) request.spec.screen = true;
      // A task's directory and what it brings back, as this station has them (remote/prepared).
      const preparedName = `${hash([workspace, session, station, key])}.json`;
      const prepared = join(this.preparedDir(session), preparedName);
      if (action === "prepare") {
        const dir = field(args, "dir");
        const back = field(args, "back");
        if (dir !== null) {
          if (typeof dir !== "string" || !isAbsolute(dir)) throw new Error("dir must be an absolute path on this machine");
          // The station reads it itself as it syncs: in a folder macOS protects, only when it may (looked at off its
          // thread, ops/places.ts), never held on a prompt.
          try {
            await this.places.directory(dir, { lang: "en", agent: true, self: true });
          } catch (e) {
            if (e instanceof PlaceRefused && (e.code === "gone" || e.code === "not_a_directory")) throw new Error(`${dir} is not a directory`);
            throw e;
          }
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
        if (dir !== null || back !== null) {
          mkdirSync(this.preparedDir(session), { recursive: true });
          writeJson(prepared, { workspace, session, station, key, dir: request.spec.dir ?? null, back: request.spec.back ?? null });
        }
        return answer;
      }
      let synced: Synced | null = null;
      if (action === "start") {
        let local: Json = null;
        try {
          local = readJson(prepared);
        } catch {
          // Not moved into its session's directory yet (movePrepared).
          try {
            local = readJson(join(this.root, "prepared", preparedName));
          } catch {}
        }
        if (typeof local?.dir === "string") {
          const dir: string = local.dir;
          const id = hash([workspace, session, station, dir]);
          const sync = this.syncOf(id, key, () =>
            syncDir((method, more) => this.ask(station, { workspace, session, key, method, ...more }), dir, () => this.store.now(), this.bulk),
          );
          const got = await this.bounded(sync.result, SYNC_ANSWER_MS);
          if (got === null) {
            return {
              key,
              syncing: true,
              dir: local.dir,
              note: `${local.dir} is still being synced to ${station}; nothing was started yet. Call start again with the same key: it waits on this sync rather than beginning another`,
            };
          }
          // Taken: the next start of this task syncs anew.
          if (this.syncs.get(id) === sync) this.syncs.delete(id);
          try {
            if ("error" in got) throw got.error;
            synced = got.ok;
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
          writeJson(path, { workspace, session, station, key, delivered: false, since: this.store.now(), ...more });
        }
        // Its station tells this one when it changes (`task.changed`), naming this record.
        request.push = basename(path, ".json");
      }
      try {
        const answer = await this.ask(station, request);
        // A station from before `task.changed` is asked about it every 5 s.
        if (action === "start" && field(answer, "push") !== true) this.watch(this.outgoing(workspace, session, station, key));
        return synced === null ? answer : { ...answer, sync: synced };
      } catch (error) {
        // An uncertain start: asked about once its station would have started it (it says something before if it did).
        if (action === "start" && !(error instanceof Refused)) {
          const path = this.outgoing(workspace, session, station, key);
          this.later(path, (asI64(field(readJson(path), "since")) ?? this.store.now()) + GIVE_UP_MS);
        }
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
        // Whole, after one request; to a station from before, in chunks.
        try {
          await this.bulk.run(() => this.ask(station, withBytes({ ...request, method: "file.put", offset: 0, size }, fileBytes(path, 0, size))));
          return { uploaded: path, bytes: size };
        } catch (error) {
          if (!(error instanceof NoBytes)) throw error;
        }
        let offset = 0;
        for (;;) {
          const chunk = Buffer.alloc(CHUNK);
          const n = readSync(fd, chunk, 0, CHUNK, offset);
          request.method = "file.put";
          request.offset = offset;
          request.data = chunk.subarray(0, n).toString("base64");
          request.final = offset + n === size;
          await this.bulk.run(() => this.ask(station, { ...request }));
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

/// Tasks of peers no longer in the workspace, or no longer allowed, stop: looked at whenever the roster or the config
/// changes.
export function followRoster(cloud: Cloud, remote: Remote, config: { listen(f: () => void): () => void }): () => void {
  const look = () => {
    const rosters = cloud.memberships().map((m) => ({ workspace: m.workspace, peers: m.peers.flatMap((p) => (typeof p?.id === "string" ? [p.id as string] : [])) }));
    void remote
      .revoke(rosters, cloud.peersCurrent)
      .catch((error) => log.warn("peer", "revoking tasks failed", { error: (error as Error).message }));
  };
  look();
  const unlisten = cloud.listen(look);
  const unconfig = config.listen(look);
  return () => (unlisten(), unconfig());
}
