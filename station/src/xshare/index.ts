// Chats shared with other workspaces (docs/chat-share.md). As stations share profiles and skills (share/index.ts), it
// is between the stations only, over the station transport; the control plane says nothing of it beyond each
// workspace's own stations.
//
// - The station a chat is on (its host) keeps whom it is shared with (stillfail.db `chat_shares`), the stations of each
//   of those workspaces (state.json `guests`: given first by the client of the person who shared it, a member of both,
//   then kept current by those stations themselves, `xshare.roster`), and which of them it told of which version
//   (`hosted[chat].told`). It tells each (`xshare.changed`) when a chat is shared, changed or no longer, the ones that
//   did not answer again later; and answers their reads and writes of the chats shared with them, nothing else.
// - A station a chat is shared with keeps which station it is from (`borrowed`), asks that station once a run what it
//   shares (`xshare.list`), and tells it the stations of its workspace whenever they change. It takes a station's word
//   only once a member of its workspace said to (`hosts`, PUT /xshare/hosts on one of its stations; the others ask that
//   one, `xshare.trusts`).
// - A session that wrote to a session of another workspace may be answered by it (`replies`): that station may send it
//   messages.
// - Each of these lapses once unused for XSHARE_IDLE_MS (6 hours): a chat's share with a workspace whose agents neither
//   read it nor wrote to it (store/store.ts `used`; a person shares it again), and an answer to a session that neither
//   wrote nor was answered (`answered`).
// - A station in several workspaces (docs/multi-workspace.md): a chat shared from here is its own workspace's (what its
//   link names); one shared with this station is the workspace's that took it (`as`: the workspace a member of which
//   said to take chats from its host, which its sessions alone see), the home one for what was kept before. Requests
//   for a session of one of those say so (`as`), as the host may share this station's other workspaces too. A chat
//   shared with another workspace of this same station is listed there without being asked of anyone.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Clock } from "effect";
import type { Cloud } from "../cloud/state.ts";
import { Refused } from "../jobs/remote.ts";
import { Fibers } from "../ops/fibers.ts";
import { writePrivate } from "../ops/files.ts";
import { log } from "../ops/log.ts";
import { LAPSED, XSHARE_IDLE_MS } from "../store/rows.ts";
import type { ChatShare, Store } from "../store/store.ts";

type Json = any;

/// What could not be told because another station did not answer is told again after this, then twice as long each
/// time up to RETRY_MAX_MS (only while there is).
const RETRY_MS = 60_000;
const RETRY_MAX_MS = 30 * 60_000;
/// At most this many workspaces for one chat, stations for one workspace, sessions answered from outside.
const MAX_TO = 16;
const MAX_STATIONS = 64;
const MAX_REPLIES = 2000;

export type Station = { id: string; name: string };
/// A workspace a chat is shared with, as the client that shared it names it.
export type Target = { workspace: string; name: string; stations: Station[] };
/// A chat of another workspace shared with this one, as the agents' chat_list shows it.
/// `as`: the workspace of this station's it is shared with (absent: the home one, as kept before).
export type Borrowed = { workspace: string; workspaceName: string; station: string; chat: string; title: string; link: string; write: boolean; version: number; as?: string };
type Hosted = { version: number; hash: string; told: Record<string, number> };
/// `as`: the workspace of this station's whose member said so (absent: the home one, as kept before).
type Host = { workspace: string; name: string; stationName: string; as?: string };
type State = {
  /// The stations of each workspace something is shared with: id → name.
  guests: Record<string, { name: string; stations: Record<string, string> }>;
  /// Each chat shared from here: its version, and each station told of it at which version.
  hosted: Record<string, Hosted>;
  /// Chats shared with this station's workspaces, by `<as>/<station>/<chat>` (`<station>/<chat>` kept from before).
  borrowed: Record<string, Borrowed>;
  /// Stations of other workspaces a member said this workspace takes chats from, by `<as>/<station>` (`<station>`
  /// kept from before: the home workspace's).
  hosts: Record<string, Host>;
  /// Sessions here that wrote to another workspace's, and the stations they wrote to (those may answer).
  replies: Record<string, string[]>;
  /// When each of those last wrote there or was answered from there, by session and station (none kept from before:
  /// when this station started).
  answered: Record<string, Record<string, number>>;
  /// The stations of this station's workspace each host was told last, as their hash, by `<as>/<host>`.
  roster: Record<string, string>;
};

