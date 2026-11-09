import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installLegacyLoginCards, legacyLoginCardsStep } from "../src/store/legacy-login-cards.ts";
import { LOGIN_CARD_TOKENS } from "./login-card-token-query.ts";

const schema = `CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,ts TEXT,kind TEXT NOT NULL,
  author_kind TEXT NOT NULL,author TEXT NOT NULL,card TEXT,PRIMARY KEY(thread,n));
  CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;
  CREATE INDEX entries_login_cards ON entries(thread,n) WHERE card LIKE '%"login"%';`;
const card = (id: string) => JSON.stringify({ type: "login", login: id });
function expected(db: DatabaseSync) {
  const tokens = db.prepare(LOGIN_CARD_TOKENS), result: { login: unknown; thread: unknown; n: unknown }[] = [];
  for (const row of db.prepare(`SELECT CAST(thread AS TEXT) thread,CAST(n AS TEXT) n,card FROM entries
    WHERE kind='message' AND author_kind='agent'`).all()) {
    for (const token of tokens.all(row.card)) if (typeof token.login === "string" && /^[0-9a-z]{1,40}$/.test(token.login)) {
      result.push({ login: token.login, thread: row.thread, n: row.n });
    }
  }
  return result.sort((a,b) => String(a.login).localeCompare(String(b.login)) || (BigInt(a.thread as string) < BigInt(b.thread as string) ? -1 :
    BigInt(a.thread as string) > BigInt(b.thread as string) ? 1 : BigInt(a.n as string) < BigInt(b.n as string) ? -1 : 1));
}
function actual(db: DatabaseSync) {
  return db.prepare("SELECT login,CAST(thread AS TEXT) thread,CAST(n AS TEXT) n FROM login_card_keys ORDER BY login,thread,n")
    .all().map((r) => ({ ...r }));
}
function finish(db: DatabaseSync, limit: number) {
  for (let i=0; i<1000; i++) {
    const step = legacyLoginCardsStep(db,limit);
    assert.ok(step.visited <= limit && step.tokens <= limit);
    if (step.ready) return;
  }
  assert.fail("preparation did not finish");
}

