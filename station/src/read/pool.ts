// The readers: worker threads, each with its own read-only connection, in two lines that share none of them. What the
// station tells as things change (the event streams, its notices: `told`) is read by a reader of its own; what devices
// ask, by the others. Neither waits on the other: on ccvm (2026-11-02) one line served both, and what was told of a
// message just said waited 50 s behind a usage read and sidebar updates, a push notice 55 s. Among what devices ask,
// bulk reads leave room for chat reads. None of these reads holds up writes.
// A reader is a V8 of its own (tens of MB), so they are started when reads come and let go once none has come for a
// while: an idle station keeps none. One that dies (its heap is bounded) fails what it held and is replaced by the next
// read.
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import type { InWorkspace } from "../store/rows.ts";
import { MinuteReader } from "../usage/minute-reader.ts";
import type { Answer, Ask } from "./worker.ts";
import { REMOTE_RUNS_PENDING, USAGE_CHATS_PENDING, USAGE_DETAIL_PENDING, USAGE_MINUTES_PENDING } from "./store.ts";
import { HttpError } from "./views.ts";
import { wall } from "../ops/fibers.ts";

/// How long a reader with nothing to do is kept.
const IDLE_MS = 60_000;
/// A read that waited or took longer than this is logged, with what it was.
const SLOW_MS = 2_000;

/// `held`: the read it is answering, if any.
type Slot = { worker: Worker; held: Asked | null; idle?: () => void; retiring?: boolean };

/// A read in line or being answered: when it was asked and when a reader took it, and the reader it is best read in (a
/// session's history, where its reading stands in memory).
type Asked = {
  ask: Ask;
  session: string | null;
  home: Slot | null;
  /// After every other read waiting, one at a time (`read`).
  background: boolean;
  at: number;
  took: number;
  resolve: (text: string) => void;
  reject: (error: Error) => void;
};

/// A line of reads and the readers that answer it, at most `size` of them, the first read first. `room`: bulk reads leave
/// one of them for a chat read (what devices ask).
type Line = { told: boolean; size: number; room: boolean; slots: Slot[]; waiting: Asked[] };

/// How many sessions' readers are remembered (the most recently read).
const HOMES = 4096;
/// How long after the store changes its log is written into the database (`checkpointSoon`): at most this often.
const CHECKPOINT_MS = 2_000;
/// Writing the store's log into the database (worker.ts `checkpoint`) is no read and waits for no one: it has a reader
/// of its own (`log`). In line behind reads, it waited up to 98 s on ccvm (2026-11-02) while the log grew, until the main
/// connection wrote it itself at its next commit (store.ts WAL_PAGES), holding every device and agent as it reached the
/// disk; going before them in their readers, it held the one left for a chat 53 s as it reached a disk short of memory
/// (2026-11-03), devices' reads waiting 40 s and more behind it.
const CHECKPOINT = "checkpoint";
const cancelled = () => new HttpError(503, "read cancelled");
/// The scoped reads on the path to showing a chat, and those a device's lists are made of, each of a few rows and the
/// statistics kept of them (the sidebar, a session's detail and summary, a chat's latest messages). Other page reads,
/// including new kinds not yet classified, leave room for these, and these go before them: a slow transcript or resource
/// snapshot can block just as a slow aggregate can. Behind a usage read of 76 s and a history's pages, the sidebar
/// waited 7 s and a session opened 9 s on ccvm (2026-11-03), their own reads 0.2 s.
const INTERACTIVE = new Set(["thread", "chats", "chatMarks", "session", "summary", "latestMessages"]);

/// One thread's current or older page is interactive. An `after` or explicit range can ask for an unbounded amount on
/// older clients, so it remains in the background until that request is paged end to end.
function interactive(a: Asked): boolean {
  if (INTERACTIVE.has(a.ask.op)) return true;
  if (a.ask.op !== "entries" && a.ask.op !== "letters") return false;
  const params = a.ask.args?.params;
  const keys = Array.isArray(params) ? params.map((p: unknown) => Array.isArray(p) ? p[0] : null) : Object.keys(params ?? {});
  return !keys.includes("after") && !keys.includes("from") && !keys.includes("to");
}

/// A stretch of a session's history in brief (`from` and `to`): what a client fills in of it in the background, where its
/// stream left a hole or it holds less than there is (client/core-ts/src/station/channel-kinds.ts TRANSCRIPT). Up to
/// 1,000 items a read, 16 MB of a Codex transcript and 6 s on ccvm (2026-11-03), the sidebar waiting 9 s behind them.
/// One read whole (a step opened) is someone's waiting on it.
function filling(op: string, args: unknown): boolean {
  const a = args as { from?: unknown; to?: unknown; brief?: unknown } | null;
  return op === "timeline" && a !== null && typeof a.from === "string" && typeof a.to === "string" && a.brief === "1";
}

