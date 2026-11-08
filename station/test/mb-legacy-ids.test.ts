// The MoonBit session backfill copies an older store's id-keyed lookups as the TypeScript does: the archive policy
// (`archivePolicyIndexStep`), the decisions by time (`decisionTimeIndexStep`) and by session
// (`decisionSessionIndexStep`), and the session lookup's repair (`decisionSessionRepairStep`), including emptying an
// old repair table and making its index and triggers again: the same answers and tables, batch by batch.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { archivePolicyIndexStep, installArchivePolicyIndex } from "../src/store/archive-policy-index.ts";
import { decisionSessionIndexStep, decisionSessionRepairStep, installDecisionSessionIndex } from "../src/store/legacy-decision-session.ts";
import { decisionTimeIndexStep, installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

type Setup = "plain" | "repair" | "emptying";

/// A store of 300 policies and 300 decisions from before their lookups, the lookups made over them (`repair`: the
/// session lookup's index removed, so a repair is made beside it; `emptying`: the repair's index removed too, its
/// table to be emptied first).
function old(setup: Setup) {
  const dir = mkdtempSync(join(tmpdir(), "mb-legacy-ids-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  db.exec("DROP INDEX IF EXISTS archive_policy_by_ws; DROP INDEX IF EXISTS decision_checks_lately; DROP INDEX IF EXISTS decision_checks_session");
  db.exec("BEGIN");
  for (let i = 1; i <= 300; i++) {
    db.prepare("INSERT INTO archive_policy(id,at,policy,author,summary,ws) VALUES (?,?,?,?,?,?)").run(i, i, "p", "a", "s", i % 4 === 0 ? null : `w${i % 3}`);
    db.prepare("INSERT INTO decision_checks(id,session,created_at,result) VALUES (?,?,?,?)").run(i, `s${i % 9}`, i * 3, "r");
  }
  db.exec("COMMIT");
  installArchivePolicyIndex(db);
  installDecisionTimeIndex(db);
  installDecisionSessionIndex(db);
  if (setup !== "plain") {
    db.exec("DROP INDEX legacy_decision_session_by_session");
    installDecisionSessionIndex(db);
  }
  if (setup === "emptying") {
    db.prepare("INSERT INTO decision_checks(id,session,created_at,result) VALUES (500,'s1',1500,'r')").run();
    db.exec("INSERT INTO legacy_decision_session_repair(id,session) SELECT id, session FROM decision_checks WHERE id <= 150");
    db.exec("DROP INDEX legacy_decision_session_repair_by_session");
    installDecisionSessionIndex(db);
  }
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db;
  if (n === 1) {
    db.exec("INSERT INTO archive_policy(id,at,policy,author,summary,ws) VALUES (400,1,'p','a','s','late')");
    db.exec("UPDATE archive_policy SET ws = 'moved' WHERE id = 7");
    db.exec("DELETE FROM archive_policy WHERE id = 290");
    db.exec("INSERT INTO decision_checks(id,session,created_at,result) VALUES (400,'late',1,'r')");
    db.exec("UPDATE decision_checks SET session = 'moved' WHERE id IN (5, 295)");
    db.exec("DELETE FROM decision_checks WHERE id = 296");
  }
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(store: Store): string {
  const db = store.db;
  const schema = (db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE 'legacy_decision%' OR name LIKE 'archive_policy_lookup%' ORDER BY type, name").all() as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND (name LIKE 'legacy_decision%' OR name LIKE 'archive_policy_lookup%') ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => (db.prepare(`SELECT * FROM ${name}`).all() as object[]).map((r) => JSON.stringify(r)).sort())]);
}

const kinds = [
  ["legacy-policy", archivePolicyIndexStep, "plain"],
  ["legacy-decision-time", decisionTimeIndexStep, "plain"],
  ["legacy-decision-session", decisionSessionIndexStep, "plain"],
  ["legacy-decision-session-repair", decisionSessionRepairStep, "repair"],
  ["legacy-decision-session-repair", decisionSessionRepairStep, "emptying"],
] as const;

for (const [kind, step, setup] of kinds) {
  test(`the MoonBit session backfill prepares ${kind}${setup === "emptying" ? " after emptying its old table" : ""} as the TypeScript does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(setup), mb = old(setup);
    const builder = new MbProcess(binary!, ["--builder", "session-backfill", "--db", mb.path]);
    try {
      assert.equal(tables(mb.store), tables(ts.store));
      let n = 0, done = false;
      for (; n < 30 && !done; n++) {
        writes(ts, n); writes(mb, n);
        const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ kind });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        assert.equal(ours.fallback, undefined);
        done = step(ts.store.db).done;
        assert.equal(ours.done, done, `batch ${n}`);
        assert.equal(tables(mb.store), tables(ts.store), `batch ${n}`);
      }
      assert.ok(done && n >= (setup === "emptying" ? 7 : 5), `${n} batches`);
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}
