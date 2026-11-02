import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import type { FSWatcher } from "node:fs";
import { test } from "node:test";
import { FolderWatches } from "../src/drive/watch.ts";
import { testClock } from "./hub-fakes.ts";

test("folder changes wake a waiting client and are kept between asks", async () => {
  const time = testClock();
  const watcher = new EventEmitter() as FSWatcher;
  watcher.close = () => {};
  let opened = 0;
  const watches = new FolderWatches(1500, 5000, time.clock, () => { opened++; return watcher; });
  try {
    const first = watches.changed("/folder", "client");
    assert.equal(opened, 1);
    await time.begun(1);
    await time.adjust(1500);
    assert.equal(await first, false);

    const waiting = watches.changed("/folder", "client");
    const sleeps = time.asked();
    watcher.emit("change", "rename", "new-file");
    await time.begun(sleeps + 1);
    await time.adjust(250);
    assert.equal(await waiting, true);

    const before = time.asked();
    watcher.emit("change", "rename", "another-file");
    await time.begun(before + 1);
    await time.adjust(250);
    assert.equal(await watches.changed("/folder", "client"), true);
  } finally { watches.close(); }
});
