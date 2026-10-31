// Slack as a chat surface (chat/slack.rs), on a socket kept up as every connect's is (connects/surface.ts): Socket Mode
// for what Slack tells the station (a card's buttons too), the Web API for what the station and its agents say and ask.
// One SlackSurface per connected connect.
import { readFile } from "node:fs/promises";
import type { Clock, Effect } from "effect";
import WebSocket from "ws";
import type { BotIdentity } from "../connects/connections.ts";
import { channelKey, personKey } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
import { ConnectedSurface, MEMBERS_MS } from "../connects/surface.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/store.ts";
import { type ChatEvent, type ChatMessage, type Handler, type InboundFile, type Member, type Person, type Place, type ThreadRef, splitForSlack } from "../sessions/chat.ts";
import { type Stands, answerOf, answeredBlocks, markdown, questionBlocks, standsBlock, standsText } from "./cards.ts";
import { ThreadStatus } from "./status.ts";
import { type Params, SlackClient, field } from "./web.ts";
import { wall } from "../ops/fibers.ts";

type Json = any;
/// A message the bot posted, as it posted it.
type Said = { text: string; blocks: Json[]; question?: boolean };

/// Who a bot token belongs to, as Slack reports it: its workspace's address, and its app's bot id besides.
export type SlackIdentity = BotIdentity;

const text = (v: unknown): string => (typeof v === "string" ? v : "");
/// A number as Rust's `str::parse::<f64>` reads one (a Slack ts); null where it does not.
const number = (s: string): number | null => (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s) ? Number(s) : null);
const firstString = (values: unknown[], ok: (s: string) => boolean): string | null => {
  for (const v of values) if (typeof v === "string" && ok(v)) return v;
  return null;
};

/// Who the bot is, and where: its name as people see it in that workspace (not its handle), when Slack says.
export async function identityOf(client: SlackClient, token: string): Promise<SlackIdentity> {
  const auth = await client.api("auth.test", [], token);
  const botUserId = text(auth.user_id);
  let user: Json = null;
  try {
    user = (await client.api("users.info", [["user", botUserId]], token)).user ?? null;
  } catch {}
  const profile = user?.profile ?? null;
  const shown = firstString([profile?.display_name, user?.real_name, profile?.real_name], (n) => n.trim() !== "");
  const image = firstString([profile?.image_72, profile?.image_48, profile?.image_original], (u) => u.startsWith("https://"));
  return {
    team: text(auth.team),
    teamId: text(auth.team_id),
    url: text(auth.url),
    botUserId,
    botName: shown ?? text(auth.user),
    botImage: image,
    botId: text(auth.bot_id),
  };
}

/// Checks a token pair without connecting: the bot token must authenticate, and the app-level token must be allowed to
/// open a Socket Mode connection. Its problems are said in `lang`.
export async function verifySlackTokens(client: SlackClient, appToken: string, botToken: string, lang: Lang = stationLang()): Promise<[SlackIdentity | null, string[]]> {
  const errors: string[] = [];
  let identity: SlackIdentity | null = null;
  if (!botToken.startsWith("xoxb-")) errors.push(tr(lang, "station.slackTokens.botPrefix"));
  else {
    try {
      identity = await identityOf(client, botToken);
    } catch (e) {
      errors.push(tr(lang, "station.slackTokens.botInvalid", { error: (e as Error).message }));
    }
  }
  if (!appToken.startsWith("xapp-")) errors.push(tr(lang, "station.slackTokens.appPrefix"));
  else {
    try {
      await client.api("apps.connections.open", [], appToken);
    } catch (e) {
      errors.push(tr(lang, "station.slackTokens.appNoSocket", { error: (e as Error).message }));
    }
  }
  return [identity, errors];
}

/// A rich_text element as Slack's own text writes it (links <url|label>, mentions <@U…>), so it reads like the rest.
function richText(el: Json): string {
  const kind = text(el?.type);
  if (Array.isArray(el?.elements)) {
    const inner = el.elements.map(richText);
    if (kind === "rich_text_list") return inner.map((s: string) => `• ${s}`).join("\n");
    return inner.join(kind === "rich_text" ? "\n" : "");
  }
  switch (kind) {
    case "text":
      return text(el.text);
    case "link":
      return el.text ? `<${text(el.url)}|${text(el.text)}>` : `<${text(el.url)}>`;
    case "user":
      return `<@${text(el.user_id)}>`;
    case "usergroup":
      return `<!subteam^${text(el.usergroup_id)}>`;
    case "channel":
      return `<#${text(el.channel_id)}>`;
    case "broadcast":
      return `<!${text(el.range)}>`;
    case "emoji":
      return `:${text(el.name)}:`;
    case "date":
      return text(el.fallback);
    default:
      return text(el?.text);
  }
}

