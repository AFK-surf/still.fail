// The MCP endpoint, as the Rust station's mcp.rs's tests have it.
import assert from "node:assert/strict";
import { test } from "node:test";
import { AGY_TOOL_BUDGET } from "../src/agents/agy.ts";
import { CLAUDE_TOOL_LOADED } from "../src/agents/claude.ts";
import { CORE, EVERY_TURN, fitted, INDIRECT, type Listing, McpEndpoint, OUTWARD, type Tool, UNBOUND_REFUSAL, weight } from "../src/tools/mcp.ts";

const echo: Tool = {
  name: "echo",
  description: "echo",
  inputSchema: { type: "object" },
  run: async (key, args) => {
    if ("fail" in args) throw new Error("nope");
    return `${key}:${typeof args.text === "string" ? args.text : ""}`;
  },
};
const endpoint = () => new McpEndpoint((token) => (token === "good" ? "session-1" : undefined), [echo]);
const rpc = (e: McpEndpoint, token: string | undefined, body: unknown) => e.handle("POST", token ? `Bearer ${token}` : undefined, JSON.stringify(body));
const tools = (names: string[]): Tool[] => names.map((name) => ({ name, description: "", inputSchema: { type: "object" }, run: async () => `${name} ran` }));

test("requests without a known token are refused", async () => {
  const e = endpoint();
  assert.equal((await rpc(e, undefined, { jsonrpc: "2.0", id: 1, method: "tools/list" })).status, 401);
  assert.equal((await rpc(e, "bad", { jsonrpc: "2.0", id: 1, method: "tools/list" })).status, 401);
});

test("initialize, list and call run on behalf of the token's session", async () => {
  const e = endpoint();
  const init: any = (await rpc(e, "good", { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } })).body;
  assert.equal(init.result.protocolVersion, "2025-06-18");
  assert.equal(init.result.serverInfo.name, "still.fail");
  assert.equal((await rpc(e, "good", { jsonrpc: "2.0", method: "notifications/initialized" })).status, 202);
  const list: any = (await rpc(e, "good", { jsonrpc: "2.0", id: 2, method: "tools/list" })).body;
  assert.equal(list.result.tools[0].name, "echo");
  const call: any = (await rpc(e, "good", { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "echo", arguments: { text: "hi" } } })).body;
  assert.deepEqual(call.result, { content: [{ type: "text", text: "session-1:hi" }] });
  const failed: any = (await rpc(e, "good", { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "echo", arguments: { fail: true } } })).body;
  assert.deepEqual([failed.result.isError, failed.result.content[0].text], [true, "nope"]);
  assert.equal((await e.handle("GET", "Bearer good", "")).status, 405);
});

test("while the station is in no workspace, outward tools are refused and the rest run", async () => {
  const names = ["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file", "peer_forward", "chat_state", "chat_history", "chat_list", "chat_read", "session_history", "job_list", "job_log", "job_stop"];
  let out = true;
  const e = new McpEndpoint(() => "s", tools(names), () => (out ? UNBOUND_REFUSAL : undefined));
  const call = async (name: string) => ((await rpc(e, "t", { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: {} } })).body as any).result;
  for (const name of names) {
    const result = await call(name);
    if (OUTWARD.includes(name)) assert.deepEqual([result.isError, result.content[0].text], [true, UNBOUND_REFUSAL], name);
    else assert.deepEqual(result, { content: [{ type: "text", text: `${name} ran` }] }, name);
  }
  assert.deepEqual(OUTWARD, ["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file", "peer_forward"]);
  // Listed all the same: an agent that read the list before keeps the same tools.
  const list: any = (await rpc(e, "t", { jsonrpc: "2.0", id: 2, method: "tools/list" })).body;
  assert.equal(list.result.tools.length, names.length);
  out = false;
  for (const name of OUTWARD) assert.equal((await call(name)).content[0].text, `${name} ran`);
});

