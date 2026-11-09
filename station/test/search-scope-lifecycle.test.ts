import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { makeStore, openStore } from "../src/read/store.ts";
import { type Asker, pick } from "../src/search/match.ts";
import { SearchScopePreparation } from "../src/search/scope-prepare.ts";
import { readSearchScopePage, SEARCH_ORPHAN_NEXT, SEARCH_SCOPE_NEXT } from "../src/search/scope-read.ts";
import { Search } from "../src/search/search.ts";
import { stationDocs } from "../src/search/sources.ts";
import { Store } from "../src/store/store.ts";

const mine: Asker = { workspace: "mine", home: false, scopes: [] };

test("scope pages merge shared, public and default chats in the original tie order", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["mine", "mine"], ["away", "away"], ["public", "*"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (let i = 0; i < 600; i++) {
      const owner = (["mine", "public", null, "away"] as const)[i % 4] ?? null;
      const thread = store.openThreadOf("ember", "CHAT", `page-${i}`, "needle", null, owner);
      if (owner !== null) store.joinThread(thread.id, owner, "ember");
      if (owner === "mine") store.joinThread(thread.id, "public", "ember");
    }
    db.exec("UPDATE threads SET created_at = 1");
    const preparation = new SearchScopePreparation(db);
    while (!preparation.step().done) { /* Prepare the candidate ranges. */ }
    const read = makeStore(db, ".");
    for (const home of [false, true]) {
      const asker = { ...mine, home };
      for (const offset of [0, 125, 255, 300]) {
        const options = { limit: 80, offset };
        const baseline = pick(stationDocs(read, ".", {}, new Set(["chat"])), ["needle"], asker, options);
        const found = pick(stationDocs(read, ".", {}, new Set(["chat"]), asker), ["needle"], asker, options);
        assert.deepEqual(found, baseline, `home=${home} offset=${offset}`);
      }
    }
  } finally { store.close(); }
});

