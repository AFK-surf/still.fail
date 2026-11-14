// A watched transcript read as it grows by the readers (read/read-tail.ts `ReadTail`, read/pool.ts `tailRead`: the
// MoonBit program's, and the worker's where it is not there) as the live view read it here (read/tail.ts `ChainTail`):
// the same entries at the same places, read after read, as a Claude Code transcript is written a piece at a time (a
// line cut in two), a chain goes on into a Codex transcript, one is written anew shorter, one is put away compressed,
// kept or only counted, and one taken up from where another's reading stood.
import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdCompressSync } from "node:zlib";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { ReadTail, type TailRead } from "../src/read/read-tail.ts";
import { ChainTail, type TailState } from "../src/read/tail.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const at = "2026-11-14T00:00:00Z";
const said = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: at, message: { id, content: [{ type: "text", text }] } })}\n`;
const call = (id: string, name: string, input: object) => `${JSON.stringify({ type: "assistant", timestamp: at, message: { id, content: [{ type: "tool_use", id, name, input }] } })}\n`;
const answer = (id: string, content: string) => `${JSON.stringify({ type: "user", timestamp: at, message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content }] } })}\n`;
const person = (text: string) => `${JSON.stringify({ type: "user", timestamp: at, message: { role: "user", content: text } })}\n`;
const item = (payload: object) => `${JSON.stringify({ type: "response_item", timestamp: at, payload })}\n`;

function claudeLines(n: number, tag: string): string[] {
  const out: string[] = [];
  for (let i = 0; i < n; i++) {
    const k = i % 5;
    if (k === 0) out.push(call(`${tag}c${i}`, "Bash", { command: `echo ${"x".repeat(i % 300)}`, description: `Step ${i}` }));
    else if (k === 1) out.push(answer(`${tag}c${i - 1}`, `out ${i} ${"y".repeat((i * 31) % 900)}`));
    else if (k === 2) out.push(person(`please ${i} 中文 ${"é".repeat(i % 40)}`));
    else if (k === 3) out.push("not json\n", "\n");
    else out.push(said(`${i} ${"s".repeat((i * 37) % 1200)}`, `${tag}m${i}`));
  }
  return out;
}

const codexLines = (n: number) => [
  `${JSON.stringify({ type: "session_meta", timestamp: at, payload: { id: "x" } })}\n`,
  ...Array.from({ length: n }, (_, i) => [
    item({ type: "message", role: "assistant", content: [{ type: "output_text", text: `codex ${i}` }] }),
    item({ type: "function_call", name: "shell", call_id: `f${i}`, arguments: JSON.stringify({ command: ["ls", `${i}`] }) }),
    item({ type: "function_call_output", call_id: `f${i}`, output: `a b ${i}` }),
  ]).flat(),
];

test("a watched transcript is read by the readers as it was read here, read after read", async (t) => {
  const data = mkdtempSync(join(tmpdir(), "read-tail-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  t.after(() => { store.close(); rmSync(data, { recursive: true, force: true }); });
  const open: Readers[] = [];
  t.after(() => Promise.all(open.map((r) => r.close())));
  const reading = (mb: boolean): TailRead => {
    const r = new Readers(data, 1);
    open.push(r);
    r.mbReader = mb ? binary : null;
    return async (runtime, state) => JSON.parse(await r.read("tailRead", { runtime, state }, "zh", { told: true }));
  };
  const ways = [reading(false), ...(binary !== null ? [reading(true)] : [])];

  const a = join(data, "a.jsonl"), b = join(data, "b.jsonl"), z = join(data, "z.jsonl");
  writeFileSync(a, "");
  const lines = claudeLines(60, "a");
  // Each way follows the same files: here, and as each reader reads them, kept and only counted.
  const chains = (keeps: boolean) => [new ChainTail("claude", [a], null, keeps), ...ways.map((w) => new ReadTail("claude", [a], w, keeps))];
  const kept = chains(true), counted = chains(false);
  const step = async (label: string) => {
    for (const set of [kept, counted]) {
      const got = [];
      for (const c of set) got.push({ read: await c.readSoon(), length: c.length, bytes: c.readBytes, paths: c.paths, ...(c.keeps ? { entries: c.entries } : {}) });
      for (let i = 1; i < got.length; i++) assert.deepEqual(got[i], got[0], `${label} (${set === kept ? "kept" : "counted"}, way ${i})`);
    }
  };
  // Written a few lines at a time, the last of each cut in two.
  for (let i = 0; i < lines.length; i += 7) {
    const piece = lines.slice(i, i + 7).join("");
    const cut = Math.floor(piece.length * 0.6);
    appendFileSync(a, piece.slice(0, cut));
    await step(`a to ${i} (cut)`);
    appendFileSync(a, piece.slice(cut));
    await step(`a to ${i}`);
  }
  await step("nothing new");
  // On into a Codex transcript of the same session.
  writeFileSync(b, codexLines(3).join(""));
  for (const c of [...kept, ...counted]) assert.equal(c.extend([a, { path: b, runtime: "codex" }]), true);
  await step("chain");
  appendFileSync(b, codexLines(4).slice(1).join(""));
  await step("chain grows");
  // The earlier one gains a line (rare: its runtime session is over): read again from there.
  appendFileSync(a, said("late", "late"));
  await step("an earlier one grows");
  // Written anew, shorter.
  writeFileSync(a, claudeLines(6, "r").join(""));
  await step("written anew");
  // One put away compressed, read whole.
  const zl = claudeLines(30, "z").join("");
  writeFileSync(`${z}.zst`, zstdCompressSync(Buffer.from(zl)));
  const packed = [new ChainTail("claude", [z], null, true), ...ways.map((w) => new ReadTail("claude", [z], w, true))];
  const reads = [];
  for (const c of packed) reads.push({ read: await c.readSoon(), entries: c.entries, again: await c.readSoon() });
  for (let i = 1; i < reads.length; i++) assert.deepEqual(reads[i], reads[0], `compressed, way ${i}`);
  // Taken up from where the reading here stood: it reads on as it would have.
  const states: TailState[] = counted[0]!.snapshot() as TailState[];
  appendFileSync(a, claudeLines(9, "u").join(""));
  const from = [ChainTail.from("claude", states), ...ways.map((w) => ReadTail.from("claude", states, w))];
  const taken = [];
  for (const c of from) taken.push({ read: await c.readSoon(), length: c.length, snapshot: c.snapshot() });
  for (let i = 1; i < taken.length; i++) assert.deepEqual(taken[i], taken[0], `taken up, way ${i}`);
});
