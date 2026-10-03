// Keyed collections (collections.ts): a row that changed is one op wherever it is, and applying the ops gives the new
// value with the rows that did not change the same objects.
import assert from "node:assert/strict";
import { test } from "node:test";
import { applyKeyed, diffKeyed, specOf } from "../src/collections.ts";
import { apply, diff } from "../src/delta.ts";

const row = (station: string, id: string, title = id, at = 1) => ({ station, id, title, lastActiveAt: at, agents: [], unread: false });
const chats = (days: { daysAgo: number; items: ReturnType<typeof row>[] }[]) => ({ me: { email: "a" }, loading: false, stations: [], days: days.map((d) => ({ ...d, at: d.daysAgo, label: `d${d.daysAgo}` })) });
const spec = specOf({ topic: "chats", scope: "ws" });

test("one_row_changed_is_one_patch_wherever_it_is", () => {
  const rows = Array.from({ length: 2000 }, (_, i) => row("ws/st", `t${i}`));
  const old = chats([{ daysAgo: 0, items: rows }]);
  const next = chats([{ daysAgo: 0, items: rows.map((r, i) => (i === 1500 ? { ...r, unread: true } : r)) }]);
  const ops = diffKeyed(old, next, spec);
  assert.deepEqual(ops, [{ path: ["days"], key: ["daysAgo"], patch: 0, ops: [{ path: ["items"], key: ["station", "id"], patch: ["ws/st", "t1500"], ops: [{ path: ["unread"], set: true }] }] }]);
  const applied = applyKeyed(old, ops) as typeof old;
  assert.deepEqual(applied, next);
  assert.equal(applied.days[0].items[3], old.days[0].items[3]);
});

test("a_row_moving_to_the_top_is_one_move", () => {
  const rows = Array.from({ length: 2000 }, (_, i) => row("ws/st", `t${i}`));
  const moved = { ...rows[1200], lastActiveAt: 9 };
  const old = chats([{ daysAgo: 0, items: rows }]);
  const next = chats([{ daysAgo: 0, items: [moved, ...rows.filter((_, i) => i !== 1200)] }]);
  const ops = diffKeyed(old, next, spec);
  const inner = (ops[0] as { ops: unknown[] }).ops;
  assert.deepEqual(inner, [
    { path: ["items"], key: ["station", "id"], move: ["ws/st", "t1200"], before: ["ws/st", "t0"] },
    { path: ["items"], key: ["station", "id"], patch: ["ws/st", "t1200"], ops: [{ path: ["lastActiveAt"], set: 9 }] },
  ]);
  assert.deepEqual(applyKeyed(old, ops), next);
  // The old ops: every row from the top to where it was is set again.
  assert.ok(JSON.stringify(diff(old, next)).length > 50 * JSON.stringify(ops).length);
});

test("rows_moving_between_days_put_and_drop_and_same_keys_in_two_stations_differ", () => {
  const a = row("ws/a", "1");
  const b = row("ws/b", "1");
  const c = row("ws/a", "2");
  const old = chats([{ daysAgo: 0, items: [a] }, { daysAgo: 1, items: [b, c] }]);
  const next = chats([{ daysAgo: 0, items: [c, a] }, { daysAgo: 1, items: [b] }]);
  const ops = diffKeyed(old, next, spec);
  assert.deepEqual(applyKeyed(old, ops), next);
  // A day gone, one new.
  const later = chats([{ daysAgo: 1, items: [b] }, { daysAgo: 3, items: [a] }]);
  assert.deepEqual(applyKeyed(next, diffKeyed(next, later, spec)), later);
});

test("shuffles_and_edits_round_trip", () => {
  let seed = 7;
  const rand = (n: number) => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed % n;
  };
  for (let round = 0; round < 200; round++) {
    const old = Array.from({ length: rand(12) }, (_, i) => row("s", `k${rand(20)}-${i}`));
    const next = old.filter(() => rand(4) > 0).map((r) => (rand(3) === 0 ? { ...r, title: `x${rand(9)}` } : r));
    for (let i = rand(4); i > 0; i--) next.splice(rand(next.length + 1), 0, row("s", `n${round}-${i}`));
    for (let i = next.length - 1; i > 0; i--) {
      if (rand(3) === 0) {
        const j = rand(i + 1);
        [next[i], next[j]] = [next[j], next[i]];
      }
    }
    const ops = diffKeyed(old, next, specOf({ topic: "chatRows", station: "s" }));
    assert.deepEqual(applyKeyed(old, ops), next, JSON.stringify({ old, next, ops }));
  }
});

test("a_key_twice_goes_the_old_way", () => {
  const old = [row("s", "1"), row("s", "1", "b")];
  const next = [row("s", "1", "c")];
  const ops = diffKeyed(old, next, specOf({ topic: "chatRows", station: "s" }));
  assert.deepEqual(ops, diff(old, next));
  assert.deepEqual(apply(structuredClone(old), ops as never), next);
});
