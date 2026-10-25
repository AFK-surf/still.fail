// Feishu as a chat surface (docs/feishu.md): its long connection for what Feishu tells the station (no public endpoint
// needed), the OpenAPI for what the station and its agents say and ask. One FeishuSurface per connected connect; its
// connection loop is a fiber in the surface's scope, and stopping the surface closes the scope (the socket with it).
import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import { Clock, Deferred, Effect, Exit, FiberSet, Result, Scope } from "effect";
import WebSocket from "ws";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/store.ts";
import type { ChatEvent, ChatMessage, ChatSurface, Handler, InboundFile, Person, Place, ThreadRef } from "../sessions/chat.ts";
import type { NameBook } from "../slack/names.ts";
import type { SlackIdentity, SocketStatus } from "../slack/surface.ts";
import { type Answer, answeredCard, inline, questionCard, textCards } from "./cards.ts";
import { CONTROL, DATA, type Frame, Parts, decode, encode, header } from "./frame.ts";
import { type FeishuMessage, cardAnswerOf, listedAsEvent, messageOf, resourceOf } from "./parse.ts";
import { FeishuStatus } from "./status.ts";
import type { FeishuThreads } from "./threads.ts";
import { type Domain, FeishuClient } from "./web.ts";

type Json = any;

const text = (v: unknown): string => (typeof v === "string" ? v : "");

/// Who the bot is and where, as the pages are shown a Slack connect's (`shownIdentity`): its name and picture, its open_id
/// as its user, its company as its team.
export async function identityOf(client: FeishuClient): Promise<SlackIdentity> {
  const info = await client.api("GET", "/open-apis/bot/v3/info");
  const bot = info?.bot ?? info?.data?.bot ?? {};
  let team = "";
  let teamId = "";
  try {
    const t = (await client.api("GET", "/open-apis/tenant/v2/tenant/query"))?.data?.tenant ?? {};
    team = text(t.name);
    teamId = text(t.tenant_key);
  } catch {}
  const image = text(bot.avatar_url);
  return { team, teamId, url: "", botUserId: text(bot.open_id), botName: text(bot.app_name), botImage: image.startsWith("https://") ? image : null, botId: "" };
}

/// Checks an app's id and secret without connecting: its token is taken, its bot read, and the long connection's address
/// asked for. Its problems are said in `lang`.
export async function verifyFeishuApp(appId: string, appSecret: string, domain: Domain, lang: Lang = stationLang()): Promise<[SlackIdentity | null, string[]]> {
  if (!/^cli_[0-9a-z]+$/i.test(appId)) return [null, [tr(lang, "station.feishu.badAppId")]];
  if (appSecret.trim() === "") return [null, [tr(lang, "station.feishu.noSecret")]];
  const client = new FeishuClient(appId, appSecret, domain);
  try {
    await client.tenantToken();
  } catch (e) {
    return [null, [tr(lang, "station.feishu.badSecret", { error: (e as Error).message })]];
  }
  let identity: SlackIdentity | null = null;
  const errors: string[] = [];
  try {
    identity = await identityOf(client);
    if (identity.botUserId === "") errors.push(tr(lang, "station.feishu.noBot"));
  } catch (e) {
    errors.push(tr(lang, "station.feishu.botUnread", { error: (e as Error).message }));
  }
  try {
    await client.endpoint();
  } catch (e) {
    errors.push(tr(lang, "station.feishu.noLongConnection", { error: (e as Error).message }));
  }
  return [identity, errors];
}

/// What Feishu takes as a message's file type, by its name.
function fileType(name: string): string {
  const ext = extname(name).toLowerCase();
  if (ext === ".opus") return "opus";
  if ([".mp4", ".mov", ".m4v"].includes(ext)) return "mp4";
  if (ext === ".pdf") return "pdf";
  if ([".doc", ".docx"].includes(ext)) return "doc";
  if ([".xls", ".xlsx", ".csv"].includes(ext)) return "xls";
  if ([".ppt", ".pptx"].includes(ext)) return "ppt";
  return "stream";
}
const IMAGE = /\.(png|jpe?g|gif|webp|bmp|ico|tiff?)$/i;
/// Images Feishu takes as images (larger ones go as files).
const MAX_IMAGE = 10 * 1024 * 1024;

/// A question posted, kept until it is answered: what it said, for the answered card.
type Asked = { text: string; card: Json; thread: string; answered: boolean };

