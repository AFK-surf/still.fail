// The real filesystem can deliver notifications late, so this belongs with the other external-timing tests.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { FolderWatches } from "../src/drive/watch.ts";

test("a real filesystem change wakes a folder watch", async () => {
  const dir = mkdtempSync(join(tmpdir(), "drive-watch-"));
  const watches = new FolderWatches();
  try {
    const waiting = watches.changed(dir, "client");
    writeFileSync(join(dir, "new-file"), "content");
    assert.equal(await waiting, true);
  } finally {
    watches.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
