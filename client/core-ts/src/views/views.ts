// The views (views.rs): what one screen shows, put together from the account and station topics so the UI does no
// joining, filtering or grouping (docs/client-core.md, Views). A view watches the topics it is built from; any change
// of them only invalidates it, and the store has it computed when its coalesced emission goes out. What a person did
// here and their station has not confirmed yet (local.ts) is laid over what the stations hold.
import { Effect, type Fiber } from "effect";
import type { Inner } from "../core.ts";
import type { Data } from "../data.ts";
import type { Host } from "../host.ts";
import type { Runner } from "../runtime.ts";
import type { Store } from "../store.ts";
import type { Owner } from "../core/routing.ts";
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
import { arr as arrU, get as getU, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";
import { presentHistory } from "../history.ts";
import { archive } from "./archive.ts";
import { Local, PENDING_PREFIX, type LocalChange } from "./local.ts";
import * as marks from "./marks.ts";
import { attention, choices, find, models, runnableOn, runtimes } from "./models.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: J): string | null => (typeof v === "string" ? v : null);
const u64 = (v: J): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

const DAY_MS = 86_400_000;

const VIEW_TOPICS = new Set(["chats", "chatSearch", "stations", "connects", "chat", "history", "archive", "workspaceMarks", "decisions", "chatJobs", "longJobs"]);

/// A station of a scope, as the workspace lists it.
export type StationInfo = { address: string; id: string; name: string; online: boolean; lastSeen: J; version: J };

/// Whether a station is taken for down: its link found it so, or — not found out yet this time — it was, last.
export function down(link: J): boolean {
  const state = get(link, "state");
  return state === "offline" || (state === "connecting" && get(link, "last") === "offline");
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

/// What a chat is called: its title, else the first line a person wrote in it, else its Slack channel.
export function chatTitle(thread: J): string {
  const text = (name: string): string | null => {
    const v = get(thread, name);
    return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
  };
  const title = text("title");
  if (title !== null) return title;
  const firstText = text("firstText");
  if (firstText !== null) {
    const first = withoutMentions(firstText)
      .split("\n")
      .map((l) => format.splitWhitespace(l).join(" "))
      .find((l) => l !== "");
    if (first !== undefined) return first;
  }
  const channel = text("channelName");
  if (channel !== null) return `#${channel}`;
  const surface = get(thread, "surface");
  if (!(surface === "ember" || surface === "stillfail") && text("channel")?.startsWith("D")) return t("core-views.direct_message");
  return t("core-views.no_messages");
}

/// What a message another chat's agent sent (session_send) is headed with: its chat's title and link, and the message.
export function sentFrom(text: string): [string, string, string] | null {
  const at = text.indexOf("\n\n");
  if (at < 0) return null;
  const head = text.slice(0, at);
  const rest = text.slice(at + 2);
  let named: string | null = null;
  if (head.startsWith("来自 ") && head.endsWith("：")) named = head.slice(3, -1);
  else if (head.startsWith("From ") && head.endsWith(":")) named = head.slice(5, -1);
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
  return [title, link, rest];
}

/// A message as a chat shows it: whether it is the viewer's, still.fail's own notice, who said it, mentions named.
export function shownMessage(m: J, agents: J[], viewer: J, slackUsers: string[], members_: J[], bots: [string, string][], creator: J): void {
  const card = decisions.ofMessage(m);
  if (card !== null) {
    decisions.labelAssignee(card, viewer, members_, creator);
    m.card = card;
  }
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
      m.by = {
        name: model !== null ? format.agentLabel(model, str(get(identity, "effort"))) : (str(get(session, "agentText")) ?? saidName ?? "agent"),
        agent: agent ? author : null,
        maker: model !== null ? present.maker(model) : session !== undefined ? (session.maker ?? null) : null,
        runtime: get(session, "runtime") ?? null,
      };
    }
  } else if (kind === "ember" || kind === "stillfail") m.by = { name: brandName() };
  else {
    const member = members_.find((x) => typeof get(x, "email") === "string" && x.email.toLowerCase() === author.toLowerCase());
    const name = present.memberName(members_, author) ?? saidName ?? (author === "local" ? t("core-views.local_author") : author);
    const picture = get(member, "picture");
    m.by = { name, picture: typeof picture === "string" && picture !== "" ? picture : null };
  }
  if (kind === "person") m.text = present.mentions(str(m.text) ?? "", bots, members_);
}