export type FeishuSurfaceOptions = {
  connect: string;
  appId: string;
  appSecret: string;
  domain: Domain;
  threads: FeishuThreads;
  /// Keeps names across restarts and lets the admin API ask without waiting (knownPerson, knownChannel).
  book?: NameBook | null;
  /// The client (tests: one pointed at a stand-in).
  client?: FeishuClient;
  /// How long the socket may say nothing before it is taken for dead, and how often it is pinged meanwhile.
  pingMs?: number;
  staleMs?: number;
  /// The first wait before connecting again after a failure (doubling up to a minute).
  backoffMs?: number;
  clock?: Clock.Clock;
  onHeard?: () => void;
};

const MAX_BACKOFF_MS = 60_000;
/// Feishu pings every two minutes; the station asks more often, to find a connection cut on the way sooner.
const PING_MS = 15_000;
const STALE_MS = 45_000;

export class FeishuSurface implements ChatSurface {
  readonly connect: string;
  readonly client: FeishuClient;
  readonly domain: Domain;
  readonly cards = true;
  private threads: FeishuThreads;
  private book: NameBook | null;
  private me: SlackIdentity | null = null;
  private status: SocketStatus = { connected: false, lastError: null };
  private listeners = new Set<() => void>();
  private names = new Map<string, Person>();
  /// Chats as Feishu says: their name, whether they are a topic group (each topic its own conversation), a direct one.
  private chats = new Map<string, { name: string | null; topics: boolean; p2p: boolean }>();
  /// The chat a person was last heard in: where their name is looked up when the contacts API will not say it.
  private heardIn = new Map<string, string>();
  private members = new Map<string, Map<string, string>>();
  private asked = new Map<string, Asked>();
  private lines = new Map<string, FeishuStatus>();
  private parts = new Parts();
  private pingMs: number;
  private staleMs: number;
  private backoffMs: number;
  private clock: Clock.Clock | undefined;
  private onHeard: () => void;
  private stopped = false;
  private scope: Scope.Closeable;
  private run: (effect: Effect.Effect<void, never>) => Promise<void>;

  constructor(options: FeishuSurfaceOptions) {
    if (options.appId === "" || options.appSecret === "") throw new Error("feishu.appId and feishu.appSecret are required");
    this.connect = options.connect;
    this.domain = options.domain;
    this.client = options.client ?? new FeishuClient(options.appId, options.appSecret, options.domain);
    this.threads = options.threads;
    this.book = options.book ?? null;
    this.pingMs = options.pingMs ?? PING_MS;
    this.staleMs = options.staleMs ?? STALE_MS;
    this.backoffMs = options.backoffMs ?? 1_000;
    this.clock = options.clock;
    this.onHeard = options.onHeard ?? (() => {});
    this.scope = Effect.runSync(Scope.make());
    const runtime = Scope.provide(FiberSet.makeRuntimePromise<never, void, never>(), this.scope);
    this.run = Effect.runSync(options.clock ? runtime.pipe(Effect.provideService(Clock.Clock, options.clock)) : runtime);
  }

  identity(): SlackIdentity | null {
    return this.me;
  }

  socket(): SocketStatus {
    return { ...this.status };
  }

  onChange(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private changed() {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {}
    }
  }

  private setStatus(connected: boolean, lastError: string | null) {
    if (this.status.connected === connected && this.status.lastError === lastError) return;
    this.status = { connected, lastError };
    this.changed();
  }

  async refreshIdentity() {
    this.me = await identityOf(this.client);
    this.changed();
  }

  botUserId(): string {
    return this.me?.botUserId ?? "";
  }

  botName(): string {
    return this.me?.botName ?? "";
  }

  workspace(): string | null {
    const team = this.me?.teamId ?? "";
    return team === "" ? null : team;
  }

  mention(user: string): string {
    return `<at id=${user}></at>`;
  }

  /// Not said: the status card links the session's page.
  sessionLink(): string | null {
    return null;
  }

  async start(handler: Handler) {
    const identity = await identityOf(this.client);
    if (identity.botUserId === "") throw new Error("this Feishu app has no bot: turn on its bot capability");
    log.info("feishu", "feishu authenticated", { connect: this.connect, bot: identity.botName, tenant: identity.team });
    this.me = identity;
    void this.run(this.connectLoop(handler)).catch(() => {});
  }