/// Reads by the pages' readers (`pages`): a history's pages, and the machine's own sessions (GET /machine-sessions, a walk
/// of every Claude and Codex project there, 14 s on ccvm, 2026-11-03), each of the files on the disk rather than the
/// database.
const PAGES = new Set(["timeline", "machineSessions"]);

export class Readers {
  /// What devices ask, and what the station tells (`told`), each answered by readers of its own.
  private asked: Line;
  /// The pages of sessions' histories (`timeline`), by a reader of their own: a page is read from the mark before it
  /// (read/transcripts.ts), megabytes of a long transcript, seconds from a disk short of memory; in line with what
  /// devices ask, the sidebar and a chat opened waited 20 s and more behind them on ccvm (2026-11-03).
  private pages: Line;
  private told: Line;
  /// The store's log written into the database (CHECKPOINT), by a reader of its own.
  private log: Line;
  /// The reader each session's history was last read in (`timeline`).
  private homes = new Map<string, Slot>();
  private next = 0;
  private closed = false;
  private minutes: MinuteReader | null = null;
  /// A checkpoint is armed or running (`checkpointSoon`), and the store changed again since it was armed.
  private checkpointing = false;
  private again = false;
  /// The station's data directory, whose database they read.
  readonly data: string;
  private readonly workerFile: URL | undefined;
  private readonly backfill: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  /// People's names as their credentials say them (the admin API's `deps.names`), given to every read.
  readonly names = new Map<string, string>();
  /// What only the hub knows, given to every read: sessions' process states and client keys (the hub sets these).
  processes: () => Map<string, string> = () => new Map();
  clientKeys: () => Map<string, string> = () => new Map();

