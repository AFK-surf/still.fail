// A chat's grant of a person's phone (docs/adb-share.md, 2026-10-29: as vault grants are): an agent asks with
// `phone_use {reason}`, a card in its chat asks the person it works for (whoever started the chat), and they approve it
// for this chat for an hour or until the chat is archived, or refuse it, from their app. Only that chat's session holds
// the grant; it ends as its scope does, as the chat is archived or deleted, or as its owner takes it back. Asks,
// decisions and ends are told in the chat; the owner's devices hear of the grants (`adb-grants`), and their phone lends
// itself to the station while one is live.
import type { DatabaseSync } from "node:sqlite";
import { UNDECIDED, threadAddress } from "../agents/instructions.ts";
import { STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";

export type Scope = "hour" | "chat";
export const SCOPES: Scope[] = ["hour", "chat"];
/// How long a scope lasts at most (seconds): `chat` until the chat is archived, 30 days at the latest.
export const LASTS: Record<Scope, number> = { hour: 3600, chat: 30 * 86400 };
const SCOPE_WORDS: Record<Scope, { label: string; detail: string }> = {
  hour: { label: "本对话 1 小时内", detail: "1 小时内这个对话的 agent 可以用这台手机" },
  chat: { label: "本对话直到归档", detail: "这个对话归档或删除前都能用，最长 30 天" },
};

export type Status = "pending" | "granted" | "denied" | "ended";
export type PhoneRequest = {
  id: string; session: string; chat: string; owner: string; reason: string; at: number; status: Status;
  scope?: Scope; exp?: number; thread?: number; cardTs?: string; why?: string;
  /// Granted, how this station's adb holds the phone (link.ts `AdbState.adb`: `connected`, `unpaired`, `off`,
  /// `unauthorized`, `missing`, `failed`; `gone`: not offered here now; none yet: not heard since it was granted), and
  /// the last of them the agent was told of (`linked`).
  link?: string; toldLink?: string;
};

/// The ways the station's adb holds a phone that are said on its card and told to the agent; `connecting` is not (it
/// is tried again and again while unpaired, and says nothing new).
const LINKS = new Set(["connected", "unpaired", "off", "unauthorized", "missing", "failed", "gone"]);

const SCHEMA = `CREATE TABLE IF NOT EXISTS adb_requests (
  id TEXT PRIMARY KEY,
  session TEXT NOT NULL,
  owner TEXT NOT NULL,
  status TEXT NOT NULL,
  body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS adb_requests_by_owner ON adb_requests (owner, status);
CREATE INDEX IF NOT EXISTS adb_requests_by_session ON adb_requests (session, status);
CREATE TABLE IF NOT EXISTS adb_lasts (
  owner TEXT PRIMARY KEY,
  lasts TEXT NOT NULL,
  at INTEGER NOT NULL
);`;

/// What it needs of the station: the chats (`hub`), its time (ms), and who hears of a change (the owner's devices).
export type GrantsDeps = {
  db: DatabaseSync;
  hub: {
    store: {
      getSession(key: string): { archivedAt?: number | null } | null;
      participants(session: string): Map<string, string[]>;
      latestThread(session: string): SessionThread | null;
      insertMessage(m: Record<string, unknown>): number[];
      withdrawCard(agent: string, thread: number, ts: string): boolean;
      restateCard(agent: string, thread: number, ts: string, card: (was: any) => any): boolean;
      subscribe(f: (c: { type: string; key: string }) => void): void;
    };
    chat(connect: string): { post(where: { channel: string; threadTs: string }, text: string, files: string[]): Promise<string> };
    shared(thread: number, n: number, session: string, text: string): void;
    notify(session: string, text: string): void;
  };
  now(): number;
  told?(r: PhoneRequest): void;
  /// A request's id (tests give their own).
  id?(): string;
};

export class Refused extends Error {}

export class PhoneGrants {
  readonly #d: GrantsDeps;

  constructor(d: GrantsDeps) {
    this.#d = d;
    d.db.exec(SCHEMA);
    d.hub.store.subscribe((c) => {
      if ((c.type === "sessionRemoved" || c.type === "session") && this.#ended(c.key)) for (const r of this.#bySession(c.key)) this.#end(r, "对话已归档");
    });
  }

  #secs(): number {
    return Math.floor(this.#d.now() / 1000);
  }

  #ended(session: string): boolean {
    const row = this.#d.hub.store.getSession(session);
    return row === null || row.archivedAt != null;
  }

  #save(r: PhoneRequest) {
    this.#d.db
      .prepare("INSERT INTO adb_requests (id, session, owner, status, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET status = excluded.status, body = excluded.body")
      .run(r.id, r.session, r.owner, r.status, JSON.stringify(r));
  }

  #load(sql: string, ...args: (string | number)[]): PhoneRequest[] {
    return (this.#d.db.prepare(sql).all(...args) as { body: string }[]).map((row) => JSON.parse(row.body) as PhoneRequest);
  }

  get(id: string): PhoneRequest | null {
    return this.#load("SELECT body FROM adb_requests WHERE id = ?", id)[0] ?? null;
  }

  /// A granted request whose scope ran out is ended as it is read.
  #live(r: PhoneRequest): boolean {
    if (r.status !== "granted") return r.status === "pending";
    if ((r.exp ?? 0) <= this.#secs() || this.#ended(r.session)) {
      this.#end(r, (r.exp ?? 0) <= this.#secs() ? "授权已到期" : "对话已归档");
      return false;
    }
    return true;
  }

  #bySession(session: string): PhoneRequest[] {
    return this.#load("SELECT body FROM adb_requests WHERE session = ? AND status IN ('pending', 'granted')", session);
  }

  /// The grants live for `session` (the agent's), and those of `owner` (their devices': which chats their phone is lent to).
  held(session: string): PhoneRequest[] {
    return this.#bySession(session).filter((r) => r.status === "granted" && this.#live(r));
  }
  ofOwner(owner: string): PhoneRequest[] {
    return this.#load("SELECT body FROM adb_requests WHERE owner = ? AND status IN ('pending', 'granted')", owner.toLowerCase()).filter((r) => this.#live(r));
  }
  /// Every grant live now, of everyone (the phones lent to this station are lent for these).
  live(): PhoneRequest[] {
    return this.#load("SELECT body FROM adb_requests WHERE status = 'granted'").filter((r) => this.#live(r));
  }

  /// The longest `owner` lets a grant last (their 默认最长授权, as their app last said it): `chat` until they say.
  lastsOf(owner: string): Scope {
    const row = this.#d.db.prepare("SELECT lasts FROM adb_lasts WHERE owner = ?").get(owner.toLowerCase()) as { lasts: string } | undefined;
    return row?.lasts === "hour" ? "hour" : "chat";
  }

  /// `owner`'s 默认最长授权 set (`at`: when, on their device: the latest wins across their devices and stations).
  setLasts(owner: string, lasts: unknown, at: unknown): string | null {
    if (lasts !== "hour" && lasts !== "chat") return "lasts: hour or chat";
    const when = typeof at === "number" && Number.isFinite(at) ? Math.floor(at) : this.#d.now();
    this.#d.db
      .prepare("INSERT INTO adb_lasts (owner, lasts, at) VALUES (?, ?, ?) ON CONFLICT (owner) DO UPDATE SET lasts = excluded.lasts, at = excluded.at WHERE excluded.at >= adb_lasts.at")
      .run(owner.toLowerCase(), lasts, when);
    return null;
  }

  /// The person a session works for: whoever started its chat.
  starter(session: string): string | null {
    const first = this.#d.hub.store.participants(session).get(session)?.[0];
    return first === undefined ? null : first.toLowerCase();
  }

  /// phone_use: a grant of this session's already live, or a request asked in its chat: not waited for (the agent's turn
  /// goes on with the chat), its decision told to the session (#settle).
  async ask(session: string, reason: string): Promise<PhoneRequest> {
    const held = this.held(session)[0];
    if (held !== undefined) return held;
    if (reason.trim() === "") throw new Refused("say why you need the phone (reason)");
    const owner = this.starter(session);
    if (owner === null) throw new Refused("this chat has no person who started it: nobody to lend a phone");
    const thread = this.#d.hub.store.latestThread(session);
    if (thread === null) throw new Refused("this session has no chat to ask in");
    const pending = this.#bySession(session).find((r) => r.status === "pending");
    const r: PhoneRequest = pending ?? {
      id: this.#d.id?.() ?? `p_${this.#d.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
      session, chat: threadAddress(thread.thread.channel, thread.thread.threadTs), owner, reason: reason.trim(), at: this.#secs(), status: "pending",
    };
    if (pending === undefined) {
      this.#save(r);
      const posted = await this.#post(session, thread, r);
      if (posted !== null) {
        r.thread = thread.thread.id;
        r.cardTs = posted;
        this.#save(r);
      }
      this.#d.told?.(r);
    }
    return r;
  }

  async #post(session: string, thread: SessionThread, r: PhoneRequest): Promise<string | null> {
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const text = [`申请调试你的手机：${r.reason}`, ...(stillfail ? [] : ["请在 still.fail 安卓 app 中批准。"])].join("\n\n");
    // The scopes its owner allows (their 默认最长授权), the longest recommended.
    const lasts = this.lastsOf(r.owner);
    const scopes = SCOPES.slice(0, SCOPES.indexOf(lasts) + 1);
    const card = stillfail
      ? {
          type: "options",
          options: [...scopes.map((s, i) => ({ ...SCOPE_WORDS[s], ...(i === scopes.length - 1 ? { recommended: true } : {}) })), { label: "拒绝", detail: "通知 agent 已拒绝" }],
          assignee: r.owner,
          // The request as the app draws it; its outcome added once decided.
          adb: { request: r.id, reason: r.reason, lasts },
        }
      : null;
    const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
    const posted = await this.#d.hub.chat(thread.connect).post(here, text, []);
    const [n] = this.#d.hub.store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card });
    this.#d.hub.shared(thread.thread.id, n!, session, text);
    return card !== null ? posted : null;
  }

  /// How the station's adb holds `owner`'s phone changed (null: offered here no longer): said on the cards of their
  /// grants (`adb.outcome.link`), so a granted card says whether its station reaches the phone yet and what is left to
  /// do (2026-10-30: approved, its station not paired with the phone, the card said 已允许 and nothing more), and told to
  /// their agents as it comes to be reached or to wait on its person.
  linked(owner: string, state: { adb: string; message?: string } | null) {
    const link = state === null ? "gone" : state.adb;
    if (!LINKS.has(link)) return;
    for (const r of this.ofOwner(owner)) {
      if (r.status !== "granted" || r.link === link) continue;
      r.link = link;
      const tell = (link === "connected" || link === "unpaired") && r.toldLink !== link;
      if (tell) r.toldLink = link;
      this.#save(r);
      this.#restate(r);
      if (tell) {
        try {
          this.#d.hub.notify(r.session, linkSaid(r));
        } catch {
          // The session is gone: nobody to tell.
        }
      }
    }
  }

  /// The request's card as it stands now: its outcome (and, granted, how its phone is reached) beside its words.
  #restate(r: PhoneRequest) {
    if (r.thread === undefined || r.cardTs === undefined) return;
    const outcome = { status: r.status, ...(r.scope ? { scope: r.scope } : {}), ...(r.why ? { why: r.why } : {}), ...(r.status === "granted" && r.link ? { link: r.link } : {}) };
    this.#d.hub.store.restateCard(r.session, r.thread, r.cardTs, (card) => ({ ...card, adb: { ...card?.adb, outcome } }));
  }

  /// The owner (`email`) decides request `id`: `scope` grants it, null refuses it. Why it is refused, or null.
  decide(email: string, id: string, scope: Scope | null): string | null {
    const r = this.get(id);
    if (r === null) return "no such request";
    if (r.owner !== email.toLowerCase()) return "only the person the chat's agent works for decides its requests";
    if (r.status !== "pending") return `the request is ${r.status} already`;
    if (scope !== null && !SCOPES.includes(scope)) return "scope: hour or chat";
    if (scope !== null && SCOPES.indexOf(scope) > SCOPES.indexOf(this.lastsOf(email))) return "longer than your 默认最长授权 allows";
    if (scope !== null && this.#ended(r.session)) return "the chat is archived";
    if (scope === null) this.#settle(r, "denied");
    else {
      r.scope = scope;
      r.exp = this.#secs() + LASTS[scope];
      this.#settle(r, "granted");
    }
    return null;
  }

  /// The owner takes a grant (or a request) of theirs back.
  revoke(email: string, id: string): string | null {
    const r = this.get(id);
    if (r === null) return "no such request";
    if (r.owner !== email.toLowerCase()) return "only its owner takes a grant back";
    if (r.status !== "granted" && r.status !== "pending") return `the request is ${r.status} already`;
    this.#end(r, "已收回");
    return null;
  }

  #end(r: PhoneRequest, why: string) {
    if (r.status !== "granted" && r.status !== "pending") return;
    r.why = why;
    this.#settle(r, r.status === "pending" ? "denied" : "ended");
  }

  #settle(r: PhoneRequest, status: Status) {
    r.status = status;
    this.#save(r);
    if (r.thread !== undefined && r.cardTs !== undefined) {
      this.#d.hub.store.withdrawCard(r.session, r.thread, r.cardTs);
      this.#restate(r);
    }
    if (status !== "pending") {
      try {
        this.#d.hub.notify(r.session, said(r));
      } catch {
        // The session is gone: nobody to tell.
      }
    }
    this.#d.told?.(r);
  }
}

