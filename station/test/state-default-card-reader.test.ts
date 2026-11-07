import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { newSession, say } from "../src/sessions/lifecycle.ts";
import { CARD_POST_LATEST } from "../src/store/card-post-index.ts";
import { Store } from "../src/store/store.ts";
import { Rig, settle } from "./hub-fakes.ts";

const card = { type: "options", options: [{ label: "yes" }] };

test("default cards preserve original ordering, missing timestamps, and pending rules", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const a = store.openThread("ember", "CHAT", "a", null, null).id;
    const b = store.openThread("ember", "CHAT", "b", null, null).id;
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,options,at)
      VALUES(?,?,'message',?,'agent','worker','ask',?,?,?)`);
    const read = readStore.makeStore(db, "");
    const same = (threads: number[]) => {
      const cards = threads.flatMap((thread) => store.pendingCard(thread)?.[0] ?? []);
      cards.sort((x, y) => x.createdAt - y.createdAt);
      const m = cards.at(-1);
      assert.deepEqual(readStore.statePendingCard(read, threads), m ? [m.thread, m.n, m.ts] : null);
    };
    put.run(a, 1, null, JSON.stringify(card), null, 2);
    put.run(b, 1, "b1", "{", JSON.stringify([{ label: "yes" }]), 2);
    same([a, b]);
    same([b, a]);
    assert.deepEqual(readStore.statePendingCard(read, [b, a]), [a, 1, ""]);
    put.run(a, 2, "bad", "{", null, 3);
    same([a, b]);
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,1,'person',4)").run(b);
    same([a, b]);
    put.run(b, 2, "b2", JSON.stringify(card), null, 5);
    same([a, b]);
    db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,3,'message','answer','person','p','yes',6)").run(b);
    same([a, b]);
  } finally { store.close(); }
});

test("default cards and their answer checks use the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "default-card-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "snapshot", null, null).id;
    store.db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','ask','agent','worker','ask',?,1)")
      .run(thread, JSON.stringify(card));
    let changed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === CARD_POST_LATEST && !changed) {
          changed = true;
          writer.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','answer','person','p','yes',2)").run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.deepEqual(readStore.statePendingCard(read, [thread]), [thread, 1, "ask"]);
    assert.equal(changed, true);
    assert.equal(readStore.statePendingCard(read, [thread]), null);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const tool of ["chat_state", "chat_post"] as const) {
  test(`${tool} finds its default card without the station's merged lookup`, async () => {
    const r = new Rig();
    try {
      const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
      say(r.hub, thread.id, "ada@x.com", "please do this");
      await settle();
      const to = `CHAT/${thread.threadTs}`;
      if (tool === "chat_state") await r.call(key, "chat_post", { to, text: "May I continue?", card });
      const reader = readStore.makeStore(r.store.db, r.dir);
      r.hub.statePendingCard = async (threads) => readStore.statePendingCard(reader, threads);
      const previous = r.store.pendingCard;
      r.store.pendingCard = () => { throw new Error("station merged pending-card lookup used"); };
      try {
        const args = tool === "chat_state" ? { kind: "need_human", need: "permission" }
          : { to, text: "May I continue?", card, kind: "need_human", need: "permission" };
        const result = await r.call(key, tool, args);
        assert.match(result, tool === "chat_state" ? /Recorded state need_human/ : /recorded state need_human/);
      } finally { r.store.pendingCard = previous; }
      const question = r.said(thread.id).at(-1)!;
      r.claude.last().complete();
      await settle();
      assert.deepEqual(r.store.lastTurn(key)!.about, { thread: thread.id, seq: question.n, ts: question.ts });
    } finally { await r.close(); }
  });
}

test("an answer while the default card is being read is checked before recording a need", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?", card });
    const reader = readStore.makeStore(r.store.db, r.dir), started = Promise.withResolvers<void>();
    r.hub.statePendingCard = async (threads) => {
      const result = readStore.statePendingCard(reader, threads);
      started.resolve();
      await release.promise;
      return result;
    };
    const pending = r.call(key, "chat_state", { kind: "need_human", need: "permission" });
    void pending.catch(() => {});
    const readStarted = await Promise.race([started.promise.then(() => true), pending.then(() => false, () => false)]);
    assert.equal(readStarted, true, "the default-card check must wait for its reader");
    say(r.hub, thread.id, "ada@x.com", "yes");
    release.resolve();
    await assert.rejects(pending, /requires a visible question/);
  } finally { release.resolve(); await r.close(); }
});

