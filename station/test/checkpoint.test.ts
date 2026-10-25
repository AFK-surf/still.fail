// The store's log (the WAL) written into the database by a reader, not by the main connection (store.ts, read/pool.ts
// `checkpointSoon`, read/worker.ts `checkpoint`).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

test("the main connection leaves the log to the readers, and a reader writes it into the database", async () => {
  const data = mkdtempSync(join(tmpdir(), "checkpoint-"));
  const path = join(data, "stillfail.db");
  const store = Store.open(path, join(data, "archive"));
  const readers = new Readers(data, 1);
  try {
    const before = statSync(path).size;
    // Some 1,500 pages written, past the thousand at which SQLite writes the log into the database itself.
    store.db.exec("CREATE TABLE filler (a TEXT)");
    const insert = store.db.prepare("INSERT INTO filler (a) VALUES (?)");
    for (let i = 0; i < 1500; i++) insert.run("x".repeat(4000));
    assert.ok(statSync(path).size - before < 1000 * 4096, "the main connection wrote none of it into the database");
    const done = JSON.parse(await readers.read("checkpoint", {}, "en"));
    assert.equal(done.busy, 0);
    assert.ok(done.log >= 1500, JSON.stringify(done));
    assert.equal(done.checkpointed, done.log, "all of it");
    assert.ok(statSync(path).size - before >= 1500 * 4096, "now in the database");
    // Read by the main connection as before.
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM filler").get() as { n: number }).n, 1500);
  } finally {
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
