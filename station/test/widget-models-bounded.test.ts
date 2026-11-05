import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";
import { WIDGET_SOURCE } from "../src/store/widget-sources.ts";

test("widget models name the latest matching message as edits and membership change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    for (const key of ["widget-session", "other-session"]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
        token: key, createdAt: 1, lastActiveAt: 1 });
    }
    const one = store.openThread("ember", "EMBER", "one", null, null).id;
    const two = store.openThread("ember", "EMBER", "two", null, null).id;
    const other = store.openThread("ember", "EMBER", "other", null, null).id;
    store.joinThread(one, "widget-session", "ember");
    store.joinThread(two, "widget-session", "ember");
    store.joinThread(other, "other-session", "ember");
    const path = "/w/target.html";
    const attachment = (name: string) => JSON.stringify([{ path, name, size: 1 }]);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,attachments)
      VALUES(?,?,?,?, 'agent','widget-session','words',?,?)`);
    put.run(one, 1, "message", null, 100, attachment("first.html"));
    put.run(two, 1, "message", null, 200, attachment("newer.html"));
    put.run(other, 1, "message", null, 999, attachment("other.html"));
    store.putWidgetState("widget-session", path, "{}", "selected");
    const expect = (name: string, thread: string | null) => assert.deepEqual(store.untoldWidgetModels("widget-session"),
      [{ path, name, thread: thread === null ? null : ["EMBER", thread], model: "selected" }]);
    expect("newer.html", "two");
    put.run(two, 2, "edit", 1, 300, "[]");
    expect("first.html", "one");
    put.run(one, 2, "edit", 1, 400, attachment("edited.html"));
    put.run(two, 3, "message", null, 50, attachment("earlier.html"));
    expect("edited.html", "one");
    db.prepare("DELETE FROM entries WHERE thread=? AND n=2").run(one);
    expect("first.html", "one");
    db.prepare("UPDATE entries SET attachments=? WHERE thread=? AND n=2").run(attachment("revived.html"), two);
    expect("revived.html", "two");
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session=?").run(two, "widget-session");
    expect("first.html", "one");
    db.prepare("DELETE FROM entries WHERE thread=? AND n=1").run(one);
    expect("target.html", null);
  } finally { store.close(); }
});

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
    db.function("visited_widget_source", (name) => { visits++; return name; });
    db.exec(`ALTER TABLE widget_source_rows RENAME TO widget_source_rows_test;
      CREATE VIEW widget_source_rows AS SELECT thread,n,slot,path,at,visited_widget_source(name) AS name FROM widget_source_rows_test;`);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${WIDGET_SOURCE}`).all("widget-session", path) as { detail: string }[];
    assert.ok(plan.some(({ detail }) => detail.includes("widget_source_by_path")), "the path lookup uses its index");
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
