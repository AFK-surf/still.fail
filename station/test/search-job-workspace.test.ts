import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import type { DatabaseSync } from "node:sqlite";
import { makeStore, openStore } from "../src/read/store.ts";
import { JOB_SCOPE_NUL_WORKSPACES, JOB_SCOPE_SESSIONS, smallJobScope } from "../src/search/job-scope.ts";
import { pick, type Asker } from "../src/search/match.ts";
import { Search } from "../src/search/search.ts";
import { stationDocs, stationDocSteps } from "../src/search/sources.ts";
import { auditSessionListStep, sessionListStep } from "../src/store/session-list-index.ts";
import { Store } from "../src/store/store.ts";

function audit(db: DatabaseSync): void {
  let batches = 0;
  while (!auditSessionListStep(db, 64).done) assert.ok(++batches < 20);
}

test("job search does not visit every other workspace's session with a job", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    const add = (key: string, ws: string | null) => writer.insertSession({ key, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws });
    const job = db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
      VALUES(?,?,'needle','run','/work',?,'exited',1,'')`);
    for (const [key, ws] of [["mine", "mine"], ["public", "*"], ["default", null]] as const) {
      add(key, ws); job.run(`job-${key}`, key, `job-${key}`);
    }
    for (let i = 0; i < 400; i++) {
      const key = `away-${String(i).padStart(4, "0")}`;
      add(key, "away"); job.run(`job-${key}`, key, `job-${key}`);
    }
    audit(db);
    const visited = new Set<unknown>();
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        return new Proxy(statement, { get(stmt, method) {
          const value = Reflect.get(stmt, method, stmt);
          if (typeof value !== "function") return value;
          if (method === "get" && sql === "SELECT * FROM sessions WHERE key = ?") return (...args: unknown[]) => {
            visited.add(args[0]);
            return Reflect.apply(value, stmt, args);
          };
          return value.bind(stmt);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const original = makeStore(db, "."), read = makeStore(traced, ".");
    for (const home of [false, true]) {
      const asker: Asker = { workspace: "mine", home, scopes: ["write"] };
      const options = { limit: 10 };
      const expected = pick(stationDocs(original, ".", {}, new Set(["job"])), ["needle"], asker, options);
      const actual = pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker, options);
      assert.deepEqual(actual, expected);
      assert.deepEqual(actual.flatMap((group) => group.hits.map((hit) => hit.job)).sort(),
        (home ? ["job-default", "job-mine", "job-public"] : ["job-mine", "job-public"]).sort());
      assert.ok(visited.size <= 66, `visited ${visited.size} sessions with only ${home ? 3 : 2} visible`);
      visited.clear();
    }
  } finally { writer.close(); }
});

test("a small job scope is bounded, includes default and public sessions, and falls back when incomplete", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    const add = (key: string, ws: string | null) => writer.insertSession({ key, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (let i = 0; i < 62; i++) add(`own-${String(i).padStart(3, "0")}`, "mine");
    add("public", "*"); add("default", null);
    audit(db);
    const asker: Asker = { workspace: "mine", home: true, scopes: [] };
    const keys = smallJobScope(db, asker, "zzzz");
    assert.equal(keys?.length, 64);
    assert.ok(keys?.includes("public"));
    assert.ok(keys?.includes("default"));
    add("one-too-many", "mine");
    assert.equal(smallJobScope(db, asker, "zzzz"), null);
    db.prepare("DELETE FROM sessions WHERE key = 'one-too-many'").run();
    db.exec("UPDATE session_list_meta SET complete = 0 WHERE id = 1");
    assert.equal(smallJobScope(db, asker, "zzzz"), null);
    db.exec("UPDATE session_list_meta SET version = 2, complete = 1 WHERE id = 1");
    assert.equal(smallJobScope(db, asker, "zzzz"), null);
    for (const [sql, args] of [[JOB_SCOPE_SESSIONS, [1, "mine", 65]], [JOB_SCOPE_NUL_WORKSPACES, ["mine", 65]]] as const) {
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[])
        .map((row) => row.detail).join("\n");
      assert.match(plan, /SEARCH session_list_rows USING (?:COVERING INDEX|PRIMARY KEY)/);
      assert.doesNotMatch(plan, /USE TEMP B-TREE|SCAN session_list_rows/);
    }
  } finally { writer.close(); }
});

test("a large or unusual scope does not start an audit it cannot use", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    const add = (key: string) => writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    for (let i = 0; i < 65; i++) add(`s${i}`);
    const asker: Asker = { workspace: "mine", home: false, scopes: [] };
    let pending = 0;
    assert.equal(smallJobScope(db, asker, "zzzz", () => pending++), null);
    assert.equal(pending, 0);
    db.prepare("DELETE FROM sessions WHERE key=?").run("s64");
    assert.equal(smallJobScope(db, asker, "zzzz", () => pending++), null);
    assert.equal(pending, 1);
    add("nul\0key");
    db.prepare("DELETE FROM sessions WHERE key=?").run("s63");
    assert.equal(smallJobScope(db, asker, "zzzz", () => pending++), null);
    assert.equal(pending, 1);
  } finally { writer.close(); }
});

test("a workspace with a NUL suffix keeps the visibility seen by JavaScript", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    const add = (key: string, ws: string) => {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
      db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
        VALUES(?,?,'needle','run','/work',?,'exited',1,'')`).run(`job-${key}`, key, `job-${key}`);
    };
    add("mine", "mine"); add("mine-nul", "mine\0different"); add("public-nul", "*\0different"); add("other", "away");
    audit(db);
    const asker: Asker = { workspace: "mine", home: false, scopes: [] }, read = makeStore(db, ".");
    assert.deepEqual(smallJobScope(db, asker, "zzzz"), ["mine", "mine-nul", "public-nul"]);
    const actual = pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker);
    assert.deepEqual(actual, pick(stationDocs(read, ".", {}, new Set(["job"])), ["needle"], asker));
    assert.deepEqual(actual.flatMap((group) => group.hits.map((hit) => hit.session)).sort(), ["mine", "mine-nul", "public-nul"]);
  } finally { writer.close(); }
});

