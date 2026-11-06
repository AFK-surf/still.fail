import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { addClientColumn } from "../src/store/schema.ts";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";

// The old index orders a single message's edits together. History of other messages must not be searched on a read.
test("the old edit lookup seeks the requested message rather than its chat's history", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-edits", null, null).id;
    db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
    installLegacyEdits(db);
    addClientColumn(db);
    const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?, 'person','p',?,?)`);
    insert.run(thread, 1, "message", null, "unedited", 1);
    insert.run(thread, 2, "message", null, "before", 2);
    insert.run(thread, 3, "edit", 2, "after", 3);
    let visits = 0;
    db.function("visit_old_edit", (n) => { visits++; return n; });
    const view = String(db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql);
    const observed = view.replace("CREATE VIEW merged", "CREATE TEMP VIEW counted_merged")
      .replace("FROM entries x INDEXED BY entries_target WHERE", "FROM entries x INDEXED BY entries_target WHERE visit_old_edit(x.n)=x.n AND");
    assert.notEqual(observed, view);
    assert.ok(observed.includes("visit_old_edit"));
    db.exec(observed);
    const query = "SELECT text FROM counted_merged WHERE thread=? AND n=?";
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${query}`).all(thread, 1).map((row) => String(row.detail)).join("\n");
    assert.match(plan, /SEARCH x USING (?:COVERING )?INDEX entries_target \(thread=\? AND target=\?\)/, plan);
    const visitsFor = (n: number, expected: string) => {
      visits = 0;
      assert.equal(db.prepare(query).get(thread, n)?.text, expected);
      return visits;
    };
    const before = [visitsFor(1, "unedited"), visitsFor(2, "after")];
    assert.deepEqual(before, [0, 1]);
    for (let n = 4; n <= 403; n++) insert.run(thread, n, "edit", n + 1000, "other", n);
    assert.deepEqual([visitsFor(1, "unedited"), visitsFor(2, "after")], before);
  } finally { store.close(); }
});

test("the old edit lookup chooses the largest entry number, not the newest rowid", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-edit-order", null, null).id;
    db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
    installLegacyEdits(db);
    addClientColumn(db);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?, 'person','p',?,1)`);
    put.run(thread, 1, "message", null, "first");
    put.run(thread, 9007199254740999n, "edit", 1, "largest");
    put.run(thread, 10, "edit", 1, "inserted later");
    assert.equal(db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, "largest");
    put.run(thread, 9007199254741001n, "edit", 1, "new largest");
    assert.equal(db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, "new largest");
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    assert.equal(db.prepare("SELECT text FROM merged WHERE thread=? AND n=1").get(thread)?.text, "new largest");
  } finally { store.close(); }
});

test("the old edit lookup does not reread a message's entire edit history", () => {
  const visitsFor = (edits: number) => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `old-own-edits-${edits}`, null, null).id;
      db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,?,?,?, 'person','p',?,?)`);
      put.run(thread, 1, "message", null, "before", 1);
      for (let n = 2; n <= edits + 1; n++) put.run(thread, n, "edit", 1, `edit ${n}`, n);
      installLegacyEdits(db);
      while (!legacyEditStep(db,8).ready) { /* prepare */ }
      addClientColumn(db);
      let visits = 0;
      db.function("visit_own_edit", (n) => { visits++; return n; });
      const view = String(db.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql);
      const observed = view.replace("CREATE VIEW merged", "CREATE TEMP VIEW counted_own_edits")
        .replaceAll("s.thread=m.thread AND s.target=m.n", "s.thread=m.thread AND s.target=m.n AND visit_own_edit(s.n)=s.n");
      assert.notEqual(observed, view);
      assert.ok(observed.includes("visit_own_edit"));
      db.exec(observed);
      assert.equal(db.prepare("SELECT text FROM counted_own_edits WHERE thread=? AND n=1").get(thread)?.text, `edit ${edits + 1}`);
      return visits;
    } finally { store.close(); }
  };
  const small = visitsFor(40), large = visitsFor(400);
  assert.equal(small,1);
  assert.equal(large, small, `same-message edits visited: ${small} / ${large}`);
});

