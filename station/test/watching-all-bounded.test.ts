import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore, WATCHING_ALL, watching } from "../src/read/store.ts";
import { JOBS_RUNNING, Store } from "../src/store/store.ts";

test("the station-wide watching view does not read ordinary running jobs", () => {
  const reads: { ordinary: number; watches: number }[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let seen = 0, watches = 0;
    db.function("ordinary_seen", (id) => { if (String(id).startsWith("ordinary-")) seen++; return 1; });
    db.function("watch_seen", () => { watches++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
        ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND ordinary_seen(id)")
        : sql === WATCHING_ALL ? sql.replace("ON j.id = w.job", "ON j.id = w.job AND watch_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,watch,name,command,cwd,started_at,log)
        VALUES(?,?,?,'running',?,?,'','',?,'')`);
      insert.run("watch", "watch", "mine", 1, "watching", 10);
      for (let i = 0; i < unrelated; i++) insert.run(`ordinary-${i}`, `ordinary-${i}`, "other", 0, "job", i);
      assert.deepEqual(watching(makeStore(observed, ".")).get("mine"), { names: ["watching"], since: 10, at: 10 });
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${WATCHING_ALL}`).all() as { detail: string }[]).map((r) => r.detail).join(" | ");
      assert.match(plan, /SCAN w/);
      assert.match(plan, /SEARCH j USING INDEX \S+ \(id=\?\)/);
      reads.push({ ordinary: seen, watches });
    } finally { store.close(); }
  }
  assert.deepEqual(reads, [{ ordinary: 0, watches: 1 }, { ordinary: 0, watches: 1 }]);
});

test("station-wide watches keep equal-time order and work with a pre-index store", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`INSERT INTO jobs(id,token,session_key,state,watch,name,command,cwd,started_at,log)
      VALUES ('first','first','mine','running',1,'first','','',10,''),
        ('second','second','mine','running',1,'second','','',10,'')`);
    const read = makeStore(db, ".");
    const expected = { names: ["first", "second"], since: 10, at: 10 };
    assert.deepEqual(watching(read).get("mine"), expected);
    db.exec("DROP TABLE active_watch_jobs");
    assert.deepEqual(watching(read).get("mine"), expected);
  } finally { store.close(); }
});