/// A table cell's content on one line, its pipes kept from closing the cell (those inside <url|label> stay as Slack's).
function cellText(cell: Json): string {
  const kind = text(cell?.type);
  const raw = kind === "rich_text" ? richText(cell) : kind === "raw_number" ? String(cell?.number ?? cell?.text ?? "") : text(cell?.text);
  return raw.replace(/\s*\n\s*/g, " ").replace(/(<[^<>]*>)|\|/g, (m, slack) => slack ?? "\\|").trim();
}

/// A table block as a Markdown table, its first row the header (as Slack shows it).
function tableText(block: Json): string {
  const rows: string[][] = (Array.isArray(block?.rows) ? block.rows : []).map((row: Json) => (Array.isArray(row) ? row.map(cellText) : []));
  if (rows.length === 0) return "";
  const width = Math.max(...rows.map((r) => r.length));
  const line = (r: string[]) => `| ${Array.from({ length: width }, (_, i) => r[i] ?? "").join(" | ")} |`;
  return [line(rows[0]), line(Array(width).fill("---")), ...rows.slice(1).map(line)].join("\n");
}

/// What a message says: its text, and the tables in its blocks and attachments, which Slack leaves out of the text
/// (a table drawn in Slack's composer arrives as a table block in an attachment).
export function messageText(m: Json): string {
  const blocks = [...(Array.isArray(m?.blocks) ? m.blocks : []), ...(Array.isArray(m?.attachments) ? m.attachments : []).flatMap((a: Json) => (Array.isArray(a?.blocks) ? a.blocks : []))];
  const tables = blocks.filter((b: Json) => b?.type === "table").map(tableText).filter((t: string) => t !== "");
  return [text(m?.text), ...tables].filter((t) => t !== "").join("\n\n");
}

/// The files shared with a message. Ones Slack keeps back (over a free workspace's limit, deleted) or that live
/// elsewhere (external: Google Drive and the like) have no url.
export function messageFiles(m: Json): InboundFile[] {
  return (Array.isArray(m?.files) ? m.files : [])
    .filter((f: Json) => text(f?.id) !== "")
    .map((f: Json) => {
      const held = !["tombstone", "hidden_by_limit", "external"].includes(text(f?.mode));
      const url = text(f?.url_private_download) || text(f?.url_private);
      return { id: text(f.id), name: text(f?.name) || text(f?.title) || text(f.id), size: typeof f?.size === "number" ? f.size : 0, url: held && url !== "" ? url : null };
    });
}

/// A Slack event as the station takes it: someone's message (a person, or another app's bot: agents work together in
/// threads), an edit, or nothing it keeps (its own messages, deletes). `botId`: this app's bot id (B…).
export function toEvent(event: Json, botUserId: string, botId: string): ChatEvent | null {
  // A message this bot posted itself: the station records those as it posts them.
  const own = (e: Json) => {
    const is = (key: string, mine: string) => mine !== "" && e?.[key] === mine;
    return is("user", botUserId) || is("bot_id", botId);
  };
  const kind = text(event?.type);
  const subtype = typeof event?.subtype === "string" ? event.subtype : null;
  if (kind === "agent_session_stopped") {
    const channel = text(event.channel);
    const threadTs = text(event.thread_ts);
    const ts = text(event.event_ts);
    if (!channel || !threadTs || !/^\d+(?:\.\d+)?$/.test(ts) || !Number.isFinite(Number(ts))) return null;
    return { type: "stop", channel, threadTs, ts };
  }
  if (kind === "message" && subtype === "message_changed") {
    const changed = event.message ?? null;
    const ts = text(changed?.ts);
    if (ts === "" || own(changed)) return null;
    // A message outside any thread is the root of its own.
    const threadTs = typeof changed?.thread_ts === "string" ? changed.thread_ts : ts;
    return { type: "changed", channel: text(event.channel), threadTs, ts, text: messageText(changed) };
  }
  // The station has no retraction: a deleted message stays as it was said.
  if (kind === "message" && subtype === "message_deleted") return null;
  if (kind !== "app_mention" && kind !== "message") return null;
  // Message subtypes that are someone talking: a person, or another app's bot.
  if (![null, "file_share", "thread_broadcast", "bot_message"].includes(subtype) || own(event)) return null;
  // Its bot user when Slack gives one, else its bot id.
  const by = event.user !== undefined && event.user !== null ? event.user : event.bot_id;
  const user = text(by);
  if (user === "") return null;
  const body = messageText(event);
  const ts = text(event.ts);
  const files = messageFiles(event);
  return {
    type: "message",
    message: {
      channel: text(event.channel),
      threadTs: typeof event.thread_ts === "string" ? event.thread_ts : ts,
      ts,
      user,
      text: body,
      addressed: kind === "app_mention" || event.channel_type === "im" || body.includes(`<@${botUserId}>`),
      ...(files.length > 0 ? { files } : {}),
    },
  };
}

