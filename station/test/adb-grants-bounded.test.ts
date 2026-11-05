import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";

function fixture(pending: number, granted: boolean) {
  const db = new DatabaseSync(":memory:");
  let fetched = 0;
  // Count rows actually returned to the grants reader, without changing its SQL or query plan.
  const traced = new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!/FROM adb_requests WHERE session\s*=\s*\?/.test(sql)) return statement;
        return new Proxy(statement, {
          get(s, p) {
            if (p === "all") return (...args: any[]) => { const rows = s.all(...args); fetched += rows.length; return rows; };
            if (p === "get") return (...args: any[]) => { const row = s.get(...args); if (row !== undefined) fetched++; return row; };
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
  const grants = new PhoneGrants({ db: traced, hub, home: () => "w", title: () => null, now: () => 1_800_000_000_000 });
  const put = db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)");
  const add = (id: string, status: "pending" | "granted") => {
    const body = { id, session: "s", chat: "CHAT/1", owner: "p@example.test", reason: "test", at: 1,
      status, thread: 1, cardTs: "card", ...(status === "granted" ? { exp: 1_800_003_600 } : {}) };
    put.run(id, "s", "p@example.test", status, JSON.stringify(body));
  };
  for (let n = 0; n < pending; n++) add(`p-${n}`, "pending");
  if (granted) add("live", "granted");
  return { db, grants, reset: () => { fetched = 0; }, fetched: () => fetched };
}

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
