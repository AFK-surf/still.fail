import assert from "node:assert/strict";
import { test } from "node:test";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { USAGE_MS, UseCounts, type UsageSink } from "../src/use-counts.ts";

const SINK: UsageSink = { host: "https://posthog.test", key: "phc_test" };

function rig(o: { origin?: string; sink?: UsageSink | null; account?: string | null; status?: number } = {}) {
  const host = new FakeHost();
  host.origin = o.origin ?? "https://app.still.fail";
  const bodies: { api_key: string; batch: { event: string; distinct_id: string; properties: Record<string, unknown> }[] }[] = [];
  let status = o.status ?? 200;
  host.onFetch((request) => {
    assert.equal(request.url, "https://posthog.test/batch/");
    bodies.push(JSON.parse(new TextDecoder().decode(request.body!)));
    return { status, headers: [], body: new Uint8Array() };
  });
  const runner = new Runner(host.time.clock);
  let account = o.account === undefined ? "sub-1" : o.account;
  const usage = new UseCounts(host, runner, o.sink === undefined ? SINK : o.sink, () => account, () => ({ app: "desktop", os: "macos", build: "0.1.9300" }));
  return { host, usage, bodies, setStatus: (s: number) => (status = s), setAccount: (a: string | null) => (account = a) };
}

const counted = (body: { batch: { event: string; properties: Record<string, unknown> }[] }) =>
  Object.fromEntries(body.batch.map((e) => [`${e.event}:${e.properties.feature ?? e.properties.page}`, e.properties.count]));

test("counts each call and page by name and sends them together, as the account signed in", async () => {
  const { host, usage, bodies } = rig();
  usage.setOn(true);
  usage.used("chat.send");
  usage.used("chat.send");
  usage.used("chat.archive");
  usage.shown("Chat");
  usage.shown("Setting Usage");
  await host.time.pass(USAGE_MS - 1_000);
  assert.equal(bodies.length, 0, "what comes in a burst waits to go together");
  await host.time.pass(2_000);
  assert.equal(bodies.length, 1);
  assert.equal(bodies[0]!.api_key, "phc_test");
  assert.deepEqual(counted(bodies[0]!), { "feature_used:chat.send": 2, "feature_used:chat.archive": 1, "page_shown:Chat": 1, "page_shown:Setting Usage": 1 });
  const e = bodies[0]!.batch[0]!;
  assert.equal(e.distinct_id, "sub-1");
  assert.deepEqual({ app: e.properties.app, os: e.properties.os, v: e.properties.$app_version }, { app: "desktop", os: "macos", v: "0.1.9300" });
  await host.time.pass(USAGE_MS * 2);
  assert.equal(bodies.length, 1, "nothing counted, nothing sent");
});

test("only what the code names: a page's kind of letters and spaces, a call's name", async () => {
  const { host, usage, bodies } = rig();
  usage.setOn(true);
  usage.shown("Chat c-1234/abc");
  usage.shown("/Users/someone");
  usage.used("chat send with words");
  usage.used("prefs.set");
  await host.time.pass(USAGE_MS + 1_000);
  assert.deepEqual(counted(bodies[0]!), { "feature_used:prefs.set": 1 });
});

test("nothing is counted or sent while off, and turning it off drops what was counted", async () => {
  const { host, usage, bodies } = rig();
  usage.used("chat.send");
  await host.time.pass(USAGE_MS + 1_000);
  assert.equal(bodies.length, 0, "off until the app says on");
  usage.setOn(true);
  usage.used("chat.send");
  usage.setOn(false);
  await host.time.pass(USAGE_MS + 1_000);
  assert.equal(bodies.length, 0);
});

test("nothing from another product's cloud, nor from a build given no key", async () => {
  for (const o of [{ origin: "https://monoid.build" }, { origin: "http://localhost:8787" }, { sink: null }]) {
    const { host, usage, bodies } = rig(o);
    usage.setOn(true);
    usage.used("chat.send");
    await host.time.pass(USAGE_MS + 1_000);
    assert.equal(bodies.length, 0, JSON.stringify(o));
  }
});

test("counts that did not go out are sent again with what came since; none signed in, they wait", async () => {
  const { host, usage, bodies, setStatus, setAccount } = rig({ status: 503, account: null });
  usage.setOn(true);
  usage.used("chat.send");
  await host.time.pass(USAGE_MS + 1_000);
  assert.equal(bodies.length, 0, "no account yet");
  setAccount("sub-1");
  await host.time.pass(USAGE_MS + 1_000);
  assert.equal(bodies.length, 1);
  usage.used("chat.send");
  setStatus(200);
  await host.time.pass(USAGE_MS * 4);
  assert.equal(bodies.length, 2);
  assert.deepEqual(counted(bodies[1]!), { "feature_used:chat.send": 2 });
});
