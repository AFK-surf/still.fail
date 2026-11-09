import { parentPort } from "node:worker_threads";

// A reader that counts the reads it starts (state[0]), says which kinds started (state[1]: 1 a thread, 2 a told read,
// 4 one held), and holds those asked to be held (`hold`) until the gate opens (state[2]).
parentPort.on("message", (ask) => {
  const state = new Int32Array(ask.args.state);
  if (ask.op === "thread") Atomics.or(state, 1, 1);
  if (ask.op === "told") Atomics.or(state, 1, 2);
  if (ask.args.hold) Atomics.or(state, 1, 4);
  Atomics.add(state, 0, 1);
  Atomics.notify(state, 0);
  if (ask.args.hold) Atomics.wait(state, 2, 0);
  parentPort.postMessage({ id: ask.id, text: "{}" });
});
