// The agents' tools for their conversations (the Rust station's hub.rs `tools`): chat_post, chat_state, chat_history,
// chat_list, chat_read, session_send, session_history, and chat_create (sessions/opened.ts), which came after the Rust.
// Names, descriptions and input schemas are the Rust station's, byte for byte (test/hub-tools.test.ts reads them from
// hub.rs and compares); what they do is src/sessions/.
import { sandboxed } from "../agents/sandbox.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { chatHistory, chatPost, chatState, mayStage, fromSandbox, staged, target } from "../sessions/conversations.ts";
import type { Hub } from "../sessions/hub.ts";
import { sessionSend } from "../sessions/messages.ts";
import { chatCreate } from "../sessions/opened.ts";
import type { Args } from "../sessions/args.ts";
import { chatList, chatRead, elsewhere, readAfar, scopeOf, sessionHistory } from "../sessions/others.ts";
import { suggestArchive } from "../sessions/review.ts";
import { STILLFAIL_SURFACE } from "../store/store.ts";
import type { Tool } from "./mcp.ts";
import { slackTools } from "./slack.ts";

export const CHAT_POST = {
  name: "chat_post",
  description:
    "Post a message to one of your conversations, in Markdown (a Slack thread and a Feishu chat draw it too; mentions and files differ: see Formatting in your instructions). Users always have a chat input box and can reply freely. When you ask people to choose among answers you can name or to confirm one, carry it as a card (options, a single one is fine), and a field (text) when they must write a value; no filler options or unnecessary questions. A post that ends your turn says how with kind: all_done (nothing in the chat is left unfinished: done says why, with the evidence) or need_human (a person has to give, do or decide something: need says what; after posting a card, this is how the turn ends).",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS: the thread attribute of the message you are answering."
      },
      "withdraw": {
        "type": "string",
        "description": "Withdraw your own answer card by its message ts when the question is resolved or obsolete. Use only to and withdraw; this sends no message, preserves the original post and does not finish your work. Then continue and record the correct ending state."
      },
      "text": {
        "type": "string",
        "description": "The message, formatted for where it goes (posted as written). With a card: what it asks and the facts it turns on, so it can be answered from this message alone."
      },
      "kind": {
        "type": "string",
        "enum": [
          "all_done",
          "need_human"
        ],
        "description": "Omit for a progress update. all_done: the chat has nothing unfinished at all (no branch left unmerged, no open question, nothing waiting for a yes); give done. need_human: a person has to give, do or decide something, or answer an open question (a card you posted included); give need. (need_decision, from before cards, is still taken: options, the turn ends need_human.)"
      },
      "need": {
        "type": "string",
        "description": "For need_human (required): what the person has to give, do or decide, in one sentence in the language people use there (e.g. 要 Stripe 的测试 key, 选统计口径); to verify something, where, how and what to look at; work of yours still running, after the ask (e.g. 选统计口径；CI 还在跑)."
      },
      "about": {
        "type": "string",
        "description": "With kind, optional: the ts of the message in this conversation the state is about (all_done: the one with the result; need_human: the one that asks, by default the card still waiting there, this post's own when it carries one). People's lists jump to it."
      },
      "done": {
        "type": "string",
        "description": "Only a real unresolved need requires need_human; a factual answer alone needs no follow-up decision. For all_done (required): why nothing in the chat is left, so people can trust it, in the language they use there: what was finished and where it landed or how it was confirmed, naming the evidence (a commit, a release, a person's confirmation, the answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以. Not just 做完了 or done: that is refused."
      },
      "files": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Absolute paths of files on this machine to attach (images show inline; in a Slack thread they are uploaded below the text). Shown below the text unless the text refers to one by its file name, as ![](shot.png) or [report](report.pdf), which places it there. Up to 10, 50 MB each."
      },
      "title": {
        "type": "string",
        "description": "The conversation's name in still.fail lists (including Slack threads; does not rename anything in Slack): a few words on what it is about, in the language people use there (at most 30 characters). Give one with your first post that ends a turn in a chat. Give another only when the chat has moved to something else and the name no longer says what it is about, not to reword it; the station changes it rarely, and never over a name people gave."
      },
      "card": {
        "type": "object",
        "description": "Still.fail chats only: what people answer this message with, shown with it and in their 待处理 (what waits for them) until they look at it. {\"type\": \"options\", \"options\": [...]} when they choose between answers you can name (1 to 6, recommend one if you can): shown under the message, numbered in the order given with the recommended one moved last; a tap answers. Where the message itself lists or numbers the same choices, put them in that order too (the recommended one last), so its numbers and the card's agree. {\"type\": \"text\", \"placeholder\": \"…\"} when they must write something (a value, a name, a key): they write it in the chat. {\"type\": \"login\", \"login\": \"<id>\"} for a login the login tool started: they finish it from the card in their own browser, and it closes as the login ends. An option with action=close ends the wait silently; other answers reach you as their message quoting this one, and anything they write in the chat instead answers it too. A card waits until a person writes in the chat or you post a newer one. It says nothing of your turn: end the turn need_human (with need) after posting one.",
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
                  "description": "A short phrase that reads on its own, in the language people use there (e.g. 按今天累计, 先不改)."
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
                  "description": "Default reply sends the selected label to you. close ends this need_human without a message or waking you; use only when choosing it needs no further work (e.g. 不需要部署)."
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
            "description": "The email of the person who must decide, chosen explicitly by you from the conversation. Only their 待处理 includes this card; others can still answer in the chat. Always set it for new cards. Omitted: whoever started the chat decides."
          },
          "placeholder": {
            "type": "string",
            "description": "For a text card: a hint shown in the empty field (e.g. sk_test_…)."
          }
        },
        "required": [
          "type"
        ],
        "additionalProperties": false
      },
      "options": {
        "type": "array",
        "description": "As said before cards: the same as card {\"type\": \"options\", \"options\": …}. Prefer card.",
        "items": {
          "type": "object",
          "properties": {
            "label": {
              "type": "string",
              "description": "A short phrase that reads on its own, in the language people use there (e.g. 按今天累计, 先不改)."
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
              "description": "Default reply sends the selected label to you. close ends this need_human without a message or waking you; use only when choosing it needs no further work (e.g. 不需要部署)."
            }
          },
          "required": [
            "label"
          ],
          "additionalProperties": false
        }
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
    "Record how this turn ends without posting another message: all_done (nothing in the chat is left unfinished: done says why, with the evidence), need_human (requires about pointing to your visible question, or a pending answer card; need alone is not visible in the chat) or waiting (only for work you started that brings you back on its own, such as a background command or agent, a job, a loop watching CI, and only when nothing else is left to do meanwhile: for says what; waiting on a person is need_human).",
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
        "description": "For need_human (required): what the person has to give, do or decide, in one sentence in the language people use there (e.g. 要 Stripe 的测试 key, 选统计口径); to verify something, where, how and what to look at; work of yours still running, after the ask (e.g. 选统计口径；CI 还在跑)."
      },
      "about": {
        "type": "string",
        "description": "Optional: the ts of the message in your conversation the state is about (all_done: the one with the result; need_human: required unless a card is pending, the message where you visibly ask what is still needed; waiting: the one saying what you started). People's lists jump to it."
      },
      "done": {
        "type": "string",
        "description": "Only a real unresolved need requires need_human; a factual answer alone needs no follow-up decision. For all_done (required): why nothing in the chat is left, so people can trust it, in the language they use there: what was finished and where it landed or how it was confirmed, naming the evidence (a commit, a release, a person's confirmation, the answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以. Not just 做完了 or done: that is refused."
      },
      "seconds": {
        "type": "integer",
        "minimum": 10,
        "maximum": 3600,
        "description": "For waiting: how long until the work brings you back; if nothing has by then, you are asked again (not while a watch of yours runs: job_start with watch). A fallback only: something must watch the work. When it truly cannot be watched, give the shortest it could take, not the longest."
      },
      "for": {
        "type": "string",
        "description": "For waiting (required): what you wait for, in a few words people read under your name, in the language they use there (e.g. 安卓滑动测试在模拟器上跑完)."
      }
    },
    "required": [
      "kind"
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
    "Read the messages of any conversation on this station or, by its link, on another station of the workspace or a chat another workspace shares with this one, not only your own, oldest first: the chat people refer to by its link.",
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
    "Send a message to another session's agent: a chat on this station, on another station of the workspace, or one another workspace shares with this one to write to. Its agent takes it like any message, headed with a link to your chat; it stays out of that chat's conversation (people read agents' letters on a page of their own). It answers you the same way, so to wait for the answer end your turn waiting. Use chat_post for your own conversations.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "The other chat: its link (…/chats/<key>, …/o/<workspace>/<station>/<key>, the link a message from it is headed with), its session key, or a thread address CHANNEL/THREAD_TS on this station; chat_list lists this station's."
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
        "description": "Absolute local paths of files to attach (at most 10, each up to 50 MB): they are copied to that chat, on this station or another, and its agent gets their paths there."
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
    "Open a new still.fail chat with an agent of its own, on this station or another station of the workspace, for work that should go on visibly beside yours (a part to do in parallel, something another machine is better placed for). It begins with your message, headed as opened by your chat; whoever started your chat is its starter, so what it asks goes to them. Each time a turn of it ends all_done or need_human (or fails, or a person stops it), you are told with its done or need: to wait for it, end your turn waiting. Write to its agent with session_send to its link. Nothing is retried by itself: when an answer was uncertain, call again with the same key, which gives the chat made then (and sends its first message once) rather than opening another. A chat opened this way opens none itself.",
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
        "description": "The chat's name in still.fail lists: a few words, in the language people use (at most 120 characters). Its agent names it when left out."
      },
      "station": {
        "type": "string",
        "description": "Another station of the workspace to open it on, by its name or id (station_list lists them). Left out: this station."
      },
      "runtime": {
        "type": "string",
        "enum": RUNTIME_KINDS,
        "description": "Its agent's runtime (dsh: DeepSeek Harness, grok: Grok Build, cursor: Cursor, devin: Devin, hermes: Hermes Agent). Default: that of its model."
      },
      "model": {
        "type": "string",
        "description": "Its agent's model. Default: the one the person it goes to has opened most chats with on that station (of the models its profiles run there, of runtime when given), when it is used at least twice as often as any other; when not, it is not opened and you are told them: ask the person which, then call again with it."
      },
      "effort": {
        "type": "string",
        "description": "Its agent's reasoning effort. Default: its model's."
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
  // The session's files in its sandbox, when it runs in one, first brought here (conversations.ts `fromSandbox`).
  if (sandboxed(hub.config().dataDir)) return fromSandbox(hub, key, args, links).then((here) => stagedRun(hub, key, here, links, run));
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
        const said = await withStaged(hub, key, args, stillfail, (a) => chatPost(hub, key, a));
        // A turn ended all_done (or final from before): whether the chat is finished is asked in the background.
        if (args.kind === "all_done" || args.kind === "final") suggestArchive(hub, key);
        return said;
      },
    },
    ...slackTools(hub),
    { ...CHAT_STATE, run: (key, args) => chatState(hub, key, args) },
    { ...CHAT_HISTORY, run: (key, args) => chatHistory(hub, key, args) },
    { ...CHAT_LIST, run: async (key, args) => chatList(hub, key, args) },
    { ...CHAT_READ, run: (key, args) => afar(hub, key, "chat_read", args) ?? chatRead(hub, key, args, undefined, scopeOf(hub, key)) },
    { ...SESSION_SEND, run: (key, args) => withStaged(hub, key, args, false, (a) => sessionSend(hub, key, a)) },
    { ...CHAT_CREATE, run: (key, args) => withStaged(hub, key, args, false, (a) => chatCreate(hub, key, a)) },
    { ...SESSION_HISTORY, run: async (key, args) => afar(hub, key, "session_history", args) ?? sessionHistory(hub, args, scopeOf(hub, key)) },
  ];
}
