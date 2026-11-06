import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { Store } from "../src/store/store.ts";
import { withoutSaidState } from "./legacy-message-fixture.ts";

function populate(store: Store): number {
  const thread=store.openThread("ember","CHAT","legacy-edits-worker",null,null).id;
  const put=store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card,ts)
    VALUES(?,?,?,?, 'agent','a',?,?,?,?)`);
  put.run(thread,1,"message",null,"before",1,null,"message");
  for (let n=2;n<=130;n++) put.run(thread,n,n%3===0 ? "edit" : "message",n%3===0 ? 1 : null,`entry ${n}`,n,
    n===10 ? '{"type":"login","login":"old"}' : null,`ts${n}`);
  return thread;
}

test("the old edit worker waits for handover, resumes and follows the old writer", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edits-worker-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=populate(initial);
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    store=Store.open(path);
    assert.equal(legacyEditStep(store.db,8).ready,false);
    const cursor=store.db.prepare("SELECT cursor_thread,cursor_n FROM legacy_edit_meta").get();
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    let settled=false; void builder.ready.then(() => { settled=true; });
    await Promise.resolve();
    assert.equal(settled,false);
    assert.deepEqual(store.db.prepare("SELECT cursor_thread,cursor_n FROM legacy_edit_meta").get(),cursor);
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,200,'edit',1,'agent','a','old writer',200)`).run(thread);
    assert.equal(store.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text,"old writer");
    previous.resolve();
    assert.equal(await builder.ready,true);
    assert.equal(store.db.prepare("SELECT scanned FROM legacy_edit_meta").get()?.scanned,1);
    assert.equal(store.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text,"old writer");
    old.prepare("UPDATE entries SET target=2 WHERE thread=? AND n=200").run(thread);
    assert.equal(store.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text,"entry 129");
    assert.equal(store.db.prepare("SELECT text FROM merged WHERE thread=? AND n=2").get(thread)?.text,"old writer");
    builder.wake();
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a stopped edit worker settles handover and retries its saved work", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edits-retry-")),path=join(dir,"station.db");
  const initial=Store.open(path); populate(initial);
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    store=Store.open(path);
    assert.equal(legacyEditStep(store.db,1).ready,false);
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    await builder.close();
    assert.equal(await builder.ready,false);
    assert.equal(store.db.prepare("SELECT scanned FROM legacy_edit_meta").get()?.scanned,0);
    previous.resolve();
    const flag=join(dir,"failed"),script=join(dir,"flaky-worker.mjs");
    const worker=new URL("../src/sessions/workspace-activity-worker.ts",import.meta.url).href;
    writeFileSync(script,`import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(flag)})) { writeFileSync(${JSON.stringify(flag)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder=buildLegacyEntryLookups(store,Promise.resolve(),pathToFileURL(script));
    assert.equal(await builder.ready,true);
    assert.equal(existsSync(flag),true);
    assert.equal(store.db.prepare("SELECT scanned FROM legacy_edit_meta").get()?.scanned,1);
  } finally { await builder?.close(); store?.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a card restatement uses its latest eligible edit throughout preparation", () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edits-card-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=initial.openThread("ember","CHAT","legacy-edits-card",null,null).id;
  const put=initial.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card,ts)
    VALUES(?,?,?,?, 'agent','a','card',?,?,?)`);
  put.run(thread,1,"message",null,1,'{"type":"text","value":"base"}',"post");
  put.run(thread,2,"edit",1,2,'{"type":"text","value":"edited"}',null);
  put.run(thread,3,"edit",1,3,null,null);
  put.run(thread,4,"message",1,4,'{"type":"text","value":"ineligible"}',null);
  for (let n=5;n<=70;n++) put.run(thread,n,"message",null,n,null,null);
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  let store: Store | null=null;
  try {
    store=Store.open(path);
    const seen: unknown[]=[];
    const restate=(marker: string) => store!.restateCard("a",thread,"post",(card) => {
      seen.push(card); return {...card,marker};
    });
    assert.equal(restate("first"),true);
    while (!legacyEditStep(store.db,8).ready) { /* prepare */ }
    assert.equal(restate("second"),true);
    while (legacyEditDrain(store.db,8)) { /* reconcile */ }
    assert.equal(restate("third"),true);
    assert.deepEqual(seen,[{type:"text",value:"edited"},{type:"text",value:"edited",marker:"first"},
      {type:"text",value:"edited",marker:"second"}]);
  } finally { store?.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("the four old entry lookups share preparation after handover", async () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edits-shared-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=populate(initial); initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    withoutSaidState(old);
    old.exec(`DROP INDEX entries_agent_at; DROP INDEX entries_login_cards; DROP INDEX entries_edits;
      CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL`);
    store=Store.open(path);
    store.db.exec(`CREATE TABLE build_order(kind TEXT);
      CREATE TRIGGER observe_said_build AFTER INSERT ON legacy_said_build BEGIN INSERT INTO build_order VALUES('said'); END;
      CREATE TRIGGER observe_agent_build AFTER INSERT ON legacy_agent_build BEGIN INSERT INTO build_order VALUES('agent'); END;
      CREATE TRIGGER observe_login_build AFTER INSERT ON login_card_keys BEGIN INSERT INTO build_order VALUES('login'); END;
      CREATE TRIGGER observe_edit_build AFTER INSERT ON legacy_edit_build BEGIN INSERT INTO build_order VALUES('edit'); END;`);
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    await Promise.resolve();
    for (const table of ["legacy_said_meta","legacy_agent_meta","login_card_meta","legacy_edit_meta"])
      assert.equal(store.db.prepare(`SELECT scanned FROM ${table}`).get()?.scanned,0);
    previous.resolve();
    assert.equal(await builder.ready,true);
    for (const table of ["legacy_said_meta","legacy_agent_meta","login_card_meta","legacy_edit_meta"])
      assert.equal(store.db.prepare(`SELECT scanned FROM ${table}`).get()?.scanned,1);
    const order=store.db.prepare("SELECT kind FROM build_order ORDER BY rowid").all().map((r) => r.kind);
    assert.ok(order.includes("login") && order.includes("edit"));
    assert.ok(order.indexOf("edit")<130,"edit preparation runs before all message preparation finishes");
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,200,'edit',1,'agent','a','after handover',200)`).run(thread);
    assert.equal(store.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text,"after handover");
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});
