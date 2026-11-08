// The MoonBit builder of an old chat's latest message (station/mb, src/archivelast) makes the guard's tables and
// triggers as `installArchiveLast` does and finds the message as `archiveLastStep` does: the same chats, slice by
// slice, give the same answers and guards, and the station reads the same answer through it.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { archiveLastKey, archiveLastRead, archiveLastStep } from "../src/store/archive-last.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// Chats whose latest message is behind a long tail of edits (700), a short one (3), none at all, and only edits.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-archive-last-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  const put = store.db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at,letter) VALUES(?,?,?,'person','me','x',?,?,?)`);
  const threads = [700, 3, 0, -1].map((tail, i) => {
    const thread = store.openThread("ember", "CHAT", `chat-${i}`, null, "me").id;
    store.db.exec("BEGIN");
    if (tail >= 0) put.run(thread, 1, "message", `m${i}`, 77 + i, null);
    for (let n = 2; n <= Math.max(tail, 3) + 1 && tail !== 0; n++) put.run(thread, n, "edit", `e${i}-${n}`, n, n % 3 === 0 ? "{}" : null);
    store.db.exec("COMMIT");
    return thread;
  });
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const spaced = (sql: string | null) => (sql ?? "").replace(/\s+/g, " ").trim();
const schema = (store: Store) => JSON.stringify((store.db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'archive_last%' ORDER BY name").all() as { sql: string }[])
  .map((r) => ({ ...r, sql: spaced(r.sql).replace(/ ?-- archive_last_v1 ?/, " ") })));
const guards = (store: Store) => JSON.stringify(store.db.prepare("SELECT thread, before_n, at, ready FROM archive_last_guard ORDER BY thread").all());

test("the MoonBit builder finds an old chat's latest message slice by slice as archiveLastStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "archive-last", "--db", mb.path]);
  try {
    const steps: { ts: boolean; mb: boolean }[] = [];
    for (const thread of mb.threads) {
      for (let k = 0; k < 20; k++) {
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ thread });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        steps.push({ ts: archiveLastStep(ts.store.db, thread).done, mb: ours.done });
        if (ours.done) break;
      }
    }
    assert.ok(steps.length >= 14, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(schema(mb.store), schema(ts.store), "the same tables and triggers, marked");
    assert.equal(guards(mb.store), guards(ts.store));
    for (const thread of mb.threads) {
      assert.deepEqual(archiveLastRead(mb.store.db, thread), archiveLastRead(ts.store.db, thread));
      assert.deepEqual(archiveLastKey(mb.store.db, thread), archiveLastKey(ts.store.db, thread));
    }
    assert.deepEqual(archiveLastRead(mb.store.db, mb.threads[0]!), { known: true, at: 77 });
    // a new message: its triggers drop the guard, and the builder finds the new one
    mb.store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,ts,at) VALUES(?,9000,'message','person','me','x','late',5000)").run(mb.threads[0]);
    assert.equal((mb.store.db.prepare("SELECT count(*) AS n FROM archive_last_guard WHERE thread=?").get(mb.threads[0]) as { n: number }).n, 0);
    assert.deepEqual(archiveLastRead(mb.store.db, mb.threads[0]!), { known: true, at: 5000 });
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station prepares the archive's last messages through the MoonBit builder", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const readers = new Readers(f.dir, 1);
  try {
    await readers.prepareArchiveLast(f.threads);
    for (const thread of f.threads) assert.equal(archiveLastRead(f.store.db, thread).known, true);
  } finally {
    readers.close();
    f.close();
  }
});
