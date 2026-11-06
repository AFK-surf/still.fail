import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLegacyEdits, legacyEditDrain, legacyEditLatest, legacyEditStep, legacyEditsUseOldIndex } from "../src/store/legacy-edits-build.ts";

function database() {
  const dir = mkdtempSync(join(tmpdir(),"legacy-edits-build-")), path = join(dir,"store.db"), db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL;
    CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,kind TEXT NOT NULL,target INTEGER,ts TEXT,
      card TEXT,text TEXT,PRIMARY KEY(thread,n));
    CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;
    CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL`);
  return { db,path,close() { db.close(); rmSync(dir,{ recursive: true,force: true }); } };
}

const put = (db: DatabaseSync,thread: number,n: number,target: number | null,ts: string | null = null) =>
  db.prepare("INSERT INTO entries(thread,n,kind,target,ts,card,text) VALUES(?,?,?, ?,?,NULL,?)")
    .run(thread,n,target === null ? "message" : "edit",target,ts,`entry ${n}`);
const expected = (db: DatabaseSync,thread: number,target: number,filter = "1") =>
  db.prepare(`SELECT MAX(x.n) n FROM entries x INDEXED BY entries_target WHERE x.thread=?1 AND x.target=?2 AND (${filter})`)
    .get(thread,target)!.n;
const actual = (db: DatabaseSync,thread: number,target: number,filter = "1") =>
  db.prepare(`SELECT ${legacyEditLatest("?1","?2",filter)} AS n`).get(thread,target)!.n;
const same = (db: DatabaseSync) => {
  for (const thread of [1,2,3]) for (const target of [1,2,3,9,50,500]) for (const filter of ["1","x.kind='edit' AND x.card IS NOT NULL"])
    assert.equal(actual(db,thread,target,filter),expected(db,thread,target,filter),`${thread}/${target}: ${filter}`);
};

for (const recursive of [false,true]) test(`old edit preparation follows another writer (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
  try {
    old.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    for (let n=1;n<=80;n++) { put(db,1,n,n%9+1,`t${n}`); if (n<=10) put(db,2,n,n%3+1,`u${n}`); }
    installLegacyEdits(db);
    same(db);
    assert.deepEqual(legacyEditStep(db,8),{ ready: false,visited: 8 });
    old.exec("UPDATE entries SET target=50,card='yes' WHERE thread=1 AND n=3");
    old.exec("UPDATE entries SET target=NULL WHERE thread=1 AND n=4");
    old.exec("INSERT OR REPLACE INTO entries VALUES(1,70,'edit',2,'t1','new','replacement')");
    const displaced = old.prepare("SELECT rowid id FROM entries WHERE thread=1 AND n=7").get()!.id;
    old.prepare("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,text) VALUES(?,3,1,'edit',3,'moved')").run(displaced);
    old.exec("DELETE FROM entries WHERE thread=2 AND n=1");
    put(old,1,0,9,"before");
    same(db);
    let result;
    do { result = legacyEditStep(db,8); assert.ok(result.visited<=8); same(db); } while (!result.ready);
    old.exec("UPDATE entries SET target=2,card='yes' WHERE thread=1 AND n=3");
    old.exec("INSERT OR IGNORE INTO entries VALUES(1,8,'edit',1,'ignored',NULL,'ignored')");
    same(db);
    while (legacyEditDrain(db,8)) same(db);
    same(db);
    assert.deepEqual(db.prepare("SELECT thread,target,n FROM legacy_edit_build ORDER BY thread,target,n").all(),
      db.prepare("SELECT thread,target,n FROM entries WHERE target IS NOT NULL ORDER BY thread,target,n").all());
  } finally { old.close(); rig.close(); }
});

test("prepared edit lookup seeks the newest key even for many edits of one message", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) put(db,1,n,1);
    while (!legacyEditStep(db,16).ready) { /* prepare */ }
    let visited = 0;
    db.function("visit_prepared_edit", (_n) => { visited++; return 1; });
    const sql = legacyEditLatest("?1","?2");
    const traced = sql.replace("AND s.target=?2", "AND s.target=?2 AND visit_prepared_edit(s.n)");
    assert.notEqual(traced,sql);
    assert.equal(db.prepare(`SELECT ${traced} AS n`).get(1,1)?.n,400);
    assert.equal(visited,1);
    const plan = db.prepare(`EXPLAIN QUERY PLAN SELECT ${sql}`).all(1,1).map((r) => String(r.detail)).join("\n");
    assert.match(plan,/SEARCH s USING PRIMARY KEY \(thread=\? AND target=\? AND n>\?\)/,plan);
  } finally { rig.close(); }
});

