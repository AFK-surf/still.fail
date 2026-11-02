// The readers: worker threads, each with its own read-only connection. Two kinds, kept apart: one reader only for what
// stands between a person and a message or file they are looking at (a chat's page, a file, the message just said),
// and the rest for everything else (lists, summaries, usage, histories, notices). A bulk read never takes the chat
// reader, however long it runs or however many wait, so a message is never queued behind one (2026-11-02 on ccvm: a
// 97 s usage read and a sidebar update held both readers of one line, and two messages waited 50 s and 31 s for an
// 11 ms read). What counts as a chat read is listed (`chat`); anything else, a new kind of read too, is bulk. A chat read
// may also use a bulk reader that is free. Within each, what the event streams tell goes before the pages asked. None of
// these reads holds up writes.
// A reader is a V8 of its own (tens of MB), so they are started when reads come and let go once none has come for a
// while: an idle station keeps none. One that dies (its heap is bounded) fails what it held and is replaced by the next
// read.
import { availableParallelism } from "node:os";
import { Worker } from "node:worker_threads";
import { log } from "../ops/log.ts";
import type { Answer, Ask } from "./worker.ts";
import { HttpError } from "./views.ts";
import { wall } from "../ops/fibers.ts";

/// How long a reader with nothing to do is kept.
const IDLE_MS = 60_000;
/// A read that waited or took longer than this is logged, with what it was.
const SLOW_MS = 2_000;

/// `held`: the read it is answering, if any. `chat`: the reader kept for chat reads.
type Slot = { worker: Worker; held: Asked | null; chat: boolean; idle?: () => void };

/// A read in line or being answered: when it was asked and when a reader took it, and the reader it is best read in (a
/// session's history, where its reading stands in memory).
type Asked = {
  ask: Ask;
  told: boolean;
  /// A chat read (`chat`): it may use any reader free; the others only the bulk ones.
  chat: boolean;
  session: string | null;
  home: Slot | null;
  at: number;
  took: number;
  resolve: (text: string) => void;
  reject: (error: Error) => void;
};

/// How many sessions' readers are remembered (the most recently read).
const HOMES = 4096;
/// How long after the store changes its log is written into the database (`checkpointSoon`): at most this often.
const CHECKPOINT_MS = 2_000;
/// A chat or a file, read whole and bounded by itself.
const CHAT = new Set(["thread", "sessionFile"]);
/// The most entries or letters a chat read gives (a page of an `after` is clamped to 500 too).
const PAGE = 500;

/// Whether a read is one a person is waiting on to see a message or a file, and bounded: a chat, a file, one chat's
/// current or older page, or a range or catch-up of at most PAGE (as the streams read the message just said). An open
/// `after` or a wide range (older clients page everything at once) is bulk.
export function chat(op: string, args: unknown): boolean {
  if (CHAT.has(op)) return true;
  if (op !== "entries" && op !== "letters") return false;
  const params = (args as { params?: unknown } | null)?.params;
  const pairs: [string, unknown][] = Array.isArray(params) ? params.filter((p): p is [string, unknown] => Array.isArray(p) && p.length >= 2) : Object.entries(params ?? {});
  const value = (key: string) => pairs.find(([name]) => name === key)?.[1];
  const has = (key: string) => pairs.some(([name]) => name === key);
  if (has("after")) return has("limit");
  if (!has("from") && !has("to")) return true;
  const [from, to] = [Number(value("from")), Number(value("to"))];
  return Number.isSafeInteger(from) && Number.isSafeInteger(to) && from >= 0 && to >= from && to - from < PAGE;
}

export class Readers {
  private slots: Slot[] = [];
  /// The reads no reader has taken yet: those told first, each in the order asked.
  private line: Asked[] = [];
  /// The reader each session's history was last read in (`timeline`).
  private homes = new Map<string, Slot>();
  private next = 0;
  private closed = false;
  /// A checkpoint is armed or running (`checkpointSoon`), and the store changed again since it was armed.
  private checkpointing = false;
  private again = false;
  private readonly data: string;
  /// How many bulk readers at most; the chat reader is one more.
  private readonly bulk: number;
  private readonly workerFile: URL | undefined;
  /// People's names as their credentials say them (the admin API's `deps.names`), given to every read.
  readonly names = new Map<string, string>();
  /// What only the hub knows, given to every read: sessions' process states and client keys (the hub sets these).
  processes: () => Map<string, string> = () => new Map();
  clientKeys: () => Map<string, string> = () => new Map();

  /// At most two by default, one of them the chat reader (STILLFAIL_READERS says how many in all; never fewer than
  /// one of each).
  constructor(data: string, size = Number(process.env.STILLFAIL_READERS) || Math.min(2, Math.max(1, availableParallelism() - 1)), workerFile?: URL) {
    this.data = data;
    this.bulk = Math.max(1, size - 1);
    this.workerFile = workerFile;
  }

