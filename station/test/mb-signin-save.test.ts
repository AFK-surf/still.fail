// The MoonBit builder of the sign-in lookup (station/mb, src/signin) indexes an older session's sign-ins as
// `stepSigninSaveIndex` does: the same answers, lookup and progress, batch by batch, with sign-ins added and changed
// behind and ahead of the cursor.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { installSigninSaveIndex, stepSigninSaveIndex } from "../src/vault/signin-save-index.ts";

const binary = mbReaderBinary();

/// A store's sign-ins: 300 of one session over three statuses (most naming a save), 100 of another, the lookup made
/// over them, none indexed.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-signin-save-"));
  const path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode = WAL;
    CREATE TABLE signin_asks (id TEXT PRIMARY KEY, session TEXT NOT NULL, owner TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL);
    CREATE INDEX signin_asks_by_session ON signin_asks (session, status);`);
  const put = db.prepare("INSERT INTO signin_asks (id, session, owner, status, body) VALUES (?, ?, 'p', ?, ?)");
  db.exec("BEGIN");
  for (let n = 0; n < 300; n++) put.run(`t${n}`, "target", ["done", "pending", "aaa"][n % 3]!, JSON.stringify(n % 5 === 0 ? { n } : n % 7 === 0 ? { save: 5 } : { save: `save-${n}` }));
  for (let n = 0; n < 100; n++) put.run(`o${n}`, "other", "done", JSON.stringify({ save: `o-${n}` }));
  db.exec("COMMIT");
  installSigninSaveIndex(db);
  return { dir, path, db, put, close: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  if (n === 1) {
    f.put.run("late", "target", "aaa", JSON.stringify({ save: "late" }));
    f.db.prepare("UPDATE signin_asks SET status = 'zzz', body = ? WHERE id = 't3'").run(JSON.stringify({ save: "moved" }));
    f.db.prepare("DELETE FROM signin_asks WHERE id = 't6'").run();
  }
}

const tables = (db: DatabaseSync) => JSON.stringify([db.prepare("SELECT * FROM signin_save_lookup ORDER BY ask").all(),
  db.prepare("SELECT * FROM signin_save_progress ORDER BY session").all()]);

test("the MoonBit builder indexes an older session's sign-ins as stepSigninSaveIndex does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "signin-save", "--db", mb.path]);
  try {
    let steps = 0;
    for (const session of ["target", "other"]) {
      let done = false;
      for (let n = 0; n < 20 && !done; n++, steps++) {
        writes(ts, steps); writes(mb, steps);
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage(session);
        const ours = await answered;
        assert.equal(ours.error, undefined);
        done = stepSigninSaveIndex(ts.db, session).done;
        assert.equal(ours.done, done, `${session} step ${n}`);
        assert.equal(tables(mb.db), tables(ts.db), `${session} step ${n}`);
      }
      assert.ok(done);
    }
    assert.ok(steps >= 7, `${steps} steps`);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});
