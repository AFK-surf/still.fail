import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { Readers } from "../src/read/pool.ts";
import { makeStore } from "../src/read/store.ts";
import { JOB_NAME_FIRST_LARGE, JOB_NAME_FIRST_PENDING, JOB_NAME_FIRST_ROW, jobNameFirstStep } from "../src/store/job-name-first.ts";
import { Store } from "../src/store/store.ts";

const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member" as const, workspace: "A", device: "dev", home: false };

function fixture(s: Store, count: number): number {
  const add = (key: string, ws: string) => s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
    token: key, ws, createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
  add("a", "A");
  s.insertJob({ id: "job-a", sessionKey: "a", name: "job", command: "true", cwd: "/", port: null, token: "job-a",
    state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
  const t = s.openThreadOf("ember", "CHAT", "shared", "Shared", "ann@x", "a");
  const member = s.db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,?,'ember',?)");
  member.run(t.id, "a", 0);
  for (let i = 0; i < count; i++) { const key = `peer-${i}`; add(key, "B"); member.run(t.id, key, i + 1); }
  return t.id;
}

function prepare(s: Store, thread: number): void {
  let done = false, batches = 0;
  while (!done) { done = jobNameFirstStep(s.db, "a", thread).done; assert.ok(++batches < 1000); }
}

for (const count of [40, 400, 4000]) test(`job name reads bounded members with ${count} peers`, () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, count);
    let visited = 0, selected = 0, full = 0;
    s.db.function("job_member_visit", (_rowid: unknown) => { visited++; return 1; });
    s.db.function("job_member_selected", (_rowid: unknown) => { selected++; return 1; });
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === JOB_NAME_FIRST_LARGE) return target.prepare("SELECT 1 FROM thread_sessions WHERE thread=? AND job_member_visit(rowid)=1 LIMIT 1 OFFSET 64");
        if (sql === JOB_NAME_FIRST_ROW) return target.prepare(sql + " AND job_member_selected(m.rowid)=1");
        const statement = target.prepare(sql);
        if (sql !== "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid") return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "all") return (...args: any[]) => { const rows = stmt.all(...args); full += rows.length; return rows; };
          const value = Reflect.get(stmt, method, stmt); return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target); return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, ".");
    if (count > 64) {
      assert.throws(() => openJobs(reader, viewer, "en"), (error: any) => error.status === 503 && error.message.startsWith(JOB_NAME_FIRST_PENDING));
      assert.equal(visited, 65); assert.equal(full, 0);
      prepare(s, thread); visited = 0;
    }
    assert.deepEqual(openJobs(reader, viewer, "en")[0]?.chat, { id: "a", title: "Shared", archived: false });
    assert.equal(visited, Math.min(count + 1, 65));
    assert.equal(full, count > 64 ? 0 : count + 1);
    assert.equal(selected, count > 64 ? 1 : 0);
  } finally { s.close(); }
});

test("a changed first member and a dirty summary retain workspace and archive behavior", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 100), reader = makeStore(s.db, ".");
    prepare(s, thread);
    assert.equal(openJobs(reader, viewer, "en")[0]?.chat?.title, "Shared");
    s.db.prepare("UPDATE thread_sessions SET joined_at=-1 WHERE thread=? AND session='peer-0'").run(thread);
    assert.equal(openJobs(reader, viewer, "en")[0]?.chat, undefined);
    s.db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='peer-0'").run(thread);
    assert.throws(() => openJobs(reader, viewer, "en"), (error: any) => error.status === 503 && error.message.startsWith(JOB_NAME_FIRST_PENDING));
    prepare(s, thread);
    assert.equal(openJobs(reader, viewer, "en")[0]?.chat?.title, "Shared");
    s.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='a'").run();
    assert.notEqual(openJobs(reader, viewer, "en")[0]?.chat?.title, "Shared");
  } finally { s.close(); }
});

test("a first raw membership decoding to the job session keeps the same title", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 100), reader = makeStore(s.db, ".");
    s.db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,CAST(X'610078' AS TEXT),'ember',-1)").run(thread);
    prepare(s, thread);
    assert.deepEqual(openJobs(reader, viewer, "en")[0]?.chat, { id: "a", title: "Shared", archived: false });
  } finally { s.close(); }
});

test("a reader waits for the first-member builder and returns the job", { timeout: 30_000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "job-name-first-reader-")), s = Store.open(join(dir, "stillfail.db"));
  const readers = new Readers(dir, 1);
  try {
    const thread = fixture(s, 100);
    const jobs = JSON.parse(await readers.read("openJobs", { viewer, lang: "en" }, "en"));
    assert.deepEqual(jobs[0]?.chat, { id: "a", title: "Shared", archived: false });
    assert.equal(s.db.prepare("SELECT ready FROM job_name_first WHERE owner=? AND thread=?").get("a", thread)?.ready, 1);
  } finally { readers.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
