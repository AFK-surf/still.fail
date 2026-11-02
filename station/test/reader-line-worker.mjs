import { parentPort } from "node:worker_threads";

parentPort.on("message", (ask) => {
  const state = new Int32Array(ask.args.state);
  if (ask.op === "thread") Atomics.or(state, 1, 1);
  if (ask.op === "told") Atomics.or(state, 1, 2);
  if (ask.op === "sessionFile") Atomics.or(state, 1, 4);
  Atomics.add(state, 0, 1);
  Atomics.notify(state, 0);
  if (ask.op === "entries" || ask.op === "letters") Atomics.or(state, 1, 8);
  // Chat reads answer at once; any other (or one told to hold) waits at the gate.
  if (!["thread", "told", "sessionFile", "entries", "letters"].includes(ask.op) || ask.args.hold) Atomics.wait(state, 2, 0);
  parentPort.postMessage({ id: ask.id, text: "{}" });
});
