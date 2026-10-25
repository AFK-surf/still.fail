// Real Hermes ACP against a local deterministic model and MCP server. No external model calls or real credentials.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { HermesDriver } from "../src/agents/hermes.ts";
import { isPosting, transcriptPath } from "../src/read/transcript.ts";
import type { OpenOptions, RuntimeEvent, TurnOutcome } from "../src/agents/runtime.ts";

const data = mkdtempSync(join(tmpdir(), "hm-real-"));
const home = join(data, "profile");
mkdirSync(join(home, "hermes"), { recursive: true });
let turn = 1;
let requests = 0;
let restored = false;
const posts: string[] = [];
const violations: string[] = [];
const json = (res: any, body: any) => { res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(body)); };
const server = createServer(async (req, res) => {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  const body = raw ? JSON.parse(raw) : {};
  if (req.url === "/mcp") {
    if (req.headers.authorization !== "Bearer smoke-token") {
      violations.push("MCP bearer token missing"); res.statusCode = 401; res.end(); return;
    }
    if (req.method === "GET") { res.statusCode = 405; res.end(); return; }
    if (body.id === undefined) { res.statusCode = 202; res.end(); return; }
    let result: any = {};
    if (body.method === "initialize") result = { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "stillfail-smoke", version: "1" } };
    if (body.method === "tools/list") result = { tools: [{ name: "chat_post", description: "Post a reply", inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] } }] };
    if (body.method === "tools/call") {
      if (body.params?.name !== "chat_post") violations.push("wrong MCP tool");
      posts.push(body.params?.arguments?.text);
      result = { content: [{ type: "text", text: "Posted" }] };
    }
    json(res, { jsonrpc: "2.0", id: body.id, result }); return;
  }
  if (req.url === "/v1/models") { json(res, { data: [{ id: "smoke-model", object: "model" }] }); return; }
  // Hermes probes local model metadata (Ollama, llama.cpp, etc.) before using an OpenAI-compatible endpoint.
  if (req.url !== "/v1/chat/completions") { res.statusCode = 404; res.end(); return; }
  requests++;
  if (turn === 2 && body.messages?.some((m: any) => m.role === "assistant" && m.content === "Hermes turn 1 complete")) restored = true;
  const tools: string[] = body.tools?.map((t: any) => t.function?.name) ?? [];
  const direct = tools.find(name => name.endsWith("chat_post"));
  // Hermes may expose MCP tools through its discovery bridge. Use the name that a real search returned.
  const discovered = (body.messages ?? []).flatMap((m: any) => {
    if (m.role !== "tool" || typeof m.content !== "string") return [];
    try { return Object.keys(JSON.parse(m.content).tools ?? {}); } catch { return []; }
  }).find((name: string) => name.endsWith("chat_post"));
  const tool = direct ?? (discovered ? "tool_call" : "tool_search");
  const args = direct ? { text: `Hermes turn ${turn} reply` }
    : discovered ? { calls: [{ name: discovered, arguments: { text: `Hermes turn ${turn} reply` } }] }
    : { queries: ["stillfail chat_post"] };
  const call = posts.length < turn && tools.includes(tool);
  const message = call
    ? { role: "assistant", content: null, tool_calls: [{ id: `call_smoke_${requests}`, type: "function", function: { name: tool, arguments: JSON.stringify(args) } }] }
    : { role: "assistant", content: `Hermes turn ${turn} complete` };
  const response = { id: "smoke", object: "chat.completion", created: 1, model: "smoke-model", choices: [{ index: 0, message, finish_reason: call ? "tool_calls" : "stop" }], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } };
  if (body.stream) {
    res.setHeader("Content-Type", "text/event-stream");
    const delta: any = { ...message };
    if (delta.tool_calls) delta.tool_calls = delta.tool_calls.map((t: any, index: number) => ({ ...t, index }));
    res.write(`data: ${JSON.stringify({ ...response, object: "chat.completion.chunk", choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`);
    res.write(`data: ${JSON.stringify({ ...response, object: "chat.completion.chunk", choices: [{ index: 0, delta: {}, finish_reason: call ? "tool_calls" : "stop" }] })}\n\n`);
    res.end("data: [DONE]\n\n");
  } else json(res, response);
});
await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
const port = (server.address() as any).port;
writeFileSync(join(home, "hermes", "config.yaml"), `model:\n  default: smoke-model\n  provider: custom\n  base_url: http://127.0.0.1:${port}/v1\n  stream: false\nagent:\n  max_turns: 4\nmemory:\n  memory_enabled: false\n  user_profile_enabled: false\n`);
const options: OpenOptions = {
  key: "real-smoke", profile: { id: "hm", runtime: "hermes", home, access: { kind: "env" }, env: { OPENAI_API_KEY: "local-test-placeholder", OPENAI_BASE_URL: `http://127.0.0.1:${port}/v1`, HERMES_TELEMETRY_ENABLED: "false" } },
  cwd: data, instructions: "Use the stillfail chat_post tool to send the answer.", mcpToken: "smoke-token", mcpUrl: `http://127.0.0.1:${port}/mcp`, route: "smoke",
};
const driver = new HermesDriver({ data });
function completion() {
  let complete!: (outcome: TurnOutcome) => void;
  const done = new Promise<TurnOutcome>(resolve => { complete = resolve; });
  const events: RuntimeEvent[] = [];
  return { events, done, event: (e: RuntimeEvent) => { events.push(e); if (e.type === "turnEnded") complete(e.outcome); } };
}
async function completed(done: Promise<TurnOutcome>) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    assert.deepEqual(await Promise.race([done, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("turn timeout")), 45000); })]), { kind: "completed" });
  } finally { clearTimeout(timer); }
}
try {
  const first = completion();
  const session = await driver.open(options, first.event);
  await session.prompt("Post the first result with chat_post.");
  await completed(first.done);
  assert.deepEqual(posts, ["Hermes turn 1 reply"]);
  const id = session.id();
  await session.dispose();
  turn = 2;
  const second = completion();
  const resumed = await driver.open({ ...options, resume: id }, second.event);
  assert.equal(resumed.id(), id);
  assert.equal(second.events.length, 0, "loading history emits no new turn");
  await resumed.prompt("Continue the same conversation and post the second result.");
  await completed(second.done);
  assert.deepEqual(posts, ["Hermes turn 1 reply", "Hermes turn 2 reply"]);
  assert.equal(restored, true, "the second model request includes the first turn from Hermes' native history");
  const records = readFileSync(transcriptPath("hermes", home, id)!, "utf8").trim().split("\n").map(line => JSON.parse(line));
  assert.equal(records.filter(r => r.type === "tool" && isPosting(r.name)).length, 2, "both real MCP posts are recognised in history");
  assert.equal(records.filter(r => r.type === "assistant" && r.text.trim() === "Hermes turn 1 complete").length, 1, "loading history does not duplicate the transcript");
  assert.deepEqual(violations, []);
  await resumed.dispose();
  console.log(`PASS real Hermes: authenticated MCP, two completed turns, native resume preserves prior messages, readable history (${requests} local model requests)`);
} finally {
  await driver.shutdown(); server.closeAllConnections();
  await new Promise<void>(resolve => server.close(() => resolve()));
  rmSync(data, { recursive: true, force: true });
}
