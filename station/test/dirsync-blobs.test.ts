import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdCompressSync } from "node:zlib";
import { blobId, putBlobs } from "../src/jobs/dirsync.ts";

test("interleaved pieces are verified in order, with other contents and retries", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dirsync-blobs-"));
  try {
    const a = Buffer.from("first content");
    const b = Buffer.from("second content");
    const ah = blobId(a), bh = blobId(b);
    const index = [[ah, a.length, 0, 5], [bh, b.length, 0, b.length], [ah, a.length, 5, a.length - 5]];
    const packed = zstdCompressSync(Buffer.concat([a.subarray(0, 5), b, a.subarray(5)]));
    assert.equal(await putBlobs(dir, index, packed), 3);
    assert.deepEqual(await readFile(join(dir, ah)), a);
    assert.deepEqual(await readFile(join(dir, bh)), b);
    assert.equal(await putBlobs(dir, index, packed), 3);
    assert.deepEqual((await readdir(dir)).sort(), [ah, bh].sort());
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("a bad content is refused and the request can be retried", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dirsync-blobs-"));
  try {
    const good = Array.from({ length: 20 }, (_, i) => Buffer.from(`content-${i}`));
    const wrong = Buffer.from("wrong");
    const expected = blobId(Buffer.from("right"));
    const index = [[expected, wrong.length, 0, wrong.length], ...good.map((b) => [blobId(b), b.length, 0, b.length])];
    await assert.rejects(putBlobs(dir, index, zstdCompressSync(Buffer.concat([wrong, ...good]))), /does not match its id/);
    assert.ok(!(await readdir(dir)).includes(`${expected}.part`));
    assert.ok((await readdir(dir)).every((name) => !name.endsWith(".part")));
    // A retry can complete all contents, including ones already written by the failed request.
    const right = Buffer.from("right");
    assert.equal(await putBlobs(dir, index, zstdCompressSync(Buffer.concat([right, ...good]))), index.length);
    assert.deepEqual(await readFile(join(dir, expected)), right);
    assert.equal((await readdir(dir)).length, index.length);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
