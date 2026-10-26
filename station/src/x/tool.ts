// x_api (docs/x.md「agent 看到的」): X's API v2 read as the account of one of the session's X conversations. It only
// reads (a post, a user, a search): the agent's words go with chat_post, which keeps what was said. Each post or user it
// reads is billed to the account's app.
import { jsString } from "../sessions/args.ts";
import { target } from "../sessions/conversations.ts";
import type { Hub } from "../sessions/hub.ts";
import type { Tool } from "../tools/mcp.ts";

export const X_API = {
  name: "x_api",
  description:
    "Read X's API v2 as your X account, e.g. GET /2/tweets/:id, GET /2/users/by/username/:username, GET /2/tweets/search/recent (params: query, max_results). X bills each post ($0.005) and user ($0.010) it returns: ask for few. It only reads: answer with chat_post.",
  inputSchema: {
    type: "object",
    properties: {
      method: { type: "string", description: 'GET and the path, e.g. "GET /2/tweets/1234567890".' },
      params: { type: "object", description: "Query parameters (post.fields, expansions, max_results…).", additionalProperties: true },
      to: { type: "string", description: "POST_ID/POST_ID of one of your X conversations: whose account to read as. Default: this session's own connect." },
    },
    required: ["method"],
    additionalProperties: false,
  },
};

export function xTools(hub: () => Hub | undefined, isX: (connect: string) => boolean): Tool[] {
  return [
    {
      ...X_API,
      run: async (key, args) => {
        const h = hub();
        if (!h) throw new Error("the station is starting; try again in a moment");
        const method = (args.method === undefined ? "" : jsString(args.method)).trim();
        const params = args.params !== null && typeof args.params === "object" && !Array.isArray(args.params) ? (args.params as Record<string, unknown>) : {};
        let connect: string | null = null;
        if (typeof args.to === "string" && args.to !== "") connect = target(h, key, args.to).connect;
        else {
          const own = h.store.getSession(key)?.connect ?? null;
          connect = own !== null && isX(own) ? own : (h.store.sessionThreads(key).map((t) => t.connect).find(isX) ?? null);
        }
        if (connect === null || !isX(connect)) throw new Error("this session has no X conversation: give to= one of your X conversations");
        const chat = h.chat(connect);
        if (!chat.api) throw new Error("this X connect is not connected");
        const text = JSON.stringify(await chat.api(method, params));
        const chars = Array.from(text);
        return chars.length > 60_000 ? `${chars.slice(0, 60_000).join("")}… (cut at 60000 characters; ask for less, e.g. a smaller max_results)` : text;
      },
    },
  ];
}
