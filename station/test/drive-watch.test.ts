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

test("a followed folder tells each burst of changes once, and once more when it goes, until it is let go", async () => {
  const time = testClock();
  const watcher = new EventEmitter() as FSWatcher;
  let closed = 0;
  watcher.close = () => void closed++;
  const watches = new FolderWatches(1500, 5000, time.clock, () => watcher);
  try {
    let told = 0;
    const stop = watches.follow("/folder", () => void told++)!;
    assert.notEqual(stop, null);
    const before = time.asked();
    watcher.emit("change", "rename", "a");
    watcher.emit("change", "change", "a");
    await time.begun(before + 1);
    await time.adjust(250);
    assert.equal(told, 1, "a burst is one change");
    // Nothing more is told while nothing changes, however long it is followed.
    await time.adjust(60_000);
    assert.equal(told, 1);
    watcher.emit("error", new Error("gone"));
    assert.equal(told, 2, "gone is told");
    stop();
    assert.ok(closed >= 1);
  } finally { watches.close(); }
});
