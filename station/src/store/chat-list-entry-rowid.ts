// REPLACE can evict a selected message through its rowid without firing DELETE triggers. Find the selected chat
// before the write, using the entry's rowid and the chat state primary key instead of scanning message history.
export const recentChatDisplacedEntry = (rowid: string): string => `SELECT e.thread FROM entries e
  JOIN thread_state s ON s.thread = e.thread AND s.said_n = e.n
  WHERE e.rowid = ${rowid} AND e.kind = 'message'`;
