// What an agent is doing, said in the Feishu chat it works for (docs/feishu.md「工作中」): a card posted as the turn
// starts, following the agent's steps (sessions/chat.ts `toolStatus`) at most once a second, and once the turn is over
// saying how long it took and where its steps can be read. The card is a CardKit entity, changed by its id as often as
// needed (a message's own edits run out after a few dozen); where the app may not make those (no cardkit:card:write),
// a card message changed in place instead.
import { Clock, Effect } from "effect";
import { type Lang, stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { doneCard, entity, inline, workingCard } from "./cards.ts";

type Json = any;

export const MIN_INTERVAL_MS = 1_000;

/// What the line needs of its surface: calls of the OpenAPI, and a card posted where the thread is.
export type StatusCalls = {
  api(method: string, path: string, body: Json | null): Promise<Json>;
  /// Posts a message (`msg_type`, `content`) where the thread is: its message id.
  send(msgType: string, content: string): Promise<string>;
};

export type Run = (effect: Effect.Effect<void>) => Promise<void>;

/// One thread's line. `say("")` ends it.
export class FeishuStatus {
  private calls: StatusCalls;
  private run: Run;
  private lang: Lang;
  /// The card of the turn now (its entity, or its message where there is none), and how many times it changed.
  private card: { id: string | null; message: string | null; sequence: number } | null = null;
  private startedAt = 0;
  private page: string | null = null;
  private shown = "";
  private wanted = "";
  private lastAt = Number.NEGATIVE_INFINITY;
  private timer = false;
  /// The app may not make CardKit cards: messages stand in.
  private noEntities = false;
  private sending: Promise<void> = Promise.resolve();

  constructor(calls: StatusCalls, run: Run, lang: Lang = stationLang()) {
    this.calls = calls;
    this.run = run;
    this.lang = lang;
  }

  say(status: string, page: string | null) {
    if (page !== null) this.page = page;
    this.wanted = status;
    if (this.timer) return;
    this.timer = true;
    const due = Clock.currentTimeMillis.pipe(
      Effect.flatMap((now) => Effect.sleep(status === "" ? 0 : Math.max(0, this.lastAt + MIN_INTERVAL_MS - now))),
      Effect.andThen(Clock.currentTimeMillis),
      Effect.flatMap((now) => Effect.promise(() => this.due(now))),
    );
    void this.run(due).catch(() => {});
  }

  private async due(now: number) {
    this.timer = false;
    if (this.wanted === this.shown) return;
    this.lastAt = now;
    const next = this.wanted;
    const sent = this.sending.then(() => this.send(next, now));
    this.sending = sent.catch(() => {});
    await sent;
  }

  private async send(status: string, now: number) {
    this.shown = status;
    try {
      if (status === "") {
        const card = this.card;
        this.card = null;
        if (card !== null) await this.change(card, doneCard(now - this.startedAt, this.page, this.lang));
        return;
      }
      if (this.card === null) {
        this.startedAt = now;
        this.card = await this.open(workingCard(status));
        return;
      }
      await this.change(this.card, workingCard(status));
    } catch (error) {
      log.warn("feishu", "could not say the agent's status in Feishu", { error: (error as Error).message });
    }
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

  private async change(at: { id: string | null; message: string | null; sequence: number }, card: Json) {
    if (at.id !== null) {
      at.sequence++;
      await this.calls.api("PUT", `/open-apis/cardkit/v1/cards/${at.id}`, { card: { type: "card_json", data: JSON.stringify(card) }, sequence: at.sequence });
    } else if (at.message !== null) await this.calls.api("PATCH", `/open-apis/im/v1/messages/${at.message}`, { content: inline(card) });
  }
}
