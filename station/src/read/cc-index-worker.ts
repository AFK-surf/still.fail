import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { CcIndexPreparation } from "../store/cc-thread-index.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 250 });
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;
const preparation = new CcIndexPreparation();
db.exec("PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (message: { session: string; cancel?: boolean }) => {
  if (message.cancel) { preparation.cancel(message.session); return; }
  let result: { done: boolean; error?: string } = { done: false };
  let owns = false;
  try {
    if ((owns = takeBackfill(priority, threadId))) result = { done: preparation.step(db, message.session).done };
  } catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
  } finally { if (owns) giveBackfill(priority, threadId); }
  if (!result.done && !result.error) await wall.sleep(REQUEST_BACKFILL_PAUSE_MS);
  parentPort!.postMessage(result);
});
