// The views (views.rs): what one screen shows, put together from the account and station topics so the UI does no
// joining, filtering or grouping (docs/client-core.md, Views). A view watches the topics it is built from; any change
// of them only invalidates it, and the store has it computed when its coalesced emission goes out. What a person did
// here and their station has not confirmed yet (local.ts) is laid over what the stations hold.
import { Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import type { Data } from "../data.ts";
import type { Derive } from "../db/account.ts";
import type { Host } from "../host.ts";
import type { Runner } from "../runtime.ts";
import type { Store } from "../store.ts";
import type { Owner } from "../core/routing.ts";
import * as chatTabs from "../chat-tabs.ts";
import * as decisions from "../decisions.ts";
import { merge } from "../entries.ts";
import { CoreError } from "../error.ts";
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import * as jobs from "../jobs.ts";
import * as looks from "../looks.ts";
import { conformTy, type Ty } from "../conform.ts";
import * as present from "../present.ts";
import { topicKey, type Topic } from "../protocol.ts";
import * as refs from "../refs.ts";
import { chatsLinked } from "../refLinks.ts";
import { timed } from "../spent.ts";
import type { Value, Watch } from "../store.ts";
import { arr as arrU, deepFreeze, get as getU, isObject, shaped, sharedValue } from "../util.ts";
import { ofAddress } from "../workspace.ts";
import { presentHistory } from "../history.ts";
import { archiveHintOf, badgeKindsOf, jobsSeenOf, type ArchiveHint } from "../prefs.ts";
import { markdown, type MdStore } from "../markdown.ts";
import { withDrive } from "../drive-browse.ts";
import { heardFiles } from "../elsewhere.ts";
import { isImage, near, placeFiles } from "../placed.ts";
import { KINDS as THING_KINDS, isVideo, mediaDays, thingsHaving, thingsOf } from "../things.ts";
import { archive } from "./archive.ts";
import { Local, PENDING_PREFIX, type LocalChange } from "./local.ts";
import { askAnswers } from "./vault.ts";
import * as marks from "./marks.ts";
import { usageView } from "./usage.ts";
import { fleetView } from "./fleet.ts";
import { chatsCard, usageCard } from "./rail-cards.ts";
import { resourcesView } from "./resources.ts";
import { workspaceProfiles } from "./profiles.ts";
import { settingsView } from "./settings.ts";
import { waysView, type WaysView } from "./ways.ts";
import { admin, sources as adminSources } from "./admin.ts";
import { attention, choices, find, models, runnableOn, runtimes, servingIn } from "./models.ts";
import * as brief from "./brief.ts";
import * as xshare from "./xshare.ts";
import * as memberships from "./memberships.ts";
import * as publish from "./publish.ts";
import { type SearchSource, searchView, stationTopic } from "./search.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: J): string | null => (typeof v === "string" ? v : null);
const u64 = (v: J): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

const DAY_MS = 86_400_000;
/// How many rows a list shows before its stations' rows are loaded: more than a screen holds. Done whenever the
/// stations hold more (2026-10-29: on a phone's Hermes, 300 rows made at once kept the first page 150 ms; 80, 60).
export const HEAD = 80;

const VIEW_TOPICS = new Set(["chats", "chatSearch", "search", "stations", "profiles", "connects", "chat", "history", "agentCard", "stationNet", "archive", "workspaceMarks", "chatJobs", "chatLetters", "chatThings", "imageNear", "longJobs", "usage", "fleet", "railCard", "settings", "resources", "adminList", "adminItem", "adminOverview", "adminRelays", "workspaceWays"]);

/// What a chat row's columns say that the views find rows by (db/account.ts): how urgent it is for its person
/// (workspace marks), whether it asks something of them.
export const chatDerive: Derive = {
  tone: marks.rowTone,
  asks: (row) => {
    const d = decisions.asked(row);
    return d !== null && !decisions.dismissed(d);
  },
};

/// A station of a scope, as the workspace lists it.
/// `joined`: the station's home is another workspace (docs/multi-workspace.md), this one it joined.
export type StationInfo = { address: string; id: string; name: string; emoji: string | null; icon: string | null; online: boolean; lastSeen: J; version: J; joined: boolean };

/// Whether a station is taken for down: its link found it so, or — not found out yet this time — it was, last.
export function down(link: J): boolean {
  const state = get(link, "state");
  // (gone for its update: down from the moment it goes, as it will be a while)
  if (state !== "online" && get(link, "cause") === "updating") return true;
  return state === "offline" || (state === "connecting" && get(link, "last") === "offline");
}

/// A station taken for down, in words, as its link says why (link.ts DownCause): the device's network, the station, or
/// the way between them, or its update.
export function downWords(link: J, name: string): string {
  const cause = get(link, "cause");
  if (cause === "updating") return t("core-views.station.updating", { name });
  if (cause === "network") return t("core-views.station.offline_network", { name });
  if (cause === "unreached") return t("core-views.station.unreachable", { name });
  if (cause === "lock") return t("core-views.station.lock", { name });
  return t("core-views.station.offline", { name });
}

/// Whether a station's versions offer the 测试版 switch.
export function betaOffered(overview: J, accountInBeta: () => boolean): boolean {
  const station = arr(get(overview, "updates")).find((v) => get(v, "id") === "station");
  const channel = get(station, "channel");
  if (channel === "beta") return true;
  if (typeof channel === "string") return accountInBeta();
  return false;
}

/// The session keys taking part in a thread.
export function members(thread: J): string[] {
  return arr(get(thread, "sessions")).flatMap((m) => (typeof get(m, "session") === "string" ? [m.session] : []));
}

/// Text without Slack's `<@U123>` mentions.
function withoutMentions(text: string): string {
  let out = "";
  let rest = text;
  for (;;) {
    const at = rest.indexOf("<@");
    if (at < 0) break;
    out += rest.slice(0, at);
    const after = rest.slice(at + 2);
    const end = after.indexOf(">");
    if (end > 0 && /^[A-Z0-9]+$/.test(after.slice(0, end))) rest = after.slice(end + 1);
    else {
      out += "<@";
      rest = after;
    }
  }
  return out + rest;
}

/// What a chat is called, as its station calls it (read/views.ts titleOf): the name people gave it, else the one its
/// agent gave it; a chat of still.fail's own is a new chat until it has one, the same all along; a Slack or Feishu
/// thread the first line a person wrote in it, else its channel.
/// Where a Slack or Feishu thread is, in words: #channel, 私信, the Feishu group; null for a still.fail chat.
function placeName(surface: string, channel: string, channelName: string): string | null {
  const feishu = surface.startsWith("feishu:") || format.isFeishuChat(channel);
  if (feishu) return channelName || t("core-logic.format.thread.feishu");
  if (surface === "ember" || surface === "stillfail" || surface === "") return null;
  return channel.startsWith("D") ? t("core-views.direct_message") : `#${channelName || channel}`;
}

export function chatTitle(thread: J): string {
  const text = (name: string): string | null => {
    const v = get(thread, name);
    return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
  };
  const title = text("title") ?? text("autoTitle");
  if (title !== null) return title;
  const surface = get(thread, "surface");
  if (surface === "ember" || surface === "stillfail") return t("core-views.new_chat");
  const firstText = text("firstText");
  if (firstText !== null) {
    const first = withoutMentions(firstText)
      .split("\n")
      .map((l) => format.splitWhitespace(l).join(" "))
      .find((l) => l !== "");
    if (first !== undefined) return first;
  }
  const channel = text("channelName");
  // A Feishu chat is named as it is there (no #).
  if (channel !== null) return typeof surface === "string" && surface.startsWith("feishu:") ? channel : `#${channel}`;
  if (text("channel")?.startsWith("D")) return t("core-views.direct_message");
  return t("core-views.new_chat");
}

/// What a message another chat's agent sent (session_send, or the first of a chat it opened with chat_create) is headed
/// with: its chat's title and link, and the message.
export function sentFrom(text: string): [string, string, string] | null {
  const sent = sentHead(text);
  return sent === null ? null : [sent.title, sent.link, sent.rest];
}

/// What sentFrom reads, and whether it heads the first message of a chat that agent opened (`由 … 开的 chat：`) rather
/// than one it wrote to (`来自 …：`).
function sentHead(text: string): { title: string; link: string; rest: string; opened: boolean } | null {
  const at = text.indexOf("\n\n");
  if (at < 0) return null;
  const head = text.slice(0, at);
  const rest = text.slice(at + 2);
  let named: string | null = null;
  let opened = false;
  if (head.startsWith("来自 ") && head.endsWith("：")) named = head.slice(3, -1);
  else if (head.startsWith("From ") && head.endsWith(":")) named = head.slice(5, -1);
  else if (head.startsWith("由 ") && head.endsWith(" 开的 chat：")) [named, opened] = [head.slice(2, -" 开的 chat：".length), true];
  else if (head.startsWith("Opened by ") && head.endsWith(":")) [named, opened] = [head.slice(10, -1), true];
  if (named === null) return null;
  let title: string;
  let link: string;
  if (named.startsWith("[") && named.endsWith(")")) {
    const md = named.slice(1, -1);
    const cut = md.indexOf("](");
    if (cut < 0) return null;
    title = md.slice(0, cut);
    link = md.slice(cut + 2);
  } else if (named.startsWith("<") && named.endsWith(">")) {
    const inner = named.slice(1, -1);
    const cut = inner.indexOf("|");
    if (cut < 0) return null;
    link = inner.slice(0, cut);
    title = inner.slice(cut + 1);
  } else return null;
  if (title === "" || !link.startsWith("http") || /\s/.test(link)) return null;
  return { title, link, rest, opened };
}

/// Whether a message is a letter: what two chats' agents wrote each other (session_send), as its station marked it
/// (`letter`: which way, and the other chat); from a station before that, one another chat's agent wrote to this chat,
/// headed `来自 …：`, by an agent that is not one of this chat's (`keys`). The first message of a chat such an agent opened
/// is not: it is what the chat is about.
export function isLetter(message: J, keys: ReadonlySet<string>): boolean {
  if (isObject(message.letter)) return true;
  if (message.authorKind !== "agent" || keys.has(str(message.author) ?? "")) return false;
  const sent = sentHead(str(message.text) ?? "");
  return sent !== null && !sent.opened;
}

/// Which way a letter (isLetter) went and the other chat, as its station marked it; from a station before that, coming
/// in from the chat its heading names.
export function letterWay(message: J): { way: "in" | "out"; title: string; link: string | null } {
  const marked = message.letter;
  if (isObject(marked) && typeof marked.title === "string") {
    return { way: marked.way === "out" ? "out" : "in", title: marked.title, link: str(marked.link) };
  }
  const sent = sentHead(str(message.text) ?? "");
  return { way: "in", title: sent?.title ?? "", link: sent?.link ?? null };
}

/// A letter's words without the heading its station wrote (`来自 …：`, `发给 …：`): the page says which chat.
export function letterWords(text: string): string {
  const at = text.indexOf("\n\n");
  return at < 0 ? text : text.slice(at + 2);
}

/// A chat's letters as their page shows them (`chatLetters`): by the other chat, the one written with last first, each
/// with its letters both ways in the order written (`way`).
export function lettersByChat(letters: { message: J; way: "in" | "out"; title: string; link: string | null }[]): J[] {
  const chats = new Map<string, { title: string; link: string | null; letters: J[]; last: number }>();
  for (const l of letters) {
    const key = l.link ?? `\u0000${l.title}`;
    const was = chats.get(key);
    const letter = { ...l.message, way: l.way };
    // (by when written: letters from before their own log are entries, numbered among the chat's, those of it in it)
    const at = u64(l.message.createdAt) ?? 0;
    chats.set(key, was === undefined ? { title: l.title, link: l.link, letters: [letter], last: at } : { ...was, letters: [...was.letters, letter], last: Math.max(was.last, at) });
  }
  return [...chats.values()].sort((a, b) => b.last - a.last).map(({ title, link, letters }) => {
    const last = letters.at(-1)!;
    // In brief, as a row of the page's list has it: the last letter's words on a line, said by this chat's agent when
    // it went out (one coming in is the row's own chat's).
    const words = format.plainText(str(last.text) ?? "").replace(/\s+/g, " ").trim();
    const said = last.way === "out" ? t("core-views.letters.out", { name: str(get(last.by, "name")) ?? "", text: words }) : words;
    return { key: link ?? title, title, link, letters, last: said, lastActiveAt: u64(last.createdAt) ?? 0 };
  });
}

/// The notices that a runtime is not installed, said where they matter: under the viewer's message that waits for it
/// (its `blocked`, the last such before them) rather than as notices of their own; once it is installed they are gone
/// (what waited went on). One with none of the viewer's waiting before it stays a notice, with installing it.
export function blockedUnder(messages: J[]): J[] {
  const gone = new Set<number>();
  const blocked = new Map<number, J>();
  for (let i = 0; i < messages.length; i++) {
    const install = messages[i]!.install;
    if (!isObject(install)) continue;
    let j = i - 1;
    while (j >= 0 && !(messages[j]!.mine === true && messages[j]!.waiting === true)) j--;
    if (j >= 0) blocked.set(j, install);
    if (j >= 0 || install.state === "installed") gone.add(i);
  }
  if (gone.size === 0) return messages;
  return messages.flatMap((m, i) => (gone.has(i) ? [] : blocked.has(i) ? [{ ...m, blocked: blocked.get(i) }] : [m]));
}

/// A message as a chat shows it: whether it is the viewer's, still.fail's own notice, who said it, mentions named.
export function shownMessage(message: J, agents: J[], viewer: J, slackUsers: string[], members_: J[], bots: [string, string][], creator: J): J {
  const m: J = { ...message };
  const card = decisions.ofMessage(message);
  if (card !== null) m.card = decisions.labelAssignee(card, viewer, members_, creator);
  const kind = str(m.authorKind) ?? "";
  const author = str(m.author) ?? "";
  const saidName = str(m.authorName) || null;
  m.mine = kind === "person" && present.isViewer(viewer, author, slackUsers);
  m.system = kind === "ember" || kind === "stillfail";
  if (kind === "agent") {
    const agent = agents.find((a) => get(get(a, "session"), "key") === author);
    const session = agent ? agent.session : undefined;
    const identity = m.agentIdentity ?? null;
    const model = str(get(identity, "model"));
    const sent = agent === undefined ? sentFrom(str(m.text) ?? "") : null;
    if (sent !== null) {
      const [title, link, rest] = sent;
      m.text = rest;
      m.by = { name: title, from: link, maker: model !== null ? present.maker(model) : null };
    } else {
      // Before its session is read: the model and runtime the station gave with the message.
      const said = str(m.authorModel);
      m.by = {
        name: model !== null ? format.agentLabel(model, str(get(identity, "effort"))) : (str(get(session, "agentText")) ?? saidName ?? "agent"),
        agent: agent ? author : null,
        maker: model !== null ? present.maker(model) : session !== undefined ? (session.maker ?? null) : present.maker(said),
        runtime: get(session, "runtime") ?? str(m.authorRuntime) ?? null,
      };
    }
  } else if (kind === "ember" || kind === "stillfail") {
    m.by = { name: brandName() };
    m.notice = noticeOf(str(m.text) ?? "", str(m.profile) !== null);
  }
  else {
    const member = members_.find((x) => typeof get(x, "email") === "string" && x.email.toLowerCase() === author.toLowerCase());
    const name = present.memberName(members_, author) ?? saidName ?? (author === "local" ? t("core-views.local_author") : author);
    // A Slack person's own picture, as their Slack shows it; else their workspace account's.
    const picture = str(m.authorPicture) || str(get(member, "picture")) || null;
    m.by = { name, picture };
  }
  if (kind === "person" || kind === "agent") m.text = present.mentions(str(m.text) ?? "", bots, members_);
  return m;
}

import * as brand from "../brand.ts";
import { noticeOf } from "../notice.ts";
export { noticeOf };
const brandName = () => brand.name();

/// The pictures of the Slack people a session heard, by their Slack id, as the station gives them: those who wrote in its
/// threads (`participants`), and its threads' people and starters; and of its station's bots (`connects`), another
/// agent's words it was given.
function slackPictures(session: J, threads: J[], connects: J[]): Map<string, string> {
  const pictures = new Map<string, string>();
  for (const c of connects) {
    const conn = get(c, "connection");
    const bot = str(get(conn, "botUserId")) ?? str(get(get(conn, "workspace"), "botUserId"));
    const picture = str(get(c, "botImage")) || str(get(get(conn, "workspace"), "botImage"));
    if (bot !== null && picture) pictures.set(bot, picture);
  }
  const people = [...arr(get(session, "participants")), ...threads.flatMap((th) => [...arr(get(th, "people")), get(th, "creator")])];
  for (const p of people) {
    const id = str(get(p, "id"));
    const picture = str(get(p, "picture"));
    if (id === null || picture === null || picture === "" || !id.startsWith("slack:")) continue;
    const user = id.slice(id.lastIndexOf(":") + 1);
    if (!pictures.has(user)) pictures.set(user, picture);
  }
  return pictures;
}

/// The Slack workspaces a station's connects are signed in to, by team: their names and links.
function slackWorkspaces(overview: J): Map<string, format.SlackWorkspace> {
  const workspaces = new Map<string, format.SlackWorkspace>();
  for (const c of arr(get(overview, "connects"))) {
    if (get(c, "kind") === "feishu") {
      const id = str(get(c, "id"));
      if (id !== null) workspaces.set(`feishu:${id}`, { name: str(get(c, "team")) ?? "", url: format.feishuApplink(str(get(get(c, "feishu"), "domain"))) });
      continue;
    }
    const conn = get(c, "connection");
    const s = get(conn, "state");
    const seen = s === "connected" || s === "reconnecting" ? get(conn, "workspace") : undefined;
    const team = str(get(seen, "teamId"));
    if (team === null) continue;
    const name = str(get(seen, "team")) ?? str(get(c, "team")) ?? "";
    const url = str(get(seen, "url")) || null;
    if (!workspaces.has(team)) workspaces.set(team, { name, url });
  }
  return workspaces;
}

/// Whether the viewer added something: its creator's id, or email in any case, is theirs.
function isMine(me: J, creator: J): boolean {
  if (!isObject(creator)) return false;
  const id = get(creator, "id");
  if (id !== undefined && id !== null && id === get(me, "id")) return true;
  const email = (v: J) => (typeof get(v, "email") === "string" && v.email !== "" ? (v.email as string).toLowerCase() : null);
  const mine = email(me);
  return mine !== null && email(creator) === mine;
}

/// A connect's sessions as its page shows them.
function connectSessions(connect: J, connects: J[], sessions: J[], threads: J[], clock: present.Clock): J {
  const id = str(get(connect, "id")) ?? "";
  const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
  const at = (v: J) => (typeof get(v, "lastActiveAt") === "number" ? v.lastActiveAt : 0);
  const nameOf = (c: string) => {
    const n = strOf(connects.find((x) => strOf(x, "id") === c), "name");
    return n !== "" ? n : c;
  };
  const shown = (s: J) => {
    const c = present.session(s);
    const key = strOf(c, "key");
    const thread = threads.find((th) => arr(get(th, "sessions")).some((m) => get(m, "session") === key));
    c.chat = thread !== undefined ? (get(thread, "id") ?? null) : null;
    return c;
  };
  const byRecent = [...sessions].sort((a, b) => at(b) - at(a));
  const boundTo = (s: J) => arr(get(s, "boundTo")).some((c) => c === id);
  const own = byRecent.filter((s) => strOf(s, "connect") === id).slice(0, 12).map(shown);
  const running = sessions.filter((s) => (strOf(s, "connect") === id || boundTo(s)) && strOf(s, "process") === "running").length;
  const current = str(get(connect, "session"));
  const runtime = str(get(get(connect, "bind"), "runtime")) ?? "";
  const candidates = byRecent
    .filter((s) => strOf(s, "runtime") === runtime)
    .map((s) => {
      const c = shown(s);
      const others = arr(get(s, "boundTo"))
        .filter((x): x is string => typeof x === "string" && x !== id)
        .map(nameOf);
      let description = [
        strOf(s, "scope") === "all" ? t("core-views.connect.single") : t("core-views.connect.from_thread"),
        nameOf(strOf(s, "connect")),
        t("core-views.connect.turns", { n: u64(get(s, "turns")) ?? 0 }),
        format.relativeTime(at(s), clock.now, clock.offsetMin),
      ].join(" · ");
      if (others.length > 0) description += ` · ${t("core-views.connect.also_used", { names: others.join(t("core-views.list_separator")) })}`;
      c.description = description;
      c.current = strOf(s, "key") === current;
      return c;
    });
  const bound = sessions.find((s) => current !== null && strOf(s, "key") === current);
  return { sessions: own, bound: bound !== undefined ? shown(bound) : null, candidates, running, changes: present.modeChanges(connect, running) };
}

/// What the views are put together with: the core's store and data, and what the accounts say of a workspace.
export type ViewsEnv = {
  host: Host;
  runner: Runner;
  store: Store;
  data: Data;
  /// The email of the signed-in account that reaches a workspace.
  emailOf: (workspace: string) => string | null;
  /// Whether that account is in the beta.
  betaOf: (workspace: string) => boolean;
  /// What still.fail calls the relay at a host.
  relayName: (host: string) => string | null;
  /// Every workspace the signed-in accounts are in (xshare.ts); none where not given.
  places?: () => xshare.Place[];
  /// A chat's sharing asked here (`chat.xshare`) and not answered yet.
  xshareAsked?: (station: string, session: string) => xshare.Asked | undefined;
  /// A chat's snapshot being revoked here (`chat.unpublish`) and not answered yet.
  revoking?: (station: string, id: string) => boolean;
  /// The name of the home workspace of a station a workspace joined, when the viewer is in it (memberships.ts).
  homeName?: (workspace: string, id: string) => string | null;
  /// Whether a workspace's notices are heard of on this device (`notify.set` `workspaces`); every one where not given.
  heard?: (workspace: string) => boolean;
  /// A topic a view watches shown again (its owner asked to bring it up to date, store.ts `resume`).
  resume?: (topic: Topic) => void;
  /// How agents' requests about vault items are answered on this device, from the vault as the core holds it
  /// (views/vault.ts askAnswers): each `{answer, lasts?}`, in the order asked.
  vaultAnswers?: (workspace: string, asks: VaultAskOf[]) => J[];
  /// How a workspace's members' devices reach its stations (views/ways.ts), from `/v1/me`; undefined while no account's
  /// is held.
  ways?: (workspace: string) => WaysView | undefined;
  /// Whether a station's topic with no value yet waits on the station for what it shows (station/topics.ts `waits`);
  /// none does where not given.
  waits?: (topic: Topic) => boolean;
};

/// An agent's request about a vault item a card names (`card.vault`), and whether it is one to keep a secret.
export type VaultAskOf = { request: string; save: boolean };

/// The request card `card` names and says what it asks (`vaultAsk`); null for any other.
function vaultAskOf(card: J): VaultAskOf | null {
  const request = typeof get(card, "vault") === "string" ? (card.vault as string) : null;
  const ask = get(card, "vaultAsk");
  return request === null || request === "" || !isObject(ask) ? null : { request, save: get(ask, "save") !== undefined };
}

/// The views' environment in a core.
export function envOf(core: Inner): ViewsEnv {
  const owner = (workspace: string) => core.workspaces.of(workspace).owner;
  return {
    host: core.host,
    runner: core.runner,
    store: core.store,
    data: core.data,
    waits: (topic) => core.stationTopics.waits(topic),
    emailOf: (workspace) => {
      const sub = owner(workspace);
      return sub === null ? null : (core.accounts.list().find((a) => a.sub === sub)?.email ?? null);
    },
    betaOf: (workspace) => {
      const sub = owner(workspace);
      return sub !== null && get(get(core.data.record("me", sub), "user"), "beta") === true;
    },
    places: () => xshare.places(core),
    resume: (topic) => core.router.resume(topic),
    xshareAsked: (station, session) => xshare.asked(core, station, session),
    revoking: (station, id) => publish.revoking(core, station, id),
    homeName: (workspace, id) => memberships.homeName(core, workspace, id),
    vaultAnswers: (workspace, asks) => askAnswers(core, workspace, asks),
    heard: (workspace) => core.attention?.attend.heard(workspace) ?? true,
    ways: (workspace) => {
      for (const account of core.accounts.list()) {
        const me = core.data.record("me", account.sub);
        const relays = arr(get(me, "relay_urls")).filter((u): u is string => typeof u === "string");
        if (relays.length === 0) continue;
        const names = get(me, "relay_names");
        return waysView(relays, isObject(names) ? names : {}, core.cloudSync.workspaceRelays(workspace), core.cloudSync.workspaceOff(workspace));
      }
      return undefined;
    },
    relayName: (host) => {
      for (const account of core.accounts.list()) {
        const names = get(core.data.record("me", account.sub), "relay_names");
        if (!isObject(names)) continue;
        for (const [url, name] of Object.entries(names)) {
          try {
            if (new URL(url).host === host && typeof name === "string") return name;
          } catch {
            // Not an address.
          }
        }
      }
      return null;
    },
  };
}

/// The views a core shows, as an owner of their topics.
export class Views implements Owner {
  /// The list rows made from each record (with what else they were made with), so a row whose record did not change
  /// is not made again (rule 7). Kept as long as the record is.
  readonly #rowsMade = new WeakMap<object, { sig: string; row: J }>();
  readonly #core: ViewsEnv;
  readonly local: Local;
  /// Per live view, the topics it watches.
  readonly #views = new Map<string, { topic: Topic; watches: Map<string, Watch> }>();
  /// The latest chats' things read (`#things`), by station and thread, with what they were read from.
  readonly #thingsKept = new Map<string, { entries: unknown; agents: unknown; value: { messages: J[]; things: ReturnType<typeof thingsOf>; whole: boolean; title: unknown } }>();
  readonly #updateNoticesOpen = new Set<string>();
  /// The threads chats copy what is sent from here to (`ccOn`), by `<station> <thread> <to>`.
  readonly #cc = new Set<string>();
  /// Views whose words count seconds (a chat's jobs): each computed again when they next change.
  readonly #again = new Map<string, Fiber.Fiber<unknown, unknown>>();
  /// The scopes whose stations' rows are being loaded (the list showed its first screen meanwhile).
  readonly #loading = new Set<string>();
  /// Since when each station up has had no host reading (by address): unanswered that long, it is said to be silent.
  readonly #hostless = new Map<string, number>();
  /// Each station's overview and host reading as the stations' list shows them, made again only as the station said
  /// something new (or, the overview's times in words, the minute changed): a host reading of one station, every few
  /// seconds from each, made every station's anew, the list and the new chat's view after it (50-80 ms a time on a
  /// phone, 2026-10-31).
  readonly #stationShown = new Map<string, { overview: unknown; minute: number; shown: J; host: unknown; presented: J }>();
  /// The live views that show agents' requests about vault items (a chat's cards, the 奏 page's), by the view: the
  /// requests, each in its workspace, and how they were answered here when it was made (`#vaultCard`), so that a change
  /// of the vault shows it again only where it changes what the cards say (`vaultChanged`).
  readonly #vaultShown = new Map<string, { topic: Topic; asks: { ws: string; ask: VaultAskOf }[]; said: string }>();

  constructor(core: ViewsEnv) {
    this.#core = core;
    this.local = new Local(core.data, () => core.host.nowMs());
    this.local.load();
    this.local.onChange = (change) => this.#localChanged(change);
    // What was said changed: the searches that find messages look again.
    core.data.onLogChange((table) => {
      if (table === "entry") this.#invalidate((v) => ((v.topic === "chatSearch" && typeof v.messages === "number" && v.messages > 0) || v.topic === "search") && refs.terms(String(v.query ?? "")).length > 0);
    });
    // What an agent said in Slack or heard from it changed: the chats it is in show it.
    core.data.onLogChange((table, station, key) => {
      if (table !== "slack") return;
      const session = topicKey({ topic: "session", station, key });
      for (const v of [...this.#views.values()]) if (v.topic.topic === "chat" && v.topic.station === station && v.watches.has(session)) this.#core.store.invalidate(v.topic);
    });
  }

  owns(topic: Topic): boolean {
    return VIEW_TOPICS.has(topic.topic);
  }

  // ── what the views watch ──

  start(view: Topic): void {
    this.#views.set(topicKey(view), { topic: view, watches: new Map() });
    this.#sync(view);
    this.#core.store.invalidate(view);
  }

  /// Shown again while it was kept: a search asks its stations again (what they hold changes; station/sync.ts
  /// `searchShown`), what they found before shown meanwhile.
  resume(view: Topic): void {
    if (view.topic !== "search") return;
    const live = this.#views.get(topicKey(view));
    for (const key of live?.watches.keys() ?? []) {
      const topic = JSON.parse(key) as Topic;
      if (topic.topic === "stationSearch") this.#core.resume?.(topic);
    }
  }

  /// Whether a station's search (`stationSearch`) is subscribed to, or of a search a UI subscribes to now: one let go is kept a while
  /// (EVICT_AFTER_MS) with its watches, and is not asked again for them (each words typed was one).
  searchShownNow(topic: Topic): boolean {
    if (this.#core.store.subscribed(topic)) return true;
    const key = topicKey(topic);
    for (const live of this.#views.values()) {
      if (live.topic.topic === "search" && live.watches.has(key) && this.#core.store.subscribed(live.topic)) return true;
    }
    return false;
  }

  stop(view: Topic): void {
    const key = topicKey(view);
    const again = this.#again.get(key);
    if (again) {
      this.#core.runner.interrupt(again);
      this.#again.delete(key);
    }
    const live = this.#views.get(key);
    this.#views.delete(key);
    this.#vaultShown.delete(key);
    for (const w of live?.watches.values() ?? []) w.drop();
  }

  // ── agents' requests about vault items, on their cards ──

  /// The vault of workspace `ws` (null: any) changed as this core holds it (views/vault.ts): the views whose cards it
  /// answers otherwise now made again.
  vaultChanged(ws: string | null): void {
    for (const shown of [...this.#vaultShown.values()]) {
      if (ws !== null && !shown.asks.some((a) => a.ws === ws)) continue;
      const said = this.#vaultSaid(shown.asks);
      if (said === shown.said) continue;
      shown.said = said;
      this.#core.store.invalidate(shown.topic);
    }
  }

  #vaultSaid(asks: { ws: string; ask: VaultAskOf }[]): string {
    return JSON.stringify(asks.map((a) => this.#core.vaultAnswers?.(a.ws, [a.ask])[0] ?? null));
  }

  /// Card `card` of a message in workspace `ws` as the clients draw it, an agent's request about a vault item it names
  /// answered: how it is answered on this device (`vaultAsk.answer`, `lasts`: the vault as the core holds it, so the
  /// card is whole with its message and no client asks for more), and, decided here, how it went before its station
  /// says so (`status`, `scope`). Any other card as it is.
  #vaultCard(card: J, ws: string): J {
    const one = vaultAskOf(card);
    if (one === null) return card;
    const shown: J = { ...card.vaultAsk, ...(this.#core.vaultAnswers?.(ws, [one])[0] ?? {}) };
    const done = this.local.vaultOutcome(one.request);
    if (done !== undefined && shown.status === undefined) {
      shown.status = done.status;
      if (done.scope !== undefined) shown.scope = done.scope;
    }
    return { ...card, vaultAsk: shown };
  }

  /// The vault requests view `view` shows on `cards` (each in its workspace): kept while it shows any.
  #vaultSeen(view: Topic, cards: [string, J][]): void {
    const key = topicKey(view);
    const asks = cards.flatMap(([ws, card]) => {
      const ask = vaultAskOf(card);
      return ask === null ? [] : [{ ws, ask }];
    });
    if (asks.length === 0 || !this.#views.has(key)) this.#vaultShown.delete(key);
    else this.#vaultShown.set(key, { topic: view, asks, said: this.#vaultSaid(asks) });
  }

  /// A chat's view (`out`) with its messages' vault cards answered (`#vaultCard`).
  #vaultCards<V extends Value | undefined>(view: Topic, out: V): V {
    if (out === undefined || !("ok" in out) || !isObject(out.ok) || !Array.isArray(out.ok.messages)) {
      this.#vaultSeen(view, []);
      return out;
    }
    const ws = ofAddress(String(view.station ?? ""));
    const cards = (out.ok.messages as J[]).flatMap((m): [string, J][] => (isObject(m) && vaultAskOf(get(m, "card")) !== null ? [[ws, m.card]] : []));
    this.#vaultSeen(view, cards);
    if (cards.length === 0) return out;
    const messages = (out.ok.messages as J[]).map((m) => (isObject(m) && vaultAskOf(get(m, "card")) !== null ? { ...m, card: this.#vaultCard(m.card, ws) } : m));
    return { ...out, ok: { ...(out.ok as J), messages } } as V;
  }

  #live(): Topic[] {
    return [...this.#views.values()].map((v) => v.topic);
  }

  #invalidate(pick: (view: Topic) => boolean): void {
    for (const view of this.#live()) if (pick(view)) this.#core.store.invalidate(view);
  }

  #localChanged(change: LocalChange): void {
    switch (change.kind) {
      case "outbox":
        for (const view of this.chatViews(change.station, change.thread)) this.#core.store.invalidate(view);
        if (change.chat) return;
        // A card answered from here waits no more; a message that did not go marks its chat's row.
        this.#invalidate((v) => v.topic === "workspaceMarks" || v.topic === "chats" || v.topic === "chatSearch" || v.topic === "search");
        return;
      case "pending":
        this.#invalidate((v) => (v.topic === "chat" && v.thread === null && v.session === change.key) || v.topic === "chats" || v.topic === "chatSearch" || v.topic === "search");
        return;
      case "first":
        this.#invalidate((v) => v.topic === "chat" && v.station === change.station && v.thread === null && v.session === change.key);
        return;
      case "archiving":
        this.#invalidate((v) => v.topic === "chats" || v.topic === "workspaceMarks");
        return;
      case "letGo":
        // (the chat says it let go at once: its end's line, the asks)
        for (const view of this.chatViews(change.station, change.thread)) this.#core.store.invalidate(view);
        return;
      case "vault": {
        const showing = [...this.#vaultShown.values()].filter((s) => s.asks.some((a) => a.ask.request === change.request)).map((s) => topicKey(s.topic));
        this.#invalidate((v) => showing.includes(topicKey(v)));
        return;
      }
      case "changing":
        this.#invalidate((v) => ["chats", "chatSearch", "search", "archive", "workspaceMarks"].includes(v.topic) || (v.topic === "chat" && v.station === change.station));
        return;
    }
  }

  /// The live pages showing a chat: by its thread, or by its agent once the chat is the agent's.
  chatViews(station: string, thread: number): Topic[] {
    return this.#live().filter((view) => {
      if (view.topic !== "chat" || view.station !== station) return false;
      if (view.thread === thread) return true;
      if (view.thread !== null || typeof view.session !== "string") return false;
      if (view.session.startsWith(PENDING_PREFIX)) return this.local.pendingThread(station, view.session) === thread;
      return this.boundThread(station, view.session) === thread;
    });
  }

  /// A tree shown from an older reading was read again in the background: show its current reading in the views that
  /// used it. The things page also keeps what it drew until its entries change.
  mdChanged(station: string, of: string): void {
    if (of.startsWith("t:")) {
      const thread = Number(of.slice(2));
      this.#thingsKept.delete(`${station}/${thread}`);
      for (const view of this.chatViews(station, thread)) this.#core.store.invalidate(view);
      this.#invalidate((v) => v.station === station && v.thread === thread && ["chatLetters", "chatThings", "imageNear"].includes(v.topic));
    } else if (of.startsWith("s:")) {
      const key = of.slice(2);
      this.#invalidate((v) => v.station === station && ((v.topic === "history" && v.key === key) || (v.topic === "chat" && v.thread === null && v.session === key)));
    }
  }

  /// A message on its way to a chat: shown in it at once, as `sending`; `after` is the chat's newest entry now.
  outboxAdd(station: string, thread: number, message: J): string {
    const after = u64(get(this.ok({ topic: "thread", station, thread }), "last")) ?? 0;
    return this.local.outboxAdd(station, thread, message, after);
  }

  /// The station has the message as entry `seq` (see Local.outboxSent).
  outboxSent(station: string, thread: number, id: string, seq: number): void {
    this.local.outboxSent(station, thread, id, seq, this.chatViews(station, thread).length > 0);
  }

  updateNoticeOpen(station: string, open: boolean): void {
    if (open) this.#updateNoticesOpen.add(station);
    else this.#updateNoticesOpen.delete(station);
    this.#invalidate((v) => v.topic === "chat" && v.station === station);
  }

  /// Watches what the view needs now and lets go of the rest.
  #sync(view: Topic): void {
    const live = this.#views.get(topicKey(view));
    if (!live) return;
    const wanted = new Map(this.#sources(view).map((t) => [topicKey(t), t] as [string, Topic]));
    for (const [key, w] of [...live.watches]) {
      if (!wanted.has(key)) {
        live.watches.delete(key);
        w.drop();
      }
    }
    for (const [key, topic] of wanted) {
      if (live.watches.has(key)) continue;
      const watch = this.#core.store.watch(topic, () => this.#core.store.invalidate(view));
      // Released meanwhile (a watch's start can stop the view).
      if (this.#views.get(topicKey(view)) !== live) {
        watch.drop();
        return;
      }
      live.watches.set(key, watch);
    }
  }

  /// The topics a view is built from, given what is known now.
  #sources(view: Topic): Topic[] {
    const topics: Topic[] = [];
    const station = typeof view.station === "string" ? view.station : "";
    // (and its station's screens, for its bar's way to them)
    if (view.topic === "chat") topics.push({ topic: "prefs" }, { topic: "screens", station });
    let scope: string;
    let perStation: (station: string) => Topic[];
    switch (view.topic) {
      case "chats":
      case "chatSearch":
        scope = (view.scope ?? view.workspace) as string;
        perStation = (s) => [{ topic: "chatRows", station: s }, { topic: "overview", station: s }, { topic: "link", station: s }];
        break;
      case "search": {
        scope = view.scope as string;
        // With words, what each station finds (views/search.ts).
        const typed = String(view.query ?? "").trim() !== "";
        perStation = (s) => [{ topic: "chatRows", station: s }, { topic: "overview", station: s }, { topic: "link", station: s }, ...(typed ? [stationTopic(s, view)] : [])];
        break;
      }
      case "stations":
      case "profiles":
      case "settings":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "link", station: s }, { topic: "overview", station: s }, { topic: "host", station: s }, { topic: "way", station: s }];
        break;
      case "archive":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "archivedRows", station: s }];
        break;
      case "longJobs":
        scope = view.scope as string;
        // With the sidebar rows of the stations whose chats run tasks there (`#ranFrom`).
        perStation = (s) => [
          { topic: "jobs", station: s },
          ...arr(this.ok({ topic: "jobs", station: s })).flatMap((j) => {
            const owner = jobs.remoteOwner(str(get(j, "session")) ?? "");
            return owner === null ? [] : [{ topic: "chatRows", station: owner.station }];
          }),
        ];
        break;
      case "usage":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "stationUsage", station: s }];
        break;
      case "fleet":
        // (the card shared of the agents at work: views/fleet.ts)
        scope = view.scope as string;
        perStation = (s) => [{ topic: "chatRows", station: s }, { topic: "archivedRows", station: s }, { topic: "jobs", station: s }, { topic: "overview", station: s }, { topic: "link", station: s }, { topic: "host", station: s }, { topic: "way", station: s }, { topic: "stationUsage", station: s }];
        break;
      case "railCard": {
        // (the cards over the rail's places: views/rail-cards.ts) what the place's card is made of
        scope = view.scope as string;
        const place = view.place;
        perStation = (s) => [
          { topic: "chatRows", station: s },
          { topic: "overview", station: s },
          { topic: "link", station: s },
          ...(place === "chats" ? [{ topic: "archivedRows", station: s }] : []),
          ...(place === "usage" ? [{ topic: "stationUsage", station: s }] : []),
        ];
        if (place === "chats") topics.push({ topic: "prefs" }, { topic: "workspaces" });
        break;
      }
      case "resources":
        scope = view.scope as string;
        // One station's (its page's 进程), or every station's.
        perStation = (s) => (view.station === undefined || view.station === s ? [{ topic: "stationResources", station: s }] : []);
        break;
      case "connects":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "overview", station: s }, { topic: "sessions", station: s }, { topic: "threads", station: s }];
        break;
      case "chatJobs":
        return [{ topic: "chat", station, thread: view.thread ?? null, session: view.session ?? null }];
      // (an image of a chat steps through all of its, as far as it is on the device: its `letters`, all its entries)
      case "imageNear":
        return [
          { topic: "chat", station, thread: view.thread ?? null, session: view.session ?? null },
          ...(typeof view.thread === "number" ? [{ topic: "letters", station, thread: view.thread }] : []),
        ];
      // (and each pull request's card, for its title and how it stands)
      case "chatThings":
        return [
          { topic: "chat", station, thread: view.thread, session: null },
          { topic: "letters", station, thread: view.thread },
          { topic: "workspace", workspace: ofAddress(station) },
          ...(this.#things(station, view.thread as number)?.things.pulls ?? []).map((p): Topic => ({ topic: "linkPreview", station, url: p.url! })),
        ];
      case "chatLetters":
        return [
          { topic: "chat", station, thread: view.thread, session: null },
          { topic: "letters", station, thread: view.thread },
          { topic: "workspace", workspace: ofAddress(station) },
        ];
      case "workspaceMarks":
        return this.#marksSources();
      // (what `/v1/me` says, as the workspaces list is made from it)
      case "workspaceWays":
        return [{ topic: "workspaces" }];
      case "agentCard":
        return [
          { topic: "live", station, key: view.key },
          { topic: "session", station, key: view.key },
          { topic: "sessions", station },
          { topic: "chatRows", station },
          { topic: "overview", station },
          { topic: "workspace", workspace: ofAddress(station) },
        ];
      case "stationNet":
        return [{ topic: "net", station }];
      case "history":
        return [
          { topic: "live", station, key: view.key },
          { topic: "session", station, key: view.key },
          { topic: "overview", station },
          { topic: "workspace", workspace: ofAddress(station) },
        ];
      case "chat": {
        const session = typeof view.session === "string" ? view.session : null;
        if (view.thread === null && session !== null && session.startsWith(PENDING_PREFIX)) {
          topics.push({ topic: "overview", station });
          const thread = this.local.pendingThread(station, session);
          if (typeof thread === "number") return this.#sources({ topic: "chat", station, thread, session: null });
          topics.push({ topic: "link", station }, { topic: "workspace", workspace: ofAddress(station) });
          return topics;
        }
        if (view.thread === null && session !== null) {
          const bound = this.boundThread(station, session);
          if (bound !== null) return this.#sources({ topic: "chat", station, thread: bound, session: null });
        }
        if (view.thread === null) {
          if (session !== null) topics.push({ topic: "session", station, key: session });
          topics.push(
            { topic: "threads", station },
            { topic: "chatRows", station },
            { topic: "sessions", station },
            { topic: "overview", station },
            { topic: "link", station },
            { topic: "workspace", workspace: ofAddress(station) },
          );
          return topics;
        }
        const thread = view.thread as number;
        const kept = () => {
          const t0 = get(this.ok({ topic: "thread", station, thread }), "thread");
          return isObject(t0) ? t0 : null;
        };
        for (const key of members(this.threadOf(station, thread) ?? kept())) topics.push({ topic: "session", station, key });
        topics.push(
          { topic: "threads", station },
          { topic: "sessions", station },
          { topic: "thread", station, thread },
          { topic: "chatRows", station },
          { topic: "overview", station },
          { topic: "link", station },
          { topic: "workspace", workspace: ofAddress(station) },
          // Its sharing names the viewer's other workspaces.
          { topic: "workspaces" },
        );
        // The chats its messages link to, as their stations' lists have them (#linkedChats, each its row alone). Not the
        // archive: shown, a station's archive is read from it whole (sync.ts archivedShown), its thousands of rows the
        // most of opening a chat with a link in it (0.63 s on a phone, 2026-10-31); one archived meanwhile is said so
        // as the chat is made again.
        for (const s of this.#linkedStations(station, arr(get(this.ok({ topic: "thread", station, thread }), "entries")))) {
          if (s !== station) topics.push({ topic: "chatRows", station: s });
        }
        return topics;
      }
      default:
        if (view.topic.startsWith("admin")) return adminSources(view);
        return topics;
    }
    if (view.topic === "chats" || view.topic === "longJobs") topics.push({ topic: "prefs" });
    topics.push({ topic: "workspace", workspace: scope });
    if (view.topic === "stations") topics.push({ topic: "workspaces" });
    for (const s of this.stations(scope) ?? []) {
      topics.push({ topic: "link", station: s.address });
      if (s.online) topics.push(...perStation(s.address));
    }
    // The `@` menu's other workspaces (`elsewhere`): their chats too, once something is typed.
    if (view.topic === "chatSearch" && view.elsewhere === true && String(view.query ?? "").trim() !== "") {
      topics.push({ topic: "workspaces" });
      for (const place of this.#core.places?.() ?? []) {
        if (place.id === scope) continue;
        topics.push({ topic: "workspace", workspace: place.id });
        for (const s of this.stations(place.id) ?? []) {
          topics.push({ topic: "link", station: s.address });
          if (s.online) topics.push(...perStation(s.address));
        }
      }
    }
    return topics;
  }

  // ── what the views read ──

  /// Whether a workspace's notices are heard of on this device.
  heard(workspace: string): boolean {
    return this.#core.heard?.(workspace) ?? true;
  }

  ok(topic: Topic): J {
    const v = this.#core.store.value(topic);
    return v && "ok" in v ? v.ok : undefined;
  }

  value(topic: Topic): Value | undefined {
    return this.#core.store.value(topic);
  }

  /// The scope's stations; undefined until the workspace has been read (an error: none to show).
  stations(scope: string): StationInfo[] | undefined {
    const v = this.value({ topic: "workspace", workspace: scope });
    if (v === undefined || !("ok" in v)) return v === undefined ? undefined : [];
    return arr(get(v.ok, "stations")).flatMap((s) => {
      const id = str(get(s, "id"));
      if (id === null) return [];
      const address = `${scope}/${id}`;
      return [{ address, id, name: str(get(s, "name")) ?? id, emoji: str(get(s, "emoji")) || null, icon: str(get(s, "icon")) || null, online: !down(this.link(address)), lastSeen: get(s, "last_seen") ?? null, version: get(s, "version") ?? null, joined: get(s, "joined") === true }];
    });
  }

  #stationsOr(scope: string): StationInfo[] | Value | undefined {
    const v = this.value({ topic: "workspace", workspace: scope });
    if (v === undefined) return undefined;
    if ("err" in v) return v;
    return this.stations(scope);
  }

  /// The stations whose chats what was said in a chat on `station` links to (its entries' words): its own, and those of
  /// the viewer's workspaces online.
  #linkedStations(station: string, entries: J[]): string[] {
    const out: string[] = [];
    for (const e of entries) {
      const text = str(get(e, "text")) ?? "";
      if (!text.includes("/chats/") && !text.includes("/o/")) continue;
      for (const c of chatsLinked(text, station)) {
        if (out.includes(c.station)) continue;
        if (c.station === station || (this.stations(ofAddress(c.station)) ?? []).some((s) => s.address === c.station && s.online)) out.push(c.station);
      }
    }
    return out;
  }

  /// The chats `text`, said in a chat on `station`, links to, as their stations' lists have them: each found its link,
  /// its title as its row says it, and whether it is archived (archivedRows), said so. One no list has is left out.
  /// Each its row alone, read where it is kept: a station's whole lists, its archive's thousands of rows, read for a
  /// link were most of what opening a chat that has one took (0.65-0.83 s on a phone, 2026-10-31).
  #linkedChats(station: string, text: string): J[] {
    if (!text.includes("/chats/") && !text.includes("/o/")) return [];
    return chatsLinked(text, station).flatMap((c) => {
      const found = this.#core.data.chatNamed(c.station, c.id);
      if (found === undefined || (found.archived && !isObject(get(found.row, "archived")))) return [];
      const row = found.row as J;
      return [{ href: c.href, title: str(get(row, "title")) || t("core-views.new_chat"), ...(found.archived ? { archived: true, note: t("core-views.search.archived") } : {}) }];
    });
  }

  /// Who is looking: the account that reaches the workspace.
  me(scope: string): J {
    const email = this.#core.emailOf(scope);
    return { id: email, email };
  }

  #betaOf(scope: string): boolean {
    return this.#core.betaOf(scope);
  }

  relayName(host: string): string | null {
    return this.#core.relayName(host);
  }

  /// The rows of these stations that ask something of their person or are unread (views/marks.ts).
  marked(stations: string[]): [string, J][] {
    return this.#core.data.marked(stations);
  }

  /// The chat an agent's item has: the still.fail chat bound to it, as the station's items say, or its threads do.
  boundThread(station: string, key: string): number | null {
    const fromRows = u64(get(this.#core.data.chatOfSession(station, key), "thread"));
    if (fromRows !== null) return fromRows;
    return this.#core.data.threadOf(station, key);
  }

  /// A thread among the station's (null when it lists none such, or its threads were never read).
  threadOf(station: string, id: number): J {
    const data = this.#core.data;
    if (typeof id !== "number") return null;
    return data.listed(station, "threads") ? (data.listedThread(station, id) ?? null) : null;
  }

  /// The station's link as `{ state, message, last, retrying }`.
  link(station: string): J {
    const v = this.value({ topic: "link", station });
    if (v === undefined) return { state: "connecting", message: null };
    if ("err" in v) return { state: "error", message: v.err.message };
    const cause = get(v.ok, "cause");
    const catching = get(v.ok, "catching");
    return { state: get(v.ok, "state") ?? "connecting", message: get(v.ok, "message") ?? null, last: get(v.ok, "last") ?? null, ...(get(v.ok, "retrying") === true ? { retrying: true } : {}), ...(typeof cause === "string" ? { cause } : {}), ...(typeof catching === "number" ? { catching } : {}) };
  }

  #clock(): present.Clock {
    const now = this.#core.host.nowMs();
    return { now, offsetMin: this.#core.host.utcOffsetMin(now) };
  }

  /// The names of a workspace's stations by id (none until the workspace has been read).
  stationNames(scope: string): Map<string, string> {
    return new Map((this.stations(scope) ?? []).map((s) => [s.id, s.name]));
  }

  /// A station's name as its workspace has it, else its id.
  stationName(station: string): string {
    const at = station.indexOf("/");
    if (at < 0) return "";
    const found = this.stations(station.slice(0, at))?.find((s) => s.address === station);
    return found ? found.name : station.slice(at + 1);
  }

  /// Whether a station is offline, as its workspace says.
  offline(station: string): boolean {
    const at = station.indexOf("/");
    if (at < 0) return false;
    return this.stations(station.slice(0, at))?.find((s) => s.address === station)?.online === false;
  }

  /// A station's sidebar row of a thread or an agent, as changes from here have it; undefined while the station's rows
  /// were never read (null: none such).
  #row(station: string, by: { thread: number } | { session: string }): J | null | undefined {
    const data = this.#core.data;
    if (!data.listed(station, "chats")) return undefined;
    this.local.settle(station, data.rowsRev(station));
    const raw = "thread" in by ? data.chatOfThread(station, by.thread) : data.chat(station, by.session);
    return raw === undefined ? null : this.local.asChanging(station, raw);
  }

  // ── computing ──

  /// Whether a view with no value yet waits on a station for what it shows (store.ts `waits`): a chat whose messages it
  /// opens with are not on the device. Not what it is built from but not computed yet this turn (that comes as soon as
  /// it is): the device is asked, not the thread's topic.
  waits(view: Topic): boolean {
    if (view.topic !== "chat" || typeof view.station !== "string") return false;
    const station = view.station;
    let thread: number | null = typeof view.thread === "number" ? view.thread : null;
    const session = typeof view.session === "string" ? view.session : null;
    if (thread === null && session !== null) {
      const pending = session.startsWith(PENDING_PREFIX) ? this.local.pendingThread(station, session) : this.boundThread(station, session);
      thread = typeof pending === "number" ? pending : null;
    }
    return thread !== null && this.#core.waits?.({ topic: "thread", station, thread }) === true;
  }

  compute(view: Topic): Value | undefined {
    if (!this.#views.has(topicKey(view))) return undefined;
    timed(`${view.topic}.sources`, () => this.#sync(view));
    const out = timed(`${view.topic}.make`, () => this.#compute(view));
    if (view.topic !== "chat" || out === undefined || !("ok" in out)) return out;
    const v = out.ok as J;
    const station = view.station as string;
    if (isObject(v.link)) v.connection = looks.linkShown(v.link, this.stationName(station));
    const overview = this.ok({ topic: "overview", station });
    const prefs = this.ok({ topic: "prefs" }) ?? null;
    const workspace = this.ok({ topic: "workspace", workspace: ofAddress(station) }) ?? null;
    const role = get(workspace, "role");
    const manager = role === "owner" || role === "admin";
    // Its side panel's tabs, as kept on this device for it by its page's key (chat-tabs.ts).
    const session = typeof view.thread === "number" ? null : typeof view.session === "string" ? view.session : null;
    const kept = get(get(prefs, "chatTabs"), `${station}:${session ?? view.thread}`);
    v.tabs = chatTabs.tabsOf(kept, arr(v.agents), v.noChat === true, session);
    const dismissed = get(get(prefs, "stationUpdatesDismissed"), station);
    v.stationUpdate = looks.stationUpdate(overview, v, typeof dismissed === "string" ? dismissed : null, this.#updateNoticesOpen.has(station), manager, this.stationName(station));
    if (Array.isArray(v.outbox)) v.outbox = looks.outboxWaits(v.outbox, v.stationUpdate);
    // The screens of the machine it runs on, a press away from its bar: its own display first (screens.ts screensView),
    // each marked while an agent drives it.
    const screens = arr(get(this.ok({ topic: "screens", station }), "screens")).map((s) => ({ id: s.id, kind: s.kind, title: s.title, line: s.line, ...(s.agent === true ? { agent: true } : {}) }));
    if (screens.length > 0) v.screens = screens;
    if (v.offline === true) {
      v.offlineNote = looks.offlineNote(v.link, this.stationName(station));
      if (get(v.link, "cause") === "updating") v.updating = true;
      if (Array.isArray(v.outbox)) v.outbox = looks.outboxHeld(v.outbox);
    }
    // Its agent's prompt cache over: said over the composer, computed again as the next one's is over.
    const context = get(overview, "context");
    const above = get(context, "afreshAbove");
    const [cold, coldIn] = v.archived === true ? [null, Infinity] : brief.cacheCold(v.agents, this.#core.host.nowMs(), get(context, "afreshWhenCold") === true, typeof above === "number" ? above : undefined);
    if (cold !== null) v.cacheCold = cold;
    this.#againIn(view, coldIn);
    // Its sharing with the viewer's other workspaces, as asked here meanwhile.
    const shared = xshare.shown({ places: this.#core.places?.() ?? [], asked: (session) => this.#core.xshareAsked?.(station, session), me: str(get(v.me, "email")) }, station, v.thread);
    if (shared !== null) v.xshare = shared;
    // Its public snapshots, without those being revoked here meanwhile.
    const published = publish.shown({ me: str(get(v.me, "email")), role: typeof role === "string" ? role : null, members: arr(get(workspace, "members")), revoking: (id) => this.#core.revoking?.(station, id) === true }, station, v.thread);
    if (published !== null) v.publish = published;
    return out;
  }

  #compute(view: Topic): Value | undefined {
    switch (view.topic) {
      case "chats":
        return this.#chats(view.scope as string, view.mine === true, view.watching === true);
      case "search": {
        const chats = this.#chats(view.scope as string, false, false);
        if (chats === undefined || !("ok" in chats)) return chats;
        return searchView(this.#searchSource, chats.ok, view);
      }
      case "chatSearch": {
        const chats = this.#chats(view.scope as string, false, false);
        if (chats === undefined || !("ok" in chats)) return chats;
        const elsewhere = view.elsewhere === true && String(view.query ?? "").trim() !== "";
        const found = refs.search(chats.ok, view.query as string, view.station as string | undefined, view.exclude as string | undefined, elsewhere ? undefined : (view.limit as number | undefined));
        // With something typed (`elsewhere`, the `@` menu), those of the viewer's other workspaces whose title has it
        // too, each saying whose, ranked so as not to crowd this workspace's (refs.ts withOutside).
        if (elsewhere) {
          const others: J[] = [];
          for (const place of this.#core.places?.() ?? []) {
            if (place.id === view.scope) continue;
            const theirs = this.#chats(place.id, false, false);
            if (theirs === undefined || !("ok" in theirs)) continue;
            for (const item of arr(refs.search(theirs.ok, view.query as string, undefined, undefined, undefined).items)) others.push({ ...item, outside: place.name, ...xshare.markOf(place, "outside") });
          }
          found.items = refs.withOutside(arr(found.items), others, view.query as string, view.scope as string, view.limit as number | undefined);
        }
        if (typeof view.messages === "number" && view.messages > 0) {
          found.messages = this.#foundMessages(chats.ok, view);
          found.words = refs.terms(view.query as string);
        }
        return { ok: found };
      }
      case "stations": {
        // Asked with `drive`: those with a drive, this machine's (`here`) first (drive-browse.ts withDrive).
        const stations = this.#stationsView(view.scope as string, view);
        if (view.drive !== true || stations === undefined || !("ok" in stations)) return stations;
        return { ok: withDrive(stations.ok as J[], typeof view.here === "string" ? view.here : null) };
      }
      case "profiles": {
        const stations = this.#stationsView(view.scope as string);
        if (stations === undefined || !("ok" in stations)) return stations;
        return { ok: workspaceProfiles(stations.ok as J[]) };
      }
      case "settings": {
        const stations = this.#stationsView(view.scope as string);
        if (stations === undefined || !("ok" in stations)) return stations;
        return { ok: settingsView(stations.ok as J[]) };
      }
      case "connects":
        return this.#connects(view.scope as string, view.mine === true);
      case "chat": {
        const station = view.station as string;
        // (its agents' Markdown read once on the device: kept by the chat it is read for)
        const draw = <V extends Value | undefined>(out: V) => {
          const thread = out !== undefined && "ok" in out ? u64(get(get(out.ok, "thread"), "id")) : null;
          const of = thread !== null ? `t:${thread}` : typeof view.thread === "number" ? `t:${view.thread}` : `s:${String(view.session ?? "")}`;
          const held = (session: string, name: string) => this.#core.data.hasKeptFile(station, session, name, "thumb") || this.#core.data.hasKeptFile(station, session, name, "poster");
          const shown = timed("chat.draw", () => drawn(out, (path) => this.local.uploadOf(station, path), this.#core.data.mdStore(station, of), (text) => timed("chat.links", () => this.#linkedChats(station, text)), held));
          return timed("chat.vault", () => this.#vaultCards(view, shown));
        };
        if (typeof view.thread === "number") return draw(this.#chat(station, view.thread));
        const session = typeof view.session === "string" ? view.session : null;
        if (session === null) return { err: CoreError.invalid(t("core-views.error.chat_needs_thread")) };
        if (session.startsWith(PENDING_PREFIX)) return draw(this.#pendingChat(station, session) ?? { err: new CoreError("http_404", t("core-views.error.no_chat"), 404) });
        const bound = this.boundThread(station, session);
        const out = bound !== null ? this.#chat(station, bound) : this.#unchatted(station, session);
        const waiting = this.local.firstOutbox(station, session);
        if (waiting.length === 0 || out === undefined || !("ok" in out)) return draw(out);
        const v = out.ok as J;
        if (Array.isArray(v.outbox)) v.outbox.push(...waiting);
        return draw(out);
      }
      case "chatLetters":
        return this.#chatLetters(view.station as string, view.thread as number);
      case "chatThings":
        return this.#chatThings(view.station as string, view.thread as number, typeof view.q === "string" ? view.q : "");
      case "history":
        return this.#history(view.station as string, view.key as string);
      case "stationNet": {
        // A station's connection with every figure, sampled while this is shown (station/topics.ts).
        const net = this.ok({ topic: "net", station: view.station as string });
        return { ok: net === undefined ? null : present.net(net, (h) => this.relayName(h)) };
      }
      case "agentCard": {
        const agent = this.agent(view.station as string, view.key as string);
        if (agent === null) return undefined;
        const live = this.value({ topic: "live", station: view.station as string, key: view.key as string });
        return { ok: brief.card(agent, live !== undefined && "ok" in live ? live.ok : null, this.stationNames(ofAddress(view.station as string))) };
      }
      case "archive":
        return archive(this, this.local, view.scope as string, this.#core.host, typeof view.q === "string" ? view.q : "", typeof view.limit === "number" ? view.limit : 0);
      case "workspaceMarks":
        return marks.marks(this, this.local, typeof view.workspace === "string" ? view.workspace : null);
      case "chatJobs": {
        const chat = this.value({ topic: "chat", station: view.station, thread: view.thread ?? null, session: view.session ?? null });
        if (chat === undefined || !("ok" in chat)) return chat;
        const [value, next] = jobs.chatJobs(chat.ok, this.#clock());
        this.#againIn(view, next);
        return { ok: value };
      }
      case "imageNear": {
        const chat = this.value({ topic: "chat", station: view.station, thread: view.thread ?? null, session: view.session ?? null });
        if (chat === undefined || !("ok" in chat)) return chat;
        // All of the chat's held, where it has a thread (its page holds a window of it); the outbox's after them.
        const whole = typeof view.thread === "number" ? this.#things(view.station as string, view.thread) : null;
        return { ok: near(whole === null ? chat.ok : { messages: whole.messages, outbox: get(chat.ok, "outbox") }, view.path as string) };
      }
      case "workspaceWays": {
        const ways = this.#core.ways?.(view.workspace as string);
        return ways === undefined ? undefined : { ok: ways };
      }
      case "adminList":
      case "adminItem":
      case "adminOverview":
      case "adminRelays": {
        const now = this.#core.host.nowMs();
        return admin(view, (account, list) => this.value({ topic: "admin", account, list }), now, this.#core.host.utcOffsetMin(now));
      }
      case "usage": {
        const scope = view.scope as string;
        const stations = this.#stationsOr(scope);
        if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
        const sources = stations.map((s) => ({ address: s.address, name: s.name, online: s.online, value: s.online ? this.value({ topic: "stationUsage", station: s.address }) : undefined }));
        const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
        const now = this.#core.host.nowMs();
        return { ok: usageView(sources, typeof view.days === "number" ? view.days : 7, now, this.#core.host.utcOffsetMin(now), this.me(scope), members_) };
      }
      case "fleet": {
        const scope = view.scope as string;
        const stations = this.#stationsOr(scope);
        if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
        // what they did over the last 7 days, as the usage page has it
        const sources = stations.map((s) => ({ address: s.address, name: s.name, online: s.online, value: s.online ? this.value({ topic: "stationUsage", station: s.address }) : undefined }));
        const now = this.#core.host.nowMs();
        const usage = usageView(sources, 7, now, this.#core.host.utcOffsetMin(now), this.me(scope), arr(get(this.ok({ topic: "workspace", workspace: scope }), "members")));
        // the subscriptions, as the profiles page lists them
        const listed = this.#stationsView(scope);
        const profiles = listed !== undefined && "ok" in listed ? arr(get(workspaceProfiles(listed.ok as J[]), "items")) : [];
        // the chats at work, when each archived one was archived (as the archive has it: views/archive.ts), the jobs (the
        // tasks other stations' chats run there now), the tasks they ran there before
        const read = stations.map((s) => {
          const rows = this.value({ topic: "chatRows", station: s.address });
          const archived = this.value({ topic: "archivedRows", station: s.address });
          const at = (chat: J) => get(get(chat, "archived"), "at") ?? get(chat, "lastActiveAt");
          return {
            station: s.address,
            online: s.online && !down(this.link(s.address)),
            rows: rows && "ok" in rows ? arr(rows.ok) : [],
            archived: archived && "ok" in archived ? arr(archived.ok).filter((c) => isObject(get(c, "archived"))).map(at).filter((x): x is number => typeof x === "number") : [],
            jobs: arr(this.ok({ topic: "jobs", station: s.address })),
            // the tasks other stations' chats ran here, as its usage says them (a station from before says none)
            runs: arr(get(this.ok({ topic: "stationUsage", station: s.address }), "remoteRuns"))
              .filter((r) => typeof get(r, "at") === "number" && typeof get(r, "session") === "string")
              .map((r) => ({ at: get(r, "at") as number, session: get(r, "session") as string })),
            // its chats' calls, by day, chat, profile and model, as the usage page reads them
            calls: arr(get(this.ok({ topic: "stationUsage", station: s.address }), "rows")),
          };
        });
        const offset = this.#core.host.utcOffsetMin(now);
        return { ok: fleetView(read, profiles, usage, now, offset) };
      }
      case "railCard": {
        const scope = view.scope as string;
        const chats = this.#chats(scope, false, false);
        if (chats === undefined || !("ok" in chats)) return chats;
        const now = this.#core.host.nowMs();
        const offset = this.#core.host.utcOffsetMin(now);
        const online = (this.stations(scope) ?? []).filter((s) => s.online);
        switch (view.place) {
          case "chats": {
            const rows = arr(get(chats.ok, "days")).flatMap((d) => arr(get(d, "items")));
            const mark = get(get(get(marks.marks(this, this.local, scope), "ok"), "workspaces"), scope);
            // when each archived chat was, as the archive has it (views/archive.ts)
            const archived = online.flatMap((s) =>
              arr(this.ok({ topic: "archivedRows", station: s.address }))
                .filter((c) => isObject(get(c, "archived")))
                .map((c) => get(get(c, "archived"), "at") ?? get(c, "lastActiveAt"))
                .filter((x): x is number => typeof x === "number"),
            );
            return { ok: chatsCard(rows, mark, archived, now, offset) };
          }
          case "usage": {
            const stations = this.#stationsOr(scope);
            if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
            const sources = stations.map((s) => ({ address: s.address, name: s.name, online: s.online, value: s.online ? this.value({ topic: "stationUsage", station: s.address }) : undefined }));
            return { ok: usageCard(usageView(sources, 7, now, offset, this.me(scope), arr(get(this.ok({ topic: "workspace", workspace: scope }), "members")))) };
          }
        }
        return undefined;
      }
      case "resources": {
        const stations = this.#stationsOr(view.scope as string);
        if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
        const sources = stations.filter((s) => view.station === undefined || s.address === view.station)
          .map((s) => ({ address: s.address, name: s.name, online: s.online, value: s.online ? this.value({ topic: "stationResources", station: s.address }) : undefined }));
        return { ok: resourcesView(sources, this.#core.host.nowMs(), looks.waitNote) };
      }
      case "longJobs": {
        const stations = this.#stationsOr(view.scope as string);
        if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
        const several = stations.length > 1;
        const open = stations.filter((s) => s.online).map((s) => [s.address, several ? s.name : null, arr(this.ok({ topic: "jobs", station: s.address }))] as [string, string | null, J[]]);
        const prefs = this.ok({ topic: "prefs" }) ?? null;
        const bell = { on: badgeKindsOf(prefs).services, seen: jobsSeenOf(prefs, view.scope as string) };
        return { ok: jobs.longJobs(open, this.#clock(), (session) => this.#ranFrom(stations, session), bell) };
      }
    }
    return undefined;
  }

  /// The chat on another of the scope's stations a task here runs for (`jobs.remoteOwner`), as that station's sidebar
  /// has it: the session's own chat over one it only takes part in (as the station names its own jobs' chats).
  #ranFrom(stations: StationInfo[], session: string): jobs.From | null {
    const owner = jobs.remoteOwner(session);
    const station = owner && stations.find((s) => s.address === owner.station);
    if (!owner || !station) return null;
    const rows = arr(this.ok({ topic: "chatRows", station: station.address }));
    const row = rows.find((r) => get(r, "session") === owner.session) ??
      rows.find((r) => arr(get(r, "agents")).some((a) => get(a, "key") === owner.session));
    const id = str(get(row, "id"));
    return { name: station.name, chat: id === null ? null : { id, title: str(get(row, "title")), archived: false, station: station.address } };
  }

  /// Has a view computed again in `ms` (the timer set last is the one that counts).
  #againIn(view: Topic, ms: number): void {
    const key = topicKey(view);
    const before = this.#again.get(key);
    if (before) {
      this.#core.runner.interrupt(before);
      this.#again.delete(key);
    }
    if (!Number.isFinite(ms)) return;
    const fiber = this.#core.runner.fork(
      Effect.sleep(Math.ceil(ms)).pipe(
        Effect.andThen(
          Effect.sync(() => {
            this.#again.delete(key);
            this.#core.store.invalidate(view);
          }),
        ),
      ),
    );
    this.#again.set(key, fiber as Fiber.Fiber<unknown, unknown>);
  }

  // ── the chat list ──

  #chats(scope: string, mine: boolean, watching: boolean): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const data = this.#core.data;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const hint = archiveHintOf(this.ok({ topic: "prefs" }) ?? null);
    const states: J[] = [];
    const troubles: [string, string, boolean, string][] = [];
    const rows: J[] = [];
    let loading = false;
    const unread: string[] = [];
    // Catching up on what changed while away (station/sync.ts `#catching`): whether a station has yet to say what, and
    // how many chats are left to bring the latest of.
    let checking = false;
    let behind = 0;
    // The first screen first (docs/core-db.md): while the stations' rows are not loaded, and they are more than a list
    // shows on top, those are read by one query, and the rest are loaded after, a station at a time.
    const known = stations.filter((s) => data.listed(s.address, "chats")).map((s) => s.address);
    const unloaded = known.filter((s) => !data.loaded({ topic: "chatRows", station: s }));
    const head = unloaded.length > 0 && data.chatCount(unloaded) > HEAD ? this.#head(scope, known) : null;
    for (const s of stations) {
      const read = head !== null && data.listed(s.address, "chats") ? ({ ok: head.get(s.address) ?? [] } as Value) : this.value({ topic: "chatRows", station: s.address });
      if (!(read && "ok" in read)) unread.push(s.address);
      if (read && "ok" in read) {
        const slackUsers = arr(get(this.ok({ topic: "overview", station: s.address }), "slackUsers")).filter((u): u is string => typeof u === "string");
        this.local.settle(s.address, data.rowsRev(s.address));
        const listed = arr(read.ok);
        const asked = this.local.pendingRows(s.address);
        // What a row is made with besides its record: a row whose record and these are as they were is the one made
        // before (rule 7: the list redoes only the rows that changed).
        const link = this.link(s.address);
        // Its station's emoji and icon only with several stations (with one, it says nothing).
        const mark = stations.length > 1 ? { emoji: s.emoji, icon: s.icon } : null;
        const sig = JSON.stringify([s.address, s.name, mark, s.online, link.state ?? null, link.cause ?? null, me, slackUsers, members_, watching, hint]);
        for (const raw of [...asked, ...listed]) {
          if (mine && get(raw, "mine") !== true) continue;
          if (this.local.beingArchived(s.address, raw)) continue;
          const shown = this.local.asChanging(s.address, raw);
          // Only a frozen row (db/account.ts) is surely as it was when its row was made.
          const keepable = isObject(shown) && Object.isFrozen(shown);
          const kept = keepable ? this.#rowsMade.get(shown) : undefined;
          let row: J;
          if (kept && kept.sig === sig) row = kept.row;
          else {
            row = this.#chatRow(s, shown, me, slackUsers, members_, watching, mark, hint);
            // Frozen all through: a row made once and shared from then on (output.ts takes it as it is).
            if (row !== null) deepFreeze(row);
            if (keepable) this.#rowsMade.set(shown, { sig, row });
          }
          if (row !== null) rows.push(this.#unsentRow(s.address, row));
        }
      }
      let state: string;
      let message: J = null;
      if (!s.online) state = "offline";
      else {
        const link = this.link(s.address);
        const linkState = str(link.state) ?? "connecting";
        if (read && "err" in read) [state, message] = ["error", read.err.message];
        else if (read && "ok" in read) {
          if (linkState === "error") [state, message] = ["error", link.message];
          else if (linkState === "reconnecting") [state, message] = ["connecting", link.message];
          else state = "online";
        } else {
          loading = true;
          if (linkState === "error") [state, message] = ["error", link.message];
          else state = "connecting";
        }
      }
      if (s.online) {
        const link = this.link(s.address);
        const catching = typeof link.catching === "number" ? (link.catching as number) : null;
        if (link.state === "connecting" && link.retrying !== true) checking = true;
        else if (link.state === "online" && catching !== null) {
          if (catching < 0) checking = true;
          else behind += catching;
        }
      }
      if (state === "offline") troubles.push(["offline", downWords(this.link(s.address), s.name), get(this.link(s.address), "cause") === "network", s.address]);
      else if (state === "error") troubles.push(["error", t("core-views.station.unreachable", { name: s.name }), false, s.address]);
      else if (state === "connecting" && read && "ok" in read) troubles.push(["reconnecting", t("core-views.station.reconnecting", { name: s.name }), false, s.address]);
      const cause = state === "offline" ? get(this.link(s.address), "cause") : undefined;
      // Refused for a security mode: why.
      if (cause === "lock") message = get(this.link(s.address), "message") ?? null;
      const now = looks.doing(state, cause, this.ok({ topic: "overview", station: s.address }));
      states.push({ station: s.address, id: s.id, name: s.name, state, message, ...(typeof cause === "string" ? { cause } : {}), ...now });
    }
    const days = this.#days(rows);
    let trouble: J = null;
    if (troubles.length === 1) trouble = { text: troubles[0][1], state: troubles[0][0], retry: false, station: troubles[0][3] };
    else if (troubles.length > 1) {
      const worst = ["error", "offline", "reconnecting"].find((w) => troubles.some(([s]) => s === w)) ?? "offline";
      // Every one down as the device's network is: that, once, and not as so many stations amiss.
      const network = troubles.every(([, , n]) => n === true);
      trouble = { text: network ? t("core-views.station.network") : t("core-views.station.troubles", { n: troubles.length }), state: worst, retry: false };
    }
    const glyph = looks.glyph(states, days);
    const note = looks.listNote(states, days, loading, unread);
    const ws = this.ok({ topic: "workspace", workspace: scope });
    const count = Array.isArray(get(ws, "members")) ? ws.members.length : null;
    // (one station still to say: how many are left is not known yet)
    const syncing = checking ? t("core-views.station.syncing") : behind > 0 ? t("core-views.station.syncing_left", { n: behind }) : null;
    return { ok: { me, stations: states, loading, days, trouble, members: count, leading: "agents", glyph, note, ...(syncing !== null ? { syncing } : {}) } };
  }

  /// The rows a scope's list shows on top (HEAD of them), by station, while its stations' rows load: one is loaded
  /// after another, the list computed again after each.
  /// The messages a search's words find in the chats the sidebar lists (those `refs.search` would list, by the same
  /// station and exclusion), newest first, at most `view.messages`: each with its chat's row, who said it and its line.
  /// What the search (views/search.ts) reads of the views.
  readonly #searchSource: SearchSource = {
    value: (topic) => this.value(topic),
    ok: (topic) => this.ok(topic),
    stations: (scope) => this.stations(scope),
    foundMessages: (chats, view) => this.#foundMessages(chats, view),
    me: (scope) => this.me(scope),
    clock: () => this.#clock(),
  };

  #foundMessages(chats: J, view: Topic): J[] {
    const words = refs.terms(view.query as string);
    if (words.length === 0) return [];
    const scope = view.scope as string;
    const rows = new Map<string, J>();
    for (const item of arr(get(chats, "days")).flatMap((d) => arr(get(d, "items")))) {
      if (get(item, "pending") === true || typeof item.thread !== "number") continue;
      if (typeof view.station === "string" && item.station !== view.station) continue;
      if (typeof view.exclude === "string" && (item.id === view.exclude || item.session === view.exclude)) continue;
      rows.set(`${item.station}\u0001${item.thread}`, item);
    }
    const stations = [...new Set([...rows.values()].map((i) => i.station as string))];
    const wanted = view.messages as number;
    const data = this.#core.data;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const clock = this.#clock();
    const out: J[] = [];
    // Those of chats not listed (archived) are passed over: some more are asked for.
    for (const hit of data.findSaid(stations, words, wanted * 3)) {
      const chat = rows.get(`${hit.station}\u0001${hit.thread}`);
      if (!chat) continue;
      const entry = data.logRange("entry", hit.station, String(hit.thread), hit.seq, hit.seq).get(hit.seq);
      const slackUsers = arr(get(this.ok({ topic: "overview", station: hit.station }), "slackUsers")).filter((u): u is string => typeof u === "string");
      const by = isObject(entry) ? present.lastBy({ last: entry, agents: chat.agents }, me, slackUsers, members_) : null;
      const message: J = { station: hit.station, thread: hit.thread, seq: hit.seq, by: str(get(by, "name")) ?? "", ...refs.excerpt(hit.text, words) };
      if (hit.at !== null) message.createdAt = hit.at;
      // Its chat's row as the list made it (frozen, its times in words already).
      out.push({ chat, ...(present.times(message, clock) as J) });
      if (out.length >= wanted) break;
    }
    return out;
  }

  #head(scope: string, stations: string[]): Map<string, J[]> {
    const data = this.#core.data;
    const out = new Map<string, J[]>();
    for (const [station, row] of data.chatHead(stations, HEAD)) out.set(station, [...(out.get(station) ?? []), row]);
    if (!this.#loading.has(scope)) {
      this.#loading.add(scope);
      this.#core.runner.fork(
        Effect.gen({ self: this }, function* () {
          for (const station of stations) {
            yield* Effect.yieldNow;
            data.shared({ topic: "chatRows", station });
          }
          this.#loading.delete(scope);
          this.#invalidate((v) => (v.topic === "chats" || v.topic === "chatSearch" || v.topic === "search") && v.scope === scope);
        }),
      );
    }
    return out;
  }

  /// A station's row as the list shows it (null: not in this list).
  #chatRow(s: StationInfo, raw: J, me: J, slackUsers: string[], members_: J[], watching: boolean, mark: { emoji: string | null; icon: string | null } | null, hint: ArchiveHint): J {
    let row = structuredClone(raw);
    // Pinned rows are pinned (true) in the list, in the order they were pinned in (pinnedAt, below); one unpinned says
    // false.
    if (row.pinned !== undefined) row.pinned = typeof row.pinned === "number";
    row.station = s.address;
    row.stationName = s.name;
    // A chat made here keeps the key it was asked for by (its page still open by it) as long as this device keeps it:
    // its station says it only a while (CLIENT_KEY_KEPT_MS), and the row and that page are one chat all along.
    if (typeof row.clientKey !== "string" && typeof row.session === "string") {
      const key = this.local.pendingKey(s.address, row.session);
      if (key !== undefined) row.clientKey = key;
    }
    if (mark?.emoji) row.stationEmoji = mark.emoji;
    if (mark?.icon) row.stationIcon = mark.icon;
    if (!s.online) row.offline = downWords(this.link(s.address), s.name);
    else {
      const state = str(this.link(s.address).state) ?? "connecting";
      if (state === "error") row.reconnecting = t("core-views.station.retrying", { name: s.name });
      else if (state === "reconnecting") row.reconnecting = t("core-views.station.reconnecting_now", { name: s.name });
    }
    const agents = arr(row.agents);
    const watch = present.rowWatch(agents);
    if (watch !== null) row.watch = watch;
    else if (watching) return null;
    row.state = present.rowState(agents);
    if (Array.isArray(row.agents)) row.agents = row.agents.map((agent: J) => present.session(agent));
    if (row.connect !== undefined && row.connect !== null) {
      const o = row.origin ?? null;
      const text = (k: string) => (typeof get(o, k) === "string" && o[k] !== "" ? (o[k] as string) : null);
      const channelName = text("channelName");
      // A Feishu chat's: its group by name, no #.
      const feishu = text("surface")?.startsWith("feishu:") === true || format.isFeishuChat(text("channel") ?? "");
      const place = feishu ? channelName : channelName !== null ? `#${channelName}` : text("channel")?.startsWith("D") ? t("core-views.direct_message") : null;
      row.originKind = feishu ? "feishu" : "slack";
      row.originText = [feishu ? t("core-views.feishu") : "Slack", text("teamName"), place].filter((x) => x !== null).join(" · ");
    }
    if (isObject(row.last)) {
      const text = format.cleanText(format.plainText(str(row.last.text) ?? ""));
      row.last.preview = text === "" ? t("core-views.file") : text;
    }
    Object.assign(row, present.rowPeople(row, me, slackUsers, members_));
    const by = present.lastBy(row, me, slackUsers, members_);
    if (by !== null) {
      row.last.by = by;
      const name = str(by.name) ?? "";
      by.label = typeof by.state === "string" ? t("core-views.by_label", { name, state: present.badgeText(by.state) }) : name;
      by.maker = present.maker(str(by.model));
    }
    row = decisions.presentRow(row);
    // Archived with one tap whenever nothing is left in it; offered to archive (faded, below the rest of its day) as the
    // viewer's `archiveHint` says.
    if (row.archiveReminderDismissed === true) row.kept = true;
    if (present.archivable(row)) {
      row.archivable = true;
      if (present.offered(row, hint)) row.settled = true;
    }
    // Swiped away by a finger whenever it has ended: unread, pinned, kept or not recommended by its station's review
    // alike (the swipe is the viewer's own say, nothing offered), its station there to take it.
    if (present.ended(row) && row.offline === undefined) row.swipeArchive = true;
    const line = present.rowStateLine(row);
    if (line !== null) {
      row.stateText = line[0];
      if (line[1] !== null) row.stateAbout = line[1];
      const lead = line[3];
      if (lead !== null) {
        row.stateLead = lead.kind;
        if (lead.text !== undefined) row.stateLeadText = lead.text;
        row.stateRest = lead.rest;
      }
    }
    // Gone for its update: said on its second line, in place of where its agents were as it went (what one needs of the
    // viewer kept), as it is back by itself in a while (2026-10-29: only its unplugged mark said it was away, not why).
    if (!s.online && get(this.link(s.address), "cause") === "updating") {
      row.updating = true;
      if (row.stateLead !== "need") {
        row.stateText = row.offline;
        for (const k of ["stateLead", "stateLeadText", "stateRest", "stateAbout"]) delete row[k];
      }
    }
    const opener = this.#opener(s.address, raw);
    if (opener !== null) row.opener = opener;
    else delete row.opener;
    if (typeof raw.pinned === "number") pinnedAt.set(row, raw.pinned);
    return row;
  }

  /// The chats a chat's agent opened (its station's row's `opened`), as their lists have them: each on its station, titled
  /// as its row is (else as it was given), where it stands as its row's second line says it (what it needs of the viewer,
  /// a card, done), its mark; one in its station's archive said so. The first opened first.
  #opened(station: string, raw: J): J[] {
    return arr(get(raw, "opened")).flatMap((o) => {
      const session = str(get(o, "session"));
      if (session === null) return [];
      const there = str(get(o, "station"));
      const at = there !== null && there !== "" ? `${ofAddress(station)}/${there}` : station;
      const found = this.#core.data.chatNamed(at, session);
      const row = found?.row as J | undefined;
      const title = str(get(row, "title")) || str(get(o, "title")) || t("core-views.new_chat");
      const out: J = { station: at, session, title };
      if (isObject(row)) {
        const agents = arr(row.agents);
        const mark = present.rowState(agents);
        if (mark !== null) out.mark = mark;
        const shown = decisions.presentRow({ ...structuredClone(row), agents: agents.map((a: J) => present.session(a)) });
        const line = present.rowStateLine(shown);
        if (line !== null) {
          out.stateText = line[0];
          if (line[3] !== null) out.stateLead = line[3].kind;
        }
      }
      if (found?.archived === true) {
        out.archived = true;
        out.note = t("core-views.search.archived");
      }
      return [out];
    });
  }

  /// The chat an agent opened a row's chat from (its station's `opener`), as its list has it: on its station (the row's
  /// own when the station names none), titled as its row is, else as it was called then; one in its archive is said
  /// so. Null for a chat a person started.
  #opener(station: string, raw: J): J | null {
    const o = get(raw, "opener");
    const session = str(get(o, "session"));
    if (session === null) return null;
    const there = str(get(o, "station"));
    const at = there !== null && there !== "" ? `${ofAddress(station)}/${there}` : station;
    const found = this.#core.data.chatNamed(at, session);
    const title = str(get(found?.row, "title")) || str(get(o, "title")) || t("core-views.new_chat");
    return { station: at, session, title, text: t("core-views.opener", { title }), ...(found?.archived === true ? { archived: true, note: t("core-views.search.archived") } : {}) };
  }

  /// A row whose chat has a message sent here that did not go: marked red, its second line saying which (`unsent`: drawn
  /// in red), before
  /// anything its agents do (the message waits in the chat to be sent again or dropped).
  #unsentRow(station: string, row: J): J {
    const thread = typeof row.thread === "number" ? row.thread : null;
    const unsent = this.local.unsent(station, thread, row.pending === true && typeof row.clientKey === "string" ? row.clientKey : null);
    if (unsent === undefined) return row;
    const text = format.cleanText(format.plainText(str(unsent.text) ?? ""));
    const { stateAbout: _stateAbout, stateLead: _stateLead, stateLeadText: _stateLeadText, stateRest: _stateRest, ...rest } = row;
    const marked: J = { ...rest, tone: "alert", unsent: true, stateText: t("core-views.unsent", { text: text === "" ? t("core-views.file") : text }) };
    deepFreeze(marked);
    const pinned = pinnedAt.get(row);
    if (pinned !== undefined) pinnedAt.set(marked, pinned);
    return marked;
  }

  /// Rows newest first, grouped by the viewer's local calendar day; the pinned above them all.
  #days(rows: J[]): J[] {
    const host = this.#core.host;
    const at = (row: J) => (typeof row.lastActiveAt === "number" ? row.lastActiveAt : 0);
    const pinned = rows.filter((row) => pinnedAt.has(row));
    const rest = rows.filter((row) => !pinnedAt.has(row));
    const when = (row: J) => pinnedAt.get(row) ?? 0;
    pinned.sort((a, b) => when(b) - when(a) || at(b) - at(a));
    const day = (ms: number) => Math.floor((ms + host.utcOffsetMin(ms) * 60_000) / DAY_MS);
    const settled = (row: J) => (row.settled === true ? 1 : 0);
    rest.sort((a, b) => day(at(b)) - day(at(a)) || settled(a) - settled(b) || at(b) - at(a));
    const now = host.nowMs();
    const today = day(now);
    const days: [number, number, J[]][] = [];
    for (const row of rest) {
      const d = day(at(row));
      const last = days[days.length - 1];
      if (last && last[0] === d) last[2].push(row);
      else days.push([d, at(row), [row]]);
    }
    const offset = host.utcOffsetMin(now);
    const out: J[] = [];
    if (pinned.length > 0) out.push({ daysAgo: -1, at: at(pinned[0]), label: t("core-views.pinned"), pinned: true, items: pinned });
    for (const [d, ti, items] of days) out.push({ daysAgo: today - d, at: ti, label: format.dayLabel(ti, now, offset), items });
    return out;
  }

  // ── stations and connects ──

  /// `view`: the topic asking, computed again when one of its stations has been silent long enough to say so.
  #stationsView(scope: string, view?: Topic): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const c = this.#clock();
    let silentNext = Infinity;
    const items = stations.map((s) => {
      const overview = this.ok({ topic: "overview", station: s.address });
      const hostRaw = this.ok({ topic: "host", station: s.address });
      const { host, shown } = this.#stationParts(s.address, overview, hostRaw, c);
      let summary: string;
      const cause = get(this.link(s.address), "cause");
      if (!s.online && cause === "updating") summary = t("core-views.station.updating_short");
      else if (!s.online && cause === "network") summary = t("core-views.station.network");
      else if (!s.online && cause === "unreached") summary = t("core-views.station.unreachable_short");
      else if (!s.online && cause === "lock") summary = t("core-views.station.lock_short");
      else if (!s.online) {
        summary = typeof s.lastSeen === "number" ? t("core-views.station.offline_since", { ago: format.relativeTime(s.lastSeen * 1000, c.now, c.offsetMin) }) : t("core-views.station.offline_short");
      } else if (host !== null) {
        const running = u64(get(get(overview, "counts"), "running")) ?? 0;
        const what = str(host.identity) || str(host.os) || "";
        // What its agents do first: a narrow card cuts the line short at its end.
        summary = `${running > 0 ? t("core-views.station.running", { n: running }) : t("core-views.station.idle")} · ${what}`;
      } else summary = t("core-views.station.connecting");
      // How it is reached alone, not its figures (they change with each reading: the `stationNet` view has them).
      const way = this.ok({ topic: "way", station: s.address });
      const state = str(this.link(s.address).state);
      // Up without a host reading for SILENT_MS: said to be silent (the cloud says it is up, nothing answers).
      let silent = false;
      if (s.online && host === null) {
        const since = this.#hostless.get(s.address) ?? c.now;
        this.#hostless.set(s.address, since);
        silent = c.now - since >= SILENT_MS;
        if (!silent) silentNext = Math.min(silentNext, since + SILENT_MS - c.now);
      } else this.#hostless.delete(s.address);
      const blocked = !s.online && cause === "lock" && typeof get(this.link(s.address), "message") === "string" ? (get(this.link(s.address), "message") as string) : null;
      const running = u64(get(get(overview, "counts"), "running")) ?? 0;
      return {
        station: s.address,
        id: s.id,
        name: s.name,
        ...(s.emoji ? { emoji: s.emoji } : {}),
        ...(s.icon ? { icon: s.icon } : {}),
        summary,
        face: looks.face(s.online, overview),
        line: !s.online && cause === "lock" ? t("core-views.station.lock_short") : looks.stationLine(s.online, host),
        online: s.online,
        reconnecting: s.online && state !== "online" && state !== "error",
        ...stationState(s.online, blocked !== null || cause === "updating", summary, typeof s.lastSeen === "number" ? s.lastSeen : null, overview !== undefined, running, c),
        problems: stationProblems(s.online, silent, blocked, typeof s.lastSeen === "number", cause === "updating"),
        // Down for a security mode: why, in place of the page's 离线 words.
        ...(blocked !== null ? { blocked } : {}),
        lastSeen: s.lastSeen,
        version: s.version,
        link: this.link(s.address),
        // What this workspace's chats run on: the profiles open to it.
        runtimes: runtimes(overview !== undefined ? servingIn(overview, scope, s.joined === true) : overview),
        models: models(overview !== undefined ? servingIn(overview, scope, s.joined === true) : overview, c.now),
        overview: shown,
        host,
        way: way === undefined ? null : present.way(way, (h) => this.relayName(h)),
        betaOffered: betaOffered(overview, () => this.#betaOf(scope)),
        ...(s.joined ? { joined: true, home: this.#core.homeName?.(scope, s.id) ?? null } : {}),
      };
    });
    if (view !== undefined) this.#againIn(view, silentNext);
    return { ok: items };
  }

  /// A station's host reading and overview as its list's item shows them: made once for each the station said (and each
  /// minute, for the overview's times in words), shared after (`shaped`: never changed, not copied or shaped again as
  /// they go out).
  #stationParts(station: string, overview: J, hostRaw: J, c: present.Clock): { host: J; shown: J } {
    const minute = Math.floor(c.now / 60_000);
    let kept = this.#stationShown.get(station);
    if (!kept || kept.overview !== overview || kept.minute !== minute) {
      const shown = overview === undefined ? null : asShaped("Overview", present.decorate({ topic: "overview", station }, structuredClone(overview), c));
      kept = { overview, minute, shown, host: kept?.host, presented: kept?.presented ?? null };
      this.#stationShown.set(station, kept);
    }
    if (kept.host !== hostRaw || kept.presented === undefined) {
      const presented = hostRaw === undefined ? null : asShaped("Host", present.host(hostRaw));
      kept.host = hostRaw;
      kept.presented = presented;
    }
    return { host: kept.presented, shown: kept.shown };
  }

  #connects(scope: string, mine: boolean): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const items: J[] = [];
    const waiting: string[] = [];
    const failing: { station: string; name: string; message: string }[] = [];
    for (const s of stations.filter((s) => s.online)) {
      const v = this.value({ topic: "overview", station: s.address });
      if (v === undefined) {
        waiting.push(s.name);
        continue;
      }
      if ("err" in v) {
        failing.push({ station: s.address, name: s.name, message: v.err.message });
        continue;
      }
      const sessions = arr(this.ok({ topic: "sessions", station: s.address }));
      const threads = arr(this.ok({ topic: "threads", station: s.address }));
      const connects = arr(get(v.ok, "connects"));
      for (const connect of connects) {
        const id = get(get(connect, "createdBy"), "id");
        const creator = id !== undefined ? { id, email: id } : null;
        if (mine && !isMine(me, creator)) continue;
        const shown = present.connect(connect);
        if (shown.createdBy !== undefined) shown.createdBy = present.person(shown.createdBy, me, members_);
        items.push({ station: s.address, stationName: s.name, connect: shown, ...connectSessions(connect, connects, sessions, threads, this.#clock()) });
      }
    }
    return { ok: { me, items, wait: looks.waitNote(waiting, failing, items.length === 0) } };
  }

  // ── a chat ──

  #chat(station: string, id: number): Value | undefined {
    const pageV = this.value({ topic: "thread", station, thread: id });
    if (pageV === undefined) return undefined;
    if ("err" in pageV) return pageV;
    const page = pageV.ok as J;
    let thread: J;
    const data = this.#core.data;
    if (data.listed(station, "threads")) {
      const found = data.listedThread(station, id);
      if (found === undefined) return { err: new CoreError("http_404", t("core-views.error.no_chat"), 404) };
      thread = structuredClone(found);
    } else {
      const threadsV = this.value({ topic: "threads", station });
      if (threadsV !== undefined && "err" in threadsV) return threadsV;
      if (!isObject(page.thread)) return undefined;
      thread = structuredClone(page.thread);
    }
    const agents = timed("chat.agents", () => this.#agentsOf(station, thread));
    // What two chats' agents wrote each other is not said in it: it has a page of its own (`chatLetters`).
    const keys = new Set(members(thread));
    const all: J[] = merge(arr(page.entries));
    const said = all.filter((m) => !isLetter(m, keys));
    const letters = Math.max(u64(get(thread, "letters")) ?? 0, all.length - said.length);
    const { scope, viewer, members_, bots } = this.#peopleOf(station, agents);
    const waiting = agents.reduce((max, a) => Math.max(max, u64(get(a.session, "pending")) ?? 0), 0);
    const peopleSeqs = said.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [m.seq as number] : []));
    const waits = peopleSeqs.slice(Math.max(peopleSeqs.length - waiting, 0));
    const written = said.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [[m.seq as number, str(m.text) ?? ""] as [number, string]] : []));
    let messages = timed("chat.shown", () => this.#shown(station, thread, agents, said, waits));
    // A sent message leaves the outbox as its own entry (or anything later) arrives; before the station answered
    // with its seq, it is the viewer's first message since it was sent with the same words.
    const newest = u64(page.last);
    const mine = written.filter(([seq]) => messages.some((m) => m.seq === seq && m.mine === true));
    let past = 0;
    const list = this.local.outbox(station, id).map((m) => ({ ...m }));
    const kept: J[] = [];
    for (const m of list) {
      // Queued messages have not reached the station; equal text cannot acknowledge them.
      if (m.queued || m.uploads?.length) { kept.push(m); continue; }
      const seq = u64(m.seq);
      if (seq !== null) {
        past = Math.max(past, seq);
        const arrived = newest !== null && newest >= seq;
        if (arrived) this.local.remember(station, id, seq, String(m.id));
        else kept.push(m);
        continue;
      }
      const after = Math.max(u64(m.after) ?? 0, past);
      m.after = after;
      const text = str(m.text) ?? "";
      const found = mine.find(([s, said]) => s > after && said === text);
      if (found) {
        past = found[0];
        this.local.remember(station, id, found[0], String(m.id));
      } else kept.push(m);
    }
    this.local.outboxSettle(station, id, kept);
    const outbox = structuredClone(kept);
    for (const m of messages) {
      const seq = u64(m.seq);
      if (seq === null) continue;
      const outgoing = this.local.outgoing(station, id, seq);
      if (outgoing !== undefined) m.outgoing = outgoing;
    }
    const people = (Array.isArray(thread.people) ? thread.people : []).map((p: J) => present.person(p, viewer, members_));
    if (Array.isArray(thread.people)) thread.people = people;
    if (thread.creator !== undefined) thread.creator = present.person(thread.creator, viewer, members_);
    const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
    const { place, slackUrl, slackApp, feishuUrl } = this.#whereIn(station, agents, strOf(thread, "surface"), strOf(thread, "channel"), strOf(thread, "channelName"), strOf(thread, "threadTs"));
    // (a Slack thread's agents with no chat of their own here are listed by their session alone, its row's thread null)
    let found = this.#row(station, { thread: id });
    for (const key of found === null ? members(thread) : []) {
      const alone = this.#row(station, { session: key });
      if (alone !== null && alone !== undefined && alone.thread === null) {
        found = alone;
        break;
      }
    }
    // what is asked here, let go from here (忽略): said let go at once, as its station will say it (back if refused)
    const asking = found !== undefined && found !== null ? decisions.asked(found) : null;
    const lettingGo = found !== undefined && found !== null && asking !== null && this.local.lettingGo(station, id, u64(asking.seq) ?? -1);
    const row = lettingGo ? decisions.withLetGo(found) : (found ?? undefined);
    const open = (d: J) => !this.local.answered(station, id, u64(d.seq) ?? 0);
    let pendingCard: [number, boolean] | null | undefined;
    if (found !== undefined) {
      const d = row !== undefined ? decisions.ofRow(row) : null;
      pendingCard = d !== null && open(d) ? [u64(d.seq) ?? 0, decisions.dismissed(d)] : null;
    }
    messages.splice(0, messages.length, ...decisions.inMessages(messages, pendingCard, outbox.filter((m) => m.state !== "failed")));
    const elsewhere = timed("chat.elsewhere", () => this.#sentElsewhere(station, thread, agents, messages, u64(page.first) !== null && page.first > 1, page.end === false, { members: members_, bots }));
    const title = row !== undefined && row.title !== undefined ? row.title : typeof page.title === "string" ? page.title : chatTitle(thread);
    const view: J = {
      me: this.me(scope),
      place,
      slackUrl,
      ...(slackApp !== null ? { slackApp } : {}),
      ...(feishuUrl !== null ? { feishuUrl } : {}),
      title,
      people,
      agents,
      messages,
      elsewhere,
      more: u64(page.first) !== null && page.first > 1,
      newer: page.end === false,
      firstEntry: u64(page.first),
      lastEntry: u64(page.last),
      at: page.at ?? null,
      atOffset: page.atOffset ?? null,
      caught: page.caught ?? null,
      outbox,
      link: this.link(station),
      offline: this.offline(station),
      thread,
      archived: thread.hiddenAt !== undefined && thread.hiddenAt !== null,
    };
    const archived = this.local.archivedChanging(station, id, null);
    if (archived !== null) view.archived = archived;
    if (row !== undefined && row.pinned !== undefined) view.pinned = typeof row.pinned === "number";
    const opener = row !== undefined ? this.#opener(station, row) : null;
    if (opener !== null) view.opener = opener;
    // the chats it opened, each where it stands, for its bar's list of them
    const opened = row !== undefined ? this.#opened(station, row) : [];
    if (opened.length > 0) {
      view.opened = opened;
      view.openedText = t("core-views.opened", { n: opened.length });
    }
    const sessions = arr(view.agents).flatMap((a) => (a.session !== undefined ? [a.session] : []));
    const watch = present.rowWatch(sessions);
    if (watch !== null) view.watch = watch;
    const card = row !== undefined ? decisions.ofRow(row) : null;
    if (card !== null && open(card)) view.decision = decisions.shown(card);
    if (row !== undefined && present.archivable(row) && view.archived !== true) view.archivable = true;
    // Where it stands, as its row's second line says it (what an agent needs, why it stopped, what it waits on, done):
    // said at the end of its messages too. A card waiting is not: it shows in the chat itself; nor what an agent waits
    // on: its activity under the messages says it, with how long it has waited.
    const shown = row !== undefined && Array.isArray(row.agents) ? { ...row, agents: row.agents.map((a: J) => present.session(a)) } : null;
    const line = shown !== null ? present.rowStateLine(shown, false) : null;
    // What it needed of a person, let go by the viewer (忽略): kept, said as let go, in place of what its row says
    const letGo = shown !== null ? present.rowLetGoNeed(shown) : null;
    if (letGo !== null) {
      view.stateText = t("core-logic.decisions.dismissedNeed", { text: letGo });
      view.stateLead = "dismissed";
      view.stateRest = letGo;
    } else if (line !== null && line[3]?.kind !== "wait") {
      view.stateText = line[0];
      const lead = line[3];
      if (lead !== null) {
        view.stateLead = lead.kind;
        view.stateRest = lead.rest;
      }
    }
    // What is asked here and not decided yet (a card, or an agent needing a person): the page leads to each. A card is
    // let go under its post (`asked`), with its options; an agent's need where the chat's end says what it needs
    // (`stateAsk`), the reminder the viewer reads, else under the post that asks.
    view.asks = row !== undefined && view.archived !== true
      ? decisions.undecided(row).filter((d) => u64(d.seq) !== null && open(d)).map((d) => decisions.askOf(row, d, view.me))
      : [];
    for (const ask of view.asks) {
      if (!ask.card && view.stateLead === "need") {
        view.stateAsk = ask.seq;
        continue;
      }
      const m = messages.find((x) => u64(get(x, "seq")) === ask.seq);
      if (isObject(m)) (m as J).asked = true;
    }
    // The bell to what waits floats over the list's end only while that is out of view there: one at the end itself
    // (the line saying what an agent needs, or the last post with nothing after it) shows whenever the end does, so
    // the end keeps clear of the bell only for another. Else a need coming in would push the chat up for nothing.
    const lastSeq = messages.length > 0 ? u64(get(messages[messages.length - 1], "seq")) : null;
    const atEnd = (seq: number) => view.newer !== true && (seq === view.stateAsk || (seq === lastSeq && arr(outbox).length === 0 && view.stateText === undefined));
    if (view.asks.some((a: J) => !atEnd(a.seq))) view.askClear = true;
    if (letters > 0) view.letters = letters;
    // Its Slack and Feishu threads, where what is sent can be copied (`chat.cc`), each ticked or not.
    const ccTo = arr(get(thread, "cc")).flatMap((o) => {
      const to = u64(get(o, "thread"));
      const place = placeName(strOf(o, "surface"), strOf(o, "channel"), strOf(o, "channelName"));
      if (to === null || place === null) return [];
      const via = strOf(o, "surface").startsWith("feishu:") || format.isFeishuChat(strOf(o, "channel")) ? "feishu" : "slack";
      return [{ thread: to, place, via, on: this.ccOn(station, id, to) }];
    });
    if (ccTo.length > 0) view.cc = ccTo;
    return { ok: view };
  }

  /// A chat's agents: those its thread names that are known.
  #agentsOf(station: string, thread: J): J[] {
    return members(thread).flatMap((key) => {
      const a = this.agent(station, key);
      return a === null ? [] : [a];
    });
  }

  /// Who a chat's messages are told apart by: the viewer, its workspace's members, the Slack names a mention may be.
  #peopleOf(station: string, agents: J[]): { scope: string; viewer: J; slackUsers: string[]; members_: J[]; bots: [string, string][] } {
    const scope = ofAddress(station);
    const viewer = this.me(scope);
    const slackUsers = arr(get(this.ok({ topic: "overview", station }), "slackUsers")).filter((u): u is string => typeof u === "string");
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const bots = agents.flatMap((a) => {
      const b = a.connect !== undefined ? present.botOf(a.connect) : null;
      return b === null ? [] : [b];
    }).concat(this.#core.data.slackNames(station));
    return { scope, viewer, slackUsers, members_, bots };
  }

  /// A chat's messages (`said`: its entries merged, letters left out) as its page shows each (shownMessage): the
  /// viewer's those with seqs in `waits` still waiting for its agents; a notice that a runtime is not installed with
  /// installing it, as the station's updates have it now (or under the viewer's message that waits for it); a failure
  /// notice one to report where the station takes bug reports.
  #shown(station: string, thread: J, agents: J[], said: J[], waits: number[]): J[] {
    const { scope, viewer, slackUsers, members_, bots } = this.#peopleOf(station, agents);
    const updates = arr(get(this.ok({ topic: "overview", station }), "updates"));
    const role = get(this.ok({ topic: "workspace", workspace: scope }), "role");
    const manages = role === "owner" || role === "admin";
    const reports = get(this.ok({ topic: "overview", station }), "feedback") === true;
    const messages = said.map((raw) => {
      const m = shownMessage(raw, agents, viewer, slackUsers, members_, bots, thread.creator);
      const out: J = { ...m, waiting: u64(m.seq) !== null && waits.includes(m.seq) };
      const install = m.system === true && typeof m.runtime === "string" ? present.installView(m.runtime, updates, manages) : null;
      if (install !== null) out.install = install;
      else if (reports && m.system === true && u64(m.seq) !== null && (str(m.text) ?? "").startsWith("⚠️")) out.reportable = true;
      return out;
    });
    return blockedUnder(messages);
  }

  /// Chat `id`'s messages as its page draws them (`ChatView.messages`), from `entries` as its station reads them (GET
  /// /threads/:id/entries): a picture of the chat draws them as its list does (publish.ts). Nothing of the page's own
  /// is in them: none waits, nothing is on its way, nothing is asked.
  listed(station: string, id: number, entries: unknown[]): J[] {
    const thread = this.#core.data.listedThread(station, id) ?? get(this.ok({ topic: "thread", station, thread: id }), "thread") ?? {};
    const agents = this.#agentsOf(station, thread);
    const keys = new Set(members(thread));
    const messages = decisions.inMessages(this.#shown(station, thread, agents, merge(entries).filter((m) => !isLetter(m, keys)), []), null);
    const out = drawn({ ok: { agents, messages } }, (path) => this.local.uploadOf(station, path), this.#core.data.mdStore(station, `t:${id}`));
    const ws = ofAddress(station);
    return arr(get(out.ok, "messages")).map((m) => (isObject(m) && vaultAskOf(get(m, "card")) !== null ? { ...m, card: this.#vaultCard(m.card, ws) } : m));
  }

  /// Whether what is sent to a chat from here is copied to its Slack or Feishu thread `to` (`chat.cc`): off until ticked,
  /// for as long as the app runs.
  ccOn(station: string, thread: number, to: number): boolean {
    return this.#cc.has(`${station} ${thread} ${to}`);
  }

  /// The threads what is sent to a chat from here is copied to now.
  ccTo(station: string, thread: number): number[] {
    const prefix = `${station} ${thread} `;
    return [...this.#cc].filter((k) => k.startsWith(prefix)).map((k) => Number(k.slice(prefix.length)));
  }

  /// Copying to a chat's thread `to` ticked or not: its pages show it.
  setCc(station: string, thread: number, to: number, on: boolean): void {
    const key = `${station} ${thread} ${to}`;
    if (on === this.#cc.has(key)) return;
    if (on) this.#cc.add(key);
    else this.#cc.delete(key);
    for (const view of this.chatViews(station, thread)) this.#core.store.invalidate(view);
  }


  /// What a chat's agents and other chats' wrote each other (`chatLetters`), all of it as far as it is on the device
  /// (`whole` once all is): by the other chat, as lettersByChat has them, each named as the chat's page names its
  /// messages, with the chat's title.
  #chatLetters(station: string, id: number): Value | undefined {
    const chat = this.value({ topic: "chat", station, thread: id, session: null });
    if (chat === undefined || "err" in chat) return chat;
    const held = this.value({ topic: "letters", station, thread: id });
    if (held === undefined || "err" in held) return held;
    const view = chat.ok as J;
    const thread = view.thread as J;
    const keys = new Set(members(thread));
    const agents = arr(view.agents);
    const scope = ofAddress(station);
    const viewer = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    // Those kept as entries before letters had their own log, and those of it (`letters`), in the order written.
    const written = [...merge(arr(get(held.ok, "entries"))).filter((m) => isLetter(m, keys)), ...merge(arr(get(held.ok, "letters")))];
    const at = (m: J) => u64(m.createdAt) ?? 0;
    written.sort((a, b) => at(a) - at(b));
    const letters = written.flatMap((m) => {
      if (!isLetter(m, keys)) return [];
      const l = letterWay(m);
      const shown: J = { ...shownMessage({ ...m, text: letterWords(str(m.text) ?? "") }, agents, viewer, [], members_, [], thread.creator), waiting: false };
      // Coming in: by the agent of the chat it came from, named by that chat.
      if (l.way === "in") shown.by = { name: t("core-views.letters.their", { chat: l.title }), from: l.link, maker: get(shown.by, "maker") ?? null };
      return [{ message: shown, ...l }];
    });
    // Each chat's letters drawn as the chat's page draws its messages (their Markdown, their files).
    const chats = lettersByChat(letters).map((c) => {
      const out = drawn({ ok: { agents, messages: c.letters } }, (path) => this.local.uploadOf(station, path), this.#core.data.mdStore(station, `t:${id}`));
      return { ...c, letters: arr(get(out.ok, "messages")) };
    });
    return { ok: { title: view.title, chats, whole: get(held.ok, "whole") === true } };
  }

  /// A chat's messages as far as they are on the device (its `letters` topic: all its entries held), those that say
  /// something besides words (a file, a web link) drawn as its page draws them (`drawn`), and its things read from them
  /// (things.ts); kept while neither its entries nor its agents change. Null until its chat and its entries are read.
  #things(station: string, id: number): { messages: J[]; things: ReturnType<typeof thingsOf>; whole: boolean; title: unknown } | null {
    const chat = this.value({ topic: "chat", station, thread: id, session: null });
    const held = this.value({ topic: "letters", station, thread: id });
    if (chat === undefined || !("ok" in chat) || held === undefined || !("ok" in held)) return null;
    const view = chat.ok as J;
    const key = `${station}/${id}`;
    const was = this.#thingsKept.get(key);
    if (was !== undefined && was.entries === held.ok && was.agents === view.agents) return was.value;
    const thread = view.thread as J;
    const keys = new Set(members(thread));
    const agents = arr(view.agents);
    const scope = ofAddress(station);
    const viewer = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const some = merge(arr(get(held.ok, "entries"))).filter((m) => {
      if (isLetter(m, keys) || m.authorKind === "ember" || m.authorKind === "stillfail") return false;
      return (Array.isArray(m.attachments) && m.attachments.length > 0) || (str(m.text) ?? "").includes("://");
    });
    const shown = some.map((m) => shownMessage(m, agents, viewer, [], members_, [], thread?.creator));
    const out = drawn({ ok: { agents, messages: shown } }, (path) => this.local.uploadOf(station, path), this.#core.data.mdStore(station, `t:${id}`));
    const messages = arr(get(out.ok, "messages"));
    const value = { messages, things: thingsOf(messages), whole: get(held.ok, "whole") === true, title: view.title };
    this.#thingsKept.delete(key);
    this.#thingsKept.set(key, { entries: held.ok, agents: view.agents, value });
    // (a few chats': those open, and the last ones left)
    for (const k of this.#thingsKept.keys()) if (this.#thingsKept.size > 6) this.#thingsKept.delete(k);
    return value;
  }

  /// What was said in a chat besides words (`chatThings`), as far as it is on the device (`whole` once all is): its
  /// pictures and videos, files, web links and pull requests, each the latest first, how many of each, those of each
  /// that have the words `q` (all of them without any), the pictures and videos also by the day and the message they were
  /// sent with (`mediaDays`). A pull request says what its card says of it (its title, how it
  /// stands, its checks, when it last changed) once its station has read it.
  #chatThings(station: string, id: number, q: string): Value | undefined {
    const chat = this.value({ topic: "chat", station, thread: id, session: null });
    if (chat === undefined || "err" in chat) return chat;
    const held = this.value({ topic: "letters", station, thread: id });
    if (held === undefined || "err" in held) return held;
    const read = this.#things(station, id);
    if (read === null) return undefined;
    const clock = this.#clock();
    const pulls = read.things.pulls.map((p) => {
      const card = this.ok({ topic: "linkPreview", station, url: p.url! });
      if (get(card, "kind") !== "github_pull_request") return p;
      const changed = u64(get(card, "updatedAt"));
      const checks = get(card, "checks");
      return {
        ...p,
        title: str(get(card, "title")) ?? "",
        ...(typeof get(card, "state") === "string" ? { state: get(card, "state") } : {}),
        ...(isObject(checks) ? { checks } : {}),
        ...(changed !== null && changed > 0 ? { updatedAt: changed, time: { updatedAt: present.stamp(changed, clock) } } : {}),
      };
    });
    const all = { ...read.things, pulls };
    const words = refs.terms(q);
    const counts = Object.fromEntries(THING_KINDS.map((k) => [k, all[k].length]));
    const found = Object.fromEntries(THING_KINDS.map((k) => [k, thingsHaving(all[k], words)])) as typeof all;
    const days = mediaDays(found.media, (ms) => format.dayLabel(ms, clock.now, clock.offsetMin), (ms) => format.clock(ms, clock.offsetMin));
    return { ok: { title: read.title, whole: read.whole, counts, ...found, mediaDays: days } };
  }

  /// What a chat's agents said in Slack and were given from it (not this chat's own thread), each after the message it
  /// followed. Only what falls in the window of messages shown (`more`/`newer`: the chat goes on before/after it): the
  /// rest comes with its page. A Slack message given to several of its agents shows once. With no chat (`thread`
  /// null), all of it, each before any message.
  #sentElsewhere(station: string, thread: J, agents: J[], messages: J[], more: boolean, newer: boolean, people: { members: J[]; bots: [string, string][] }): J[] {
    const own = thread === null ? null : `${str(get(thread, "channel")) ?? ""}/${str(get(thread, "threadTs")) ?? ""}`;
    const first = u64(messages[0]?.createdAt);
    const last = u64(messages.at(-1)?.createdAt);
    if ((more || newer) && (first === null || last === null)) return [];
    const overview = this.ok({ topic: "overview", station });
    const workspaces = slackWorkspaces(overview);
    const connects = arr(get(overview, "connects"));
    const offsetMin = this.#core.host.utcOffsetMin(this.#core.host.nowMs());
    const out: J[] = [];
    const heard = new Set<string>();
    for (const a of agents) {
      const key = str(get(a.session, "key"));
      if (key === null) continue;
      const said = this.#core.data.slackSaid(station, key).filter((s) => s.to !== own && !(more && s.at < first!) && !(newer && s.at >= last!));
      if (said.length === 0) continue;
      const threads = arr(get(this.ok({ topic: "session", station, key }), "threads"));
      const agent = { name: str(get(a.session, "agentText")) ?? "agent", agent: key, maker: get(a.session, "maker") ?? null, runtime: get(a.session, "runtime") ?? null };
      const pictures = slackPictures(a.session, threads, connects);
      for (const s of said) {
        if (!s.out) {
          const id = `${s.user ?? ""} ${s.to} ${s.at}`;
          if (heard.has(id)) continue;
          heard.add(id);
        }
        let after = 0;
        for (const m of messages) {
          if (typeof m.createdAt !== "number" || m.createdAt > s.at) break;
          after = m.seq;
        }
        let place: J = s.to === "" ? null : format.place(threads, s.to, offsetMin, workspaces);
        if (place === null && s.to !== "") {
          // A message of its own in a channel, before its ts is known.
          const named = threads.find((th) => get(th, "channel") === s.to && typeof get(th, "channelName") === "string");
          const channel = s.to.split("/")[0]!;
          place = format.isFeishuChat(channel)
            ? { name: named?.channelName ?? t("core-logic.format.thread.feishu"), surface: "feishu" }
            : { name: s.to.startsWith("D") ? t("core-views.direct_message") : `#${named?.channelName ?? s.to}`, surface: "slack" };
        }
        // (a bot is said as its mention, `<@U…>`)
        const picture = s.out || s.user === null ? undefined : pictures.get(s.user.replace(/^<@(.+)>$/, "$1"));
        const by = s.out ? structuredClone(agent) : { name: s.who || s.user || "Slack", ...(picture !== undefined ? { picture } : {}) };
        // A person's files are listed after their words, as the agent was given them: drawn as files, kept in the
        // workspace of the agent's session that was given them.
        const words = s.out ? { text: s.text, files: [] } : heardFiles(s.text);
        const text = present.mentions(words.text, people.bots, people.members);
        const item: J = { key: `${key}/${s.i}/${s.k}`, after, createdAt: s.at, text, place, failed: s.failed, by };
        if (words.files.length > 0) item.attachments = words.files.map((f) => ({ ...f, owner: key }));
        if (!s.out) item.received = true;
        out.push(item);
      }
    }
    return out.sort((a, b) => a.createdAt - b.createdAt);
  }

  /// A pending chat's page: its station's chat once made and read, else what is known here.
  #pendingChat(station: string, key: string): Value | undefined | null {
    const chat = this.local.pending(key);
    if (!chat) return null;
    if (chat.made) {
      const view = this.#chat(station, chat.made[1]);
      if (view !== undefined && "ok" in view) {
        (view.ok as J).key = chat.made[0];
        return view;
      }
    }
    const outbox = chat.made ? structuredClone(this.local.outbox(station, chat.made[1])) : structuredClone(chat.queue);
    return {
      ok: {
        me: this.me(ofAddress(station)),
        thread: null,
        // named by no one yet: what its station will call it till then (chatTitle)
        title: t("core-views.new_chat"),
        people: [],
        agents: [],
        messages: [],
        more: false,
        outbox,
        link: this.link(station),
        offline: this.offline(station),
        pending: chat.made === null,
        key: chat.made ? chat.made[0] : null,
        failed: chat.failed,
      },
    };
  }

  /// An agent of a chat: its session, the connect that started it, its profile, turns and threads.
  agent(station: string, key: string): J {
    const v = this.value({ topic: "session", station, key });
    let detail: J;
    if (v !== undefined && "ok" in v) detail = v.ok;
    else if (v !== undefined) return null;
    else {
      const data = this.#core.data;
      if (data.listed(station, "sessions")) {
        const found = data.listedSummary(station, key);
        if (found === undefined) return null;
        detail = { session: found };
      } else {
        const agent = this.#rowAgent(station, key);
        if (agent === null) return null;
        detail = { session: agent };
      }
    }
    const overview = this.ok({ topic: "overview", station });
    const now = this.#core.host.nowMs();
    const session = present.session(get(detail, "session") ?? null);
    const connect = present.connect(find(get(overview, "connects"), get(session, "connect")));
    const profile = present.profile(find(get(overview, "profiles"), get(session, "profile")));
    const runnable = runnableOn(overview, session, now);
    let account: J = runnable.find((p) => p.current === true) ?? null;
    if (account === null && isObject(profile)) {
      account = { id: profile.id ?? null, name: profile.name ?? null, current: true, kind: get(profile.access, "kind") ?? null, runtime: profile.runtime ?? null, quota: profile.quota ?? null };
      if (typeof profile.providerMark === "string") account.mark = profile.providerMark;
    }
    const turns = arr(get(detail, "turns"));
    const lastTurn = turns[turns.length - 1];
    const since = lastTurn !== undefined && (lastTurn.endedAt === undefined || lastTurn.endedAt === null) ? (lastTurn.startedAt ?? null) : null;
    return {
      status: present.shownStatus(session),
      badge: present.markOf(session),
      session,
      connect,
      profile,
      profiles: runnableOn(overview, session, now),
      choices: choices(overview, session, now),
      account,
      attention: attention(overview, session, now),
      since,
      wait: present.watching(session) ? null : present.waiting(session),
      turns: structuredClone(get(detail, "turns") ?? []),
      threads: structuredClone(get(detail, "threads") ?? []),
      jobs: structuredClone(get(detail, "jobs") ?? []),
    };
  }

  /// An agent as its sidebar row lists it, with the connect its row came from.
  #rowAgent(station: string, key: string): J {
    const row: J = this.#core.data.chatOfSession(station, key);
    const agent = arr(get(row, "agents")).find((a) => get(a, "key") === key);
    if (agent === undefined) return null;
    const out = structuredClone(agent);
    if (typeof get(row, "connect") === "string") out.connect = row.connect;
    return out;
  }

  /// Where a Slack or Feishu thread is, in words (placeName), and its link in Slack (while one of `agents`' Slack
  /// connects is signed in; `slackApp` into Slack's app) or in Feishu: none of them for a still.fail chat.
  #whereIn(station: string, agents: J[], surface: string, channel: string, channelName: string, threadTs: string): { place: string | null; slackUrl: string | null; slackApp: string | null; feishuUrl: string | null } {
    const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
    const feishu = surface.startsWith("feishu:") || format.isFeishuChat(channel);
    const slack = !(surface === "ember" || surface === "stillfail") && !feishu;
    const place = placeName(surface, channel, channelName);
    // A Feishu chat opens in Feishu (Lark's own app for its connect's).
    const feishuConnect = arr(get(this.ok({ topic: "overview", station }), "connects")).find((c) => `feishu:${strOf(c, "id")}` === surface);
    const feishuUrl = feishu ? format.feishuChatUrl(format.feishuApplink(str(get(get(feishuConnect, "feishu"), "domain"))), channel) : null;
    let workspaceUrl: string | null = null;
    let team = "";
    for (const a of agents) {
      const c = a.connect;
      if (strOf(c, "kind") !== "slack") continue;
      const conn = get(c, "connection");
      const state = get(conn, "state");
      if ((state === "connected" || state === "reconnecting") && typeof get(get(conn, "workspace"), "url") === "string") {
        workspaceUrl = conn.workspace.url;
        team = strOf(conn.workspace, "teamId");
        break;
      }
    }
    const slackUrl = slack && workspaceUrl !== null ? `${workspaceUrl}archives/${channel}/p${threadTs.replaceAll(".", "")}` : null;
    const slackApp = slackUrl !== null && team !== "" ? format.slackAppUrl(team, channel, threadTs, threadTs) : null;
    return { place, slackUrl, slackApp, feishuUrl };
  }

  /// The page of an item whose agent has no chat yet.
  #unchatted(station: string, key: string): Value | undefined {
    const agent = this.agent(station, key);
    if (agent === null) {
      const detail = this.value({ topic: "session", station, key });
      if (detail === undefined) return undefined;
      return { err: "err" in detail ? detail.err : new CoreError("http_404", t("core-views.error.no_agent"), 404) };
    }
    const found = this.#row(station, { session: key });
    if (found === undefined && this.value({ topic: "chatRows", station }) === undefined) return undefined;
    const row = found ?? undefined;
    if (row === undefined) {
      const threads = this.value({ topic: "threads", station });
      if (threads === undefined) return undefined;
      if ("err" in threads) return threads;
    }
    const archived = this.local.archivedChanging(station, null, key) ?? (get(agent.session, "archivedAt") !== undefined && get(agent.session, "archivedAt") !== null);
    // An agent that has only been in Slack: what was said there is all it has to show.
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: ofAddress(station) }), "members"));
    const bot = agent.connect !== undefined ? present.botOf(agent.connect) : null;
    const elsewhere = this.#sentElsewhere(station, null, [agent], [], false, false, { members: members_, bots: (bot === null ? [] : [bot]).concat(this.#core.data.slackNames(station)) });
    // No chat at all, as its detail says: none here, none in Slack (a Slack thread has no chat here either), not archived.
    const detail = this.value({ topic: "session", station, key });
    const noChat = !archived && detail !== undefined && "ok" in detail && arr(get(detail.ok, "threads")).length === 0;
    // Where the Slack or Feishu thread it came from is (the row's origin), as a chat's page says its own.
    const origin = get(row, "origin");
    const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
    const surface = isObject(origin) && isObject(agent.connect) ? `${strOf(agent.connect, "kind")}:${strOf(agent.connect, "id")}` : "";
    const where = isObject(origin) ? this.#whereIn(station, [agent], surface, strOf(origin, "channel"), strOf(origin, "channelName"), strOf(origin, "threadTs")) : null;
    return {
      ok: {
        me: this.me(ofAddress(station)),
        thread: null,
        ...(where !== null && where.place !== null ? { place: where.place, slackUrl: where.slackUrl, ...(where.slackApp !== null ? { slackApp: where.slackApp } : {}) } : {}),
        ...(where !== null && where.feishuUrl !== null ? { feishuUrl: where.feishuUrl } : {}),
        ...(noChat ? { noChat: true } : {}),
        title: row !== undefined && row.title !== undefined ? row.title : t("core-views.new_chat"),
        people: [],
        archived,
        agents: [agent],
        messages: [],
        elsewhere,
        more: false,
        outbox: [],
        link: this.link(station),
        offline: this.offline(station),
      },
    };
  }

  // ── an agent's history ──

  #history(station: string, key: string): Value | undefined {
    const live = this.value({ topic: "live", station, key });
    if (live === undefined || "err" in live) return live;
    const detail = this.ok({ topic: "session", station, key });
    const session = get(detail, "session") ?? null;
    const threads = arr(get(detail, "threads"));
    const overview = this.ok({ topic: "overview", station });
    const connect = find(get(overview, "connects"), get(session, "connect"));
    const connection = get(connect, "connection");
    const state = get(connection, "state");
    const signedIn = state === "connected" || state === "reconnecting";
    const botUserId = signedIn ? str(get(connection, "botUserId")) : null;
    const botName = str(get(connect, "name")) ?? str(get(session, "connect")) ?? "";
    const slackUsers = arr(get(overview, "slackUsers")).filter((u): u is string => typeof u === "string");
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: ofAddress(station) }), "members"));
    const workspaces = slackWorkspaces(overview);
    const now = this.#core.host.nowMs();
    const md = this.#core.data.mdStore(station, `s:${key}`);
    return {
      // What its calls used, from its stream while it works, else from its summary (brief.ts `usageNow`).
      ok: presentHistory({ ...(live.ok as object), usage: brief.usageNow(session, live.ok) }, {
        workspaces,
        threads,
        members: members_,
        slackUsers,
        botUserId,
        botName,
        slackNames: this.#core.data.slackNames(station),
        runtime: str(get(session, "runtime")) ?? "claude",
        started: typeof get(session, "runtimeSessionId") === "string",
        offsetMin: this.#core.host.utcOffsetMin(now),
        now,
        stations: this.stationNames(ofAddress(station)),
        ...(md !== undefined ? { md } : {}),
      }),
    };
  }

  // ── workspace marks ──

  #marksSources(): Topic[] {
    const topics: Topic[] = [{ topic: "workspaces" }, { topic: "prefs" }];
    for (const id of marks.workspaceIds(this.ok({ topic: "workspaces" }))) {
      topics.push({ topic: "workspace", workspace: id });
      for (const s of this.stations(id) ?? []) {
        topics.push({ topic: "link", station: s.address });
        if (s.online) topics.push({ topic: "chatRows", station: s.address });
      }
    }
    return topics;
  }
}

/// When each pinned list row was pinned (the rows say only `pinned: true`).
const pinnedAt = new WeakMap<object, number>();

/// `value` put through shape `ty` once, as it would go out, and marked so (`shaped`: shared, never changed, not copied or
/// shaped again where it goes out inside another value); as it is when it does not fit (its topic's shape says why).
function asShaped(ty: Ty, value: J): J {
  const out = conformTy(ty, value);
  if (!("ok" in out) || out.ok === null || typeof out.ok !== "object") return value;
  shaped.add(sharedValue(out.ok));
  return out.ok;
}

/// What a chat's page draws by each message, decided here so the page only draws it (docs/client-core.md): the chats it
/// links to (`linked`: each its title and whether it is archived), whether the
/// agent who said it is one of the chat's (its name opens its history), whose workspace keeps each of its files (and the
/// outbox's) and which of them went up from here after it was sent (`uploadOf`: their pictures are still here), which of an agent's files its text places (placed.ts), and what its
/// agents sent to Slack or were given there after it (`elsewhere`; the chat's own `elsewhere` keeps what came before
/// its first message), and which of the viewer's go close together with their next one, its time under that one (`followed`, `joined`).
/// `held`: whether a file's picture (an image's thumbnail, a video's still) is kept on the device, by its owner and
/// name (`held: true` on it: the app's first page waits for it as for the rest of what it shows, a decode away).
function drawn<V extends Value | undefined>(out: V, uploadOf: (path: unknown) => string | undefined, md?: MdStore, linked?: (text: string) => J[], held?: (session: string, name: string) => boolean): V {
  if (out === undefined || !("ok" in out) || !isObject(out.ok)) return out;
  // Everything said here goes on copies: what the view is made of may be the core's kept values, frozen (a message's
  // files, the outbox's), and writing on one of them threw and took the core down.
  const view = { ...(out.ok as J) };
  const agents = arr(view.agents);
  const keys = new Set(agents.map((a) => str(get(a.session, "key"))).filter((k): k is string => k !== null));
  const owner = (path: unknown) => {
    const by = typeof path === "string" ? agents.find((a) => path.startsWith(`${str(get(a.session, "workspace")) ?? "\0"}/`)) : undefined;
    return str(get((by ?? agents[0])?.session, "key"));
  };
  const own = (files: unknown): J => {
    if (!Array.isArray(files)) return files;
    return files.map((f) => {
      if (!isObject(f)) return f;
      const key = owner(get(f, "path"));
      // One sent from here before it was up: its picture is still here, under its upload's id.
      const upload = uploadOf(get(f, "path"));
      const path = str(get(f, "path")) ?? "";
      const kept = key !== null && held !== undefined && path !== "" && held(key, path.slice(path.lastIndexOf("/") + 1));
      return key !== null || upload !== undefined ? { ...f, ...(key !== null ? { owner: key } : {}), ...(upload !== undefined ? { upload } : {}), ...(kept ? { held: true } : {}) } : f;
    });
  };
  const here = (by: J): J => {
    const agent = str(get(by, "agent"));
    return agent !== null && keys.has(agent) ? { ...by, here: true } : by;
  };
  const messages: J[] = arr(view.messages).map((m) => {
    if (!isObject(m)) return m;
    const files = own(m.attachments);
    const out: J = { ...m, by: here(m.by), attachments: files };
    // The chats it links to, each with its title (one linked bare reads as it) and whether it is archived.
    const chats = linked?.(str(m.text) ?? "") ?? [];
    if (chats.length > 0) out.chats = chats;
    // A person's words are drawn as they wrote them and place nothing: their files are all below them. An agent's are
    // Markdown, read here (once: markdown.ts keeps it by the words); still.fail's notice's are too, as its pill says
    // them (noticeOf: a chat it opened is a link to it).
    if (isObject(m.notice)) out.notice = { ...m.notice, md: markdown(str(m.notice.words) ?? "", md) };
    else if (m.authorKind !== "person") {
      out.md = markdown(str(m.text) ?? "", md);
      if (Array.isArray(files) && files.length > 0) {
        const { placed } = placeFiles(str(m.text) ?? "", files as J[]);
        if (placed.size > 0) out.placed = [...placed.keys()];
      }
    }
    return out;
  });
  view.messages = messages;
  if (Array.isArray(view.outbox)) view.outbox = view.outbox.map((o: J) => (isObject(o) ? goingUp({ ...o, attachments: own(o.attachments) }) : o));
  const elsewhere = arr(view.elsewhere);
  if (elsewhere.length > 0) {
    const bySeq = new Map(messages.map((m) => [u64(m.seq), m]));
    const first: J[] = [];
    for (const item of elsewhere) {
      const s = isObject(item) ? { ...item, by: here(item.by) } : item;
      // Before the first message (0), or after one shown; after one outside the window, not shown with it.
      const after = bySeq.get(u64(s.after));
      if (u64(s.after) === 0) first.push(s);
      else if (after !== undefined) after.elsewhere = [...(after.elsewhere ?? []), s];
    }
    view.elsewhere = first;
  }
  // The viewer's messages sent one after another, in their bubbles: close together, the time only under the last of
  // them, while each one's is within FOLLOWED_MS of the time shown under a later one (nothing else between them: no
  // one else's, nothing sent to Slack). Those still on their way count; one not sent stands apart.
  const outbox = view.newer === true ? [] : arr(view.outbox);
  const all: J[] = [...messages, ...outbox];
  const followed = new Set<number>();
  let shownAt: number | null = null;
  for (let i = all.length - 1; i >= 0; i--) {
    const m = all[i];
    const at = u64(m.createdAt);
    const mine = i >= messages.length ? m.state !== "failed" : m.mine === true;
    if (!mine || at === null) { shownAt = null; continue; }
    if (shownAt !== null && m.elsewhere === undefined && shownAt - at <= FOLLOWED_MS) followed.add(i);
    else shownAt = at;
  }
  if (followed.size > 0) {
    const marked = all.map((m, i) => (followed.has(i) || followed.has(i - 1) ? { ...m, ...(followed.has(i) ? { followed: true } : {}), ...(followed.has(i - 1) ? { joined: true } : {}) } : m));
    view.messages = marked.slice(0, messages.length);
    if (outbox.length > 0) view.outbox = marked.slice(messages.length);
  }
  return { ...out, ok: view } as V;
}

/// An outgoing message's files still going up (`uploads`) as its row draws them: an image or a video among its files at
/// once, in its place and shape, drawn from the picture this device has of it (`upload`; on no station yet, its path
/// names the upload), as its message draws it once up, not a card that turns into it then; any other a card saying how
/// far, as it is a card once up. While any goes up, 正在上传 under it (`waits`), unless something else holds it, and how far all
/// of them together are (`progress`, 正在上传 42%) once each says how much of it the station has (a station's file
/// copied across says nothing until it is there).
function goingUp(o: J): J {
  const { uploads, ...rest } = o as Record<string, unknown>;
  const going = arr(uploads).filter((u) => isObject(u));
  if (going.length === 0) return rest;
  const pictured = going.filter((u) => isImage(str(u.name) ?? "") || isVideo(str(u.name) ?? ""));
  const shown = pictured.map((u) => ({ name: u.name, path: `upload:${u.id}`, size: u.size, ...(u.width && u.height ? { width: u.width, height: u.height } : {}), upload: u.id }));
  const cards = going.filter((u) => !pictured.includes(u));
  const size = going.reduce((n, u) => n + (u64(u.size) ?? 0), 0);
  const told = going.every((u) => u64(u.sent) !== null) && size > 0;
  const progress = told ? Math.min(going.reduce((n, u) => n + u64(u.sent)!, 0) / size, 1) : null;
  return {
    ...rest,
    attachments: [...arr(o.attachments), ...shown],
    ...(cards.length > 0 ? { uploads: cards } : {}),
    ...(o.state === "sending" && typeof o.waits !== "string"
      ? progress !== null ? { waits: t("core-views.outbox.uploading", { percent: Math.floor(progress * 100) }), progress } : { waits: t("common.uploading") }
      : {}),
  };
}

/// How far apart the viewer's messages sent one after another still go together, one time under the last.
const FOLLOWED_MS = 5 * 60_000;

/// How long a station up may go without a host reading before it is said to be silent (StationCards.tsx useLong's 15 s).
const SILENT_MS = 15_000;

/// How a station is in a few words, as its page's head and its card say it (StationCards.tsx state): down for a security
/// mode, its line; away, when it was last online (or never); up, connecting until its overview is read, then its
/// agents at work (`busy`) or idle.
export function stationState(online: boolean, saysWhy: boolean, summary: string, lastSeen: number | null, read: boolean, running: number, c: present.Clock): { stateText: string; stateBusy: boolean } {
  if (!online && saysWhy) return { stateText: summary, stateBusy: false };
  if (!online) {
    return { stateText: lastSeen !== null ? t("core-views.station.last_online", { time: format.relativeTime(lastSeen * 1000, c.now, c.offsetMin) }) : t("core-views.station.never_online"), stateBusy: false };
  }
  if (!read) return { stateText: t("core-views.station.connecting"), stateBusy: false };
  return running > 0 ? { stateText: t("core-views.station.running_agents", { n: running }), stateBusy: true } : { stateText: t("core-views.station.idle"), stateBusy: false };
}

/// What may be wrong with a station, each in words, worst first (StationCards.tsx problems): silent though up, down for
/// a security mode (why), away (red once it has been online, else amber: never connected).
export function stationProblems(online: boolean, silent: boolean, blocked: string | null, seen: boolean, updating = false): { key: string; level: string; text: string }[] {
  if (online && silent) return [{ key: "silent", level: "amber", text: t("core-views.station.silent", { name: brand.name() }) }];
  if (!online && blocked !== null) return [{ key: "blocked", level: "red", text: blocked }];
  // Gone for its update: back by itself once it is done.
  if (!online && updating) return [{ key: "updating", level: "amber", text: t("core-views.station.updating_back") }];
  if (!online) return [{ key: "away", level: seen ? "red" : "amber", text: seen ? t("core-views.station.away", { name: brand.name() }) : t("core-views.station.never_connected", { name: brand.name() }) }];
  return [];
}
