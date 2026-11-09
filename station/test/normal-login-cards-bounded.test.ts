import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { hasLegacyLoginCards, LEGACY_LOGIN_CARDS, LEGACY_LOGIN_CARDS_NATIVE, legacyLoginCardsStep } from "../src/store/legacy-login-cards.ts";
import { LOGIN_CARDS, Store } from "../src/store/store.ts";
import { withoutLoginKeys } from "./legacy-login-fixture.ts";

function fill(store: Store, count: number): number {
  const thread = store.openThread("ember", "CHAT", `normal-login-${count}`, null, null).id;
  const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card)
    VALUES(?,?,'message','agent','agent',?,?)`);
  for (let n = 1; n <= count; n++) put.run(thread, n, n, JSON.stringify({ type: "login", login: `old${n}` }));
  put.run(thread, count + 1, count + 1, JSON.stringify({ type: "login", login: "wanted" }));
  return thread;
}

/// Count candidates read by the actual Store method, regardless of which lookup it selects.
function closeAndCount(store: Store, thread: number, expected: number): number {
  const db = store.db, prepare = DatabaseSync.prototype.prepare;
  let visited = 0, traced = false;
  db.function("visit_normal_login_candidate", () => { visited++; return 1; });
  DatabaseSync.prototype.prepare = function (this: DatabaseSync, sql: string) {
    if (sql === LOGIN_CARDS) {
      sql = sql.replace("AND card LIKE ? AND NOT EXISTS",
        "AND CASE WHEN visit_normal_login_candidate()=1 THEN card LIKE ? ELSE 0 END AND NOT EXISTS");
      traced = true;
    } else if (sql === LEGACY_LOGIN_CARDS || sql === LEGACY_LOGIN_CARDS_NATIVE) {
      sql = sql.replaceAll("AND e.card LIKE ?2",
        "AND CASE WHEN visit_normal_login_candidate()=1 THEN e.card LIKE ?2 ELSE 0 END");
      traced = true;
    }
    return prepare.call(this, sql);
  };
  try {
    assert.deepEqual(store.closeLoginCards("wanted"), ["agent"]);
    assert.ok(traced, "the lookup used by closeLoginCards was instrumented");
    assert.ok(db.prepare("SELECT 1 FROM closed_cards WHERE thread=? AND n=?").get(thread, expected));
    return visited;
  } finally { DatabaseSync.prototype.prepare = prepare; }
}

test("a new store closes one login without reading the other login cards", () => {
  const visits: number[] = [];
  for (const count of [40, 400]) {
    const store = Store.open(":memory:");
    try { visits.push(closeAndCount(store, fill(store, count), count + 1)); }
    finally { store.close(); }
  }
  assert.ok(visits.every((n) => n <= 2), `one login read ${visits.join(" / ")} candidate cards`);
});

test("an existing native login-card index prepares a bounded lookup for its old cards", () => {
  const dir = mkdtempSync(join(tmpdir(), "normal-login-")), path = join(dir, "station.db");
  let thread = 0;
  try {
    const initial = Store.open(path);
    try { thread = fill(initial, 400); } finally { initial.close(); }
    // Model a store made before the per-login lookup existed, retaining its native card index.
    const old = new DatabaseSync(path);
    try {
      withoutLoginKeys(old);
    } finally { old.close(); }
    const store = Store.open(path);
    try {
      assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_login_cards'").get());
      assert.ok(hasLegacyLoginCards(store.db), "the per-login lookup is installed for this store");
      while (!legacyLoginCardsStep(store.db, 64).ready) { /* bounded preparation */ }
      assert.ok(closeAndCount(store, thread, 401) <= 2);
    } finally { store.close(); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("an old prepared writer and the native fallback stay usable while login keys are prepared", () => {
  const dir=mkdtempSync(join(tmpdir(), "normal-login-old-writer-")), path=join(dir, "station.db");
  const initial=Store.open(path), thread=fill(initial,80);
  initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null;
  try {
    withoutLoginKeys(old);
    const write=old.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card)
      VALUES(?,?,'message','agent','old-writer',?,?)`);
    store=Store.open(path);
    assert.equal(store.db.prepare("SELECT scanned FROM login_card_meta WHERE id=1").get()?.scanned,0);
    write.run(thread,82,82,JSON.stringify({type:"login",login:"before"}));
    let selected = "";
    const prepare=DatabaseSync.prototype.prepare;
    DatabaseSync.prototype.prepare=function (this: DatabaseSync, sql: string) {
      if (sql === LEGACY_LOGIN_CARDS_NATIVE || sql === LEGACY_LOGIN_CARDS) selected=sql;
      return prepare.call(this,sql);
    };
    try { assert.deepEqual(store.closeLoginCards("before"),["old-writer"]); }
    finally { DatabaseSync.prototype.prepare=prepare; }
    assert.equal(selected,LEGACY_LOGIN_CARDS_NATIVE);
    const plan=store.db.prepare(`EXPLAIN QUERY PLAN ${selected}`).all("before",'%"login":"before"%');
    assert.ok(plan.some((r) => String(r.detail).includes("USING INDEX entries_login_cards")));
    while (!legacyLoginCardsStep(store.db,8).ready) { /* bounded preparation */ }
    old.exec("DROP INDEX entries_login_cards");
    write.run(thread,83,83,JSON.stringify({type:"login",login:"after"}));
    assert.deepEqual(store.closeLoginCards("after"),["old-writer"]);
  } finally { store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});

test("a login lookup falls back if another connection removes the native index at preparation", () => {
  const dir=mkdtempSync(join(tmpdir(), "normal-login-index-race-")), path=join(dir, "station.db");
  const initial=Store.open(path);
  fill(initial,2);
  initial.close();
  const old=new DatabaseSync(path,{timeout:5000});
  let store: Store | null=null;
  try {
    withoutLoginKeys(old);
    store=Store.open(path);
    let removed=false;
    const prepare=DatabaseSync.prototype.prepare;
    DatabaseSync.prototype.prepare=function (this: DatabaseSync, sql: string) {
      if (sql === LEGACY_LOGIN_CARDS_NATIVE && !removed) {
        old.exec("DROP INDEX entries_login_cards");
        removed=true;
      }
      return prepare.call(this,sql);
    };
    try { assert.deepEqual(store.closeLoginCards("wanted"),["agent"]); }
    finally { DatabaseSync.prototype.prepare=prepare; }
    assert.ok(removed, "the native index disappeared after the lookup checked for it");
  } finally { store?.close(); old.close(); rmSync(dir,{recursive:true,force:true}); }
});
