import assert from "node:assert/strict";
import { test } from "node:test";
import { sessions } from "../src/read/sessions.ts";
import { makeStore, sessionUsages, transcriptLengths, watching } from "../src/read/store.ts";
import { PEOPLE_AT } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";

test("a workspace's session list reads details only for the sessions it shows", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person',?,'hello',?)");
    const ws = db.prepare("UPDATE sessions SET ws=? WHERE key=?");
    const length = db.prepare("INSERT INTO transcript_lengths(session,n) VALUES (?,?)");
    const usage = db.prepare("INSERT INTO session_usage(session,usage) VALUES (?,?)");
    const coverage = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='usage_totals_incremental'").get()
      ? db.prepare("INSERT INTO usage_totals_source_sessions(session,done) VALUES (?,1) ON CONFLICT(session) DO UPDATE SET done=1") : null;
    const job = db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log,watch)
      VALUES (?,?,?,'true','/',?,'running',?,'/dev/null',1)`);
    for (let n = 0; n < 102; n++) {
      const key = `session-${n}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: `token-${n}`, createdAt: n, lastActiveAt: n });
      ws.run(n < 2 ? "mine" : "elsewhere", key);
      const thread = store.openThread("ember", "EMBER", `chat-${n}`, null, null).id;
      store.joinThread(thread, key, "ember");
      put.run(thread, `person-${n}`, n);
      length.run(key, n + 10);
      usage.run(key, JSON.stringify({ input: n }));
      coverage?.run(key);
      job.run(`job-${n}`, key, `watch-${n}`, `job-token-${n}`, n + 1);
    }
    const viewer = { workspace: "mine", home: false };
    const expected = sessions(makeStore(db, "/no-station-config"), null, false, "en", viewer);
    assert.deepEqual(expected.map((row: any) => row.key), ["session-1", "session-0"]);
    assert.ok(expected.every((row: any) => row.participants.length === 1 && row.watch && row.usage));

    const visited = { stats: 0, people: 0, lengths: 0, usage: 0, watches: 0 };
    const queries: Record<string, string> = {};
    db.function("visit_session_stat", (key) => { visited.stats++; return key; });
    db.function("visit_session_person", () => { visited.people++; return 1; });
    db.function("visit_session_length", (key) => { visited.lengths++; return key; });
    db.function("visit_session_usage", (key) => { visited.usage++; return key; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql.startsWith("SELECT ts.session, ts.connect")) queries.people = sql;
          if (sql.startsWith("SELECT session, n FROM transcript_lengths")) queries.lengths = sql;
          if (sql.startsWith("SELECT u.session, u.usage FROM")) queries.usage = sql;
          if (sql.startsWith("SELECT j.* FROM active_watch_jobs")) queries.watches = sql;
          if (sql.includes("FROM session_turns c")) sql = sql.replace("SELECT s.key,", "SELECT s.key, visit_session_stat(s.key) AS visited,");
          if (sql === PEOPLE_AT) sql = sql.replace("WHERE p.thread = ?", "WHERE p.thread = ? AND visit_session_person()");
          if (sql.startsWith("SELECT session, n FROM transcript_lengths")) sql = sql.replace("SELECT session, n", "SELECT visit_session_length(session) AS session, n");
          if (sql.startsWith("SELECT u.session, u.usage FROM")) sql = sql.replace("SELECT u.session, u.usage", "SELECT visit_session_usage(u.session) AS session, u.usage");
          if (sql.startsWith("SELECT at, text FROM job_notices WHERE job_id = ?")) visited.watches++;
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.deepEqual(sessions(makeStore(instrumented, "/no-station-config"), null, false, "en", viewer), expected);
    assert.deepEqual(visited, { stats: 2, people: 2, lengths: 2, usage: 2, watches: 2 });
    const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(JSON.stringify(["session-0", "session-1"]))
      .map((r: any) => r.detail).join("\n");
    assert.match(plan(queries.people!), /SEARCH ts USING INDEX thread_sessions_session \(session=\?\)/);
    assert.match(plan(queries.lengths!), /SEARCH transcript_lengths USING INDEX .* \(session=\?\)/);
    assert.match(plan(queries.usage!), /SEARCH u USING INDEX .* \(session=\?\)/);
    assert.match(plan(queries.watches!), /SEARCH w USING (?:COVERING )?INDEX active_watch_jobs_session \(session=\?\)/);

    // A station with incomplete old usage still shows only totals known to be complete.
    db.exec(`CREATE TABLE usage_totals_incremental (id INTEGER PRIMARY KEY);
      CREATE TABLE usage_totals_source_sessions (session TEXT PRIMARY KEY, done INTEGER NOT NULL);
      INSERT INTO usage_totals_source_sessions VALUES ('session-0', 1), ('session-1', 0)`);
    const limited = sessionUsages(makeStore(instrumented, "/no-station-config"), ["session-0", "session-1", "session-2"]);
    assert.deepEqual([...limited], [["session-0", { input: 0 }]]);
    assert.match(plan(queries.usage!), /SEARCH u USING INDEX .* \(session=\?\)/);
    assert.match(plan(queries.usage!), /SEARCH c USING INDEX .* \(session=\?\)/);
    const manyKeys = Array.from({ length: 2000 }, (_, n) => `absent-${n}`).concat("session-0");
    assert.deepEqual([...transcriptLengths(makeStore(db, "/no-station-config"), manyKeys)], [["session-0", 10]]);

    db.prepare("UPDATE sessions SET archived_at=99 WHERE key='session-1'").run();
    db.prepare("UPDATE sessions SET connect='other' WHERE key='session-0'").run();
    ws.run(null, "session-2");
    const keys = (connect: string | null, archived: boolean, who: typeof viewer | null) =>
      sessions(makeStore(db, "/no-station-config"), connect, archived, "en", who).map((r: any) => r.key);
    assert.deepEqual(keys(null, false, viewer), ["session-0"]);
    assert.deepEqual(keys(null, true, viewer), ["session-1"]);
    assert.deepEqual(keys("other", false, viewer), ["session-0"]);
    assert.deepEqual(keys("ember", false, viewer), []);
    assert.deepEqual(keys(null, false, { workspace: "mine", home: true }), ["session-2", "session-0"]);
    assert.equal(keys(null, false, null).length, 101);
  } finally { store.close(); }
});

test("named sessions' watches keep their order and work on a database from before the lookup", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const job = db.prepare(`INSERT INTO jobs(id,session_key,name,command,cwd,token,state,started_at,log,watch)
      VALUES (?,?,?,'true','/',?,'running',10,'/dev/null',?)`);
    job.run("a", "one", "first", "a", 1);
    job.run("other", "another", "other", "other", 1);
    job.run("b", "one", "second", "b", 1);
    job.run("ordinary", "one", "ordinary", "ordinary", 0);
    const read = makeStore(db, "/no-station-config");
    const expected = watching(read).get("one");
    assert.deepEqual(expected, { names: ["first", "second"], since: 10, at: 10 });
    assert.deepEqual(watching(read, ["one"]).get("one"), expected);
    assert.deepEqual([...watching(read, [])], []);
    db.exec("DROP TABLE active_watch_jobs");
    assert.deepEqual(watching(read, ["one"]).get("one"), expected);
  } finally { store.close(); }
});
