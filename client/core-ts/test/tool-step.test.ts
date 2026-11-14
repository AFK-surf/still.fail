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

test("agy_file_and_command_steps_render_diff_code_and_clean_terminal_output", () => {
  const ws = "/Users/zuozijian/.stillfail/sessions/chat/c-4282c9a37cb40bab469a3b91c261af05/workspace/stillfail";
  const editCall = JSON.stringify({
    Path: `${ws}/station/src/mesh/screens.ts`,
    Target: "const a = 1;\nconst b = 2;",
    Replacement: "const a = 1;\nconst b = 3;",
  });
  assert.deepEqual(toolCall(`File ${ws}/station/src/mesh/screens.ts`, editCall, true, t), [
    { kind: "path", path: "station/src/mesh/screens.ts" },
    { kind: "diff", rows: [[" ", "const a = 1;"], ["-", "const b = 2;"], ["+", "const b = 3;"]] },
  ]);
  assert.deepEqual(
    toolResult(
      `File ${ws}/station/src/mesh/screens.ts`,
      editCall,
      `Created At: 2026-11-13T04:00:00+08:00\nCompleted At: 2026-11-13T04:00:01+08:00\n\nMade 1 replacement in ${ws}/station/src/mesh/screens.ts`,
      false,
      t,
    ),
    [],
  );
  assert.deepEqual(toolResult("Edit", editCall, "The file has been updated.", false, t), []);

  const readCall = JSON.stringify({ Path: `${ws}/station/src/url.ts`, StartLine: 1, EndLine: 2 });
  assert.deepEqual(toolCall("read_file", readCall, true, t), [
    { kind: "path", path: "station/src/url.ts", extra: "第 1 行起，2 行" },
  ]);
  assert.deepEqual(
    toolResult(
      "read_file",
      readCall,
      "Created At: 2026-11-13T04:00:00+08:00\nCompleted At: 2026-11-13T04:00:00+08:00\nShowing lines 1-2 of 10\n1: export const a = 1;\n2: export const b = 2;",
      false,
      t,
    ),
    [{ kind: "code", text: "export const a = 1;\nexport const b = 2;", lang: "ts" }],
  );

  const cmdCall = JSON.stringify({ CommandLine: `cd ${ws} && git status --short`, toolSummary: "Git status check", WaitMsBeforeAsync: 5000 });
  assert.deepEqual(toolCall("run_command", cmdCall, true, t), [
    { kind: "code", text: "git status --short", lang: "sh" },
  ]);
  assert.deepEqual(
    toolResult(
      "run_command",
      cmdCall,
      "Created At: 2026-11-13T04:00:00+08:00\nCompleted At: 2026-11-13T04:00:02+08:00\nCommand exited with code 0\nCommand output:\nM station/src/url.ts",
      false,
      t,
    ),
    [
      { kind: "facts", items: [{ key: "退出码 0", plain: true }] },
      { kind: "output", text: "M station/src/url.ts" },
    ],
  );
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

  const sendCall = JSON.stringify({
    to: "a036720bc24844903",
    message: "All 4 review findings are valid (`src/sf/markdown.mbt`). Please fix all 4.",
    summary: "Tell verifier all 4 findings are valid, ask to fix all",
  });
  const sendRes = JSON.stringify({
    type: "message_sent",
    recipient: "a036720bc24844903",
    recipient_kind: "agent",
  });
  call(core, ui, 2, "history.tool", { name: "SendMessage", call: sendCall, result: sendRes, said: true });
  await host.settle();
  const sendOk = (answers(host.takeEmitted(), 2) as J).ok;
  assert.equal(sendOk.call[0].kind, "markdown");
  assert.equal(sendOk.call[0].target, "a036720bc24844903");
  assert.equal(sendOk.call[0].summary, "Tell verifier all 4 findings are valid, ask to fix all");
  assert.ok(Array.isArray(sendOk.call[0].md), "dispatch message parsed as Markdown");
  assert.deepEqual(sendOk.result, [
    {
      kind: "fields",
      rows: [
        { key: "type", value: "message_sent", form: "short" },
        { key: "recipient", value: "a036720bc24844903", form: "short" },
        { key: "recipient_kind", value: "agent", form: "short" },
      ],
    },
  ]);

  const customCall = JSON.stringify({
    id: "req_1",
    summary: "Short natural language summary",
    reason: "A longer explanation with `inline_code` that should render as a full-width Markdown block.",
  });
  call(core, ui, 3, "history.tool", { name: "custom_tool", call: customCall, result: null, said: false });
  await host.settle();
  const customOk = (answers(host.takeEmitted(), 3) as J).ok;
  assert.equal(customOk.call[0].kind, "fields");
  assert.equal(customOk.call[0].rows[0].form, "short");
  assert.equal(customOk.call[0].rows[0].prose, undefined);
  assert.equal(customOk.call[0].rows[1].form, "short");
  assert.equal(customOk.call[0].rows[1].prose, true);
  assert.equal(customOk.call[0].rows[2].form, "long");
  assert.ok(Array.isArray(customOk.call[0].rows[2].md), "long field row carries parsed Markdown tree");
  core.close();
});
