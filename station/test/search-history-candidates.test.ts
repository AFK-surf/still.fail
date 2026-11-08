import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { historySessions, historySessionSnapshot, makeStore, openStore } from "../src/read/store.ts";
import { historyHits } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

test("history search brings only a bounded page of session objects out before an early hit or cancellation", async () => {
  const data = mkdtempSync(join(tmpdir(), "history-candidates-")), store = Store.open(":memory:");
  try {
    store.db.exec("BEGIN");
    for (let i = 0; i < 513; i++) store.insertSession({ key: `s-${i}`, connect: "ember", runtime: "claude",
      profile: "cc", workspace: "/w", token: `token-${i}`, createdAt: i, lastActiveAt: i, ws: "mine" });
    store.setRuntimeSessionId("s-512", "newest");
    store.db.exec("COMMIT");
    const home = join(data, "profile"), dir = join(home, "projects", "w");
    mkdirSync(dir, { recursive: true });
    const record = JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: "needle" }] } });
    writeFileSync(join(dir, "newest.jsonl"), `${record}\n${record}\n`);
    let visited = 0;
    const db = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        return new Proxy(stmt, { get(statement, method) {
          const value = Reflect.get(statement, method, statement);
          if (typeof value !== "function") return value;
          if (method === "all" && /\bsessions\b|history_session_snapshot_/i.test(sql)) return (...args: unknown[]) => {
            const rows = Reflect.apply(value, statement, args) as { key?: unknown }[];
            visited += rows.filter((row) => row.key !== undefined).length;
            return rows;
          };
          return value.bind(statement);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(db, data), asker = { workspace: "mine", home: false, scopes: [] };
    const options = { limit: 1, offset: 0, ms: 10_000, now: () => 0 };
    const found = await historyHits(read, [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    assert.equal(found.hits[0]?.session, "s-512");
    assert.equal(found.more, true);
    assert.ok(visited <= 129, `read ${visited} session rows before finding the first page`);
    visited = 0;
    await assert.rejects(historyHits(read, [], ["needle"], asker, { ...options, cancelled: () => true }), /the search took too long/);
    assert.equal(visited, 0, "an already cancelled search need not read its session candidates");

    const first = historyHits(read, [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    const second = historyHits(read, [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    const snapshots = () => (store.db.prepare("SELECT COUNT(*) AS n FROM sqlite_temp_master WHERE name LIKE 'history_session_snapshot_%'").get() as { n: number }).n;
    assert.equal(snapshots(), 2, "overlapping searches hold separate candidate snapshots");
    const [a, b] = await Promise.all([first, second]);
    assert.deepEqual(a, b);
    assert.equal(snapshots(), 0);
    let checks = 0;
    await assert.rejects(historyHits(read, [], ["needle"], asker, { ...options, cancelled: () => ++checks > 1 }), /the search took too long/);
    assert.equal(snapshots(), 0, "cancellation after snapshot creation releases it");

    store.setRuntimeSessionId("s-512", null);
    store.setRuntimeSessionId("s-385", "newest");
    visited = 0;
    const atBoundary = await historyHits(read, [{ id: "cc", home, runtime: "claude" }], ["needle"], asker, options);
    assert.equal(atBoundary.hits[0]?.session, "s-385");
    assert.ok(visited <= 129, `read ${visited} session rows for a hit at the end of the first page`);
  } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
});

test("history candidate pages retain their original order and snapshot while other connections write", () => {
  const data = mkdtempSync(join(tmpdir(), "history-candidate-pages-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const viewer = { workspace: "mine", home: true };
  let read: ReturnType<typeof openStore> | undefined;
  try {
    writer.db.exec("BEGIN");
    for (let i = 0; i < 320; i++) writer.insertSession({ key: `s-${i}`, connect: i % 2 ? "ember" : "slack", runtime: "claude",
      profile: "cc", workspace: `/w-${i}`, token: `token-${i}`, title: `title-${i}`, createdAt: i, lastActiveAt: i % 3,
      ws: i % 7 === 0 ? "other" : i % 4 === 0 ? "*" : i % 4 === 1 ? null : "mine" });
    writer.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='s-1'").run();
    writer.db.exec("COMMIT");
    read = openStore(data);
    const original = historySessions(read, viewer).map(({ key, workspace, cwd, title }) => ({ key, workspace, cwd, title }));
    const first = historySessionSnapshot(read, viewer);
    assert.equal(first.length, original.length);
    writer.db.prepare("UPDATE sessions SET ws='other', title='changed' WHERE key='s-1'").run();
    const second = historySessionSnapshot(read, viewer);
    const fields = ({ key, workspace, cwd, title }: typeof original[number]) => ({ key, workspace, cwd, title });
    assert.deepEqual([...first].map(fields), original);
    assert.equal([...second].some((row) => row.key === "s-1"), false);
    assert.equal((read.db.prepare("SELECT title FROM sessions WHERE key='s-1'").get() as { title: string }).title, "changed");
    first.close();
    second.close();
    assert.equal((read.db.prepare("SELECT COUNT(*) AS n FROM sqlite_temp_master WHERE name LIKE 'history_session_snapshot_%'").get() as { n: number }).n, 0);

    read.db.exec("BEGIN");
    const inTransaction = historySessionSnapshot(read, viewer);
    assert.ok(inTransaction.length > 128);
    inTransaction.close();
    read.db.exec("ROLLBACK");

    read.db.exec("PRAGMA query_only=ON");
    const fallback = historySessionSnapshot(read, viewer);
    assert.deepEqual([...fallback].map(fields), historySessions(read, viewer).map(fields));
    fallback.close();
  } finally { read?.db.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a history candidate can be ordered by a timestamp outside JavaScript's safe integer range", () => {
  const store = Store.open(":memory:");
  try {
    for (const key of ["large", "ordinary"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws: "mine" });
    store.db.exec("UPDATE sessions SET last_active_at=9007199254740993 WHERE key='large'");
    const snapshot = historySessionSnapshot(makeStore(store.db, "/no-station-config"), { workspace: "mine", home: false });
    try { assert.deepEqual([...snapshot].map((row) => row.key), ["large", "ordinary"]); }
    finally { snapshot.close(); }
  } finally { store.close(); }
});
