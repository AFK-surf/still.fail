// The agents' tools for their conversations: chat_post, chat_state, chat_history,
// chat_leave, chat_list, chat_read, session_send, session_history, and chat_create (sessions/opened.ts), which came after the Rust.
// Names and parameters are the Rust station's; the descriptions say what a tool does and when, the details being the
// skills' (src/skills/), and are held under ceilings (test/tools-weight.test.ts). What they do is src/sessions/.
// chat_post still takes `options` beside `text` and kind need_decision, from before cards (sessions/args.ts), and
// declares neither: with them its schema was over what Codex keeps the parameter descriptions of.
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { chatHistory, chatLeave, chatPost, chatState, mayStage, staged, target, unheld, NOT_POSTED } from "../sessions/conversations.ts";
import type { Hub } from "../sessions/hub.ts";
import { sessionSend } from "../sessions/messages.ts";
import { chatCreate } from "../sessions/opened.ts";
import { chatArchive } from "../sessions/chat-archive.ts";
import type { Args } from "../sessions/args.ts";
import { chatList, chatRead, elsewhere, readAfar, scopeOf, sessionHistory } from "../sessions/others.ts";
import { suggestArchive } from "../sessions/review.ts";
import { STILLFAIL_SURFACE } from "../store/store.ts";
import type { Tool } from "./mcp.ts";
import { slackTools } from "./slack.ts";

export const CHAT_POST = {
  name: "chat_post",
  description:
    "Post a message to one of your conversations, in Markdown (Slack and Feishu draw it too; Formatting in your instructions says what differs). kind ends your turn with it; card carries what people answer by choosing or typing (skill stillfail-chats: cards, held posts). With only to and title it names the conversation, nothing posted or ended.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS: the thread attribute of the message you are answering."
      },
      "send": {
        "type": "string",
        "description": "The id of a post held back (its chat_post answered it): sends it as written. Give only to, send and the state the turn now ends with (kind, need, done, about)."
      },
      "withdraw": {
        "type": "string",
        "description": "The message ts of your own answer card to withdraw, its question resolved or obsolete. With to alone: nothing is sent and no turn ends."
      },
      "text": {
        "type": "string",
        "description": "The message, formatted for where it goes (posted as written). With a card: what it asks and the facts it turns on, answerable from this message alone."
      },
      "kind": {
        "type": "string",
        "enum": [
          "all_done",
          "need_human"
        ],
        "description": "Omit for a progress update. all_done: nothing in the chat is left unfinished; give done. need_human: a person has to give, do or decide something (a card you posted included); give need. Only for a real unresolved need: a factual answer alone needs no follow-up question."
      },
      "need": {
        "type": "string",
        "description": "For need_human (required): what the person has to give, do or decide, in one sentence in their language (要 Stripe 的测试 key); to verify something, where, how and what to look at; work of yours still running, after the ask (选统计口径；CI 还在跑)."
      },
      "about": {
        "type": "string",
        "description": "With kind: the ts of the message here the state is about (all_done: the result's; need_human: the one that asks, by default the card still waiting there, or this post's own). People's lists jump to it."
      },
      "done": {
        "type": "string",
        "description": "For all_done (required): why nothing in the chat is left, in their language: what was finished and where it landed or how it was confirmed, naming the evidence (已合进 main 82f108a5，测试版 1389 已发). Not just 做完了 or done: that is refused."
      },
      "files": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Absolute paths of files on this machine to attach (up to 10, 50 MB each), shown below the text unless it places one by name (Formatting in your instructions)."
      },
      "title": {
        "type": "string",
        "description": "The conversation's name in still.fail lists (nothing is renamed in Slack): a few words on what it is about, in their language, at most 30 characters. Another only when the chat has moved to something else, not to reword it: the station changes it rarely, and never over a name people gave."
      },
      "card": {
        "type": "object",
        "description": "What people answer this message with, in the chat and in their 待处理: options, text (a value they type) or login (one the login tool started). It does not end your turn: end need_human. A newer card replaces the previous one. A person's next message closes it, a decision or not: ask again with a new card if it is still needed.",
        "properties": {
          "type": {
            "type": "string",
            "enum": [
              "options",
              "text",
              "login"
            ]
          },
          "login": {
            "type": "string",
            "description": "For a login card (required): the id the login tool's start answered."
          },
          "station": {
            "type": "string",
            "description": "For a login card on another station's login: that station's key."
          },
          "options": {
            "type": "array",
            "description": "For an options card (required): the answers (1 to 6).",
            "items": {
              "type": "object",
              "properties": {
                "label": {
                  "type": "string",
                  "description": "A short phrase that reads on its own, in their language (按今天累计, 先不改)."
                },
                "detail": {
                  "type": "string",
                  "description": "One line on what choosing it leads to."
                },
                "recommended": {
                  "type": "boolean",
                  "description": "The one you recommend (at most one); the card shows it last."
                },
                "action": {
                  "type": "string",
                  "enum": [
                    "reply",
                    "close"
                  ],
                  "description": "reply (default) sends you the chosen label. close ends this need_human with no message and without waking you (you are told the choice with what you are next handed): only where choosing it needs no further work (不需要部署)."
                }
              },
              "required": [
                "label"
              ],
              "additionalProperties": false
            }
          },
          "assignee": {
            "type": "string",
            "description": "The email of the person who must decide, from the conversation: the card is in their 待处理 alone. Always set it."
          },
          "placeholder": {
            "type": "string",
            "description": "For a text card: a hint shown in the empty field (sk_test_…)."
          }
        },
        "required": [
          "type"
        ],
        "additionalProperties": false
      }
    },
    "required": [
      "to"
    ],
    "additionalProperties": false
  },
};

