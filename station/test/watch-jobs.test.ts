import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { ACTIVE_WATCHES_AT_INSTALL, HAS_ACTIVE_WATCH, installActiveWatches } from "../src/store/watch-jobs.ts";

for (const recursive of [false, true]) test(`active watch lookup follows job changes and older writers (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"};
      CREATE TABLE jobs (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, state TEXT NOT NULL, watch INTEGER NOT NULL, token TEXT NOT NULL UNIQUE);
      CREATE INDEX jobs_state ON jobs (state);
      CREATE TABLE thread_sessions (thread INTEGER NOT NULL, session TEXT NOT NULL, PRIMARY KEY (thread, session));
      INSERT INTO thread_sessions VALUES (1, 'a'), (2, 'b');`);
    const add = (id: string, session: string, state: string, watch: number, token = `token-${id}`) =>
      db.prepare("INSERT INTO jobs VALUES (?, ?, ?, ?, ?)").run(id, session, state, watch, token);
    for (let i = 0; i < 200; i++) add(`old-${i}`, "a", "exited", 1);
    add("a-watch", "a", "running", 1);
    add("b-task", "b", "running", 0);
    const before = (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    installActiveWatches(db);
    assert.equal((db.prepare("SELECT total_changes() AS n").get() as { n: number }).n - before, 1,
      "installation copies only the watch running now, not completed job history");
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${ACTIVE_WATCHES_AT_INSTALL}`).all() as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /jobs_state \(state=\?\)/);
    const lookupPlan = (db.prepare(`EXPLAIN QUERY PLAN ${HAS_ACTIVE_WATCH}`).all(1) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(lookupPlan, /SEARCH t USING COVERING INDEX .* \(thread=\?\)/);
    assert.match(lookupPlan, /SEARCH w USING COVERING INDEX active_watch_jobs_session \(session=\?\)/);
    const has = (thread: number) => db.prepare(HAS_ACTIVE_WATCH).get(thread) !== undefined;
    assert.equal(has(1), true);
    assert.equal(has(2), false);

    add("b-watch", "b", "running", 2);
    assert.equal(has(2), true, "nonzero watch values follow the original job reader");
    db.prepare("UPDATE jobs SET state = 'exited' WHERE id = ?").run("a-watch");
    assert.equal(has(1), false);
    db.prepare("UPDATE jobs SET session_key = 'a' WHERE id = ?").run("b-watch");
    assert.equal(has(1), true);
    assert.equal(has(2), false);
    db.prepare("INSERT OR REPLACE INTO jobs VALUES (?, ?, ?, ?, ?)").run("b-watch", "a", "exited", 1, "token-b-watch");
    assert.equal(has(1), false, "replacing a running watch cannot leave a stale lookup");
    db.prepare("UPDATE jobs SET state = 'running' WHERE id = ?").run("b-watch");
    add("also-watching", "a", "running", 1);
    db.prepare("DELETE FROM jobs WHERE id = ?").run("b-watch");
    assert.equal(has(1), true, "a second running watch remains");
    db.prepare("UPDATE jobs SET watch = 0 WHERE id = ?").run("also-watching");
    assert.equal(has(1), false);
    add("replaced-by-token", "a", "running", 1);
    db.prepare("INSERT OR IGNORE INTO jobs VALUES (?, ?, ?, ?, ?)").run("ignored", "b", "running", 0, "token-replaced-by-token");
    assert.equal(has(1), true, "an ignored insert does not remove the running watch");
    db.prepare("INSERT OR REPLACE INTO jobs VALUES (?, ?, ?, ?, ?)").run("replacement", "b", "running", 0, "token-replaced-by-token");
    assert.equal(has(1), false, "a replacement on the unique token removes the old watch");
    add("updated-by-token", "a", "running", 1);
    db.prepare("UPDATE OR REPLACE jobs SET token = ? WHERE id = ?").run("token-updated-by-token", "replacement");
    assert.equal(has(1), false, "a token update replacing a different watch removes it too");
    const unchanged = (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    add("ordinary", "a", "running", 0);
    db.prepare("UPDATE jobs SET state = 'exited' WHERE id = ?").run("ordinary");
    assert.equal((db.prepare("SELECT total_changes() AS n").get() as { n: number }).n - unchanged, 2,
      "ordinary jobs do not write the watch lookup");
    installActiveWatches(db);
    assert.equal(has(1), false, "reopening the lookup does not recreate stopped watches");
  } finally { db.close(); }
});
