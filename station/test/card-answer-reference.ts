// An intentionally unbounded reference for tests of the scoped reader, never used by a running station.
import { cardOf, toMessage, type CardAnswer, type Json, type MessageRow } from "../src/store/rows.ts";
import type { Store } from "../src/store/store.ts";

export function referenceAnswersSince(store: Store, since: number): CardAnswer[] {
  const db = store.db, out: CardAnswer[] = [];
  const one = (sql: string, ...args: any[]): Json | undefined => db.prepare(sql).get(...args);
  const cardAt = (thread: number, n: number): [MessageRow, Json] | null => {
    const row = one("SELECT card, options FROM entries WHERE thread = ? AND n = ?", thread, n);
    const card = row ? cardOf(row.card, row.options) : undefined;
    if (card === undefined) return null;
    const message = one("SELECT * FROM merged WHERE thread = ? AND n = ?", thread, n);
    return message ? [toMessage(message), card] : null;
  };
  const people = db.prepare(`SELECT thread,n FROM entries
    WHERE author_kind='person' AND kind='message' AND at>=? ORDER BY at,rowid`).all(since) as Json[];
  for (const { thread, n } of people) {
    const asked = one(`SELECT MAX(n) AS n FROM entries WHERE thread=? AND n<? AND kind='message'
      AND (card IS NOT NULL OR options IS NOT NULL)`, thread, n)!.n as number | null;
    if (asked === null) continue;
    const earlier = one(`SELECT 1 FROM entries WHERE thread=? AND kind='message' AND author_kind='person'
      AND n>? AND n<? LIMIT 1`, thread, asked, n);
    if (earlier || one("SELECT 1 FROM closed_cards WHERE thread=? AND n=?", thread, asked)) continue;
    const found = cardAt(thread, asked);
    const answer = one("SELECT * FROM merged WHERE thread=? AND n=?", thread, n);
    if (!found || !answer) continue;
    const a = toMessage(answer);
    out.push({ question: found[0], card: found[1], by: a.author, at: a.createdAt, answer: a });
  }
  const closed = db.prepare("SELECT thread,n,viewer,at FROM closed_cards WHERE at>=? ORDER BY at,rowid").all(since) as Json[];
  for (const { thread, n, viewer: by, at } of closed) {
    const found = cardAt(thread, n);
    if (found && found[0].author !== by) out.push({ question: found[0], card: found[1], by, at, answer: null });
  }
  return out;
}
