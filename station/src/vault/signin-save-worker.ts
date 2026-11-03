import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { stepSigninSaveIndex } from "./signin-save-index.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 250 });
const priority = workerData.priority ? new Int32Array(workerData.priority as SharedArrayBuffer) : null;
db.exec("PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (session: string) => {
  let result: { done: boolean; error?: string } = { done: false };
  if (takeBackfill(priority, threadId)) {
    try { result = stepSigninSaveIndex(db, session); }
    catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
    } finally { giveBackfill(priority, threadId); }
  }
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage(result);
});
