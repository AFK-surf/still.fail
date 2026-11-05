// The vault's use pages and their resumable backfill run away from the station's request thread.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { BACKFILL_PAUSE_MS, REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { backfillPendingPreparation, pendingPreparationComplete } from "./pending-index.ts";
import { backfillReboxIndex } from "./rebox-index.ts";
import { backfillNextWorkspace, backfillUseIndex, readUses, useIndexComplete, type PendingPrepare, type UseAnswer, type UseRead } from "./use-index.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 100 });
db.exec("PRAGMA synchronous = NORMAL");
const waiting: (UseRead | PendingPrepare)[] = [];
const ready = new Set<string>();
let backgroundComplete = false;
let reboxComplete = false;
let reboxTurn = true;
let scheduled = false;
let foregroundWaiting = false;
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;

function schedule(delay = 0) {
  if (scheduled) return;
  scheduled = true;
  const step = () => {
    scheduled = false;
    const q = waiting.shift();
    // A completed page is a WAL read, not a backfill write. It must stay available even while a writer is waiting.
    if (q) {
      try {
        const pending = "kind" in q;
        if (pending ? pendingPreparationComplete(db, q.ws, q.members) : ready.has(q.ws) || useIndexComplete(db, q.ws)) {
          if (pending) {
            parentPort!.postMessage({ id: q.id, ready: true } satisfies UseAnswer);
          } else {
            ready.add(q.ws);
            parentPort!.postMessage({ id: q.id, bodies: readUses(db, q) } satisfies UseAnswer);
          }
          if (waiting.length || !backgroundComplete || !reboxComplete) schedule(waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
          return;
        }
      } catch (e) {
        const code = (e as { errcode?: number }).errcode;
        if (code !== undefined && ((code & 0xff) === 5 || (code & 0xff) === 6)) waiting.push(q);
        else parentPort!.postMessage({ id: q.id, error: (e as Error).message } satisfies UseAnswer);
        if (waiting.length || !backgroundComplete || !reboxComplete) schedule(waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
        return;
      }
    }
    if (!takeBackfill(priority, threadId)) {
      if (q) waiting.push(q);
      if (!foregroundWaiting && priority !== null && Atomics.load(priority, 0) !== 0) {
        foregroundWaiting = true;
        parentPort!.postMessage({ foreground: true, request: q?.id });
      }
      schedule(waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
      return;
    }
    foregroundWaiting = false;
    let background: "uses" | "rebox" | null = null;
    try {
      if (q) {
        const pending = "kind" in q;
        if (pending ? backfillPendingPreparation(db, q.ws, q.members) : backfillUseIndex(db, q.ws)) {
          if (pending) {
            parentPort!.postMessage({ id: q.id, ready: true } satisfies UseAnswer);
          } else {
            ready.add(q.ws);
            parentPort!.postMessage({ id: q.id, bodies: readUses(db, q) } satisfies UseAnswer);
          }
        } else waiting.push(q); // Give other workspaces a turn between this one's batches.
      } else if (!reboxComplete && (backgroundComplete || reboxTurn)) {
        background = "rebox";
        reboxComplete = backfillReboxIndex(db);
        reboxTurn = false;
      } else if (!backgroundComplete) {
        background = "uses";
        backgroundComplete = backfillNextWorkspace(db);
        reboxTurn = true;
      }
    } catch (e) {
      // Another process can be writing at handover. Give it the connection and resume the same batch later.
      const sqliteCode = (e as { errcode?: number }).errcode;
      if (sqliteCode !== undefined && ((sqliteCode & 0xff) === 5 || (sqliteCode & 0xff) === 6)) {
        if (q) waiting.push(q);
        schedule(waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
        return;
      }
      if (q) parentPort!.postMessage({ id: q.id, error: (e as Error).message } satisfies UseAnswer);
      else if (background === "rebox") {
        log.error("vault", "the recovery index backfill stopped", { error: (e as Error).message });
        reboxComplete = true;
      }
      else {
        // A broken old request must not prevent a different workspace's indexed page from being read.
        log.error("vault", "the use history backfill stopped", { error: (e as Error).message });
        backgroundComplete = true;
      }
    } finally {
      giveBackfill(priority, threadId);
    }
    if (waiting.length || !backgroundComplete || !reboxComplete) schedule(waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
  };
  if (delay > 0) wall.after(delay, step);
  else setImmediate(step);
}

parentPort!.on("message", (q: UseRead | PendingPrepare) => {
  foregroundWaiting = false;
  waiting.push(q);
  schedule();
});
schedule();
