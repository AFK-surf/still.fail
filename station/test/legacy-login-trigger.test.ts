import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LEGACY_LOGIN_CARD_SCHEMA } from "../src/store/legacy-login-cards.ts";
import { LOGIN_CARD_TOKENS } from "./login-card-token-query.ts";

const schema = `CREATE TABLE entries(thread INTEGER NOT NULL,n INTEGER NOT NULL,ts TEXT,kind TEXT NOT NULL,
  author_kind TEXT NOT NULL,author TEXT NOT NULL,card TEXT,PRIMARY KEY(thread,n));
  CREATE UNIQUE INDEX entries_ts ON entries(thread,ts) WHERE ts IS NOT NULL;`;
const card = (id: string) => JSON.stringify({ type: "login", login: id });
const nested = (when: string, by: string) => `CREATE TRIGGER nested_${when.toLowerCase()}_${by} ${when} INSERT ON entries
  WHEN NEW.author='outer' BEGIN
  INSERT OR REPLACE INTO entries(rowid,thread,n,ts,kind,author_kind,author,card)
  VALUES(${by === "rowid" ? "NEW.rowid" : "900"},${by === "rowid" ? "2" : "NEW.thread"},
    ${by === "number" ? "NEW.n" : "99"},${by === "timestamp" ? "NEW.ts" : "'inner'"},
    'message','agent','inner','{"type":"login","login":"inner"}'); END;`;

// Compare with the original LIKE semantics after every write, including malformed and multiple literal fields.
function check(db: DatabaseSync): void {
  const keyRows = db.prepare("SELECT login,thread,n FROM login_card_keys ORDER BY login,thread,n").all().map((r) => ({ ...r }));
  const expected: { login: unknown; thread: unknown; n: unknown }[] = [];
  const tokens = db.prepare(LOGIN_CARD_TOKENS);
  for (const e of db.prepare("SELECT thread,n,card FROM entries WHERE kind='message' AND author_kind='agent'").all()) {
    for (const t of tokens.all(e.card)) {
      if (typeof t.login === "string" && /^[0-9a-z]{1,40}$/.test(t.login)) expected.push({ login: t.login, thread: e.thread, n: e.n });
    }
  }
  expected.sort((a, b) => String(a.login).localeCompare(String(b.login)) || Number(a.thread) - Number(b.thread) || Number(a.n) - Number(b.n));
  assert.deepEqual(keyRows, expected);
}

