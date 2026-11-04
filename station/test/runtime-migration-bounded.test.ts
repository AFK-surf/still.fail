import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, ORIGINAL_RUNTIME_ORDERED, originalRuntime, runtimeSessionSources, sessionOfRuntime } from "../src/read/store.ts";
import { addRuntimeSessionRuntime } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("opening an old runtime history adds its fields without rewriting the history", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, runtime TEXT NOT NULL);
      CREATE TABLE runtime_sessions (session_key TEXT NOT NULL, id TEXT NOT NULL, profile TEXT, at INTEGER NOT NULL,
        PRIMARY KEY (session_key, id));
      INSERT INTO sessions VALUES ('s', 'claude');
      INSERT INTO runtime_sessions VALUES ('s', 'old', 'cc', 1);`);
    db.setAuthorizer((action, table) => action === constants.SQLITE_UPDATE && table === "runtime_sessions"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.doesNotThrow(() => addRuntimeSessionRuntime(db)); }
    finally { db.setAuthorizer(null); }
    assert.equal((db.prepare("SELECT runtime FROM runtime_sessions WHERE session_key = 's' AND id = 'old'").get() as { runtime: string | null }).runtime, null);
  } finally { db.close(); }
});

test("old runtime records remain readable after switching runtimes without filling them", () => {
  const dir = mkdtempSync(join(tmpdir(), "runtime-history-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    store.setRuntimeSessionId("s", "old");
    store.ranIn("s", "old", "cc");
    store.close();
    const old = new DatabaseSync(path);
    old.exec("DROP TRIGGER sessions_original_runtime; DROP INDEX IF EXISTS runtime_sessions_ordered; ALTER TABLE runtime_sessions DROP COLUMN runtime; ALTER TABLE sessions DROP COLUMN original_runtime");
    old.close();
    store = Store.open(path);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'runtime_sessions_ordered'").get(), undefined,
      "startup does not build an index over the old runtime history");
    assert.equal((store.db.prepare("SELECT runtime FROM runtime_sessions WHERE session_key = 's' AND id = 'old'").get() as { runtime: string | null }).runtime, null);
    const reader = makeStore(store.db, dir);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "runtime_sessions"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.equal(originalRuntime(reader, "s"), "claude");
      store.setSessionRuntime("s", "codex", "cx", false, null, null, null, null);
    } finally { store.db.setAuthorizer(null); }
    assert.deepEqual(store.runtimeSessionSources("s"), [{ id: "old", runtime: "claude", profile: "cc" }]);
    assert.deepEqual(runtimeSessionSources(reader, "s"), [{ id: "old", runtime: "claude", profile: "cc" }]);
    assert.equal(store.sessionOfRuntime("claude", "old")?.key, "s");
    assert.equal(store.sessionOfRuntime("codex", "old"), null);
    assert.equal(sessionOfRuntime(reader, "claude", "old"), "s");
    assert.equal(sessionOfRuntime(reader, "codex", "old"), null);
    assert.equal(originalRuntime(reader, "s"), "claude");
    store.setRuntimeSessionId("s", "new");
    store.ranIn("s", "new", "cx");
    store.close();
    store = Store.open(path);
    assert.deepEqual(store.runtimeSessionSources("s").map((source) => [source.id, source.runtime]), [["old", "claude"], ["new", "codex"]]);
    assert.equal(originalRuntime(makeStore(store.db, dir), "s"), "claude");
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a previous writer changing an old session keeps its original runtime", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    store.setRuntimeSessionId("s", "old");
    store.ranIn("s", "old", "cc");
    store.db.prepare("UPDATE runtime_sessions SET runtime = NULL WHERE session_key = ?").run("s");
    store.db.prepare("UPDATE sessions SET runtime = ? WHERE key = ?").run("codex", "s");
    const reader = makeStore(store.db, ".");
    assert.equal(originalRuntime(reader, "s"), "claude");
    assert.deepEqual(runtimeSessionSources(reader, "s"), [{ id: "old", runtime: "claude", profile: "cc" }]);
    assert.equal(sessionOfRuntime(reader, "claude", "old"), "s");
    assert.equal(sessionOfRuntime(reader, "codex", "old"), null);
    store.db.prepare("UPDATE sessions SET runtime = ? WHERE key = ?").run("claude", "s");
    assert.equal(originalRuntime(reader, "s"), "claude");
  } finally { store.close(); }
});

test("a session switched by the previous station keeps its first runtime during handover and later switches", () => {
  const dir = mkdtempSync(join(tmpdir(), "runtime-switched-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    store.setRuntimeSessionId("s", "old");
    store.ranIn("s", "old", "cc");
    store.setSessionRuntime("s", "codex", "cx", false, null, null, null, null);
    store.setRuntimeSessionId("s", "new");
    store.ranIn("s", "new", "cx");
    store.close();

    // The preceding version remembered a runtime on each transcript and built this index, but had no session field.
    const old = new DatabaseSync(path);
    old.exec("DROP TRIGGER sessions_original_runtime; ALTER TABLE sessions DROP COLUMN original_runtime; CREATE INDEX runtime_sessions_ordered ON runtime_sessions (session_key, at)");
    const reader = makeStore(old, dir);
    assert.deepEqual(runtimeSessionSources(reader, "s").map((source) => [source.id, source.runtime]), [["old", "claude"], ["new", "codex"]]);
    assert.equal(originalRuntime(reader, "s"), "claude");
    assert.equal(sessionOfRuntime(reader, "claude", "old"), "s");
    assert.equal(sessionOfRuntime(reader, "codex", "old"), null);
    old.close();

    store = Store.open(path);
    const upgraded = makeStore(store.db, dir);
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${ORIGINAL_RUNTIME_ORDERED}`).all("s") as { detail: string }[]).map((row) => row.detail);
    assert.ok(plan.some((step) => step.includes("SEARCH r USING INDEX runtime_sessions_ordered")), plan.join(" | "));
    assert.ok(!plan.some((step) => step.startsWith("SCAN ") || step.includes("TEMP B-TREE")), plan.join(" | "));
    assert.equal(originalRuntime(upgraded, "s"), "claude");
    // A still-running previous station does not know the new session field.
    store.db.prepare("UPDATE sessions SET runtime = ? WHERE key = ?").run("claude", "s");
    assert.equal((store.db.prepare("SELECT original_runtime FROM sessions WHERE key = 's'").get() as { original_runtime: string }).original_runtime, "claude");
    assert.deepEqual(store.runtimeSessionSources("s").map((source) => [source.id, source.runtime]), [["old", "claude"], ["new", "codex"]]);
    assert.equal(originalRuntime(upgraded, "s"), "claude");
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