test("a parameter newer than the session's tool list, sent as text, is read as its schema types it", async () => {
  // phone_use {done: true} from a session begun before `done` was added arrives as done: "true".
  const seen: Record<string, unknown>[] = [];
  const tool: Tool = {
    name: "phone_use",
    description: "",
    inputSchema: { type: "object", properties: { reason: { type: "string" }, done: { type: "boolean" }, seconds: { type: "integer" } } },
    run: async (_s, args) => { seen.push(args); return "ok"; },
  };
  const e = new McpEndpoint((token) => (token === "good" ? "session-1" : undefined), [tool]);
  const call = (args: unknown) => rpc(e, "good", { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "phone_use", arguments: args } });
  await call({ reason: "true", done: "true", seconds: "30" });
  await call({ done: "false" });
  await call({ done: true, seconds: "soon" });
  assert.deepEqual(seen, [{ reason: "true", done: true, seconds: 30 }, { done: false }, { done: true, seconds: "soon" }]);
});

// A tool of about `bytes` bytes declared, as the station's are (chat_post the largest).
const sized = (name: string, bytes: number): Tool => ({ name, description: `${name}. ${"x".repeat(Math.max(0, bytes - 80))}`, inputSchema: { type: "object" }, run: async (_key, args) => `${name} ran ${JSON.stringify(args)}` });
// The station's tools as Antigravity CLI dropped them on 2026-11-12: 42, 73 KB, chat_post 8 KB the largest.
const station = (): Tool[] => [
  sized("chat_post", 8000), sized("station_task", 5000), sized("secret_save", 4800), sized("computer", 4300), sized("login", 3400),
  sized("chat_state", 2800), sized("job_start", 2750), ...Array.from({ length: 35 }, (_, i) => sized(`t${String(i).padStart(2, "0")}`, 400 + i * 30)),
];

test("a runtime that budgets its tools is declared the core ones and those that fit, and station_tool for the rest", async () => {
  const all = station();
  const total = all.reduce((n, t) => n + weight(t), 0);
  assert.ok(total > AGY_TOOL_BUDGET, `the station's tools (${total} B) are more than the budget`);
  const e = new McpEndpoint(() => "s", all, undefined, (session) => (session === "s" ? { budget: AGY_TOOL_BUDGET } : undefined));
  const list: any[] = ((await rpc(e, "t", { jsonrpc: "2.0", id: 1, method: "tools/list" })).body as any).result.tools;
  const names = list.map((t) => t.name);
  const bytes = list.reduce((n, t) => n + Buffer.byteLength(JSON.stringify(t)), 0);
  assert.ok(bytes <= AGY_TOOL_BUDGET, `declared ${bytes} B`);
  for (const name of CORE.filter((n) => all.some((t) => t.name === n))) assert.ok(names.includes(name), name);
  assert.equal(names.at(-1), INDIRECT);
  // Every tool is declared or named by station_tool, once.
  const indirect: string[] = list.at(-1).inputSchema.properties.name.enum;
  assert.deepEqual([...names.slice(0, -1), ...indirect].sort(), all.map((t) => t.name).sort());
  assert.ok(indirect.includes("secret_save") && indirect.every((n) => !names.includes(n)));
  // The same every time.
  assert.deepEqual(fitted(all, AGY_TOOL_BUDGET).indirect.map((t) => t.name), indirect);
  // Without a budget, every tool as before.
  const plain = new McpEndpoint(() => "other", all, undefined, (session) => (session === "s" ? { budget: AGY_TOOL_BUDGET } : undefined));
  assert.equal(((await rpc(plain, "t", { jsonrpc: "2.0", id: 1, method: "tools/list" })).body as any).result.tools.length, all.length);
});

