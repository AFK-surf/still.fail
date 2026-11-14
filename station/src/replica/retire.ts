// A station retired from a workspace, its chats going on on another station of it that a person chose (the user,
// 2026-11-13: 「搬家主要考虑的场景是要废弃掉一个 station」「要允许用户选择目标迁移 station」; replica/AGENTS.md).
//
// On the station retired (`retire`): the other station is told it is coming (`retire.begin`), and what goes along with
// the chats (their transcripts and their sessions' rooms, carry-worker.ts) is sent while its agents still work, what it
// lacks of each session's list a bounded batch at a time (`retire.lacking`), its agent home's own files with them
// (carry-worker.ts `homeFiles`). Then it is `sent`: all that goes along is there and the chats still work. A retirement
// a person started in the app's panel goes on from there at once (that panel said the chats would pause); one an agent
// asked for (station_retire, retire-asks.ts) waits there until an owner or admin confirms the hand-over in the app
// (the user, 2026-11-14: 「迁移最好能 agent 辅助，因为中途可能出问题，然后人应该只需要在关键节点点卡片来确认就行」).
// Then its chats of that workspace take no more turns, their jobs stop (each kept with what it takes to run it again),
// and their platforms' messages are kept for the other (sessions/hub.ts `quiet`, connects/workspace.ts); what changed
// meanwhile goes after it, the lists and their index, then the chats' copy (copies.ts `bringTo`), and the other station
// is asked to take them (`retire.take`). It says when it took this one's place (`retire.took`, or `retire.failed`):
// this station's chats there go out of sight here; retired from its home workspace, its accounts move there too
// (share/index.ts `moveProfile`); its connects of the workspace move to it (connects/workspace.ts `moveAll`, what was
// kept for it first), and it is done; it stays quiet there for good, and the app takes it out of the workspace.
//
// Where the hand-over fails in a way that does not go on by itself (the other station could not put the chats in, or
// was not reached for a minute after they stopped, QUIET_UNREACHED_MS, before it was asked to take them), the chats are put back
// to work here (`#fallBack`: as a cancel does for them, their jobs started again, what their platforms said meanwhile
// taken here), the other station told to put in nothing of it by itself, and it rests at `sent`, why kept: what was
// sent stays there, so the next hand-over, confirmed again, sends only what changed. Never once the other said it took
// them. Who asked for it with station_retire (its `driver`, a session here or on another station) is told each step
// that needs them: the files there, a failure and what was done of it, the chats taken, accounts left, done.
//
// On the station the chats go to (`take`): what goes along is put in place, the linked worktrees made again by git, and
// the copy put in beside its own chats as it starts again (restore.ts `build`'s `merge`), after which it is that station
// too (`formerly`): a link or a request naming the retired one comes to it, but what it tells the retired one itself
// (mesh/bus.ts `askItself`). Then the jobs the chats had running are started again in their sessions, in the same
// directories under this data directory, as after a restart of the station (jobs.ts `relaunch`: the lead, 2026-11-14,
// after the owner's 「不能自动搬吗？」), each once, their agents told at once; the agent home merged into this one's
// (agent-carry.ts); each moved chat's agent told once what came of it.
//
// Each step is safe to run again where it stopped; where each side stands is kept in a file (`retiring.json`,
// `taking/<origin>.json`, `drops-owed.json`) so that a restart goes on with it.
import { execFile } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { createReadStream, readFileSync, readdirSync } from "node:fs";
import { copyFile, mkdir, open, readFile, readdir, rename, rm, stat, statfs, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import { Worker } from "node:worker_threads";
import { type Bytes, Refused, bytesOf, withBytes } from "../mesh/bus.ts";
import { fileBytes, oneBytes, stopBytes } from "../mesh/files.ts";
import type { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { knownOf, localOf } from "../connects/remote.ts";
import type { CarriedJob, CarriedSession, CarryIndex, Gathered } from "./carry-worker.ts";
import { GEN, HASH, STATION, WORKSPACE } from "./format.ts";
import { FolderPlace } from "./places.ts";
import type { Ask } from "./peers.ts";
import { type Outcome, moved, outcomeFile, readyFile, restoreDir } from "./restore.ts";
import { mergeAgentHome } from "./agent-carry.ts";
import { movedSaid } from "../jobs/jobs.ts";
import { hold as holdUpdates } from "../updates/holds.ts";

type Json = any;

/// A failed step is tried again after this, twice as long each time, up to RETRY_MOST_MS.
export const RETRY_MS = 10_000;
export const RETRY_MOST_MS = 10 * 60_000;
/// How long the workspace's chats wait stopped for the station picked to be reached, before it was asked to take them,
/// before they go back to work here (`#fallBack`; the lead, 2026-11-14: the backoff's longest wait would have them sit
/// about twenty minutes). Falling back is cheap: the chats work again at once, and the next hand-over sends only what
/// changed meanwhile; sitting stopped is what people notice.
export const QUIET_UNREACHED_MS = 60_000;
/// How often at most the settings are told how far the files went.
export const TELL_MS = 1_000;
/// What is left free on the other station beside what is sent: this, and a twentieth of what is sent.
export const HEADROOM = 1024 * 1024 * 1024;
/// The most hashes one `retire.lacking` asks of (and what it answers): what goes in one message never grows with the
/// files a station has.
export const LACK_MOST = 2_000;
/// The times a station taking another's chats starts again to put them in before it says it could not.
export const RESTARTS_MOST = 2;

/// Where this station stands in being retired from a workspace, as its settings show it.
/// - `sending`: what goes along is sent while the chats still work (`done` of `total` bytes);
/// - `sent`: it is all there and the chats still work; one an agent asked for waits here for a person to confirm the
///   hand-over, and so does one whose hand-over failed (`#fallBack`, its `error` and `reason` kept);
/// - `quiet`: the chats stopped; what changed meanwhile, then their copy, sent after it;
/// - `handing`: the other station is putting them in (it starts again for it);
/// - `accounts`: it took this station's place; this station's accounts move to it (its home workspace retired from);
/// - `connects`: the connects of the workspace move to it;
/// - `done`: all of it there; the app takes this station out of the workspace.
export type Step = "sending" | "sent" | "quiet" | "handing" | "accounts" | "connects" | "done";
/// Whether a step is one where the chats are stopped.
const stopped = (step: Step) => step !== "sending" && step !== "sent";
/// Who asked for a retirement with station_retire: a session, on this station or another of the workspace (told of
/// its steps; after the chats moved, one of them that was here is on the station they went to).
export type Driver = { station: string; session: string };
/// A job a moved chat had running, as it went on the station the chats went to: started again (its id there) or not,
/// and why not; `old`: gathered by a station from before jobs moved, so not tried.
export type JobOutcome = { session: string; name: string; command: string; port: number | null; id: string | null; started: boolean; why: string | null; old?: boolean };
/// Why a step does not go on: the other station not reached, its disk too full, it is from before stations could be
/// retired, it could not put the chats in (`failed`: nothing goes on by itself), or something else.
export type Reason = "offline" | "full" | "old" | "failed" | "error";
/// An account that did not move with the retirement (it stays here; the person moves it by hand or signs in there).
export type AccountLeft = { id: string; name: string; error: string };
/// What the settings show of it (`copies.retiring`).
export type Retiring = { workspace: string; to: string; toName: string; by: string; at: number; step: Step; done: number; total: number; error: string | null; reason: Reason | null; cancellable: boolean; retriable: boolean; accountsLeft: AccountLeft[]; home: boolean };
/// What this station keeps of it: that, the jobs its chats had running as they stopped, and what it asked the other to
/// take (`retire.take`, asked again as it starts again in `handing`); whether it waits at `sent` for a person
/// (`wait`), who is told of it (`driver`, and what is still to be told them, `owed`), how many files went along and when
/// they were all there (`sentAt`), whether the other is asked to put the copy in again even where it is the one it could
/// not (`retake`: after a fallback), what came of the jobs there (`jobsThere`, as it says), the failure last told.
type State = Omit<Retiring, "cancellable" | "retriable" | "home"> & {
  jobs: CarriedJob[]; take: Take | null; wait: boolean; driver: Driver | null; owed: string[]; files: number; sentAt: number | null;
  retake: boolean; jobsThere: JobOutcome[] | null; toldError: string | null;
};
type Take = { gen: string; carry: string; connects: Record<string, string>; bindings: Record<string, string>; driver?: Driver | null };
/// What a station's disk and git are, as it says them (`retire.begin`, `retire.room`).
type Room = { free: number | null; clones: boolean; git: boolean };

/// What a station taking another's chats keeps of it: whose, of which workspace, the copy's generation, what goes along
/// (its index's hash), how the connects' ids go here and the single-session connects' bindings, and how far it went.
/// `coming`: told it is coming, files being sent; `failed`: the copy could not be put in (nothing goes on by itself);
/// `took`: it is that station now, which is told so until it answers. `rooms`: the sessions' rooms put here that were
/// not here before (removed where it is called off). `restarts`: the starts again asked for to put it in. Once it is that
/// station: what came of its jobs (`jobs`, started again once), whether their agents and the driver were told
/// (`jobsTold`), whether its agent home was merged (`home`); `driver`, as its take said.
export type TakingStep = "coming" | "placing" | "gits" | "copy" | "restart" | "failed" | "took";
export type Taking = {
  origin: string; name: string; workspace: string; gen: string; carry: string; connects: Record<string, string>; bindings: Record<string, string>;
  step: TakingStep; placed: number; missing: number; gits: number; gitsFailed: number; rooms: string[] | null; error: string | null; told: boolean; restarts: number;
  driver: Driver | null; jobs: JobOutcome[] | null; jobsTold: boolean; home: boolean; driverTold: boolean;
};
/// A retired station's chats taken here, kept after it was told (a few, the latest), for station_retire's status.
export type Taken = { origin: string; name: string; workspace: string; at: number; chats: number; jobs: JobOutcome[] };
const TAKEN_KEPT = 10;
/// A retirement called off while the station picked was not reached: it is told to drop what it was sent, until it
/// answers or is no longer of the workspace. `keep`: a hand-over that failed, the chats back to work here: it keeps what
/// was sent (the next sends only what changed) and puts in nothing of it by itself.
type DropOwed = { to: string; workspace: string; keep?: boolean };

export type RetireDeps = {
  data: string;
  here: () => string | null;
  home: () => string | null;
  /// The stations of `ws` with their names (null while not current).
  roster: (ws: string) => { id: string; name: string }[] | null;
  ask: Ask;
  /// A request to the station an id names itself, not to one that took its place (mesh/bus.ts `askItself`).
  askItself: Ask;
  fibers: Fibers;
  changed: () => void;
  /// The chats' copy (copies.ts).
  copies: {
    settleExport(): Promise<void>;
    bringTo(ws: string, peer: string): Promise<string>;
    takeOver(ws: string, origin: string, gen: string, extra: { connects: Record<string, string>; ws: string | null }): Promise<void>;
    formerly(): string[];
    restored(): Outcome | null;
  };
  /// The workspace's chats stop, and their jobs (sessions/hub.ts `quiet`, jobs.ts `stopAll`): the jobs it stopped.
  quiet: (ws: string) => Promise<CarriedJob[]>;
  /// They go on again (sessions/hub.ts `unquiet`): the retirement called off.
  unquiet: (ws: string) => void;
  /// They are out of sight here (store `setSessionsWs` to sessions/hub.ts `retiredWs`): the other station took them.
  retired: (ws: string) => void;
  /// This station's own accounts (no copy borrowed, not the machine's login), and one moved to another station
  /// (share/index.ts `moveProfile`, which refuses in words).
  accounts: { own(): { id: string; name: string }[]; move(id: string, to: string): Promise<unknown> };
  /// The ids of this station's connects of `ws` (config.json's), the sessions single-session ones are bound to, and each
  /// moved to `to`, what was kept for it first (connects/workspace.ts).
  connectsOf: (ws: string) => string[];
  bindingsOf: (connects: string[]) => Record<string, string>;
  moveConnects: (ws: string, to: string) => Promise<void>;
  /// On the station taking them, once it is that one: the bindings set, and what each moved chat's agent is told.
  took: (t: { bindings: Record<string, string>; notes: { session: string; text: string }[] }) => void;
  /// The station's repository cache (sessions/hub.ts `reposDir`).
  reposDir: string;
  /// The bytes free where the data directory is, and whether a copy there is a clone (statfs and the platform, unless a
  /// test says); whether git runs here.
  room?: () => Promise<{ free: number | null; clones: boolean }>;
  hasGit?: () => Promise<boolean>;
  /// git run in `dir`, its output (throws where it fails).
  git?: (dir: string, args: string[]) => Promise<string>;
  /// The most hashes one `retire.lacking` asks of and takes (LACK_MOST unless a test says).
  lackMost?: number;
  /// carry-worker.ts's gathering, placing and preview (in a thread of their own, a gathering stopped by `signal`, unless a
  /// test says otherwise).
  work?: { gather: typeof gatherSoon; place: typeof placeSoon; preview?: typeof previewSoon };
  /// The jobs and services of `ws`'s chats up now (what `quiet` stops), and its connects as the app names them.
  jobsIn: (ws: string) => CarriedJob[];
  connectsNamed: (ws: string) => { id: string; name: string; kind: string }[];
  /// A session's agent here told something by the station, woken by it (hub.notify; throws where there is none).
  tell?: (session: string, text: string) => void;
  /// The jobs (jobs.ts): one a chat had running started again in its session (what it is named by, or throws why
  /// not), whether one like it runs there already, and a word told to a session's agent as theirs are (`say`). None: a
  /// station's jobs not started again (a test's).
  jobs?: {
    start(session: string, j: { name: string; command: string; cwd: string; port: number | null; watch: boolean }): { id: string; name: string; port: number | null };
    running(session: string, name: string, command: string): boolean;
    say(session: string, text: string): void;
  };
  /// The agent home of `ws` here (its MEMORY.md, skills/, presets.json): what goes along from it, and where one taken
  /// here is merged (null: none goes, none is merged).
  agentHome?: (ws: string) => string | null;
  /// Whether a session here asked for the retirement of `station` with station_retire (retire-asks.ts): what that
  /// station tells of it (`retire.tell`) is told its agent.
  drives?: (station: string, session: string) => boolean;
  /// Whether a session is one of `ws`'s chats here (it goes along as they move).
  ofWorkspace?: (session: string, ws: string) => boolean;
  /// What keeps the station from updating itself while the hand-over goes on (updates/holds.ts `hold`, unless a test
  /// says): its let-go.
  hold?: () => () => void;
};

/// The steps of a take here that an update of this station would cut (what it was sent put in place, the worktrees
/// made, the copy brought for its restart, that restart's own start): held from the take until it took them or could
/// not. Its own restart to put them in is no update, and goes on.
const TAKING_HELD: ReadonlySet<TakingStep> = new Set(["placing", "gits", "copy", "restart"]);

const retiringFile = (data: string) => join(data, "replica", "retiring.json");
const takingDir = (data: string) => join(data, "replica", "taking");
const dropsFile = (data: string) => join(data, "replica", "drops-owed.json");
const carryRoot = (data: string) => join(data, "replica", "carry");
const takenFile = (data: string) => join(data, "replica", "taken.json");
const scratchDir = (data: string) => join(data, "replica", "carrying");

function readJsonNow<T>(path: string): T | null {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as T; // sync: read once, before the station serves
  } catch {
    return null;
  }
}

async function writeJson(path: string, v: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  // (a file of its own each time: two writes of the same file at once, the run's and the driver's told, each rename
  // their own, the later one's last)
  const tmp = `${path}.${randomBytes(4).toString("hex")}.tmp`;
  await writeFile(tmp, JSON.stringify(v));
  await rename(tmp, path);
}

const there = (path: string) => stat(path).then(() => true, () => false);

const gitRun = (dir: string, args: string[]): Promise<string> =>
  new Promise((resolve, reject) => {
    execFile("git", ["-C", dir, ...args], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: 30 * 60_000, env: { ...process.env, GIT_TERMINAL_PROMPT: "0", GIT_SSH_COMMAND: "ssh -o BatchMode=yes" } }, (e, out, err) =>
      e ? reject(new Error(String(err).trim() || e.message)) : resolve(String(out).trim()));
  });

