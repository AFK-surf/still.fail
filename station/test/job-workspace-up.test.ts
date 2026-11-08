import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { makeStore, seenBy } from "../src/read/store.ts";
import { JOBS_UP } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

const viewer = (home: boolean) => ({ sub: "a@example.test", email: "a@example.test", name: "A", role: "member",
  workspace: "A", home, device: "dev" } as const);
const session = (s: Store, key: string, ws: string | null) => s.insertSession({ key, connect: "ember", runtime: "claude",
  profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws });
const job = (s: Store, id: string, key: string, state: string, port: number | null, at = 10) => s.insertJob({
  id, sessionKey: key, name: id, command: "true", cwd: "/", port, token: id, state, pgid: null,
  exitCode: null, startedAt: at, endedAt: null, restarts: 0, log: "/dev/null", watch: false,
});

for (const home of [false, true]) test(`job lists read only the viewer's workspace (home ${home})`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "visible", "A"); session(s, "home", null); session(s, "elsewhere", "B");
    job(s, "visible-running", "visible", "running", null);
    job(s, "visible-service", "visible", "exited", 3300);
    job(s, "visible-finished", "visible", "exited", null);
    job(s, "home-running", "home", "running", 3400);
    job(s, "missing-running", "missing", "running", null);
    job(s, "other-running", "elsewhere", "running", null);
    for (let i = 0; i < 400; i++) {
      const key = `away-${i}`;
      session(s, key, "B");
      job(s, `job-${key}`, key, i % 2 ? "exited" : "running", i % 2 ? 4000 + i : null, i % 3 ? i : 10);
    }
    const raw = s.db.prepare(JOBS_UP).all() as Array<{ id: string; session_key: string }>;
    const canSee = seenBy(makeStore(s.db, "."), viewer(home), raw.map((r) => r.session_key));
    const expected = raw.filter((r) => canSee(r.session_key)).map((r) => r.id);
    assert.ok(expected.includes("visible-running") && expected.includes("visible-service"));
    assert.equal(expected.includes("home-running"), home);
    assert.equal(expected.includes("missing-running"), home);
    assert.ok(!expected.includes("visible-finished") && !expected.includes("other-running"));

    const returned: string[] = [];
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!/\bFROM\s+jobs\b/i.test(sql)) return statement;
        return new Proxy(statement, { get(stmt, method) {
          const value = Reflect.get(stmt, method, stmt);
          if (method === "all") return (...args: any[]) => {
            const rows = value.apply(stmt, args);
            for (const row of rows) if (typeof row.session_key === "string") returned.push(row.session_key);
            return rows;
          };
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer(home), "en", false).map((r) => r.id), expected);
    assert.deepEqual(returned.filter((key) => key === "elsewhere" || key.startsWith("away-")), []);
  } finally { s.close(); }
});

test("job lists retain their workspace semantics without the workspace index", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a", "A"); session(s, "b", "B");
    job(s, "ja", "a", "running", null); job(s, "jb", "b", "running", null);
    s.db.exec("DROP INDEX sessions_ws");
    assert.deepEqual(openJobs(makeStore(s.db, "."), viewer(false), "en", false).map((r) => r.id), ["ja"]);
  } finally { s.close(); }
});

test("job lists keep JavaScript workspace visibility for unusual stored identities", () => {
  const s = Store.open(":memory:");
  try {
    for (const [key, ws] of [["plain", "A"], ["nul-workspace", "A\0B"], ["replacement", "\uFFFD"],
      ["invalid-workspace", "temporary"], ["key", "B"], ["key\0tail", "A"],
      ["bad\uFFFD", "B"], ["invalid-key", "A"]] as const) {
      session(s, key, ws);
      job(s, `job-${key}`, key, "running", null);
    }
    // Old writers may have stored text bytes that JavaScript cannot represent directly.
    s.db.exec(`UPDATE sessions SET ws=CAST(x'80' AS TEXT) WHERE key='invalid-workspace';
      UPDATE sessions SET key=CAST(x'62616480' AS TEXT) WHERE key='invalid-key';
      UPDATE jobs SET session_key=CAST(x'62616480' AS TEXT) WHERE id='job-invalid-key';`);
    for (const workspace of ["A", "A\0B", "B", "\uFFFD", "\uD800"]) for (const home of [false, true]) {
      const who = { ...viewer(home), workspace };
      const raw = s.db.prepare(JOBS_UP).all() as Array<{ id: string; session_key: string }>;
      const canSee = seenBy(makeStore(s.db, "."), who, raw.map((r) => r.session_key));
      const expected = raw.filter((r) => canSee(r.session_key)).map((r) => r.id);
      assert.deepEqual(openJobs(makeStore(s.db, "."), who, "en", false).map((r) => r.id), expected,
        `workspace ${JSON.stringify(workspace)}, home ${home}`);
    }
  } finally { s.close(); }
});

test("job selection and workspace visibility share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-workspace-up-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(s, "a", "A"); session(s, "b", "B");
    job(s, "ja", "a", "running", null); job(s, "jb", "b", "running", null);
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT j.* FROM jobs j LEFT JOIN sessions")) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "all") return (...args: any[]) => {
            const rows = stmt.all(...args);
            if (!changed) {
              writer.exec("UPDATE sessions SET ws=CASE key WHEN 'a' THEN 'B' ELSE 'A' END WHERE key IN ('a','b')");
              changed = true;
            }
            return rows;
          };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    reader.db.exec("BEGIN");
    try {
      assert.deepEqual(openJobs(reader, viewer(false), "en", false).map((r) => r.id), ["ja"]);
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.deepEqual(openJobs(reader, viewer(false), "en", false).map((r) => r.id), ["jb"]);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an old sessions table without a workspace belongs to the home workspace", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE sessions(key TEXT PRIMARY KEY);
      CREATE TABLE jobs(id TEXT, session_key TEXT, name TEXT, command TEXT, cwd TEXT, port INTEGER, token TEXT,
        state TEXT, pgid INTEGER, exit_code INTEGER, started_at INTEGER, ended_at INTEGER, restarts INTEGER, log TEXT, watch INTEGER);
      CREATE TABLE job_notices(job_id TEXT, at INTEGER, text TEXT);
      INSERT INTO sessions VALUES ('a');
      INSERT INTO jobs VALUES ('ja', 'a', 'job', 'true', '/', NULL, 'token', 'running', NULL, NULL, 1, NULL, 0, '/dev/null', 0);`);
    assert.deepEqual(openJobs(makeStore(db, "."), viewer(true), "en", false).map((r) => r.id), ["ja"]);
    assert.deepEqual(openJobs(makeStore(db, "."), viewer(false), "en", false), []);
  } finally { db.close(); }
});
