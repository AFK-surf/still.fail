import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { cardAt, LAST_MESSAGE_RECENT_EDIT, makeStore, pendingCard } from "../src/read/store.ts";
import { CARD_POST_LATEST } from "../src/store/card-post-index.ts";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

const card = JSON.stringify({ type: "options", options: [{ label: "Pick" }] });

function oldCard(size: number, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `old-card-${size}`, null, null).id;
  const short = store.openThread("ember", "CHAT", `short-${size}`, null, null).id;
  db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','worker','ask',?,1)").run(thread, card);
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','worker','other',?)");
  db.exec("BEGIN");
  for (let n = 2; n <= size + 1; n++) edit.run(thread, n, n + 1000, n);
  db.exec("COMMIT");
  installLegacyEdits(db);
  addClientColumn(db);
  return { store, db, thread, short };
}

test("a card message leaves a long unprepared old edit lookup to bounded preparation", () => {
  for (const size of [80, 800]) {
    const { store, db, thread } = oldCard(size);
    try {
      const read = makeStore(db, "");
      for (const lookup of [() => cardAt(read, thread, 1), () => pendingCard(read, thread)])
        assert.throws(lookup, { status: 503, message: "legacy edit lookup pending" });
      while (!legacyEditStep(db).ready) { /* bounded old lookup preparation */ }
      assert.equal(cardAt(read, thread, 1)?.[0].text, "ask");
      assert.equal(pendingCard(read, thread)?.[0].text, "ask");
    } finally { store.close(); }
  }
});

test("a recent edit makes an old card readable while other edits are prepared", () => {
  const { store, db, thread } = oldCard(150);
  try {
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,152,'edit',1,'agent','worker','recent',152)").run(thread);
    const read = makeStore(db, "");
    assert.equal(cardAt(read, thread, 1)?.[0].text, "recent");
    assert.equal(pendingCard(read, thread)?.[0].text, "recent");
    assert.deepEqual(pendingCard(read, thread), store.pendingCard(thread));
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("an old card's edit probe stops at its bounded tail", () => {
  for (const size of [63, 64]) {
    const { store, db, thread } = oldCard(size);
    try {
      const read = makeStore(db, "");
      if (size === 63) assert.equal(cardAt(read, thread, 1)?.[0].text, "ask");
      else assert.throws(() => cardAt(read, thread, 1), { status: 503, message: "legacy edit lookup pending" });
    } finally { store.close(); }
  }
});

test("an answered, closed or invalid card does not wait for old edits", () => {
  for (const outcome of ["answered", "closed", "invalid"] as const) {
    const { store, db, thread } = oldCard(150);
    try {
      if (outcome === "answered")
        db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,152,'message','152.1','person','p','yes',152)").run(thread);
      else if (outcome === "closed")
        db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,1,'person',152)").run(thread);
      else db.prepare("UPDATE entries SET card='not json' WHERE thread=? AND n=1").run(thread);
      const read = makeStore(db, "");
      assert.equal(cardAt(read, thread, 1), null);
      assert.equal(pendingCard(read, thread), null);
      assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
    } finally { store.close(); }
  }
});

test("an unrelated 64-bit edit key does not change an old card", () => {
  const { store, db, thread } = oldCard(5);
  try {
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',1000,'agent','worker','other',1)")
      .run(thread, 9007199254740993n);
    const read = makeStore(db, "");
    assert.equal(cardAt(read, thread, 1)?.[0].text, "ask");
    assert.equal(pendingCard(read, thread)?.[0].text, "ask");
  } finally { store.close(); }
});

test("a card and its unprepared old edit are read from one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "old-card-edit-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldCard(80, path), writer = new DatabaseSync(path);
  try {
    db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,82,'edit',1,'agent','worker','before',82)").run(thread);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LAST_MESSAGE_RECENT_EDIT && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET text='after' WHERE thread=? AND n=82").run(thread);
          writer.prepare("UPDATE entries SET card=? WHERE thread=? AND n=1").run(JSON.stringify({ type: "text", placeholder: "new" }), thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    const before = cardAt(read, thread, 1);
    assert.ok(changed);
    assert.equal(before?.[0].text, "before");
    assert.equal(before?.[1].type, "options");
    const after = cardAt(read, thread, 1);
    assert.equal(after?.[0].text, "after");
    assert.equal(after?.[1].type, "text");
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("pending card readiness and an answer share one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "old-card-answer-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldCard(0, path), writer = new DatabaseSync(path);
  try {
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === CARD_POST_LATEST && !changed) {
          changed = true;
          writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','2.1','person','p','yes',2)").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    assert.equal(pendingCard(read, thread)?.[0].n, 1);
    assert.ok(changed);
    assert.equal(pendingCard(read, thread), null);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("review readers share old edit preparation after handover when one cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "old-card-reader-")), path = join(dir, "stillfail.db");
  const { store, thread, short } = oldCard(150, path);
  const previous = Promise.withResolvers<void>(), readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const controller = new AbortController();
    const stopped = readers.read("reviewPendingCard", { thread }, "en", { signal: controller.signal });
    const kept = readers.read("reviewPendingCard", { thread }, "en");
    void stopped.catch(() => {}); void kept.catch(() => {});
    assert.equal(JSON.parse(await readers.read("reviewPendingCard", { thread: short }, "en")), null);
    controller.abort();
    await assert.rejects(stopped, /read cancelled/);
    previous.resolve();
    const [message, returnedCard] = JSON.parse(await kept);
    assert.equal(message.text, "ask");
    assert.equal(returnedCard.type, "options");
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
