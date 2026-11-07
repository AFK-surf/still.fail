import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as readStore from "../src/read/store.ts";
import { newSession, say } from "../src/sessions/lifecycle.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { Rig, settle } from "./hub-fakes.ts";

test("named questions retain their visibility and pending-card rules through the reader", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    const person = r.said(thread.id).at(-1)!, to = `CHAT/${thread.threadTs}`;
    await r.call(key, "chat_post", { to, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const read = readStore.makeStore(r.store.db, r.dir);
    r.hub.stateQuestion = async (session, threads, ts) => readStore.stateQuestion(read, session, threads, ts);
    const args = { kind: "need_human", need: "permission", about: question.ts };
    assert.match(await r.refused(key, "chat_state", { ...args, about: "missing" }), /about must be the ts of a message/);
    assert.match(await r.refused(key, "chat_state", { ...args, about: person.ts }), /your visible question/);
    r.store.editMessage(thread.surface, thread.channel, thread.threadTs, question.ts, "  ");
    assert.match(await r.refused(key, "chat_post", { ...args, to, text: "Still waiting" }), /your visible question/);
    r.store.editMessage(thread.surface, thread.channel, thread.threadTs, question.ts, "May I continue?");
    assert.equal(await r.call(key, "chat_state", args), "Recorded state need_human.");
    say(r.hub, thread.id, "ada@x.com", "yes");
    assert.match(await r.refused(key, "chat_state", args), /no longer pending/);
    const card = { type: "options", options: [{ label: "yes" }] };
    await r.call(key, "chat_post", { to, text: "First card?", card });
    const first = r.said(thread.id).at(-1)!;
    await r.call(key, "chat_post", { to, text: "New card?", card });
    const latest = r.said(thread.id).at(-1)!;
    assert.match(await r.refused(key, "chat_state", { ...args, about: first.ts }), /no longer pending/);
    assert.equal(await r.call(key, "chat_state", { ...args, about: latest.ts }), "Recorded state need_human.");
    assert.match(await r.refused(key, "chat_post", { ...args, about: latest.ts, to, text: "Another card?", card }), /omit about/);
    assert.equal(r.store.withdrawCard(key, thread.id, latest.ts), true);
    assert.match(await r.refused(key, "chat_state", { ...args, about: latest.ts }), /no longer pending/);
  } finally { await r.close(); }
});

test("a question and its latest edit come from one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "state-question-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), writer = new DatabaseSync(path);
  try {
    const thread = store.openThread("ember", "CHAT", "snapshot", null, null).id;
    store.db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,1,'message','ask','agent','worker','May I?',1)`).run(thread);
    let changed = false;
    const observed = new Proxy(store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM merged WHERE thread = ? AND n = ?" && !changed) {
          changed = true;
          writer.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at)
            VALUES(?,2,'edit',1,'agent','worker',' ',2)`).run(thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = readStore.makeStore(observed, dir);
    assert.deepEqual(readStore.stateQuestion(read, "worker", [thread], "ask"), { kind: "found", about: [thread, 1, "ask"] });
    assert.equal(changed, true);
    assert.deepEqual(readStore.stateQuestion(read, "worker", [thread], "ask"), { kind: "invalid" });
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a need about a visible question reads its current state away from the station's merged lookup", async () => {
  const r = new Rig();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    const to = `CHAT/${thread.threadTs}`;
    await r.call(key, "chat_post", { to, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const read = readStore.makeStore(r.store.db, r.dir);
    r.hub.stateQuestion = async (session, threads, ts) => readStore.stateQuestion(read, session, threads, ts);
    const original = r.store.messageAt;
    r.store.messageAt = () => { throw new Error("station merged question lookup used"); };
    try {
      assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts }), "Recorded state need_human.");
    } finally { r.store.messageAt = original; }
    r.claude.last().complete();
    await settle();
    assert.deepEqual(r.store.lastTurn(key)!.about, { thread: thread.id, seq: question.n, ts: question.ts });
  } finally { await r.close(); }
});

