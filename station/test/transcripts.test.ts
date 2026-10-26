// Reading transcripts as they grow (src/read/tail.ts), and where a reader reads the pages of a history from
// (src/read/transcripts.ts).
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { appendFileSync, mkdtempSync, openSync, readFileSync, readdirSync, rmSync, writeFileSync, writeSync, closeSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdCompressSync } from "node:zlib";
import { ChainTail, MARK_EVERY, PIECE, TranscriptTail } from "../src/read/tail.ts";
import { READING, brief, readTimeline } from "../src/read/transcript.ts";
import { chainOf, entriesOf, forgetKept, lengthOf } from "../src/read/transcripts.ts";

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
  // Written on: only what came, numbered on; a line half written waits.
  const half = said("later", "mz");
  appendFileSync(path, half.slice(0, 20));
  assert.deepEqual(tail.read(), [entries.length, []]);
  appendFileSync(path, half.slice(20));
  const [next, more] = tail.read();
  assert.deepEqual([next, more.map((e) => e.text)], [entries.length, ["later"]]);
  rmSync(dir, { recursive: true, force: true });
});

/// Entries `from ..< to` of transcripts as a reader gives them (read/transcripts.ts), and how many they have.
const page = (paths: string[], dir: string | null, from: number, to: number, inBrief = false, runtime: "claude" | "codex" = "claude") => {
  const chain = chainOf(runtime, paths, dir);
  return { entries: entriesOf(runtime, chain, from, to, inBrief), end: lengthOf(chain) };
};

