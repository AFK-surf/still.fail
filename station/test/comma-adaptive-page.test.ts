import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CommaStats, IndexSync, PAGE_BYTES, RevIndex, statsWire, taskWire, type Held, type IndexRow } from "../src/comma/stats.ts";

// Count rows returned by SQLite to the page reader, not bytes read from disk.
function countPageRows(db: DatabaseSync, count: (rows: number) => void): DatabaseSync {
  return new Proxy(db, { get(target, property) {
    if (property === "prepare") return (sql: string) => {
      const statement = target.prepare(sql);
      if (!sql.includes("ORDER BY rev LIMIT") || !sql.includes(" AS json")) return statement;
      return new Proxy(statement, { get(s, prop) {
        if (prop === "all") return (...args: any[]) => { const rows = s.all(...args); count(rows.length); return rows; };
        const value = Reflect.get(s, prop, s);
        return typeof value === "function" ? value.bind(s) : value;
      } });
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
}

function fixture(name: "stats_index" | "task_index" = "stats_index") {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  let fetched = 0;
  const index = new RevIndex(countPageRows(db, (n) => { fetched += n; }), name);
  const put = db.prepare(`INSERT INTO ${name} (key,source,kind,rev,json,removed) VALUES (?,'stillfail','task',?,?,?)`);
  return {
    db, index,
    add: (key: string, rev: number, json: string, removed = 0) => put.run(key, rev, json, removed),
    rev: (n: number) => db.prepare("INSERT INTO meta (key,value) VALUES (?,?)").run(`${name}.rev`, String(n)),
    count: () => { const n = fetched; fetched = 0; return n; },
  };
}

test("a sender learns to read fewer large wire rows on later pages without losing changes", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 201; n++) f.add(`chat\0${n}`, n, JSON.stringify({ thread: n, title: "x".repeat(16_384) }));
    f.rev(201);
    const sync = new IndexSync(f.index);
    try {
      let held: Held = { epoch: null, through: 0 };
      const seen: number[] = [];
      let pages = 0;
      for (let page = sync.next(held); page !== null; page = sync.next(held)) {
        pages++;
        const fetched = f.count();
        if (pages === 1) assert.deepEqual([page.reset, page.rows.length, fetched], [true, 3, 201]);
        if (pages === 2) assert.deepEqual([page.reset, page.rows.length, fetched], [false, 3, 9]);
        assert.ok(page.through > held.through);
        assert.ok(Buffer.byteLength(JSON.stringify(page.rows)) <= PAGE_BYTES);
        seen.push(...page.rows.map((row: any) => row.row.thread));
        held = { epoch: page.epoch, through: page.through };
        assert.ok(pages <= 100, "the receiver must make progress");
      }
      assert.deepEqual(seen, Array.from({ length: 201 }, (_, i) => i + 1));
      assert.equal(held.through, 201);
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("a sender expands again after large rows give way to small ones", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 612; n++) f.add(`chat${n}`, n, JSON.stringify({ thread: n, title: n <= 12 ? "x".repeat(16_384) : "small" }));
    f.rev(612);
    const sync = new IndexSync(f.index);
    try {
      let held: Held = { epoch: null, through: 0 };
      const seen: number[] = [], sizes: number[] = [];
      for (let page = sync.next(held); page !== null; page = sync.next(held)) {
        sizes.push(page.rows.length);
        seen.push(...page.rows.map((row: any) => row.row.thread));
        assert.ok(page.through > held.through);
        held = { epoch: page.epoch, through: page.through };
        assert.ok(sizes.length <= 8, "small rows should quickly return to full pages");
      }
      assert.ok(sizes.includes(200));
      assert.deepEqual(seen, Array.from({ length: 612 }, (_, i) => i + 1));
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("large stored Task bodies that encode to small rows keep full pages", () => {
  const f = fixture("task_index");
  try {
    for (let n = 1; n <= 201; n++) f.add(`chat${n}`, n, JSON.stringify({ task: `task${n}`, title: "short", padding: "x".repeat(16_384) }));
    f.rev(201);
    const sync = new IndexSync(f.index, taskWire);
    try {
      const first = sync.next({ epoch: null, through: 0 })!;
      const second = sync.next({ epoch: first.epoch, through: first.through })!;
      assert.deepEqual([first.rows.length, second.rows.length, second.through], [200, 1, 201]);
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("a smaller page does not introduce a boundary within equal revisions", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 13; n++) {
      const revision = n <= 11 ? n : n - 1;
      f.add(`chat${n}`, revision, JSON.stringify({ thread: n, title: n <= 4 ? "x".repeat(16_384) : "small" }));
    }
    f.rev(12);
    const sync = new IndexSync(f.index);
    try {
      const first = sync.next({ epoch: null, through: 0 })!;
      const second = sync.next({ epoch: first.epoch, through: first.through })!;
      assert.deepEqual(first.rows.map((row: any) => row.row.thread), [1, 2, 3]);
      assert.deepEqual(second.rows.map((row: any) => row.row.thread), [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
      assert.equal(second.through, 12);
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("adaptive pages preserve tombstones, malformed positions, and the last revision", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 30; n++) {
      const removed = n > 3 && n % 7 === 0;
      const json = n > 3 && n % 11 === 0 ? "not json" : JSON.stringify({ thread: n, title: "x".repeat(16_384) });
      f.add(`chat${n}`, n, json, removed ? 1 : 0);
    }
    f.rev(31);
    const expected = f.index.since(0, 30).map(statsWire).filter((row) => row !== null);
    const sync = new IndexSync(f.index);
    try {
      let held: Held = { epoch: null, through: 0 }, resets = 0, pages = 0;
      const seen: unknown[] = [];
      for (let page = sync.next(held); page !== null; page = sync.next(held)) {
        resets += page.reset ? 1 : 0;
        seen.push(...page.rows);
        assert.ok(page.through > held.through);
        held = { epoch: page.epoch, through: page.through };
        assert.ok(++pages < 30);
      }
      assert.equal(resets, 1);
      assert.equal(held.through, 31);
      assert.deepEqual(seen, expected);
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("a prune during adaptive paging resets the receiver and resumes from a single snapshot", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 20; n++) f.add(`chat${n}`, n, JSON.stringify({ thread: n, title: "x".repeat(16_384) }), n === 10 ? 1 : 0);
    f.rev(20);
    const sync = new IndexSync(f.index);
    try {
      let held: Held = { epoch: null, through: 0 }, resets = 0, pages = 0;
      const copy = new Map<string, unknown>();
      const apply = (page: NonNullable<ReturnType<IndexSync["next"]>>) => {
        if (page.reset) { resets++; copy.clear(); }
        for (const row of page.rows) row.removed ? copy.delete(row.key) : copy.set(row.key, row.row);
        held = { epoch: page.epoch, through: page.through };
      };
      apply(sync.next(held)!);
      assert.equal(held.through, 3);
      f.db.prepare("DELETE FROM stats_index WHERE key = ?").run("chat10");
      assert.equal(f.index.pruned(), 10);
      for (let page = sync.next(held); page !== null; page = sync.next(held)) {
        apply(page);
        assert.ok(++pages < 30);
      }
      const expected = f.index.since(0, 30).map(statsWire).filter((row) => row !== null && !row.removed);
      assert.equal(resets, 2);
      assert.equal(held.through, 20);
      assert.deepEqual([...copy], expected.map((row) => [row.key, row.row]));
    } finally { sync.close(); }
  } finally { f.db.close(); }
});

test("an older connection can remember a Router write while an adaptive page is encoded", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-adaptive-page-"));
  const path = join(dir, "index.db");
  const db = new DatabaseSync(path);
  try {
    db.exec("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
    const index = new RevIndex(db, "stats_index");
    const put = db.prepare("INSERT INTO stats_index (key,source,kind,rev,json) VALUES (?,'stillfail','task',?,?)");
    for (let n = 1; n <= 20; n++) put.run(`chat${n}`, n, JSON.stringify({ thread: n, title: "x".repeat(16_384) }));
    db.prepare("INSERT INTO meta VALUES ('stats_index.rev','20')").run();
    const sync = new IndexSync(index);
    const older = new CommaStats(path, async () => ({ stations: [], unread: [] }), () => () => {});
    try {
      const first = sync.next({ epoch: null, through: 0 })!;
      assert.equal(first.through, 3);
      const stringify = JSON.stringify;
      let written = false;
      try {
        JSON.stringify = ((value: any, replacer?: any, space?: any) => {
          if (!written && value?.row?.thread === 4) { written = true; older.remember("dedup", 1); }
          return stringify(value, replacer, space);
        }) as typeof JSON.stringify;
        const second = sync.next({ epoch: first.epoch, through: first.through })!;
        assert.equal(second.rows.length, 3);
      } finally { JSON.stringify = stringify; }
      assert.equal(written, true);
      assert.equal(older.said("dedup"), 1);
    } finally { older.close(); sync.close(); }
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("changes committed during adaptive-page encoding reach the receiver in later pages", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-adaptive-change-"));
  const path = join(dir, "index.db");
  const stats = new CommaStats(path, async () => ({ stations: [], unread: [] }), () => () => {});
  const older = new CommaStats(path, async () => ({ stations: [], unread: [] }), () => () => {});
  try {
    const chats = Array.from({ length: 32 }, (_, i) => ({ thread: i + 1, title: i < 12 ? "x".repeat(16_384) : "small", agents: [] }));
    const given = (list: typeof chats) => [{ usage: { rows: [] }, chats: list }];
    stats.apply(given(chats), [], 0);
    const sync = new IndexSync(stats.stats);
    try {
      let held: Held = { epoch: null, through: 0 }, pages = 0, written = false;
      const copy = new Map<string, unknown>();
      const apply = (page: NonNullable<ReturnType<IndexSync["next"]>>) => {
        if (page.reset) copy.clear();
        for (const row of page.rows) row.removed ? copy.delete(row.key) : copy.set(row.key, row.row);
        held = { epoch: page.epoch, through: page.through };
      };
      apply(sync.next(held)!);
      assert.equal(held.through, 3);
      const stringify = JSON.stringify;
      try {
        JSON.stringify = ((value: any, replacer?: any, space?: any) => {
          if (!written && value?.row?.thread === 4) {
            written = true;
            const changed = chats.filter((chat) => chat.thread !== 8).map((chat) =>
              chat.thread === 1 || chat.thread === 4 ? { ...chat, title: "updated" } : chat);
            changed.push({ thread: 33, title: "new", agents: [] });
            older.apply(given(changed), [], 0);
          }
          return stringify(value, replacer, space);
        }) as typeof JSON.stringify;
        apply(sync.next(held)!);
      } finally { JSON.stringify = stringify; }
      assert.equal(written, true);
      for (let page = sync.next(held); page !== null; page = sync.next(held)) {
        apply(page);
        assert.ok(++pages < 30);
      }
      const expected = stats.stats.since(0, 1000).map(statsWire).filter((row) => row !== null && !row.removed);
      const ordered = (entries: [string, unknown][]) => entries.sort(([a], [b]) => a.localeCompare(b));
      assert.deepEqual(ordered([...copy]), ordered(expected.map((row) => [row.key, row.row])));
      assert.equal(held.through, stats.stats.rev());
    } finally { sync.close(); }
  } finally { older.close(); stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a custom encoder retains the original page size and is called once per considered row", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 201; n++) f.add(`chat${n}`, n, JSON.stringify({ thread: n }));
    f.rev(201);
    const calls: number[] = [];
    const wire = (row: IndexRow) => { calls.push(row.rev); return { rev: row.rev }; };
    const sync = new IndexSync(f.index, wire);
    try {
      const first = sync.next({ epoch: null, through: 0 })!;
      assert.equal(first.rows.length, 200);
      assert.deepEqual(calls, Array.from({ length: 200 }, (_, i) => i + 1));
    } finally { sync.close(); }
  } finally { f.db.close(); }
});
