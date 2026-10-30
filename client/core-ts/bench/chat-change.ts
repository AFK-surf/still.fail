// What a change a station tells costs the core while the app shows Home (the topics its first page and frame ask), over
// the data bench/chat-open.ts seeds: one chat's summary moved on (a new reply in it, unread), as the events that came
// while the app was away come when it is back, one after another. Each: from the change put to the last topic it
// changed going out, and the core's busy time over all of them (CHAT_CHANGE_PROF=<file>: their CPU profile).
//
//   CHATS=1400 node bench/chat-open.ts seed <dir>
//   node --expose-gc bench/chat-change.ts <dir>
import { writeFileSync } from "node:fs";
import { Session } from "node:inspector/promises";
import { Core } from "../src/core.ts";
import { NodeHost } from "../src/hosts/node.ts";
import { HostWire } from "../src/station/wire.ts";

const [, , dir] = process.argv;
if (!dir) throw new Error("usage: chat-change.ts <dir>");
const ST = "w/s00";
const NOW = Date.UTC(2026, 9, 3, 12);

let lastOut = 0;
let outs = 0;
const host = new NodeHost(dir, "http://127.0.0.1:9", false, () => {
  lastOut = performance.now();
  outs++;
});
const core = await Core.create(host, { iroh: null, wire: () => new HostWire(host) });
const ui = core.connect();
const topics = [
  { topic: "chats", scope: "w", mine: false },
  { topic: "workspaceMarks" },
  { topic: "stations", scope: "w" },
  { topic: "workspaces" },
  { topic: "longJobs", scope: "w" },
  { topic: "notify" },
  { topic: "status" },
  { topic: "doing" },
  { topic: "prefs" },
];
topics.forEach((t, i) => core.receive(ui, { kind: "subscribe", id: i + 1, subscribe: t, keyed: true }));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
await sleep(5000);

function thread(i: number, last: number) {
  return {
    id: i, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${i}.0`, title: null, createdBy: null, creator: null, createdAt: NOW - i * 3_600_000,
    sessions: [{ thread: i, session: `k${i}`, connect: "ember", joinedAt: NOW - i * 3_600_000 }], last, read: last - 1, unread: 1, people: [],
    lastMessage: { seq: last, thread: i, ts: `${i}.${last}`, authorKind: "agent", author: `k${i}`, authorName: null, text: `第 ${last} 条新的回复`, attachments: [], quotes: [], declared: "final", createdAt: Date.now(), editedAt: null },
    firstText: `帮我看看第 ${i} 个问题`,
  };
}

const prof = process.env.CHAT_CHANGE_PROF ? new Session() : null;
if (prof) {
  prof.connect();
  await prof.post("Profiler.enable");
  await prof.post("Profiler.setSamplingInterval", { interval: 100 });
  await prof.post("Profiler.start");
}
const took: number[] = [];
for (let k = 0; k < 20; k++) {
  const i = 30 + k * 37;
  outs = 0;
  const t0 = performance.now();
  core.inner.stations.putThread(ST, thread(i, 200 + k));
  await sleep(400);
  took.push(outs === 0 ? -1 : Math.round(lastOut - t0));
}
if (prof) {
  const { profile } = await prof.post("Profiler.stop");
  writeFileSync(process.env.CHAT_CHANGE_PROF!, JSON.stringify(profile));
}
console.log(JSON.stringify({ took }));
await core.close();
host.close();
process.exit(0);
