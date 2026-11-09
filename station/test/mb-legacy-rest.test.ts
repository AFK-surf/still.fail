// The MoonBit session backfill keeps an older store's agent-message times (`legacyAgentMaintenanceStep`) and login
// cards (`legacyLoginCardsMaintenanceStep`) and reclaims orphaned page-letter scopes (`pageLetterGcStep`) as the
// TypeScript does: the same answers and tables, batch by batch, with an older writer changing entries meanwhile.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { installLegacyAgent, legacyAgentMaintenanceStep } from "../src/store/legacy-agent-build.ts";
import { installLegacyLoginCards, legacyLoginCardsMaintenanceStep } from "../src/store/legacy-login-cards.ts";
import { installPageLetterIndex, pageLetterGcStep } from "../src/store/page-letter-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A store of three chats of 120 entries: agents' and people's messages, some with login cards (folded case, a NUL,
/// tokens too long or not plain, one card of 150 tokens), from before these lookups, the lookups made over them.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-legacy-rest-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  const threads = ["a", "b", "c"].map((key) => store.openThread("ember", "CHAT", key, null, null).id);
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,ts,card) VALUES(?,?,'message',?,'x','t',?,?,?)");
  const card = (i: number) => i % 5 === 0 ? JSON.stringify({ type: "login", login: `user${i}` })
    : i % 5 === 1 ? `{"type":"login","LOGIN":"Mixed${i}","login":"ok${i}"}`
    : i % 5 === 2 ? `{"type":"login","login":"before${i}"}\u0000"login":"after${i}"`
    : i % 5 === 3 ? `{"type":"login","login":"${"x".repeat(41)}","login":"bad-${i}"}` : null;
  db.exec("BEGIN");
  for (const thread of threads) for (let n = 1; n <= 120; n++)
    put.run(thread, n, n % 3 === 0 ? "person" : "agent", n * 5, `ts-${n}`, card(n));
  put.run(threads[2], 121, "agent", 999, "ts-many", `{"type":"login",${Array.from({ length: 150 }, (_, i) => `"login":"t${i}"`).join(",")}}`);
  db.exec("COMMIT");
  installLegacyAgent(db);
  installLegacyLoginCards(db);
  installPageLetterIndex(db);
  // orphaned page-letter scopes: one of an older epoch, one already queued, each with more rows than a batch
  const epoch = (db.prepare("SELECT epoch FROM page_letter_meta WHERE id=1").get() as { epoch: number }).epoch;
  db.prepare("INSERT INTO page_letter_scopes(thread,token,epoch,cursor_n,end_n,complete) VALUES (?,?,?,NULL,NULL,1)").run(threads[0], "old", epoch - 1);
  db.prepare("INSERT INTO page_letter_garbage(thread,token) VALUES (?, 'gone')").run(threads[1]);
  for (const [thread, token] of [[threads[0], "old"], [threads[1], "gone"]] as const) for (let n = 1; n <= 100; n++) {
    db.prepare("INSERT INTO page_letter_rows(thread,token,n) VALUES (?,?,?)").run(thread, token, n);
    db.prepare("INSERT INTO page_letter_dirty(thread,token,n) VALUES (?,?,?)").run(thread, token, n);
  }
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db, [a, b] = f.threads as [number, number];
  if (n === 1) {
    db.prepare("UPDATE entries SET at = 7 WHERE thread = ? AND n = 2").run(a);
    db.prepare("UPDATE entries SET author_kind = 'person' WHERE thread = ? AND n = 4").run(a);
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at,card) VALUES(?,300,'message','agent','x','late',3000,'{\"login\":\"late\"}')").run(b);
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 10").run(b);
  }
  if (n === 3) for (let i = 1; i <= 80; i++) db.prepare("UPDATE entries SET at = at + 1 WHERE thread = ? AND n = ?").run(b, i);
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store, prefixes: string[]): string {
  const db = store.db, like = prefixes.map((p) => `name LIKE '${p}%'`).join(" OR ");
  const schema = (db.prepare(`SELECT type, name, sql FROM sqlite_master WHERE ${like} ORDER BY type, name`).all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND (${like}) ORDER BY name`).all() as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => (db.prepare(`SELECT * FROM ${name}`).all() as object[]).map((r) => JSON.stringify(r)).sort())]);
}

const kinds = [
  ["legacy-agent", legacyAgentMaintenanceStep, ["legacy_agent"]],
  ["legacy-login", legacyLoginCardsMaintenanceStep, ["login_card"]],
  ["page-letter-gc", (db: Store["db"]) => pageLetterGcStep(db), ["page_letter"]],
] as const;

for (const [kind, step, prefixes] of kinds) {
  test(`the MoonBit session backfill does ${kind} as the TypeScript does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(), mb = old();
    const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
    try {
      let n = 0, done = false;
      for (; n < 60 && !(done && n > 4); n++) {
        writes(ts, n); writes(mb, n);
        const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ kind });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        assert.equal(ours.fallback, undefined);
        done = step(ts.store.db).done;
        assert.equal(ours.done, done, `batch ${n}`);
        assert.equal(tables(mb.store, [...prefixes]), tables(ts.store, [...prefixes]), `batch ${n}`);
      }
      assert.ok(done && n >= 5, `${n} batches`);
      if (kind === "legacy-login") assert.ok((mb.store.db.prepare("SELECT COUNT(*) AS n FROM login_card_keys").get() as { n: number }).n > 150);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}
