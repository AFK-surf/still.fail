import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CARD_POST_LATEST } from "../src/store/card-post-index.ts";
import { Store } from "../src/store/store.ts";

test("a pending card header keeps the existing card and replacement rules", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "card-header", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,text,card,options,at) VALUES(?,?,?,?,?,?,?,?,?,?,?)");
    const add = (n: number, kind: string, ts: string | null, author: string, card: string | null, options: string | null, target: number | null = null) =>
      put.run(thread, n, kind, target, ts, author, "author", "words", card, options, n);
    const check = (expected: unknown) => {
      const full = store.pendingCard(thread);
      const header = store.pendingCardHeader(thread);
      assert.deepEqual(header, expected);
      assert.deepEqual(header, full === null ? null : [{ n: full[0].n, ts: full[0].ts }, full[1]]);
    };
    check(null);
    add(1, "message", "1.1", "agent", JSON.stringify({ type: "text" }), null);
    check([{ n: 1, ts: "1.1" }, { type: "text" }]);
    add(2, "edit", null, "agent", JSON.stringify({ type: "options" }), null, 1);
    check([{ n: 1, ts: "1.1" }, { type: "text" }]);
    add(3, "message", "3.3", "agent", null, JSON.stringify([{ label: "yes" }]));
    check([{ n: 3, ts: "3.3" }, { type: "options", options: [{ label: "yes" }] }]);
    add(4, "message", "4.4", "person", null, null);
    check(null);
    add(5, "message", null, "agent", JSON.stringify({ type: "text" }), null);
    check([{ n: 5, ts: "" }, { type: "text" }]);
    add(6, "message", "6.6", "agent", "invalid", "invalid");
    check(null);
    db.prepare("UPDATE entries SET options=? WHERE thread=? AND n=6").run(JSON.stringify([{ label: "old" }]), thread);
    check([{ n: 6, ts: "6.6" }, { type: "options", options: [{ label: "old" }] }]);
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,6,'person',7)").run(thread);
    check(null);
    add(7, "message", "7.7", "agent", "null", null);
    check([{ n: 7, ts: "7.7" }, null]);
  } finally { store.close(); }
});

test("the bounded card header and its pending checks use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-header-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), db = store.db, writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "header-snapshot", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','ask','agent','worker','ask',?,1)")
      .run(thread, JSON.stringify({ type: "text" }));
    let changed = false;
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, { get(target, key) {
      if (key === "prepare") return (sql: string) => {
        if (sql === CARD_POST_LATEST && !changed) {
          changed = true;
          writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','answer','person','p','yes',2)").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    } }) });
    assert.deepEqual(store.pendingCardHeaderIfReady(thread), [{ n: 1, ts: "ask" }, { type: "text" }]);
    assert.equal(changed, true);
    assert.equal(store.pendingCardHeaderIfReady(thread), null);
  } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
