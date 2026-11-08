// The MoonBit builder of the agents' post markers (station/mb, src/posts) marks an older store's requested chat suffix
// as `postBlocksStep` does: the same answers, markers and coverage, step by step, with messages written meanwhile.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { postBlocksStep } from "../src/store/post-blocks.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A store from before the markers' backfill (not fresh): two chats of 400 messages by people and three agents.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-post-blocks-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  const threads = ["a", "b"].map((key) => store.openThread("ember", "CHAT", key, null, null).id);
  db.exec("BEGIN");
  const put = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,?,?,?,?,'t',1)");
  for (const thread of threads) for (let n = -20; n < 380; n++) put.run(thread, n, n % 11 === 0 ? "edit" : "message", n % 3 === 0 ? "person" : "agent", `a${Math.abs(n) % 3}`);
  db.exec("COMMIT");
  db.exec("DELETE FROM post_blocks; DELETE FROM post_blocks_coverage; UPDATE post_blocks_meta SET fresh = 0");
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function writes(f: ReturnType<typeof old>, n: number) {
  const db = f.store.db, [a] = f.threads as [number];
  if (n === 1) {
    db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES (?,500,'message','agent','late','t',1)").run(a);
    db.prepare("UPDATE entries SET author = 'moved' WHERE thread = ? AND n = 370").run(a);
    db.prepare("DELETE FROM entries WHERE thread = ? AND n = 100").run(a);
  }
}

function tables(store: Store): string {
  return JSON.stringify([store.db.prepare("SELECT * FROM post_blocks ORDER BY thread, author, bucket").all(),
    store.db.prepare("SELECT * FROM post_blocks_coverage ORDER BY thread").all()]);
}

test("the MoonBit builder marks requested chat suffixes as postBlocksStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "post-blocks", "--db", mb.path]);
  try {
    let steps = 0;
    // a suffix from 200, then a longer one from -20 (the whole chat), then another chat's
    for (const [i, after] of [[0, 200], [0, -20], [1, 50]] as const) {
      const thread = ts.threads[i]!;
      let done = false;
      for (let n = 0; n < 20 && !done; n++, steps++) {
        writes(ts, steps); writes(mb, steps);
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ thread, after });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        done = postBlocksStep(ts.store.db, thread, after).done;
        assert.equal(ours.done, done, `chat ${thread} from ${after}, step ${n}`);
        assert.equal(tables(mb.store), tables(ts.store), `chat ${thread} from ${after}, step ${n}`);
      }
      assert.ok(done);
    }
    assert.ok(steps >= 10, `${steps} steps`);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});
