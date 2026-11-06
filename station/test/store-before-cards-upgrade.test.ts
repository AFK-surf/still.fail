import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

test("a version 12 store from before cards can open and add its card column", () => {
  const dir = mkdtempSync(join(tmpdir(), "stillfail-before-cards-"));
  try {
    const path = join(dir, "stillfail.db");
    const old = new DatabaseSync(path);
    old.exec(readFileSync(new URL("./fixtures/old-store-before-cards.sql", import.meta.url), "utf8"));
    // The Rust store added these columns, index and view after its base schema when it opened.
    old.exec(`ALTER TABLE turns ADD COLUMN profile TEXT;
      ALTER TABLE turns ADD COLUMN person TEXT;
      ALTER TABLE turns ADD COLUMN thread INTEGER;
      CREATE INDEX entries_options ON entries(thread,n) WHERE options IS NOT NULL;
      CREATE VIEW merged AS SELECT m.thread,m.n,m.ts,m.author_kind,m.author,
        CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
        CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
        CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
        m.declared,m.client,m.at AS created_at,e.at AS edited_at FROM entries m
        LEFT JOIN entries e ON e.thread=m.thread AND e.n=(SELECT MAX(x.n) FROM entries x WHERE x.thread=m.thread AND x.target=m.n)
        WHERE m.kind='message';`);
    old.exec(`INSERT INTO threads(id,surface,channel,thread_ts,created_at) VALUES (1,'ember','CHAT','old',1);
      INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (1,1,'message','person','local','hello',1);`);
    old.exec("PRAGMA user_version = 12");
    old.close();
    const store = Store.open(path);
    try {
      assert.ok(store.db.prepare("SELECT 1 FROM pragma_table_info('entries') WHERE name = 'card'").get());
      assert.deepEqual({ ...store.db.prepare("SELECT text,card FROM entries WHERE thread=1 AND n=1").get() }, { text: "hello", card: null });
      store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,card,at)
        VALUES(1,2,'message','agent','agent',?,2)`).run(JSON.stringify({ type: "login" }));
      assert.equal((store.db.prepare(`SELECT n FROM entries INDEXED BY entries_login_cards
        WHERE thread=1 AND card LIKE '%"login"%'`).get() as { n: number }).n, 2);
    } finally { store.close(); }
    const reopened = Store.open(path);
    try {
      assert.equal((reopened.db.prepare("SELECT text FROM merged WHERE thread=1 AND n=1").get() as { text: string }).text, "hello");
      assert.ok(reopened.db.prepare(`SELECT 1 FROM entries INDEXED BY entries_login_cards WHERE thread=1 AND card LIKE '%"login"%'`).get());
    } finally { reopened.close(); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
