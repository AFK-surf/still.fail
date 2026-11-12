// Keyed collections (collections.ts): a row that changed is one op wherever it is, and applying the ops gives the new
// value with the rows that did not change the same objects.
import assert from "node:assert/strict";
import { test } from "node:test";
import { type AnyOp, applyKeyed, diffKeyed, heavier, keyOf, share, type Spec, specOf, textOf } from "../src/collections.ts";
import { apply, diff, diffAt, largerThan, type Op, type Segment } from "../src/delta.ts";
import { compareKeys, equal, isObject } from "../src/util.ts";
import { walked } from "../src/work.ts";

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

test("a_history_going_back_a_page_puts_its_items_before_and_leaves_the_rest_as_they_were", () => {
  const item = (key: string, text = key) => ({ key, entries: [1, 1], body: { kind: "text", content: { text, md: [["p", [text]]], subagent: false } } });
  const history = (items: ReturnType<typeof item>[]) => ({ items, live: [], edge: "", empty: false, loaded: true });
  const shown = Array.from({ length: 30 }, (_, i) => item(`k${i + 10}`));
  const old = history(shown);
  const next = history([item("k8"), item("k9"), ...shown.slice(0, 29), item("k39", "改了")]);
  const ops = diffKeyed(old, next, specOf({ topic: "history", station: "w/s", key: "k" }));
  assert.deepEqual(ops.map((op) => Object.keys(op).find((k) => ["put", "patch", "drop", "move"].includes(k))).sort(), ["patch", "put", "put"]);
  const applied = applyKeyed(old, ops) as typeof old;
  assert.deepEqual(applied, next);
  assert.equal(applied.items[5], old.items[3]);
});

// ── The same objects cost one comparison each (share, a keyed list's diff), what they give as it was ──

/// `share` and `diffKeyed` as they were before the same objects at a list's start and end were trimmed first: the
/// oracle the trimmed ones give the same as (a key twice anywhere in a list takes the old way here).
const before = {
  share(prev: unknown, next: unknown, spec: Spec | null): unknown {
    if (prev === next || typeof next !== "object" || next === null || typeof prev !== "object" || prev === null) return next;
    if (Array.isArray(next)) {
      if (!Array.isArray(prev)) return next;
      const fields = spec?.key;
      const byKey = fields ? new Map(prev.map((item) => [textOf(item, fields), item])) : null;
      let all = prev.length === next.length;
      const items = next.map((item, i) => {
        const kept = before.share(byKey ? byKey.get(textOf(item, fields!)) : prev[i], item, spec?.item ?? null);
        if (kept !== prev[i]) all = false;
        return kept;
      });
      return all ? prev : items;
    }
    if (!isObject(prev) || !isObject(next)) return next;
    const keys = Object.keys(next);
    let all = keys.length === Object.keys(prev).length;
    const fields: Record<string, unknown> = {};
    for (const key of keys) {
      const kept = before.share(prev[key], next[key], spec?.fields?.[key] ?? null);
      if (kept !== prev[key] || !(key in prev)) all = false;
      fields[key] = kept;
    }
    return all ? prev : fields;
  },
  diff(old: unknown, next: unknown, spec: Spec | null): AnyOp[] {
    const ops: AnyOp[] = [];
    before.at([], old, next, spec, ops);
    return ops;
  },
  at(path: Segment[], old: unknown, next: unknown, spec: Spec | null, ops: AnyOp[]): void {
    if (old === next) return;
    if (spec === null) return diffAt([...path], old, next, ops as Op[]);
    if (spec?.key && Array.isArray(old) && Array.isArray(next) && before.list(path, old, next, spec, ops)) return;
    if (isObject(old) && isObject(next)) {
      const has = Object.prototype.hasOwnProperty;
      const changed = Object.keys(next).filter((key) => !has.call(old, key) || old[key] !== next[key]).sort(compareKeys);
      for (const key of changed) {
        if (has.call(old, key)) before.at([...path, key], old[key], next[key], spec?.fields?.[key] ?? null, ops);
        else ops.push({ path: [...path, key], set: next[key] });
      }
      for (const key of Object.keys(old).filter((key) => !has.call(next, key)).sort(compareKeys)) ops.push({ path: [...path, key], remove: true });
      return;
    }
    if (Array.isArray(old) && Array.isArray(next)) {
      if (old.length === next.length) {
        for (let i = 0; i < old.length; i++) before.at([...path, i], old[i], next[i], spec?.item ?? null, ops);
        return;
      }
      if (old.length < next.length && old.every((v, i) => equal(v, next[i]))) {
        ops.push({ path: [...path], append: next.slice(old.length) });
        return;
      }
    }
    if (equal(old, next)) return;
    ops.push({ path: [...path], set: next });
  },
  list(path: Segment[], old: unknown[], next: unknown[], spec: Spec, ops: AnyOp[]): boolean {
    const fields = spec.key!;
    if (old.length === next.length && old.every((item, i) => item === next[i])) return true;
    const keys = (l: unknown[]) => {
      const out = l.map((item) => textOf(item, fields));
      return new Set(out).size === out.length ? out : null;
    };
    const allOld = keys(old);
    const allNext = keys(next);
    if (!allOld || !allNext) return false;
    let start = 0;
    while (start < old.length && start < next.length && old[start] === next[start]) start++;
    let oldEnd = old.length;
    let nextEnd = next.length;
    while (oldEnd > start && nextEnd > start && old[oldEnd - 1] === next[nextEnd - 1]) {
      oldEnd--;
      nextEnd--;
    }
    const nextKeys = allNext.slice(start, nextEnd);
    const was = new Map(allOld.slice(start, oldEnd).map((k, i) => [k, start + i]));
    const now = new Set(nextKeys);
    const out: AnyOp[] = [];
    for (let i = start; i < oldEnd; i++) if (!now.has(allOld[i]!)) out.push({ path: [...path], key: fields, drop: keyOf(old[i], fields) });
    const positions = nextKeys.map((k) => was.get(k) ?? -1);
    const fresh = positions.filter((p) => p < 0).length;
    if (fresh > 256 && fresh * 2 > next.length) {
      ops.push({ path: [...path], set: next });
      return true;
    }
    // (a longest increasing run of the kept ones' places stays)
    const tails: number[] = [];
    const back = new Array<number>(positions.length).fill(-1);
    positions.forEach((p, i) => {
      if (p < 0) return;
      let lo = 0;
      let hi = tails.length;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (positions[tails[mid]!]! < p) lo = mid + 1;
        else hi = mid;
      }
      if (lo > 0) back[i] = tails[lo - 1]!;
      tails[lo] = i;
    });
    const stay = new Set<number>();
    for (let i = tails.length > 0 ? tails[tails.length - 1]! : -1; i >= 0; i = back[i]!) stay.add(i);
    for (let j = positions.length - 1; j >= 0; j--) {
      const i = start + j;
      const at = i + 1 < next.length ? keyOf(next[i + 1], fields) : null;
      const from = positions[j]!;
      if (from < 0) {
        out.push({ path: [...path], key: fields, put: next[i], before: at });
        continue;
      }
      if (!stay.has(j)) out.push({ path: [...path], key: fields, move: keyOf(next[i], fields), before: at });
      const changes = before.diff(old[from], next[i], spec.item ?? null);
      if (changes.length === 0) continue;
      const long = (l: AnyOp[]): boolean => l.some((op) => ("set" in op && Array.isArray(op.set) && op.set.length > 256) || ("patch" in op && long(op.ops)));
      const put = !long(changes) && largerThan(changes as Op[], next[i]);
      out.push(put ? { path: [...path], key: fields, put: next[i] } : { path: [...path], key: fields, patch: keyOf(next[i], fields), ops: changes });
    }
    if (out.length > 0 && heavier(out, next)) ops.push({ path: [...path], set: next });
    else ops.push(...out);
    return true;
  },
};

