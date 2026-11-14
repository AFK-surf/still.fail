// Tasks on other stations of the workspace. Workspace peers call named operations over an
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
// nothing asks about a task while nothing happens to it; one on a station from before that is not followed (its session is told).
// What is retried (a request that did not get through, a closed session's stations every 60 s) and the hourly sweep
// are Effect schedules; nothing here polls local state.
import { createHash, randomBytes } from "node:crypto";
import { constants, createReadStream, lstatSync, mkdirSync, readFileSync, renameSync } from "node:fs";
import { access, appendFile, link, lstat, mkdir, open, readFile, readdir, readlink, rename, rm, stat, writeFile } from "node:fs/promises";
import { createInterface } from "node:readline";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { DISK_LOW_BYTES, diskFree } from "../ops/disk.ts";
import { portableComponent, relativeParts } from "../ops/paths.ts";
import { PlaceRefused, Places } from "../ops/places.ts";
import { platform } from "../platform/index.ts";
import { isDeepStrictEqual } from "node:util";
import { Clock, Duration, Effect, Exit, FiberSet, Schedule, Scope } from "effect";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { type Cloud, UNPROTECTED } from "../cloud/state.ts";
import { type Json, type Store } from "../store/store.ts";
import { type Jobs, jobJson, tail } from "./jobs.ts";
import { detailed, summary } from "./load.ts";
import { type Inbox, MESH_WAIT_MS, NoBytes, NoLink, type PeerCall, PeerBus, Refused, bytesOf, withBytes } from "../mesh/bus.ts";
import { version as runningVersion } from "../ops/version.ts";
import { fileBytes, readBytes, stopBytes, writeBytes } from "../mesh/files.ts";
import { Bulk, LINK, PACKED, type Synced, actual, apply, listed, page, patchOf, planPart, putBlobs, readManifest, syncDir, writeManifest } from "./dirsync.ts";
import { DEFAULT_LIMIT, WorkspaceReader } from "./workspace-size.ts";
import { SANDBOX, type Sandbox, ensureIdentity, sandboxDescribed } from "../agents/sandbox.ts";

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
/// A request that did not get through (`task.changed` to the source, `task.get` after it) is asked again after 1 s,
/// then twice as long each time, at most a minute apart.
const AGAIN = Schedule.min([Schedule.exponential("1 second"), Schedule.spaced("1 minute")]);
const CLOSE_EVERY = "60 seconds";
const SWEEP_EVERY = "1 hour";
/// A task its station does not know, or has not started, this long after its start was asked for is no longer followed.
export const GIVE_UP_MS = 10 * 60_000;
/// A mirror (a task's `dir` on the target) no task of its session has run in or synced for this long goes, with what
/// its tasks made there; the next start syncs it anew. Chats made one for each worktree and kept them all: 204 of
/// one session's, enough to fill the station's disk in hours (2026-10-20).
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
  /// Remove a mirror's tree. Tests can hold or fail the removal to exercise interrupted requests.
  removeMirror?: (path: string) => Promise<void>;
  /// How a closed session's task directory is removed (tests hold it to come between).
  removeTask?: (path: string) => Promise<void>;
  /// This station's version as `describe` says it (ops/version.ts; tests say theirs).
  version?: string;
  /// The last completed cleanup of files brought back. Tests can keep this across station restarts in memory.
  backTidy?: { read: () => Promise<number | null>; write: (at: number) => Promise<void> };
};

/// A start that syncs a directory answers within this, synced or not (the sync goes on): an agent's tool call is given
/// up on after a minute, and the agent asking again (the same key) began another sync over the first, which the target
/// then refused as over, again and again (2026-10-19). Asked again, the start takes up the sync under way.
export const SYNC_ANSWER_MS = 40_000;
/// A sync that ended while no start waited for it is what the next start of its task gets, this long after.
const SYNC_KEPT_MS = 10 * 60_000;
/// A large mirror can take longer than the peer transport's 30-second answer limit to remove.
const CLEAN_ANSWER_MS = 1000;
const CLEAN_KEPT_MS = 10 * 60_000;

/// A directory's sync to a station, for one task: the start that began it, and later ones of the same task, wait on it.
type Syncing = { key: string; result: Promise<Synced | null>; endedAt: number | null };
type Cleaning = { result: Promise<Json>; endedAt: number | null };
type IncomingTask = { dir: string; meta: Json };

/// The requests about tasks that only read what is here: answered as they come, never after another one (`lanes`).
const READS = new Set(["task.get", "task.gets", "task.log", "task.list", "session.size"]);
/// The tasks a source asks about at once (`task.gets`), at most.
export const GETS_MAX = 200;

/// station_list asks every station of the workspace at once and lists one that has not answered within this as
/// unanswered: not as offline, which it does not know (2026-11-14: one up and updating itself, asked by a station whose
/// relay was at 8 s, was listed offline and its person told so).
export const LIST_WAIT_MS = 2000;
/// station_list {station} waits this long for the one station asked before it says it did not answer.
export const LIST_ALONE_WAIT_MS = 10_000;
/// A station asked how busy it is (`describe`'s `load`) says it does not know when measuring takes longer than this.
export const LOAD_WAIT_MS = 1000;

/// What station_list says of a station asked `describe` (`got`, null when it did not answer within LIST_WAIT_MS), its
/// version as the roster has it being `seen`: offline only where no link to it would open (NoLink); otherwise it
/// did not answer, which says nothing of whether it is up. Its version is the one it says itself; the roster's copy,
/// what still.fail cloud listed when it last told this station its stations (it is not told again as a station
/// updates), is `version_seen`, never its version now. One from before says none in `describe`: it keeps the copy.
function heard(got: { ok: Json } | { error: Error } | null, seen: Json): Json {
  const copy = typeof seen === "string" ? { version_seen: seen } : {};
  if (got === null) return { ...copy, unanswered: `did not answer within ${LIST_WAIT_MS / 1000} s; not known to be offline: ask it alone` };
  if ("error" in got) {
    const { error } = got;
    if (error instanceof Refused) return { ...copy, refused: error.message };
    if (error instanceof NoLink) return { ...copy, offline: error.message };
    return { ...copy, unanswered: `${error.message}; not known to be offline: ask it alone` };
  }
  const says = field(got.ok, "version");
  return { ...(typeof says === "string" ? { version: says } : copy), load: summary(field(got.ok, "load")) };
}

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

/// What chats used of other stations' workspaces (`usedPath`), as last written or read here: what `workspaceTargets`
/// says of every chat shown, again and again, read from the disk each time on the station's thread, 16 of them held it
/// 2.5 s on a station short of memory (2026-11-03), and `recordUse` at each of their tool calls. Written only by this station
/// (`writeJson` keeps it current); null: none written.
const used = new Map<string, Json | null>();

/// How many times each record was written here (`writeJson`): one read before a write is not kept after it.
const writes = new Map<string, number>();

/// Every chat's record read in, off the station's thread, as the station starts: read on it as each chat is first
/// shown after every update, the reads can hold up its other work.
async function readAllUsed(dir: string): Promise<void> {
  for (const name of await readdir(dir).catch(() => [] as string[])) {
    if (!name.endsWith(".json")) continue;
    const path = join(dir, name);
    if (used.has(path)) continue;
    const before = writes.get(path) ?? 0;
    let read: Json | null;
    try {
      read = JSON.parse(await readFile(path, "utf8"));
    } catch {
      continue;
    }
    if (!used.has(path) && (writes.get(path) ?? 0) === before) used.set(path, read);
  }
}

/// A chat's record (null: none), not to be changed in place: a copy is written (`writeJson`).
function readUsed(path: string): Json | null {
  const kept = used.get(path);
  if (kept !== undefined) return kept;
  let read: Json | null;
  try {
    read = readJson(path);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    read = null;
  }
  used.set(path, read);
  if (used.size > 4096) used.delete(used.keys().next().value!);
  return read;
}

/// How long what a task brought back is kept once nothing in it changed (`tidyBack`), and how often that is looked at.
const BACK_KEPT_MS = 6 * 3600_000;
const BACK_TIDY_MS = 3600_000;

/// When anything under `path` last changed (its own time for a file), off the thread; Infinity where it cannot be said
/// (kept).
async function latestIn(path: string): Promise<number> {
  let st;
  try {
    st = await stat(path);
  } catch {
    return Infinity;
  }
  if (!st.isDirectory()) return st.mtimeMs;
  let latest = st.mtimeMs;
  for (const name of await readdir(path).catch(() => null) ?? [""]) {
    if (name === "") return Infinity;
    latest = Math.max(latest, await latestIn(join(path, name)));
    if (latest === Infinity) return latest;
  }
  return latest;
}

/// readJson off the station's thread (fs/promises): what is read again on a schedule, or all the records at once. Read
/// after what was asked to be written of it before (`writeJson`).
const readJsonSoon = async (path: string): Promise<Json> => {
  await written(path);
  return JSON.parse(await readFile(path, "utf8"));
};

/// Path::with_extension: the file name's extension replaced (or added).
function withExtension(path: string, ext: string): string {
  const name = basename(path);
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  return join(dirname(path), `${stem}.${ext}`);
}

/// Each record's writes, in the order they were asked (`writeJson`, `updateJson`): one written before another is never
/// renamed over by it.
const writing = new Map<string, Promise<unknown>>();

function inTurn<T>(path: string, work: () => Promise<T>): Promise<T> {
  const mine = (writing.get(path) ?? Promise.resolve()).then(work, work);
  const tail = mine.catch(() => undefined);
  writing.set(path, tail);
  void tail.then(() => {
    if (writing.get(path) === tail) writing.delete(path);
  });
  return mine;
}

/// Once what was asked of `path` before is written (or failed).
export async function written(path: string): Promise<void> {
  await writing.get(path);
}

