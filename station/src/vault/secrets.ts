// Agents asking for the vault's secrets (docs/vault.md, agent 用密钥): a request from a session, its card in the
// session's chat for the vault's owner, the grant or refusal the owner's app sends back (checked by the keeper, which
// alone ever holds the secret), and the commands run with a grant. Without security mode, the secrets are the plain
// library's (plain.ts): the same request and card, decided by the item's owner, the value read from the station. The requests and what was done with them are kept
// in the station's database (`vault_requests`, `vault_audit`), never a secret; the vaults' grants only in memory, the
// plain library's written down without their value (`vault_grants`) and taken up again after a restart. A grant ends
// with its chat: archived or deleted, its session's grants are dropped.
import { randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { LockState } from "../cloud/lock.ts";
import { threadAddress } from "../agents/instructions.ts";
import { wall } from "../ops/fibers.ts";
import { STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";
import type { Hub } from "../sessions/hub.ts";
import { hold } from "../updates/holds.ts";
import { type Deny, type Grant, type Listing, type Mode, type Request, type Scope, SCOPES, TAG, allows, signedOk, signerOf } from "./crypto.ts";
import { type Held, Keeper, hostAllowed, valueOf } from "./keeper.ts";
import { PLAIN, type PlainStore } from "./plain.ts";
import { Proxy, placeholder } from "./proxy.ts";
import { type Ran, SECRET_VAR, runWith } from "./run.ts";
import type { VaultStore } from "./store.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vault_requests (
  ws TEXT NOT NULL,
  id TEXT NOT NULL,
  session TEXT NOT NULL,
  status TEXT NOT NULL,
  body TEXT NOT NULL,
  thread INTEGER,
  card_ts TEXT,
  PRIMARY KEY (ws, id)
);
CREATE TABLE IF NOT EXISTS vault_audit (
  ws TEXT NOT NULL,
  at INTEGER NOT NULL,
  request TEXT NOT NULL,
  vault TEXT NOT NULL,
  item TEXT NOT NULL,
  session TEXT NOT NULL,
  kind TEXT NOT NULL,
  detail TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS vault_grants (
  ws TEXT NOT NULL,
  id TEXT NOT NULL,
  session TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, id)
);
`;

/// The words of a grant's scope on its card, and what each means.
const SCOPE_WORDS: Record<Scope, { label: string; detail: string }> = {
  once: { label: "仅本次", detail: "单次有效" },
  hour: { label: "本对话 1 小时内", detail: "期间无需再次批准" },
  chat: { label: "本对话直到归档", detail: "归档后失效" },
};

/// How long secret_use waits for the decision before it says the request is waiting: within the minute the agents'
/// MCP clients give a tool call (Claude Code's, Codex's), or the call times out unanswered, and a decision after that
/// but within the wait is told to nobody (#settle takes the waiting call for the one that tells).
const WAIT_MS = 45_000;
/// A request no one decided is let go after a day.
const PENDING_SECS = 86400;
/// A command run with a grant is stopped after this long, unless it asks for less (at most an hour).
const RUN_MS = 10 * 60_000;

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
/// A ULID: 48 bits of milliseconds, 80 random.
export function ulid(ms: number): string {
  let t = "";
  for (let v = ms, i = 0; i < 10; i++, v = Math.floor(v / 32)) t = CROCKFORD[v % 32] + t;
  const r = randomBytes(16);
  let rest = "";
  for (let i = 0; i < 16; i++) rest += CROCKFORD[r[i]! % 32];
  return t + rest;
}

export type SecretsDeps = {
  db: DatabaseSync;
  vaults: VaultStore;
  plain: PlainStore;
  /// The station's home workspace (a session of it has none of its own).
  home(): string | null;
  /// A chat's title, for the uses of a secret.
  title?(session: string): string | null;
  hub: Hub;
  /// The station's data directory: the proxy's CA is kept under `vault/`.
  data: string;
  /// The lock pinned in a workspace (null: the station's home workspace); null when none is.
  lock(ws: string | null): LockState | null;
  /// Milliseconds.
  now(): number;
  /// The proxy (a test's own, trusting its hosts).
  proxy?: Proxy;
};

/// A request as the station keeps it: the contract's, and where its card is.
type Kept = { request: Request; thread: number | null; cardTs: string | null };

/// What a tool or a route is told when it cannot go on.
class Refused extends Error {}

/// An item an agent may ask for: of a vault (its id) or of the plain library (`plain`), whose owner (email) decides.
export type Listed = { vault: string; item: string; owner: string | null; listing: Listing };

/// A use of a secret, as the pages list them: a request decided, in the chat that asked.
export type Use = { item: string; at: number; session: string; chatTitle: string | null; mode: Mode; command: string | null; hosts: string[]; denied: boolean };

export class Secrets {
  readonly keeper: Keeper;
  readonly proxy: Proxy;
  /// The plain library's items (docs/vault.md 不加锁的库).
  readonly plain: PlainStore;
  readonly #d: SecretsDeps;
  readonly #waiting = new Map<string, Set<(r: Request) => void>>();
  readonly #listeners: ((r: Request) => void)[] = [];

  constructor(d: SecretsDeps) {
    this.#d = d;
    d.db.exec(SCHEMA);
    const ended = (session: string) => {
      const row = d.hub.store.getSession(session);
      return row === null || row.archivedAt != null;
    };
    this.keeper = new Keeper(() => Math.floor(d.now() / 1000), {
      ended,
      kept: {
        // The plain library's only: a vault's secret is never written down, and its grant is gone with the process.
        save: (h) => {
          if (h.request.vault !== PLAIN) return;
          const { secret: _, ...grant } = h.grant;
          d.db.prepare("INSERT INTO vault_grants (ws, id, session, body) VALUES (?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET body = excluded.body")
            .run(h.request.ws, h.request.id, h.request.session, JSON.stringify({ request: h.request, grant, uses: h.uses }));
        },
        forget: (id) => d.db.prepare("DELETE FROM vault_grants WHERE id = ?").run(id),
      },
    });
    this.plain = d.plain;
    this.proxy = d.proxy ?? new Proxy(`${d.data}/vault`, d.now);
    this.#restore(ended);
    d.hub.store.subscribe((c) => {
      if ((c.type === "sessionRemoved" || c.type === "session") && this.keeper.holds(c.key) && ended(c.key)) this.keeper.end(c.key);
    });
  }

  /// The plain library's grants written down before a restart, held again: those not run out, whose chat goes on and
  /// whose item is still given as granted, its value read again from the store.
  #restore(ended: (session: string) => boolean) {
    const now = Math.floor(this.#d.now() / 1000);
    const rows = this.#d.db.prepare("SELECT ws, id, body FROM vault_grants").all() as { ws: string; id: string; body: string }[];
    for (const row of rows) {
      const { request, grant, uses } = JSON.parse(row.body) as { request: Request; grant: Omit<Grant, "secret">; uses: number };
      const item = this.#d.plain.item(row.ws, request.item);
      const l = item?.listing;
      const secret = item ? { kind: item.kind, name: item.name, fields: item.fields } : null;
      const still = grant.exp > now && !ended(request.session) && this.#d.lock(row.ws) === null && l !== undefined && !item!.deleted && l.modes.includes(grant.mode) && allows(l, grant.scope)
        && grant.hosts.every((h) => l.hosts.includes(h) || (!h.startsWith("*.") && hostAllowed(h, l.hosts))) && secret !== null && valueOf(secret) !== null;
      if (still) this.keeper.restore({ request, grant: { ...grant, secret: "" } as Grant, secret: secret!, uses });
      else this.#d.db.prepare("DELETE FROM vault_grants WHERE ws = ? AND id = ?").run(row.ws, row.id);
    }
  }

  /// Tells `f` of each request made or decided (the members' event streams).
  listen(f: (r: Request) => void) {
    this.#listeners.push(f);
  }

  #told(r: Request) {
    for (const f of this.#listeners) f(r);
    for (const w of this.#waiting.get(r.id) ?? []) w(r);
  }

  #kept(ws: string, id: string): Kept | null {
    const row = this.#d.db.prepare("SELECT body, thread, card_ts FROM vault_requests WHERE ws = ? AND id = ?").get(ws, id) as any;
    return row ? { request: JSON.parse(row.body), thread: row.thread ?? null, cardTs: row.card_ts ?? null } : null;
  }

  #save(k: Kept) {
    const r = k.request;
    this.#d.db
      .prepare("INSERT INTO vault_requests (ws, id, session, status, body, thread, card_ts) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET status = excluded.status, body = excluded.body, thread = excluded.thread, card_ts = excluded.card_ts")
      .run(r.ws, r.id, r.session, r.status, JSON.stringify(r), k.thread, k.cardTs);
  }

  #audit(r: Request, kind: string, detail: string) {
    this.#d.db.prepare("INSERT INTO vault_audit (ws, at, request, vault, item, session, kind, detail) VALUES (?, ?, ?, ?, ?, ?, ?, ?)").run(r.ws, Math.floor(this.#d.now() / 1000), r.id, r.vault, r.item, r.session, kind, detail);
  }

  /// What was done with the vault's secrets in a workspace, the latest first (never a value).
  audit(ws: string, vault: string, limit = 200): { at: number; request: string; item: string; session: string; kind: string; detail: string }[] {
    return this.#d.db.prepare("SELECT at, request, item, session, kind, detail FROM vault_audit WHERE ws = ? AND vault = ? ORDER BY rowid DESC LIMIT ?").all(ws, vault, limit) as any;
  }

  /// A session's workspace and its lock (null: security mode off, the plain library's secrets then).
  #placeOf(session: string): { ws: string; lock: LockState | null } {
    const row = this.#d.hub.store.getSession(session);
    if (!row) throw new Refused("unknown session");
    const ws = row.ws ?? this.#d.home();
    if (ws === null) throw new Refused("this station is in no workspace");
    return { ws, lock: this.#d.lock(row.ws ?? null) };
  }

  /// The person a session works for: whoever started its chat (their email).
  #starter(session: string): string | null {
    const first = this.#d.hub.store.participants(session).get(session)?.[0];
    return first === undefined ? null : first.toLowerCase();
  }

  /// The items a session may ask for: those with a listing of whoever started its chat, in their vaults (security
  /// mode on) or their plain library (off).
  listings(session: string): Listed[] {
    const { ws, lock } = this.#placeOf(session);
    const email = this.#starter(session);
    if (email === null) return [];
    if (lock === null) {
      return this.#d.plain.items(ws, email).flatMap((i) => (!i.deleted && i.listing ? [{ vault: PLAIN, item: i.id, owner: i.owner, listing: i.listing }] : []));
    }
    const sub = [...lock.members.values()].find((m) => m.email.toLowerCase() === email)?.sub;
    if (sub === undefined) return [];
    return this.#d.vaults
      .vaults(lock.ws)
      .filter((v) => v.members.includes(sub))
      .flatMap((vault) => this.#d.vaults.items(lock.ws, vault.id).flatMap((i) =>
        !i.deleted && i.listing !== undefined && i.epoch === vault.epoch ? [{ vault: vault.id, item: i.id, owner: lock.members.get(vault.owner)?.email ?? null, listing: i.listing }] : []));
  }

  /// Whether `viewer` decides request `r`: the plain library's item's owner, a member of the vault.
  #decides(r: Request, viewer: { sub: string; email: string }, lock: LockState | null): boolean {
    if (r.vault === PLAIN) return r.owner === viewer.email.toLowerCase();
    return lock !== null && this.#d.vaults.vault(lock.ws, r.vault)?.members.includes(viewer.sub) === true;
  }

  /// Whether request `r`'s changes are told to `viewer` (the members' event streams).
  tells(r: Request, viewer: { sub: string; email: string; workspace: string }): boolean {
    return viewer.workspace === r.ws && (r.vault === PLAIN ? r.owner === viewer.email.toLowerCase() : this.#d.vaults.vault(r.ws, r.vault)?.members.includes(viewer.sub) === true);
  }

  /// The requests `viewer` may decide in workspace `ws`, still waiting.
  pending(ws: string, lock: LockState | null, viewer: { sub: string; email: string }): Request[] {
    const now = Math.floor(this.#d.now() / 1000);
    const rows = this.#d.db.prepare("SELECT body FROM vault_requests WHERE ws = ? AND status = 'pending'").all(ws) as { body: string }[];
    return rows
      .map((r) => JSON.parse(r.body) as Request)
      .filter((r) => {
        // A vault's request whose box this station no longer holds (it restarted) can never be granted: let go.
        if (r.at + PENDING_SECS > now && (r.vault === PLAIN || this.keeper.waiting(r.id))) return true;
        this.#settle(r, "expired");
        return false;
      })
      .filter((r) => this.#decides(r, viewer, lock));
  }

  /// The uses of a vault's (or the plain library's) secrets `viewer` may see, the latest first: the requests decided.
  uses(ws: string, lock: LockState | null, vault: string, viewer: { sub: string; email: string }, limit = 500): Use[] {
    if (vault !== PLAIN && (lock === null || this.#d.vaults.vault(ws, vault)?.members.includes(viewer.sub) !== true)) return [];
    const rows = this.#d.db
      .prepare("SELECT body FROM vault_requests WHERE ws = ? AND status IN ('granted', 'denied') AND json_extract(body, '$.vault') = ? ORDER BY json_extract(body, '$.at') DESC LIMIT ?")
      .all(ws, vault, limit) as { body: string }[];
    return rows
      .map((row) => JSON.parse(row.body) as Request)
      .filter((r) => vault !== PLAIN || r.owner === viewer.email.toLowerCase())
      .map((r) => ({ item: r.item, at: r.at, session: r.session, chatTitle: this.#title(r.session), mode: r.mode, command: r.command ?? null, hosts: r.hosts ?? [], denied: r.status === "denied" }));
  }

  #title(session: string): string | null {
    try {
      return this.#d.title?.(session) ?? null;
    } catch {
      return null;
    }
  }

  /// The listing of a request's item, where it still is.
  #listingOf(r: Request): Listing | undefined {
    return r.vault === PLAIN ? this.#d.plain.item(r.ws, r.item)?.listing : this.#d.vaults.item(r.ws, r.vault, r.item)?.listing;
  }

  /// secret_use: a request for `itemName` (its id or listed name) from `session`; waits a while for its decision.
  async ask(session: string, a: { item: string; mode?: string; reason: string; command?: string; hosts?: string[] }): Promise<string> {
    const { ws } = this.#placeOf(session);
    const wanted = a.item.trim().toLowerCase();
    const found = this.listings(session).find((l) => l.item.toLowerCase() === wanted || l.listing.name.toLowerCase() === wanted);
    if (found === undefined) throw new Refused(`No secret named ${JSON.stringify(a.item)} may be asked for here: secret_list lists those that may.`);
    const { listing } = found;
    const plain = found.vault === PLAIN;
    const mode = (a.mode ?? listing.modes[0]) as Mode;
    if (!listing.modes.includes(mode)) throw new Refused(`「${listing.name}」 is given only by ${listing.modes.join(", ")}.`);
    if (a.reason.trim() === "") throw new Refused("reason is required: why you need it, for the person deciding");
    const hosts = a.hosts?.length ? a.hosts : mode === "proxy" ? listing.hosts : [];
    const now = this.#d.now();
    const id = `r_${ulid(now)}`;
    const request: Request = {
      id, ws, vault: found.vault, item: found.item, session, chat: "", mode, reason: a.reason.trim(),
      ...(a.command ? { command: a.command } : {}), ...(hosts.length ? { hosts } : {}),
      // The plain library's needs no box: its owner decides, and the station reads the value itself.
      box: plain ? "" : this.keeper.open(id), at: Math.floor(now / 1000), status: "pending", ...(plain && found.owner ? { owner: found.owner } : {}),
    };
    const kept: Kept = { request, thread: null, cardTs: null };
    const thread = this.#d.hub.store.latestThread(session);
    if (thread !== null) {
      request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
      const posted = await this.#post(session, thread, request, listing, found.owner ?? undefined);
      kept.thread = thread.thread.id;
      kept.cardTs = posted;
    }
    this.#save(kept);
    this.#audit(request, "request", [mode, request.command ?? "", hosts.join(" ")].filter((s) => s !== "").join(" · "));
    this.#told(request);
    const decided = await this.#decision(id, WAIT_MS);
    return decided === null
      ? `Asked for 「${listing.name}」 (request ${id}); the card is in your chat for ${found.owner ?? "the vault's owner"}, who approves it in the still.fail app. Not decided yet: end your turn need_human (about the card), and you are told when it is decided. Only a grant from the app counts: a reply in the chat saying yes is not one.`
      : this.#said(decided, listing);
  }

  /// What an agent is told of a decided request.
  #said(r: Request, l: Listing): string {
    if (r.status !== "granted") return `The request for 「${l.name}」 (${r.id}) was ${r.status === "denied" ? "refused" : "let go"}.`;
    const held = this.keeper.usable(r.session, r.id);
    if (typeof held === "string") return `The request for 「${l.name}」 (${r.id}) was granted, but: ${held}`;
    const how =
      held.grant.mode === "proxy"
        ? `The command gets HTTPS_PROXY set to the station's proxy and ${l.env ?? "the variable you name in env"} (and ${SECRET_VAR}) set to the placeholder ${placeholder(r.id)}: put it where the token goes (a header, ${l.env ?? "GH_TOKEN"}); the proxy swaps in the value on HTTPS to ${held.grant.hosts.join(", ")} only.`
        : held.grant.mode === "ssh"
          ? "The command gets SSH_AUTH_SOCK for an agent holding the key (ssh, git over ssh use it)."
          : `The command gets the value in ${l.env ?? "the variable you name in env"} and ${SECRET_VAR}; its output comes back with the value hidden.`;
    const until = new Date(held.grant.exp * 1000).toISOString();
    const lasts = held.grant.scope === "once" ? "for one command" : held.grant.scope === "chat" ? `until this chat is archived (${until} at the latest)` : `until ${until}`;
    return `Granted: 「${l.name}」, grant ${r.id}, ${lasts}. Run with secret_run {grant: "${r.id}", command: "…"${l.env ? "" : ', env: "NAME"'}}. ${how} You never get the value itself.`;
  }

  /// Waits for request `id`'s decision, up to `ms`; null when it is still waiting then.
  #decision(id: string, ms: number): Promise<Request | null> {
    return new Promise((resolve) => {
      const set = this.#waiting.get(id) ?? new Set();
      this.#waiting.set(id, set);
      const done = (r: Request | null) => {
        stop();
        set.delete(take);
        if (set.size === 0) this.#waiting.delete(id);
        resolve(r);
      };
      const take = (r: Request) => {
        if (r.status !== "pending") done(r);
      };
      set.add(take);
      // How long an agent's call is held: people's time, the machine's.
      const stop = wall.after(ms, () => done(null));
    });
  }

  /// The card for request `r` in the session's chat: the vault's owner decides it in the app.
  async #post(session: string, thread: SessionThread, r: Request, l: Listing, owner: string | undefined): Promise<string | null> {
    const how = r.mode === "proxy" ? `代理（限 ${(r.hosts ?? l.hosts).join(", ")}）` : r.mode === "ssh" ? "ssh-agent（私钥不出 station）" : "环境变量（命令可读取明文）";
    const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    // In a still.fail chat the card says where it is approved; Slack has no card, so the words say it.
    const where = stillfail ? [] : ["请在 still.fail 客户端的「密钥」中批准。"];
    const text = [`申请使用「${l.name}」：${r.reason}`, ...(r.command ? [`命令：\`${r.command.replace(/`/g, "'")}\``] : []), `方式：${how}`, ...where].join("\n\n");
    // The scopes the item allows, the longest recommended.
    const scopes = SCOPES.filter((s) => allows(l, s));
    const card = stillfail
      ? {
          type: "options",
          options: [
            ...scopes.map((s, i) => ({ ...SCOPE_WORDS[s], ...(i === scopes.length - 1 ? { recommended: true } : {}) })),
            { label: "拒绝", detail: "通知 agent 已拒绝" },
          ],
          ...(owner ? { assignee: owner.toLowerCase() } : {}),
          // The request as the app draws it (VaultAsk.tsx); its outcome added once decided (#settle).
          vault: { request: r.id, name: l.name, reason: r.reason, ...(r.command ? { command: r.command } : {}), mode: r.mode, hosts: r.mode === "proxy" ? (r.hosts ?? l.hosts) : [] },
        }
      : null;
    const posted = await this.#d.hub.chat(thread.connect).post(here, text, []);
    const [n] = this.#d.hub.store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card });
    this.#d.hub.shared(thread.thread.id, n, session, text);
    return card !== null ? posted : null;
  }

  /// A request decided otherwise than granted, or granted (`grant` checked by the keeper first).
  #settle(r: Request, status: Request["status"], scope?: Scope) {
    const k = this.#kept(r.ws, r.id);
    if (k === null || k.request.status !== "pending") return;
    k.request.status = status;
    this.#save(k);
    if (status !== "granted") this.keeper.drop(r.id);
    if (k.thread !== null && k.cardTs !== null) {
      this.#d.hub.store.withdrawCard(r.session, k.thread, k.cardTs);
      // The post says how it ended: 已批准 · 仅本次, 已拒绝, 已过期.
      const outcome = { status, ...(status === "granted" && scope ? { scope } : {}) };
      this.#d.hub.store.restateCard(r.session, k.thread, k.cardTs, (card) => ({ ...card, vault: { ...card?.vault, outcome } }));
    }
    this.#audit(k.request, status, "");
    const heard = (this.#waiting.get(r.id)?.size ?? 0) > 0;
    this.#told(k.request);
    // Not waited for in a tool call: the agent is told in its session.
    if (!heard && status !== "expired") {
      const l = this.#listingOf(r);
      try {
        this.#d.hub.notify(r.session, l ? this.#said(k.request, l) : `The request ${r.id} was ${status}.`);
      } catch {
        // The session is gone: nobody to tell.
      }
    }
  }

  /// POST vault/grants: `grant`, sent by `sub`'s app; why it is refused, or null.
  grant(lock: LockState, sub: string, grant: Grant): string | null {
    const k = typeof grant?.request === "string" ? this.#kept(lock.ws, grant.request) : null;
    if (k === null) return "no such request";
    const vault = this.#d.vaults.vault(lock.ws, k.request.vault);
    const item = this.#d.vaults.item(lock.ws, k.request.vault, k.request.item);
    if (vault === null || item === null) return "the request's vault or item is gone";
    if (!vault.members.includes(sub)) return "only the vault's members decide its requests";
    const why = this.keeper.accept(lock, vault, item, k.request, grant);
    if (why !== null) return why;
    this.#settle(k.request, "granted", grant.scope);
    return null;
  }

  /// POST vault/plain/grants: the plain library's request `request` granted by `email` (its item's owner) for `scope`;
  /// why it is refused, or null. Security mode on, nothing of the plain library is given out (it is moved into a vault).
  grantPlain(ws: string, lock: LockState | null, email: string, d: { request?: unknown; scope?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || k.request.vault !== PLAIN) return "no such request of the plain library";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (lock !== null) return "security mode is on: the plain library's secrets are moved into the vault, not given out";
    const item = this.#d.plain.item(ws, k.request.item);
    if (item === null || item.deleted || item.listing === undefined) return "the item is gone, or not one agents may ask for";
    const hosts = k.request.mode === "proxy" ? (k.request.hosts ?? item.listing.hosts) : [];
    const why = this.keeper.hold(k.request, { scope: d.scope as Scope, hosts, listing: item.listing }, { kind: item.kind, name: item.name, fields: item.fields });
    if (why !== null) return why;
    this.#settle(k.request, "granted", d.scope as Scope);
    return null;
  }

  /// POST vault/plain/denials: the plain library's request turned down by its item's owner.
  denyPlain(ws: string, email: string, d: { request?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || k.request.vault !== PLAIN) return "no such request of the plain library";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    this.#settle(k.request, "denied");
    return null;
  }

  /// POST vault/denials: `deny`, sent by `sub`'s app; why it is refused, or null.
  deny(lock: LockState, sub: string, deny: Deny): string | null {
    const d = deny as any;
    const k = typeof d?.request === "string" ? this.#kept(lock.ws, d.request) : null;
    if (k === null) return "no such request";
    if (d.v !== 1 || d.ws !== lock.ws) return "a refusal is {v: 1, ws, request, at, sig} of this workspace";
    const vault = this.#d.vaults.vault(lock.ws, k.request.vault);
    if (vault === null || !vault.members.includes(sub)) return "only the vault's members decide its requests";
    const by = typeof d.sig?.key === "string" ? signerOf(lock, d.sig.key) : null;
    if (by === null || !vault.members.includes(by.sub)) return "a refusal is signed by a vault member's device in the lock";
    if (!signedOk(d, TAG.deny)) return "the refusal's signature is invalid";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    this.#settle(k.request, "denied");
    return null;
  }

  /// secret_run: `command` with grant `id`, in the session's workspace (or `cwd` under it).
  async run(session: string, a: { grant: string; command: string; env?: string; cwd: string; timeoutMs?: number }): Promise<string> {
    const held = this.keeper.usable(session, a.grant);
    if (typeof held === "string") throw new Refused(held);
    if (a.env !== undefined && !/^[A-Za-z_][A-Za-z0-9_]*$/.test(a.env)) throw new Refused("env must be a variable name");
    const listing = this.#listingOf(held.request);
    this.keeper.spend(held.request.id);
    const env = a.env ?? listing?.env;
    // The station's environment, without what would let the command act as the station or its agents' accounts.
    const base = Object.fromEntries(Object.entries(process.env).filter((e): e is [string, string] => e[1] !== undefined && !/^(STILLFAIL_|EMBER_|ANTHROPIC_|CLAUDE_|OPENAI_|CODEX_)/.test(e[0])));
    // The station does not update itself meanwhile: the proxy or ssh-agent the command uses is this process's.
    const letGo = hold();
    const ran = await runWith(held, { command: a.command, cwd: a.cwd, ...(env ? { env } : {}), timeoutMs: Math.min(a.timeoutMs ?? RUN_MS, 3600_000) }, this.proxy, base, (detail) =>
      this.#audit(held.request, "use", detail),
    ).finally(letGo);
    this.#audit(held.request, "run", a.command.slice(0, 500));
    return said(ran);
  }

  /// The grants a session holds that may still be used.
  held(session: string): Held[] {
    return this.keeper.held(session);
  }
}

function said(r: Ran): string {
  const end = r.timedOut ? "stopped: it ran too long" : r.code !== null ? `exit code ${r.code}` : `ended by ${r.signal}`;
  return `${end}${r.cut ? " (output cut in the middle)" : ""}\n${r.output}`;
}

export { Refused };