  async stop() {
    if (this.stopped) return;
    this.stopped = true;
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }

  private connectLoop(handler: Handler): Effect.Effect<void> {
    const self = this;
    return Effect.gen(function* () {
      let backoff = self.backoffMs;
      for (;;) {
        const ran = yield* Effect.result(
          Effect.gen(function* () {
            const { url } = yield* Effect.tryPromise({ try: () => self.client.endpoint(), catch: (e) => e as Error });
            yield* self.runSocket(url, handler);
          }),
        );
        if (Result.isSuccess(ran)) backoff = self.backoffMs;
        else {
          const said = ran.failure.message;
          self.setStatus(false, said);
          log.warn("feishu", "feishu connection failed", { connect: self.connect, error: said, retryInMs: backoff });
          yield* Effect.sleep(backoff);
          backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
        }
      }
    });
  }

  /// One long connection: ends when the socket closes, and fails when it went quiet for `staleMs` (a connection cut
  /// on the way can look open forever). Pinged every `pingMs`, with Feishu's own ping frame and the socket's. Each event is
  /// acknowledged once its handler kept it; one that failed is not, and Feishu sends it again.
  runSocket(url: string, handler: Handler): Effect.Effect<void, Error> {
    const self = this;
    const service = Number(new URL(url).searchParams.get("service_id") ?? "0");
    const socket = Effect.gen(function* () {
      const clock = yield* Clock.Clock;
      const opened = yield* Deferred.make<void>();
      let ws: WebSocket | undefined;
      let heard = clock.currentTimeMillisUnsafe();
      const ping = () => {
        try {
          ws?.send(encode({ seqId: 0n, logId: 0n, service, method: CONTROL, headers: [["type", "ping"]] }));
          ws?.ping();
        } catch {}
      };
      const open = Effect.callback<void, Error>((resume) => {
        const socket = new WebSocket(url);
        ws = socket;
        let finished = false;
        const cut = () => {
          finished = true;
          socket.removeAllListeners();
          socket.on("error", () => {});
          if (socket.readyState !== WebSocket.CLOSED) socket.terminate();
        };
        const end = (error: Error | null) => {
          if (finished) return;
          cut();
          if (error !== null) resume(Effect.fail(error));
          else {
            self.setStatus(false, self.status.lastError);
            resume(Effect.void);
          }
        };
        // Feishu says no in the handshake's answer (an app without the long connection, too many connections).
        socket.on("unexpected-response", (_request, response) => {
          end(new Error(`feishu refused the connection: HTTP ${response.statusCode} ${response.headers["handshake-msg"] ?? ""}`.trim()));
        });
        socket.on("open", () => {
          heard = clock.currentTimeMillisUnsafe();
          self.setStatus(true, null);
          Deferred.doneUnsafe(opened, Effect.void);
          ping();
          void self.catchUp(handler).catch((error) => log.warn("feishu", "what was said while away not read", { connect: self.connect, error: (error as Error).message }));
        });
        const alive = () => {
          heard = clock.currentTimeMillisUnsafe();
          self.onHeard();
        };
        socket.on("pong", alive);
        socket.on("ping", alive);
        socket.on("message", (data) => {
          alive();
          let frame: Frame;
          try {
            frame = decode(new Uint8Array(data as Buffer));
          } catch (error) {
            log.warn("feishu", "feishu frame unreadable", { error: (error as Error).message });
            return;
          }
          if (frame.method !== DATA) return;
          const kind = header(frame, "type");
          if (kind !== "event" && kind !== "card") return;
          const now = clock.currentTimeMillisUnsafe();
          self.parts.drop(now - 5 * 60_000);
          const whole = self.parts.add(frame, now);
          if (whole === null) return;
          void (async () => {
            let answer: Json;
            try {
              answer = await self.take(JSON.parse(new TextDecoder().decode(whole)), handler);
            } catch (error) {
              // Not acknowledged: Feishu sends it again, and the store dedupes.
              log.error("feishu", "failed to accept feishu event", { connect: self.connect, error: (error as Error).message });
              return;
            }
            const payload: Json = { code: 200 };
            if (answer !== null && answer !== undefined) payload.data = Buffer.from(JSON.stringify(answer)).toString("base64");
            if (socket.readyState === WebSocket.OPEN) {
              socket.send(encode({ ...frame, headers: [...frame.headers, ["biz_rt", "0"]], payload: new TextEncoder().encode(JSON.stringify(payload)) }));
            }
          })();
        });
        socket.on("close", () => end(null));
        socket.on("error", (error) => end(error));
        return Effect.sync(() => {
          if (!finished) cut();
        });
      });
      const watch = Deferred.await(opened).pipe(
        Effect.timeoutOrElse({
          duration: self.staleMs,
          orElse: () => Effect.fail(new Error(`feishu connection did not open within ${self.staleMs / 1000}s`)),
        }),
        Effect.andThen(
          Effect.forever(
            Effect.sleep(self.pingMs).pipe(
              Effect.andThen(
                Effect.suspend(() => {
                  const quiet = clock.currentTimeMillisUnsafe() - heard;
                  if (quiet >= self.staleMs) return Effect.fail(new Error(`feishu connection said nothing for ${quiet / 1000}s`));
                  ping();
                  return Effect.void;
                }),
              ),
            ),
          ),
        ),
      );
      return yield* Effect.raceFirst(open, watch);
    });
    return this.clock ? socket.pipe(Effect.provideService(Clock.Clock, this.clock)) : socket;
  }

