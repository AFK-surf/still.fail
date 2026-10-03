// What the Rust core kept (the Rust core's kept.rs storage chunks) is read into records on the first start.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Data } from "../src/data.ts";
import { CHUNK, readKept } from "../src/kept.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost } from "../src/testing.ts";
import { run } from "./run.ts";

const entry = (n: number) => ({ thread: 7, n, kind: "message", text: `m${n}` });

function rustKept(host: FakeHost) {
  // Thread 7 of `st/x` holds 250 ..= 300: chunk 0 (entries 1..=256) from 250, chunk 1 to 300.
  host.storage.set("kept", new TextEncoder().encode(JSON.stringify({
    "thread/st/x/7": { station: "st/x", opened: 1, chunks: { 0: 10, 1: 10 } },
    "transcript/st/x/k1": { station: "st/x", opened: 1, chunks: { 0: 10 } },
    "thread/st/x/8": { station: "st/x", opened: 1, chunks: { 0: 10 } },
  })));
  const put = (k: string, v: unknown) => host.storage.set(k, new TextEncoder().encode(JSON.stringify(v)));
  put("thread/st/x/7/meta", { first: 250, last: 300 });
  put("thread/st/x/7/0", Array.from({ length: CHUNK - 250 + 1 }, (_, i) => entry(250 + i)));
  put("thread/st/x/7/1", Array.from({ length: 300 - 257 + 1 }, (_, i) => entry(257 + i)));
  put("transcript/st/x/k1/meta", { first: 0, last: 2 });
  put("transcript/st/x/k1/0", [{ kind: "user" }, { kind: "assistant" }, { kind: "result" }]);
  // A chunk out of place (an entry not where the meta says): not read.
  put("thread/st/x/8/meta", { first: 1, last: 2 });
  put("thread/st/x/8/0", [entry(1), entry(5)]);
}

test("kept_chunks_become_records_once", async () => {
  const host = new FakeHost();
  rustKept(host);
  const runner = new Runner();
  const data = new Data(host, runner);
  await run(readKept(host, data));
  const thread = await run(data.log("entry", "st/x", "7"));
  assert.equal(thread.size, 51);
  assert.deepEqual(thread.get(250), entry(250));
  assert.deepEqual(thread.get(256), entry(256));
  assert.deepEqual(thread.get(300), entry(300));
  const transcript = await run(data.log("transcript", "st/x", "k1"));
  assert.deepEqual([...transcript.keys()], [0, 1, 2]);
  assert.equal((await run(data.log("entry", "st/x", "8"))).size, 0);
  await run(data.written);

  // The records are in the database; a second start reads nothing again (the storage is left as it was).
  const again = new Data(host, runner);
  assert.equal((await run(again.log("entry", "st/x", "7"))).size, 51);
  await run(again.forgetLog("entry", "st/x", "7"));
  await run(readKept(host, again));
  assert.equal(again.loaded("entry", "st/x", "7")?.size, 0);
  assert.ok(host.storage.has("thread/st/x/7/0"));
  runner.shutdown();
});
