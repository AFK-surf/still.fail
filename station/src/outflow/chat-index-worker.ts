// Bring forward chat ordering in small transactions, leaving foreground writes and other background work a turn.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { installOutflowChatIndex, outflowChatIndexStep } from "../store/outflow-index.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = workerData.priority ? new Int32Array(workerData.priority as SharedArrayBuffer) : null;
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (scope: string) => {
  let result: { done: boolean; error?: string } = { done: false };
  if (takeBackfill(priority, threadId)) {
    try {
      installOutflowChatIndex(db);
      result = outflowChatIndexStep(db, scope);
    } catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
    } finally { giveBackfill(priority, threadId); }
  }
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage(result);
});