  /// One event, kept: a message goes to the hub; a card's answer too, and Feishu is answered with the card as it is now.
  async take(envelope: Json, handler: Handler): Promise<Json> {
    const type = text(envelope?.header?.event_type);
    const tenant = text(envelope?.header?.tenant_key);
    if (tenant !== "" && this.me !== null && this.me.teamId === "") this.me = { ...this.me, teamId: tenant };
    if (type === "im.message.receive_v1") {
      const m = messageOf(envelope.event, this.botUserId());
      if (m !== null) await this.heard(m, handler);
      return null;
    }
    if (type === "card.action.trigger") return this.answered(envelope.event, text(envelope?.header?.event_id), handler);
    return null;
  }

  private async chatInfo(chat: string): Promise<{ name: string | null; topics: boolean; p2p: boolean }> {
    const known = this.chats.get(chat);
    if (known) return known;
    let info = { name: null as string | null, topics: false, p2p: false };
    try {
      const d = (await this.client.api("GET", `/open-apis/im/v1/chats/${encodeURIComponent(chat)}`))?.data ?? {};
      const p2p = text(d.chat_mode) === "p2p";
      info = { name: p2p ? null : text(d.name) || null, topics: text(d.group_message_type) === "thread" || text(d.chat_mode) === "topic", p2p };
    } catch (error) {
      log.warn("feishu", "chat not read", { chat, error: (error as Error).message });
      return info;
    }
    this.chats.set(chat, info);
    return info;
  }

  /// What was said in the chats with a conversation while the station was not connected (Feishu keeps no events for a
  /// connection that is not there), heard as if it had come: the store keeps each message once.
  async catchUp(handler: Handler) {
    for (const [chat, since] of this.threads.conversations(this.connect)) {
      if (since === 0) continue;
      let token = "";
      for (let page = 0; page < 10; page++) {
        const d = (await this.client.api("GET", "/open-apis/im/v1/messages", null, { container_id_type: "chat", container_id: chat, start_time: String(Math.floor(since / 1000)), sort_type: "ByCreateTimeAsc", page_size: "50", ...(token ? { page_token: token } : {}) }))?.data ?? {};
        for (const item of Array.isArray(d.items) ? d.items : []) {
          const m = messageOf(listedAsEvent(item), this.botUserId());
          if (m !== null && m.at > since) await this.heard(m, handler);
        }
        token = text(d.page_token);
        if (d.has_more !== true || token === "") break;
      }
    }
  }

  /// Which thread a message is in (docs/feishu.md「会话怎么分」): a topic group's topic is its own; anything else said in
  /// the chat is the chat's conversation now, begun by the first message that @s the bot (or a new one asked for).
  private async heard(m: FeishuMessage, handler: Handler) {
    this.heardIn.set(m.user, m.chat);
    if (m.at > 0) this.threads.heard(this.connect, m.chat, m.at);
    let threadTs: string;
    const topics = m.topic !== null && !m.p2p && (await this.chatInfo(m.chat)).topics;
    if (topics) {
      threadTs = m.topic!;
      this.threads.heardTopic(this.connect, m.topic!, m.root ?? m.id);
    } else {
      const current = this.threads.current(this.connect, m.chat);
      if (current === null || m.fresh) {
        if (m.addressed) this.threads.begin(this.connect, m.chat, m.id);
        threadTs = m.addressed || current === null ? m.id : current;
      } else threadTs = current;
    }
    const event: ChatEvent = {
      type: "message",
      message: { channel: m.chat, threadTs, ts: m.id, user: m.user, text: m.text, addressed: m.addressed, ...(m.files.length > 0 ? { files: m.files } : {}) },
    };
    await handler(event);
  }

