import assert from "node:assert/strict";
import { test } from "node:test";
import { specOf, type Spec } from "../src/collections.ts";
import { markdown } from "../src/markdown.ts";
import { Output } from "../src/output.ts";
import * as present from "../src/present.ts";
import { deepFreeze, isObject, shaped } from "../src/util.ts";
import { walked, work } from "../src/work.ts";

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

// (an agent's turns and threads go out to neither: its shape, ChatAgent, has them not, views.test.ts)
test("a_compact_chat_sends_its_page_without_the_agents_jobs", () => {
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
  assert.deepEqual(compact.ok.agents[0]!.jobs, []);
  assert.equal(compact.ok.agents[0]!.hasJobs, true);
  assert.equal(raw.agents[0]!.jobs.length, 1, "the full value stays available to other readers");
});

test("a_new_minute_makes_again_only_the_items_whose_times_it_may_say_otherwise", () => {
  // Each minute every chat of a list of 1400 was decorated and shaped again, those from weeks ago too, to send nothing
  // (2026-11-08): one a day or more past says its day until local midnight. (The list says no times now, ListedChat: a
  // search's chats do.)
  const now = Date.UTC(2026, 10, 8, 4, 30, 10);
  const topic = { topic: "search", scope: "w", query: "" };
  const row = (id: string, at: number) => Object.freeze({ id, station: "w/s", lastActiveAt: at });
  const old = row("old", now - 3 * 86_400_000);
  const recent = row("recent", now - 2 * 60_000);
  const value = { items: [old, recent] };
  const out = new Output();
  const items = (c: { now: number; offsetMin: number }) =>
    (out.shape(topic, value, c, false) as { ok: { items: { id: string; time: { lastActiveAt: { ago: string } } }[] } }).ok.items;
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

test("a_value_given_again_as_the_same_object_goes_out_as_it_went_until_what_it_read_moves_on", () => {
  // `profiles`, no keyed items, was copied, decorated and shaped whole each time it went out, the same value too: 5 ms
  // in Hermes each time (2026-11-11).
  const now = Date.UTC(2026, 10, 11, 4, 30, 10);
  const topic = { topic: "linkPreview", station: "w/s", url: "https://x" };
  const raw = Object.freeze({ kind: "github_pull_request", title: "PR", updatedAt: now - 2 * 60_000 });
  const out = new Output();
  const shape = (v: unknown, c: { now: number; offsetMin: number }) => out.shape(topic, v, c, true) as { ok: { time: { updatedAt: { ago: string } } } };
  const from = work.shapes;
  const first = shape(raw, { now, offsetMin: 480 });
  assert.equal(work.shapes - from, 1);
  const again = shape(raw, { now: now + 20_000, offsetMin: 480 });
  assert.equal(again, first, "the same value, in the same minute: what went out");
  assert.equal(again.ok, first.ok);
  assert.equal(work.shapes - from, 1, "nothing made again");
  // a minute on: its words move on (the clock's signal it read), made again
  const later = shape(raw, { now: now + 60_000, offsetMin: 480 });
  assert.equal(work.shapes - from, 2);
  assert.notEqual(later.ok, first.ok);
  assert.notEqual(later.ok.time.updatedAt.ago, first.ok.time.updatedAt.ago);
  assert.equal(shape(raw, { now: now + 70_000, offsetMin: 480 }), later);
  // another object, equal to it: made again
  const other = shape({ ...raw }, { now: now + 70_000, offsetMin: 480 });
  assert.equal(work.shapes - from, 3);
  assert.notEqual(other, later);
  assert.deepEqual(other.ok, later.ok);
  // given without its shape: made again
  out.shape(topic, { ...raw }, { now: now + 70_000, offsetMin: 480 }, false);
  assert.equal(work.shapes - from, 4);
  // let go of: made again
  const kept = { ...raw };
  out.shape(topic, kept, { now: now + 70_000, offsetMin: 480 }, true);
  out.stop();
  out.shape(topic, kept, { now: now + 70_000, offsetMin: 480 }, true);
  assert.equal(work.shapes - from, 6);
});

test("a_value_given_again_is_made_again_as_a_signal_its_making_read_moves_on_whatever_the_minute", () => {
  // (what its watch fired for: here the clock's minute moved on by another's clockAt, as the store's minute does)
  const now = Date.UTC(2026, 10, 11, 4, 30, 10);
  const topic = { topic: "filePeek", station: "w/s", path: "/a" };
  const raw = Object.freeze({ name: "a", mtime: now - 2 * 60_000 });
  let agains = 0;
  const out = new Output(() => agains++);
  const c = { now, offsetMin: 480 };
  const first = out.shape(topic, raw, c, false);
  present.clockAt({ now: now + 60_000, offsetMin: 480 });
  assert.equal(agains, 1, "told it is out of date");
  const from = work.shapes;
  // (given the old clock again: the minute is the same as it was made in, but what it read moved on)
  const again = out.shape(topic, raw, c, false);
  assert.equal(work.shapes - from, 1);
  assert.notEqual(again, first);
});

test("every_keyed_topics_items_are_decorated_as_they_are_never_written_and_never_marked_as_gone_out", () => {
  // Each item was deep-copied before it was decorated: 1.3 ms of the 52 items of a chat list's first page in Hermes
  // (2026-11-11). Decoration copies what it puts something in: an item given it frozen, as the store's are, goes out
  // as a copy decorated would, and is itself never marked as gone out (which another value holding it would take it as).
  const now = Date.UTC(2026, 10, 11, 4, 30, 10);
  const c = { now, offsetMin: 480 };
  // An item with what each of `times`'s ways puts in (times in words beside a time, a quota's windows, its resets and
  // credits, beside a `time` it already has), what `session` reads, and parts with nothing put in.
  const item = (spec: Spec, i: number): Record<string, unknown> => ({
    ...Object.fromEntries((spec.key ?? []).map((k) => [k, k === "outgoing" ? null : `${k}${i}`])),
    lastActiveAt: now - (i + 2) * 60_000,
    time: { updatedAt: { ago: "早先" } },
    last_seen: Math.floor(now / 1000) - 3600,
    process: "cold", pending: 0, runtime: "claude", model: "opus", title: `item ${i}`,
    lastTurn: { kind: "message", ending: "final", need: "合并了", outcome: "completed", startedAt: now - 600_000, endedAt: now - 500_000 },
    quota: {
      state: "ok", credits: { balance: "3.5" }, resetCount: 1, resetExpiries: [now + 86_400_000],
      resets: [{ kind: "weekly", left: 1, expiries: [now + 86_400_000] }],
      windows: [{ label: "5h", usedPercent: 40, resetsAt: now + 3_600_000 }], scoped: [{ label: "Fable", usedPercent: 10 }],
    },
    plain: { parts: [1, { b: 2 }], text: "无" },
  });
  // A value of the topic's keyed lists, each of two items, and one item with nothing in it to put.
  const valueOf = (spec: Spec, i = 0): unknown => {
    if (spec.key) return [0, 1].map((n) => (spec.item ? { ...item({ key: spec.key }, n), ...(valueOf(spec.item, n) as object) } : item(spec, i * 2 + n))).concat(spec.item ? [] : [Object.fromEntries(spec.key.map((k) => [k, `${k}-bare`]))]);
    return Object.fromEntries(Object.entries(spec.fields ?? {}).map(([f, s]) => [f, valueOf(s, i)]));
  };
  const leaves = (spec: Spec, v: unknown): unknown[] => {
    if (spec.key) return (v as unknown[]).flatMap((x) => (spec.item ? leaves(spec.item, x) : [x]));
    return Object.entries(spec.fields ?? {}).flatMap(([f, s]) => leaves(s, (v as Record<string, unknown>)[f]));
  };
  const topics = ["chats", "chatSearch", "search", "chat", "archive", "chatRows", "archivedRows", "threads", "sessions", "jobs", "history", "chatOutline", "changelog", "vaults", "vaultItems", "driveTransfers", "downloads", "jobLog", "stations", "newChat"];
  for (const name of topics) {
    const topic = { topic: name, station: "w/s", scope: "w" };
    const spec = specOf(topic)!;
    const raw = valueOf(spec);
    deepFreeze(raw);
    const out = new Output().shape(topic, raw, c, false) as { ok: unknown };
    assert.ok("ok" in out, name);
    // (a job's log is made anew of its items whole, jobs.ts `log`: its items decorated all the same, above)
    if (name === "jobLog") continue;
    const given = leaves(spec, raw);
    const sent = leaves(spec, out.ok);
    assert.equal(sent.length, given.length, name);
    for (const [i, x] of given.entries()) {
      assert.deepEqual(sent[i], present.decorateItem(topic, structuredClone(x), c), `${name}: as a copy decorated`);
      assert.notEqual(sent[i], x, `${name}: not the item itself`);
      assert.ok(!shaped.has(x as object), `${name}: the item not marked as gone out`);
      // (a part of it nothing is put in goes out as it is, not a copy: no shape here to make it anew)
      const part = (x as Record<string, unknown>).plain;
      if (part !== undefined && present.ticks(topic) && name !== "stations") assert.equal((sent[i] as Record<string, unknown>).plain, part, `${name}: a part with nothing put in, not copied`);
    }
    // (what the decoration puts in, where the topic says times in words: so it was put, not left out)
    if (present.ticks(topic) && name !== "stations") assert.ok(isObject((sent[0] as Record<string, unknown>).time) && "lastActiveAt" in ((sent[0] as Record<string, Record<string, unknown>>).time), name);
  }
});

test("an_item_the_very_object_it_was_goes_out_as_made_found_by_the_object_and_nothing_of_it_walked", () => {
  const now = Date.UTC(2026, 10, 12, 4, 30, 10);
  const c = { now, offsetMin: 480 };
  const topic = { topic: "chatRows", station: "w/s" };
  const rows = Array.from({ length: 90 }, (_, i) => Object.freeze({ id: `t${i}`, key: `t${i}`, title: `chat ${i}` }));
  const out = new Output();
  const shape = (v: unknown) => (out.shape(topic, v, c, false) as { ok: { id: string }[] }).ok;
  const first = shape(rows);
  // one changed in a new list: that one made, the others found by the object
  const from = { ...walked };
  const next = shape(rows.map((r, i) => (i === 40 ? Object.freeze({ ...r, title: "new" }) : r)));
  assert.equal(walked.built - from.built, 1);
  assert.equal(walked.same - from.same, 89 + 1, "the others, and the list as it goes out to copy");
  // (the others' making read nothing that can change: not read again, the one made and the list alone)
  assert.ok(walked.reads - from.reads <= 3, `reads ${walked.reads - from.reads}`);
  assert.equal(walked.copied - from.copied, 1, "the one made, copied as no shape makes it anew");
  assert.equal(next[0], first[0]);
  assert.notEqual(next[40], first[40]);
  assert.deepEqual(next, first.map((r, i) => (i === 40 ? { ...r, title: "new" } : r)));
  // the very list again in another value: the list as it went out, its items not looked at
  const value = { items: rows };
  const history = new Output();
  const h = (v: unknown) => (history.shape({ topic: "history", station: "w/s", key: "k" }, v, c, false) as { ok: { items: unknown[] } }).ok;
  const was = h(value);
  const again = { ...walked };
  assert.equal(h({ ...value, edge: "x" }).items, was.items);
  assert.equal(walked.built - again.built, 0);
  assert.ok(walked.same - again.same <= 3, `${walked.same - again.same}`);
});

test("an_item_holding_keyed_lists_the_very_object_it_was_goes_out_as_made_until_its_items_words_move_on", () => {
  const now = Date.UTC(2026, 10, 8, 4, 30, 10);
  const topic = { topic: "search", scope: "w", query: "" };
  const row = (key: string, at: number) => Object.freeze({ key, lastActiveAt: at });
  const recent = row("recent", now - 2 * 60_000);
  const old = row("old", now - 3 * 86_400_000);
  const group = Object.freeze({ kind: "chat", items: Object.freeze([recent, old]) });
  const other = Object.freeze({ kind: "file", items: Object.freeze([row("f", now - 5 * 86_400_000)]) });
  const out = new Output();
  type G = { kind: string; items: { key: string; time: { lastActiveAt: { ago: string } } }[] };
  const groups = (v: unknown, c: { now: number; offsetMin: number }) => (out.shape(topic, v, c, false) as { ok: { groups: G[] } }).ok.groups;
  const c = { now, offsetMin: 480 };
  const first = groups({ items: [], groups: [group, other] }, c);
  // the other group changed, this one the same object: as it went, nothing of it made
  const from = { ...walked };
  const shaped0 = work.shaped;
  const next = groups({ items: [], groups: [group, { ...other, items: [row("g", now - 5 * 86_400_000)] }] }, c);
  assert.equal(next[0], first[0]);
  assert.notEqual(next[1], first[1]);
  assert.equal(work.shaped - shaped0, 2, "the other group and its one item");
  assert.equal(walked.built - from.built, 2);
  // a minute on, the same value: the group made again for its recent item's words, its old one as it went
  const later = groups({ items: [], groups: [group, other] }, { now: now + 60_000, offsetMin: 480 });
  assert.notEqual(later[0], first[0]);
  assert.notEqual(later[0]!.items[0]!.time.lastActiveAt.ago, first[0]!.items[0]!.time.lastActiveAt.ago);
  assert.equal(later[0]!.items[1], first[0]!.items[1]);
  assert.equal(later[1]!.items[0]!.key, "f");
});

test("the_very_object_sent_by_two_topics_of_two_shapes_goes_out_in_each_ones_shape", () => {
  // (a chat's row in a search, ChatItem, and in the chat list, ListedChat: what a list's row carries, `mayShare` not)
  const c = { now: Date.UTC(2026, 10, 12, 4, 30, 10), offsetMin: 480 };
  const chat = (id: string) => Object.freeze({ id, session: `s-${id}`, title: id, agents: [], unread: false, station: "w/s", stationName: "S", mayShare: true });
  const r = chat("a");
  const search = new Output();
  const list = new Output();
  type Row = { id: string; mayShare?: boolean };
  const searched = (items: unknown[]) => {
    const out = search.shape({ topic: "chatSearch", scope: "w", query: "" }, { items, words: [], messages: [] }, c, true);
    assert.ok("ok" in out, JSON.stringify(out));
    return (out.ok as { items: Row[] }).items;
  };
  const listed = (items: unknown[]) => {
    const out = list.shape({ topic: "chats", scope: "w" }, { stations: [], days: [{ daysAgo: 0, label: "今天", items }] }, c, true);
    assert.ok("ok" in out, JSON.stringify(out));
    return (out.ok as { days: { items: Row[] }[] }).days[0]!.items;
  };
  for (let round = 0; round < 2; round++) {
    // (and again, the same row beside a new one: each as its own made it)
    const s = searched(round === 0 ? [r] : [chat("b"), r]);
    const l = listed(round === 0 ? [r] : [chat("b"), r]);
    const sr = s[s.length - 1]!;
    const lr = l[l.length - 1]!;
    assert.equal(sr.mayShare, true, "a search's row as ChatItem");
    assert.ok(!("mayShare" in lr), "the list's as ListedChat");
    assert.equal(sr.id, "a");
    assert.equal(lr.id, "a");
  }
});