/// `json` written whole or not at all, off the station's thread: a private temporary file, synced, renamed over. The
/// sync was the main thread's, every remote tool call's: on a disk kept busy, 1,600 of them held it 3 minutes on a
/// station (2026-11-06).
async function writeWhole(path: string, json: string): Promise<void> {
  const temp = withExtension(path, `${randomBytes(8).toString("hex")}.tmp`);
  const file = await open(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
  try {
    await file.writeFile(json);
    await file.sync();
  } finally {
    await file.close();
  }
  await rename(temp, path);
}

/// `value` as a record, written in its turn (`writeWhole`); what this station's reads keep of it (`readUsed`) is the new
/// one from now.
export function writeJson(path: string, value: Json): Promise<void> {
  const json = JSON.stringify(value);
  writes.set(path, (writes.get(path) ?? 0) + 1);
  if (used.has(path)) used.set(path, JSON.parse(json));
  return inTurn(path, () => writeWhole(path, json));
}

/// A record read after what was written of it before, changed by `edit` and written in its turn: what `edit` gives is
/// written (undefined: nothing; null: the record removed). False when it could not be read; one not there is `missing`
/// where that is given.
export function updateJson(path: string, edit: (v: Json) => Json | null | undefined, missing?: Json): Promise<boolean> {
  return inTurn(path, async () => {
    let v: Json;
    try {
      v = JSON.parse(await readFile(path, "utf8"));
    } catch (error) {
      if (missing === undefined || (error as NodeJS.ErrnoException).code !== "ENOENT") return false;
      v = structuredClone(missing);
    }
    const next = edit(v);
    if (next === undefined) return true;
    writes.set(path, (writes.get(path) ?? 0) + 1);
    if (next === null) {
      used.delete(path);
      await rm(path, { force: true });
      return true;
    }
    const json = JSON.stringify(next);
    if (used.has(path)) used.set(path, JSON.parse(json));
    await writeWhole(path, json);
    return true;
  });
}

const isLink = (path: string): Promise<boolean> => lstat(path).then((st) => st.isSymbolicLink(), () => false);

/// Whether `path` is there, asked off the station's thread.
const there = (path: string): Promise<boolean> => access(path).then(() => true, () => false);

/// Relative paths only; transfers must not follow links planted by a task. Task commands themselves are trusted shell
/// execution, so separate working directories are organizational isolation, not an OS security boundary. Its links
/// looked at off the station's thread.
export async function filePath(root: string, relative: string, create: boolean): Promise<string> {
  if ((await lstat(root)).isSymbolicLink()) throw new Error("transfer root is a symbolic link");
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
    if (await isLink(out)) throw new Error("file path contains a symbolic link");
  }
  if (create) await mkdir(dirname(out), { recursive: true });
  return out;
}

/// `filePath` on this thread, for a sync's application (dirsync.ts `apply`), which writes every file it sets so.
export function filePathHere(root: string, relative: string, create: boolean): string {
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
    if (isLinkHere(out)) throw new Error("file path contains a symbolic link");
  }
  if (create) mkdirSync(dirname(out), { recursive: true });
  return out;
}