for (const prepared of [false,true]) test(`tracking an edited widget source does not read other messages' edits on an old store (prepared ${prepared})`, () => {
  const visitsFor = (otherEdits: number) => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `old-widget-edits-${otherEdits}`, null, null).id;
      db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,attachments)
        VALUES(?,?,?,?, 'person','p','text',?,?)`);
      put.run(thread, 1, "message", null, 1, null);
      for (let n = 2; n <= otherEdits + 1; n++) put.run(thread, n, "edit", n + 1000, n, null);
      installLegacyEdits(db);
      if (prepared) while (!legacyEditStep(db,16).ready) { /* prepare */ }
      addClientColumn(db);
      installWidgetSources(db);
      db.prepare("INSERT INTO widget_source_scopes(thread,last_n,end_n,complete) VALUES(?,0,0,1)").run(thread);
      let visits = 0;
      db.function("visit_widget_edit", (n) => { visits++; return n; });
      const trigger = String(db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='widget_source_before_gate_run'").get()?.sql);
      const observed = trigger.replace(
        "WHERE x.thread=NEW.thread AND x.target=NEW.target",
        "WHERE x.thread=NEW.thread AND visit_widget_edit(x.n)=x.n AND x.target=NEW.target",
      ).replaceAll("s.thread=NEW.thread AND s.target=NEW.target",
        "s.thread=NEW.thread AND s.target=NEW.target AND visit_widget_edit(s.n)=s.n")
        .replace("t.thread=NEW.thread AND t.target=NEW.target AND x.target=t.target",
          "t.thread=NEW.thread AND t.target=NEW.target AND visit_widget_edit(t.n)=t.n AND x.target=t.target");
      assert.notEqual(observed, trigger, "instrumented the widget's actual edit lookup");
      db.exec("DROP TRIGGER widget_source_before_gate_run");
      db.exec(observed);
      put.run(thread, -1, "edit", 1, 2, "[]");
      const withoutMatch = visits;
      visits = 0;
      put.run(thread, -2, "edit", 1, 3, '[{"path":"p","name":"x"}]');
      assert.ok(visits > 0, "the actual trigger consulted the matching edit");
      return withoutMatch;
    } finally { store.close(); }
  };
  const small = visitsFor(40), large = visitsFor(400);
  assert.equal(large, small, `unrelated widget edit candidates: ${small} / ${large}`);
});

test("restating a card in an old store does not read unrelated card edits", () => {
  const visitsFor = (otherCards: number) => {
    const dir = mkdtempSync(join(tmpdir(), "legacy-edit-card-")), path = join(dir, "station.db");
    const initial = Store.open(path);
    const seed = initial.openThread("ember", "CHAT", "old-card-seed", null, null).id;
    const seedPut = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,?,'message','person','p',?)");
    for (let n=1;n<=65;n++) seedPut.run(seed,n,n);
    initial.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits;");
    initial.close();
    const store = Store.open(path), db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `old-card-edits-${otherCards}`, null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,text,at,card)
        VALUES(?,?,?,?,?, 'agent','a','card',?,?)`);
      put.run(thread, 1, "message", null, "target", 1, '{"type":"options"}');
      for (let n = 2; n <= otherCards + 1; n++) put.run(thread, n, "edit", n + 1000, null, n, '{"type":"options"}');
      let visits = 0, instrumented = false;
      db.function("visit_restate_card", (n) => { visits++; return n; });
      const traced = new Proxy(db, {
        get(target, property) {
          if (property === "prepare") return (statement: string) => {
            if (statement.startsWith("SELECT x.card FROM entries x WHERE x.thread=?1")) {
              instrumented = true;
              const measured = statement.replace("FROM entries x INDEXED BY entries_target WHERE", "FROM entries x INDEXED BY entries_target WHERE visit_restate_card(x.n)=x.n AND");
              assert.notEqual(measured,statement);
              return target.prepare(measured);
            }
            return target.prepare(statement);
          };
          const value = Reflect.get(target, property, target);
          return typeof value === "function" ? value.bind(target) : value;
        },
      });
      (store as any).db = traced;
      assert.equal(store.restateCard("a", thread, "target", (card) => card), true);
      assert.ok(instrumented, "measured the query used by restateCard");
      return visits;
    } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
  };
  const small = visitsFor(40), large = visitsFor(400);
  assert.equal(large, small, `unrelated card edits visited: ${small} / ${large}`);
});
