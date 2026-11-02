import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore, USAGE_DAY_SCOPED, USAGE_QUARTERS_SCOPED, VISIBLE_USAGE_CARDS } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";

function session(store: Store, key: string, ws: string | null) {
  store.insertSession({ key, connect: key, runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 1, lastActiveAt: 1 });
}

test("usage history counts only the chats and cards visible in the viewer's workspace", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "workspace-a");
    session(store, "b", "workspace-b");
    const thread = (surface: string, id: string, members: string[], picked: boolean) => {
      const t = store.openThread(surface, id, id, null, null).id;
      for (const member of members) store.joinThread(t, member, member);
      store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, 1, 'agent', '[]', 1, ?)").run(t, picked ? 1 : 0);
      return t;
    };
    thread("slack:a", "a", ["a"], true);
    const b = thread("feishu:b", "b", ["b"], false);
    thread("slack:shared", "shared", ["a", "b"], true);
    thread("ember", "orphan", [], false);
    store.db.prepare("UPDATE threads SET hidden_at = 1 WHERE id = ?").run(b);
    const reader = makeStore(store.db, ".");

    const a = usageHistory(reader, 0n, { workspace: "workspace-a", home: true });
    assert.deepEqual(a.places, { slack: 2, ember: 1 });
    assert.deepEqual([a.cards, a.picked, a.archived], [3, 2, 0]);
    const other = usageHistory(reader, 0n, { workspace: "workspace-b", home: false });
    assert.deepEqual(other.places, { feishu: 1, slack: 1 });
    assert.deepEqual([other.cards, other.picked, other.archived], [2, 1, 1]);
    const all = usageHistory(reader, 0n, null);
    assert.deepEqual([all.cards, all.picked, all.archived], [4, 2, 1]);

    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${VISIBLE_USAGE_CARDS}`).all("workspace-a", 1) as { detail: string }[];
    assert.match(plan.map((r) => r.detail).join(" | "), /SEARCH c USING PRIMARY KEY \(thread=\?\)/);
    let visited = 0;
    store.db.function("visited_card", (n) => { visited++; return n; });
    const tracked = store.db.prepare(VISIBLE_USAGE_CARDS.replace("ON c.thread = v.thread", "ON c.thread = v.thread AND visited_card(c.n) IS NOT NULL"));
    assert.equal(tracked.all("workspace-a", 1).length, 3);
    assert.equal(visited, 3);
    const insert = store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, ?, 'agent', '[]', 1, 0)");
    store.db.exec("BEGIN");
    for (let n = 2; n <= 2_001; n++) insert.run(b, n);
    store.db.exec("COMMIT");
    visited = 0;
    assert.equal(tracked.all("workspace-a", 1).length, 3);
    assert.equal(visited, 3, "another workspace's card history does not add examined cards");
  } finally {
    store.close();
  }
});

test("usage history assigns calls to their actual local day for any minute offset", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "workspace-a");
    const offsets = [1, -1, 0, 15, -15, 345, -345, 1_439, -1_439, 1_440, -1_440];
    const times = offsets.flatMap((offset) => {
      const midnight = Date.UTC(2026, 0, 2) - offset * 60_000;
      return [midnight - 900_001, midnight - 30_000, midnight + 30_000, midnight + 900_001];
    }).concat([-900_001, -900_000, -1, 0, 1, 899_999, 900_000]);
    const calls = times.map((at, i) => [{ id: `call-${i}`, at, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null },
      { turn: null, person: null, thread: null, profile: null }] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", calls as never);
    for (const offset of offsets) {
      const expected = new Map<string, number>();
      for (const at of times) {
        const day = new Date(at + offset * 60_000).toISOString().slice(0, 10);
        expected.set(day, (expected.get(day) ?? 0) + 1);
      }
      const got = usageHistory(makeStore(store.db, "."), BigInt(offset), null).days;
      assert.deepEqual(got.map((d: { day: string; calls: number }) => [d.day, d.calls]), [...expected].sort(), `offset ${offset}`);
    }
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${USAGE_DAY_SCOPED}`).all(1n, "workspace-a") as { detail: string }[];
    assert.match(plan.map((r) => r.detail).join(" | "), /SEARCH sc USING COVERING INDEX usage_minute_scope_ws \(ws=\?\)/);
    assert.match(plan.map((r) => r.detail).join(" | "), /SEARCH q USING PRIMARY KEY \(session=\?\)/);
    assert.match(plan.map((r) => r.detail).join(" | "), /SEARCH m USING PRIMARY KEY \(session=\? AND minute>\? AND minute<\?\)/);
    let visited = 0;
    let edgeVisited = 0;
    store.db.function("visited_quarter", (quarter) => { visited++; return quarter; });
    store.db.function("visited_minute", (minute) => { edgeVisited++; return minute; });
    const tracked = store.db.prepare(USAGE_DAY_SCOPED
      .replaceAll("ON q.session = sc.session", "ON q.session = sc.session AND visited_quarter(q.quarter) IS NOT NULL")
      .replace("ON m.session = e.session", "ON m.session = e.session AND visited_minute(m.minute) IS NOT NULL"));
    const noon = Date.UTC(2026, 0, 1, 12);
    const noonCall = { id: "noon", at: noon, model: "m", subagent: false, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null };
    const of = { turn: null, person: null, thread: null, profile: null };
    store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [[noonCall, of]]);
    tracked.all(1n, "workspace-a");
    const before = visited;
    const edgesBefore = edgeVisited;
    const extra = Array.from({ length: 2_000 }, (_, i) => [{ ...noonCall, id: `noon-${i}`, at: noon + i }, of] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 3, model: "m" }, "claude", extra as never);
    visited = 0;
    edgeVisited = 0;
    tracked.all(1n, "workspace-a");
    assert.equal(visited, before, "more calls in a minute do not add examined summaries");
    assert.equal(edgeVisited, edgesBefore);
    const spread = Array.from({ length: 14 }, (_, i) => [{ ...noonCall, id: `spread-${i}`, at: noon + (i + 1) * 60_000 }, of] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 4, model: "m" }, "claude", spread as never);
    visited = 0;
    edgeVisited = 0;
    tracked.all(1n, "workspace-a");
    assert.equal(visited, before, "more calls in an ordinary quarter do not add examined summaries");
    assert.equal(edgeVisited, edgesBefore, "minutes outside local midnight are not read individually");
    const aligned = store.db.prepare(`EXPLAIN QUERY PLAN ${USAGE_QUARTERS_SCOPED}`).all(0n, "workspace-a") as { detail: string }[];
    assert.match(aligned.map((r) => r.detail).join(" | "), /SEARCH q USING PRIMARY KEY \(session=\?\)/);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_minute" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.ok(usageHistory(makeStore(store.db, "."), 0n, { workspace: "workspace-a", home: false }).days.length > 0,
        "a quarter-aligned time zone does not inspect minute summaries");
    } finally {
      store.db.setAuthorizer(null);
    }
    session(store, "b", "workspace-b");
    const other = Array.from({ length: 2_000 }, (_, i) => [{ ...noonCall, id: `other-${i}`, at: noon + i * 60_000 }, of] as const);
    store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: "m" }, "claude", other as never);
    visited = 0;
    edgeVisited = 0;
    tracked.all(1n, "workspace-a");
    assert.equal(visited, before, "another workspace's growing history is not read");
    assert.equal(edgeVisited, edgesBefore);
  } finally {
    store.close();
  }
});
