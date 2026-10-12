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
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Clock } from "effect";
import type { Cloud } from "../cloud/state.ts";
import { Refused } from "../jobs/remote.ts";
import { Fibers } from "../ops/fibers.ts";
import { writePrivate } from "../ops/files.ts";
import { log } from "../ops/log.ts";
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
export type Borrowed = { workspace: string; workspaceName: string; station: string; chat: string; title: string; link: string; write: boolean; version: number };
type Hosted = { version: number; hash: string; told: Record<string, number> };
type Host = { workspace: string; name: string; stationName: string };
type State = {
  /// The stations of each workspace something is shared with: id → name.
  guests: Record<string, { name: string; stations: Record<string, string> }>;
  /// Each chat shared from here: its version, and each station told of it at which version.
  hosted: Record<string, Hosted>;
  /// Chats shared with this workspace, by `<station>/<chat>`.
  borrowed: Record<string, Borrowed>;
  /// Stations of other workspaces a member said this workspace takes chats from.
  hosts: Record<string, Host>;
  /// Sessions here that wrote to another workspace's, and the stations they wrote to (those may answer).
  replies: Record<string, string[]>;
  /// The stations of this workspace each host was told last, as their hash.
  roster: Record<string, string>;
};

export type XshareDeps = {
  data: string;
  store: Store;
  /// Which workspace this station is in, its stations (cloud.json).
  cloud: Cloud;
  /// A request to another station: of this workspace, or of another with `request.workspace` its.
  ask: (station: string, request: Json) => Promise<Json>;
  /// The link and the title a chat goes by (by the session key its link names); a link is null outside a workspace.
  link: (chat: string) => string | null;
  title: (chat: string) => string;
  /// The chats (by the session keys their links name) a session.* request of another station reads or writes in.
  touches: (request: Json) => string[];
  /// Where session.* requests go once allowed (as they do from the stations of this workspace).
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

  constructor(deps: XshareDeps) {
    this.deps = deps;
    this.time = new Fibers("xshare", deps.clock);
  }

  private get root() {
    return join(this.deps.data, "xshare");
  }

  /// The one copy of state.json in memory, read at the first use and written through.
  private readState(): State {
    if (this.state) return this.state;
    const empty: State = { guests: {}, hosted: {}, borrowed: {}, hosts: {}, replies: {}, roster: {} };
    try {
      const s = JSON.parse(readFileSync(join(this.root, "state.json"), "utf8"));
      for (const k of Object.keys(empty) as (keyof State)[]) if (isObject(s[k])) (empty as any)[k] = s[k];
    } catch {}
    this.state = empty;
    return empty;
  }

  private writeState() {
    mkdirSync(this.root, { recursive: true });
    writePrivate(join(this.root, "state.json"), JSON.stringify(this.readState(), null, 2));
  }

  private own(): { workspace: string; name: string; station: string } | null {
    const s = this.deps.cloud.state;
    if (s === null || this.deps.cloud.removed()) return null;
    return { workspace: s.workspace, name: s.workspace_name, station: s.station };
  }

  /// The workspace a station that is not this workspace's is in, as far as this one knows; null when it knows none.
  workspaceOf(station: string): string | null {
    const state = this.readState();
    if (state.hosts[station]) return state.hosts[station].workspace;
    const borrowed = Object.values(state.borrowed).find((b) => b.station === station);
    if (borrowed) return borrowed.workspace;
    return this.guestOf(station);
  }

  /// The workspace a station is in that chats here are shared with, or null.
  private guestOf(station: string): string | null {
    for (const [workspace, g] of Object.entries(this.readState().guests)) if (station in g.stations) return workspace;
    return null;
  }

  /// Whether this station may ask `target` of workspace `workspace` (not its own) anything: a station chats are
  /// shared from or with.
  reaches(target: string, workspace: string): boolean {
    return this.workspaceOf(target) === workspace;
  }

  /// A request to another station as it is sent: to one of another workspace with that workspace, noting (for
  /// session.message) that it may answer the session that wrote.
  address(station: string, request: Json): Json {
    const s = this.deps.cloud.state;
    if (s !== null && s.peers.some((p: Json) => p?.id === station)) return request;
    const workspace = this.workspaceOf(station);
    if (workspace === null) return request;
    if (request?.method === "session.message" && typeof request?.session === "string") this.noteSent(request.session, station);
    return { ...request, workspace };
  }

  private noteSent(session: string, station: string) {
    const state = this.readState();
    const had = state.replies[session] ?? [];
    if (had.includes(station)) return;
    state.replies[session] = [...had, station];
    const keys = Object.keys(state.replies);
    for (const k of keys.slice(0, Math.max(0, keys.length - MAX_REPLIES))) delete state.replies[k];
    this.writeState();
  }

  // ── running ──

  start() {
    this.stops.push(this.deps.cloud.listen(() => void this.reconcile()));
    this.stops.push(
      this.deps.store.subscribe((change) => {
        // A shared chat's name changed: told again. Its session deleted: no longer shared.
        if (change.type === "thread") {
          const home = this.deps.store.getThread(change.id)?.home ?? null;
          if (home !== null && this.deps.store.chatShare(home) !== null) void this.reconcile();
        } else if (change.type === "sessionRemoved" && this.deps.store.chatShare(change.key) !== null) {
          this.deps.store.setChatShare(change.key, [], false, "");
          void this.reconcile();
        }
      }),
    );
    void this.reconcile();
  }

  async close() {
    for (const stop of this.stops.splice(0)) stop();
    await this.time.close();
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
    const own = this.own();
    if (own === null) return;
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
      for (const [station, workspace] of audience) {
        if (hosted.told[station] === hosted.version) continue;
        const said = { method: "xshare.changed", chat, version: hosted.version, title, link, write: share.write, from: own.workspace, fromName: own.name };
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
    // Workspaces nothing is shared with any more, once told so: forgotten.
    const used = new Set([...shares.values()].flatMap((s) => s.to.map((t) => t.workspace)));
    for (const [workspace, g] of Object.entries(state.guests)) {
      if (used.has(workspace)) continue;
      if (Object.values(state.hosted).some((h) => Object.keys(h.told).some((st) => st in g.stations))) continue;
      delete state.guests[workspace];
    }
    this.writeState();

    // The chats shared with this workspace: each host asked once a run what it shares (what changed while this
    // station was away), and told this workspace's stations when they changed.
    const roster = this.roster();
    const hosts = new Map<string, string>();
    for (const b of Object.values(state.borrowed)) hosts.set(b.station, b.workspace);
    for (const [station, h] of Object.entries(state.hosts)) if (!hosts.has(station)) hosts.set(station, h.workspace);
    for (const [host, workspace] of hosts) {
      if (!this.listed.has(host)) {
        const mark = this.heard.get(host) ?? 0;
        try {
          const got = await this.deps.ask(host, { method: "xshare.list", workspace });
          this.listed.add(host);
          this.took(host, workspace, got, (this.heard.get(host) ?? 0) === mark);
        } catch (e) {
          if (!(e instanceof Refused)) pending = true;
          else if ((this.heard.get(host) ?? 0) === mark) {
            // It shares nothing with this workspace (any more).
            this.listed.add(host);
            for (const [k, b] of Object.entries(state.borrowed)) if (b.station === host) delete state.borrowed[k];
          }
        }
      }
      if (roster !== null && Object.values(state.borrowed).some((b) => b.station === host) && state.roster[host] !== roster.hash) {
        try {
          await this.deps.ask(host, { method: "xshare.roster", workspace, stations: roster.stations });
          state.roster[host] = roster.hash;
        } catch (e) {
          if (!(e instanceof Refused)) pending = true;
        }
      }
    }
    for (const host of Object.keys(state.roster)) if (!hosts.has(host)) delete state.roster[host];
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

  /// The stations a chat is shared with now: each with its workspace.
  private audience(share: ChatShare): Map<string, string> {
    const state = this.readState();
    const out = new Map<string, string>();
    for (const t of share.to) for (const station of Object.keys(state.guests[t.workspace]?.stations ?? {})) out.set(station, t.workspace);
    return out;
  }

  /// This workspace's stations as the control plane said last, and their hash; null while that is not current.
  private roster(): { stations: Station[]; hash: string } | null {
    const cloud = this.deps.cloud;
    if (!cloud.peersCurrent || cloud.state === null) return null;
    const stations = (cloud.state.peers ?? []).flatMap((p: Json) => (isId(p?.id) ? [{ id: p.id as string, name: text(p?.name, 80) || p.id.slice(0, 8) }] : []));
    if (stations.length === 0) return null;
    return { stations, hash: hashOf(stations.map((s: Station) => s.id).sort()) };
  }

  /// What a host answered xshare.list with: its chats shared with this workspace, in place of what was had from it
  /// (`whole`); added to it, the newer of each, when the host said something changed meanwhile.
  private took(host: string, workspace: string, got: Json, whole: boolean) {
    const state = this.readState();
    if (whole) for (const [k, b] of Object.entries(state.borrowed)) if (b.station === host) delete state.borrowed[k];
    const chats: Json[] = Array.isArray(got?.chats) ? got.chats : [];
    for (const c of chats) {
      const b = this.borrowedFrom(host, workspace, text(got?.fromName, 80) || workspace, c);
      const key = `${host}/${b?.chat}`;
      if (b && (whole || (state.borrowed[key]?.version ?? -1) < b.version)) state.borrowed[key] = b;
    }
    this.writeState();
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

  /// A request of a station of this workspace: whether a station of another one is one this workspace takes chats from.
  async inside(_peer: string, request: Json): Promise<Json> {
    const method = String(request?.method ?? "");
    if (method === "xshare.trusts") {
      const host = this.readState().hosts[String(request?.station ?? "")];
      return host ? { trusted: true, ...host } : { trusted: false };
    }
    throw new Error(`unknown request ${method}`);
  }

  /// A request of a station that is not of this workspace: only what is shared with its workspace, or an answer to a
  /// session here that wrote to it.
  async outside(peer: string, request: Json): Promise<Json> {
    const method = String(request?.method ?? "");
    if (method === "xshare.changed") return this.changed(peer, request);
    const to = typeof request?.to === "string" ? request.to : "";
    if ((method === "session.message" || method === "session.put") && (this.readState().replies[to] ?? []).includes(peer)) return this.deps.inbox(peer, request);
    const workspace = this.guestOf(peer);
    if (workspace === null) throw new Error("this station shares no chat with your workspace");
    switch (method) {
      case "describe":
        return { protocol: 1, outside: true, reads: true, messages: true, files: true };
      case "xshare.list":
        return this.list(peer, workspace);
      case "xshare.roster":
        return this.rosterOf(peer, workspace, request);
      case "session.read":
      case "session.file":
        this.check(workspace, request, false);
        return this.deps.inbox(peer, request);
      case "session.put":
      case "session.message":
        this.check(workspace, request, true);
        return this.deps.inbox(peer, request);
    }
    throw new Error(`${method} is not open to other workspaces: only reading and writing in the chats shared with them`);
  }

  /// Whether a request reads (or writes in) a chat shared with `workspace`; throws why not.
  private check(workspace: string, request: Json, write: boolean) {
    const chats = this.deps.touches(request);
    const shares = chats.map((c) => this.deps.store.chatShare(c)).filter((s): s is ChatShare => s !== null && s.to.some((t) => t.workspace === workspace));
    if (shares.length === 0) throw new Error("that chat is not shared with your workspace");
    if (write && !shares.some((s) => s.write)) throw new Error("that chat is shared with your workspace to read only: nothing can be sent to it");
  }

  /// xshare.list: the chats shared with the asking station's workspace; it has them now.
  private list(peer: string, workspace: string): Json {
    const own = this.own();
    const state = this.readState();
    const chats: Json[] = [];
    for (const [chat, share] of this.deps.store.chatShares()) {
      if (!share.to.some((t) => t.workspace === workspace)) continue;
      const link = this.deps.link(chat);
      if (link === null) continue;
      const hosted = state.hosted[chat];
      chats.push({ chat, title: this.deps.title(chat), link, write: share.write, version: hosted?.version ?? 0 });
      if (hosted) hosted.told[peer] = hosted.version;
    }
    this.writeState();
    return { from: own?.workspace ?? "", fromName: own?.name ?? "", chats };
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

  /// xshare.changed: a host says a chat is shared with this workspace, changed, or no longer is.
  private async changed(peer: string, request: Json): Promise<Json> {
    const own = this.own();
    if (own === null) throw new Error("this station is in no workspace");
    const from = String(request?.from ?? "");
    const state = this.readState();
    let host: Host | undefined = state.hosts[peer];
    if (!host && request?.gone !== true) {
      host = (await this.askTrust(peer)) ?? undefined;
      if (!host) throw new Error("no member of this workspace said to take chats from your station");
      state.hosts[peer] = host;
    }
    const chat = text(request?.chat, 200);
    this.heard.set(peer, (this.heard.get(peer) ?? 0) + 1);
    if (request?.gone === true) {
      delete state.borrowed[`${peer}/${chat}`];
    } else {
      if (from !== host!.workspace) throw new Error("your station is not of the workspace it was said to be");
      const b = this.borrowedFrom(peer, from, text(request?.fromName, 80) || host!.name, request);
      if (b === null) throw new Error("a chat's link must be of the station sharing it");
      state.borrowed[`${peer}/${chat}`] = b;
    }
    this.writeState();
    void this.reconcile();
    return { heard: true };
  }

  /// Whether another station of this workspace was told to take chats from `station`: its word on it.
  private async askTrust(station: string): Promise<Host | null> {
    const s = this.deps.cloud.state;
    if (s === null || !this.deps.cloud.peersCurrent) return null;
    const peers = (s.peers ?? []).flatMap((p: Json) => (typeof p?.id === "string" && p.id !== s.station ? [p.id as string] : []));
    const answers = await Promise.all(peers.map((p: string) => this.deps.ask(p, { method: "xshare.trusts", station }).catch(() => null)));
    const yes = answers.find((a) => a?.trusted === true && isId(a?.workspace));
    return yes ? { workspace: yes.workspace, name: text(yes.name, 80) || yes.workspace, stationName: text(yes.stationName, 80) } : null;
  }

  // ── the pages ──

  /// Shares chat `chat` (by the session key its link names) with workspaces `to` (none: no longer), as `by`.
  async share(chat: string, to: Target[], write: boolean, by: string): Promise<ChatShare | null> {
    const own = this.own();
    if (own === null) throw new Error("this station is in no workspace");
    if (to.length > MAX_TO) throw new Error(`at most ${MAX_TO} workspaces`);
    const state = this.readState();
    for (const t of to) {
      if (!isId(t.workspace) || t.workspace === own.workspace) throw new Error("to: other workspaces, each {workspace, name, stations}");
      state.guests[t.workspace] = { name: t.name, stations: Object.fromEntries(stationsOf(t.stations).map((s) => [s.id, s.name])) };
    }
    this.writeState();
    this.deps.store.setChatShare(chat, to.map((t) => ({ workspace: t.workspace, name: text(t.name, 80) || t.workspace })), write, by);
    void this.reconcile();
    return this.deps.store.chatShare(chat);
  }

  /// A member of this workspace says it takes chats from `station`, of workspace `workspace`; it is asked what it shares.
  async trust(workspace: string, name: string, station: string, stationName: string): Promise<void> {
    const own = this.own();
    if (own === null) throw new Error("this station is in no workspace");
    if (!isId(workspace) || workspace === own.workspace || !isId(station)) throw new Error("workspace and station are another workspace's");
    const state = this.readState();
    state.hosts[station] = { workspace, name: text(name, 80) || workspace, stationName: text(stationName, 80) };
    this.listed.delete(station);
    this.writeState();
    void this.reconcile();
  }

  /// The chats of other workspaces shared with this one, the latest first.
  borrowed(): Borrowed[] {
    return Object.values(this.readState().borrowed).sort((a, b) => b.version - a.version);
  }
}
