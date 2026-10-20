// `stillfail heap` (src/ops/heap.ts): the command asks, the station writes its heap snapshot (the owner's alone, the
// latest only) and says where; a request the station's watcher did not see is taken all the same.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, openSync, readSync, readdirSync, rmSync, statSync, closeSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { answerHeapRequests, heapCommand } from "../src/ops/heap.ts";

const snapshots = (dir: string) => readdirSync(dir).filter((n) => n.endsWith(".heapsnapshot"));

test("asked from the command line, the station writes its heap snapshot, only the latest kept, the owner's alone", async () => {
  const data = mkdtempSync(join(tmpdir(), "heap-"));
  const stop = answerHeapRequests(data);
  try {
    const run = join(data, "run");
    assert.equal(await heapCommand(data), 0);
    const [first] = snapshots(run);
    assert.ok(first, "a snapshot is there");
    const path = join(run, first!);
    assert.equal(statSync(path).mode & 0o777, 0o600);
    // A heap snapshot: JSON that starts with its meta.
    const head = Buffer.alloc(32);
    const fd = openSync(path, "r");
    readSync(fd, head, 0, 32, 0);
    closeSync(fd);
    assert.match(head.toString(), /^\{"snapshot":\{"meta"/);
    assert.equal(await heapCommand(data), 0);
    assert.equal(snapshots(run).length, 1, "the one before is gone");
    assert.ok(!existsSync(join(run, "heap.request")) && !existsSync(join(run, "heap.answer")), "nothing left of the asking");
  } finally {
    stop();
    rmSync(data, { recursive: true, force: true });
  }
});

test("asked before the station watched, the request is taken all the same", async () => {
  const data = mkdtempSync(join(tmpdir(), "heap-"));
  const asked = heapCommand(data);
  const stop = answerHeapRequests(data);
  try {
    assert.equal(await asked, 0);
    assert.equal(snapshots(join(data, "run")).length, 1);
  } finally {
    stop();
    rmSync(data, { recursive: true, force: true });
  }
});