  /// A card's button pressed or its field sent: said in its thread as the person's message, and the card shows the answer.
  private async answered(event: Json, eventId: string, handler: Handler): Promise<Json> {
    const a = cardAnswerOf(event, eventId);
    const value = (a?.value ?? null) as Answer | null;
    if (a === null || value?.sf !== "answer" || typeof value.t !== "string") return null;
    const lang = stationLang();
    const said = typeof value.l === "string" ? value.l : text(a.form?.answer).trim();
    if (said === "") return { toast: { type: "warning", content: tr(lang, "station.feishu.answerEmpty") } };
    const asked = this.asked.get(a.message);
    if (asked?.answered) return { toast: { type: "info", content: tr(lang, "station.feishu.answeredBefore") } };
    await handler({ type: "message", message: { channel: a.chat, threadTs: value.t, ts: `card-${a.event}`, user: a.user, text: said, addressed: true } });
    if (asked) asked.answered = true;
    const who = this.names.get(a.user)?.name || this.knownPerson(a.user)?.name || "";
    const answer: Json = { toast: { type: "success", content: tr(lang, "station.feishu.sent") } };
    if (asked) answer.card = { type: "raw", data: answeredCard(asked.text, who, said, lang) };
    return answer;
  }

  /// Posts a message where the thread is: a topic's reply in it, else in the chat. Its message id.
  private async send(thread: ThreadRef, msgType: string, content: string): Promise<string> {
    const root = thread.threadTs.startsWith("omt_") ? this.threads.topicRoot(this.connect, thread.threadTs) : null;
    const answer =
      root !== null
        ? await this.client.api("POST", `/open-apis/im/v1/messages/${encodeURIComponent(root)}/reply`, { msg_type: msgType, content, reply_in_thread: true })
        : await this.client.api("POST", "/open-apis/im/v1/messages", { receive_id: thread.channel, msg_type: msgType, content }, { receive_id_type: "chat_id" });
    const id = answer?.data?.message_id;
    if (typeof id !== "string" || id === "") throw new Error("feishu gave no message_id");
    return id;
  }

  /// The agent's words as cards (a question's buttons or field with them), then each file as a message of its own. The
  /// first message's id stands for the whole.
  async post(thread: ThreadRef, message: string, files: Attachment[], card?: Json | null): Promise<string> {
    let first: string | null = null;
    const lang = stationLang();
    const question = card && (card.type === "options" || card.type === "text") ? card : null;
    const cards = question ? [questionCard(message, question, thread.threadTs, lang)] : textCards(message);
    for (const c of cards) {
      const id = await this.send(thread, "interactive", inline(c));
      first ??= id;
      if (question) {
        this.asked.set(id, { text: message, card: question, thread: thread.threadTs, answered: false });
        // The oldest go once there are many: an answer to one of those shows as said, without its card changed.
        if (this.asked.size > 500) this.asked.delete(this.asked.keys().next().value!);
      }
    }
    for (const file of files) {
      const bytes = await readFile(file.path);
      let id: string;
      if (IMAGE.test(file.name) && bytes.length <= MAX_IMAGE) {
        const up = await this.client.api("POST", "/open-apis/im/v1/images", { image_type: "message" }, undefined, [{ field: "image", bytes, name: file.name, mime: "application/octet-stream" }]);
        id = await this.send(thread, "image", JSON.stringify({ image_key: up?.data?.image_key }));
      } else {
        const up = await this.client.api("POST", "/open-apis/im/v1/files", { file_type: fileType(file.name), file_name: file.name }, undefined, [{ field: "file", bytes, name: file.name, mime: "application/octet-stream" }]);
        id = await this.send(thread, "file", JSON.stringify({ file_key: up?.data?.file_key }));
      }
      first ??= id;
    }
    if (first === null) throw new Error("nothing to post");
    return first;
  }

