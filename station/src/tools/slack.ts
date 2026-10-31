// slack_api (the Rust station's hub.rs): any Slack Web API method, as the session's bot (or the bot of one of its Slack
// conversations, `to`; a still.fail chat's, the station's Slack bot, `bot`). The method's shape, what is not for agents, and the threads rule for writes (WRITES) are
// src/sessions/conversations.ts's `slackApi`.
import { jsString } from "../sessions/args.ts";
import { slackApi, target } from "../sessions/conversations.ts";
import type { Hub } from "../sessions/hub.ts";
import type { Tool } from "./mcp.ts";

export const SLACK_API = {
  name: "slack_api",
  description:
    "Call any Slack Web API method as your Slack bot, e.g. conversations.history, users.info, reactions.add, chat.update, chat.postMessage in a channel, conversations.open then chat.postMessage for a direct message. A chat that did not start in Slack (a still.fail chat) calls as the station's Slack bot. Writes in a thread another session takes part in are refused; posting in a thread nobody else is in, or a new message, makes that thread one of your conversations (its replies come to you). Prefer chat_post to answer the thread you are working in.",
  inputSchema: {
    "type": "object",
    "properties": {
      "method": {
        "type": "string",
        "description": "The Web API method, e.g. \"conversations.replies\"."
      },
      "params": {
        "type": "object",
        "description": "Its arguments as Slack documents them (blocks and other structures as JSON values).",
        "additionalProperties": true
      },
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS of one of your Slack conversations: whose bot to call as. Default: this session's own connect."
      },
      "bot": {
        "type": "string",
        "description": "Which of the station's Slack bots to call as, by its id or name, when the chat has none of its own and the station has several (the error names them). Default: the one bound to your runtime."
      }
    },
    "required": [
      "method"
    ],
    "additionalProperties": false
  },
};

export function slackTools(hub: Hub): Tool[] {
  return [
    {
      ...SLACK_API,
      run: (key, args) => {
        const method = (args.method === undefined ? "" : jsString(args.method)).trim();
        const params = args.params !== null && typeof args.params === "object" && !Array.isArray(args.params) ? args.params : {};
        const via = typeof args.to === "string" && args.to !== "" ? target(hub, key, args.to).connect : null;
        const bot = typeof args.bot === "string" && args.bot.trim() !== "" ? args.bot : null;
        return slackApi(hub, key, method, params, via, bot);
      },
    },
  ];
}
