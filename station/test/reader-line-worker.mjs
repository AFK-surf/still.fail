import { parentPort } from "node:worker_threads";

parentPort.on("message", (ask) => {
  const state = new Int32Array(ask.args.state);
  if (ask.op === "thread") Atomics.or(state, 1, 1);
  if (ask.op === "told") Atomics.or(state, 1, 2);
  if (ask.op === "sessionFile") Atomics.or(state, 1, 4);
  Atomics.add(state, 0, 1);
  Atomics.notify(state, 0);
  if (!["thread", "told", "sessionFile"].includes(ask.op)) Atomics.wait(state, 2, 0);
  parentPort.postMessage({ id: ask.id, text: "{}" });
});