/// What `share` and `diffKeyed` give of `prev` and `next`, held to the oracle, and what they walked.
function measured(prev: unknown, next: unknown, spec: Spec) {
  const from = { ...walked };
  const shared = share(prev, next, spec);
  const sharing = { same: walked.same - from.same, shared: walked.shared - from.shared };
  assert.deepEqual(shared, before.share(prev, next, spec), "shared as before");
  assert.deepEqual(shared, next);
  // (diffed as the store does: what went out against what share gave)
  const mid = { ...walked };
  const ops = diffKeyed(prev, shared, spec);
  const diffing = { same: walked.same - mid.same, diffed: walked.diffed - mid.diffed };
  assert.deepEqual(ops, before.diff(prev, shared, spec), "the ops as before");
  assert.deepEqual(applyKeyed(prev, ops), next);
  return { shared, ops, sharing, diffing };
}

const N = 90;
const listSpec: Spec = { key: ["station", "id"] };
const rowsOf = () => Array.from({ length: N }, (_, i) => Object.freeze(row("ws/st", `t${i}`)));

test("a_keyed_list_with_one_item_changed_walks_that_item_alone", () => {
  const rows = rowsOf();
  // replaced in the middle, at the start, at the end
  for (const at of [45, 0, N - 1]) {
    const next = rows.map((r, i) => (i === at ? { ...r, title: "new" } : r));
    const m = measured(rows, next, listSpec);
    assert.equal(m.sharing.same, N - 1, `${at}: the others one comparison each`);
    // (the list, the item mapped and the one before it put in the map, the item's object)
    assert.equal(m.sharing.shared, 4, `${at}`);
    assert.equal(m.diffing.same, N - 1);
    assert.equal(m.diffing.diffed, 2);
    const shared = m.shared as unknown[];
    assert.equal(shared[at === 0 ? 1 : 0], rows[at === 0 ? 1 : 0], "the others are the objects they were");
  }
});

