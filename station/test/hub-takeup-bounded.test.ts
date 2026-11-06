import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { runnerId } from "../src/agents/process.ts";
import { keyPart } from "../src/agents/sandbox-name.ts";
import { runtimeNamed } from "../src/sessions/config.ts";
import { SandboxNameBuilder } from "../src/sessions/sandbox-name-builder.ts";
import { enableSandboxIndex, runnerTakeUpSessions, sandboxIndexReady, sandboxIndexStep } from "../src/store/sandbox-index.ts";
import { type SessionRow, Store } from "../src/store/store.ts";
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

const add = `INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,running,created_at,last_active_at,archived_at)
  VALUES (?,'cl','thread',?,'cc','/workspace',?,?,0,?,?)`;
const takenBy = (rows: SessionRow[], runners: Set<string>) => rows.filter((row) => {
  const runtime = runtimeNamed(row.runtime);
  return runtime !== null && (runtime === "codex" ? row.running : runners.has(runnerId(runtime, row.key)));
}).map((row) => row.key);
const finish = (db: DatabaseSync) => { while (!sandboxIndexReady(db)) sandboxIndexStep(db, 64); };

test("takeup keeps all colliding runner names, running Codex sessions and old activity order as sessions change", async () => {
  const r = new Rig(), db = r.store.db, insert = db.prepare(add);
  const first = "a:b", second = keyPart(first);
  assert.equal(keyPart(second), keyPart(first));
  const runners = new Set([runnerId("claude", first), "unknown-runner"]);
  try {
    insert.run(first, "claude", first, 0, 10, null);
    insert.run("codex", "codex", "codex", 1, 10, 1);
    insert.run("idle-codex", "codex", "idle-codex", 0, 20, null);
    enableSandboxIndex(db);
    finish(db);
    insert.run(second, "claude", second, 0, 10, 1); // A colliding key still in the journal.
    const parts = [keyPart(first)];
    const check = () => {
      const rows = runnerTakeUpSessions(db, parts);
      assert.notEqual(rows, null);
      assert.deepEqual(takenBy(rows!, runners), takenBy(r.store.listSessions(), runners));
    };
    check();
    assert.deepEqual(takenBy(runnerTakeUpSessions(db, parts)!, runners), [first, "codex", second]);
    db.exec(`UPDATE sessions SET rowid = 9007199254740993 WHERE key = '${first}'`);
    check(); // SQLite keeps equal-time ordering even for rowids beyond JavaScript's safe integers.
    db.prepare("UPDATE sessions SET runtime = 'dsh', last_active_at = 30 WHERE key = ?").run(second);
    check(); // Runtime and activity changes need no name-journal write.
    db.prepare("DELETE FROM sessions WHERE key = ?").run(first);
    check(); // A stale indexed name cannot resurrect its removed session.
    db.prepare("UPDATE sessions SET runtime = 'claude' WHERE key = ?").run(second);
    check();
    const hub = r.newHub({ chats: () => undefined, internal: false, runners: [...runners] });
    const actual: string[] = [];
    (hub as any).adoptOne = async (row: SessionRow) => { actual.push(row.key); };
    try { await hub.takeUp(); assert.deepEqual(actual, takenBy(r.store.listSessions(), runners)); }
    finally { await hub.shutdown(); }
    for (let i = 0; i < 65; i++) insert.run(`new-${i}`, "claude", `new-${i}`, 0, i, null);
    assert.equal(runnerTakeUpSessions(db, parts), null);
    finish(db);
    check();
  } finally { await r.close(); }
});

test("takeup answers immediately during handover and prepares old runner names afterwards", async () => {
  const dir = mkdtempSync(join(tmpdir(), "takeup-handover-")), path = join(dir, "store.db");
  const store = Store.open(path), previous = Promise.withResolvers<void>();
  const builder = new SandboxNameBuilder(store, previous.promise);
  try {
    store.db.prepare(add).run("one", "claude", "one", 0, 1, null);
    assert.equal(builder.takeUp([keyPart("one")]), "fallback");
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'sandbox_name_meta'").get(), undefined);
    previous.resolve();
    await builder.settled();
    const rows = builder.takeUp([keyPart("one")]);
    assert.notEqual(rows, "fallback");
    assert.deepEqual((rows as SessionRow[]).map((row) => row.key), ["one"]);
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("takeup reads names, pending keys and session rows from one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "takeup-snapshot-")), path = join(dir, "store.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    db.prepare(add).run("session", "claude", "token", 0, 1, null);
    enableSandboxIndex(db);
    finish(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT 1 FROM sandbox_name_meta")) return statement;
        return new Proxy(statement, { get(stmt, part) {
          if (part === "get") return (...args: Parameters<typeof statement.get>) => {
            const result = stmt.get(...args);
            if (!changed) { changed = true; old.prepare("DELETE FROM sessions WHERE key = ?").run("session"); }
            return result;
          };
          const value = Reflect.get(stmt, part, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(runnerTakeUpSessions(observed, [keyPart("session")])?.map((row) => row.key), ["session"]);
    assert.deepEqual(runnerTakeUpSessions(db, [keyPart("session")])?.map((row) => row.key), []);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
