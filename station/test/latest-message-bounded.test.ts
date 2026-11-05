import assert from "node:assert/strict";
import { test } from "node:test";
import { lastMessage as readLastMessage, makeStore } from "../src/read/store.ts";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

for (const side of ["station", "reader"] as const) {
  test(`${side} finds a chat's last message without traversing its later edits`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      const thread = store.openThread("ember", "EMBER", "last-message", null, null).id;
      const insert = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
        VALUES(?,?,?,?, 'person','viewer',?,?)`);
      insert.run(thread, 1, "message", null, "original", 1);
      const add = (from: number, to: number) => {
        db.exec("BEGIN");
        for (let n = from; n <= to; n++) insert.run(thread, n, "edit", 1, `edit-${n}`, n);
        db.exec("COMMIT");
      };
      add(2, 41);
      let visits = 0;
      db.function("visited_message_kind", (kind) => { visits++; return kind; });
      db.exec("DROP VIEW merged");
      db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_message_kind(m.kind) = 'message'"));
      const read = () => side === "station" ? store.lastMessage(thread) : readLastMessage(makeStore(db, "/no-station-config"), thread);
      assert.equal(read()?.text, "edit-41");
      const before = visits;
      assert.ok(before > 0, "the message lookup was observed");
      add(42, 401);
      visits = 0;
      const last = read();
      assert.equal(last?.n, 1);
      assert.equal(last?.text, "edit-401");
      assert.equal(visits, before, `message candidates grew from ${before} to ${visits}`);
    } finally { store.close(); }
  });
}
