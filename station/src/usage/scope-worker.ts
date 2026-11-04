// Process one bounded workspace move or total batch, then let the station choose who goes next.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { compactTotalsStep, hasCompactUsage, moveCompactStep } from "../store/usage-compact.ts";
import { historyMovesPending, moveHistoryStep } from "../store/usage-history-moves.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (message: { wake?: boolean; scope?: string }) => {
  if (!message.wake) return;
  const scope = message.scope;
  let result: { done: boolean; session?: string; sessions?: string[]; from?: number; historyReady?: boolean; error?: string } = { done: true };
  try {
    if (scope === undefined && historyMovesPending(db)) {
      if (!takeBackfill(priority, threadId)) result = { done: false };
      else {
        try {
          const step = moveHistoryStep(db, 256);
          result = { done: step.done, historyReady: step.ready };
        } catch (error) {
          const code = (error as { errcode?: number }).errcode;
          if (code === undefined || ![5, 6].includes(code & 255)) throw error;
          result = { done: false };
        } finally { giveBackfill(priority, threadId); }
      }
    } else if (hasCompactUsage(db)) {
      const all = scope === undefined || scope === "G";
      const moving = all ? db.prepare("SELECT 1 FROM usage_compact_moving LIMIT 1").get()
        : db.prepare("SELECT 1 FROM usage_compact_moving_scope WHERE scope = ? LIMIT 1").get(scope);
      const pending = scope === undefined ? undefined : all
        ? db.prepare("SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_session WHERE pending = 1 LIMIT 1").get()
        : db.prepare("SELECT 1 FROM usage_compact INDEXED BY usage_compact_pending_scope WHERE pending = 1 AND scope = ? LIMIT 1").get(scope);
      if (moving !== undefined || pending !== undefined) {
        if (!takeBackfill(priority, threadId)) result = { done: false };
        else {
          try {
            result = moving !== undefined ? moveCompactStep(db, 256, all ? undefined : scope)
              : compactTotalsStep(db, 256, all ? undefined : scope);
          } catch (error) {
            const code = (error as { errcode?: number }).errcode;
            if (code === undefined || ![5, 6].includes(code & 255)) throw error;
            result = { done: false };
          } finally { giveBackfill(priority, threadId); }
        }
      }
    }
  } catch (error) {
    result = { done: false, error: (error as Error).message };
  }
  // Leave a gap for foreground work and other requested scopes between batches.
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage(result);
});
