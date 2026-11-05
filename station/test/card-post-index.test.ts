import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { cardPostsReady, cardPostsStep, installCardPosts } from "../src/store/card-post-index.ts";

const textCard = '{"type":"text"}';
const posts = (db: DatabaseSync, thread: number) => db.prepare(
  "SELECT CAST(n AS TEXT) AS n FROM card_posts WHERE thread=? ORDER BY card_posts.n",
).all(thread).map((row) => row.n);
const original = (db: DatabaseSync, thread: number) => db.prepare(
  "SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread=? AND kind='message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY entries.n",
).all(thread).map((row) => row.n);

for (const recursive of [false, true]) {
  test(`card posts follow mixed writes and replacements (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      const untracked = store.openThread("ember", "EMBER", "untracked", null, null).id;
      installCardPosts(db);
      const tracked = store.openThread("ember", "EMBER", "tracked", null, null).id;
      assert.equal(cardPostsReady(db, tracked), true);
      assert.equal(cardPostsReady(db, untracked), false);
      const put = db.prepare(`INSERT INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,card,options)
        VALUES(?,?,?,?,?,?,'agent','a',?,?,?)`);
      const replace = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,card,options)
        VALUES(?,?,?,?,?,?,'agent','a',?,?,?)`);
      const check = () => assert.deepEqual(posts(db, tracked), original(db, tracked));
      put.run(-1, tracked, 1, "message", null, "one", 1, textCard, null); check();
      // An automatic rowid is exposed as -1 in a BEFORE INSERT. Its apparent collision must not remove the real -1.
      db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,2,'message','agent','a',2)").run(tracked); check();
      put.run(4, tracked, 3, "edit", 1, null, 3, textCard, '["yes"]'); check();
      put.run(5, tracked, 4, "message", null, "four", 4, null, '["yes"]'); check();
      db.prepare("UPDATE entries SET card=?,options=NULL WHERE thread=? AND n=4").run(textCard, tracked); check();
      db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=4").run(tracked); check();
      db.prepare("UPDATE entries SET kind='message' WHERE thread=? AND n=4").run(tracked); check();
      replace.run(20, tracked, 5, "message", null, "four", 5, null, null); check();
      db.exec("BEGIN");
      replace.run(21, tracked, 6, "message", null, "six", 6, textCard, null); check();
      db.exec("ROLLBACK"); check();
      db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,author_kind,author,at)
        VALUES(-1,?,7,'message','agent','a',7)`).run(untracked); check();
      replace.run(-1, untracked, 8, "message", null, "elsewhere", 8, null, null); check();
    } finally { store.close(); }
  });
  for (const alias of ["rowid", "_rowid_", "oid"]) {
    test(`a card post displaced by ${alias} is removed (recursive triggers ${recursive})`, () => {
      const store = Store.open(":memory:"), db = store.db;
      try {
        db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
        installCardPosts(db);
        const a = store.openThread("ember", "EMBER", "a", null, null).id;
        const b = store.openThread("ember", "EMBER", "b", null, null).id;
        const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,1,'message','agent','a',1,?)");
        put.run(a, textCard); put.run(b, textCard);
        const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(b) as { rowid: number }).rowid;
        db.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=? AND n=1`).run(rowid, a);
        assert.deepEqual(posts(db, a), original(db, a));
        assert.deepEqual(posts(db, b), original(db, b));
      } finally { store.close(); }
    });
  }
}

test("old card posts are prepared in bounded batches while another connection writes", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-posts-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,at,card,options)
      VALUES(?,?,?,?,'agent','a',?,?,?)`);
    put.run(thread, 1, "message", null, 1, textCard, null);
    for (let n = 2; n <= 11; n++) put.run(thread, n, "edit", 1, n, textCard, '["yes"]');
    put.run(thread, 12, "message", null, 12, null, '["yes"]');
    db.exec(`INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(${thread},9007199254740993,'message','agent','a',13,'{}')`);
    installCardPosts(db);
    assert.equal(cardPostsReady(db, thread), false);
    let step = cardPostsStep(db, thread, 3);
    assert.ok(step.visited <= 3 && !step.done);
    other = new DatabaseSync(path);
    other.prepare("UPDATE entries SET card=NULL WHERE thread=? AND n=1").run(thread);
    other.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,0,'message','agent','a',0,?)").run(thread, textCard);
    for (let i = 0; !step.done && i < 30; i++) { step = cardPostsStep(db, thread, 3); assert.ok(step.visited <= 3); }
    assert.equal(step.done, true);
    assert.equal(cardPostsReady(db, thread), true);
    assert.deepEqual(posts(db, thread), original(db, thread));
    assert.ok(posts(db, thread).includes("9007199254740993"));
    other.prepare("DELETE FROM entries WHERE thread=? AND n=12").run(thread);
    assert.deepEqual(posts(db, thread), original(db, thread));
  } finally { other?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed card post batch rolls back its rows and cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "rollback", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,1,'message','agent','a',1,?)").run(thread, textCard);
    installCardPosts(db);
    db.exec("CREATE TRIGGER deny_card_post BEFORE INSERT ON card_posts BEGIN SELECT RAISE(ABORT, 'no'); END");
    assert.throws(() => cardPostsStep(db, thread, 3), /no/);
    assert.equal(cardPostsReady(db, thread), false);
    db.exec("DROP TRIGGER deny_card_post");
    let step = cardPostsStep(db, thread, 3);
    while (!step.done) step = cardPostsStep(db, thread, 3);
    assert.deepEqual(posts(db, thread), original(db, thread));
  } finally { store.close(); }
});

test("an old store losing a card index during preparation restarts the bounded primary-key walk", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "missing-index", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card,options) VALUES(?,?,'message','agent','a',?,?,?)");
    put.run(thread, 1, 1, null, '["yes"]');
    put.run(thread, 2, 2, textCard, null);
    put.run(thread, 3, 3, textCard, null);
    installCardPosts(db);
    assert.equal(cardPostsStep(db, thread, 1).done, false);
    db.exec("DROP INDEX entries_options");
    let step = cardPostsStep(db, thread, 1);
    for (let i = 0; !step.done && i < 10; i++) step = cardPostsStep(db, thread, 1);
    assert.equal(step.done, true);
    assert.deepEqual(posts(db, thread), original(db, thread));
  } finally { store.close(); }
});
