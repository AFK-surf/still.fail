import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { historyHits } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

const asker = { workspace: "mine", home: false, scopes: [] };
const options = { limit: 5, offset: 0, ms: 10_000, now: () => 0 };

test("a history search can be cancelled while resolving one session's many old transcripts", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-sources-bounded-"));
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    store.db.exec("BEGIN");
    for (let i = 0; i < 513; i++) put.run("one", `source-${i}`, "cc", i, "claude");
    store.db.exec("COMMIT");
    let scheduled = false, cancelled = false;
    const db = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (!scheduled && /FROM\s+(?:sessions\s+\w+\s+CROSS JOIN\s+)?runtime_sessions\b/i.test(sql)) {
          scheduled = true;
          setImmediate(() => { cancelled = true; });
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const home = join(data, "profile"); mkdirSync(home);
    await assert.rejects(historyHits(makeStore(db, data), [{ id: "cc", home, runtime: "claude" }], ["needle"], asker,
      { ...options, cancelled: () => cancelled }), /the search took too long/);
    assert.equal(scheduled, true);
    assert.equal(cancelled, true);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_temp_master WHERE name LIKE 'history_runtime_snapshot_%'").get() as { n: number }).n, 0);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a history search rechecks visibility when another request runs during source lookup", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-sources-moved-"));
  const store = Store.open(":memory:");
  let scheduled = false, moved = false;
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    store.db.exec("BEGIN");
    for (let i = 0; i < 140; i++) put.run("one", `source-${i}`, "cc", i, "claude");
    store.db.exec("COMMIT");
    const db = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (!scheduled && /FROM\s+(?:sessions\s+\w+\s+CROSS JOIN\s+)?runtime_sessions\b/i.test(sql)) {
          scheduled = true;
          setImmediate(() => { store.db.prepare("UPDATE sessions SET ws='other' WHERE key='one'").run(); moved = true; });
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const home = join(data, "profile"); mkdirSync(home);
    await assert.rejects(historyHits(makeStore(db, data), [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options), /session changed while searching/);
    assert.equal(moved, true);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_temp_master WHERE name LIKE 'history_runtime_snapshot_%'").get() as { n: number }).n, 0);
  } finally {
    if (scheduled && !moved) await new Promise<void>((resolve) => setImmediate(resolve));
    store.close(); rmSync(data, { recursive: true, force: true });
  }
});

test("history search keeps transcript order and step numbers when the current runtime is an older one", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-sources-order-"));
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    put.run("one", "old", "cc", 1, "claude");
    put.run("one", "new", "cc", 2, "claude");
    store.setRuntimeSessionId("one", "old");
    const home = join(data, "profile"), dir = join(home, "projects", "w");
    mkdirSync(dir, { recursive: true });
    const entry = (text: string) => JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text }] } });
    writeFileSync(join(dir, "old.jsonl"), `${entry("needle old")}\n`);
    writeFileSync(join(dir, "new.jsonl"), `${entry("introduction")}\n${entry("needle new")}\n`);
    const found = await historyHits(makeStore(store.db, data), [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    assert.deepEqual(found.hits.map((hit) => ({ index: hit.index, text: hit.text })),
      [{ index: 2, text: "needle old" }, { index: 1, text: "needle new" }]);
    assert.equal(found.more, false);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});

test("history search keeps step numbers across source pages with missing files", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-sources-pages-"));
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    store.db.exec("BEGIN");
    for (let i = 0; i < 140; i++) put.run("one", `source-${i}`, "cc", i, "claude");
    store.db.exec("COMMIT");
    store.setRuntimeSessionId("one", "source-0");
    const home = join(data, "profile"), dir = join(home, "projects", "w");
    mkdirSync(dir, { recursive: true });
    for (const [id, text] of [["source-70", "needle middle"], ["source-139", "needle last"], ["source-0", "needle current"]]) {
      const entry = JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text }] } });
      writeFileSync(join(dir, `${id}.jsonl`), `${entry}\n`);
    }
    const found = await historyHits(makeStore(store.db, data), [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    assert.deepEqual(found.hits.map((hit) => ({ index: hit.index, text: hit.text })),
      [{ index: 2, text: "needle current" }, { index: 1, text: "needle last" }, { index: 0, text: "needle middle" }]);
    assert.equal(found.more, false);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});
