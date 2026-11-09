import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { pick, pickAsync, type Asker, type Doc } from "../src/search/match.ts";
import { jobDocs, stationDocs, stationDocSteps } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

const asker: Asker = { workspace: "mine", home: false, scopes: ["write"] };

test("job search reads sessions and one session's jobs in bounded, cancellable batches", async () => {
  const store = Store.open(":memory:");
  try {
    const addSession = (key: string, ws: string) => store.insertSession({
      key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
      token: `session-${key}`, createdAt: 1, lastActiveAt: 1, ws,
    });
    addSession("a", "mine");
    for (let i = 0; i < 600; i++) addSession(`other-${String(i).padStart(4, "0")}`, "other");
    const addJob = store.db.prepare(`INSERT INTO jobs (id, session_key, name, command, cwd, token, state, started_at, log)
      VALUES (?, ?, ?, 'run needle', '/w', ?, 'exited', ?, '')`);
    store.db.exec("BEGIN");
    for (let i = 0; i < 1_024; i++) addJob.run(`j${i}`, "a", `job ${i}`, `job-token-${i}`, i % 7);
    addJob.run("private", "other-0000", "other job", "private-token", 100);
    store.db.exec("COMMIT");
    // The original job-index walk remains the fallback while the session list is still being prepared.
    store.db.exec("UPDATE session_list_meta SET complete = 0 WHERE id = 1");

    let largestSessions = 0;
    let largestJobs = 0;
    const sessionLookups: string[] = [];
    const jobReads: { sql: string; args: unknown[] }[] = [];
    const candidates: { sql: string; args: unknown[] }[] = [];
    const traced = new Proxy(store.db, {
      get(target, prop) {
        if (prop === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(stmt, method) {
              const value = Reflect.get(stmt, method, stmt);
              if (typeof value !== "function") return value;
              if (method === "get" && /SELECT \* FROM sessions WHERE key = \?/i.test(sql)) return (...args: unknown[]) => {
                sessionLookups.push(String(args[0]));
                return Reflect.apply(value, stmt, args);
              };
              if (method === "get" && /SELECT session_key, CAST\(session_key AS BLOB\)/i.test(sql) && /WHERE session_key/i.test(sql)) return (...args: unknown[]) => {
                candidates.push({ sql, args });
                return Reflect.apply(value, stmt, args);
              };
              if (method === "all") return (...args: unknown[]) => {
                const rows = Reflect.apply(value, stmt, args) as unknown[];
                if (/\bFROM sessions\b/i.test(sql)) largestSessions = Math.max(largestSessions, rows.length);
                if (/\bFROM jobs\b/i.test(sql)) {
                  largestJobs = Math.max(largestJobs, rows.length);
                  jobReads.push({ sql, args });
                }
                return rows;
              };
              return value.bind(stmt);
            },
          });
        };
        const value = Reflect.get(target, prop, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const read = makeStore(traced, ".");
    const steps = stationDocSteps(read, ".", {}, new Set(["job"]), asker);
    let first: Doc | undefined;
    while (first === undefined) {
      const step = steps.next();
      assert.equal(step.done, false);
      first = step.value;
    }
    assert.equal(first.kind, "job");
    assert.ok(largestSessions <= 256, `the first result read ${largestSessions} session keys`);
    assert.ok(largestJobs <= 256, `the first result read ${largestJobs} jobs`);

    // The extra row is after the captured end of this session's job history. A busy job producer cannot extend a
    // search indefinitely; a subsequent search will find the new row.
    addJob.run("later", "a", "later job", "later-token", 999);
    assert.ok(![...steps].some((d) => d?.key === "j:later"));
    assert.deepEqual([...new Set(sessionLookups)], ["a", "other-0000"], "sessions with no jobs add no lookups to a job search");
    assert.ok(candidates.length <= 3, "a session's many jobs are skipped in one index seek");
    assert.ok(jobReads.every((r) => r.args[0] === "a"), "jobs in another workspace are never read");
    const jobSeek = jobReads.find((r) => /rowid > \?/i.test(r.sql))!;
    const sessionSeek = candidates.find((r) => /session_key > (?:CAST\()?\?/i.test(r.sql))!;
    for (const [query, index] of [[jobSeek, /jobs_by_session/], [sessionSeek, /jobs_by_session/]] as const) {
      assert.ok(query, "the next batch seeks after the previous one");
      const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${query.sql}`).all(...query.args as any[]) as { detail: string }[])
        .map((r) => r.detail).join(" | ");
      assert.match(plan, index);
      assert.doesNotMatch(plan, /SCAN |USE TEMP B-TREE/);
    }
    assert.ok([...stationDocs(read, ".", {}, new Set(["job"]), asker)].some((d) => d.key === "j:later"));
    addJob.run("orphan", "gone", "orphan job", "orphan-token", 1_000);
    assert.ok(![...stationDocs(read, ".", {}, new Set(["job"]), asker)].some((d) => d.key === "j:orphan"),
      "a job whose session has gone stays outside search");

    const expected = pick(jobDocs(read, "a"), ["needle"], asker, { limit: 15, offset: 4 });
    const actual = pick(stationDocs(read, ".", {}, new Set(["job"]), asker), ["needle"], asker, { limit: 15, offset: 4 });
    assert.deepEqual(actual, expected, "newest order, ties and workspace filtering stay the same");

    const moving = stationDocSteps(read, ".", {}, new Set(["job"]), asker);
    assert.equal(moving.next().value?.kind, "job");
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("other", "a");
    const beforeMove = jobReads.length;
    assert.throws(() => [...moving], /session changed while searching/);
    assert.equal(jobReads.length, beforeMove, "after a session moves, no further batch is read for the old workspace");
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("mine", "a");

    addSession("single", "mine");
    addJob.run("only", "single", "only job", "only-token", 1);
    const short = stationDocSteps(read, ".", {}, new Set(["job"]), asker);
    for (;;) {
      const next = short.next();
      assert.equal(next.done, false);
      if (next.value?.ref.session === "single") break;
    }
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("other", "single");
    assert.throws(() => [...short], /session changed while searching/, "a final short batch is checked too");
    store.db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run("mine", "single");

    let cancelled = false;
    const pending = pickAsync(stationDocSteps(read, ".", {}, new Set(["job"]), asker), ["needle"], asker, {}, () => cancelled);
    await new Promise<void>((resolve) => setImmediate(resolve));
    cancelled = true;
    await assert.rejects(pending, /the search took too long/);
  } finally {
    store.close();
  }
});
