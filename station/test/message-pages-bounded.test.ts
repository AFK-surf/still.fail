import assert from "node:assert/strict";
import { test } from "node:test";
import { makeStore, messagesBefore as readMessagesBefore } from "../src/read/store.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const side of ["station", "reader"] as const) {
  test(`${side} finds a page of messages without traversing their later edits`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "EMBER", "message-page", null, null).id;
      const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,?,?,?, 'person','viewer',?,?)`);
      for (let n = 1; n <= 3; n++) put.run(thread, n, "message", null, `message-${n}`, n);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) put.run(thread, n, "edit", 3, `edit-${n}`, n);
        db.exec("COMMIT");
      };
      add(4, 43);
      let visits = 0;
      db.function("visited_page_kind", (kind) => { visits++; return kind; });
      db.exec("DROP VIEW merged");
      db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_page_kind(m.kind) = 'message'"));
      const read = () => side === "station" ? store.messagesBefore(thread, null, 3)
        : readMessagesBefore(makeStore(db, "/no-station-config"), thread, null, 3);
      assert.deepEqual(read().map((m) => [m.n, m.text]), [[1, "message-1"], [2, "message-2"], [3, "edit-43"]]);
      const before = visits;
      assert.ok(before > 0, "the page lookup was observed");
      add(44, 403);
      visits = 0;
      assert.deepEqual(read().map((m) => [m.n, m.text]), [[1, "message-1"], [2, "message-2"], [3, "edit-403"]]);
      assert.equal(visits, before, `page candidates grew from ${before} to ${visits}`);
    } finally { store.close(); }
  });
}
