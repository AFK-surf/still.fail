import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { cardEditPage, cardMessagePage, cardOutcomeHeads, installCardOutbox } from "../src/store/card-outbox.ts";
import { CardOutcomeWorker } from "../src/store/card-outbox-worker.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { STILLFAIL_SURFACE, Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";
import { SignIns } from "../src/vault/signin.ts";
import { queueSigninSave } from "../src/vault/signin-save-index.ts";

async function until(check: () => boolean, timeout = 5000): Promise<void> {
  const end = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= end) throw new Error("timed out waiting for sign-in outcome");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function rig(status = "pending", path = ":memory:") {
  const store = Store.open(path), db = store.db, thread = store.openThread("ember", "CHAT", "signin", null, null).id;
  const message = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other edit',?)");
  for (let n = 1; n <= 100; n++) message.run(thread, n, `other-${n}`, n);
  for (let n = 101; n <= 200; n++) edit.run(thread, n, n - 100, n);
  db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,201,'message','card','agent','agent','sign in',201,?)`)
    .run(thread, JSON.stringify({ type: "options", signin: { id: "g1", site: "example.com", reason: "test" } }));
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  installLegacyEdits(db); addClientColumn(db); installWidgetSources(db);
  const prior = Promise.withResolvers<void>();
  const worker = new CardOutcomeWorker(store, prior.promise,
    async (t, target, before) => cardEditPage(db, t, target, before),
    async (t, target, before) => cardMessagePage(db, t, target, before));
  const where = { connect: "test", thread: { id: thread, channel: "CHAT", threadTs: "root", surface: STILLFAIL_SURFACE } };
  const hub = { store: { getSession: () => ({ archivedAt: null }), sessionThreadById: () => where, pendingCardHeader: () => null,
    insertMessage: (m: any, before?: () => void) => {
      before?.();
      const n = Number(db.prepare("SELECT MAX(n)+1 AS n FROM entries WHERE thread=?").get(thread)!.n);
      db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES(?,?,'message',?,'agent',?,?,?,?)")
        .run(thread, n, m.ts, m.author, m.text, n, JSON.stringify(m.card));
      return [n];
    },
    withdrawCard: store.withdrawCard.bind(store), restateCard: store.restateCard.bind(store), subscribe: () => {} },
    chat: () => ({ post: async () => "replacement" }), shared: () => {}, notify: () => {} };
  const deps = { db, hub, cardOutcomes: worker, now: () => 1_800_000_000_000, after: () => () => {},
    workspace: () => "work", screenLink: () => null, backfill: { previousGone: prior.promise },
    browser: { tabs: () => [], look: async () => ({}), drive: async () => ({ state: "left" }) },
    vault: { listed: () => null, held: () => null, use: async () => "", keep: async (_s: string, _site: string, _reason: string, made: (id: string) => void) => { made("r_save"); return "asked to keep"; } },
  } as any;
  const signIns = new SignIns(deps);
  const ask = { id: "g1", session: "agent", chat: "chat", owner: "person@example.com", site: "example.com", tab: "T1", reason: "test",
    at: 1_800_000_000, status, thread, cardTs: "card" };
  db.prepare("INSERT INTO signin_asks(id,session,owner,status,body) VALUES(?,?,?,?,?)").run(ask.id, ask.session, ask.owner, ask.status, JSON.stringify(ask));
  const close = async () => { prior.resolve(); await worker.close(); await signIns.close(); store.close(); };
  return { store, db, thread, prior, worker, signIns, deps, ask, close };
}

test("a sign-in denial closes immediately and writes its outcome after handover", async () => {
  const r = rig();
  try {
    assert.equal(r.signIns.deny(r.ask.owner, "work", r.ask.id), null);
    assert.equal(r.signIns.get(r.ask.id)?.status, "denied");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 1);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=? AND n>201").get(r.thread)?.n, 0);
    assert.equal(cardOutcomeHeads(r.db, "0").length, 1);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).signin.outcome, { status: "denied" });
  } finally { await r.close(); }
});

test("a sign-in waiting to be saved stays open until the vault decision", async () => {
  const r = rig("left");
  try {
    assert.match(await r.signIns.ask("agent", { site: "example.com", done: true }), /asked to keep/);
    assert.equal(r.signIns.get(r.ask.id)?.status, "done");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 0);
    r.signIns.heard({ id: "r_save", session: "agent", status: "granted", save: { kind: "browser" } } as any);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 1);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM card_outbox").get()?.n, 2);
    const seen: unknown[] = [];
    r.store.subscribe((change) => {
      if (change.type === "thread" && change.id === r.thread && change.entries.some((entry) => entry.kind === "edit")) {
        const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
        seen.push(JSON.parse(String(last.card)).signin.outcome);
      }
    });
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    assert.deepEqual(seen, [{ status: "done", save: "r_save" }, { status: "done", save: "r_save", kept: "granted" }]);
  } finally { await r.close(); }
});

test("a failed sign-in outcome queue rolls back its request and card close", async () => {
  const r = rig();
  try {
    installCardOutbox(r.db);
    r.db.exec("CREATE TRIGGER fail_signin_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    assert.throws(() => r.signIns.deny(r.ask.owner, "work", r.ask.id), /queue failed/);
    assert.equal(r.signIns.get(r.ask.id)?.status, "pending");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { await r.close(); }
});

test("sign-in progress is replayed in order without persisting credentials", async () => {
  const r = rig();
  try {
    const seen: unknown[] = [];
    r.store.subscribe((change) => {
      if (change.type === "thread" && change.id === r.thread && change.entries.some((entry) => entry.kind === "edit")) {
        const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
        seen.push(JSON.parse(String(last.card)).signin.outcome);
      }
    });
    assert.equal(r.signIns.fill(r.ask.owner, "work", r.ask.id, { username: "private-user", password: "private-password", keep: true }), null);
    await until(() => r.signIns.get(r.ask.id)?.status === "left");
    const saved = JSON.stringify(r.db.prepare("SELECT body FROM signin_asks WHERE id=?").get(r.ask.id));
    const queued = JSON.stringify(r.db.prepare("SELECT outcome FROM card_outbox ORDER BY id").all());
    assert.doesNotMatch(saved + queued, /private-user|private-password/);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    assert.deepEqual(seen, [{ status: "filling", keep: true }, { status: "left", keep: true }]);
  } finally { await r.close(); }
});

test("a vault decision retries after its sign-in outcome cannot be queued", async () => {
  const r = rig("left");
  try {
    await r.signIns.ask("agent", { site: "example.com", done: true });
    r.db.exec("CREATE TRIGGER fail_signin_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    const result = { id: "r_save", session: "agent", status: "granted", save: { kind: "browser" } } as any;
    assert.throws(() => r.signIns.heard(result), /queue failed/);
    assert.equal(r.signIns.get(r.ask.id)?.kept, undefined);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    r.db.exec("DROP TRIGGER fail_signin_outcome");
    r.signIns.heard(result);
    assert.equal(r.signIns.get(r.ask.id)?.kept, "granted");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 1);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).signin.outcome, { status: "done", save: "r_save", kept: "granted" });
  } finally { await r.close(); }
});

test("a reissued sign-in queues its current and later state on the new card", async () => {
  const r = rig();
  try {
    assert.equal(r.signIns.self(r.ask.owner, "work", r.ask.id, false), null);
    r.store.withdrawCard("agent", r.thread, "card");
    await r.signIns.ask("agent", { site: "example.com", reask: true });
    assert.equal(r.signIns.get(r.ask.id)?.cardTs, "replacement");
    assert.equal(r.signIns.self(r.ask.owner, "work", r.ask.id, true), null);
    const queued = r.db.prepare("SELECT ts,outcome FROM card_outbox ORDER BY id").all();
    assert.deepEqual(queued.map((row) => [row.ts, JSON.parse(String(row.outcome)).status]),
      [["card", "person"], ["replacement", "person"], ["replacement", "left"]]);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).signin.outcome, { status: "left" });
  } finally { await r.close(); }
});

test("a failed reissue withdraws its new card and keeps the previous location", async () => {
  const r = rig();
  try {
    r.store.withdrawCard("agent", r.thread, "card");
    installCardOutbox(r.db);
    r.db.exec("CREATE TRIGGER fail_signin_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    await assert.rejects(r.signIns.ask("agent", { site: "example.com", reask: true }), /queue failed/);
    assert.equal(r.signIns.get(r.ask.id)?.cardTs, "card");
    const replacement = r.db.prepare("SELECT n FROM entries WHERE thread=? AND ts='replacement'").get(r.thread)!;
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=?").get(r.thread, replacement.n)?.n, 1);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { await r.close(); }
});

test("a recovered vault decision finishes the queued sign-in outcome", async () => {
  const r = rig("done");
  let restarted: SignIns | undefined;
  try {
    await r.signIns.close();
    const ask = { ...r.ask, status: "done", save: "r_save", kept: "granted" };
    r.db.prepare("UPDATE signin_asks SET body=? WHERE id=?").run(JSON.stringify(ask), ask.id);
    queueSigninSave(r.db, "agent", "r_save", "granted");
    restarted = new SignIns(r.deps);
    r.prior.resolve();
    await until(() => r.db.prepare("SELECT 1 FROM signin_save_pending").get() === undefined);
    await until(() => {
      const row = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread);
      return row?.card != null && JSON.parse(String(row.card)).signin.outcome?.kept === "granted";
    });
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 1);
  } finally { await restarted?.close(); await r.close(); }
});

test("a queued sign-in outcome survives restart and follows the previous station's edit", async () => {
  const dir = mkdtempSync(join(tmpdir(), "signin-outbox-restart-")), path = join(dir, "stillfail.db");
  const r = rig("pending", path), previous = Promise.withResolvers<void>();
  let store: Store | undefined, worker: CardOutcomeWorker | undefined, old: DatabaseSync | undefined;
  try {
    assert.equal(r.signIns.deny(r.ask.owner, "work", r.ask.id), null);
    await r.worker.close();
    await r.signIns.close();
    r.store.close();
    store = Store.open(path);
    const db = store.db;
    worker = new CardOutcomeWorker(store, previous.promise,
      async (t, target, before) => cardEditPage(db, t, target, before),
      async (t, target, before) => cardMessagePage(db, t, target, before));
    old = new DatabaseSync(path, { timeout: 5000 });
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,202,'edit',201,'agent','agent','previous station text',202,?)`)
      .run(r.thread, JSON.stringify({ type: "options", signin: { id: "g1", reason: "edited during handover" } }));
    assert.equal(db.prepare("SELECT status FROM signin_asks WHERE id='g1'").get()?.status, "denied");
    assert.equal(cardOutcomeHeads(db, "0").length, 1);
    previous.resolve();
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "previous station text");
    assert.equal(JSON.parse(String(last.card)).signin.reason, "edited during handover");
    assert.deepEqual(JSON.parse(String(last.card)).signin.outcome, { status: "denied" });
  } finally {
    previous.resolve(); old?.close(); await worker?.close(); store?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
