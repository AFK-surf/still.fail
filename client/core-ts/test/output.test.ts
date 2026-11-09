import assert from "node:assert/strict";
import { test } from "node:test";
import { markdown } from "../src/markdown.ts";
import { Output } from "../src/output.ts";

test("output_an_agents_markdown_goes_out_as_the_tree_kept_for_its_words_not_copied_again", () => {
  // A chat's page of agents' replies is mostly their trees: copied, put through the shape and cloned to keep for the
  // next change, each time it went out, they were most of what the core did to open a chat (2026-10-31).
  const md = markdown("一段 **粗** 和 `code`\n\n- 一\n- 二");
  const message = { seq: 1, outgoing: null, authorKind: "agent", text: "…", md };
  const out = new Output();
  const topic = { topic: "chat", station: "w/s", thread: 1, session: null };
  const clock = { now: Date.UTC(2026, 9, 31, 12), offsetMin: 480 };
  const first = out.shape(topic, { messages: [message], outbox: [] }, clock, false) as { ok: { messages: { md: unknown }[] } };
  assert.equal(first.ok.messages[0]!.md, md, "the tree itself");
  // and again, its message changed beside it (a reaction, an edit's time): the same tree
  const again = out.shape(topic, { messages: [{ ...message, text: "…!" }], outbox: [] }, clock, false) as { ok: { messages: { md: unknown }[] } };
  assert.equal(again.ok.messages[0]!.md, md);
});

test("a_compact_chat_sends_its_page_without_the_agents_unshown_histories", () => {
  const raw = {
    title: "Chat", messages: [], outbox: [],
    agents: [{ session: { key: "k" }, turns: [{ id: "t1" }], threads: [{ id: 1 }], jobs: [{ id: "j1", state: "exited", startedAt: 1 }] }],
  };
  const clock = { now: Date.UTC(2026, 9, 31, 12), offsetMin: 480 };
  const topic = { topic: "chat", station: "w/s", thread: 1, session: null };
  const full = new Output().shape(topic, raw, clock, false) as { ok: typeof raw };
  const compact = new Output().shape({ ...topic, compact: true }, raw, clock, false) as { ok: typeof raw & { agents: ({ hasJobs?: boolean } & typeof raw.agents[number])[] } };
  assert.equal(full.ok.agents[0]!.turns[0]!.id, "t1");
  assert.equal(full.ok.agents[0]!.jobs[0]!.id, "j1");
  assert.deepEqual(compact.ok.messages, full.ok.messages);
  assert.equal(compact.ok.agents[0]!.session.key, "k");
  assert.deepEqual([compact.ok.agents[0]!.turns, compact.ok.agents[0]!.threads, compact.ok.agents[0]!.jobs], [[], [], []]);
  assert.equal(compact.ok.agents[0]!.hasJobs, true);
  assert.equal(raw.agents[0]!.turns.length, 1, "the full value stays available to other readers");
});

test("a_new_minute_makes_again_only_the_items_whose_times_it_may_say_otherwise", () => {
  // Each minute every chat of a list of 1400 was decorated and shaped again, those from weeks ago too, to send nothing
  // (2026-11-08): one a day or more past says its day until local midnight.
  const now = Date.UTC(2026, 10, 8, 4, 30, 10);
  const topic = { topic: "chats", scope: "w" };
  const row = (id: string, at: number) => Object.freeze({ id, station: "w/s", lastActiveAt: at });
  const old = row("old", now - 3 * 86_400_000);
  const recent = row("recent", now - 2 * 60_000);
  const value = { days: [{ daysAgo: 0, items: [old, recent] }] };
  const out = new Output();
  const items = (c: { now: number; offsetMin: number }) =>
    (out.shape(topic, value, c, false) as { ok: { days: { items: { id: string; time: { lastActiveAt: { ago: string } } }[] }[] } }).ok.days[0]!.items;
  const first = items({ now, offsetMin: 480 });
  const next = items({ now: now + 60_000, offsetMin: 480 });
  assert.equal(next[0], first[0], "a chat of days ago: as it went out");
  assert.notEqual(next[1], first[1], "a chat of minutes ago: made again");
  assert.notEqual(next[1]!.time.lastActiveAt.ago, first[1]!.time.lastActiveAt.ago);
  // past local midnight (UTC+8: 16:00 UTC) its day is said otherwise: made again then
  const midnight = Date.UTC(2026, 10, 8, 16, 0, 0);
  assert.equal(items({ now: midnight - 60_000, offsetMin: 480 })[0], first[0]);
  assert.notEqual(items({ now: midnight + 1000, offsetMin: 480 })[0], first[0]);
  // another time zone: every time says it otherwise
  assert.notEqual(items({ now: midnight + 61_000, offsetMin: 0 })[0], items({ now: midnight + 62_000, offsetMin: 480 })[0]);
});
