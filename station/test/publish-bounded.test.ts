import assert from "node:assert/strict";
import { test } from "node:test";
import { snapshotOf } from "../src/publish/snapshot.ts";
import { publishDraft } from "../src/read/publish.ts";
import { makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("publishing an earlier preview does not read later entries for the preview's views", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "agent", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "token", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "CHAT", "chat", "The chat", null).id;
    store.joinThread(thread, "agent", "ember");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','agent','agent',?,?)");
    db.exec("BEGIN");
    put.run(thread, 1, "before", 1);
    for (let n = 2; n <= 5_001; n++) put.run(thread, n, "later", n);
    // The selected message can still be edited after the preview was taken.
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES (?,5002,'edit',1,'agent','agent','edited after preview',5002)").run(thread);
    db.exec("COMMIT");

    let visited = 0;
    db.function("visit_published_view", (_n) => { visited++; return 1; });
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n")
            ? sql.replace("AND n <= ?", "AND visit_published_view(n) IS NOT NULL AND n <= ?")
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const read = makeStore(instrumented, "/no-station-config");
    const args = { thread, upto: 1, names: {}, viewer: "" };
    const preview = publishDraft(read, args, "en");
    assert.equal(visited, 5_002, "the preview still obtains the entries it needs to draw");
    assert.equal(preview.entries[0]?.text, "edited after preview");

    visited = 0;
    const published = publishDraft(read, { ...args, includeViews: false }, "en");
    assert.equal(published.entries[0]?.text, "edited after preview");
    assert.deepEqual(snapshotOf(published, "Station", "Alice", 1, null), snapshotOf(preview, "Station", "Alice", 1, null));
    assert.equal(visited, 0, `publishing read ${visited} entries solely for unused preview views`);
  } finally { store.close(); }
});
