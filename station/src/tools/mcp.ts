// The station's MCP endpoint (the Rust station's mcp.rs): streamable HTTP, JSON responses only. Every request carries the
// session's bearer token; tools run on behalf of that session. This takes a request's method, authorization and body,
// and gives its status and body; the HTTP wiring is the server's.
import { log } from "../ops/log.ts";

/// The tools that reach out of the station, refused while it is in no workspace (`gated`): what posts or sends to
/// people (chat_post, into still.fail chats and Slack, with its files), slack_api (as the workspace's Slack bot) and
/// job_start, and the peer stations' tools (peer_forward too). The rest only read the station's own records, record the turn's state
/// (chat_state) or stop something (job_stop), and stay open.
export const OUTWARD = ["chat_post", "slack_api", "job_start", "station_list", "station_task", "station_file", "peer_forward"];

/// What a refused outward call says.
export const UNBOUND_REFUSAL =
  "Refused: this station is not in a still.fail workspace right now (it was removed from it, or has not joined one), so it does not post to chats or Slack, call Slack, or start jobs. Nothing was sent. Stop here and do not retry: when the station is back in its workspace, the interrupted work resumes and you can post then.";

/// A tool result's parts (MCP's content): text, or an image as base64 with its type.
export type Content = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };
export type ToolReply = { content: Content[]; isError?: boolean };

export type Tool = {
  name: string;
  description: string;
  inputSchema: unknown;
  /// The text the agent sees; a thrown error's message comes back as a tool error.
  run(session: string, args: Record<string, unknown>): Promise<string>;
  /// What the agent sees when it is more than text (a screenshot): called instead of `run` where there is one.
  content?(session: string, args: Record<string, unknown>): Promise<ToolReply>;
};

export type Reply = { status: number; body?: unknown };

/// The arguments as the tool's schema types them now. A session whose tool list is older than a parameter (it is told to
/// pass new ones anyway) sends it untyped, as text: `done: "true"` (2026-11-03: phone_use {done: true} from such a
/// session was read as not given). A boolean or number parameter given as its text is read as the value it says.
export function typed(args: Record<string, unknown>, schema: unknown): Record<string, unknown> {
  const properties = (schema as { properties?: Record<string, { type?: unknown }> } | null)?.properties;
  if (properties === undefined || properties === null) return args;
  let out: Record<string, unknown> | null = null;
  for (const [key, value] of Object.entries(args)) {
    if (typeof value !== "string") continue;
    const type = properties[key]?.type;
    const t = value.trim();
    const read = type === "boolean" ? (t === "true" ? true : t === "false" ? false : undefined)
      : (type === "number" || type === "integer") && /^-?\d+(\.\d+)?$/.test(t) ? Number(t) : undefined;
    if (read === undefined) continue;
    out ??= { ...args };
    out[key] = read;
  }
  return out ?? args;
}

export class McpEndpoint {
  /// The tools as they are now: the agents' own and the station's parts' (parts.ts), which say theirs as they are made.
  private tools: () => readonly Tool[];
  /// A bearer token's session key.
  private resolve: (token: string) => string | undefined;
  /// Why the OUTWARD tools are refused now for a session, if they are.
  private gate?: (session: string) => string | undefined;

  constructor(resolve: (token: string) => string | undefined, tools: readonly Tool[] | (() => readonly Tool[]), gate?: (session: string) => string | undefined) {
    this.tools = typeof tools === "function" ? tools : () => tools;
    this.resolve = resolve;
    this.gate = gate;
  }

  async handle(method: string, authorization: string | undefined, body: Buffer | string): Promise<Reply> {
    if (method !== "POST") return { status: 405 };
    const token = (authorization ?? "").replace(/^(Bearer |bearer )/, "").trim();
    const session = token ? this.resolve(token) : undefined;
    if (!session) return { status: 401, body: { error: "unknown session token" } };
    let message: any;
    try {
      message = JSON.parse(body.toString());
    } catch {
      return { status: 400, body: { jsonrpc: "2.0", id: null, error: { code: -32700, message: "parse error" } } };
    }
    if (message === null || typeof message !== "object" || !("id" in message)) return { status: 202 }; // a notification
    const params = message.params ?? null;
    const reply = (rest: Record<string, unknown>): Reply => ({ status: 200, body: { jsonrpc: "2.0", id: message.id, ...rest } });
    switch (typeof message.method === "string" ? message.method : "") {
      case "initialize":
        return reply({
          result: {
            protocolVersion: typeof params?.protocolVersion === "string" ? params.protocolVersion : "2025-06-18",
            capabilities: { tools: {} },
            serverInfo: { name: "still.fail", version: "0.0.0" },
          },
        });
      case "ping":
        return reply({ result: {} });
      case "tools/list":
        return reply({ result: { tools: this.tools().map((t) => ({ name: t.name, description: t.description, inputSchema: t.inputSchema })) } });
      case "tools/call": {
        const name = typeof params?.name === "string" ? params.name : "";
        const tool = this.tools().find((t) => t.name === name);
        if (!tool) return reply({ error: { code: -32602, message: `unknown tool ${name}` } });
        if (OUTWARD.includes(name)) {
          const why = this.gate?.(session);
          if (why !== undefined) {
            log.warn("mcp", "outward tool refused: the station is in no workspace", { session, tool: name });
            return reply({ result: { content: [{ type: "text", text: why }], isError: true } });
          }
        }
        const given = params?.arguments && typeof params.arguments === "object" && !Array.isArray(params.arguments) ? params.arguments : {};
        const args = typed(given, tool.inputSchema);
        try {
          if (tool.content) {
            const { content, isError } = await tool.content(session, args);
            return reply({ result: { content, ...(isError ? { isError: true } : {}) } });
          }
          return reply({ result: { content: [{ type: "text", text: await tool.run(session, args) }] } });
        } catch (error) {
          log.warn("mcp", "tool call failed", { session, tool: name, error: (error as Error).message });
          return reply({ result: { content: [{ type: "text", text: (error as Error).message }], isError: true } });
        }
      }
      default:
        return reply({ error: { code: -32601, message: `method not found: ${message.method}` } });
    }
  }
}
