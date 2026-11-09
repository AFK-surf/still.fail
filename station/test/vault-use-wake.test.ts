import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MessageChannel, Worker } from "node:worker_threads";
import { backfillPendingPreparation, initializePendingIndex } from "../src/vault/pending-index.ts";
import { initializeReboxIndex } from "../src/vault/rebox-index.ts";
import { backfillUsePreparation, initializeUseIndex } from "../src/vault/use-index.ts";

test("ready use and pending reads do not wait for a paused background batch", async () => {
  const dir = mkdtempSync(join(tmpdir(), "vault-use-wake-")), path = join(dir, "station.db");
  const db = new DatabaseSync(path);
  let worker: Worker | null = null;
  try {
    db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE vault_requests (ws TEXT NOT NULL, id TEXT NOT NULL,
      session TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY (ws,id));`);
    db.prepare("INSERT INTO vault_requests VALUES('w','r','s','granted',?)")
      .run(JSON.stringify({ vault: "v", at: 1, item: "r" }));
    initializeUseIndex(db);
    initializePendingIndex(db);
    initializeReboxIndex(db);
    while (!backfillUsePreparation(db, "w")) {}
    while (!backfillPendingPreparation(db, "w", false, true)) {}
    const control = new MessageChannel();
    worker = new Worker(new URL("./vault-use-paused-worker.ts", import.meta.url),
      { workerData: { path, control: control.port2 }, transferList: [control.port2] });
    const [paused] = await once(worker, "message", { signal: AbortSignal.timeout(5000) }) as [{ paused?: boolean }];
    assert.equal(paused.paused, true);
    // An unrelated page still needs a backfill. It must not block this ready page or run while the timer is held.
    worker.postMessage({ id: 3, ws: "slow", vault: "v", owner: null, limit: 10 });
    worker.postMessage({ id: 1, ws: "w", vault: "v", owner: null, limit: 10 });
    const [use] = await once(worker, "message", { signal: AbortSignal.timeout(5000) }) as [{ id?: number; bodies?: string[] }];
    assert.equal(use.id, 1);
    assert.deepEqual(use.bodies!.map((b) => JSON.parse(b).item), ["r"]);
    worker.postMessage({ kind: "pending", id: 2, ws: "w", members: false, audit: true });
    const [pending] = await once(worker, "message", { signal: AbortSignal.timeout(5000) }) as [{ id?: number; ready?: boolean }];
    assert.deepEqual([pending.id, pending.ready], [2, true]);
    assert.equal(db.prepare("SELECT 1 FROM vault_use_backfill WHERE ws='slow'").get(), undefined);
    control.port1.postMessage("continue");
    const [slow] = await once(worker, "message", { signal: AbortSignal.timeout(5000) }) as [{ id?: number; bodies?: string[] }];
    assert.deepEqual([slow.id, slow.bodies], [3, []]);
    control.port1.close();
  } finally {
    if (worker !== null) await worker.terminate();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
