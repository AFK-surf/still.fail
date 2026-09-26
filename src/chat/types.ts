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

/** What a platform tells ember: a new message, or an edit of one already said (deletes are not taken: ember keeps what was said). */
export type ChatEvent =
  | { kind: "message"; message: InboundMessage }
  | { kind: "changed"; channel: string; threadTs: string; ts: string; text: string };

export interface ChatMessage {
  ts: string;
  user: string;
  text: string;
  fromBot: boolean;
}

export interface ChatSurface {
  /** The bot's own user id, once started. */
  readonly botUserId: string;
  /** The platform workspace (Slack team id) once started; threads are named by it. */
  readonly workspace: string | null;
  /**
   * Starts receiving. `handler` must finish persisting the event before it
   * resolves: the platform is acknowledged only afterwards.
   */
  start(handler: (event: ChatEvent) => Promise<void>): Promise<void>;
  /**
   * Posts Markdown into the thread and returns the posted message's ts.
   * `files` are attachments already copied into the session's uploads; surfaces that cannot carry files refuse them.
   */
  post(thread: ThreadRef, markdown: string, files?: Attachment[]): Promise<string>;
  /** A person's display name, or null if unknown. Optional: not every platform can say. */
  userName?(userId: string): Promise<string | null>;
  /** A person's email, where the platform shares it. */
  userEmail?(userId: string): Promise<string | null>;
  /** What is already known of a person or a channel, without waiting (unknown ones are fetched in the background). */
  knownPerson?(userId: string): { name: string; email: string } | null;
  knownChannel?(channelId: string): string | null;
  /** A channel's name without the #, where the platform says; null for direct messages. */
  channelName?(channelId: string): Promise<string | null>;
  /**
   * Messages in the thread strictly before `before`, oldest first, at most
   * `limit`: what was said before ember joined a thread. Only platforms
   * where ember can join late have it.
   */
  history?(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]>;
  stop(): Promise<void>;
}
