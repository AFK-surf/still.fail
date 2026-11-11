// A chat list's window (`chats.window`, views.ts Views `chatsWindow`): how many of its rows go out is no part of its
// topic, so a list scrolled to its foot is told a window more and sends the rows added, not itself whole again as
// another topic (`limit + 50` was one, 2026-11-11); its first screen reads and makes what it shows. Counted (work.ts),
// never timed.
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseCall } from "../src/core/calls.ts";
import { holdLanguage } from "../src/i18n.ts";
import { parseTopic, type Topic } from "../src/protocol.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { work, type Work } from "../src/work.ts";
import { link, rows, setup, workspace } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const NAMES = ["a", "b", "c", "d", "e"];
/// A list as the core takes it asked (protocol.ts parseTopic: `mine` said).
const list = (mine: boolean): Topic => parseTopic({ topic: "chats", scope: "ws", mine })!;
const ALL = list(false);
const MINE = list(true);

const session = (key: string): J => ({ key, connect: "c1", profile: "p1", runtime: "claude", model: "opus", effort: null, process: "cold", pending: 0, lastTurn: null });

/// A workspace of real size's list (test/real-size.ts's: 420 chats on 5 stations, 84 a station, an hour apart across
/// the stations, over 17 days; a few pinned, some at work, every other one the viewer's), its rows on the device and
/// none of them read yet, as a core started anew has them as it opens (views.ts #head reads the first of them alone).
async function opened() {
  const w = setup({ all: true });
  const now = w.host.nowMs();
  w.set(workspace(), { id: "ws", stations: NAMES.map((id) => ({ id, name: id, last_seen: null, version: null })) });
  for (const [st, name] of NAMES.entries()) {
    w.set(
      rows(`ws/${name}`),
      Array.from({ length: 84 }, (_, i) => {
        const id = `${name}${i}`;
        const at = now - (i * 5 + st) * 3_600_000;
        return {
          id, session: id, thread: null, title: `${id} 的标题`, agents: [{ ...session(id), ...(i % 7 === 0 ? { process: "running" } : {}) }], last: null, unread: false,
          mine: i % 2 === 0, lastActiveAt: Math.trunc(at), connect: null, origin: null, ...(i === 3 ? { pinned: 1000 + st } : {}),
        };
      }),
    );
  }
  // (written as its time passes; read by a core started anew on that database)
  await w.host.time.pass(100);
  const t = setup({ all: true, host: w.host });
  for (const name of NAMES) t.set(link(`ws/${name}`), { state: "online" });
  assert.ok(NAMES.every((name) => !t.data.loaded(rows(`ws/${name}`))));
  return t;
}
type Rig = Awaited<ReturnType<typeof opened>>;

/// What a keyed subscriber (the app) is sent, by subscription, and what the core's work had come to as each came.
function heard(t: Rig): { messages: Map<number, J[]>; workAt: Map<J, Work> } {
  const messages = new Map<number, J[]>();
  const workAt = new Map<J, Work>();
  const emit = t.host.emit.bind(t.host);
  t.host.emit = (client, message) => {
    emit(client, message);
    const m = t.host.emitted[t.host.emitted.length - 1]![1] as J;
    workAt.set(m, { ...work });
    messages.set(m.id, [...(messages.get(m.id) ?? []), m]);
  };
  return { messages, workAt };
}

/// The rows of a list's value, in order.
const rowsOf = (v: J): J[] => v.days.flatMap((d: J) => d.items);
/// What a message weighs as the host hands it over.
const bytes = (m: J) => new TextEncoder().encode(JSON.stringify(m)).length;
/// The list's value as the core holds it.
const valueOf = (t: Rig, list: Topic): J => (t.store.value(list) as J).ok;

/// What a list's first `n` rows were as `chats` asked with `limit: n` gave them (views.ts firstRows before the window):
/// its days holding those alone, how many more it has.
function firstOf(whole: J, n: number): J {
  let left = n;
  let more = 0;
  const days: J[] = [];
  for (const d of whole.days) {
    if (left <= 0) more += d.items.length;
    else if (d.items.length <= left) days.push(d);
    else {
      days.push({ ...d, items: d.items.slice(0, left) });
      more += d.items.length - left;
    }
    left -= Math.min(left, d.items.length);
  }
  return more === 0 ? whole : { ...whole, days, more };
}

test("chats.window is a call of the list's params and its rows", () => {
  assert.deepEqual(parseCall("chats.window", { scope: "ws", rows: 20 }), { kind: "chatsWindow", list: { topic: "chats", scope: "ws", mine: false }, rows: 20 });
  assert.deepEqual(parseCall("chats.window", { scope: "ws", mine: true, hidden: true, rows: 30 }), { kind: "chatsWindow", list: { topic: "chats", scope: "ws", mine: true, hidden: true }, rows: 30 });
  assert.throws(() => parseCall("chats.window", { scope: "ws" }));
});

test("a list of 420 chats on 5 stations told a window of 20 makes 20 rows and reads about 20 records for its first answer", async () => {
  const t = await opened();
  const { messages, workAt } = heard(t);
  const from = { ...work };
  t.window(ALL, 20);
  t.store.subscribe(1, 1, ALL, true);
  await t.host.time.pass(100);
  const first = messages.get(1)?.[0];
  assert.ok(first !== undefined && "value" in first, "a first value");
  const spent = (() => {
    const w = workAt.get(first)!;
    const out: Record<string, number> = {};
    for (const k of ["rows", "rowJson"] as const) out[k] = w[k] - from[k];
    return out;
  })();
  assert.equal(rowsOf(first.value).length, 20);
  assert.equal(first.value.more > 0, true, "it says it has more");
  assert.ok(spent.rows <= 20, `its first answer made ${spent.rows} rows`);
  assert.ok(spent.rowJson <= 21, `its first answer read ${spent.rowJson} records' JSON`);
  // (the rest of its stations' rows loaded behind it, none of them made)
  await t.host.time.pass(100);
  assert.ok(NAMES.every((name) => t.data.loaded(rows(`ws/${name}`))), "its stations' rows loaded behind it");
  assert.equal(rowsOf(valueOf(t, ALL)).length, 20);
  assert.equal(valueOf(t, ALL).more, 400);
  assert.ok(work.rows - from.rows <= 20, `the list made ${work.rows - from.rows} rows`);
});

