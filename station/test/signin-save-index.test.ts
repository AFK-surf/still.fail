import assert from "node:assert/strict";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installSigninSaveIndex, SIGNIN_SAVE, signinForSave, signinSaveComplete, stepSigninSaveIndex } from "../src/vault/signin-save-index.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE signin_asks (id TEXT PRIMARY KEY, session TEXT NOT NULL, owner TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL);
    CREATE INDEX signin_asks_by_session ON signin_asks (session, status);`);
  const put = db.prepare("INSERT INTO signin_asks (id, session, owner, status, body) VALUES (?, ?, 'p', ?, ?)");
  const add = (id: string, session: string, status: string, save?: string) => put.run(id, session, status, JSON.stringify({ id, session, status, ...(save ? { save } : {}) }));
  const rows = () => (db.prepare("SELECT ask,session,save FROM signin_save_lookup ORDER BY ask").all() as {ask:string;session:string;save:string}[])
    .map((row) => [row.ask, row.session, row.save]);
  const expected = () => (db.prepare("SELECT id,session,json_extract(body,'$.save') AS save FROM signin_asks WHERE json_type(body,'$.save')='text' ORDER BY id")
    .all() as {id:string;session:string;save:string}[]).map((row) => [row.id,row.session,row.save]);
  return { db, add, rows, expected };
}

test("old sign-ins are indexed only in bounded resumable session batches", () => {
  const { db, add, rows, expected } = fixture();
  try {
    for (let n=0; n<200; n++) add(`other-${n}`, "other", "done", `save-other-${n}`);
    add("a", "target", "done", "save-a"); add("b", "target", "done"); add("c", "target", "pending", "save-c");
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "signin_asks" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installSigninSaveIndex(db); } finally { db.setAuthorizer(null); }
    assert.deepEqual(rows(), []);
    assert.deepEqual(stepSigninSaveIndex(db, "target", 1), { done:false, visited:1 });
    // A changed row and a new row behind the cursor remain covered even across a restart.
    db.prepare("UPDATE signin_asks SET status='aaa',body=? WHERE id='c'").run(JSON.stringify({ id:"c", session:"target", status:"aaa", save:"save-c2" }));
    add("new", "target", "aaa", "save-new");
    installSigninSaveIndex(db);
    let steps=0;
    while (!signinSaveComplete(db, "target")) {
      const step = stepSigninSaveIndex(db, "target", 1);
      assert.ok(step.visited <= 1);
      assert.ok(++steps < 10);
    }
    assert.deepEqual(rows(), expected().filter((row) => row[1] === "target"));
    assert.equal(JSON.parse(signinForSave(db,"target","save-a")!).id, "a");
    assert.equal(signinForSave(db,"other","save-a"), null);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${SIGNIN_SAVE}`).all("target","save-a") as {detail:string}[]).map((row) => row.detail).join(" | ");
    assert.match(plan, /SEARCH l USING COVERING INDEX signin_save_by_request \(session=\? AND save=\?\)/);
    assert.match(plan, /SEARCH a USING INDEX .* \(id=\?\)/);
  } finally { db.close(); }
});

test("a resumed sign-in batch seeks past old rows with the same status", () => {
  const { db, add } = fixture();
  try {
    db.exec("BEGIN");
    for (let n=0; n<5_000; n++) { add(`old-${n}`, "target", "done"); add(`other-${n}`, "other", "done"); }
    db.exec("COMMIT");
    installSigninSaveIndex(db);
    const row = (db.prepare("SELECT rowid AS row FROM signin_asks WHERE id = ?").get("old-4900") as {row:number}).row;
    db.prepare("INSERT INTO signin_save_progress VALUES ('target', 'done', ?, 0)").run(row);
    let visited = 0;
    db.function("visit_signin", (_row) => { visited++; return 1; });
    const prepare = db.prepare.bind(db);
    db.prepare = ((sql: string) => prepare(sql.startsWith("SELECT status, rowid AS row FROM")
      ? sql.replace("WHERE session = ?1", "WHERE visit_signin(rowid) AND session = ?1") : sql)) as typeof db.prepare;
    assert.deepEqual(stepSigninSaveIndex(db, "target", 2), { done: false, visited: 2 });
    assert.ok(visited <= 3, `the cursor seeks beyond same-status rows (visited ${visited})`);
  } finally { db.close(); }
});

for (const recursive of [false,true]) test(`sign-in save lookup follows older writers and replacements (recursive triggers ${recursive})`, () => {
  const { db, add, rows, expected } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installSigninSaveIndex(db);
    add("a", "one", "done", "save-a"); add("b", "one", "done", "save-b");
    const same = () => assert.deepEqual(rows(),expected());
    same();
    db.prepare("UPDATE signin_asks SET session='two', body=? WHERE id='a'").run(JSON.stringify({ id:"a", session:"two", save:"save-new" })); same();
    db.prepare("INSERT OR IGNORE INTO signin_asks (id,session,owner,status,body) VALUES ('a','one','p','done',?)").run(JSON.stringify({ save:"ignored" })); same();
    db.prepare("INSERT OR REPLACE INTO signin_asks (id,session,owner,status,body) VALUES ('a','one','p','done',?)").run(JSON.stringify({ save:"replaced" })); same();
    db.prepare("UPDATE OR REPLACE signin_asks SET id='b',body=? WHERE id='a'").run(JSON.stringify({ save:"evicted" })); same();
    db.prepare("DELETE FROM signin_asks WHERE id='b'").run(); same();
  } finally { db.close(); }
});
