// What ember needs from a chat platform. Slack is the first implementation.
import type { Attachment } from "../store.ts";

export interface ThreadRef {
  channel: string;
  threadTs: string;
}

export interface InboundMessage extends ThreadRef {
  ts: string;
  user: string;
  text: string;
  /** Mentions the bot or is a direct message: may start a session. Other thread replies only continue one. */
  addressed: boolean;
}

export interface ChatMessage {
  ts: string;
  user: string;
  text: string;
  fromBot: boolean;
}

export interface ChatSurface {
  /** The bot's own user id, once started. */
  readonly botUserId: string;
  /**
   * Starts receiving. `handler` must finish persisting the message before it
   * resolves: the platform is acknowledged only afterwards.
   */
  start(handler: (message: InboundMessage) => Promise<void>): Promise<void>;
  /** Posts Markdown into the thread. */
  /** `files` are attachments already copied into the session's uploads; surfaces that cannot carry files refuse them. */
  post(thread: ThreadRef, markdown: string, files?: Attachment[]): Promise<void>;
  /** A person's display name, or null if unknown. Optional: not every platform can say. */
  userName?(userId: string): Promise<string | null>;
  /** A person's email, where the platform shares it. */
  userEmail?(userId: string): Promise<string | null>;
  /** A channel's name without the #, where the platform says; null for direct messages. */
  channelName?(channelId: string): Promise<string | null>;
  /** Messages in the thread strictly before `before` (all when absent), oldest first, at most `limit`. */
  history(thread: ThreadRef, before: string | undefined, limit: number): Promise<ChatMessage[]>;
  stop(): Promise<void>;
}
