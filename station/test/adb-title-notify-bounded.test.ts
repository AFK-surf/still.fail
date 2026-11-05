import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants, TITLE_MEMBER_PROBE, TITLE_ONE_MEMBER, TITLE_SHOWN_MEMBERS } from "../src/adb/grants.ts";

function world(extraMembers = 0) {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE thread_sessions(thread INTEGER NOT NULL, session TEXT NOT NULL, joined_at INTEGER NOT NULL, UNIQUE(thread,session))");
  const members = ["s", ...Array.from({ length: extraMembers }, (_, n) => `other-${n}`)];
  const join = db.prepare("INSERT INTO thread_sessions(thread,session,joined_at) VALUES(1,?,?)");
  members.forEach((session, at) => join.run(session, at));
  let fetched = 0, memberReads = 0, memberRows = 0;
  const queries: { sql: string; args: any[] }[] = [];
  const traced = new Proxy(db, {
    get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        const requests = /\badb_requests\b/i.test(sql), memberships = /\bthread_sessions\b/i.test(sql);
        if (!requests && !memberships) return statement;
        return new Proxy(statement, {
          get(s, p) {
            if (p === "get" && memberships) return (...args: any[]) => {
              const row = s.get(...args); if (row !== undefined) memberRows++; return row;
            };
            if (p === "all") return (...args: any[]) => {
              const rows = s.all(...args);
              if (requests) { fetched += rows.length; queries.push({ sql, args }); }
              if (memberships) memberRows += rows.length;
              return rows;
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
    threadSessions: () => { memberReads++; memberRows += members.length; return members.map((session) => ({ session })); },
    getSession: () => ({ ws: "w", archivedAt: null }),
  } } as any;
  const grants = new PhoneGrants({ db: traced, hub, home: () => "w", now: () => 1_800_000_000_000,
    title: (r) => { named.push(r.id); return title; }, told: (r, _ws, change) => { if (change === "title") told.push(r.id); } });
  const put = db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)");
  const add = (id: string, status: "pending" | "granted" = "pending", session = "s") => {
    const r = { id, session, chat: "CHAT/1", owner: "p@example.test", reason: "test", at: 1, status,
      ...(status === "granted" ? { exp: 1_800_003_600 } : {}) };
    put.run(id, r.session, r.owner, status, JSON.stringify(r));
    return r;
  };
  return { db, grants, add, named, told, queries, fetched: () => fetched, memberReads: () => memberReads, memberRows: () => memberRows,
    reset: () => { fetched = 0; memberReads = 0; memberRows = 0; queries.length = 0; named.length = 0; },
    rename: (next: string) => { title = next; changed!({ type: "thread", id: 1 }); } };
}

test("a changed chat skips members with no shown phone request", () => {
  const reads: number[] = [];
  for (const size of [40, 400]) {
    const w = world(size);
    try {
      w.grants.shown(w.add("known"));
      w.reset(); w.rename("After");
      assert.deepEqual(w.told, ["known"]);
      reads.push(w.memberRows());
    } finally { w.db.close(); }
  }
  assert.equal(reads[0], reads[1], `the change read ${reads[0]}, then ${reads[1]}, memberships`);
});

test("shown requests from unrelated sessions do not increase a short chat's membership work", () => {
  const reads: number[] = [];
  for (const size of [40, 400]) {
    const w = world();
    try {
      w.grants.shown(w.add("known"));
      for (let n = 0; n < size; n++) w.grants.shown(w.add(`other-${n}`, "pending", `elsewhere-${n}`));
      w.reset(); w.rename("After");
      assert.deepEqual(w.told, ["known"]);
      reads.push(w.memberRows());
    } finally { w.db.close(); }
  }
  assert.equal(reads[0], reads[1], `the change read ${reads[0]}, then ${reads[1]}, memberships`);
});

test("shown members are told in membership order even when the shown set is smaller", () => {
  const w = world(5);
  try {
    for (const [id, session] of [["last", "other-3"], ["first", "s"], ["middle", "other-1"]] as const)
      w.grants.shown(w.add(id, "pending", session));
    w.reset(); w.rename("After");
    assert.deepEqual(w.told, ["first", "middle", "last"]);
  } finally { w.db.close(); }
});

test("phone title membership selection seeks the thread and its shown members", () => {
  const w = world();
  try {
    const plan = (sql: string, ...args: any[]) => w.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args).map((row) => String(row.detail)).join(" | ");
    assert.match(plan(TITLE_MEMBER_PROBE, 1, 2), /SEARCH thread_sessions USING INDEX sqlite_autoindex_thread_sessions_1 \(thread=\?\)/);
    assert.match(plan(TITLE_SHOWN_MEMBERS, 1, '["s"]'), /SEARCH m USING INDEX sqlite_autoindex_thread_sessions_1 \(thread=\? AND session=\?\)/);
    assert.match(plan(TITLE_ONE_MEMBER, 1, "s"), /SEARCH thread_sessions USING COVERING INDEX sqlite_autoindex_thread_sessions_1 \(thread=\? AND session=\?\)/);
    assert.match(TITLE_MEMBER_PROBE, /candidates AS MATERIALIZED/);
  } finally { w.db.close(); }
});

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

test("a chat change needs no membership lookup when no request title is shown", () => {
  const w = world();
  try {
    w.add("unseen");
    w.rename("After");
    assert.equal(w.memberReads(), 0);
    assert.equal(w.fetched(), 0);
    assert.deepEqual(w.told, []);
  } finally { w.db.close(); }
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

test("a request changed elsewhere is checked again when it becomes active", () => {
  const w = world();
  try {
    w.grants.shown(w.add("p"));
    const update = w.db.prepare("UPDATE adb_requests SET status=?,body=json_set(body,'$.status',?) WHERE id='p'");
    update.run("denied", "denied");
    w.rename("After");
    assert.deepEqual(w.told, []);
    update.run("pending", "pending");
    w.rename("After");
    assert.deepEqual(w.told, ["p"]);
  } finally { w.db.close(); }
});

test("ending the last shown request removes its title listener", () => {
  const w = world();
  try {
    w.grants.shown(w.add("p"));
    assert.equal(w.grants.revoke("p@example.test", "p", "w"), null);
    w.reset();
    w.rename("After");
    assert.equal(w.memberReads(), 0);
    assert.equal(w.fetched(), 0);
    assert.deepEqual(w.told, []);
  } finally { w.db.close(); }
});
