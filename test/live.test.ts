import assert from "node:assert/strict";
import { appendFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { LiveHub, type LiveMessage } from "../src/live.ts";
import { liveFromClaude } from "../src/runtime/claude.ts";
import { liveFromCodex } from "../src/runtime/codex.ts";
import type { LiveEvent } from "../src/runtime/types.ts";
import { TranscriptTail } from "../src/transcript.ts";

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("claude partial messages become steps: text and thinking end with their block, a tool with its result", () => {
  const all: LiveEvent[] = [];
  const feed = liveFromClaude((e) => all.push(e));
  const out: LiveEvent[] = [];
  const ev = (event: object, parent: string | null = null) => feed({ type: "stream_event", event, parent_tool_use_id: parent });
  ev({ type: "message_start", message: { id: "m1" } });
  ev({ type: "content_block_start", index: 0, content_block: { type: "thinking", thinking: "" } });
  ev({ type: "content_block_delta", index: 0, delta: { type: "thinking_delta", thinking: "hmm" } });
  ev({ type: "content_block_stop", index: 0 });
  ev({ type: "content_block_start", index: 1, content_block: { type: "tool_use", id: "call_1", name: "Bash", input: {} } });
  ev({ type: "content_block_delta", index: 1, delta: { type: "input_json_delta", partial_json: "{\"command\":" } });
  ev({ type: "content_block_stop", index: 1 });
  feed({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: "call_1", content: "hi" }] } });
  ev({ type: "message_start", message: { id: "m2" } });
  ev({ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } });
  ev({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Done" } });
  ev({ type: "content_block_stop", index: 0 });
  out.push(...all.filter((e) => e.kind !== "phase"));
  assert.deepEqual(all.filter((e) => e.kind === "phase").map((e) => (e as any).phase), ["responding", "responding"]);
  assert.deepEqual(out, [
    { kind: "start", id: "m1:0", step: "thinking" },
    { kind: "delta", id: "m1:0", field: "text", text: "hmm" },
    { kind: "end", id: "m1:0" },
    { kind: "start", id: "call_1", step: "tool", tool: "Bash" },
    { kind: "delta", id: "call_1", field: "input", text: "{\"command\":" },
    { kind: "delta", id: "call_1", field: "output", text: "hi" },
    { kind: "end", id: "call_1" },
    { kind: "start", id: "m2:0", step: "text" },
    { kind: "delta", id: "m2:0", field: "text", text: "Done" },
    { kind: "end", id: "m2:0" },
  ].filter(Boolean));
});

test("codex item notifications become steps, command output streaming as it runs", () => {
  const out: LiveEvent[] = [];
  const feed = liveFromCodex((e) => out.push(e));
  feed("item/started", { item: { type: "userMessage", id: "u" } });
  feed("item/started", { item: { type: "commandExecution", id: "c1", command: "ls" } });
  feed("item/commandExecution/outputDelta", { itemId: "c1", delta: "a\n" });
  feed("item/completed", { item: { id: "c1" } });
  feed("item/started", { item: { type: "agentMessage", id: "a1" } });
  feed("item/agentMessage/delta", { itemId: "a1", delta: "ok" });
  feed("item/completed", { item: { id: "a1" } });
  const phases = out.filter((e) => e.kind === "phase").map((e) => (e as any).phase);
  assert.deepEqual(phases, ["working", "responding"]);
  out.splice(0, out.length, ...out.filter((e) => e.kind !== "phase"));
  assert.deepEqual(out, [
    { kind: "start", id: "c1", step: "tool", tool: "shell", input: "ls" },
    { kind: "delta", id: "c1", field: "output", text: "a\n" },
    { kind: "end", id: "c1" },
    { kind: "start", id: "a1", step: "text" },
    { kind: "delta", id: "a1", field: "text", text: "ok" },
    { kind: "end", id: "a1" },
  ]);
});

const line = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: "2026-09-26T00:00:00Z", message: { id, content: [{ type: "text", text }], usage: { input_tokens: 10, output_tokens: 2 } } })}\n`;

test("a transcript read as it grows gives what a full read gives, a half-written line waiting", () => {
  const path = join(mkdtempSync(join(tmpdir(), "ember-tail-")), "t.jsonl");
  writeFileSync(path, line("one", "m1"));
  const tail = new TranscriptTail("claude", path);
  assert.deepEqual(tail.read().entries.map((e) => e.text), ["one"]);
  const two = line("two", "m2");
  appendFileSync(path, two.slice(0, 20));
  assert.deepEqual(tail.read(), { start: 1, entries: [] });
  appendFileSync(path, two.slice(20));
  const r = tail.read();
  assert.equal(r.start, 1);
  assert.deepEqual(r.entries.map((e) => e.text), ["two"]);
  assert.deepEqual(tail.entries.map((e) => e.text), ["one", "two"]);
  assert.deepEqual(new TranscriptTail("claude", path).read().entries, tail.entries, "read in pieces, the same as read at once");
  assert.equal(tail.usage.modelCalls, 2);
});

test("a watcher gets what it lacks, the steps in flight, then new entries as the file grows", async (t) => {
  const path = join(mkdtempSync(join(tmpdir(), "ember-live-")), "t.jsonl");
  writeFileSync(path, line("one", "m1") + line("two", "m2"));
  const hub = new LiveHub(() => ({ runtime: "claude", path }));
  // A failed assertion must not leave the file watched (the run would never end).
  t.after(() => hub.close());
  hub.event("s", { kind: "start", id: "x", step: "text" });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "wri" });
  const got: LiveMessage[] = [];
  const stop = hub.subscribe("s", 1, (m) => got.push(m));
  assert.deepEqual(got.map((m) => m.type), ["timeline", "steps"]);
  assert.deepEqual((got[0] as any).entries.map((e: any) => e.text), ["two"]);
  // What a step is, not what it wrote: deltas are not told (a step's words come with its entry).
  assert.deepEqual([(got[1] as any).steps[0].step, (got[1] as any).steps[0].text], ["text", undefined]);
  const before = got.length;
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "ting" });
  assert.equal(got.length, before, "a delta sends nothing");
  hub.event("s", { kind: "end", id: "x" });
  appendFileSync(path, line("writing", "m3"));
  await wait(300);
  const timeline = got.filter((m) => m.type === "timeline").at(-1) as any;
  assert.equal(timeline.start, 2);
  assert.deepEqual(timeline.entries.map((e: any) => e.text), ["writing"]);
  hub.turnEnded("s");
  assert.equal(got.some((m) => m.type === "clear"), true);
  stop();
  hub.close();
});

test("how fast the model writes is told at most once a second, and 0 once it stops", () => {
  const hub = new LiveHub(() => undefined);
  const got: LiveMessage[] = [];
  const stop = hub.subscribe("s", 0, (m) => got.push(m));
  hub.event("s", { kind: "start", id: "x", step: "text" });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "x".repeat(400) });
  hub.event("s", { kind: "delta", id: "x", field: "text", text: "x".repeat(400) });
  const rates = () => got.filter((m) => m.type === "rate").map((m) => (m as { tokensPerSecond: number }).tokensPerSecond);
  assert.equal(rates().length, 1, "the first output at once, then not within the second");
  assert.ok(rates()[0]! > 0);
  hub.event("s", { kind: "end", id: "x" });
  assert.deepEqual(rates().at(-1), 0);
  assert.ok(!got.some((m) => m.type === "step" && (m as any).event.kind === "delta"), "no delta is told");
  stop();
});
