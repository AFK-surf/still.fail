// The readers' one line (read/pool.ts): what the event streams tell goes before the pages asked, so a message just said
// is not held up behind them.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { Store } from "../src/store/store.ts";

test("a read the streams tell is answered before the pages asked before it", async () => {
  const data = mkdtempSync(join(tmpdir(), "reader-line-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const readers = new Readers(data, 1);
  try {
    const answered: string[] = [];
    // Reads no reader knows: each is answered (refused) in turn, in the order the one reader took them.
    const ask = (name: string, told = false) => readers.read(name, {}, "en", { told }).catch(() => void answered.push(name));
    await Promise.all([ask("taken"), ask("page 1"), ask("page 2"), ask("told", true), ask("page 3")]);
    assert.deepEqual(answered, ["taken", "told", "page 1", "page 2", "page 3"]);
  } finally {
    readers.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
