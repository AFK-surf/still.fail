// The recent chat_list: count and order the chats first, then read details only for those displayed. The count and
// ordering still consider every chat, but need neither each chat's people nor its merged messages.
import type { DatabaseSync } from "node:sqlite";
import type { Membership, MessageRow, SessionRow, ThreadRow, ThreadSummary } from "./rows.ts";

export type ChatListSession = Pick<SessionRow, "key" | "title" | "archivedAt" | "ws">;
export type ChatListThread = Pick<ThreadSummary, "thread" | "sessions" | "lastMessage" | "firstText">;
export type RecentChatList = { threads: ChatListThread[]; sessions: ChatListSession[]; total: number };

/// A chat with a home belongs there; otherwise it belongs to any of its sessions' workspaces, or the home workspace
/// when it has none. Unknown sessions, and sessions with no workspace, belong to the home workspace too.
const SCOPED_CHATS = `FROM threads t
  LEFT JOIN sessions h ON h.key = t.home
  LEFT JOIN thread_state s ON s.thread = t.id
  LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message'
  WHERE ?1 IS NULL OR CASE
    WHEN t.home IS NOT NULL THEN COALESCE(h.ws, ?2) = ?1
    WHEN NOT EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id) THEN ?2 = ?1
    ELSE EXISTS (SELECT 1 FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session
                 WHERE m.thread = t.id AND COALESCE(a.ws, ?2) = ?1)
  END`;
const CHAT_ORDER = "ORDER BY COALESCE(e.at, t.created_at) DESC, COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC";
export const RECENT_CHAT_LIST = `SELECT t.id, COUNT(*) OVER () AS total ${SCOPED_CHATS} ${CHAT_ORDER} LIMIT ?3`;
export const SEARCH_CHAT_LIST = `SELECT t.id ${SCOPED_CHATS} ${CHAT_ORDER}`;

export function recentChatIds(db: DatabaseSync, ws: string | null, home: string | null, limit: number): { ids: number[]; total: number } {
  if (limit === 0) return { ids: [], total: 0 };
  const rows = db.prepare(RECENT_CHAT_LIST).all(ws, home, limit) as { id: number; total: number }[];
  return { ids: rows.map((r) => r.id), total: rows[0]?.total ?? 0 };
}

type SearchAccess = {
  thread(id: number): ThreadRow | null;
  sessions(id: number): Membership[];
  last(id: number): MessageRow | null;
  firstText(id: number): string | null;
  session(key: string): ChatListSession | null;
};

/// Search needs the titles and latest words of every chat in scope, but not its people, unread count or letters. Keep
/// only matched chats for the page, and count the rest without sending all of their details back to the hub.
export function searchChats(db: DatabaseSync, ws: string | null, home: string | null, limit: number, query: string, access: SearchAccess): RecentChatList {
  if (limit === 0) return { threads: [], sessions: [], total: 0 };
  const threads: ChatListThread[] = [];
  const sessions = new Map<string, ChatListSession | null>();
  let total = 0;
  for (const row of db.prepare(SEARCH_CHAT_LIST).iterate(ws, home) as Iterable<{ id: number }>) {
    const thread = access.thread(row.id);
    if (thread === null) continue;
    const members = access.sessions(row.id);
    for (const m of members) if (!sessions.has(m.session)) {
      const s = access.session(m.session);
      sessions.set(m.session, s === null ? null : { key: s.key, title: s.title, archivedAt: s.archivedAt, ws: s.ws });
    }
    const lastMessage = access.last(row.id);
    const firstText = access.firstText(row.id);
    const titles = [thread.title, thread.autoTitle, firstText, ...members.map((m) => sessions.get(m.session)?.title ?? null)].filter((x): x is string => x !== null);
    const haystack = `${titles.join(" ")} ${lastMessage?.text ?? ""} ${members.map((m) => m.session).join(" ")}`.toLowerCase();
    if (!haystack.includes(query)) continue;
    total++;
    if (threads.length < limit) threads.push({ thread, sessions: members, lastMessage, firstText });
  }
  const selected = new Set(threads.flatMap((t) => t.sessions.map((m) => m.session)));
  return { threads, sessions: [...selected].flatMap((key) => { const s = sessions.get(key); return s ? [s] : []; }), total };
}
