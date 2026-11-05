import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { CARD_POST_ADD_CHANGED, cardPostsReady, cardPostsStep, installCardPosts } from "../src/store/card-post-index.ts";

const textCard = '{"type":"text"}';
function beforeIndex(db: DatabaseSync): void {
  const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'card_post%' AND type IN ('trigger','table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type))
    db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
}
const posts = (db: DatabaseSync, thread: number) => db.prepare(
  "SELECT CAST(n AS TEXT) AS n FROM card_posts WHERE thread=? ORDER BY card_posts.n",
).all(thread).map((row) => row.n);

test("a failed card post index installation leaves no partial schema", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    db.exec("CREATE TABLE card_posts (sentinel INTEGER)");
    assert.throws(() => installCardPosts(db), /already exists/);
    const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'card_post%' ORDER BY name").all();
    assert.deepEqual(objects.map((row) => [row.type, row.name]), [["table", "card_posts"]]);
  } finally { store.close(); }
});

test("an incompatible card post index is neither read nor prepared", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "incompatible", null, null).id;
    db.exec("UPDATE card_post_meta SET version=999");
    assert.throws(() => cardPostsReady(db, thread), /incompatible/);
    assert.throws(() => cardPostsStep(db, thread), /incompatible/);
    assert.throws(() => installCardPosts(db), /incompatible/);
  } finally { store.close(); }
});
const original = (db: DatabaseSync, thread: number) => db.prepare(
  "SELECT CAST(n AS TEXT) AS n FROM entries WHERE thread=? AND kind='message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY entries.n",
).all(thread).map((row) => row.n);

test("reconciling a card post seeks its changed entries", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installCardPosts(db);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${CARD_POST_ADD_CHANGED}`).all().map((row) => String(row.detail)).join("\n");
    assert.match(plan, /SCAN c/);
    assert.match(plan, /SEARCH e USING INDEX .*entries/);
    assert.doesNotMatch(plan, /SCAN e/);
  } finally { store.close(); }
});

test("a new card post does not stage a conflict", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    installCardPosts(db);
    const thread = store.openThread("ember", "CHAT", "fast", null, null).id;
    let staged = 0;
    db.function("count_card_post_stage", () => { staged++; return 0; });
    db.exec("CREATE TRIGGER count_card_post_stage AFTER INSERT ON card_post_changed BEGIN SELECT count_card_post_stage(); END");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,?,'message','agent','a',?,?)");
    for (let n = 1; n <= 20; n++) put.run(thread, n, n, textCard);
    assert.equal(staged, 0);
    assert.deepEqual(posts(db, thread), original(db, thread));
    db.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,author_kind,author,at) VALUES(?,1,'message','agent','a',21)").run(thread);
    assert.ok(staged > 0);
    assert.deepEqual(posts(db, thread), original(db, thread));
  } finally { store.close(); }
});

for (const recursive of [false, true]) {
  test(`card posts follow mixed writes and replacements (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      beforeIndex(db);
      const untracked = store.openThread("ember", "CHAT", "untracked", null, null).id;
      installCardPosts(db);
      const tracked = store.openThread("ember", "CHAT", "tracked", null, null).id;
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
        const a = store.openThread("ember", "CHAT", "a", null, null).id;
        const b = store.openThread("ember", "CHAT", "b", null, null).id;
        const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,1,'message','agent','a',1,?)");
        put.run(a, textCard); put.run(b, textCard);
        const rowid = (db.prepare("SELECT rowid FROM entries WHERE thread=? AND n=1").get(b) as { rowid: number }).rowid;
        db.prepare(`UPDATE OR REPLACE entries SET ${alias}=? WHERE thread=? AND n=1`).run(rowid, a);
        assert.deepEqual(posts(db, a), original(db, a));
        assert.deepEqual(posts(db, b), original(db, b));
      } finally { store.close(); }
    });
  }
  test(`card posts agree after interleaved writes (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
      beforeIndex(db);
      const untracked = store.openThread("ember", "CHAT", "untracked", null, null).id;
      installCardPosts(db);
      const tracked = ["one", "two"].map((name) => store.openThread("ember", "CHAT", name, null, null).id);
      const threads = [...tracked, untracked];
      let seed = 71239;
      const next = (max: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
      const insert = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,card,options)
        VALUES(?,?,?,?,?,?,'agent','a',?,?,?)`);
      const ignore = db.prepare(`INSERT OR IGNORE INTO entries(rowid,thread,n,kind,target,ts,author_kind,author,at,card,options)
        VALUES(?,?,?,?,?,?,'agent','a',?,?,?)`);
      const update = db.prepare(`UPDATE OR REPLACE entries SET rowid=?,thread=?,n=?,kind=?,target=?,ts=?,at=?,card=?,options=? WHERE rowid=?`);
      for (let step = 0; step < 150; step++) {
        const current = db.prepare("SELECT rowid FROM entries ORDER BY rowid").all() as { rowid: number }[];
        const action = current.length === 0 ? 0 : next(4);
        if (action === 3) db.prepare("DELETE FROM entries WHERE rowid=?").run(current[next(current.length)]!.rowid);
        else {
          const kind = next(3) === 0 ? "edit" : "message";
          const args = [next(25) - 1, threads[next(threads.length)]!, next(16) - 3, kind,
            kind === "edit" ? next(16) - 3 : null, next(4) === 0 ? `ts-${next(8)}` : null,
            next(20), next(3) === 0 ? textCard : null, next(3) === 0 ? '["yes"]' : null] as const;
          if (action === 2) update.run(...args, current[next(current.length)]!.rowid);
          else (action === 1 ? ignore : insert).run(...args);
        }
        for (const thread of tracked) assert.deepEqual(posts(db, thread), original(db, thread), `step ${step}, thread ${thread}`);
      }
    } finally { store.close(); }
  });
}

test("old card posts are prepared in bounded batches while another connection writes", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-posts-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
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

test("a writer between the old-position read and commit cannot be missed", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-race-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  let other: DatabaseSync | null = null;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "CHAT", "race", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,1,'message','agent','a',1,?)").run(thread, textCard);
    installCardPosts(db);
    other = new DatabaseSync(path);
    let wrote = false;
    const watched = new Proxy(db, {
      get(target, key) {
        if (key === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (!sql.startsWith("SELECT CAST(n AS TEXT) AS n FROM")) return statement;
          return new Proxy(statement, {
            get(s, name) {
              if (name === "all") return (...args: Parameters<typeof s.all>) => {
                const rows = s.all(...args);
                if (!wrote) {
                  wrote = true;
                  other!.prepare("UPDATE entries SET card=NULL WHERE thread=? AND n=1").run(thread);
                  other!.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,-1,'message','agent','a',2,?)").run(thread, textCard);
                }
                return rows;
              };
              const value = Reflect.get(s, name, s);
              return typeof value === "function" ? value.bind(s) : value;
            },
          });
        };
        const value = Reflect.get(target, key, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) as DatabaseSync;
    let step = cardPostsStep(watched, thread, 4);
    while (!step.done) step = cardPostsStep(db, thread, 4);
    assert.equal(wrote, true);
    assert.deepEqual(posts(db, thread), original(db, thread));
  } finally { other?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed card post batch rolls back its rows and cursor", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    beforeIndex(db);
    const thread = store.openThread("ember", "CHAT", "rollback", null, null).id;
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
    beforeIndex(db);
    const thread = store.openThread("ember", "CHAT", "missing-index", null, null).id;
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
