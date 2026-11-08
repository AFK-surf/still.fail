// The execution histories searched by the MoonBit program (station/mb, src/history) as search/worker.ts searches them:
// transcripts of every runtime (Claude Code's queued prompts, commands, side chains and posts; Codex's injected context,
// typed requests, code-mode scripts and their outputs; DeepSeek Harness's versions and times; Grok Build's queries and
// MCP calls; Cursor's, Devin's, Hermes' and Antigravity's), plain and put away, with odd lines (CRLF, a byte order mark,
// not JSON, a last line not ended), for each asker, page and word (quoted, cased beyond ASCII), the same groups.
import assert from "node:assert/strict";
import { appendFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import type { Asker } from "../src/search/match.ts";
import { Search } from "../src/search/search.ts";
import { packFile } from "../src/sessions/archive.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const line = (v: unknown) => `${JSON.stringify(v)}\n`;
const put = (path: string, text: string) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };

async function station() {
  const data = mkdtempSync(join(tmpdir(), "mb-search-history-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const t = (runtime: string) => join(data, "transcripts", runtime);
  let at = 0;
  const session = (key: string, runtime: string, ws: string | null, ids: string[]) => {
    store.insertSession({ key, connect: "ember", runtime, profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: ++at, ws } as Parameters<Store["insertSession"]>[0]);
    for (const id of ids) store.ranIn(key, id, "cc");
    store.setRuntimeSessionId(key, ids.at(-1)!);
  };
  // Claude Code's.
  session("cl", "claude", "W1", ["c1", "c2"]);
  const thread = store.openThreadOf("ember", "ember", "cl", null, "a@x", "cl").id;
  store.joinThread(thread, "cl", "ember");
  store.setAutoTitle(thread, "  Deploy chat ", true);
  put(join(t("claude"), "-w-cl", "c1.jsonl"), [
    line({ type: "user", timestamp: "2026-11-01T10:00:00.123Z", message: { content: "deploy the thing" } }),
    line({ type: "assistant", timestamp: "2026-11-01T10:00:01Z", message: { content: [{ type: "text", text: "I will deploy \"now\"" }, { type: "thinking", thinking: "deploy plan ÄBC" }, { type: "tool_use", name: "Bash", id: "t1", input: { command: "deploy --all", n: 1.5, "2": true } }] } }),
    line({ type: "user", timestamp: "2026-11-01T10:00:02+08:00", message: { content: [{ type: "tool_result", tool_use_id: "t1", content: [{ type: "text", text: "deployed ok" }, { type: "image" }] }] } }),
    line({ type: "assistant", timestamp: "bad time", isSidechain: true, message: { content: [{ type: "tool_use", name: "mcp__stillfail__chat_post", input: { text: "deploy posted" } }, { type: "tool_use", name: "mcp__stillfail__slack_api", input: { deploy: "x".repeat(5000) } }] } }),
    line({ type: "attachment", timestamp: "2026-11-01T10:00:03Z", attachment: { type: "queued_command", prompt: [{ type: "text", text: "deploy queued" }] } }),
    line({ type: "user", isMeta: true, message: { content: "deploy meta" } }),
    "\r\n", "not json deploy\n", "\ufeff" + line({ type: "assistant", message: { content: "deploy bom" } }).trimEnd() + "\r\n",
    line({ type: "assistant", message: { content: "deploy " + "é".repeat(4100) } }),
  ].join(""));
  put(join(t("claude"), "-w-cl", "c2.jsonl"), line({ type: "assistant", timestamp: "2026-11-02T00:00:00Z", message: { content: [{ type: "tool_use", name: "Read", input: { path: "/deploy" } }] } }) + JSON.stringify({ type: "assistant", message: { content: "deploy unended" } }));
  // Codex's, one of them put away.
  session("cx", "codex", "W1", ["x1"]);
  const rollout = join(t("codex"), "2026", "11", "01", "rollout-2026-11-01T00-00-00-x1.jsonl");
  put(rollout, [
    line({ type: "response_item", timestamp: "2026-11-01T00:00:00Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>deploy</environment_context>" }, { type: "input_text", text: "# AGENTS.md instructions deploy" }, { type: "input_text", text: "# ctx\n## My request for Codex:\n  deploy please  " }] } }),
    line({ type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "deploy reply" }] } }),
    line({ type: "response_item", payload: { type: "reasoning", content: [], summary: [{ type: "summary_text", text: "deploy reasoning" }] } }),
    line({ type: "response_item", payload: { type: "function_call", name: "shell", call_id: "f1", arguments: "{\"cmd\":[\"deploy\"],\"b\":{}}" } }),
    line({ type: "response_item", payload: { type: "function_call_output", call_id: "f1", output: "deploy out\nProcess exited with code 2" } }),
    line({ type: "response_item", payload: { type: "custom_tool_call", name: "exec", call_id: "e1", input: "const r = await tools.shell({cmd: ['deploy', `x`], 'n': 1e3, ok: true});\ntext(r);\nconsole.log('deploy extra')" } }),
    line({ type: "response_item", payload: { type: "custom_tool_call_output", call_id: "e1", output: [{ type: "text", text: "deploy script out" }] } }),
    line({ type: "response_item", payload: { type: "custom_tool_call", name: "exec", call_id: "e2", input: "text(await tools.web_search({query: \"deploy \\u00e9\"}))" } }),
    line({ type: "response_item", payload: { type: "custom_tool_call", name: "apply_patch", call_id: "p1", input: "*** deploy patch" } }),
  ].join(""));
  await packFile(rollout);
  // DeepSeek Harness's, Grok Build's, Cursor's and the others'.
  session("ds", "dsh", "W2", ["d1"]);
  for (const v of ["1", "2"]) put(join(t("dsh"), "-w", "d1", `session.v${v}.jsonl`), [
    line({ type: "user/message", time: 1_700_000_000_000, data: { source: { kind: "user" }, content: [{ type: "text", text: `deploy v${v}` }] } }),
    line({ type: "assistant/message", time: 1_700_000_000_500.7, data: { message: { content: [{ type: "text", text: "deploy dsh" }, { type: "reasoning", text: "deploy why" }, { type: "tool-call", name: "run", id: "r1", arguments: "{\"deploy\":1}" }] } } }),
    line({ type: "tool/result", time: -5, data: { message: { content: [{ type: "text", text: "deploy result" }], toolCallId: "r1" } } }),
  ].join(""));
  session("gk", "grok", null, ["g1"]);
  put(join(t("grok"), "-w", "g1", "chat_history.jsonl"), [
    line({ type: "user", prompt_index: 0, content: "  <user_query>\ndeploy grok\n</user_query>  " }),
    line({ type: "reasoning", summary: [{ text: "deploy think" }, { text: "" }] }),
    line({ type: "assistant", content: "deploy said", tool_calls: [{ name: "use_tool", id: "u1", arguments: "{\"tool_name\":\"srv__deploy\",\"tool_input\":{\"a\":1}}" }, { name: "x", arguments: "not json deploy" }] }),
    line({ type: "tool_result", content: { deploy: [1, 2] }, tool_call_id: "u1" }),
  ].join(""));
  for (const [key, rt] of [["cu", "cursor"], ["dv", "devin"], ["hm", "hermes"], ["ag", "agy"]] as const) {
    session(key, rt, "W1", [`${key}1`]);
    put(join(t(rt), `${key}1.jsonl`), [
      line({ type: "user", time: 1_700_000_000_000, text: `deploy ${rt}` }),
      line({ type: "tool", time: 1_700_000_000_001, name: "mcp", id: "m1", args: { providerIdentifier: "srv", toolName: "deploy", args: { q: 1 } }, result: "{\"value\":{\"stdout\":\"deploy stdout\",\"stderr\":\"\"}}", status: "ok" }),
      line({ type: "tool", name: "shell", args: { cmd: "deploy" }, result: { content: [{ text: { text: "deploy mcp text" } }, { text: "deploy plain" }] }, status: "error" }),
    ].join(""));
  }
  appendFileSync(join(t("cursor"), "cu1.jsonl"), line({ type: "thinking", text: "deploy final thought" }));
  return { data, store, close: () => { store.close(); rmSync(data, { recursive: true, force: true }); } };
}