export const CHAT_STATE = {
  name: "chat_state",
  description:
    "Record how this turn ends without posting another message (End every turn, in your instructions): all_done, need_human (about points to your visible question unless a card is pending: need alone is not shown in the chat) or waiting (only work you started that brings you back by itself, with nothing else left to do meanwhile; waiting on a person is need_human).",
  inputSchema: {
    "type": "object",
    "properties": {
      "kind": {
        "type": "string",
        "enum": [
          "all_done",
          "need_human",
          "waiting"
        ]
      },
      "need": {
        "type": "string",
        "description": "For need_human (required): as chat_post's need."
      },
      "about": {
        "type": "string",
        "description": "The ts of the message in your conversation the state is about (all_done: the result's; need_human: the one where you visibly ask what is still needed, required unless a card is pending; waiting: the one saying what you started). People's lists jump to it."
      },
      "done": {
        "type": "string",
        "description": "For all_done (required): as chat_post's done."
      },
      "seconds": {
        "type": "integer",
        "minimum": 10,
        "maximum": 3600,
        "description": "For waiting: how long until the work brings you back; if nothing has by then, you are asked again (not with watch). A fallback only: something must watch the work. Where it truly cannot be watched, the shortest it could take."
      },
      "for": {
        "type": "string",
        "description": "For waiting (required): what you wait for, in a few words people read under your name, in their language (e.g. 安卓滑动测试在模拟器上跑完)."
      },
      "watch": {
        "type": "boolean",
        "description": "For waiting: true when all you wait on is your watch keeping on (job_start with watch): people see the chat as watching, and the clock does not ask you again. Left out when you wait on anything else, even with a watch running."
      }
    },
    "required": [
      "kind"
    ],
    "additionalProperties": false
  },
};

export const CHAT_LEAVE = {
  name: "chat_leave",
  description:
    "Stop following a Slack or Feishu thread you take part in, when people there tell you to (stop watching, 别跟了): its messages stop reaching you until someone mentions you there again, which brings you back. Tell them so in the thread first. You can still read it with chat_history and post there.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS: the thread to leave."
      }
    },
    "required": [
      "to"
    ],
    "additionalProperties": false
  },
};

export const CHAT_HISTORY = {
  name: "chat_history",
  description:
    "Read earlier messages of one of your conversations, oldest first, your own posts included.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS: the thread attribute of the message you are answering."
      },
      "before": {
        "type": "string",
        "description": "Only messages older than this message ts."
      },
      "limit": {
        "type": "integer",
        "minimum": 1,
        "maximum": 200,
        "description": "Default 30."
      }
    },
    "required": [
      "to"
    ],
    "additionalProperties": false
  },
};

export const CHAT_LIST = {
  name: "chat_list",
  description:
    "List the conversations on this station (still.fail chats and Slack threads), the latest first: each with its address, title, agents (session keys), last message and, on a station of a workspace, its link (the one to give people); then the chats other workspaces share with this one, by their links. Use it to find a chat people refer to.",
  inputSchema: {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Only conversations whose title, last message or agents contain this (case-insensitive)."
      },
      "limit": {
        "type": "integer",
        "minimum": 1,
        "maximum": 100,
        "description": "Default 20."
      }
    },
    "additionalProperties": false
  },
};

