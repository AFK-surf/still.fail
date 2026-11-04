import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { Store } from "../src/store/store.ts";
import { installSigninSaveIndex } from "../src/vault/signin-save-index.ts";

// The release's main.js loads and answers: a module importing createRequire as the bundle's banner did declared it
// twice, and every station updated to 0.1.7119 kept its old one (the new one exited with 1 before it was ready).
test("the station in a release starts", { skip: !process.env.STATION_BUNDLE }, () => {
  const data = mkdtempSync(join(tmpdir(), "station-bundle-main-"));
  try {
    const run = spawnSync(process.execPath, [join(process.env.STATION_BUNDLE!, "main.js"), "status", "--data", data], { encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
  } finally { rmSync(data, { recursive: true, force: true }); }
});

// The mac-build job calls this on the release it just laid out; the regular test suite has no release directory.
test("the workers in a station release start and process a batch", { skip: !process.env.STATION_BUNDLE }, async () => {
  const directory = mkdtempSync(join(tmpdir(), "station-bundle-workers-"));
  const path = join(directory, "station.db");
  const store = Store.open(path);
  try {
    store.db.exec(`CREATE TABLE signin_asks (id TEXT PRIMARY KEY, session TEXT NOT NULL, owner TEXT NOT NULL, status TEXT NOT NULL, body TEXT NOT NULL);
      CREATE INDEX signin_asks_by_session ON signin_asks (session, status);`);
    installSigninSaveIndex(store.db);
    const thread = store.openThread("ember", "EMBER", "old", null, null).id;
    store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,1,'message','agent','s','post',1)").run(thread);
    store.db.exec("UPDATE post_blocks_meta SET fresh = 0; DELETE FROM post_blocks");
    for (const [file, message] of [
      ["sessions/workspace-activity-worker.js", {}],
      ["sessions/post-block-worker.js", { thread, after: 0 }],
      ["outflow/chat-index-worker.js", "H"],
      ["vault/signin-save-worker.js", "s"],
    ] as const) {
      const worker = new Worker(join(process.env.STATION_BUNDLE!, file), { workerData: { path, priority: store.backfillPriority } });
      try {
        const result = new Promise<{ done: boolean; error?: string }>((resolve, reject) => {
          worker.once("message", resolve);
          worker.once("error", reject);
        });
        worker.postMessage(message);
        const answer = await result;
        assert.equal(answer.error, undefined, file);
        assert.equal(answer.done, true, file);
      } finally { await worker.terminate(); }
    }
    assert.deepEqual(store.postAfter("s", thread, 0), { n: 1, ts: "post" });
  } finally { store.close(); rmSync(directory, { recursive: true, force: true }); }
});
