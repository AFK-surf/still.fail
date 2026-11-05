// Bring forward only the active session keys of an older store, in bounded low-priority transactions.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { workspaceActivityStep } from "../store/workspace-activity.ts";
import { recoverWaitsStep } from "../store/recover-waits.ts";
import { awakeWaitsStep } from "../store/awake-waits.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (message: { kind?: "activity" | "recovery" | "awake" }) => {
  const kind = message.kind ?? "activity";
  let result: { done: boolean; error?: string } = { done: false };
  if (takeBackfill(priority, threadId)) {
    try { result = kind === "recovery" ? recoverWaitsStep(db) : kind === "awake" ? awakeWaitsStep(db) : workspaceActivityStep(db); }
    catch (error) {
      const code = (error as { errcode?: number }).errcode;
      if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
    } finally { giveBackfill(priority, threadId); }
  }
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage({ ...result, kind });
});