  /// For what devices ask, at most two by default (STILLFAIL_READERS says otherwise); for what is told, `tellers`.
  constructor(data: string, size = Number(process.env.STILLFAIL_READERS) || Math.min(2, Math.max(1, availableParallelism() - 1)), workerFile?: URL, tellers = 1, backfill: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}) {
    this.data = data;
    this.workerFile = workerFile;
    this.backfill = backfill;
    this.asked = { told: false, size, room: true, slots: [], waiting: [] };
    // Two: one a background page (a history brought on, a stretch filled) may hold, one left for a page someone waits on.
    this.pages = { told: false, size: 2, room: false, slots: [], waiting: [] };
    this.told = { told: true, size: tellers, room: false, slots: [], waiting: [] };
    this.log = { told: true, size: 1, room: false, slots: [], waiting: [] };
  }

  /// Check statistical coverage without occupying a device reader or writing old history.
  startUsageIndex() {
    if (this.closed) return;
    if (this.minutes === null) this.minutes = new MinuteReader(join(this.data, "stillfail.db"), this.backfill);
    this.minutes.start();
  }

  private start(line: Line): Slot {
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/read/worker.js.
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./read/worker.js", import.meta.url);
    // A reader's heap stays small: what it builds is answered and dropped.
    const worker = new Worker(file, { workerData: { data: this.data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    const slot: Slot = { worker, held: null };
    worker.on("message", (answer: Answer) => {
      // An abandoned read may finish while its worker is being stopped. Do not give that worker another read until it exits.
      if (slot.retiring) return;
      const asked = slot.held;
      slot.held = null;
      if (asked !== null && asked.ask.id === answer.id) {
        const now = wall.now();
        if (now - asked.at > SLOW_MS) log.warn("readers", "a read went slowly", { op: asked.ask.op, told: line.told, waitedMs: asked.took - asked.at, ms: now - asked.took });
        if (answer.text !== undefined) asked.resolve(answer.text);
        else asked.reject(new HttpError(answer.status ?? 500, answer.error ?? "read failed"));
      }
      this.pump(line);
    });
    worker.on("error", (error) => log.error("readers", "a reader failed", { error: error.message, reading: slot.held?.ask.op ?? null }));
    worker.on("exit", (code) => {
      slot.idle?.();
      line.slots = line.slots.filter((s) => s !== slot);
      slot.held?.reject(new HttpError(500, `the reader stopped (exit ${code})`));
      slot.held = null;
      this.pump(line);
    });
    line.slots.push(slot);
    return slot;
  }

  private letGoLater(slot: Slot) {
    if (slot.idle) return;
    // A thread's resources: the machine's time.
    slot.idle = wall.after(IDLE_MS, () => {
      slot.idle = undefined;
      if (slot.held === null) void slot.worker.terminate();
    });
  }

  /// The answer, as JSON text. `told`: what an event stream or a notice tells, read by the station's own reader.
  /// `background`: what a client brings onto its device in the background (POST /batch: a session's history page after
  /// page): after every other read waiting, and one at a time. In line with the rest, a sweep's pages (1 to 4 s each on
  /// ccvm, 2 to 7 MB of a Codex transcript read: 2026-11-03) held the sidebar, a session opened and the rest 10 s and
  /// more behind them, four at once from each device.
  read(op: string, args: unknown, lang: Ask["lang"], { told = false, background = false, signal }: { told?: boolean; background?: boolean; signal?: AbortSignal } = {}): Promise<string> {
    if (op === "usage") return this.usageRead(args, lang, told, signal);
    if (op === "outflowUsage") return this.outflowUsageRead(args, lang, told, signal);
    return this.enqueue(op, args, lang, told, op === CHECKPOINT, background || filling(op, args), signal);
  }

  private async covered(check: Promise<void>, signal?: AbortSignal): Promise<void> {
    try {
      if (!signal) await check;
      else await new Promise<void>((resolve, reject) => {
        const abort = () => { signal.removeEventListener("abort", abort); reject(cancelled()); };
        if (signal.aborted) abort();
        else signal.addEventListener("abort", abort, { once: true });
        check.then(() => { signal.removeEventListener("abort", abort); resolve(); }, (error) => { signal.removeEventListener("abort", abort); reject(error); });
      });
    }
    catch (error) {
      if (error instanceof HttpError && error.message === "read cancelled") throw error;
      if (this.closed) throw new HttpError(502, "station stopping");
      throw new HttpError(503, (error as Error).message);
    }
  }

  private async usageRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const viewer = (args as { viewer?: InWorkspace | null } | null)?.viewer ?? null;
    const history = (args as { history?: unknown } | null)?.history === true;
    while (!this.closed) {
      try {
        return await this.enqueue("usage", args, lang, told, false, false, signal);
      } catch (error) {
        // The reader checks its own snapshot: a session may have moved after the coverage check.
        if (error instanceof HttpError && error.message === USAGE_MINUTES_PENDING && history)
          throw new HttpError(503, "historical minute statistics are unavailable");
        if (error instanceof HttpError && error.message === USAGE_DETAIL_PENDING) {
          this.startUsageIndex();
          await this.covered(this.minutes!.readyDetail(viewer), signal);
          continue;
        }
        if (error instanceof HttpError && error.message === USAGE_CHATS_PENDING && history) {
          this.startUsageIndex();
          await this.covered(this.minutes!.readyChats(viewer), signal);
          continue;
        }
        if (!(error instanceof HttpError) || error.message !== REMOTE_RUNS_PENDING) throw error;
        this.startUsageIndex();
        await this.covered(this.minutes!.readyRemote(), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  private async outflowUsageRead(args: unknown, lang: Ask["lang"], told: boolean, signal?: AbortSignal): Promise<string> {
    const ws = (args as { ws?: InWorkspace } | null)?.ws;
    const viewer: InWorkspace = ws !== null && typeof ws === "object" && typeof ws.workspace === "string"
      ? { workspace: ws.workspace, home: ws.home === true } : { workspace: "\u0000home", home: true };
    while (!this.closed) {
      try { return await this.enqueue("outflowUsage", args, lang, told, false, false, signal); }
      catch (error) {
        if (!(error instanceof HttpError) || error.message !== USAGE_DETAIL_PENDING) throw error;
        this.startUsageIndex();
        await this.covered(this.minutes!.readyDetail(viewer), signal);
      }
    }
    throw new HttpError(502, "station stopping");
  }

  /// `first`: before the reads waiting (CHECKPOINT).
  private enqueue(op: string, args: unknown, lang: Ask["lang"], told: boolean, first = false, background = false, signal?: AbortSignal): Promise<string> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    if (signal?.aborted) return Promise.reject(cancelled());
    const line = op === CHECKPOINT ? this.log : told ? this.told : PAGES.has(op) ? this.pages : this.asked;
    // A session's history read where it was read before: that reader keeps where its reading stands in memory, another
    // reads it from disk (read/transcripts.ts).
    const session = (op === "timeline" || op === "transcriptState") && typeof (args as { key?: unknown })?.key === "string" ? (args as { key: string }).key : null;
    const home = session !== null ? this.homes.get(session) : undefined;
    const ask: Ask = { id: this.next++, op, args, lang, names: [], processes: [], clientKeys: [] };
    return new Promise((resolve, reject) => {
      let finished = false;
      const done = () => { finished = true; signal?.removeEventListener("abort", abort); };
      const asked: Asked = {
        ask, session, home: home !== undefined && line.slots.includes(home) ? home : null, background, at: wall.now(), took: 0,
        resolve: (text) => { if (!finished) { done(); resolve(text); } },
        reject: (error) => { if (!finished) { done(); reject(error); } },
      };
      const abort = () => {
        if (finished) return;
        const at = line.waiting.indexOf(asked);
        if (at >= 0) line.waiting.splice(at, 1);
        else {
          const slot = line.slots.find((s) => s.held === asked);
          if (slot) { slot.retiring = true; void slot.worker.terminate(); }
        }
        asked.reject(cancelled());
        if (at >= 0) this.pump(line);
      };
      signal?.addEventListener("abort", abort, { once: true });
      if (first) line.waiting.unshift(asked);
      else line.waiting.push(asked);
      this.pump(line);
    });
  }

  /// Reads in line go to its readers free, the first first (a session's history to its home reader when that one is
  /// free). Where bulk reads leave room (`room`, two readers or more), they hold one less than all: a later interactive
  /// read passes a waiting bulk read to the one left.
  private pump(line: Line) {
    if (this.closed) return;
    while (line.waiting.length > 0) {
      const bulkHeld = line.slots.filter((s) => s.held !== null && !interactive(s.held) && !s.held.background).length;
      const limited = line.room && line.size > 1 && bulkHeld >= line.size - 1;
      // A background read only when no other waits, none of its kind is being read, and a reader is left beside it.
      const foreground = line.waiting.findIndex((a) => !a.background);
      const free = line.slots.filter((s) => s.held === null).length + (line.size - line.slots.length);
      const behind = line.slots.some((s) => s.held?.background === true) || (free < 2 && line.size > 1) ? -1 : line.waiting.findIndex((a) => a.background);
      const first = line.waiting.findIndex((a) => interactive(a) || a.ask.op === CHECKPOINT);
      const at = limited || first >= 0 ? first : foreground >= 0 ? foreground : behind;
      if (at < 0) break;
      const asked = line.waiting[at]!;
      const home = asked.home !== null && asked.home.held === null && line.slots.includes(asked.home) ? asked.home : null;
      const slot = home ?? line.slots.find((s) => s.held === null) ?? (line.slots.length < line.size ? this.start(line) : null);
      if (slot === null) break;
      line.waiting.splice(at, 1);
      this.give(slot, asked);
    }
    for (const slot of line.slots) if (slot.held === null) this.letGoLater(slot);
  }

  private give(slot: Slot, asked: Asked) {
    slot.idle?.();
    slot.idle = undefined;
    slot.held = asked;
    asked.took = wall.now();
    if (asked.session !== null) {
      // Where its reading will stand.
      this.homes.delete(asked.session);
      this.homes.set(asked.session, slot);
      while (this.homes.size > HOMES) this.homes.delete(this.homes.keys().next().value!);
    }
    asked.ask.names = [...this.names];
    asked.ask.processes = [...this.processes()];
    asked.ask.clientKeys = [...this.clientKeys()];
    slot.worker.postMessage(asked.ask);
  }

  /// The store changed: what its log (the WAL) holds is written into the database shortly, by a reader (worker.ts
  /// `checkpoint`), one at a time, at most once a CHECKPOINT_MS. The main thread does not (store.ts): there it held
  /// every device while it reached the disk.
  checkpointSoon() {
    if (this.closed) return;
    if (this.checkpointing) return void (this.again = true);
    this.checkpointing = true;
    this.again = false;
    wall.after(CHECKPOINT_MS, () => {
      if (this.closed) return;
      this.read(CHECKPOINT, {}, "en")
        .catch((error) => log.warn("readers", "the database's log not written into it", { error: (error as Error).message }))
        .finally(() => {
          this.checkpointing = false;
          if (this.again) this.checkpointSoon();
        });
    });
  }

  /// Each running reader's JS heap in use, in bytes (for the memory log).
  heaps(): Promise<number[]> {
    return Promise.all([...this.asked.slots, ...this.told.slots, ...this.log.slots, ...this.pages.slots].map((s) => s.worker.getHeapStatistics().then((h) => h.used_heap_size, () => 0)));
  }

  close() {
    this.closed = true;
    if (this.minutes !== null) void this.minutes.close();
    for (const line of [this.asked, this.told, this.log, this.pages]) {
      for (const asked of line.waiting.splice(0)) asked.reject(new HttpError(502, "station stopping"));
      for (const { worker } of line.slots) void worker.terminate();
    }
  }
}
