import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PhoneGrants } from "../src/adb/grants.ts";
import { Readers } from "../src/read/pool.ts";
import { cardEditPage, cardMessagePage, cardOutcomeHeads, installCardOutbox } from "../src/store/card-outbox.ts";
import { CardOutcomeWorker } from "../src/store/card-outbox-worker.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";

async function until(check: () => boolean, timeout = 5000): Promise<void> {
  const end = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= end) throw new Error("timed out waiting for phone outcome");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function rig() {
  const store = Store.open(":memory:"), db = store.db;
  const thread = store.openThread("ember", "CHAT", "phone", null, null).id;
  const insert = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other edit',?)");
  for (let n = 1; n <= 100; n++) insert.run(thread, n, `other-${n}`, n);
  for (let n = 101; n <= 200; n++) edit.run(thread, n, n - 100, n);
  db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,201,'message','card','agent','agent','question',201,?)`)
    .run(thread, JSON.stringify({ type: "options", adb: { request: "p1", reason: "debug" } }));
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  installLegacyEdits(db); addClientColumn(db); installWidgetSources(db);
  const prior = Promise.withResolvers<void>();
  const worker = new CardOutcomeWorker(store, prior.promise,
    async (t, target, before) => cardEditPage(db, t, target, before),
    async (t, target, before) => cardMessagePage(db, t, target, before));
  const hub = { store: { getSession: () => ({ ws: "work", archivedAt: null }),
    withdrawCard: store.withdrawCard.bind(store), restateCard: store.restateCard.bind(store), subscribe: () => {} }, notify: () => {} } as any;
  const grants = new PhoneGrants({ db, hub, cardOutcomes: worker, home: () => "work", title: () => null, now: () => 1_800_000_000_000 });
  const request = { id: "p1", session: "agent", chat: "chat", owner: "person@example.com", reason: "debug",
    at: 1_800_000_000, status: "pending", thread, cardTs: "card" };
  db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)")
    .run(request.id, request.session, request.owner, request.status, JSON.stringify(request));
  return { store, db, thread, prior, worker, grants, request };
}

test("a phone decision closes its card immediately and replays ordered outcomes after handover", async () => {
  const r = rig();
  try {
    const seen: unknown[] = [];
    r.store.subscribe((change) => {
      if (change.type === "thread" && change.id === r.thread && change.entries.some((entry) => entry.kind === "edit")) {
        const row = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
        seen.push(JSON.parse(String(row.card)).adb.outcome);
      }
    });
    assert.equal(r.grants.decide(r.request.owner, r.request.id, "hour", "work"), null);
    assert.equal(r.grants.get(r.request.id)?.status, "granted");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 1);
    assert.equal(cardOutcomeHeads(r.db, "0").length, 1);
    r.grants.linked(r.request.owner, { adb: "connected" });
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM card_outbox").get()?.n, 2);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    assert.deepEqual(seen, [{ status: "granted", scope: "hour" }, { status: "granted", scope: "hour", link: "connected" }]);
  } finally { r.prior.resolve(); await r.worker.close(); r.store.close(); }
});

test("a phone decision rolls back its status and close when its outcome cannot be queued", async () => {
  const r = rig();
  try {
    installCardOutbox(r.db);
    r.db.exec("CREATE TRIGGER fail_phone_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    assert.throws(() => r.grants.decide(r.request.owner, r.request.id, "hour", "work"), /queue failed/);
    assert.equal(r.grants.get(r.request.id)?.status, "pending");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { r.prior.resolve(); await r.worker.close(); r.store.close(); }
});

test("a denied phone request records its outcome after the card is closed", async () => {
  const r = rig();
  try {
    assert.equal(r.grants.decide(r.request.owner, r.request.id, null, "work"), null);
    assert.equal(r.grants.get(r.request.id)?.status, "denied");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 1);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).adb.outcome, { status: "denied" });
  } finally { r.prior.resolve(); await r.worker.close(); r.store.close(); }
});

test("signing, link changes and revocation are written in the same order as their phone states", async () => {
  const r = rig();
  try {
    const seen: unknown[] = [];
    r.store.subscribe((change) => {
      if (change.type === "thread" && change.id === r.thread && change.entries.some((entry) => entry.kind === "edit")) {
        const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
        seen.push(JSON.parse(String(last.card)).adb.outcome);
      }
    });
    assert.equal(r.grants.decide(r.request.owner, r.request.id, "hour", "work"), null);
    assert.equal(r.grants.sign(r.request.owner, r.request.id, { body: "signed", sig: "signature" }, "work"), null);
    r.grants.linked(r.request.owner, { adb: "connected" });
    assert.equal(r.grants.revoke(r.request.owner, r.request.id, "work"), null);
    assert.equal(r.grants.get(r.request.id)?.status, "ended");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM card_outbox").get()?.n, 4);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    assert.deepEqual(seen, [
      { status: "granted", scope: "hour" }, { status: "granted", scope: "hour" },
      { status: "granted", scope: "hour", link: "connected" }, { status: "ended", scope: "hour", why: "已收回" },
    ]);
  } finally { r.prior.resolve(); await r.worker.close(); r.store.close(); }
});

test("a grant that expires while being listed queues its ended outcome", async () => {
  const r = rig();
  try {
    assert.equal(r.grants.decide(r.request.owner, r.request.id, "hour", "work"), null);
    const expired = { ...r.grants.get(r.request.id)!, exp: 1 };
    r.db.prepare("UPDATE adb_requests SET body=? WHERE id=?").run(JSON.stringify(expired), expired.id);
    assert.deepEqual(r.grants.live(), []);
    assert.equal(r.grants.get(r.request.id)?.status, "ended");
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).adb.outcome, { status: "ended", scope: "hour", why: "授权已到期" });
  } finally { r.prior.resolve(); await r.worker.close(); r.store.close(); }
});

test("a saved phone decision survives restart and follows the preceding station's last edit", async () => {
  const dir = mkdtempSync(join(tmpdir(), "phone-outbox-restart-")), path = join(dir, "stillfail.db");
  let store = Store.open(path), worker: CardOutcomeWorker | undefined, readers: Readers | undefined;
  const firstPrevious = Promise.withResolvers<void>(), nextPrevious = Promise.withResolvers<void>();
  let old: DatabaseSync | undefined;
  try {
    let db = store.db;
    const thread = store.openThread("ember", "CHAT", "phone", null, null).id;
    const message = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','old edit',?)");
    for (let n = 1; n <= 100; n++) message.run(thread, n, `other-${n}`, n);
    for (let n = 101; n <= 200; n++) edit.run(thread, n, n - 100, n);
    db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
      VALUES(?,201,'message','card','agent','agent','question',201,?)`)
      .run(thread, JSON.stringify({ type: "options", adb: { request: "p1", reason: "debug" } }));
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    installLegacyEdits(db); addClientColumn(db); installWidgetSources(db);
    worker = new CardOutcomeWorker(store, firstPrevious.promise, async () => ({ kind: "end" }), async () => ({ kind: "end" }));
    const hub = { store: { getSession: () => ({ ws: "work", archivedAt: null }),
      withdrawCard: store.withdrawCard.bind(store), restateCard: store.restateCard.bind(store), subscribe: () => {} }, notify: () => {} } as any;
    const grants = new PhoneGrants({ db, hub, cardOutcomes: worker, home: () => "work", title: () => null, now: () => 1_800_000_000_000 });
    const request = { id: "p1", session: "agent", chat: "chat", owner: "person@example.com", reason: "debug",
      at: 1_800_000_000, status: "pending", thread, cardTs: "card" };
    db.prepare("INSERT INTO adb_requests(id,session,owner,status,body) VALUES(?,?,?,?,?)")
      .run(request.id, request.session, request.owner, request.status, JSON.stringify(request));
    assert.equal(grants.decide(request.owner, request.id, "hour", "work"), null);
    await worker.close(); worker = undefined; store.close();

    store = Store.open(path); db = store.db;
    readers = new Readers(dir, 1, undefined, 1, { previousGone: nextPrevious.promise });
    worker = new CardOutcomeWorker(store, nextPrevious.promise,
      (t, target, before, signal) => readers!.cardEditPage(t, target, before, signal),
      (t, target, before, signal) => readers!.cardMessagePage(t, target, before, signal));
    old = new DatabaseSync(path, { timeout: 5000 });
    old.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,202,'edit',201,'agent','agent','previous station text',202,?)`)
      .run(thread, JSON.stringify({ type: "options", adb: { request: "p1", reason: "edited during handover" } }));
    assert.equal(cardOutcomeHeads(db, "0").length, 1);
    assert.equal(db.prepare("SELECT status FROM adb_requests WHERE id='p1'").get()?.status, "granted");
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(thread)?.n, 1);
    nextPrevious.resolve();
    await until(() => cardOutcomeHeads(db, "0").length === 0, 30_000);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(thread)!;
    assert.equal(last.text, "previous station text");
    assert.deepEqual(JSON.parse(String(last.card)).adb, { request: "p1", reason: "edited during handover", outcome: { status: "granted", scope: "hour" } });
  } finally {
    firstPrevious.resolve(); nextPrevious.resolve(); old?.close(); await worker?.close(); readers?.close(); store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
