// Where a long-lived operation's card stands: its request can outlive a question card closed by a chat message.
import type { SessionThread } from "../store/rows.ts";

type CardStore = {
  sessionThreads(session: string): SessionThread[];
  pendingCard(thread: number): [{ ts: string }, unknown] | null;
};

/// The original conversation and whether this exact card, another card, or no card is waiting there. Null when the
/// operation was asked on a surface without its own card. A different pending card must not be silently replaced.
export function cardPlace(store: CardStore, session: string, thread: number | null | undefined, ts: string | null | undefined): { thread: SessionThread; state: "same" | "other" | "none" } | null {
  if (thread == null || ts == null) return null;
  const where = store.sessionThreads(session).find((t) => t.thread.id === thread);
  if (where === undefined) throw new Error("the original conversation is no longer available to this session");
  const current = store.pendingCard(thread);
  return { thread: where, state: current === null ? "none" : current[0].ts === ts ? "same" : "other" };
}

export const CARD_OCCUPIED = "Another card is pending in that conversation. Resolve or withdraw it before asking this again.";
