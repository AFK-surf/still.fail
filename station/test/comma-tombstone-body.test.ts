import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { nextPage, RevIndex, statsWire, taskWire } from "../src/comma/stats.ts";

// Count stored tombstone body bytes returned from SQLite to the page reader.
function countTombstones(db: DatabaseSync, count: (bytes: number) => void): DatabaseSync {
  return new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      return new Proxy(statement, { get(s, prop) {
        if (prop === "all") return (...args: any[]) => {
          const rows = s.all(...args) as any[];
          for (const row of rows) if (row.removed !== undefined && row.removed !== 0 && typeof row.json === "string") {
            count(Buffer.byteLength(row.json));
          }
          return rows;
        };
        const value = Reflect.get(s, prop, s);
        return typeof value === "function" ? value.bind(s) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
}

for (const [name, wire] of [["stats_index", statsWire], ["task_index", taskWire]] as const) {
  test(`${name} pages send tombstones without returning their old bodies from SQLite`, () => {
    const raw = new DatabaseSync(":memory:");
    raw.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    let bodyBytes = 0;
    const index = new RevIndex(countTombstones(raw, (n) => { bodyBytes += n; }), name);
    const body = JSON.stringify({ task: "chat", title: "x".repeat(4096) });
    try {
      const insert = raw.prepare(`INSERT INTO ${name}(key,source,kind,rev,json,removed) VALUES (?,'stillfail','task',?,?,?)`);
      for (let i = 1; i <= 16; i++) {
        const removed = i === 1 ? -1 : i === 2 ? "other" : i === 3 ? Buffer.from([0]) : 1;
        insert.run(`key-${i}`, i, body, removed);
      }
      insert.run("active", 17, JSON.stringify({ task: "active", title: "kept" }), "0");
      raw.prepare("INSERT INTO meta (key,value) VALUES (?,?)").run(`${name}.rev`, "17");
      const page = nextPage(index, { epoch: null, through: 0 }, wire)!;
      assert.equal(page.through, 17);
      assert.equal(page.rows.filter((row) => row.removed === true).length, 16);
      assert.equal(page.rows.filter((row) => row.removed !== true).length, 1);
      assert.equal(bodyBytes, 0, "the page returned stored tombstone bodies even though the wire format omits them");
    } finally { raw.close(); }
  });
}

test("other readers and a custom page encoder still receive a tombstone's stored body", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  const index = new RevIndex(db, "stats_index");
  const body = JSON.stringify({ title: "old body" });
  try {
    db.prepare("INSERT INTO stats_index (key,source,kind,rev,json,removed) VALUES ('key','stillfail','task',1,?,1)").run(body);
    db.prepare("INSERT INTO meta (key,value) VALUES ('stats_index.rev','1')").run();
    assert.equal(index.since(0, 1)[0]?.json, body);
    const page = nextPage(index, { epoch: null, through: 0 }, (row) => ({ title: JSON.parse(row.json).title }))!;
    assert.deepEqual(page.rows, [{ title: "old body" }]);
  } finally { db.close(); }
});
