import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ChainTail } from "../src/read/tail.ts";
import { LiveHub, type LiveMessage, type Locate } from "../src/sessions/live.ts";
import { settle, testClock } from "./hub-fakes.ts";

const line = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-09-26T00:00:00Z", message: { id, content: [{ type: "text", text }] } })}\n`;
const deferred = () => {
  let resolve!: (at: ReturnType<Locate>) => void;
  const promise = new Promise<ReturnType<Locate>>((done) => { resolve = done; });
  return { promise, resolve };
};

test("subscribers share a pending location and get the transcript before events and the turn ending", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-locate-lifecycle-")), path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1"));
  const hub = new LiveHub(() => { throw new Error("synchronous location"); });
  const pending = deferred();
  let calls = 0;
  hub.locateAsync = () => { calls++; return pending.promise; };
  const first: LiveMessage[] = [], second: LiveMessage[] = [];
  try {
    hub.subscribe("s", 0, null, (m) => first.push(m));
    hub.subscribe("s", 0, null, (m) => second.push(m));
    hub.event("s", { kind: "start", id: "x", step: "text" });
    appendFileSync(path, line("two", "m2"));
    hub.turnEnded("s");
    await settle(2);
    assert.equal(calls, 1);
    assert.deepEqual(first, []);
    pending.resolve({ runtime: "claude", paths: [path], current: true });
    await settle();
    await hub.idle();
    for (const got of [first, second]) {
      const timeline = got.find((m): m is Extract<LiveMessage, { type: "timeline" }> => m.type === "timeline")!;
      assert.deepEqual(timeline.entries.map((e) => e.text), ["one", "two"]);
      assert.ok(got.findIndex((m) => m.type === "timeline") < got.findIndex((m) => m.type === "clear"));
      assert.ok(got.findIndex((m) => m.type === "step") < got.findIndex((m) => m.type === "clear"));
    }
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("unsubscribing during location preserves handover state, while deleting a session discards it", async () => {
  const dir = mkdtempSync(join(tmpdir(), "live-locate-lifecycle-")), path = join(dir, "t.jsonl");
  writeFileSync(path, line("one", "m1"));
  const tail = new ChainTail("claude", [path], null, false);
  tail.read();
  const states = tail.snapshot();
  const hub = new LiveHub(() => { throw new Error("synchronous location"); });
  const requests: { signal: AbortSignal; pending: ReturnType<typeof deferred> }[] = [];
  hub.locateAsync = (_key, signal) => {
    const pending = deferred();
    requests.push({ signal, pending });
    return pending.promise; // Deliberately finish even if cancelled, as an already delivered response can.
  };
  let stateReads = 0;
  hub.history = { state: async () => { stateReads++; return null; }, page: async () => ({ start: 0, end: 0, entries: [] }) };
  try {
    const abandoned: LiveMessage[] = [];
    const first = hub.subscribe("s", 1, null, (m) => abandoned.push(m));
    await settle(2);
    hub.takeTails([{ key: "s", states }]);
    hub.unsubscribe("s", first);
    assert.equal(requests[0]!.signal.aborted, true);
    assert.deepEqual(hub.carriedTails(), [{ key: "s", states }]);
    const joined: LiveMessage[] = [];
    hub.subscribe("s", 1, null, (m) => joined.push(m));
    await settle(2);
    requests[0]!.pending.resolve({ runtime: "claude", paths: [path], current: true });
    requests[1]!.pending.resolve({ runtime: "claude", paths: [path], current: true });
    await settle();
    await hub.idle();
    assert.deepEqual(abandoned, []);
    assert.equal(stateReads, 0, "the next watch resumes the carried reading");
    assert.equal(joined[0]?.type, "timeline");
    hub.forget("s");
    assert.deepEqual(hub.carriedTails(), []);

    hub.subscribe("gone", 0, null, () => {});
    await settle(2);
    hub.takeTails([{ key: "gone", states }]);
    hub.forget("gone");
    assert.equal(requests[2]!.signal.aborted, true);
    requests[2]!.pending.resolve({ runtime: "claude", paths: [path], current: true });
    await settle();
    await hub.idle();
    assert.deepEqual(hub.carriedTails(), [], "a late answer cannot restore a deleted session's state");
  } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a newly written transcript is announced even when its location takes longer than the read timer", async () => {
  for (const withReader of [false, true]) {
    const dir = mkdtempSync(join(tmpdir(), "live-locate-lifecycle-")), path = join(dir, "t.jsonl");
    const time = testClock();
    const hub = new LiveHub(() => { throw new Error("synchronous location"); }, time.clock);
    const requests: ReturnType<typeof deferred>[] = [];
    hub.locateAsync = () => { const pending = deferred(); requests.push(pending); return pending.promise; };
    if (withReader) hub.history = { state: async () => null, page: async () => ({ start: 0, end: 0, entries: [] }) };
    const got: LiveMessage[] = [];
    try {
      hub.subscribe("s", 0, null, (m) => got.push(m));
      await settle(2);
      requests[0]!.resolve(null);
      await settle();
      assert.equal(got.some((m) => m.type === "timeline"), false);
      writeFileSync(path, line("one", "m1"));
      hub.event("s", { kind: "start", id: "x", step: "text" });
      hub.event("s", { kind: "end", id: "x" });
      await settle(2);
      assert.equal(requests.length, 2);
      await time.adjust(40);
      await settle();
      requests[1]!.resolve({ runtime: "claude", paths: [path], current: true });
      await settle();
      await hub.idle();
      await time.adjust(40);
      await settle();
      await hub.idle();
      const timeline = got.find((m): m is Extract<LiveMessage, { type: "timeline" }> => m.type === "timeline");
      assert.ok(timeline, `the new transcript is announced with reader=${withReader}`);
      assert.equal(timeline.start, 1);
    } finally { hub.close(); rmSync(dir, { recursive: true, force: true }); }
  }
});
