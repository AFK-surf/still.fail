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
    // Written again until told: the system's watch starts a moment after it is asked for (FSEvents on macOS), and a write
    // before that is not one it sees (side run 41635377489). Told within the asking's hold, or it answers false.
    let told = false;
    void waiting.then(() => { told = true; });
    for (let i = 0; !told && i < 40; i++) {
      writeFileSync(join(dir, `new-file-${i}`), "content");
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    assert.equal(await waiting, true);
  } finally {
    watches.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
