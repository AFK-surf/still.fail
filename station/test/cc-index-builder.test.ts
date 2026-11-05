import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";
import { CcIndexBuilder } from "../src/read/cc-index-builder.ts";
import { ccSessionReady, installCcIndex } from "../src/store/cc-thread-index.ts";
import { Store } from "../src/store/store.ts";

function oldSessions(store: Store): void {
  const db = store.db;
  const thread = db.prepare("INSERT INTO threads(surface,channel,thread_ts,created_at) VALUES('slack:one','C',?,1)");
  const member = db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(?,?,'slack',1)");
  db.exec("BEGIN");
  for (let n = 0; n < 257; n++) {
    const id = thread.run(`long-${n}`).lastInsertRowid;
    member.run(id, "long");
  }
  member.run(thread.run("short").lastInsertRowid, "short");
  db.exec("COMMIT");
  installCcIndex(db);
}

test("copy destination preparation waits for handover and lets a short session finish first", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cc-index-builder-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = new CcIndexBuilder(path, { previousGone: previous.promise });
  try {
    oldSessions(store);
    let longReady = false;
    const one = builder.ready(["long"]).then(() => { longReady = true; });
    const two = builder.ready(["short"]);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(ccSessionReady(store.db, "short"), false);
    assert.equal(store.db.prepare("SELECT count(*) AS n FROM cc_sessions").get()?.n, 0);
    previous.resolve(); await two;
    assert.equal(ccSessionReady(store.db, "short"), true);
    assert.equal(longReady, false);
    await one;
    assert.equal(ccSessionReady(store.db, "long"), true);
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("cancelling one copy destination request leaves another waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cc-index-cancel-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>(), cancel = new AbortController();
  const builder = new CcIndexBuilder(path, { previousGone: previous.promise });
  try {
    oldSessions(store);
    const stopped = builder.ready(["short"], cancel.signal), kept = builder.ready(["short"]);
    cancel.abort(); await assert.rejects(stopped, /read cancelled/);
    previous.resolve(); await kept;
    assert.equal(ccSessionReady(store.db, "short"), true);
  } finally { cancel.abort(); previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped copy destination worker resumes its request", async () => {
  const dir = mkdtempSync(join(tmpdir(), "cc-index-worker-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const file = join(dir, "worker.mjs"), marker = join(dir, "exited");
  const real = new URL("../src/read/cc-index-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new CcIndexBuilder(path, {}, pathToFileURL(file));
  try {
    oldSessions(store);
    await builder.ready(["short"]);
    assert.ok(existsSync(marker));
    assert.equal(ccSessionReady(store.db, "short"), true);
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
