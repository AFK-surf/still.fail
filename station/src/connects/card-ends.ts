// Cards that stop waiting where a platform shows them (Slack's and Feishu's buttons): as in still.fail, a card is no
// longer pending once a person writes after it, a newer card replaces it, its agent withdraws it or someone closes it
// (store.ts pendingCard). A press of its own button changes it there already; these change it for the rest, so nothing
// is left to press that would answer a question gone by.
import { type Lang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { ChatSurface } from "../sessions/chat.ts";
import { INTERNAL_CONNECT } from "../sessions/internal.ts";
import { type Json, type MessageRow, STILLFAIL_SURFACE, type StoreChange, type ThreadRow } from "../store/rows.ts";

/// Why a card stopped waiting: a person's message after it (`by` its author, `byTs` that message's ts), a newer card,
/// its agent withdrawing it, or a person closing it (a choice that closes it, in still.fail).
export type CardEnd = { why: "message"; by: string; byTs: string } | { why: "replaced" } | { why: "withdrawn" } | { why: "closed" };

/// A card that stopped waiting: its post, the card, and why.
export type EndedCard = { message: MessageRow; card: Json; end: CardEnd };

type Cards = {
  getThread(id: number): ThreadRow | null;
  threadSessions(thread: number): { connect: string }[];
  cardEndedByMessage(thread: number, n: number): [MessageRow, Json] | null;
  cardReplacedBy(thread: number, n: number): [MessageRow, Json] | null;
  closedCard(thread: number, n: number): [MessageRow, Json, string] | null;
};

/// The cards a change of the store ended (none for any change but a thread's).
export function cardsEnded(store: Cards, change: StoreChange): EndedCard[] {
  if (change.type !== "thread") return [];
  const out: EndedCard[] = [];
  for (const e of change.entries) {
    if (e.kind !== "message") continue;
    if (e.authorKind === "person") {
      const ended = store.cardEndedByMessage(change.id, e.n);
      if (ended !== null) out.push({ message: ended[0], card: ended[1], end: { why: "message", by: e.author, byTs: e.ts ?? "" } });
    } else if (e.card != null || e.options !== undefined) {
      const replaced = store.cardReplacedBy(change.id, e.n);
      if (replaced !== null) out.push({ message: replaced[0], card: replaced[1], end: { why: "replaced" } });
    }
  }
  if (change.closed !== undefined) {
    const closed = store.closedCard(change.id, change.closed);
    if (closed !== null) out.push({ message: closed[0], card: closed[1], end: { why: closed[2] === closed[0].author ? "withdrawn" : "closed" } });
  }
  return out;
}

/// The cards a change of the store ended, changed where their thread's platform shows them (`chat`: a connect's
/// surface, where it is connected). Not waited on.
export function showEnded(store: Cards, chat: (connect: string) => ChatSurface | undefined, change: StoreChange): void {
  if (change.type !== "thread" || (change.entries.length === 0 && change.closed === undefined)) return;
  const t = store.getThread(change.id);
  if (t === null || t.surface === STILLFAIL_SURFACE) return;
  const connect = store.threadSessions(change.id).map((m) => m.connect).find((c) => c !== INTERNAL_CONNECT);
  const shown = connect === undefined ? undefined : chat(connect);
  if (shown?.cards !== true || shown.cardEnded === undefined) return;
  const cards = cardsEnded(store, change);
  for (const { message, card, end } of cards) {
    shown.cardEnded({ channel: t.channel, threadTs: t.threadTs }, message.ts, message.text, card, end).catch((error) =>
      log.warn("connects", "a card that stopped waiting was not changed where it shows", { thread: change.id, ts: message.ts, error: (error as Error).message }),
    );
  }
}

/// What a card that stopped waiting says under its words, in small grey letters: why it is closed (`name`: who wrote
/// the message that closed it, when known). A text card's answer is that message: it says they replied.
export function endedWords(card: Json, end: CardEnd, name: string | null, lang: Lang): string {
  switch (end.why) {
    case "message": {
      const key = card?.type === "text" ? "station.card.replied" : "station.card.endedByMessage";
      return name !== null && name !== "" ? tr(lang, key, { name }) : tr(lang, `${key}Bare`);
    }
    case "replaced":
      return tr(lang, "station.card.endedReplaced");
    case "withdrawn":
      return tr(lang, "station.card.endedWithdrawn");
    case "closed":
      return tr(lang, "station.card.endedClosed");
  }
}
