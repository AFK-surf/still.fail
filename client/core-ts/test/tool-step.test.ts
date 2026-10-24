// A history step's call and what came back, read by what they are (src/tool-step.ts, `history.tool`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { toolCall, toolResult } from "../src/tool-step.ts";
import { parseCall } from "../src/core/calls.ts";
import { t } from "../src/i18n.ts";
import { answers, call, cloudCore } from "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

test("a_call_is_read_by_what_it_is", () => {
  assert.deepEqual(toolCall("Bash", JSON.stringify({ command: "ls -la", timeout: 5000, run_in_background: true }), false, t), [
    { kind: "code", text: "ls -la", lang: "sh" },
    { kind: "facts", items: [{ key: "timeout", value: "5000" }, { key: "run_in_background" }] },
  ]);
  assert.deepEqual(toolCall("exec", JSON.stringify({ cmd: ["bash", "-lc", "make test"] }), false, t)[0], { kind: "code", text: "make test", lang: "sh" });
  assert.deepEqual(toolCall("Edit", JSON.stringify({ file_path: "/a.ts", old_string: "x\ny\nz", new_string: "x\nY\nz" }), false, t), [
    { kind: "path", path: "/a.ts" },
    { kind: "diff", rows: [[" ", "x"], ["-", "y"], ["+", "Y"], [" ", "z"]] },
  ]);
  assert.deepEqual(toolCall("Write", JSON.stringify({ file_path: "/b.rs", content: "fn main() {}" }), false, t)[1], { kind: "code", text: "fn main() {}", lang: "rs" });
  assert.deepEqual(toolCall("Read", JSON.stringify({ file_path: "/c.md", offset: 10, limit: 5 }), false, t), [{ kind: "path", path: "/c.md", extra: "第 10 行起，5 行" }]);
  assert.deepEqual(toolCall("TodoWrite", JSON.stringify({ todos: [{ content: "a", status: "completed" }, { content: "b", status: "in_progress" }] }), false, t), [
    { kind: "plan", items: [{ text: "a", status: "completed" }, { text: "b", status: "in_progress" }] },
  ]);
  assert.deepEqual(toolCall("Grep", JSON.stringify({ pattern: "foo", path: "src" }), false, t), [
    { kind: "lead", text: "foo" }, { kind: "fields", rows: [{ key: "path", value: "src", form: "short" }] },
  ]);
  assert.deepEqual(toolCall("apply_patch", "*** Begin Patch\n*** Update File: a\n@@\n-old\n+new\n*** End Patch", false, t), [
    { kind: "diff", rows: [["@", "*** Update File: a"], ["@", "@@"], ["-", "old"], ["+", "new"]] },
  ]);
  assert.deepEqual(toolCall("x", "{}", false, t), [{ kind: "none", text: "无参数" }]);
  // Cut short by the station: closed where it stops.
  assert.deepEqual(toolCall("Write", `{"file_path": "/d.txt", "content": "abc\n… (900 more characters)`, false, t)[1], { kind: "code", text: "abc…", lang: "txt" });
});

test("what_came_back_is_read_by_what_it_is", () => {
  assert.deepEqual(toolResult("x", "{}", "  ", false, t), [{ kind: "none", text: "无输出" }]);
  assert.deepEqual(toolResult("exec_command", "{}", "Wall time: 1.2s\nProcess exited with code 1\nOutput:\noops", true, t), [
    { kind: "facts", items: [{ key: "退出码 1", plain: true }, { key: "用时 1.2s", plain: true }] },
    { kind: "output", text: "oops", failed: true },
  ]);
  assert.deepEqual(toolResult("Read", JSON.stringify({ file_path: "/e.py" }), "     1→a\n     2→b\n<note>", false, t), [{ kind: "code", text: "a\nb", lang: "py" }]);
  assert.deepEqual(toolResult("x", "{}", '{"ok": true}', false, t), [{ kind: "fields", rows: [{ key: "ok", value: "true", form: "short" }] }]);
  assert.deepEqual(toolResult("x", "{}", "plain words", false, t), [{ kind: "output", text: "plain words" }]);
});

test("a_client_asks_the_core_what_a_step_is", async () => {
  assert.deepEqual(parseCall("history.tool", { name: "Bash", call: "{}" }), { kind: "historyTool", name: "Bash", call: "{}", result: null, failed: false, said: false });
  const { host, core } = await cloudCore();
  const ui = core.connect();
  call(core, ui, 1, "history.tool", { name: "Agent", call: JSON.stringify({ prompt: "**go**" }), result: "done", said: false });
  await host.settle();
  const ok = (answers(host.takeEmitted(), 1) as J).ok;
  assert.equal(ok.call[0].kind, "markdown");
  assert.ok(Array.isArray(ok.call[0].md), "its Markdown read as everywhere");
  assert.deepEqual(ok.result, [{ kind: "output", text: "done" }]);
  core.close();
});
