// What an agent is doing, said in the Slack thread it works for while it works (chat/status.rs; when and how often:
// connects/status.ts): an agent session under the thread (agents.sessions.setStatus). Where Slack will not
// show one (the app lacks the scope, the conversation does not take it), an 👀 on the message that started the work says
// the same, and goes when it is done.
import { type Run, StatusLine } from "../connects/status.ts";
import { log } from "../ops/log.ts";
import type { Params } from "./web.ts";

/// How often the status line may change: Slack's limit on the call, and enough to follow along.
export const MIN_INTERVAL_MS = 2_000;
const FALLBACK_REACTION = "eyes";

/// What Slack answers when it will not show a status here: the reaction says it instead.
const noStatus = (error: string) =>
  ["missing_scope", "unknown_method", "not_allowed_token_type", "feature_not_enabled", "method_not_supported_for_channel_type", "not_in_channel"].some((code) =>
    error.includes(code),
  );

/// A Web API call as the bot; fails with Slack's error.
export type Call = (method: string, params: Params) => Promise<void>;

/// One thread's status line. `say("")` clears it.
export class ThreadStatus extends StatusLine {
  private call: Call;
  readonly channel: string;
  readonly threadTs: string;
  /// Slack will not show a status line here: the reaction stands in.
  private reactionOnly = false;
  /// An app that cannot yet use agent sessions can still show the older status for this turn.
  private legacy = false;
  private reacted: string | null = null;

  constructor(call: Call, run: Run, channel: string, threadTs: string) {
    super(run, MIN_INTERVAL_MS);
    this.call = call;
    this.channel = channel;
    this.threadTs = threadTs;
  }

  protected async show(status: string): Promise<boolean> {
    if (!this.reactionOnly) {
      const address: Params = [
        ["channel_id", this.channel],
        ["thread_ts", this.threadTs],
      ];
      if (!this.legacy) {
        try {
          await this.call("agents.sessions.setStatus", [...address, ["status", status === "" ? "active" : "processing"]]);
          return true;
        } catch (error) {
          const said = (error as Error).message;
          if (!noStatus(said) && !["not_authorized", "feature_disabled"].some((code) => said.includes(code))) {
            log.warn("slack", "could not say the agent's status in Slack", { channel: this.channel, thread: this.threadTs, error: said });
            return false;
          }
          this.legacy = true;
        }
      }
      const params: Params = [...address, ["status", status]];
      if (status !== "") params.push(["loading_messages", status]);
      try {
        await this.call("assistant.threads.setStatus", params);
        if (status === "") this.legacy = false;
        return true;
      } catch (error) {
        const said = (error as Error).message;
        if (!noStatus(said)) {
          log.warn("slack", "could not say the agent's status in Slack", { channel: this.channel, thread: this.threadTs, error: said });
          return false;
        }
        this.reactionOnly = true;
      }
    }
    const [target, reacted] = [this.messageTs, this.reacted];
    try {
      if (status !== "") {
        if (target !== null && reacted !== target) {
          await this.call("reactions.add", this.reaction(target));
          this.reacted = target;
        }
      } else if (reacted !== null) {
        this.reacted = null;
        await this.call("reactions.remove", this.reaction(reacted));
      }
    } catch (error) {
      const said = (error as Error).message;
      if (!said.includes("already_reacted") && !said.includes("no_reaction")) log.warn("slack", "could not mark the agent's work in Slack", { channel: this.channel, error: said });
    }
    return true;
  }

  private reaction(timestamp: string): Params {
    return [
      ["channel", this.channel],
      ["timestamp", timestamp],
      ["name", FALLBACK_REACTION],
    ];
  }
}
