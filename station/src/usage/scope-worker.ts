// Move compact usage buckets and apply their totals in bounded transactions, yielding to foreground writes.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { compactTotalsStep, hasCompactUsage, moveCompactStep } from "../store/usage-compact.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");
let requested = false;
let running = false;

async function drain(): Promise<void> {
  if (running) return;
  running = true;
  try {
    do {
      requested = false;
      if (!hasCompactUsage(db)) continue;
      let movesDone = false;
      for (;;) {
        // An idle read request can wake us too; do not acquire the writer just to discover there is no work.
        if (!movesDone && db.prepare("SELECT 1 FROM usage_compact_moving LIMIT 1").get() === undefined) movesDone = true;
        if (movesDone && db.prepare("SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_session WHERE pending = 1 LIMIT 1").get() === undefined) break;
        if (!takeBackfill(priority, threadId)) { await wall.sleep(20); continue; }
        let result: { done: boolean; session?: string; sessions?: string[]; from?: number } | undefined;
        try { result = movesDone ? compactTotalsStep(db) : moveCompactStep(db); }
        catch (error) {
          const code = (error as { errcode?: number }).errcode;
          if (code === undefined || ![5, 6].includes(code & 255)) throw error;
        } finally { giveBackfill(priority, threadId); }
        if (result?.session !== undefined) parentPort!.postMessage({ session: result.session });
        if (result?.sessions?.length) parentPort!.postMessage({ sessions: result.sessions, ...(result.from !== undefined ? { from: result.from } : {}) });
        if (result?.done) {
          if (movesDone) break;
          movesDone = true;
          continue;
        }
        await wall.sleep(20);
      }
    } while (requested);
  } catch (error) {
    parentPort!.postMessage({ error: (error as Error).message });
  } finally {
    running = false;
    parentPort!.postMessage({ idle: true });
  }
}

parentPort!.on("message", (message: { wake?: boolean }) => {
  if (message.wake) { requested = true; void drain(); }
});
