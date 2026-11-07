// Prepare only old state a reader needs, in small slices and without holding a write lock over the scan.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import { SAID_BATCH_SIZE, saidScanStep, type SaidScan } from "../store/said-state.ts";
import { archiveLastStep } from "../store/archive-last.ts";
import { legacyEditsMaintenanceStep, legacyMergedReadReady } from "../store/legacy-edits-build.ts";
import { TURN_COUNT_BATCH, turnCountStep, type TurnCountScan } from "../store/turn-state.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 250 });
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;
const scans = new Map<number, SaidScan>();
const counts = new Map<string, TurnCountScan>();
db.exec("PRAGMA synchronous = NORMAL");

parentPort!.on("message", async (message: { thread: number; cancel?: boolean; archiveLast?: boolean; legacyEdits?: boolean } | { session: string; cancel?: boolean }) => {
  if (message.cancel) {
    if ("thread" in message) {
      if (message.archiveLast || message.legacyEdits) return;
      const scan = scans.get(message.thread);
      scans.delete(message.thread);
      if (scan && takeBackfill(priority, threadId)) {
        try { db.prepare("DELETE FROM said_state_guard WHERE thread=? AND token=? AND ready=0").run(message.thread, scan.token); }
        catch { /* A later request or mutation replaces the guard. */ }
        finally { giveBackfill(priority, threadId); }
      }
    } else {
      const scan = counts.get(message.session);
      counts.delete(message.session);
      if (scan && takeBackfill(priority, threadId)) {
        try { db.prepare("DELETE FROM session_turns_guard WHERE session=? AND token=?").run(message.session, scan.token); }
        catch { /* A later request or mutation replaces the guard. */ }
        finally { giveBackfill(priority, threadId); }
      }
    }
    return;
  }
  let result: { done: boolean; error?: string } = { done: false };
  let owns = false;
  try {
    if ("thread" in message) {
      if (message.legacyEdits) {
        owns = takeBackfill(priority, threadId);
        if (owns) {
          if (!legacyMergedReadReady(db)) legacyEditsMaintenanceStep(db);
          result = { done: legacyMergedReadReady(db) };
        }
      } else if (message.archiveLast) {
        owns = takeBackfill(priority, threadId);
        if (owns) result = { done: archiveLastStep(db, message.thread).done };
      } else {
        const step = saidScanStep(db, message.thread, scans.get(message.thread) ?? null, SAID_BATCH_SIZE,
          () => (owns = takeBackfill(priority, threadId)));
        if (step.scan === null) scans.delete(message.thread);
        else scans.set(message.thread, step.scan);
        result = { done: step.done };
      }
    } else {
      const step = turnCountStep(db, message.session, counts.get(message.session) ?? null, TURN_COUNT_BATCH,
        () => (owns = takeBackfill(priority, threadId)));
      if (step.scan === null) counts.delete(message.session);
      else counts.set(message.session, step.scan);
      result = { done: step.done };
    }
  } catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
  } finally { if (owns) giveBackfill(priority, threadId); }
  if (!result.done && !result.error) await wall.sleep(REQUEST_BACKFILL_PAUSE_MS);
  parentPort!.postMessage(result);
});
