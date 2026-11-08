// What the core's computeds read is what makes them again (reactive.ts): state kept outside signals marks what changed
// (Marks), time is read as the moment a thing changes at (clock.ts), and a topic made from another reads it rather
// than watching it to be told.
import assert from "node:assert/strict";
import { test } from "node:test";
import { AgentEnvForms } from "../src/agent-env.ts";
import { Moments } from "../src/clock.ts";
import { Core } from "../src/core.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { computed, Marks, observe } from "../src/reactive.ts";
import { Runner } from "../src/runtime.ts";
import { Seen } from "../src/station/seen.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Local } from "../src/views/local.ts";
import { apply, subscribe } from "./helpers.ts";

holdLanguage();

/// How often `read` is made again, as `act` changes what it reads.
function runs(read: () => unknown): { count: () => number; stop: () => void } {
  let n = 0;
  const made = computed(() => { n++; return read(); });
  const stop = observe(() => void made.get(), (job) => job());
  return { count: () => n, stop };
}

test("a mark makes again what read its key or all of them, and nothing else", () => {
  const marks = new Marks();
  const a = runs(() => marks.read("a"));
  const b = runs(() => marks.read("b"));
  const all = runs(() => marks.read());
  marks.touch("a");
  assert.deepEqual([a.count(), b.count(), all.count()], [2, 1, 2]);
  marks.touch();
  assert.deepEqual([a.count(), b.count(), all.count()], [2, 1, 3]);
  for (const r of [a, b, all]) r.stop();
  // (no one reads them now: touched, nothing is made)
  marks.touch("a");
  assert.equal(a.count(), 2);
});

test("a station's change with no key reaches what read one of its keys; one of another station's does not", () => {
  const seen = new Seen();
  const log = runs(() => seen.read("w/a", "log", "k"));
  const other = runs(() => seen.read("w/b", "log", "k"));
  seen.touch("w/a", "log");
  seen.touch("w/a", "log", "k");
  seen.touch("w/a", "log", "j");
  seen.touch("w/a", "link");
  assert.deepEqual([log.count(), other.count()], [3, 1]);
});

test("a moment read makes its reader again as it comes, and one no longer read keeps no timer", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const moments = new Moments(() => host.nowMs(), runner);
  const at = host.nowMs() + 1_000;
  let reached = false;
  const r = runs(() => (reached = moments.reached(at)));
  await host.time.pass(999);
  assert.deepEqual([r.count(), reached], [1, false]);
  await host.time.pass(1);
  assert.deepEqual([r.count(), reached], [2, true]);
  r.stop();
  let later = 0;
  const gone = runs(() => { later++; moments.reached(host.nowMs() + 1_000); });
  gone.stop();
  await host.time.pass(2_000);
  assert.equal(later, 1);
});

test("a chat's outbox read makes again what showed it, not what showed another chat's", () => {
  const host = new FakeHost();
  const data = { of: () => undefined, putLocal: () => {}, dbs: () => [] } as never;
  const local = new Local(data, () => host.nowMs());
  const one = runs(() => local.outbox("w/a", 1));
  const two = runs(() => local.outbox("w/a", 2));
  const rows = runs(() => local.outboxes());
  local.outboxAdd("w/a", 1, { text: "hi" }, 0);
  assert.deepEqual([one.count(), two.count(), rows.count()], [2, 1, 2]);
});

test("a form made from its station's overview goes out again as the overview changes, with no watch of its own", async () => {
  const host = new FakeHost();
  const store = new Store(host, new Runner(host.time.clock));
  const forms = new AgentEnvForms(store);
  const overview: Topic = { topic: "overview", station: "ws/st" };
  const form: Topic = { topic: "agentEnvForm", station: "ws/st", form: "f" };
  store.setSource({ start: (t) => store.invalidate(t), stop: () => {}, compute: (t) => (t.topic === "agentEnvForm" ? { ok: forms.value(t) } : undefined) });
  forms.change(form, 1, "open", {});
  store.subscribe(1, 1, form);
  const station = (value: string) => store.set(overview, { ok: { agentEnv: [{ key: "HTTP_PROXY", value, secret: false }] } });
  await host.settle();
  station("http://p:1");
  await host.settle();
  host.takeEmitted();
  station("http://p:2");
  await host.settle();
  const sent = JSON.stringify(host.takeEmitted());
  assert.ok(sent.includes("http://p:2"), sent);
});

test("the status says a wait once it is slow, its seconds each second while shown, and wakes for nothing after", async () => {
  const host = new FakeHost();
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "status" });
  await host.settle();
  apply(host, values);
  const wait = core.inner.status.begin({ cloud: true }, "读取", false);
  await host.time.pass(1_500);
  assert.equal(host.takeEmitted().length, 0);
  await host.time.pass(600);
  apply(host, values);
  const first = (values.get(1) as { text: string }).text;
  assert.match(first, /2/);
  await host.time.pass(1_000);
  apply(host, values);
  assert.notEqual((values.get(1) as { text: string }).text, first);
  wait.end();
  await host.settle();
  apply(host, values);
  assert.deepEqual((values.get(1) as { items: unknown[] }).items, []);
  await host.time.pass(5_000);
  assert.equal(host.takeEmitted().length, 0);
});
