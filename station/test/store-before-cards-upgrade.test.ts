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
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
