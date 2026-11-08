// The MoonBit session backfill makes and fills the sessions' directory lookup (`installSessionDirectories`,
// `sessionDirectoriesStep`) and the chat shares' deadlines (`installChatShareIndex`, `chatShareIndexStep`) as the
// TypeScript does: the same schema, answers and rows, batch by batch, with sessions and shares written meanwhile,
// shares JavaScript would not read exactly kept uncertain as it keeps them.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { chatShareIndexStep, installChatShareIndex } from "../src/store/chat-share-index.ts";
import { installSessionDirectories, sessionDirectoriesStep } from "../src/store/session-directory.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const HOUR = 3_600_000;

/// Shares as stores keep them, plain and not: no `used`, `used` as a fraction or past 2^53, not JSON, not a list,
/// entries without a workspace, more than 16 targets, a deadline past 2^53, a blob.
const shares = (i: number): [unknown, number | bigint] => {
  const at = 1_700_000_000_000 + i;
  switch (i % 9) {
    case 0: return [JSON.stringify([{ workspace: `w${i}`, name: "W", used: at + HOUR }]), at];
    case 1: return [JSON.stringify([{ workspace: `w${i}` }, { workspace: "x", used: at }]), at];
    case 2: return [JSON.stringify([{ workspace: "w", used: 1.5 }]), at];
    case 3: return [JSON.stringify([{ workspace: "w", used: 2 ** 60 }]), at];
    case 4: return ["not json", at];
    case 5: return [JSON.stringify({ workspace: "w" }), at];
    case 6: return [JSON.stringify([null, 3, { name: "n" }, { workspace: "ok", used: 10 }]), at];
    case 7: return [JSON.stringify(Array.from({ length: 17 }, (_, k) => ({ workspace: `m${k}`, used: at }))), at];
    // (`used` from `at`, whose deadline is past 2^53)
    default: return [JSON.stringify([{ workspace: "w" }]), Number.MAX_SAFE_INTEGER - 5];
  }
};

/// A store of 300 sessions (workspaces, working directories) and 300 shared chats from before their lookups.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-session-lookups-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const prefix of ["session_dir", "chat_share_index", "chat_share"]) {
    for (const row of db.prepare(`SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE '${prefix}%'`).all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  }
  db.exec(`DROP TABLE IF EXISTS session_dir_meta; DROP TABLE IF EXISTS session_dir_rows; DROP TABLE IF EXISTS session_dir_dirty;
    DROP TABLE IF EXISTS chat_share_index_meta; DROP TABLE IF EXISTS chat_share_targets; DROP TABLE IF EXISTS chat_share_uncertain; DROP TABLE IF EXISTS chat_share_dirty`);
  db.exec("BEGIN");
  for (let i = 0; i < 300; i++) {
    const key = `s${String(i).padStart(3, "0")}`;
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: i % 5 === 0 ? "" : `/w/${i % 7}`, token: key, createdAt: 1, lastActiveAt: 1, ws: null });
    if (i % 3 === 0) db.prepare("UPDATE sessions SET cwd = ? WHERE key = ?").run(i % 2 ? `/c/${i}` : "", key);
    const [shared, at] = shares(i);
    db.prepare("INSERT INTO chat_shares(session,shared,write,by,at) VALUES (?,?,0,'a',?)").run(key, i === 8 ? Buffer.from("blob") : shared as string, at);
  }
  db.exec("COMMIT");
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db;
  if (n === 1) {
    db.exec("UPDATE sessions SET workspace = '/moved' WHERE key = 's001'");
    db.exec("UPDATE sessions SET cwd = '/late' WHERE key = 's290'");
    db.exec("DELETE FROM sessions WHERE key = 's002'");
    db.exec(`UPDATE chat_shares SET shared = '[{"workspace":"again","used":5}]' WHERE session IN ('s004', 's295')`);
    db.exec("DELETE FROM chat_shares WHERE session = 's010'");
    db.prepare("INSERT INTO chat_shares(session,shared,write,by,at) VALUES ('zz','[]',0,'a',1)").run();
  }
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store, prefixes: string[]): string {
  const db = store.db, like = prefixes.map((p) => `name LIKE '${p}%'`).join(" OR ");
  const schema = (db.prepare(`SELECT type, name, sql FROM sqlite_master WHERE (${like}) AND name NOT IN ('chat_shares') ORDER BY type, name`).all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND (${like}) AND name NOT IN ('chat_shares') ORDER BY name`).all() as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => (db.prepare(`SELECT * FROM ${name}`).all() as object[]).map((r) => JSON.stringify(r)).sort())]);
}

const kinds = [
  ["directory", (db: Store["db"]) => { installSessionDirectories(db); return sessionDirectoriesStep(db).done; }, ["session_dir"]],
  ["chat-share", (db: Store["db"]) => { installChatShareIndex(db); return chatShareIndexStep(db).done; }, ["chat_share"]],
] as const;

for (const [kind, step, prefixes] of kinds) {
  test(`the MoonBit session backfill makes and fills the ${kind} lookup as the TypeScript does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(), mb = old();
    const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
    try {
      let n = 0, done = false;
      for (; n < 30 && !done; n++) {
        writes(ts, n); writes(mb, n);
        const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ kind });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        assert.equal(ours.fallback, undefined);
        done = step(ts.store.db);
        assert.equal(ours.done, done, `batch ${n}`);
        assert.equal(tables(mb.store, [...prefixes]), tables(ts.store, [...prefixes]), `batch ${n}`);
      }
      assert.ok(done && n >= 5, `${n} batches`);
      if (kind === "chat-share") {
        const uncertain = (mb.store.db.prepare("SELECT COUNT(*) AS n FROM chat_share_uncertain").get() as { n: number }).n;
        assert.ok(uncertain > 100 && uncertain < 250, `${uncertain} uncertain`);
      }
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}