const gitHere = (): Promise<boolean> =>
  new Promise((resolve) => execFile("git", ["--version"], { timeout: 30_000 }, (e) => resolve(e === null)));

/// The bytes free where `data` is; a copy there a clone where the disk makes them (APFS: macOS).
const roomHere = (data: string) => async () => {
  const s = await statfs(data).catch(() => null);
  return { free: s === null ? null : Number(s.bavail) * Number(s.bsize), clones: platform.clonesFiles };
};

/// `carry-worker.ts`'s work in a thread of its own, ended at once where `signal` says (a cancel).
function inThread<T>(asked: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
  const file = new URL(import.meta.url.endsWith(".ts") ? "./carry-worker.ts" : "./replica/carry-worker.js", import.meta.url);
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new Error("called off"));
    const w = new Worker(file, { workerData: { carry: asked } });
    const stop = () => {
      void w.terminate();
      reject(new Error("called off"));
    };
    signal?.addEventListener("abort", stop, { once: true });
    const done = () => signal?.removeEventListener("abort", stop);
    w.once("message", (m: { answer?: T; error?: string }) => (done(), m.error !== undefined ? reject(new Error(m.error)) : resolve(m.answer as T)));
    w.once("error", (e) => (done(), reject(e)));
  });
}
export const gatherSoon = (dataDir: string, db: string, ws: string, home: boolean, scratch: string, signal?: AbortSignal, agent: string | null = null) => inThread<Gathered>({ op: "gather", dataDir, db, ws, home, scratch, agent }, signal);
export const placeSoon = (dataDir: string, index: string, from: string) => inThread<{ placed: number; missing: number; kept: number }>({ op: "place", dataDir, index, from });
export const previewSoon = (dataDir: string, db: string, ws: string, home: boolean) => inThread<{ chats: number; archived: number; outside: number }>({ op: "preview", dataDir, db, ws, home });

/// What a retirement of a workspace would move, as the app shows it before a person retires the station (GET
/// /retire/preview): found as the retirement finds it (the same predicates), nothing of it moved.
export type Preview = { home: boolean; chats: number; archived: number; connects: { id: string; name: string; kind: string }[]; accounts: { id: string; name: string }[]; accountsStay: { id: string; name: string }[]; jobs: { name: string; session: string }[]; outside: number };

/// How this station's connect ids go on `to`: its own (`id`) are `id@<here>` there; one of `to`'s (`id@<to>`) is `id`.
export function connectsThere(own: string[], used: string[], here: string, to: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const id of new Set([...own, ...used])) {
    const there = own.includes(id) || id.includes("@") ? localOf(knownOf(id, here), to) : id;
    if (there !== id) out[id] = there;
  }
  return out;
}

const gb = (n: number) => `${(n / 1024 ** 3).toFixed(1)} GB`;

/// What came of a moved chat's jobs on the station they went to, in a sentence (empty: none).
export function jobWords(jobs: JobOutcome[]): string {
  if (jobs.length === 0) return "";
  const started = jobs.filter((j) => j.started).map((j) => j.name);
  const not = jobs.filter((j) => !j.started).map((j) => `${j.name} (${j.old === true ? "from a station before jobs moved" : (j.why ?? "not started")})`);
  return [
    started.length > 0 ? `Jobs started again there: ${started.join(", ")}.` : "",
    not.length > 0 ? `Not started again: ${not.join("; ")}.` : "",
  ].filter((x) => x !== "").join(" ");
}

/// The other station's disk cannot hold what is sent.
class Full extends Error {}

/// What a moved chat's agent is told once (with what it is next handed: sessions/actor.ts): where it came from, where
/// its files are now, how a worktree still naming the old place is mended, what came of its jobs (`jobs`: as they were
/// started again here; none, a station that started none: they did not move).
export function movedNote(from: string, here: string, index: CarryIndex, s: CarriedSession, dataDir: string, reposDir: string, jobs: JobOutcome[] | null = null): string {
  const lines = [
    `<chat-moved>This chat moved here from station ${from || "(retired)"}, which was retired from this workspace: it goes on on this station${here ? ` (${here})` : ""}.`,
  ];
  if (s.room === null) lines.push(`Its working directory ${s.workspace} was not the station's own and did not move: it is not on this machine unless it was here already.`);
  else lines.push(`Its files were under ${index.dataDir} and are under ${dataDir} now: a path you noted under the old one is the same under the new one (your working directory is ${moved(s.workspace, index.dataDir, dataDir)}).`);
  lines.push(`A git worktree that still names the old place is mended with \`git worktree repair <its directory>\` run in its repository under ${reposDir}.`);
  const named = (j: { name: string; command: string }) => `${j.name} (\`${j.command}\`)`;
  const mine = index.jobs.filter((j) => j.session === s.key);
  const outcomes = jobs?.filter((j) => j.session === s.key) ?? null;
  const notMoved = outcomes === null ? mine : outcomes.filter((j) => j.old === true);
  if (notMoved.length > 0) lines.push(`These background jobs and services of it did not move and are not running: ${notMoved.map(named).join("; ")}. Start again those still needed.`);
  const started = outcomes?.filter((j) => j.started) ?? [];
  if (started.length > 0) lines.push(`These background jobs and services of it were started again here, as after a restart of the station, in the same directories under the new place: ${started.map((j) => `${named(j)}${j.id === null ? "" : `, ${j.id}`}`).join("; ")}.`);
  const not = outcomes?.filter((j) => !j.started && j.old !== true) ?? [];
  if (not.length > 0) lines.push(`These were not started again: ${not.map((j) => `${named(j)}: ${j.why ?? "not started"}`).join("; ")}. Start again those still needed.`);
  lines.push("It is said once; nobody asked anything of you by it.</chat-moved>");
  return lines.join("\n");
}

export class Retire {
  readonly #d: RetireDeps;
  readonly #carried: FolderPlace;
  readonly #git: (dir: string, args: string[]) => Promise<string>;
  readonly #work: { gather: typeof gatherSoon; place: typeof placeSoon; preview?: typeof previewSoon };
  readonly #room: () => Promise<{ free: number | null; clones: boolean }>;
  readonly #hasGit: () => Promise<boolean>;
  readonly #lackMost: number;
  #state: State | null;
  #running: Promise<void> | null = null;
  /// Asked to run again as the run under way ends (the other station said it took them meanwhile).
  #more = false;
  /// The run under way asked to stop between files, its gathering ended (a cancel).
  #stopping = false;
  #abort: AbortController | null = null;
  #again: (() => void) | null = null;
  #tries = 0;
  /// Since when the other station has not been reached, its chats stopped (none: it was, or they work): a hand-over not
  /// reached for QUIET_UNREACHED_MS falls back.
  #unreachedSince: number | null = null;
  /// The holds on updating this station (`#holdsNow`): while its chats stop and are handed over, and each take here
  /// under way, by its origin.
  readonly #hold: () => () => void;
  #retiringHeld: (() => void) | null = null;
  readonly #takingHeld = new Map<string, () => void>();
  /// Since when sending the files has failed in a row, each tried again by itself (null: it has not).
  #sendingFailedSince: number | null = null;
  /// The writes of `retiring.json`, one after another.
  #writes: Promise<void> = Promise.resolve();
  /// What is owed to the driver being told (`#driverSoon`), and its retry.
  #driving: Promise<void> | null = null;
  #driverAgain: (() => void) | null = null;
  #driverTries = 0;
  /// A person asked it again: the other station puts in again a copy it could not put in (`retire.take`'s `again`).
  #retake = false;
  #closed = false;
  readonly #taking = new Map<string, Taking>();
  readonly #takingRuns = new Map<string, Promise<void>>();
  readonly #takeAgain = new Map<string, () => void>();
  readonly #tellRuns = new Map<string, Promise<void>>();
  readonly #tellAgain = new Map<string, () => void>();
  #drops: DropOwed[];
  /// The retired stations' chats taken here lately (`takenFile`), read as the station starts.
  #tookHere: Taken[];
  #dropping: Promise<void> | null = null;
  #dropAgain: (() => void) | null = null;
  #dropTries = 0;
  #telling: (() => void) | null = null;

