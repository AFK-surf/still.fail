// Where the viewer's attention is, and what follows from it (attend.rs; the `notify` topic, `client.focus`): a
// chat's unread line, what is read, what comes in with a motion while a chat shows, which notices a page shows now,
// and the workspace the viewer is in. Whether notifications are on, and whether the system was asked, are kept on the
// device.
import { Effect } from "effect";
import type { ChatOf, FocusCall } from "./attend-parse.ts";
import type { Host } from "./host.ts";
import type { ClientId } from "./protocol.ts";
import { parseJson, toJsonBytes } from "./util.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Where the settings are kept (host storage).
const KEY = "notify";
/// A notice no page took this long is not shown any more.
const SHOW_FOR_MS = 30_000;

type Settings = { on: boolean; asked: boolean };

function is(c: ChatOf, station: string, thread: number | null, session: string | null): boolean {
  return c.station === station && ((thread !== null && c.thread === thread) || (session !== null && c.session === session));
}

/// What one UI shows.
type Focus = { visible: boolean; focused: boolean; chat: ChatOf | null; workspace: string | null };

function workspaceOf(f: Focus): string | null {
  return f.workspace ?? (f.chat ? ofAddress(f.chat.station) : null);
}

/// A chat shown: from when, and up to where it had been read then.
type Visit = {
  at: number;
  read: number;
  session: string | null;
  top: number;
  said: Set<number>;
  visible: boolean;
  resumedAt: number | null;
  statuses: Map<string, string>;
  started: Set<string>;
};

/// What a chat's value asks of the core once computed: a read position recorded.
export type Due = { read: { thread: number; seq: number } };

export class Attend {
  readonly #host: Host;
  #settings: Settings;
  #pushing = false;
  readonly #focus = new Map<ClientId, Focus>();
  readonly visits = new Map<string, Visit>();
  readonly #reads = new Map<string, number>();
  #show: [J, number][] = [];

  private constructor(host: Host, settings: Settings) {
    this.#host = host;
    this.#settings = settings;
  }

  static load(host: Host): Effect.Effect<Attend> {
    return Effect.map(Effect.orElseSucceed(host.storageGet(KEY), () => null), (bytes) => {
      const kept = parseJson(bytes) as J;
      const settings = kept && typeof kept.on === "boolean" ? { on: kept.on, asked: kept.asked === true } : { on: true, asked: false };
      return new Attend(host, settings);
    });
  }

  on(): boolean {
    return this.#settings.on;
  }