test("a completed lookup skips changed candidates of other messages", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) { put(db,1,n,1); put(db,2,n,2); }
    while (!legacyEditStep(db,16).ready) { /* prepare */ }
    db.exec("UPDATE entries SET target=3 WHERE thread=2");
    let prepared=0, changed=0, fallback=0;
    db.function("visit_fast_edit", () => { prepared++; return 1; });
    db.function("visit_changed_edit", () => { changed++; return 1; });
    db.function("visit_fallback_edit", () => { fallback++; return 1; });
    const source = legacyEditLatest("?1","?2");
    const traced = source.replaceAll("s.thread=?1 AND s.target=?2", "s.thread=?1 AND s.target=?2 AND visit_fast_edit()")
      .replace("t.thread=?1 AND t.target=?2 AND x.target=t.target", "t.thread=?1 AND t.target=?2 AND visit_changed_edit() AND x.target=t.target")
      .replace("x.thread=?1 AND x.target=?2", "x.thread=?1 AND x.target=?2 AND visit_fallback_edit()");
    assert.notEqual(traced,source);
    assert.ok(traced.includes("visit_fast_edit()") && traced.includes("visit_changed_edit()") && traced.includes("visit_fallback_edit()"));
    assert.equal(db.prepare(`SELECT ${traced} AS n`).get(1,1)?.n,400);
    assert.deepEqual({ prepared,changed,fallback },{ prepared:1,changed:0,fallback:0 });
  } finally { rig.close(); }
});

test("changed latest edits do not make the prepared arm reread the whole history", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) put(db,1,n,1);
    while (!legacyEditStep(db,16).ready) { /* prepare */ }
    db.exec("UPDATE entries SET target=2 WHERE thread=1");
    db.exec("UPDATE entries SET target=1 WHERE thread=1");
    let visited=0;
    db.function("visit_prepared_changed_edit", () => { visited++; return 1; });
    const source=legacyEditLatest("?1","?2");
    const traced=source.replace("AND s.n>=COALESCE", "AND visit_prepared_changed_edit() AND s.n>=COALESCE");
    assert.notEqual(traced,source);
    assert.equal(db.prepare(`SELECT ${traced} AS n`).get(1,1)?.n,400);
    assert.ok(visited<=1,`prepared branch visited ${visited} changed entries`);
  } finally { rig.close(); }
});

test("a changed-away edit history does not make a lookup walk all stale candidates", () => {
  const visitsFor = (size: number) => {
    const rig=database(), {db}=rig;
    try {
      for (let n=1;n<=size;n++) put(db,1,n,1);
      while (!legacyEditStep(db,16).ready) { /* prepare */ }
      db.exec("UPDATE entries SET target=2 WHERE thread=1");
      let visited=0;
      db.function("visit_stale_edit", (n) => { visited++; return n; });
      const source=legacyEditLatest("?1","?2");
      const traced=source.replace("ON x.thread=t.thread AND x.n=t.n", "ON x.thread=t.thread AND x.n=visit_stale_edit(t.n)")
        .replaceAll("d.thread=s.thread AND d.n=s.n", "d.thread=s.thread AND d.n=visit_stale_edit(s.n)");
      assert.notEqual(traced,source);
      const read=db.prepare(`SELECT ${traced} AS n`);
      assert.equal(read.get(1,2)?.n,size);
      assert.ok(visited>0,"the probe counted matching changed candidates");
      visited=0;
      assert.equal(read.get(1,1)?.n,null);
      return visited;
    } finally { rig.close(); }
  };
  const small=visitsFor(40),large=visitsFor(400);
  assert.equal(large,small,`stale edit candidates visited: ${small} / ${large}`);
});

test("a failed edit batch rolls back its cursor and staged entries", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=40;n++) put(db,1,n,1);
    installLegacyEdits(db);
    db.exec("CREATE TRIGGER fail_edit_batch BEFORE INSERT ON legacy_edit_build WHEN NEW.n=4 BEGIN SELECT RAISE(ABORT,'interrupted'); END");
    assert.throws(() => legacyEditStep(db,8),/interrupted/);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_edit_build").get()?.n,0);
    assert.equal(db.prepare("SELECT cursor_n FROM legacy_edit_meta").get()?.cursor_n,null);
    db.exec("DROP TRIGGER fail_edit_batch");
    while (!legacyEditStep(db,8).ready) { /* retry */ }
    assert.equal(actual(db,1,1),40);
  } finally { rig.close(); }
});

