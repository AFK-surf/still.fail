// A restore put in (restore.ts `takeBack`), off the thread that opens the store after it.
import { parentPort, workerData } from "node:worker_threads";
import { takeBack } from "./restore.ts";

try {
  parentPort!.postMessage({ ready: takeBack(workerData.data, workerData.db, workerData.now) });
} catch (e) {
  parentPort!.postMessage({ error: (e as Error).message });
}
