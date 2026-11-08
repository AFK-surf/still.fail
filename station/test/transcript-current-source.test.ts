import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { transcriptFile } from "../src/read/sessions.ts";
import { makeStore, openStore, runtimeSessionSource, runtimeSessionSources } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("a current transcript lookup does not read a session's other runtime sources", () => {
  const data = mkdtempSync(join(tmpdir(), "transcript-current-source-"));
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES(?,?,?,?,?)");
    store.db.exec("BEGIN");
    for (let i = 0; i < 513; i++) put.run("one", `old-${i}`, "cc", i, "claude");
    put.run("one", "current", "cc", 1000, "claude");
    store.setRuntimeSessionId("one", "current");
    store.db.exec("COMMIT");
    const home = join(data, "profile"), dir = join(home, "projects", "w");
    mkdirSync(dir, { recursive: true });
    const path = join(dir, "current.jsonl"); writeFileSync(path, "");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", home }] }));
    let visited = 0;
    const queries: { sql: string; args: unknown[] }[] = [];
    const db = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!/\bruntime_sessions\b/i.test(sql)) return stmt;
        return new Proxy(stmt, { get(statement, method) {
          const value = Reflect.get(statement, method, statement);
          if (method === "all") return (...args: unknown[]) => {
            const rows = Reflect.apply(value, statement, args) as unknown[]; visited += rows.length; return rows;
          };
          if (method === "get") return (...args: unknown[]) => {
            queries.push({ sql, args });
            const row = Reflect.apply(value, statement, args); if (row !== undefined) visited++; return row;
          };
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(db, data);
    assert.deepEqual(transcriptFile(read, "one", "en"), { path });
    assert.ok(visited <= 2, `read ${visited} runtime sources to locate one current transcript`);
    const point = queries.find((query) => query.sql.includes("r.id = ?2"));
    assert.ok(point);
    const plan = (query: { sql: string; args: unknown[] }) => {
      const stmt = store.db.prepare(`EXPLAIN QUERY PLAN ${query.sql}`);
      return (Reflect.apply(stmt.all, stmt, query.args) as { detail: string }[]).map((row) => row.detail).join("\n");
    };
    assert.match(plan(point), /SEARCH r USING .*\(session_key=\? AND id=\?\)/);
    assert.match(plan(point), /SEARCH x USING .*\(session_key=\? AND id>\? AND id<\?\)/);
    store.setRuntimeSessionId("one", null);
    visited = 0;
    assert.deepEqual(transcriptFile(read, "one", "en"), { path: null });
    assert.equal(visited, 0);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a source lookup agrees with the original reader across current and old identities", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const db = store.db, read = makeStore(db, "/no-station-config");
    const put = db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one',CAST(? AS TEXT),?,?,?)");
    put.run(Buffer.from("target\0old"), "earlier", 1, "codex");
    put.run(Buffer.from("target"), "current", 2, "claude");
    put.run(Buffer.from("\0old"), "empty-prefix", 3, "claude");
    put.run(Buffer.from([0x61, 0xff, 0x62]), "invalid", 4, "codex");
    put.run(Buffer.from("emoji-😀"), "emoji", 5, null);
    db.prepare("UPDATE sessions SET original_runtime='codex' WHERE key='one'").run();
    const sameAsOriginal = (id: string) => assert.deepEqual(runtimeSessionSource(read, "one", id),
      runtimeSessionSources(read, "one").find((source) => source.id === id) ?? null);
    for (const current of ["target", "target\0old", "", "a\ufffdb", "emoji-😀", "missing", null]) {
      store.setRuntimeSessionId("one", current);
      for (const requested of ["target", "target\0old", "", "a\ufffdb", "emoji-😀", "missing", "absent"]) sameAsOriginal(requested);
    }
    db.prepare("UPDATE sessions SET runtime_session_id=CAST(X'0102' AS BLOB) WHERE key='one'").run();
    sameAsOriginal("target");
  } finally { store.close(); }
});

test("a current transcript keeps the original source when old ids decode alike", () => {
  const data = mkdtempSync(join(tmpdir(), "transcript-current-identity-"));
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "current", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const put = store.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one',CAST(? AS TEXT),?,?,'claude')");
    put.run(Buffer.from("target\0old"), "earlier", 1);
    put.run(Buffer.from("target"), "current", 2);
    store.setRuntimeSessionId("one", "target");
    const profiles = ["earlier", "current"].map((id) => ({ id, home: join(data, id) }));
    for (const profile of profiles) {
      const dir = join(profile.home, "projects", "w");
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "target.jsonl"), "");
    }
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles }));
    const read = makeStore(store.db, data);
    const original = runtimeSessionSources(read, "one").find((source) => source.id === "target");
    assert.ok(original);
    const home = profiles.find((profile) => profile.id === original.profile)!.home;
    assert.deepEqual(transcriptFile(read, "one", "en"), { path: join(home, "projects", "w", "target.jsonl") });
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});

test("current source and ambiguity are read from one snapshot during a concurrent write", () => {
  const data = mkdtempSync(join(tmpdir(), "transcript-current-snapshot-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let read: ReturnType<typeof openStore> | undefined;
  try {
    writer.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "before", workspace: "/w", token: "t",
      createdAt: 1, lastActiveAt: 1, ws: "mine" });
    writer.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one','source','before',2,'claude')").run();
    writer.setRuntimeSessionId("one", "source");
    read = openStore(data);
    const expected = runtimeSessionSources(read, "one").find((source) => source.id === "source");
    let changed = false;
    read.db.function("change_source_during_read", () => {
      writer.db.exec("BEGIN");
      writer.db.prepare("UPDATE runtime_sessions SET profile='after' WHERE session_key='one' AND id='source'").run();
      writer.db.prepare("INSERT INTO runtime_sessions(session_key,id,profile,at,runtime) VALUES('one',CAST(? AS TEXT),'earlier',1,'claude')")
        .run(Buffer.from("source\0old"));
      writer.db.exec("COMMIT");
      changed = true;
      return 1;
    });
    const db = new Proxy(read.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql.includes("AS ambiguous")
        ? sql.replace("SELECT s.runtime_session_id", "SELECT change_source_during_read() AS changed, s.runtime_session_id") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(runtimeSessionSource(makeStore(db, data), "one", "source"), expected);
    assert.equal(changed, true);
    assert.deepEqual(runtimeSessionSource(read, "one", "source"),
      runtimeSessionSources(read, "one").find((source) => source.id === "source") ?? null);
  } finally { read?.db.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a source lookup keeps the old schema's fallback", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE sessions(key TEXT PRIMARY KEY, runtime TEXT, profile TEXT, runtime_session_id TEXT, workspace TEXT);
      CREATE TABLE runtime_sessions(session_key TEXT, id TEXT, at INTEGER, PRIMARY KEY(session_key,id));
      INSERT INTO sessions VALUES('one','claude','cc','current','/w');
      INSERT INTO runtime_sessions VALUES('one','old',1)`);
    const read = makeStore(db, "/no-station-config");
    for (const id of ["old", "current", "absent"]) assert.deepEqual(runtimeSessionSource(read, "one", id),
      runtimeSessionSources(read, "one").find((source) => source.id === id) ?? null);
  } finally { db.close(); }
});
