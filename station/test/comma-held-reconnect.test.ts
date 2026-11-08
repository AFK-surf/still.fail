// Two independent Comma copies, applying pages by the receiver's epoch, reset and revision rules.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CommaStats, IndexSync, RevIndex, nextPage, probePage, type Held, type Page } from "../src/comma/stats.ts";

class Copy {
  held: Held = { epoch: null, through: 0 };
  rows = new Map<string, unknown>();
  apply(page: Page): Held {
    if (!page.reset && (page.epoch !== this.held.epoch || page.since > this.held.through)) return this.held;
    if (page.reset) this.rows.clear();
    for (const row of page.rows) {
      if (!page.reset && row.rev <= this.held.through) continue;
      if (row.removed) this.rows.delete(row.key);
      else this.rows.set(row.key, row.row);
    }
    this.held = { epoch: page.epoch, through: page.reset ? page.through : Math.max(this.held.through, page.through) };
    return this.held;
  }
}

function follow(index: RevIndex, reader: IndexSync, copy: Copy): Page[] {
  let held = copy.apply(probePage(index));
  const pages: Page[] = [];
  for (let page = reader.next(held); page !== null; page = reader.next(held)) {
    assert.ok(pages.length < 10, "the reader must make progress");
    pages.push(page);
    held = copy.apply(page);
  }
  return pages;
}

function open(db: DatabaseSync) {
  db.exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
  return new RevIndex(db, "stats_index");
}

const row = (i: number) => ({ kind: "task", json: JSON.stringify({ creator: `person${i}` }) });

test("an upgrading station opens the existing index while the old writer holds its lock", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-held-upgrade-")), path = join(dir, "comma-stats.db");
  const nothing = async () => ({ stations: [], unread: [] });
  const quiet = () => () => {};
  const prior = CommaStats.at(dir, nothing, quiet);
  prior.close();
  const old = new DatabaseSync(path);
  let next: CommaStats | undefined;
  try {
    old.exec("BEGIN IMMEDIATE");
    const opened = CommaStats.at(dir, nothing, quiet, new Promise(() => {}));
    next = opened;
    assert.throws(() => new IndexSync(opened.stats), /locked/);
    old.exec("ROLLBACK");
    new IndexSync(opened.stats).close();
    new IndexSync(opened.tasks).close();
    assert.equal((old.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type = 'trigger' AND name IN ('stats_index_pruned', 'task_index_pruned')").get() as { n: number }).n, 2);
  } finally {
    try { old.exec("ROLLBACK"); } catch {}
    next?.close(); old.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a reconnecting Comma resets when another copy pruned a tombstone it missed", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), a = new Copy(), b = new Copy();
    index.write(new Map([["chat", row(1)]]), () => true);
    const first = new IndexSync(index), second = new IndexSync(index);
    follow(index, first, a); follow(index, second, b);
    assert.equal(b.rows.size, 1);
    second.close();
    index.write(new Map(), () => true);
    follow(index, first, a);
    assert.equal(index.pruned(), index.rev());
    const reconnected = new IndexSync(index);
    const pages = follow(index, reconnected, b);
    assert.deepEqual(pages.map((p) => p.reset), [true]);
    assert.deepEqual([...b.rows], [...a.rows]);
    first.close(); reconnected.close();
  } finally { db.close(); }
});

test("a reconnecting copy that already held the pruned deletion continues without a reset", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), a = new Copy(), b = new Copy();
    index.write(new Map([["chat", row(1)]]), () => true);
    const first = new IndexSync(index), second = new IndexSync(index);
    follow(index, first, a); follow(index, second, b);
    index.write(new Map(), () => true);
    follow(index, first, a); follow(index, second, b);
    assert.equal(index.pruned(), b.held.through);
    second.close();
    index.write(new Map([["new", row(2)]]), () => true);
    follow(index, first, a);
    const resumed = new IndexSync(index);
    assert.deepEqual(follow(index, resumed, b).map((p) => p.reset), [false]);
    assert.deepEqual([...b.rows], [...a.rows]);
    first.close(); resumed.close();
  } finally { db.close(); }
});

test("a receiver ahead of a restored database resets even if its epoch matches", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), copy = new Copy();
    index.write(new Map([["chat", row(1)]]), () => true);
    copy.held = { epoch: index.epoch(), through: index.rev() + 10 };
    copy.rows.set("stale", {});
    const reader = new IndexSync(index);
    assert.deepEqual(follow(index, reader, copy).map((p) => p.reset), [true]);
    assert.equal(copy.rows.has("stale"), false);
    assert.equal(copy.rows.size, 1);
    reader.close();
  } finally { db.close(); }
});

test("a prune floor ahead of the database revision cannot restart a reset forever", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), copy = new Copy();
    index.write(new Map([["chat", row(1)]]), () => true);
    copy.held = { epoch: index.epoch(), through: 0 };
    db.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.pruned', '500')").run();
    const reader = new IndexSync(index);
    assert.deepEqual(follow(index, reader, copy).map((p) => p.reset), [true]);
    assert.equal(copy.rows.size, 1);
    reader.close();
  } finally { db.close(); }
});

