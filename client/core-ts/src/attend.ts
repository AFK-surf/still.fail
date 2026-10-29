// Where the viewer's attention is, and what follows from it (attend.rs; the `notify` topic, `client.focus`): a
// chat's unread line, what is read, what comes in with a motion while a chat shows, which notices a page shows now,
// and the workspace the viewer is in. Whether notifications are on, whether the system was asked, and which
// workspaces are heard of, are kept on the device.
import { Deferred, Effect } from "effect";
import type { ChatOf, FocusCall, Permission } from "./attend-parse.ts";
import type { Host } from "./host.ts";
import type { ClientId } from "./protocol.ts";
import { t } from "./i18n.ts";
import { parseJson, toJsonBytes } from "./util.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// Where the settings are kept (host storage).
const KEY = "notify";
/// A notice no page took this long is not shown any more.
const SHOW_FOR_MS = 30_000;

/// Which notices are shown (docs/notifications.md): a card or an agent needing them (wait, block), something gone
/// wrong, a turn done (never, only while no page of the app is in front, or always), someone else saying something.
export type Kinds = { wait: boolean; failed: boolean; done: "off" | "away" | "always"; message: boolean };
export const ALL_KINDS: Kinds = { wait: true, failed: true, done: "away", message: true };

/// `preview`: a notice says what was said; off, only what kind of thing happened (as a phone's 「显示预览」). `muted`:
/// the workspaces not heard of (each one is unless turned off, those joined later too).
type Settings = { on: boolean; asked: boolean; kinds: Kinds; preview: boolean; muted: string[] };

/// The workspaces turned off, as kept or given: `changes` (a workspace's id → heard of) on top of `base`.
function mutedOf(base: string[], changes: J): string[] {
  const muted = new Set(base.filter((w) => typeof w === "string"));
  if (changes !== null && typeof changes === "object") for (const [w, on] of Object.entries(changes)) if (typeof on === "boolean") on ? muted.delete(w) : muted.add(w);
  return [...muted].sort();
}

/// Kinds as given (or kept): what is not given stays as `base` has it.
export function kindsOf(v: J, base: Kinds = ALL_KINDS): Kinds {
  const k = v !== null && typeof v === "object" ? v : {};
  const flag = (name: "wait" | "failed" | "message") => (typeof k[name] === "boolean" ? k[name] : base[name]);
  return { wait: flag("wait"), failed: flag("failed"), done: ["off", "away", "always"].includes(k.done) ? k.done : base.done, message: flag("message") };
}

/// A notice's body with `preview` off: what kind of thing happened, not what was said.
function hidden(kind: unknown): string {
  return t(kind === "wait" || kind === "block" ? "core-misc.notice.hidden.wait" : kind === "failed" ? "core-misc.notice.hidden.failed" : kind === "message" ? "core-misc.notice.hidden.message" : "core-misc.notice.hidden.done");
}

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
  /// Made here as it showed (its station had no thread for it yet): an agent first seen at work in it started while it
  /// shows, as none was there before; until it is out of view.
  made: boolean;
};

/// What a chat's value asks of the core once computed: a read position recorded (its end shown on a page in front).
export type Due = { read: { thread: number; seq: number } };

export class Attend {
  readonly #host: Host;
  #settings: Settings;
  #pushing = false;
  /// What the system lets this device do, as its app last said (`notify.permission`); not kept: said again each start.
  #permission: Permission = "unknown";
  readonly #focus = new Map<ClientId, Focus>();
  /// Done when a page comes into view again (`untilShown`).
  #shownAgain = Deferred.makeUnsafe<void>();
  /// Done when no page is in view any more (`untilHidden`).
  #hiddenNow = Deferred.makeUnsafe<void>();
  readonly visits = new Map<string, Visit>();
  readonly #reads = new Map<string, number>();
  #show: [J, number][] = [];
  /// Chats being made, shown before their station has a thread for them, by station and session: their agents, once
  /// there, start while they show.
  readonly #making = new Set<string>();

  private constructor(host: Host, settings: Settings) {
    this.#host = host;
    this.#settings = settings;
  }

  static load(host: Host): Effect.Effect<Attend> {
    return Effect.map(Effect.orElseSucceed(host.storageGet(KEY), () => null), (bytes) => {
      const kept = parseJson(bytes) as J;
      const settings = kept && typeof kept.on === "boolean" ? { on: kept.on, asked: kept.asked === true, kinds: kindsOf(kept.kinds), preview: kept.preview !== false, muted: Array.isArray(kept.muted) ? mutedOf(kept.muted, null) : [] } : { on: true, asked: false, kinds: { ...ALL_KINDS }, preview: true, muted: [] };
      return new Attend(host, settings);
    });
  }