  /// The groups the bot is in (`GET /im/v1/chats`), each a topic group or not as Feishu says of it.
  async places(): Promise<Place[]> {
    const found: { id: string; name: string }[] = [];
    let token = "";
    for (let page = 0; page < 10; page++) {
      const d = (await this.client.api("GET", "/open-apis/im/v1/chats", null, { page_size: "100", ...(token ? { page_token: token } : {}) }))?.data ?? {};
      for (const c of Array.isArray(d.items) ? d.items : []) {
        const id = text(c?.chat_id);
        if (id !== "") found.push({ id, name: text(c?.name) || id });
      }
      token = text(d.page_token);
      if (d.has_more !== true || token === "") break;
    }
    const out: Place[] = [];
    for (const c of found) {
      const info = await this.chatInfo(c.id);
      if (!info.p2p) out.push({ id: c.id, name: info.name ?? c.name, kind: info.topics ? "topics" : "group" });
    }
    return out;
  }

  /// The chat in Feishu's (or Lark's) app; a topic opens with its chat.
  permalink(thread: ThreadRef): string | null {
    const app = this.domain === "lark" ? "https://applink.larksuite.com" : "https://applink.feishu.cn";
    return `${app}/client/chat/open?openChatId=${encodeURIComponent(thread.channel)}`;
  }

  /// A new message in the chat, as the agent's words are (cards): in a topic group a topic of its own; elsewhere the
  /// chat's conversation from now on, as a new one asked for in it begins (docs/feishu.md「会话怎么分」).
  async begin(chat: string, message: string): Promise<{ thread: ThreadRef; ts: string }> {
    const { topics } = await this.chatInfo(chat);
    let first: Json = null;
    let thread: ThreadRef | null = null;
    for (const c of textCards(message)) {
      if (thread !== null) {
        await this.send(thread, "interactive", inline(c));
        continue;
      }
      first = (await this.client.api("POST", "/open-apis/im/v1/messages", { receive_id: chat, msg_type: "interactive", content: inline(c) }, { receive_id_type: "chat_id" }))?.data ?? {};
      const id = text(first.message_id);
      if (id === "") throw new Error("feishu gave no message_id");
      let topic = topics ? text(first.thread_id) : "";
      // A topic group's message is a topic, whose id Feishu may leave out of the answer: read the message back.
      if (topics && topic === "") topic = text((await this.client.api("GET", `/open-apis/im/v1/messages/${encodeURIComponent(id)}`))?.data?.items?.[0]?.thread_id);
      if (topic !== "") {
        this.threads.heardTopic(this.connect, topic, id);
        thread = { channel: chat, threadTs: topic };
      } else {
        this.threads.begin(this.connect, chat, id);
        thread = { channel: chat, threadTs: id };
      }
    }
    if (thread === null) throw new Error("nothing to post");
    return { thread, ts: text(first?.message_id) };
  }

  /// A card changed in place (its message patched: the station's cards are shared, `update_multi`), as `post` writes one.
  async edit(_thread: ThreadRef, ts: string, message: string): Promise<boolean> {
    const cards = textCards(message);
    if (cards.length !== 1) return false;
    await this.client.api("PATCH", `/open-apis/im/v1/messages/${encodeURIComponent(ts)}`, { content: inline(cards[0]) });
    return true;
  }

  async download(file: InboundFile): Promise<Uint8Array> {
    const at = file.url === null ? null : resourceOf(file.url);
    if (at === null) throw new Error("Feishu does not give its contents");
    return this.client.resource(at.message, at.key, at.type);
  }

  /// A person's name and email: from the contacts (as far as the app may read them), else their name in the chat they
  /// were heard in.
  private async lookUp(user: string): Promise<Person | null> {
    try {
      const u = (await this.client.api("GET", `/open-apis/contact/v3/users/${encodeURIComponent(user)}`, null, { user_id_type: "open_id" }))?.data?.user ?? {};
      const name = text(u.name) || text(u.en_name);
      if (name !== "") return { name, email: (text(u.enterprise_email) || text(u.email)).toLowerCase() };
    } catch {}
    const chat = this.heardIn.get(user);
    if (chat === undefined) return null;
    let names = this.members.get(chat);
    if (!names) {
      names = new Map();
      try {
        let token = "";
        for (let page = 0; page < 20; page++) {
          const d = (await this.client.api("GET", `/open-apis/im/v1/chats/${encodeURIComponent(chat)}/members`, null, { member_id_type: "open_id", page_size: "100", ...(token ? { page_token: token } : {}) }))?.data ?? {};
          for (const item of Array.isArray(d.items) ? d.items : []) if (text(item?.member_id) !== "") names.set(item.member_id, text(item.name));
          token = text(d.page_token);
          if (d.has_more !== true || token === "") break;
        }
      } catch {
        return null;
      }
      this.members.set(chat, names);
    }
    const name = names.get(user) ?? "";
    return name === "" ? null : { name, email: "" };
  }

