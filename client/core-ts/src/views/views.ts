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
import * as present from "../present.ts";
import { topicKey, type Topic } from "../protocol.ts";
import * as refs from "../refs.ts";
import type { Value, Watch } from "../store.ts";
import { arr as arrU, deepFreeze, get as getU, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";
import { presentHistory } from "../history.ts";
import { archiveHintOf, type ArchiveHint } from "../prefs.ts";
import { markdown, type MdStore } from "../markdown.ts";
import { withDrive } from "../drive-browse.ts";
import { near, placeFiles } from "../placed.ts";
import { archive } from "./archive.ts";
import { Local, PENDING_PREFIX, type LocalChange } from "./local.ts";
import { askAnswers } from "./vault.ts";
import * as marks from "./marks.ts";
import { usageView } from "./usage.ts";
import { resourcesView } from "./resources.ts";
import { workspaceProfiles } from "./profiles.ts";
import { settingsView } from "./settings.ts";
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
/// How many rows a list shows before its stations' rows are loaded: more than a screen holds; and from how many rows
/// the stations hold on that is done (fewer are loaded at once).
export const HEAD = 80;
export const HEAD_FROM = 500;

const VIEW_TOPICS = new Set(["chats", "chatSearch", "search", "stations", "profiles", "connects", "chat", "history", "agentCard", "stationNet", "archive", "workspaceMarks", "decisions", "chatJobs", "chatLetters", "imageNear", "longJobs", "usage", "settings", "resources", "adminList", "adminItem", "adminOverview", "adminRelays"]);

/// What a chat row's columns say that the views find rows by (db/account.ts): how urgent it is for its person
/// (workspace marks), whether it asks something of them, whether the 奏 page lists it.
export const chatDerive: Derive = {
  tone: marks.rowTone,
  asks: (row) => {
    const d = decisions.asked(row);
    return d !== null && !decisions.dismissed(d);
  },
  desk: (row) => {
    const d = decisions.asked(row);
    if (d !== null && !decisions.dismissed(d)) return true;
    if (arr(get(row, "answered")).length > 0) return true;
    return u64(get(row, "thread")) !== null && get(row, "mine") === true && present.workingLine(row) !== null;
  },
};

/// A station of a scope, as the workspace lists it.
/// `joined`: the station's home is another workspace (docs/multi-workspace.md), this one it joined.
export type StationInfo = { address: string; id: string; name: string; emoji: string | null; icon: string | null; online: boolean; lastSeen: J; version: J; joined: boolean };

/// Whether a station is taken for down: its link found it so, or — not found out yet this time — it was, last.
export function down(link: J): boolean {
  const state = get(link, "state");
  return state === "offline" || (state === "connecting" && get(link, "last") === "offline");
}

/// A station taken for down, in words, as its link says why (link.ts DownCause): the device's network, the station, or
/// the way between them.
export function downWords(link: J, name: string): string {
  const cause = get(link, "cause");
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
    const seq = u64(l.message.seq) ?? 0;
    chats.set(key, was === undefined ? { title: l.title, link: l.link, letters: [letter], last: seq } : { ...was, letters: [...was.letters, letter], last: Math.max(was.last, seq) });
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
  /// A topic a view watches shown again (its owner asked to bring it up to date, store.ts `resume`).
  resume?: (topic: Topic) => void;
  /// How agents' requests about vault items are answered on this device, from the vault as the core holds it
  /// (views/vault.ts askAnswers): each `{answer, lasts?}`, in the order asked.
  vaultAnswers?: (workspace: string, asks: VaultAskOf[]) => J[];
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
  readonly #updateNoticesOpen = new Set<string>();
  /// Views whose words count seconds (a chat's jobs): each computed again when they next change.
  readonly #again = new Map<string, Fiber.Fiber<unknown, unknown>>();
  /// The scopes whose stations' rows are being loaded (the list showed its first screen meanwhile).
  readonly #loading = new Set<string>();
  /// Since when each station up has had no host reading (by address): unanswered that long, it is said to be silent.
  readonly #hostless = new Map<string, number>();
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
        this.#invalidate((v) => v.topic === "decisions" || v.topic === "workspaceMarks" || v.topic === "chats" || v.topic === "chatSearch" || v.topic === "search");
        return;
      case "pending":
        this.#invalidate((v) => (v.topic === "chat" && v.thread === null && v.session === change.key) || v.topic === "chats" || v.topic === "chatSearch" || v.topic === "search");
        return;
      case "first":
        this.#invalidate((v) => v.topic === "chat" && v.station === change.station && v.thread === null && v.session === change.key);
        return;
      case "archiving":
        this.#invalidate((v) => v.topic === "chats" || v.topic === "workspaceMarks" || v.topic === "decisions");
        return;
      case "letGo":
        this.#invalidate((v) => v.topic === "decisions");
        return;
      case "vault": {
        const showing = [...this.#vaultShown.values()].filter((s) => s.asks.some((a) => a.ask.request === change.request)).map((s) => topicKey(s.topic));
        this.#invalidate((v) => v.topic === "decisions" || showing.includes(topicKey(v)));
        return;
      }
      case "changing":
        this.#invalidate((v) => ["chats", "chatSearch", "search", "archive", "workspaceMarks", "decisions"].includes(v.topic) || (v.topic === "chat" && v.station === change.station));
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
    if (view.topic === "chat") topics.push({ topic: "prefs" });
    let scope: string;
    let perStation: (station: string) => Topic[];
    switch (view.topic) {
      case "chats":
      case "chatSearch":
      case "decisions":
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
      case "imageNear":
        return [{ topic: "chat", station, thread: view.thread ?? null, session: view.session ?? null }];
      case "chatLetters":
        return [
          { topic: "chat", station, thread: view.thread, session: null },
          { topic: "letters", station, thread: view.thread },
          { topic: "workspace", workspace: ofAddress(station) },
        ];
      case "workspaceMarks":
        return this.#marksSources();
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
        return topics;
      }
      default:
        if (view.topic.startsWith("admin")) return adminSources(view);
        return topics;
    }
    if (view.topic === "chats" || view.topic === "decisions") topics.push({ topic: "prefs" });
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
    return { state: get(v.ok, "state") ?? "connecting", message: get(v.ok, "message") ?? null, last: get(v.ok, "last") ?? null, ...(get(v.ok, "retrying") === true ? { retrying: true } : {}), ...(typeof cause === "string" ? { cause } : {}) };
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

  compute(view: Topic): Value | undefined {
    if (!this.#views.has(topicKey(view))) return undefined;
    this.#sync(view);
    const out = this.#compute(view);
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
    if (v.offline === true) {
      v.offlineNote = looks.offlineNote(v.link, this.stationName(station));
      if (Array.isArray(v.outbox)) v.outbox = looks.outboxHeld(v.outbox);
    }
    // Its sharing with the viewer's other workspaces, as asked here meanwhile.
    const shared = xshare.shown({ places: this.#core.places?.() ?? [], asked: (session) => this.#core.xshareAsked?.(station, session), me: str(get(v.me, "email")) }, station, v.thread);
    if (shared !== null) v.xshare = shared;
    // Its public snapshots, without those being revoked here meanwhile.
    const published = publish.shown({ me: str(get(v.me, "email")), role: typeof role === "string" ? role : null, revoking: (id) => this.#core.revoking?.(station, id) === true }, station, v.thread);
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
            for (const item of arr(refs.search(theirs.ok, view.query as string, undefined, undefined, undefined).items)) others.push({ ...item, outside: place.name });
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
          return this.#vaultCards(view, drawn(out, (path) => this.local.uploadOf(station, path), this.#core.data.mdStore(station, of)));
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
      case "decisions": {
        const out = this.#decisions(view.workspace as string);
        this.#vaultSeen(view, out !== undefined && "ok" in out ? arr(get(out.ok, "items")).map((i): [string, J] => [ofAddress(str(i.station) ?? ""), i.card]) : []);
        return out;
      }
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
        return { ok: near(chat.ok, view.path as string) };
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
        return { ok: jobs.longJobs(open, this.#clock(), (session) => this.#ranFrom(stations, session)) };
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
    // The first screen first (docs/core-db.md): while the stations' rows are not loaded, and they are many, the rows a
    // list shows on top are read by one query, and the rest are loaded after, a station at a time.
    const known = stations.filter((s) => data.listed(s.address, "chats")).map((s) => s.address);
    const unloaded = known.filter((s) => !data.loaded({ topic: "chatRows", station: s }));
    const head = unloaded.length > 0 && data.chatCount(unloaded) > HEAD_FROM ? this.#head(scope, known) : null;
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
      if (state === "offline") troubles.push(["offline", downWords(this.link(s.address), s.name), get(this.link(s.address), "cause") === "network", s.address]);
      else if (state === "error") troubles.push(["error", t("core-views.station.unreachable", { name: s.name }), false, s.address]);
      else if (state === "connecting" && read && "ok" in read) troubles.push(["reconnecting", t("core-views.station.reconnecting", { name: s.name }), false, s.address]);
      const cause = state === "offline" ? get(this.link(s.address), "cause") : undefined;
      // Refused for a security mode: why.
      if (cause === "lock") message = get(this.link(s.address), "message") ?? null;
      states.push({ station: s.address, id: s.id, name: s.name, state, message, ...(typeof cause === "string" ? { cause } : {}) });
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
    return { ok: { me, stations: states, loading, days, trouble, members: count, leading: "agents", glyph, note } };
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
    if (typeof raw.pinned === "number") pinnedAt.set(row, raw.pinned);
    return row;
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
      const host = hostRaw === undefined ? null : present.host(hostRaw);
      const shown = overview === undefined ? null : present.decorate({ topic: "overview", station: s.address }, structuredClone(overview), c);
      let summary: string;
      const cause = get(this.link(s.address), "cause");
      if (!s.online && cause === "network") summary = t("core-views.station.network");
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
        ...stationState(s.online, blocked !== null, summary, typeof s.lastSeen === "number" ? s.lastSeen : null, overview !== undefined, running, c),
        problems: stationProblems(s.online, silent, blocked, typeof s.lastSeen === "number"),
        // Down for a security mode: why, in place of the page's 离线 words.
        ...(blocked !== null ? { blocked } : {}),
        lastSeen: s.lastSeen,
        version: s.version,
        link: this.link(s.address),
        // What this workspace's chats run on: on a station it joined, the profiles open to it.
        runtimes: runtimes(s.joined && overview !== undefined ? servingIn(overview, scope) : overview),
        models: models(s.joined && overview !== undefined ? servingIn(overview, scope) : overview, c.now),
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
    const agents = members(thread).flatMap((key) => {
      const a = this.agent(station, key);
      return a === null ? [] : [a];
    });
    // What two chats' agents wrote each other is not said in it: it has a page of its own (`chatLetters`).
    const keys = new Set(members(thread));
    const all: J[] = merge(arr(page.entries));
    let messages: J[] = all.filter((m) => !isLetter(m, keys));
    const letters = Math.max(u64(get(thread, "letters")) ?? 0, all.length - messages.length);
    const scope = ofAddress(station);
    const viewer = this.me(scope);
    const slackUsers = arr(get(this.ok({ topic: "overview", station }), "slackUsers")).filter((u): u is string => typeof u === "string");
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const bots = agents.flatMap((a) => {
      const b = a.connect !== undefined ? present.botOf(a.connect) : null;
      return b === null ? [] : [b];
    }).concat(this.#core.data.slackNames(station));
    const waiting = agents.reduce((max, a) => Math.max(max, u64(get(a.session, "pending")) ?? 0), 0);
    const peopleSeqs = messages.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [m.seq as number] : []));
    const waits = peopleSeqs.slice(Math.max(peopleSeqs.length - waiting, 0));
    const written = messages.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [[m.seq as number, str(m.text) ?? ""] as [number, string]] : []));
    // Notices that a runtime is not installed: installing it, as the station's updates have it now.
    const updates = arr(get(this.ok({ topic: "overview", station }), "updates"));
    const role = get(this.ok({ topic: "workspace", workspace: scope }), "role");
    const manages = role === "owner" || role === "admin";
    // A failure notice may be sent to the still.fail team where the station takes bug reports.
    const reports = get(this.ok({ topic: "overview", station }), "feedback") === true;
    for (let i = 0; i < messages.length; i++) {
      const m = shownMessage(messages[i], agents, viewer, slackUsers, members_, bots, thread.creator);
      messages[i] = { ...m, waiting: u64(m.seq) !== null && waits.includes(m.seq) };
      const install = m.system === true && typeof m.runtime === "string" ? present.installView(m.runtime, updates, manages) : null;
      if (install !== null) messages[i].install = install;
      else if (reports && m.system === true && u64(m.seq) !== null && (str(m.text) ?? "").startsWith("⚠️")) messages[i].reportable = true;
    }
    messages = blockedUnder(messages);
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
    const surface = strOf(thread, "surface");
    const channel = strOf(thread, "channel");
    const feishu = surface.startsWith("feishu:") || format.isFeishuChat(channel);
    const slack = !(surface === "ember" || surface === "stillfail") && !feishu;
    const place = feishu ? strOf(thread, "channelName") || t("core-logic.format.thread.feishu") : slack ? (channel.startsWith("D") ? t("core-views.direct_message") : `#${strOf(thread, "channelName") || channel}`) : null;
    // A Feishu chat opens in Feishu (Lark's own app for its connect's).
    const feishuConnect = arr(get(this.ok({ topic: "overview", station }), "connects")).find((c) => `feishu:${strOf(c, "id")}` === surface);
    const feishuUrl = feishu ? format.feishuChatUrl(format.feishuApplink(str(get(get(feishuConnect, "feishu"), "domain"))), channel) : null;
    let workspaceUrl: string | null = null;
    for (const a of agents) {
      const c = a.connect;
      if (strOf(c, "kind") !== "slack") continue;
      const conn = get(c, "connection");
      const state = get(conn, "state");
      if ((state === "connected" || state === "reconnecting") && typeof get(get(conn, "workspace"), "url") === "string") {
        workspaceUrl = conn.workspace.url;
        break;
      }
    }
    const slackUrl = slack && workspaceUrl !== null ? `${workspaceUrl}archives/${channel}/p${strOf(thread, "threadTs").replaceAll(".", "")}` : null;
    const found = this.#row(station, { thread: id });
    const row = found ?? undefined;
    const open = (d: J) => !this.local.answered(station, id, u64(d.seq) ?? 0);
    let pendingCard: [number, boolean] | null | undefined;
    if (found !== undefined) {
      const d = row !== undefined ? decisions.ofRow(row) : null;
      pendingCard = d !== null && open(d) ? [u64(d.seq) ?? 0, decisions.dismissed(d)] : null;
    }
    messages.splice(0, messages.length, ...decisions.inMessages(messages, pendingCard, outbox.filter((m) => m.state !== "failed")));
    const elsewhere = this.#sentElsewhere(station, thread, agents, messages, u64(page.first) !== null && page.first > 1, page.end === false, { members: members_, bots });
    const title = row !== undefined && row.title !== undefined ? row.title : typeof page.title === "string" ? page.title : chatTitle(thread);
    const view: J = {
      me: this.me(scope),
      place,
      slackUrl,
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
    const sessions = arr(view.agents).flatMap((a) => (a.session !== undefined ? [a.session] : []));
    const watch = present.rowWatch(sessions);
    if (watch !== null) view.watch = watch;
    const card = row !== undefined ? decisions.ofRow(row) : null;
    if (card !== null && open(card)) view.decision = decisions.shown(card);
    // What is asked here and not decided yet (a card, or an agent needing a person): the page leads to each, and the
    // post that asks says so (`asked`: it can be let go there).
    view.asks = row !== undefined && view.archived !== true
      ? decisions.undecided(row).filter((d) => u64(d.seq) !== null && open(d)).map((d) => decisions.askOf(row, d, view.me))
      : [];
    for (const ask of view.asks) {
      const m = messages.find((x) => u64(get(x, "seq")) === ask.seq);
      if (isObject(m)) (m as J).asked = true;
    }
    if (row !== undefined && present.archivable(row) && view.archived !== true) view.archivable = true;
    if (letters > 0) view.letters = letters;
    return { ok: view };
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
    const letters = merge(arr(get(held.ok, "entries"))).flatMap((m) => {
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

  /// What a chat's agents said in Slack and were given from it (not this chat's own thread), each after the message it
  /// followed. Only what falls in the window of messages shown (`more`/`newer`: the chat goes on before/after it): the
  /// rest comes with its page. A Slack message given to several of its agents shows once. With no chat (`thread`
  /// null), all of it, each before any message.
  #sentElsewhere(station: string, thread: J, agents: J[], messages: J[], more: boolean, newer: boolean, people: { members: J[]; bots: [string, string][] }): J[] {
    const own = thread === null ? null : `${str(get(thread, "channel")) ?? ""}/${str(get(thread, "threadTs")) ?? ""}`;
    const first = u64(messages[0]?.createdAt);
    const last = u64(messages.at(-1)?.createdAt);
    if ((more || newer) && (first === null || last === null)) return [];
    const workspaces = slackWorkspaces(this.ok({ topic: "overview", station }));
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
        const by = s.out ? structuredClone(agent) : { name: s.who || s.user || "Slack" };
        const text = present.mentions(s.text, people.bots, people.members);
        const item: J = { key: `${key}/${s.i}/${s.k}`, after, createdAt: s.at, text, place, failed: s.failed, by };
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
    return {
      ok: {
        me: this.me(ofAddress(station)),
        thread: null,
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

  // ── the 奏 page ──

  /// The decision the wide 奏 page shows, by workspace (`decision.show`, decisions.ts Shown).
  readonly #decisionShown = new Map<string, decisions.Shown>();

  /// The one shown from now on (`decision.show`).
  showDecision(workspace: string, station: string, thread: number, seq: number): void {
    this.#decisionShown.set(workspace, decisions.picked(this.#decisionShown.get(workspace) ?? { key: null, at: 0 }, decisions.deferralKey(station, thread, seq)));
    this.#invalidate((v) => v.topic === "decisions" && v.workspace === workspace);
  }

  /// Set aside (`decision.defer`): if it is the one shown, the one now in its place shows (itself if it is the only one).
  decisionDeferred(station: string, thread: number, seq: number): void {
    const key = decisions.deferralKey(station, thread, seq);
    for (const [workspace, shown] of this.#decisionShown) this.#decisionShown.set(workspace, decisions.setAside(shown, key));
  }

  /// Where the one shown is in `items` (decisions.ts shownIn), kept for the next view; null for none.
  #shownDecision(workspace: string, items: J[]): number | null {
    const keys = items.map((d) => decisions.deferralKey(d.station, d.thread, d.seq));
    const { at, next } = decisions.shownIn(this.#decisionShown.get(workspace) ?? { key: null, at: 0 }, keys);
    this.#decisionShown.set(workspace, next);
    return at;
  }

  #decisions(scope: string): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const prefs = this.ok({ topic: "prefs" }) ?? null;
    const waiting: string[] = [];
    const failing: { station: string; name: string; message: string }[] = [];
    const items: [J, number, number | null][] = [];
    const answered: J[] = [];
    const working: J[] = [];
    // Only the rows the 奏 page lists (found by their column, not loaded whole: db/account.ts).
    const data = this.#core.data;
    const desk = new Map<string, J[]>();
    for (const [station, row] of data.desk(stations.map((s) => s.address))) desk.set(station, [...(desk.get(station) ?? []), row]);
    for (const s of stations) {
      if (!data.listed(s.address, "chats")) {
        const v = this.value({ topic: "chatRows", station: s.address });
        if (v === undefined && s.online) {
          waiting.push(s.name);
        } else if (v !== undefined && "err" in v) failing.push({ station: s.address, name: s.name, message: v.err.message });
        continue;
      }
      this.local.settle(s.address, data.rowsRev(s.address));
      const slackUsers = arr(get(this.ok({ topic: "overview", station: s.address }), "slackUsers")).filter((u): u is string => typeof u === "string");
      for (const raw of desk.get(s.address) ?? []) {
        if (this.local.beingArchived(s.address, raw)) continue;
        const row = this.local.asChanging(s.address, raw);
        const place = () => ({ station: s.address, stationName: s.name, ...(s.emoji ? { stationEmoji: s.emoji } : {}), ...(s.icon ? { stationIcon: s.icon } : {}), session: row.id ?? null, thread: row.thread ?? null, title: row.title ?? "" });
        for (const a of arr(row.answered)) {
          const seq = u64(get(a, "seq"));
          const at = get(a, "answeredAt");
          if (seq === null || typeof at !== "number") continue;
          answered.push({ ...place(), seq, text: decisions.question(str(get(a, "text")) ?? ""), answer: decisions.answerText(a), answeredAt: at, askedAt: get(a, "askedAt") ?? at });
        }
        if (u64(row.thread) !== null && row.mine === true && !decisions.waits(row)) {
          const line = present.workingLine(row);
          if (line !== null) working.push({ ...place(), line, lastActiveAt: row.lastActiveAt ?? null });
        }
        const d = decisions.forViewer(row, me);
        if (d === null) continue;
        const thread = u64(row.thread);
        const seq = u64(d.seq);
        if (thread === null || seq === null) continue;
        // Answered, let go or its vault request decided from here: gone at once (back if that could not be done).
        if (this.local.answered(s.address, thread, seq) || this.local.lettingGo(s.address, thread, seq)) continue;
        const shownCard = decisions.labelAssignee(decisions.cardShown(d.card), me, members_, row.creator);
        if (typeof shownCard.vault === "string" && this.local.decidedVault(shownCard.vault)) continue;
        const card = this.#vaultCard(shownCard, ofAddress(s.address));
        const agents = arr(row.agents).map((a) => ({ session: present.session(a) }));
        const shown = (m: J): J => ({ ...shownMessage(m, agents, me, slackUsers, members_, [], row.creator), waiting: false });
        const options = card.options ?? [];
        const message = shown(d.message);
        if (decisions.kind(d.card) === "options") message.options = structuredClone(options);
        else delete message.options;
        message.card = structuredClone(card);
        message.decision = { resolved: false };
        const before = arr(d.before).map(shown);
        const deferred = decisions.deferredAt(prefs, s.address, thread, seq);
        const asked = typeof message.createdAt === "number" ? message.createdAt : 0;
        const text = str(get(d.message, "text")) ?? "";
        items.push([
          {
            station: s.address,
            stationName: s.name,
            ...(s.emoji ? { stationEmoji: s.emoji } : {}),
            ...(s.icon ? { stationIcon: s.icon } : {}),
            session: row.id ?? null,
            thread,
            title: row.title ?? "",
            seq,
            message,
            before,
            options,
            card,
            deferred: deferred !== null ? true : null,
            text: decisions.line(text),
            question: decisions.asks(row, seq, text),
          },
          asked,
          deferred,
        ]);
      }
    }
    const ordered = decisions.order(items);
    const at = (v: J, k: string) => (typeof v[k] === "number" ? v[k] : 0);
    answered.sort((a, b) => at(b, "answeredAt") - at(a, "answeredAt"));
    working.sort((a, b) => at(b, "lastActiveAt") - at(a, "lastActiveAt"));
    const list = ordered.map((i) => i[0]);
    const shown = this.#shownDecision(scope, list);
    return { ok: { items: list, count: ordered.length, ...(shown !== null ? { shown } : {}), wait: looks.waitNote(waiting, failing, ordered.length === 0), answered, working } };
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

/// What a chat's page draws by each message, decided here so the page only draws it (docs/client-core.md): whether the
/// agent who said it is one of the chat's (its name opens its history), whose workspace keeps each of its files (and the
/// outbox's) and which of them went up from here after it was sent (`uploadOf`: their pictures are still here), which of an agent's files its text places (placed.ts), and what its
/// agents sent to Slack or were given there after it (`elsewhere`; the chat's own `elsewhere` keeps what came before
/// its first message), and which of the viewer's go close together with their next one, its time under that one (`followed`, `joined`).
function drawn<V extends Value | undefined>(out: V, uploadOf: (path: unknown) => string | undefined, md?: MdStore): V {
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
      return key !== null || upload !== undefined ? { ...f, ...(key !== null ? { owner: key } : {}), ...(upload !== undefined ? { upload } : {}) } : f;
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
    // A person's words are drawn as they wrote them and place nothing: their files are all below them. An agent's are
    // Markdown, read here (once: markdown.ts keeps it by the words).
    if (m.authorKind !== "person") {
      out.md = markdown(str(m.text) ?? "", md);
      if (Array.isArray(files) && files.length > 0) {
        const { placed } = placeFiles(str(m.text) ?? "", files as J[]);
        if (placed.size > 0) out.placed = [...placed.keys()];
      }
    }
    return out;
  });
  view.messages = messages;
  if (Array.isArray(view.outbox)) view.outbox = view.outbox.map((o: J) => (isObject(o) ? { ...o, attachments: own(o.attachments) } : o));
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

/// How far apart the viewer's messages sent one after another still go together, one time under the last.
const FOLLOWED_MS = 5 * 60_000;

/// How long a station up may go without a host reading before it is said to be silent (StationCards.tsx useLong's 15 s).
const SILENT_MS = 15_000;

/// How a station is in a few words, as its page's head and its card say it (StationCards.tsx state): down for a security
/// mode, its line; away, when it was last online (or never); up, connecting until its overview is read, then its
/// agents at work (`busy`) or idle.
export function stationState(online: boolean, blocked: boolean, summary: string, lastSeen: number | null, read: boolean, running: number, c: present.Clock): { stateText: string; stateBusy: boolean } {
  if (!online && blocked) return { stateText: summary, stateBusy: false };
  if (!online) {
    return { stateText: lastSeen !== null ? t("core-views.station.last_online", { time: format.relativeTime(lastSeen * 1000, c.now, c.offsetMin) }) : t("core-views.station.never_online"), stateBusy: false };
  }
  if (!read) return { stateText: t("core-views.station.connecting"), stateBusy: false };
  return running > 0 ? { stateText: t("core-views.station.running_agents", { n: running }), stateBusy: true } : { stateText: t("core-views.station.idle"), stateBusy: false };
}

/// What may be wrong with a station, each in words, worst first (StationCards.tsx problems): silent though up, down for
/// a security mode (why), away (red once it has been online, else amber: never connected).
export function stationProblems(online: boolean, silent: boolean, blocked: string | null, seen: boolean): { key: string; level: string; text: string }[] {
  if (online && silent) return [{ key: "silent", level: "amber", text: t("core-views.station.silent", { name: brand.name() }) }];
  if (!online && blocked !== null) return [{ key: "blocked", level: "red", text: blocked }];
  if (!online) return [{ key: "away", level: seen ? "red" : "amber", text: seen ? t("core-views.station.away", { name: brand.name() }) : t("core-views.station.never_connected", { name: brand.name() }) }];
  return [];
}