test("an answer during a question read cannot leave the state waiting for that answered question", async () => {
  const r = new Rig();
  const release = Promise.withResolvers<void>();
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    const to = `CHAT/${thread.threadTs}`;
    await r.call(key, "chat_post", { to, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const read = readStore.makeStore(r.store.db, r.dir);
    const started = Promise.withResolvers<void>();
    let reads = 0;
    r.hub.stateQuestion = async (session, threads, ts) => {
      const result = readStore.stateQuestion(read, session, threads, ts);
      if (reads++ === 0) { started.resolve(); await release.promise; }
      return result;
    };
    const pending = r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts });
    void pending.catch(() => {});
    const readStarted = await Promise.race([started.promise.then(() => true), pending.then(() => false, () => false)]);
    assert.equal(readStarted, true, "the question check must wait for its reader");
    say(r.hub, thread.id, "ada@x.com", "yes");
    release.resolve();
    await assert.rejects(pending, /no longer pending/);
  } finally { release.resolve(); await r.close(); }
});

for (const change of ["edit", "withdraw"] as const) {
  test(`${change} during a question read is checked before a state is recorded`, async () => {
    const r = new Rig(), release = Promise.withResolvers<void>();
    try {
      const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
      say(r.hub, thread.id, "ada@x.com", "please do this");
      await settle();
      const to = `CHAT/${thread.threadTs}`;
      await r.call(key, "chat_post", { to, text: "May I continue?", ...(change === "withdraw" ? { card: { type: "options", options: [{ label: "yes" }] } } : {}) });
      const question = r.said(thread.id).at(-1)!;
      const read = readStore.makeStore(r.store.db, r.dir), started = Promise.withResolvers<void>();
      let reads = 0;
      r.hub.stateQuestion = async (session, threads, ts) => {
        const result = readStore.stateQuestion(read, session, threads, ts);
        if (reads++ === 0) { started.resolve(); await release.promise; }
        return result;
      };
      const args = { kind: "need_human", need: "permission", about: question.ts };
      const pending = change === "edit"
        ? r.call(key, "chat_post", { ...args, to, text: "Still waiting" })
        : r.call(key, "chat_state", args);
      void pending.catch(() => {});
      await started.promise;
      if (change === "edit") r.store.editMessage(thread.surface, thread.channel, thread.threadTs, question.ts, "   ");
      else assert.equal(r.store.withdrawCard(key, thread.id, question.ts), true);
      release.resolve();
      await assert.rejects(pending, change === "edit" ? /your visible question/ : /no longer pending/);
      if (change === "edit") assert.equal(r.said(thread.id).some((m) => m.text === "Still waiting"), false);
    } finally { release.resolve(); await r.close(); }
  });
}

test("a question is checked again when another database connection records an answer", async () => {
  const r = new Rig(), release = Promise.withResolvers<void>();
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
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!, started = Promise.withResolvers<void>();
    let reads = 0;
    r.hub.stateQuestion = async (session, threads, ts) => {
      const result = JSON.parse(await readers.read("stateQuestion", { key: session, threads, ts }, "en"));
      if (reads++ === 0) { started.resolve(); await release.promise; }
      return result;
    };
    const pending = r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts });
    void pending.catch(() => {});
    await started.promise;
    const last = writer.prepare("SELECT max(n) AS n FROM entries WHERE thread = ?").get(thread.id)!.n as number;
    writer.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,?,'message','external-answer','person','ada','yes',?)`).run(thread.id, last + 1, Date.now());
    release.resolve();
    await assert.rejects(pending, /no longer pending/);
  } finally { release.resolve(); writer.close(); readers.close(); await r.close(); }
});

test("unrelated writes from another connection do not keep a valid question from being recorded", async () => {
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
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const other = r.store.openThread("ember", "CHAT", "unrelated", null, null).id;
    let writes = 0;
    r.hub.stateQuestion = async (session, threads, ts) => {
      if (writes === 5) throw new Error("unrelated writes kept the question from being recorded");
      const result = JSON.parse(await readers.read("stateQuestion", { key: session, threads, ts }, "en"));
      writes++;
      writer.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,?,'message',?,'person','other','unrelated',?)`).run(other, writes, `other-${writes}`, Date.now());
      return result;
    };
    assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts }), "Recorded state need_human.");
  } finally { writer.close(); readers.close(); await r.close(); }
});