test("a page of a history is what a read of it whole gives, from anywhere in it, in brief or whole, as it grows", () => {
  forgetKept();
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const lines = Array.from({ length: MARK_EVERY * 3 + 17 }, (_, i) => (i % 5 === 0 ? call(`c${i}`, `true && ${"x".repeat(i)}`) : said(`${i}`, `m${i}`)));
  writeFileSync(path, lines.join(""));
  const whole = readTimeline("claude", path);
  for (const [from, to] of [[0, 10], [MARK_EVERY - 3, MARK_EVERY + 3], [MARK_EVERY * 2, MARK_EVERY * 2 + 200], [whole.length - 5, whole.length + 5]] as const) {
    assert.deepEqual(page([path], null, from, to).entries, whole.slice(from, to));
    assert.deepEqual(JSON.stringify(page([path], null, from, to, true).entries), JSON.stringify(whole.slice(from, to).map(brief)));
  }
  assert.equal(page([path], null, 0, 0).end, whole.length);
  appendFileSync(path, said("later", "m-later"));
  const grown = page([path], null, whole.length, whole.length + 10);
  assert.deepEqual([grown.entries.map((e) => e.text), grown.end], [["later"], whole.length + 1]);
  // Two transcripts read as one, the first first.
  const before = join(dir, "before.jsonl");
  writeFileSync(before, said("first", "b1") + said("second", "b2"));
  assert.deepEqual(page([before, path], null, 1, 3).entries.map((e) => e.text), ["second", whole[0]!.text]);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

test("a reader that starts again reads on from where the last stood, kept on disk, and anew once lines are read another way", () => {
  forgetKept();
  const dir = temp();
  const marks = join(dir, "marks");
  const path = join(dir, "t.jsonl");
  writeFileSync(path, Array.from({ length: MARK_EVERY * 2 + 10 }, (_, i) => said(`${i}`, `m${i}`)).join(""));
  const whole = readTimeline("claude", path);
  assert.equal(page([path], marks, 0, 0).end, whole.length);
  // The first line spoilt where it is: a read from the start would give an entry less; one on from a mark gives them all.
  const file = openSync(path, "r+");
  writeSync(file, "#", 0);
  closeSync(file);
  forgetKept();
  const later = MARK_EVERY + 5;
  const again = page([path], marks, later, later + 3);
  assert.deepEqual([again.entries, again.end], [whole.slice(later, later + 3), whole.length]);
  // Kept by another way of reading lines: read anew.
  const [kept] = readdirSync(marks);
  const reading = JSON.parse(readFileSync(join(marks, kept!), "utf8"));
  writeFileSync(join(marks, kept!), JSON.stringify({ ...reading, reading: reading.reading + 1 }));
  forgetKept();
  assert.equal(page([path], marks, 0, 0).end, whole.length - 1);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

/// Line `n` of a transcript of `lines` spoilt where it is (its first byte, so it is no record): a read of it from before
/// gives an entry less.
function spoil(path: string, lines: string[], n: number) {
  const file = openSync(path, "r+");
  writeSync(file, "#", Buffer.byteLength(lines.slice(0, n).join("")));
  closeSync(file);
}

test("what a reader writes down of a reading goes on as the transcript grows: one that starts again reads on from the last", () => {
  forgetKept();
  const dir = temp();
  const marks = join(dir, "marks");
  const path = join(dir, "t.jsonl");
  const lines = Array.from({ length: 10 }, (_, i) => said(`${i}`, `m${i}`));
  writeFileSync(path, lines.join(""));
  assert.equal(page([path], marks, 0, 0).end, 10);
  const more = Array.from({ length: MARK_EVERY + 10 }, (_, i) => said(`${10 + i}`, `m${10 + i}`));
  appendFileSync(path, more.join(""));
  lines.push(...more);
  assert.equal(page([path], marks, 0, 0).end, lines.length);
  // Spoilt past where the first reading was written down: one starting from there would count an entry less.
  spoil(path, lines, 20);
  forgetKept();
  assert.equal(page([path], marks, 0, 0).end, lines.length);
  // A reading marking gives no entries, only counts them: a reader keeps none of a long transcript as it reads it.
  const tail = new TranscriptTail("claude", path, null, false, true);
  assert.deepEqual([tail.read(), tail.length], [[0, []], lines.length - 1]);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

test("a transcript put away is read from a mark as one read whole reads it, decompressed once for its pages", () => {
  forgetKept();
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const lines = Array.from({ length: MARK_EVERY * 2 + 10 }, (_, i) => (i % 7 === 0 ? call(`c${i}`, `ls ${i}`) : said(`${i}`, `m${i}`)));
  writeFileSync(path, lines.join(""));
  const whole = readTimeline("claude", path);
  writeFileSync(`${path}.zst`, zstdCompressSync(readFileSync(path)));
  rmSync(path);
  for (const at of [3, MARK_EVERY + 1, whole.length - 4]) assert.deepEqual(page([path], null, at, at + 4).entries, whole.slice(at, at + 4));
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

test("a transcript of a chain that cannot be read any more ends a page: those after it are not given in its place", () => {
  forgetKept();
  const dir = temp();
  const [a, b] = ["a", "b"].map((n) => join(dir, `${n}.jsonl`));
  writeFileSync(a!, said("a1", "a1") + said("a2", "a2"));
  writeFileSync(b!, said("b1", "b1"));
  const chain = chainOf("claude", [a!, b!], null);
  rmSync(a!);
  assert.deepEqual(entriesOf("claude", chain, 0, 3, false), []);
  assert.deepEqual(entriesOf("claude", chain, 2, 3, false).map((e) => e.text), ["b1"]);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

test("a line starting with a byte order mark is no record, however lines are cut into what is decoded at once", () => {
  forgetKept();
  const dir = temp();
  const path = join(dir, "t.jsonl");
  writeFileSync(path, `\uFEFF${said("first", "m1")}${said("two", "m2")}\uFEFF${said("three", "m3")}${said("four", "m4")}`);
  const whole = readTimeline("claude", path);
  assert.deepEqual(whole.map((e) => e.text), ["two", "four"]);
  const live = new ChainTail("claude", [path], null, false);
  live.read();
  assert.deepEqual([live.length, page([path], null, 0, 9).entries], [whole.length, whole]);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

/// Lines of the kinds Claude Code and Codex write, as a transcript has them.
function corpus(): { claude: string; codex: string } {
  const at = "2026-10-24T00:00:00Z";
  const claude = [
    { type: "user", timestamp: at, message: { role: "user", content: "fix the build" } },
    { type: "user", timestamp: at, message: { role: "user", content: "<command-name>/clear</command-name>" } },
    { type: "user", timestamp: at, isMeta: true, message: { role: "user", content: "meta" } },
    { type: "assistant", timestamp: at, message: { id: "r1", content: [{ type: "thinking", thinking: "look first" }, { type: "text", text: "Looking." }], usage: { input_tokens: 5, output_tokens: 2 } } },
    { type: "assistant", timestamp: at, message: { id: "r2", content: [{ type: "tool_use", id: "t1", name: "Bash", input: { command: `make ${"x".repeat(700)}`, description: "Build" } }] } },
    { type: "user", timestamp: at, message: { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "error: missing", is_error: true }] } },
    { type: "assistant", timestamp: at, message: { id: "r3", content: [{ type: "tool_use", id: "t2", name: "mcp__stillfail__chat_post", input: { to: "C/1", text: "done" } }] } },
    { type: "user", timestamp: at, message: { role: "user", content: [{ type: "tool_result", tool_use_id: "t2", content: [{ type: "text", text: "Posted." }, { type: "image", source: {} }] }] } },
    // What came while it worked, given to it between two calls; the rest of what Claude Code attaches gives nothing.
    { type: "attachment", timestamp: at, attachment: { type: "queued_command", prompt: '<message via="slack" from="Ada (U1)" ts="1.2">and the tests</message>' } },
    { type: "attachment", timestamp: at, attachment: { type: "queued_command", prompt: [{ type: "text", text: "<task-notification>\n<status>completed</status>\n</task-notification>" }, { type: "image", source: {} }], commandMode: "task-notification" } },
    { type: "attachment", timestamp: at, attachment: { type: "total_tokens_reminder", text: "<total_tokens>1 tokens left</total_tokens>" } },
    { type: "assistant", timestamp: at, isSidechain: true, message: { id: "r4", content: [{ type: "text", text: "from a subagent" }] } },
    { type: "system", timestamp: at, content: "compacted" },
  ];
  const item = (payload: object) => ({ type: "response_item", timestamp: at, payload });
  const codex = [
    { type: "session_meta", timestamp: at, payload: { id: "s" } },
    item({ type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>x</environment_context>" }, { type: "input_text", text: "add a test" }] }),
    item({ type: "reasoning", summary: [{ type: "summary_text", text: "plan" }] }),
    item({ type: "message", role: "assistant", content: [{ type: "output_text", text: "On it." }] }),
    item({ type: "function_call", name: "shell", call_id: "f1", arguments: JSON.stringify({ command: ["ls"] }) }),
    item({ type: "function_call_output", call_id: "f1", output: "a b\nProcess exited with code 1" }),
    item({ type: "custom_tool_call", name: "exec", call_id: "x1", input: 'const a = await tools.exec_command({"cmd":"ls"}); console.log(a)' }),
    item({ type: "custom_tool_call_output", call_id: "x1", output: "done" }),
    item({ type: "custom_tool_call", name: "exec", call_id: "x2", input: 'await tools.exec_command({"cmd":"pwd"})' }),
    item({ type: "custom_tool_call_output", call_id: "x2", output: "/w" }),
    item({ type: "custom_tool_call", name: "apply_patch", call_id: "p1", input: "*** Begin Patch" }),
    { type: "event_msg", timestamp: at, payload: { type: "token_count", info: null } },
  ];
  const text = (records: object[]) => records.map((r) => `${JSON.stringify(r)}\n`).join("");
  return { claude: text(claude), codex: text(codex) };
}

/// What lines gave when READING was each: a reading kept on disk (read/transcripts.ts) counts and marks entries as lines
/// gave them then.
const READ_AS: Record<number, string> = { 2: "8a08a82d23cb7c00" };

test("a prompt that came while a Claude agent worked is read as one that began a turn, where it was given", () => {
  const dir = temp();
  const path = join(dir, "claude.jsonl");
  writeFileSync(path, corpus().claude);
  const entries = readTimeline("claude", path);
  const posted = entries.findIndex((e) => e.kind === "tool_result" && e.callId === "t2");
  assert.deepEqual(entries.slice(posted + 1, posted + 3).map((e) => [e.kind, e.text]), [
    ["user", '<message via="slack" from="Ada (U1)" ts="1.2">and the tests</message>'],
    ["user", "<task-notification>\n<status>completed</status>\n</task-notification>"],
  ]);
  assert.ok(!entries.some((e) => e.text.includes("tokens left")));
  rmSync(dir, { recursive: true, force: true });
});

test("what lines give is what READING says: a change to it takes READING higher", () => {
  const dir = temp();
  const given = (["claude", "codex"] as const).map((runtime) => {
    const path = join(dir, `${runtime}.jsonl`);
    writeFileSync(path, corpus()[runtime]);
    return readTimeline(runtime, path);
  });
  assert.ok(given.every((entries) => entries.length >= 6));
  const hash = createHash("sha256").update(JSON.stringify(given)).digest("hex").slice(0, 16);
  assert.equal(hash, READ_AS[READING], `lines give other entries now (${hash}): take READING (read/transcript.ts) higher and say ${hash} for it here`);
  rmSync(dir, { recursive: true, force: true });
});

test("what a Codex script's calls are given, read from a mark after the script, is as a read of it whole", () => {
  forgetKept();
  const dir = temp();
  const path = join(dir, "rollout.jsonl");
  const item = (payload: object) => `${JSON.stringify({ type: "response_item", timestamp: "2026-10-24T00:00:00Z", payload })}\n`;
  const script = 'const a = await tools.exec_command({"cmd":"ls"}); const b = await tools.exec_command({"cmd":"pwd"}); console.log(a, b)';
  const lines = [item({ type: "custom_tool_call", name: "exec", call_id: "x1", input: script })];
  for (let i = 0; i < MARK_EVERY + 10; i++) lines.push(item({ type: "message", role: "assistant", content: [{ type: "output_text", text: `${i}` }] }));
  lines.push(item({ type: "custom_tool_call_output", call_id: "x1", output: "done" }));
  writeFileSync(path, lines.join(""));
  const whole = readTimeline("codex", path);
  const last = page([path], null, whole.length - 3, whole.length, false, "codex");
  assert.deepEqual(last.entries, whole.slice(-3));
  assert.deepEqual(last.entries.map((e) => e.callId), ["x1", "x1#0", "x1#1"]);
  // A script done with is not kept between lines, nor at the marks after it.
  assert.deepEqual(chainOf("codex", [path], null)[0]!.state.inner, []);
  forgetKept();
  rmSync(dir, { recursive: true, force: true });
});

test("where a reading stands goes to another thread: a tail made from it reads on as the one it was taken of, keeping none", () => {
  const dir = temp();
  const path = join(dir, "t.jsonl");
  const half = said("three", "m3");
  writeFileSync(path, said("one", "m1") + said("two", "m2") + half.slice(0, 15));
  const there = new TranscriptTail("claude", path, brief);
  there.read();
  const state = JSON.parse(JSON.stringify(there.snapshot()));
  appendFileSync(path, half.slice(15) + said("four", "m4"));
  const here = TranscriptTail.from("claude", state);
  const [start, entries] = here.read();
  assert.deepEqual([start, entries.map((e) => e.text)], [2, ["three", "four"]]);
  assert.deepEqual([here.keeps, here.length, here.entries.length], [false, 4, 0]);
  rmSync(dir, { recursive: true, force: true });
});

test("a chain that keeps nothing tells all that follows one of its transcripts that changed, numbered on", () => {
  const dir = temp();
  const [a, b] = ["a", "b"].map((n) => join(dir, `${n}.jsonl`));
  writeFileSync(a!, said("a1", "a1"));
  writeFileSync(b!, said("b1", "b1"));
  const chain = new ChainTail("claude", [a!, b!], null, false);
  assert.deepEqual(chain.read()[0], 0);
  assert.equal(chain.length, 2);
  // The first grew (its runtime session is over, rarely): what follows it is told again, after it.
  appendFileSync(a!, said("a2", "a2"));
  const [from, told] = chain.read();
  assert.deepEqual([from, told.map((e) => e.text)], [1, ["a2", "b1"]]);
  assert.equal(chain.length, 3);
  rmSync(dir, { recursive: true, force: true });
});