for (const recursive of [false,true]) {
  test(`old login candidates follow another writer during bounded preparation (recursive ${recursive})`, () => {
    const dir = mkdtempSync(join(tmpdir(),"login-card-build-")), path = join(dir,"store.db");
    const db = new DatabaseSync(path), old = new DatabaseSync(path);
    try {
      db.exec(`${schema} PRAGMA journal_mode=WAL;`);
      old.exec(`PRAGMA recursive_triggers=${recursive ? 1 : 0};`);
      const put = old.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,ts,kind,author_kind,author,card)
        VALUES(?,?,?,?,?,?,?,?)`);
      for (let i=1; i<=80; i++) put.run(i,1,i,`ts${i}`,"message","agent","agent",card(`old${i}`));
      installLegacyLoginCards(db);
      assert.equal((db.prepare("SELECT COUNT(*) AS n FROM login_card_keys").get() as { n: number }).n,0);
      const first = legacyLoginCardsStep(db,7);
      assert.equal(first.ready,false); assert.ok(first.visited <= 7 && first.tokens <= 7);
      assert.deepEqual((db.prepare("SELECT n FROM login_card_keys ORDER BY n").all() as { n: number }[]).map((r) => r.n), [1,2,3,4,5,6,7]);
      put.run(200,1,1,"replacement","message","agent","agent",card("new1"));
      assert.ok(db.prepare("SELECT 1 FROM login_card_keys WHERE login='old2'").get(),"old2 remains after replacing old1");
      put.run(201,1,90,"ts30","message","agent","agent",card("new90"));
      assert.ok(db.prepare("SELECT 1 FROM login_card_keys WHERE login='old2'").get(),"old2 remains after timestamp conflict");
      put.run(80,2,91,"rowid","message","agent","agent",card("new91"));
      assert.ok(db.prepare("SELECT 1 FROM login_card_keys WHERE login='old2'").get(),"old2 remains after rowid conflict");
      old.exec("DELETE FROM entries WHERE thread=1 AND n=50");
      old.prepare("UPDATE entries SET card=? WHERE thread=1 AND n=60").run('broken "login":"two" and "login":"three"');
      assert.ok(db.prepare("SELECT 1 FROM login_card_keys WHERE login='old2'").get(),"old2 remains after updates");
      finish(db,7);
      assert.deepEqual(actual(db),expected(db));
      put.run(300,1,100,"later","message","agent","agent",card("later"));
      assert.deepEqual(actual(db),expected(db));
    } finally { old.close(); db.close(); rmSync(dir,{ recursive: true,force: true }); }
  });
}

test("a single old card with many candidate keys is staged in bounded batches", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const long = Array.from({ length: 400 },(_,i) => `"login":"id${i}"`).join(",");
    db.prepare("INSERT INTO entries VALUES(1,1,'old','message','agent','agent',?)").run(long);
    installLegacyLoginCards(db);
    let previous = 0, batches = 0;
    while (true) {
      const step = legacyLoginCardsStep(db,7);
      const current = (db.prepare("SELECT COUNT(*) AS n FROM login_card_keys").get() as { n: number }).n;
      assert.ok(step.visited <= 7 && step.tokens <= 7 && current-previous <= 7);
      previous = current; batches++;
      if (step.ready) break;
      assert.ok(batches < 1000);
    }
    assert.ok(batches > 1);
    assert.deepEqual(actual(db),expected(db));
    assert.equal(previous,400);
  } finally { db.close(); }
});

test("changing a partially scanned card keeps the replacement's keys", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const long = Array.from({ length: 40 },(_,i) => `"login":"id${i}"`).join(",");
    db.prepare("INSERT INTO entries VALUES(1,1,'old','message','agent','agent',?)").run(long);
    installLegacyLoginCards(db);
    assert.equal(legacyLoginCardsStep(db,3).ready,false);
    db.prepare("UPDATE entries SET card=? WHERE thread=1 AND n=1").run(card("replacement"));
    finish(db,3);
    assert.deepEqual(actual(db),expected(db));
    assert.deepEqual(actual(db),[{ login:"replacement",thread:"1",n:"1" }]);
  } finally { db.close(); }
});

test("a failed batch rolls back its cursor and candidates together", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    db.prepare("INSERT INTO entries VALUES(1,1,'old','message','agent','agent',?)")
      .run('broken "login":"first" and "login":"fail"');
    installLegacyLoginCards(db);
    const before = db.prepare("SELECT * FROM login_card_meta").get();
    db.exec("CREATE TRIGGER fail_candidate BEFORE INSERT ON login_card_keys WHEN NEW.login='fail' BEGIN SELECT RAISE(ABORT,'injected'); END");
    assert.throws(() => legacyLoginCardsStep(db,7),/injected/);
    assert.deepEqual(db.prepare("SELECT * FROM login_card_meta").get(),before);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM login_card_keys").get() as { n: number }).n,0);
    db.exec("DROP TRIGGER fail_candidate");
    finish(db,7);
    assert.deepEqual(actual(db),expected(db));
  } finally { db.close(); }
});

test("preparation keeps SQLite's integer order beyond JavaScript's exact integers", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put=db.prepare("INSERT INTO entries VALUES(1,?,NULL,'message','agent','agent',?)");
    put.run(9007199254740993n,card("one")); put.run(9007199254740995n,card("two"));
    installLegacyLoginCards(db); finish(db,1);
    assert.deepEqual(actual(db),expected(db));
  } finally { db.close(); }
});

test("an empty store is ready without scanning entries and follows later cards", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    installLegacyLoginCards(db);
    assert.deepEqual(legacyLoginCardsStep(db,4),{ ready:true,visited:0,tokens:0 });
    db.prepare("INSERT INTO entries VALUES(1,1,NULL,'message','agent','agent',?)").run(card("later"));
    assert.deepEqual(actual(db),[{ login:"later",thread:"1",n:"1" }]);
  } finally { db.close(); }
});

test("preparation follows SQLite's match for NUL and non-text card values", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put=db.prepare("INSERT INTO entries VALUES(1,?,NULL,'message','agent','agent',?)");
    put.run(1,'"login":"first"\0"login":"hidden"');
    put.run(2,Buffer.from('"login":"blob"'));
    put.run(3,12345);
    const old=db.prepare("SELECT n FROM entries WHERE card LIKE ? ORDER BY n");
    const answers=new Map(["first","hidden","blob"].map(login => [login,old.all(`%\"login\":\"${login}\"%`).map(r=>r.n)]));
    installLegacyLoginCards(db); finish(db,2);
    const indexed=db.prepare("SELECT n FROM login_card_keys WHERE login=? ORDER BY n");
    for (const [login,rows] of answers) assert.deepEqual(indexed.all(login).map(r=>r.n),rows);
  } finally { db.close(); }
});

