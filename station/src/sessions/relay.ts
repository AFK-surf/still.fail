// A chat relayed to a channel (docs/relay.md): a person picks a Slack channel or a Feishu/Lark group one of the
// station's connects' bots is in, and the chat's agent goes on there too. The station starts the conversation there
// itself (who relayed it, from which chat, their note), or joins a Slack thread a person gave the link of, makes it one of the agent's conversations, says so in the chat
// it came from, and tells the agent, who writes people there what they need to pick it up. The chat it came from goes
// on as before.
import { tr, stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { ThreadRow } from "../store/rows.ts";
import { threadAddress } from "../agents/instructions.ts";
import { FeishuSurface } from "../feishu/surface.ts";
import { SlackSurface } from "../slack/surface.ts";
import type { ChatSurface, Place, ThreadRef } from "./chat.ts";
import type { Connect } from "./config.ts";
import type { Hub } from "./hub.ts";

/// A place a chat can be relayed to, with when one was last relayed there (absent if never).
export type RelayPlace = Place & { used?: number };

/// A connect a chat can be relayed through, with where its bot can start a conversation (or why that was not read).
export type RelayConnect = {
  id: string;
  /// Its platform as people know it: Lark is a Feishu connect on larksuite.com.
  kind: "slack" | "feishu" | "lark";
  name: string;
  team: string | null;
  /// Its bot's picture as the platform shows it, once known.
  botImage: string | null;
  /// The bot the chat goes on through unless another is picked (one of them at most): see `preferredOf`.
  preferred: boolean;
  places: RelayPlace[];
  error?: string;
};

/// Where a chat was relayed: the conversation started there, and a link to it where the platform has one.
export type Relayed = { thread: number; to: string; place: string; link: string | null };

/// The session a chat's relaying goes on with: the first to take part in it (its own agent).
function agentOf(hub: Hub, thread: ThreadRow): string {
  const member = hub.store.threadSessions(thread.id)[0];
  if (member === undefined) throw new Error("this chat has no agent to go on with");
  return member.session;
}

/// The connects of the session's workspace that are on and connected, with the surface each speaks through.
function connectsFor(hub: Hub, session: string): { id: string; chat: ChatSurface; kind: RelayConnect["kind"]; bind: Connect["bind"] }[] {
  const home = hub.workspaces()[0] ?? null;
  const ws = hub.wsOf(session);
  return hub
    .config()
    .connects.filter((c) => c.enabled && (home === null || (c.workspace ?? home) === ws))
    .flatMap((c) => {
      const chat = hub.chatOf(c.id);
      if (chat === undefined || !chat.places || !chat.begin) return [];
      const kind: RelayConnect["kind"] = c.kind === "feishu" ? (chat instanceof FeishuSurface && chat.domain === "lark" ? "lark" : "feishu") : "slack";
      return [{ id: c.id, chat, kind, bind: c.bind }];
    });
}

/// The bot a chat goes on through unless another is picked: the chat's own (its session's connect), else the first
/// bound to the profile its agent runs on, else to its runtime and model, else to its runtime; none where no bot runs
/// what its agent runs.
function preferredOf(hub: Hub, session: string, connects: { id: string; bind: Connect["bind"] }[]): string | null {
  const row = hub.store.getSession(session);
  if (row === null) return null;
  const runs = connects.filter((c) => c.bind.runtime === row.runtime);
  const found =
    connects.find((c) => c.id === row.connect) ??
    runs.find((c) => c.bind.profile === row.profile) ??
    runs.find((c) => row.model !== null && c.bind.model === row.model) ??
    runs[0];
  return found?.id ?? null;
}

/// The team (Slack workspace, Feishu tenant) a surface's bot is in, and its bot's picture, once they are known.
function identityOf(chat: ChatSurface): { team: string | null; botImage: string | null } {
  const me = chat instanceof SlackSurface || chat instanceof FeishuSurface ? chat.identity() : null;
  return { team: me?.team || null, botImage: me?.botImage || null };
}

/// Where a chat can be relayed to: each connect's places, read now (one that cannot be read says why), those relayed to
/// before first (the latest first), then by name.
export async function relayPlaces(hub: Hub, thread: ThreadRow): Promise<RelayConnect[]> {
  const session = agentOf(hub, thread);
  const out: RelayConnect[] = [];
  const connects = connectsFor(hub, session);
  const preferred = preferredOf(hub, session, connects);
  for (const c of connects) {
    const shown = { id: c.id, kind: c.kind, name: c.chat.botName?.() || c.id, ...identityOf(c.chat), preferred: c.id === preferred };
    try {
      const used = hub.store.relayedTo(c.id);
      const places: RelayPlace[] = (await c.chat.places!()).map((p) => (used.has(p.id) ? { ...p, used: used.get(p.id)! } : p));
      places.sort((a, b) => (b.used ?? -1) - (a.used ?? -1) || a.name.localeCompare(b.name));
      out.push({ ...shown, places });
    } catch (error) {
      log.warn("hub", "a connect's places were not read for relaying", { connect: c.id, error: (error as Error).message });
      out.push({ ...shown, places: [], error: (error as Error).message });
    }
  }
  return out;
}

/// What a place is called in the station's words: #channel for Slack, the group's name for Feishu.
const placeName = (place: Place) => (place.kind === "channel" ? `#${place.name}` : place.name);

/// Where a person relays a chat: a connect's place (a new conversation there), or a link to a message of a thread
/// in one (that thread; through the connect named, when it is in that workspace, else the first that is).
export type RelayTarget = { connect: string; channel: string } | { link: string; connect?: string };

/// Relays a chat by `by` (a person's name), with their `note`.
export async function relay(hub: Hub, thread: ThreadRow, by: string, target: RelayTarget, note: string): Promise<Relayed> {
  const session = agentOf(hub, thread);
  const connects = connectsFor(hub, session);
  let c: (typeof connects)[number] | undefined;
  let existing: ThreadRef | null = null;
  if ("link" in target) {
    const named = connects.filter((o) => o.id === target.connect);
    for (const candidate of [...named, ...connects.filter((o) => o.id !== target.connect)]) {
      existing = candidate.chat.threadOf?.(target.link) ?? null;
      if (existing !== null) {
        c = candidate;
        break;
      }
    }
    if (c === undefined || existing === null) throw new Error("not a link to a message of a Slack workspace this station's connects are in");
  } else {
    c = connects.find((c) => c.id === target.connect);
    if (c === undefined) throw new Error(`connect ${target.connect} cannot take this chat`);
  }
  const channel = existing?.channel ?? (target as { channel: string }).channel;
  const place = (await c.chat.places!()).find((p) => p.id === channel);
  if (place === undefined) throw new Error(`the bot is not in ${channel}`);
  const surface = hub.surface(c.id);
  if (existing !== null) {
    // A thread another session of the same bot takes part in is that one's (as slack_api keeps to).
    const known = hub.store.threadAt(surface, existing.channel, existing.threadTs);
    const members = known === null ? [] : hub.store.threadSessions(known.id).filter((m) => m.connect === c!.id);
    if (members.some((m) => m.session === session)) throw new Error("this chat's agent is in that thread already");
    if (members.length > 0) throw new Error("another chat's agent is in that thread: it cannot be relayed there");
  }
  const lang = stationLang();
  const title = thread.title ?? thread.autoTitle ?? tr(lang, "station.relay.untitled");
  const page = hub.link(session) ?? null;
  const from = page !== null ? `[${title.replace(/[[\]]/g, "")}](${page})` : title;
  const said = note.trim();
  const opening = tr(lang, "station.relay.opening", { who: by, chat: from }) + (said === "" ? "" : `\n\n${said}`);
  const begun = existing !== null ? { thread: existing, ts: await c.chat.post(existing, opening, []) } : await c.chat.begin!(channel, opening);
  const there = hub.store.openThread(surface, begun.thread.channel, begun.thread.threadTs, null, by);
  hub.store.noteRelayed(c.id, channel);
  hub.store.joinThread(there.id, session, c.id);
  // Kept as the station's words there; the agent hears of it in its notice below, not as a message.
  hub.store.insertMessage({ thread: there.id, ts: begun.ts, authorKind: "ember", author: "ember", text: opening, attachments: [] });
  const to = threadAddress(begun.thread.channel, begun.thread.threadTs);
  const link = c.chat.permalink?.(begun.thread) ?? null;
  const name = existing !== null ? tr(lang, "station.relay.threadIn", { place: placeName(place) }) : placeName(place);
  // Said in the chat it came from, for its people: where it went on.
  const named = link !== null ? `[${name}](${link})` : name;
  const here = hub.store.threadSessions(thread.id).find((m) => m.session === session);
  if (here !== undefined) {
    const text = `↗ ${tr(lang, "station.relay.relayed", { who: by, place: named })}`;
    try {
      const ts = await hub.chat(here.connect).post({ channel: thread.channel, threadTs: thread.threadTs }, text, []);
      hub.store.insertMessage({ thread: thread.id, ts, authorKind: "ember", author: "ember", text, attachments: [] });
    } catch (error) {
      log.warn("hub", "a relay was not said in the chat it came from", { thread: thread.id, error: (error as Error).message });
    }
  }
  const where =
    existing !== null
      ? `a Slack thread people were already talking in, in #${place.name}`
      : place.kind === "channel"
        ? `a new thread in Slack channel #${place.name}`
        : place.kind === "topics"
          ? `a new topic in Feishu topic group ${place.name}`
          : `Feishu group ${place.name}, whose conversation is now yours`;
  hub.notify(
    session,
    `${by} relayed the chat ${threadAddress(thread.channel, thread.threadTs)} to ${where}: ${to} is now one of your conversations, and replies there come to you. ` +
      `The station posted its first message (who relayed it, a link to this chat${said === "" ? "" : ", and their note"}). ` +
      (existing !== null ? `Read what was said there before first (slack_api conversations.replies with channel ${begun.thread.channel} and ts ${begun.thread.threadTs}). ` : "") +
      `Post there now with chat_post to=${to}: what this conversation is about, what is decided and what is open, so the people there can take part without reading it. ` +
      `${said === "" ? "" : `Their note: ${JSON.stringify(said)}. `}Keep answering the chat it came from too.`,
  );
  log.info("hub", "chat relayed", { thread: thread.id, session, connect: c.id, to });
  return { thread: there.id, to, place: name, link };
}
