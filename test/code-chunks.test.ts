import assert from "node:assert/strict";
import { test } from "node:test";
import { codeChunks } from "../web/src/codeChunks.ts";
import { ink, runsOf } from "../client/core-ts/src/highlight.ts";

test("long code keeps every character and its colour across chunk boundaries", () => {
  const text = ('const sample = "你好 👋"; // comment\n').repeat(1200) + "x".repeat(3999) + "👋\n";
  const colours = ink(text, "typescript")!;
  const chunks = codeChunks(text, colours);
  assert(chunks.length > 20);
  assert.equal(chunks.map(c => c.text).join(""), text);
  const expand = (runs: [string, string][]) => runs.flatMap(([words, scope]) => Array(words.length).fill(scope));
  assert.deepEqual(expand(chunks.flatMap(c => c.runs)), expand(runsOf(text, colours)));
  for (const chunk of chunks) {
    assert.equal(chunk.runs.map(([words]) => words).join(""), chunk.text);
    assert(chunk.text.length <= 4001);
    assert(!/[\uD800-\uDBFF]$/.test(chunk.text), "an emoji is not split across text nodes");
  }
});