/// The name a users.info answer gives a person, their email and their profile picture (72px, as Slack's own lists
/// draw it at twice their size).
export function personOf(answer: Json): Person {
  const u = answer?.user ?? null;
  const p = u?.profile ?? null;
  const name = firstString([p?.display_name, u?.real_name, u?.name], (n) => n !== "") ?? "";
  return { name, email: text(p?.email).toLowerCase(), picture: text(p?.image_72) };
}

async function channelNameOf(client: SlackClient, channel: string, token: string): Promise<string | null> {
  let r: Json;
  try {
    r = await client.api("conversations.info", [["channel", channel]], token);
  } catch {
    return null;
  }
  const c = r?.channel ?? null;
  if (c?.is_im === true) return null;
  return typeof c?.name === "string" && c.name !== "" ? c.name : null;
}

export type SlackSurfaceOptions = {
  appToken: string;
  botToken: string;
  client?: SlackClient;
  /// The connect it is (for the log).
  connect?: string;
  /// Keeps names across restarts and lets the admin API ask without waiting (knownPerson, knownChannel).
  book?: NameBook | null;
  /// How often the socket is pinged, and how long it may say nothing before it is taken for dead (connects/surface.ts).
  pingMs?: number;
  staleMs?: number;
  backoffMs?: number;
  clock?: Clock.Clock;
  onHeard?: () => void;
  /// A new turn began showing its status, an opportunity to retry an app setup that previously failed.
  onWorking?: () => void;
};
/// The most of a question's words its card carries (Slack takes 12,000 characters of Markdown in a message, and long
/// options are listed with them).
const QUESTION_CHARS = 8_000;
/// How long the workspace's people are kept for (peopleIn).
export const PEOPLE_MS = 10 * 60_000;

export class SlackSurface extends ConnectedSurface {
  protected readonly kind = "slack";
  readonly appToken: string;
  readonly botToken: string;
  readonly client: SlackClient;
  private channels = new Map<string, string | null>();
  /// The questions answered (their messages' ts): a second press before the card changed is not said again.
  private answered = new Set<string>();
  /// Each thread's newest message as the station saw it (by `channel/threadTs`), the bot's with what it posted (to be
  /// changed: `standsAt`), anyone else's with null; and where the thread stands said at its end: on the bot's message
  /// (`mine`, what it said before) or in a message of its own (null). Kept while connected: a restart forgets them.
  private ends = new Map<string, { ts: string; mine: Said | null }>();
  private stands = new Map<string, { ts: string; mine: Said | null; block: Json }>();
  /// One change at a time in each thread, in order.
  private standing = new Map<string, Promise<void>>();
  private onWorking: () => void;

  constructor(options: SlackSurfaceOptions) {
    if (!options.appToken.startsWith("xapp-")) throw new Error("slack.appToken must be an app-level token (xapp-…)");
    if (!options.botToken.startsWith("xoxb-")) throw new Error("slack.botToken must be a bot token (xoxb-…)");
    // Like Slack's Python SDK (slack_sdk.socket_mode.builtin): a ping every 5 s, dead after 20 s of nothing (4 pings).
    super({ ...options, pingMs: options.pingMs ?? 5_000, staleMs: options.staleMs ?? 20_000 });
    this.appToken = options.appToken;
    this.botToken = options.botToken;
    this.client = options.client ?? new SlackClient();
    this.onWorking = options.onWorking ?? (() => {});
  }

  protected identify() {
    return identityOf(this.client, this.botToken);
  }

  protected async address() {
    const open = await this.client.api("apps.connections.open", [], this.appToken);
    if (typeof open?.url !== "string") throw new Error("slack gave no socket url");
    return open.url as string;
  }

