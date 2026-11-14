// The MoonBit reader (station/mb, read/mb-reader.ts) answers what it has been moved to as the worker it replaces
// answers it: the same reads on the same database, step by step, give the same answers.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbReader, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import type { Answer, Ready } from "../src/read/worker.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// The checkpoints' answers on a database written and read the same way each time, by the reader `mb` names (the
/// MoonBit one's program, or none: the worker).
async function checkpoints(mb: string | null): Promise<unknown[]> {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-"));
  const path = join(data, "stillfail.db");
  const store = Store.open(path, join(data, "archive"));
  const readers = new Readers(data, 1);
  readers.mbReader = mb;
  const said: unknown[] = [];
  const checkpoint = async () => said.push(JSON.parse(await readers.read("checkpoint", {}, "en")));
  try {
    store.db.exec("CREATE TABLE filler (a TEXT)");
    const insert = store.db.prepare("INSERT INTO filler (a) VALUES (?)");
    // past the thousand pages at which SQLite would write the log into the database itself
    for (let i = 0; i < 1500; i++) insert.run("x".repeat(4000));
    await checkpoint();
    // nothing new: nothing to write
    await checkpoint();
    // a reader on a snapshot from before more was written: what it may still read stays in the log
    const other = new DatabaseSync(path, { readOnly: true });
    other.exec("BEGIN");
    other.prepare("SELECT COUNT(*) FROM filler").get();
    for (let i = 0; i < 20; i++) insert.run("y".repeat(4000));
    await checkpoint();
    other.exec("COMMIT");
    other.close();
    await checkpoint();
    return said;
  } finally {
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
}

test("the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)", () => {
  assert.notEqual(binary, null);
});

test("its checkpoints answer as the worker's, step by step", async () => {
  assert.notEqual(binary, null);
  const worker = await checkpoints(null);
  const moonbit = await checkpoints(binary);
  assert.deepEqual(moonbit, worker);
  // and they are checkpoints: all written, then nothing more (the same log, all of it in), then held back by the
  // reader, then the rest
  const [all, none, held, rest] = worker as { busy: number; log: number; checkpointed: number }[];
  assert.ok(all!.log >= 1500 && all!.checkpointed === all!.log, JSON.stringify(all));
  assert.deepEqual(none, all);
  assert.ok(held!.checkpointed < held!.log, JSON.stringify(held));
  assert.equal(rest!.checkpointed, rest!.log);
});

test("it says it is ready and answers what it has not been moved to with an error", async () => {
  assert.notEqual(binary, null);
  const data = mkdtempSync(join(tmpdir(), "mb-reader-"));
  const reader = new MbReader(binary!, data);
  try {
    const said: (Answer | Ready)[] = [];
    const next = () => new Promise<Answer | Ready>((resolve) => reader.once("message", resolve));
    said.push(await next());
    reader.postMessage({ id: 7, op: "noSuchRead", args: {}, lang: "en", names: [], processes: [], clientKeys: [] });
    said.push(await next());
    // no database there: the checkpoint fails as an error answered, and the reader goes on
    reader.postMessage({ id: 8, op: "checkpoint", args: {}, lang: "en", names: [], processes: [], clientKeys: [] });
    said.push(await next());
    assert.ok("ready" in said[0]!);
    assert.deepEqual(said[1], { id: 7, status: 500, error: "no read noSuchRead" });
    const failed = said[2] as Answer;
    assert.equal(failed.id, 8);
    assert.equal(failed.status, 500);
    assert.equal(typeof failed.error, "string");
  } finally {
    assert.equal(typeof await reader.terminate(), "number");
    rmSync(data, { recursive: true, force: true });
  }
});