test("unusual job-session identities keep the original search behavior", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    let sequence = 0;
    const add = (key: string, ws: string) => {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
      db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
        VALUES(?,?,'needle','run','/work',?,'exited',1,'')`).run(`job-${sequence}`, key, `job-${sequence++}`);
    };
    add("plain", "mine"); add("null\0key", "mine"); add("null", "away"); add("é", "mine"); add("other", "工作区");
    audit(db);
    const read = makeStore(db, ".");
    for (const workspace of ["mine", "away", "工作区"]) {
      const asker: Asker = { workspace, home: false, scopes: [] };
      if (workspace === "away") assert.deepEqual(smallJobScope(db, asker, "zzzz"), ["null"]);
      else assert.equal(smallJobScope(db, asker, "zzzz"), null);
      const actual = pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker);
      assert.deepEqual(actual, pick(stationDocs(read, ".", {}, new Set(["job"])), ["needle"], asker));
      assert.deepEqual(actual.flatMap((group) => group.hits.map((hit) => hit.session)).sort(),
        (workspace === "mine" ? ["plain", "null\0key", "é"] : workspace === "away" ? ["null"] : ["other"]).sort());
    }
  } finally { writer.close(); }
});

test("job search keeps an old NUL session after the session list is prepared", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    for (const [key, ws] of [["old\0key", "mine"], ["zz", "away"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
      db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
        VALUES(?,?,'needle','run','/work',?,'exited',1,'')`).run(key, key, key);
    }
    // Simulate the old rows present when an index was installed on an existing database.
    db.exec(`DELETE FROM session_list_rows; UPDATE session_list_meta SET complete = 0, last_rowid = NULL,
      end_rowid = (SELECT MAX(rowid) FROM sessions) WHERE id = 1`);
    while (!sessionListStep(db, 1).done) {}
    // A version-1 list may already have completed under the old, truncating backfill.
    db.prepare("DELETE FROM session_list_rows WHERE session = ?").run("old\0key");
    const read = makeStore(db, "."), asker: Asker = { workspace: "mine", home: false, scopes: [] };
    const expected = pick(stationDocs(read, ".", {}, new Set(["job"])), ["needle"], asker);
    assert.deepEqual(expected.flatMap((group) => group.hits.map((hit) => hit.session)), ["old\0key"]);
    assert.deepEqual(pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker), expected);
    audit(db);
    assert.ok(db.prepare("SELECT 1 FROM session_list_rows WHERE session = ?").get("old\0key"));
    assert.deepEqual(pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker), expected);
  } finally { writer.close(); }
});

