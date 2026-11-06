import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { installLegacyLoginCards, LEGACY_LOGIN_CARDS, legacyLoginCardsStep } from "../src/store/legacy-login-cards.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { Store } from "../src/store/store.ts";
import { withoutSaidState } from "./legacy-message-fixture.ts";

function populate(store: Store, count: number): number {
  const thread = store.openThread("ember","CHAT","legacy-login-cards",null,null).id;
  const insert = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card,ts)
    VALUES(?,?,'message','agent',?,?,?,?)`);
  for (let n=1;n<=count;n++) insert.run(thread,n,`author${n%3}`,n,
    n%10 === 0 ? JSON.stringify({type:"login",login:`old${n}`}) : null,`ts${n}`);
  insert.run(thread,count+1,"first",count+1,'{"LOGIN":"WANTED"}',"wanted-1");
  insert.run(thread,count+2,"second",count+2,'broken "login":"wanted" and "login":"other"',"wanted-2");
  insert.run(thread,count+3,"special",count+3,'{"login":"a_b"}',"wildcard");
  store.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,?,?,?)").run(thread,count+2,"second",1);
  return thread;
}

function check(store: Store, login: string, initiallyClosed: number): void {
  const pattern = `%"login":${JSON.stringify(login)}%`;
  const rows = store.db.prepare(`SELECT thread,n,author FROM entries WHERE kind='message' AND author_kind='agent'
    AND card LIKE '%"login"%' AND card LIKE ? AND NOT EXISTS
      (SELECT 1 FROM closed_cards c WHERE c.thread=entries.thread AND c.n=entries.n) ORDER BY thread,n`).all(pattern);
  assert.deepEqual(store.closeLoginCards(login),[...new Set(rows.map((r) => r.author))],`authors for ${login}`);
  const closed = store.db.prepare("SELECT thread,n FROM closed_cards WHERE n!=? ORDER BY thread,n").all(initiallyClosed);
  assert.deepEqual(closed.map((r) => ({...r})),rows.map((r) => ({thread:r.thread,n:r.n})),`closed cards for ${login}`);
  store.db.prepare("DELETE FROM closed_cards WHERE n!=?").run(initiallyClosed);
}

test("an old store closes the same cards before and after bounded preparation while old writers continue", () => {
  const dir = mkdtempSync(join(tmpdir(),"legacy-login-store-")), path = join(dir,"station.db");
  const initial = Store.open(path), thread = populate(initial,120);
  initial.close();
  const old = new DatabaseSync(path,{ timeout:5000 });
  let station: Store | null = null;
  try {
    old.exec("DROP INDEX entries_login_cards");
    station = Store.open(path);
    assert.equal(station.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_login_cards'").get(),undefined);
    assert.equal(station.db.prepare("SELECT scanned FROM login_card_meta WHERE id=1").get()?.scanned,0);
    for (const login of ["wanted","WANTED","other","old10","a_b","a%b",'a"b']) check(station,login,122);
    const write = old.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at,card,ts)
      VALUES(?,?,'message','agent',?,?,?,?)`);
    write.run(thread,10,"changed",1000,'{"login":"wanted"}',"ts10");
    write.run(thread,140,"later",1001,'{"login":"wanted"}',"later");
    check(station,"wanted",122);
    do {
      const step = legacyLoginCardsStep(station.db,8);
      assert.ok(step.visited<=8 && step.tokens<=8);
      if (step.ready) break;
    } while (true);
    for (const login of ["wanted","WANTED","other","old10","a_b","a%b",'a"b']) check(station,login,122);
    write.run(thread,140,"after",1002,'{"login":"other"}',"later");
    old.prepare("UPDATE entries SET card=? WHERE thread=? AND n=?").run('{"login":"wanted"}',thread,20);
    check(station,"wanted",122);
    check(station,"other",122);
  } finally { station?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("the login lookup reads only the active branch before and after preparation", () => {
  for (const count of [80,800]) {
    const store=Store.open(":memory:"), db=store.db;
    try {
      populate(store,count);
      db.exec("DROP INDEX entries_login_cards");
      // The two arms are instrumented here to count actual row visits.
      installLegacyLoginCards(db);
      let fallback=0,prepared=0;
      db.function("visit_fallback", (_n) => { fallback++; return 1; });
      db.function("visit_prepared", (_n) => { prepared++; return 1; });
      const traced=LEGACY_LOGIN_CARDS.replace("AND e.card IS NOT NULL", "AND visit_fallback(e.n) AND e.card IS NOT NULL")
        .replace("AND k.login=?1", "AND visit_prepared(k.n) AND k.login=?1");
      assert.notEqual(traced,LEGACY_LOGIN_CARDS);
      const query=db.prepare(traced);
      const pattern='%"login":"wanted"%';
      const before=query.all("wanted",pattern);
      assert.ok(fallback>0); assert.equal(prepared,0);
      while (!legacyLoginCardsStep(db,8).ready) { /* bounded preparation */ }
      fallback=0; prepared=0;
      const after=query.all("wanted",pattern);
      assert.deepEqual(after,before);
      assert.equal(fallback,0); assert.ok(prepared<=2,`prepared lookup visited ${prepared} cards with ${count} other entries`);
    } finally { store.close(); }
  }
});

test("the old login-card worker waits for handover and resumes saved batches", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-login-worker-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=populate(initial,130);
  initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let station: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    old.exec("DROP INDEX entries_login_cards");
    station=Store.open(path);
    assert.equal(legacyLoginCardsStep(station.db,8).ready,false);
    const cursor=station.db.prepare("SELECT cursor_thread,cursor_n FROM login_card_meta").get();
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(station,previous.promise);
    let settled=false; void builder.ready.then(() => { settled=true; });
    await Promise.resolve();
    assert.equal(settled,false);
    assert.deepEqual(station.db.prepare("SELECT cursor_thread,cursor_n FROM login_card_meta").get(),cursor);
    old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card,ts)
      VALUES(?,200,'message','agent','later',200,'{"login":"wanted"}','later')`).run(thread);
    check(station,"wanted",132);
    previous.resolve();
    assert.equal(await builder.ready,true);
    assert.equal(station.db.prepare("SELECT scanned FROM login_card_meta").get()?.scanned,1);
    check(station,"wanted",132);
  } finally { await builder?.close(); station?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});


test("a large version 12 store from before cards can open and close a new login card", () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-login-precard-")),path=join(dir,"station.db");
  const old=new DatabaseSync(path);
  try {
    old.exec(readFileSync(new URL("./fixtures/old-store-before-cards.sql",import.meta.url),"utf8"));
    old.exec(`ALTER TABLE turns ADD COLUMN profile TEXT;
      ALTER TABLE turns ADD COLUMN person TEXT;
      ALTER TABLE turns ADD COLUMN thread INTEGER;
      CREATE INDEX entries_options ON entries(thread,n) WHERE options IS NOT NULL;
      CREATE VIEW merged AS SELECT m.thread,m.n,m.ts,m.author_kind,m.author,
        CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
        CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
        CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
        m.declared,m.client,m.at AS created_at,e.at AS edited_at FROM entries m
        LEFT JOIN entries e ON e.thread=m.thread AND e.n=(SELECT MAX(x.n) FROM entries x WHERE x.thread=m.thread AND x.target=m.n)
        WHERE m.kind='message';
      INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES(1,'ember','CHAT','old',1);
      PRAGMA user_version=12;`);
    const put=old.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(1,?,'message','person','old','hello',?)");
    for (let n=1;n<=100;n++) put.run(n,n);
  } finally { old.close(); }
  let store: Store | null=null;
  try {
    store=Store.open(path);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE text='hello'").get()?.n,100);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_login_cards'").get(),undefined);
    assert.equal(store.db.prepare("SELECT scanned FROM login_card_meta").get()?.scanned,0);
    store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,card,at)
      VALUES(1,101,'message','agent','agent','{"type":"login","login":"welcome"}',101)`).run();
    assert.deepEqual(store.closeLoginCards("welcome"),["agent"]);
    assert.ok(store.db.prepare("SELECT 1 FROM closed_cards WHERE thread=1 AND n=101").get());
  } finally { store?.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a stopped login-card worker settles handover and retries saved work", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-login-retry-")),path=join(dir,"station.db");
  const initial=Store.open(path); populate(initial,130); initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    old.exec("DROP INDEX entries_login_cards");
    store=Store.open(path);
    assert.equal(legacyLoginCardsStep(store.db,1).ready,false);
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    await builder.close();
    assert.equal(await builder.ready,false);
    assert.equal(store.db.prepare("SELECT scanned FROM login_card_meta").get()?.scanned,0);
    previous.resolve();
    const flag=join(dir,"failed"),script=join(dir,"flaky-worker.mjs");
    const worker=new URL("../src/sessions/workspace-activity-worker.ts",import.meta.url).href;
    writeFileSync(script,`import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(flag)})) { writeFileSync(${JSON.stringify(flag)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder=buildLegacyEntryLookups(store,Promise.resolve(),pathToFileURL(script));
    assert.equal(await builder.ready,true);
    assert.equal(existsSync(flag),true);
    assert.equal(store.db.prepare("SELECT scanned FROM login_card_meta").get()?.scanned,1);
    check(store,"wanted",132);
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a completed login-card worker does not recheck its finished scan on later writes", async () => {
  const store=Store.open(":memory:");
  let builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    populate(store,80);
    store.db.exec("DROP INDEX entries_login_cards");
    installLegacyLoginCards(store.db);
    let checks=0;
    const db=new Proxy(store.db,{get(target,property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM login_card_meta")) checks++;
        return target.prepare(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    }});
    const observed=new Proxy(store,{get(target,property) {
      if (property === "db") return db;
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    }});
    builder=buildLegacyEntryLookups(observed,Promise.resolve());
    assert.equal(await builder.ready,true);
    checks=0;
    builder.wake(); builder.wake(); builder.wake();
    assert.equal(checks,0,`a completed lookup rechecked its metadata ${checks} times`);
  } finally { await builder?.close(); store.close(); }
});


test("the three old entry lookups share preparation after handover", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-login-shared-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=populate(initial,130); initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    withoutSaidState(old);
    old.exec("DROP INDEX entries_agent_at; DROP INDEX entries_login_cards");
    store=Store.open(path);
    store.db.exec(`CREATE TABLE build_order(kind TEXT);
      CREATE TRIGGER observe_said_build AFTER INSERT ON legacy_said_build BEGIN INSERT INTO build_order VALUES('said'); END;
      CREATE TRIGGER observe_agent_build AFTER INSERT ON legacy_agent_build BEGIN INSERT INTO build_order VALUES('agent'); END;
      CREATE TRIGGER observe_login_build AFTER INSERT ON login_card_keys BEGIN INSERT INTO build_order VALUES('login'); END;`);
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    await Promise.resolve();
    for (const table of ["legacy_said_meta","legacy_agent_meta","login_card_meta"]) {
      assert.equal(store.db.prepare(`SELECT scanned FROM ${table}`).get()?.scanned,0);
    }
    previous.resolve();
    assert.equal(await builder.ready,true);
    for (const table of ["legacy_said_meta","legacy_agent_meta","login_card_meta"]) {
      assert.equal(store.db.prepare(`SELECT scanned FROM ${table}`).get()?.scanned,1);
    }
    const order=store.db.prepare("SELECT kind FROM build_order ORDER BY rowid").all().map((r)=>r.kind);
    assert.ok(order.includes("login") && order.indexOf("login")<133,"login preparation runs before all messages finish");
    old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card,ts)
      VALUES(?,200,'message','agent','old-writer',200,'{"login":"wanted"}','later')`).run(thread);
    check(store,"wanted",132);
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});
