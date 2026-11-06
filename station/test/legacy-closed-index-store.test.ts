import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { ClosedCardsBuilder } from "../src/read/card-posts-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { answersSince, makeStore } from "../src/read/store.ts";
import { CLOSED_CARDS_PENDING, closedCardsReady, closedCardsStep } from "../src/store/legacy-closed-cards.ts";
import { Store } from "../src/store/store.ts";
import { referenceAnswersSince } from "./card-answer-reference.ts";

function oldStore(dir: string) {
  const path = join(dir, "stillfail.db"), initial = Store.open(path);
  const threads = ["first", "second"].map((key) => initial.openThread("ember", "CHAT", key, null, null).id);
  const card = JSON.stringify({ type: "text" });
  const entry = initial.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,?,'message','agent','a','choose',1,?)");
  const close = initial.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,?,?,?)");
  for (const thread of threads) {
    entry.run(thread,1,card); close.run(thread,1,"p",100);
    for (let n=2;n<=200;n++) close.run(thread,n,"p",n % 3);
  }
  initial.db.exec("DROP INDEX closed_cards_thread_at");
  initial.close();
  return { path, threads };
}

test("old prepared writes and read snapshots agree as requested chats are prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-store-"));
  const { path, threads } = oldStore(dir);
  const old = new DatabaseSync(path);
  const write = old.prepare("INSERT OR REPLACE INTO closed_cards(thread,n,viewer,at) VALUES(?,?,?,?)");
  const store = Store.open(path), builder = new ClosedCardsBuilder(path);
  let snapshot: DatabaseSync | null = null;
  try {
    const expected = referenceAnswersSince(store, 50);
    const read = makeStore(store.db, dir);
    assert.throws(() => answersSince(read, 50, threads), (error: Error) => {
      assert.match(error.message, /^closed cards pending:/);
      assert.deepEqual(JSON.parse(error.message.slice(CLOSED_CARDS_PENDING.length)), threads);
      return true;
    });
    const step = closedCardsStep(store.db, threads[0]!, 2);
    assert.deepEqual(step, { done: false, visited: 2 });
    write.run(threads[0]!, 1, "new-person", 125);
    write.run(threads[0]!, 201, "p", 110);
    await builder.ready(threads);
    assert.equal(closedCardsReady(store.db, threads[0]!), true);
    assert.deepEqual(answersSince(read, 50, threads), referenceAnswersSince(store, 50));
    assert.notDeepEqual(answersSince(read, 50, threads), expected);
    snapshot = new DatabaseSync(path, { readOnly: true });
    snapshot.exec("BEGIN");
    const snapRead = makeStore(snapshot, dir), before = answersSince(snapRead, 50, threads);
    write.run(threads[1]!, 1, "later", 150);
    assert.deepEqual(answersSince(snapRead, 50, threads), before);
    snapshot.exec("COMMIT");
    assert.deepEqual(answersSince(snapRead, 50, threads), referenceAnswersSince(store, 50));
  } finally { snapshot?.close(); await builder.close(); store.close(); old.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("handover, cancellation and a stopped worker preserve requested progress", async () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-worker-"));
  const { path, threads } = oldStore(dir), store = Store.open(path);
  const previous = Promise.withResolvers<void>(), abort = new AbortController();
  const worker = join(dir, "worker.mjs"), marker = join(dir, "stopped");
  const real = new URL("../src/read/card-posts-worker.ts", import.meta.url).href;
  writeFileSync(worker, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new ClosedCardsBuilder(path, { previousGone: previous.promise }, pathToFileURL(worker));
  try {
    const dropped = builder.ready([threads[0]!], abort.signal), kept = builder.ready([threads[0]!]);
    abort.abort();
    await assert.rejects(dropped, /read cancelled/);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(closedCardsReady(store.db, threads[0]!), false);
    previous.resolve();
    await kept;
    assert.equal(closedCardsReady(store.db, threads[0]!), true);
    assert.equal(closedCardsReady(store.db, threads[1]!), false);
  } finally { abort.abort(); previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the readers retry an old chat after its closed cards are prepared", async () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-reader-"));
  const { path, threads } = oldStore(dir), store = Store.open(path);
  const readers = new Readers(dir, 1);
  try {
    const sessions = threads.map((thread, i) => {
      const key = `s${i}`;
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
        token: key, createdAt: 1, lastActiveAt: 1 });
      store.joinThread(thread, key, "ember");
      return key;
    });
    const batches: number[][] = [];
    const prepare = readers.prepareClosedCards.bind(readers);
    readers.prepareClosedCards = (items, signal) => { batches.push([...items]); return prepare(items, signal); };
    const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" };
    await readers.read("chatMarks", { viewer, scope: { sessions, threads } }, "en");
    assert.equal(batches.length, 1);
    assert.deepEqual(new Set(batches[0]), new Set(threads));
    assert.ok(threads.every((thread) => closedCardsReady(store.db, thread)));
  } finally { readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a removed native index is prepared again instead of breaking a direct read", async () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-index-race-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path), other = new DatabaseSync(path);
  const builder = new ClosedCardsBuilder(path);
  try {
    const thread = store.openThread("ember", "CHAT", "index-race", null, null).id;
    const card = JSON.stringify({ type: "text" });
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,1,'message','agent','a','choose',1,?)").run(thread,card);
    store.db.prepare("INSERT INTO closed_cards VALUES(?,1,'p',100)").run(thread);
    let dropped = false;
    const traced = new Proxy(store.db, { get(target, key) {
      if (key !== "prepare") {
        const value = Reflect.get(target, key, target);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== "SELECT 1 FROM sqlite_master WHERE type=? AND name=?") return statement;
        return new Proxy(statement, { get(query, method) {
          if (method === "get") return (...args: any[]) => {
            const found = query.get(...args);
            if (!dropped && args[1] === "closed_cards_thread_at" && found) {
              dropped = true;
              other.exec("DROP INDEX closed_cards_thread_at");
            }
            return found;
          };
          const value = Reflect.get(query, method, query);
          return typeof value === "function" ? value.bind(query) : value;
        } });
      };
    } });
    assert.throws(() => answersSince(makeStore(traced, dir), 50, [thread]), /closed cards pending:/);
    await builder.ready([thread]);
    assert.deepEqual(answersSince(makeStore(store.db, dir), 50, [thread]), referenceAnswersSince(store, 50));
  } finally { await builder.close(); other.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a short old chat can answer without preparing its old closed cards", () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-short-"));
  const { path, threads } = oldStore(dir), store = Store.open(path);
  try {
    while (!closedCardsStep(store.db, threads[0]!).done) {}
    const thread = store.openThread("ember", "CHAT", "short", null, null).id;
    const card = JSON.stringify({ type: "text" });
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,1,'message','agent','a','choose',1,?)").run(thread,card);
    store.db.prepare("INSERT INTO closed_cards VALUES(?,1,'p',100)").run(thread);
    assert.deepEqual(answersSince(makeStore(store.db, dir), 50, [threads[0]!,thread]),
      referenceAnswersSince(store, 50).filter((a) => a.question.thread === threads[0] || a.question.thread === thread));
    assert.equal(store.db.prepare("SELECT 1 FROM legacy_closed_scopes WHERE thread=?").get(thread), undefined);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the old time index answers a sparse window without preparing a long chat", () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-sparse-"));
  const { path, threads } = oldStore(dir);
  const old = new DatabaseSync(path);
  old.exec("CREATE INDEX closed_cards_at ON closed_cards(at)");
  old.close();
  const store = Store.open(path);
  try {
    assert.deepEqual(answersSince(makeStore(store.db, dir), 50, threads), referenceAnswersSince(store, 50));
    assert.equal(store.db.prepare("SELECT count(*) AS n FROM legacy_closed_scopes").get()?.n, 0);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a short-chat probe keeps SQLite's time comparisons", () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-text-time-"));
  const { path } = oldStore(dir), store = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "text-time", null, null).id;
    const card = JSON.stringify({ type: "text" });
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,1,'message','agent','a','choose',1,?)").run(thread,card);
    store.db.prepare("INSERT INTO closed_cards VALUES(?,1,'p','later')").run(thread);
    const expected = referenceAnswersSince(store,50).filter((a) => a.question.thread === thread);
    assert.equal(expected.length, 1);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]), expected);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a short-chat probe does not decode an out-of-window 64-bit key", () => {
  const dir = mkdtempSync(join(tmpdir(), "closed-cards-int64-"));
  const { path } = oldStore(dir), store = Store.open(path);
  try {
    const thread = store.openThread("ember", "CHAT", "int64-old", null, null).id;
    store.db.prepare("INSERT INTO closed_cards VALUES(?,9223372036854775806,'p',0)").run(thread);
    assert.deepEqual(answersSince(makeStore(store.db,dir),50,[thread]), []);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
