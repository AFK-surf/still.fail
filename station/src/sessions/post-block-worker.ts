// Read only the requested old thread suffix, in bounded steps, away from the station's request thread.
import { DatabaseSync } from "node:sqlite";
import { parentPort, threadId, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { giveBackfill, takeBackfill } from "../store/backfill.ts";
import { POST_BLOCK_SIZE, postBlocksStep } from "../store/post-blocks.ts";

const db = new DatabaseSync(workerData.path as string, { timeout: 250 });
const priority = workerData.priority instanceof SharedArrayBuffer ? new Int32Array(workerData.priority) : null;
db.exec("PRAGMA synchronous = NORMAL");

parentPort!.on("message", async ({ thread, after }: { thread: number; after: number }) => {
  let result: { done: boolean; error?: string } = { done: false };
  let owns = false;
  try {
    result = postBlocksStep(db, thread, after, POST_BLOCK_SIZE, () => (owns = takeBackfill(priority, threadId)));
  } catch (error) {
    const code = (error as { errcode?: number }).errcode;
    if (code === undefined || ![5, 6].includes(code & 255)) result = { done: false, error: (error as Error).message };
  } finally {
    if (owns) giveBackfill(priority, threadId);
  }
  if (!result.done && !result.error) await wall.sleep(20);
  parentPort!.postMessage(result);
});
