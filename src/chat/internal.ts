// ember's own chat: conversations on ember's page. To the agent it is one
// more chat platform, like Slack: people's messages arrive with their source,
// and the agent answers with chat_post to their thread. Every chat lives in
// one channel, INTERNAL_CHANNEL; its thread_ts is its address. The messages
// themselves are the store's, like every thread's.
import type { Attachment } from "../store.ts";
import type { ChatSurface, ThreadRef } from "./types.ts";

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
  readonly workspace = null;
  /** Display names of page users (the Access email, or "local"). */
  readonly #names: (user: string) => string;

  constructor(names: (user: string) => string = (user) => (user === "local" ? "管理员" : user)) {
    this.#names = names;
  }

  async start(): Promise<void> {}
  async stop(): Promise<void> {}

  /** Nothing to send anywhere: the message is recorded under the ts this returns, and the page reads it from there. */
  async post(thread: ThreadRef, _message: string, _files: Attachment[] = []): Promise<string> {
    if (thread.channel !== INTERNAL_CHANNEL) throw new Error(`no ember chat ${thread.channel}/${thread.threadTs}`);
    return nextTs();
  }

  async userName(user: string): Promise<string | null> {
    return user === INTERNAL_BOT_USER ? null : this.#names(user);
  }

  async channelName(): Promise<string | null> {
    return null;
  }
}
