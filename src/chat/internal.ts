// ember's own chat: conversations opened on a session from the admin page. To
// the agent it is one more chat platform, like Slack: people's messages arrive
// with their source, and the agent answers with chat_post to their thread.
// Every chat lives in one channel, INTERNAL_CHANNEL; its thread_ts is its
// address and its primary key.
import type { Attachment, Quote, Store } from "../store.ts";
import type { ChatMessage, ChatSurface, InboundMessage, ThreadRef } from "./types.ts";

/** The connect id ember's own chat goes by. Not configurable; never in config.json. */
export const INTERNAL_CONNECT = "ember";
export const INTERNAL_CHANNEL = "EMBER";
/** How the agent is named in these chats. */
export const INTERNAL_BOT_USER = "UEMBER";

let lastMicros = 0;
/** Slack-style timestamps ("seconds.micros"), strictly increasing within this process. */
export function nextTs(now = Date.now()): string {
  lastMicros = Math.max(lastMicros + 1, now * 1000);
  return `${Math.floor(lastMicros / 1_000_000)}.${String(lastMicros % 1_000_000).padStart(6, "0")}`;
}

export class InternalChat implements ChatSurface {
  readonly botUserId = INTERNAL_BOT_USER;
  readonly #store: Store;
  /** Display names of admin-page users (the Access email, or "local"). */
  readonly #names: (user: string) => string;

  constructor(store: Store, names: (user: string) => string = (user) => (user === "local" ? "管理员" : user)) {
    this.#store = store;
    this.#names = names;
  }

  async start(): Promise<void> {}
  async stop(): Promise<void> {}

  /** Opens a chat on a session. Returns its thread address parts. */
  open(sessionKey: string, createdBy: string, title: string | null): ThreadRef {
    const threadTs = nextTs();
    this.#store.insertChat({ threadTs, sessionKey, title, createdBy, createdAt: Date.now() });
    return { channel: INTERNAL_CHANNEL, threadTs };
  }

  /** Records what a person typed; the caller hands the returned message to the hub. */
  say(threadTs: string, user: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = []): InboundMessage {
    const ts = nextTs();
    this.#store.insertChatMessage({ threadTs, ts, role: "person", user, text, createdAt: Date.now(), attachments, quotes });
    // The agent reads quotes as Zork writes them (author, the passage as a
    // blockquote, then the comment), then the words, then the files as paths.
    const quoted = quotes.map((q) => `${q.author}\n${q.text.split("\n").map((l) => `> ${l}`).join("\n")}${q.comment ? `\n\n${q.comment}` : ""}`);
    const files = attachments.length ? `Attached files:\n${attachments.map((a) => `- ${a.path} (${a.name}, ${a.size} bytes)`).join("\n")}` : "";
    const forAgent = [...quoted, text, files].filter(Boolean).join("\n\n");
    return { channel: INTERNAL_CHANNEL, threadTs, ts, user, text: forAgent, addressed: true };
  }

  async post(thread: ThreadRef, markdown: string): Promise<void> {
    if (thread.channel !== INTERNAL_CHANNEL || !this.#store.getChat(thread.threadTs)) throw new Error(`no ember chat ${thread.channel}/${thread.threadTs}`);
    this.#store.insertChatMessage({ threadTs: thread.threadTs, ts: nextTs(), role: "agent", user: INTERNAL_BOT_USER, text: markdown, createdAt: Date.now() });
  }

  async history(thread: ThreadRef, before: string | undefined, limit: number): Promise<ChatMessage[]> {
    return this.#store.chatMessages(thread.threadTs, before, limit)
      .map((m) => ({ ts: m.ts, user: m.user, text: m.text, fromBot: m.role === "agent" }));
  }

  async userName(user: string): Promise<string | null> {
    return user === INTERNAL_BOT_USER ? null : this.#names(user);
  }

  async channelName(): Promise<string | null> {
    return null;
  }
}
