import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { setTimeout as pause } from "node:timers/promises";
import { pathToFileURL } from "node:url";
import { askingMessage, makeStore } from "../src/read/store.ts";
import { legacyAgentDrain, legacyAgentStep } from "../src/store/legacy-agent-build.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { addTellIndexes } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { withoutSaidState } from "./legacy-message-fixture.ts";

test("an old database does not build the agent-time lookup in an unbounded write", () => {
  const counts: number[] = [];
  for (const size of [40,400]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember","CHAT",`old-agent-${size}`,null,null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message',?,?,?)");
      for (let n=1;n<=size;n++) put.run(thread,n,n%2 ? "person" : "agent","a",n);
      db.exec("DROP INDEX entries_said; DROP INDEX entries_agent_at");
      let writing = false, largest = 0, builds = 0;
      const seen = new Set<string>();
      db.function("visit_agent_build", { deterministic: true }, (n) => { if (writing) seen.add(String(n)); return n; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE") { writing = true; seen.clear(); }
          if (sql.includes("CREATE INDEX IF NOT EXISTS entries_agent_at")) {
            const traced = sql.replace("WHERE kind = 'message' AND author_kind = 'agent'",
              "WHERE visit_agent_build(n) IS NOT NULL AND kind = 'message' AND author_kind = 'agent'");
            assert.notEqual(traced,sql);
            builds++;
            sql = traced;
          }
          const result = target.exec(sql);
          if (sql === "COMMIT" || sql === "ROLLBACK") { largest = Math.max(largest,seen.size); writing = false; }
          return result;
        };
        if (property === "prepare") return (sql: string) => target.prepare(sql === "SELECT 1 FROM entries LIMIT 1 OFFSET 63"
          ? "SELECT 1 FROM entries WHERE visit_agent_build(n) IS NOT NULL LIMIT 1 OFFSET 63" : sql);
        const value = Reflect.get(target,property,target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      addTellIndexes(observed);
      assert.equal(builds,size < 64 ? 1 : 0);
      counts.push(largest);
    } finally { store.close(); }
  }
  assert.deepEqual(counts,[40,64]);
});