test("a store without the old card index scans only bounded entry ranges", () => {
  const db=new DatabaseSync(":memory:");
  try {
    db.exec(`${schema} DROP INDEX entries_login_cards;`);
    const put=db.prepare("INSERT INTO entries VALUES(?,?,NULL,'message','agent','agent',?)");
    for (let n=1;n<=400;n++) { put.run(1,n,n%10===0 ? card(`a${n}`) : null); put.run(2,n,n%10===0 ? card(`b${n}`) : null); }
    installLegacyLoginCards(db);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_login_cards'").get(),undefined);
    let visited=0,queries=0;
    db.function("visit_old_entry", () => { visited++; return 1; });
    const counted=new Proxy(db,{ get(target,property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM entries WHERE 1")) {
          queries++;
          sql=sql.replace("FROM entries WHERE 1","FROM entries WHERE visit_old_entry() AND 1");
        }
        return target.prepare(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    let step;
    do {
      visited=0;
      step=legacyLoginCardsStep(counted,8);
      assert.ok(visited<=8,`one batch visited ${visited} entries`);
    } while (!step.ready);
    assert.ok(queries>8);
    assert.deepEqual(actual(db),expected(db));
  } finally { db.close(); }
});

test("a store with the native card index prepares without walking ordinary messages", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put = db.prepare("INSERT INTO entries VALUES(?,?,NULL,'message','agent','agent',?)");
    for (let n=1;n<=400;n++) {
      put.run(1,n,n%100===0 ? card(`a${n}`) : null);
      put.run(2,n,n%100===0 ? card(`b${n}`) : null);
    }
    installLegacyLoginCards(db);
    let visited=0,queries=0;
    db.function("visit_native_card", () => { visited++; return 1; });
    const counted=new Proxy(db,{ get(target,property) {
      if (property === "prepare") return (sql: string) => {
        const source = `FROM entries INDEXED BY entries_login_cards WHERE card LIKE '%"login"%'`;
        if (sql.includes(source)) { queries++; sql=sql.replace(source,`${source} AND visit_native_card()`); }
        return target.prepare(sql);
      };
      const value=Reflect.get(target,property,target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    let step, total=0;
    do {
      visited=0;
      step=legacyLoginCardsStep(counted,3);
      assert.ok(visited<=3,`one batch visited ${visited} cards`);
      total+=visited;
    } while (!step.ready);
    assert.ok(queries>0);
    assert.equal(total,8);
    assert.deepEqual(actual(db),expected(db));
  } finally { db.close(); }
});

test("preparation remains correct if the native card index changes between batches", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put=db.prepare("INSERT INTO entries VALUES(1,?,NULL,'message','agent','agent',?)");
    for (let n=1;n<=12;n++) put.run(n,n%2===0 ? card(`id${n}`) : null);
    installLegacyLoginCards(db);
    assert.equal(legacyLoginCardsStep(db,2).ready,false);
    db.exec("DROP INDEX entries_login_cards");
    assert.equal(legacyLoginCardsStep(db,2).ready,false);
    db.exec(`CREATE INDEX entries_login_cards ON entries(thread,n) WHERE card LIKE '%"login"%'`);
    finish(db,2);
    assert.deepEqual(actual(db),expected(db));
  } finally { db.close(); }
});
