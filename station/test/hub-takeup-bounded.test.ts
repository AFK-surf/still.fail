import assert from "node:assert/strict";
import { test } from "node:test";
import { runnerId } from "../src/agents/process.ts";
import { enableSandboxIndex, sandboxIndexReady, sandboxIndexStep } from "../src/store/sandbox-index.ts";
import { Rig } from "./hub-fakes.ts";

test("taking up a session-owned runner does not read unrelated session history", async () => {
  const counts: number[] = [];
  for (const unrelated of [40, 400]) {
    const r = new Rig(), db = r.store.db;
    let observing = false, read = 0;
    db.function("takeup_seen", (key) => { if (observing && String(key).startsWith("other:")) read++; return 1; });
    const proxy = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT * FROM sessions ORDER BY last_active_at DESC"
        ? sql.replace(" ORDER BY", " WHERE takeup_seen(key) ORDER BY") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const add = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,running,created_at,last_active_at,archived_at)
      VALUES (?,'cl','thread',?,'cc',?,?,?,0,?,?)`);
    add.run("claude", "claude", "/claude", "claude", 0, 20, null);
    add.run("codex", "codex", "/codex", "codex", 1, 10, null);
    add.run("idle-codex", "codex", "/idle", "idle", 0, 30, null);
    for (let i = 0; i < unrelated; i++) add.run(`other:${i}`, "claude", `/other/${i}`, `other:${i}`, 0, i, i % 2 ? 1 : null);
    enableSandboxIndex(db);
    while (!sandboxIndexReady(db)) sandboxIndexStep(db, 64);
    Object.defineProperty(r.store, "db", { value: proxy });
    const hub = r.newHub({ chats: () => undefined, internal: false, runners: [runnerId("claude", "claude")] });
    const taken: string[] = [];
    (hub as any).adoptOne = async (row: { key: string }) => { taken.push(row.key); };
    try {
      observing = true;
      await hub.takeUp();
      observing = false;
      assert.deepEqual(taken, ["claude", "codex"]);
      counts.push(read);
    } finally { await hub.shutdown(); await r.close(); }
  }
  assert.deepEqual(counts, [0, 0]);
});