for (const recursive of [false, true]) {
  for (const when of ["BEFORE", "AFTER"]) {
    for (const by of ["number", "timestamp", "rowid"]) {
      for (const installFirst of [false, true]) {
        test(`login candidates follow ${when.toLowerCase()} nested ${by} replacement (recursive ${recursive}, installed first ${installFirst})`, () => {
          const db = new DatabaseSync(":memory:");
          try {
            db.exec(`${schema} PRAGMA recursive_triggers=${recursive ? 1 : 0};`);
            if (installFirst) db.exec(LEGACY_LOGIN_CARD_SCHEMA);
            db.exec(nested(when, by));
            if (!installFirst) db.exec(LEGACY_LOGIN_CARD_SCHEMA);
            const put = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,ts,kind,author_kind,author,card)
              VALUES(?,?,?,?,?,?,?,?)`);
            put.run(1,1,1,"old","message","agent","old",card("old")); check(db);
            put.run(2,1,2,"other","message","agent","other",'broken "login":"one" and "login":"two"'); check(db);
            put.run(3,1,3,"outer","message","agent","outer",card("outer")); check(db);
            db.exec("UPDATE OR IGNORE entries SET ts='other' WHERE thread=1 AND n=1"); check(db);
            db.prepare(`INSERT OR IGNORE INTO entries(thread,n,ts,kind,author_kind,author,card)
              VALUES(1,1,'ignored','message','agent','ignored',?)`).run(card("ignored")); check(db);
            db.exec("UPDATE entries SET card=NULL WHERE thread=1 AND n=2"); check(db);
            db.exec("DELETE FROM entries WHERE thread=1 AND n=1"); check(db);
          } finally { db.close(); }
        });
      }
    }
  }
}

for (const by of ["timestamp", "rowid"]) {
  test(`repeated ${by} replacements do not accumulate or scan unrelated login candidates`, () => {
    for (const count of [40, 400]) {
      const db = new DatabaseSync(":memory:");
      try {
        db.exec(schema);
        let visited = 0;
        db.function("visit_candidate", (_key) => { visited++; return 1; });
        const instrumented = LEGACY_LOGIN_CARD_SCHEMA.replaceAll("WHERE ((login_card_keys.thread=", "WHERE visit_candidate(login_card_keys.login)=1 AND ((login_card_keys.thread=");
        assert.notEqual(instrumented, LEGACY_LOGIN_CARD_SCHEMA);
        db.exec(instrumented);
        const put = db.prepare(`INSERT OR REPLACE INTO entries(rowid,thread,n,ts,kind,author_kind,author,card)
          VALUES(?,1,?,?,'message','agent','agent',?)`);
        let max = 0;
        for (let i = 1; i <= count; i++) {
          visited = 0;
          put.run(by === "rowid" ? 1 : i, i, by === "timestamp" ? "same" : `ts${i}`, card(`old${i}`));
          max = Math.max(max, visited);
        }
        check(db);
        assert.equal((db.prepare("SELECT COUNT(*) AS n FROM login_card_keys").get() as { n: number }).n, 1);
        assert.ok(max <= 2, `a ${by} replacement visited ${max} candidates after ${count} writes`);
      } finally { db.close(); }
    }
  });
}

test("appending and updating unrelated entries does not traverse existing candidates", () => {
  for (const count of [40,400]) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(schema);
      let visited = 0;
      db.function("visit_candidate", (_key) => { visited++; return 1; });
      const instrumented = LEGACY_LOGIN_CARD_SCHEMA.replaceAll("WHERE ((login_card_keys.thread=", "WHERE visit_candidate(login_card_keys.login)=1 AND ((login_card_keys.thread=");
      assert.notEqual(instrumented,LEGACY_LOGIN_CARD_SCHEMA);
      db.exec(instrumented);
      const put = db.prepare(`INSERT INTO entries(thread,n,ts,kind,author_kind,author,card)
        VALUES(1,?,?,'message','agent','agent',?)`);
      for (let i=1; i<=count; i++) put.run(i,`old${i}`,card(`old${i}`));
      visited=0;
      put.run(count+1,"new",card("new"));
      assert.ok(visited<=2,`append visited ${visited} candidates with ${count} unrelated cards`);
      visited=0;
      db.prepare("UPDATE entries SET card=? WHERE thread=1 AND n=?").run(card("updated"),count+1);
      assert.ok(visited<=2,`update visited ${visited} candidates with ${count} unrelated cards`);
      check(db);
    } finally { db.close(); }
  }
});

test("ordinary writes seek candidate conflicts without scanning unrelated login cards", () => {
  for (const count of [40,400]) {
    const db=new DatabaseSync(":memory:");
    try {
      db.exec(schema);
      let visited=0;
      db.function("visit_guard", (_login) => { visited++; return 1; });
      const candidate = (prefix: string) => `(login_card_keys.thread=${prefix}.thread AND login_card_keys.n=${prefix}.n)
  OR login_card_keys.entry_rowid=${prefix}.rowid OR (${prefix}.ts IS NOT NULL AND login_card_keys.thread=${prefix}.thread AND login_card_keys.ts=${prefix}.ts)`;
      let traced=LEGACY_LOGIN_CARD_SCHEMA;
      for (const prefix of ["NEW","OLD"]) {
        const sql=`EXISTS(SELECT 1 FROM login_card_keys WHERE ${candidate(prefix)})`;
        traced=traced.replaceAll(sql,`EXISTS(SELECT 1 FROM login_card_keys WHERE visit_guard(login_card_keys.login) AND (${candidate(prefix)}))`);
      }
      assert.notEqual(traced,LEGACY_LOGIN_CARD_SCHEMA);
      db.exec(traced);
      const put=db.prepare(`INSERT INTO entries(thread,n,ts,kind,author_kind,author,card)
        VALUES(1,?,?,'message','agent','agent',?)`);
      for (let n=1;n<=count;n++) put.run(n,`old${n}`,card(`old${n}`));
      visited=0;
      put.run(count+1,"new",null);
      assert.equal(visited,0,`a non-card append visited ${visited} candidate keys with ${count} other cards`);
      visited=0;
      db.prepare("UPDATE entries SET ts=? WHERE thread=1 AND n=?").run("moved",count+1);
      assert.equal(visited,0,`an unrelated update visited ${visited} candidate keys with ${count} other cards`);
      visited=0;
      db.prepare("DELETE FROM entries WHERE thread=1 AND n=?").run(count+1);
      assert.equal(visited,0,`an unrelated deletion visited ${visited} candidate keys with ${count} other cards`);
      check(db);
    } finally { db.close(); }
  }
});
