// The vault's use pages and their resumable backfill run away from the station's request thread.
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { backfillNextWorkspace, backfillUseIndex, readUses, useIndexComplete, type UseAnswer, type UseRead } from "./use-index.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 5_000 });
db.exec("PRAGMA synchronous = NORMAL");
const waiting: UseRead[] = [];
const ready = new Set<string>();
let backgroundComplete = false;
let scheduled = false;

function schedule() {
  if (scheduled) return;
  scheduled = true;
  setImmediate(() => {
    scheduled = false;
    const q = waiting.shift();
    try {
      if (q) {
        if (ready.has(q.ws) || useIndexComplete(db, q.ws) || backfillUseIndex(db, q.ws)) {
          ready.add(q.ws);
          parentPort!.postMessage({ id: q.id, bodies: readUses(db, q) } satisfies UseAnswer);
        } else waiting.push(q); // Give other workspaces a turn between this one's batches.
      } else if (!backgroundComplete) backgroundComplete = backfillNextWorkspace(db);
    } catch (e) {
      // Another process can be writing at handover. Give it the connection and resume the same batch later.
      const sqliteCode = (e as { errcode?: number }).errcode;
      if (sqliteCode !== undefined && ((sqliteCode & 0xff) === 5 || (sqliteCode & 0xff) === 6)) {
        if (q) waiting.push(q);
        wall.after(50, schedule);
        return;
      }
      if (q) parentPort!.postMessage({ id: q.id, error: (e as Error).message } satisfies UseAnswer);
      else {
        // A broken old request must not prevent a different workspace's indexed page from being read.
        log.error("vault", "the use history backfill stopped", { error: (e as Error).message });
        backgroundComplete = true;
      }
    }
    if (waiting.length || !backgroundComplete) schedule();
  });
}

parentPort!.on("message", (q: UseRead) => {
  waiting.push(q);
  schedule();
});
schedule();
