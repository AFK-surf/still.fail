import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { dropUsageIndexStep, stopUsageIndexes } from "../store/usage-retire.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");
const pause = () => new Promise<void>((resolve) => setTimeout(resolve, 20));
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
  await step(() => stopUsageIndexes(db));
  while (!await step(() => dropUsageIndexStep(db))) await pause();
  parentPort!.postMessage({ complete: true });
} finally { db.close(); }
