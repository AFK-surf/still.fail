// What an agent is doing, said in the Slack thread it works for while it works: Slack's own status line under the
// thread (assistant.threads.setStatus), updated at most every couple of seconds and cleared when the turn ends. Where
// Slack will not show one (the app lacks the scope, the conversation does not take it), an 👀 on the message that
// started the work says the same, and goes when it is done.
import { log } from "../log.ts";

/** How often the status line may change: Slack's limit on the call, and enough to follow along. */
const MIN_INTERVAL_MS = 2_000;
const FALLBACK_REACTION = "eyes";
/** What Slack answers when it will not show a status here: the reaction says it instead. */
const NO_STATUS = /missing_scope|unknown_method|not_allowed_token_type|feature_not_enabled|method_not_supported_for_channel_type|not_in_channel/;

type Call = (method: string, params: Record<string, string>) => Promise<unknown>;

/** One thread's status line. `say("")` clears it. */
export class ThreadStatus {
  readonly #call: Call;
  readonly #channel: string;
  readonly #threadTs: string;
  /** The message that started the work: where the fallback reaction goes. */
  #messageTs: string | null = null;
  #shown = "";
  #wanted = "";
  #lastAt = 0;
  #timer: ReturnType<typeof setTimeout> | undefined;
  #chain: Promise<void> = Promise.resolve();
  /** Slack will not show a status line here: the reaction stands in. */
  #reactionOnly = false;
  #reacted: string | null = null;

  constructor(call: Call, channel: string, threadTs: string) {
    this.#call = call;
    this.#channel = channel;
    this.#threadTs = threadTs;
  }

  say(status: string, messageTs: string | null): void {
    if (messageTs) this.#messageTs = messageTs;
    this.#wanted = status;
    if (this.#timer) return;
    const wait = status === "" ? 0 : Math.max(0, this.#lastAt + MIN_INTERVAL_MS - Date.now());
    this.#timer = setTimeout(() => {
      this.#timer = undefined;
      const next = this.#wanted;
      if (next === this.#shown) return;
      this.#lastAt = Date.now();
      this.#chain = this.#chain.then(() => this.#send(next));
    }, wait);
    this.#timer.unref?.();
  }

  async #send(status: string): Promise<void> {
    if (!this.#reactionOnly) {
      try {
        await this.#call("assistant.threads.setStatus", {
          channel_id: this.#channel, thread_ts: this.#threadTs, status, ...(status ? { loading_messages: status } : {}),
        });
        this.#shown = status;
        return;
      } catch (error) {
        if (!NO_STATUS.test(String(error))) {
          log.warn("could not say the agent's status in Slack", { channel: this.#channel, thread: this.#threadTs, error: String(error) });
          return;
        }
        this.#reactionOnly = true;
      }
    }
    this.#shown = status;
    const target = this.#messageTs;
    try {
      if (status && target && this.#reacted !== target) {
        await this.#call("reactions.add", { channel: this.#channel, timestamp: target, name: FALLBACK_REACTION });
        this.#reacted = target;
      } else if (!status && this.#reacted) {
        const reacted = this.#reacted;
        this.#reacted = null;
        await this.#call("reactions.remove", { channel: this.#channel, timestamp: reacted, name: FALLBACK_REACTION });
      }
    } catch (error) {
      if (!/already_reacted|no_reaction/.test(String(error))) log.warn("could not mark the agent's work in Slack", { channel: this.#channel, error: String(error) });
    }
  }
}

/** A tool call in words for the status line, by the tool's name (Claude Code's or Codex's). */
export function toolStatus(tool: string): string {
  const name = tool.toLowerCase().replace(/^mcp__[^_]+__/, "");
  if (/^(read|grep|glob|ls|list|view|search_files|stat)/.test(name)) return "正在查看文件…";
  if (/^(edit|multiedit|write|apply_patch|notebookedit|delete|copy)/.test(name)) return "正在修改文件…";
  if (/^(bash|shell|exec|exec_command|local_shell|unified_exec|run)/.test(name)) return "正在运行命令…";
  if (/^(websearch|web_search|search_query|image_query)/.test(name)) return "正在搜索网页…";
  if (/^(webfetch|fetch|browse)/.test(name)) return "正在读网页…";
  if (/^(task|agent|spawn)/.test(name)) return "正在交给子任务…";
  if (/^(chat_|slack)/.test(name)) return "正在看 Slack…";
  if (/^(todowrite|update_plan|plan)/.test(name)) return "正在安排步骤…";
  return "正在处理…";
}