import * as brand from "../brand.ts";
const brandName = () => brand.name();

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
function connectSessions(item: J, connect: J, connects: J[], sessions: J[], threads: J[], clock: present.Clock): void {
  const id = str(get(connect, "id")) ?? "";
  const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
  const at = (v: J) => (typeof get(v, "lastActiveAt") === "number" ? v.lastActiveAt : 0);
  const nameOf = (c: string) => {
    const n = strOf(connects.find((x) => strOf(x, "id") === c), "name");
    return n !== "" ? n : c;
  };
  const shown = (s: J) => {
    const c = structuredClone(s);
    present.session(c);
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
  item.sessions = own;
  const bound = sessions.find((s) => current !== null && strOf(s, "key") === current);
  item.bound = bound !== undefined ? shown(bound) : null;
  item.candidates = candidates;
  item.running = running;
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
};

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
    relayName: (host) => {
      for (const account of core.accounts.list()) {
        const names = get(core.data.record("me", account.sub), "relay_names");
        if (!isObject(names)) continue;
        for (const [url, name] of Object.entries(names)) {
          try {
            if (new URL(url).hostname === host && typeof name === "string") return name;
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
  readonly #core: ViewsEnv;
  readonly local: Local;
  /// Per live view, the topics it watches.
  readonly #views = new Map<string, { topic: Topic; watches: Map<string, Watch> }>();
  readonly #updateNoticesOpen = new Set<string>();
  /// Views whose words count seconds (a chat's jobs): each computed again when they next change.
  readonly #again = new Map<string, Fiber.Fiber<unknown, unknown>>();

  constructor(core: ViewsEnv) {
    this.#core = core;
    this.local = new Local(core.data, () => core.host.nowMs());
    this.local.onChange = (change) => this.#localChanged(change);
  }

  owns(topic: Topic): boolean {
    return VIEW_TOPICS.has(topic.topic) || topic.topic.startsWith("admin") && topic.topic !== "admin";
  }

  // ── what the views watch ──

  start(view: Topic): void {
    this.#views.set(topicKey(view), { topic: view, watches: new Map() });
    this.#sync(view);
    this.#core.store.invalidate(view);
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
    for (const w of live?.watches.values() ?? []) w.drop();
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
        // A card answered from here waits no more.
        this.#invalidate((v) => v.topic === "decisions" || v.topic === "workspaceMarks");
        return;
      case "pending":
        this.#invalidate((v) => (v.topic === "chat" && v.thread === null && v.session === change.key) || v.topic === "chats" || v.topic === "chatSearch");
        return;
      case "first":
        this.#invalidate((v) => v.topic === "chat" && v.station === change.station && v.thread === null && v.session === change.key);
        return;
      case "archiving":
        this.#invalidate((v) => v.topic === "chats" || v.topic === "workspaceMarks" || v.topic === "decisions");
        return;
      case "changing":
        this.#invalidate((v) => ["chats", "chatSearch", "archive", "workspaceMarks", "decisions"].includes(v.topic) || (v.topic === "chat" && v.station === change.station));
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
      case "stations":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "link", station: s }, { topic: "overview", station: s }, { topic: "host", station: s }, { topic: "net", station: s }];
        break;
      case "archive":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "archivedRows", station: s }];
        break;
      case "longJobs":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "jobs", station: s }];
        break;
      case "connects":
        scope = view.scope as string;
        perStation = (s) => [{ topic: "overview", station: s }, { topic: "sessions", station: s }, { topic: "threads", station: s }];
        break;
      case "chatJobs":
        return [{ topic: "chat", station, thread: view.thread ?? null, session: view.session ?? null }];
      case "workspaceMarks":
        return this.#marksSources();
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
        );
        return topics;
      }
      default:
        if (view.topic.startsWith("admin")) return [{ topic: "admin", account: view.account, list: view.topic === "adminOverview" ? "overview" : view.list }];
        return topics;
    }
    if (view.topic === "chats" || view.topic === "decisions") topics.push({ topic: "prefs" });
    topics.push({ topic: "workspace", workspace: scope });
    if (view.topic === "stations") topics.push({ topic: "workspaces" });
    for (const s of this.stations(scope) ?? []) {
      topics.push({ topic: "link", station: s.address });
      if (s.online) topics.push(...perStation(s.address));
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
      return [{ address, id, name: str(get(s, "name")) ?? id, online: !down(this.link(address)), lastSeen: get(s, "last_seen") ?? null, version: get(s, "version") ?? null }];
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

  /// The chat an agent's item has: the still.fail chat bound to it, as the station's items say, or its threads do.
  boundThread(station: string, key: string): number | null {
    const rows = arr(this.ok({ topic: "chatRows", station }));
    const fromRows = u64(get(rows.find((r) => get(r, "session") === key), "thread"));
    if (fromRows !== null) return fromRows;
    const thread = arr(this.ok({ topic: "threads", station })).find((th) => (get(th, "surface") === "ember" || get(th, "surface") === "stillfail") && members(th)[0] === key);
    return u64(get(thread, "id"));
  }

  threadOf(station: string, id: number): J {
    return arr(this.ok({ topic: "threads", station })).find((th) => get(th, "id") === id) ?? null;
  }

  /// The station's link as `{ state, message, last }`.
  link(station: string): J {
    const v = this.value({ topic: "link", station });
    if (v === undefined) return { state: "connecting", message: null };
    if ("err" in v) return { state: "error", message: v.err.message };
    return { state: get(v.ok, "state") ?? "connecting", message: get(v.ok, "message") ?? null, last: get(v.ok, "last") ?? null };
  }

  #clock(): present.Clock {
    const now = this.#core.host.nowMs();
    return { now, offsetMin: this.#core.host.utcOffsetMin(now) };
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

  #rows(station: string): J[] | undefined {
    const rows = this.ok({ topic: "chatRows", station });
    if (rows === undefined) return undefined;
    this.local.settle(station, rows);
    return arr(rows);
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
    const dismissed = get(get(prefs, "stationUpdatesDismissed"), station);
    v.stationUpdate = looks.stationUpdate(overview, v, typeof dismissed === "string" ? dismissed : null, this.#updateNoticesOpen.has(station), manager);
    return out;
  }

  #compute(view: Topic): Value | undefined {
    switch (view.topic) {
      case "chats":
        return this.#chats(view.scope as string, view.mine === true, view.watching === true);
      case "chatSearch": {
        const chats = this.#chats(view.scope as string, false, false);
        if (chats === undefined || !("ok" in chats)) return chats;
        return { ok: refs.search(chats.ok, view.query as string, view.station as string | undefined, view.exclude as string | undefined, view.limit as number | undefined) };
      }
      case "stations":
        return this.#stationsView(view.scope as string);
      case "connects":
        return this.#connects(view.scope as string, view.mine === true);
      case "chat": {
        const station = view.station as string;
        if (typeof view.thread === "number") return this.#chat(station, view.thread);
        const session = typeof view.session === "string" ? view.session : null;
        if (session === null) return { err: CoreError.invalid(t("core-views.error.chat_needs_thread")) };
        if (session.startsWith(PENDING_PREFIX)) return this.#pendingChat(station, session) ?? { err: new CoreError("http_404", t("core-views.error.no_chat"), 404) };
        const bound = this.boundThread(station, session);
        const out = bound !== null ? this.#chat(station, bound) : this.#unchatted(station, session);
        const waiting = this.local.firstOutbox(station, session);
        if (waiting.length === 0 || out === undefined || !("ok" in out)) return out;
        const v = out.ok as J;
        if (Array.isArray(v.outbox)) v.outbox.push(...waiting);
        return out;
      }
      case "history":
        return this.#history(view.station as string, view.key as string);
      case "archive":
        return archive(this, this.local, view.scope as string, this.#core.host);
      case "workspaceMarks":
        return marks.marks(this, this.local, typeof view.workspace === "string" ? view.workspace : null);
      case "decisions":
        return this.#decisions(view.workspace as string);
      case "chatJobs": {
        const chat = this.value({ topic: "chat", station: view.station, thread: view.thread ?? null, session: view.session ?? null });
        if (chat === undefined || !("ok" in chat)) return chat;
        const [value, next] = jobs.chatJobs(chat.ok, this.#clock());
        this.#againIn(view, next);
        return { ok: value };
      }
      case "longJobs": {
        const stations = this.#stationsOr(view.scope as string);
        if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
        const several = stations.length > 1;
        const open = stations.filter((s) => s.online).map((s) => [s.address, several ? s.name : null, arr(this.ok({ topic: "jobs", station: s.address }))] as [string, string | null, J[]]);
        return { ok: jobs.longJobs(open, this.#clock()) };
      }
    }
    return undefined;
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
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const states: J[] = [];
    const troubles: [string, string][] = [];
    const rows: J[] = [];
    let loading = false;
    const unread: string[] = [];
    for (const s of stations) {
      const read = this.value({ topic: "chatRows", station: s.address });
      if (!(read && "ok" in read)) unread.push(s.address);
      if (read && "ok" in read) {
        const slackUsers = arr(get(this.ok({ topic: "overview", station: s.address }), "slackUsers")).filter((u): u is string => typeof u === "string");
        this.local.settle(s.address, read.ok);
        const listed = arr(read.ok).slice();
        const asked = this.local.pendingRows(s.address, listed);
        for (const raw of [...asked, ...listed]) {
          if (mine && get(raw, "mine") !== true) continue;
          if (this.local.beingArchived(s.address, raw)) continue;
          const row = this.#chatRow(s, this.local.asChanging(s.address, raw), me, slackUsers, members_, watching);
          if (row !== null) rows.push(row);
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
      if (state === "offline") troubles.push(["offline", t("core-views.station.offline", { name: s.name })]);
      else if (state === "error") troubles.push(["error", t("core-views.station.unreachable", { name: s.name })]);
      else if (state === "connecting" && read && "ok" in read) troubles.push(["reconnecting", t("core-views.station.reconnecting", { name: s.name })]);
      states.push({ station: s.address, id: s.id, name: s.name, state, message });
    }
    const days = this.#days(rows);
    let trouble: J = null;
    if (troubles.length === 1) trouble = { text: troubles[0][1], state: troubles[0][0], retry: false };
    else if (troubles.length > 1) {
      const worst = ["error", "offline", "reconnecting"].find((w) => troubles.some(([s]) => s === w)) ?? "offline";
      trouble = { text: t("core-views.station.troubles", { n: troubles.length }), state: worst, retry: false };
    }
    const glyph = looks.glyph(states, days);
    const note = looks.listNote(states, days, loading, unread);
    const ws = this.ok({ topic: "workspace", workspace: scope });
    const count = Array.isArray(get(ws, "members")) ? ws.members.length : null;
    return { ok: { me, stations: states, loading, days, trouble, members: count, leading: "agents", glyph, note } };
  }

  /// A station's row as the list shows it (null: not in this list).
  #chatRow(s: StationInfo, raw: J, me: J, slackUsers: string[], members_: J[], watching: boolean): J {
    const row = structuredClone(raw);
    row.station = s.address;
    row.stationName = s.name;
    if (!s.online) row.offline = t("core-views.station.offline", { name: s.name });
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
    for (const agent of arr(row.agents)) present.session(agent);
    if (row.connect !== undefined && row.connect !== null) {
      const o = row.origin ?? null;
      const text = (k: string) => (typeof get(o, k) === "string" && o[k] !== "" ? (o[k] as string) : null);
      const channelName = text("channelName");
      const place = channelName !== null ? `#${channelName}` : text("channel")?.startsWith("D") ? t("core-views.direct_message") : null;
      row.originText = ["Slack", text("teamName"), place].filter((x) => x !== null).join(" · ");
    }
    if (isObject(row.last)) {
      const text = format.cleanText(str(row.last.text) ?? "");
      row.last.preview = text === "" ? t("core-views.file") : text;
    }
    present.rowPeople(row, me, slackUsers, members_);
    const by = present.lastBy(row, me, slackUsers, members_);
    if (by !== null) {
      row.last.by = by;
      const name = str(by.name) ?? "";
      by.label = typeof by.state === "string" ? t("core-views.by_label", { name, state: present.badgeText(by.state) }) : name;
      by.maker = present.maker(str(by.model));
    }
    decisions.presentRow(row);
    if (present.settled(row) && !present.pinned(row) && row.archiveReminderDismissed !== true) {
      row.settled = true;
      row.archivable = true;
    }
    const line = present.rowStateLine(row);
    if (line !== null) {
      row.stateText = line[0];
      if (line[1] !== null) row.stateAbout = line[1];
    }
    return row;
  }

  /// Rows newest first, grouped by the viewer's local calendar day; the pinned above them all.
  #days(rows: J[]): J[] {
    const host = this.#core.host;
    const at = (row: J) => (typeof row.lastActiveAt === "number" ? row.lastActiveAt : 0);
    const pinned = rows.filter((row) => typeof row.pinned === "number");
    const rest = rows.filter((row) => typeof row.pinned !== "number");
    const pinnedAt = (row: J) => (typeof row.pinned === "number" ? row.pinned : 0);
    pinned.sort((a, b) => pinnedAt(b) - pinnedAt(a) || at(b) - at(a));
    for (const row of pinned) row.pinned = true;
    for (const row of rest) if (row.pinned !== undefined) row.pinned = false;
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

  #stationsView(scope: string): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const c = this.#clock();
    const items = stations.map((s) => {
      const overview = this.ok({ topic: "overview", station: s.address });
      const hostRaw = this.ok({ topic: "host", station: s.address });
      const host = hostRaw === undefined ? null : structuredClone(hostRaw);
      if (host !== null) present.host(host);
      const shown = overview === undefined ? null : present.decorate({ topic: "overview", station: s.address }, structuredClone(overview), c);
      let summary: string;
      if (!s.online) {
        summary = typeof s.lastSeen === "number" ? t("core-views.station.offline_since", { ago: format.relativeTime(s.lastSeen * 1000, c.now, c.offsetMin) }) : t("core-views.station.offline_short");
      } else if (host !== null) {
        const running = u64(get(get(overview, "counts"), "running")) ?? 0;
        const what = str(host.cpuModel) || str(host.os) || "";
        summary = `${what} · ${running > 0 ? t("core-views.station.running", { n: running }) : t("core-views.station.idle")}`;
      } else summary = t("core-views.station.connecting");
      const net = this.ok({ topic: "net", station: s.address });
      return {
        station: s.address,
        id: s.id,
        name: s.name,
        summary,
        face: looks.face(s.online, overview),
        line: looks.stationLine(s.online, host),
        online: s.online,
        lastSeen: s.lastSeen,
        version: s.version,
        link: this.link(s.address),
        runtimes: runtimes(overview),
        models: models(overview, c.now),
        overview: shown,
        host,
        net: net === undefined ? null : present.net(net, (h) => this.relayName(h)),
        betaOffered: betaOffered(overview, () => this.#betaOf(scope)),
      };
    });
    return { ok: items };
  }

  #connects(scope: string, mine: boolean): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const items: J[] = [];
    let loading = false;
    for (const s of stations.filter((s) => s.online)) {
      const v = this.value({ topic: "overview", station: s.address });
      if (v === undefined) {
        loading = true;
        continue;
      }
      if ("err" in v) continue;
      const sessions = arr(this.ok({ topic: "sessions", station: s.address }));
      const threads = arr(this.ok({ topic: "threads", station: s.address }));
      const connects = arr(get(v.ok, "connects"));
      for (const connect of connects) {
        const id = get(get(connect, "createdBy"), "id");
        const creator = id !== undefined ? { id, email: id } : null;
        if (mine && !isMine(me, creator)) continue;
        const shown = structuredClone(connect);
        present.connect(shown);
        if (shown.createdBy !== undefined) present.person(shown.createdBy, me, members_);
        const item: J = { station: s.address, stationName: s.name, connect: shown };
        connectSessions(item, connect, connects, sessions, threads, this.#clock());
        items.push(item);
      }
    }
    return { ok: { me, items, loading } };
  }

  // ── a chat ──

  #chat(station: string, id: number): Value | undefined {
    const pageV = this.value({ topic: "thread", station, thread: id });
    if (pageV === undefined) return undefined;
    if ("err" in pageV) return pageV;
    const page = pageV.ok as J;
    let thread: J;
    const threadsV = this.value({ topic: "threads", station });
    if (threadsV !== undefined && "ok" in threadsV) {
      const found = arr(threadsV.ok).find((th) => get(th, "id") === id);
      if (found === undefined) return { err: new CoreError("http_404", t("core-views.error.no_chat"), 404) };
      thread = structuredClone(found);
    } else if (threadsV !== undefined && "err" in threadsV) return threadsV;
    else {
      if (!isObject(page.thread)) return undefined;
      thread = structuredClone(page.thread);
    }
    const agents = members(thread).flatMap((key) => {
      const a = this.agent(station, key);
      return a === null ? [] : [a];
    });
    const messages: J[] = merge(arr(page.entries));
    const scope = ofAddress(station);
    const viewer = this.me(scope);
    const slackUsers = arr(get(this.ok({ topic: "overview", station }), "slackUsers")).filter((u): u is string => typeof u === "string");
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const bots = agents.flatMap((a) => {
      const b = a.connect !== undefined ? present.botOf(a.connect) : null;
      return b === null ? [] : [b];
    });
    const waiting = agents.reduce((max, a) => Math.max(max, u64(get(a.session, "pending")) ?? 0), 0);
    const peopleSeqs = messages.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [m.seq as number] : []));
    const waits = peopleSeqs.slice(Math.max(peopleSeqs.length - waiting, 0));
    const written = messages.filter((m) => m.authorKind === "person").flatMap((m) => (u64(m.seq) !== null ? [[m.seq as number, str(m.text) ?? ""] as [number, string]] : []));
    for (const m of messages) {
      shownMessage(m, agents, viewer, slackUsers, members_, bots, thread.creator);
      m.waiting = u64(m.seq) !== null && waits.includes(m.seq);
    }
    // A sent message leaves the outbox as its own entry (or anything later) arrives; before the station answered
    // with its seq, it is the viewer's first message since it was sent with the same words.
    const newest = u64(page.last);
    const mine = written.filter(([seq]) => messages.some((m) => m.seq === seq && m.mine === true));
    let past = 0;
    const list = this.local.outbox(station, id).map((m) => ({ ...m }));
    const kept: J[] = [];
    for (const m of list) {
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
    const people = Array.isArray(thread.people) ? thread.people : [];
    for (const p of people) present.person(p, viewer, members_);
    if (thread.creator !== undefined) present.person(thread.creator, viewer, members_);
    const strOf = (v: J, k: string) => str(get(v, k)) ?? "";
    const surface = strOf(thread, "surface");
    const slack = !(surface === "ember" || surface === "stillfail");
    const channel = strOf(thread, "channel");
    const place = slack ? (channel.startsWith("D") ? t("core-views.direct_message") : `#${strOf(thread, "channelName") || channel}`) : null;
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
    const rows = this.#rows(station);
    const rawRow = rows?.find((r) => get(r, "thread") === id);
    const row = rawRow !== undefined ? this.local.asChanging(station, rawRow) : undefined;
    const open = (d: J) => !this.local.answered(station, id, u64(d.seq) ?? 0);
    let pendingCard: [number, boolean] | null | undefined;
    if (rows !== undefined) {
      const d = row !== undefined ? decisions.ofRow(row) : null;
      pendingCard = d !== null && open(d) ? [u64(d.seq) ?? 0, decisions.dismissed(d)] : null;
    }
    decisions.inMessages(messages, pendingCard);
    const focusLast = page.end !== false && outbox.length === 0 && messages.length > 0 && present.focusMessage(messages[messages.length - 1]);
    const title = row !== undefined && row.title !== undefined ? row.title : typeof page.title === "string" ? page.title : chatTitle(thread);
    const view: J = {
      me: this.me(scope),
      focusLast,
      place,
      slackUrl,
      title,
      people,
      agents,
      messages,
      more: u64(page.first) !== null && page.first > 1,
      newer: page.end === false,
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
    if (row !== undefined && present.settled(row) && !present.pinned(row) && row.archiveReminderDismissed !== true && view.archived !== true) view.archivable = true;
    return { ok: view };
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
    const firstText = str(get(outbox[0], "text"))?.trim() ?? "";
    const title = firstText !== "" ? (firstText.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? t("core-views.new_chat")) : t("core-views.new_chat");
    return {
      ok: {
        me: this.me(ofAddress(station)),
        thread: null,
        title,
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
      const summaries = this.ok({ topic: "sessions", station });
      if (summaries !== undefined) {
        const found = arr(summaries).find((s) => get(s, "key") === key);
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
    const session = structuredClone(get(detail, "session") ?? null);
    present.session(session);
    const connect = find(get(overview, "connects"), get(session, "connect"));
    present.connect(connect);
    const profile = find(get(overview, "profiles"), get(session, "profile"));
    present.profile(profile);
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

  /// An agent as a sidebar row lists it, with the connect its row came from.
  #rowAgent(station: string, key: string): J {
    for (const row of arr(this.ok({ topic: "chatRows", station }))) {
      const agent = arr(get(row, "agents")).find((a) => get(a, "key") === key);
      if (agent === undefined) continue;
      const out = structuredClone(agent);
      if (get(row, "session") === key && typeof get(row, "connect") === "string") out.connect = row.connect;
      return out;
    }
    return null;
  }

  /// The page of an item whose agent has no chat yet.
  #unchatted(station: string, key: string): Value | undefined {
    const agent = this.agent(station, key);
    if (agent === null) {
      const detail = this.value({ topic: "session", station, key });
      if (detail === undefined) return undefined;
      return { err: "err" in detail ? detail.err : new CoreError("http_404", t("core-views.error.no_agent"), 404) };
    }
    const rows = this.#rows(station);
    if (rows === undefined && this.value({ topic: "chatRows", station }) === undefined) return undefined;
    const raw = rows?.find((r) => get(r, "id") === key);
    const row = raw !== undefined ? this.local.asChanging(station, raw) : undefined;
    if (row === undefined) {
      const threads = this.value({ topic: "threads", station });
      if (threads === undefined) return undefined;
      if ("err" in threads) return threads;
    }
    const archived = this.local.archivedChanging(station, null, key) ?? (get(agent.session, "archivedAt") !== undefined && get(agent.session, "archivedAt") !== null);
    return {
      ok: {
        me: this.me(ofAddress(station)),
        thread: null,
        title: row !== undefined && row.title !== undefined ? row.title : t("core-views.no_messages"),
        people: [],
        archived,
        agents: [agent],
        messages: [],
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
    const workspaces = new Map<string, format.SlackWorkspace>();
    for (const c of arr(get(overview, "connects"))) {
      const conn = get(c, "connection");
      const s = get(conn, "state");
      const seen = s === "connected" || s === "reconnecting" ? get(conn, "workspace") : undefined;
      const team = str(get(seen, "teamId"));
      if (team === null) continue;
      const name = str(get(seen, "team")) ?? str(get(c, "team")) ?? "";
      const url = str(get(seen, "url")) || null;
      if (!workspaces.has(team)) workspaces.set(team, { name, url });
    }
    const now = this.#core.host.nowMs();
    return {
      ok: presentHistory(live.ok, {
        workspaces,
        threads,
        members: members_,
        slackUsers,
        botUserId,
        botName,
        runtime: str(get(session, "runtime")) ?? "claude",
        started: typeof get(session, "runtimeSessionId") === "string",
        offsetMin: this.#core.host.utcOffsetMin(now),
      }),
    };
  }

  // ── the 奏 page ──

  #decisions(scope: string): Value | undefined {
    const stations = this.#stationsOr(scope);
    if (stations === undefined || !Array.isArray(stations)) return stations as Value | undefined;
    const me = this.me(scope);
    const members_ = arr(get(this.ok({ topic: "workspace", workspace: scope }), "members"));
    const prefs = this.ok({ topic: "prefs" }) ?? null;
    let loading = false;
    const items: [J, number, number | null][] = [];
    const answered: J[] = [];
    const working: J[] = [];
    for (const s of stations) {
      const v = this.value({ topic: "chatRows", station: s.address });
      if (v === undefined) {
        loading ||= s.online;
        continue;
      }
      if ("err" in v) continue;
      this.local.settle(s.address, v.ok);
      const slackUsers = arr(get(this.ok({ topic: "overview", station: s.address }), "slackUsers")).filter((u): u is string => typeof u === "string");
      for (const raw of arr(v.ok)) {
        if (this.local.beingArchived(s.address, raw)) continue;
        const row = this.local.asChanging(s.address, raw);
        const place = () => ({ station: s.address, stationName: s.name, session: row.id ?? null, thread: row.thread ?? null, title: row.title ?? "" });
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
        if (this.local.answered(s.address, thread, seq)) continue;
        const agents = arr(row.agents).map((a) => {
          const c = structuredClone(a);
          present.session(c);
          return { session: c };
        });
        const shown = (m: J) => {
          const c = structuredClone(m);
          shownMessage(c, agents, me, slackUsers, members_, [], row.creator);
          c.waiting = false;
          return c;
        };
        const card = decisions.cardShown(d.card);
        decisions.labelAssignee(card, me, members_, row.creator);
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
    decisions.order(items);
    const at = (v: J, k: string) => (typeof v[k] === "number" ? v[k] : 0);
    answered.sort((a, b) => at(b, "answeredAt") - at(a, "answeredAt"));
    working.sort((a, b) => at(b, "lastActiveAt") - at(a, "lastActiveAt"));
    return { ok: { items: items.map((i) => i[0]), count: items.length, loading, answered, working } };
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