const askers: Asker[] = [{ workspace: "W1", home: true, scopes: [] }, { workspace: "W2", home: false, scopes: [] }];
const queries = ["deploy", "DEPLOY \"now\"", "äbc", "deploy é", "stdout", "script", "nothing"];
const pages = [{}, { limit: 3 }, { limit: 2, offset: 3 }, { limit: 200 }];

test("the MoonBit program searches the execution histories as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false, timeout: 300_000 }, async () => {
  const f = await station();
  const worker = new Search({ data: f.data, mb: null }), program = new Search({ data: f.data });
  worker.start(); program.start();
  try {
    let hits = 0;
    for (const asker of askers) for (const q of queries) for (const p of pages) {
      const options = { kinds: ["history"], ...p };
      const ours = await program.query(q, asker, options).then((r) => r.groups, (e: Error) => e.message);
      const theirs = await worker.query(q, asker, options).then((r) => r.groups, (e: Error) => e.message);
      assert.deepEqual(ours, theirs, `${q} for ${asker.workspace} ${JSON.stringify(p)}`);
      hits += JSON.stringify(ours).split("\"kind\":\"history\"").length - 1;
    }
    assert.ok(hits > 50, `${hits} hits`);
  } finally {
    await worker.stop(); await program.stop();
    f.close();
  }
});
