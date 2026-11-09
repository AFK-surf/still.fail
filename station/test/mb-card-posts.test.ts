// The MoonBit builder of the posts that carry a card or options (station/mb, src/cards) prepares an old thread as
// `cardPostsStep` does: the same entries, batch by batch and phase by phase, give the same answers and the same tables.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { CardPostsBuilder } from "../src/read/card-posts-builder.ts";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { cardPostsReady, cardPostsStep, installCardPosts } from "../src/store/card-post-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose entries are from before the card posts' index: a long thread of cards, options, both,
/// edits of them (which the cards' index holds too) and plain messages, and a short one; `lose` drops the options'
/// index, so the walk is by the primary key.
function old(lose = false) {
  const dir = mkdtempSync(join(tmpdir(), "mb-card-posts-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'card_post%' AND type IN ('trigger','table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type))
    db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
  const long = store.openThread("ember", "CHAT", "long", null, null).id;
  const short = store.openThread("ember", "CHAT", "short", null, null).id;
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,at,card,options) VALUES(?,?,?,?,'agent','a',?,?,?)");
  db.exec("BEGIN");
  for (let n = 1; n <= 700; n++) {
    const edit = n % 5 === 0;
    put.run(long, n, edit ? "edit" : "message", edit ? n - 1 : null, n,
      n % 3 === 0 ? "{}" : null, n % 4 === 0 ? '["yes","no"]' : null);
  }
  put.run(short, 1, "message", null, 1, "{}", null);
  db.exec("COMMIT");
  installCardPosts(db);
  if (lose) db.exec("DROP INDEX entries_options");
  return { dir, path, store, long, short, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT thread, n FROM card_posts ORDER BY thread, n"),
    all("SELECT thread, last_n, end_n, phase FROM card_post_scopes ORDER BY thread"),
  ].join("\n");
}

for (const lose of [false, true]) {
  test(`the MoonBit builder prepares an old thread's card posts as cardPostsStep does${lose ? ", by the primary key without the options' index" : ""}`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(lose), mb = old(lose);
    const builder = new MbProcess(binary!, ["--builder", "card-posts", "--db", mb.path]);
    try {
      const steps: { thread: number; ts: boolean; mb: boolean }[] = [];
      for (const thread of [mb.short, mb.long, 999]) {
        for (let i = 0; i < 20; i++) {
          const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
          builder.postMessage({ thread });
          const ours = await answered;
          assert.equal(ours.error, undefined);
          steps.push({ thread, ts: cardPostsStep(ts.store.db, thread).done, mb: ours.done });
          if (ours.done) break;
        }
      }
      assert.ok(steps.filter((s) => s.thread === mb.long).length >= 4, JSON.stringify(steps));
      assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
      assert.equal(tables(mb.store), tables(ts.store));
      assert.ok((mb.store.db.prepare("SELECT count(*) AS n FROM card_posts").get() as { n: number }).n > 200);
      for (const thread of [mb.short, mb.long]) assert.equal(cardPostsReady(mb.store.db, thread), true);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}

test("the station's card post builder finishes what it is asked", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new CardPostsBuilder(f.path, {});
  try {
    await builder.ready([f.long, f.short]);
    assert.equal(cardPostsReady(f.store.db, f.long), true);
    assert.equal(cardPostsReady(f.store.db, f.short), true);
  } finally {
    await builder.close();
    f.close();
  }
});