test("each edit-preparation batch seeks its next entry range", () => {
  const rig=database(), {db}=rig;
  try {
    for (let n=1;n<=400;n++) { put(db,1,n,n%3); put(db,2,n,n%3); }
    installLegacyEdits(db);
    let visited=0,queries=0;
    db.function("visit_edit_scan", () => { visited++; return 1; });
    const counted=new Proxy(db,{get(target,property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("SELECT CAST(e.thread AS TEXT) thread,CAST(e.n AS TEXT) n FROM entries e")) {
          queries++;
          const measured=sql.replace(/FROM entries e\s+WHERE/,"FROM entries e WHERE visit_edit_scan() AND");
          assert.notEqual(measured,sql); sql=measured;
        }
        return target.prepare(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    }});
    let step;
    do { visited=0; step=legacyEditStep(counted,8); assert.ok(visited<=8,`a batch read ${visited} entries`); } while (!step.ready);
    assert.ok(queries>8);
  } finally { rig.close(); }
});

test("the current-row bound does not assume rowid and edit number have the same order", () => {
  const rig=database(), {db}=rig;
  try {
    db.exec("INSERT INTO entries(rowid,thread,n,kind,target) VALUES(400,1,1,'edit',9),(300,1,2,'edit',9),(200,1,3,'edit',9)");
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    db.exec("UPDATE entries SET target=2 WHERE thread=1 AND n=3");
    db.exec("INSERT INTO entries(rowid,thread,n,kind,target) VALUES(100,1,4,'edit',9)");
    assert.equal(actual(db,1,9),4);
    db.exec("DELETE FROM entries WHERE thread=1 AND n=4");
    assert.equal(actual(db,1,9),2);
    const plan=db.prepare(`EXPLAIN QUERY PLAN SELECT n FROM entries INDEXED BY entries_target
      WHERE thread=? AND target=? ORDER BY rowid DESC LIMIT 1`).all(1,9).map((r) => String(r.detail)).join("\n");
    assert.match(plan,/SEARCH entries USING INDEX entries_target \(thread=\? AND target=\?\)/,plan);
    assert.doesNotMatch(plan,/USE TEMP B-TREE/,plan);
  } finally { rig.close(); }
});

test("an edit lookup reads its readiness and candidates from one snapshot", () => {
  const rig=database(), {db}=rig, old=new DatabaseSync(rig.path);
  try {
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    db.function("write_during_edit_read", () => { old.exec("UPDATE entries SET target=2 WHERE thread=1 AND n=1"); return 1; });
    const source=legacyEditLatest("?1","?2");
    const traced=source.replace("WHEN NOT EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1)",
      "WHEN write_during_edit_read() AND NOT EXISTS (SELECT 1 FROM legacy_edit_dirty LIMIT 1)");
    assert.notEqual(traced,source);
    assert.equal(db.prepare(`SELECT ${traced} AS n`).get(1,1)?.n,1);
    assert.equal(actual(db,1,1),null);
    assert.equal(actual(db,1,2),1);
  } finally { old.close(); rig.close(); }
});

test("an old store without a usable target index is still readable during bounded preparation", () => {
  const rig = database(), { db } = rig;
  try {
    for (let n=1;n<=400;n++) put(db,1,n,n%3+1);
    db.exec("DROP INDEX entries_target");
    installLegacyEdits(db);
    assert.equal(legacyEditsUseOldIndex(db),false);
    const read=db.prepare(`SELECT ${legacyEditLatest("?1","?2","1",false)} AS n`);
    const expected=db.prepare("SELECT MAX(n) n FROM entries WHERE thread=?1 AND target=?2");
    const same=() => { for (const target of [1,2,3,4]) assert.equal(read.get(1,target)?.n,expected.get(1,target)?.n); };
    same();
    let result;
    do { result=legacyEditStep(db,8); assert.ok(result.visited<=8); same(); } while (!result.ready);
    db.exec("UPDATE entries SET target=4 WHERE thread=1 AND n=10");
    same();
    while (legacyEditDrain(db,8)) same();
  } finally { rig.close(); }
});

test("edit preparation preserves SQLite values and integer ordering", () => {
  const rig = database(), { db } = rig;
  try {
    const putValue = db.prepare("INSERT INTO entries(thread,n,kind,target) VALUES(1,?,'edit',?)");
    putValue.run(2,"not-a-number"); putValue.run(3,new Uint8Array([0,1,2]));
    putValue.run(9007199254740999n,9007199254740997n);
    putValue.run(9007199254741001n,9007199254740997n);
    while (!legacyEditStep(db,2).ready) { /* prepare */ }
    assert.equal(db.prepare(`SELECT CAST(${legacyEditLatest("1","9007199254740997")} AS TEXT) AS n`).get()?.n,"9007199254741001");
    db.exec("UPDATE entries SET target=x'0102' WHERE n=2; UPDATE entries SET target='new text' WHERE n=3");
    while (legacyEditDrain(db,2)) { /* reconcile */ }
    const staged = db.prepare("SELECT target,CAST(n AS TEXT) n FROM legacy_edit_build ORDER BY legacy_edit_build.n");
    const entries = db.prepare("SELECT target,CAST(n AS TEXT) n FROM entries WHERE target IS NOT NULL ORDER BY entries.n");
    staged.setReadBigInts(true); entries.setReadBigInts(true);
    assert.deepEqual(staged.all(),entries.all());
  } finally { rig.close(); }
});