test("the search worker requests preparation before answering and only while it is needed", async () => {
  const data = mkdtempSync(join(tmpdir(), "search-scope-signal-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let worker: Worker | undefined;
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const thread = writer.openThreadOf("ember", "CHAT", "chat", "needle", null, "s").id;
    writer.joinThread(thread, "s", "ember");
    worker = new Worker(new URL("../src/search/worker.ts", import.meta.url), { workerData: { data } });
    const tell = (id: number) => worker!.postMessage({ type: "query", id, query: "needle", asker: mine, kinds: ["chat"] });
    tell(1);
    const [pending] = await once(worker, "message") as [{ scopePending?: boolean }];
    assert.equal(pending.scopePending, true);
    const [first] = await once(worker, "message") as [{ id?: number }];
    assert.equal(first.id, 1);
    const preparation = new SearchScopePreparation(writer.db);
    while (!preparation.step().done) { /* The next query can use its index. */ }
    tell(2);
    const [ready] = await once(worker, "message") as [{ id?: number; scopePending?: boolean }];
    assert.equal(ready.id, 2);
    assert.equal(ready.scopePending, undefined);
  } finally {
    await worker?.terminate();
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("prepared search agrees with the original documents through scope changes and unusual identities", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const [key, ws] of [["mine", "mine"], ["away", "away"], ["public", "*"], ["old", null],
      ["unicode", "工作区"], ["nul\0member", "mine"], ["surrogate\ud800", "mine"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const chat = (key: string, home: string | null, ...members: string[]) => {
      const id = store.openThreadOf("ember", "CHAT", key, "needle", null, home).id;
      for (const member of members) store.joinThread(id, member, "ember");
      return id;
    };
    chat("home-not-member", "away", "mine");
    chat("public", "public", "public");
    chat("old", "away", "old");
    chat("orphan", "away");
    chat("unknown", "away", "missing");
    chat("unicode", "unicode", "unicode");
    chat("nul", "away", "nul\0member");
    chat("surrogate", "away", "surrogate\ud800");
    const moving = chat("moving", "away", "away");
    const read = makeStore(db, "."), preparation = new SearchScopePreparation(db, 2);
    const drain = () => {
      let done = false;
      for (let i = 0; i < 500 && !done; i++) done = preparation.step().done;
      assert.ok(done);
    };
    const compare = () => {
      for (const asker of [mine, { ...mine, home: true }, { ...mine, workspace: "*" }, { ...mine, workspace: "工作区" }]) {
        const baseline = pick(stationDocs(read, ".", {}, new Set(["chat"])), ["needle"], asker, { limit: 20 });
        const actual = pick(stationDocs(read, ".", {}, new Set(["chat"]), asker), ["needle"], asker, { limit: 20 });
        assert.deepEqual(actual, baseline, `workspace=${asker.workspace} home=${asker.home}`);
      }
    };
    compare();
    drain();
    compare();
    db.prepare("UPDATE sessions SET ws = 'mine' WHERE key = 'away'").run();
    assert.equal(readSearchScopePage(db, mine, null, moving, 20), null, "a changed session cannot use stale candidates");
    compare();
    // A second move while the first is being repaired must restart its member walk.
    preparation.step();
    db.prepare("UPDATE sessions SET ws = 'away' WHERE key = 'away'").run();
    drain();
    compare();
    store.joinThread(moving, "mine", "ember");
    db.prepare("UPDATE threads SET home = 'mine' WHERE id = ?").run(moving);
    compare();
    db.prepare("DELETE FROM sessions WHERE key = 'mine'").run();
    assert.equal(readSearchScopePage(db, mine, null, moving, 20), null);
    drain();
    compare();

    const scopePlan = (db.prepare(`EXPLAIN QUERY PLAN ${SEARCH_SCOPE_NEXT}`).all(1, "mine", 0, moving, 10) as { detail: string }[])
      .map((row) => row.detail).join("\n");
    const orphanPlan = (db.prepare(`EXPLAIN QUERY PLAN ${SEARCH_ORPHAN_NEXT}`).all(0, moving, 10) as { detail: string }[])
      .map((row) => row.detail).join("\n");
    assert.match(scopePlan, /SEARCH search_scope_threads USING PRIMARY KEY \(kind=\? AND ws=\? AND thread>\? AND thread<\?\)/);
    assert.match(orphanPlan, /SEARCH search_scope_orphans USING INTEGER PRIMARY KEY \(rowid>\? AND rowid<\?\)/);
    assert.doesNotMatch(`${scopePlan}\n${orphanPlan}`, /USE TEMP B-TREE/);
  } finally { store.close(); }
});

test("a search remains available during handover and prepares its scope in the background", async () => {
  const data = mkdtempSync(join(tmpdir(), "search-scope-worker-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const previous = Promise.withResolvers<void>();
  const priority = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 2));
  const search = new Search({ data, backfill: { previousGone: previous.promise, priority: priority.buffer } });
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const thread = writer.openThreadOf("ember", "CHAT", "chat", "needle", null, "s").id;
    writer.joinThread(thread, "s", "ember");
    search.start();
    const query = () => search.query("needle", mine, { kinds: ["chat"] });
    const keys = (found: Awaited<ReturnType<typeof query>>) => found.groups.flatMap((group) => group.hits.map((hit) => hit.key));
    assert.deepEqual(keys(await query()), [`c:${thread}`]);
    assert.equal(writer.db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'search_scope_meta'").get(), undefined);
    priority[0] = 1;
    previous.resolve();
    assert.deepEqual(keys(await query()), [`c:${thread}`], "a foreground write does not hold up the old read");
    priority[0] = 0;
    const waitReady = async () => {
      const end = Date.now() + 10_000;
      while (readSearchScopePage(writer.db, mine, null, thread, 10) === null) {
        if (Date.now() >= end) throw new Error("search scope preparation did not finish");
        await delay(10);
      }
    };
    await waitReady();
    assert.deepEqual(readSearchScopePage(writer.db, mine, null, thread, 10), [thread]);
    writer.db.prepare("UPDATE sessions SET ws = 'away' WHERE key = 's'").run();
    assert.equal(readSearchScopePage(writer.db, mine, null, thread, 10), null);
    assert.deepEqual(keys(await query()), [], "the old path checks the current session while repair waits");
    await waitReady();
    assert.deepEqual(readSearchScopePage(writer.db, mine, null, thread, 10), []);
  } finally {
    priority[0] = 0;
    previous.resolve();
    await search.stop();
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("scope readiness and its candidates use one snapshot, then the chat's visibility is checked again", () => {
  const data = mkdtempSync(join(tmpdir(), "search-scope-snapshot-"));
  const writer = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  let reader: ReturnType<typeof openStore> | null = null;
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    const thread = writer.openThreadOf("ember", "CHAT", "chat", "needle", null, "s").id;
    writer.joinThread(thread, "s", "ember");
    const preparation = new SearchScopePreparation(writer.db);
    while (!preparation.step().done) { /* Prepare the candidate. */ }
    reader = openStore(data);
    let moved = false;
    const db = new Proxy(reader.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        return new Proxy(stmt, { get(statement, method) {
          const value = Reflect.get(statement, method, statement);
          if (typeof value !== "function") return value;
          if (method === "get" && sql.startsWith("SELECT version, threads_done")) return (...args: unknown[]) => {
            const result = Reflect.apply(value, statement, args);
            if (!moved) { moved = true; writer.db.prepare("UPDATE sessions SET ws = 'away' WHERE key = 's'").run(); }
            return result;
          };
          return value.bind(statement);
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(pick(stationDocs({ ...reader, db }, data, {}, new Set(["chat"]), mine), ["needle"], mine), []);
    assert.ok(moved);
    assert.equal(readSearchScopePage(reader.db, mine, null, thread, 10), null, "the next snapshot sees the dirty session");
  } finally {
    reader?.db.close();
    writer.close();
    rmSync(data, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) test(`an older connection's replacements are repaired during preparation (recursive triggers ${recursive})`, () => {
  const data = mkdtempSync(join(tmpdir(), "search-scope-old-writer-")), path = join(data, "stillfail.db");
  const writer = Store.open(path, join(data, "archive")), old = new DatabaseSync(path);
  try {
    old.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [key, ws] of [["a", "mine"], ["b", "away"]] as const)
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: 1, lastActiveAt: 1, ws });
    const first = writer.openThreadOf("ember", "CHAT", "first", "needle", null, "a").id;
    const second = writer.openThreadOf("ember", "CHAT", "second", "needle", null, "b").id;
    writer.joinThread(first, "a", "ember");
    writer.joinThread(second, "b", "ember");
    const rowid = (old.prepare("SELECT rowid AS n FROM thread_sessions WHERE thread = ? AND session = 'a'").get(first) as { n: number }).n;
    // These statements were prepared by the old process before the new writers were installed.
    const replaceMember = old.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES (?,?,?,'ember',1)");
    const replaceSession = old.prepare("UPDATE OR REPLACE sessions SET token = ? WHERE key = ?");
    const move = old.prepare("UPDATE sessions SET ws = ? WHERE key = ?");
    const preparation = new SearchScopePreparation(writer.db, 1);
    for (let i = 0; i < 3; i++) preparation.step();
    replaceMember.run(rowid, second, "a");
    move.run("mine", "b");
    let done = false;
    for (let i = 0; i < 300 && !done; i++) done = preparation.step().done;
    assert.ok(done);
    const reader = openStore(data);
    try {
      const compare = () => assert.deepEqual(
        pick(stationDocs(reader, data, {}, new Set(["chat"]), mine), ["needle"], mine, { limit: 10 }),
        pick(stationDocs(reader, data, {}, new Set(["chat"])), ["needle"], mine, { limit: 10 }));
      compare();
      // Evict b through its unique token; its former memberships now refer to a missing session.
      replaceSession.run("b", "a");
      assert.equal(readSearchScopePage(reader.db, mine, null, second, 10), null);
      done = false;
      for (let i = 0; i < 300 && !done; i++) done = preparation.step().done;
      assert.ok(done);
      compare();
      reader.db.exec("BEGIN");
      try { assert.ok(readSearchScopePage(reader.db, mine, null, second, 10)); }
      finally { reader.db.exec("ROLLBACK"); }
    } finally { reader.db.close(); }
  } finally { old.close(); writer.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a failed old-membership batch rolls its cursor and candidates back together", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/work",
      token: "s", createdAt: 1, lastActiveAt: 1, ws: "mine" });
    for (let i = 0; i < 3; i++) {
      const id = store.openThread("ember", "CHAT", `old-${i}`, "needle", null).id;
      store.joinThread(id, "s", "ember");
    }
    const preparation = new SearchScopePreparation(db, 1);
    preparation.step();
    db.exec("CREATE TRIGGER fail_search_scope BEFORE INSERT ON search_scope_members BEGIN SELECT RAISE(ABORT, 'scope batch failed'); END");
    let failed = false;
    for (let i = 0; i < 20 && !failed; i++) {
      const before = { ...db.prepare("SELECT * FROM search_scope_meta WHERE id = 1").get() };
      const count = db.prepare("SELECT COUNT(*) AS n FROM search_scope_members").get()?.n;
      try { preparation.step(); }
      catch (error) {
        assert.match(String(error), /scope batch failed/);
        assert.deepEqual({ ...db.prepare("SELECT * FROM search_scope_meta WHERE id = 1").get() }, before);
        assert.equal(db.prepare("SELECT COUNT(*) AS n FROM search_scope_members").get()?.n, count);
        failed = true;
      }
    }
    assert.ok(failed);
    db.exec("DROP TRIGGER fail_search_scope");
    let done = false;
    for (let i = 0; i < 100 && !done; i++) done = preparation.step().done;
    assert.ok(done);
    assert.equal(readSearchScopePage(db, mine, null, 3, 10)?.length, 3);
  } finally { store.close(); }
});
