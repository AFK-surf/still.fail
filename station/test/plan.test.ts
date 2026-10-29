// An agent's checklist as each runtime says it: read from its transcript's plan calls (read/plan.ts), or as an ACP
// runtime's `plan` update says it (agents/acp.ts).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { planOfAcp } from "../src/agents/acp.ts";
import { noPlan, planItems, readPlan } from "../src/read/plan.ts";
import { readTimeline } from "../src/read/transcript.ts";

const transcript = (lines: object[]) => {
  const dir = mkdtempSync(join(tmpdir(), "plan-"));
  const path = join(dir, "t.jsonl");
  writeFileSync(path, lines.map((l) => `${JSON.stringify(l)}\n`).join(""));
  return { path, done: () => rmSync(dir, { recursive: true, force: true }) };
};
const claudeCall = (id: string, name: string, input: object) => ({ type: "assistant", timestamp: "2026-10-29T00:00:00Z", message: { id: `m${id}`, content: [{ type: "tool_use", id, name, input }] } });
const claudeResult = (id: string, text: string) => ({ type: "user", timestamp: "2026-10-29T00:00:01Z", message: { content: [{ type: "tool_result", tool_use_id: id, content: text }] } });

test("Claude Code's TodoWrite says its list whole, the latest call winning; a long one is read whole", () => {
  const long = Array.from({ length: 60 }, (_, i) => ({ content: `Step ${i} of a long plan that goes on and on`, status: i < 2 ? "completed" : i === 2 ? "in_progress" : "pending", activeForm: `Doing step ${i}` }));
  const t = transcript([
    claudeCall("t1", "TodoWrite", { todos: [{ content: "old", status: "pending", activeForm: "x" }] }),
    claudeResult("t1", "Todos have been modified successfully."),
    claudeCall("t2", "TodoWrite", { todos: long }),
  ]);
  const state = noPlan();
  assert.equal(readPlan(state, readTimeline("claude", t.path)), true);
  const items = planItems(state);
  assert.equal(items.length, 60, "not cut short at 4000 characters");
  assert.deepEqual(items.slice(0, 4), [
    { text: "Step 0 of a long plan that goes on and on", status: "completed" },
    { text: "Step 1 of a long plan that goes on and on", status: "completed" },
    { text: "Step 2 of a long plan that goes on and on", status: "in_progress" },
    { text: "Step 3 of a long plan that goes on and on", status: "pending" },
  ]);
  t.done();
});

test("Claude Code's task tools change the list an item at a time: an item by the id its creation's result says", () => {
  const t = transcript([
    claudeCall("c1", "TaskCreate", { subject: "Read the code", description: "d", activeForm: "Reading" }),
    claudeResult("c1", "Task #1 created successfully: Read the code"),
    claudeCall("c2", "TaskCreate", { subject: "Write the test", description: "d" }),
    claudeResult("c2", "Task #2 created successfully: Write the test"),
    claudeCall("c3", "TaskCreate", { subject: "Throwaway", description: "d" }),
    claudeResult("c3", "Task #3 created successfully: Throwaway"),
    claudeCall("u1", "TaskUpdate", { taskId: "1", status: "completed" }),
    claudeResult("u1", "Updated task #1 status"),
    claudeCall("u2", "TaskUpdate", { taskId: "2", status: "in_progress", subject: "Write the tests" }),
    claudeCall("u3", "TaskUpdate", { taskId: "3", status: "deleted" }),
    // Another's list (a subagent's is in its own transcript) or an id never made: nothing.
    claudeCall("u4", "TaskUpdate", { taskId: "9", status: "completed" }),
  ]);
  const state = noPlan();
  readPlan(state, readTimeline("claude", t.path));
  assert.deepEqual(planItems(state), [
    { text: "Read the code", status: "completed" },
    { text: "Write the tests", status: "in_progress" },
  ]);
  // Read on, a piece at a time, as the live view reads a transcript that grows: the same.
  const again = noPlan();
  const entries = readTimeline("claude", t.path);
  for (const e of entries) readPlan(again, [e]);
  assert.deepEqual(planItems(again), planItems(state));
  t.done();
});

test("Codex's update_plan says its list whole", () => {
  const t = transcript([
    { type: "session_meta", timestamp: "2026-10-29T00:00:00.000Z", payload: { id: "th", cwd: "/w" } },
    { type: "response_item", timestamp: "2026-10-29T00:00:01.000Z", payload: { type: "function_call", name: "update_plan", call_id: "p1", arguments: JSON.stringify({ explanation: "first", plan: [{ step: "Look", status: "in_progress" }, { step: "Fix", status: "pending" }] }) } },
    { type: "response_item", timestamp: "2026-10-29T00:00:02.000Z", payload: { type: "function_call_output", call_id: "p1", output: "Plan updated" } },
    { type: "response_item", timestamp: "2026-10-29T00:00:03.000Z", payload: { type: "function_call", name: "update_plan", call_id: "p2", arguments: JSON.stringify({ plan: [{ step: "Look", status: "completed" }, { step: "Fix", status: "in_progress" }] }) } },
  ]);
  const state = noPlan();
  readPlan(state, readTimeline("codex", t.path));
  assert.deepEqual(planItems(state), [
    { text: "Look", status: "completed" },
    { text: "Fix", status: "in_progress" },
  ]);
  t.done();
});

test("an ACP runtime's plan update, as checklist items", () => {
  assert.deepEqual(
    planOfAcp({ sessionUpdate: "plan", entries: [{ content: "Survey", status: "completed", priority: "high" }, { content: "Patch", status: "in_progress", priority: "medium" }, { content: "Ship", priority: "low" }, { status: "pending" }] }),
    [
      { text: "Survey", status: "completed" },
      { text: "Patch", status: "in_progress" },
      { text: "Ship", status: "pending" },
    ],
  );
  assert.equal(planOfAcp({ sessionUpdate: "plan" }), null);
});