/// What the agent is told of how its granted phone is reached (`r.link`).
export function linkSaid(r: PhoneRequest): string {
  switch (r.link) {
    case "connected":
      return `${r.owner}'s phone (your grant ${r.id}) is connected to this station's adb now: call phone_use for its adb server and serial.`;
    case "unpaired":
      return `${r.owner}'s phone (your grant ${r.id}) is lent to this station, but this station's adb is not paired with it yet. Its card in your chat shows its person how to pair it (去配对, in the still.fail app on the phone); you are told here when it connects. Do not send them to the phone's settings yourself.`;
    case "gone":
      return `${r.owner}'s phone (your grant ${r.id}) is not offered to this station now; it offers itself again while its 共享调试 switch is on.`;
    default:
      return `${r.owner}'s phone (your grant ${r.id}): this station's adb holds it as ${r.link ?? "not yet heard"}.`;
  }
}

/// What the agent is told of its request.
export function said(r: PhoneRequest): string {
  switch (r.status) {
    case "granted":
      return `Your request ${r.id} to debug ${r.owner}'s phone was granted (${r.scope === "hour" ? "for an hour" : "until this chat is archived"}). Call phone_use again for how to reach it.${r.link === undefined || r.link === "connected" ? "" : ` ${linkSaid(r)}`}`;
    case "denied":
      return `Your request ${r.id} to debug ${r.owner}'s phone was refused${r.why ? ` (${r.why})` : ""}.`;
    case "ended":
      return `Your grant ${r.id} of ${r.owner}'s phone ended (${r.why ?? "ended"}): adb no longer reaches it.`;
    default:
      return `Your request ${r.id} to debug ${r.owner}'s phone waits for them to approve it on the card in your chat. ${UNDECIDED}`;
  }
}