test("a window raised from 20 to 40 makes the 20 rows added and sends them alone, as inserts", async () => {
  const t = await opened();
  const { messages } = heard(t);
  t.window(ALL, 20);
  t.store.subscribe(1, 1, ALL, true);
  await t.host.time.pass(200);
  const shown = valueOf(t, ALL);
  const out = rowsOf(shown);
  assert.equal(out.length, 20);
  const sent = messages.get(1)!.length;
  const made = work.rows;
  t.window(ALL, 40);
  await t.host.time.pass(100);
  const now = valueOf(t, ALL);
  assert.equal(rowsOf(now).length, 40);
  assert.equal(now.more, 380);
  assert.equal(work.rows - made, 20, "the rows added made, no other");
  rowsOf(now).slice(0, 20).forEach((r, i) => assert.equal(r, out[i], `row ${i} the same object`));
  const grew = messages.get(1)!.slice(sent);
  assert.equal(grew.length, 1, "one message");
  const m = grew[0];
  assert.ok(!("value" in m) && Array.isArray(m.delta), "what changed, not the list whole");
  // (the days the first rows ended in grown by puts, the days after put whole, `more` said again: nothing of the 20
  // rows out before)
  const put = new Set<string>();
  const walk = (ops: J[]) => {
    for (const op of ops) {
      if ("put" in op) {
        if (op.key.join() === "station,id") put.add(op.put.id);
        else for (const r of op.put.items ?? []) put.add(r.id);
      } else if ("ops" in op) walk(op.ops);
      else assert.ok(!("drop" in op) && !("move" in op), `no row dropped or moved: ${JSON.stringify(op)}`);
    }
  };
  walk(m.delta);
  assert.deepEqual([...put].sort(), rowsOf(now).slice(20).map((r: J) => r.id).sort());
  assert.ok(bytes(m) < bytes({ id: 1, value: now }) * 0.6, `the rows added (${bytes(m)} B), not the list whole (${bytes({ id: 1, value: now })} B)`);
});

test("a list let go of and evicted starts again from the window it is told then; kept, a smaller one keeps what it showed", async () => {
  const t = await opened();
  t.window(ALL, 40);
  t.store.subscribe(1, 1, ALL, true);
  await t.host.time.pass(200);
  assert.equal(rowsOf(valueOf(t, ALL)).length, 40);
  t.store.unsubscribe(1, 1);
  await t.host.time.pass(1000);
  // (let go of a moment, asked again with a first window: what it showed kept)
  t.window(ALL, 20);
  t.store.subscribe(1, 2, ALL, true);
  await t.host.time.pass(200);
  assert.equal(rowsOf(valueOf(t, ALL)).length, 40);
  t.store.unsubscribe(1, 2);
  await t.host.time.pass(EVICT_AFTER_MS + 1000);
  assert.equal(t.store.value(ALL), undefined, "evicted");
  t.window(ALL, 20);
  t.store.subscribe(1, 3, ALL, true);
  await t.host.time.pass(200);
  assert.equal(rowsOf(valueOf(t, ALL)).length, 20);
});

test("two lists of a workspace keep windows of their own", async () => {
  const t = await opened();
  t.window(ALL, 20);
  t.window(MINE, 30);
  t.store.subscribe(1, 1, ALL, true);
  t.store.subscribe(1, 2, MINE, true);
  await t.host.time.pass(200);
  assert.equal(rowsOf(valueOf(t, ALL)).length, 20);
  assert.equal(rowsOf(valueOf(t, MINE)).length, 30);
  t.window(MINE, 50);
  await t.host.time.pass(100);
  assert.equal(rowsOf(valueOf(t, ALL)).length, 20);
  assert.equal(rowsOf(valueOf(t, MINE)).length, 50);
  assert.ok(rowsOf(valueOf(t, MINE)).every((r: J) => r.mine === true));
});

test("what a list gives at a window of n is what it gave asked with `limit: n`", async () => {
  // (the lists whole, as they were given asked with no limit: told a window past their rows, on a rig of their own)
  const wholeRig = await opened();
  const lists = list;
  for (const mine of [false, true]) {
    wholeRig.window(lists(mine), 1000);
    wholeRig.store.subscribe(1, mine ? 2 : 1, lists(mine), true);
  }
  await wholeRig.host.time.pass(300);
  const t = await opened();
  const asked: [boolean, number][] = [[false, 20], [true, 30], [false, 50], [true, 100]];
  for (const [mine, n] of asked) {
    // (each its own rig: one list's window a value at a time)
    const r = n === 20 ? t : await opened();
    r.window(lists(mine), n);
    r.store.subscribe(1, 1, lists(mine), true);
    await r.host.time.pass(300);
    const whole = valueOf(wholeRig, lists(mine));
    assert.equal(whole.more, undefined);
    assert.deepEqual(valueOf(r, lists(mine)), firstOf(whole, n), `${mine ? "mine" : "all"} at ${n}`);
  }
});