export type XshareDeps = {
  data: string;
  store: Store;
  /// Which workspaces this station is in, their stations (cloud.json).
  cloud: Cloud;
  /// The workspace a chat of this station is in (by the session key its link names); absent: the home one.
  chatWs?: (chat: string) => string | null;
  /// A request to another station: of this workspace, or of another with `request.workspace` its.
  ask: (station: string, request: Json) => Promise<Json>;
  /// The link and the title a chat goes by (by the session key its link names); a link is null outside a workspace.
  link: (chat: string) => string | null;
  title: (chat: string) => string;
  /// The chats (by the session keys their links name) a session.* request of another station reads or writes in.
  touches: (request: Json) => string[];
  /// Where session.* requests go once allowed (as they do from the stations of this workspace, for any of its chats).
  inbox: (peer: string, request: Json) => Promise<Json>;
  clock?: Clock.Clock;
};

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const hashOf = (v: unknown) => createHash("sha256").update(JSON.stringify(v)).digest("hex");
const text = (v: unknown, max = 200) => (typeof v === "string" ? Array.from(v.trim()).slice(0, max).join("") : "");
/// A station's id (its iroh public key, hex) or a workspace's id: what can be a path segment of a link.
const isId = (v: unknown): v is string => typeof v === "string" && /^[0-9A-Za-z_-]{1,128}$/.test(v);

/// The stations a request names, checked: [{id, name}], at least one.
function stationsOf(v: unknown): Station[] {
  if (!Array.isArray(v) || v.length === 0 || v.length > MAX_STATIONS) throw new Error(`stations: 1 to ${MAX_STATIONS}, each {id, name}`);
  return v.map((s: Json) => {
    if (!isId(s?.id)) throw new Error("a station's id is its public key");
    return { id: s.id, name: text(s?.name, 80) || s.id.slice(0, 8) };
  });
}