export const CHAT_READ = {
  name: "chat_read",
  description:
    "Read the messages of any conversation, not only your own, oldest first: one on this station or, by its link, on another station of the workspace or one another workspace shares with this one.",
  inputSchema: {
    "type": "object",
    "properties": {
      "chat": {
        "type": "string",
        "description": "The chat: its link as people give it (…/chats/<key>, …/o/<workspace>/<station>/<key>), a thread address CHANNEL/THREAD_TS, or a session key (reads that session's chat)."
      },
      "before": {
        "type": "string",
        "description": "Only messages older than this message ts."
      },
      "limit": {
        "type": "integer",
        "minimum": 1,
        "maximum": 200,
        "description": "Default 30."
      },
      "fetch": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "A chat on another station: its attachments to fetch here although large, by the paths listed there. Those up to 16 MB come by themselves, their paths replaced with where they are here."
      }
    },
    "required": [
      "chat"
    ],
    "additionalProperties": false
  },
};

export const SESSION_SEND = {
  name: "session_send",
  description:
    "Send a message to another session's agent: a chat on this station, on another station of the workspace, or one another workspace shares with this one to write to. Its agent takes it like any message, headed with a link to your chat, and it stays out of that chat's conversation. It answers you the same way, so to wait for the answer end your turn waiting. Use chat_post for your own conversations.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "The other chat: its link (…/chats/<key>, …/o/<workspace>/<station>/<key>, the link a message from it is headed with), its session key, or a thread address CHANNEL/THREAD_TS on this station."
      },
      "text": {
        "type": "string",
        "description": "The message, standing on its own: what you need or found, with what the other agent needs to act on it. Markdown."
      },
      "files": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Absolute local paths of files to attach (at most 10, each up to 50 MB): copied to that chat, and its agent gets their paths there."
      }
    },
    "required": [
      "to",
      "text"
    ],
    "additionalProperties": false
  },
};

export const CHAT_CREATE = {
  name: "chat_create",
  description:
    "Open a new still.fail chat with an agent of its own, on this station or another station of the workspace, for work that should go on visibly beside yours (a part to do in parallel, something another machine is better placed for). It begins with your message. You are told how each of its turns ends: to wait for it, end your turn waiting. Write to its agent with session_send to its link. When an answer was uncertain, call again with the same key, which gives the chat made then rather than opening another. Skill stillfail-chats (Other agents) says more.",
  inputSchema: {
    "type": "object",
    "properties": {
      "key": {
        "type": "string",
        "description": "A name of your choosing for this chat (e.g. build-android): the same key again gives the same chat; a new one opens another."
      },
      "text": {
        "type": "string",
        "description": "The first message, standing on its own: what its agent is to do and what it needs to do it (it does not see your chat). Markdown."
      },
      "title": {
        "type": "string",
        "description": "The chat's name in still.fail lists: a few words, in their language (at most 120 characters). Its agent names it when left out."
      },
      "station": {
        "type": "string",
        "description": "Another station of the workspace to open it on, by its name or id. Left out: this station."
      },
      "runtime": {
        "type": "string",
        "enum": RUNTIME_KINDS,
        "description": "Its agent's runtime (dsh: DeepSeek Harness, grok: Grok Build, cursor: Cursor, devin: Devin, hermes: Hermes Agent, agy: Antigravity CLI). Default: that of its model."
      },
      "model": {
        "type": "string",
        "description": "Its agent's model. Default: the one the person it goes to uses most on that station, when one clearly leads; else it is not opened and you are told which to ask them about."
      },
      "effort": {
        "type": "string",
        "description": "Its agent's reasoning effort. Default: the one that person has opened most chats with on that runtime and model there lately, else its model's."
      },
      "fast": {
        "type": "boolean",
        "description": "Fast mode."
      },
      "context": {
        "type": "integer",
        "description": "The most context it runs with, in tokens."
      },
      "preset": {
        "type": "string",
        "description": "One of this station's presets, by name or id, taken as it is (skill stillfail-chats). Left out: none."
      },
      "files": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Absolute local paths of files to attach to the first message (at most 10, each up to 50 MB): copied to that chat, and its agent gets their paths there."
      }
    },
    "required": [
      "key",
      "text"
    ],
    "additionalProperties": false
  },
};

export const CHAT_ARCHIVE = {
  name: "chat_archive",
  description: "Archive another still.fail chat on this station or another station of your workspace. As when a person archives it in the app, its own session goes with it: its running turn can finish, and its jobs and services stop. The chat and its messages remain, but its workspace files may later be cleaned up. Calling again on an already manually archived chat leaves it as it was.",
  inputSchema: {
    type: "object",
    properties: {
      chat: { type: "string", description: "Another chat's link, or its thread address or session key on this station; chat_list finds them." },
    },
    required: ["chat"],
    additionalProperties: false,
  },
};

