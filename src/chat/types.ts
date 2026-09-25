// What ember needs from a chat platform. Slack is the first implementation.

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
  post(thread: ThreadRef, markdown: string): Promise<void>;
  /** A person's display name, or null if unknown. Optional: not every platform can say. */
  userName?(userId: string): Promise<string | null>;
  /** Messages in the thread strictly before `before` (all when absent), oldest first, at most `limit`. */
  history(thread: ThreadRef, before: string | undefined, limit: number): Promise<ChatMessage[]>;
  stop(): Promise<void>;
}
