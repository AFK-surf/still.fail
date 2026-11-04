import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { dropUsageIndexStep } from "../store/usage-retire.ts";
import { convertUsageHistoryStep, historyTransferPending } from "../store/usage-history.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");
// The wall timer does not hold a process open. Keep this worker's port alive while it is clearing the shared database.
parentPort!.ref();
const pause = () => wall.sleep(20);
async function step<T>(run: () => T): Promise<T> {
  for (;;) {
    if (!takeBackfill(priority, threadId)) { await pause(); continue; }
    try { return run(); }
    catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code === undefined || ![5, 6].includes(code & 255)) throw error;
    } finally { giveBackfill(priority, threadId); }
    await pause();
  }
}
try {
  const converting = historyTransferPending(db);
  while (!await step(() => convertUsageHistoryStep(db))) await pause();
  if (converting) parentPort!.postMessage({ historyReady: true });
  while (!await step(() => dropUsageIndexStep(db))) await pause();
  parentPort!.postMessage({ complete: true });
} finally { db.close(); parentPort!.close(); }