test("ignored invalid writes do not make an older writer fail", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    assert.doesNotThrow(() => db.exec("INSERT OR IGNORE INTO entries(thread,n,kind,target) VALUES(1,NULL,'edit',1)"));
    assert.doesNotThrow(() => db.exec("INSERT OR IGNORE INTO entries(thread,n,kind,target) VALUES(NULL,2,'edit',1)"));
    assert.doesNotThrow(() => db.exec("UPDATE OR IGNORE entries SET n=NULL WHERE thread=1 AND n=1"));
    same(db);
    while (legacyEditDrain(db,8)) { /* reconcile */ }
    assert.equal(actual(db,1,1),1);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`nested replacements expose the current edit target (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"};
      CREATE TRIGGER nested_edit BEFORE INSERT ON entries WHEN NEW.text='outer' BEGIN
        INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'edit',2,'inner',NULL,'inner'); END;`);
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    const current = (target: number) => legacyEditLatest("NEW.thread",String(target));
    db.exec(`CREATE TABLE observed(which TEXT,n INTEGER);
      CREATE TRIGGER observe_edit AFTER INSERT ON entries WHEN NEW.text IN ('inner','outer') BEGIN
        INSERT INTO observed SELECT NEW.text,(${current(2)}) WHERE NEW.text='inner';
        INSERT INTO observed SELECT NEW.text,(${current(3)}) WHERE NEW.text='outer'; END;`);
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,1,'edit',3,'outer',NULL,'outer')");
    assert.deepEqual(db.prepare("SELECT which,n FROM observed ORDER BY rowid").all().map((r) => ({ ...r })),
      [{ which:"inner",n:1 },{ which:"outer",n:1 }]);
    same(db);
    while (legacyEditDrain(db,8)) same(db);
  } finally { rig.close(); }
});

