import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { runnerId } from "../src/agents/process.ts";
import { keyPart, sandboxName } from "../src/agents/sandbox-name.ts";
import { runnerSessions } from "../src/jobs/memory.ts";
import { SandboxNameBuilder } from "../src/sessions/sandbox-name-builder.ts";
import { enableSandboxIndex, runnerNameSessions, RUNNER_SESSION_CANDIDATES, sandboxIndexReady, sandboxIndexStep } from "../src/store/sandbox-index.ts";
import { LIVE_SESSIONS, Store } from "../src/store/store.ts";

test("rechecking runner ownership does not read unrelated live sessions", async () => {
  const read: { none: number; one: number }[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let seen = 0, observing = false;
    db.function("runner_session_seen", (_key) => { if (observing) seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql === LIVE_SESSIONS
          ? sql.replace("archived_at IS NULL", "runner_session_seen(key) AND archived_at IS NULL")
          : sql === "SELECT * FROM sessions ORDER BY last_active_at DESC"
            ? sql.replace(" ORDER BY", " WHERE runner_session_seen(key) ORDER BY")
            : sql === RUNNER_SESSION_CANDIDATES
              ? sql.replace("WHERE n.name = ?", "WHERE n.name = ? AND runner_session_seen(s.key)") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
    try {
      const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      const key = "chat:c-1234567890abcdef1234567890";
      put.run(key, "target");
      for (let i = 0; i < unrelated; i++) put.run(`other:${i}`, `token-${i}`);
      Object.defineProperty(store, "db", { value: observed });
      const whose = runnerSessions(store, (runners) => builder.runners(runners));
      const id = runnerId("claude", key);
      assert.equal((await whose([id])).get(id), key); // The first lookup may prepare old sessions.
      await builder.settled();
      observing = true;
      seen = 0;
      assert.equal((await whose([])).get("no-such-runner"), undefined);
      const none = seen;
      seen = 0;
      assert.equal((await whose([id])).get(id), key);
      const one = seen;
      observing = false;
      read.push({ none, one });
    } finally { await builder.close(); store.close(); }
  }
  assert.deepEqual(read, [{ none: 0, one: 1 }, { none: 0, one: 1 }]);
});

test("a new unrelated session does not make a runner reread all sessions", async () => {
  const reads: number[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let seen = 0, observing = false;
    db.function("runner_session_seen", (_key) => { if (observing) seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(
        sql === LIVE_SESSIONS
          ? sql.replace("archived_at IS NULL", "runner_session_seen(key) AND archived_at IS NULL")
          : sql === RUNNER_SESSION_CANDIDATES
            ? sql.replace("WHERE n.name = ?", "WHERE n.name = ? AND runner_session_seen(s.key)") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
    try {
      const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      put.run("target", "target");
      for (let i = 0; i < unrelated; i++) put.run(`other:${i}`, `token-${i}`);
      Object.defineProperty(store, "db", { value: observed });
      const whose = runnerSessions(store, (runners) => builder.runners(runners));
      const id = runnerId("claude", "target");
      assert.equal(whose([id]).get(id), "target");
      await builder.settled();
      put.run("unrelated:new", "new-token"); // Its journal entry has not yet been prepared.
      observing = true;
      assert.equal(whose([id]).get(id), "target");
      observing = false;
      reads.push(seen);
      await builder.settled();
    } finally { await builder.close(); store.close(); }
  }
  assert.deepEqual(reads, [1, 1]);
});

test("runner names use the old live and archived order, including colliding key parts", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
  try {
    const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,archived_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,?,?)`);
    const first = "odd:name", second = keyPart(first), other = "someone-else";
    assert.equal(keyPart(first), keyPart(second));
    put.run(first, "first", 8, null);
    put.run(second, "second", 5, null);
    put.run(other, "other", -1, null);
    const id = runnerId("claude", first);
    const whose = runnerSessions(store, (runners) => builder.runners(runners));
    assert.equal(whose([id]).get(id), second);
    await builder.settled();
    // A collision in the shortened sandbox name alone does not make this other key the runner's session.
    db.prepare("UPDATE sandbox_name_rows SET name = ? WHERE session = ?").run(sandboxName(keyPart(first)), other);
    const matchesOriginal = () => assert.equal(whose([id]).get(id), runnerSessions(store)([id]).get(id));
    matchesOriginal();
    db.prepare("DELETE FROM sessions WHERE key = ?").run(second);
    matchesOriginal(); // A removed colliding key is reflected before its journal entry is prepared.
    await builder.settled();
    put.run(second, "second", 5, null);
    matchesOriginal(); // So is a newly inserted colliding key.
    await builder.settled();
    db.prepare("UPDATE sessions SET last_active_at = 1 WHERE key = ?").run(first);
    matchesOriginal();
    db.prepare("UPDATE sessions SET archived_at = 1 WHERE key = ?").run(first);
    matchesOriginal();
    db.prepare("UPDATE sessions SET archived_at = 1, last_active_at = 1 WHERE key = ?").run(second);
    matchesOriginal();
    // Switching sandbox mode off cannot disable a lookup the memory watch is using.
    await builder.disable();
    assert.equal(db.prepare("SELECT enabled FROM sandbox_name_meta WHERE id = 1").get()?.enabled, 1);
    matchesOriginal();
  } finally { await builder.close(); store.close(); }
});

test("a memory look answers while the previous station still writes, then uses the prepared names", async () => {
  const store = Store.open(":memory:");
  const previous = Promise.withResolvers<void>();
  const builder = new SandboxNameBuilder(store, previous.promise, () => false);
  try {
    const put = store.db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
    put.run("before", "token-before");
    const whose = runnerSessions(store, (runners) => builder.runners(runners));
    assert.equal(whose(["other-unknown"]).get("other-unknown"), undefined);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
    assert.equal(whose([runnerId("claude", "before")]).get(runnerId("claude", "before")), "before");
    put.run("after", "token-after");
    previous.resolve();
    await builder.settled();
    assert.equal(whose([runnerId("claude", "after")]).get(runnerId("claude", "after")), "after");
  } finally { previous.resolve(); await builder.close(); store.close(); }
});

test("a pause between runners does not make their return rebuild historical names", async () => {
  const store = Store.open(":memory:");
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
  try {
    const db = store.db;
    const put = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
    put.run("before", "token-before");
    const whose = runnerSessions(store, (runners) => builder.runners(runners));
    assert.equal(whose([runnerId("claude", "before")]).get(runnerId("claude", "before")), "before");
    await builder.settled();
    assert.equal(db.prepare("SELECT enabled FROM sandbox_name_meta WHERE id = 1").get()?.enabled, 1);
    whose([]);
    await builder.settled();
    assert.equal(db.prepare("SELECT enabled FROM sandbox_name_meta WHERE id = 1").get()?.enabled, 1);
    put.run("later", "token-later");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_dirty").get()?.n, 1);
    whose([]); // Maintain the small journal even while there is no runner to look up.
    await builder.settled();
    assert.equal(db.prepare("SELECT phase FROM sandbox_name_meta WHERE id = 1").get()?.phase, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_dirty").get()?.n, 0);
    const later = runnerId("claude", "later");
    assert.equal(whose([later]).get(later), "later");
  } finally { await builder.close(); store.close(); }
});

test("runner ownership follows a previous station's prepared writes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "memory-runner-old-"));
  const path = join(dir, "store.db");
  const store = Store.open(path), old = new DatabaseSync(path);
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
  try {
    const put = old.prepare(`INSERT OR REPLACE INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,?)`);
    put.run("before", "token", 1);
    const whose = runnerSessions(store, (runners) => builder.runners(runners));
    const before = runnerId("claude", "before"), after = runnerId("claude", "after");
    assert.equal(whose([before]).get(before), "before");
    await builder.settled();
    put.run("after", "token", 2); // Replacement by the old connection removes "before" too.
    assert.equal(whose([after]).get(after), "after"); // The pending journal is reflected immediately.
    await builder.settled();
    assert.equal(whose([before]).get(before), undefined);
    assert.equal(whose([after]).get(after), "after");
  } finally {
    await builder.close();
    old.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a large pending journal keeps the immediate old answer while the worker catches up", async () => {
  const store = Store.open(":memory:");
  const builder = new SandboxNameBuilder(store, Promise.resolve(), () => false);
  try {
    const put = store.db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
    put.run("target", "target");
    const whose = runnerSessions(store, (runners) => builder.runners(runners));
    const id = runnerId("claude", "target");
    assert.equal(whose([id]).get(id), "target");
    await builder.settled();
    for (let i = 0; i < 65; i++) put.run(`new-${i}`, `new-token-${i}`);
    assert.equal(builder.runners([{ id, part: "target" }]), "fallback");
    assert.equal(whose([id]).get(id), "target");
    await builder.settled();
    assert.equal(whose([id]).get(id), "target");
  } finally { await builder.close(); store.close(); }
});

test("runner candidates and pending changes use the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "memory-runner-snapshot-"));
  const path = join(dir, "store.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    const put = old.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
      VALUES (?,'connected','thread','claude','default','.',?,0,?)`);
    const first = "odd:name", second = keyPart(first), id = runnerId("claude", first);
    put.run(first, "first", 8);
    enableSandboxIndex(db);
    while (!sandboxIndexReady(db)) sandboxIndexStep(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!sql.startsWith("SELECT 1 FROM sandbox_name_meta")) return stmt;
        return new Proxy(stmt, { get(statement, part) {
          if (part === "get") return (...args: Parameters<typeof stmt.get>) => {
            const result = statement.get(...args);
            if (!changed) { changed = true; put.run(second, "second", 1); }
            return result;
          };
          const value = Reflect.get(statement, part, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const names = [{ id, part: keyPart(first) }];
    assert.deepEqual(runnerNameSessions(observed, names), new Map([[id, first]]));
    assert.deepEqual(runnerNameSessions(db, names), new Map([[id, second]]));
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
