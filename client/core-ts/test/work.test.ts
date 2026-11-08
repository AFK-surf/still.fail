// What a change costs must follow what changed, not how much is held or shown (work.ts): the same change made with
// twice the data, or twice the chat shown, is counted the same. Counted, never timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { work, workSince } from "../src/work.ts";
import { call, subscribe } from "./helpers.ts";
import { base, started, threadView } from "./station-fixture.ts";

const ST = "ws/st";
/// A chat's entry `n`: the agent's a few lines of Markdown, the person's one.
const said = (n: number) =>
  n % 2 === 0
    ? { thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "agent", author: "k1", declared: "final", text: `## 第 ${n} 步\n\n改了 \`a.ts\`，**测试**都过了：\n\n- 一\n- 二`, at: n }
    : { thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "person", author: "a@x.com", text: `第 ${n} 条：再看一下`, at: n };
const run = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => said(from + i));

/// A chat of `n` entries shown (its latest page, `back` pages before it brought into view) while 10 new messages come.
async function arriving(n: number, back: number) {
  const answers: Record<string, unknown> = { ...base(), "GET /threads": [threadView(7, n)], "GET /threads/7/entries?limit=50": { last: n, entries: run(n - 49, n) } };
  for (let to = n - 50; to >= 1; to -= 50) answers[`GET /threads/7/entries?from=${Math.max(1, to - 49)}&to=${to}`] = { last: n, entries: run(Math.max(1, to - 49), to) };
  const { host, core, push } = await started(answers);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: ST, session: "k1" });
  await host.time.pass(1_000, 50);
  for (let i = 0; i < back; i++) {
    call(core, ui, 10 + i, "chat.older", { station: ST, thread: 7 });
    await host.time.pass(500, 50);
  }
  const shown = (core.inner.store.get({ topic: "chat", station: ST, session: "k1" }) as { messages: unknown[] }).messages.length;
  const from = { ...work };
  for (let k = 1; k <= 10; k++) {
    push("thread", { id: 7, entries: [said(n + k)] });
    await host.time.pass(200, 50);
  }
  const counted = workSince(from);
  core.close();
  return { shown, counted };
}

test("a_new_message_costs_the_same_in_a_chat_of_2000_entries_as_in_one_of_1000", async () => {
  const small = await arriving(1000, 0);
  assert.ok(small.counted.shaped > 0, "what came went out");
  const large = await arriving(2000, 0);
  assert.deepEqual(large.counted, small.counted, JSON.stringify({ large: large.counted, small: small.counted }));
});

test("a_new_message_costs_the_same_with_150_messages_shown_as_with_50", async () => {
  const fifty = await arriving(1000, 0);
  const more = await arriving(1000, 2);
  assert.ok(more.shown > fifty.shown, `more shown: ${more.shown} > ${fifty.shown}`);
  assert.deepEqual(more.counted, fifty.counted, JSON.stringify({ more: more.counted, fifty: fifty.counted }));
});
