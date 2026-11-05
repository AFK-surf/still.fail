import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { pathToFileURL } from "node:url";
import { test } from "node:test";
import { CardPostsBuilder } from "../src/read/card-posts-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { answersSince, makeStore, pendingCard } from "../src/read/store.ts";
import { cardPostsReady, installCardPosts } from "../src/store/card-post-index.ts";
import { Store } from "../src/store/store.ts";

function oldThreads(store: Store): [number, number] {
  const db = store.db;
  const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'card_post%' AND type IN ('trigger','table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type))
    db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
  const first = store.openThread("ember", "EMBER", "long", null, null).id;
  const second = store.openThread("ember", "EMBER", "short", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,at,card) VALUES(?,?,?,?,'agent','a',?,'{}')");
  db.exec("BEGIN");
  put.run(first, 1, "message", null, 1);
  for (let n = 2; n <= 513; n++) put.run(first, n, "edit", 1, n);
  put.run(second, 1, "message", null, 1);
  db.exec("COMMIT");
  installCardPosts(db);
  return [first, second];
}

test("card post preparation waits for handover and lets a short thread finish first", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-builder-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = new CardPostsBuilder(path, { previousGone: previous.promise });
  try {
    const [long, short] = oldThreads(store);
    let longReady = false;
    const one = builder.ready([long]).then(() => { longReady = true; });
    const two = builder.ready([short]);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(cardPostsReady(store.db, short), false);
    assert.equal(store.db.prepare("SELECT count(*) AS n FROM card_post_scopes").get()?.n, 0);
    previous.resolve();
    await two;
    assert.equal(cardPostsReady(store.db, short), true);
    assert.equal(longReady, false);
    await one;
    assert.equal(cardPostsReady(store.db, long), true);
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("cancelling one card post request leaves another waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-builder-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>(), cancel = new AbortController();
  const builder = new CardPostsBuilder(path, { previousGone: previous.promise });
  try {
    const [thread] = oldThreads(store);
    const stopped = builder.ready([thread], cancel.signal), kept = builder.ready([thread]);
    cancel.abort();
    await assert.rejects(stopped, /read cancelled/);
    previous.resolve();
    await kept;
    assert.equal(cardPostsReady(store.db, thread), true);
  } finally { cancel.abort(); previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped card post worker resumes the requested thread", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-worker-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const file = join(dir, "worker.mjs"), marker = join(dir, "exited");
  const real = new URL("../src/read/card-posts-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new CardPostsBuilder(path, {}, pathToFileURL(file));
  try {
    const [, thread] = oldThreads(store);
    await builder.ready([thread]);
    assert.ok(existsSync(marker));
    assert.equal(cardPostsReady(store.db, thread), true);
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a read asks for its old card threads together and keeps their original answers", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-read-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const builder = new CardPostsBuilder(path);
  try {
    const [first, second] = oldThreads(store);
    const person = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,1000,'message','person','p','yes',100)");
    person.run(first); person.run(second);
    const read = makeStore(store.db, dir);
    assert.throws(() => answersSince(read, 100, [first, second]), (error: Error) => {
      assert.match(error.message, /^card posts pending:/);
      assert.deepEqual(JSON.parse(error.message.slice("card posts pending:".length)), [first, second]);
      return true;
    });
    await builder.ready([first, second]);
    assert.deepEqual(answersSince(read, 100, [first, second]).map((a) => [a.question.thread, a.question.n, a.answer?.n]),
      [[first, 1, 1000], [second, 1, 1000]]);
    assert.equal(pendingCard(read, first), null);
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const operation of ["chats", "chatMarks"] as const) {
  test(`${operation} prepares the old cards it needs together and retries the read`, async () => {
    const dir = mkdtempSync(join(tmpdir(), "card-post-pages-"));
    const store = Store.open(join(dir, "stillfail.db"));
    const readers = new Readers(dir, 1);
    try {
      const threads = oldThreads(store);
      const sessions = threads.map((thread, i) => {
        const key = `s${i}`;
        store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
          token: key, createdAt: 1, lastActiveAt: 1 });
        store.joinThread(thread, key, "ember");
        return key;
      });
      // The cards predate the table that remembers a pending card.
      store.db.exec("DELETE FROM pending_cards; UPDATE pending_cards_from SET entry=(SELECT MAX(rowid) FROM entries)");
      const batches: number[][] = [];
      const prepare = readers.prepareCardPosts.bind(readers);
      readers.prepareCardPosts = (items, signal) => { batches.push([...items]); return prepare(items, signal); };
      const viewer = { sub: "me", email: "me", name: "Me", role: "owner", workspace: "w", device: "d" };
      const args = operation === "chats" ? { viewer, archived: false } : { viewer, scope: { sessions, threads } };
      const result = JSON.parse(await readers.read(operation, args, "en"));
      if (operation === "chats") {
        for (const thread of threads) assert.equal(result.find((row: any) => row.thread === thread)?.card?.seq, 1);
      } else {
        for (const thread of threads) assert.equal(result.card[thread]?.seq, 1);
      }
      assert.equal(batches.length, 1, "the list is prepared in one request");
      assert.deepEqual(new Set(batches[0]), new Set(threads));
    } finally { readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
  });
}

test("a card answer and its prepared posts are read from the same snapshot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-post-snapshot-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const builder = new CardPostsBuilder(path);
  let db: DatabaseSync | null = null;
  try {
    const [, thread] = oldThreads(store);
    await builder.ready([thread]);
    db = new DatabaseSync(path, { readOnly: true });
    const read = makeStore(db, dir);
    db.exec("BEGIN");
    assert.equal(cardPostsReady(db, thread), true);
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,at,card) VALUES(?,2,'message','agent','a',2,'{}')").run(thread);
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,3,'message','person','p','yes',3)").run(thread);
    assert.deepEqual(answersSince(read, 0, [thread]), []);
    db.exec("COMMIT");
    assert.deepEqual(answersSince(read, 0, [thread]).map((a) => [a.question.n, a.answer?.n]), [[2, 3]]);
  } finally { db?.close(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
