// The MoonBit session backfill names sandboxes as agents/sandbox-name.ts does (a hash of each session's key) and keeps
// their reverse lookup as `enableSandboxIndex`, `disableSandboxIndex` and `sandboxIndexStep` do: the same schema,
// answers and rows, batch by batch, for keys of every kind, with sessions written meanwhile and the lookup switched off
// and on again.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { disableSandboxIndex, enableSandboxIndex, sandboxIndexStep } from "../src/store/sandbox-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// Keys plain, long, with spaces and symbols, non-ASCII letters, emoji, the Kelvin sign and İ.
const key = (i: number) => [`plain-${i}`, `CHAT/1794127491.${i}`, `a very long session key number ${i} with spaces`,
  `${i}::über/ß`, `emoji-${i}-😀`, `K${i}İ`, `-_-${i}`, `${"x".repeat(30)}${i}`][i % 8]!;

function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-sandbox-names-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sandbox_name_%'").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE IF EXISTS sandbox_name_meta; DROP TABLE IF EXISTS sandbox_name_rows; DROP TABLE IF EXISTS sandbox_name_dirty");
  db.exec("BEGIN");
  for (let i = 0; i < 300; i++) store.insertSession({ key: key(i), connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: `t${i}`, createdAt: 1, lastActiveAt: 1, ws: null });
  db.exec("COMMIT");
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db;
  if (n === 1) {
    db.prepare("UPDATE sessions SET key = 'renamed-Ω' WHERE key = ?").run(key(3));
    db.prepare("DELETE FROM sessions WHERE key = ?").run(key(299));
    f.store.insertSession({ key: "late 😀 key", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "late", createdAt: 1, lastActiveAt: 1, ws: null });
  }
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store): string {
  const db = store.db;
  const schema = (db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'sandbox_name%' ORDER BY type, name").all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  return JSON.stringify([schema, db.prepare("SELECT session, name FROM sandbox_name_rows ORDER BY session").all(),
    db.prepare("SELECT session FROM sandbox_name_dirty ORDER BY session").all(),
    db.prepare("SELECT version, enabled, phase, cursor, prune, end_session, end_prune FROM sandbox_name_meta").all()]);
}

test("the MoonBit session backfill names sandboxes and keeps their lookup as the TypeScript does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
  const ask = async (kind: string) => {
    const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
    builder.postMessage({ kind });
    const ours = await answered;
    assert.equal(ours.error, undefined);
    assert.equal(ours.fallback, undefined);
    return ours.done;
  };
  const settle = async (change: (f: ReturnType<typeof old>, n: number) => void) => {
    let n = 0, done = false;
    for (; n < 30 && !done; n++) {
      change(ts, n); change(mb, n);
      const ours = await ask("sandbox");
      enableSandboxIndex(ts.store.db);
      done = sandboxIndexStep(ts.store.db).done;
      assert.equal(ours, done, `batch ${n}`);
      assert.equal(tables(mb.store), tables(ts.store), `batch ${n}`);
    }
    assert.ok(done, `${n} batches`);
    return n;
  };
  try {
    assert.ok(await settle(writes) >= 5);
    // switched off, changed while off (nothing journaled), switched on: every key checked again, gone ones pruned
    assert.equal(await ask("sandbox-off"), true);
    disableSandboxIndex(ts.store.db);
    assert.equal(tables(mb.store), tables(ts.store));
    for (const f of [ts, mb]) {
      f.store.db.prepare("DELETE FROM sessions WHERE key IN (?, ?)").run(key(10), key(20));
      f.store.insertSession({ key: "while off", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "off", createdAt: 1, lastActiveAt: 1, ws: null });
    }
    assert.ok(await settle(() => {}) >= 5);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});
