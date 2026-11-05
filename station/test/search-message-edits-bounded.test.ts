import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { threadDocs } from "../src/search/sources.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("search reads a chat's messages without traversing later edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "search-edits", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
      VALUES(?,?,?,?, 'person','viewer',?,?)`);
    put.run(thread, 1, "message", null, "original", 1);
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) put.run(thread, n, "edit", 1, `edited-${n}`, n);
      db.exec("COMMIT");
    };
    add(2, 41);
    let visits = 0;
    db.function("visited_search_message_kind", (kind) => { visits++; return kind; });
    db.exec("DROP VIEW merged");
    db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_search_message_kind(m.kind) = 'message'"));
    const reader = makeStore(db, "/no-station-config");
    const read = () => threadDocs(reader, thread).filter((doc) => doc.kind === "message").map((doc) => doc.body);
    assert.deepEqual(read(), ["edited-41"]);
    const before = visits;
    assert.ok(before > 0, "the message lookup was observed");
    add(42, 401);
    visits = 0;
    assert.deepEqual(read(), ["edited-401"]);
    assert.equal(visits, before, `search candidates grew from ${before} to ${visits}`);
  } finally { store.close(); }
});
