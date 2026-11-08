// The MoonBit program in the vault use reader's place (station/mb, src/vaultuses; vault/use-reader-mb.ts) prepares and
// reads as use-index-worker.ts does: step by step the same answers and the same lookups (exceptional bodies read as
// JavaScript reads them: duplicate keys, lone surrogates, NULs in keys, odd times), the pending lookup and the
// recovery lookup alike, and the same pages through `UseIndex`, for identities with lone surrogates too.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { backfillPendingPreparation, initializePendingIndex } from "../src/vault/pending-index.ts";
import { backfillReboxIndex, initializeReboxIndex } from "../src/vault/rebox-index.ts";
import { backfillNextWorkspace, backfillUsePreparation, initializeUseIndex, tryReadUses, UseIndex } from "../src/vault/use-index.ts";

const binary = mbReaderBinary();

const fields = [
  '"vault":"v","at":20', '"vault":"wrong","vault":"v","at":21', '"vault":"v","at":99,"at":19', '"vault":"v","vault":"wrong","at":100',
  '"vault":"v","save":{"typed":true},"save":null,"at":18', '"vault":"v","save":null,"save":{"typed":true},"at":101',
  '"vault":"\\ud800","at":3', '"vault":"plain","owner":"\\udc00@x","at":4', '"vault":"plain","owner":"a@x\\u0000y","at":5',
  '"vault":"v","k\\u0000":1,"at":6', '"vault":"v","at":{"b":1.5,"2":[true,null,1e21],"a":"x\\ud800"},"at":{"z":0.1,"10":-0}',
  '"vault":"v","at":true,"vault":"v"', '"vault":"v","at":"t\\udfff","at":"later"', '"vault":"plain","owner":"o@x","at":7',
  '"vault":"v","save":0,"at":8', '"vault":"v","save":"","at":9', '"vault":"plain","owner":"o@x","save":"s","at":10',
];

/// A store's vault requests (two workspaces, many of each kind, ordinary and exceptional, decided and pending), the
/// lookups made over them, none prepared.
function store() {
  const dir = mkdtempSync(join(tmpdir(), "mb-vault-uses-"));
  const path = join(dir, "stillfail.db");
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode = WAL; CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL, session TEXT NOT NULL,
    status TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY (ws,id));`);
  const put = db.prepare("INSERT INTO vault_requests VALUES(?,?,'s',?,?)");
  db.exec("BEGIN");
  for (const ws of ["w", "x"]) for (let i = 0; i < 120; i++) {
    const status = ["granted", "denied", "pending"][i % 3]!;
    put.run(ws, `r${String(i).padStart(3, "0")}`, status, `{"item":"${ws}${i}","session":"s","status":"${status}",${fields[i % fields.length]}}`);
  }
  db.exec("COMMIT");
  initializeUseIndex(db);
  initializePendingIndex(db);
  initializeReboxIndex(db);
  return { dir, path, db, put, close: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(db: DatabaseSync): string[] {
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'vault_%' AND name <> 'vault_requests' ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  return names.flatMap((name) => (db.prepare(`SELECT * FROM ${name}`).all() as Record<string, unknown>[])
    .map((r) => `${name} ${JSON.stringify(r, (_, v) => v instanceof Uint8Array ? `blob:${Buffer.from(v).toString("hex")}` : v)}`)).sort();
}

function same(ours: string[], theirs: string[], what: string) {
  const a = new Set(ours), b = new Set(theirs);
  assert.deepEqual({ ours: ours.filter((r) => !b.has(r)).slice(0, 4), theirs: theirs.filter((r) => !a.has(r)).slice(0, 4) }, { ours: [], theirs: [] }, what);
}

const reads = [
  { id: 1, ws: "w", vault: "v", owner: null, limit: 10 }, { id: 2, ws: "w", vault: "wrong", owner: null, limit: 5 },
  { id: 3, ws: "w", vault: "\ud800", owner: null, limit: 10 }, { id: 4, ws: "w", vault: "plain", owner: "\udc00@x", limit: 10 },
  { id: 5, ws: "w", vault: "plain", owner: "a@x\0y", limit: 10 }, { id: 6, ws: "x", vault: "plain", owner: "o@x", limit: 3 },
  { id: 7, ws: "x", vault: "v", owner: null, limit: 50 },
];

test("the MoonBit program prepares and reads the vault's uses, pending and recovery lookups as the TypeScript does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = store(), mb = store();
  const program = new MbProcess(binary!, ["--builder", "vault-uses", "--db", mb.path]);
  const ask = (op: string, q?: object) => new Promise<Record<string, unknown>>((resolve) => { program.once("message", resolve); program.postMessage({ op, ...(q ? { q } : {}) }); });
  try {
    // a workspace's uses, step by step, with a request written meanwhile
    let n = 0;
    for (let done = false; !done && n < 40; n++) {
      if (n === 2) for (const f of [ts, mb]) f.put.run("w", "r999", "granted", '{"item":"late","vault":"v","vault":"v","at":1}');
      const ours = await ask("prepare", reads[0]);
      assert.equal(ours.error, undefined);
      done = backfillUsePreparation(ts.db, "w");
      assert.equal(ours.complete, done, `uses step ${n}`);
      same(tables(mb.db), tables(ts.db), `uses step ${n}`);
    }
    assert.ok(n >= 4, `${n} steps`);
    // the pending lookup, the background workspaces and the recovery lookup
    for (const [op, step, q] of [
      ["prepare", () => backfillPendingPreparation(ts.db, "x", true, true), { kind: "pending", id: 9, ws: "x", members: true, audit: true }],
      ["uses", () => backfillNextWorkspace(ts.db), undefined],
      ["rebox", () => backfillReboxIndex(ts.db), undefined],
    ] as const) {
      let k = 0;
      for (let done = false; !done && k < 40; k++) {
        const ours = await ask(op, q);
        assert.equal(ours.error, undefined);
        done = step();
        assert.equal(op === "prepare" ? ours.complete : ours.done, done, `${op} step ${k}`);
        same(tables(mb.db), tables(ts.db), `${op} step ${k}`);
      }
      assert.ok(k >= 2, `${op}: ${k} steps`);
    }
    // the pages, as the reader reads them
    for (const q of reads) {
      const ours = await ask("ready", q);
      assert.deepEqual((ours.answered as { bodies?: string[] } | undefined)?.bodies ?? null, tryReadUses(ts.db, q), JSON.stringify(q));
    }
  } finally {
    await program.terminate();
    ts.close(); mb.close();
  }
});

test("UseIndex reads through the MoonBit program what it reads on its own", async () => {
  assert.notEqual(binary, null);
  const f = store(), mem = store();
  const index = new UseIndex(f.db);
  try {
    for (const q of reads) {
      const page = await index.read(q.ws, q.vault, q.owner, q.limit);
      while (!backfillUsePreparation(mem.db, q.ws)) { /* the same preparation on its own */ }
      assert.deepEqual(page, tryReadUses(mem.db, q), JSON.stringify(q));
    }
    await index.preparePending("w", true, true);
  } finally {
    await index.close();
    f.close(); mem.close();
  }
});