  private start(chat: boolean): Slot {
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/read/worker.js.
    const file = this.workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./read/worker.js", import.meta.url);
    // A reader's heap stays small: what it builds is answered and dropped.
    const worker = new Worker(file, { workerData: { data: this.data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    const slot: Slot = { worker, held: null, chat };
    worker.on("message", (answer: Answer) => {
      const asked = slot.held;
      slot.held = null;
      if (asked !== null && asked.ask.id === answer.id) {
        const now = wall.now();
        if (now - asked.at > SLOW_MS) log.warn("readers", "a read went slowly", { op: asked.ask.op, told: asked.told, waitedMs: asked.took - asked.at, ms: now - asked.took });
        if (answer.text !== undefined) asked.resolve(answer.text);
        else asked.reject(new HttpError(answer.status ?? 500, answer.error ?? "read failed"));
      }
      this.pump();
    });
    worker.on("error", (error) => log.error("readers", "a reader failed", { error: error.message, reading: slot.held?.ask.op ?? null }));
    worker.on("exit", (code) => {
      slot.idle?.();
      this.slots = this.slots.filter((s) => s !== slot);
      slot.held?.reject(new HttpError(500, `the reader stopped (exit ${code})`));
      slot.held = null;
      this.pump();
    });
    this.slots.push(slot);
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

  /// The answer, as JSON text. `told`: what an event stream tells, read before the pages asked.
  read(op: string, args: unknown, lang: Ask["lang"], { told = false }: { told?: boolean } = {}): Promise<string> {
    if (this.closed) return Promise.reject(new HttpError(502, "station stopping"));
    // A session's history read where it was read before: that reader keeps where its reading stands in memory, another
    // reads it from disk (read/transcripts.ts).
    const session = (op === "timeline" || op === "transcriptState") && typeof (args as { key?: unknown })?.key === "string" ? (args as { key: string }).key : null;
    const home = session !== null ? this.homes.get(session) : undefined;
    const ask: Ask = { id: this.next++, op, args, lang, names: [], processes: [], clientKeys: [] };
    return new Promise((resolve, reject) => {
      const asked: Asked = { ask, told, chat: chat(op, args), session, home: home !== undefined && this.slots.includes(home) ? home : null, at: wall.now(), took: 0, resolve, reject };
      const behind = told ? this.line.findIndex((a) => !a.told) : -1;
      if (behind < 0) this.line.push(asked);
      else this.line.splice(behind, 0, asked);
      this.pump();
    });
  }

  /// Reads in line go to readers free, the first first (a session's history to its home reader when that one is free):
  /// a chat read to the chat reader or any bulk reader free, a bulk read to a bulk reader only. One that cannot be
  /// placed holds up none of the others.
  private pump() {
    if (this.closed) return;
    for (let at = 0; at < this.line.length; ) {
      const asked = this.line[at]!;
      const slot = this.slotFor(asked);
      if (slot === null) {
        at++;
        continue;
      }
      this.line.splice(at, 1);
      this.give(slot, asked);
    }
    for (const slot of this.slots) if (slot.held === null) this.letGoLater(slot);
  }

  /// A reader free for this read, started if there is room for one: null when it has to wait.
  private slotFor(asked: Asked): Slot | null {
    const free = (s: Slot) => s.held === null && this.slots.includes(s);
    if (asked.home !== null && free(asked.home) && (asked.chat || !asked.home.chat)) return asked.home;
    const chatSlot = this.slots.find((s) => s.chat);
    const bulkSlots = this.slots.filter((s) => !s.chat);
    if (asked.chat) {
      if (chatSlot === undefined) return this.start(true);
      if (free(chatSlot)) return chatSlot;
    }
    const idle = bulkSlots.find(free);
    if (idle !== undefined) return idle;
    return bulkSlots.length < this.bulk ? this.start(false) : null;
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
      this.read("checkpoint", {}, "en")
        .catch((error) => log.warn("readers", "the database's log not written into it", { error: (error as Error).message }))
        .finally(() => {
          this.checkpointing = false;
          if (this.again) this.checkpointSoon();
        });
    });
  }

  /// Each running reader's JS heap in use, in bytes (for the memory log).
  heaps(): Promise<number[]> {
    return Promise.all(this.slots.map((s) => s.worker.getHeapStatistics().then((h) => h.used_heap_size, () => 0)));
  }

  close() {
    this.closed = true;
    for (const asked of this.line.splice(0)) asked.reject(new HttpError(502, "station stopping"));
    for (const { worker } of this.slots) void worker.terminate();
  }
}
