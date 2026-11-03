// Move compact usage buckets after a session changes workspace. Each transaction is bounded and yields to foreground writes.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { hasCompactUsage, moveCompactStep } from "../store/usage-compact.ts";

const db = new DatabaseSync(workerData.path as string);
const priority = new Int32Array(workerData.priority as SharedArrayBuffer);
db.exec("PRAGMA busy_timeout = 250; PRAGMA synchronous = NORMAL");
let requested = false;
let running = false;

async function drain(): Promise<void> {
  if (running) return;
  running = true;
  try {
    do {
      requested = false;
      if (!hasCompactUsage(db)) continue;
      for (;;) {
        if (!takeBackfill(priority, threadId)) { await wall.sleep(20); continue; }
        let result: ReturnType<typeof moveCompactStep> | undefined;
        try { result = moveCompactStep(db); }
        catch (error) {
          const code = (error as { errcode?: number }).errcode;
          if (code === undefined || ![5, 6].includes(code & 255)) throw error;
        } finally { giveBackfill(priority, threadId); }
        if (result?.session !== undefined) parentPort!.postMessage({ session: result.session });
        if (result?.done) break;
        await wall.sleep(20);
      }
    } while (requested);
  } catch (error) {
    parentPort!.postMessage({ error: (error as Error).message });
  } finally {
    running = false;
    parentPort!.postMessage({ idle: true });
  }
}

parentPort!.on("message", (message: { wake?: boolean }) => {
  if (message.wake) { requested = true; void drain(); }
});
