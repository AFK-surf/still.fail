import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";

function fixture(pending: number, granted: boolean) {
  const db = new DatabaseSync(":memory:");
  let fetched = 0;
  let ownerFetched = 0;
  let titles = 0;
  const queries: string[] = [];
  // Count rows actually returned to the grants reader, without changing its SQL or query plan.
  const traced = new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        const bySession = /FROM adb_requests WHERE session\s*=\s*\?/.test(sql);
        const byOwner = /FROM adb_requests WHERE owner\s*=\s*\?/.test(sql);
        if (!bySession && !byOwner) return statement;
        if (bySession) queries.push(sql);
        return new Proxy(statement, {
          get(s, p) {
            if (p === "all") return (...args: any[]) => {
              const rows = s.all(...args);
              if (bySession) fetched += rows.length;
              if (byOwner) ownerFetched += rows.length;
              return rows;
            };
            if (p === "get") return (...args: any[]) => {
              const row = s.get(...args);
              if (row !== undefined && bySession) fetched++;
              if (row !== undefined && byOwner) ownerFetched++;
              return row;
            };
            const value = Reflect.get(s, p, s);
            return typeof value === "function" ? value.bind(s) : value;
          },
        });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const thread = { connect: "c", thread: { id: 1, channel: "CHAT", threadTs: "1", surface: "ember" } };
  const hub = {
    store: {
      subscribe: () => {}, getSession: () => ({ ws: "w", archivedAt: null }), starter: () => "p@example.test",
      latestThread: () => thread, sessionThreadById: () => thread, pendingCard: () => null,
    },
  } as any;
  const grants = new PhoneGrants({ db: traced, hub, home: () => "w", title: () => { titles++; return null; }, now: () => 1_800_000_000_000 });
  const put = db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)");
  const add = (id: string, status: "pending" | "granted") => {
    const body = { id, session: "s", chat: "CHAT/1", owner: "p@example.test", reason: "test", at: 1,
      status, thread: 1, cardTs: "card", ...(status === "granted" ? { exp: 1_800_003_600 } : {}) };
    put.run(id, "s", "p@example.test", status, JSON.stringify(body));
  };
  for (let n = 0; n < pending; n++) add(`p-${n}`, "pending");
  if (granted) add("live", "granted");
  return { db, grants, queries, reset: () => { fetched = 0; ownerFetched = 0; titles = 0; queries.length = 0; },
    fetched: () => fetched, ownerFetched: () => ownerFetched, titles: () => titles };
}

test("a phone link change only reads live grants and does not compute request titles", () => {
  const reads: number[] = [], named: number[] = [];
  for (const pending of [40, 400]) {
    const w = fixture(pending, true);
    try {
      w.db.prepare("UPDATE adb_requests SET body=json_set(body,'$.link','connected') WHERE id='live'").run();
      w.reset();
      w.grants.linked("P@EXAMPLE.TEST", { adb: "connected" });
      reads.push(w.ownerFetched());
      named.push(w.titles());
    } finally { w.db.close(); }
  }
  assert.deepEqual({ reads, named }, { reads: [1, 1], named: [0, 0] });
});

test("the internal owner grant list ignores pending requests and does not mark titles shown", () => {
  const reads: number[] = [], named: number[] = [];
  for (const pending of [40, 400]) {
    const w = fixture(pending, true);
    try {
      w.reset();
      assert.deepEqual(w.grants.grantedOfOwner("P@EXAMPLE.TEST").map((r) => r.id), ["live"]);
      reads.push(w.ownerFetched());
      named.push(w.titles());
    } finally { w.db.close(); }
  }
  assert.deepEqual({ reads, named }, { reads: [1, 1], named: [0, 0] });
});

test("internal owner grants seek the existing owner and status index", () => {
  const w = fixture(2, true);
  try {
    const plan = w.db.prepare("EXPLAIN QUERY PLAN SELECT body FROM adb_requests WHERE owner = ? AND status = 'granted'")
      .all("p@example.test").map((row) => String(row.detail)).join(" | ");
    assert.match(plan, /SEARCH adb_requests USING INDEX adb_requests_by_owner \(owner=\? AND status=\?\)/);
    assert.doesNotMatch(plan, /SCAN |TEMP B-TREE/);
  } finally { w.db.close(); }
});

test("finding a held phone grant does not read the session's pending requests", () => {
  const reads: number[] = [];
  for (const pending of [40, 400]) {
    const w = fixture(pending, true);
    try {
      w.reset();
      assert.deepEqual(w.grants.held("s").map((r) => r.id), ["live"]);
      reads.push(w.fetched());
    } finally { w.db.close(); }
  }
  assert.deepEqual(reads, [1, 1]);
});

test("reusing a pending phone request reads only the one it returns", async () => {
  const reads: number[] = [];
  for (const pending of [40, 400]) {
    const w = fixture(pending, false);
    try {
      w.reset();
      assert.equal((await w.grants.ask("s", "again")).id, "p-0");
      reads.push(w.fetched());
    } finally { w.db.close(); }
  }
  assert.deepEqual(reads, [1, 1]);
});

test("phone request status reads seek the existing session and status index", async () => {
  const w = fixture(3, false);
  try {
    w.reset();
    await w.grants.ask("s", "again");
    assert.equal(w.queries.length, 2);
    for (const sql of w.queries) {
      const plan = w.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s").map((row) => row.detail).join(" | ");
      assert.match(plan, /SEARCH adb_requests USING INDEX adb_requests_by_session \(session=\? AND status=\?\)/);
      assert.doesNotMatch(plan, /TEMP B-TREE/);
    }
  } finally { w.db.close(); }
});