  on(): boolean {
    return this.#settings.on;
  }

  /// What this device shows of notices, as its push registration says it (the cloud makes a push to it so).
  shows(): { kinds: Kinds; preview: boolean; muted: string[] } {
    return { kinds: { ...this.#settings.kinds }, preview: this.#settings.preview, muted: [...this.#settings.muted] };
  }

  /// Whether a workspace's notices are heard of on this device.
  heard(workspace: string): boolean {
    return !this.#settings.muted.includes(workspace);
  }

  /// The `notify` topic: the settings, whether this device should hold a push registration, what to show now.
  /// `nameOf`: a workspace's name, put before the title of a notice of a workspace the viewer is not in.
  value(nameOf: (workspace: string) => string | null = () => null): J {
    const now = this.#host.nowMs();
    const show = this.#show.filter(([, at]) => now - at < SHOW_FOR_MS).map(([n]) => {
      const out = this.#settings.preview ? structuredClone(n) : { ...structuredClone(n), body: hidden(n.kind) };
      return { ...out, title: this.titled(of(n), out.title, nameOf) };
    });
    return { on: this.#settings.on, asked: this.#settings.asked, push: this.#settings.on, kinds: { ...this.#settings.kinds }, preview: this.#settings.preview, muted: [...this.#settings.muted], permission: this.#permission, show };
  }

  /// A notice's title as shown: of a workspace the viewer is not in, that workspace's name first.
  titled(workspace: string, title: unknown, nameOf: (workspace: string) => string | null): string {
    const text = typeof title === "string" ? title : "";
    const name = workspace === "" || this.#currentHas(workspace) ? null : nameOf(workspace);
    return name ? t("core-misc.notice.elsewhere", { workspace: name, title: text }) : text;
  }

  /// Changes the settings and keeps them; `workspaces`: a workspace's id → heard of, each given changing.
  set(on: boolean | null, asked: boolean | null, kinds: J = null, preview: boolean | null = null, workspaces: J = null): Effect.Effect<void> {
    const s = { on: on ?? this.#settings.on, asked: asked ?? this.#settings.asked, kinds: kinds === null ? this.#settings.kinds : kindsOf(kinds, this.#settings.kinds), preview: preview ?? this.#settings.preview, muted: mutedOf(this.#settings.muted, workspaces) };
    this.#settings = s;
    if (!s.on) this.#show = [];
    else this.#show = this.#show.filter(([n]) => this.heard(of(n)));
    return Effect.ignore(this.#host.storageSet(KEY, toJsonBytes(s)), { log: "Unhandled", message: "attention kept" });
  }

  /// The app found what the system allows; whether that changed.
  permit(state: Permission): boolean {
    if (state === this.#permission) return false;
    this.#permission = state;
    return true;
  }

  setPushing(on: boolean): void {
    this.#pushing = on;
  }

  /// Any page in view.
  seen(): boolean {
    return [...this.#focus.values()].some((f) => f.visible);
  }

  /// Any page in view, or none said where it is (a UI that never says is taken as looking): what is measured only to
  /// be shown (a station's connection) is measured only then.
  shown(): boolean {
    return this.#focus.size === 0 || this.seen();
  }

  /// Returns once a page is in view (at once if one is).
  untilShown(): Effect.Effect<void> {
    return this.shown() ? Effect.void : Deferred.await(this.#shownAgain);
  }

  /// Returns once no page is in view (never while one is).
  untilHidden(): Effect.Effect<void> {
    return this.shown() ? Deferred.await(this.#hiddenNow) : Effect.void;
  }

  #told(): void {
    if (!this.shown()) {
      Deferred.doneUnsafe(this.#hiddenNow, Effect.void);
      this.#hiddenNow = Deferred.makeUnsafe<void>();
      return;
    }
    Deferred.doneUnsafe(this.#shownAgain, Effect.void);
    this.#shownAgain = Deferred.makeUnsafe<void>();
  }

  /// Whether a notice of this kind is shown at all; `inFront`: a page of the app is in front (a turn done is shown
  /// then only with `done: always`).
  wants(kind: unknown, inFront: boolean): boolean {
    const k = this.#settings.kinds;
    if (kind === "wait" || kind === "block") return k.wait;
    if (kind === "failed") return k.failed;
    if (kind === "message") return k.message;
    return k.done === "always" || (k.done === "away" && !inFront);
  }

  /// Any page in front: shown and focused.
  #inFront(): boolean {
    return [...this.#focus.values()].some((f) => f.visible && f.focused);
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
    this.#told();
  }

  /// A UI went away.
  gone(client: ClientId): void {
    this.#focus.delete(client);
    this.#endVisits();
    this.#told();
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
        v.made = false;
        if (visible) v.resumedAt = this.#host.nowMs();
        v.visible = visible;
      }
      if (showing.length === 0) this.visits.delete(key);
    }
    for (const key of [...this.#making]) {
      const at = key.indexOf("\u0001");
      if (!focus.some((f) => f.visible && f.chat !== null && is(f.chat, key.slice(0, at), null, key.slice(at + 1)))) this.#making.delete(key);
    }
  }

  #showing(station: string, thread: number | null, session: string | null): Focus[] {
    return [...this.#focus.values()].filter((f) => f.chat !== null && is(f.chat, station, thread, session));
  }

  /// A chat's value as computed, with its unread line (and what was said and started while it showed) put in, and
  /// what it asks of the core.
  chat(station: string, session: string | null, value: J): { due: Due[]; value: J } {
    const due: Due[] = [];
    const thread = value?.thread?.id;
    if (typeof thread !== "number") {
      // (being made, shown: its agents, there once it is made, start while it shows)
      if (session !== null && this.#showing(station, null, session).some((f) => f.visible)) this.#making.add(`${station}\u0001${session}`);
      return { due, value };
    }
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
    const out: J = { ...value, unreadAbove: false };
    if (shown.length === 0) {
      out.unreadLine = unreadLine(known, now);
      return { due, value: out };
    }
    const key = `${station}\u0001${thread}`;
    const newest = messages.length > 0 ? seq(messages[messages.length - 1]) : 0;
    let visit = this.visits.get(key);
    if (!visit) {
      const made = session !== null && this.#making.delete(`${station}\u0001${session}`);
      visit = { at: now, read: known, session, top: newest, said: new Set(), visible: shown.some((f) => f.visible), resumedAt: null, statuses: new Map(), started: new Set(), made };
      this.visits.set(key, visit);
    }
    const caught = typeof value.caught === "number" ? value.caught : 0;
    for (const m of messages) {
      const n = seq(m);
      if (visit.visible && n > visit.top && n > caught && (visit.resumedAt === null || (typeof m.createdAt === "number" && m.createdAt >= visit.resumedAt))) visit.said.add(n);
    }
    visit.top = Math.max(visit.top, newest);
    if (messages.some((m) => visit.said.has(seq(m)))) out.messages = messages.map((m) => (visit.said.has(seq(m)) ? { ...m, said: true } : m));
    const agents: J[] = Array.isArray(value.agents) ? value.agents : [];
    const started: J[] = [];
    for (const a of agents) {
      const k = a?.session?.key;
      if (typeof k !== "string") continue;
      const status = typeof a.status === "string" ? a.status : "";
      const running = status === "running";
      const was = visit.statuses.get(k);
      visit.statuses.set(k, status);
      if (!running) visit.started.delete(k);
      // (one first seen at work: at work already as the chat came into view, unless the chat was made as it showed)
      else if ((was === undefined ? visit.made : was !== "running") && visit.visible && (visit.resumedAt === null || (typeof a.since === "number" && a.since >= visit.resumedAt))) visit.started.add(k);
      if (visit.started.has(k)) started.push(a);
    }
    if (started.length > 0) out.agents = agents.map((a) => (started.includes(a) ? { ...a, started: true } : a));
    out.unreadLine = unreadLine(visit.read, visit.at);
    // Read only on a page in front (shown and focused): a window left open on the chat behind others, or on another
    // screen, is not being looked at. Read up to its newest while its end shows, and up to a message shown whole
    // (`seen`) whether the end does or not: a message seen whole is read.
    const short = value.newer === true;
    let upTo = 0;
    for (const f of shown) {
      if (!f.visible || !f.focused || f.chat === null) continue;
      if (!short && f.chat.end === true) upTo = Math.max(upTo, newest);
      if (typeof f.chat.seen === "number") upTo = Math.max(upTo, Math.min(f.chat.seen, newest));
    }
    if (upTo > known) {
      const sent = this.#reads.get(key) ?? 0;
      if (sent < upTo) {
        this.#reads.set(key, upTo);
        due.push({ read: { thread, seq: upTo } });
      }
    }
    return { due, value: out };
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
      if (!this.heard(of(n)) || !this.wants(n.kind, this.#inFront())) continue;
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

  /// A push came: shown unless notifications are off, a page is in view, its kind is off, or its workspace is.
  pushed(workspace: string | null, kind: string | null = null): boolean {
    return this.on() && !this.seen() && (kind === null || this.wants(kind, false)) && (workspace === null || this.heard(workspace));
  }
}

function of(notice: J): string {
  return typeof notice?.workspace === "string" ? notice.workspace : ofAddress(typeof notice?.station === "string" ? notice.station : "");
}
