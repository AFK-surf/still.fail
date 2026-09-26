import assert from "node:assert/strict";
import { test } from "node:test";
import { CoreClient, CoreError, type Channel, type Opener } from "../web/src/core/client.ts";
import { migrateLegacy } from "../web/src/core/migrate.ts";

/** A worker stand-in: records what the client posts and answers on demand. */
class FakeWorkers {
  opened: { sent: unknown[]; closed: boolean; reply: (data: unknown) => void; fail: (reason: string) => void }[] = [];
  delays: number[] = [];
  opener: Opener = (onMessage, onFail) => {
    const worker = { sent: [] as unknown[], closed: false, reply: onMessage, fail: onFail };
    this.opened.push(worker);
    const channel: Channel = { post: (message) => worker.sent.push(structuredClone(message)), close: () => { worker.closed = true; } };
    return channel;
  };
  get last() {
    const worker = this.opened.at(-1);
    assert.ok(worker);
    return worker;
  }
  client(): CoreClient {
    return new CoreClient(this.opener, { schedule: (ms, run) => { this.delays.push(ms); run(); } });
  }
}

test("a call is answered by the message with its id", async () => {
  const workers = new FakeWorkers();
  const client = workers.client();
  const first = client.call("station.request", { station: "local", method: "GET", path: "/overview" });
  const second = client.call("auth.signOut", { account: "a" });
  assert.deepEqual(workers.last.sent, [
    { id: 1, call: "station.request", params: { station: "local", method: "GET", path: "/overview" } },
    { id: 2, call: "auth.signOut", params: { account: "a" } },
  ]);
  workers.last.reply({ id: 2, error: { code: "signed_out", message: "已退出", status: 401 } });
  workers.last.reply({ id: 1, ok: { hosts: 1 } });
  assert.deepEqual(await first, { hosts: 1 });
  await assert.rejects(second, (error: unknown) => error instanceof CoreError && error.code === "signed_out" && error.status === 401 && error.message === "已退出");
});

test("subscription values and errors go to their subscriber until it unsubscribes", () => {
  const workers = new FakeWorkers();
  const client = workers.client();
  const seen: unknown[] = [];
  const stop = client.subscribe({ topic: "sessions", station: "w/s" }, (v) => seen.push(v), (e) => seen.push(e.code));
  assert.deepEqual(workers.last.sent, [{ id: 1, subscribe: { topic: "sessions", station: "w/s" } }]);
  workers.last.reply({ id: 1, value: [] });
  workers.last.reply({ id: 1, error: { code: "offline", message: "离线" } });
  workers.last.reply({ id: 1, value: [{ key: "k" }] });
  stop();
  stop();
  workers.last.reply({ id: 1, value: ["late"] });
  assert.deepEqual(seen, [[], "offline", [{ key: "k" }]]);
  assert.deepEqual(workers.last.sent.at(-1), { id: 1, unsubscribe: true });
  assert.equal(workers.last.sent.length, 2);
});

test("a failed worker is replaced: calls in flight fail, subscriptions come back", async () => {
  const workers = new FakeWorkers();
  const client = workers.client();
  const values: unknown[] = [];
  client.subscribe({ topic: "accounts" }, (v) => values.push(v), () => undefined);
  const stopped = client.subscribe({ topic: "link", station: "w/s" }, () => undefined, () => undefined);
  stopped();
  const pending = client.call("cloud.request", {});
  const old = workers.last;
  old.reply({ fatal: "unreachable" });
  await assert.rejects(pending, (error: unknown) => error instanceof CoreError && error.code === "core_restarted");
  assert.equal(old.closed, true);
  assert.equal(workers.opened.length, 2);
  assert.deepEqual(workers.last.sent, [{ id: 1, subscribe: { topic: "accounts" } }]);
  // The old worker's late words are not the new one's.
  old.reply({ id: 1, value: "stale" });
  workers.last.reply({ id: 1, value: ["a"] });
  assert.deepEqual(values, [["a"]]);
  // Calls get fresh ids.
  void client.call("x");
  assert.deepEqual(workers.last.sent.at(-1), { id: 4, call: "x", params: {} });
});

test("a worker that keeps failing is retried with growing pauses, reset by a healthy answer", () => {
  const workers = new FakeWorkers();
  workers.client();
  workers.last.fail("load");
  workers.last.fail("load");
  workers.last.reply({ fatal: "panic" });
  assert.deepEqual(workers.delays, [0, 1000, 2000]);
  workers.last.reply({ id: 99, ok: null });
  workers.last.fail("again");
  assert.deepEqual(workers.delays, [0, 1000, 2000, 0]);
});

