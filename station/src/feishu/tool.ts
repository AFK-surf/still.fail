// feishu_api (docs/feishu.md「agent 看到的」): any Feishu OpenAPI call as the bot of one of the session's Feishu chats.
// Messages are not sent through it (chat_post answers a chat, and keeps what was said), nor is the app itself managed.
import { jsString } from "../sessions/args.ts";
import { target } from "../sessions/conversations.ts";
import type { Hub } from "../sessions/hub.ts";
import type { Tool } from "../tools/mcp.ts";

export const FEISHU_API = {
  name: "feishu_api",
  description:
    "Call a Feishu (Lark) OpenAPI method as your Feishu bot, e.g. GET /open-apis/im/v1/chats/:chat_id, GET /open-apis/docx/v1/documents/:id/raw_content, POST /open-apis/im/v1/messages/:message_id/reactions. What it may read and change is what the app's permissions allow. Send and answer messages with chat_post, not this.",
  inputSchema: {
    type: "object",
    properties: {
      method: { type: "string", description: 'An HTTP method and the path, e.g. "GET /open-apis/contact/v3/users/ou_xxx".' },
      params: {
        type: "object",
        description: "A GET's query parameters; for other methods the JSON body (its query parameters under \"query\").",
        additionalProperties: true,
      },
      to: { type: "string", description: "CHANNEL/THREAD_TS of one of your Feishu conversations: whose bot to call as. Default: this session's own connect." },
    },
    required: ["method"],
    additionalProperties: false,
  },
};

/// Paths that are not for agents: the app's credentials and settings.
const MANAGING = ["/open-apis/auth/", "/open-apis/application/", "/open-apis/app_engine/"];

export function feishuTools(hub: () => Hub | undefined, isFeishu: (connect: string) => boolean): Tool[] {
  return [
    {
      ...FEISHU_API,
      run: async (key, args) => {
        const h = hub();
        if (!h) throw new Error("the station is starting; try again in a moment");
        const method = (args.method === undefined ? "" : jsString(args.method)).trim();
        const params = args.params !== null && typeof args.params === "object" && !Array.isArray(args.params) ? (args.params as Record<string, unknown>) : {};
        const path = method.split(/\s+/)[1] ?? "";
        const verb = (method.split(/\s+/)[0] ?? "").toUpperCase();
        if (MANAGING.some((p) => path.startsWith(p))) throw new Error(`${path} is not for agents: it manages the Feishu app itself`);
        if (verb !== "GET" && path.startsWith("/open-apis/im/v1/messages") && !/\/reactions(\/|$)/.test(path)) {
          throw new Error("send, answer and change messages with chat_post (it keeps what is said in the conversation); feishu_api reads messages and adds reactions");
        }
        let connect: string | null = null;
        if (typeof args.to === "string" && args.to !== "") connect = target(h, key, args.to).connect;
        else {
          const own = h.store.getSession(key)?.connect ?? null;
          connect = own !== null && isFeishu(own) ? own : (h.store.sessionThreads(key).map((t) => t.connect).find(isFeishu) ?? null);
        }
        if (connect === null || !isFeishu(connect)) throw new Error("this session has no Feishu conversation: give to= one of your Feishu chats");
        const chat = h.chat(connect);
        if (!chat.api) throw new Error("this Feishu connect is not connected");
        const result = await chat.api(method, params);
        const text = JSON.stringify(result);
        const chars = Array.from(text);
        return chars.length > 60_000 ? `${chars.slice(0, 60_000).join("")}… (cut at 60000 characters; ask for less, e.g. a smaller page_size)` : text;
      },
    },
  ];
}
