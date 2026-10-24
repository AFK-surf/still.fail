// Reading transcripts as they grow (src/read/tail.ts), and what a reader keeps read in brief for the pages of a history
// (src/read/transcripts.ts).
import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { PIECE, TranscriptTail } from "../src/read/tail.ts";
import { brief, readTimeline } from "../src/read/transcript.ts";
import { KEPT_ENTRIES, forgetKept, inBrief, keptNow } from "../src/read/transcripts.ts";

const temp = () => mkdtempSync(join(tmpdir(), "transcripts-"));
const said = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-24T00:00:00Z", message: { id, content: [{ type: "text", text }], usage: { input_tokens: 1, output_tokens: 1 } } })}\n`;
const call = (id: string, command: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-10-24T00:00:00Z", message: { id, content: [{ type: "tool_use", id, name: "Bash", input: { command, description: `Step ${id}` } }] } })}\n`;

test("a transcript longer than a piece is read a piece at a time, as one read from its start reads it", () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  // Lines of uneven length, so pieces end inside lines; some longer than what a brief keeps.
  const lines: string[] = [];
  let bytes = 0;
  for (let i = 0; bytes < PIECE * 2 + 12345; i++) {
    const line = i % 3 === 0 ? call(`c${i}`, `echo ${"x".repeat(i % 2000)}`) : said(`${i} ${"y".repeat((i * 37) % 5000)}`, `m${i}`);
    lines.push(line);
    bytes += Buffer.byteLength(line);
  }
  writeFileSync(path, lines.join(""));
  const tail = new TranscriptTail("claude", path);
  const [start, entries] = tail.read();
  assert.equal(start, 0);
  assert.deepEqual(entries.map((e) => e.text), readTimeline("claude", path).map((e) => e.text));
  assert.equal(tail.usage.modelCalls, lines.filter((l) => l.includes('"usage"')).length);
  // Written on: only what came, numbered on; a line half written waits.
  const half = said("later", "mz");
  appendFileSync(path, half.slice(0, 20));
  assert.deepEqual(tail.read(), [entries.length, []]);
  appendFileSync(path, half.slice(20));
  const [next, more] = tail.read();
  assert.deepEqual([next, more.map((e) => e.text)], [entries.length, ["later"]]);
  rmSync(dir, { recursive: true, force: true });
});

test("a reader keeps a transcript read in brief: a page is what one read whole and in brief gives, and it reads on as it grows", () => {
  forgetKept();
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, said("one", "m1") + call("c2", `true && ${"x".repeat(2000)}`) + said("three", "m3"));
  const first = inBrief("claude", [path]);
  assert.deepEqual(JSON.stringify(first), JSON.stringify(readTimeline("claude", path).map(brief)));
  assert.equal(first[1]!.brief, true);
  appendFileSync(path, said("four", "m4"));
  const again = inBrief("claude", [path]);
  assert.deepEqual(again.map((e) => e.text).slice(-1), ["four"]);
  assert.deepEqual(keptNow(), { chains: 1, entries: 4 });
  rmSync(dir, { recursive: true, force: true });
});

test("a reader keeps no more than its share, the least recently read let go first", () => {
  forgetKept();
  const dir = temp();
  const each = Math.ceil(KEPT_ENTRIES / 2);
  const paths = ["a", "b", "c"].map((name) => {
    const path = join(dir, `${name}.jsonl`);
    writeFileSync(path, Array.from({ length: each }, (_, i) => said(`${name}${i}`, `${name}m${i}`)).join(""));
    return path;
  });
  inBrief("claude", [paths[0]!]);
  inBrief("claude", [paths[1]!]);
  assert.equal(keptNow().chains, 2);
  // The first read again: the second is the one let go for the third.
  inBrief("claude", [paths[0]!]);
  inBrief("claude", [paths[2]!]);
  const now = keptNow();
  assert.equal(now.chains, 2);
  assert.ok(now.entries <= KEPT_ENTRIES);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});
