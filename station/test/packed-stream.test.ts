import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { open } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { constants, zstdCompressSync } from "node:zlib";
import { seekTable, segmentsFrom } from "../src/read/packed.ts";
import { restoreFile } from "../src/sessions/archive.ts";

test("a search can stop inside an older single-frame archive without reading and expanding the whole frame", async () => {
  const dir = mkdtempSync(join(tmpdir(), "packed-stream-"));
  const path = join(dir, "history.zst");
  const original = randomBytes(4 << 20);
  const packed = zstdCompressSync(original);
  writeFileSync(path, Buffer.concat([packed, seekTable([{ packed: packed.length, size: original.length }])]));
  const file = await open(path, "r");
  const fileType = Object.getPrototypeOf(file);
  await file.close();
  const chunks = await segmentsFrom(path, 0);
  assert.ok(chunks);
  const read = fileType.read;
  let bytes = 0;
  fileType.read = async function (...args: any[]) {
    const result = await read.apply(this, args);
    bytes += result.bytesRead;
    return result;
  };
  try {
    const first = await chunks.next();
    if (first.done) assert.fail("the archive has a first piece");
    assert.ok(first.value.length <= 1 << 20, "the first decompressed piece is bounded");
    assert.deepEqual(first.value, original.subarray(0, first.value.length));
    assert.ok(bytes < packed.length, "stopping after the first piece need not read the rest of the frame");
  } finally {
    fileType.read = read;
    await chunks.return(undefined);
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a frame missing the end of its checksum is not accepted as a complete archive", async () => {
  const dir = mkdtempSync(join(tmpdir(), "packed-stream-"));
  const path = join(dir, "history.zst");
  const original = Buffer.from("the only copy of this history\n");
  const complete = zstdCompressSync(original, { params: { [constants.ZSTD_c_checksumFlag]: 1 } });
  const cut = complete.subarray(0, complete.length - 1);
  writeFileSync(path, Buffer.concat([cut, seekTable([{ packed: cut.length, size: original.length }])]));
  try {
    const chunks = await segmentsFrom(path, 0);
    assert.ok(chunks);
    await assert.rejects(async () => { for await (const _ of chunks) {} });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a truncated frame is not restored over the only copy of an execution history", async () => {
  const dir = mkdtempSync(join(tmpdir(), "packed-stream-"));
  const path = join(dir, "history.jsonl");
  const packedPath = `${path}.zst`;
  const original = Buffer.from('{"type":"user"}\n');
  const complete = zstdCompressSync(original, { params: { [constants.ZSTD_c_checksumFlag]: 1 } });
  const cut = complete.subarray(0, complete.length - 1);
  writeFileSync(packedPath, Buffer.concat([cut, seekTable([{ packed: cut.length, size: original.length }])]));
  try {
    await assert.rejects(restoreFile(path));
    assert.equal(existsSync(path), false);
    assert.equal(existsSync(packedPath), true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("streamed frames preserve offsets and detect a frame that ends early", async () => {
  const dir = mkdtempSync(join(tmpdir(), "packed-stream-"));
  const path = join(dir, "history.zst");
  const a = Buffer.from("first frame\n");
  const b = Buffer.from("second frame\n");
  const left = zstdCompressSync(a);
  const right = zstdCompressSync(b);
  const make = (secondSize: number) => writeFileSync(path, Buffer.concat([
    left, right, seekTable([{ packed: left.length, size: a.length }, { packed: right.length, size: secondSize }]),
  ]));
  const read = async (from: number) => {
    const chunks = await segmentsFrom(path, from);
    assert.ok(chunks);
    const got: Buffer[] = [];
    for await (const chunk of chunks) got.push(chunk);
    return Buffer.concat(got);
  };
  try {
    make(b.length);
    const whole = Buffer.concat([a, b]);
    for (const from of [0, 3, a.length, a.length + 2, whole.length]) {
      assert.deepEqual(await read(from), whole.subarray(from));
    }
    make(b.length + 1);
    await assert.rejects(read(0), /frame has the wrong size/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
