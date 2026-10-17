// linesBefore (src/agents/process.ts): the lines a station that crashed had handled, read a part at a time.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { linesBefore } from "../src/agents/process.ts";

test("lines before a place, whole, across parts and longer than a part, without their \\r", () => {
  const dir = mkdtempSync(join(tmpdir(), "lines-"));
  try {
    const file = join(dir, "x.out");
    const long = "x".repeat(50);
    const text = `a\nbé\r\n${long}\n\nlast\nnot yet acknowledged\n`;
    writeFileSync(file, text);
    const end = Buffer.byteLength(text) - "not yet acknowledged\n".length;
    for (const chunk of [1, 3, 7, 1 << 20]) assert.deepEqual([...linesBefore(file, end, chunk)], ["a", "bé", long, "", "last"], `parts of ${chunk}`);
    assert.deepEqual([...linesBefore(file, 0)], []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
