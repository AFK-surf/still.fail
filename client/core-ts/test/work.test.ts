// What a change costs must follow what changed, not how much is held or shown (work.ts): the same change made with
// twice the data, or twice the chat shown, is counted the same. Counted, never timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { work, workSince } from "../src/work.ts";
import { call, subscribe } from "./helpers.ts";
import { base, entry, session, started, threadView } from "./station-fixture.ts";

const ST = "ws/st";
/// A chat's entry `n`: the agent's a few lines of Markdown, the person's one.
const said = (n: number) =>
  n % 2 === 0
    ? { thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "agent", author: "k1", declared: "final", text: `## 第 ${n} 步\n\n改了 \`a.ts\`，**测试**都过了：\n\n- 一\n- 二`, at: n }
    : { thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "person", author: "a@x.com", text: `第 ${n} 条：再看一下`, at: n };
const run = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => said(from + i));

/// A chat of `n` entries shown (its latest page, `back` pages before it brought into view) while 10 new messages come;
/// and what opening it took.
async function arriving(n: number, back: number) {
  const answers: Record<string, unknown> = { ...base(), "GET /threads": [threadView(7, n)], "GET /threads/7/entries?limit=50": { last: n, entries: run(n - 49, n) } };
  for (let to = n - 50; to >= 1; to -= 50) answers[`GET /threads/7/entries?from=${Math.max(1, to - 49)}&to=${to}`] = { last: n, entries: run(Math.max(1, to - 49), to) };
  const { host, core, push } = await started(answers);
  const ui = core.connect();
  // (every entry on the device before it is opened, as a chat read before is)
  for (let from = 1; from <= n; from += 500) push("thread", { id: 7, entries: run(from, Math.min(n, from + 499)) });
  await host.time.pass(1_000, 50);
  const opening = { ...work };
  subscribe(core, ui, 1, { topic: "chat", station: ST, session: "k1", compact: true });
  await host.time.pass(1_000, 50);
  const opened = workSince(opening);
  for (let i = 0; i < back; i++) {
    call(core, ui, 10 + i, "chat.older", { station: ST, thread: 7 });
    await host.time.pass(500, 50);
  }
  const shown = (core.inner.store.get({ topic: "chat", station: ST, session: "k1", compact: true }) as { messages: unknown[] }).messages.length;
  const from = { ...work };
  for (let k = 1; k <= 10; k++) {
    push("thread", { id: 7, entries: [said(n + k)] });
    await host.time.pass(200, 50);
  }
  const counted = workSince(from);
  core.close();
  return { shown, counted, opened };
}

test("a_new_message_costs_the_same_in_a_chat_of_2000_entries_as_in_one_of_1000", async () => {
  const small = await arriving(1000, 0);
  assert.ok(small.counted.shaped > 0, "what came went out");
  const large = await arriving(2000, 0);
  assert.deepEqual(large.counted, small.counted, JSON.stringify({ large: large.counted, small: small.counted }));
});

test("opening_a_chat_of_2000_entries_costs_what_opening_one_of_1000_does", async () => {
  const small = await arriving(1000, 0);
  assert.ok(small.opened.shaped > 0, "it went out");
  const large = await arriving(2000, 0);
  assert.deepEqual(large.opened, small.opened, JSON.stringify({ large: large.opened, small: small.opened }));
});

test("a_new_message_costs_the_same_with_150_messages_shown_as_with_50", async () => {
  const fifty = await arriving(1000, 0);
  const more = await arriving(1000, 2);
  assert.ok(more.shown > fifty.shown, `more shown: ${more.shown} > ${fifty.shown}`);
  assert.deepEqual(more.counted, fifty.counted, JSON.stringify({ more: more.counted, fifty: fifty.counted }));
});

/// Home's list (its first 50 chats) on a station of `n` chats while one of them moves to the top 10 times, as its station
/// tells each new message in it: the sidebar made here of the summaries held and the station's marks (rows-made.ts).
async function homeChanging(n: number) {
  const marks = { card: {}, need: {}, answered: {}, suggested: [], verdicts: {}, reviews: false, kept: [], hidden: [], pins: {}, openers: {}, opened: {}, shares: {}, clientKeys: {}, teams: {}, selves: [] };
  const sessions = Array.from({ length: n }, (_, i) => ({ ...session(`k${i}`), lastActiveAt: 1_000_000 - i * 1000 }));
  const threads = Array.from({ length: n }, (_, i) => ({ ...threadView(i, 1), sessions: [{ thread: i, session: `k${i}`, connect: "ember", joinedAt: 1 }], lastMessage: { ...threadView(i, 1).lastMessage, createdAt: 1_000_000 - i * 1000 } }));
  const answers: Record<string, unknown> = { ...base(), "GET /sessions": sessions, "GET /threads": threads, "GET /chats?marks=1": marks, "GET /chats": [] };
  const { host, core, push } = await started(answers);
  push("made", { rows: true, marks: true });
  const ui = core.connect();
  // (its window said first, as the app says it: chats.window)
  call(core, ui, 2, "chats.window", { scope: "ws", rows: 50 });
  subscribe(core, ui, 1, { topic: "chats", scope: "ws", mine: false });
  await host.time.pass(1_000, 50);
  const from = { ...work };
  for (let k = 1; k <= 10; k++) {
    const id = 100 + k * 7;
    push("thread", { id, entries: [{ ...entry(2, "新的"), thread: id, authorKind: "agent", author: `k${id}`, at: 2_000_000 + k * 1000 }] });
    await host.time.pass(200, 50);
  }
  const counted = workSince(from);
  const shown = core.inner.store.get({ topic: "chats", scope: "ws", mine: false }) as { days: { items: { thread: number }[] }[] };
  core.close();
  return { counted, top: shown.days.flatMap((d) => d.items).slice(0, 3).map((r) => r.thread) };
}

test("a_chat_moving_to_the_top_of_a_list_of_600_costs_what_it_costs_in_one_of_300", async () => {
  const small = await homeChanging(300);
  assert.ok(small.counted.listed > 0, "the list was made");
  assert.deepEqual(small.top, [170, 163, 156], "the chats that changed last on top");
  const large = await homeChanging(600);
  assert.deepEqual(large.counted, small.counted, JSON.stringify({ large: large.counted, small: small.counted }));
});
