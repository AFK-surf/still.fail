import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { LAST_CONTEXTS } from "../src/store/usage.ts";

function fixture() {
  const store = Store.open(":memory:");
  store.insertSession({ key: "a", connect: "a", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
  const call = (id: string, at: number, context: number) => {
    const c = { id, at, model: "m", subagent: false, fast: false, input: context, cacheRead: 0, cacheWrite: 0,
      cacheWriteLong: 0, output: 0, calls: 1, context, window: null };
    store.recordUsage("/a.jsonl", { session: "a", offset: at, model: "m" }, "claude",
      [[c, { turn: null, person: null, thread: null, profile: "cc" }]]);
  };
  return { store, call };
}

test("a late call and its removal revise the following compaction", () => {
  const { store, call } = fixture();
  try {
    call("a", 1_000, 120_000);
    call("c", 3_000, 20_000);
    assert.deepEqual([...store.compactionPoints(0)], [["m", 120_000]]);
    call("b", 2_000, 80_000);
    assert.deepEqual([...store.compactionPoints(0)], [["m", 80_000]], "the next call now follows b, not a");
    store.db.prepare("DELETE FROM usage WHERE id = 'b'").run();
    assert.deepEqual([...store.compactionPoints(0)], [["m", 120_000]]);
    store.db.prepare("DELETE FROM usage WHERE id = 'c'").run();
    assert.deepEqual([...store.compactionPoints(0)], []);
  } finally {
    store.close();
  }
});

test("calls with the same time have the same compaction in either arrival order", () => {
  for (const order of [["a", "b"], ["b", "a"]]) {
    const { store, call } = fixture();
    try {
      for (const id of order) call(id!, 1_000, id === "a" ? 120_000 : 20_000);
      assert.deepEqual([...store.compactionPoints(0)], [["m", 120_000]], `arrival ${order.join(",")}`);
    } finally {
      store.close();
    }
  }
});

test("the last main calls skip the session's growing subagent history", () => {
  const { store, call } = fixture();
  try {
    call("a", 1_000, 120_000);
    call("b", 2_000, 20_000);
    const subagents = Array.from({ length: 2_000 }, (_, n) => [{ id: `sub${n}`, at: 3_000 + n, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null },
      { turn: null, person: null, thread: null, profile: "cc" }] as const);
    store.recordUsage("/a.jsonl", { session: "a", offset: 10_000, model: "m" }, "claude", subagents as never);
    assert.deepEqual(store.lastContexts("a", 2).map((c) => c.context), [120_000, 20_000]);
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${LAST_CONTEXTS}`).all("a", 2) as { detail: string }[];
    assert.match(plan.map((p) => p.detail).join(" | "), /SEARCH m USING PRIMARY KEY \(session=\?\)/);
    assert.ok(!plan.some((p) => p.detail.includes("TEMP B-TREE")));
    let examined = 0;
    store.db.function("examined_main", (_id) => { examined++; return 1; });
    store.db.prepare(LAST_CONTEXTS.replace("WHERE m.session = ?1", "WHERE m.session = ?1 AND examined_main(m.id)")).all("a", 2);
    assert.equal(examined, 2, "two requested main calls examine two indexed main calls");
  } finally {
    store.close();
  }
});
