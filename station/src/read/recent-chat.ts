import type { DatabaseSync } from "node:sqlite";
import { readPreparedRecentHome } from "../store/chat-list-home-overlap.ts";
import { readGlobalRecentChatIndex, type RecentChatPage } from "../store/chat-list-index.ts";
import { readPreparedRecentWorkspace } from "../store/chat-list-scope-rows.ts";

export const RECENT_CHAT_PENDING = "recent chat order is still being prepared";

/// The readiness check and selected page share the reader's enclosing snapshot. No old history is read here.
export function recentChatPage(db: DatabaseSync, ws: string | null, home: string | null, limit: number): RecentChatPage {
  if (!Number.isSafeInteger(limit) || limit < 0) throw new RangeError("recent chat page size must be nonnegative");
  if (limit === 0) return { ids: [], total: 0 };
  const page = ws === null ? readGlobalRecentChatIndex(db, limit)
    : ws === home ? readPreparedRecentHome(db, ws, limit) : readPreparedRecentWorkspace(db, ws, limit);
  if (page === null) throw new Error(RECENT_CHAT_PENDING);
  return page;
}
