// Whether an agent can reach the station's tools: what the drivers take for their being out of reach (claude.ts
// `toolsLostIn`, codex.ts `codexToolsLost`), the address a process taken up was told (claude.ts `mcpUrlOf`), and the
// ports a station on its own tries (files.ts), so a station started again is where the agents it left know it to be.
import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { mcpUrlOf, toolsLostIn } from "../src/agents/claude.ts";
import { codexToolsLost } from "../src/agents/codex.ts";
import { unreachable } from "../src/agents/runtime.ts";
import { ownData, portsToTry } from "../src/ops/files.ts";

const call = (id: string, name: string) => ({ type: "assistant", message: { content: [{ type: "tool_use", id, name, input: {} }] } });
const result = (id: string, text: string, isError = true) => ({ type: "user", message: { content: [{ type: "tool_result", tool_use_id: id, is_error: isError, content: text }] } });

test("claude: a call to the station's tools that cannot connect, or its server failing, is the tools lost; a tool's refusal is not", () => {
  const calls = new Set<string>();
  // As seen in the field (a station started again on another port, the process taken up told the old one).
  assert.equal(toolsLostIn(call("a", "mcp__stillfail__chat_post"), calls), null);
  assert.ok(toolsLostIn(result("a", "ECONNREFUSED: Unable to connect. Is the computer able to access the url?"), calls)?.includes("ECONNREFUSED"));
  toolsLostIn(call("b", "mcp__ember__chat_state"), calls);
  assert.ok(toolsLostIn(result("b", 'MCP server "ember" is not connected'), calls)?.includes("not connected"));
  // The tool answered, refusing: it is reached.
  toolsLostIn(call("c", "mcp__stillfail__chat_post"), calls);
  assert.equal(toolsLostIn(result("c", "text is empty"), calls), null);
  // Another server's or a shell's failure is not the station's.
  toolsLostIn(call("d", "mcp__github__get_pr"), calls);
  assert.equal(toolsLostIn(result("d", "ECONNREFUSED"), calls), null);
  toolsLostIn(call("e", "Bash"), calls);
  assert.equal(toolsLostIn(result("e", "curl: (7) Failed to connect: connection refused"), calls), null);
  assert.equal(calls.size, 0, "each call forgotten once answered");
  // A turn starting with the server failed; pending is it still connecting.
  const init = (status: string) => ({ type: "system", subtype: "init", mcp_servers: [{ name: "stillfail", status }] });
  assert.ok(toolsLostIn(init("failed"), calls)?.includes("failed"));
  assert.equal(toolsLostIn(init("pending"), calls), null);
  assert.equal(toolsLostIn(init("connected"), calls), null);
});

test("claude: the address a process was started with is read from its arguments", () => {
  const config = (name: string) => JSON.stringify({ mcpServers: { [name]: { type: "http", url: "http://127.0.0.1:12671/mcp", headers: {} } } });
  assert.equal(mcpUrlOf(["-p", "--mcp-config", config("stillfail")]), "http://127.0.0.1:12671/mcp");
  assert.equal(mcpUrlOf(["--mcp-config", config("ember")]), "http://127.0.0.1:12671/mcp");
  assert.equal(mcpUrlOf(["-p"]), null);
  assert.equal(mcpUrlOf(["--mcp-config", "{not json"]), null);
});

test("codex: a failed call to the station's tools that cannot connect is the tools lost", () => {
  const done = (server: string, status: string, message: string | null) => ({ item: { type: "mcpToolCall", id: "i", server, tool: "chat_post", status, error: message === null ? null : { message } } });
  assert.ok(codexToolsLost("item/completed", done("stillfail", "failed", "error sending request: connection refused"))?.includes("connection refused"));
  assert.equal(codexToolsLost("item/completed", done("stillfail", "failed", "text is empty")), null);
  assert.equal(codexToolsLost("item/completed", done("stillfail", "completed", null)), null);
  assert.equal(codexToolsLost("item/completed", done("github", "failed", "connection refused")), null);
  assert.equal(codexToolsLost("item/started", done("stillfail", "failed", "connection refused")), null);
  assert.ok(unreachable("fetch failed") && !unreachable("unknown session"));
});

test("on its own, a station tries the port named, else the one it had, the usual one on the machine's own data, then any", () => {
  assert.deepEqual(portsToTry(5000, 12671, 4750, true), [5000]);
  assert.deepEqual(portsToTry(undefined, 12671, 4750, true), [12671, 4750, 0]);
  assert.deepEqual(portsToTry(undefined, 4750, 4750, true), [4750, 0]);
  assert.deepEqual(portsToTry(undefined, undefined, 4750, true), [4750, 0]);
  // A test's or a development station's data: never the usual port.
  assert.deepEqual(portsToTry(undefined, undefined, 4750, false), [0]);
  assert.deepEqual(portsToTry(undefined, 12671, 4750, false), [12671, 0]);
  const home = join("/", "home", "u");
  assert.ok(ownData(join(home, ".stillfail"), home));
  assert.ok(ownData(join(home, ".ember"), home));
  assert.ok(!ownData(join("/", "tmp", "scratchpad", "inst"), home));
});