/// A chat's link as a still.fail link names it: …/o/<workspace>/<station>/<key>.
function linkParts(link: string): { workspace: string; station: string; chat: string } | null {
  const m = /\/o\/([^/?#\s]+)\/([^/?#\s]+)\/([^/?#\s]+)/u.exec(link);
  return m ? { workspace: m[1]!, station: m[2]!, chat: decodeURIComponent(m[3]!) } : null;
}

export class ChatShares {
  private deps: XshareDeps;
  private time: Fibers;
  private retry: (() => void) | null = null;
  private retryMs = RETRY_MS;
  private stops: (() => void)[] = [];
  private reconciling: Promise<void> | null = null;
  private again = false;
  /// Hosts asked what they share in this run.
  private listed = new Set<string>();
  /// How often each host said something changed (xshare.changed), so a list asked for before is not taken over it.
  private heard = new Map<string, number>();
  private state: State | null = null;
  /// Shares that lapsed by this time were told of (their views changed); the next to lapse is waited for.
  private lapsed = 0;
  private lapsing: (() => void) | null = null;

  constructor(deps: XshareDeps) {
    this.deps = deps;
    this.time = new Fibers("xshare", deps.clock);
    this.lapsed = this.time.now();
  }

  private get root() {
    return join(this.deps.data, "xshare");
  }

  /// The one copy of state.json in memory, read at the first use and written through.
  private readState(): State {
    if (this.state) return this.state;
    const empty: State = { guests: {}, hosted: {}, borrowed: {}, hosts: {}, replies: {}, answered: {}, roster: {} };
    try {
      const s = JSON.parse(readFileSync(join(this.root, "state.json"), "utf8"));
      for (const k of Object.keys(empty) as (keyof State)[]) if (isObject(s[k])) (empty as any)[k] = s[k];
    } catch {}
    const now = this.time.now();
    for (const [session, stations] of Object.entries(empty.replies)) {
      const at = (empty.answered[session] ??= {});
      for (const station of Array.isArray(stations) ? stations : []) at[station] ??= now;
    }
    this.state = empty;
    return empty;
  }

  private writeState() {
    mkdirSync(this.root, { recursive: true });
    writePrivate(join(this.root, "state.json"), JSON.stringify(this.readState(), null, 2));
  }

  /// The workspace this station was enrolled in first: what was kept before workspaces were told apart is its.
  private home(): string | null {
    return this.deps.cloud.home();
  }

  /// This station's id.
  private station(): string | null {
    return this.deps.cloud.state?.station ?? null;
  }

  /// What one of this station's workspaces is called.
  private nameOf(ws: string): string {
    return this.deps.cloud.membership(ws)?.workspace_name ?? ws;
  }

  /// The workspace a chat of this station is in.
  private chatWs(chat: string): string | null {
    return this.deps.chatWs?.(chat) ?? this.home();
  }

  /// The workspace of this station's a chat borrowed or a host said is for.
  private asOf(b: { as?: string }): string | null {
    return b.as ?? this.home();
  }

  /// The host a member of workspace `as` said to take chats from, and its key in `hosts`.
  private hostOf(station: string, as: string | null): [string, Host] | null {
    const state = this.readState();
    for (const [key, h] of Object.entries(state.hosts)) if (this.hostKey(key, h)[1] === station && this.asOf(h) === as) return [key, h];
    return null;
  }

  /// The station a key in `hosts` is of, with the workspace of this station's it is for.
  private hostKey(key: string, h: Host): [string | null, string] {
    const at = key.indexOf("/");
    return [this.asOf(h), at < 0 ? key : key.slice(at + 1)];
  }

  /// The workspace a station that is not of workspace `as` (absent: the home one) is in, as far as this one knows;
  /// null when it knows none.
  workspaceOf(station: string, as?: string | null): string | null {
    const a = as === undefined ? this.home() : as;
    const host = this.hostOf(station, a);
    if (host) return host[1].workspace;
    const borrowed = Object.values(this.readState().borrowed).find((b) => b.station === station && this.asOf(b) === a);
    if (borrowed) return borrowed.workspace;
    return this.guestOf(station);
  }

  /// The workspace a station is in that chats here are shared with, or null.
  private guestOf(station: string): string | null {
    for (const [workspace, g] of Object.entries(this.readState().guests)) if (station in g.stations) return workspace;
    return null;
  }

  /// The workspaces chats here are shared with that a station asks for: the one it says it asks for (`as`), when it is
  /// one of its stations; else every one it is a station of.
  private guestsOf(station: string, as: unknown): string[] {
    const guests = this.readState().guests;
    if (typeof as === "string") return station in (guests[as]?.stations ?? {}) ? [as] : [];
    return Object.entries(guests).flatMap(([workspace, g]) => (station in g.stations ? [workspace] : []));
  }

  /// Whether this station may ask `target` of workspace `workspace` (not its own) anything: a station chats are
  /// shared from or with.
  reaches(target: string, workspace: string): boolean {
    const state = this.readState();
    if (Object.entries(state.hosts).some(([key, h]) => this.hostKey(key, h)[1] === target && h.workspace === workspace)) return true;
    if (Object.values(state.borrowed).some((b) => b.station === target && b.workspace === workspace)) return true;
    return target in (state.guests[workspace]?.stations ?? {});
  }

  /// A request to another station as it is sent: to one of another workspace with that workspace, noting (for
  /// session.message) that it may answer the session that wrote. `request.workspace`, when given, is the one of this
  /// station's it is asked for (a session's); a station of another goes the shared way only, saying for which (`as`).
  address(station: string, request: Json): Json {
    const as = typeof request?.workspace === "string" ? request.workspace : this.home();
    const own = as === null ? null : this.deps.cloud.membership(as);
    // Out of it (or a station of it): the transport says.
    if (own === null || own.peers.some((p: Json) => p?.id === station)) return request;
    const workspace = this.workspaceOf(station, as);
    if (workspace === null) return request;
    if (request?.method === "session.message" && typeof request?.session === "string") this.noteSent(request.session, station);
    // For which of this station's workspaces, when it is not plain: not the home one, or the host's is one of this
    // station's too (it would take the request for one of that workspace's).
    return as !== this.home() || this.deps.cloud.membership(workspace) !== null ? { ...request, workspace, as } : { ...request, workspace };
  }

  private noteSent(session: string, station: string) {
    const state = this.readState();
    const had = state.replies[session] ?? [];
    if (!had.includes(station)) state.replies[session] = [...had, station];
    (state.answered[session] ??= {})[station] = this.time.now();
    const keys = Object.keys(state.replies);
    for (const k of keys.slice(0, Math.max(0, keys.length - MAX_REPLIES))) {
      delete state.replies[k];
      delete state.answered[k];
    }
    this.writeState();
  }

  /// Whether `station` may answer session `session` here: it wrote to it, and it or that station spoke within
  /// XSHARE_IDLE_MS (which it does now, from when it goes on).
  private answers(session: string, station: string): boolean {
    const state = this.readState();
    if (!(state.replies[session] ?? []).includes(station)) return false;
    const now = this.time.now();
    if (now - (state.answered[session]?.[station] ?? 0) >= XSHARE_IDLE_MS) return false;
    (state.answered[session] ??= {})[station] = now;
    this.writeState();
    return true;
  }

  // ── running ──

  start() {
    this.lapseLater();
    this.stops.push(this.deps.cloud.listen(() => void this.reconcile()));
    this.stops.push(
      this.deps.store.subscribe((change) => {
        // A shared chat's name changed: told again. Its session deleted: no longer shared.
        if (change.type === "thread") {
          const home = this.deps.store.getThread(change.id)?.home ?? null;
          if (home !== null && this.deps.store.chatShare(home) !== null) void this.reconcile();
        } else if (change.type === "sessionRemoved" && (this.deps.store.chatShare(change.key) !== null || this.deps.store.chatShareLapsed(change.key, null))) {
          this.deps.store.setChatShare(change.key, [], false, "");
          void this.reconcile();
        }
      }),
    );
    void this.reconcile();
  }

  async close() {
    for (const stop of this.stops.splice(0)) stop();
    this.lapsing?.();
    await this.time.close();
  }

  /// Once the next share lapses (unused too long), its chat's views change and its workspace's stations are told it is
  /// no longer shared with them.
  private lapseLater() {
    this.lapsing?.();
    this.lapsing = null;
    const next = this.deps.store.lapseChatShares(this.lapsed);
    this.lapsed = this.time.now();
    if (next === null) return;
    this.lapsing = this.time.after(next - this.lapsed, () => {
      this.lapsing = null;
      this.lapseLater();
      void this.reconcile();
    });
  }

  /// Brings what is told and asked in line: one at a time, again if asked meanwhile.
  reconcile(): Promise<void> {
    if (this.reconciling) {
      this.again = true;
      return this.reconciling;
    }
    this.reconciling = (async () => {
      do {
        this.again = false;
        try {
          await this.reconcileOnce();
        } catch (e) {
          log.warn("xshare", "bringing chat shares in line failed", { error: (e as Error).message });
        }
      } while (this.again);
    })().finally(() => (this.reconciling = null));
    return this.reconciling;
  }

  private async reconcileOnce() {
    const me = this.station();
    if (this.home() === null || me === null) return;
    const state = this.readState();
    let pending = false;
    const tell = async (station: string, workspace: string, request: Json): Promise<boolean> => {
      try {
        await this.deps.ask(station, { ...request, workspace });
        return true;
      } catch (e) {
        pending = true;
        log.info("xshare", "a station of another workspace was not told", { station, error: (e as Error).message });
        return false;
      }
    };

    // The chats shared from here: each station of the workspaces they are for told of their version, the ones no
    // longer for it that they are not.
    const shares = this.deps.store.chatShares();
    for (const [chat, share] of shares) {
      const link = this.deps.link(chat);
      if (link === null) continue;
      const title = this.deps.title(chat);
      const hash = hashOf({ to: share.to.map((t) => t.workspace).sort(), write: share.write, title, link });
      const hosted = (state.hosted[chat] ??= { version: 0, hash: "", told: {} });
      if (hosted.hash !== hash) {
        hosted.version += 1;
        hosted.hash = hash;
      }
      this.writeState();
      const audience = this.audience(share);
      // Of the workspace it is in.
      const from = this.chatWs(chat) ?? "";
      for (const [station, workspace] of audience) {
        if (hosted.told[station] === hosted.version) continue;
        const said = { method: "xshare.changed", chat, version: hosted.version, title, link, write: share.write, from, fromName: this.nameOf(from) };
        if (await tell(station, workspace, said)) hosted.told[station] = hosted.version;
      }
      for (const station of Object.keys(hosted.told)) {
        if (audience.has(station)) continue;
        const workspace = this.guestOf(station);
        if (workspace === null || (await tell(station, workspace, { method: "xshare.changed", chat, gone: true }))) delete hosted.told[station];
      }
    }
    for (const [chat, hosted] of Object.entries(state.hosted)) {
      if (shares.has(chat)) continue;
      for (const station of Object.keys(hosted.told)) {
        const workspace = this.guestOf(station);
        if (workspace === null || (await tell(station, workspace, { method: "xshare.changed", chat, gone: true }))) delete hosted.told[station];
      }
      if (Object.keys(hosted.told).length === 0) delete state.hosted[chat];
    }
    // Workspaces nothing is shared with any more, once told so: forgotten (those a share with lapsed are answered why).
    const used = new Set([...shares.values()].flatMap((s) => s.to.map((t) => t.workspace)));
    for (const workspace of this.deps.store.lapsedShareWorkspaces()) used.add(workspace);
    for (const [workspace, g] of Object.entries(state.guests)) {
      if (used.has(workspace)) continue;
      if (Object.values(state.hosted).some((h) => Object.keys(h.told).some((st) => st in g.stations))) continue;
      delete state.guests[workspace];
    }
    this.writeState();

    // The chats shared with this station's workspaces: each host asked once a run what it shares (what changed while
    // this station was away), and told the stations of the workspace that takes them when they changed.
    const hosts = new Map<string, { as: string; host: string; workspace: string }>();
    for (const b of Object.values(state.borrowed)) {
      const as = this.asOf(b);
      if (as !== null) hosts.set(`${as}/${b.station}`, { as, host: b.station, workspace: b.workspace });
    }
    for (const [key, h] of Object.entries(state.hosts)) {
      const [as, host] = this.hostKey(key, h);
      if (as !== null && !hosts.has(`${as}/${host}`)) hosts.set(`${as}/${host}`, { as, host, workspace: h.workspace });
    }
    for (const [key, { as, host, workspace }] of hosts) {
      // A workspace this station is out of asks nothing.
      if (this.deps.cloud.membership(as) === null) continue;
      const ofHost = (b: Borrowed) => b.station === host && this.asOf(b) === as;
      if (!this.listed.has(key)) {
        const mark = this.heard.get(key) ?? 0;
        try {
          const got = await this.deps.ask(host, { method: "xshare.list", workspace, as });
          this.listed.add(key);
          this.took(host, workspace, as, got, (this.heard.get(key) ?? 0) === mark);
        } catch (e) {
          if (!(e instanceof Refused)) pending = true;
          else if ((this.heard.get(key) ?? 0) === mark) {
            // It shares nothing with this workspace (any more).
            this.listed.add(key);
            for (const [k, b] of Object.entries(state.borrowed)) if (ofHost(b)) delete state.borrowed[k];
          }
        }
      }
      const roster = this.roster(as);
      if (roster !== null && Object.values(state.borrowed).some(ofHost) && state.roster[key] !== roster.hash) {
        try {
          await this.deps.ask(host, { method: "xshare.roster", workspace, stations: roster.stations, as });
          state.roster[key] = roster.hash;
        } catch (e) {
          if (!(e instanceof Refused)) pending = true;
        }
      }
    }
    for (const key of Object.keys(state.roster)) if (!hosts.has(key)) delete state.roster[key];
    this.writeState();

    if (!pending) this.retryMs = RETRY_MS;
    else if (this.retry === null) {
      const wait = this.retryMs;
      this.retryMs = Math.min(this.retryMs * 2, RETRY_MAX_MS);
      this.retry = this.time.after(wait, () => {
        this.retry = null;
        void this.reconcile();
      });
    }
  }

  /// The stations a chat is shared with now: each with its workspace (this one, in another of its workspaces, is told
  /// nothing: it has the chat).
  private audience(share: ChatShare): Map<string, string> {
    const state = this.readState();
    const me = this.station();
    const out = new Map<string, string>();
    for (const t of share.to) for (const station of Object.keys(state.guests[t.workspace]?.stations ?? {})) if (station !== me) out.set(station, t.workspace);
    return out;
  }

  /// The stations of workspace `as` (one of this station's) as the control plane said last, and their hash; null while
  /// that is not current.
  private roster(as: string): { stations: Station[]; hash: string } | null {
    const cloud = this.deps.cloud;
    const of = cloud.membership(as);
    if (!cloud.peersCurrent || of === null) return null;
    const stations = (of.peers ?? []).flatMap((p: Json) => (isId(p?.id) ? [{ id: p.id as string, name: text(p?.name, 80) || p.id.slice(0, 8) }] : []));
    if (stations.length === 0) return null;
    return { stations, hash: hashOf(stations.map((s: Station) => s.id).sort()) };
  }

  /// What a host answered xshare.list with: its chats shared with workspace `as` of this station's, in place of what
  /// was had from it (`whole`); added to it, the newer of each, when the host said something changed meanwhile.
  private took(host: string, workspace: string, as: string, got: Json, whole: boolean) {
    const state = this.readState();
    if (whole) for (const [k, b] of Object.entries(state.borrowed)) if (b.station === host && this.asOf(b) === as) delete state.borrowed[k];
    const chats: Json[] = Array.isArray(got?.chats) ? got.chats : [];
    for (const c of chats) {
      const b = this.borrowedFrom(host, workspace, text(got?.fromName, 80) || workspace, c);
      if (b === null) continue;
      const had = this.borrowedAt(host, b.chat, as);
      if (whole || (had?.[1].version ?? -1) < b.version) {
        if (had) delete state.borrowed[had[0]];
        state.borrowed[`${as}/${host}/${b.chat}`] = { ...b, as };
      }
    }
    this.writeState();
  }

  /// A chat borrowed from `host` for workspace `as`, with its key.
  private borrowedAt(host: string, chat: string, as: string): [string, Borrowed] | null {
    for (const [k, b] of Object.entries(this.readState().borrowed)) if (b.station === host && b.chat === chat && this.asOf(b) === as) return [k, b];
    return null;
  }

  /// A chat as its host describes it, checked: its link must be of that host and workspace.
  private borrowedFrom(host: string, workspace: string, workspaceName: string, c: Json): Borrowed | null {
    const chat = text(c?.chat, 200);
    const link = text(c?.link, 1000);
    const parts = linkParts(link);
    if (chat === "" || parts === null || parts.station !== host || parts.workspace !== workspace) return null;
    return { workspace, workspaceName, station: host, chat, title: text(c?.title, 200) || chat, link, write: c?.write === true, version: Number(c?.version ?? 0) };
  }

  // ── requests ──

  /// A request of a station of one of this station's workspaces (`workspace`: which; absent: the home one): whether a
  /// station of another one is one that workspace takes chats from. A station in that other workspace too asks the rest
  /// as a station of it (as another workspace's would).
  async inside(peer: string, request: Json, workspace?: string): Promise<Json> {
    const method = String(request?.method ?? "");
    if (method === "xshare.trusts") {
      const host = this.hostOf(String(request?.station ?? ""), workspace ?? this.home());
      if (!host) return { trusted: false };
      const { workspace: of, name, stationName } = host[1];
      return { trusted: true, workspace: of, name, stationName };
    }
    if (method.startsWith("xshare.")) return this.outside(peer, request, workspace);
    throw new Error(`unknown request ${method}`);
  }

  /// A request of a station that is not of this workspace (`workspace`: the one of this station's it names; absent:
  /// the home one): only what is shared with its workspace, or an answer to a session here that wrote to it.
  async outside(peer: string, request: Json, workspace?: string): Promise<Json> {
    const method = String(request?.method ?? "");
    const here = workspace ?? this.home();
    if (method === "xshare.changed") return this.changed(peer, request, here);
    const to = typeof request?.to === "string" ? request.to : "";
    if ((method === "session.message" || method === "session.put") && this.answers(to, peer)) return this.deps.inbox(peer, request);
    const guests = this.guestsOf(peer, request?.as);
    if (guests.length === 0) throw new Error("this station shares no chat with your workspace");
    switch (method) {
      case "describe":
        return { protocol: 1, outside: true, reads: true, messages: true, files: true };
      case "xshare.list":
        return this.list(peer, here, guests);
      case "xshare.roster":
        return this.rosterOf(peer, guests[0]!, request);
      case "session.read":
      case "session.file":
        this.check(guests, request, false);
        return this.deps.inbox(peer, request);
      case "session.put":
      case "session.message":
        this.check(guests, request, true);
        return this.deps.inbox(peer, request);
    }
    throw new Error(`${method} is not open to other workspaces: only reading and writing in the chats shared with them`);
  }

  /// Whether a request reads (or writes in) a chat shared with one of `workspaces`; throws why not. Its share goes on
  /// from now.
  private check(workspaces: string[], request: Json, write: boolean) {
    const store = this.deps.store;
    const chats = this.deps.touches(request);
    const shared = chats.flatMap((c) => {
      const s = store.chatShare(c);
      return s !== null && s.to.some((t) => workspaces.includes(t.workspace)) ? [{ chat: c, share: s }] : [];
    });
    if (shared.length === 0) {
      if (chats.some((c) => store.chatShareLapsed(c, workspaces))) throw new Error(LAPSED);
      throw new Error("that chat is not shared with your workspace");
    }
    if (write && !shared.some((s) => s.share.write)) throw new Error("that chat is shared with your workspace to read only: nothing can be sent to it");
    for (const { chat } of shared) store.usedChatShare(chat, workspaces);
  }

  /// xshare.list: the chats of workspace `here` (null: the home one) shared with the asking station's workspaces; it
  /// has them now.
  private list(peer: string, here: string | null, workspaces: string[]): Json {
    const state = this.readState();
    const chats: Json[] = [];
    for (const [chat, share] of this.deps.store.chatShares()) {
      if (!share.to.some((t) => workspaces.includes(t.workspace)) || this.chatWs(chat) !== here) continue;
      const link = this.deps.link(chat);
      if (link === null) continue;
      const hosted = state.hosted[chat];
      chats.push({ chat, title: this.deps.title(chat), link, write: share.write, version: hosted?.version ?? 0 });
      if (hosted) hosted.told[peer] = hosted.version;
    }
    this.writeState();
    return { from: here ?? "", fromName: here === null ? "" : this.nameOf(here), chats };
  }

  /// xshare.roster: the stations of the asking station's workspace now, in place of those known; the new ones are told.
  private rosterOf(peer: string, workspace: string, request: Json): Json {
    const stations = stationsOf(request?.stations);
    if (!stations.some((s) => s.id === peer)) throw new Error("the stations given must include the one giving them");
    const state = this.readState();
    state.guests[workspace] = { name: state.guests[workspace]?.name ?? workspace, stations: Object.fromEntries(stations.map((s) => [s.id, s.name])) };
    this.writeState();
    void this.reconcile();
    return { ok: true };
  }

  /// xshare.changed: a host says a chat is shared with workspace `as` of this station's, changed, or no longer is.
  private async changed(peer: string, request: Json, as: string | null): Promise<Json> {
    if (as === null || this.deps.cloud.membership(as) === null) throw new Error("this station is in no workspace");
    const from = String(request?.from ?? "");
    const state = this.readState();
    let host: Host | undefined = this.hostOf(peer, as)?.[1];
    if (!host && request?.gone !== true) {
      host = (await this.askTrust(peer, as)) ?? undefined;
      if (!host) throw new Error("no member of this workspace said to take chats from your station");
      state.hosts[`${as}/${peer}`] = { ...host, as };
    }
    const chat = text(request?.chat, 200);
    this.heard.set(`${as}/${peer}`, (this.heard.get(`${as}/${peer}`) ?? 0) + 1);
    const had = this.borrowedAt(peer, chat, as);
    if (request?.gone === true) {
      if (had) delete state.borrowed[had[0]];
    } else {
      if (from !== host!.workspace) throw new Error("your station is not of the workspace it was said to be");
      const b = this.borrowedFrom(peer, from, text(request?.fromName, 80) || host!.name, request);
      if (b === null) throw new Error("a chat's link must be of the station sharing it");
      if (had) delete state.borrowed[had[0]];
      state.borrowed[`${as}/${peer}/${chat}`] = { ...b, as };
    }
    this.writeState();
    void this.reconcile();
    return { heard: true };
  }

  /// Whether another station of workspace `as` was told to take chats from `station`: its word on it.
  private async askTrust(station: string, as: string): Promise<Host | null> {
    const me = this.station();
    const of = this.deps.cloud.membership(as);
    if (of === null || !this.deps.cloud.peersCurrent) return null;
    const peers = (of.peers ?? []).flatMap((p: Json) => (typeof p?.id === "string" && p.id !== me ? [p.id as string] : []));
    const answers = await Promise.all(peers.map((p: string) => this.deps.ask(p, { method: "xshare.trusts", station, workspace: as }).catch(() => null)));
    const yes = answers.find((a) => a?.trusted === true && isId(a?.workspace));
    return yes ? { workspace: yes.workspace, name: text(yes.name, 80) || yes.workspace, stationName: text(yes.stationName, 80) } : null;
  }

  // ── the pages ──

  /// Shares chat `chat` (by the session key its link names) with workspaces `to` (none: no longer), as `by`.
  async share(chat: string, to: Target[], write: boolean, by: string): Promise<ChatShare | null> {
    if (this.home() === null) throw new Error("this station is in no workspace");
    if (to.length > MAX_TO) throw new Error(`at most ${MAX_TO} workspaces`);
    const state = this.readState();
    // Its own workspace is the one it is in.
    const own = this.chatWs(chat);
    for (const t of to) {
      if (!isId(t.workspace) || t.workspace === own) throw new Error("to: other workspaces, each {workspace, name, stations}");
      state.guests[t.workspace] = { name: t.name, stations: Object.fromEntries(stationsOf(t.stations).map((s) => [s.id, s.name])) };
    }
    this.writeState();
    this.deps.store.setChatShare(chat, to.map((t) => ({ workspace: t.workspace, name: text(t.name, 80) || t.workspace })), write, by);
    this.lapseLater();
    void this.reconcile();
    return this.deps.store.chatShare(chat);
  }

  /// A member of workspace `as` of this station's (absent: the home one) says it takes chats from `station`, of
  /// workspace `workspace`; it is asked what it shares.
  async trust(workspace: string, name: string, station: string, stationName: string, as?: string): Promise<void> {
    const of = as ?? this.home();
    if (of === null || this.deps.cloud.membership(of) === null) throw new Error("this station is in no workspace");
    if (!isId(workspace) || workspace === of || !isId(station)) throw new Error("workspace and station are another workspace's");
    const state = this.readState();
    const had = this.hostOf(station, of);
    if (had) delete state.hosts[had[0]];
    state.hosts[`${of}/${station}`] = { workspace, name: text(name, 80) || workspace, stationName: text(stationName, 80), as: of };
    this.listed.delete(`${of}/${station}`);
    this.writeState();
    void this.reconcile();
  }

  /// The chats of other workspaces shared with workspace `as` of this station's (absent: the home one), the latest
  /// first: those of other stations, and those of this one's other workspaces.
  borrowed(as?: string | null): Borrowed[] {
    const of = as ?? this.home();
    const state = this.readState();
    const theirs = Object.values(state.borrowed).filter((b) => this.asOf(b) === of);
    const me = this.station();
    const ours: Borrowed[] = [];
    if (of !== null && me !== null) {
      for (const [chat, share] of this.deps.store.chatShares()) {
        const ws = this.chatWs(chat);
        const link = this.deps.link(chat);
        if (ws === null || ws === of || link === null || !share.to.some((t) => t.workspace === of)) continue;
        ours.push({ workspace: ws, workspaceName: this.nameOf(ws), station: me, chat, title: this.deps.title(chat), link, write: share.write, version: state.hosted[chat]?.version ?? 0, as: of });
      }
    }
    return [...theirs, ...ours].sort((a, b) => b.version - a.version);
  }
}