export const SESSION_HISTORY = {
  name: "session_history",
  description:
    "Read a session's execution history, as the pages show it: what its agent thought, the tools it called and what they returned, numbered #0 onwards. The latest entries unless before is given. A session on another station of the workspace is read by its chat's link.",
  inputSchema: {
    "type": "object",
    "properties": {
      "chat": {
        "type": "string",
        "description": "Whose: a session key, a chat's link (…/chats/<key>, …/o/…/<key>, or an execution history link with ?history=<key>&entry=<n>, which shows the entries around n), or a thread address CHANNEL/THREAD_TS with one agent."
      },
      "before": {
        "type": "integer",
        "minimum": 0,
        "description": "Only entries before #before (the reply says where older ones start)."
      },
      "limit": {
        "type": "integer",
        "minimum": 1,
        "maximum": 200,
        "description": "Default 40."
      },
      "max_chars": {
        "type": "integer",
        "minimum": 100,
        "maximum": 4000,
        "description": "Each entry cut to this many characters. Default 1500."
      }
    },
    "required": [
      "chat"
    ],
    "additionalProperties": false
  },
};

/// A chat on another station, by its link: read there, in the session's workspace (others.ts `readAfar`); null to read it
/// here.
function afar(hub: Hub, key: string, tool: "chat_read" | "session_history", args: Args): Promise<string> | null {
  const station = typeof args.chat === "string" ? elsewhere(hub, key, args.chat) : null;
  return station !== null ? readAfar(hub, key, station, tool, args) : null;
}

/// `run` with `args`' files (and with `links` its text's local links) in folders macOS protects copied first
/// (conversations.ts `staged`), the copies removed after.
function withStaged(hub: Hub, key: string, args: Args, links: boolean, run: (args: Args) => Promise<string>): Promise<string> {
  return stagedRun(hub, key, args, links, run);
}

function stagedRun(hub: Hub, key: string, args: Args, links: boolean, run: (args: Args) => Promise<string>): Promise<string> {
  // Nothing that could be in such a folder: as it was, not a moment later.
  if (!mayStage(hub, args, links)) return run(args);
  return (async () => {
    const { args: given, done } = await staged(hub, key, args, links);
    try {
      return await run(given);
    } finally {
      done();
    }
  })();
}

/// The hub's tools, in the Rust station's order (slack_api, second, is slack.ts's).
export function chatTools(hub: Hub): Tool[] {
  return [
    {
      ...CHAT_POST,
      run: async (key, args) => {
        // Its files and local links in a folder macOS protects copied first, never touched on the station's thread
        // (conversations.ts `staged`); links only where they become attachments (still.fail chats).
        let stillfail = false;
        try {
          stillfail = target(hub, key, args.to).thread.surface === STILLFAIL_SURFACE;
        } catch {}
        // A held post sent by its id is staged again, as it was written.
        const held = unheld(hub, key, args);
        const said = await withStaged(hub, key, held.args, stillfail, (a) => chatPost(hub, key, a, held));
        // A turn ended all_done (or final from before): whether the chat is finished is asked in the background.
        if ((args.kind === "all_done" || args.kind === "final") && !said.startsWith(NOT_POSTED)) suggestArchive(hub, key);
        return said;
      },
    },
    ...slackTools(hub),
    { ...CHAT_STATE, run: (key, args) => chatState(hub, key, args) },
    { ...CHAT_LEAVE, run: async (key, args) => chatLeave(hub, key, args) },
    { ...CHAT_HISTORY, run: (key, args) => chatHistory(hub, key, args) },
    { ...CHAT_LIST, run: async (key, args, signal) => chatList(hub, key, args, signal) },
    { ...CHAT_READ, run: (key, args) => afar(hub, key, "chat_read", args) ?? chatRead(hub, key, args, undefined, scopeOf(hub, key)) },
    { ...SESSION_SEND, run: (key, args) => withStaged(hub, key, args, false, (a) => sessionSend(hub, key, a)) },
    { ...CHAT_CREATE, run: (key, args) => withStaged(hub, key, args, false, (a) => chatCreate(hub, key, a)) },
    { ...CHAT_ARCHIVE, run: (key, args) => chatArchive(hub, key, args) },
    { ...SESSION_HISTORY, run: async (key, args) => afar(hub, key, "session_history", args) ?? sessionHistory(hub, args, scopeOf(hub, key)) },
  ];
}
