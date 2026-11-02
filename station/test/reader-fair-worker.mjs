import { parentPort } from "node:worker_threads";

parentPort.on("message", (ask) => {
  const state = new Int32Array(ask.args.state);
  if (ask.op === "thread") Atomics.store(state, 1, 1);
  if (ask.op === "timeline") Atomics.compareExchange(state, 3, 0, 1);
  if (ask.op === "chatRows" && !ask.args.first) Atomics.compareExchange(state, 3, 0, 2);
  Atomics.add(state, 0, 1);
  Atomics.notify(state, 0);
  if (ask.args.first) Atomics.wait(state, 2, 0);
  parentPort.postMessage({ id: ask.id, text: "{}" });
});
