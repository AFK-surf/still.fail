import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";
import { CardPostsBuilder } from "../src/read/card-posts-builder.ts";
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
