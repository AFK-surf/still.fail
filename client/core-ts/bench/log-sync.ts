// Hot log bookkeeping while messages arrive: the same numbers/behind/next/span reads as the channel sync and chat.
// Synthetic internal-letter records in real in-memory SQLite, no network or UI. This measures local sync work only.
// Run: node client/core-ts/bench/log-sync.ts
import { DatabaseSync } from "node:sqlite";
import { AccountDb } from "../src/db/account.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import { Runner } from "../src/runtime.ts";
import { behind, next } from "../src/channels/fill.ts";

for (const size of [10_000, 50_000]) {
  const inner = new NodeSql(new DatabaseSync(":memory:"), true);
  let rows = 0, reads = 0;
  const sql = {
    exec: inner.exec.bind(inner), run: inner.run.bind(inner), close: inner.close.bind(inner),
    all: (...args: Parameters<NodeSql["all"]>) => { const out = inner.all(...args); rows += out.length; reads++; return out; },
  };
  const runner = new Runner();
  const db = new AccountDb("bench", "bench", sql, runner, { tone: () => null, asks: () => false });
  const item = (n: number): [number, unknown] => [n, { kind: "letter", thread: 7, n, text: "internal letter" }];
  db.putLog("entry", "w/s", "7", Array.from({ length: size }, (_, i) => item(i + 1)));
  db.logNumbers("entry", "w/s", "7");
  db.logSpan("entry", "w/s", "7");
  rows = reads = 0;
  const start = performance.now();
  for (let i = 1; i <= 100; i++) {
    const n = size + i;
    db.putLog("entry", "w/s", "7", [item(n)]);
    behind(db.logNumbers("entry", "w/s", "7"), n);
    next(db.logNumbers("entry", "w/s", "7"), n, 50);
    db.logSpan("entry", "w/s", "7");
  }
  console.log(JSON.stringify({ size, events: 100, ms: Math.round((performance.now() - start) * 10) / 10, sqlReads: reads, rowsRead: rows }));
  const from = size - 49;
  db.putLog("entry", "w/s", "7", Array.from({ length: 50 }, (_, i) => {
    const n = from + i;
    return [n, { kind: "letter", thread: 7, n, text: "cached Markdown ".repeat(1000) }] as [number, unknown];
  }));
  db.logRange("entry", "w/s", "7", from, size);
  rows = reads = 0;
  const began = performance.now();
  for (let i = 0; i < 200; i++) db.logRange("entry", "w/s", "7", from, size);
  console.log(JSON.stringify({ size, hotWindowReads: 200, ms: Math.round((performance.now() - began) * 10) / 10, sqlReads: reads, rowsRead: rows }));
  db.close();
  runner.shutdown();
}
