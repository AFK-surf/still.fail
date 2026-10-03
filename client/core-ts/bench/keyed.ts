// Rule 7's measurement (docs/core-ts.md): a chat list of 2000 rows, one row changing, sent the Rust way (whole value
// diffed by index) and keyed (collections.ts). Bytes on the wire; the core's time from the change to the message
// (view, decorate, shape, diff); the UI's time to parse and apply it (web/src/core/delta.ts) and how many rows it gets
// as new objects (what React/Compose redraw).
// Run: node bench/keyed.ts
import { Data } from "../src/data.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { Store, type Source } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Views } from "../src/views/views.ts";
import { applyDelta } from "../../../web/src/core/delta.ts";

holdLanguage();
type J = any;
const ROWS = 2000;
const STATIONS = ["a", "b", "c"];
const VIEWS = new Set(["chats"]);

function setup(keyed: boolean) {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const store = new Store(host, runner);
  store.setShaped();
  // As core.ts has it: the station's rows are records (data.ts), read as they are kept.
  const data = new Data(host, runner);
  store.setHeld((topic) => data.shared(topic));
  data.onChange((topic) => store.changed(topic));
  const views = new Views({ host, runner, store, data, emailOf: () => "me@x.com", betaOf: () => false, relayName: () => null });
  const source: Source = { start: (t) => VIEWS.has(t.topic) && views.start(t), stop: (t) => VIEWS.has(t.topic) && views.stop(t), compute: (t) => views.compute(t) };
  store.setSource(source);
  store.subscribe(1, 1, { topic: "chats", scope: "ws" }, keyed);
  return { host, store, data };
}

const session = (key: string): J => ({ key, connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null });
function row(st: string, i: number, at: number, unread = false, text = "好的"): J {
  return {
    id: String(i), session: `s${i}`, thread: i, title: `${st} 上第 ${i} 个 chat 的标题`, agents: [session(`s${i}`)], unread, mine: i % 3 === 0, lastActiveAt: at, connect: null, origin: null,
    last: { seq: i * 10, thread: i, ts: `${i}.0`, authorKind: "agent", author: `s${i}`, authorName: null, text, attachments: [], quotes: [], declared: null, createdAt: at, editedAt: null },
  };
}

async function measure(keyed: boolean, change: "unread" | "top") {
  const { host, store, data } = setup(keyed);
  const now = host.nowMs();
  const set = (t: Topic, v: unknown) => (t.topic === "chatRows" || t.topic === "workspace" ? data.set(t, v) : store.set(t, { ok: v }));
  set({ topic: "workspace", workspace: "ws" }, { id: "ws", stations: STATIONS.map((id) => ({ id, name: id, last_seen: Math.trunc(now / 1000), version: "0.4.0" })) });
  await host.time.pass(100);
  const rows: Record<string, J[]> = {};
  STATIONS.forEach((st, s) => {
    rows[st] = Array.from({ length: ROWS / STATIONS.length + (s === 0 ? ROWS % STATIONS.length : 0) }, (_, i) => row(st, i + 1, now - (i * STATIONS.length + s) * 3_600_000 / 4));
    set({ topic: "link", station: `ws/${st}` }, { state: "online" });
    set({ topic: "chatRows", station: `ws/${st}` }, rows[st]);
  });
  await host.time.pass(100);
  let ui: unknown;
  for (const [, m] of host.takeEmitted() as [number, J][]) ui = "value" in m ? JSON.parse(JSON.stringify(m.value)) : applyDelta(ui, m.delta);
  const shown = (ui as J).days.reduce((n: number, d: J) => n + d.items.length, 0);
  const samples: { bytes: number; core: number; ui: number; newRows: number }[] = [];
  for (let round = 0; round < 30; round++) {
    const list = rows.b.slice();
    const at = 500 + round;
    if (change === "unread") list[at] = { ...list[at], unread: !list[at].unread };
    else list[at] = row("b", at + 1, host.nowMs() + round, false, `新消息 ${round}`);
    rows.b = list;
    const t0 = performance.now();
    set({ topic: "chatRows", station: "ws/b" }, list);
    await host.time.pass(60, 60);
    const out = host.takeEmitted() as [number, J][];
    const core = performance.now() - t0;
    const text = JSON.stringify(out[0][1]);
    const t1 = performance.now();
    const m = JSON.parse(text);
    const before = new Set((ui as J).days.flatMap((d: J) => d.items));
    ui = "value" in m ? m.value : applyDelta(ui, m.delta);
    const uiMs = performance.now() - t1;
    const newRows = (ui as J).days.flatMap((d: J) => d.items).filter((r: unknown) => !before.has(r)).length;
    samples.push({ bytes: text.length, core, ui: uiMs, newRows });
  }
  const med = (k: keyof (typeof samples)[0]) => samples.map((s) => s[k]).sort((a, b) => a - b)[samples.length >> 1];
  return { shown, bytes: med("bytes"), coreMs: +med("core").toFixed(2), uiMs: +med("ui").toFixed(3), newRows: med("newRows") };
}

for (const change of ["unread", "top"] as const) {
  for (const keyed of [false, true]) {
    console.log(JSON.stringify({ change, way: keyed ? "keyed" : "rust-style", ...(await measure(keyed, change)) }));
  }
}
process.exit(0);
