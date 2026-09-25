// ember's MCP endpoint (streamable HTTP, JSON responses only). Every request
// carries the session's bearer token; tools run on behalf of that session.
import type { IncomingMessage, ServerResponse } from "node:http";
import { log } from "./log.ts";

export interface Tool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  /** Returns the text the agent sees. Throwing returns the message as a tool error. */
  run(sessionKey: string, args: Record<string, unknown>): Promise<string>;
}

type Json = Record<string, unknown>;

export class McpEndpoint {
  readonly #tools = new Map<string, Tool>();
  readonly #resolve: (token: string) => string | undefined;

  /** `resolve` maps a bearer token to a session key. */
  constructor(resolve: (token: string) => string | undefined, tools: Tool[]) {
    this.#resolve = resolve;
    for (const tool of tools) this.#tools.set(tool.name, tool);
  }

  async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.method !== "POST") {
      res.writeHead(405, { allow: "POST" }).end();
      return;
    }
    const token = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
    const sessionKey = token ? this.#resolve(token) : undefined;
    if (!sessionKey) {
      res.writeHead(401, { "content-type": "application/json" }).end(JSON.stringify({ error: "unknown session token" }));
      return;
    }
    let message: { id?: string | number; method?: string; params?: Json };
    try {
      message = JSON.parse(await readBody(req)) as typeof message;
    } catch {
      res.writeHead(400, { "content-type": "application/json" })
        .end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "parse error" } }));
      return;
    }
    if (message.id === undefined) {
      res.writeHead(202).end(); // a notification
      return;
    }
    const reply = (body: Json) =>
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ jsonrpc: "2.0", id: message.id, ...body }));
    switch (message.method) {
      case "initialize":
        reply({ result: {
          protocolVersion: typeof message.params?.protocolVersion === "string" ? message.params.protocolVersion : "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: "ember", version: "0.0.0" },
        } });
        return;
      case "ping":
        reply({ result: {} });
        return;
      case "tools/list":
        reply({ result: { tools: [...this.#tools.values()].map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) } });
        return;
      case "tools/call": {
        const name = String(message.params?.name ?? "");
        const tool = this.#tools.get(name);
        if (!tool) {
          reply({ error: { code: -32602, message: `unknown tool ${name}` } });
          return;
        }
        const args = (message.params?.arguments ?? {}) as Json;
        try {
          const text = await tool.run(sessionKey, args);
          reply({ result: { content: [{ type: "text", text }] } });
        } catch (error) {
          log.warn("tool call failed", { sessionKey, tool: name, error });
          reply({ result: { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], isError: true } });
        }
        return;
      }
      default:
        reply({ error: { code: -32601, message: `method not found: ${String(message.method)}` } });
    }
  }
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (chunk: string) => { body += chunk; });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}
