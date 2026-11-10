import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

for (const count of [40,400]) test(`an old store with ${count} entries keeps its edit lookup while opening`, () => {
  const dir=mkdtempSync(join(tmpdir(),"legacy-edits-")),path=join(dir,"station.db");
  const initial=Store.open(path),thread=initial.openThread("ember","CHAT","legacy-edits",null,null).id;
  const put=initial.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
    VALUES(?,?,?,?,?,?,?,?)`);
  for(let n=1;n<=count;n++) put.run(thread,n,"message",null,"person","p",`message ${n}`,n);
  put.run(thread,count+1,"edit",10,"person","p","first edit",count+1);
  put.run(thread,count+2,"edit",10,"person","p","latest edit",count+2);
  initial.db.exec(`CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL;
    DROP INDEX entries_edits;`);
  initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let station: Store | null=null;
  try {
    const before=old.prepare("SELECT text FROM merged WHERE thread=? AND n=10").get(thread)?.text;
    station=Store.open(path);
    const native=station.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_edits'").get();
    assert.equal(native !== undefined,count < 64);
    assert.equal(station.db.prepare("SELECT text FROM merged WHERE thread=? AND n=10").get(thread)?.text,before);
    const view=station.db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql as string;
    assert.equal(view.includes("legacy_edit_meta"),count > 64,view);
    if (count > 64) assert.ok(view.includes("INDEXED BY entries_target"),view);
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?, 'edit',10,'person','p','old writer',?)`).run(thread,count+3,count+3);
    assert.equal(old.prepare("SELECT text FROM merged WHERE thread=? AND n=10").get(thread)?.text,"old writer");
    assert.equal(station.db.prepare("SELECT text FROM merged WHERE thread=? AND n=10").get(thread)?.text,"old writer");
  } finally { station?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a store switches back to the native edit index if another station installs it", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-edits-native-")), path = join(dir, "station.db");
  const initial = Store.open(path);
  const seed = initial.openThread("ember", "CHAT", "old-native-seed", null, null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
  for (let n=1;n<=65;n++) put.run(seed,n,n);
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
  initial.close();
  let old: Store | null = null, reopened: Store | null = null;
  try {
    old = Store.open(path);
    const thread = old.openThread("ember", "CHAT", "old-and-native", null, null).id;
    old.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,1,'message','person','p','hello',1)").run(thread);
    assert.match(String(old.db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql), /legacy_edit_meta/);
    assert.match(String(old.db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='widget_source_before_add'").get()?.sql), /widget_source_before_gate/);
    assert.match(String(old.db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='widget_source_before_gate_run'").get()?.sql), /legacy_edit_meta/);
    old.db.exec("CREATE INDEX entries_edits ON entries(thread,target,n) WHERE target IS NOT NULL;");
    reopened = Store.open(path);
    assert.doesNotMatch(String(reopened.db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql), /legacy_edit_meta/);
    assert.doesNotMatch(String(reopened.db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='widget_source_before_add'").get()?.sql), /widget_source_before_gate/);
    assert.equal(reopened.db.prepare("SELECT 1 FROM sqlite_master WHERE name='widget_source_before_gate'").get(), undefined);
    assert.equal(reopened.db.prepare("SELECT 1 FROM sqlite_master WHERE name='widget_source_before_gate_run'").get(), undefined);
    assert.equal(old.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, "hello");
    assert.equal(reopened.db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, "hello");
  } finally { reopened?.close(); old?.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const [description, index] of [
  ["partial predicate", "CREATE INDEX entries_target ON entries(thread,target) WHERE kind='message'"],
  ["different target collation", "CREATE INDEX entries_target ON entries(thread,target COLLATE NOCASE) WHERE target IS NOT NULL"],
]) test(`an old-named index with a ${description} is not chosen for the merged view`, () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-edits-other-")), path = join(dir, "station.db");
  const initial = Store.open(path);
  initial.db.exec(`DROP INDEX entries_edits; ${index};`);
  initial.close();
  let reopened: Store | null = null;
  try {
    reopened = Store.open(path);
    assert.ok(reopened.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_edits'").get());
    assert.doesNotMatch(String(reopened.db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql), /INDEXED BY entries_target/);
  } finally { reopened?.close(); rmSync(dir, { recursive: true, force: true }); }
});
