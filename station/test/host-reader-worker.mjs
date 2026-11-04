import { parentPort } from "node:worker_threads";

let ticks = 0;
parentPort.on("message", ({ id, op }) => {
  const value = op === "host"
    ? { info: { checkedAt: 1_000, cpuBusy: null }, seen: { at: 1_000, ticks: [10, 20] }, needsTicks: true }
    : op === "hostTicks" ? (++ticks === 1 ? [10, 20] : [20, 40]) : {};
  parentPort.postMessage({ id, text: JSON.stringify(value) });
});
