// Complete the old main-call index away from the station's thread, giving other writers a turn after each batch.
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { backfillUsageCompactions } from "../store/usage-compactions.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 100 });
db.exec("PRAGMA synchronous = NORMAL");
// A retry timer does not keep the worker alive on its own. The port stays open until the index is complete.
parentPort!.ref();
let waiting = false;

function step() {
  try {
    const result = backfillUsageCompactions(db);
    waiting = false;
    if (result.done) {
      db.close();
      parentPort!.postMessage({ complete: true });
      parentPort!.close();
    } else setImmediate(step);
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
  }
}

setImmediate(step);
