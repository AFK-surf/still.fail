// Lines (src/agents/runner.ts): whole lines of bytes that come a piece at a time, what a runner's connection and a
// station reading an output again after a crash both split with.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Lines } from "../src/agents/runner.ts";

/// The lines `text` gives split into pieces of `size`, as text.
function split(text: Buffer, size: number): string[] {
  const lines = new Lines();
  const out: string[] = [];
  for (let i = 0; i < text.length; i += size) for (const line of lines.take(text.subarray(i, i + size))) out.push(line.toString("utf8"));
  return out;
}

test("lines in order and whole across pieces of any size, empty ones too, what is not ended held back", () => {
  const long = "y".repeat(200_000);
  const text = Buffer.from(`a\n\nbé\n${long}\n\n\nlast\nnot ended`);
  const expected = ["a", "", "bé", long, "", "", "last"];
  for (const size of [1, 3, 7, 64 * 1024, text.length]) assert.deepEqual(split(text, size), expected, `pieces of ${size}`);
  // A line ending exactly at a piece's end, and a piece that is only its newline.
  const lines = new Lines();
  assert.deepEqual(lines.take(Buffer.from("ab\n")).map(String), ["ab"]);
  assert.deepEqual(lines.take(Buffer.from("cd")).map(String), []);
  assert.deepEqual(lines.take(Buffer.from("\n")).map(String), ["cd"]);
  assert.deepEqual(lines.take(Buffer.from("\n")).map(String), [""]);
  assert.deepEqual(lines.take(Buffer.alloc(0)).map(String), []);
  // What is held is let go of: the next line begins with the next piece.
  assert.deepEqual(lines.take(Buffer.from("cut ")).map(String), []);
  assert.deepEqual(lines.take(Buffer.from("sho")).map(String), []);
  lines.drop();
  assert.deepEqual(lines.take(Buffer.from("def\ng")).map(String), ["def"]);
  assert.deepEqual(lines.take(Buffer.from("h\n")).map(String), ["gh"]);
});

test("a long line is joined once: what it copies is its own size, not its square", (t) => {
  const real = Buffer.concat;
  let copied = 0;
  Buffer.concat = ((list: readonly Uint8Array[], length?: number) => {
    const joined = real(list, length);
    copied += joined.length;
    return joined;
  }) as typeof Buffer.concat;
  try {
    const line = Buffer.alloc(8 << 20, "x".charCodeAt(0));
    const lines = new Lines();
    const got: Buffer[] = [];
    for (let i = 0; i < line.length; i += 64 * 1024) got.push(...lines.take(line.subarray(i, i + 64 * 1024)));
    got.push(...lines.take(Buffer.from("\n")));
    assert.equal(got.length, 1);
    assert.ok(got[0]!.equals(line), "the line whole");
    t.diagnostic(`copied ${copied} bytes for a line of ${line.length}`);
    assert.ok(copied <= 2 * line.length, `copied ${copied} bytes for a line of ${line.length}`);
  } finally {
    Buffer.concat = real;
  }
});
