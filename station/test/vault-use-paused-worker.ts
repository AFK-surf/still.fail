// Hold the worker's background timer until the test ends, so a new ready request must be served independently of it.
import { parentPort, workerData, type MessagePort } from "node:worker_threads";
import { wall } from "../src/ops/fibers.ts";

let resume: (() => void) | undefined;
wall.after = (_ms, callback) => {
  resume = callback;
  parentPort!.postMessage({ paused: true });
  return () => { if (resume === callback) resume = undefined; };
};
(workerData.control as MessagePort).on("message", () => { const next = resume; resume = undefined; next?.(); });
await import("../src/vault/use-index-worker.ts");
