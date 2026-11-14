import assert from "node:assert/strict";
import { test } from "node:test";
import { undecided } from "../src/sessions/review.ts";
import { Rig } from "./hub-fakes.ts";

test("a review sweep reads each workspace's policy once and sees changes on its next pass", () => {
  const sessions = Array.from({ length: 120 }, (_, n) => ({ key: `s${n}`, ws: n < 30 ? null : n < 60 ? "W" : "B", running: false }));
  const lookup = new Map(sessions.map((s) => [s.key, s]));
  const ids = new Map<string | null, number>([[null, 10], ["B", 20]]);
  const read: (string | null)[] = [];
  const store = {
    liveSessions: () => sessions,
    lastTurn: () => ({ endedAt: 1, ending: "all_done" }),
    hasUndelivered: () => false,
    archivePolicy: (ws: string | null) => { read.push(ws); return { change: { id: ids.get(ws) } }; },
    recentSessionThreads: (key: string) => ({ threads: [{ thread: { id: Number(key.slice(1)) } }], more: false }),
    lastDecision: (key: string) => ({ policyAt: lookup.get(key)!.ws === "B" ? 20 : 10, result: {}, error: null, threads: [[Number(key.slice(1)), 5]] }),
    archiveSuggested: () => false,
    lastEntry: () => 5,
  };
  const hub: any = { store, workspaces: () => ["W", "B"], wsOf: (s: string | typeof sessions[number]) => (typeof s === "string" ? lookup.get(s)?.ws : s.ws) ?? "W" };
  assert.deepEqual(undecided(hub), []);
  assert.deepEqual(read, [null, "B"], "the number of policy reads follows workspaces, not sessions");
  ids.set("B", 21);
  read.length = 0;
  assert.deepEqual(undecided(hub), sessions.filter((s) => s.ws === "B").map((s) => s.key));
  assert.deepEqual(read, [null, "B"], "a later sweep reads the changed policy again");
});

test("a review sweep only checks whether there are undelivered messages or letters", async () => {
  const r = new Rig();
  try {
    r.store.insertSession({ key: "s", connect: "cl", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
    const thread = r.store.openThread("cl", "cl", "chat", null, null).id;
    r.store.joinThread(thread, "s", "cl");
    r.store.startTurn("done", "s", "input");
    r.store.endTurn("done", "completed", null, "all_done", null);
    // The old count treated even orphaned deliveries as pending. Keep that behavior, without counting the rest.
    const delivery = r.store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, ?, 's')");
    r.store.db.exec("BEGIN");
    for (let n = 1; n <= 2_000; n++) delivery.run(thread, n);
    r.store.db.exec("COMMIT");
    let examined = 0;
    const db = r.store.db;
    db.function("review_examined", (n) => { examined++; return n; });
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          /FROM (?:letter_)?deliveries INDEXED BY (?:letter_)?deliveries_pending/.test(sql)
            ? sql.replace("delivered_at IS NULL", "delivered_at IS NULL AND review_examined(n) IS NOT NULL") : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(r.store, "db", { value: traced, configurable: true });
    r.store.statsOf = () => { throw new Error("counted pending deliveries"); };
    assert.deepEqual(undecided(r.hub), []);
    assert.equal(examined, 1, "one undelivered message is enough, even when there are 2,000");
    r.store.db.prepare("DELETE FROM deliveries WHERE session = 's'").run();
    r.store.db.prepare("INSERT INTO letter_deliveries (thread, n, session) VALUES (?, 1, 's')").run(thread);
    examined = 0;
    assert.deepEqual(undecided(r.hub), [], "an orphaned letter delivery also keeps the session pending");
    assert.equal(examined, 1);
    r.store.db.prepare("DELETE FROM letter_deliveries WHERE session = 's'").run();
    assert.deepEqual(undecided(r.hub), ["s"]);
    Object.defineProperty(r.store, "db", { value: db, configurable: true });
  } finally { await r.close(); }
});
