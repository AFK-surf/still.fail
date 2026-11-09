// A filesystem lookup that cannot yield until it returns, for the locator's cancellation test.
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { parentPort, workerData } from "node:worker_threads";

parentPort!.on("message", (message: { type: string; id: number; key?: string }) => {
  if (message.type !== "locate") return;
  if (message.key === "slow") {
    writeFileSync(join(workerData.data, "blocked"), "");
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 8000);
  }
  parentPort!.postMessage({ type: "done", id: message.id, identity: null, runtime: null, current: false });
});
