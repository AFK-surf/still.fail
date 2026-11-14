// The copies' work in memory that does not grow with what a station has (replica/export.ts `#fold`, restore.ts `build`):
// a copy of some 100 MB of messages exported, folded whole (a chat deleted) and taken back in a thread whose heap is a
// quarter of it; one holding a fold or a restore whole in memory fails there.
import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { Store } from "../src/store/store.ts";
import { HOME, ORIGIN, dataDir } from "./replica-fakes.ts";

const THREADS = 100;
const EACH = 960;
const TEXT = 1000;

test("a copy several times the export's heap is exported, folded whole and taken back within it", async () => {
  const data = dataDir("big");
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  store.insertSession({ key: "chat:big", connect: "chat", runtime: "claude", profile: "cc", workspace: "/w", token: "t-big", createdAt: 1, lastActiveAt: 1, ws: null });
  const put = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'p@x', ?, 1)");
  const words = "the quick brown fox jumps over the lazy dog ".repeat(Math.ceil(TEXT / 44)).slice(0, TEXT);
  store.db.exec("BEGIN");
  for (let t = 0; t < THREADS; t++) {
    const id = store.openThread("ember", "C", `big-${t}`, `Big ${t}`, null).id;
    store.joinThread(id, "chat:big", "chat");
    for (let n = 1; n <= EACH; n++) put.run(id, n, `${t}.${n} ${words}`);
  }
  store.db.exec("COMMIT");
  store.close();
  const to = dataDir("into");
  Store.open(join(to, "stillfail.db"), join(to, "archive")).close();
  const heapMb = 24;
  const said = await new Promise<any>((resolve, reject) => {
    const w = new Worker(new URL("./replica-heap-worker.ts", import.meta.url), { workerData: { data, to, origin: ORIGIN, home: HOME }, resourceLimits: { maxOldGenerationSizeMb: heapMb } });
    w.once("message", resolve);
    w.once("error", reject);
    w.once("exit", (code) => code !== 0 && reject(new Error(`the worker ended (${code})`)));
  });
  const raw = THREADS * EACH * TEXT;
  assert.ok(raw > 3 * heapMb * 1e6, "the copy is several times the heap");
  assert.ok(said.batches > 10, `${said.batches} batches of at most 1 MB`);
  assert.ok(said.foldedBatches > 10, "a whole fold writes several batches");
  assert.equal(said.messages, THREADS * EACH);
  assert.equal(said.rows.entries, THREADS * EACH, "every message taken back");
});
