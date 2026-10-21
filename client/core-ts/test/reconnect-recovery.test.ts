import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import { HostWire } from "../src/station/wire.ts";
import { Wake } from "../src/wake.ts";
import { started, base } from "./station-fixture.ts";
import { run } from "./run.ts";

const ST = "ws/st";

test("short streams back off to a minute and a stable stream resets the wait", async () => {
  const s = await started();
  try {
    for (const wait of [2000, 4000, 8000, 16000, 32000, 60000, 60000]) {
      const n = s.streams.length;
      s.end();
      await s.host.time.pass(wait - 50, 50);
      assert.equal(s.streams.length, n, `must wait ${wait} ms`);
      await s.host.time.pass(100, 50);
      assert.equal(s.streams.length, n + 1);
    }
    // Keep the stream alive for a minute, without triggering its idle timeout.
    for (let i = 0; i < 4; i++) {
      s.push("overview", {});
      await s.host.time.pass(16000, 100);
    }
    const n = s.streams.length;
    s.end();
    await s.host.time.pass(2050, 50);
    assert.equal(s.streams.length, n + 1);
  } finally {
    s.core.close();
  }
});

test("restart repairs a snapshot interrupted after its cursor was saved", async () => {
  const answers = base();
  const s = await started(answers);
  let again: Core | undefined;
  try {
    answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "UPDATED", agents: [], lastActiveAt: 2 }];
    const release = s.host.hold("/admin/api/changed/chats");
    s.core.inner.stations.snapshot(ST);
    await s.host.settle();
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode('id: abcdef.50\nevent: overview\ndata: {}\n\n'));
    await s.host.settle();
    assert.equal(s.core.inner.data.record("heard", ST), "abcdef.50");
    await run(s.core.inner.data.written);
    s.core.close();
    await s.host.settle();
    release();
    s.gate.resumes = true;
    const before = s.host.requests.length;
    again = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
    await s.host.time.pass(1000, 50);
    assert.ok(s.streams.at(-1)!.path.includes("since=abcdef.50"));
    const rows = again.inner.data.get({ topic: "chatRows", station: ST }) as { title: string }[];
    assert.equal(rows[0].title, "UPDATED");
    assert.equal(s.host.requests.slice(before).filter((r) => /\/admin\/api\/(changed\/)?chats(?:\?|$)/.test(r.url)).length, 1);
  } finally {
    again?.close();
    s.core.close();
  }
});

test("a failed cloud replacement allows the next wake to reconnect", async () => {
  const s = await started();
  try {
    const original = s.host.websocket.bind(s.host);
    let attempts = 0;
    let fail = true;
    s.host.websocket = (url, protocols) => {
      attempts++;
      return fail ? Effect.fail(new HostError("temporary outage")) : original(url, protocols);
    };
    const wake = () => s.core.inner.wakes.wake(new Wake(s.host.nowMs(), 31000, false, false));
    wake();
    await s.host.settle();
    assert.equal(attempts, 1);
    fail = false;
    wake();
    await s.host.settle();
    assert.equal(attempts, 2);
    assert.equal(s.host.openSockets("/v1/events"), 1);
    await s.host.time.pass(61000, 1000);
    assert.equal(attempts, 3, "the first heartbeat also has a deadline");
  } finally {
    s.core.close();
  }
});
