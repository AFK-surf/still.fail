import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";
import { PostBlockBuilder } from "../src/sessions/post-block-builder.ts";
import { installPostBlocks, postBlocksReady } from "../src/store/post-blocks.ts";
import { Store } from "../src/store/store.ts";

function fromBefore(store: Store): number {
  const thread = store.openThread("ember", "EMBER", "old", null, null).id;
  const put = store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message','agent',?,?,?)");
  store.db.exec("BEGIN");
  for (let n = 1; n <= 200; n++) put.run(thread, n, n === 180 ? "wanted" : "other", `m${n}`, n);
  store.db.exec("COMMIT");
  const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE name LIKE 'post_blocks%' AND type IN ('trigger', 'table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type)) {
    store.db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
  }
  installPostBlocks(store.db);
  return thread;
}

test("deliveries wait for the previous station and only index their requested suffix", async () => {
  const dir = mkdtempSync(join(tmpdir(), "post-builder-"));
  const store = Store.open(join(dir, "station.db"));
  const previous = Promise.withResolvers<void>();
  const builder = new PostBlockBuilder(store, previous.promise);
  try {
    const thread = fromBefore(store);
    assert.throws(() => store.postAfter("wanted", thread, 170), /not ready/);
    let finished = false;
    const waiting = builder.ready([{ thread, n: 170 }]).then(() => { finished = true; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(finished, false);
    assert.equal(postBlocksReady(store.db, thread, 170), false);
    previous.resolve();
    await waiting;
    assert.deepEqual(store.postAfter("wanted", thread, 170), { n: 180, ts: "m180" });
    assert.equal(postBlocksReady(store.db, thread, 100), false);
    assert.deepEqual({ ...store.db.prepare("SELECT cursor, complete FROM post_blocks_coverage WHERE thread = ?").get(thread) },
      { cursor: 137, complete: 0 });
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("concurrent requests share progress, and closing releases waiters", async () => {
  const store = Store.open(":memory:");
  const builder = new PostBlockBuilder(store, Promise.resolve());
  try {
    const thread = fromBefore(store);
    const short = builder.ready([{ thread, n: 190 }]);
    const long = builder.ready([{ thread, n: 0 }]);
    await short;
    assert.equal(postBlocksReady(store.db, thread, 190), true);
    assert.equal(postBlocksReady(store.db, thread, 0), false);
    await long;
    assert.deepEqual(store.postAfter("wanted", thread, 0), { n: 180, ts: "m180" });
  } finally { await builder.close(); store.close(); }

  const other = Store.open(":memory:");
  const previous = Promise.withResolvers<void>();
  const stopping = new PostBlockBuilder(other, previous.promise);
  try {
    const thread = fromBefore(other);
    const rejected = assert.rejects(stopping.ready([{ thread, n: 0 }]), /station stopping/);
    await stopping.close();
    await rejected;
  } finally { previous.resolve(); await stopping.close(); other.close(); }
});

test("a stopped post block worker retries the requested suffix", async () => {
  const dir = mkdtempSync(join(tmpdir(), "post-worker-retry-"));
  const store = Store.open(join(dir, "station.db"));
  const file = join(dir, "worker.mjs");
  const marker = join(dir, "exited");
  const real = new URL("../src/sessions/post-block-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new PostBlockBuilder(store, Promise.resolve(), pathToFileURL(file));
  try {
    const thread = fromBefore(store);
    await builder.ready([{ thread, n: 170 }]);
    assert.deepEqual(store.postAfter("wanted", thread, 170), { n: 180, ts: "m180" });
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
