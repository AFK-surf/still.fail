// Where a long-lived operation's card stands: its request can outlive a question card closed by a chat message.
import type { SessionThread } from "../store/rows.ts";

type CardStore = {
  sessionThreadById(session: string, thread: number): SessionThread | null;
  pendingCard(thread: number): [{ ts: string }, unknown] | null;
};

/// The original conversation and whether this exact card, another card, or no card is waiting there. Null when the
/// operation was asked on a surface without its own card. A different pending card must not be silently replaced.
export function cardPlace(store: CardStore, session: string, thread: number | null | undefined, ts: string | null | undefined): { thread: SessionThread; state: "same" | "other" | "none" } | null {
  if (thread == null || ts == null) return null;
  const where = store.sessionThreadById(session, thread);
  if (where === null) throw new Error("the original conversation is no longer available to this session");
  const current = store.pendingCard(thread);
  return { thread: where, state: current === null ? "none" : current[0].ts === ts ? "same" : "other" };
}

export const CARD_OCCUPIED = "Another card is pending in that conversation. Resolve or withdraw it before asking this again.";

/// What a long-lived operation posts its card through: the session's chat's surface, and the store it keeps it in.
export type CardHub = {
  store: CardStore & { insertMessage(m: Record<string, unknown>): readonly unknown[] };
  actors?: Map<string, { messageIdentity(): { model: string | null; effort: string | null; runtime: string } | null }>;
  chat(connect: string): { post(where: { channel: string; threadTs: string }, text: string, files: never[]): Promise<string> };
  shared(thread: number, n: number, session: string, text: string): void;
};

/// Says `text` in `thread` as `session`'s agent, with `card` (null on a surface without cards): posted, then kept as
/// the agent's message; when another card came meanwhile, `occupied`'s refusal (where given). The card's ts, or null
/// with none.
export async function postCard(hub: CardHub, session: string, thread: SessionThread, text: string, card: unknown | null, occupied: ((why: string) => Error) | null): Promise<string | null> {
  const identity = hub.actors?.get(session)?.messageIdentity() ?? undefined;
  const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
  const posted = await hub.chat(thread.connect).post(here, text, []);
  if (occupied !== null && hub.store.pendingCard(thread.thread.id) !== null) throw occupied(CARD_OCCUPIED);
  const [n] = hub.store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card, agentIdentity: identity });
  hub.shared(thread.thread.id, n as number, session, text);
  return card !== null ? posted : null;
}
