import assert from "node:assert/strict";
import { test } from "node:test";
import { outflowUsage } from "../src/read/outflow.ts";
import { makeStore } from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";

for (const count of [4, 40]) test(`a usage export keeps its rows without reading ${count} chat details`, () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a",
      token: "a", createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws: null });
    const calls: unknown[] = [];
    for (let i = 0; i < count; i++) {
      const thread = store.openThreadOf("ember", "CHAT", `100.${i}`, `Chat ${i}`, "ann@x", "a");
      store.joinThread(thread.id, "a", "ember");
      calls.push([{ id: `call${i}`, at: 86_400_001, model: "claude-opus-5-5", subagent: false, fast: false,
        input: 100, cacheRead: 40, cacheWrite: 10, cacheWriteLong: 0, output: 5, calls: 1, context: null, window: null },
      { turn: null, person: "ann@x", thread: thread.id, profile: "cc" }]);
    }
    store.recordUsage("/a.jsonl", { session: "a", offset: count, model: null }, "claude", calls as never);
    const reader = makeStore(store.db, ".");
    const db = reader.db;
    let lookups = 0;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM threads WHERE id = ?") lookups++;
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    const exported = outflowUsage(reader, "en", 86_400_000, 2 * 86_400_000, 0);
    assert.equal(lookups, 0, "the export does not read chat details it will discard");
    const page = usage(reader, "en", 86_400_000n, 2n * 86_400_000n, 0n, false);
    assert.equal(lookups, count, "the usage page still reads its chat details");
    assert.equal(Object.keys(page.threads).length, count);
    assert.deepEqual(exported.rows, page.rows.map((r: any) => ({
      day: r.day, thread: r.thread, session: r.session, person: r.person, account: r.profile, runtime: r.runtime, model: r.model,
      calls: r.calls, input: r.input, cacheRead: r.cacheRead, cacheWrite: r.cacheWrite, output: r.output, cost: r.cost,
    })));
    assert.ok(exported.rows.every((row: any) => row.cost > 0));
    assert.deepEqual(exported.people, { "ann@x": { name: null, email: "ann@x", via: "cloud" } });
    assert.equal(exported.since, page.since ?? null);
  } finally { store.close(); }
});
