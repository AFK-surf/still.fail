import assert from "node:assert/strict";
import { test } from "node:test";
import { MANUAL, Store } from "../src/store/store.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

test("recording a duplicate needs only its original message key", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,1,'message','1.1','person','person','original',1)").run(thread);
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,2,'edit',1,'person','person','edited',2)").run(thread);
    (store as any).db = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM merged WHERE thread = ? AND ts = ?") throw new Error("duplicate lookup merged edits");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(store.insertMessage({ thread, ts: "1.1", authorKind: "person", author: "person", text: "redelivered" }), [1, false]);
    (store as any).db = db;
    assert.equal(store.messageAt(thread, "1.1")?.text, "edited");
  } finally { (store as any).db = db; store.close(); }
});

test("a non-message entry with the same timestamp is not a duplicate message", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    store.db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,at) VALUES(?,1,'edit','2.1','person','person',1)").run(thread);
    assert.throws(() => store.insertMessage({ thread, ts: "2.1", authorKind: "person", author: "person", text: "new" }), /UNIQUE/);
  } finally { store.close(); }
});

test("the duplicate lookup seeks the existing timestamp index", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "1.1", null, null).id;
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,1,'message','1.1','person','person','original',1)").run(thread);
    const prepared: string[] = [];
    (store as any).db = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => { prepared.push(sql); return target.prepare(sql); };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(store.messageNumberAt(thread, "1.1"), 1);
    const sql = prepared.at(-1);
    assert.ok(sql);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(thread, "1.1").map((row) => String(row.detail)).join("\n");
    assert.match(plan, /SEARCH entries USING INDEX entries_ts/);
  } finally { (store as any).db = db; store.close(); }
});

test("a redelivered message does not fetch its files or merge its edits again", async () => {
  const rig = new Rig();
  try {
    rig.chat.shared.set("F1", "content");
    const m = say("<@UBOT> hello", { files: [{ id: "F1", name: "note.txt", size: 7, url: "https://files.slack.com/F1" }] });
    await rig.accept(m);
    await settle();
    rig.store.messageAt = () => { throw new Error("redelivery lookup merged edits"); };
    await rig.accept(m);
    await settle();
    assert.deepEqual(rig.chat.downloads, ["F1"]);
    assert.equal(rig.claude.last().prompts.length, 1);
  } finally { await rig.close(); }
});

test("a manually archived thread only warns for an unseen message", async () => {
  const rig = new Rig();
  try {
    const m = say("<@UBOT> hello");
    await rig.accept(m);
    await settle();
    const thread = rig.thread(m.channel, m.threadTs);
    rig.store.setThreadHidden(thread.id, true, MANUAL);
    assert.equal(rig.store.manuallyArchived(thread.id), true);
    rig.store.messageAt = () => { throw new Error("archive lookup merged edits"); };
    const posts = rig.chat.posts.length;
    await rig.accept(m);
    assert.equal(rig.chat.posts.length, posts);
    await rig.accept({ ...m, ts: "999999.1" });
    assert.equal(rig.chat.posts.length, posts + 1);
  } finally { await rig.close(); }
});
