// The MoonBit builder of the sessions' binding lookup (station/mb, src/bindings) copies the old bindings as
// `sessionBindingsStep` does: the same bindings, batch by batch, give the same answers and the same tables.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { SessionBindingsBuilder } from "../src/read/session-bindings-builder.ts";
import { installSessionBindingsIndex, sessionBindingsReady, sessionBindingsStep } from "../src/store/session-bindings-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose bindings are from before their lookup: 700 of them over 90 sessions, some with no
/// connection, some gone again (gaps), the lookup installed over them, nothing copied.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-bindings-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_binding_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_binding_rows; DROP TABLE session_binding_replaced; DROP TABLE session_binding_meta");
  const bind = db.prepare("INSERT INTO bindings(connect, session_key) VALUES (?, ?)");
  for (let i = 0; i < 700; i++) bind.run(i % 9 === 0 ? null : `connect-${i}`, `session-${i % 90}`);
  db.exec("DELETE FROM bindings WHERE rowid % 11 = 0");
  installSessionBindingsIndex(db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT session, binding_rowid, connect FROM session_binding_rows ORDER BY session, binding_rowid"),
    all("SELECT id, version, last_rowid, end_rowid, complete FROM session_binding_meta"),
  ].join("\n");
}

test("the MoonBit builder copies the old bindings batch by batch as sessionBindingsStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-bindings", "--db", mb.path]);
  try {
    const steps: { ts: boolean; mb: boolean }[] = [];
    for (let i = 0; i < 20; i++) {
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ scope: "all" });
      const ours = await answered;
      assert.equal(ours.error, undefined);
      steps.push({ ts: sessionBindingsStep(ts.store.db).done, mb: ours.done });
      if (ours.done) break;
    }
    assert.ok(steps.length >= 3, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(steps.at(-1)!.mb, true);
    assert.equal(tables(mb.store), tables(ts.store));
    assert.equal(sessionBindingsReady(mb.store.db), true);
    // asked again with nothing left, or asked what it does not build
    for (const [ask, answer] of [[{ scope: "all" }, { done: true }], [{ scope: "some" }, { done: false, error: "invalid session binding preparation request" }]] as const) {
      const again = new Promise((resolve) => builder.once("message", resolve));
      builder.postMessage(ask);
      assert.deepEqual(await again, answer);
    }
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's session binding builder finishes what it is asked", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new SessionBindingsBuilder(f.path, {});
  try {
    await builder.readyIndex();
    assert.equal(sessionBindingsReady(f.store.db), true);
    assert.equal((f.store.db.prepare("SELECT COUNT(*) AS n FROM session_binding_rows").get() as { n: number }).n,
      (f.store.db.prepare("SELECT COUNT(*) AS n FROM bindings").get() as { n: number }).n);
  } finally {
    await builder.close();
    f.close();
  }
});