const isLinkHere = (path: string): boolean => {
  try {
    return lstatSync(path).isSymbolicLink(); // sync: dirsync's apply (`filePathHere`), not moved in this change
  } catch {
    return false;
  }
};

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
  /// One bounded queue for both this station's workspaces and those of other stations' tasks.
  readonly workspaceReader: WorkspaceReader;
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
  /// asked again into the same line (2026-10-21, one test host for another: a 1 KB file synced in 61 s).
  private lanes = new Map<string, Promise<unknown>>();
  /// When each source session's room was last used here (`seen`), as its record says once written.
  private seenAt = new Map<string, number>();
  /// The closing sessions whose stations are being asked to remove their directories.
  private watching = new Set<string>();
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
  /// A requested mirror removal survives a short answer and is taken up by the next identical request.
  private cleans = new Map<string, Cleaning>();
  /// Incoming task owners do not change. Keep them by session so each session's cleanup does not read every other
  /// session's task records. The directory's timestamps detect additions/removals, including across a handover.
  private taskOwners = new Map<string, string>();
  private ownerTasks = new Map<string, Set<string>>();
  private unreadableTasks = new Set<string>();
  private incomingStamp: string | null = null;
  private readingIncoming: Promise<void> | null = null;
  private scope: Scope.Closeable;
  private run: (effect: Effect.Effect<void>) => Promise<void>;
  private diskFree: (path: string) => number;
  private removeMirror: (path: string) => Promise<void>;
  private described: ((peer: string, workspace: string) => Json) | null = null;
  private version: string;
  private rigs: ((workspace: string, session: string, rig: Json, described: Json | null) => Promise<Json>) | null = null;
  /// This station's sandboxes (config.json's `sandboxes`, agents/sandbox.ts): stations of a kind of their own for
  /// station_task, named `sandbox:<name>`, whose tasks this station takes itself and runs there.
  private sandboxes: (() => Sandbox[]) | null = null;
  private removeTask: (path: string) => Promise<void>;

  constructor(options: RemoteOptions) {
    this.data = options.data;
    this.version = options.version ?? runningVersion();
    this.store = options.store;
    this.workspaceReader = new WorkspaceReader(() => this.store.now());
    this.jobs = options.jobs;
    this.notify = options.notify;
    this.places = options.places ?? new Places();
    this.diskFree = options.diskFree ?? diskFree;
    this.removeMirror = options.removeMirror ?? ((path) => rm(path, { recursive: true, force: true }));
    this.removeTask = options.removeTask ?? ((path) => rm(path, { recursive: true, force: true }));
    this.root = join(options.data, "remote");
    for (const name of ["incoming", "outgoing", "sessions", "used", "prepared"]) mkdirSync(join(this.root, name), { recursive: true }); // sync: once, as it is made
    void readAllUsed(join(this.root, "used"));
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
    const tidiedAt = join(this.root, "back-tidied.json");
    this.startBackTidying(options.backTidy ?? {
      read: async () => {
        try {
          const at: unknown = JSON.parse(await readFile(tidiedAt, "utf8"));
          return typeof at === "number" && Number.isSafeInteger(at) && at >= 0 ? at : null;
        } catch { return null; }
      },
      write: async (at) => { await writeFile(tidiedAt, JSON.stringify(at)); },
    });
    this.bus = options.bus ?? new PeerBus({ waitMs: options.meshWaitMs ?? MESH_WAIT_MS, sleep: (ms) => this.run(Effect.sleep(Duration.millis(ms))).catch(() => undefined) });
    // What this answers: how this station is and what it takes, and the tasks (whatever no other part answers).
    this.bus.on("describe", (peer, _request, workspace) => this.describe(peer, workspace ?? ""));
    this.bus.otherwise((peer, request, workspace) => {
      const ws = workspace ?? "";
      const method = text(request, "method");
      if (method === "task.clean") return this.cleanRequest(ws, peer, request);
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
  /// station's thread (every task's ever started from here is kept: many on a station, read at each start).
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
        entry = await readJsonSoon(path);
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
      await updateJson(record, (now) => ({ ...now, pushed: said })).catch(() => undefined);
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
      // Off the station's thread: a task's station tells this at each change.
      entry = await readJsonSoon(path);
    } catch {
      throw new Error("unknown task");
    }
    // Only what the task's own station says is taken (`check` asks that one), so this need not be from it.
    if (text(entry, "workspace") !== workspace) throw new Error("unknown task");
    this.check(path);
    return { taken: true };
  }

  /// Schedule the cleanup across station restarts, remembering each completed sweep.
  private startBackTidying(record: NonNullable<RemoteOptions["backTidy"]>): void {
    // Updates can restart the station more often than this hourly cleanup. Remember the last completed sweep, so a new
    // process waits only for what remains of the hour. A missing or unreadable record means it should sweep now.
    const delay = Effect.promise(async () => {
      const last = await record.read().catch(() => null);
      return last === null ? 0 : Math.min(BACK_TIDY_MS, Math.max(0, last + BACK_TIDY_MS - this.store.now()));
    });
    const tidy = Effect.promise(async () => {
      try {
        if (this.stopped) return;
        await this.tidyBack();
        // An interrupted sweep must be tried again by the next station, not recorded as complete.
        if (!this.stopped) await record.write(this.store.now());
      } catch (error) {
        log.warn("remote", "could not clean brought-back files", { error: String(error) });
      }
    });
    void this.run(delay.pipe(
      Effect.flatMap((ms) => Effect.sleep(Duration.millis(ms))),
      Effect.andThen(tidy.pipe(Effect.repeat(Schedule.spaced("1 hour")))),
      Effect.asVoid,
    )).catch(() => undefined);
  }

  /// What tasks brought back (`station-back/<key>` of each session's workspace in use) let go of once nothing in it
  /// changed for BACK_KEPT_MS: kept indefinitely, these files can fill the disk. Off the station's thread.
  private async tidyBack(): Promise<void> {
    const now = wall.now();
    for (const row of this.store.liveSessions()) {
      if (this.stopped) return;
      const back = join(row.workspace, "station-back");
      for (const name of await readdir(back).catch(() => [] as string[])) {
        const dir = join(back, name);
        if ((await latestIn(dir)) < now - BACK_KEPT_MS) await rm(dir, { recursive: true, force: true }).catch(() => undefined);
      }
    }
  }

  /// Its schedules end (the station stops).
  async close(): Promise<void> {
    this.stopped = true;
    this.workspaceReader.close();
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }

  private list(dir: string): Promise<string[]> {
    return readdir(dir).catch(() => [] as string[]);
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
    const now = this.store.now();
    // Used within the minute: noted already (its record's write may still be on its way: `closeHere` asks this too).
    const last = this.seenAt.get(room);
    if (last !== undefined && now - last < 60_000) return join(room, "work");
    mkdirSync(join(room, "work"), { recursive: true }); // sync: work() gives the directory at once; once a minute a room
    this.seenAt.set(room, now);
    void writeJson(join(room, "session.json"), { workspace, station: peer, session, seen: now }).catch(() => undefined);
    return join(room, "work");
  }

  /// The directory in a session's that mirrors the source's `dir` (its last name; with a part of its hash when another
  /// directory of the source's has that name there already).
  private async mirrorName(workspace: string, peer: string, session: string, dir: string): Promise<string> {
    const last = dir.split(/[\\/]/).filter((p) => p !== "").at(-1) ?? "";
    let name = last.replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(0, 100);
    if (name === "" || name === "." || name === "..") name = "dir";
    const claimed = new Map<string, string>();
    for (const { meta } of await this.tasksOf(workspace, peer, session)) {
      if (typeof meta.mirror === "string") claimed.set(meta.mirror, text(field(meta, "spec"), "dir"));
    }
    const mirrors = join(this.room(workspace, peer, session), "mirrors");
    for (const file of await this.list(mirrors)) {
      const m = readManifest(join(mirrors, file));
      if (m !== null) claimed.set(m.name, m.dir);
    }
    const owner = claimed.get(name);
    return owner === undefined || owner === dir ? name : `${name}-${hash(dir).slice(0, 8)}`;
  }

  private forgetTask(name: string): void {
    const owner = this.taskOwners.get(name);
    if (owner !== undefined) {
      const names = this.ownerTasks.get(owner);
      names?.delete(name);
      if (names?.size === 0) this.ownerTasks.delete(owner);
      this.taskOwners.delete(name);
    }
    this.unreadableTasks.delete(name);
  }

  /// Refresh the owner index off the station's thread. Only new or previously unreadable records need reading:
  /// task.json changes as work proceeds, but its owner never does. A record re-read by a caller is still checked.
  private async indexIncoming(): Promise<void> {
    const incoming = join(this.root, "incoming");
    const stamp = async () => {
      const s = await stat(incoming, { bigint: true });
      return `${s.ino}:${s.mtimeNs}:${s.ctimeNs}`;
    };
    while (true) {
      const before = await stamp();
      if (before === this.incomingStamp && this.unreadableTasks.size === 0) return;
      const names = await readdir(incoming);
      const present = new Set(names);
      for (const name of this.taskOwners.keys()) if (!present.has(name)) this.forgetTask(name);
      for (const name of this.unreadableTasks) if (!present.has(name)) this.unreadableTasks.delete(name);
      const unread = names.filter((name) => !this.taskOwners.has(name));
      // Bound disk requests: thousands of historical tasks must not crowd out the station's other I/O.
      for (let i = 0; i < unread.length; i += 32) {
        const batch = unread.slice(i, i + 32);
        const records = await Promise.all(batch.map((name) => readJsonSoon(join(incoming, name, "task.json")).catch(() => null)));
        batch.forEach((name, j) => {
          const meta = records[j];
          if (meta === null) {
            // A directory can exist before its record is written, even across a station handover. Try it again.
            this.unreadableTasks.add(name);
            return;
          }
          const owner = JSON.stringify([text(meta, "workspace"), text(meta, "station"), text(meta, "session")]);
          this.taskOwners.set(name, owner);
          const owned = this.ownerTasks.get(owner) ?? new Set<string>();
          owned.add(name);
          this.ownerTasks.set(owner, owned);
          this.unreadableTasks.delete(name);
        });
      }
      const after = await stamp();
      if (before === after) {
        this.incomingStamp = after;
        return;
      }
      // Something arrived or went while reading. Reconcile it before using the index for a cleanup decision.
      this.incomingStamp = null;
    }
  }

  /// Task records (incoming/<id>) of a source session. Multiple lookups share a refresh; records themselves are
  /// read afresh so a removed or changed record is never taken solely from the index.
  private async tasksOf(workspace: string, peer: string, session: string): Promise<IncomingTask[]> {
    const reading = this.readingIncoming ??= this.indexIncoming();
    try {
      await reading;
    } finally {
      if (this.readingIncoming === reading) this.readingIncoming = null;
    }
    const owner = JSON.stringify([workspace, peer, session]);
    const names = [...(this.ownerTasks.get(owner) ?? [])];
    const found: IncomingTask[] = [];
    for (let i = 0; i < names.length; i += 32) {
      const dirs = names.slice(i, i + 32).map((name) => join(this.root, "incoming", name));
      const records = await Promise.all(dirs.map((dir) => readJsonSoon(join(dir, "task.json")).catch(() => null)));
      records.forEach((meta, j) => {
        if (meta !== null && text(meta, "workspace") === workspace && text(meta, "station") === peer && text(meta, "session") === session) {
          found.push({ dir: dirs[j]!, meta });
        }
      });
    }
    return found;
  }

  private jobOf(task: string): string {
    return `remote_${basename(task)}`;
  }

  /// What a task waiting in the queue is told of it: its place, what blocks it, and the measured machine's capacity.
  private async queued(jobId: string, readLoad: () => Promise<Json> = () => this.measuredLoad()): Promise<Json> {
    let q = this.jobs.queueOf(jobId);
    if (q === null) return {};
    const load = await readLoad();
    // It may have started while the host was being read; do not return its old queued state.
    q = this.jobs.queueOf(jobId);
    if (q === null) return {};
    const why =
      q.why === "memory" ? "the machine's memory is under pressure"
      : q.why === "screen" ? q.holder !== undefined ? `the screen is held by ${q.holder}` : "the screen is held or an earlier request is waiting for it"
      : q.why === "person" ? "a person is using this machine's screen (its input not idle): no task is given it meanwhile"
      : q.why === "small" ? "another small task is using the station's small-work slot"
      : "it is waiting for its turn";
    return { queue: { ...q, load, note: `Waiting in this station's queue (${q.place === 1 ? "next" : `number ${q.place}`}): ${why}. It starts by itself when there is room; you are told when it ends, as for any task.` } };
  }

  private running(task: string): boolean {
    return this.store.getJob(this.jobOf(task))?.state === "running";
  }

  /// Stops a source session's tasks and removes their records and its shared directory. Callers are in its lane.
  private async closeHere(workspace: string, peer: string, session: string, idleAt?: number): Promise<boolean> {
    const tasks = await this.tasksOf(workspace, peer, session);
    const room = this.room(workspace, peer, session);
    // work() can be called outside the task lane, at any await below. An idle room goes with its tasks' directories in
    // one synchronous step, its use (`seenAt`) and its tasks' running asked again just before: a use that comes after
    // finds neither and makes its room anew, none of what it makes removed; a room used before it stays whole.
    const gone = (path: string) => `${path}.gone-${randomBytes(4).toString("hex")}`;
    const aside: string[] = [];
    if (idleAt !== undefined) {
      let seen: number;
      try {
        seen = Math.max(asI64(field(await readJsonSoon(join(room, "session.json")), "seen")) ?? idleAt, this.seenAt.get(room) ?? 0);
      } catch {
        return false;
      }
      if (idleAt - seen < IDLE_MS || (this.seenAt.get(room) ?? 0) > seen || tasks.some(({ dir }) => this.running(dir))) return false;
      for (const { dir } of tasks) {
        const to = gone(dir);
        try {
          renameSync(dir, to); // sync: the tasks' directories and the room go in one step after their use is asked again
          aside.push(to);
        } catch {}
      }
    } else {
      for (const { dir } of tasks) {
        if (this.running(dir)) await this.jobs.stop(this.jobOf(dir));
        await this.removeTask(dir);
      }
    }
    // Taken out of its place in one step, then removed off the thread (a session's whole directory, gigabytes of
    // mirrors: removed on the main thread, one held it 15 s on a station, 2026-11-02). A use after this makes it anew.
    const roomGone = gone(room);
    let moved = false;
    try {
      renameSync(room, roomGone); // sync: in the same step as its tasks' directories (idle), so that no work() comes between
      moved = true;
    } catch {}
    this.seenAt.delete(room);
    for (const dir of aside) await this.removeTask(dir).catch(() => undefined);
    if (moved) {
      log.info("remote", "remote session directory removed", { workspace, station: peer, session });
      await rm(roomGone, { recursive: true, force: true }).catch(() => undefined);
    }
    return true;
  }

  /// The target's own cleanup: a source session's directory unused for IDLE_MS, with nothing running, goes; so do task
  /// directories from before shared session directories.
  async sweep(now: number): Promise<void> {
    const sessions = join(this.root, "sessions");
    for (const name of await readdir(sessions).catch(() => [] as string[])) {
      if (this.stopped) return;
      let meta: Json;
      try {
        await written(join(sessions, name, "session.json"));
        meta = await readJsonSoon(join(sessions, name, "session.json"));
      } catch {
        continue;
      }
      const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
      await this.inLane(this.room(workspace, peer, session), async () => {
        // Asked again in its lane: used meanwhile, it stays.
        let seen: number;
        try {
          await written(join(sessions, name, "session.json"));
          seen = Math.max(asI64(field(await readJsonSoon(join(sessions, name, "session.json")), "seen")) ?? now, this.seenAt.get(join(sessions, name)) ?? 0);
        } catch {
          return;
        }
        if (now - seen >= IDLE_MS) {
          try {
            if (await this.closeHere(workspace, peer, session, now)) return;
          } catch (error) {
            log.warn("remote", "idle remote session directory not removed", { error: (error as Error).message });
            return;
          }
        }
        for (const m of await this.mirrorsOf(workspace, peer, session, now)) {
          if (!m.busy && now - m.used >= MIRROR_IDLE_MS) await this.dropMirror(workspace, peer, session, m.name, "unused");
        }
      });
    }
    const incoming = join(this.root, "incoming");
    for (const name of await readdir(incoming).catch(() => [] as string[])) {
      if (this.stopped) return;
      const dir = join(incoming, name);
      const record = join(dir, "task.json");
      let meta: Json;
      try {
        meta = await readJsonSoon(record);
      } catch {
        continue;
      }
      if (field(meta, "layout") === "session") continue;
      const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
      await this.inLane(this.room(workspace, peer, session), async () => {
        let modified = now;
        try {
          // A request may have used or migrated it since it was first read.
          meta = await readJsonSoon(record);
          modified = Math.floor((await stat(record)).mtimeMs);
        } catch {
          return;
        }
        if (field(meta, "layout") === "session" || now - modified < IDLE_MS || this.running(dir)) return;
        await rm(dir, { recursive: true, force: true });
      });
    }
  }

  /// A session's mirrors on this station: when a task last ran in or synced each (one from before this is taken as
  /// used now), and whether one runs there or syncs to it now (those are marked used now).
  private async mirrorsOf(workspace: string, peer: string, session: string, now: number): Promise<{ name: string; used: number; busy: boolean }[]> {
    const room = this.room(workspace, peer, session);
    const record = join(room, "mirrors-used.json");
    // A task that ended counts as a use then: what it made is brought back after.
    const running = new Set<string>();
    const ended = new Map<string, number>();
    for (const { dir, meta } of await this.tasksOf(workspace, peer, session)) {
      const mirror = field(meta, "mirror");
      if (typeof mirror !== "string") continue;
      const job = this.store.getJob(this.jobOf(dir));
      if (job?.state === "running" || (job && meta.safe === true && meta.collected !== true)) running.add(mirror);
      if (job?.endedAt) ended.set(mirror, Math.max(ended.get(mirror) ?? 0, job.endedAt));
    }
    const mirrors = (await this.list(join(room, "mirrors"))).filter((file) => file.endsWith(".json")).map((file) => file.slice(0, -".json".length));
    const busy = new Set<string>();
    for (const name of mirrors) if (running.has(name) || (await this.syncing(join(room, "sync", name), now))) busy.add(name);
    // Read and marked in the record's turn (after what was written of it before), never over a newer use.
    let used: Json = {};
    try {
      used = await readJsonSoon(record);
    } catch {}
    const marked = mirrors.filter((name) => asI64(field(used, name)) === null || busy.has(name));
    if (marked.length > 0) {
      await updateJson(record, (kept) => ({ ...kept, ...Object.fromEntries(marked.map((name) => [name, now])) }), {}).catch(() => undefined);
      for (const name of marked) used[name] = now;
    }
    return mirrors.map((name) => ({ name, used: Math.max(asI64(field(used, name)) ?? now, ended.get(name) ?? 0), busy: busy.has(name) }));
  }

  /// A sync to a mirror is under way: its directory there, it or what is in it touched within MIRROR_RECENT_MS (one
  /// given up on is not).
  private async syncing(dir: string, now: number): Promise<boolean> {
    let latest = 0;
    for (const path of [dir, ...(await this.list(dir)).map((name) => join(dir, name))]) {
      latest = Math.max(latest, await stat(path).then((st) => st.mtimeMs, () => 0));
    }
    return now - latest < MIRROR_RECENT_MS;
  }

  /// A task ran in or synced `mirror` now. Callers are in the session's lane.
  private async usedMirror(workspace: string, peer: string, session: string, mirror: string): Promise<void> {
    const record = join(this.room(workspace, peer, session), "mirrors-used.json");
    const now = this.store.now();
    await updateJson(record, (used) => ({ ...used, [mirror]: now }), {});
  }

  /// Removes a mirror and what its tasks made in it; its tasks that have not started sync again first. Callers are
  /// in the session's lane.
  private async dropMirror(workspace: string, peer: string, session: string, mirror: string, why: string): Promise<boolean> {
    const room = this.room(workspace, peer, session);
    try {
      // If removal is interrupted, a prepared task must resync before starting even if the manifest remains.
      for (const { dir } of await this.tasksOf(workspace, peer, session)) {
        const path = join(dir, "task.json");
        // A task notification can update this record while the index is being read; keep that newer state.
        const meta = await readJsonSoon(path);
        if (meta.mirror === mirror && meta.synced === true) {
          meta.synced = false;
          await writeJson(path, meta);
        }
      }
      await this.removeMirror(join(room, "work", mirror));
      await rm(join(room, "sync", mirror), { recursive: true, force: true });
      await rm(join(room, "mirrors", `${mirror}.json`), { force: true });
      await updateJson(join(room, "mirrors-used.json"), (used) => {
        const { [mirror]: _, ...rest } = used;
        return rest;
      }).catch(() => undefined);
      log.info("remote", "remote mirror removed", { workspace, station: peer, session, mirror, why });
      return true;
    } catch (error) {
      log.warn("remote", "remote mirror not removed", { mirror, error: (error as Error).message });
      return false;
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
    for (const name of await readdir(sessions).catch(() => [] as string[])) {
      let meta: Json;
      try {
        meta = await readJsonSoon(join(sessions, name, "session.json"));
      } catch {
        continue;
      }
      const [workspace, peer, session] = [text(meta, "workspace"), text(meta, "station"), text(meta, "session")];
      await this.inLane(this.room(workspace, peer, session), async () => {
        for (const m of await this.mirrorsOf(workspace, peer, session, now)) {
          if (!m.busy && now - m.used >= MIRROR_RECENT_MS) candidates.push({ workspace, peer, session, name: m.name, used: m.used });
        }
      });
    }
    candidates.sort((a, b) => a.used - b.used);
    for (const c of candidates) {
      if (free() >= DISK_LOW_BYTES) return;
      // Asked again in its lane: used since, it stays.
      await this.inLane(this.room(c.workspace, c.peer, c.session), async () => {
        const m = (await this.mirrorsOf(c.workspace, c.peer, c.session, now)).find((x) => x.name === c.name);
        if (m && !m.busy && now - m.used >= MIRROR_RECENT_MS) await this.dropMirror(c.workspace, c.peer, c.session, c.name, "disk low");
      });
    }
  }

  /// A session's prepared tasks' directories and what they bring back, as this station has them: one directory per
  /// session, so closing one removes its own without reading the others' (many on a station, each read on the station's
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
      // A newer prepare may have written there since this old record was read. Never replace it with the old one.
      try {
        await link(file, join(this.preparedDir(session), name));
        await rm(file, { force: true });
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "EEXIST") await rm(file, { force: true }).catch(() => undefined);
      }
    }
  }

  usedPath(session: string): string {
    return join(this.root, "used", `${hash(session)}.json`);
  }

  /// Stations on which this session has a remote workspace, within the workspace it still belongs to.
  workspaceTargets(session: string): { workspace: string; stations: string[] } | null {
    const row = this.store.getSession(session);
    if (!row || row.archivedAt !== null) return null;
    try {
      const workspace = this.workspace(row.ws ?? null);
      const record = readUsed(this.usedPath(session));
      if (record === null || record.closing === true || record.workspace !== workspace || !Array.isArray(record.stations)) return null;
      return { workspace, stations: record.stations.filter((s: unknown): s is string => typeof s === "string" && s !== "") };
    } catch {
      return null;
    }
  }

  /// Resolve only a station this chat has used; the empty id names its own station.
  async workspaceStation(session: string, named: string): Promise<string> {
    if (!this.store.getSession(session)) throw new Error("unknown session");
    if (named === "" || named === this.ownId()) return "";
    const targets = this.workspaceTargets(session);
    if (targets === null) throw new Error("this chat has no remote workspace on that station");
    const station = targets.stations.includes(named) ? named : await this.stationNamed(targets.workspace, named);
    if (station === this.ownId()) return "";
    if (!targets.stations.includes(station)) throw new Error("this chat has no remote workspace on that station");
    return station;
  }

  /// The target answers immediately while its size is measured off the station's thread. Older or offline stations
  /// simply supply no reading; the next look tries again without treating the missing answer as an empty workspace.
  async workspaceSize(session: string, station: string, limit = DEFAULT_LIMIT): Promise<{ path: string; bytes: number; complete: boolean } | null> {
    const targets = this.workspaceTargets(session);
    if (!targets || !targets.stations.includes(station)) return null;
    const answer = await this.bounded(this.ask(station, { method: "session.size", workspace: targets.workspace, session, limit }), LIST_WAIT_MS);
    if (!answer || "error" in answer) return null;
    const value = answer.ok;
    if (value?.present !== true || value.pending === true || typeof value.path !== "string" || !Number.isSafeInteger(value.bytes) || value.bytes < 0 || typeof value.complete !== "boolean") return null;
    return { path: value.path, bytes: value.bytes, complete: value.complete };
  }

  /// The source remembers which stations a session ran tasks on, to ask them to clean up when it closes.
  recordUse(workspace: string, session: string, station: string): void {
    const path = this.usedPath(session);
    let had: Json | null;
    try {
      had = readUsed(path);
    } catch {
      had = null;
    }
    const known = had !== null && Array.isArray(had.stations) && had.stations.some((s: Json) => s === station);
    if (known && had.closing !== true) return;
    const v: Json = had === null ? { session, workspace, stations: [] } : structuredClone(had);
    if (!known) {
      if (!Array.isArray(v.stations)) throw new Error("bad record");
      v.stations.push(station);
    }
    // Used again after closing (shown again): close later from the start.
    v.closing = false;
    v.closed = [];
    v.workspace = workspace;
    // Kept here at once (`readUsed`), on the disk in its turn.
    void writeJson(path, v).catch((error) => log.warn("remote", "a session's use of a station not written", { session, error: (error as Error).message }));
  }

  /// A session was archived or deleted: its tasks on other stations stop and their directories are removed. Asked until
  /// each station has answered (CLOSE_FOR_MS at most), across restarts.
  closeSession(session: string): void {
    const path = this.usedPath(session);
    let had: Json | null;
    try {
      had = readUsed(path);
    } catch {
      return;
    }
    if (had === null) return;
    const v = { ...structuredClone(had), closing: true, since: this.store.now() };
    const written = writeJson(path, v);
    // Their directories are going away: stop following this session's tasks. Every record is read to find them, off
    // the thread; one of theirs read again as it is changed (meanwhile written by its follower).
    const outgoing = join(this.root, "outgoing");
    void (async () => {
      for (const name of await readdir(outgoing).catch(() => [] as string[])) {
        const file = join(outgoing, name);
        try {
          const seen = await readJsonSoon(file);
          if (text(seen, "session") !== session || seen.delivered === true) continue;
          await updateJson(file, (entry) => entry.delivered === true ? undefined : { ...entry, delivered: true });
        } catch {}
      }
    })();
    // Its prepared tasks are in a directory of their own: removed whole, off the thread.
    void rm(this.preparedDir(session), { recursive: true, force: true }).catch(() => undefined);
    // Asked about once it is written closing (the closer reads it from the disk).
    void written.then(() => this.closer(path), () => undefined);
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
        await updateJson(path, (now) => now.closing === true ? null : undefined).catch(() => undefined);
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
          await updateJson(path, (now) => now.closing === true && Array.isArray(now.closed) ? { ...now, closed: [...now.closed, station] } : undefined)
            .catch(() => undefined);
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
    this.bus.on(["session.message", "session.read", "session.file", "session.put", "session.create", "session.create.preset", "session.archive", "session.notice"], inbox);
  }

  /// Where requests about what stations share go (share.*, share/index.ts): any station of the workspace may ask;
  /// what each share allows is checked there.
  setShares(shares: Inbox): void {
    this.bus.on("share.", shares);
  }

  /// Where requests about the agents' memory go (memory.*, share/memory.ts): the stations of the workspace it is of.
  setMemory(memory: Inbox): void {
    this.bus.on("memory.", memory);
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

  /// What is said of a workspace's rig in station_list besides how busy it is (rigs/module.ts): whose it is, whether
  /// the asking chat may use it and who may. `described`: its `describe` answer, null when it was not reached.
  setRigs(said: (workspace: string, session: string, rig: Json, described: Json | null) => Promise<Json>): void {
    this.rigs = said;
  }

  /// What this machine says of itself besides (`describe`), to the station asking: a rig says it is one, what of a
  /// station it is not (no chats, no sessions), and who may use it (rig/module.ts).
  setDescribed(more: (peer: string, workspace: string) => Json): void {
    this.described = more;
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

  /// A host reading with its own time, or why it is unavailable; a slow reader never holds a task reply indefinitely.
  private async measuredLoad(): Promise<Json> {
    const read = this.load;
    if (read === null) return { unavailable: "not measured" };
    const load = await this.bounded(Promise.resolve().then(read), LOAD_WAIT_MS);
    return load === null ? { unavailable: `not measured within ${LOAD_WAIT_MS / 1000} s` } : "ok" in load ? load.ok : { unavailable: load.error.message };
  }

  /// `describe`'s answer: what this station takes, and how busy it is (`load`, LOAD_WAIT_MS at most).
  private async describe(peer = "", workspace = ""): Promise<Json> {
    const answer: Json = { protocol: 1, version: this.version, os: OS, arch: ARCH, tasks: true, sessions: true, messages: true, reads: true, files: true, chats: true, sync: 1, smallTasks: 1, fileChunkBytes: CHUNK, maxFileBytes: MAX_FILE };
    if (this.load !== null) answer.load = await this.measuredLoad();
    return this.described === null ? answer : { ...answer, ...this.described(peer, workspace) };
  }

  /// station_list: the stations of `workspace`, each asked how busy it is at once (this one answers itself); one that
  /// has not answered within LIST_WAIT_MS is listed unanswered, one that refused says why, one safe mode leaves out
  /// (the roster's `unprotected`) after them, not asked, saying why it cannot be called. Each says its version itself.
  private async listStations(workspace: string, session: string): Promise<Json> {
    const { unprotected, ...roster } = (await this.ask("", { method: "peers", workspace })) ?? {};
    const own = this.ownId();
    const stations = Array.isArray(roster?.stations) ? roster.stations : [];
    const left = (Array.isArray(unprotected) ? unprotected : []).map((entry: Json) => ({ ...entry, unprotected: UNPROTECTED }));
    const listed = await Promise.all(
      stations.map(async (entry: Json) => {
        const id = text(entry, "id");
        if (id === "") return entry;
        const { version: seen, ...rest } = entry;
        if (id === own) return { ...rest, here: true, version: this.version, load: summary((await this.describe()).load ?? null) };
        const got = await this.bounded(this.ask(id, { method: "describe", workspace }), LIST_WAIT_MS);
        return { ...rest, ...heard(got, seen) };
      }),
    );
    // Its stations that only run tasks (rigs: rigs/module.ts says whose each is and who may use it) after the whole
    // ones, in the same list, `mode: "tasks"`: asked the same way, at once.
    const rigs = Array.isArray(roster?.rigs) ? (roster.rigs as Json[]) : [];
    const said = this.rigs;
    // Its sandboxes too (agents/sandbox.ts), by `sandbox:<name>`: nothing to ask, they are this station's.
    const sandboxes = (this.sandboxes?.() ?? []).map((d) => ({ id: SANDBOX + d.name, name: d.name, ...sandboxDescribed(d) }));
    listed.push(...sandboxes);
    if (rigs.length === 0 || said === null) return { ...roster, stations: [...listed, ...left], rigs: undefined, rigsWaiting: undefined };
    const listedRigs = await Promise.all(
      rigs.map(async (rig: Json) => {
        const entry = { id: text(rig, "id"), name: text(rig, "name") };
        const got = await this.bounded(this.ask(entry.id, { method: "describe", workspace }), LIST_WAIT_MS);
        return { ...entry, ...(await said(workspace, session, rig, got !== null && "ok" in got ? got.ok : null)), ...heard(got, field(rig, "version")) };
      }),
    );
    const { rigs: _, rigsWaiting: __, ...rest } = roster as Record<string, Json>;
    return { ...rest, stations: [...listed, ...listedRigs, ...left] };
  }

  /// The id of the station an agent names: station_list shows each by its name and its id, and either is taken. A name
  /// no station of the workspace has (a station of another workspace this one shares chats with is named by its id)
  /// goes on as given, to be refused or reached as an id.
  private async stationNamed(workspace: string, named: string): Promise<string> {
    if (named === "") return named;
    // One of its sandboxes, by `sandbox:<name>` or its name.
    const lower = named.toLowerCase();
    const sandbox = (this.sandboxes?.() ?? []).find((d) => (SANDBOX + d.name).toLowerCase() === lower || d.name.toLowerCase() === lower);
    if (sandbox !== undefined) return SANDBOX + sandbox.name;
    let stations: Json[] = [];
    let roster: Json;
    try {
      roster = await this.ask("", { method: "peers", workspace });
      // One safe mode leaves out too: named, it is refused saying why (peer.ts `member`).
      stations = [roster?.stations, roster?.rigs, roster?.unprotected].flatMap((list) => (Array.isArray(list) ? list : []));
    } catch {
      return named;
    }
    if (stations.some((s) => text(s, "id") === named)) return named;
    // (a rig is named as a station is: what runs on one is asked of it the same way)
    const same = stations.filter((s) => text(s, "name").toLowerCase() === named.toLowerCase());
    if (same.length > 1) throw new Error(`${same.length} stations are named ${named}; give the id station_list shows for the one meant`);
    if (same.length === 1) return text(same[0], "id");
    // A rig of a workspace in security mode its person has not signed for: no station sends it anything, said so.
    const waiting = (Array.isArray(roster?.rigsWaiting) ? (roster.rigsWaiting as Json[]) : []).find((r) => text(r, "id") === named || text(r, "name").toLowerCase() === named.toLowerCase());
    if (waiting !== undefined) throw new Error(`the station ${text(waiting, "name") || named} is not taken into this workspace yet: its owner ${text(waiting, "owner_email") || text(waiting, "owner")} has to check its security code in still.fail first`);
    return named;
  }

  /// mesh/cloud.json as the station keeps it in memory (`followRoster`); read from the file where none is given (tests).
  /// Read again at every task, the file held the main thread on a station whose disk was kept busy.
  place: (() => Json | null) | null = null;

  private cloudState(): Json {
    return this.place !== null ? this.place() : readJson(join(this.data, "mesh", "cloud.json"));
  }

  /// This station's id (mesh/cloud.json), "" when it has none.
  private ownId(): string {
    try {
      return text(this.cloudState(), "station");
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

  /// A request to another station of the workspace (session_send's messages, and this module's own). One to a sandbox
  /// is this station's own: answered here as a station's would be, its tasks run in the sandbox.
  ask(station: string, request: Json): Promise<Json> {
    if (station.startsWith(SANDBOX)) {
      const workspace = text(request, "workspace");
      const sandbox = this.sandboxes?.().find((d) => SANDBOX + d.name === station);
      if (sandbox === undefined) return Promise.reject(new Refused("no such sandbox on this station (config.json's sandboxes)"));
      if (text(request, "method") === "describe") return Promise.resolve(sandboxDescribed(sandbox));
      return this.bus.handle(workspace, station, request);
    }
    return this.bus.ask(station, request);
  }

  /// Where this station's sandboxes come from (config.json's, sessions/agents.ts).
  setSandboxes(list: () => Sandbox[]): void {
    this.sandboxes = list;
  }

  /// Called only after the transport authenticates the source station and checks current workspace membership.
  handle(workspace: string, peer: string, request: Json): Promise<Json> {
    return this.bus.handle(workspace, peer, request);
  }

  /// A removal holds the session's lane while it runs; the transport answers early and a retry joins the same work.
  private async cleanRequest(workspace: string, peer: string, request: Json): Promise<Json> {
    const session = text(request, "session");
    const mirror = text(request, "mirror");
    const id = hash([workspace, peer, session, mirror]);
    const now = this.store.now();
    for (const [key, entry] of this.cleans) {
      if (entry.endedAt !== null && now - entry.endedAt >= CLEAN_KEPT_MS) this.cleans.delete(key);
    }
    let clean = this.cleans.get(id);
    if (!clean) {
      clean = { result: this.inLane(this.room(workspace, peer, session), () => this.task(workspace, peer, "task.clean", request)), endedAt: null };
      const entry = clean;
      const ended = () => void (entry.endedAt = this.store.now());
      entry.result.then(ended, ended);
      this.cleans.set(id, entry);
    }
    const got = await this.bounded(clean.result, CLEAN_ANSWER_MS);
    if (got === null) return { mirror, pending: true };
    if (this.cleans.get(id) === clean) this.cleans.delete(id);
    if ("error" in got) throw got.error;
    return got.ok;
  }

  private async task(workspace: string, peer: string, method: string, request: Json, queueLoad?: () => Promise<Json>): Promise<Json> {
    if (method === "task.gets") {
      // What `task.get` says of each, in one request (a source follows all its tasks here at once: `follow`).
      const asked = field(request, "tasks");
      if (!Array.isArray(asked) || asked.length > GETS_MAX) throw new Error(`tasks are required (at most ${GETS_MAX})`);
      const tasks: Json[] = [];
      // One host reading for all queued tasks in this batch, including when the reader is slow or unavailable.
      let reading: Promise<Json> | undefined;
      const readLoad = () => (reading ??= this.measuredLoad());
      for (const one of asked) {
        const [session, key] = [field(one, "session"), field(one, "key")];
        try {
          tasks.push({ session, key, result: await this.task(workspace, peer, "task.get", { session, key }, readLoad) });
        } catch (error) {
          tasks.push({ session, key, error: (error as Error).message });
        }
      }
      return { tasks };
    }
    const session = text(request, "session");
    if (method === "session.size") {
      if (session === "" || bytes(session) > 256) throw new Error("session is required");
      const room = this.room(workspace, peer, session);
      await written(join(room, "session.json"));
      if (!(await there(join(room, "session.json")))) return { present: false };
      const path = join(room, "work");
      const cutoff = field(request, "limit") ?? DEFAULT_LIMIT;
      if (!Number.isSafeInteger(cutoff) || cutoff < 1) throw new Error("limit must be a positive whole number of bytes");
      const size = this.workspaceReader.size(path, cutoff);
      return size === null ? { present: true, pending: true, path } : { present: true, pending: false, path, ...size };
    }
    if (method === "task.mirrors" || method === "task.clean") {
      if (session === "" || bytes(session) > 256) throw new Error("session is required");
      const room = this.room(workspace, peer, session);
      await written(join(room, "session.json"));
      const mirrors = (await there(join(room, "session.json"))) ? await this.mirrorsOf(workspace, peer, session, this.store.now()) : [];
      // Unlike the automatic sweep's age-based recovery, an explicit cleanup must not interrupt even a slow sync.
      const syncingNow = new Set<string>();
      for (const m of mirrors) if (await there(join(room, "sync", m.name))) syncingNow.add(m.name);
      const inUse = (m: { name: string; busy: boolean }) => m.busy || syncingNow.has(m.name);
      if (method === "task.mirrors") {
        return { mirrors: mirrors.map((m) => ({ name: m.name, path: join(room, "work", m.name), busy: inUse(m), lastUsed: m.used })) };
      }
      const name = text(request, "mirror");
      if (name === "") throw new Error("mirror is required");
      // The name must be one the station itself listed for this peer's session, never a supplied path.
      const mirror = mirrors.find((m) => m.name === name);
      if (!mirror) return { mirror: name, removed: false };
      if (inUse(mirror)) throw new Error("mirror is in use by a task or sync");
      if (!await this.dropMirror(workspace, peer, session, name, "requested")) throw new Error("mirror could not be removed completely");
      return { mirror: name, removed: true };
    }
    if (method === "task.list") {
      if (session === "" || bytes(session) > 256) throw new Error("session is required");
      const tasks: Json[] = [];
      for (const { dir, meta } of await this.tasksOf(workspace, peer, session)) {
        const job = this.store.getJob(this.jobOf(dir));
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
      if (field(spec, "small") !== null && typeof field(spec, "small") !== "boolean") throw new Error("small must be a boolean");
      if (field(spec, "small") === true && field(spec, "screen") === true) throw new Error("a small task cannot use the screen");
      const from = field(spec, "dir");
      if (from !== null && (typeof from !== "string" || from === "" || bytes(from) > 4096)) throw new Error("dir must be a path");
      let meta: Json;
      if (await there(record)) {
        meta = await readJsonSoon(record);
        if (!isDeepStrictEqual(field(meta, "spec"), spec)) {
          throw new Error("task key already used with different inputs; choose a new key for new work");
        }
      } else {
        meta = { spec, workspace, station: peer, session, key, layout: "session" };
        if (typeof from === "string") meta.mirror = await this.mirrorName(workspace, peer, session, from);
        await mkdir(dir, { recursive: true });
        await writeJson(record, meta);
      }
      this.seen(workspace, peer, session);
      return typeof meta.mirror === "string" ? { key, prepared: true, dir: meta.mirror } : { key, prepared: true };
    }
    let meta: Json;
    try {
      meta = await readJsonSoon(record);
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
    // A task with a directory runs in its mirror, a directory of the session's.
    const mirror = typeof meta.mirror === "string" ? meta.mirror : null;
    const room = this.room(workspace, peer, session);
    const manifestPath = mirror === null ? "" : join(room, "mirrors", `${mirror}.json`);
    const syncing = mirror === null ? "" : join(room, "sync", mirror);
    if (method.startsWith("sync.") && mirror === null) throw new Error("this task has no directory to sync");
    /// Another task of the session running in the same mirror (one at a time there).
    const refuseBusy = async () => {
      const tasks = (await this.tasksOf(workspace, peer, session)).filter((t) => t.dir !== dir && field(t.meta, "mirror") === mirror);
      const other = tasks.find((t) => this.running(t.dir));
      if (other) throw new Error(`task ${text(other.meta, "key")} is running in ${mirror} on this station; wait for it or stop it`);
      const collecting = tasks.find((t) => t.meta.safe === true && t.meta.collected !== true && this.store.getJob(this.jobOf(t.dir)) !== null);
      if (collecting) throw new Error(`task ${text(collecting.meta, "key")} is still bringing back its results from ${mirror}; wait for its completion notice`);
    };
    /// The sync under way: its state, when `id` is its.
    const ongoing = async (): Promise<Json> => {
      let state: Json = null;
      try {
        state = await readJsonSoon(join(syncing, "state.json"));
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
          await refuseBusy();
        }
        if (mirror !== null) {
          cwd = await filePath(work, mirror, false);
          await this.usedMirror(workspace, peer, session, mirror);
        }
        const spec = field(meta, "spec");
        // Through the station's queue (jobs/admit.ts): started now if there is room, else when there is.
        // A sandbox's (this station's own, `ask`): run there, nothing of this machine's taken, so not queued here.
        const inSandbox = peer.startsWith(SANDBOX);
        if (inSandbox && field(spec, "screen") === true) throw new Error("a sandbox has no screen: run what needs one on a station");
        const back = field(spec, "back");
        if (inSandbox) await ensureIdentity(this.data);
        const started = inSandbox
          ? this.jobs.startId(owner, text(spec, "name"), text(spec, "command"), cwd, null, false, jobId, false, null, { sandbox: peer.slice(SANDBOX.length), session, back: Array.isArray(back) ? back.filter((b: unknown): b is string => typeof b === "string") : [] })
          : this.jobs.startId(owner, text(spec, "name"), text(spec, "command"), cwd, null, false, jobId, false, { screen: field(spec, "screen") === true, small: field(spec, "small") === true });
        // Where its source wants to be told of it (`pushOut`): from its first start, as it is then (a start asked again
        // keeps what was told).
        const push = text(request, "push");
        if (/^[0-9a-f]{64}$/.test(push) && meta.push !== push) {
          meta.push = push;
          meta.pushed = this.said(id);
          await writeJson(record, meta);
        }
        const queue = await this.queued(started.id, queueLoad);
        return { key, job: jobJson(this.store.getJob(jobId) ?? started), ...queue, ...(meta.push ? { push: true } : {}) };
      }
      case "sync.begin": {
        if (job) return { key, started: true };
        await refuseBusy();
        await rm(syncing, { recursive: true, force: true });
        await mkdir(syncing, { recursive: true });
        await mkdir(join(room, "mirrors"), { recursive: true });
        await this.usedMirror(workspace, peer, session, mirror!);
        const manifest = readManifest(manifestPath);
        const files = manifest === null ? {} : await actual(join(work, mirror!), manifest.files);
        const base = { ...(manifest?.files ?? {}) };
        // Refresh the stat only where the content is still the source's: old manifests lacked ctime and must be hashed
        // once, not at every subsequent sync. A changed file keeps the original content as its conflict base.
        for (const [path, current] of Object.entries(files)) {
          const before = base[path];
          if (before && before[0] === current[0] && before[1] === current[1]) base[path] = current;
        }
        const id = randomBytes(12).toString("hex");
        await writeJson(join(syncing, "actual.json"), files);
        await writeJson(join(syncing, "base.json"), base);
        await writeJson(join(syncing, "state.json"), { id, key, version: manifest?.version ?? 0 });
        if (field(request, "safe") === 1) {
          meta.safe = true;
          await writeJson(record, meta);
        }
        return { key, id, dir: mirror, version: manifest?.version ?? 0, safe: 1 };
      }
      case "sync.manifest": {
        await ongoing();
        const after = asU64(field(request, "after")) ?? 0;
        return page(listed(await readJsonSoon(join(syncing, "actual.json"))), after);
      }
      case "sync.base": {
        await ongoing();
        const after = asU64(field(request, "after")) ?? 0;
        return page(listed(await readJsonSoon(join(syncing, "base.json"))), after);
      }
      case "sync.put": {
        await ongoing();
        // The packed pieces after the request; from a station from before, base64 in it.
        const packed = bytesOf(request);
        return { pieces: await putBlobs(join(syncing, "blobs"), field(request, "blobs"), packed !== null ? await readBytes(packed, PACKED) : fromBase64(text(request, "data"))) };
      }
      case "sync.commit": {
        const state = await ongoing();
        const part = planPart(request);
        await appendFile(join(syncing, "plan.jsonl"), `${JSON.stringify(part)}\n`);
        if (field(request, "final") !== true) return { key, planned: true };
        await refuseBusy();
        const manifest = readManifest(manifestPath);
        const version = manifest?.version ?? 0;
        if (version !== field(state, "version")) throw new Error("the mirror changed while this sync went on; start again");
        const plan = { set: [] as [string, string, string][], remove: [] as string[] };
        // Read a line at a time off the station's thread: a plan of a large directory is megabytes.
        const lines = createInterface({ input: createReadStream(join(syncing, "plan.jsonl"), "utf8"), crlfDelay: Infinity });
        for await (const line of lines) {
          if (line === "") continue;
          const p = JSON.parse(line);
          plan.set.push(...p.set);
          plan.remove.push(...p.remove);
        }
        const base = await readJsonSoon(join(syncing, "base.json"));
        const root = join(work, mirror!);
        // Re-read at commit: a task's output may have changed while the source sent its files.
        const verify = new Set([...plan.set.map(([path]) => path), ...plan.remove]);
        const files = await actual(root, base, verify);
        const untracked: Record<string, [string, string, number, number, number, number?]> = {};
        if (await there(root)) for (const [path] of plan.set) {
          if (base[path] !== undefined || files[path] !== undefined) continue;
          let abs: string;
          try { abs = await filePath(root, path, false); } catch { throw new Error(`sync conflict at ${path}: an existing remote path would be overwritten`); }
          try {
            const st = await lstat(abs);
            if (!st.isFile()) throw new Error(`sync conflict at ${path}: an existing remote path would be overwritten`);
            untracked[path] = ["", "", 0, 0, 0];
          } catch (error) {
            if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
          }
        }
        Object.assign(files, await actual(root, untracked));
        const equal = (a: readonly unknown[] | undefined, b: readonly unknown[] | undefined) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
        const safe = { set: [] as [string, string, string][], remove: [] as string[] };
        for (const [path, hash, mode] of plan.set) {
          const before = base[path], current = files[path], wanted = [hash, mode];
          // Old sources send a plan against the actual mirror: an unchanged source must not reset remote output.
          if (equal(before, wanted) && !equal(before, current)) continue;
          if (!equal(before, current) && !equal(current, wanted)) throw new Error(`sync conflict at ${path}: source and remote both changed; preserve the remote result and reconcile the files`);
          safe.set.push([path, hash, mode]);
        }
        for (const path of plan.remove) {
          if (files[path] !== undefined && !equal(base[path], files[path])) throw new Error(`sync conflict at ${path}: the remote file changed before removal`);
          safe.remove.push(path);
        }
        const nextBase = { ...base };
        let done: { written: number; removed: number };
        try {
          done = apply(work, mirror!, join(syncing, "scratch"), join(syncing, "blobs"), files, safe);
        } finally {
          for (const [path, hash, mode] of safe.set) if (equal(files[path], [hash, mode])) nextBase[path] = files[path];
          for (const path of safe.remove) if (files[path] === undefined) delete nextBase[path];
          writeManifest(manifestPath, { dir: text(field(meta, "spec"), "dir"), name: mirror!, version: version + 1, files: nextBase });
        }
        meta.synced = true;
        await writeJson(record, meta);
        await rm(syncing, { recursive: true, force: true });
        await this.usedMirror(workspace, peer, session, mirror!);
        return { key, ...done, version: version + 1 };
      }
      case "sync.changes": {
        if (!job || job.state === "running") throw new Error("the task has not finished");
        const manifest = readManifest(manifestPath);
        const base = await filePath(work, mirror!, false);
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
          if (is?.[1] === LINK) change.link = await readlink(join(base, ...path.split("/")));
          changes.push(change);
        }
        return { key, base: mirror, changes, more };
      }
      case "task.collected": {
        if (!job || job.state === "running") throw new Error("the task has not finished");
        meta.collected = true;
        await writeJson(record, meta);
        return { key, collected: true };
      }
      case "task.files": {
        if (job?.state === "running") throw new Error("wait for the task to finish before downloading artifacts");
        const paths = field(request, "paths");
        if (!Array.isArray(paths) || paths.length > 100 || !paths.every((p) => typeof p === "string")) throw new Error("paths are required (at most 100)");
        const cwd = mirror === null ? work : await filePath(work, mirror, false);
        const files: [string, number | null][] = [];
        const visit = async (rel: string): Promise<void> => {
          if (files.length >= 1000) throw new Error("more than 1000 files to bring back");
          let st;
          try {
            st = await lstat(await filePath(cwd, rel, false));
          } catch {
            files.push([rel, null]);
            return;
          }
          if (st.isFile()) files.push([rel, st.size]);
          else if (st.isDirectory()) for (const name of (await readdir(join(cwd, ...rel.split("/")))).sort()) await visit(`${rel.replace(/\/+$/, "")}/${name}`);
        };
        for (const p of paths) await visit(p);
        return { key, base: mirror ?? "", files };
      }
      case "task.get":
      case "task.log": {
        const lines = Math.min(Math.max(asU64(field(request, "lines")) ?? 50, 1), 1000);
        const push = typeof meta.push === "string" ? { push: true } : {};
        const queue = await this.queued(jobId, queueLoad);
        const current = this.store.getJob(jobId);
        return { key, job: current ? jobJson(current) : null, log: current ? tail(current.log, lines) : null, notices: this.store.jobNotices(jobId, 20), ...queue, ...push };
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
          const path = await filePath(work, name, true);
          if (meta.uploads === null || typeof meta.uploads !== "object" || Array.isArray(meta.uploads)) meta.uploads = {};
          meta.uploads[name] = false;
          await writeJson(record, meta);
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
          await writeJson(record, meta);
          return { bytes: size };
        }
        const offset = asU64(field(request, "offset"));
        if (offset === null) throw new Error("offset is required");
        const data = fromBase64(text(request, "data"));
        if (data.length > CHUNK || offset + data.length > MAX_FILE) throw new Error("file limit exceeded");
        const name = text(request, "path");
        const path = await filePath(work, name, true);
        if (meta.uploads === null || typeof meta.uploads !== "object" || Array.isArray(meta.uploads)) meta.uploads = {};
        meta.uploads[name] = false;
        await writeJson(record, meta);
        const file = await open(path, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o666);
        try {
          const stat = await file.stat();
          if (!stat.isFile()) throw new Error("only regular files can be transferred");
          if (offset > stat.size) throw new Error("file offset leaves a gap");
          for (let at = 0; at < data.length; ) at += (await file.write(data, at, data.length - at, offset + at)).bytesWritten;
          if (field(request, "final") === true) {
            await file.truncate(offset + data.length);
            await file.sync();
          }
        } finally {
          await file.close();
        }
        if (field(request, "final") === true) {
          meta.uploads[name] = true;
          await writeJson(record, meta);
        }
        return { bytes: data.length };
      }
      case "file.get": {
        if (job?.state === "running") throw new Error("wait for the task to finish before downloading artifacts");
        const path = await filePath(work, text(request, "path"), false);
        const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
        try {
          const stat = await file.stat();
          if (!stat.isFile()) throw new Error("only regular files can be transferred");
          const size = stat.size;
          if (size > MAX_FILE) throw new Error("file limit exceeded");
          const offset = asU64(field(request, "offset")) ?? 0;
          if (offset > size) throw new Error("offset past end");
          // All of it from there, after the answer; a station from before asks for chunks.
          if (field(request, "whole") === true) return withBytes({ size }, fileBytes(path, offset, size));
          const buffer = Buffer.alloc(CHUNK);
          const { bytesRead: n } = await file.read(buffer, 0, CHUNK, offset);
          return { data: buffer.subarray(0, n).toString("base64"), size, eof: offset + n >= size };
        } finally {
          await file.close();
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
      if (!membershipCurrent) return;
      const incoming = join(this.root, "incoming");
      for (const name of await readdir(incoming).catch(() => [] as string[])) {
        let meta: Json;
        try {
          meta = await readJsonSoon(join(incoming, name, "task.json"));
        } catch {
          continue;
        }
        const peer = text(meta, "station");
        if (rosters.some((r) => text(meta, "workspace") === r.workspace && r.peers.includes(peer))) continue;
        // A sandbox's task is this station's own, not a peer's (agents/sandbox.ts).
        if (peer.startsWith(SANDBOX)) continue;
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
  /// station is still in it.
  private workspace(own: string | null): string {
    const state = this.cloudState();
    if (state === null) throw new Error("station has no workspace");
    if ((field(state, "removed_at") ?? null) !== null) throw new Error("station was removed from workspace");
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

  /// A task on a station from before `task.changed`: that station never tells of it, and it is not asked about on a
  /// timer; its session is told so, once.
  private async unfollowed(path: string): Promise<void> {
    let entry: Json;
    try {
      entry = await readJsonSoon(path);
    } catch {
      return;
    }
    if (entry.delivered === true) return;
    const message = `Remote task ${text(entry, "key")} on ${text(entry, "station")}: that station is from before it tells how its tasks go, so this one is not followed. Update that station, or ask with get.`;
    try {
      await this.notify(text(entry, "session"), message);
    } catch {
      return;
    }
    entry.delivered = true;
    try {
      await writeJson(path, entry);
    } catch {}
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

  /// What follows an outcome: asked again soon or later, nothing until its station says something, or (a station from
  /// before `task.changed`) told it is not followed.
  private after(path: string, outcome: Outcome, got: Got): void {
    if (outcome === "again") this.check(path);
    else if (typeof outcome === "object") this.later(path, outcome.at);
    else if (outcome === "wait" && !pushes(got)) void this.unfollowed(path);
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
        await writeJson(path, entry);
      } catch {
        return "again";
      }
    }
    const result = "result" in got ? got.result : null;
    // Never started there (its prepare or start did not get through, and the agent went on with another key): asked
    // about once more when it would have started, then given up on, said once.
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
        await writeJson(path, entry);
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
        await writeJson(path, entry);
      } catch {
        return "again";
      }
    }
    if (finished && typeof entry.dir === "string" && entry.brought !== undefined) {
      const brought = entry.brought;
      const missing = Array.isArray(brought?.files?.missing) ? brought.files.missing : [];
      const incomplete = brought?.error || brought?.changed?.error || brought?.changed?.more === true ||
        (Array.isArray(brought?.changed?.notInPatch) && brought.changed.notInPatch.length > 0) ||
        missing.some((m: unknown) => typeof m !== "string" || !m.endsWith(": not there"));
      if (incomplete) {
        brought.pending = "Some results were not brought back. Preserve them with station_file; then station_task release permits the next task in this mirror.";
      } else {
        try {
          await this.ask(text(entry, "station"), { method: "task.collected", workspace: field(entry, "workspace"), session: field(entry, "session"), key: field(entry, "key") });
        } catch (error) {
          // An old target has no result fence. New targets retain it until this acknowledgement is received.
          if (!(error instanceof Refused && /unsupported peer method/.test(error.message))) return "again";
        }
      }
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
        await writeJson(path, entry);
      } catch {}
    }
    return finished ? "over" : "wait";
  }

  /// A file of a task's station (`request`'s path) to `path` here, whole after one answer (a station from before answers
  /// a chunk, and is asked for each); its size. An existing file is replaced only when `replace`.
  private async download(ask: (request: Json) => Promise<Json>, request: Json, path: string, replace: boolean): Promise<number> {
    if (!replace && (await there(path))) throw new Error("local output already exists; choose another path");
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
      await mkdir(dest, { recursive: true });
      const got: string[] = [];
      const missing: string[] = [];
      for (const [p, size] of files) {
        if (size === null) {
          missing.push(`${p}: not there`);
          continue;
        }
        try {
          await this.download(ask, { path: prefix + p }, await filePath(dest, p, true), true);
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
          await mkdir(dest, { recursive: true });
          const file = join(dest, "changes.patch");
          await writeFile(file, made.patch);
          changed.patch = file;
          changed.apply = `review it, then git apply it in ${entry.dir} if wanted`;
        }
        const left = [...missing, ...(made?.missing ?? (made === null ? changes.map((c) => String(c.path)) : []))];
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
      if (station === "") return this.listStations(workspace, session);
      if (station === this.ownId()) return detailed(await this.describe());
      // Waited for longer than in the list: one starting or updating itself has its time to answer.
      const got = await this.bounded(this.ask(station, { method: "describe", workspace }), LIST_ALONE_WAIT_MS);
      if (got === null) return { id: station, unanswered: `did not answer within ${LIST_ALONE_WAIT_MS / 1000} s; not known to be offline (it may be starting or updating): ask again in a minute` };
      if ("error" in got) throw got.error;
      return detailed(got.ok);
    }
    const key = text(args, "key");
    const action = tool === "station_task" ? text(args, "action") : "";
    const sessionAction = ["list", "mirrors", "clean"].includes(action);
    if (station === "" || (key === "" && !sessionAction)) throw new Error("station and key are required (list, mirrors and clean need only station)");
    if (!sessionAction) this.recordUse(workspace, session, station);
    const request: Json = { workspace, session, key };
    if (tool === "station_task") {
      if (!["prepare", "start", "get", "log", "stop", "release", "list", "mirrors", "clean"].includes(action)) throw new Error("unknown task action");
      request.method = action === "release" ? "task.collected" : `task.${action}`;
      if (action === "mirrors" || action === "clean") {
        if (action === "clean") request.mirror = field(args, "mirror");
        return this.ask(station, request);
      }
      request.lines = field(args, "lines");
      request.spec = { name: field(args, "name"), command: field(args, "command"), requestedBy: row.createdBy };
      // Said only when so: a task prepared before keeps the same inputs.
      if (field(args, "screen") === true) request.spec.screen = true;
      if (field(args, "small") === true) request.spec.small = true;
      // A task's directory and what it brings back, as this station has them (remote/prepared).
      const preparedName = `${hash([workspace, session, station, key])}.json`;
      const prepared = join(this.preparedDir(session), preparedName);
      if (action === "prepare") {
        // Fence off any earlier spec before validation or a network request. If this attempt fails or the station
        // restarts, start must not quietly use the task the target kept from an earlier successful prepare.
        await mkdir(this.preparedDir(session), { recursive: true });
        const attempt = randomBytes(16).toString("hex");
        await writeJson(prepared, { workspace, session, station, key, preparing: attempt });
        const dir = field(args, "dir");
        const back = field(args, "back");
        const small = field(args, "small") === true;
        if (small && field(args, "screen") === true) throw new Error("a small task cannot use the screen");
        if (dir !== null && (typeof dir !== "string" || !isAbsolute(dir))) throw new Error("dir must be an absolute path on this machine");
        // An older station would silently use the ordinary queue. Ask once for both small-task support and sync.
        const described = dir !== null || small ? await this.ask(station, { method: "describe", workspace }) : null;
        if (small && field(described, "smallTasks") !== 1) throw new Error(`${station} cannot run small tasks; update that station first`);
        if (dir !== null) {
          // The station reads it itself as it syncs: in a folder macOS protects, only when it may (looked at off its
          // thread, ops/places.ts), never held on a prompt.
          try {
            await this.places.directory(dir, { lang: "en", agent: true, self: true });
          } catch (e) {
            if (e instanceof PlaceRefused && (e.code === "gone" || e.code === "not_a_directory")) throw new Error(`${dir} is not a directory`);
            throw e;
          }
          // A station from before would take the task and run it without the files.
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
        // A concurrent prepare may have begun while this one was away. Its result alone can release its fence.
        if (text(await readJsonSoon(prepared), "preparing") !== attempt) throw new Error("a newer prepare superseded this one; prepare again before starting");
        await writeJson(prepared, { workspace, session, station, key, dir: request.spec.dir ?? null, back: request.spec.back ?? null });
        return answer;
      }
      let synced: Synced | null = null;
      if (action === "start") {
        // Read off the station's thread: only this start reads it (76 ms on a station short of memory, 2026-11-03).
        let local: Json = null;
        try {
          local = await readJsonSoon(prepared);
        } catch {
          // Not moved into its session's directory yet (movePrepared), or moved meanwhile.
          local = await readJsonSoon(join(this.root, "prepared", preparedName)).catch(() => readJsonSoon(prepared)).catch(() => null);
        }
        if (typeof local?.preparing === "string") throw new Error("the last prepare failed or is still in progress; prepare again before starting this key");
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
        // A re-prepare may have failed while the directory sync was in flight.
        const latest = await readJsonSoon(prepared).catch(() => null);
        if (typeof latest?.preparing === "string") throw new Error("the last prepare failed or is still in progress; prepare again before starting this key");
        // Persist before sending: an uncertain start is still followed after a process restart.
        const path = this.outgoing(workspace, session, station, key);
        let refused = false;
        try {
          refused = (await readJsonSoon(path)).refused === true;
        } catch {}
        if (!(await there(path)) || refused) {
          const more = local === null ? {} : { dir: local.dir ?? null, back: local.back ?? null, prefix: synced?.prefix ?? "" };
          await writeJson(path, { workspace, session, station, key, delivered: false, since: this.store.now(), ...more });
        }
        // Its station tells this one when it changes (`task.changed`), naming this record.
        request.push = basename(path, ".json");
      }
      try {
        const answer = await this.ask(station, request);
        // A station from before `task.changed` never tells of it: not followed, its session told so.
        if (action === "start" && field(answer, "push") !== true) void this.unfollowed(this.outgoing(workspace, session, station, key));
        return synced === null ? answer : { ...answer, sync: synced };
      } catch (error) {
        // An uncertain start: asked about once its station would have started it (it says something before if it did).
        if (action === "start" && !(error instanceof Refused)) {
          const path = this.outgoing(workspace, session, station, key);
          this.later(path, (asI64(field(await readJsonSoon(path).catch(() => null), "since")) ?? this.store.now()) + GIVE_UP_MS);
        }
        if (action === "start" && error instanceof Refused) {
          const path = this.outgoing(workspace, session, station, key);
          await updateJson(path, (entry) => ({ ...entry, delivered: true, refused: true })).catch(() => undefined);
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
    const path = await filePath(root, relative, direction === "download");
    request.path = field(args, "path");
    if (direction === "upload") {
      const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
      try {
        const stat = await file.stat();
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
          const { bytesRead: n } = await file.read(chunk, 0, CHUNK, offset);
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
        await file.close();
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

/// The target side of the station transport: a request taken in, its answer as the wire has it
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
  remote.place = () => cloud.state as unknown as Json;
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
