// The recent chat_list: count and order the chats first, then read details only for those displayed. The count and
// ordering still consider every chat, but need neither each chat's people nor its merged messages.
import type { DatabaseSync } from "node:sqlite";
import type { SessionRow, ThreadSummary } from "./rows.ts";

export type ChatListSession = Pick<SessionRow, "key" | "title" | "archivedAt" | "ws">;
export type ChatListThread = Pick<ThreadSummary, "thread" | "sessions" | "lastMessage" | "firstText">;
export type RecentChatList = { threads: ChatListThread[]; sessions: ChatListSession[]; total: number };

/// A chat with a home belongs there; otherwise it belongs to any of its sessions' workspaces, or the home workspace
/// when it has none. Unknown sessions, and sessions with no workspace, belong to the home workspace too.
export const RECENT_CHAT_LIST = `SELECT t.id, COUNT(*) OVER () AS total
  FROM threads t
  LEFT JOIN sessions h ON h.key = t.home
  LEFT JOIN thread_state s ON s.thread = t.id
  LEFT JOIN entries e ON e.thread = t.id AND e.n = s.said_n AND e.kind = 'message'
  WHERE ?1 IS NULL OR CASE
    WHEN t.home IS NOT NULL THEN COALESCE(h.ws, ?2) = ?1
    WHEN NOT EXISTS (SELECT 1 FROM thread_sessions m WHERE m.thread = t.id) THEN ?2 = ?1
    ELSE EXISTS (SELECT 1 FROM thread_sessions m LEFT JOIN sessions a ON a.key = m.session
                 WHERE m.thread = t.id AND COALESCE(a.ws, ?2) = ?1)
  END
  ORDER BY COALESCE(e.at, t.created_at) DESC, COALESCE(e.at, 0) DESC, t.created_at DESC, t.id DESC
  LIMIT ?3`;

export function recentChatIds(db: DatabaseSync, ws: string | null, home: string | null, limit: number): { ids: number[]; total: number } {
  if (limit === 0) return { ids: [], total: 0 };
  const rows = db.prepare(RECENT_CHAT_LIST).all(ws, home, limit) as { id: number; total: number }[];
  return { ids: rows.map((r) => r.id), total: rows[0]?.total ?? 0 };
}
