import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { CARD_POST_LATEST } from "../src/store/card-post-index.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

const card = JSON.stringify({ type: "options", options: [{ label: "yes" }], vault: { request: "request-1" } });
const state = readStore.deliveryCardState;

function put(store: Store, thread: number, n: number, authorKind: string, value: string | null = null) {
  store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at)
    VALUES(?,?,'message',?,?,?,'message',?,?)`).run(thread, n, `${n}.1`, authorKind, authorKind === "person" ? "person" : "worker", value, n);
}

test("delivery card state preserves the ended card, pending card, and old options", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "state", null, null).id;
    const read = readStore.makeStore(store.db, "");
    put(store, thread, 1, "agent", card);
    put(store, thread, 2, "person");
    put(store, thread, 3, "agent", JSON.stringify({ type: "text" }));
    assert.deepEqual(state(read, thread, 2), {
      ended: { author: "worker", ts: "1.1" }, card: JSON.parse(card), current: { ts: "3.1" },
    });
    put(store, thread, 4, "person");
    assert.equal(state(read, thread, 2)?.current, null);
    assert.equal(state(read, thread, 4)?.ended.ts, "3.1");
    assert.equal(state(read, thread, 1), null);
    store.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,1,'worker',5)").run(thread);
    assert.equal(state(read, thread, 2), null);

    const old = store.openThread("ember", "CHAT", "options", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,options,at)
      VALUES(?,1,'message','old.1','agent','worker','old',?,1)`).run(old, JSON.stringify([{ label: "old" }]));
    put(store, old, 2, "person");
    const expected = store.cardEndedByMessage(old, 2)!;
    assert.deepEqual(state(read, old, 2), {
      ended: { author: expected[0].author, ts: expected[0].ts }, card: expected[1], current: null,
    });
    const invalid = store.openThread("ember", "CHAT", "invalid", null, null).id;
    put(store, invalid, 1, "agent", "{");
    put(store, invalid, 2, "person");
    assert.equal(state(read, invalid, 2), null);
  } finally { store.close(); }
});

test("delivery card state does not merge old message edits", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "old-edits", null, null).id;
    put(store, thread, 1, "agent", card);
    put(store, thread, 2, "person");
    put(store, thread, 3, "agent", card);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','worker','edit',4)");
    for (let n = 4; n <= 153; n++) edit.run(thread, n, n + 1000);
    edit.run(thread, 9007199254740993n, 99);
    installLegacyEdits(db);
    addClientColumn(db);
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        assert.doesNotMatch(sql, /\bmerged\b/i, "delivery needs the post's author and timestamp, not merged text");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(state(readStore.makeStore(observed, ""), thread, 2), {
      ended: { author: "worker", ts: "1.1" }, card: JSON.parse(card), current: { ts: "3.1" },
    });
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("delivery card state keeps the old empty value for missing timestamps", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "no-timestamps", null, null).id;
    const post = store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at)
      VALUES(?,?,'message',NULL,'agent','worker','ask',?,?)`);
    post.run(thread, 1, card, 1);
    put(store, thread, 2, "person");
    post.run(thread, 3, card, 3);
    assert.equal(store.cardEndedByMessage(thread, 2)?.[0].ts, "");
    assert.equal(store.pendingCard(thread)?.[0].ts, "");
    const found = state(readStore.makeStore(store.db, ""), thread, 2);
    assert.equal(found?.ended.ts, "");
    assert.equal(found?.current?.ts, "");
  } finally { store.close(); }
});

test("the ended and current card states use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "actor-card-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "snapshot", null, null).id;
    put(store, thread, 1, "agent", card);
    put(store, thread, 2, "person");
    put(store, thread, 3, "agent", card);
    let changed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === CARD_POST_LATEST && !changed) {
          changed = true;
          writer.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
            VALUES(?,4,'message','4.1','person','person','answer',4)`).run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.equal(state(read, thread, 2)?.current?.ts, "3.1");
    assert.ok(changed);
    assert.equal(state(read, thread, 2)?.current, null);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("delivery formats card state through its reader", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "worker", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "worker", createdAt: 1, lastActiveAt: 1 });
    const thread = rig.store.openThread("ember", "CHAT", "actor", null, null).id;
    rig.store.joinThread(thread, "worker", "ember");
    put(rig.store, thread, 1, "agent", card);
    put(rig.store, thread, 2, "person");
    put(rig.store, thread, 3, "agent", card);
    rig.store.db.prepare("INSERT INTO deliveries(thread,n,session) VALUES(?,2,'worker')").run(thread);
    const asked: number[] = [];
    (rig.hub as any).deliveryCardState = async (id: number, n: number, signal: AbortSignal) => {
      assert.equal(id, thread);
      assert.equal(signal.aborted, false);
      asked.push(n);
      return { ended: { author: "worker", ts: "1.1" }, card: JSON.parse(card), current: { ts: "3.1" } };
    };
    rig.store.cardEndedByMessage = () => { throw new Error("station ended card lookup used"); };
    rig.store.pendingCard = () => { throw new Error("station pending card lookup used"); };
    const actor = rig.hub.actor(rig.session("worker"));
    const [text] = await (actor as any).format(rig.store.pendingMessages("worker")) as [string, unknown];
    assert.deepEqual(asked, [2]);
    assert.match(text, /Your card is no longer pending/);
    assert.match(text, /message ts 3\.1/);
    assert.match(text, /secret_reask/);
  } finally { await rig.close(); }
});

