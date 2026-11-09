import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Jobs } from "../src/jobs/jobs.ts";
import { PROCESS_BY_GROUP, Store } from "../src/store/store.ts";

test("stopping a job left by an older station does not read other process records", async () => {
  const counts: number[] = [];
  for (const unrelated of [40, 400]) {
    const data = mkdtempSync(join(tmpdir(), "left-behind-job-"));
    const store = Store.open(":memory:"), db = store.db;
    const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
    let seen = 0;
    db.function("other_process_seen", (pgid) => { if (Number(pgid) !== 987654321) seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT * FROM processes"
        ? `${sql} WHERE other_process_seen(pgid)`
        : sql === PROCESS_BY_GROUP ? `${sql} AND other_process_seen(pgid)` : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const add = db.prepare("INSERT INTO processes(pgid,started_at,runtime,label) VALUES(?,1,'job','other')");
      for (let i = 0; i < unrelated; i++) add.run(10_000 + i);
      db.prepare("INSERT INTO processes(pgid,started_at,runtime,label) VALUES(987654321,1,'codex','other runtime')").run();
      db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,pgid,started_at,log)
        VALUES('old-job','old-job','mine','running','old-job','','',987654321,1,'')`).run();
      Object.defineProperty(store, "db", { value: observed });
      assert.equal((await jobs.stop("old-job")).state, "stopped");
      assert.ok(db.prepare("SELECT 1 FROM processes WHERE pgid = 987654321").get(), "another runtime's record is retained");
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${PROCESS_BY_GROUP}`).all(987654321) as { detail: string }[])
        .map((row) => row.detail).join(" | ");
      assert.match(plan, /SEARCH processes USING INTEGER PRIMARY KEY \(rowid=\?\)/);
      counts.push(seen);
    } finally { await jobs.shutdown(); store.close(); rmSync(data, { recursive: true, force: true }); }
  }
  assert.deepEqual(counts, [0, 0]);
});
