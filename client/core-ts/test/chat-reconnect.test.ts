import assert from "node:assert/strict";
import { test } from "node:test";
import { HostError } from "../src/error.ts";
import { jsonResponse } from "../src/testing.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { base, entries, started, stationLater, threadView } from "./station-fixture.ts";

async function interruptedFirstPage(failBeforeResume: boolean, batched = false) {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 3), threadView(8, 3)];
  answers["GET /threads/8/entries?limit=50"] = { last: 3, entries: entries(1, 3).map((e) => ({ ...e, thread: 8 })) };
  const held: (() => void)[] = [];
  let state: "held" | "down" | "up" = "held";
  const s = await started(answers, 0, undefined, (fixture) => {
    fixture.batches.on = batched;
    fixture.gate.marks = true;
    fixture.gate.resumes = true;
    stationLater(fixture.host, (req) => {
      const includesChat = req.url.includes("/threads/8/entries") || (req.url.endsWith("/batch") && new TextDecoder().decode(req.body ?? new Uint8Array()).includes("/threads/8/entries"));
      if (!includesChat) return undefined;
      if (state === "down") return Promise.reject(new HostError("connection lost"));
      if (state === "up") return undefined;
      return new Promise((_resolve, reject) => held.push(() => reject(new HostError("connection lost"))));
    });
  });
  try {
    const ui = s.core.connect();
    const values = new Map();
    subscribe(s.core, ui, 1, { topic: "thread", station: "ws/st", thread: 8 });
    subscribe(s.core, ui, 2, { topic: "chat", station: "ws/st", thread: 8, session: null });
    await s.host.time.pass(100, 10);
    assert.ok(held.length > 0, "the first page is still on its way");
    // Its request and stream are lost while the UI is away. Nothing of this chat has arrived yet.
    if (failBeforeResume) {
      state = "down";
      for (const fail of held.splice(0)) fail();
      await s.host.time.pass(100, 10);
    }
    assert.equal(s.core.inner.data.logSpan("entry", "ws/st", "8"), null);
    state = "up";
    s.end();
    await s.host.time.pass(3_000, 50);
    assert.ok(s.streams.at(-1)?.path.includes("since="), "the stream resumed");
    if (!failBeforeResume) {
      for (const fail of held.splice(0)) fail();
      await s.host.time.pass(100, 10);
    }
    apply(s.host, values);
    assert.deepEqual(v(values, 1)?.entries.map((e: { n: number }) => e.n), [1, 2, 3]);
    assert.deepEqual(v(values, 2)?.messages.map((m: { seq: number }) => m.seq), [1, 2, 3]);
  } finally { s.core.close(); }
}

test("a_chat_whose_first_read_failed_before_the_stream_resumed_recovers", () => interruptedFirstPage(true));
test("a_chat_whose_first_read_failed_after_the_stream_resumed_recovers", () => interruptedFirstPage(false));
test("a_chat_whose_first_read_failed_before_the_stream_resumed_recovers_with_batches", () => interruptedFirstPage(true, true));
test("a_chat_whose_first_read_failed_after_the_stream_resumed_recovers_with_batches", () => interruptedFirstPage(false, true));

test("a_chat_waiting_for_its_unread_position_recovers_after_the_stream_resumes", async () => {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 200, 20, 180)];
  answers["GET /threads/7/entries?limit=50"] = { last: 200, entries: entries(151, 200) };
  let down = true;
  const s = await started(answers, 0, undefined, (fixture) => {
    fixture.batches.on = false;
    fixture.gate.marks = true;
    fixture.gate.resumes = true;
    stationLater(fixture.host, (req) => {
      if (!req.url.includes("/threads/7/entries?")) return undefined;
      const q = new URL(req.url).searchParams;
      if (q.has("from")) {
        if (down) return Promise.reject(new HostError("connection lost"));
        const from = Number(q.get("from"));
        const to = Number(q.get("to"));
        return Promise.resolve(jsonResponse(200, { last: 200, entries: entries(from, to) }));
      }
      if (q.has("after")) return Promise.resolve(jsonResponse(200, { last: 200, entries: [] }));
      return undefined;
    });
  });
  try {
    assert.equal(s.core.inner.data.logSpan("entry", "ws/st", "7")?.min, 151);
    const ui = s.core.connect();
    const values = new Map();
    subscribe(s.core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
    subscribe(s.core, ui, 2, { topic: "chat", station: "ws/st", thread: 7, session: null });
    await s.host.time.pass(100, 10);
    apply(s.host, values);
    assert.equal(v(values, 1), undefined, "the unread position is not here yet");
    down = false;
    s.end();
    await s.host.time.pass(3_000, 50);
    assert.ok(s.streams.at(-1)?.path.includes("since="), "the stream resumed");
    apply(s.host, values);
    assert.equal(v(values, 1)?.at, 21);
    assert.ok(v(values, 1)?.entries.some((e: { n: number }) => e.n === 21));
    assert.ok(v(values, 2)?.messages.some((m: { seq: number }) => m.seq === 21));
  } finally { s.core.close(); }
});
