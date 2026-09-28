// Slack over Socket Mode (no public endpoint needed) and the Web API, with no
// SDK: Node's WebSocket and fetch are enough for what ember uses.
import { log } from "../log.ts";
import { splitForSlack } from "./mrkdwn.ts";
import { ThreadStatus } from "./slack-status.ts";
import type { ChatEvent, ChatMessage, ChatSurface, InboundMessage, ThreadRef } from "./types.ts";
import type { Attachment } from "../store.ts";
import type { NameBook, Person } from "./names.ts";

/** Message subtypes that are someone talking: a person, or another app's bot (agents work together in threads). */
const CONTENT_SUBTYPES = new Set([undefined, "file_share", "thread_broadcast", "bot_message"]);

/** Who a bot token belongs to, as Slack reports it. */
export interface SlackIdentity {
  team: string;
  teamId: string;
  /** Workspace URL, e.g. https://acme.slack.com/ */
  url: string;
  botUserId: string;
  botName: string;
  /** Its bot's picture (the app's icon), as Slack shows it; null when Slack does not say. */
  botImage: string | null;
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
      identity = await identityOf(await slackApi("auth.test", {}, tokens.botToken), (id) => slackApi("users.info", { user: id }, tokens.botToken));
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


/** Who the bot is, and where: its name as people see it in that workspace (not its handle), when Slack says. */
async function identityOf(auth: Record<string, any>, userInfo: (id: string) => Promise<Record<string, any>>): Promise<SlackIdentity> {
  const botUserId = String(auth.user_id ?? "");
  const user = await userInfo(botUserId).then((d) => d.user, () => null);
  const shown = [user?.profile?.display_name, user?.real_name, user?.profile?.real_name].find((n) => typeof n === "string" && n.trim());
  const image = [user?.profile?.image_72, user?.profile?.image_48, user?.profile?.image_original].find((u) => typeof u === "string" && u.startsWith("https://"));
  return { team: String(auth.team ?? ""), teamId: String(auth.team_id ?? ""), url: String(auth.url ?? ""), botUserId, botName: shown ? String(shown) : String(auth.user ?? ""), botImage: image ? String(image) : null };
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
  /** This app's bot id (B…), which its own messages carry besides its user. */
  #botId = "";
  readonly #names = new Map<string, Promise<{ name: string; email: string } | null>>();
  readonly #channels = new Map<string, Promise<string | null>>();
  #socket: WebSocket | undefined;
  #stopped = false;
  #connected = false;
  #lastError: string | null = null;
  readonly #statusListeners = new Set<() => void>();
  /** Each thread an agent works for: its status line (slack-status.ts). */
  readonly #working = new Map<string, ThreadStatus>();

  readonly #book: NameBook | undefined;

  /** `book` keeps names across restarts and lets the admin API ask without waiting (knownPerson, knownChannel). */
  constructor(tokens: { appToken: string; botToken: string }, book?: NameBook) {
    this.#book = book;
    if (!tokens.appToken.startsWith("xapp-")) throw new Error("slack.appToken must be an app-level token (xapp-…)");
    if (!tokens.botToken.startsWith("xoxb-")) throw new Error("slack.botToken must be a bot token (xoxb-…)");
    this.#appToken = tokens.appToken;
    this.#botToken = tokens.botToken;
  }

  get botUserId(): string {
    return this.#identity?.botUserId ?? "";
  }

  get botName(): string {
    return this.#identity?.botName ?? "";
  }

  get identity(): SlackIdentity | null {
    return this.#identity;
  }

  get workspace(): string | null {
    return this.#identity?.teamId || null;
  }

  /** For the admin page: whether the socket is up, and the last connection error. */
  get status(): { connected: boolean; lastError: string | null } {
    return { connected: this.#connected, lastError: this.#lastError };
  }

  /** Calls `listener` whenever `status` changes. */
  onStatus(listener: () => void): void {
    this.#statusListeners.add(listener);
  }

  #setStatus(connected: boolean, lastError: string | null): void {
    if (connected === this.#connected && lastError === this.#lastError) return;
    this.#connected = connected;
    this.#lastError = lastError;
    for (const listener of this.#statusListeners) listener();
  }

  async #authenticate(): Promise<void> {
    const auth = await this.#api("auth.test", {}, this.#botToken);
    this.#botId = String(auth.bot_id ?? "");
    this.#identity = await identityOf(auth, (id) => this.#api("users.info", { user: id }, this.#botToken));
  }

  /** A message this bot posted itself (the station records those as it posts them). */
  #own(event: Record<string, any>): boolean {
    return (Boolean(event.user) && event.user === this.botUserId) || (Boolean(event.bot_id) && event.bot_id === this.#botId);
  }

  async refreshIdentity(): Promise<void> {
    await this.#authenticate();
    for (const listener of this.#statusListeners) listener();
  }

  async start(handler: (event: ChatEvent) => Promise<void>): Promise<void> {
    await this.#authenticate();
    log.info("slack authenticated", { botUserId: this.botUserId, team: this.#identity?.team });
    void this.#connectLoop(handler);
  }

  async stop(): Promise<void> {
    this.#stopped = true;
    this.#socket?.close();
  }

  /** Posted as written (the agent writes Slack's formatting); a long message goes out in parts, the first part's ts standing for the whole. */
  async post(thread: ThreadRef, message: string, files: Attachment[] = []): Promise<string> {
    if (files.length) throw new Error("attaching files is not supported in Slack yet; mention the file paths in the text instead");
    let first: string | undefined;
    for (const text of splitForSlack(message)) {
      const posted = await this.#api("chat.postMessage", { channel: thread.channel, thread_ts: thread.threadTs, text, unfurl_links: "false" }, this.#botToken);
      first ??= String(posted.ts);
    }
    if (first === undefined) throw new Error("nothing to post");
    return first;
  }

  /** Display name via users.info, cached for the connection's lifetime. */
  async userName(userId: string): Promise<string | null> {
    return (await this.#profile(userId))?.name || null;
  }

  /** The person's email (users:read.email), which ties a Slack user to an ember cloud account. */
  async userEmail(userId: string): Promise<string | null> {
    return (await this.#profile(userId))?.email || null;
  }

  #profile(userId: string): Promise<{ name: string; email: string } | null> {
    let profile = this.#names.get(userId);
    if (!profile) {
      profile = this.#api("users.info", { user: userId }, this.#botToken)
        .then((r) => {
          const u = r.user ?? {};
          return { name: String(u.profile?.display_name || u.real_name || u.name || ""), email: String(u.profile?.email ?? "").toLowerCase() };
        })
        .catch(() => {
          this.#names.delete(userId); // retry next time rather than caching a failure
          return null;
        });
      this.#names.set(userId, profile);
    }
    return profile;
  }

  /** A person as far as already known, without waiting; an unknown one is looked up in the background. */
  knownPerson(userId: string): Person | null {
    return this.#book?.person(`u:${this.#identity?.teamId ?? "?"}:${userId}`, () => this.#profile(userId)) ?? null;
  }

  /** A channel's name as far as already known (null for DMs or not yet known), without waiting. */
  knownChannel(channelId: string): string | null {
    return this.#book?.channel(`c:${this.#identity?.teamId ?? "?"}:${channelId}`, () => this.channelName(channelId)) ?? null;
  }

  /** Channel name via conversations.info (null for DMs), cached for the connection's lifetime. */
  channelName(channelId: string): Promise<string | null> {
    let name = this.#channels.get(channelId);
    if (!name) {
      name = this.#api("conversations.info", { channel: channelId }, this.#botToken)
        .then((r) => (r.channel?.is_im ? null : String(r.channel?.name ?? "") || null))
        .catch(() => {
          this.#channels.delete(channelId);
          return null;
        });
      this.#channels.set(channelId, name);
    }
    return name;
  }

  async history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
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
    return all.filter((m) => Number(m.ts) < Number(before)).slice(-limit);
  }

  async #connectLoop(handler: (event: ChatEvent) => Promise<void>): Promise<void> {
    let backoff = 1000;
    while (!this.#stopped) {
      try {
        const { url } = await this.#api("apps.connections.open", {}, this.#appToken);
        await this.#runSocket(String(url), handler);
        backoff = 1000;
      } catch (error) {
        this.#setStatus(false, error instanceof Error ? error.message : String(error));
        log.warn("slack socket failed", { error, retryInMs: backoff });
        await new Promise((r) => setTimeout(r, backoff));
        backoff = Math.min(backoff * 2, 60_000);
      }
    }
  }

  /** Resolves when the socket closes (Slack rotates connections routinely). */
  #runSocket(url: string, handler: (event: ChatEvent) => Promise<void>): Promise<void> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      this.#socket = socket;
      socket.addEventListener("open", () => this.#setStatus(true, null));
      socket.addEventListener("close", () => {
        this.#setStatus(false, this.#lastError);
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
          const chatEvent = this.#toEvent(envelope.payload?.event ?? {});
          try {
            if (chatEvent) await handler(chatEvent);
            socket.send(JSON.stringify({ envelope_id: envelope.envelope_id }));
          } catch (error) {
            // Not acknowledged: Slack redelivers, and the store dedupes.
            log.error("failed to accept slack event", { error, eventId: envelope.payload?.event_id });
          }
        })();
      });
    });
  }