for (const mode of ["named", "default"] as const) {
  test(`a ${mode} question read cannot declare a later turn`, async () => {
    const r = new Rig(), release = Promise.withResolvers<void>();
    try {
      const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
      say(r.hub, thread.id, "ada@x.com", "please do this");
      await settle();
      await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?", card });
      const question = r.said(thread.id).at(-1)!;
      const read = readStore.makeStore(r.store.db, r.dir), started = Promise.withResolvers<void>();
      const active = () => r.store.db.prepare("SELECT id,declared,need,about_n FROM turns WHERE session_key=? AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1").get(key);
      const old = active();
      assert.ok(old);
      if (mode === "named") r.hub.stateQuestion = async (session, threads, ts) => {
        const found = readStore.stateQuestion(read, session, threads, ts);
        started.resolve(); await release.promise; return found;
      };
      else r.hub.statePendingCard = async (threads) => {
        const found = readStore.statePendingCard(read, threads);
        started.resolve(); await release.promise; return found;
      };
      const pending = r.call(key, "chat_state", { kind: "need_human", need: "permission", ...(mode === "named" ? { about: question.ts } : {}) });
      void pending.catch(() => {});
      await started.promise;
      r.claude.last().end({ kind: "aborted" });
      await settle();
      r.hub.notify(key, "a background job ended");
      await settle();
      const next = active();
      assert.ok(next, "the notice starts a later turn");
      assert.notEqual(next.id, old.id, "the original turn ended while reading");
      release.resolve();
      await pending.catch(() => {});
      const after = r.store.db.prepare("SELECT declared,need,about_n FROM turns WHERE id=?").get(next.id);
      assert.equal(after?.declared, null);
      assert.equal(after?.need, null);
      assert.equal(after?.about_n, null);
    } finally { release.resolve(); await r.close(); }
  });
}

test("unrelated external writes do not keep the default card from being recorded", async () => {
  const r = new Rig();
  await r.hub.shutdown();
  r.store.close();
  const path = join(r.dir, "stillfail.db");
  r.store = Store.open(path);
  r.hub = r.newHub({ chats: () => undefined });
  const readers = new Readers(r.dir, 1, undefined, 1), writer = new DatabaseSync(path);
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?", card });
    const question = r.said(thread.id).at(-1)!;
    const other = r.store.openThread("ember", "CHAT", "unrelated", null, null).id;
    let writes = 0;
    r.hub.statePendingCard = async (threads) => {
      if (writes === 5) throw new Error("unrelated writes kept the default card from being recorded");
      const result = JSON.parse(await readers.read("statePendingCard", { threads }, "en"));
      writes++;
      writer.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,?,'message',?,'person','other','unrelated',?)`).run(other, writes, `other-${writes}`, Date.now());
      return result;
    };
    assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "permission" }), "Recorded state need_human.");
    r.claude.last().complete();
    await settle();
    assert.deepEqual(r.store.lastTurn(key)!.about, { thread: thread.id, seq: question.n, ts: question.ts });
  } finally { writer.close(); readers.close(); await r.close(); }
});

test("default-card readers share old card preparation when one is cancelled", async () => {
  const dir = mkdtempSync(join(tmpdir(), "default-card-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    const short = store.openThread("ember", "CHAT", "short", null, null).id;
    db.prepare("DELETE FROM card_post_scopes WHERE thread=?").run(thread);
    const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,ts,author_kind,author,text,card,at)
      VALUES(?,?,?,?,?,'agent','worker','ask',?,?)`);
    db.exec("BEGIN");
    put.run(thread, 1, "message", null, "ask", JSON.stringify(card), 1);
    for (let n = 2; n <= 151; n++) put.run(thread, n, "edit", 1, null, JSON.stringify(card), n);
    db.exec("COMMIT");
    const controller = new AbortController();
    const abandoned = readers.read("statePendingCard", { threads: [thread] }, "en", { signal: controller.signal });
    const kept = readers.read("statePendingCard", { threads: [thread] }, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    assert.equal(JSON.parse(await readers.read("statePendingCard", { threads: [short] }, "en")), null);
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept), [thread, 1, "ask"]);
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
