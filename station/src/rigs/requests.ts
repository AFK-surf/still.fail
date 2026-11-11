// A chat's request for a rig (a station that only runs tasks, 2026-11-10; as a vault's grant and a phone's are asked): an agent asks with
// `station_use {station, reason}`, a card in its chat asks the rig's person (whoever added it), and they approve it for this
// chat for a time (idle or fixed, a vault's timeouts) or refuse it, from their app. What they approve is signed with
// a key on their own lock (client/core-ts/src/rig-form.ts) and brought to the rig, which checks it itself: this
// station only carries it, and a grant it wrote for itself is none there. Approved while the rig is away, the grant
// is kept here and brought as the rig is next heard (rigs/module.ts).
//
// The rig says when a grant ends (its time up, idle, taken back); this station says it in the chat and to the agent.
import type { DatabaseSync } from "node:sqlite";
import { type GrantBody, type RevokeBody, type Signed, type Timeout, TIMEOUT_DEFAULT, latest, timeoutRefusal, wellFormed } from "../../../client/core-ts/src/rig-form.ts";
import { UNDECIDED, threadAddress } from "../agents/instructions.ts";
import { CARD_OCCUPIED, cardPlace, postCard } from "../sessions/card-place.ts";
import type { CardOutcomeSaver } from "../store/card-outbox.ts";
import { STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";

export type Status = "pending" | "granted" | "denied" | "ended";
export type RigRequest = {
  id: string; ws: string; session: string; chat: string;
  /// The rig, as it was named when asked, and its person.
  rig: string; rigName: string; owner: string; ownerEmail: string;
  reason: string;
  /// What the agent asked for (the person may sign another).
  timeout: Timeout;
  at: number; status: Status; why?: string;
  /// The chat's title and who started it, as the card said them (what is signed names them).
  title: string; by: string;
  /// What the person's device signed as it approved this, with their own lock as that device has it: brought to the
  /// rig, which alone checks it. Carried, not read, here.
  signed?: Signed<GrantBody>; chain?: unknown[];
  /// Whether the rig took the grant (false: approved, the rig not reached yet), and until when it holds there at the
  /// latest (unix seconds).
  delivered?: boolean; until?: number;
  /// Its agent was told the rig was away as it was approved (told once).
  toldAway?: boolean;
  /// One of the rig's devices alone (devices/), and its name as asked: none, the rig itself.
  device?: string; deviceName?: string;
  thread?: number; cardTs?: string;
};

const SCHEMA = `CREATE TABLE IF NOT EXISTS rig_requests (
  id TEXT PRIMARY KEY,
  ws TEXT NOT NULL,
  session TEXT NOT NULL,
  rig TEXT NOT NULL,
  owner TEXT NOT NULL,
  status TEXT NOT NULL,
  body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rig_requests_by_session ON rig_requests (session, status);
CREATE INDEX IF NOT EXISTS rig_requests_by_rig ON rig_requests (rig, status);
CREATE INDEX IF NOT EXISTS rig_requests_by_owner ON rig_requests (owner, status);`;

/// The most a statement with its person's lock takes (bytes of JSON): a lock is a chain of a person's devices.
const SIGNED_MAX = 512 * 1024;
/// A request no one decided is let go after a day, as a vault's.
const PENDING_SECS = 86400;

export class Refused extends Error {}

/// What it needs of the station: the chats (`hub`), the workspace's rigs, and how a statement reaches a rig.
export type RequestsDeps = {
  db: DatabaseSync;
  cardOutcomes?: CardOutcomeSaver;
  hub: {
    store: {
      getSession(key: string): { archivedAt?: number | null; ws: string | null } | null;
      starter(session: string): string | null;
      latestThread(session: string): SessionThread | null;
      latestThreadIfReady?(session: string): SessionThread | null | undefined;
      sessionThreadById(session: string, thread: number): SessionThread | null;
      pendingCardHeader(thread: number): [{ ts: string }, unknown] | null;
      pendingCardHeaderIfReady?(thread: number): [{ ts: string }, unknown] | null | undefined;
      insertMessage(m: Record<string, unknown>): number[];
      withdrawCard(agent: string, thread: number, ts: string): boolean;
      restateCard(agent: string, thread: number, ts: string, card: (was: any) => any): boolean;
      subscribe(f: (c: { type: string; key?: string; id?: number; ws?: string | null }) => void): void;
    };
    prepareLatestThreads?: ((sessions: readonly string[], signal?: AbortSignal) => Promise<void>) | null;
    prepareCardPosts?: ((threads: readonly number[], signal?: AbortSignal) => Promise<void>) | null;
    chat(connect: string): { post(where: { channel: string; threadTs: string }, text: string, files: string[]): Promise<string> };
    shared(thread: number, n: number, session: string, text: string): void;
    notify(session: string, text: string): void;
  };
  /// The station's home workspace (sessions from before workspace membership was recorded), and its own id.
  home(): string | null;
  self(): string;
  /// The chat's current name, or null before it has one.
  title(r: { session: string; chat: string }): string | null;
  /// A grant brought to its rig: until when it holds there (unix seconds). Rejects with a `Refused` when the rig
  /// refused it (final), anything else when it was not reached.
  bring(r: RigRequest): Promise<{ until: number }>;
  /// A grant given back, or one taken back by its person, told to its rig (kept and told again when not reached).
  release(r: RigRequest, revoke: { signed: Signed<RevokeBody>; chain?: unknown[] } | null): void;
  now(): number;
  /// A request changed: who shows the rigs is told.
  told?(r: RigRequest): void;
  id?(): string;
};

export class RigRequests {
  readonly #d: RequestsDeps;

  constructor(d: RequestsDeps) {
    this.#d = d;
    d.db.exec(SCHEMA);
    d.hub.store.subscribe((c) => {
      if ((c.type === "sessionRemoved" || c.type === "session") && typeof c.key === "string" && this.#gone(c.key)) {
        for (const r of this.#bySession(c.key)) this.#end(r, "对话已归档", true, false);
      }
    });
  }

  #secs(): number {
    return Math.floor(this.#d.now() / 1000);
  }

  #gone(session: string): boolean {
    const row = this.#d.hub.store.getSession(session);
    return row === null || row.archivedAt != null;
  }

  #save(r: RigRequest) {
    this.#d.db
      .prepare("INSERT INTO rig_requests (id, ws, session, rig, owner, status, body) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET status = excluded.status, body = excluded.body")
      .run(r.id, r.ws, r.session, r.rig, r.owner, r.status, JSON.stringify(r));
  }

  #load(sql: string, ...args: (string | number)[]): RigRequest[] {
    return (this.#d.db.prepare(sql).all(...args) as { body: string }[]).map((row) => JSON.parse(row.body) as RigRequest);
  }

  get(id: string): RigRequest | null {
    return this.#load("SELECT body FROM rig_requests WHERE id = ?", id)[0] ?? null;
  }

  #bySession(session: string): RigRequest[] {
    return this.#load("SELECT body FROM rig_requests WHERE session = ? AND status IN ('pending', 'granted')", session);
  }

  /// A pending request nobody decided within a day is let go as it is read; a granted one past its last second ended.
  #live(r: RigRequest): boolean {
    const now = this.#secs();
    if (r.status === "pending" && now - r.at >= PENDING_SECS) {
      this.#end(r, "一天内无人处理", false);
      return false;
    }
    if (r.status === "granted" && r.signed !== undefined && r.signed.body.exp <= now) {
      this.#end(r, "授权已到期", false);
      return false;
    }
    return r.status === "pending" || r.status === "granted";
  }

  /// A chat's requests for `rig` (or, `device` named, for that device of it alone) still open (asked, or granted).
  of(session: string, rig: string, device?: string): RigRequest[] {
    return this.#bySession(session).filter((r) => r.rig === rig && r.device === device && this.#live(r));
  }

  /// The requests of a workspace's rig still open, every chat's (who lists the rig shows them).
  ofRig(ws: string, rig: string): RigRequest[] {
    return this.#load("SELECT body FROM rig_requests WHERE rig = ? AND status IN ('pending', 'granted')", rig).filter((r) => r.ws === ws && this.#live(r));
  }

  /// The granted ones the rig has not taken yet (it was away as they were approved).
  undelivered(ws: string, rig: string): RigRequest[] {
    return this.ofRig(ws, rig).filter((r) => r.status === "granted" && r.delivered !== true);
  }

  /// station_use: a request asked in the session's chat, of the rig's person; not waited for (the agent's turn goes on),
  /// its decision told to the session. One already open for the rig is said again, not asked twice.
  async ask(session: string, rig: { id: string; name: string; owner: string; owner_email: string }, ws: string, reason: string, timeout: Timeout | undefined, signal?: AbortSignal, device?: { id: string; name: string }): Promise<RigRequest> {
    signal?.throwIfAborted();
    if (this.#gone(session)) throw new Refused("this chat is archived or gone");
    const open = this.of(session, rig.id, device?.id)[0];
    if (open !== undefined) return open;
    if (reason.trim() === "") throw new Refused(device === undefined ? "say what you will run on that station and why (reason)" : "say what you will do with the device and why (reason)");
    if (timeout !== undefined) {
      const why = timeoutRefusal(timeout);
      if (why !== null) throw new Refused(why);
    }
    let thread: SessionThread | null;
    const prepare = this.#d.hub.prepareLatestThreads;
    const ready = this.#d.hub.store.latestThreadIfReady;
    if (prepare && ready) {
      const found = ready.call(this.#d.hub.store, session);
      if (found === undefined) {
        await prepare([session], signal);
        signal?.throwIfAborted();
        if (this.#gone(session)) throw new Refused("this chat is archived or gone");
        return this.ask(session, rig, ws, reason, timeout, signal, device);
      }
      thread = found;
    } else thread = this.#d.hub.store.latestThread(session);
    if (thread === null) throw new Refused("this session has no chat to ask in");
    const chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
    const r: RigRequest = {
      id: this.#d.id?.() ?? `r_${this.#d.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
      ws, session, chat, rig: rig.id, rigName: rig.name, owner: rig.owner, ownerEmail: rig.owner_email.toLowerCase(), reason: reason.trim(),
      timeout: timeout ?? TIMEOUT_DEFAULT, at: this.#secs(), status: "pending",
      title: this.#d.title({ session, chat }) ?? "", by: this.#d.hub.store.starter(session) ?? "",
      ...(device !== undefined ? { device: device.id, deviceName: device.name } : {}),
    };
    this.#save(r);
    const posted = await this.#post(session, thread, r, signal);
    if (posted !== null) {
      r.thread = thread.thread.id;
      r.cardTs = posted;
      this.#save(r);
    }
    this.#d.told?.(r);
    return r;
  }

  async #post(session: string, thread: SessionThread, r: RigRequest, signal?: AbortSignal): Promise<string | null> {
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const whose = r.ownerEmail || r.owner;
    const what = r.device === undefined ? ` station「${r.rigName}」` : `设备「${r.deviceName ?? r.device}」（在 station「${r.rigName}」上）`;
    const text = [`申请使用${what}：${r.reason}`, ...(stillfail ? [] : [`请它的所有者 ${whose} 在 still.fail app 中批准。`])].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ label: "允许", detail: r.device === undefined ? "这个对话的 agent 可以在这台 station 上运行任务" : "这个对话的 agent 可以连接这台设备", recommended: true }, { label: "拒绝", detail: "通知 agent 已拒绝" }],
          assignee: r.ownerEmail,
          // The request as the app draws it, with what its person's device signs to approve it; its outcome added
          // once decided.
          rig: {
            request: r.id, rig: r.rig, name: r.rigName, owner: r.owner, reason: r.reason, timeout: r.timeout, ws: r.ws, station: this.#d.self(), session: r.session, chat: r.chat, title: r.title, by: r.by,
            ...(r.device !== undefined ? { device: r.device, deviceName: r.deviceName ?? "" } : {}),
          },
        }
      : null;
    return postCard(this.#d.hub, session, thread, text, card, null, undefined, signal);
  }

  #outcome(r: RigRequest): Record<string, unknown> {
    return {
      status: r.status, ...(r.why ? { why: r.why } : {}),
      ...(r.status === "granted" ? { timeout: r.signed?.body.timeout ?? r.timeout, delivered: r.delivered === true, ...(r.until !== undefined ? { until: r.until } : {}) } : {}),
    };
  }

  #saveAndRestate(r: RigRequest, close: boolean) {
    if (r.thread !== undefined && r.cardTs !== undefined && this.#d.cardOutcomes) {
      this.#d.cardOutcomes.save({ thread: r.thread, ts: r.cardTs, agent: r.session, field: "rig", close, outcome: this.#outcome(r) }, () => this.#save(r));
      return;
    }
    this.#save(r);
    if (r.thread !== undefined && r.cardTs !== undefined) {
      if (close) this.#d.hub.store.withdrawCard(r.session, r.thread, r.cardTs);
      const outcome = this.#outcome(r);
      this.#d.hub.store.restateCard(r.session, r.thread, r.cardTs, (card) => ({ ...card, rig: { ...card?.rig, outcome } }));
    }
  }

  /// Whether the request's card still waits in its chat; null on a surface without one.
  cardPending(r: RigRequest): boolean | null {
    const place = cardPlace(this.#d.hub.store, r.session, r.thread, r.cardTs);
    if (place === undefined || place === null) return null;
    if (place.state === "other") throw new Refused(CARD_OCCUPIED);
    return place.state === "same";
  }

  /// The rig's person (`sub`) decides request `id`: `signed` (with their lock, `chain`) grants it, none refuses it.
  /// Why it is not taken, or null. Granted, it is brought to the rig at once (`delivered` says whether it got there).
  async decide(sub: string, id: string, workspace: string, signed: unknown, chain: unknown): Promise<string | null> {
    const r = this.get(id);
    if (r === null || r.ws !== workspace) return "no such request";
    if (r.owner !== sub) return "only the rig's owner decides who uses it";
    if (r.status !== "pending") return `the request is ${r.status} already`;
    if (signed === undefined || signed === null) {
      this.#settle(r, "denied");
      return null;
    }
    if (this.#gone(r.session)) return "the chat is archived";
    if (!wellFormed("grant", signed) || JSON.stringify([signed, chain ?? null]).length > SIGNED_MAX) return "not a rig's grant";
    const s = signed as Signed<GrantBody>;
    const b = s.body;
    if (b.sub !== sub || b.ws !== r.ws || b.rig !== r.rig || b.station !== this.#d.self() || b.session !== r.session || b.chat !== r.chat || b.request !== r.id || b.title !== r.title || b.by !== r.by || b.device !== r.device) return "signed for something else than this request";
    if (b.exp > latest(b.at, b.timeout)) return "signed for longer than its timeout";
    if (b.exp <= this.#secs()) return "the grant has expired";
    r.signed = s;
    if (Array.isArray(chain)) r.chain = chain;
    r.delivered = false;
    r.status = "granted";
    this.#save(r);
    await this.deliver(r);
    return null;
  }

  /// A granted request brought to its rig. Taken: its agent told it may use the rig. Refused there (what was signed
  /// does not hold for the rig): the request ends as refused, with why. Not reached: it waits, its agent told so once.
  async deliver(given: RigRequest): Promise<void> {
    let r = given;
    try {
      const { until } = await this.#d.bring(r);
      const now = this.get(r.id);
      if (now === null || now.status !== "granted") return;
      r = now;
      r.delivered = true;
      r.until = until;
      this.#settle(r, "granted");
    } catch (error) {
      const now = this.get(r.id);
      if (now === null || now.status !== "granted" || now.delivered === true) return;
      r = now;
      if (error instanceof Refused) {
        r.why = `这台 station 拒绝了这份授权：${error.message}`;
        delete r.signed;
        delete r.chain;
        this.#settle(r, "denied");
        return;
      }
      // Away: said once, as it was approved; brought again as the rig is next heard.
      if (r.toldAway !== true) {
        r.toldAway = true;
        this.#settle(r, "granted");
      }
    }
  }

  /// The rig's person takes a grant (signed: the rig takes it back on that) or a request still asked (no signature
  /// needed to refuse) of their rig back.
  revoke(sub: string, id: string, workspace: string, signed: unknown, chain: unknown): string | null {
    const r = this.get(id);
    if (r === null || r.ws !== workspace) return "no such request";
    if (r.owner !== sub) return "only the rig's owner takes a grant of it back";
    if (r.status === "pending") {
      r.why = "所有者已拒绝";
      this.#settle(r, "denied");
      return null;
    }
    if (r.status !== "granted") return `the request is ${r.status} already`;
    if (!wellFormed("revoke", signed)) return "not a rig's revoke";
    const s = signed as Signed<RevokeBody>;
    if (s.body.sub !== sub || s.body.ws !== r.ws || s.body.rig !== r.rig || s.body.request !== r.id) return "signed for something else than this grant";
    this.#end(r, "所有者已收回", false, true, { signed: s, ...(Array.isArray(chain) ? { chain } : {}) });
    return null;
  }

  /// The chat's agent is done with the rig (`station_use {done: true}`): its grant, or a request still asked, ends.
  /// `device`: that device's alone (undefined: the rig's, with no device; null: either; "*": any device's, none of a
  /// rig itself).
  release(session: string, rig: string | null, device: string | null | undefined = null): RigRequest[] {
    const ended = this.#bySession(session).filter((r) => (rig === null || r.rig === rig) && (device === null || (device === "*" ? r.device !== undefined : r.device === device)) && this.#live(r));
    for (const r of ended) this.#end(r, "agent 已交还", true, false);
    return ended;
  }

  /// The rig says a grant ended there (`why`: its time up, idle, taken back), or no longer lists one this station
  /// brought it.
  endedThere(id: string, why: string): void {
    const r = this.get(id);
    if (r === null || r.status !== "granted" || r.delivered !== true) return;
    this.#end(r, why, false);
  }

  /// The rig's own word on a grant it holds: until when, if the chat uses it no more.
  heldThere(id: string, until: number): void {
    const r = this.get(id);
    if (r === null || r.status !== "granted" || r.delivered !== true || r.until === until) return;
    r.until = until;
    this.#saveAndRestate(r, false);
    this.#d.told?.(r);
  }

  /// `tell`: whether the rig is told (it is not when it said so itself). `revoke`: what its person signed taking it back.
  #end(r: RigRequest, why: string, tell: boolean, notify = true, revoke: { signed: Signed<RevokeBody>; chain?: unknown[] } | null = null) {
    if (r.status !== "granted" && r.status !== "pending") return;
    const was = r.status;
    r.why = why;
    if (was === "granted" && (tell || revoke !== null)) this.#d.release(r, revoke);
    this.#settle(r, was === "pending" ? "denied" : "ended", notify);
  }

  #settle(r: RigRequest, status: Status, notify = true) {
    r.status = status;
    if (status === "ended" || status === "denied") {
      delete r.signed;
      delete r.chain;
    }
    this.#saveAndRestate(r, true);
    if (notify) {
      try {
        this.#d.hub.notify(r.session, said(r));
      } catch {
        // The session is gone: nobody to tell.
      }
    }
    this.#d.told?.(r);
  }
}

/// How long a timeout is, in words an agent reads.
export function lasting(t: Timeout): string {
  const minutes = t.seconds / 60;
  const span = minutes % 1440 === 0 ? `${minutes / 1440} d` : minutes % 60 === 0 ? `${minutes / 60} h` : `${minutes} min`;
  return t.kind === "idle" ? `until this chat has used it for nothing for ${span} (a task of yours still running there is use)` : `for ${span}`;
}

/// What the agent is told of its request.
export function said(r: RigRequest): string {
  const whose = r.ownerEmail || r.owner;
  if (r.device !== undefined) return deviceSaid(r, whose);
  switch (r.status) {
    case "granted":
      if (r.delivered !== true) return `Your request ${r.id} for the tasks-only station ${r.rigName} was approved by ${whose}, but it is not reached now: the grant is brought to it when it is back, and you are told then. Do not ask again.`;
      return `Your request ${r.id} for the tasks-only station ${r.rigName} was granted by ${whose} (${lasting(r.signed?.body.timeout ?? r.timeout)}): use it as any station, by its name, with station_task, station_file, peer_forward and secret_use's station. Done with it, call station_use with done: true.`;
    case "denied":
      return `Your request ${r.id} for the tasks-only station ${r.rigName} was refused${r.why ? ` (${r.why})` : ""}.`;
    case "ended":
      return `Your grant ${r.id} of the tasks-only station ${r.rigName} ended (${r.why ?? "ended"}): what this chat ran there was stopped, and it takes nothing more from this chat. What a task left there (its log, files to bring back) is still read with station_task and station_file. Ask again with station_use if it is still needed.`;
    default:
      return `Your request ${r.id} for the tasks-only station ${r.rigName} waits for its owner ${whose} to approve it on the card in your chat. ${UNDECIDED}`;
  }
}

/// What the agent is told of its request for one of a rig's devices.
function deviceSaid(r: RigRequest, whose: string): string {
  const what = `the device ${r.deviceName ?? r.device} (on the tasks-only station ${r.rigName})`;
  switch (r.status) {
    case "granted":
      if (r.delivered !== true) return `Your request ${r.id} for ${what} was approved by ${whose}, but that station is not reached now: the grant is brought to it when it is back, and you are told then. Do not ask again.`;
      return `Your request ${r.id} for ${what} was granted by ${whose} (${lasting(r.signed?.body.timeout ?? r.timeout)}): call device_use again with the device for where it is reached here. Done with it, call device_use with done: true.`;
    case "denied":
      return `Your request ${r.id} for ${what} was refused${r.why ? ` (${r.why})` : ""}.`;
    case "ended":
      return `Your grant ${r.id} of ${what} ended (${r.why ?? "ended"}): its port here is closed. Ask again with device_use if it is still needed.`;
    default:
      return `Your request ${r.id} for ${what} waits for its owner ${whose} to approve it on the card in your chat. ${UNDECIDED}`;
  }
}