  private async profile(user: string): Promise<Person | null> {
    const known = this.names.get(user);
    if (known) return known;
    const person = await this.lookUp(user);
    if (person) this.names.set(user, person);
    return person;
  }

  async userName(user: string): Promise<string | null> {
    const name = (await this.profile(user))?.name ?? "";
    return name === "" ? null : name;
  }

  async userEmail(user: string): Promise<string | null> {
    const email = (await this.profile(user))?.email ?? "";
    return email === "" ? null : email;
  }

  knownPerson(user: string): Person | null {
    if (!this.book) return this.names.get(user) ?? null;
    return this.book.person(`u:${this.connect}:${user}`, () => this.profile(user));
  }

  knownChannel(channel: string): string | null {
    if (!this.book) return this.chats.get(channel)?.name ?? null;
    return this.book.channel(`c:${this.connect}:${channel}`, async () => (await this.chatInfo(channel)).name);
  }

  async channelName(channel: string): Promise<string | null> {
    return (await this.chatInfo(channel)).name;
  }

  /// What a topic said before `before` (a chat's conversation begins with the message the station first heard: there is
  /// nothing before it of its own).
  history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
    return (async () => {
      if (!thread.threadTs.startsWith("omt_")) return [];
      const all: ChatMessage[] = [];
      let token = "";
      for (let page = 0; page < 20; page++) {
        const d = (await this.client.api("GET", "/open-apis/im/v1/messages", null, { container_id_type: "thread", container_id: thread.threadTs, sort_type: "ByCreateTimeAsc", page_size: "50", ...(token ? { page_token: token } : {}) }))?.data ?? {};
        for (const item of Array.isArray(d.items) ? d.items : []) {
          const id = text(item?.message_id);
          if (id === before) return all.slice(Math.max(0, all.length - limit));
          const fromBot = text(item?.sender?.sender_type) === "app";
          const event = listedAsEvent(item);
          event.sender.sender_type = "user";
          const m = messageOf(event, this.botUserId());
          if (m !== null) all.push({ ts: id, user: m.user, text: m.text, fromBot, ...(m.files.length > 0 ? { files: m.files } : {}) });
        }
        token = text(d.page_token);
        if (d.has_more !== true || token === "") break;
      }
      return all.slice(Math.max(0, all.length - limit));
    })();
  }

  /// An OpenAPI call as the bot, for feishu_api: `method` is "GET /open-apis/…"; a GET's params go in the address,
  /// anything else's as its JSON body.
  async api(method: string, params: Record<string, Json>): Promise<Json> {
    const m = /^(GET|POST|PUT|PATCH|DELETE)\s+(\/open-apis\/\S+)$/i.exec(method.trim());
    if (!m) throw new Error(`feishu_api: method is "GET /open-apis/…" (an HTTP method and a path), got ${JSON.stringify(method)}`);
    const verb = m[1]!.toUpperCase();
    const path = m[2]!;
    if (verb === "GET") {
      const query: Record<string, string> = {};
      for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined) query[k] = typeof v === "string" ? v : JSON.stringify(v);
      return this.client.api(verb, path, null, query);
    }
    const { query, ...body } = params as { query?: Record<string, string> };
    return this.client.api(verb, path, body, query);
  }

  working(thread: ThreadRef, _messageTs: string | null, status: string, page?: string | null) {
    if (this.stopped) return;
    const key = `${thread.channel}/${thread.threadTs}`;
    let line = this.lines.get(key);
    if (!line) {
      line = new FeishuStatus({ api: (method, path, body) => this.client.api(method, path, body), send: (type, content) => this.send(thread, type, content) }, this.run);
      this.lines.set(key, line);
    }
    if (status === "" && this.lines.size > 200) this.lines.delete(key);
    line.say(status, page ?? null);
  }
}
