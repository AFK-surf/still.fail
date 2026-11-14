// The station's MCP endpoint: streamable HTTP, JSON responses only. Every request carries the
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
  run(session: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<string>;
  /// What the agent sees when it is more than text (a screenshot): called instead of `run` where there is one.
  content?(session: string, args: Record<string, unknown>): Promise<ToolReply>;
};

export type Reply = { status: number; body?: unknown };

/// A tool as tools/list declares it.
const declared = (t: Tool) => ({ name: t.name, description: t.description, inputSchema: t.inputSchema });
/// What a tool's declaration weighs: its bytes as JSON, as a runtime that budgets its tools measures them closely enough.
export const weight = (t: Tool) => Buffer.byteLength(JSON.stringify(declared(t)));

/// Declared first, whatever the budget: what every turn needs (posting, ending it, reading the chat) and the work
/// sent elsewhere.
export const CORE = ["chat_post", "chat_state", "chat_history", "chat_read", "job_start", "job_log", "job_list", "job_stop", "station_task", "station_file", "skill_read"];

/// What every turn calls: an agent's answer reaches people only through chat_post, and a turn ends with chat_state.
export const EVERY_TURN = ["chat_post", "chat_state"];

/// What a session's runtime needs of its list of tools; nothing said, the list is every tool as it is.
export type Listing = {
  /// How many bytes of tools it declares to its model, for one that drops those beyond (`fitted`).
  budget?: number;
  /// The `_meta` by which it declares a tool to its model from the first request, for one that otherwise keeps a
  /// server's tools back until its model searches for them: put on the EVERY_TURN tools alone, so that a turn does not
  /// begin with a search for what it must call, and the rest stay as cheap as that runtime made them.
  loaded?: Record<string, unknown>;
};

/// The tool that reaches those a budget left undeclared.
export const INDIRECT = "station_tool";

/// The tools to declare within `budget` bytes, and the rest, reached through INDIRECT. A runtime that budgets its tools
/// drops the largest beyond it and gives the model no way to call them (Antigravity CLI 1.5.6 in ACP: chat_post,
/// the largest, went first, and a session could no longer post). So the list is fitted here, deterministically: the
/// CORE tools, then the others from the lightest while they fit, and INDIRECT naming the rest.
export function fitted(tools: readonly Tool[], budget: number): { declared: Tool[]; indirect: Tool[] } {
  const core = CORE.flatMap((name) => tools.filter((t) => t.name === name));
  const others = tools.filter((t) => !CORE.includes(t.name)).sort((a, b) => weight(a) - weight(b) || (a.name < b.name ? -1 : 1));
  const fits = (list: readonly Tool[], rest: readonly Tool[]) => list.reduce((n, t) => n + weight(t), 0) + (rest.length === 0 ? 0 : weight(indirectTool(rest)));
  const out = [...core];
  let i = 0;
  while (i < others.length && fits([...out, others[i]!], others.slice(i + 1)) <= budget) out.push(others[i++]!);
  const indirect = others.slice(i);
  return { declared: tools.filter((t) => out.includes(t)), indirect };
}

/// The tool that calls one left undeclared by name: given only `name`, it answers that tool's description and
/// parameters; given `arguments` too, it runs it (the endpoint runs it as it runs any call, refusals included).
export function indirectTool(rest: readonly Tool[]): Tool {
  const lines = rest.map((t) => `${t.name}: ${firstSentence(t.description)}`).join("\n");
  return {
    name: INDIRECT,
    description: `Call a station tool not declared to you, by name. First call it with only name to read that tool's description and parameters, then with name and arguments to run it. The tools:\n${lines}`,
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", enum: rest.map((t) => t.name) },
        arguments: { type: "object", description: "The tool's arguments, as its parameters say." },
      },
      required: ["name"],
    },
    run: async () => {
      throw new Error("station_tool is run by the endpoint");
    },
  };
}

