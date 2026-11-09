import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usage, usageHistory } from "../src/read/usage.ts";
import { REMOTE_RUNS_OF } from "../src/store/remote-runs.ts";
import { Store } from "../src/store/store.ts";

test("remote task usage does not read another workspace's growing history", () => {
  const store = Store.open(":memory:");
  try {
    const add = store.db.prepare("INSERT INTO remote_runs (job, at, session) VALUES (?, ?, ?)");
    add.run("a", 10, "remote:A:station:chat");
    store.db.exec("BEGIN");
    for (let i = 0; i < 2_000; i++) add.run(`b${i}`, 10, `remote:B:station:chat${i}`);
    store.db.exec("COMMIT");

    // Count rows returned by statements reading the remote-task history, including summary queries. This checks what
    // reaches the reader, rather than inferring work from the time the query happened to take.
    let rowsRead = 0;
    const db = new Proxy(store.db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!/\bSELECT\b/i.test(sql) || !/\b(remote_runs|remote_run_lookup|remote_run_by_time)\b/i.test(sql)) return statement;
          return new Proxy(statement, {
            get(s, method) {
              if (method === "all") return (...args: any[]) => { const rows = s.all(...args); rowsRead += rows.length; return rows; };
              if (method === "get") return (...args: any[]) => { const row = s.get(...args); if (row !== undefined) rowsRead++; return row; };
              const value = Reflect.get(s, method, s);
              return typeof value === "function" ? value.bind(s) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const reader = makeStore(db, ".");
    const viewer = { workspace: "A", home: false };
    const summary = usageHistory(reader, 0n, viewer);
    assert.equal(summary.remoteRuns, 1);
    assert.ok(rowsRead <= 1, `history summary read ${rowsRead} remote-task rows`);

    rowsRead = 0;
    const page = usage(reader, "en", 0n, 100n, 0n, false, viewer);
    assert.deepEqual(page.remoteRuns, [{ at: 10, session: "remote:A:station:chat" }]);
    assert.ok(rowsRead <= 1, `usage page read ${rowsRead} remote-task rows`);
    assert.equal(usageHistory(makeStore(store.db, "."), 0n, null).remoteRuns, 2_001);

    let examined = 0;
    store.db.function("examined_remote_task", (seq) => { examined++; return seq; });
    const tracked = store.db.prepare(REMOTE_RUNS_OF.replace("AND at >= ?2", "AND examined_remote_task(seq) IS NOT NULL AND at >= ?2"));
    assert.equal(tracked.all("A", 0).length, 1);
    assert.equal(examined, 1, "another workspace's tasks are not examined by the indexed lookup");
  } finally {
    store.close();
  }
});
