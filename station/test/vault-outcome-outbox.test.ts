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
import { Store } from "../src/store/store.ts";
import { installWidgetSources } from "../src/store/widget-sources.ts";
import { PLAIN, PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";

async function until(check: () => boolean, timeout = 5000): Promise<void> {
  const end = Date.now() + timeout;
  while (!check()) {
    if (Date.now() >= end) throw new Error("timed out waiting for vault outcome");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function rig(typedSave = false, path = ":memory:") {
  const store = Store.open(path), db = store.db, thread = store.openThread("ember", "CHAT", "vault", null, null).id;
  const message = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,?,'message',?,'person','p','other',?)");
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'person','p','other edit',?)");
  for (let n = 1; n <= 100; n++) message.run(thread, n, `other-${n}`, n);
  for (let n = 101; n <= 200; n++) edit.run(thread, n, n - 100, n);
  db.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
    VALUES(?,201,'message','card','agent','agent','secret request',201,?)`)
    .run(thread, JSON.stringify({ type: "options", vault: { request: "r1", reason: "test" } }));
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  installLegacyEdits(db); addClientColumn(db); installWidgetSources(db); installCardOutbox(db);
  const prior = Promise.withResolvers<void>();
  const worker = new CardOutcomeWorker(store, prior.promise,
    async (t, target, before) => cardEditPage(db, t, target, before),
    async (t, target, before) => cardMessagePage(db, t, target, before));
  let beforeSave: (() => void) | undefined;
  const cardOutcomes = { save: (...args: Parameters<CardOutcomeWorker["save"]>) => {
    const before = beforeSave; beforeSave = undefined; before?.();
    return worker.save(...args);
  } };
  const hub = { store: { getSession: () => ({ archivedAt: null }),
    withdrawCard: store.withdrawCard.bind(store), restateCard: store.restateCard.bind(store), subscribe: () => {} }, notify: () => {} };
  const plain = new PlainStore(db), vaults = new VaultStore(db);
  const backfill = Promise.withResolvers<void>();
  const secrets = new Secrets({ db, hub, plain, vaults, cardOutcomes, proxy: {}, data: ".", now: () => 1_800_000_000_000,
    home: () => "work", lock: () => null, backfill: { previousGone: backfill.promise } } as any);
  const request = { id: "r1", ws: "work", vault: PLAIN, item: "i_01JAPLAIN000000000000000GH", session: "agent", chat: "chat", owner: "person@example.com",
    mode: "env", reason: "test", box: "", at: 1_800_000_000, status: "pending", ...(typedSave ? { save: { kind: "token", name: "test", modes: ["env"], hosts: [], typed: true } } : {}) };
  if (!typedSave) plain.put({ ws: request.ws, id: request.item, owner: request.owner, version: 0, kind: "token", name: "test",
    fields: { value: "private-value" }, notes: "", listing: { name: "test", kind: "token", modes: ["env"], hosts: [] }, at: request.at });
  db.prepare("INSERT INTO vault_requests(ws,id,session,status,body,thread,card_ts) VALUES(?,?,?,?,?,?,?)")
    .run(request.ws, request.id, request.session, request.status, JSON.stringify(request), thread, "card");
  const close = async () => { prior.resolve(); await worker.close(); secrets.keeper.drop(request.id); store.close(); };
  return { store, db, thread, prior, worker, secrets, plain, request, close, beforeSave: (f: () => void) => { beforeSave = f; } };
}

test("a vault denial closes its card and queues its outcome until handover", async () => {
  const r = rig();
  try {
    assert.equal(r.secrets.denyPlain(r.request.ws, r.request.owner, { request: r.request.id }), null);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "denied");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 1);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread=? AND n>201").get(r.thread)?.n, 0);
    assert.equal(cardOutcomeHeads(r.db, "0").length, 1);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).vault.outcome, { status: "denied" });
  } finally { await r.close(); }
});

test("a queued vault grant includes its timeout without its secret", async () => {
  const r = rig();
  try {
    assert.equal(r.secrets.grantPlain(r.request.ws, null, r.request.owner,
      { request: r.request.id, scope: "hour", timeout: { kind: "idle", seconds: 60 } }), null);
    const [head] = cardOutcomeHeads(r.db, "0");
    assert.deepEqual(head?.outcome, { status: "granted", scope: "hour", timeout: { kind: "idle", seconds: 60 } });
    assert.doesNotMatch(JSON.stringify(head), /private-value/);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).vault.outcome, { status: "granted", scope: "hour", timeout: { kind: "idle", seconds: 60 } });
  } finally { await r.close(); }
});

test("a failed vault grant queue does not leave a usable grant or a closed card", async () => {
  const r = rig();
  try {
    r.db.exec("CREATE TRIGGER fail_vault_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    assert.throws(() => r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" }), /queue failed/);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "pending");
    assert.equal(r.secrets.held(r.request.session).length, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM vault_grants").get()?.n, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    r.db.exec("DROP TRIGGER fail_vault_outcome");
    assert.equal(r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" }), null);
    assert.equal(r.secrets.held(r.request.session).length, 1);
    assert.doesNotMatch(JSON.stringify(cardOutcomeHeads(r.db, "0")), /private-value/);
  } finally { await r.close(); }
});

test("a wake failure after commit does not discard a granted vault secret", async () => {
  const r = rig();
  try {
    const wake = r.worker.wake.bind(r.worker);
    r.worker.wake = () => { throw new Error("wake failed"); };
    assert.equal(r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" }), null);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "granted");
    assert.equal(r.secrets.held(r.request.session).length, 1);
    assert.equal(cardOutcomeHeads(r.db, "0").length, 1);
    r.worker.wake = wake;
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
  } finally { await r.close(); }
});

test("a failed typed secret save can be retried without leaving an item or grant", async () => {
  const r = rig(true);
  try {
    r.db.exec("CREATE TRIGGER fail_vault_outcome BEFORE INSERT ON card_outbox BEGIN SELECT RAISE(ABORT,'queue failed'); END");
    assert.throws(() => r.secrets.savedPlain(r.request.ws, null, r.request.owner, { request: r.request.id, fields: { value: "private-value" } }), /queue failed/);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "pending");
    assert.equal(r.plain.item(r.request.ws, r.request.item) === null, true);
    assert.equal(r.secrets.held(r.request.session).length, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM vault_grants").get()?.n, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=?").get(r.thread)?.n, 0);
    r.db.exec("DROP TRIGGER fail_vault_outcome");
    assert.equal(typeof r.secrets.savedPlain(r.request.ws, null, r.request.owner, { request: r.request.id, fields: { value: "private-value" } }), "object");
    assert.equal(r.plain.item(r.request.ws, r.request.item)?.fields.value, "private-value");
    assert.doesNotMatch(JSON.stringify(cardOutcomeHeads(r.db, "0")), /private-value/);
  } finally { await r.close(); }
});

test("a competing decision before the write cannot leave an unauthorized grant", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-outcome-race-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    r.beforeSave(() => other.prepare("UPDATE vault_requests SET status='denied',body=? WHERE ws=? AND id=?")
      .run(JSON.stringify({ ...r.request, status: "denied" }), r.request.ws, r.request.id));
    assert.match(r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" })!, /denied/);
    assert.equal(r.secrets.held(r.request.session).length, 0);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "denied");
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { other.close(); await r.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an item removed before the decision is saved cannot be granted", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-item-race-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    r.beforeSave(() => {
      const item = r.plain.item(r.request.ws, r.request.item)!;
      new PlainStore(other).put({ ...item, version: item.version + 1, deleted: true });
    });
    assert.match(r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" })!, /changed|gone/);
    assert.equal(r.secrets.held(r.request.session).length, 0);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "pending");
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { other.close(); await r.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a request made live before expiration is still returned by pending", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-expire-race-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    const old = { ...r.request, at: r.request.at - 90000 };
    r.db.prepare("UPDATE vault_requests SET body=? WHERE ws=? AND id=?").run(JSON.stringify(old), r.request.ws, r.request.id);
    r.beforeSave(() => other.prepare("UPDATE vault_requests SET body=? WHERE ws=? AND id=?")
      .run(JSON.stringify(r.request), r.request.ws, r.request.id));
    const pending = r.secrets.pending(r.request.ws, null, { sub: "person", email: r.request.owner });
    assert.deepEqual(pending.map((request) => request.id), [r.request.id]);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "pending");
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { other.close(); await r.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a changed request is not reported as expired while reasking", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-reask-expire-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    const old = { ...r.request, at: r.request.at - 90000 };
    r.db.prepare("UPDATE vault_requests SET body=? WHERE ws=? AND id=?").run(JSON.stringify(old), r.request.ws, r.request.id);
    r.beforeSave(() => other.prepare("UPDATE vault_requests SET body=? WHERE ws=? AND id=?")
      .run(JSON.stringify(r.request), r.request.ws, r.request.id));
    await assert.rejects(r.secrets.reask(r.request.session, r.request.id), /changed.*try again/);
    assert.equal(r.db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "pending");
    assert.deepEqual(cardOutcomeHeads(r.db, "0"), []);
  } finally { other.close(); await r.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a card moved before the write receives the vault outcome", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-outcome-reissue-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), other = new DatabaseSync(path, { timeout: 5000 });
  try {
    r.beforeSave(() => {
      other.prepare(`INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card)
        VALUES(?,202,'message','new-card','agent','agent','secret request',202,?)`)
        .run(r.thread, JSON.stringify({ type: "options", vault: { request: "r1" } }));
      other.prepare("UPDATE vault_requests SET card_ts='new-card' WHERE ws=? AND id=?").run(r.request.ws, r.request.id);
    });
    assert.equal(r.secrets.grantPlain(r.request.ws, null, r.request.owner, { request: r.request.id, scope: "hour" }), null);
    assert.equal(cardOutcomeHeads(r.db, "0")[0]?.ts, "new-card");
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=201").get(r.thread)?.n, 0);
    assert.equal(r.db.prepare("SELECT COUNT(*) AS n FROM closed_cards WHERE thread=? AND n=202").get(r.thread)?.n, 1);
    r.prior.resolve();
    await until(() => cardOutcomeHeads(r.db, "0").length === 0);
    const last = r.db.prepare("SELECT card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.deepEqual(JSON.parse(String(last.card)).vault.outcome, { status: "granted", scope: "hour" });
  } finally { other.close(); await r.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a queued vault outcome survives restart and follows the previous station's edit", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-outcome-restart-")), path = join(dir, "stillfail.db");
  const r = rig(false, path), previous = Promise.withResolvers<void>();
  let store: Store | undefined, worker: CardOutcomeWorker | undefined, other: DatabaseSync | undefined;
  try {
    assert.equal(r.secrets.denyPlain(r.request.ws, r.request.owner, { request: r.request.id }), null);
    await r.worker.close(); r.secrets.keeper.drop(r.request.id); r.store.close();
    store = Store.open(path);
    const db = store.db;
    worker = new CardOutcomeWorker(store, previous.promise,
      async (t, target, before) => cardEditPage(db, t, target, before),
      async (t, target, before) => cardMessagePage(db, t, target, before));
    other = new DatabaseSync(path, { timeout: 5000 });
    other.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,card)
      VALUES(?,202,'edit',201,'agent','agent','previous station text',202,?)`)
      .run(r.thread, JSON.stringify({ type: "options", vault: { request: "r1", reason: "edited during handover" } }));
    assert.equal(db.prepare("SELECT status FROM vault_requests WHERE ws=? AND id=?").get(r.request.ws, r.request.id)?.status, "denied");
    assert.equal(cardOutcomeHeads(db, "0").length, 1);
    previous.resolve();
    await until(() => cardOutcomeHeads(db, "0").length === 0);
    const last = db.prepare("SELECT text,card FROM entries WHERE thread=? ORDER BY n DESC LIMIT 1").get(r.thread)!;
    assert.equal(last.text, "previous station text");
    assert.equal(JSON.parse(String(last.card)).vault.reason, "edited during handover");
    assert.deepEqual(JSON.parse(String(last.card)).vault.outcome, { status: "denied" });
  } finally {
    previous.resolve(); other?.close(); await worker?.close(); store?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
