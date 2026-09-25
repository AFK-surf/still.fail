import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { McpEndpoint } from "../src/mcp.ts";

async function serve(endpoint: McpEndpoint) {
  const server = createServer((req, res) => void endpoint.handle(req, res));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${(server.address() as { port: number }).port}/mcp`;
  const rpc = async (token: string | null, body: unknown) => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    });
    return { status: response.status, body: response.status === 202 ? null : await response.json() as any };
  };
  return { rpc, close: () => server.close() };
}

const endpoint = () => new McpEndpoint((token) => (token === "good" ? "session-1" : undefined), [{
  name: "echo",
  description: "echo",
  inputSchema: { type: "object" },
  run: async (key, args) => {
    if (args.fail) throw new Error("nope");
    return `${key}:${String(args.text)}`;
  },
}]);

test("requests without a known token are refused", async () => {
  const { rpc, close } = await serve(endpoint());
  try {
    assert.equal((await rpc(null, { jsonrpc: "2.0", id: 1, method: "tools/list" })).status, 401);
    assert.equal((await rpc("bad", { jsonrpc: "2.0", id: 1, method: "tools/list" })).status, 401);
  } finally {
    close();
  }
});

test("initialize, list and call run on behalf of the token's session", async () => {
  const { rpc, close } = await serve(endpoint());
  try {
    const init = await rpc("good", { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
    assert.equal(init.body.result.protocolVersion, "2025-06-18");
    assert.equal((await rpc("good", { jsonrpc: "2.0", method: "notifications/initialized" })).status, 202);
    const list = await rpc("good", { jsonrpc: "2.0", id: 2, method: "tools/list" });
    assert.deepEqual(list.body.result.tools.map((t: any) => t.name), ["echo"]);
    const call = await rpc("good", { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "echo", arguments: { text: "hi" } } });
    assert.deepEqual(call.body.result, { content: [{ type: "text", text: "session-1:hi" }] });
    const failed = await rpc("good", { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "echo", arguments: { fail: true } } });
    assert.equal(failed.body.result.isError, true);
    assert.equal(failed.body.result.content[0].text, "nope");
  } finally {
    close();
  }
});