test("a removed native edit index is not scanned on the station thread during confirmation", async () => {
  const r = new Rig();
  await r.hub.shutdown();
  r.store.close();
  const path = join(r.dir, "stillfail.db");
  r.store = Store.open(path);
  r.hub = r.newHub({ chats: () => undefined });
  const readers = new Readers(r.dir, 1, undefined, 1), writer = new DatabaseSync(path);
  const original = r.store.db;
  try {
    const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
    say(r.hub, thread.id, "ada@x.com", "please do this");
    await settle();
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const last = writer.prepare("SELECT max(n) AS n FROM entries WHERE thread = ?").get(thread.id)!.n as number;
    const edit = writer.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',?)");
    for (let n = last + 1; n <= last + 150; n++) edit.run(thread.id, n, n + 10000, n);
    (r.store as { db: typeof original }).db = new Proxy(original, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM merged WHERE thread = ? AND n = ?") {
          const native = target.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='entries_edits'").get();
          const view = target.prepare("SELECT sql FROM sqlite_master WHERE type='view' AND name='merged'").get()?.sql;
          assert.ok(native || (typeof view === "string" && view.includes("legacy_edit_meta")), "station must not scan unindexed edits");
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    let reads = 0;
    r.hub.stateQuestion = async (session, threads, ts) => {
      const result = JSON.parse(await readers.read("stateQuestion", { key: session, threads, ts }, "en"));
      if (reads++ === 0) writer.exec("DROP INDEX entries_edits");
      return result;
    };
    assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts }), "Recorded state need_human.");
    assert.ok(reads >= 2);
  } finally {
    (r.store as { db: typeof original }).db = original;
    writer.close(); readers.close(); await r.close();
  }
});

test("unrelated writes do not starve a question when the native edit index is removed", async () => {
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
    await r.call(key, "chat_post", { to: `CHAT/${thread.threadTs}`, text: "May I continue?" });
    const question = r.said(thread.id).at(-1)!;
    const other = r.store.openThread("ember", "CHAT", "unrelated", null, null).id;
    const last = writer.prepare("SELECT max(n) AS n FROM entries WHERE thread = ?").get(thread.id)!.n as number;
    const edit = writer.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',?)");
    for (let n = last + 1; n <= last + 150; n++) edit.run(thread.id, n, n + 10000, n);
    let reads = 0;
    r.hub.stateQuestion = async (session, threads, ts) => {
      if (reads === 5) throw new Error("unrelated writes kept the question from being recorded after index removal");
      const result = JSON.parse(await readers.read("stateQuestion", { key: session, threads, ts }, "en"));
      if (++reads === 1) writer.exec("DROP INDEX entries_edits");
      writer.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
        VALUES(?,?,'message',?,'person','other','unrelated',?)`).run(other, reads, `other-${reads}`, Date.now());
      return result;
    };
    assert.equal(await r.call(key, "chat_state", { kind: "need_human", need: "permission", about: question.ts }), "Recorded state need_human.");
  } finally { writer.close(); readers.close(); await r.close(); }
});

test("question readers share old edit preparation, and a cancelled read leaves the other waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "state-question-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  const previous = Promise.withResolvers<void>();
  const readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const thread = store.openThread("ember", "CHAT", "old", null, null).id;
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at)
      VALUES(?,1,'message','ask','agent','worker','May I?',1)`).run(thread);
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','other','edit',?)");
    for (let n = 2; n <= 151; n++) edit.run(thread, n, n + 1000, n);
    installLegacyEdits(db);
    addClientColumn(db);
    const args = { key: "worker", threads: [thread], ts: "ask" }, controller = new AbortController();
    const abandoned = readers.read("stateQuestion", args, "en", { signal: controller.signal });
    const kept = readers.read("stateQuestion", args, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    assert.deepEqual(JSON.parse(await kept), { kind: "found", about: [thread, 1, "ask"] });
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
