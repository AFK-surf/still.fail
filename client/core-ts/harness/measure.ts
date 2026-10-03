// Memory and time to the first view, of one core in this process (docs/core-ts.md, 测量): the fake cloud and a station
// with `chats` chats of `per` entries each (harness/station.ts, in a process of its own: harness/serve.ts) over the host
// wire.
//
//   node harness/measure.ts <ts | path to the Rust core's addon> <data dir> <chats> <per>
//
// Run it twice on the same (at first empty) data dir: the first run signs in and reads everything (cold), the second
// starts from what the first kept (warm). It prints one JSON line: when the chat list first showed every chat (ms
// from the core's start), and the process's memory once the core had settled (10 s on).
import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { start as startTs } from "../src/hosts/node.ts";
import { apply } from "../src/delta.ts";

type CoreApi = { connect(): number; receive(client: number, json: string): void };
const [which, dir, chats, per] = [process.argv[2], process.argv[3], Number(process.argv[4] ?? 200), Number(process.argv[5] ?? 30)];
const PORT = 47_400;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// The cloud and station in a process of their own: what is measured is the core's.
const server = spawn(process.execPath, [new URL("./serve.ts", import.meta.url).pathname, String(PORT), String(chats), String(per)], { stdio: ["ignore", "pipe", "inherit"] });
await new Promise<void>((resolve) => server.stdout!.once("data", () => resolve()));
const origin = `http://127.0.0.1:${PORT}`;
const warm = existsSync(join(dir, "core.db")) || existsSync(join(dir, "accounts.json")) || existsSync(join(dir, "storage"));
const values = new Map<number, unknown>();
const answers = new Map<number, unknown>();
let full: number | null = null;
let first: number | null = null;
const t0 = performance.now();
const rows = (v: unknown) => ((v as { days?: { items: unknown[] }[] })?.days ?? []).reduce((n, d) => n + d.items.length, 0);
const listener = (_client: number, json: string) => {
  const m = JSON.parse(json);
  if ("value" in m) values.set(m.id, m.value);
  else if ("delta" in m) values.set(m.id, apply(values.get(m.id), m.delta));
  else if ("ok" in m || "error" in m) answers.set(m.id, m.ok ?? m.error);
  if (m.id === 1 && first === null && ("value" in m || "delta" in m)) first = performance.now() - t0;
  if (m.id === 1 && full === null && rows(values.get(1)) >= chats) full = performance.now() - t0;
};
let core: CoreApi;
if (which === "ts") core = startTs(dir, origin, listener, undefined, { hostWire: true });
else {
  process.env.STILLFAIL_HOST_WIRE = "1";
  core = (createRequire(import.meta.url)(which) as { start: (d: string, o: string, l: typeof listener) => CoreApi }).start(dir, origin, listener);
}
const ui = core.connect();
const send = (m: unknown) => core.receive(ui, JSON.stringify(m));
send({ id: 1, subscribe: { topic: "chats", scope: "ws1", mine: false } });
if (!warm) {
  send({ id: 101, call: "auth.begin", params: { redirect_uri: "stillfail://auth/callback", return_to: "/" } });
  while (!answers.has(101)) await sleep(5);
  const state = new URL(String((answers.get(101) as { url: string }).url)).searchParams.get("state");
  send({ id: 102, call: "auth.complete", params: { query: `?code=code-alice&state=${state}` } });
}
while (full === null && performance.now() - t0 < 60_000) await sleep(5);
await sleep(10_000);
globalThis.gc?.();
const mem = process.memoryUsage();
console.log(JSON.stringify({ core: which === "ts" ? "ts" : "rust", start: warm ? "warm" : "cold", chats, per, firstValueMs: Math.round(first ?? -1), allChatsMs: Math.round(full ?? -1), rssMb: Math.round(mem.rss / 1e5) / 10, heapMb: Math.round(mem.heapUsed / 1e5) / 10, externalMb: Math.round(mem.external / 1e5) / 10, buffersMb: Math.round(mem.arrayBuffers / 1e5) / 10 }));
server.kill();
process.exit(0);
