import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { fillUsageStep } from "../store/usage-fill.ts";
import { dropUsageIndexStep } from "../store/usage-retire.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");
// The wall timer does not hold a process open. Keep this worker's port alive while it is clearing the shared database.
parentPort!.ref();
const pause = () => wall.sleep(20);
const FILL_REST_MS = 200;
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
  while (!await step(() => dropUsageIndexStep(db))) await pause();
  // Old calls can wait: at most about a tenth of the time goes to them, however slow the machine is.
  let filled = false;
  for (;;) {
    const started = performance.now();
    if (await step(() => fillUsageStep(db))) break;
    filled = true;
    await wall.sleep(Math.max(FILL_REST_MS, (performance.now() - started) * 9));
  }
  parentPort!.postMessage({ complete: true, filled });
} finally { db.close(); parentPort!.close(); }