  /// One Socket Mode connection (connects/surface.ts keeps it up). Each event is acknowledged once its handler kept it;
  /// one that failed is not, and Slack sends it again.
  runSocket(url: string, handler: Handler): Effect.Effect<void, Error> {
    const bot = this.botUserId();
    const botId = this.me?.botId ?? "";
    return this.socketTo(url, {
      message: (socket, data, { binary, end }) => {
        if (binary) return;
        let envelope: Json;
        try {
          envelope = JSON.parse(data.toString());
        } catch {
          return;
        }
        if (envelope?.type === "disconnect") {
          log.info("slack", "slack asked to reconnect", { reason: JSON.stringify(envelope.reason ?? null) });
          try {
            socket.close();
          } catch {}
          return end(null);
        }
        // A card's button pressed: acknowledged at once (Slack waits 3 s), then said as the person's answer.
        if (envelope?.type === "interactive") {
          if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ envelope_id: envelope.envelope_id ?? null }));
          if (envelope.payload?.type === "block_actions") {
            void this.answer(envelope.payload, handler).catch((error) => log.error("slack", "failed to take a card's answer", { error: (error as Error).message }));
          }
          return;
        }
        if (envelope?.type !== "events_api") return;
        const event = toEvent(envelope.payload?.event ?? null, bot, botId);
        if (event?.type === "stop") event.localAt = this.client.localTimeUpper(event.ts);
        const envelopeId = envelope.envelope_id ?? null;
        void (async () => {
          try {
            if (event?.type === "message") this.heard(event.message.channel, event.message.threadTs, event.message.ts);
            if (event !== null) await handler(event);
          } catch (error) {
            // Not acknowledged: Slack redelivers, and the store dedupes.
            log.error("slack", "failed to accept slack event", { error: (error as Error).message });
            return;
          }
          if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ envelope_id: envelopeId }));
        })();
      },
    });
  }

  /// Posted as written, in a markdown block (Slack draws the agent's Markdown as still.fail does, tables too); a long
  /// message goes out in parts, the first part's ts standing for the whole. A question (`card`: options or a field) is
  /// one message with its buttons (cards.ts). Files are uploaded before anything is posted (an app without
  /// `files:write` fails there, with nothing said), then shared into the thread below the text.
  async post(thread: ThreadRef, message: string, files: Attachment[], card?: Json | null): Promise<string> {
    const uploaded: [string, string][] = [];
    for (const file of files) uploaded.push(await this.upload(file));
    let first: string | null = null;
    const send = async (said: string, blocks: Json[], question = false) => {
      const posted = await this.client.api(
        "chat.postMessage",
        [
          ["channel", thread.channel],
          ["thread_ts", thread.threadTs],
          ["text", said],
          ["blocks", JSON.stringify(blocks)],
          ["unfurl_links", "false"],
        ],
        this.botToken,
      );
      if (first === null && typeof posted?.ts === "string") first = posted.ts;
      if (typeof posted?.ts === "string") this.heard(thread.channel, thread.threadTs, posted.ts, { text: said, blocks, ...(question ? { question } : {}) });
    };
    const question = card && (card.type === "options" || card.type === "text") ? card : null;
    let parts = splitForSlack(message, 3500).filter((t) => t !== "");
    // A question is one message with its buttons; what is too long for it goes before it, in parts.
    let asking = "";
    if (question) {
      if (Array.from(message).length <= QUESTION_CHARS) [asking, parts] = [message, []];
      else asking = parts.pop() ?? "";
    }
    for (const part of parts) await send(part, [markdown(part)]);
    if (question) await send(asking, questionBlocks(asking, question, stationLang()), true);
    if (uploaded.length > 0) {
      const list = JSON.stringify(uploaded.map(([id, title]) => ({ id, title })));
      const shared = await this.client.api(
        "files.completeUploadExternal",
        [
          ["files", list],
          ["channel_id", thread.channel],
          ["thread_ts", thread.threadTs],
        ],
        this.botToken,
      );
      // (the files are its newest message, nothing the bot can add words to)
      this.heard(thread.channel, thread.threadTs, "");
      if (first === null) {
        first = await this.sharedTs(shared, uploaded[0]![0], thread.channel);
        if (first === null) {
          log.warn("slack", "slack: shared files without text, their message's ts did not show up");
          first = (wall.now() / 1000).toFixed(6);
        }
      }
    }
    if (first === null) throw new Error("nothing to post");
    return first;
  }

  /// A card's send button pressed: said in its thread as the person's message, and the card changed to say who
  /// answered what. Nothing chosen or written, or answered before: only they are told, and nothing is said.
  private async answer(payload: Json, handler: Handler) {
    const answer = answerOf(payload);
    if (answer === null) return;
    const channel = text(payload?.channel?.id) || text(payload?.container?.channel_id);
    const asked = text(payload?.message?.ts) || text(payload?.container?.message_ts);
    const threadTs = text(payload?.message?.thread_ts) || text(payload?.container?.thread_ts) || asked;
    const user = text(payload?.user?.id);
    if (channel === "" || asked === "" || user === "") return;
    const lang = stationLang();
    const tell = (key: string) =>
      this.client.api(
        "chat.postEphemeral",
        [
          ["channel", channel],
          ["user", user],
          ["thread_ts", threadTs],
          ["text", tr(lang, key)],
        ],
        this.botToken,
      );
    if (answer.said === "") return void (await tell(answer.field ? "station.feishu.answerEmpty" : "station.slack.chooseFirst"));
    if (this.answered.has(asked)) return void (await tell("station.feishu.answeredBefore"));
    this.answered.add(asked);
    // The oldest go once there are many: their cards have changed long since.
    if (this.answered.size > 500) this.answered.delete(this.answered.values().next().value!);
    const action = (payload.actions as Json[]).find((a) => text(a?.action_ts) !== "");
    const ts = text(action?.action_ts) || (wall.now() / 1000).toFixed(6);
    this.heard(channel, threadTs, ts);
    try {
      await handler({ type: "message", message: { channel, threadTs, ts, user, text: answer.said, addressed: true } });
    } catch (error) {
      this.answered.delete(asked);
      throw error;
    }
    const asking = text(payload?.message?.text);
    const who = (await this.userName(user)) ?? "";
    const answered = answeredBlocks(asking, who, answer.said, lang);
    // (its buttons gone for good: never put back with where the thread stands)
    const key = `${channel}/${threadTs}`;
    if (this.stands.get(key)?.ts === asked) this.stands.delete(key);
    const end = this.ends.get(key);
    if (end?.ts === asked && end.mine !== null) end.mine = { text: asking, blocks: answered };
    await this.client.api(
      "chat.update",
      [
        ["channel", channel],
        ["ts", asked],
        ["text", asking],
        ["blocks", JSON.stringify(answered)],
      ],
      this.botToken,
    );
  }

  /// The channels the bot is in, public and private (users.conversations), at most a couple of thousand.
  async places(): Promise<Place[]> {
    const out: Place[] = [];
    let cursor = "";
    for (let page = 0; page < 10; page++) {
      const params: Params = [
        ["types", "public_channel,private_channel"],
        ["exclude_archived", "true"],
        ["limit", "200"],
      ];
      if (cursor !== "") params.push(["cursor", cursor]);
      const d = await this.client.api("users.conversations", params, this.botToken);
      for (const c of Array.isArray(d?.channels) ? d.channels : []) {
        const id = text(c?.id);
        if (id === "") continue;
        out.push({ id, name: text(c?.name) || id, kind: "channel", ...(c?.is_private === true ? { private: true } : {}) });
      }
      cursor = text(d?.response_metadata?.next_cursor);
      if (cursor === "") break;
    }
    return out;
  }

  /// The people in a channel (conversations.members), named as users.list says (bots, deactivated accounts and
  /// Slackbot left out): their display name, their full name beside it where it differs. Who is in a channel is kept
  /// for MEMBERS_MS, the workspace's people for PEOPLE_MS (users.list is all of it, page by page, and Slack lets a bot
  /// ask it some 20 times a minute); someone in the channel the workspace's people did not have reads those again, once
  /// in MEMBERS_MS at most.
  async peopleIn(channel: string): Promise<Member[]> {
    const ids = await this.kept(`members:${channel}`, MEMBERS_MS, () => this.membersOf(channel));
    let all = await this.kept("people", PEOPLE_MS, () => this.everyone());
    if (ids.some((id) => !all.seen.has(id)) && this.forget("people", MEMBERS_MS)) all = await this.kept("people", PEOPLE_MS, () => this.everyone());
    return ids.flatMap((id) => all.people.get(id) ?? []);
  }

  /// Who is in a channel (conversations.members), at most a couple of thousand.
  private async membersOf(channel: string): Promise<string[]> {
    const ids: string[] = [];
    let cursor = "";
    for (let page = 0; page < 10; page++) {
      const params: Params = [
        ["channel", channel],
        ["limit", "200"],
      ];
      if (cursor !== "") params.push(["cursor", cursor]);
      const d = await this.client.api("conversations.members", params, this.botToken);
      for (const id of Array.isArray(d?.members) ? d.members : []) if (typeof id === "string" && !ids.includes(id)) ids.push(id);
      cursor = text(d?.response_metadata?.next_cursor);
      if (cursor === "") break;
    }
    return ids;
  }

  /// The workspace's people (users.list), at most ten thousand: every account it listed (`seen`), and those of them a
  /// note can mention by id.
  private async everyone(): Promise<{ seen: Set<string>; people: Map<string, Member> }> {
    const seen = new Set<string>();
    const people = new Map<string, Member>();
    let cursor = "";
    for (let page = 0; page < 50; page++) {
      const params: Params = [["limit", "200"]];
      if (cursor !== "") params.push(["cursor", cursor]);
      const d = await this.client.api("users.list", params, this.botToken);
      for (const u of Array.isArray(d?.members) ? d.members : []) {
        const id = text(u?.id);
        if (id === "") continue;
        seen.add(id);
        if (u?.is_bot === true || u?.deleted === true || id === "USLACKBOT") continue;
        const full = text(u?.profile?.real_name) || text(u?.real_name);
        const { name: shown, picture } = personOf({ user: u });
        const name = shown || full;
        if (name === "") continue;
        // (their full name beside it only where it says more than the name: not the same but for case or spaces)
        const same = (a: string, b: string) => a.replace(/\s+/g, "").toLowerCase() === b.replace(/\s+/g, "").toLowerCase();
        people.set(id, { id, name, ...(full !== "" && !same(full, name) ? { aka: full } : {}), ...(picture ? { picture } : {}) });
      }
      cursor = text(d?.response_metadata?.next_cursor);
      if (cursor === "") break;
    }
    return { seen, people };
  }

  /// The thread in Slack: its workspace's address, the channel, its root's ts without the dot.
  permalink(thread: ThreadRef): string | null {
    const url = this.me?.url ?? "";
    return url === "" ? null : `${url.replace(/\/+$/, "")}/archives/${thread.channel}/p${thread.threadTs.replace(".", "")}`;
  }

  /// A message's link in this workspace (https://acme.slack.com/archives/C1/p1700000000000100, a reply's with
  /// ?thread_ts=): the thread it is in.
  threadOf(link: string): ThreadRef | null {
    let url: URL;
    let home: URL;
    try {
      url = new URL(link.trim());
      home = new URL(this.me?.url ?? "");
    } catch {
      return null;
    }
    if (url.host !== home.host) return null;
    const found = /^\/archives\/([A-Z0-9]+)\/p(\d{10})(\d{6})\/?$/.exec(url.pathname);
    if (found === null) return null;
    const replyTo = url.searchParams.get("thread_ts");
    return { channel: found[1]!, threadTs: replyTo !== null && /^\d{10}\.\d{6}$/.test(replyTo) ? replyTo : `${found[2]}.${found[3]}` };
  }

  /// A new message in the channel, its thread's root: what is too long for one message goes on in the thread.
  async begin(channel: string, message: string): Promise<{ thread: ThreadRef; ts: string }> {
    const parts = splitForSlack(message, 3500).filter((t) => t !== "");
    let root = "";
    for (const part of parts) {
      const params: Params = [
        ["channel", channel],
        ["text", part],
        ["blocks", JSON.stringify([markdown(part)])],
        ["unfurl_links", "false"],
      ];
      if (root !== "") params.push(["thread_ts", root]);
      const posted = await this.client.api("chat.postMessage", params, this.botToken);
      if (root === "") root = text(posted?.ts);
      if (root === "") throw new Error("slack chat.postMessage gave no ts");
      this.heard(channel, root, text(posted?.ts) || root, { text: part, blocks: [markdown(part)] });
    }
    if (root === "") throw new Error("nothing to post");
    return { thread: { channel, threadTs: root }, ts: root };
  }

  /// A message changed in place (chat.update), as `post` writes one; where the thread stands, said under it, stays.
  async edit(thread: ThreadRef, ts: string, message: string): Promise<boolean> {
    if (splitForSlack(message, 3500).length > 1) return false;
    const key = `${thread.channel}/${thread.threadTs}`;
    const said: Said = { text: message, blocks: [markdown(message)] };
    const stands = this.stands.get(key);
    const under = stands?.ts === ts && stands.mine !== null ? stands.block : null;
    await this.client.api(
      "chat.update",
      [
        ["channel", thread.channel],
        ["ts", ts],
        ["text", message],
        ["blocks", JSON.stringify(under !== null ? [...said.blocks, under] : said.blocks)],
      ],
      this.botToken,
    );
    if (stands?.ts === ts && stands.mine !== null) stands.mine = said;
    const end = this.ends.get(key);
    if (end?.ts === ts && end.mine !== null) end.mine = said;
    return true;
  }

  /// A thread's newest message, as they came (`mine`: one the bot posted, as it posted it).
  private heard(channel: string, threadTs: string, ts: string, mine: Said | null = null) {
    const key = `${channel}/${threadTs}`;
    // (the oldest go once there are many: threads long quiet)
    if (!this.ends.has(key) && this.ends.size > 2000) this.ends.delete(this.ends.keys().next().value!);
    this.ends.set(key, { ts, mine });
  }

  /// Where the thread stands as its agent's turn ended (cards.ts standsBlock), said under its newest message, the line
  /// still.fail's chat shows at its end: added to the bot's own message when that is the newest, without a new message
  /// (nobody following the thread is told again), else in a small message of its own. Null: nothing to say (it works
  /// again, or ended waiting). Whatever was said before goes first: one line at most, at the thread's end. Best
  /// effort, never waited on.
  standsAt(thread: ThreadRef, stands: Stands | null) {
    if (this.stopped) return;
    const key = `${thread.channel}/${thread.threadTs}`;
    // (nothing said, nor on its way)
    if (stands === null && !this.stands.has(key) && !this.standing.has(key)) return;
    const next = (this.standing.get(key) ?? Promise.resolve()).then(() => this.sayStands(thread, key, stands)).catch((error) =>
      log.warn("slack", "could not say where the thread stands", { channel: thread.channel, thread: thread.threadTs, error: (error as Error).message }),
    );
    this.standing.set(key, next);
    void next.then(() => {
      if (this.standing.get(key) === next) this.standing.delete(key);
    });
  }

  private async sayStands(thread: ThreadRef, key: string, stands: Stands | null) {
    const was = this.stands.get(key);
    if (was !== undefined) {
      this.stands.delete(key);
      if (was.mine !== null) await this.update(thread.channel, was.ts, was.mine.text, was.mine.blocks);
      else await this.client.api("chat.delete", [["channel", thread.channel], ["ts", was.ts]], this.botToken);
    }
    if (stands === null) return;
    const end = this.ends.get(key);
    // (a question waiting at the end says it, as the chat leaves the line out while a card waits)
    if (stands.kind === "need" && end?.mine?.question === true) return;
    const lang = stationLang();
    const block = standsBlock(stands, lang);
    // (a message holds 50 blocks)
    if (end !== undefined && end.mine !== null && end.mine.blocks.length < 50) {
      // (known as said before it goes: a change of the message meanwhile keeps it)
      this.stands.set(key, { ts: end.ts, mine: end.mine, block });
      await this.update(thread.channel, end.ts, end.mine.text, [...end.mine.blocks, block]);
      return;
    }
    const said = standsText(stands, lang);
    const posted = await this.client.api(
      "chat.postMessage",
      [
        ["channel", thread.channel],
        ["thread_ts", thread.threadTs],
        ["text", said],
        ["blocks", JSON.stringify([block])],
      ],
      this.botToken,
    );
    const ts = text(posted?.ts);
    if (ts === "") return;
    this.stands.set(key, { ts, mine: null, block });
    this.heard(thread.channel, thread.threadTs, ts);
  }

  private update(channel: string, ts: string, said: string, blocks: Json[]) {
    return this.client.api(
      "chat.update",
      [
        ["channel", channel],
        ["ts", ts],
        ["text", said],
        ["blocks", JSON.stringify(blocks)],
      ],
      this.botToken,
    );
  }

  /// It works again: where it stood is no longer so.
  override working(thread: ThreadRef, messageTs: string | null, status: string, page?: string | null) {
    super.working(thread, messageTs, status, page);
    if (status !== "") this.standsAt(thread, null);
  }

  /// Sends a file's bytes to Slack (not yet shared anywhere): its file id and title.
  private async upload(file: Attachment): Promise<[string, string]> {
    const bytes = await readFile(file.path);
    const url = await this.client.api(
      "files.getUploadURLExternal",
      [
        ["filename", file.name],
        ["length", String(bytes.length)],
      ],
      this.botToken,
    );
    if (typeof url?.upload_url !== "string" || typeof url?.file_id !== "string") throw new Error("slack files.getUploadURLExternal: no upload_url");
    await this.client.upload(url.upload_url, bytes, file.name);
    return [url.file_id, file.name];
  }

  /// The ts of the message files were shared in, which Slack fills in a moment after the share.
  private async sharedTs(completed: Json, file: string, channel: string): Promise<string | null> {
    const find = (f: Json): string | null => {
      for (const k of ["public", "private"]) {
        const ts = f?.shares?.[k]?.[channel]?.[0]?.ts;
        if (typeof ts === "string") return ts;
      }
      return null;
    };
    const now = find(completed?.files?.[0]);
    if (now !== null) return now;
    for (let i = 0; i < 10; i++) {
      await wall.sleep(500);
      let info: Json;
      try {
        info = await this.client.api("files.info", [["file", file]], this.botToken);
      } catch {
        return null;
      }
      const ts = find(info?.file);
      if (ts !== null) return ts;
    }
    return null;
  }

  protected async lookUp(user: string): Promise<Person | null> {
    try {
      return personOf(await this.client.api("users.info", [["user", user]], this.botToken));
    } catch {
      return null;
    }
  }

  /// users.lookupByEmail (users:read.email): users_not_found, or a deactivated account, is none.
  protected async lookUpEmail(email: string): Promise<string | null> {
    try {
      const user = (await this.client.api("users.lookupByEmail", [["email", email]], this.botToken))?.user;
      return user?.deleted === true ? null : text(user?.id) || null;
    } catch {
      return null;
    }
  }

  /// A person as far as already known, without waiting; an unknown one is looked up in the background, and so is one
  /// learned before pictures were kept.
  knownPerson(user: string): Person | null {
    if (!this.book) return null;
    const team = this.workspace() ?? "?";
    const fetch = async () => {
      try {
        return personOf(await this.client.api("users.info", [["user", user]], this.botToken));
      } catch {
        return null;
      }
    };
    return this.book.person(personKey(team, user), fetch, (known) => known.picture === undefined);
  }

  /// A channel's name as far as already known (null for DMs or not yet known), without waiting.
  knownChannel(channel: string): string | null {
    if (!this.book) return null;
    const team = this.workspace() ?? "?";
    return this.book.channel(channelKey(team, channel), () => channelNameOf(this.client, channel, this.botToken));
  }

  /// Channel name via conversations.info (null for DMs), kept for the connection's lifetime.
  async channelName(channel: string): Promise<string | null> {
    if (this.channels.has(channel)) return this.channels.get(channel) ?? null;
    const name = await channelNameOf(this.client, channel, this.botToken);
    this.channels.set(channel, name);
    return name;
  }

  history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
    const bot = this.botUserId();
    return (async () => {
      const all: ChatMessage[] = [];
      let cursor: string | null = null;
      for (;;) {
        const params: Params = [
          ["channel", thread.channel],
          ["ts", thread.threadTs],
          ["limit", "200"],
        ];
        if (cursor !== null) params.push(["cursor", cursor]);
        const page = await this.client.api("conversations.replies", params, this.botToken);
        for (const m of Array.isArray(page?.messages) ? page.messages : []) {
          const by = m?.user !== undefined && m?.user !== null ? m.user : m?.bot_id;
          const user = typeof by === "string" ? by : "unknown";
          const fromBot = (m?.bot_id !== undefined && m?.bot_id !== null) || user === bot;
          const files = messageFiles(m);
          all.push({ ts: text(m?.ts), user, text: messageText(m), fromBot, ...(files.length > 0 ? { files } : {}) });
        }
        const next = page?.response_metadata?.next_cursor;
        cursor = typeof next === "string" && next !== "" ? next : null;
        if (cursor === null) break;
      }
      const until = number(before) ?? Number.MAX_VALUE;
      const earlier = all.filter((m) => (number(m.ts) ?? 0) < until);
      return earlier.slice(Math.max(0, earlier.length - limit));
    })();
  }

  /// A shared file's bytes, read as the bot (files:read).
  async download(file: InboundFile): Promise<Uint8Array> {
    if (file.url === null) throw new Error("Slack does not give its contents");
    return this.client.download(file.url, file.name, this.botToken);
  }

  /// Any Web API method as the bot; values that are not strings (blocks, arrays) go as JSON, as Slack takes them.
  async api(method: string, params: Record<string, Json>): Promise<Json> {
    const form: Params = Object.entries(params)
      .filter(([, v]) => v !== null && v !== undefined)
      .map(([k, v]) => [k, field(v)]);
    return this.client.api(method, form, this.botToken);
  }

  protected statusLine(thread: ThreadRef) {
    let working = false;
    const call = async (method: string, params: Params) => {
      await this.client.api(method, params, this.botToken);
      if (method !== "assistant.threads.setStatus") return;
      const status = params.find(([key]) => key === "status")?.[1] ?? "";
      if (status !== "" && !working) this.onWorking();
      working = status !== "";
    };
    return new ThreadStatus(call, this.run, thread.channel, thread.threadTs);
  }
}
