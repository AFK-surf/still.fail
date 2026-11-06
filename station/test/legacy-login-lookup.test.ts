import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LEGACY_LOGIN_CARDS } from "../src/store/legacy-login-cards.ts";
import { LOGIN_CARD_TOKENS } from "./login-card-token-query.ts";

test("login-key candidates agree with the old lookup without reading other login cards", () => {
  for (const count of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(`CREATE TABLE entries(thread INTEGER,n INTEGER,kind TEXT,author_kind TEXT,author TEXT,card TEXT,PRIMARY KEY(thread,n));
        CREATE INDEX entries_cards ON entries(thread,n) WHERE card IS NOT NULL;
        CREATE TABLE closed_cards(thread INTEGER,n INTEGER,PRIMARY KEY(thread,n));
        CREATE TABLE login_card_meta(id INTEGER PRIMARY KEY,scanned INTEGER NOT NULL);
        INSERT INTO login_card_meta VALUES(1,1);
        CREATE TABLE login_card_keys(login TEXT,thread INTEGER,n INTEGER,PRIMARY KEY(login,thread,n)) WITHOUT ROWID;`);
      const put = db.prepare("INSERT INTO entries VALUES(1,?,'message','agent','agent',?)");
      for (let n = 1; n <= count; n++) put.run(n, JSON.stringify({ type: "login", login: `old${n}` }));
      put.run(count + 1, '{"LOGIN":"WANTED","nested":{"login":"second"}}');
      put.run(count + 2, 'malformed "login":"wanted" and "login":"other"');
      put.run(count + 3, JSON.stringify({ type: "text", placeholder: '"login":"wanted"' }));
      db.prepare("INSERT INTO closed_cards VALUES(1,?)").run(count + 2);
      const tokens = db.prepare(LOGIN_CARD_TOKENS);
      const add = db.prepare("INSERT OR IGNORE INTO login_card_keys VALUES(?,1,?)");
      for (const entry of db.prepare("SELECT n,card FROM entries").all() as { n: number; card: string }[]) {
        for (const key of tokens.all(entry.card)) add.run(key.login, entry.n);
      }
      const before = db.prepare(`SELECT thread,n,author FROM entries e WHERE kind='message' AND author_kind='agent'
        AND card LIKE '%"login"%' AND card LIKE ?1 AND NOT EXISTS
        (SELECT 1 FROM closed_cards c WHERE c.thread=e.thread AND c.n=e.n) ORDER BY thread,n`);
      let visited = 0;
      db.function("visit_login_row", (_card) => { visited++; return 1; });
      const sql = LEGACY_LOGIN_CARDS.replace("AND k.login=?1", "AND k.login=?1 AND visit_login_row(e.card)=1") + " ORDER BY thread,n";
      const after = db.prepare(sql);
      for (const login of ["wanted", "second", "missing", "old1"]) {
        const pattern = `%"login":"${login}"%`;
        visited = 0;
        assert.deepEqual(after.all(login, pattern).map((r) => ({ ...r })), before.all(pattern).map((r) => ({ ...r })));
        assert.ok(visited <= 2, `${login} visited ${visited} source cards with ${count} unrelated cards`);
      }
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("wanted", '%"login":"wanted"%') as { detail: string }[];
      assert.ok(plan.some((row) => row.detail.includes("SEARCH k USING PRIMARY KEY (login=?)")), JSON.stringify(plan));
    } finally { db.close(); }
  }
});
