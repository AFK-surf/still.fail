import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { archivePolicyIndexStep, LEGACY_ARCHIVE_POLICY } from "../src/store/archive-policy-index.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { Store } from "../src/store/store.ts";

function oldStore(path: string) {
  const store=Store.open(path);
  try {
    const put=store.db.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?,?,?,?,?)");
    for (let n=1;n<=130;n++) put.run(n,JSON.stringify({version:n}),'{"kind":"agent"}',`change ${n}`,n%3===0 ? null : `ws${n%3}`);
    store.db.exec("DROP INDEX archive_policy_by_ws");
  } finally { store.close(); }
}
function last(store: Store,ws: string | null) {
  const row=store.db.prepare("SELECT id,at,policy,author,summary FROM archive_policy WHERE ws IS ? ORDER BY id DESC LIMIT 1").get(ws);
  return row ? {policy:JSON.parse(row.policy as string),change:{id:row.id,at:row.at,by:JSON.parse(row.author as string),summary:row.summary}} : null;
}
function check(store: Store) {
  for (const ws of [null,"ws1","ws2","missing"]) assert.deepEqual(store.archivePolicy(ws),last(store,ws));
}

test("opening an old store bounds the rows visited while installing its policy lookup", () => {
  const counts: number[]=[];
  for (const size of [40,400]) {
    const dir=mkdtempSync(join(tmpdir(),"archive-policy-start-")),path=join(dir,"station.db");
    const initial=Store.open(path);
    const put=initial.db.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?, '{}','{}','',?)");
    for (let id=1;id<=size;id++) put.run(id,"other");
    initial.db.exec("DROP INDEX archive_policy_by_ws"); initial.close();
    const execDescriptor=Object.getOwnPropertyDescriptor(DatabaseSync.prototype,"exec")!;
    const prepareDescriptor=Object.getOwnPropertyDescriptor(DatabaseSync.prototype,"prepare")!;
    const exec=execDescriptor.value as DatabaseSync["exec"],prepare=prepareDescriptor.value as DatabaseSync["prepare"];
    const visited=new Set<string>();
    Object.defineProperty(DatabaseSync.prototype,"exec",{...execDescriptor,value(this: DatabaseSync,sql: string) {
      if (sql === "CREATE INDEX IF NOT EXISTS archive_policy_by_ws ON archive_policy(ws)") {
        this.function("visit_policy_index",{deterministic:true},id=>{visited.add(String(id));return 1;});
        sql += " WHERE visit_policy_index(id)";
      }
      return exec.call(this,sql);
    }});
    Object.defineProperty(DatabaseSync.prototype,"prepare",{...prepareDescriptor,value(this: DatabaseSync,sql: string) {
      if (sql === "SELECT 1 FROM archive_policy LIMIT 1 OFFSET 63") {
        this.function("visit_policy_probe",id=>{visited.add(String(id));return 1;});
        sql="SELECT 1 FROM archive_policy WHERE visit_policy_probe(id) LIMIT 1 OFFSET 63";
      }
      return prepare.call(this,sql);
    }});
    let reopened: Store | null=null;
    try { reopened=Store.open(path); counts.push(visited.size); }
    finally {
      reopened?.close();
      Object.defineProperty(DatabaseSync.prototype,"exec",execDescriptor);
      Object.defineProperty(DatabaseSync.prototype,"prepare",prepareDescriptor);
      rmSync(dir,{recursive:true,force:true});
    }
  }
  assert.deepEqual(counts,[40,64]);
});

