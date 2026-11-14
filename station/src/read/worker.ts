// A reader: answers the admin API's reads off the main thread, on a read-only connection of its own (WAL lets readers
// and the one writer go on together). What it answers is text, ready to send: no copying the value across threads.
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import type { Lang } from "../ops/i18n.ts";
import { ops } from "./ops.ts";
import { openStore, usageGroupsBatched, UsageSummaryCache } from "./store.ts";
import { HttpError, setSpoken } from "./views.ts";
import { learn } from "../accounts/catalog.ts";
import { cardEditPage, cardMessagePage } from "../store/card-outbox.ts";

export type Ask = { id: number; op: string; args: any; lang: Lang; names: [string, string][]; processes: [string, string][]; clientKeys: [string, string][]; catalog?: Record<string, unknown> };
/// `body`: the text as its bytes, as the MoonBit reader gives it (mb-reader.ts `Said`).
export type Answer = { id: number; text?: string; body?: Buffer; status?: number; error?: string; prepareUpJobs?: string; prepareWorkspaceUpJobs?: boolean };
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
    if (ask.catalog !== undefined) learn(ask.catalog);
    store.names = new Map(ask.names);
    store.processes = new Map(ask.processes);
    store.clientKeys = new Map(ask.clientKeys);
    store.prepareUpJobs = null;
    store.prepareWorkspaceUpJobs = false;
    // Internal queue work is deliberately not in `ops`: the changed-list API must not expose an unscoped card read.
    if (ask.op === "internalCardEditPage" || ask.op === "internalCardMessagePage") {
      store.db.exec("BEGIN");
      let page;
      try {
        const a = ask.args;
        page = ask.op === "internalCardEditPage" ? cardEditPage(store.db, a.thread, a.target, a.before)
          : cardMessagePage(store.db, a.thread, a.target, a.before);
      } finally { store.db.exec("COMMIT"); }
      parentPort!.postMessage({ id: ask.id, text: JSON.stringify(page) } satisfies Answer);
      return;
    }
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
      const batched = ask.op === "usage" && a.detailsPreparing !== true
        ? await usageGroupsBatched(store, BigInt(a.from), BigInt(a.to), BigInt(a.tz), a.viewer ?? null, undefined, usageCache,
          a.summaryStrict === true ? a.summaryPrepared === true : undefined) : null;
      answer = { id: ask.id, text: JSON.stringify(op(store, { ...a, ...(batched === null ? {} : { batchedSummary: batched }) })) };
      if (store.prepareUpJobs !== null) answer.prepareUpJobs = store.prepareUpJobs;
      if (store.prepareWorkspaceUpJobs) answer.prepareWorkspaceUpJobs = true;
    } finally {
      store.db.exec("COMMIT");
    }
  } catch (error) {
    answer = { id: ask.id, status: error instanceof HttpError ? error.status : 500, error: (error as Error).message };
  }
  parentPort!.postMessage(answer);
});
