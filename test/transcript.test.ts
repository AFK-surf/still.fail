import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { readTimeline, transcriptPath } from "../src/transcript.ts";

function file(lines: unknown[]): string {
  const dir = mkdtempSync(join(tmpdir(), "ember-transcript-"));
  const path = join(dir, "t.jsonl");
  writeFileSync(path, `${lines.map((l) => JSON.stringify(l)).join("\n")}\n{"partial`);
  return path;
}

test("claude transcripts become a timeline, subagent work marked", () => {
  const timeline = readTimeline("claude", file([
    { type: "user", timestamp: "t1", message: { content: "fix it" } },
    { type: "assistant", message: { content: [{ type: "thinking", thinking: "hmm" }, { type: "text", text: "on it" }, { type: "tool_use", id: "tu1", name: "Bash", input: { command: "ls" } }] } },
    { type: "user", message: { content: [{ type: "tool_result", tool_use_id: "tu1", is_error: true, content: [{ type: "text", text: "boom" }] }] } },
    { type: "assistant", isSidechain: true, message: { content: [{ type: "text", text: "sub" }] } },
    { type: "user", isMeta: true, message: { content: "injected" } },
    { type: "attachment" },
  ]));
  assert.equal(timeline[3]!.callId, "tu1");
  assert.equal(timeline[4]!.callId, "tu1");
  assert.deepEqual(timeline.map((e) => [e.kind, e.text, e.ok, e.subagent]), [
    ["user", "fix it", undefined, undefined],
    ["thinking", "hmm", undefined, undefined],
    ["assistant", "on it", undefined, undefined],
    ["tool_call", '{\n  "command": "ls"\n}', undefined, undefined],
    ["tool_result", "boom", false, undefined],
    ["assistant", "sub", undefined, true],
  ]);
});

test("codex rollouts become a timeline without injected context", () => {
  const timeline = readTimeline("codex", file([
    { type: "session_meta", payload: {} },
    { type: "response_item", payload: { type: "message", role: "developer", content: [{ type: "input_text", text: "rules" }] } },
    { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>…" }] } },
    { type: "response_item", timestamp: "t2", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "count files" }] } },
    { type: "response_item", payload: { type: "reasoning", summary: [], content: [{ type: "reasoning_text", text: "easy" }] } },
    { type: "response_item", payload: { type: "function_call", name: "exec_command", call_id: "c1", arguments: "{\"cmd\":\"ls\"}" } },
    { type: "response_item", payload: { type: "function_call_output", call_id: "c1", output: "Process exited with code 2\nOutput:\nnope" } },
    { type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "5" }] } },
  ]));
  assert.deepEqual(timeline.map((e) => [e.kind, e.tool, e.ok]), [
    ["user", undefined, undefined],
    ["thinking", undefined, undefined],
    ["tool_call", "exec_command", undefined],
    ["tool_result", undefined, false],
    ["assistant", undefined, undefined],
  ]);
  assert.equal(timeline[0]!.at, "t2");
  assert.deepEqual([timeline[2]!.callId, timeline[3]!.callId], ["c1", "c1"]);
});

test("transcripts are found where each runtime keeps them", () => {
  const home = mkdtempSync(join(tmpdir(), "ember-home-"));
  mkdirSync(join(home, "projects", "-some-cwd"), { recursive: true });
  writeFileSync(join(home, "projects", "-some-cwd", "abc.jsonl"), "");
  mkdirSync(join(home, "sessions", "2026", "09", "26"), { recursive: true });
  writeFileSync(join(home, "sessions", "2026", "09", "26", "rollout-2026-09-26T00-00-00-xyz.jsonl"), "");
  assert.equal(transcriptPath("claude", home, "abc"), join(home, "projects", "-some-cwd", "abc.jsonl"));
  assert.equal(transcriptPath("codex", home, "xyz"), join(home, "sessions", "2026", "09", "26", "rollout-2026-09-26T00-00-00-xyz.jsonl"));
  assert.equal(transcriptPath("claude", home, "missing"), undefined);
});