const firstSentence = (text: string) => {
  const m = /^.*?[.:](?=\s|$)/s.exec(text);
  return (m ? m[0] : text).replace(/\s+/g, " ").slice(0, 160);
};

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
  /// What a session's runtime needs of its list, where it needs anything.
  private listing?: (session: string) => Listing | undefined;

  constructor(resolve: (token: string) => string | undefined, tools: readonly Tool[] | (() => readonly Tool[]), gate?: (session: string) => string | undefined, listing?: (session: string) => Listing | undefined) {
    this.tools = typeof tools === "function" ? tools : () => tools;
    this.resolve = resolve;
    this.gate = gate;
    this.listing = listing;
  }

  /// The tools a session is declared: all of them, or those within its runtime's budget and INDIRECT for the rest;
  /// the EVERY_TURN ones with its runtime's `loaded`, whose bytes its budget counts. A runtime that needs nothing is
  /// declared them byte for byte as before there was any of this: some validate or weigh what they are given.
  private listed(session: string): unknown[] {
    const all = this.tools();
    const { budget, loaded } = this.listing?.(session) ?? {};
    const say = (t: Tool) => (loaded !== undefined && EVERY_TURN.includes(t.name) ? { ...declared(t), _meta: loaded } : declared(t));
    if (budget === undefined) return all.map(say);
    const marks = all.reduce((n, t) => n + Buffer.byteLength(JSON.stringify(say(t))) - weight(t), 0);
    const { declared: fit, indirect } = fitted(all, budget - marks);
    return (indirect.length === 0 ? fit : [...fit, indirectTool(indirect)]).map(say);
  }

  async handle(method: string, authorization: string | undefined, body: Buffer | string, signal?: AbortSignal): Promise<Reply> {
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
        return reply({ result: { tools: this.listed(session) } });
      case "tools/call": {
        let name = typeof params?.name === "string" ? params.name : "";
        let given = params?.arguments && typeof params.arguments === "object" && !Array.isArray(params.arguments) ? params.arguments : {};
        // One left undeclared, called through INDIRECT: its description and parameters, or its run as any call's.
        if (name === INDIRECT && !this.tools().some((t) => t.name === INDIRECT)) {
          const named = typeof given.name === "string" ? this.tools().find((t) => t.name === given.name) : undefined;
          if (!named) return reply({ result: { content: [{ type: "text", text: `No station tool ${JSON.stringify(given.name)}: name one listed in station_tool's description.` }], isError: true } });
          const args = given.arguments;
          if (args === undefined || args === null) return reply({ result: { content: [{ type: "text", text: JSON.stringify(declared(named)) }] } });
          if (typeof args !== "object" || Array.isArray(args)) return reply({ result: { content: [{ type: "text", text: "arguments must be an object." }], isError: true } });
          name = named.name;
          given = args;
        }
        const tool = this.tools().find((t) => t.name === name);
        if (!tool) return reply({ error: { code: -32602, message: `unknown tool ${name}` } });
        if (OUTWARD.includes(name)) {
          const why = this.gate?.(session);
          if (why !== undefined) {
            log.warn("mcp", "outward tool refused: the station is in no workspace", { session, tool: name });
            return reply({ result: { content: [{ type: "text", text: why }], isError: true } });
          }
        }
        const args = typed(given, tool.inputSchema);
        try {
          if (tool.content) {
            const { content, isError } = await tool.content(session, args);
            return reply({ result: { content, ...(isError ? { isError: true } : {}) } });
          }
          return reply({ result: { content: [{ type: "text", text: await tool.run(session, args, signal) }] } });
        } catch (error) {
          if (!signal?.aborted) log.warn("mcp", "tool call failed", { session, tool: name, error: (error as Error).message });
          return reply({ result: { content: [{ type: "text", text: (error as Error).message }], isError: true } });
        }
      }
      default:
        return reply({ error: { code: -32601, message: `method not found: ${message.method}` } });
    }
  }
}
