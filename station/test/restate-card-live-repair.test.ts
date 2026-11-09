import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { repairMergedEditLookup } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const repair of ["before", "after", "older repair"]) {
  test(`an authorization outcome survives an old edit index removed with ${repair} view repair`, () => {
    const dir = mkdtempSync(join(tmpdir(), "restate-repair-")), path = join(dir, "station.db");
    const initial = Store.open(path), thread = initial.openThread("ember", "CHAT", "old", null, null).id;
    const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','person','p','other',?)");
    for (let n = 1; n <= 80; n++) put.run(thread, n, n);
    initial.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,81,'message','card','agent','a','question',81,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "base" } }));
    initial.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,82,'edit',81,'agent','a','latest question',82,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "retained" } }));
    initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
    initial.close();
    const store = Store.open(path), writer = new DatabaseSync(path, { timeout: 5000 });
    try {
      assert.equal(store.db.prepare("SELECT old_index FROM legacy_edit_meta WHERE id=1").get()?.old_index, 1);
      const oldGate = String(writer.prepare("SELECT sql FROM sqlite_master WHERE name='widget_source_before_gate_run'").get()?.sql);
      assert.match(oldGate, /INDEXED BY entries_target/);
      writer.exec("DROP INDEX entries_target");
      if (repair === "before") {
        assert.equal(store.restateCard("a", thread, "absent", () => { throw new Error("missing card must not be transformed"); }), false);
        assert.equal(writer.prepare("SELECT old_index FROM legacy_edit_meta WHERE id=1").get()?.old_index, 1);
      }
      if (repair !== "before") repairMergedEditLookup(writer);
      if (repair === "older repair") {
        // Older releases repaired only the merged view and left this gate referring to the removed index.
        writer.exec("DROP TRIGGER widget_source_before_gate_run");
        writer.exec(oldGate);
      }
      assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, adb: { ...card.adb, outcome: "granted" } })), true);
      const last = store.db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread);
      assert.equal(last?.text, "latest question");
      assert.deepEqual(JSON.parse(String(last?.card)).adb, { reason: "retained", outcome: "granted" });
    } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}

for (const repaired of [false, true]) {
  test(`an authorization outcome survives the native edit index removed ${repaired ? "after its view is repaired" : "before its view is repaired"}`, () => {
    const dir = mkdtempSync(join(tmpdir(), "restate-native-")), path = join(dir, "station.db");
    const store = Store.open(path), writer = new DatabaseSync(path, { timeout: 5000 });
    try {
      const thread = store.openThread("ember", "CHAT", "old", null, null).id;
      store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
        VALUES(?,1,'message','card','agent','a','question',1,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "base" } }));
      store.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
        VALUES(?,2,'edit',1,'agent','a','latest question',2,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "retained" } }));
      writer.exec("DROP INDEX entries_edits");
      if (repaired) repairMergedEditLookup(writer);
      assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, adb: { ...card.adb, outcome: "granted" } })), true);
      const last = writer.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread);
      assert.equal(last?.text, "latest question");
      assert.deepEqual(JSON.parse(String(last?.card)).adb, { reason: "retained", outcome: "granted" });
    } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}

test("an authorization outcome follows a native edit index added while the store is open", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-native-added-")), path = join(dir, "station.db");
  const initial = Store.open(path), thread = initial.openThread("ember", "CHAT", "old", null, null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','person','p','other',?)");
  for (let n = 1; n <= 80; n++) put.run(thread, n, n);
  initial.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,81,'message','card','agent','a','question',81,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "base" } }));
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  const store = Store.open(path), writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, first: true })), true);
    writer.exec("CREATE INDEX entries_edits ON entries(thread,target,n) WHERE target IS NOT NULL");
    assert.match(String(writer.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql), /legacy_edit_meta/);
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, second: true })), true);
    const last = writer.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread);
    assert.deepEqual(JSON.parse(String(last?.card)), { type: "text", adb: { reason: "base" }, first: true, second: true });
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an authorization outcome reads its card and old index from the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-snapshot-")), path = join(dir, "station.db");
  const initial = Store.open(path), thread = initial.openThread("ember", "CHAT", "old", null, null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','person','p','other',?)");
  for (let n = 1; n <= 80; n++) put.run(thread, n, n);
  initial.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,81,'message','card','agent','a','question',81,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "base" } }));
  initial.db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
    VALUES(?,82,'edit',81,'agent','a','latest question',82,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "retained" } }));
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  const store = Store.open(path), writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    let removed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql.startsWith("SELECT CAST(n AS TEXT) AS n,card FROM entries")) return new Proxy(statement, { get(stmt, member) {
          if (member === "get") return (...args: Parameters<typeof stmt.get>) => {
            const row = stmt.get(...args);
            if (!removed) {
              removed = true;
              writer.exec("DROP INDEX entries_target");
              repairMergedEditLookup(writer);
            }
            return row;
          };
          const value = Reflect.get(stmt, member, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
        return statement;
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => ({ ...card, adb: { ...card.adb, outcome: "granted" } })), true);
    assert.equal(removed, true);
    const last = writer.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread);
    assert.equal(last?.text, "latest question");
    assert.deepEqual(JSON.parse(String(last?.card)).adb, { reason: "retained", outcome: "granted" });
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an authorization outcome survives the old index being removed after its snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "restate-after-snapshot-")), path = join(dir, "station.db");
  const initial = Store.open(path), thread = initial.openThread("ember", "CHAT", "old", null, null).id;
  const put = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,?,'message','person','p','other',?)");
  for (let n = 1; n <= 80; n++) put.run(thread, n, n);
  initial.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,81,'message','card','agent','a','question',81,?)`).run(thread, JSON.stringify({ type: "text", adb: { reason: "base" } }));
  initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  initial.close();
  const store = Store.open(path), writer = new DatabaseSync(path, { timeout: 5000 });
  try {
    let removed = false, transformed = 0;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "exec") return (sql: string) => {
        target.exec(sql);
        if (sql === "RELEASE restate_card_read" && !removed) { removed = true; writer.exec("DROP INDEX entries_target"); }
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    (store as any).db = observed;
    assert.equal(store.restateCard("a", thread, "card", (card) => {
      transformed++;
      return { ...card, adb: { ...card.adb, outcome: "granted" } };
    }), true);
    assert.equal(removed, true);
    assert.equal(transformed, 1);
    const last = writer.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread);
    assert.equal(last?.text, "question");
    assert.deepEqual(JSON.parse(String(last?.card)).adb, { reason: "base", outcome: "granted" });
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
