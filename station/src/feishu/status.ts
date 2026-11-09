// What an agent is doing, said in the Feishu chat it works for (「工作中」; when and how often:
// connects/status.ts): a card posted as the turn starts, following the agent's steps at most once a second, and once
// the turn is over saying how long it took and where its steps can be read. The card is a CardKit entity, changed by
// its id as often as needed (a message's own edits run out after a few dozen); where the app may not make those (no
// cardkit:card:write), a card message changed in place instead. A turn for a message that did not call the bot shows
// no card until it does more than think and read the chat; a turn that said nothing takes its card back.
import { type Run, StatusLine } from "../connects/status.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { doneCard, entity, inline, workingCard } from "./cards.ts";

type Json = any;

export const MIN_INTERVAL_MS = 1_000;

/// What the line needs of its surface: calls of the OpenAPI, and a card posted where the thread is.
export type StatusCalls = {
  api(method: string, path: string, body: Json | null): Promise<Json>;
  /// Posts a message (`msg_type`, `content`) where the thread is: its message id.
  send(msgType: string, content: string): Promise<string>;
  /// Whether this message called the bot (an @, a direct message, a card's answer).
  called(ts: string): boolean;
};

/// One thread's line. `say("")` ends it.
export class FeishuStatus extends StatusLine {
  private calls: StatusCalls;
  private lang: Lang;
  /// The card of the turn now (its entity, or its message where there is none), and how many times it changed.
  private card: { id: string | null; message: string | null; sequence: number } | null = null;
  private startedAt: number | null = null;
  /// The agent posted in the thread during this turn.
  private said = false;
  /// The app may not make CardKit cards: messages stand in.
  private noEntities = false;

  constructor(calls: StatusCalls, run: Run, lang: Lang = stationLang()) {
    super(run, MIN_INTERVAL_MS);
    this.calls = calls;
    this.lang = lang;
  }

  /// The agent posts in the thread.
  spoke() {
    this.said = true;
  }

  /// Whether a turn doing this may still be one that lets a message by: what the agent does before it says nothing.
  private idle(status: string) {
    return status === tr(stationLang(), "station.status.thinking") || status === tr(stationLang(), "station.status.readingChat");
  }

  protected async show(status: string, now: number): Promise<boolean> {
    try {
      if (status === "") {
        const [card, said, startedAt] = [this.card, this.said, this.startedAt ?? now];
        this.card = null;
        this.said = false;
        this.startedAt = null;
        if (card !== null && (said || !(await this.takeBack(card)))) await this.change(card, doneCard(now - startedAt, this.page, this.lang));
        return true;
      }
      this.startedAt ??= now;
      if (this.card === null) {
        if (this.idle(status) && (this.messageTs === null || !this.calls.called(this.messageTs))) return true;
        this.card = await this.open(workingCard(status));
        return true;
      }
      await this.change(this.card, workingCard(status));
    } catch (error) {
      log.warn("feishu", "could not say the agent's status in Feishu", { error: (error as Error).message });
    }
    return true;
  }

  private async open(card: Json): Promise<{ id: string | null; message: string | null; sequence: number }> {
    if (!this.noEntities) {
      try {
        const made = await this.calls.api("POST", "/open-apis/cardkit/v1/cards", { type: "card_json", data: JSON.stringify(card) });
        const id = made?.data?.card_id;
        if (typeof id !== "string" || id === "") throw new Error("feishu gave no card_id");
        return { id, message: await this.calls.send("interactive", entity(id)), sequence: 0 };
      } catch (error) {
        log.info("feishu", "status as a card message: no card entities here", { error: (error as Error).message });
        this.noEntities = true;
      }
    }
    return { id: null, message: await this.calls.send("interactive", inline(card)), sequence: 0 };
  }

  /// The card's message recalled: whether it went (Feishu may refuse one too old: it stays, saying the turn is over).
  private async takeBack(card: { message: string | null }): Promise<boolean> {
    if (card.message === null) return false;
    try {
      await this.calls.api("DELETE", `/open-apis/im/v1/messages/${encodeURIComponent(card.message)}`, null);
      return true;
    } catch (error) {
      log.info("feishu", "status card not recalled", { error: (error as Error).message });
      return false;
    }
  }

  private async change(at: { id: string | null; message: string | null; sequence: number }, card: Json) {
    if (at.id !== null) {
      at.sequence++;
      await this.calls.api("PUT", `/open-apis/cardkit/v1/cards/${at.id}`, { card: { type: "card_json", data: JSON.stringify(card) }, sequence: at.sequence });
    } else if (at.message !== null) await this.calls.api("PATCH", `/open-apis/im/v1/messages/${at.message}`, { content: inline(card) });
  }
}