test("calls made while the worker is being replaced are sent once it is up", () => {
  const workers = new FakeWorkers();
  let later: (() => void) | null = null;
  const client = new CoreClient(workers.opener, { schedule: (_ms, run) => { later = run; } });
  workers.last.fail("gone");
  void client.call("auth.begin", { redirect_uri: "r" });
  client.subscribe({ topic: "workspaces" }, () => undefined, () => undefined);
  assert.equal(workers.opened.length, 1);
  assert.ok(later);
  (later as () => void)();
  assert.deepEqual(workers.last.sent, [{ id: 2, subscribe: { topic: "workspaces" } }, { id: 1, call: "auth.begin", params: { redirect_uri: "r" } }]);
});

test("back from the back/forward cache: bye, then everything subscribed again", async () => {
  const workers = new FakeWorkers();
  const client = workers.client();
  client.subscribe({ topic: "session", station: "local", key: "k" }, () => undefined, () => undefined);
  const pending = client.call("station.file", {});
  client.suspend();
  client.resume();
  await assert.rejects(pending);
  assert.deepEqual(workers.last.sent.slice(2), [{ bye: true }, { id: 1, subscribe: { topic: "session", station: "local", key: "k" } }]);
});

test("localStorage is handed to the core once", async () => {
  const store = new Map<string, string>([["ember.accounts", JSON.stringify([{ sub: "s" }])], ["ember.device", "AAEC"]]);
  const storage = { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v) } as Storage;
  const calls: unknown[] = [];
  let failing = true;
  const client = { call: async (name: string, params?: unknown) => { calls.push([name, params]); if (failing) throw new Error("no"); return null; } };
  const quiet = console.error;
  console.error = () => undefined;
  await migrateLegacy(client, storage);
  console.error = quiet;
  failing = false;
  await migrateLegacy(client, storage);
  await migrateLegacy(client, storage);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1], ["migrate", { accounts: [{ sub: "s" }], device: "AAEC" }]);
  assert.ok(store.get("ember.core.migrated"));
});

test("deltas apply to the subscription's value, copying only along their paths", () => {
  const workers = new FakeWorkers();
  const client = workers.client();
  const seen: unknown[] = [];
  client.subscribe({ topic: "session", station: "w/s", key: "k" }, (v) => seen.push(v), (e) => seen.push(e.code));
  const first = { detail: { timeline: [{ text: "a" }], usage: { n: 1 } }, link: { state: "offline", message: "断了" }, other: { x: 1 } };
  // Before any value there is nothing to apply a delta to.
  workers.last.reply({ id: 1, delta: [{ path: ["other"], set: 2 }] });
  workers.last.reply({ id: 1, value: first });
  workers.last.reply({ id: 1, delta: [
    { path: ["detail", "timeline"], append: [{ text: "b" }] },
    { path: ["detail", "usage", "n"], set: 2 },
    { path: ["link", "state"], set: "online" },
    { path: ["link", "message"], remove: true },
  ] });
  workers.last.reply({ id: 1, delta: [{ path: ["detail", "timeline", 1, "text"], set: "bc" }] });
  assert.equal(seen.length, 3);
  const second = seen[1] as typeof first;
  const third = seen[2] as typeof first;
  assert.deepEqual(second, { detail: { timeline: [{ text: "a" }, { text: "b" }], usage: { n: 2 } }, link: { state: "online" }, other: { x: 1 } });
  assert.deepEqual(first.detail.timeline, [{ text: "a" }], "the old value is left as it was");
  assert.equal(second.other, first.other);
  assert.equal(second.detail.timeline[0], first.detail.timeline[0]);
  assert.deepEqual(third.detail.timeline[1], { text: "bc" });
  assert.equal(third.detail.timeline[0], first.detail.timeline[0]);
  assert.equal(third.link, second.link);
  // After an error, deltas wait for a whole value again.
  workers.last.reply({ id: 1, error: { code: "offline", message: "离线" } });
  workers.last.reply({ id: 1, delta: [{ path: ["other"], set: 3 }] });
  workers.last.reply({ id: 1, value: { fresh: true } });
  assert.deepEqual(seen.slice(3), ["offline", { fresh: true }]);
});
