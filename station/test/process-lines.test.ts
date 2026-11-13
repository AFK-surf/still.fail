// linesBefore (src/agents/process.ts): the lines a station that crashed had handled, read a part at a time.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { linesBefore, linesWithin } from "../src/agents/process.ts";

/// What an async generator gives, all of it.
async function all<T>(lines: AsyncIterable<T>): Promise<T[]> {
  const out: T[] = [];
  for await (const line of lines) out.push(line);
  return out;
}

test("lines before a place, whole, across parts and longer than a part, without their \\r", async () => {
  const dir = mkdtempSync(join(tmpdir(), "lines-"));
  try {
    const file = join(dir, "x.out");
    const long = "x".repeat(50);
    const text = `a\nbé\r\n${long}\n\nlast\nnot yet acknowledged\n`;
    writeFileSync(file, text);
    const end = Buffer.byteLength(text) - "not yet acknowledged\n".length;
    for (const chunk of [1, 3, 7, 1 << 20]) assert.deepEqual(await all(linesBefore(file, end, chunk)), ["a", "bé", long, "", "last"], `parts of ${chunk}`);
    assert.deepEqual(await all(linesBefore(file, 0)), []);
    // From a place on (a line's start), each with where it begins.
    const from = Buffer.byteLength("a\nbé\r\n");
    for (const chunk of [1, 3, 7, 1 << 20]) assert.deepEqual(await all(linesWithin(file, from, end, chunk)), [{ text: long, at: from }, { text: "", at: from + 51 }, { text: "last", at: from + 52 }], `parts of ${chunk}`);
    assert.deepEqual(await all(linesWithin(file, end, end)), []);
    // What the runner gave back reads as zeros: skipped, with the line it cut, the lines after it read on.
    const holed = join(dir, "holed.out");
    const after = "cut short\nnext\n";
    const cut = "one\ntwo is cu";
    writeFileSync(holed, Buffer.concat([Buffer.from(cut), Buffer.alloc(40), Buffer.from(after)]));
    const holedEnd = cut.length + 40 + after.length;
    for (const chunk of [8, 16, 1 << 20]) {
      const got = await all(linesWithin(holed, 0, holedEnd, chunk));
      assert.deepEqual([got[0], got.at(-1)], [{ text: "one", at: 0 }, { text: "next", at: holedEnd - "next\n".length }], `parts of ${chunk}`);
      // Between them, at most what the hole cut (no JSON: passed over by whoever reads them).
      assert.ok(got.slice(1, -1).every((l) => l.text.endsWith("cut short") && l.text.length <= cut.length + 40 + 9), `parts of ${chunk}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a line longer than many parts is joined once: what it copies is its own size, not its square", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "lines-"));
  const real = Buffer.concat;
  let copied = 0;
  try {
    const file = join(dir, "long.out");
    const long = Buffer.alloc(8 << 20, "x".charCodeAt(0));
    writeFileSync(file, Buffer.concat([Buffer.from("a\n"), long, Buffer.from("\nb\n")]));
    Buffer.concat = ((list: readonly Uint8Array[], length?: number) => {
      const joined = real(list, length);
      copied += joined.length;
      return joined;
    }) as typeof Buffer.concat;
    const got = await all(linesWithin(file, 0, long.length + 5, 64 * 1024));
    Buffer.concat = real;
    assert.deepEqual(got.map((l) => [l.text.length, l.at]), [[1, 0], [long.length, 2], [1, long.length + 3]]);
    t.diagnostic(`copied ${copied} bytes for a line of ${long.length}`);
    assert.ok(copied <= 2 * long.length, `copied ${copied} bytes for a line of ${long.length}`);
  } finally {
    Buffer.concat = real;
    rmSync(dir, { recursive: true, force: true });
  }
});
