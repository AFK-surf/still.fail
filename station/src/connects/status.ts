// What an agent is doing, said where it works while it works (the words: sessions/chat.ts `toolStatus`): one line per
// thread, changed at most once an interval (the first change at once), one change at a time and in order, only the
// latest of those said meanwhile, cleared ("") once the turn ends. How a platform shows it is its own: Slack's status
// line (slack/status.ts), Feishu's card (feishu/status.ts).
import { Clock, Effect } from "effect";

/// Runs an effect as a fiber of whoever owns the line (its timers end with it).
export type Run = (effect: Effect.Effect<void>) => Promise<void>;

export abstract class StatusLine {
  private readonly run: Run;
  private readonly interval: number;
  /// The message that started the work, and the session's page in still.fail (where there is one), as last said.
  protected messageTs: string | null = null;
  protected page: string | null = null;
  private shown = "";
  private wanted = "";
  /// When it last changed (never, at first: the first change goes at once, whatever the clock says).
  private lastAt = Number.NEGATIVE_INFINITY;
  private timer = false;
  private sending: Promise<void> = Promise.resolve();

  constructor(run: Run, interval: number) {
    this.run = run;
    this.interval = interval;
  }

  /// Shows `status` ("": the turn ended) at `now`: whether it was shown (one that was not is tried again with the next).
  protected abstract show(status: string, now: number): Promise<boolean>;

  say(status: string, messageTs: string | null = null, page: string | null = null) {
    if (messageTs !== null) this.messageTs = messageTs;
    if (page !== null) this.page = page;
    this.wanted = status;
    if (this.timer) return;
    this.timer = true;
    // On the clock of whoever runs it (a TestClock in tests).
    const due = Clock.currentTimeMillis.pipe(
      Effect.flatMap((now) => Effect.sleep(status === "" ? 0 : Math.max(0, this.lastAt + this.interval - now))),
      Effect.andThen(Clock.currentTimeMillis),
      Effect.flatMap((now) => Effect.promise(() => this.due(now))),
    );
    void this.run(due).catch(() => {});
  }

  private async due(now: number) {
    this.timer = false;
    if (this.wanted === this.shown) return;
    this.lastAt = now;
    const [was, next] = [this.shown, this.wanted];
    // Shown as it goes: said again meanwhile, it does not go twice; not shown after all, it goes with the next.
    this.shown = next;
    const sent = this.sending.then(async () => {
      if (!(await this.show(next, now)) && this.shown === next) this.shown = was;
    });
    this.sending = sent.catch(() => {});
    await sent;
  }
}
