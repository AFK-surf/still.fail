// Slack over Socket Mode (no public endpoint needed) and the Web API, with no
// SDK: Node's WebSocket and fetch are enough for what ember uses.
import { log } from "../log.ts";
import { splitForSlack, toMrkdwn } from "./mrkdwn.ts";
import type { ChatMessage, ChatSurface, InboundMessage, ThreadRef } from "./types.ts";

/** Message subtypes that are still a person talking. */
const CONTENT_SUBTYPES = new Set([undefined, "file_share", "thread_broadcast"]);

export class SlackSurface implements ChatSurface {
  readonly #appToken: string;
  readonly #botToken: string;
  #botUserId = "";
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
    return this.#botUserId;
  }

  /** For the admin page: whether the socket is up, and the last connection error. */
  get status(): { connected: boolean; lastError: string | null } {
    return { connected: this.#connected, lastError: this.#lastError };
  }

  async start(handler: (message: InboundMessage) => Promise<void>): Promise<void> {
    const auth = await this.#api("auth.test", {}, this.#botToken);
    this.#botUserId = String(auth.user_id);
    log.info("slack authenticated", { botUserId: this.#botUserId, team: auth.team });
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

  async history(thread: ThreadRef, before: string | undefined, limit: number): Promise<ChatMessage[]> {
    const all: ChatMessage[] = [];
    let cursor: string | undefined;
    do {
      const page = await this.#api("conversations.replies", {
        channel: thread.channel, ts: thread.threadTs, limit: "200", ...(cursor ? { cursor } : {}),
      }, this.#botToken);
      for (const m of (page.messages ?? []) as Record<string, any>[]) {
        all.push({ ts: String(m.ts), user: String(m.user ?? m.bot_id ?? "unknown"), text: String(m.text ?? ""), fromBot: Boolean(m.bot_id) || m.user === this.#botUserId });
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
    if (!CONTENT_SUBTYPES.has(event.subtype) || event.bot_id || !event.user || event.user === this.#botUserId) return undefined;
    const text = String(event.text ?? "");
    return {
      channel: String(event.channel),
      threadTs: String(event.thread_ts ?? event.ts),
      ts: String(event.ts),
      user: String(event.user),
      text,
      addressed: event.type === "app_mention" || event.channel_type === "im" || text.includes(`<@${this.#botUserId}>`),
    };
  }

  async #api(method: string, params: Record<string, string>, token: string): Promise<Record<string, any>> {
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
}
