// A bounded source for the default part of the home workspace. A caller must restart this cursor when the chat's
// home, members, or their workspace changes; this helper alone does not certify an indexed home page.
import type { DatabaseSync } from "node:sqlite";

export type HomeChatCursor = { after: string | null; seen: boolean };
export type HomeChatStep = { done: false; cursor: HomeChatCursor; visited: number } |
  { done: true; included: boolean; visited: number };

export const FIRST_HOME_CHAT_MEMBERS = "SELECT session FROM thread_sessions WHERE thread = ?1 ORDER BY session LIMIT ?2";
export const NEXT_HOME_CHAT_MEMBERS = "SELECT session FROM thread_sessions WHERE thread = ?1 AND session > ?2 ORDER BY session LIMIT ?3";

/// Decide whether this chat belongs to the default home range. Limit the raw membership rows before consulting
/// the sessions, so a chat with many named-workspace members cannot make one call scan all of them.
export function recentHomeChatStep(db: DatabaseSync, thread: bigint, cursor: HomeChatCursor, limit = 64): HomeChatStep {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError("recent home source batch must be positive");
  const chat = db.prepare("SELECT home FROM threads WHERE id = ?").get(thread) as { home: string | null } | undefined;
  if (!chat) return { done: true, included: false, visited: 0 };
  const getSession = db.prepare("SELECT ws FROM sessions WHERE key = ?");
  if (chat.home !== null) {
    const session = getSession.get(chat.home) as { ws: string | null } | undefined;
    return { done: true, included: session?.ws === null || session === undefined, visited: 1 };
  }
  const members = (cursor.after === null ? db.prepare(FIRST_HOME_CHAT_MEMBERS).all(thread, limit)
    : db.prepare(NEXT_HOME_CHAT_MEMBERS).all(thread, cursor.after, limit)) as { session: string }[];
  for (let i = 0; i < members.length; i++) {
    const session = getSession.get(members[i]!.session) as { ws: string | null } | undefined;
    if (session === undefined || session.ws === null) return { done: true, included: true, visited: members.length };
  }
  if (members.length < limit) return { done: true, included: !cursor.seen && members.length === 0, visited: members.length };
  return { done: false, cursor: { after: members.at(-1)!.session, seen: true }, visited: members.length };
}