test("a_keyed_list_with_one_item_moved_inserted_or_dropped_walks_the_stretch_between", () => {
  const rows = rowsOf();
  const fresh = Object.freeze(row("ws/st", "new"));
  const cases: [string, unknown[], number][] = [
    // (what, the new list, how many items lie between the same start and end, of the new list and the old)
    ["moved to the top", [rows[60], ...rows.filter((_, i) => i !== 60)], 61 + 61],
    ["moved down by one", [...rows.slice(0, 10), rows[11], rows[10], ...rows.slice(12)], 2 + 2],
    ["put at the start", [fresh, ...rows], 1],
    ["put in the middle", [...rows.slice(0, 40), fresh, ...rows.slice(40)], 1],
    ["put at the end", [...rows, fresh], 1],
    ["dropped", rows.filter((_, i) => i !== 30), 1],
  ];
  for (const [what, next, between] of cases) {
    const m = measured(rows, next, listSpec);
    assert.equal(m.diffing.diffed, between, what);
    assert.equal(m.diffing.same, next.length - (what === "dropped" ? 0 : what.startsWith("put") ? 1 : between / 2), what);
    assert.equal(m.sharing.same, m.diffing.same, what);
    assert.ok(m.sharing.shared <= 1 + between, `${what}: shared ${m.sharing.shared}`);
    // (the items between are each the object they were: one moved is the very row)
    for (const item of m.shared as unknown[]) if (item !== fresh) assert.ok(rows.includes(item as never), what);
  }
});

test("a_keyed_list_all_the_same_is_the_list_it_was", () => {
  const rows = rowsOf();
  const value = { items: rows, live: [] };
  const spec: Spec = { fields: { items: listSpec } };
  // the same items in a new array, and in a new value: the value it was, as its holder
  const m = measured(value, { items: [...rows], live: value.live }, spec);
  assert.equal(m.shared, value);
  assert.deepEqual(m.ops, []);
  assert.equal(m.sharing.same, N);
  assert.equal(m.sharing.shared, 2, "the value and its list, nothing of an item");
  assert.equal(m.diffing.diffed, 0);
  // the same array: nothing looked at in it
  const from = walked.same;
  assert.equal(share(rows, rows, listSpec), rows);
  assert.deepEqual(diffKeyed(rows, rows, listSpec), []);
  assert.equal(walked.same, from);
  // the same items but one fewer: not the list it was
  const shorter = share(rows, rows.slice(0, N - 1), listSpec);
  assert.notEqual(shorter, rows);
  assert.equal((shorter as unknown[]).length, N - 1);
});

test("an_item_the_same_object_whose_list_moved_under_another_parent_goes_as_before", () => {
  const spec = specOf({ topic: "chats", scope: "ws" })!;
  const rows = rowsOf();
  const old = chats([{ daysAgo: 0, items: rows.slice(0, 50) }, { daysAgo: 1, items: rows.slice(50) }]);
  // the first of yesterday's rows, the same object, now the first of today's
  const next = chats([{ daysAgo: 0, items: [rows[50]!, ...rows.slice(0, 50)] }, { daysAgo: 1, items: rows.slice(51) }]);
  const m = measured(old, next, spec);
  const days = (m.shared as typeof next).days;
  assert.equal(days[0]!.items[0], rows[50]);
  assert.equal(days[0]!.items[1], rows[0]);
  // (the days, two of each list; the row put in one and dropped from the other)
  assert.equal(m.diffing.diffed, 4 + 1 + 1);
  assert.equal(m.diffing.same, 50 + 39);
  // and back again, the days as they were
  const back = measured(next, old, spec);
  assert.deepEqual(back.shared, old);
});

test("shares_and_diffs_of_shuffles_are_what_they_were", () => {
  let seed = 11;
  const rand = (n: number) => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed % n;
  };
  const spec = specOf({ topic: "chats", scope: "ws" })!;
  for (let round = 0; round < 300; round++) {
    const pool = Array.from({ length: 30 }, (_, i) => row("s", `k${i}`));
    const day = (d: number) => ({ daysAgo: d, items: pool.filter(() => rand(3) === 0) });
    const old = chats([day(0), day(1), day(2)]);
    const next = chats(
      old.days.map((d) => {
        if (rand(3) === 0) return d;
        const items = d.items.filter(() => rand(6) > 0).map((r) => (rand(5) === 0 ? { ...r, title: `x${rand(9)}` } : r));
        if (rand(2) === 0) items.splice(rand(items.length + 1), 0, pool[rand(30)]!);
        if (items.length > 1 && rand(2) === 0) items.splice(rand(items.length), 0, items.splice(rand(items.length), 1)[0]!);
        return { daysAgo: d.daysAgo, items };
      }),
    );
    // (a key twice in a list, which a row put again may make, goes the old way: not held to the oracle where it lies
    // across the same objects at its ends)
    if (next.days.some((d) => new Set(d.items.map((r) => r.id)).size !== d.items.length)) continue;
    measured(old, next, spec);
  }
});
