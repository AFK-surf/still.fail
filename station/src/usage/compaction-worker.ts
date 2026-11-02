// Complete the old main-call index away from the station's thread, giving other writers a turn after each batch.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { backfillUsageCompactions } from "../store/usage-compactions.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 100 });
db.exec("PRAGMA synchronous = NORMAL");
// A retry timer does not keep the worker alive on its own. The port stays open until the index is complete.
parentPort!.ref();
let waiting = false;
let foregroundWaiting = false;
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;

function step() {
  if (!takeBackfill(priority, threadId)) {
    if (!foregroundWaiting && priority !== null && Atomics.load(priority, 0) !== 0) {
      foregroundWaiting = true;
      parentPort!.postMessage({ foreground: true });
    }
    wall.after(BACKFILL_PAUSE_MS, step);
    return;
  }
  foregroundWaiting = false;
  try {
    const result = backfillUsageCompactions(db);
    waiting = false;
    if (result.done) {
      db.close();
      parentPort!.postMessage({ complete: true });
      parentPort!.close();
    } else wall.after(BACKFILL_PAUSE_MS, step);
  } catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code !== undefined && ((code & 0xff) === 5 || (code & 0xff) === 6)) {
      if (!waiting) parentPort!.postMessage({ waiting: true });
      waiting = true;
      wall.after(50, step);
      return;
    }
    log.error("usage", "the compaction history backfill stopped", { error: (error as Error).message });
    db.close();
    parentPort!.close();
  } finally {
    giveBackfill(priority, threadId);
  }
}

setImmediate(step);
