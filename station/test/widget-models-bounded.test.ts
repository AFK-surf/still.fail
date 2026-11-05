import assert from "node:assert/strict";
import { test } from "node:test";
import { MERGED } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

test("a widget model does not traverse other messages to find its attachment", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "widget-session", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "widget-session", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "EMBER", "widget-thread", null, null).id;
    store.joinThread(thread, "widget-session", "ember");
    const path = "/w/target.html";
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,at,attachments)
      VALUES(?,?,'message','agent','widget-session','words',?,?)`);
    put.run(thread, 1, 1, JSON.stringify([{ name: "target.html", path, size: 1 }]));
    const add = (from: number, to: number) => {
      db.exec("BEGIN");
      for (let n = from; n <= to; n++) put.run(thread, n, n, JSON.stringify([{ name: `other-${n}.html`, path: `/other/${n}`, size: 1 }]));
      db.exec("COMMIT");
    };
    add(2, 41);
    store.putWidgetState("widget-session", path, "{}", "selected");
    let visits = 0;
    db.function("visited_widget_message_kind", (kind) => { visits++; return kind; });
    db.exec("DROP VIEW merged");
    db.exec(MERGED.replace("WHERE m.kind = 'message'", "WHERE visited_widget_message_kind(m.kind) = 'message'"));
    const read = () => store.untoldWidgetModels("widget-session");
    assert.deepEqual(read(), [{ path, name: "target.html", thread: ["EMBER", "widget-thread"], model: "selected" }]);
    const before = visits;
    assert.ok(before > 0, "the attachment lookup was observed");
    add(42, 401);
    visits = 0;
    assert.deepEqual(read(), [{ path, name: "target.html", thread: ["EMBER", "widget-thread"], model: "selected" }]);
    assert.equal(visits, before, `widget message candidates grew from ${before} to ${visits}`);
  } finally { store.close(); }
});