for (const winner of ["old writes","native index"]) test(`agent-time installation rechecks the ${winner} before taking a writer`, () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-start-")), path = join(dir,"store.db");
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember","CHAT","old-agent-race",null,null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
  for (let n=1;n<=(winner === "old writes" ? 40 : 100);n++) put.run(thread,n,n);
  db.exec("DROP INDEX entries_agent_at");
  const old = new DatabaseSync(path,{ timeout: 5000 });
  try {
    let begins = 0;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        if (sql === "BEGIN IMMEDIATE") {
          begins++;
          if (winner === "old writes" && begins === 1) {
            old.exec("BEGIN");
            const insert = old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
            for (let n=41;n<=100;n++) insert.run(thread,n,n);
            old.exec("COMMIT");
          } else if (winner === "native index" && begins === 2) old.exec(`CREATE INDEX entries_agent_at
            ON entries(thread,at) WHERE kind='message' AND author_kind='agent'`);
        }
        return target.exec(sql);
      };
      const value = Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    addTellIndexes(observed);
    assert.equal(begins,2);
    const native = db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_agent_at'").get();
    const staged = db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='legacy_agent_meta'").get();
    assert.equal(native !== undefined,winner === "native index");
    assert.equal(staged !== undefined,winner === "old writes");
  } finally { old.close(); store.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("an old store answers a turn's question while its time lookup is prepared", () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-live-")), path = join(dir,"store.db");
  const initial = Store.open(path), thread = initial.openThread("ember","CHAT","legacy-agent-live",null,null).id;
  const initialPut = initial.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
    VALUES(?,?,'message','agent','a',?,?,?)`);
  for (let n=1;n<=100;n++) initialPut.run(thread,n,`message-${n}`,n,`t-${n}`);
  initial.close();
  const old = new DatabaseSync(path,{ timeout:5000 });
  let station: Store | null = null;
  try {
    old.exec("DROP INDEX entries_agent_at");
    station = Store.open(path);
    assert.equal(station.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_agent_at'").get(),undefined);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,0);
    const read = makeStore(station.db,dir);
    const check = () => {
      for (const [from,to] of [[1,30],[10,80],[200,300]]) {
        const n = station!.db.prepare(`SELECT MAX(n) n FROM entries WHERE thread=? AND kind='message'
          AND author_kind='agent' AND at>=? AND at<=?`).get(thread,from,to)!.n;
        assert.equal(station!.askingMessage(thread,null,[from,to])?.[0].n ?? null,n);
        assert.equal(askingMessage(read,thread,null,[from,to])?.[0].n ?? null,n);
      }
    };
    check();
    old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
      VALUES(?,101,'message','agent','a','during',20,'new')`).run(thread);
    old.prepare("UPDATE entries SET at=250 WHERE thread=? AND n=90").run(thread);
    let step;
    do { step=legacyAgentStep(old,8); assert.ok(step.visited<=8); check(); } while (!step.ready);
    old.prepare("UPDATE entries SET at=15 WHERE thread=? AND n=90").run(thread);
    check();
    while (legacyAgentDrain(old,8)) check();
    check();
  } finally { station?.close(); old.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("both old message lookups share a worker after handover and reconcile later writes", async () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-worker-")), path = join(dir,"store.db");
  const initial = Store.open(path), thread = initial.openThread("ember","CHAT","legacy-both",null,null).id;
  const initialPut = initial.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
    VALUES(?,?,'message','agent','a',?,?,?)`);
  for (let n=1;n<=130;n++) initialPut.run(thread,n,`message-${n}`,n,`t-${n}`);
  initial.close();
  const old = new DatabaseSync(path,{ timeout:5000 });
  let station: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    withoutSaidState(old);
    old.exec("DROP INDEX entries_agent_at");
    const oldPut = old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts)
      VALUES(?,131,'message','agent','a','after',15,'after')`);
    station = Store.open(path);
    station.db.exec(`CREATE TABLE build_order(kind TEXT);
      CREATE TRIGGER observe_said_build AFTER INSERT ON legacy_said_build BEGIN INSERT INTO build_order VALUES('said'); END;
      CREATE TRIGGER observe_agent_build AFTER INSERT ON legacy_agent_build BEGIN INSERT INTO build_order VALUES('agent'); END;`);
    const previous = Promise.withResolvers<void>();
    builder = buildLegacyEntryLookups(station,previous.promise);
    let settled = false;
    void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled,false);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta").get()?.scanned,0);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,0);
    assert.equal(station.askingMessage(thread,null,[1,130])?.[0].n,130);
    previous.resolve();
    assert.equal(await builder.ready,true);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_said_meta").get()?.scanned,1);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,1);
    const order = station.db.prepare("SELECT kind FROM build_order ORDER BY rowid").all().map((r) => r.kind);
    assert.equal(order.length,260);
    assert.ok(order.indexOf("agent")<130,"agent preparation makes progress before all said batches finish");
    const stale = station.db.prepare("SELECT name,sql FROM sqlite_master WHERE type IN ('trigger','view') AND sql LIKE '%entries_said%'").all();
    assert.deepEqual(stale,[],`stale references: ${JSON.stringify(stale)}`);
    oldPut.run(thread);
    assert.equal(station.askingMessage(thread,null,[1,20])?.[0].n,131);
    builder.wake();
    while (station.db.prepare("SELECT 1 FROM legacy_said_dirty UNION ALL SELECT 1 FROM legacy_agent_dirty LIMIT 1").get()) await pause(10);
    assert.equal(station.askingMessage(thread,null,[1,20])?.[0].n,131);
  } finally { await builder?.close(); station?.close(); old.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("the time lookup resumes its saved scan when the worker fails", async () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-retry-")), path = join(dir,"store.db");
  const initial = Store.open(path), thread = initial.openThread("ember","CHAT","legacy-agent-retry",null,null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
  for (let n=1;n<=130;n++) put.run(thread,n,n);
  initial.close();
  const old = new DatabaseSync(path,{ timeout:5000 });
  let station: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    old.exec("DROP INDEX entries_agent_at");
    station = Store.open(path);
    assert.deepEqual(legacyAgentStep(old,1),{ ready:false,visited:1 });
    const flag = join(dir,"failed"), script = join(dir,"flaky-worker.mjs");
    const worker = new URL("../src/sessions/workspace-activity-worker.ts",import.meta.url).href;
    writeFileSync(script,`import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(flag)})) { writeFileSync(${JSON.stringify(flag)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder = buildLegacyEntryLookups(station,Promise.resolve(),pathToFileURL(script));
    assert.equal(await builder.ready,true);
    assert.equal(existsSync(flag),true);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,1);
    assert.equal(station.db.prepare("SELECT COUNT(*) n FROM legacy_agent_build WHERE thread=?").get(thread)?.n,130);
    old.prepare("UPDATE entries SET at=4 WHERE thread=? AND n=130").run(thread);
    assert.equal(station.askingMessage(thread,null,[1,5])?.[0].n,130);
    builder.wake();
    while (station.db.prepare("SELECT 1 FROM legacy_agent_dirty LIMIT 1").get()) await pause(10);
    assert.equal(station.askingMessage(thread,null,[1,5])?.[0].n,130);
  } finally { await builder?.close(); station?.close(); old.close(); rmSync(dir,{ recursive:true,force:true }); }
});

test("closing a time lookup while waiting for handover leaves it available for a later builder", async () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-agent-close-")), path = join(dir,"store.db");
  const initial = Store.open(path), thread = initial.openThread("ember","CHAT","legacy-agent-close",null,null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','agent','a',?)");
  for (let n=1;n<=64;n++) put.run(thread,n,n);
  initial.close();
  const old = new DatabaseSync(path,{ timeout:5000 });
  let station: Store | null = null, builder: ReturnType<typeof buildLegacyEntryLookups> | null = null;
  try {
    old.exec("DROP INDEX entries_agent_at");
    station = Store.open(path);
    const previous = Promise.withResolvers<void>();
    builder = buildLegacyEntryLookups(station,previous.promise);
    await builder.close();
    assert.equal(await builder.ready,false);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,0);
    previous.resolve();
    builder = buildLegacyEntryLookups(station,Promise.resolve());
    assert.equal(await builder.ready,true);
    assert.equal(station.db.prepare("SELECT scanned FROM legacy_agent_meta").get()?.scanned,1);
    assert.equal(station.askingMessage(thread,null,[1,64])?.[0].n,64);
  } finally { await builder?.close(); station?.close(); old.close(); rmSync(dir,{ recursive:true,force:true }); }
});
