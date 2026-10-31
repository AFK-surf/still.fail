// A core closing writes what the device's tables changed and were yet to write (#847): the core that follows on the
// same storage (node.ts `fatal` starts it in the same process) reads it; a write that fails is said, not dropped.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { Core } from "../src/core.ts";
import { DEVICE_TABLES } from "../src/data.ts";
import { HostError } from "../src/host.ts";
import { HostWire } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { answers, apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

const ST = "ws/st";
const ROOT = "/Users/a/Movies";

const again = (host: FakeHost) => Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });

/// The device's storage held: each write waits until `release`, as a slow disk's does.
function holdDevice(host: FakeHost) {
  const gate = Effect.runSync(Deferred.make<void>());
  const set = host.storageSet.bind(host);
  host.storageSet = (key, value) => (key.startsWith("device/") ? Effect.andThen(Deferred.await(gate), set(key, value)) : set(key, value));
  return { release: () => Effect.runSync(Deferred.succeed(gate, undefined)) };
}

test("where a file was left, put just before the core closes, is read by the core that follows", async () => {
  const { host, core } = await started();
  const held = holdDevice(host);
  const ui = core.connect();
  call(core, ui, 1, "drive.place", { station: ST, root: ROOT, path: "book.txt", at: 1200, of: 50000 });
  call(core, ui, 2, "prefs.set", { reader: { size: 30 } });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.ok(answers(emitted, 1) && "ok" in answers(emitted, 1)!, "drive.place answered");
  assert.ok(answers(emitted, 2) && "ok" in answers(emitted, 2)!, "prefs.set answered");
  assert.equal(host.storage.get("device/drive_place"), undefined, "not yet written");
  const closing = core.close();
  held.release();
  await closing;

  const next = await again(host);
  try {
    const ui2 = next.connect();
    subscribe(next, ui2, 1, { topic: "drivePlace", station: ST, root: ROOT, path: "book.txt" });
    subscribe(next, ui2, 2, { topic: "prefs" });
    await host.settle();
    const values = new Map();
    apply(host, values);
    assert.deepEqual([v(values, 1)?.at, v(values, 1)?.of], [1200, 50000]);
    assert.equal(v(values, 2).reader.size, 30);
  } finally {
    await next.close();
  }
});

test("each device table changed just before the core closes is written before it goes", async () => {
  const { host, core } = await started();
  const keyOf = { prefs: "device", changelog: "seen", choice: "station", chat_ref: "last", drive_place: `${ST}\n${ROOT}\nbook.txt`, verified: "a1" } as const;
  for (const table of DEVICE_TABLES) core.inner.data.put(table, keyOf[table], { table, n: 1 });
  // Closed at once: the writer has written none of them.
  await core.close();

  const next = await again(host);
  try {
    for (const table of DEVICE_TABLES) assert.deepEqual(next.inner.data.record(table, keyOf[table]), { table, n: 1 }, table);
  } finally {
    await next.close();
  }
});

test("a device table that cannot be written as the core closes is said, not dropped", async () => {
  const { host, core } = await started();
  const set = host.storageSet.bind(host);
  host.storageSet = (key, value) => (key === "device/choice" ? Effect.fail(new HostError("disk full")) : set(key, value));
  core.inner.data.put("choice", "station", "a");
  core.inner.data.put("prefs", "device", { n: 2 });
  await assert.rejects(core.close(), (e: unknown) => e instanceof HostError && /device\/choice: disk full/.test(e.message));
  // What could be written was.
  assert.ok(host.storage.get("device/prefs"));
});
