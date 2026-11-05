import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";

function world() {
  const db = new DatabaseSync(":memory:");
  let fetched = 0;
  const queries: { sql: string; args: any[] }[] = [];
  const traced = new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!/\badb_requests\b/i.test(sql)) return statement;
        return new Proxy(statement, {
          get(s, p) {
            if (p === "all") return (...args: any[]) => {
              const rows = s.all(...args); fetched += rows.length; queries.push({ sql, args }); return rows;
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
  let changed: ((event: { type: string; id?: number }) => void) | undefined;
  let title = "Before";
  const named: string[] = [], told: string[] = [];
  const hub = { store: {
    subscribe: (f: typeof changed) => { changed = f; },
    threadSessions: () => [{ session: "s" }],
    getSession: () => ({ ws: "w", archivedAt: null }),
  } } as any;
  const grants = new PhoneGrants({ db: traced, hub, home: () => "w", now: () => 1_800_000_000_000,
    title: (r) => { named.push(r.id); return title; }, told: (r, _ws, change) => { if (change === "title") told.push(r.id); } });
  const put = db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)");
  const add = (id: string, status: "pending" | "granted" = "pending") => {
    const r = { id, session: "s", chat: "CHAT/1", owner: "p@example.test", reason: "test", at: 1, status,
      ...(status === "granted" ? { exp: 1_800_003_600 } : {}) };
    put.run(id, r.session, r.owner, status, JSON.stringify(r));
    return r;
  };
  return { db, grants, add, named, told, queries, fetched: () => fetched,
    reset: () => { fetched = 0; queries.length = 0; named.length = 0; },
    rename: (next: string) => { title = next; changed!({ type: "thread", id: 1 }); } };
}

test("a changed chat reads only the phone request titles already shown", () => {
  const reads: number[] = [], nameCounts: number[] = [], renamedReads: number[] = [], plans: string[] = [];
  for (const size of [40, 400]) {
    const w = world();
    try {
      const known = w.add("known");
      for (let n = 0; n < size; n++) w.add(`old-${n}`);
      w.grants.shown(known);
      w.reset();
      w.rename("Before");
      reads.push(w.fetched());
      nameCounts.push(w.named.length);
      assert.deepEqual(w.told, []);
      w.reset();
      w.rename("After");
      assert.deepEqual(w.told, ["known"]);
      renamedReads.push(w.fetched());
      assert.equal(w.queries.length, 1);
      const { sql, args } = w.queries[0]!;
      plans.push(w.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args).map((r) => String(r.detail)).join(" | "));
    } finally { w.db.close(); }
  }
  assert.deepEqual(reads, [1, 1]);
  assert.deepEqual(nameCounts, [1, 1]);
  assert.deepEqual(renamedReads, [1, 1]);
  for (const plan of plans) assert.match(plan, /SEARCH .* USING INDEX sqlite_autoindex_adb_requests_1 \(id=\?\)/);
});

test("changed titles keep the order of the existing requests", () => {
  const w = world();
  try {
    const p1 = w.add("p1"), g1 = w.add("g1", "granted"), p2 = w.add("p2"), g2 = w.add("g2", "granted");
    for (const request of [g2, p2, g1, p1]) w.grants.shown(request);
    w.reset();
    w.rename("After");
    assert.deepEqual(w.told, ["g1", "g2", "p1", "p2"]);
  } finally { w.db.close(); }
});
