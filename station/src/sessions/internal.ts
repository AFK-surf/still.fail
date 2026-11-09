// The station's own chat (the Rust station's chat/internal.rs): conversations on its pages. To the agent it is one more chat
// platform, like Slack: people's messages arrive with their source, and the agent answers with chat_post to their
// thread. Every chat lives in one channel, INTERNAL_CHANNEL; its thread_ts is its address. The messages themselves are
// the store's, like every thread's.
import type { Clock } from "effect";
import { join } from "node:path";
import { liveClock } from "../ops/fibers.ts";
import type { Attachment } from "../store/store.ts";
import type { ChatSurface, ThreadRef } from "./chat.ts";
import { STILLFAIL_CONNECT } from "../store/rows.ts";

/// The connect id the station's own chat goes by, as its rows store it (named as before the rename, like the threads'
/// surface, store/rows.ts STILLFAIL_SURFACE: the stations' data has it). Not configurable; never in config.json.
export const INTERNAL_CONNECT = STILLFAIL_CONNECT;
/// The channel its chats are made in, their address `CHAT/<ts>`; chats made before the rename are in EMBER and keep
/// their address.
export const INTERNAL_CHANNEL = "CHAT";
const FORMER_CHANNEL = "EMBER";
/// Whether a channel is the station's own chats'.
export const isInternalChannel = (channel: string) => channel === INTERNAL_CHANNEL || channel === FORMER_CHANNEL;
/// What the keys of sessions made for its chats begin with (`chat:c-…`); those made before the rename, `chat:c-…`.
export const CHAT_KEY = "chat";
const FORMER_CHAT_KEY = STILLFAIL_CONNECT;
/// A chat's session key, from its id (`c-…`): the one already made with `made` (true: it is the station's), else a
/// new one.
export const chatKey = (id: string, made: (key: string) => boolean = () => false) =>
  [FORMER_CHAT_KEY, CHAT_KEY].map((p) => `${p}:${id}`).find(made) ?? `${CHAT_KEY}:${id}`;
/// Where a chat session's workspace is, under the station's data: `sessions/<its key's first part>/<the rest>`.
export const chatWorkspace = (dataDir: string, key: string) => {
  const at = key.indexOf(":");
  return join(dataDir, "sessions", key.slice(0, at), key.slice(at + 1), "workspace");
};
/// How the agent is named in these chats.
export const INTERNAL_BOT_USER = "UEMBER";

/// The last ts given, in microseconds: they only go up within this process (a clock, not a registry).
let lastMicros = 0;

/// Slack-style timestamps ("seconds.micros") at `nowMs` (its clock's now), strictly increasing within this process.
export function nextTsAt(nowMs: number): string {
  const next = Math.max(lastMicros + 1, nowMs * 1000);
  lastMicros = next;
  return `${Math.floor(next / 1_000_000)}.${String(next % 1_000_000).padStart(6, "0")}`;
}

export class InternalChat implements ChatSurface {
  /// Display names of page users (an email; "local" in chats written on the page this machine had, before it went).
  private names: (user: string) => string;
  private clock: Clock.Clock;

  constructor(names: (user: string) => string = (user) => (user === "local" ? "管理员" : user), clock: Clock.Clock = liveClock) {
    this.names = names;
    this.clock = clock;
  }

  botUserId(): string {
    return INTERNAL_BOT_USER;
  }

  workspace(): string | null {
    return null;
  }

  /// Nothing to send anywhere: the message is recorded under the ts this gives, and the page reads it from there.
  async post(thread: ThreadRef, _message: string, _files: Attachment[]): Promise<string> {
    if (!isInternalChannel(thread.channel)) throw new Error(`no still.fail chat ${thread.channel}/${thread.threadTs}`);
    return nextTsAt(this.clock.currentTimeMillisUnsafe());
  }

  async userName(user: string): Promise<string | null> {
    return user !== INTERNAL_BOT_USER ? this.names(user) : null;
  }
}