for (const alias of ["rowid","_rowid_","oid"]) test(`an old writer replacing an edit by ${alias} keeps its lookup exact`, () => {
  const rig = database(), { db } = rig, old = new DatabaseSync(rig.path);
  try {
    put(db,1,1,1); put(db,2,2,2); put(db,3,3,3);
    while (!legacyEditStep(db,2).ready) { /* prepare */ }
    const displaced = old.prepare("SELECT rowid id FROM entries WHERE thread=2 AND n=2").get()!.id;
    old.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=1 AND n=1`).run(displaced);
    same(db);
    while (legacyEditDrain(db,2)) same(db);
    assert.deepEqual(db.prepare("SELECT thread,target,n FROM legacy_edit_build ORDER BY thread,target,n").all(),
      db.prepare("SELECT thread,target,n FROM entries WHERE target IS NOT NULL ORDER BY thread,target,n").all());
  } finally { old.close(); rig.close(); }
});

test("many changes to one edit target are removed in bounded batches", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    const update = db.prepare("UPDATE entries SET target=? WHERE thread=1 AND n=1");
    for (let target=2;target<=401;target++) update.run(target);
    let removed = 0, read = 0;
    db.function("visit_edit_cleanup", () => { removed++; return 1; });
    db.function("visit_edit_cleanup_read", () => { read++; return 1; });
    db.exec("CREATE TRIGGER count_edit_cleanup AFTER DELETE ON legacy_edit_targets BEGIN SELECT visit_edit_cleanup(); END");
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM legacy_edit_targets INDEXED BY legacy_edit_targets_by_key")) {
          const measured=sql.replace("AND n=CAST(?2 AS INTEGER)","AND n=CAST(?2 AS INTEGER) AND visit_edit_cleanup_read()");
          assert.notEqual(measured,sql); sql=measured;
        }
        return target.prepare(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    }});
    while (true) {
      removed = 0; read = 0;
      const visited = legacyEditDrain(traced,8);
      assert.ok(visited<=8);
      assert.ok(removed<=8,`one batch removed ${removed} targets`);
      assert.ok(read<=9,`one batch read ${read} targets`);
      assert.equal(actual(db,1,401),1);
      if (!visited) break;
    }
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_edit_targets").get()?.n,0);
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_edit_dirty").get()?.n,0);
  } finally { rig.close(); }
});

test("unrelated writes do not add edit preparation work", () => {
  const rig = database(), { db } = rig;
  try {
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    for (let n=2;n<=401;n++) put(db,1,n,null);
    db.exec("UPDATE entries SET text='changed' WHERE thread=1");
    db.exec("DELETE FROM entries WHERE thread=1 AND target IS NULL");
    assert.equal(db.prepare("SELECT COUNT(*) n FROM legacy_edit_dirty").get()?.n,0);
    assert.equal(actual(db,1,1),1);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) test(`later triggers can replace an edit before its outer write (recursive triggers ${recursive})`, () => {
  const rig = database(), { db } = rig;
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    put(db,1,1,1);
    while (!legacyEditStep(db,8).ready) { /* prepare */ }
    db.exec(`CREATE TRIGGER later_nested_edit BEFORE INSERT ON entries WHEN NEW.text='outer' BEGIN
      INSERT OR REPLACE INTO entries VALUES(NEW.thread,NEW.n,'edit',2,'inner',NULL,'inner'); END;`);
    const current = (target: number) => legacyEditLatest("NEW.thread",String(target));
    db.exec(`CREATE TABLE observed(which TEXT,n INTEGER);
      CREATE TRIGGER observe_later_edit AFTER INSERT ON entries WHEN NEW.text IN ('inner','outer') BEGIN
        INSERT INTO observed SELECT NEW.text,(${current(2)}) WHERE NEW.text='inner';
        INSERT INTO observed SELECT NEW.text,(${current(3)}) WHERE NEW.text='outer'; END;`);
    db.exec("INSERT OR REPLACE INTO entries VALUES(1,1,'edit',3,'outer',NULL,'outer')");
    assert.deepEqual(db.prepare("SELECT which,n FROM observed ORDER BY rowid").all().map((r) => ({ ...r })),
      [{ which:"inner",n:1 },{ which:"outer",n:1 }]);
    same(db);
    while (legacyEditDrain(db,8)) same(db);
  } finally { rig.close(); }
});

for (const recursive of [false,true]) for (const when of ["BEFORE","AFTER"]) for (const by of ["number","timestamp","rowid"]) {
  for (const installFirst of [false,true]) test(`nested ${when.toLowerCase()} ${by} replacements preserve edit reads (recursive ${recursive}, installed first ${installFirst})`, () => {
    const rig = database(), { db } = rig;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      db.exec("INSERT INTO entries(rowid,thread,n,kind,target,ts,text) VALUES(1,1,1,'edit',1,'old','old')");
      db.exec("INSERT INTO entries(rowid,thread,n,kind,target,ts,text) VALUES(2,1,2,'edit',2,'other','other')");
      const install = () => { installLegacyEdits(db); while (!legacyEditStep(db,8).ready) { /* prepare */ } };
      const nested = `CREATE TRIGGER nested_matrix ${when} INSERT ON entries WHEN NEW.text='outer' BEGIN
        INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,text)
        VALUES(${by === "rowid" ? "NEW.rowid" : "900"},${by === "rowid" ? "2" : "NEW.thread"},
          ${by === "number" ? "NEW.n" : "99"},'edit',2,${by === "timestamp" ? "NEW.ts" : "'inner'"},'inner'); END`;
      if (installFirst) install();
      db.exec(nested);
      if (!installFirst) install();
      const checks = [1,2].flatMap((thread) => [1,2,3].map((target) => `INSERT INTO observed
        SELECT NEW.text,${thread},${target},(${legacyEditLatest(String(thread),String(target))}),
          (SELECT MAX(n) FROM entries WHERE thread=${thread} AND target=${target});`)).join("\n");
      db.exec(`CREATE TABLE observed(which TEXT,thread INTEGER,target INTEGER,actual INTEGER,expected INTEGER);
        CREATE TRIGGER observe_matrix AFTER INSERT ON entries WHEN NEW.text IN ('inner','outer') BEGIN ${checks} END;`);
      db.exec("INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,text) VALUES(3,1,3,'edit',3,'outer','outer')");
      const observations = db.prepare("SELECT * FROM observed ORDER BY rowid").all();
      assert.ok(observations.some((r) => r.which === "inner"));
      assert.ok(observations.some((r) => r.which === "outer"));
      for (const row of observations) assert.equal(row.actual,row.expected,JSON.stringify(row));
      same(db);
      while (legacyEditDrain(db,8)) same(db);
    } finally { rig.close(); }
  });
}
