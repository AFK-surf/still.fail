// The MoonBit builder of the sidebar's said state (station/mb, src/said) finds the latest message not by the latest
// person as `saidScanStep` does, asking for the backfill permit only when it writes: the same chats, slice by slice,
// give the same answers and states, also when the chat changes in the middle of a search; a store read through the
// legacy lookup is left to the worker.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { SaidBuilder } from "../src/read/said-builder.ts";
import { saidScanStep, type SaidScan } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// Chats whose said state is from before it was kept: each an agent's message, then `length - 1` of one person's.
function old(lengths: number[]) {
  const dir = mkdtempSync(join(tmpdir(), "mb-said-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  const threads = lengths.map((length, i) => {
    const key = `s${i}`;
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "CHAT", `chat${i}`, null, null).id;
    store.joinThread(thread, key, "ember");
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,?,'message',?,?,?,?)");
    store.db.exec("BEGIN");
    put.run(thread, 1, "agent", key, `first-${i}`, 1);
    for (let n = 2; n <= length; n++) put.run(thread, n, "person", "me", `t${i}-${n}`, n);
    store.db.exec("COMMIT");
    store.db.prepare("UPDATE thread_state SET said_other_known=0 WHERE thread=?").run(thread);
    return thread;
  });
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

const states = (store: Store) => JSON.stringify([
  store.db.prepare("SELECT thread, said_n, said_other_n, said_other_known FROM thread_state ORDER BY thread").all(),
  store.db.prepare("SELECT thread, author, other_n, ready FROM said_state_guard ORDER BY thread").all(),
]);

function asker(builder: MbProcess, permit: () => boolean) {
  return (message: Record<string, unknown>) => new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => {
    const on = (line: { take?: boolean; give?: boolean }) => {
      if (line.take) return void builder.postMessage({ permit: permit() });
      if (line.give) return;
      builder.off("message", on);
      resolve(line as { done: boolean });
    };
    builder.on("message", on);
    builder.postMessage(message);
  });
}

test("the MoonBit builder finds the said state slice by slice as saidScanStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const lengths = [300, 3, 1, 70];
  const ts = old(lengths), mb = old(lengths);
  const builder = new MbProcess(binary!, ["--builder", "said", "--db", mb.path]);
  const ask = asker(builder, () => true);
  try {
    const steps: { thread: number; ts: boolean; mb: boolean }[] = [];
    for (const [i, thread] of mb.threads.entries()) {
      let scan: SaidScan | null = null;
      for (let k = 0; k < 20; k++) {
        const ours = await ask({ thread });
        assert.equal(ours.error, undefined);
        const theirs = saidScanStep(ts.store.db, thread, scan);
        scan = theirs.scan;
        steps.push({ thread, ts: theirs.done, mb: ours.done });
        // the person writes again in the middle of the long search, in both: the search starts over
        if (i === 0 && k === 2) for (const f of [ts, mb])
          f.store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,ts,at) VALUES (?,301,'message','person','me','late',301)").run(f.threads[0]);
        if (ours.done) break;
      }
    }
    assert.ok(steps.length >= 8, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(states(mb.store), states(ts.store));
    assert.equal((mb.store.db.prepare("SELECT said_other_n FROM thread_state WHERE thread=?").get(mb.threads[0]) as { said_other_n: number }).said_other_n, 1);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("a store read through the legacy lookup is left to the worker", async () => {
  assert.notEqual(binary, null);
  const f = old([5]);
  f.store.db.exec("CREATE VIEW legacy_said AS SELECT 1 AS n");
  const builder = new MbProcess(binary!, ["--builder", "said", "--db", f.path]);
  try {
    assert.deepEqual(await asker(builder, () => true)({ thread: f.threads[0] }), { fallback: true });
  } finally {
    await builder.terminate();
    f.close();
  }
});

test("the station's said builder finds what it is asked, the pool giving the permit", async () => {
  assert.notEqual(binary, null);
  const f = old([200, 4]);
  const priority = new SharedArrayBuffer(8);
  const builder = new SaidBuilder(f.path, { priority });
  try {
    await builder.ready(f.threads);
    for (const thread of f.threads)
      assert.equal((f.store.db.prepare("SELECT said_other_known FROM thread_state WHERE thread=?").get(thread) as { said_other_known: number }).said_other_known, 1);
    assert.equal(Atomics.load(new Int32Array(priority), 1), 0, "the permit given back");
  } finally {
    await builder.close();
    f.close();
  }
});
