// The MoonBit builder of an old chat's letter-message keys (station/mb, src/letters) makes the shadow's tables and
// triggers as `installPageLetterIndex` does and fills it as `pageLetterStep` does: the same entries, batch by batch,
// with and without the letters' index, and changed in between, give the same answers and the same keys.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { pageLetterReady, pageLetterStep } from "../src/store/page-letter-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// Chats of 500 entries (messages with letters, messages without, and other entries with letters) and of 3.
function old(lose = false) {
  const dir = mkdtempSync(join(tmpdir(), "mb-page-letters-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,letter,ts,author_kind,author,text,at) VALUES(?,?,?,?,?,'agent','a','x',?)`);
  const threads = [500, 3].map((size, i) => {
    const thread = store.openThread("ember", "CHAT", `chat-${i}`, null, null).id;
    store.db.exec("BEGIN");
    for (let n = 1; n <= size; n++) put.run(thread, n, n % 4 === 0 ? "status" : "message", n % 3 === 0 ? null : "{}", `t${i}-${n}`, n);
    store.db.exec("COMMIT");
    return thread;
  });
  if (lose) store.db.exec("DROP INDEX entries_letters");
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const spaced = (sql: string | null) => (sql ?? "").replace(/\s+/g, " ").trim();
const schema = (store: Store) => JSON.stringify((store.db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'page_letter%' ORDER BY name").all() as { sql: string }[])
  .map((r) => ({ ...r, sql: spaced(r.sql) })));
const shadow = (store: Store) => JSON.stringify([
  store.db.prepare("SELECT s.thread, s.epoch, s.cursor_n, s.end_n, s.complete FROM page_letter_scopes s ORDER BY thread").all(),
  store.db.prepare("SELECT r.thread, r.n FROM page_letter_rows r ORDER BY thread, n").all(),
  store.db.prepare("SELECT d.thread, d.n FROM page_letter_dirty d ORDER BY thread, n").all(),
]);

for (const lose of [false, true]) {
  test(`the MoonBit builder fills the letter keys batch by batch as pageLetterStep does${lose ? ", without the letters' index" : ""}`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(lose), mb = old(lose);
    const builder = new MbProcess(binary!, ["--builder", "page-letters", "--db", mb.path]);
    try {
      const steps: { ts: boolean; mb: boolean }[] = [];
      for (const thread of mb.threads) {
        for (let k = 0; k < 20; k++) {
          const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
          builder.postMessage({ thread });
          const ours = await answered;
          assert.equal(ours.error, undefined);
          steps.push({ ts: pageLetterStep(ts.store.db, thread).done, mb: ours.done });
          // letters changed while the long chat is scanned: kept as dirty keys, then reconciled
          if (thread === mb.threads[0] && k === 2) for (const f of [ts, mb]) {
            f.store.db.prepare("UPDATE entries SET letter=NULL WHERE thread=? AND n=2").run(f.threads[0]);
            f.store.db.prepare("DELETE FROM entries WHERE thread=? AND n=5").run(f.threads[0]);
          }
          if (ours.done) break;
        }
      }
      assert.ok(steps.length >= 7, JSON.stringify(steps));
      assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
      assert.equal(schema(mb.store), schema(ts.store), "the same tables and marked triggers");
      assert.equal(shadow(mb.store), shadow(ts.store));
      for (const thread of mb.threads) assert.notEqual(pageLetterReady(mb.store.db, thread), null);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}

test("the station prepares the letter keys through the MoonBit builder", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const readers = new Readers(f.dir, 1);
  try {
    await readers.preparePageLetters(f.threads);
    for (const thread of f.threads) assert.notEqual(pageLetterReady(f.store.db, thread), null);
  } finally {
    readers.close();
    f.close();
  }
});