  /// Where each side stood, read as the station starts, before it serves: what it is taking is known before its copies
  /// could hand over a copy it is taking (copies.ts `#handOver`), and a retired station's chats are quiet again before
  /// its agents are taken up.
  constructor(d: RetireDeps) {
    this.#d = d;
    this.#carried = new FolderPlace(carryRoot(d.data));
    this.#git = d.git ?? gitRun;
    this.#work = d.work ?? { gather: gatherSoon, place: placeSoon };
    this.#room = d.room ?? roomHere(d.data);
    this.#hasGit = d.hasGit ?? gitHere;
    this.#lackMost = d.lackMost ?? LACK_MOST;
    this.#hold = d.hold ?? holdUpdates;
    this.#state = readJsonNow<State>(retiringFile(d.data));
    if (this.#state !== null) {
      const st = this.#state;
      st.jobs ??= [];
      st.take ??= null;
      st.accountsLeft ??= [];
      st.wait ??= false;
      st.driver ??= null;
      st.owed ??= [];
      st.files ??= 0;
      st.sentAt ??= null;
      st.retake ??= false;
      st.jobsThere ??= null;
      st.toldError ??= null;
    }
    this.#drops = readJsonNow<DropOwed[]>(dropsFile(d.data)) ?? [];
    this.#tookHere = readJsonNow<Taken[]>(takenFile(d.data)) ?? [];
    let names: string[] = [];
    try {
      names = readdirSync(takingDir(d.data)); // sync: read once, before the station serves
    } catch {}
    for (const name of names) {
      const t = readJsonNow<Taking>(join(takingDir(d.data), name));
      if (t !== null && STATION.test(t.origin)) {
        this.#taking.set(t.origin, { ...t, bindings: t.bindings ?? {}, rooms: t.rooms ?? null, told: t.told ?? false, restarts: t.restarts ?? 0, driver: t.driver ?? null, jobs: t.jobs ?? null, jobsTold: t.jobsTold ?? false, home: t.home ?? false, driverTold: t.driverTold ?? false });
      }
    }
    const s = this.#state;
    if (s !== null && stopped(s.step)) void this.#quiet(s).catch((e) => log.warn("retire", "a retired station's chats not quiet yet", { error: (e as Error).message }));
    // (held again as the process starts, before the updater can decide: a hold is this process's)
    this.#holdsNow();
  }