  #toEvent(event: Record<string, any>): ChatEvent | undefined {
    if (event.type === "message" && event.subtype === "message_changed") {
      const changed = event.message ?? {};
      if (!changed.ts || this.#own(changed)) return undefined;
      // A message outside any thread is the root of its own.
      return { kind: "changed", channel: String(event.channel), threadTs: String(changed.thread_ts ?? changed.ts), ts: String(changed.ts), text: String(changed.text ?? "") };
    }
    // ember has no retraction: a deleted message stays as it was said.
    if (event.type === "message" && event.subtype === "message_deleted") return undefined;
    const message = this.#toInbound(event);
    return message && { kind: "message", message };
  }

  #toInbound(event: Record<string, any>): InboundMessage | undefined {
    if (event.type !== "app_mention" && event.type !== "message") return undefined;
    if (!CONTENT_SUBTYPES.has(event.subtype) || this.#own(event)) return undefined;
    // A person, or another app's bot: its bot user when Slack gives one, else its bot id.
    const user = String(event.user ?? event.bot_id ?? "");
    if (!user) return undefined;
    const text = String(event.text ?? "");
    return {
      channel: String(event.channel),
      threadTs: String(event.thread_ts ?? event.ts),
      ts: String(event.ts),
      user,
      text,
      addressed: event.type === "app_mention" || event.channel_type === "im" || text.includes(`<@${this.botUserId}>`),
    };
  }

  /** Any Web API method as the bot; values that are not strings (blocks, arrays) go as JSON, as Slack takes them. */
  api(method: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
    const form = Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined && v !== null)
      .map(([k, v]) => [k, typeof v === "string" ? v : JSON.stringify(v)]));
    return this.#api(method, form, this.#botToken);
  }

  working(thread: ThreadRef, messageTs: string | null, status: string): void {
    const key = `${thread.channel}/${thread.threadTs}`;
    let line = this.#working.get(key);
    if (!line) {
      line = new ThreadStatus((method, params) => this.#api(method, params, this.#botToken), thread.channel, thread.threadTs);
      this.#working.set(key, line);
    }
    line.say(status, messageTs);
    if (status === "" && this.#working.size > 200) this.#working.delete(key);
  }

  #api(method: string, params: Record<string, string>, token: string): Promise<Record<string, any>> {
    return slackApi(method, params, token);
  }
}