test("the last job session may contain NUL or invalid UTF-8 without repeating the cursor", () => {
  const writer = Store.open(":memory:"), db = writer.db;
  try {
    for (const [key, ws] of [["tail", "away"], ["tail\0last", "mine"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const job = db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
      VALUES(?,?,'needle','run','/work',?,'exited',1,'')`);
    job.run("prefix", "tail", "prefix"); job.run("nul", "tail\0last", "nul");
    const asker: Asker = { workspace: "mine", home: false, scopes: [] }, read = makeStore(db, ".");
    const verify = () => {
      const steps = stationDocSteps(read, ".", {}, new Set(["job"]), asker), docs = [];
      let done = false;
      for (let i = 0; i < 15 && !done; i++) {
        const step = steps.next(); done = !!step.done;
        if (!step.done && step.value) docs.push(step.value);
      }
      assert.ok(done, "every distinct job-session cursor advances");
      assert.deepEqual(pick(docs, ["needle"], asker).flatMap((group) => group.hits.map((hit) => hit.session)), ["tail\0last"]);
    };
    verify();
    db.exec(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
      VALUES('bad',CAST(X'FF' AS TEXT),'needle','run','/work','bad','exited',1,'')`);
    verify();
  } finally { writer.close(); }
});

test("scope readiness and candidate sessions share a snapshot, then visibility is checked again", () => {
  const data = mkdtempSync(join(tmpdir(), "search-job-scope-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let reader: ReturnType<typeof openStore> | undefined;
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    writer.db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
      VALUES('job','s','needle','run','/work','job','exited',1,'')`).run();
    audit(writer.db);
    reader = openStore(data);
    let moved = false;
    const traced = new Proxy(reader.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        return new Proxy(stmt, { get(statement, method) {
          const value = Reflect.get(statement, method, statement);
          if (typeof value !== "function") return value;
          if (method === "get" && sql.startsWith("SELECT version, complete FROM session_list_meta")) return (...args: unknown[]) => {
            const result = Reflect.apply(value, statement, args);
            if (!moved) { moved = true; writer.db.prepare("UPDATE sessions SET ws = 'away' WHERE key = 's'").run(); }
            return result;
          };
          return value.bind(statement);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const asker: Asker = { workspace: "mine", home: false, scopes: [] };
    assert.deepEqual(pick(stationDocs({ ...reader, db: traced }, data, {}, new Set(["job"]), asker), ["needle"], asker), []);
    assert.ok(moved);
    assert.deepEqual(smallJobScope(reader.db, asker, "z"), []);
    reader.db.exec("BEGIN");
    try { assert.deepEqual(smallJobScope(reader.db, asker, "z"), []); }
    finally { reader.db.exec("ROLLBACK"); }
  } finally { reader?.db.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("job search uses the old path during handover and prepares the session list in the background", async () => {
  const data = mkdtempSync(join(tmpdir(), "search-job-prepare-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const previous = Promise.withResolvers<void>();
  const search = new Search({ data, backfill: { previousGone: previous.promise } });
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    writer.db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log)
      VALUES('job','s','needle','run','/work','job','exited',1,'')`).run();
    writer.db.exec(`DELETE FROM session_list_rows; UPDATE session_list_meta SET complete = 0, last_rowid = NULL,
      end_rowid = (SELECT MAX(rowid) FROM sessions) WHERE id = 1`);
    search.start();
    const asker: Asker = { workspace: "mine", home: false, scopes: [] };
    const query = async () => (await search.query("needle", asker, { kinds: ["job"] }))
      .groups.flatMap((group) => group.hits.map((hit) => hit.job));
    assert.deepEqual(await query(), ["job"]);
    assert.equal(writer.db.prepare("SELECT complete FROM session_list_meta WHERE id = 1").get()?.complete, 0);
    previous.resolve();
    const until = Date.now() + 10_000;
    while (writer.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_job_session_audit'").get() === undefined ||
      writer.db.prepare("SELECT complete FROM search_job_session_audit WHERE id = 1").get()?.complete !== 1) {
      if (Date.now() >= until) throw new Error("the session list did not finish preparing");
      await delay(10);
    }
    assert.deepEqual(await query(), ["job"]);
  } finally {
    previous.resolve();
    await search.stop();
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});
