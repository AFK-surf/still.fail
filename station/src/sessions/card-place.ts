// Where a long-lived operation's card stands: its request can outlive a question card closed by a chat message.
import { wall } from "../ops/fibers.ts";
import type { SessionThread } from "../store/rows.ts";
import { MessageWriteBusy } from "../store/store.ts";

type CardStore = {
  sessionThreadById(session: string, thread: number): SessionThread | null;
  pendingCardHeader(thread: number): [{ ts: string }, unknown] | null;
  pendingCardHeaderIfReady?(thread: number): [{ ts: string }, unknown] | null | undefined;
};

/// A bounded card header, or undefined if an old thread must be prepared first.
export function cardHeaderIfReady(store: CardStore, thread: number): [{ ts: string }, unknown] | null | undefined {
  return store.pendingCardHeaderIfReady ? store.pendingCardHeaderIfReady(thread) : store.pendingCardHeader(thread);
}

/// The original conversation and whether this exact card, another card, or no card is waiting there. Null when the
/// operation was asked on a surface without its own card. A different pending card must not be silently replaced.
export function cardPlace(store: CardStore, session: string, thread: number | null | undefined, ts: string | null | undefined): { thread: SessionThread; state: "same" | "other" | "none" } | null | undefined {
  if (thread == null || ts == null) return null;
  const where = store.sessionThreadById(session, thread);
  if (where === null) throw new Error("the original conversation is no longer available to this session");
  const current = cardHeaderIfReady(store, thread);
  if (current === undefined) return undefined;
  return { thread: where, state: current === null ? "none" : current[0].ts === ts ? "same" : "other" };
}

export const CARD_OCCUPIED = "Another card is pending in that conversation. Resolve or withdraw it before asking this again.";

/// What a long-lived operation posts its card through: the session's chat's surface, and the store it keeps it in.
export type CardHub = {
  store: CardStore & { insertMessage(m: Record<string, unknown>, before?: () => void): readonly unknown[] };
  prepareCardPosts?: ((threads: readonly number[], signal?: AbortSignal) => Promise<void>) | null;
  actors?: Map<string, { messageIdentity(): { model: string | null; effort: string | null; runtime: string } | null }>;
  chat(connect: string): { post(where: { channel: string; threadTs: string }, text: string, files: never[]): Promise<string> };
  shared(thread: number, n: number, session: string, text: string): void;
};

class CardPreparationNeeded extends Error {}
class CardNoLongerNeeded extends Error {}

async function waitForWriter(ms: number, signal?: AbortSignal): Promise<void> {
  if (!signal) return wall.sleep(ms);
  signal.throwIfAborted();
  await new Promise<void>((resolve, reject) => {
    const abort = () => { stop(); signal.removeEventListener("abort", abort); reject(signal.reason); };
    const stop = wall.after(ms, () => { signal.removeEventListener("abort", abort); resolve(); });
    signal.addEventListener("abort", abort, { once: true });
    if (signal.aborted) abort();
  });
}

/// Once the surface has given the post its timestamp, record it only while the request and card are still valid.
/// The second check runs inside the insert's write transaction. A busy writer or an old index is waited for outside it.
export async function recordPostedCard(hub: CardHub, session: string, thread: SessionThread, text: string, card: unknown | null,
  posted: string, occupied: ((why: string) => Error) | null, needed?: () => boolean,
  identity?: { model: string | null; effort: string | null; runtime: string }, signal?: AbortSignal): Promise<string | null> {
  const message = { thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card, agentIdentity: identity };
  const check = () => {
    signal?.throwIfAborted();
    if (needed && !needed()) throw new CardNoLongerNeeded();
    if (hub.store.sessionThreadById(session, thread.thread.id) === null)
      throw occupied!("the original conversation is no longer available to this session");
    const current = cardHeaderIfReady(hub.store, thread.thread.id);
    if (current === undefined) throw new CardPreparationNeeded();
    if (current !== null) throw occupied!(CARD_OCCUPIED);
  };
  let delay = 10;
  for (;;) {
    signal?.throwIfAborted();
    let n: unknown;
    try {
      if (occupied !== null) check();
      [n] = hub.store.insertMessage(message, occupied === null ? undefined : check);
    } catch (error) {
      if (error instanceof CardNoLongerNeeded) return null;
      if (error instanceof CardPreparationNeeded) {
        if (!hub.prepareCardPosts) throw occupied!("card lookup is not ready");
        await hub.prepareCardPosts([thread.thread.id], signal);
        continue;
      }
      if (error instanceof MessageWriteBusy) {
        await waitForWriter(delay, signal);
        delay = Math.min(delay * 2, 250);
        continue;
      }
      throw error;
    }
    hub.shared(thread.thread.id, n as number, session, text);
    return card !== null ? posted : null;
  }
}

/// Says `text` in `thread` as `session`'s agent, with `card` (null on a surface without cards): posted, then kept as
/// the agent's message; when another card came meanwhile, `occupied`'s refusal (where given). The card's ts, or null
/// with none.
export async function postCard(hub: CardHub, session: string, thread: SessionThread, text: string, card: unknown | null, occupied: ((why: string) => Error) | null, needed?: () => boolean, signal?: AbortSignal): Promise<string | null> {
  const identity = hub.actors?.get(session)?.messageIdentity() ?? undefined;
  const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
  signal?.throwIfAborted();
  const posted = await hub.chat(thread.connect).post(here, text, []);
  // A non-card surface has already delivered the message; finish recording it even if the caller leaves.
  return recordPostedCard(hub, session, thread, text, card, posted, occupied, needed, identity, card === null ? undefined : signal);
}
