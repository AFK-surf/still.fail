// The reader (station/mb) as built for this machine, run where the station's own tests do not run (Linux, Windows):
// the same writes on two databases, one checkpointed by the reader and one by Node's SQLite, give the same answers.
// Nothing of the station's is imported, so it runs from a checkout with no packages installed.
//   node station/mb/test/smoke.mjs PROGRAM
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { DatabaseSync } from "node:sqlite";

const program = process.argv[2];
if (!program) throw new Error("usage: node smoke.mjs PROGRAM");

/// A station's data directory whose database has rows written and the connection kept open (its log not written in).
function written(rows) {
  const data = mkdtempSync(join(tmpdir(), "mb-smoke-"));
  const db = new DatabaseSync(join(data, "stillfail.db"));
  db.exec("PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0; CREATE TABLE filler (a TEXT)");
  const insert = db.prepare("INSERT INTO filler (a) VALUES (?)");
  for (let i = 0; i < rows; i++) insert.run("x".repeat(4000));
  return { data, db };
}

const theirs = written(300);
const ours = written(300);
const reader = spawn(program, ["--data", ours.data], { stdio: ["pipe", "pipe", "inherit"] });
const lines = createInterface({ input: reader.stdout })[Symbol.asyncIterator]();
const next = async () => JSON.parse((await lines.next()).value);
try {
  assert.ok("ready" in (await next()), "it says it is ready");
  for (const id of [1, 2]) {
    reader.stdin.write(`${JSON.stringify({ id, op: "checkpoint", args: {}, lang: "en", names: [], processes: [], clientKeys: [] })}\n`);
    const answer = await next();
    const expected = theirs.db.prepare("PRAGMA wal_checkpoint(PASSIVE)").get();
    assert.deepEqual({ id: answer.id, ...JSON.parse(answer.text) }, { id, ...expected });
    console.log(`checkpoint ${id}: ${answer.text}`);
  }
  reader.stdin.write(`${JSON.stringify({ id: 3, op: "noSuchRead", args: {} })}\n`);
  assert.deepEqual(await next(), { id: 3, status: 500, error: "no read noSuchRead" });
  reader.stdin.end();
  const code = await new Promise((resolve) => reader.on("exit", resolve));
  assert.equal(code, 0, "it ends with its input");
  console.log("the reader answers as Node's SQLite does");
} finally {
  reader.kill();
  for (const { data, db } of [theirs, ours]) { db.close(); rmSync(data, { recursive: true, force: true }); }
}
