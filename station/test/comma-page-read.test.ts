import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { nextPage, RevIndex } from "../src/comma/stats.ts";

test("a page reads only the statistics bodies it needs, leaving the remaining revisions for later pages", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  let bodies = 0;
  // Count bodies returned from the page query, whether it collects them all or iterates them.
  const watched = new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.includes("FROM stats_index") || !sql.includes("CAST(key AS BLOB)") || !sql.includes("json")) return statement;
      return new Proxy(statement, { get(s, prop) {
        if (prop === "all") return (...args: any[]) => { const rows = s.all(...args); bodies += rows.length; return rows; };
        if (prop === "iterate") return function* (...args: any[]) { for (const row of s.iterate(...args)) { bodies++; yield row; } };
        const value = Reflect.get(s, prop, s);
        return typeof value === "function" ? value.bind(s) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
  const index = new RevIndex(watched, "stats_index");
  const add = db.prepare("INSERT INTO stats_index (key,source,kind,rev,json) VALUES (?,'stillfail','task',?,?)");
  try {
    db.exec("BEGIN");
    for (let n = 1; n <= 201; n++) add.run(`chat\0${n}`, n, JSON.stringify({ thread: n, title: "x".repeat(16_384) }));
    db.exec("COMMIT");
    db.prepare("INSERT INTO meta (key,value) VALUES ('stats_index.rev','201')").run();
    const first = nextPage(index, { epoch: null, through: 0 })!;
    assert.deepEqual([first.rows.length, first.through, first.reset], [3, 3, true]);
    assert.ok(bodies > 0 && bodies <= 4, `read ${bodies} full bodies to send three`);
    const seen = first.rows.map((r: any) => r.row.thread);
    let held = { epoch: first.epoch, through: first.through };
    for (let page = nextPage(index, held); page !== null; page = nextPage(index, held)) {
      seen.push(...page.rows.map((r: any) => r.row.thread));
      held = { epoch: page.epoch, through: page.through };
    }
    assert.deepEqual(seen, Array.from({ length: 201 }, (_, i) => i + 1));
    assert.equal(held.through, 201);
  } finally { db.close(); }
});

test("a page that stops early releases its read cursor for another connection", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-page-read-"));
  const path = join(dir, "index.db");
  const db = new DatabaseSync(path);
  try {
    db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    const index = new RevIndex(db, "stats_index");
    const add = db.prepare("INSERT INTO stats_index (key,source,kind,rev,json) VALUES (?,'stillfail','task',?,?)");
    for (let n = 1; n <= 8; n++) add.run(`chat${n}`, n, JSON.stringify({ thread: n, title: "x".repeat(16_384) }));
    db.prepare("INSERT INTO meta (key,value) VALUES ('stats_index.rev','8')").run();
    assert.equal(nextPage(index, { epoch: null, through: 0 })!.through, 3);
    const other = new DatabaseSync(path);
    try {
      other.prepare("UPDATE stats_index SET json = ? WHERE key = ?").run('{"thread": 1}', "chat1");
      assert.throws(() => nextPage(index, { epoch: null, through: 0 }, () => { throw new Error("wire failed"); }), /wire failed/);
      other.prepare("UPDATE stats_index SET json = ? WHERE key = ?").run('{"thread": 2}', "chat2");
    }
    finally { other.close(); }
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the row limit, malformed bodies and pruned revisions retain their page positions", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  const index = new RevIndex(db, "stats_index");
  try {
    const add = db.prepare("INSERT INTO stats_index (key,source,kind,rev,json,removed) VALUES (?,'stillfail','task',?,?,?)");
    for (let n = 1; n <= 200; n++) add.run(`key${n}`, n, n === 1 ? "not json" : JSON.stringify({ thread: n }), n === 2 ? 1 : 0);
    db.prepare("INSERT INTO meta (key,value) VALUES ('stats_index.rev','205')").run();
    const all = nextPage(index, { epoch: null, through: 0 })!;
    assert.deepEqual([all.rows.length, all.through, all.reset], [199, 205, true]);
    assert.equal(all.rows[0].removed, true);
    add.run("key201", 201, JSON.stringify({ thread: 201 }), 0);
    const first = nextPage(index, { epoch: null, through: 0 })!;
    assert.deepEqual([first.rows.length, first.through], [199, 200]);
    const second = nextPage(index, { epoch: first.epoch, through: first.through })!;
    assert.deepEqual([second.rows.length, second.rows[0].row.thread, second.through], [1, 201, 205]);
    assert.equal(nextPage(index, { epoch: second.epoch, through: second.through }), null);
  } finally { db.close(); }
});
