// A reader: answers the admin API's reads off the main thread, on a read-only connection of its own (WAL lets readers
// and the one writer go on together). What it answers is text, ready to send: no copying the value across threads.
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import type { Lang } from "../ops/i18n.ts";
import { ops } from "./ops.ts";
import { openStore, usageChatsReady, usageGroupsBatched, UsageSummaryCache, USAGE_CHATS_PENDING } from "./store.ts";
import { compactTotal, hasCompactUsage } from "../store/usage-compact.ts";
import { validHistoryRange } from "./usage.ts";
import { HttpError, setSpoken } from "./views.ts";

export type Ask = { id: number; op: string; args: any; lang: Lang; names: [string, string][]; processes: [string, string][]; clientKeys: [string, string][] };
export type Answer = { id: number; text?: string; status?: number; error?: string };
/// Said once, as a reader is ready: how long it took from its first line (its code read in) to its store opened.
export type Ready = { ready: { loadedMs: number; openedMs: number } };

const loaded = performance.now();
const store = openStore(workerData.data as string);
const usageCache = new UsageSummaryCache();
parentPort!.postMessage({ ready: { loadedMs: Math.round(loaded), openedMs: Math.round(performance.now() - loaded) } } satisfies Ready);

/// The connection a checkpoint is made on: one that may write (a read-only one may not), made at the first, and used
/// for nothing else.
let writer: DatabaseSync | null = null;

/// What of the log (the WAL) is not in the database yet, written into it, as far as no reader still reads it (a passive
/// checkpoint: it waits for no one, and holds up no read or write): the main thread leaves it to the readers (store.ts).
function checkpoint(): unknown {
  if (writer === null) {
    writer = new DatabaseSync(join(workerData.data as string, "stillfail.db"), { timeout: 0 });
    writer.exec("PRAGMA synchronous = NORMAL");
  }
  return writer.prepare("PRAGMA wal_checkpoint(PASSIVE)").get();
}

parentPort!.on("message", async (ask: Ask) => {
  let answer: Answer;
  try {
    if (ask.op === "checkpoint") {
      parentPort!.postMessage({ id: ask.id, text: JSON.stringify(checkpoint()) } satisfies Answer);
      return;
    }
    setSpoken(ask.lang);
    store.names = new Map(ask.names);
    store.processes = new Map(ask.processes);
    store.clientKeys = new Map(ask.clientKeys);
    const op = ops[ask.op];
    if (!op) throw new HttpError(500, `no read ${ask.op}`);
    // One snapshot for the whole read: its statements see the same database, and what the first of them read in serves
    // the rest. Each statement began on its own before, and as the station writes all the while (each model call, each
    // message), SQLite let go of all this reader held at nearly every one (a connection's pages are dropped whenever the
    // database changed since it last read): each was read again, from the disk while memory was short.
    store.db.exec("BEGIN");
    try {
      // Usage can span many minutes. Read its compact statistics in bounded steps on this same snapshot, resting
      // between them so the cold database does not displace other work's pages all at once.
      const a = ask.args;
      const batched = ask.op === "usage"
        ? await usageGroupsBatched(store, BigInt(a.from), BigInt(a.to), BigInt(a.tz), a.viewer ?? null, undefined, usageCache) : null;
      let batchedHistory = null;
      let historyPrepassMs: number | undefined;
      if (ask.op === "usage" && a.history === true && a.historyRange && hasCompactUsage(store.db)) {
        const range = { from: BigInt(a.historyRange.from), to: BigInt(a.historyRange.to) };
        const offset = BigInt(a.tz);
        const coverage = store.db.prepare("SELECT old_days FROM usage_compact_since WHERE id = 1").get() as { old_days: number };
        let chatsReady = true;
        try { usageChatsReady(store, a.viewer ?? null); }
        catch (error) { if ((error as Error).message === USAGE_CHATS_PENDING) chatsReady = false; else throw error; }
        if (chatsReady && coverage.old_days === 0 && validHistoryRange(range, offset) &&
          compactTotal(store.db, a.viewer ?? null, range.to / 60_000n) !== null) {
          const started = performance.now();
          const result = await usageGroupsBatched(store, range.from, range.to, offset, a.viewer ?? null, undefined, usageCache, "history");
          historyPrepassMs = Math.round(performance.now() - started);
          if (result !== null) batchedHistory = { range, result };
        }
      }
      answer = { id: ask.id, text: JSON.stringify(op(store, { ...a, ...(batched === null ? {} : { batchedSummary: batched }),
        ...(batchedHistory === null ? {} : { batchedHistory }), ...(historyPrepassMs === undefined ? {} : { historyPrepassMs }) })) };
    } finally {
      store.db.exec("COMMIT");
    }
  } catch (error) {
    answer = { id: ask.id, status: error instanceof HttpError ? error.status : 500, error: (error as Error).message };
  }
  parentPort!.postMessage(answer);
});
