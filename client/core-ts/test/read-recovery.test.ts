import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import { EVENTS_COALESCE_MS } from "../src/station/sync.ts";
import { HostWire } from "../src/station/wire.ts";
import { base, started, stationLater, threadView } from "./station-fixture.ts";
import { call, subscribe } from "./helpers.ts";

const station = "ws/st";
const unread = (core: Core) => (core.inner.data.chat(station, "k1") as { unread: boolean }).unread;
const puts = (urls: { method: string; url: string }[], thread = 7) => urls.filter((r) => r.method === "PUT" && r.url.endsWith(`/threads/${thread}/read`)).length;

function answers() {
  const marks = { card: {}, need: {}, answered: {}, suggested: [], verdicts: {}, reviews: false, kept: [], hidden: [], muted: [], pins: {}, openers: {}, opened: {}, shares: {}, clientKeys: {}, teams: {}, selves: [], dismissed: [], reads: { 7: 2 } };
  const shared = {
    id: "k1", session: "k1", thread: 7, title: "", agents: [{ key: "k1", runtime: "claude" }],
    last: { seq: 3, authorKind: "agent", author: "k1", text: "New update", createdAt: 3 },
    unread: false, mine: false, lastActiveAt: 3, connect: null, origin: null, creator: null, people: [],
    ws: null, named: { thread: { surface: "ember", title: null, autoTitle: "Chat" }, firstText: null, channelName: null },
    mineOf: [{ id: "a@x.com", email: "a@x.com", via: "cloud" }],
    said: { n: 3, authorKind: "agent", author: "k1", other: 3 }, pinned: null,
  };
  return { ...base(), "GET /chats?marks=1": marks, "GET /threads": [threadView(7, 3, 2, 1)], "GET /chats?shared=1": [shared], "GET /chats": [], "PUT /threads/7/read": { n: 3 } };
}

test("an explicit read repairs a stale cached position and leaves unrelated reads alone", async () => {
  const { host, core, push } = await started(answers());
  try {
    push("made", { rows: true, marks: true, shared: true });
    await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
    assert.equal(unread(core), true);
    // The cached thread is ahead of the station's unread mark, as after an interrupted optimistic read.
    core.inner.data.putThread(station, threadView(7, 3, 3, 0));
    await Effect.runPromise(core.inner.stations.read(station, 7, 2, null));
    assert.equal(puts(host.requests), 0, "a read already confirmed by the station is not repeated");
    assert.equal(unread(core), true, "reading only up to 2 leaves message 3 unread");
    await Effect.runPromise(core.inner.stations.read(station, 7, 3, null));
    await host.settle();
    assert.equal(puts(host.requests), 1, "an explicit read reaches the station when its unread mark disagrees");
    assert.equal(unread(core), false);
    await Effect.runPromise(core.inner.stations.read(station, 7, 3, null));
    assert.equal(puts(host.requests), 1, "the confirmed read is not repeated");
    // A chat absent from the shared list (for example an archived one) has no mark in that list to compare with.
    core.inner.data.putThread(station, threadView(99, 3, 3, 0));
    await Effect.runPromise(core.inner.stations.read(station, 99, 3, null));
    assert.equal(puts(host.requests, 99), 0);
  } finally {
    core.close();
  }
});

test("after an interrupted read and restart, showing the chat retries the read", async () => {
  const s = await started(answers(), 0, undefined, (st) => { st.gate.shared = true; st.gate.marks = true; st.gate.resumes = true; });
  const { host, core } = s;
  let next: Core | undefined;
  try {
    await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
    assert.equal(unread(core), true);
    stationLater(host, (req) => req.method === "PUT" && req.url.endsWith("/threads/7/read") ? Promise.reject(new HostError("disconnected")) : undefined);
    const failed = await Effect.runPromise(Effect.result(core.inner.stations.read(station, 7, 3, null)));
    assert.equal(failed._tag, "Failure");
    assert.equal(core.inner.data.readPosition(station, 7), 3);
    await Effect.runPromise(core.inner.data.written);
    core.close();
    stationLater(host, () => undefined);
    next = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
    await host.time.pass(500);
    await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
    assert.equal(unread(next), true);
    assert.equal(next.inner.data.readPosition(station, 7), 3);
    const ui = next.connect();
    subscribe(next, ui, 1, { topic: "chat", station, thread: 7 });
    call(next, ui, 2, "client.focus", { visible: true, focused: true, chat: { station, thread: 7, end: true } });
    await host.time.pass(EVENTS_COALESCE_MS + 100, 50);
    assert.equal(puts(host.requests), 2, "showing the chat retries the read after the interrupted attempt");
    assert.equal(unread(next), false);
  } finally {
    next?.close();
    core.close();
  }
});