test("delivery formats a real reader's card state", async () => {
  const rig = new Rig();
  await rig.hub.shutdown();
  rig.store.close();
  rig.store = Store.open(join(rig.dir, "stillfail.db"));
  rig.hub = rig.newHub({ chats: () => undefined });
  const readers = new Readers(rig.dir, 1, undefined, 1);
  try {
    rig.store.insertSession({ key: "worker", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "worker", createdAt: 1, lastActiveAt: 1 });
    const thread = rig.store.openThread("ember", "CHAT", "reader", null, null).id;
    rig.store.joinThread(thread, "worker", "ember");
    put(rig.store, thread, 1, "agent", card);
    put(rig.store, thread, 2, "person");
    put(rig.store, thread, 3, "agent", card);
    rig.store.db.prepare("INSERT INTO deliveries(thread,n,session) VALUES(?,2,'worker')").run(thread);
    rig.hub.deliveryCardState = async (id, n, signal) => JSON.parse(await readers.read("deliveryCardState", { thread: id, n }, "en", { signal }));
    rig.store.cardEndedByMessage = () => { throw new Error("station ended card lookup used"); };
    rig.store.pendingCard = () => { throw new Error("station pending card lookup used"); };
    const actor = rig.hub.actor(rig.session("worker"));
    const [text] = await (actor as any).format(rig.store.pendingMessages("worker")) as [string, unknown];
    assert.match(text, /Your card is no longer pending/);
    assert.match(text, /message ts 3\.1/);
    assert.match(text, /secret_reask/);
  } finally { readers.close(); await rig.close(); }
});

test("delivery readers share old card preparation after handover when one cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "actor-card-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    const short = store.openThread("ember", "CHAT", "empty", null, null).id;
    put(store, thread, 1, "agent", card);
    put(store, thread, 2, "person");
    put(store, short, 1, "person");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,card,at) VALUES(?,?,'edit',1,'agent','worker','edit',?,?)");
    for (let n = 3; n <= 153; n++) edit.run(thread, n, card, n);
    db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
    const controller = new AbortController();
    const abandoned = readers.read("deliveryCardState", { thread, n: 2 }, "en", { signal: controller.signal });
    const kept = readers.read("deliveryCardState", { thread, n: 2 }, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    assert.equal(JSON.parse(await readers.read("deliveryCardState", { thread: short, n: 1 }, "en")), null);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept), {
      ended: { author: "worker", ts: "1.1" }, card: JSON.parse(card), current: null,
    });
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