test("a runtime that keeps tools back until they are searched for is told to load the two every turn calls, and no other list changes", async () => {
  const all = station();
  // As sessions/agents.ts gives each runtime's: Claude Code's mark, Antigravity CLI's budget, nothing for the rest.
  const listings: Record<string, Listing> = { claude: { loaded: CLAUDE_TOOL_LOADED }, agy: { budget: AGY_TOOL_BUDGET } };
  const e = new McpEndpoint((token) => token, all, undefined, (session) => listings[session]);
  const list = async (token: string): Promise<any[]> => ((await rpc(e, token, { jsonrpc: "2.0", id: 1, method: "tools/list" })).body as any).result.tools;
  const claude = await list("claude");
  assert.deepEqual(claude.filter((t) => "_meta" in t).map((t) => [t.name, t._meta]), [["chat_post", { "anthropic/alwaysLoad": true }], ["chat_state", { "anthropic/alwaysLoad": true }]]);
  assert.deepEqual(EVERY_TURN, ["chat_post", "chat_state"]);
  // But for the mark, every tool as any runtime is declared it.
  const before = JSON.stringify(all.map((t) => ({ name: t.name, description: t.description, inputSchema: t.inputSchema })));
  assert.equal(JSON.stringify(claude.map(({ _meta, ...t }) => t)), before);
  // Another runtime's list is byte for byte what it was, no `_meta` anywhere in it.
  assert.equal(JSON.stringify(await list("codex")), before);
  // One with a budget: what `fitted` gives, as before, unmarked.
  const { declared, indirect } = fitted(all, AGY_TOOL_BUDGET);
  const agy = await list("agy");
  assert.deepEqual(agy.map((t) => t.name), [...declared.map((t) => t.name), INDIRECT]);
  assert.deepEqual(agy.at(-1).inputSchema.properties.name.enum, indirect.map((t) => t.name));
  assert.ok(agy.every((t) => !("_meta" in t)));
});

test("a budget counts the marks of the tools it declares loaded", async () => {
  const all = station();
  const list = async (listing: Listing): Promise<any[]> => ((await rpc(new McpEndpoint(() => "s", all, undefined, () => listing), "t", { jsonrpc: "2.0", id: 1, method: "tools/list" })).body as any).result.tools;
  const bytes = (tools: any[]) => tools.reduce((n, t) => n + Buffer.byteLength(JSON.stringify(t)), 0);
  // A budget the unmarked list fills to the byte: with the marks, the list still stays within it.
  const budget = bytes(await list({ budget: AGY_TOOL_BUDGET }));
  const marked = await list({ budget, loaded: CLAUDE_TOOL_LOADED });
  assert.deepEqual(marked.filter((t) => "_meta" in t).map((t) => t.name), EVERY_TURN);
  assert.ok(bytes(marked) <= budget, `declared ${bytes(marked)} B of ${budget}`);
  assert.equal(marked.at(-1).name, INDIRECT);
});

test("station_tool reads an undeclared tool's parameters, runs it as any call, and is refused as it is", async () => {
  let out = false;
  const all = [...station(), sized("slack_api", 3000)];
  const e = new McpEndpoint(() => "s", all, () => (out ? UNBOUND_REFUSAL : undefined), () => ({ budget: AGY_TOOL_BUDGET }));
  const call = async (args: unknown) => ((await rpc(e, "t", { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: INDIRECT, arguments: args } })).body as any).result;
  const read = await call({ name: "secret_save" });
  assert.deepEqual(JSON.parse(read.content[0].text), { name: "secret_save", description: all.find((t) => t.name === "secret_save")!.description, inputSchema: { type: "object" } });
  assert.deepEqual((await call({ name: "secret_save", arguments: { a: "1" } })).content[0].text, 'secret_save ran {"a":"1"}');
  assert.equal((await call({ name: "nothing" })).isError, true);
  assert.equal((await call({ name: "secret_save", arguments: "x" })).isError, true);
  // An outward one is refused through it as directly.
  out = true;
  assert.deepEqual([(await call({ name: "slack_api", arguments: {} })).content[0].text], [UNBOUND_REFUSAL]);
});