test("opening an old store preserves current policies while old connections write and preparation advances", () => {
  const dir=mkdtempSync(join(tmpdir(),"archive-policy-store-")),path=join(dir,"station.db");
  oldStore(path);
  const old=new DatabaseSync(path,{timeout:5000});
  const write=old.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?,?,?,?,?)");
  let store: Store | null=null;
  try {
    store=Store.open(path);
    assert.equal(store.db.prepare("SELECT complete FROM archive_policy_lookup_meta").get()?.complete,0);
    check(store);
    write.run(200,'{"version":200}','{"kind":"person"}',"later",null);
    check(store);
    assert.deepEqual(archivePolicyIndexStep(store.db,7),{done:false,visited:7});
    old.prepare("UPDATE archive_policy SET ws=? WHERE id=?").run("ws1",130);
    old.prepare("DELETE FROM archive_policy WHERE id=?").run(129);
    check(store);
    while (!archivePolicyIndexStep(store.db,7).done) { /* bounded preparation */ }
    check(store);
    write.run(201,'{"version":201}','{"kind":"person"}',"later","ws2");
    check(store);
    assert.equal(store.db.prepare("SELECT complete FROM archive_policy_lookup_meta").get()?.complete,1);
  } finally { store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("the policy worker waits for handover and continues saved batches after an old write", async () => {
  const dir=mkdtempSync(join(tmpdir(),"archive-policy-worker-")),path=join(dir,"station.db");
  oldStore(path);
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    store=Store.open(path);
    assert.equal(archivePolicyIndexStep(store.db,7).done,false);
    const before=store.db.prepare("SELECT cursor,complete FROM archive_policy_lookup_meta").get();
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    let settled=false; void builder.ready.then(()=>{settled=true;});
    await Promise.resolve();
    assert.equal(settled,false);
    assert.deepEqual(store.db.prepare("SELECT cursor,complete FROM archive_policy_lookup_meta").get(),before);
    old.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?,?,?,?,?)")
      .run(201,'{"version":201}','{"kind":"agent"}',"later","ws1");
    check(store);
    previous.resolve();
    assert.equal(await builder.ready,true);
    assert.equal(store.db.prepare("SELECT complete FROM archive_policy_lookup_meta").get()?.complete,1);
    check(store);
  } finally { await builder?.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a stopped policy worker can resume its saved progress", async () => {
  const dir=mkdtempSync(join(tmpdir(),"archive-policy-retry-")),path=join(dir,"station.db");
  oldStore(path);
  let store: Store | null=null,builder: ReturnType<typeof buildLegacyEntryLookups> | null=null;
  try {
    store=Store.open(path);
    archivePolicyIndexStep(store.db,7);
    const before=store.db.prepare("SELECT cursor,complete FROM archive_policy_lookup_meta").get();
    const previous=Promise.withResolvers<void>();
    builder=buildLegacyEntryLookups(store,previous.promise);
    await builder.close();
    assert.equal(await builder.ready,false);
    assert.deepEqual(store.db.prepare("SELECT cursor,complete FROM archive_policy_lookup_meta").get(),before);
    previous.resolve();
    const flag=join(dir,"failed"),script=join(dir,"flaky-worker.mjs");
    const worker=new URL("../src/sessions/workspace-activity-worker.ts",import.meta.url).href;
    writeFileSync(script,`import { existsSync, writeFileSync } from 'node:fs';\n` +
      `if (!existsSync(${JSON.stringify(flag)})) { writeFileSync(${JSON.stringify(flag)}, 'failed'); process.exit(1); }\n` +
      `await import(${JSON.stringify(worker)});\n`);
    builder=buildLegacyEntryLookups(store,Promise.resolve(),pathToFileURL(script));
    assert.equal(await builder.ready,true);
    assert.equal(existsSync(flag),true);
    assert.equal(store.db.prepare("SELECT complete FROM archive_policy_lookup_meta").get()?.complete,1);
    check(store);
  } finally { await builder?.close(); store?.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a reader snapshot retains the same policy while preparation completes and another writer saves", () => {
  const dir=mkdtempSync(join(tmpdir(),"archive-policy-snapshot-")),path=join(dir,"station.db");
  oldStore(path);
  const old=new DatabaseSync(path,{timeout:5000}),reader=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null;
  try {
    store=Store.open(path);
    reader.exec("BEGIN");
    const query=reader.prepare(LEGACY_ARCHIVE_POLICY),before=query.get("ws1");
    old.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(?,?,?,?,?)")
      .run(201,'{"version":201}','{"kind":"agent"}',"later","ws1");
    while (!archivePolicyIndexStep(store.db,7).done) { /* bounded preparation */ }
    assert.deepEqual(query.get("ws1"),before);
    reader.exec("COMMIT");
    assert.notDeepEqual(query.get("ws1"),before);
    check(store);
  } finally { reader.close(); store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("an unrelated 64-bit policy id is never decoded while reading a workspace", () => {
  const dir=mkdtempSync(join(tmpdir(),"archive-policy-int64-")),path=join(dir,"station.db");
  oldStore(path);
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null;
  try {
    old.prepare("INSERT INTO archive_policy(id,at,policy,author,summary,ws) VALUES(?,?,?,?,?,?)")
      .run(9007199254740993n,1,'{"version":1}','{"kind":"agent"}',"large","other");
    store=Store.open(path);
    check(store);
    while (!archivePolicyIndexStep(store.db,7).done) { /* bounded preparation */ }
    check(store);
  } finally { store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});