  /// Begun (the mesh attached): where each side stood, gone on with.
  async start(): Promise<void> {
    for (const t of [...this.#taking.values()]) {
      if (this.#d.copies.formerly().includes(t.origin)) {
        // (this station started again having put a retired one's chats in: it is that one now)
        if (t.step !== "took") await this.#tookPlace(t);
        this.#tell(t);
      } else if (t.step === "restart") {
        // (started again for it, and the copy did not go in: said, and nothing more by itself, so it does not start
        // again and again; nor where the restore itself never said how it went, after RESTARTS_MOST starts)
        const o = this.#d.copies.restored();
        const failed = o !== null && o.origin === t.origin && o.error !== null && !o.pending
          ? o.error
          : t.restarts >= RESTARTS_MOST ? `this station started again ${t.restarts} times to put the chats in and they did not go in (its log says why): retry, or cancel on the station retired` : null;
        if (failed !== null) {
          t.step = "failed";
          t.error = failed;
          t.told = false;
          await this.#saveTaking(t);
          log.warn("retire", "a retired station's chats could not be put in here", { origin: t.origin, error: failed });
          this.#tell(t);
        } else this.#take(t);
      } else if (t.step === "failed") {
        if (!t.told) this.#tell(t);
      } else if (t.step === "took") this.#tell(t);
      else if (t.step !== "coming") this.#take(t);
    }
    this.#dropSoon();
    const s = this.#state;
    if (s === null) return;
    // (its chats stopped before this start: still stopped, a station retired from it for good)
    if (stopped(s.step)) await this.#quiet(s);
    if (s.step !== "done" && s.reason !== "failed") this.#go();
    this.#driverSoon();
  }

  async close(): Promise<void> {
    this.#closed = true;
    // (let go first: the next process holds again, as it starts, for what is still under way)
    this.#holdsNow();
    this.#again?.();
    this.#telling?.();
    this.#dropAgain?.();
    this.#driverAgain?.();
    for (const stop of [...this.#takeAgain.values(), ...this.#tellAgain.values()]) stop();
    // (the run under way ended between files, its gathering ended, as a cancel ends it: a gathering of a million files
    // goes on for minutes, and the process handing over to the next would wait for it. Each step is safe to run again,
    // and the next process goes on from where it stands)
    this.#stopping = true;
    this.#abort?.abort();
    await this.#running?.catch(() => {});
    await this.#dropping?.catch(() => {});
    await this.#driving?.catch(() => {});
    await Promise.all([...this.#takingRuns.values(), ...this.#tellRuns.values()].map((p) => p.catch(() => {})));
  }

  /// What is under way here brought to rest: what a test waits for (it does not wait on a timer).
  async settle(): Promise<void> {
    for (;;) {
      const going = [this.#running, this.#dropping, this.#driving, ...this.#takingRuns.values(), ...this.#tellRuns.values()].filter((p): p is Promise<void> => p !== null);
      if (going.length === 0) return;
      await Promise.all(going.map((p) => p.catch(() => {})));
    }
  }

  /// The origins whose chats this station is taking: their copies are not handed to the stations that keep them.
  takingNow(): Set<string> {
    return new Set([...this.#taking.values()].filter((t) => t.step !== "took").map((t) => t.origin));
  }

  /// The holds on updating this station as where each side stands says now, taken or let go of, each exactly once:
  /// called wherever that changes (`#changed`), as the process starts, and as it closes (all let go). Retired: held
  /// while sending, its chats stopping and handed over go on, until the other took them, it fell back to `sent`, it was
  /// called off: the sending too (the lead, 2026-11-14: a real retirement's station updated itself three times in one
  /// sending, each cut starting it again from gathering a million files, a beta every ten minutes). Not while it rests
  /// or waits: at `sent`, failed, the other's disk full or it from before, nor while the other is not reached (nothing
  /// goes on that an update would cut, and a hold must not outlast a station gone for good). Taking: each take while a
  /// step of TAKING_HELD (what comes while the other sends is only files written by their hash).
  #holdsNow(): void {
    const s = this.#state;
    const going = s !== null && (s.step === "sending" || s.step === "quiet" || s.step === "handing");
    const rests = s !== null && (s.reason === "failed" || s.reason === "full" || s.reason === "old" || s.reason === "offline");
    const retiring = !this.#closed && going && !rests;
    if (retiring && this.#retiringHeld === null) this.#retiringHeld = this.#hold();
    else if (!retiring && this.#retiringHeld !== null) {
      const letGo = this.#retiringHeld;
      this.#retiringHeld = null;
      letGo();
    }
    for (const t of this.#taking.values()) {
      if (!this.#closed && TAKING_HELD.has(t.step) && !this.#takingHeld.has(t.origin)) this.#takingHeld.set(t.origin, this.#hold());
    }
    for (const [origin, letGo] of [...this.#takingHeld]) {
      const t = this.#taking.get(origin);
      if (!this.#closed && t !== undefined && TAKING_HELD.has(t.step)) continue;
      this.#takingHeld.delete(origin);
      letGo();
    }
  }

  #changed(now: boolean): void {
    this.#holdsNow();
    if (now) {
      this.#telling?.();
      this.#telling = null;
      this.#d.changed();
      return;
    }
    if (this.#telling !== null) return;
    this.#telling = this.#d.fibers.after(TELL_MS, () => { // timer: a debounce of a burst (each file sent)
      this.#telling = null;
      this.#d.changed();
    });
  }

  // ── this station retired ──

  /// Retires this station from `ws`: its chats there go on on `to`, another station of it. `by`: who asked. Refused
  /// while a retirement is recorded (one that failed is called off first: two stations would take the chats). `wait`:
  /// it waits at `sent` for a person to confirm the hand-over (one an agent asked for); `driver`: who is told of it.
  async retire(ws: string, to: string, by: string, opts: { wait?: boolean; driver?: Driver | null } = {}): Promise<void> {
    const here = this.#d.here();
    if (!WORKSPACE.test(ws) || !STATION.test(to) || here === null) throw new Refused("not a station");
    if (this.#state !== null) {
      throw new Refused(this.#state.step === "done"
        ? "this station was retired from a workspace already: its chats went to another station"
        : `this station is being retired already, its chats going to ${this.#state.toName || "another station"}: cancel that first`);
    }
    if (to === here) throw new Refused("the chats go to another station");
    const roster = this.#d.roster(ws) ?? [];
    const target = roster.find((s) => s.id === to);
    if (target === undefined) throw new Refused("that station is not one of this workspace's");
    // (that station answers, and knows how: told before anything stops)
    await this.#d.ask(to, { method: "retire.begin", workspace: ws, origin: here, name: roster.find((s) => s.id === here)?.name ?? "" }).catch((e) => {
      if (e instanceof Refused) throw new Refused(/no such retire request|unknown/.test(e.message) ? "that station is from before stations could be retired: update it first" : `that station refused it: ${e.message}`);
      throw new Refused("that station is not reached now: try again once it is up");
    });
    if (this.#state !== null) throw new Refused("this station is being retired already");
    // (a drop owed to it from a retirement called off before: this one begins anew there)
    this.#drops = this.#drops.filter((x) => !(x.to === to && x.workspace === ws));
    await writeJson(dropsFile(this.#d.data), this.#drops);
    this.#state = {
      workspace: ws, to, toName: target.name, by, at: this.#d.fibers.now(), step: "sending", done: 0, total: 0, error: null, reason: null, jobs: [], take: null, accountsLeft: [],
      wait: opts.wait === true, driver: opts.driver ?? null, owed: [], files: 0, sentAt: null, retake: false, jobsThere: null, toldError: null,
    };
    await writeJson(retiringFile(this.#d.data), this.#state);
    this.#changed(true);
    this.#go();
  }

  #go(): void {
    if (this.#closed) return;
    if (this.#running !== null) {
      this.#more = true;
      return;
    }
    this.#again?.();
    this.#again = null;
    this.#more = false;
    this.#abort = new AbortController();
    this.#running = this.#run(this.#abort.signal)
      .then(() => {
        this.#tries = 0;
        this.#unreachedSince = null;
        this.#sendingFailedSince = null;
      }, async (e) => {
        const s = this.#state;
        if (s === null || this.#stopping) return;
        const message = (e as Error).message;
        log.warn("retire", "a step of the retirement failed", { step: s.step, to: s.to, error: message });
        s.error = message;
        s.reason = e instanceof Full || /ENOSPC|disk is full|no space left/i.test(message) ? "full"
          : e instanceof Refused && /no such retire request/.test(message) ? "old"
          : e instanceof Refused ? "error"
          : /not reached|unreachable|timed out|no route|closed/i.test(message) ? "offline" : "error";
        this.#changed(true);
        // (the chats stopped and the other station not reached for QUIET_UNREACHED_MS, the retries in it as the backoff
        // gives them, before it was asked to take them: they work again here, rather than sit stopped for as long as it
        // is away. Once it was asked, it may be taking them: as a cancel, they stay stopped until it answers)
        const unreached = s.reason === "offline" && s.step === "quiet" && s.take === null;
        if (!unreached) this.#unreachedSince = null;
        else this.#unreachedSince ??= this.#d.fibers.now();
        if (unreached && this.#d.fibers.now() - this.#unreachedSince! >= QUIET_UNREACHED_MS) {
          this.#tries = 0;
          this.#unreachedSince = null;
          await this.#fallBack(s).catch((x) => log.warn("retire", "the chats not put back to work", { error: (x as Error).message }));
          return;
        }
        // (what needs someone, while the chats still work, said once to who asked for it: at once what does not go on by
        // itself; what is tried again by itself (`error`, `offline`: the other not reached, a stream cut by this
        // station's own update) only once it has failed for RETRY_MOST_MS in a row, as most of it is gone past by the
        // next try)
        if (s.step !== "sending") this.#sendingFailedSince = null;
        else {
          const now = this.#d.fibers.now();
          this.#sendingFailedSince ??= now;
          const retried = s.reason === "error" || s.reason === "offline";
          const failing = now - this.#sendingFailedSince;
          const told = retried ? `retried since ${this.#sendingFailedSince}` : message;
          if ((!retried || failing >= RETRY_MOST_MS) && s.toldError !== told) {
            s.toldError = told;
            await this.#toDriver(s, retried
              ? `Retiring this station: sending the files to ${s.toName || "the other station"} has been failing for ${Math.round(failing / 60_000)} min (${s.reason}): ${message}. The chats still work here; the station goes on trying by itself. Look at what keeps it (station_retire status, station_task on that station), or cancel.`
              : `Retiring this station: sending the files to ${s.toName || "the other station"} failed (${s.reason}): ${message}. The chats still work here; it is tried again by itself, but this needs someone: fix it (or call station_retire again after), or cancel.`);
          }
        }
        const wait = Math.min(RETRY_MS * 2 ** this.#tries, RETRY_MOST_MS);
        this.#tries++;
        if (!this.#closed) this.#again = this.#d.fibers.after(wait, () => this.#go()); // timer: a retry after a failure
      })
      .finally(() => {
        this.#running = null;
        this.#abort = null;
        if (this.#more && !this.#stopping) this.#go();
      });
  }

  /// Where this station stands, written: as it is now, after what was being written (the run's steps and the driver
  /// told write it each), so the last written is the latest.
  async #save(): Promise<void> {
    const s = this.#state;
    if (s !== null) {
      const now = JSON.parse(JSON.stringify(s));
      const write = this.#writes.then(() => writeJson(retiringFile(this.#d.data), now));
      this.#writes = write.catch(() => {});
      await write;
    }
    this.#changed(true);
  }

  /// The chats stopped (again, as it starts again), and the jobs that stopped with them kept with what goes along.
  async #quiet(s: State): Promise<void> {
    const stopped = await this.#d.quiet(s.workspace);
    const fresh = stopped.filter((j) => !s.jobs.some((k) => k.session === j.session && k.name === j.name && k.command === j.command));
    if (fresh.length === 0 || this.#state !== s) return;
    s.jobs.push(...fresh);
    await this.#save();
  }

  async #run(signal: AbortSignal): Promise<void> {
    const s = this.#state;
    const here = this.#d.here();
    if (s === null || here === null) return;
    // (all of it there, waiting for a person to confirm the hand-over: nothing until then, why it waits kept)
    if (s.step === "sent" && s.wait) return;
    s.error = null;
    s.reason = null;
    this.#holdsNow();
    const ws = s.workspace;
    const home = this.#d.home() === ws;
    const db = join(this.#d.data, "stillfail.db");
    const agent = this.#d.agentHome?.(ws) ?? null;
    const gather = async () => {
      const g = await this.#work.gather(this.#d.data, db, ws, home, scratchDir(this.#d.data), signal, agent);
      if (g.skipped > 0) log.warn("retire", "sessions whose directory is not the station's own: their files stay", { n: g.skipped });
      return g;
    };
    if (s.step === "sending") {
      // What goes along, while the chats still work: most of it is there before they stop. Not begun where the other
      // station has not the room for it, or no git for the worktrees it is to make again.
      const g = await gather();
      if (this.#stopping) return;
      const room = (await this.#d.ask(s.to, { method: "retire.room", workspace: ws, origin: here })) as Room;
      if (g.gits > 0 && room?.git === false) {
        throw new Error(`${s.toName || "that station"} has no git, and ${g.gits} git worktree${g.gits === 1 ? "" : "s"} here ${g.gits === 1 ? "is" : "are"} to be made again there: install git on that station first, then retry`);
      }
      // (what is sent is kept until it is put in: twice the room where a copy there is not a clone)
      const need = g.bytes * (room?.clones === true ? 1 : 2) + HEADROOM + Math.ceil(g.bytes / 20);
      if (typeof room?.free === "number" && need > room.free) {
        throw new Full(`${s.toName || "that station"} has ${gb(room.free)} free and this needs ${gb(need)}: free some room there, or cancel and pick another station`);
      }
      await this.#send(s, g, here, false);
      if (this.#stopping) return;
      s.step = "sent";
      s.files = g.files;
      s.sentAt = this.#d.fibers.now();
      s.toldError = null;
      await this.#save();
      if (s.wait) {
        const took = Math.max(0, Math.round((s.sentAt - s.at) / 1000));
        await this.#toDriver(s, `Retiring this station: everything that goes along is on ${s.toName || "the other station"} (${s.files} files, ${gb(s.total)}, in ${took} s); the chats still work here. What changes from now on is sent once they stop. Nothing more happens until the hand-over is confirmed: call station_retire hand_over (it posts a card that an owner or admin confirms in the still.fail app; it pauses the chats).`);
        return;
      }
    }
    if (s.step === "sent") {
      s.step = "quiet";
      await this.#save();
    }
    if (s.step === "quiet") {
      // (a hand-over that failed before told that station to keep what it has and put in nothing by itself: it knows
      // that before it is sent anything more)
      await this.#keepOwedTo(s, here);
      // (after a hand-over that failed, it begins again there: the files it holds stay, and one from before, which let
      // go of them as it was told, takes them anew)
      if (s.retake) await this.#d.ask(s.to, { method: "retire.begin", workspace: ws, origin: here, name: this.#hereName(ws) });
      await this.#quiet(s);
      // What changed since, then the chats' copy as they are now, and what goes along with them said last.
      const g = await gather();
      if (this.#stopping) return;
      const carry = await this.#send(s, g, here, true);
      if (this.#stopping || carry === null) return;
      const gen = await this.#d.copies.bringTo(ws, s.to);
      const own = this.#d.connectsOf(ws);
      const used = await this.#used(db, ws, home);
      s.take = { gen, carry, connects: connectsThere(own, used, here, s.to), bindings: this.#d.bindingsOf(own), driver: s.driver };
      s.step = "handing";
      await this.#save();
      await rm(scratchDir(this.#d.data), { recursive: true, force: true });
    }
    if (s.step === "handing") {
      // (asked again as it starts again here, or as a person asks it again: it says whether it took them; else it
      // tells, `retire.took` or `retire.failed`)
      const t = s.take;
      if (t === null) throw new Error("what the other station was to take is not known: cancel it and retire this station again");
      const again = this.#retake || s.retake;
      const answer = await this.#d.ask(s.to, { method: "retire.take", workspace: ws, origin: here, name: this.#d.roster(ws)?.find((r) => r.id === here)?.name ?? "", ...t, again });
      if (again) {
        this.#retake = false;
        s.retake = false;
      }
      if (typeof answer?.failed === "string") {
        // (it could not put them in, and says so again: the chats back to work here, until a person confirms it again)
        s.error = answer.failed || "that station could not put the chats in";
        s.reason = "failed";
        await this.#fallBack(s);
        return;
      }
      if (answer?.took !== true) return;
      await this.#tookThere(s, answer);
    }
    if (s.step === "accounts") {
      // This station's accounts go there too, retired from its home workspace (one staying in other workspaces keeps
      // them for those): each that cannot be moved is said, and the step goes on.
      for (const p of this.#d.accounts.own()) {
        if (s.accountsLeft.some((a) => a.id === p.id && a.error === "")) continue;
        try {
          await this.#d.accounts.move(p.id, s.to);
          s.accountsLeft = s.accountsLeft.filter((a) => a.id !== p.id);
        } catch (e) {
          log.warn("retire", "an account did not move with the retirement", { profile: p.id, error: (e as Error).message });
          s.accountsLeft = [...s.accountsLeft.filter((a) => a.id !== p.id), { id: p.id, name: p.name, error: (e as Error).message }];
        }
        await this.#save();
      }
      s.step = "connects";
      await this.#save();
      if (s.accountsLeft.length > 0) {
        await this.#toDriver(s, `Retiring station ${this.#hereName(ws)}: these accounts did not move to ${s.toName || "the other station"} and are still on the retired one: ${s.accountsLeft.map((a) => `${a.name}: ${a.error}`).join("; ")}. Sign them in there (the login tool) or move them by hand in the app, before the retired station is taken out.`);
      }
    }
    if (s.step === "connects") {
      await this.#d.moveConnects(ws, s.to);
      s.step = "done";
      await this.#save();
      log.info("retire", "this station's chats of a workspace went on another station", { workspace: ws, to: s.to });
      await this.#toDriver(s, `Retiring station ${this.#hereName(ws)} is done: its chats, accounts and connects are on ${s.toName || "the other station"}. Check there that a chat goes on, its worktrees and jobs, and its logins (see the stillfail-retire skill). Taking the retired station out of the workspace is a person's own step in the app (its station page offers it).`);
    }
  }

  /// This station's name in `ws`, as its roster says.
  #hereName(ws: string): string {
    const here = this.#d.here();
    return this.#d.roster(ws)?.find((r) => r.id === here)?.name || (here ?? "").slice(0, 12);
  }

  /// The other station took this one's place: its chats there are that station's now, out of sight here so that
  /// nobody sees each twice; then the accounts (retired from its home workspace) or the connects. `answer`: what it
  /// said (`retire.took`): what came of the jobs there, whether it told the driver itself.
  async #tookThere(s: State, answer?: Json): Promise<void> {
    this.#d.retired(s.workspace);
    // (the same test as the preview's)
    s.step = this.#d.home() === s.workspace ? "accounts" : "connects";
    s.error = null;
    s.reason = null;
    if (Array.isArray(answer?.jobs)) s.jobsThere = answer.jobs as JobOutcome[];
    const here = this.#d.here();
    const d = s.driver;
    // (a driver that was one of the chats moved is on the station they went to now: told there from here on)
    const moved = d !== null && d.station === here && (this.#d.ofWorkspace?.(d.session, s.workspace) ?? true);
    if (d !== null && moved) s.driver = { station: s.to, session: d.session };
    await this.#save();
    // (one that moved there was told there, by the station that took them; a station from before tells nothing)
    if (d !== null && !(moved && answer?.driverTold === true)) {
      const jobs = s.jobsThere === null ? "" : ` ${jobWords(s.jobsThere)}`;
      await this.#toDriver(s, `Retiring this station: ${s.toName || "the other station"} took its chats; they go on there.${jobs} Its ${s.step === "accounts" ? "accounts, then its connects" : "connects"} move next.`);
    }
  }

  /// The chats back to work here, as the hand-over did not go through (`s.error` and `s.reason` say why), resting at
  /// `sent` until a person confirms it again: what a cancel does for them (unquiet, what their platforms said meanwhile
  /// taken here, their jobs started again), the other station told to put in nothing of it by itself and keep what it
  /// was sent (`retire.drop` with `keep`, told until it answers), so the next hand-over sends only what changed.
  async #fallBack(s: State): Promise<void> {
    if (this.#state !== s || (s.step !== "quiet" && s.step !== "handing")) return;
    const here = this.#d.here();
    const ws = s.workspace;
    // (that station told first: one that says it is about to put them in after all, or is putting them in just now,
    // takes them, and the chats stay stopped for it; one not reached is told once it is up, before anything more is
    // sent there: it was not asked to take them, or said it could not)
    let owed = false;
    if (here !== null) {
      const answer = await this.#d.ask(s.to, { method: "retire.drop", workspace: ws, origin: here, keep: true }).catch((e) => {
        if (e instanceof Refused) return { refused: e.message };
        owed = true;
        return null;
      });
      if (answer?.took === true || typeof answer?.refused === "string") {
        log.warn("retire", "a hand-over that failed not called off: the station picked may put the chats in", { to: s.to, answer });
        if (answer?.took === true && s.step === "handing") {
          s.error = null;
          s.reason = null;
        }
        // (where it rests failed, nothing here goes on that an update would cut: let go)
        await this.#save();
        return;
      }
    }
    const jobs = s.jobs;
    s.step = "sent";
    s.wait = true;
    s.take = null;
    s.retake = true;
    s.jobs = [];
    this.#again?.();
    this.#again = null;
    if (owed) {
      this.#drops = [...this.#drops.filter((x) => !(x.to === s.to && x.workspace === ws)), { to: s.to, workspace: ws, keep: true }];
      await writeJson(dropsFile(this.#d.data), this.#drops);
      this.#dropSoon();
    }
    await this.#save();
    this.#d.unquiet(ws);
    const back = this.#jobsBack(s, jobs, `The move of this chat to station ${s.toName || s.to.slice(0, 12)} did not go through, and it works here again`);
    log.warn("retire", "a hand-over did not go through: the chats work here again", { to: s.to, reason: s.reason, error: s.error });
    await this.#toDriver(s, `Retiring this station: the hand-over to ${s.toName || "the other station"} failed (${s.reason}): ${s.error}. The station already put the chats back to work here${back === "" ? "" : ` (${back})`}; what was sent stays there, so the next hand-over sends only what changed. Fix the cause, then call station_retire hand_over again (a person confirms it again), or cancel.`);
  }

  /// The jobs a chat stopped as its chats did, started again here (the move called off or failed: `why`), each told to
  /// its agent; what came of them in a few words.
  #jobsBack(s: State, jobs: CarriedJob[], why: string): string {
    const j = this.#d.jobs;
    if (j === undefined) return "";
    let started = 0;
    for (const job of jobs) {
      if (job.cwd === undefined || j.running(job.session, job.name, job.command)) continue;
      let error: string | null = null;
      let made: { id: string; name: string; port: number | null } | null = null;
      try {
        made = j.start(job.session, { name: job.name, command: job.command, cwd: job.cwd, port: job.port ?? null, watch: job.watch === true });
        started++;
      } catch (e) {
        error = (e as Error).message;
      }
      j.say(job.session, movedSaid(why, made ?? { name: job.name, port: job.port ?? null }, error));
    }
    void s;
    return started === 0 ? "" : `${started} job${started === 1 ? "" : "s"} started again`;
  }

  /// A drop with `keep` owed to the station picked, told it before anything more is sent there (thrown where it is not
  /// reached: the step is tried again).
  async #keepOwedTo(s: State, here: string): Promise<void> {
    const owed = this.#drops.find((x) => x.to === s.to && x.workspace === s.workspace && x.keep === true);
    if (owed === undefined) return;
    await this.#d.ask(s.to, { method: "retire.drop", workspace: s.workspace, origin: here, keep: true });
    this.#drops = this.#drops.filter((x) => x !== owed);
    await writeJson(dropsFile(this.#d.data), this.#drops);
  }

  /// `text` to be told to the driver, kept until it is (`#driverSoon`).
  async #toDriver(s: State, text: string): Promise<void> {
    if (s.driver === null) return;
    s.owed.push(text);
    await this.#save();
    this.#driverSoon();
  }

  /// What is owed to the driver told, in order: a session here by the station's word (hub.notify, which wakes it), one
  /// elsewhere asked of its station (`retire.tell`) until it answers; one refused (its session gone, a station from
  /// before) let go.
  #driverSoon(): void {
    const s = this.#state;
    if (this.#driving !== null || this.#closed || s === null || s.driver === null || s.owed.length === 0) return;
    this.#driverAgain?.();
    this.#driverAgain = null;
    this.#driving = (async () => {
      const here = this.#d.here();
      let left = false;
      while (this.#state === s && s.driver !== null && s.owed.length > 0) {
        const d = s.driver;
        const text = s.owed[0]!;
        try {
          if (d.station === here) this.#d.tell?.(d.session, text);
          else await this.#d.ask(d.station, { method: "retire.tell", workspace: s.workspace, session: d.session, text });
        } catch (e) {
          if (d.station !== here && !(e instanceof Refused)) {
            left = true;
            break;
          }
          log.warn("retire", "who asked for the retirement not told", { session: d.session, error: (e as Error).message });
        }
        s.owed.shift();
        await this.#save();
      }
      if (!left) {
        this.#driverTries = 0;
        return;
      }
      const wait = Math.min(RETRY_MS * 2 ** this.#driverTries, RETRY_MOST_MS);
      this.#driverTries++;
      if (!this.#closed) this.#driverAgain = this.#d.fibers.after(wait, () => this.#driverSoon()); // timer: a retry after a failure
    })().finally(() => {
      this.#driving = null;
    });
  }

  /// The connect ids this station's chats of `ws` name.
  async #used(db: string, ws: string, home: boolean): Promise<string[]> {
    const { DatabaseSync } = await import("node:sqlite");
    const d = new DatabaseSync(db, { readOnly: true });
    try {
      return (d.prepare(`SELECT DISTINCT connect FROM sessions WHERE ${home ? "(ws = ? OR ws IS NULL)" : "ws = ?"}`).all(ws) as { connect: string }[]).map((r) => r.connect);
    } finally {
      d.close();
    }
  }

  /// What the gathering `g` names that the other station lacks, sent: each session's list read as it streams, its hashes
  /// asked of in batches (`retire.lacking`, LACK_MOST at most), then the list itself; the index last, its hash said back
  /// (null: stopped). A file that changed since it was gathered is refused there: left for the next gathering while the
  /// chats work, gathered again (the step tried again) once they are stopped (`strict`). The agent home's list is one more.
  async #send(s: State, g: Gathered, here: string, strict: boolean): Promise<string | null> {
    const index = JSON.parse(await readFile(g.index, "utf8")) as CarryIndex;
    s.total = index.bytes;
    s.done = 0;
    this.#changed(true);
    for (const session of [...index.sessions, ...(index.agent ? [index.agent] : [])]) {
      let batch: { hash: string; path: string; size: number }[] = [];
      const lines = createInterface({ input: createReadStream(session.at), crlfDelay: Infinity });
      try {
        for await (const line of lines) {
          if (this.#stopping) return null;
          if (line === "") continue;
          const f = JSON.parse(line);
          if (typeof f?.hash !== "string") continue;
          batch.push({ hash: f.hash, path: f.path, size: f.size });
          if (batch.length >= this.#lackMost) {
            await this.#sendBatch(s, here, batch, strict);
            batch = [];
          }
        }
      } finally {
        lines.close();
      }
      await this.#sendBatch(s, here, batch, strict);
      if (strict) await this.#sendBatch(s, here, [{ hash: session.list, path: session.at, size: 0 }], true);
    }
    await this.#sendBatch(s, here, Object.entries(index.bundles).map(([hash, path]) => ({ hash, path, size: 0 })), strict);
    if (this.#stopping || !strict) return null;
    index.jobs = s.jobs;
    const text = Buffer.from(JSON.stringify(index));
    const hash = createHash("sha256").update(text).digest("hex");
    await this.#d.ask(s.to, withBytes({ method: "retire.put", workspace: s.workspace, origin: here, name: hash }, oneBytes(text)));
    return hash;
  }

  /// Of `batch`, what the other station lacks, sent.
  async #sendBatch(s: State, here: string, batch: { hash: string; path: string; size: number }[], strict: boolean): Promise<void> {
    if (batch.length === 0) return;
    const asked = [...new Set(batch.map((f) => f.hash))];
    const answer = await this.#d.ask(s.to, { method: "retire.lacking", workspace: s.workspace, origin: here, hashes: asked });
    const lacking = new Set<string>(Array.isArray(answer?.lacking) ? answer.lacking : asked);
    for (const f of batch) {
      if (this.#stopping) return;
      if (lacking.delete(f.hash)) {
        let size = 0;
        try {
          size = (await stat(f.path)).size;
        } catch {
          continue;
        }
        try {
          await this.#d.ask(s.to, withBytes({ method: "retire.put", workspace: s.workspace, origin: here, name: f.hash }, fileBytes(f.path, 0, size)));
        } catch (e) {
          if (!(e instanceof Refused && /changed/.test(e.message)) && !/got shorter/.test((e as Error).message)) throw e;
          if (strict) throw new Error("a file changed as it was sent: gathered again");
          continue;
        }
      }
      s.done += f.size;
      this.#changed(false);
    }
  }

  /// The other station says it took this one's place (`retire.took`): the accounts and connects next.
  async #took(peer: string, request?: Json): Promise<void> {
    const s = this.#state;
    if (s === null || s.to !== peer) return;
    if (s.step !== "handing") {
      // (it put in a copy after this station's chats went back to work: never so, as it was told to put in nothing)
      if (s.step === "sent" || s.step === "quiet") log.warn("retire", "the station picked says it took the chats while they work here", { to: peer, step: s.step });
      return;
    }
    await this.#tookThere(s, request);
    this.#go();
  }

  /// It says it could not put them in (`retire.failed`): the chats back to work here, nothing more until a person
  /// confirms the hand-over again or cancels.
  async #failed(peer: string, error: string): Promise<void> {
    const s = this.#state;
    if (s === null || s.to !== peer || s.step !== "handing") return;
    s.error = error || "that station could not put the chats in";
    s.reason = "failed";
    this.#again?.();
    this.#again = null;
    await this.#fallBack(s);
  }

  /// Called off (the settings' cancel), answered at once: the run under way stopped (its gathering ended), the other
  /// station told to drop what it was sent, and this station's chats go on here. Before the other was asked to take
  /// them, called off here whatever it answers (told again until it does, where it is not reached); after, not where it
  /// is not reached (it may be taking them), and never once it took them: each refusal says what to do.
  async cancel(ws: string): Promise<void> {
    const s = this.#state;
    const here = this.#d.here();
    if (s === null || s.workspace !== ws || here === null) return;
    const name = s.toName || "the other station";
    const tookWords = `${name} took this station's chats already: it goes on moving its accounts and connects there, and is done then`;
    if (s.step === "accounts" || s.step === "connects" || s.step === "done") throw new Refused(tookWords);
    this.#stopping = true;
    this.#again?.();
    this.#again = null;
    this.#abort?.abort();
    await this.#running?.catch(() => {});
    this.#stopping = false;
    const resume = () => {
      if (s.reason !== "failed") this.#go();
    };
    // (it may have gone on while the run under way was let finish)
    const now = s.step as Step;
    if (now === "accounts" || now === "connects" || now === "done") {
      this.#go();
      throw new Refused(tookWords);
    }
    let answer: Json;
    try {
      answer = await this.#d.ask(s.to, { method: "retire.drop", workspace: ws, origin: here });
    } catch (e) {
      if (e instanceof Refused) {
        resume();
        throw new Refused(/busy/.test(e.message) ? `${name} is putting the chats in just now: cancel again in a minute, or let it finish` : `${name} did not call it off: ${e.message}`);
      }
      if (s.take !== null) {
        resume();
        throw new Refused(`${name} is not reached, and may be taking the chats: they stay stopped here until it answers. Cancel again once it is up, or let the move finish`);
      }
      // (nothing there is put in before this station asks it to: called off here, that station told once it is up)
      this.#drops = [...this.#drops.filter((x) => !(x.to === s.to && x.workspace === ws)), { to: s.to, workspace: ws }];
      await writeJson(dropsFile(this.#d.data), this.#drops);
      answer = { dropped: true };
    }
    if (answer?.took === true) {
      await this.#took(s.to);
      throw new Refused(tookWords);
    }
    // (at `sent` the chats work already: a hand-over that failed put them back)
    if (stopped(s.step)) {
      this.#d.unquiet(ws);
      this.#jobsBack(s, s.jobs, `The move of this chat to station ${name} was called off, and it works here again`);
    }
    this.#state = null;
    // (nothing written of it after it is gone: what the driver's telling writes is of the state, none now; it is not
    // waited for, as it may be waiting on another station)
    await this.#writes;
    await rm(retiringFile(this.#d.data), { force: true });
    await rm(scratchDir(this.#d.data), { recursive: true, force: true });
    log.info("retire", "a retirement called off", { workspace: ws, to: s.to });
    this.#changed(true);
    this.#dropSoon();
  }

  /// The drops owed told, each until its station answers or is no longer of the workspace.
  #dropSoon(): void {
    if (this.#dropping !== null || this.#closed || this.#drops.length === 0) return;
    this.#dropAgain?.();
    this.#dropAgain = null;
    this.#dropping = (async () => {
      const here = this.#d.here();
      let left = false;
      for (const x of [...this.#drops]) {
        const roster = this.#d.roster(x.workspace);
        let done = roster !== null && !roster.some((r) => r.id === x.to);
        if (!done && here !== null) {
          done = await this.#d.ask(x.to, { method: "retire.drop", workspace: x.workspace, origin: here, ...(x.keep === true ? { keep: true } : {}) }).then(() => true, (e) => e instanceof Refused && !/busy/.test(e.message));
        }
        if (done) this.#drops = this.#drops.filter((y) => y !== x);
        else left = true;
      }
      await writeJson(dropsFile(this.#d.data), this.#drops);
      if (!left) {
        this.#dropTries = 0;
        return;
      }
      const wait = Math.min(RETRY_MS * 2 ** this.#dropTries, RETRY_MOST_MS);
      this.#dropTries++;
      if (!this.#closed) this.#dropAgain = this.#d.fibers.after(wait, () => this.#dropSoon()); // timer: a retry after a failure
    })().finally(() => {
      this.#dropping = null;
    });
  }

  /// Tried again now (the settings' retry): a step waiting to be tried again, or the other station asked again to take
  /// the chats it could not put in. Resting at `sent` after a hand-over that failed, it is the hand-over again where a
  /// person asks it in the app (`handOver`: POST /retire/again); an agent's `again` never pauses the chats.
  async again(ws: string, opts: { handOver?: boolean } = { handOver: true }): Promise<void> {
    const s = this.#state;
    if (s === null || s.workspace !== ws) throw new Refused("this station is not being retired from this workspace");
    if (s.step === "sent") {
      if (opts.handOver !== true) throw new Refused("it waits for the hand-over to be confirmed: station_retire hand_over posts the card an owner or admin confirms (it pauses the chats)");
      if (s.error === null) return;
      s.step = "quiet";
    } else if (s.error === null) return;
    this.#tries = 0;
    this.#unreachedSince = null;
    if (s.reason === "failed" && s.step === "handing") this.#retake = true;
    s.reason = null;
    await this.#save();
    this.#go();
  }

  /// The hand-over confirmed by a person (an owner or admin, in the app: retire-asks.ts): from `sent`, the chats stop
  /// and their copy goes. `by`: who confirmed it.
  async handOver(ws: string, by: string): Promise<void> {
    const s = this.#state;
    if (s === null || s.workspace !== ws) throw new Refused("this station is not being retired from this workspace");
    if (s.step !== "sent") {
      throw new Refused(s.step === "sending" ? "the files are still being sent: you are told once they are all there" : `it is past that: ${s.step} (station_retire status)`);
    }
    log.info("retire", "the hand-over confirmed", { workspace: ws, to: s.to, by });
    s.step = "quiet";
    s.error = null;
    s.reason = null;
    this.#tries = 0;
    this.#unreachedSince = null;
    await this.#save();
    this.#go();
  }

  /// What a station_retire asks of this station's retirement from `ws` (retire-asks.ts, here or over the mesh as
  /// `retire.ask`): `preview` (and, with `to`, how that station stands for it), `status`, `start` (a person confirmed
  /// it: `by`, the `driver` who asked), `hand_over` (confirmed, `by`), `again`, `cancel`. What it answers is data the
  /// tool puts in words.
  async agentAsk(ws: string, request: { op: string; to?: string; by?: string; driver?: Driver | null }): Promise<Json> {
    const status = () => this.#status(ws);
    switch (request.op) {
      case "preview": {
        const to = typeof request.to === "string" && STATION.test(request.to) ? request.to : null;
        return { station: { id: this.#d.here(), name: this.#hereName(ws) }, preview: await this.preview(ws), status: status(), to: to === null ? null : await this.#readiness(ws, to) };
      }
      case "status":
        return { station: { id: this.#d.here(), name: this.#hereName(ws) }, status: status() };
      case "start":
        if (typeof request.to !== "string" || typeof request.by !== "string") throw new Refused("to and by are needed");
        await this.retire(ws, request.to, request.by, { wait: true, driver: request.driver ?? null });
        return { status: status() };
      case "hand_over":
        await this.handOver(ws, typeof request.by === "string" ? request.by : "");
        return { status: status() };
      case "again":
        await this.again(ws, { handOver: false });
        return { status: status() };
      case "cancel":
        await this.cancel(ws);
        return { status: status() };
    }
    throw new Refused("no such station_retire action");
  }

  /// How the station `to` stands for taking this one's chats, as `retire.room` says it: reached or not, from before,
  /// its git and its room.
  async #readiness(ws: string, to: string): Promise<Json> {
    const here = this.#d.here();
    const name = this.#d.roster(ws)?.find((r) => r.id === to)?.name ?? "";
    if (here === null || to === here) return { id: to, name, reached: false, error: "that is this station" };
    try {
      const room = (await this.#d.ask(to, { method: "retire.room", workspace: ws, origin: here })) as Room;
      return { id: to, name, reached: true, free: room?.free ?? null, clones: room?.clones === true, git: room?.git === true };
    } catch (e) {
      if (e instanceof Refused) return { id: to, name, reached: true, old: /no such retire request|unknown/.test(e.message), error: e.message };
      return { id: to, name, reached: false, error: (e as Error).message };
    }
  }

  /// Where this station's retirement from `ws` stands, for station_retire, and the chats of retired stations taken here.
  #status(ws: string): Json {
    const o = this.overview(ws);
    const s = this.#state !== null && this.#state.workspace === ws ? this.#state : null;
    return {
      retiring: o.retiring === null || s === null ? null : {
        ...o.retiring, wait: s.wait, files: s.files, sentAt: s.sentAt, driver: s.driver, jobsThere: s.jobsThere,
        jobsStopped: s.jobs.map((j) => ({ session: j.session, name: j.name })),
      },
      taking: o.taking,
      taken: this.#takenNow().filter((t) => t.workspace === ws),
    };
  }

  #takenNow(): Taken[] {
    return this.#tookHere;
  }

  /// What retiring this station from `ws` would move (GET /retire/preview).
  async preview(ws: string): Promise<Preview> {
    const home = this.#d.home() === ws;
    const counts = await (this.#work.preview ?? previewSoon)(this.#d.data, join(this.#d.data, "stillfail.db"), ws, home);
    const own = this.#d.accounts.own().map((p) => ({ id: p.id, name: p.name }));
    return {
      home, chats: counts.chats, archived: counts.archived, outside: counts.outside,
      connects: this.#d.connectsNamed(ws),
      // (the accounts step moves them only out of the home workspace: `#tookThere`)
      accounts: home ? own : [],
      accountsStay: home ? [] : own,
      jobs: this.#d.jobsIn(ws).map((j) => ({ name: j.name, session: j.session })),
    };
  }

  // ── another station's chats taken here ──

  /// What this station answers of it (`retire.*`): from stations of the workspace, each of its own chats only; and, on
  /// the station retired, the one its chats go to telling how it went.
  answers(inWorkspace: (peer: string, ws: string) => boolean) {
    return async (peer: string, request: Json, workspace?: string): Promise<Json> => {
      const ws = typeof request?.workspace === "string" ? request.workspace : "";
      const bytes = bytesOf(request);
      try {
        if (!WORKSPACE.test(ws) || (workspace !== undefined && workspace !== ws) || !inWorkspace(peer, ws)) throw new Refused("not a station of this workspace");
        switch (request?.method) {
          case "retire.took":
            await this.#took(peer, request);
            return { ok: true };
          case "retire.failed":
            await this.#failed(peer, typeof request.error === "string" ? request.error : "");
            return { ok: true };
          case "retire.tell": {
            // (a station whose retirement a session here asked for, or one whose chats this station took, telling that
            // session how it goes: nothing else is told this way)
            const session = typeof request.session === "string" ? request.session : "";
            const text = typeof request.text === "string" ? [...request.text].slice(0, 4000).join("") : "";
            if (session === "" || text === "") throw new Refused("session and text are needed");
            if (!this.#d.copies.formerly().includes(peer) && this.#d.drives?.(peer, session) !== true) throw new Refused("no session here asked for that station's retirement");
            if (this.#d.tell === undefined) throw new Refused("nobody to tell here");
            try {
              this.#d.tell(session, text);
            } catch (e) {
              throw new Refused((e as Error).message);
            }
            return { ok: true };
          }
          case "retire.ask": {
            // (station_retire on another station of the workspace, asked of this one's retirement: its session is the
            // driver, on the station that asked)
            const op = typeof request.op === "string" ? request.op : "";
            const session = typeof request.session === "string" ? request.session : "";
            return await this.agentAsk(ws, { op, to: typeof request.to === "string" ? request.to : undefined, by: typeof request.by === "string" ? request.by : undefined, driver: session === "" ? null : { station: peer, session } });
          }
        }
        // (what a station sends and asks is of its own chats: it retires itself alone)
        if (request?.origin !== peer) throw new Refused("a station's own chats only");
        switch (request?.method) {
          case "retire.begin":
            return { ...(await this.#begin(peer, ws, request)), ...(await this.#roomHere()) };
          case "retire.room":
            return await this.#roomHere();
          case "retire.lacking": {
            const hashes = Array.isArray(request.hashes) ? request.hashes : [];
            if (hashes.length > this.#lackMost || !hashes.every((h: unknown) => typeof h === "string" && HASH.test(h))) throw new Refused(`at most ${this.#lackMost} files' hashes`);
            const t = this.#taking.get(peer);
            if (t === undefined || t.workspace !== ws) throw new Refused("not begun: retire.begin first");
            const files = join(this.#carried.dir(ws, peer), "files");
            const held = await Promise.all(hashes.map((h: string) => there(join(files, h))));
            return { lacking: hashes.filter((_: string, i: number) => !held[i]) };
          }
          case "retire.put": {
            const name = String(request.name ?? "");
            if (bytes === null || !HASH.test(name)) throw new Refused("not a file's hash");
            const t = this.#taking.get(peer);
            if (t === undefined || t.workspace !== ws) throw new Refused("not begun: retire.begin first");
            await this.#receive(ws, peer, name, bytes as Bytes);
            return { ok: true };
          }
          case "retire.take":
            return await this.#takeAsked(peer, ws, request);
          case "retire.drop":
            return request.keep === true ? await this.#keep(peer, ws) : await this.#drop(peer, ws);
        }
        throw new Refused("no such retire request");
      } finally {
        if (bytes !== null) await stopBytes(bytes).catch(() => {});
      }
    };
  }

  /// This station's disk and git, as a station sending it its chats asks.
  async #roomHere(): Promise<Room> {
    const [room, git] = await Promise.all([this.#room().catch(() => ({ free: null, clones: false })), this.#hasGit().catch(() => false)]);
    return { free: room.free, clones: room.clones, git };
  }

  async #saveTaking(t: Taking): Promise<void> {
    await writeJson(join(takingDir(this.#d.data), `${t.origin}.json`), t);
    this.#changed(true);
  }

  /// A station of the workspace says it is being retired, its chats coming here: kept, before anything comes.
  async #begin(origin: string, ws: string, request: Json): Promise<Json> {
    if (this.#d.copies.formerly().includes(origin)) return { ok: true, took: true };
    const was = this.#taking.get(origin);
    if (this.#takingRuns.has(origin) || was?.step === "restart" || was?.step === "took") throw new Refused("busy: this station is putting in what that station sent before");
    // (what was sent before stays: only what it lacks is sent again; the rooms an earlier placing made are still to go
    // where it is called off)
    const t: Taking = {
      origin, name: typeof request.name === "string" ? request.name : (was?.name ?? ""), workspace: ws, gen: "", carry: "", connects: {}, bindings: {}, step: "coming", placed: 0, missing: 0, gits: 0, gitsFailed: 0, rooms: was?.rooms ?? null, error: null, told: false, restarts: 0,
      driver: null, jobs: null, jobsTold: false, home: false, driverTold: false,
    };
    if (was !== undefined && was.workspace !== ws) await rm(this.#carried.dir(was.workspace, origin), { recursive: true, force: true });
    this.#taking.set(origin, t);
    await this.#saveTaking(t);
    log.info("retire", "a station retired from a workspace sends its chats here", { origin, workspace: ws });
    return { ok: true };
  }

  /// A file sent: written beside, its bytes' hash checked as they come, then put in place; one whose bytes are not what
  /// its name says (it changed as it was read) refused.
  async #receive(ws: string, origin: string, hash: string, bytes: Bytes): Promise<void> {
    const dir = join(this.#carried.dir(ws, origin), "files");
    const path = join(dir, hash);
    if (await there(path)) {
      for await (const _ of bytes) void _;
      return;
    }
    await mkdir(dir, { recursive: true });
    const tmp = `${path}.${randomBytes(4).toString("hex")}.tmp`;
    const h = createHash("sha256");
    const f = await open(tmp, "w");
    try {
      for await (const piece of bytes) {
        h.update(piece);
        for (let done = 0; done < piece.length; ) done += (await f.write(piece, done, piece.length - done)).bytesWritten;
      }
      await f.sync();
    } catch (e) {
      await f.close().catch(() => {});
      await rm(tmp, { force: true });
      throw e;
    }
    await f.close();
    if (h.digest("hex") !== hash) {
      await rm(tmp, { force: true });
      throw new Refused("changed: its bytes are not what its name says");
    }
    await rename(tmp, path);
  }

  async #takeAsked(origin: string, ws: string, request: Json): Promise<Json> {
    const gen = String(request.gen ?? "");
    const carry = String(request.carry ?? "");
    if (!GEN.test(gen) || !HASH.test(carry)) throw new Refused("not a copy's name");
    if (this.#d.copies.formerly().includes(origin)) return { ok: true, took: true };
    const was = this.#taking.get(origin);
    if (was === undefined || was.workspace !== ws) throw new Refused("not begun: retire.begin first");
    if (was.step === "took") return { ok: true, took: true };
    const same = was.gen === gen && was.carry === carry;
    if (this.#takingRuns.has(origin)) {
      if (same) return { ok: true };
      throw new Refused("busy: this station is putting in another copy of that station's chats");
    }
    // (it is about to start again to put it in: nothing more to do)
    if (same && was.step === "restart") return { ok: true };
    const strings = (v: Json) => Object.fromEntries(Object.entries(v ?? {}).filter((e): e is [string, string] => typeof e[1] === "string"));
    was.connects = strings(request.connects);
    was.bindings = strings(request.bindings);
    const d = request.driver;
    was.driver = d !== null && typeof d === "object" && typeof d.station === "string" && STATION.test(d.station) && typeof d.session === "string" && d.session !== "" ? { station: d.station, session: d.session } : null;
    if (typeof request.name === "string" && request.name !== "") was.name = request.name;
    if (!same || was.step === "coming") {
      was.gen = gen;
      was.carry = carry;
      was.step = "placing";
    } else if (was.step === "failed") {
      // (it is put in again only as a person asks it: else it would start again and again)
      if (request.again !== true) return { ok: true, failed: was.error ?? "" };
      // (asked again, by a person: what came of the last restart goes, and the copy is put in again)
      const o = this.#d.copies.restored();
      if (o !== null && o.origin === origin) await rm(outcomeFile(this.#d.data), { force: true });
      was.step = "copy";
      was.restarts = 0;
    }
    was.error = null;
    was.told = false;
    await this.#saveTaking(was);
    this.#take(was);
    return { ok: true };
  }

  /// The station retired calls it off: what it sent goes, unless this station is putting it in or took its place.
  async #drop(origin: string, ws: string): Promise<Json> {
    if (this.#d.copies.formerly().includes(origin)) return { took: true };
    const t = this.#taking.get(origin);
    if (t === undefined || t.workspace !== ws) return { dropped: true };
    if (t.step === "took") return { took: true };
    // (the copy is about to go in as this station starts again)
    const ready = await readFile(readyFile(this.#d.data), "utf8").then((x) => JSON.parse(x)?.origin === origin, () => false);
    if (ready) return { took: true };
    if (this.#takingRuns.has(origin)) throw new Refused("busy: this station is putting them in place just now");
    this.#takeAgain.get(origin)?.();
    this.#takeAgain.delete(origin);
    this.#taking.delete(origin);
    await rm(this.#carried.dir(t.workspace, origin), { recursive: true, force: true });
    for (const room of t.rooms ?? []) await rm(room, { recursive: true, force: true });
    await rm(join(takingDir(this.#d.data), `${origin}.json`), { force: true });
    log.info("retire", "a station's retirement called off: what it sent here is gone", { origin, workspace: ws });
    this.#changed(true);
    return { dropped: true };
  }

  /// The station retired puts its chats back to work, its hand-over having failed (`#fallBack`): what it sent stays
  /// (the next hand-over sends only what changed), and nothing of it is put in by itself: a copy that could not go in is
  /// let go of from the restore's place, where a start would take it up again. One being put in just now is busy.
  async #keep(origin: string, ws: string): Promise<Json> {
    if (this.#d.copies.formerly().includes(origin)) return { took: true };
    const t = this.#taking.get(origin);
    if (t === undefined || t.workspace !== ws) return { kept: true };
    if (t.step === "took") return { took: true };
    if (this.#takingRuns.has(origin)) throw new Refused("busy: this station is putting them in place just now");
    if (t.step !== "coming" && t.step !== "failed") throw new Refused("busy: this station is about to put them in");
    const ready = await readFile(readyFile(this.#d.data), "utf8").then((x) => JSON.parse(x)?.origin === origin, () => false);
    if (ready) await rm(restoreDir(this.#d.data), { recursive: true, force: true });
    log.info("retire", "a retired station's chats work there again: what it sent is kept, nothing put in", { origin, workspace: ws });
    return { kept: true };
  }

  #take(t: Taking): void {
    if (this.#takingRuns.has(t.origin) || this.#closed) return;
    this.#takeAgain.get(t.origin)?.();
    this.#takeAgain.delete(t.origin);
    const run = this.#taken(t).catch((e) => {
      t.error = (e as Error).message;
      log.warn("retire", "a retired station's chats not taken yet", { origin: t.origin, step: t.step, error: t.error });
      this.#changed(true);
      if (!this.#closed && this.#taking.get(t.origin) === t) this.#takeAgain.set(t.origin, this.#d.fibers.after(RETRY_MS, () => this.#take(t))); // timer: a retry after a failure
    }).finally(() => this.#takingRuns.delete(t.origin));
    this.#takingRuns.set(t.origin, run);
  }

  async #taken(t: Taking): Promise<void> {
    t.error = null;
    const dir = this.#carried.dir(t.workspace, t.origin);
    const files = join(dir, "files");
    const indexPath = join(files, t.carry);
    const index = JSON.parse(await readFile(indexPath, "utf8")) as CarryIndex;
    if (t.step === "placing") {
      // (the rooms put here that were not: what a cancel takes away again)
      if (t.rooms === null) {
        const fresh: string[] = [];
        for (const s of index.sessions) {
          if (s.room === null) continue;
          const room = resolve(moved(s.room, index.dataDir, this.#d.data));
          if (room.startsWith(resolve(this.#d.data, "sessions") + sep) && !(await there(room))) fresh.push(room);
        }
        t.rooms = fresh;
        await this.#saveTaking(t);
      }
      const placed = await this.#work.place(this.#d.data, indexPath, files);
      t.placed = placed.placed + placed.kept;
      t.missing = placed.missing;
      t.step = "gits";
      await this.#saveTaking(t);
    }
    if (t.step === "gits") {
      const made = await rebuildGits(this.#d.data, this.#d.reposDir, index, files, this.#git);
      t.gits = made.made;
      t.gitsFailed = made.failed;
      t.step = "copy";
      await this.#saveTaking(t);
    }
    if (t.step === "copy" || t.step === "restart") {
      // (each start again asked for counted first: one whose restore never says how it went is not asked for again and
      // again)
      t.step = "restart";
      t.restarts++;
      await this.#saveTaking(t);
      // (the copy brought into the restore's place, and the station started again to put it in, its sessions of the
      // workspace as this station says them)
      await this.#d.copies.takeOver(t.workspace, t.origin, t.gen, { connects: t.connects, ws: this.#d.home() === t.workspace ? null : t.workspace });
    }
  }

  /// This station took `t`'s station's place: its agent home merged into this one's, the jobs its chats had running
  /// started again (each once: what came of them kept before anything is told), the bindings set, each moved chat's
  /// agent to be told, those whose jobs were started told at once, and the driver where it moved here; what was brought
  /// for it gone; that station told so (`#tell`). Each part is kept done as it is, so a start again in the middle goes on
  /// from there.
  async #tookPlace(t: Taking): Promise<void> {
    const dir = this.#carried.dir(t.workspace, t.origin);
    const files = join(dir, "files");
    const index = await readFile(join(files, t.carry), "utf8").then((x) => JSON.parse(x) as CarryIndex, () => null);
    const at = this.#d.fibers.now();
    if (index !== null && !t.home) {
      const to = index.agent ? this.#d.agentHome?.(t.workspace) ?? null : null;
      if (to !== null && index.agent) {
        const merged = await mergeAgentHome(to, index.agent, join(files, index.agent.list), files, { origin: t.origin, name: t.name, at })
          .catch((e) => (log.warn("retire", "a retired station's agent home not merged here", { origin: t.origin, error: (e as Error).message }), null));
        if (merged !== null) log.info("retire", "a retired station's agent home merged here", { origin: t.origin, ...merged });
      }
      t.home = true;
      await this.#saveTaking(t);
    }
    if (index !== null && t.jobs === null) {
      t.jobs = this.#startJobs(index);
      await this.#saveTaking(t);
    }
    const bindings: Record<string, string> = {};
    for (const [connect, session] of Object.entries(t.bindings)) bindings[t.connects[connect] ?? connect] = session;
    const here = this.#d.here();
    const name = here === null ? "" : (this.#d.roster(t.workspace)?.find((r) => r.id === here)?.name ?? "");
    const notes = index === null ? [] : index.sessions.map((s) => ({ session: s.key, text: movedNote(t.name, name, index, s, this.#d.data, this.#d.reposDir, t.jobs) }));
    this.#d.took({ bindings, notes });
    if (!t.jobsTold) {
      // (each moved chat whose jobs were tried told at once, which wakes it, its moved note before it)
      const from = `This chat moved here from station ${t.name || t.origin.slice(0, 12)}`;
      const by = new Map<string, string[]>();
      for (const j of t.jobs ?? []) {
        if (j.old === true) continue;
        by.set(j.session, [...(by.get(j.session) ?? []), movedSaid(from, j, j.started ? null : (j.why ?? "not started"))]);
      }
      for (const [session, said] of by) this.#d.jobs?.say(session, said.join("\n"));
      const d = t.driver;
      if (d !== null && d.station === t.origin && index?.sessions.some((s) => s.key === d.session) === true && this.#d.tell !== undefined) {
        const jobs = jobWords(t.jobs ?? []);
        try {
          this.#d.tell(d.session, `Retiring station ${t.name || t.origin.slice(0, 12)}: its chats were taken here, this chat with them (${index.sessions.length} chats); this station is that one too now.${jobs === "" ? "" : ` ${jobs}`} The retired station moves its accounts and connects here next and tells you what is left. Check that the chats go on here (see the stillfail-retire skill).`);
          t.driverTold = true;
        } catch (e) {
          log.warn("retire", "who asked for the retirement not told here", { session: d.session, error: (e as Error).message });
        }
      }
      t.jobsTold = true;
      await this.#saveTaking(t);
    }
    // (kept a while for station_retire's status here: what came of it)
    this.#tookHere = [...this.#tookHere.filter((x) => x.origin !== t.origin), { origin: t.origin, name: t.name, workspace: t.workspace, at, chats: index?.sessions.length ?? 0, jobs: t.jobs ?? [] }].slice(-TAKEN_KEPT);
    await writeJson(takenFile(this.#d.data), this.#tookHere);
    await rm(dir, { recursive: true, force: true });
    t.step = "took";
    t.error = null;
    await this.#saveTaking(t);
    log.info("retire", "a retired station's chats went on here", { origin: t.origin, workspace: t.workspace });
  }

  /// The jobs `index` says its chats had running, started again here in their sessions, in the same directories under
  /// this data directory (`moved`, as the moved note says them): one that ran outside the retired station's data
  /// directory (a person's project, which stayed) is not; one like it running already (started before a start again
  /// of this station) is not twice; one gathered by a station from before is not tried. What came of each.
  #startJobs(index: CarryIndex): JobOutcome[] {
    const out: JobOutcome[] = [];
    const keys = new Set(index.sessions.map((s) => s.key));
    const from = resolve(index.dataDir);
    for (const j of index.jobs ?? []) {
      if (!keys.has(j.session)) continue;
      const o: JobOutcome = { session: j.session, name: j.name, command: j.command, port: j.port ?? null, id: null, started: false, why: null };
      const jobs = this.#d.jobs;
      if (j.cwd === undefined || jobs === undefined) {
        out.push({ ...o, old: true });
        continue;
      }
      const cwd = resolve(j.cwd);
      if (cwd !== from && !cwd.startsWith(from + sep)) {
        out.push({ ...o, why: `it ran in ${j.cwd}, which was not the retired station's own and did not move` });
        continue;
      }
      if (jobs.running(j.session, j.name, j.command)) {
        out.push({ ...o, started: true });
        continue;
      }
      try {
        const made = jobs.start(j.session, { name: j.name, command: j.command, cwd: moved(cwd, from, this.#d.data), port: j.port ?? null, watch: j.watch === true });
        out.push({ ...o, started: true, id: made.id, name: made.name, port: made.port });
      } catch (e) {
        log.warn("retire", "a moved chat's job not started again", { session: j.session, job: j.name, error: (e as Error).message });
        out.push({ ...o, why: (e as Error).message });
      }
    }
    return out;
  }

  /// The station retired told how its chats went here (`retire.took`, `retire.failed`), until it answers: asked of that
  /// station itself, as this one is that station too now (mesh/bus.ts `askItself`).
  #tell(t: Taking, tries = 0): void {
    if (this.#closed || this.#tellRuns.has(t.origin) || (t.step !== "took" && t.step !== "failed")) return;
    this.#tellAgain.get(t.origin)?.();
    this.#tellAgain.delete(t.origin);
    const method = t.step === "took" ? "retire.took" : "retire.failed";
    const run = this.#d.askItself(t.origin, { method, workspace: t.workspace, error: t.error, ...(t.step === "took" ? { jobs: t.jobs ?? [], driverTold: t.driverTold } : {}) })
      .then(async () => {
        if (t.step === "took") {
          // (it knows: nothing more is kept of it here)
          if (this.#taking.get(t.origin) === t) this.#taking.delete(t.origin);
          await rm(join(takingDir(this.#d.data), `${t.origin}.json`), { force: true });
          this.#changed(true);
        } else {
          t.told = true;
          await this.#saveTaking(t);
        }
      }, () => {
        if (this.#closed || this.#taking.get(t.origin) !== t) return;
        const wait = Math.min(RETRY_MS * 2 ** tries, RETRY_MOST_MS);
        this.#tellAgain.set(t.origin, this.#d.fibers.after(wait, () => this.#tell(t, tries + 1))); // timer: a retry after a failure
      })
      .finally(() => this.#tellRuns.delete(t.origin));
    this.#tellRuns.set(t.origin, run);
  }

  // ── what the settings show ──

  /// Where this station stands in being retired from `ws` (null: it is not), and the chats of retired stations being
  /// taken here.
  overview(ws: string): { retiring: Retiring | null; taking: { origin: string; name: string; step: TakingStep; error: string | null }[] } {
    const s = this.#state !== null && this.#state.workspace === ws ? this.#state : null;
    return {
      retiring: s === null ? null : {
        workspace: s.workspace, to: s.to, toName: s.toName, by: s.by, at: s.at, step: s.step, done: s.done, total: s.total, error: s.error, reason: s.reason,
        cancellable: s.step === "sending" || s.step === "sent" || s.step === "quiet" || s.step === "handing",
        retriable: s.error !== null && s.step !== "done",
        accountsLeft: s.accountsLeft,
        // (whether its accounts move with it: the same test as the step's and the preview's)
        home: this.#d.home() === s.workspace,
      },
      taking: [...this.#taking.values()].filter((t) => t.workspace === ws && t.step !== "took").map((t) => ({ origin: t.origin, name: t.name, step: t.step, error: t.error })),
    };
  }
}

/// Each linked worktree `carry` names made again here by git, at the place its files were put (`moved` under
/// `dataDir`): its repository from the station's cache (`reposDir`, cloned there from its remote where none has it, as
/// sessions/clones.ts fills it), its commits no remote has fetched from their bundle (in `from`), a worktree of it at
/// that commit made beside it and its `.git` put in the checkout, which `git worktree repair` binds to it; the index set
/// to its commit, its branch taken where no branch of that name is here. Its files are left as they were put: what it
/// changed shows as changed. One that cannot be made is left as its files, its bundle kept beside it
/// (`<dir>.carried.bundle`: the only copy of its commits no remote has), counted.
export async function rebuildGits(dataDir: string, reposDir: string, carry: { dataDir: string; gits: CarryIndex["gits"] }, from: string, git: (dir: string, args: string[]) => Promise<string>): Promise<{ made: number; failed: number }> {
  let made = 0;
  let failed = 0;
  const repos = new Map<string, string>();
  const repoOf = async (remote: string): Promise<string> => {
    const kept = repos.get(remote);
    if (kept !== undefined) return kept;
    await mkdir(reposDir, { recursive: true });
    for (const name of (await readdir(reposDir).catch(() => [] as string[])).sort()) {
      if (name.startsWith(".")) continue;
      const dir = join(reposDir, name);
      const url = await git(dir, ["remote", "get-url", "origin"]).catch(() => null);
      if (url === remote) {
        repos.set(remote, dir);
        return dir;
      }
    }
    const base = basename(remote).replace(/\.git$/, "").replace(/[^A-Za-z0-9._-]/g, "-") || "repo";
    let name = base;
    for (let i = 2; await there(join(reposDir, name)); i++) name = `${base}-${i}`;
    // (cloned into a dot-named directory, which nothing that lists the cache takes for a clone, and moved in whole)
    const temp = `.cloning-${randomBytes(4).toString("hex")}`;
    try {
      await git(reposDir, ["clone", "-q", "--", remote, temp]);
      await rename(join(reposDir, temp), join(reposDir, name));
    } finally {
      await rm(join(reposDir, temp), { recursive: true, force: true });
    }
    const dir = join(reposDir, name);
    repos.set(remote, dir);
    return dir;
  };
  for (const g of carry.gits) {
    const dir = resolve(moved(g.dir, carry.dataDir, dataDir));
    try {
      if (!dir.startsWith(resolve(dataDir) + sep)) throw new Error("not under this station's data directory");
      if (await there(join(dir, ".git"))) {
        made++;
        continue;
      }
      const repo = await repoOf(g.remote);
      if (g.bundle !== null) await git(repo, ["fetch", "-q", join(from, g.bundle), `+HEAD:refs/carried/${g.head}`]);
      if (await git(repo, ["cat-file", "-e", `${g.head}^{commit}`]).then(() => false, () => true)) await git(repo, ["fetch", "-q", "origin"]);
      const beside = `${dir}.git-carrying`;
      await rm(beside, { recursive: true, force: true });
      await git(repo, ["worktree", "add", "-q", "--no-checkout", "--detach", beside, g.head]);
      await rename(join(beside, ".git"), join(dir, ".git"));
      await rm(beside, { recursive: true, force: true });
      await git(dir, ["worktree", "repair"]);
      await git(dir, ["reset", "-q"]);
      if (g.branch !== null) {
        const at = await git(repo, ["rev-parse", "-q", "--verify", `refs/heads/${g.branch}`]).catch(() => null);
        // (a branch of that name here already is another's: the checkout stays at its commit, detached)
        if (at === null) await git(dir, ["checkout", "-q", "-b", g.branch]);
      }
      made++;
    } catch (e) {
      failed++;
      // (its commits no remote has stay beside it, as a bundle git takes back: `git fetch <it>`)
      if (g.bundle !== null) await copyFile(join(from, g.bundle), `${dir}.carried.bundle`).catch(() => {});
      log.warn("retire", "a checkout not made again by git: its files are there", { dir, error: (e as Error).message });
    }
  }
  return { made, failed };
}