  /// The `notify` topic: the settings, whether this device should hold a push registration, what to show now.
  value(workspace: string | null): J {
    const now = this.#host.nowMs();
    const show = this.#show.filter(([n, at]) => now - at < SHOW_FOR_MS && (workspace === null || of(n) === workspace)).map(([n]) => structuredClone(n));
    return { on: this.#settings.on, asked: this.#settings.asked, push: this.#settings.on, show };
  }

  /// Changes the settings and keeps them.
  set(on: boolean | null, asked: boolean | null): Effect.Effect<void> {
    const s = { on: on ?? this.#settings.on, asked: asked ?? this.#settings.asked };
    this.#settings = s;
    if (!s.on) this.#show = [];
    return Effect.ignore(this.#host.storageSet(KEY, toJsonBytes(s)));
  }

  setPushing(on: boolean): void {
    this.#pushing = on;
  }

  /// Any page in view.
  seen(): boolean {
    return [...this.#focus.values()].some((f) => f.visible);
  }

  /// The workspaces the viewer is in; null while no UI says.
  current(): Set<string> | null {
    const ofUis = (inView: boolean) => new Set([...this.#focus.values()].filter((f) => f.visible || !inView).flatMap((f) => (workspaceOf(f) !== null ? [workspaceOf(f)!] : [])));
    const shown = ofUis(true);
    const all = shown.size === 0 ? ofUis(false) : shown;
    return all.size > 0 ? all : null;
  }

  #currentHas(workspace: string): boolean {
    const c = this.current();
    return c === null || c.has(workspace);
  }

  /// A UI's focus changed.
  focus(client: ClientId, call: FocusCall): void {
    let f = this.#focus.get(client);
    if (!f) {
      f = { visible: false, focused: false, chat: null, workspace: null };
      this.#focus.set(client, f);
    }
    if (call.visible !== null) f.visible = call.visible;
    if (call.focused !== null) f.focused = call.focused;
    if (call.left !== null && f.chat !== null && is(f.chat, call.left.station, call.left.thread, call.left.session)) f.chat = null;
    if (call.chat !== undefined) f.chat = call.chat;
    if (call.workspace !== null) f.workspace = call.workspace;
    this.#endVisits();
  }

  /// A UI went away.
  gone(client: ClientId): void {
    this.#focus.delete(client);
    this.#endVisits();
  }

  #endVisits(): void {
    const focus = [...this.#focus.values()];
    for (const [key, v] of [...this.visits]) {
      const at = key.indexOf("\u0001");
      const station = key.slice(0, at);
      const thread = Number(key.slice(at + 1));
      const showing = focus.filter((f) => f.chat !== null && is(f.chat, station, thread, v.session));
      const visible = showing.some((f) => f.visible);
      if (visible !== v.visible) {
        v.said.clear();
        v.started.clear();
        v.statuses.clear();
        if (visible) v.resumedAt = this.#host.nowMs();
        v.visible = visible;
      }
      if (showing.length === 0) this.visits.delete(key);
    }
  }

  #showing(station: string, thread: number | null, session: string | null): Focus[] {
    return [...this.#focus.values()].filter((f) => f.chat !== null && is(f.chat, station, thread, session));
  }

  /// A chat's value as computed: its unread line goes in, and what it asks of the core comes back.
  chat(station: string, session: string | null, value: J): Due[] {
    const due: Due[] = [];
    const thread = value?.thread?.id;
    if (typeof thread !== "number") return due;
    const shown = this.#showing(station, thread, session);
    const known = typeof value.thread.read === "number" ? value.thread.read : 0;
    const messages: J[] = Array.isArray(value.messages) ? value.messages : [];
    const seq = (m: J) => (typeof m?.seq === "number" ? m.seq : 0);
    const now = this.#host.nowMs();
    const more = value.more === true;
    const unreadLine = (read: number, opened: number) => {
      if (more && (messages.length === 0 || seq(messages[0]) > read + 1)) return null;
      const m = messages.find((x) => seq(x) > read && typeof x.createdAt === "number" && x.createdAt <= opened && x.mine !== true);
      return m === undefined ? null : seq(m);
    };
    value.unreadAbove = false;
    if (shown.length === 0) {
      value.unreadLine = unreadLine(known, now);
      return due;
    }
    const key = `${station}\u0001${thread}`;
    const newest = messages.length > 0 ? seq(messages[messages.length - 1]) : 0;
    let visit = this.visits.get(key);
    if (!visit) {
      visit = { at: now, read: known, session, top: newest, said: new Set(), visible: shown.some((f) => f.visible), resumedAt: null, statuses: new Map(), started: new Set() };
      this.visits.set(key, visit);
    }
    const caught = typeof value.caught === "number" ? value.caught : 0;
    for (const m of messages) {
      const n = seq(m);
      if (visit.visible && n > visit.top && n > caught && (visit.resumedAt === null || (typeof m.createdAt === "number" && m.createdAt >= visit.resumedAt))) visit.said.add(n);
    }
    visit.top = Math.max(visit.top, newest);
    for (const m of messages) if (visit.said.has(seq(m))) m.said = true;
    for (const a of Array.isArray(value.agents) ? value.agents : []) {
      const k = a?.session?.key;
      if (typeof k !== "string") continue;
      const status = typeof a.status === "string" ? a.status : "";
      const running = status === "running";
      const was = visit.statuses.get(k);
      visit.statuses.set(k, status);
      if (!running) visit.started.delete(k);
      else if (was !== undefined && visit.visible && was !== "running" && (visit.resumedAt === null || (typeof a.since === "number" && a.since >= visit.resumedAt))) visit.started.add(k);
      if (visit.started.has(k)) a.started = true;
    }
    value.unreadLine = unreadLine(visit.read, visit.at);
    const short = value.newer === true;
    if (!short && shown.some((f) => f.visible && f.chat?.end === true) && newest > known) {
      const sent = this.#reads.get(key) ?? 0;
      if (sent < newest) {
        this.#reads.set(key, newest);
        due.push({ read: { thread, seq: newest } });
      }
    }
    return due;
  }

  /// What was due could not be done: asked again the next time.
  failed(station: string, due: Due): void {
    this.#reads.delete(`${station}\u0001${due.read.thread}`);
  }

  /// Notices new since the last look: whether any is to be shown now. `listened`: a page takes what is shown.
  noticed(added: J[], listened: boolean): boolean {
    if (!this.on() || !listened) return false;
    if (this.#pushing && !this.seen()) return false;
    const now = this.#host.nowMs();
    this.#show = this.#show.filter(([, at]) => now - at < SHOW_FOR_MS);
    const before = this.#show.length;
    for (const n of added) {
      if (!this.#currentHas(of(n))) continue;
      const station = typeof n.station === "string" ? n.station : "";
      const looking = this.#showing(station, typeof n.thread === "number" ? n.thread : null, typeof n.session === "string" ? n.session : null).some((f) => f.visible && f.focused);
      if (!looking) this.#show.push([structuredClone(n), now]);
    }
    return this.#show.length > before;
  }

  /// A page takes a notice to show: the first to ask.
  claim(id: string): boolean {
    const before = this.#show.length;
    this.#show = this.#show.filter(([n]) => n.id !== id);
    return this.#show.length < before;
  }

  /// A push came: shown unless notifications are off, a page is in view, or it is of another workspace.
  pushed(workspace: string | null): boolean {
    return this.on() && !this.seen() && (workspace === null || this.#currentHas(workspace));
  }
}

function of(notice: J): string {
  return typeof notice?.workspace === "string" ? notice.workspace : ofAddress(typeof notice?.station === "string" ? notice.station : "");
}
