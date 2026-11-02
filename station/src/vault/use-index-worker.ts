// The vault's use pages and their resumable backfill run away from the station's request thread.
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import { backfillUseIndex, readUses, type UseAnswer, type UseRead } from "./use-index.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 5_000 });
db.exec("PRAGMA synchronous = NORMAL");
const waiting: UseRead[] = [];
let complete = false;
let scheduled = false;

function schedule() {
  if (scheduled) return;
  scheduled = true;
  setImmediate(() => {
    scheduled = false;
    if (!complete) {
      try {
        complete = backfillUseIndex(db);
      } catch (e) {
        // Another process can be writing at handover. Give it the connection and resume the same batch later.
        const sqliteCode = (e as { errcode?: number }).errcode;
        if (sqliteCode !== undefined && ((sqliteCode & 0xff) === 5 || (sqliteCode & 0xff) === 6)) {
          setTimeout(schedule, 50);
          return;
        }
        throw e;
      }
    }
    if (complete) {
      const q = waiting.shift();
      if (q) {
        try {
          parentPort!.postMessage({ id: q.id, bodies: readUses(db, q) } satisfies UseAnswer);
        } catch (e) {
          parentPort!.postMessage({ id: q.id, error: (e as Error).message } satisfies UseAnswer);
        }
      }
    }
    if (!complete || waiting.length) schedule();
  });
}

parentPort!.on("message", (q: UseRead) => {
  waiting.push(q);
  schedule();
});
schedule();
