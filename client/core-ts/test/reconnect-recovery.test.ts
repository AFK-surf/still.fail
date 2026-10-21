// Coming back on a weak link: streams that end as soon as they open wait longer each time, a station read afresh is
// taken up from its last event only once all of it was read, and the cloud's socket is tried again after a replacement
// that failed (link.ts, cursor.ts, sync/cloud.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import { RECONNECT_MAX_MS, RECONNECT_MS, STREAM_HELD_MS } from "../src/station/link.ts";
import { HostWire } from "../src/station/wire.ts";
import { Wake } from "../src/wake.ts";
import { run } from "./run.ts";
import { base, started, stationReplies, status } from "./station-fixture.ts";

const ST = "ws/st";

/// Ends the stream open now, and finds when the next one opens: after `wait` and not before.
async function opensAfter(s: Awaited<ReturnType<typeof started>>, wait: number): Promise<void> {
  const n = s.streams.length;
  s.end();
  await s.host.time.pass(wait - 50, 50);
  assert.equal(s.streams.length, n, `not before ${wait} ms`);
  await s.host.time.pass(100, 50);
  assert.equal(s.streams.length, n + 1, `after ${wait} ms`);
}

test("streams_that_end_as_they_open_wait_longer_each_time_and_one_held_waits_as_before", async () => {
  const s = await started();
  try {
    for (const wait of [2000, 4000, 8000, 16000, 32000, RECONNECT_MAX_MS, RECONNECT_MAX_MS]) await opensAfter(s, wait);
    // One that held past the station's keepalive shows the link holds a stream: those after it wait as the first again.
    await s.host.time.pass(STREAM_HELD_MS, 1000);
    await opensAfter(s, RECONNECT_MS);
    await opensAfter(s, RECONNECT_MS);
    await opensAfter(s, 2 * RECONNECT_MS);
  } finally {
    s.core.close();
  }
});

test("streams_that_hold_a_while_on_a_weak_link_are_opened_again_at_once_each_time", async () => {
  const s = await started();
  try {
    // Each brought what the station told, and went some half a minute later: never more than RECONNECT_MS between.
    for (let i = 0; i < 6; i++) {
      s.push("overview", {});
      await s.host.time.pass(STREAM_HELD_MS + 5000, 1000);
      await opensAfter(s, RECONNECT_MS);
    }
  } finally {
    s.core.close();
  }
});

test("the_ui_coming_back_opens_a_stream_at_once_and_it_waits_as_the_first_again", async () => {
  const s = await started();
  try {
    for (const wait of [2000, 4000, 8000, 16000]) await opensAfter(s, wait);
    const n = s.streams.length;
    s.end();
    await s.host.time.pass(1000, 50);
    assert.equal(s.streams.length, n);
    s.core.inner.wakes.wake(new Wake(s.host.nowMs(), 31_000, false, false));
    await s.host.time.pass(100, 50);
    assert.equal(s.streams.length, n + 1, "at once");
    await opensAfter(s, RECONNECT_MS);
  } finally {
    s.core.close();
  }
});

test("a_core_started_again_while_its_station_was_read_afresh_reads_it_again", async () => {
  const answers = base();
  const s = await started(answers);
  let again: Core | undefined;
  try {
    // Read afresh, the chats not yet answered, as the stream tells on: where it is is not written down meanwhile.
    answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "UPDATED", agents: [], lastActiveAt: 2 }];
    const release = s.host.hold("/admin/api/changed/chats");
    s.core.inner.stations.snapshot(ST);
    await s.host.settle();
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.50\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), undefined);
    // The app's process let go before the chats came.
    s.core.close();
    await s.host.settle();
    release();
    s.gate.resumes = true;
    again = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
    await s.host.time.pass(1000, 50);
    assert.ok(!s.streams.at(-1)!.path.includes("since="), s.streams.at(-1)!.path);
    const rows = again.inner.data.get({ topic: "chatRows", station: ST }) as { title: string }[];
    assert.equal(rows[0].title, "UPDATED");
    // All of it read, where it is is written down with what came after.
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.51\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(again.inner.data.written);
    assert.equal(again.inner.data.record("heard", ST), "abcdef.51");
  } finally {
    again?.close();
    s.core.close();
  }
});

test("a_station_read_afresh_that_could_not_be_read_whole_is_not_taken_up_from_its_last_event", async () => {
  const s = await started();
  try {
    // The chats not answered (the station failing as they were asked): nothing is written down, though the stream tells on.
    let down = true;
    stationReplies(s.host, (req) => (down && /\/admin\/api\/(changed\/)?chats$/.test(req.url) ? status(503, { error: "down" }) : undefined));
    s.core.inner.stations.snapshot(ST);
    await s.host.time.pass(1000, 50);
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.60\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), undefined);
    // Read whole the next time: written down.
    down = false;
    s.core.inner.stations.snapshot(ST);
    await s.host.time.pass(1000, 50);
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), "abcdef.60");
  } finally {
    s.core.close();
  }
});

test("a_failed_cloud_replacement_lets_the_next_wake_reconnect", async () => {
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
