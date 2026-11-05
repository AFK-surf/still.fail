// Prepare only requested recent-chat scopes, yielding the write lock and shared backfill priority after each batch.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { RecentChatPreparation } from "../store/chat-list-prepare.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 250 });
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;
db.exec("PRAGMA synchronous = NORMAL");
const preparation = new RecentChatPreparation(db);

parentPort!.on("message", async (message: { scope: string; cancel?: boolean }) => {
  if (message.cancel) return;
  let result: { done: boolean; error?: string } = { done: false };
  let owns = false;
  try {
    const scope: unknown = JSON.parse(message.scope);
    if (!Array.isArray(scope) || scope.length !== 2 || !scope.every((item) => item === null || typeof item === "string"))
      throw new Error("invalid recent chat scope");
    if ((owns = takeBackfill(priority, threadId))) {
      const step = preparation.step({ ws: scope[0], home: scope[1] });
      result = { done: step.done };
    }
  } catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
  } finally { if (owns) giveBackfill(priority, threadId); }
  if (!result.done && !result.error) await wall.sleep(REQUEST_BACKFILL_PAUSE_MS);
  parentPort!.postMessage(result);
});
