// Slack over Socket Mode (no public endpoint needed) and the Web API, with no
// SDK: Node's WebSocket and fetch are enough for what ember uses.
import { log } from "../log.ts";
import { splitForSlack, toMrkdwn } from "./mrkdwn.ts";
import type { ChatMessage, ChatSurface, InboundMessage, ThreadRef } from "./types.ts";

/** Message subtypes that are still a person talking. */
const CONTENT_SUBTYPES = new Set([undefined, "file_share", "thread_broadcast"]);

/** Who a bot token belongs to, as Slack reports it. */
export interface SlackIdentity {
  team: string;
  teamId: string;
  /** Workspace URL, e.g. https://cue.slack.com/ */
  url: string;
  botUserId: string;
  botName: string;
}

/**
 * Checks a token pair without connecting: the bot token must authenticate, and
 * the app-level token must be allowed to open a Socket Mode connection.
 */
export async function verifySlackTokens(tokens: { appToken: string; botToken: string }): Promise<{ identity: SlackIdentity | null; errors: string[] }> {
  const errors: string[] = [];
  let identity: SlackIdentity | null = null;
  if (!tokens.botToken.startsWith("xoxb-")) errors.push("Bot Token 应该以 xoxb- 开头");
  else {
    try {
      identity = identityOf(await slackApi("auth.test", {}, tokens.botToken));
    } catch (error) {
      errors.push(`Bot Token 无效：${error instanceof Error ? error.message : String(error)}`);
    }
  }
  if (!tokens.appToken.startsWith("xapp-")) errors.push("App-Level Token 应该以 xapp- 开头");
  else {
    try {
      await slackApi("apps.connections.open", {}, tokens.appToken);
    } catch (error) {
      errors.push(`App-Level Token 无法建立 Socket Mode 连接：${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return { identity, errors };
}

function identityOf(auth: Record<string, any>): SlackIdentity {
  return { team: String(auth.team ?? ""), teamId: String(auth.team_id ?? ""), url: String(auth.url ?? ""), botUserId: String(auth.user_id ?? ""), botName: String(auth.user ?? "") };
}

async function slackApi(method: string, params: Record<string, string>, token: string): Promise<Record<string, any>> {
  for (let attempt = 0; ; attempt++) {
    const response = await fetch(`https://slack.com/api/${method}`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params),
    });
    if (response.status === 429 && attempt < 5) {
      const wait = Number(response.headers.get("retry-after") ?? "1") * 1000;
      await new Promise((r) => setTimeout(r, wait));
      continue;
    }
    const body = await response.json() as Record<string, any>;
    if (!body.ok) throw new Error(`slack ${method}: ${String(body.error)}`);
    return body;
  }
}

export class SlackSurface implements ChatSurface {
  readonly #appToken: string;
  readonly #botToken: string;
  #identity: SlackIdentity | null = null;
  readonly #names = new Map<string, Promise<string | null>>();
  #socket: WebSocket | undefined;
  #stopped = false;
  #connected = false;
  #lastError: string | null = null;

  constructor(tokens: { appToken: string; botToken: string }) {
    if (!tokens.appToken.startsWith("xapp-")) throw new Error("slack.appToken must be an app-level token (xapp-…)");
    if (!tokens.botToken.startsWith("xoxb-")) throw new Error("slack.botToken must be a bot token (xoxb-…)");
    this.#appToken = tokens.appToken;
    this.#botToken = tokens.botToken;
  }

  get botUserId(): string {
    return this.#identity?.botUserId ?? "";
  }

  get identity(): SlackIdentity | null {
    return this.#identity;
  }

