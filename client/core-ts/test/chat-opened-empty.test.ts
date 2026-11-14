import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, subscribe, v } from "./helpers.ts";
import { base, entries, started, threadView } from "./station-fixture.ts";

// A chat open while it had nothing in it, its messages then said while the device did not hear them, the latest one
// told: it shows what is held and that there is more before it, never that it is empty.
test("a_chat_opened_empty_shows_what_came_after_though_its_first_entries_are_not_held", async () => {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 3), threadView(8, 0)];
  answers["GET /threads/8/entries?limit=50"] = { last: 0, entries: [] };
  const s = await started(answers);
  try {
    const ui = s.core.connect();
    const values = new Map();
    subscribe(s.core, ui, 1, { topic: "thread", station: "ws/st", thread: 8 });
    subscribe(s.core, ui, 2, { topic: "chat", station: "ws/st", thread: 8, session: null });
    await s.host.time.pass(100, 10);
    apply(s.host, values);
    assert.deepEqual(v(values, 2)?.messages, [], "empty as it opens");
    answers["GET /threads/8"] = threadView(8, 3);
    s.push("thread", { id: 8, entries: [{ ...entries(3, 3)[0], thread: 8 }] });
    await s.host.time.pass(3_000, 50);
    apply(s.host, values);
    assert.deepEqual(s.core.inner.data.logSpan("entry", "ws/st", "8"), { min: 3, max: 3, count: 1 }, "entries 1 and 2 not on the device");
    assert.deepEqual(v(values, 1)?.entries.map((e: { n: number }) => e.n), [3]);
    assert.deepEqual(v(values, 2)?.messages.map((m: { seq: number }) => m.seq), [3]);
    assert.equal(v(values, 2)?.more, true, "the page before is there to read");
  } finally { s.core.close(); }
});