test("a reset covering several pages only clears the receiver once, even after an interrupted reset", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), a = new Copy(), b = new Copy();
    const rows = new Map(Array.from({ length: 250 }, (_, i) => [`chat${i}`, row(i)]));
    index.write(rows, () => true);
    const first = new IndexSync(index), second = new IndexSync(index);
    follow(index, first, a); follow(index, second, b);
    second.close();
    rows.delete("chat249"); index.write(rows, () => true);
    follow(index, first, a);
    assert.ok(index.pruned() > 200);
    const interrupted = new IndexSync(index);
    const held = b.apply(probePage(index));
    const page = interrupted.next(held)!;
    assert.equal(page.reset, true);
    assert.equal(page.rows.length, 200);
    b.apply(page);
    interrupted.close();
    const resumed = new IndexSync(index);
    const pages = follow(index, resumed, b);
    assert.deepEqual(pages.map((p) => p.reset), [true, false]);
    assert.equal(b.rows.size, 249);
    assert.deepEqual([...b.rows.keys()].sort(), [...a.rows.keys()].sort());
    first.close(); resumed.close();
  } finally { db.close(); }
});

test("a socket still paging protects its unread tombstones, including when an older socket closes", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), a = new Copy(), b = new Copy();
    index.write(new Map([["chat", row(1)]]), () => true);
    const first = new IndexSync(index), old = new IndexSync(index);
    follow(index, first, a); follow(index, old, b);
    const replacing = new IndexSync(index);
    old.close();
    index.write(new Map(), () => true);
    follow(index, first, a);
    assert.equal(index.since(0, 10).filter((r) => r.removed).length, 1);
    const pages = follow(index, replacing, b);
    assert.deepEqual(pages.map((p) => p.reset), [false]);
    assert.equal(b.rows.size, 0);
    first.close(); replacing.close();
  } finally { db.close(); }
});

test("a reset starts again if an older writer prunes a newer tombstone while it is paging", () => {
  const db = new DatabaseSync(":memory:");
  try {
    const index = open(db), a = new Copy(), b = new Copy();
    const rows = new Map(Array.from({ length: 250 }, (_, i) => [`chat${i}`, row(i)]));
    index.write(rows, () => true);
    const first = new IndexSync(index), second = new IndexSync(index);
    follow(index, first, a); follow(index, second, b);
    second.close();
    rows.delete("chat249"); index.write(rows, () => true);
    follow(index, first, a);
    const resumed = new IndexSync(index);
    const page = resumed.next(b.apply(probePage(index)))!;
    assert.equal(page.reset, true);
    const held = b.apply(page);
    rows.delete("chat0"); index.write(rows, () => true);
    // A pre-upgrade process does not know about this socket's position, but its delete still updates the floor.
    db.exec("DELETE FROM stats_index WHERE removed = 1");
    const restarted = resumed.next(held)!;
    assert.equal(restarted.reset, true);
    b.apply(restarted);
    let steps = 0;
    for (let next = resumed.next(b.held); next !== null; next = resumed.next(b.held)) {
      assert.ok(++steps < 10, "the restarted reset must finish");
      b.apply(next);
    }
    assert.equal(b.rows.size, 248);
    assert.equal(b.rows.has(page.rows[0]!.key), false);
    first.close(); resumed.close();
  } finally { db.close(); }
});

test("a prune by an older connection records the floor transactionally and survives reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-pruned-")), path = join(dir, "stats.db");
  const db = new DatabaseSync(path), old = new DatabaseSync(path);
  try {
    const index = open(db);
    // The older process may have prepared this before the new process installs the trigger.
    const prune = old.prepare("DELETE FROM stats_index WHERE removed = 1");
    new IndexSync(index).close();
    index.write(new Map([["chat", row(1)]]), () => true);
    index.write(new Map(), () => true);
    old.exec("BEGIN IMMEDIATE"); prune.run(); old.exec("ROLLBACK");
    assert.equal(index.pruned(), 0);
    prune.run();
    assert.equal(index.pruned(), 2);
    db.close(); old.close();
    const reopened = new DatabaseSync(path);
    try { assert.equal(open(reopened).pruned(), 2); } finally { reopened.close(); }
  } finally { try { db.close(); } catch {} try { old.close(); } catch {} rmSync(dir, { recursive: true, force: true }); }
});

test("the floor and rows come from one snapshot when another connection prunes between them", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-prune-snapshot-")), path = join(dir, "stats.db");
  const db = new DatabaseSync(path), other = new DatabaseSync(path);
  try {
    db.exec("PRAGMA journal_mode = WAL");
    const index = open(db);
    new IndexSync(index).close();
    index.write(new Map([["chat", row(1)]]), () => true);
    const epoch = index.epoch();
    index.write(new Map(), () => true);
    const pruned = index.pruned.bind(index);
    let visited = false;
    index.pruned = () => {
      const floor = pruned();
      if (!visited) { visited = true; other.exec("DELETE FROM stats_index WHERE removed = 1"); }
      return floor;
    };
    const page = nextPage(index, { epoch, through: 1 });
    assert.equal(visited, true);
    assert.deepEqual(page?.rows.map((r) => r.removed), [true]);
    assert.equal(pruned(), 2);
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("encoding a page releases its snapshot so another connection can write", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-snapshot-")), path = join(dir, "stats.db");
  const db = new DatabaseSync(path), other = new DatabaseSync(path);
  try {
    const index = open(db);
    index.write(new Map([["chat", row(1)]]), () => true);
    const page = nextPage(index, { epoch: null, through: 0 }, (entry) => {
      other.prepare("INSERT INTO meta (key, value) VALUES ('other', 'written')").run();
      return { key: entry.key, rev: entry.rev };
    });
    assert.equal(page?.rows.length, 1);
    assert.equal((db.prepare("SELECT value FROM meta WHERE key = 'other'").get() as { value: string }).value, "written");
  } finally { other.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