  /** For the admin page: whether the socket is up, and the last connection error. */
  get status(): { connected: boolean; lastError: string | null } {
    return { connected: this.#connected, lastError: this.#lastError };
  }

  async start(handler: (message: InboundMessage) => Promise<void>): Promise<void> {
    this.#identity = identityOf(await this.#api("auth.test", {}, this.#botToken));
    log.info("slack authenticated", { botUserId: this.#identity.botUserId, team: this.#identity.team });
    void this.#connectLoop(handler);
  }

  async stop(): Promise<void> {
    this.#stopped = true;
    this.#socket?.close();
  }

  async post(thread: ThreadRef, markdown: string): Promise<void> {
    for (const text of splitForSlack(toMrkdwn(markdown))) {
      await this.#api("chat.postMessage", { channel: thread.channel, thread_ts: thread.threadTs, text, unfurl_links: "false" }, this.#botToken);
    }
  }

  /** Display name via users.info, cached for the connection's lifetime. */
  userName(userId: string): Promise<string | null> {
    let name = this.#names.get(userId);
    if (!name) {
      name = this.#api("users.info", { user: userId }, this.#botToken)
        .then((r) => {
          const u = r.user ?? {};
          return String(u.profile?.display_name || u.real_name || u.name || "") || null;
        })
        .catch(() => {
          this.#names.delete(userId); // retry next time rather than caching a failure
          return null;
        });
      this.#names.set(userId, name);
    }
    return name;
  }

  async history(thread: ThreadRef, before: string | undefined, limit: number): Promise<ChatMessage[]> {
    const all: ChatMessage[] = [];
    let cursor: string | undefined;
    do {
      const page = await this.#api("conversations.replies", {
        channel: thread.channel, ts: thread.threadTs, limit: "200", ...(cursor ? { cursor } : {}),
      }, this.#botToken);
      for (const m of (page.messages ?? []) as Record<string, any>[]) {
        all.push({ ts: String(m.ts), user: String(m.user ?? m.bot_id ?? "unknown"), text: String(m.text ?? ""), fromBot: Boolean(m.bot_id) || m.user === this.botUserId });
      }
      cursor = page.response_metadata?.next_cursor || undefined;
    } while (cursor);
    const earlier = before === undefined ? all : all.filter((m) => Number(m.ts) < Number(before));
    return earlier.slice(-limit);
  }

  async #connectLoop(handler: (message: InboundMessage) => Promise<void>): Promise<void> {
    let backoff = 1000;
    while (!this.#stopped) {
      try {
        const { url } = await this.#api("apps.connections.open", {}, this.#appToken);
        await this.#runSocket(String(url), handler);
        backoff = 1000;
      } catch (error) {
        this.#lastError = error instanceof Error ? error.message : String(error);
        log.warn("slack socket failed", { error, retryInMs: backoff });
        await new Promise((r) => setTimeout(r, backoff));
        backoff = Math.min(backoff * 2, 60_000);
      }
    }
  }

  /** Resolves when the socket closes (Slack rotates connections routinely). */
  #runSocket(url: string, handler: (message: InboundMessage) => Promise<void>): Promise<void> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      this.#socket = socket;
      socket.addEventListener("open", () => {
        this.#connected = true;
        this.#lastError = null;
      });
      socket.addEventListener("close", () => {
        this.#connected = false;
        resolve();
      });
      socket.addEventListener("error", () => reject(new Error("slack socket error")));
      socket.addEventListener("message", (event) => {
        void (async () => {
          const envelope = JSON.parse(String(event.data)) as Record<string, any>;
          if (envelope.type === "disconnect") {
            log.info("slack asked to reconnect", { reason: envelope.reason });
            socket.close();
            return;
          }
          if (envelope.type !== "events_api") return;
          const message = this.#toInbound(envelope.payload?.event ?? {});
          try {
            if (message) await handler(message);
            socket.send(JSON.stringify({ envelope_id: envelope.envelope_id }));
          } catch (error) {
            // Not acknowledged: Slack redelivers, and the store dedupes.
            log.error("failed to accept slack event", { error, eventId: envelope.payload?.event_id });
          }
        })();
      });
    });
  }

  #toInbound(event: Record<string, any>): InboundMessage | undefined {
    if (event.type !== "app_mention" && event.type !== "message") return undefined;
    if (!CONTENT_SUBTYPES.has(event.subtype) || event.bot_id || !event.user || event.user === this.botUserId) return undefined;
    const text = String(event.text ?? "");
    return {
      channel: String(event.channel),
      threadTs: String(event.thread_ts ?? event.ts),
      ts: String(event.ts),
      user: String(event.user),
      text,
      addressed: event.type === "app_mention" || event.channel_type === "im" || text.includes(`<@${this.botUserId}>`),
    };
  }

  #api(method: string, params: Record<string, string>, token: string): Promise<Record<string, any>> {
    return slackApi(method, params, token);
  }
}
