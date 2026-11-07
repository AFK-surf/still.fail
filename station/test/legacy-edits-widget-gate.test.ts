import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn, repairMergedEditLookup } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { installWidgetSources, WIDGET_SOURCE, WIDGET_SOURCE_ORIGINAL, widgetSourcesStep } from "../src/store/widget-sources.ts";

const plain = (row: unknown) => row === undefined ? null : { ...(row as object) };

function oldEditLookup(store: Store, prepared: boolean, beforeWidgetInstall?: () => void): void {
  const db = store.db;
  const seed = store.openThread("ember", "CHAT", "old-edit-seed", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
  for (let n = 1; n <= 10; n++) put.run(seed, n, n);
  db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  installLegacyEdits(db);
  addClientColumn(db);
  beforeWidgetInstall?.();
  installWidgetSources(db);
  if (prepared) while (!legacyEditStep(db, 4).ready) { /* prepare */ }
  assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta").get()?.scanned, prepared ? 1 : 0);
}

for (const recursive of [false, true]) for (const when of ["BEFORE", "AFTER"]) for (const installFirst of [false, true]) {
  test(`nested ${when} widget writes agree with the direct trigger (recursive ${recursive}, installed first ${installFirst})`, () => {
    const outcome = (direct: boolean) => {
      const store = Store.open(":memory:"), db = store.db;
      try {
        const nested = () => db.exec(`CREATE TRIGGER nested_widget ${when} INSERT ON entries WHEN NEW.text='outer' BEGIN
          INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at,attachments)
            VALUES(NEW.thread,NEW.n,'message','agent','a','inner',2,'[{"path":"/w/item","name":"inner"}]');
        END`);
        oldEditLookup(store, true, installFirst ? nested : undefined);
        if (direct) {
          const outer = String(db.prepare("SELECT sql FROM sqlite_master WHERE name='widget_source_before_add'").get()?.sql);
          const gate = String(db.prepare("SELECT sql FROM sqlite_master WHERE name='widget_source_before_gate_run'").get()?.sql);
          const body = gate.match(/BEGIN ([\s\S]*) END$/)?.[1];
          assert.ok(body);
          const replacement = outer.replace(/BEGIN [\s\S]* END$/, `BEGIN ${body.replaceAll("NEW.entry_rowid", "NEW.rowid")} END`);
          assert.notEqual(replacement, outer);
          db.exec("DROP TRIGGER widget_source_before_add"); db.exec(replacement);
        }
        if (!installFirst) nested();
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        const thread = store.openThread("ember", "CHAT", "nested-widget", null, null).id;
        widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember");
        db.prepare(`INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,text,at,attachments)
          VALUES(?,1,'message','agent','a','outer',1,'[{"path":"/w/item","name":"outer"}]')`).run(thread);
        const expected = when === "BEFORE" ? "outer" : "inner";
        assert.equal(db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, expected);
        const indexed = plain(db.prepare(WIDGET_SOURCE).get("a", "/w/item"));
        const original = plain(db.prepare(WIDGET_SOURCE_ORIGINAL).get("a", "/w/item"));
        // With recursive triggers off, the original direct trigger can leave a stale source when a later BEFORE trigger
        // creates the row it replaces. Compare the gate to that behavior; the existing bug is tracked separately.
        if (recursive || when === "AFTER" || !installFirst) assert.deepEqual(indexed, original);
        return { indexed, original };
      } finally { store.close(); }
    };
    assert.deepEqual(outcome(false), outcome(true));
  });
}

for (const recursive of [false, true]) for (const prepared of [false, true]) {
  test(`old widget sources follow replacements with the edit lookup (recursive ${recursive}, prepared ${prepared})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      oldEditLookup(store, prepared);
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const first = store.openThread("ember", "CHAT", "first", null, null).id;
      const second = store.openThread("ember", "CHAT", "second", null, null).id;
      const outside = store.openThread("ember", "CHAT", "outside", null, null).id;
      for (const thread of [first, second]) { widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember"); }
      const path = "/w/item.html", files = (name: string) => JSON.stringify([{ path, name }]);
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,'agent','a',?,?)`);
      const replace = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const check = (name: string | null) => {
        const current = plain(db.prepare(WIDGET_SOURCE).get("a", path));
        assert.deepEqual(current, plain(db.prepare(WIDGET_SOURCE_ORIGINAL).get("a", path)));
        assert.equal((current as { name: string } | null)?.name ?? null, name);
      };
      put.run(first, 1, "message", null, "first", 20, files("first")); check("first");
      put.run(second, 1, "message", null, "second", 40, files("second")); check("second");
      put.run(second, 2, "edit", 1, null, 50, "[]"); check("first");
      put.run(first, 2, "edit", 1, null, 60, files("updated")); check("updated");
      db.prepare("UPDATE entries SET attachments=? WHERE thread=? AND n=?").run(files("back"), second, 2); check("back");
      const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(first) as { rowid: number }).rowid;
      // IGNORE must leave the old source intact, including when the colliding row is in an unrequested thread.
      db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,author_kind,author,at,attachments)
        VALUES(?, ?,3,'message','agent','a',80,'[]')`).run(rowid, outside); check("back");
      replace.run(rowid, outside, 4, "message", null, "outside", 100, "[]"); check("back");
      replace.run(12345, second, 5, "message", null, "second", 90, files("same-ts")); check("same-ts");
      db.prepare("DELETE FROM entries WHERE thread=? AND n=?").run(second, 5); check(null);
    } finally { store.close(); }
  });

  test(`old widget sources agree after mixed writes (recursive ${recursive}, prepared ${prepared})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      oldEditLookup(store, prepared);
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const threads = ["one", "two", "unrequested"].map((name) => store.openThread("ember", "CHAT", name, null, null).id);
      for (const thread of threads.slice(0, 2)) { widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember"); }
      const paths = ["/w/one", "/w/two", "/w/three"];
      let seed = 71239;
      const next = (max: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
      const files = () => next(4) === 0 ? "[]" : JSON.stringify([{ path: paths[next(paths.length)], name: `n${next(9)}` }]);
      const insert = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const ignore = db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,attachments)
        VALUES(?,?,?,?,?,?,'agent','a',?,?)`);
      const update = db.prepare("UPDATE OR REPLACE entries SET rowid=?,thread=?,n=?,kind=?,target=?,ts=?,at=?,attachments=? WHERE rowid=?");
      for (let step = 0; step < 100; step++) {
        const current = db.prepare("SELECT rowid FROM entries ORDER BY rowid").all() as { rowid: number }[];
        const action = current.length === 0 ? 0 : next(4);
        if (action === 3) db.prepare("DELETE FROM entries WHERE rowid=?").run(current[next(current.length)]!.rowid);
        else {
          const kind = next(3) === 0 ? "edit" : "message";
          const args = [next(25) + 1, threads[next(threads.length)]!, next(16) - 3, kind,
            kind === "edit" ? next(16) - 3 : null, next(4) === 0 ? `ts-${next(8)}` : null, next(20), files()] as const;
          if (action === 2) update.run(...args, current[next(current.length)]!.rowid);
          else (action === 1 ? ignore : insert).run(...args);
        }
        for (const path of paths) assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", path)),
          plain(db.prepare(WIDGET_SOURCE_ORIGINAL).get("a", path)), `step ${step}, ${path}`);
      }
    } finally { store.close(); }
  });
}

test("another connection's writes run the gated old widget lookup", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-widget-gate-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let old: DatabaseSync | null = null;
  try {
    oldEditLookup(store, true);
    const thread = store.openThread("ember", "CHAT", "tracked", null, null).id;
    widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember");
    old = new DatabaseSync(path, { timeout: 5000 });
    const files = (name: string) => JSON.stringify([{ path: "/w/item", name }]);
    const put = old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,?,?,?, 'agent','a',?,?)`);
    put.run(thread, 1, "message", null, 1, files("message"));
    put.run(thread, 2, "edit", 1, 2, files("edit"));
    assert.equal(db.prepare(WIDGET_SOURCE).get("a", "/w/item")?.name, "edit");
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", "/w/item")), plain(db.prepare(WIDGET_SOURCE_ORIGINAL).get("a", "/w/item")));
  } finally { old?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("repairing a removed old edit index keeps tracked widget files current for another writer", () => {
  const dir = mkdtempSync(join(tmpdir(), "legacy-widget-repair-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let old: DatabaseSync | null = null;
  try {
    oldEditLookup(store, true);
    const thread = store.openThread("ember", "CHAT", "tracked-repair", null, null).id;
    widgetSourcesStep(db, thread); store.joinThread(thread, "a", "ember");
    const files = (name: string) => JSON.stringify([{ path: "/w/item", name }]);
    db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
      VALUES(?,1,'message','agent','a',1,?)`).run(thread, files("message"));
    old = new DatabaseSync(path, { timeout: 5000 });
    old.exec("DROP INDEX entries_target");
    repairMergedEditLookup(old);
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,attachments)
      VALUES(?,2,'edit',1,'agent','a',2,?)`).run(thread, files("edited"));
    assert.equal(db.prepare(WIDGET_SOURCE).get("a", "/w/item")?.name, "edited");
    assert.deepEqual(plain(db.prepare(WIDGET_SOURCE).get("a", "/w/item")), plain(db.prepare(WIDGET_SOURCE_ORIGINAL).get("a", "/w/item")));
  } finally { old?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
