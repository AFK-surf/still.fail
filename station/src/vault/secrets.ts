// Agents asking for the vault's secrets (docs/vault.md, agent 用密钥): a request from a session, its card in the
// session's chat for the vault's owner, the grant or refusal the owner's app sends back (checked by the keeper, which
// alone ever holds the secret), and the commands run with a grant. Without security mode, the secrets are the plain
// library's (plain.ts): the same request and card, decided by the item's owner, the value read from the station. An
// agent may also ask to keep a secret in its owner's vault (secret_save): sealed to their devices, written by the app
// that approves it (or, without security mode, into the plain library here); or one only they hold, typed in on its card
// by them, written by their app as it is approved (`save.typed`). A grant may be for commands on another
// station of the workspace (`runOn`): the secret is sent there over the station transport for each command, run in the
// session's directory there, and only the outcome comes back. The requests and what was done with them are kept
// in the station's database (`vault_requests`, `vault_audit`), never a secret; the vaults' grants only in memory, the
// plain library's written down without their value (`vault_grants`) and taken up again after a restart. A grant ends
// with its chat: archived or deleted, its session's grants are dropped.
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { basename } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import type { LockState } from "../cloud/lock.ts";
import type { To } from "../api/events.ts";
import { threadAddress } from "../agents/instructions.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type Json, STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";
import type { Hub } from "../sessions/hub.ts";
import { hold } from "../updates/holds.ts";
import { type BoxCert, type Deny, type Grant, type Kind, type Listing, type Mode, type Request, type Save, type Scope, SCOPES, TAG, allows, certOk, saveContext, seal, signedOk, signerOf } from "./crypto.ts";
import { type Held, Keeper, accountOf, hostAllowed, valueOf } from "./keeper.ts";
import { FILE_MOST, KINDS, MODES, PLAIN, type PlainItem, type PlainStore, plainOk } from "./plain.ts";
import { Proxy, placeholder } from "./proxy.ts";
import { ACCOUNT_VAR, type Captured, type Ran, SECRET_VAR, capture, runWith } from "./run.ts";
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
  once: { label: "仅本次", detail: "只给这一条命令用，下次还要再批准" },
  hour: { label: "本对话 1 小时内", detail: "1 小时内这个对话可以反复使用，不用再批准" },
  chat: { label: "本对话直到归档", detail: "这个对话归档或删除前都能用，最长 30 天" },
};

/// How long secret_use waits for the decision before it says the request is waiting: within the minute the agents'
/// MCP clients give a tool call (Claude Code's, Codex's), or the call times out unanswered, and a decision after that
/// but within the wait is told to nobody (#settle takes the waiting call for the one that tells).
const WAIT_MS = 45_000;
/// A request no one decided is let go after a day.
const PENDING_SECS = 86400;
/// A command run with a grant is stopped after this long, unless it asks for less (at most an hour).
const RUN_MS = 10 * 60_000;
/// A command printing a secret to keep is stopped after this long.
const CAPTURE_MS = 2 * 60_000;

/// The words on the card of a request to keep a secret.
const SAVE_WORDS = {
  save: { label: "存入密钥库", detail: "agent 之后每次使用仍需你批准" },
  deny: { label: "拒绝", detail: "不保存，通知 agent" },
};
const KIND_WORDS: Record<Kind, string> = { token: "Token", login: "登录", ssh_key: "SSH 密钥", file: "文件" };
const howWords = (mode: Mode, hosts: string[]): string =>
  mode === "proxy" ? `代理（限 ${hosts.join(", ")}）` : mode === "ssh" ? "ssh-agent（私钥不出 station）" : mode === "file" ? "文件（命令运行时临时写出，可读取内容）" : "环境变量（命令可读取明文）";

/// The field of each kind that holds its secret.
const SECRET_FIELD: Record<Kind, string> = { token: "value", login: "password", ssh_key: "private_key", file: "content" };
/// The most a secret typed in may be, its fields together (as a command's output may: one secret); a file's, as
/// plainOk says (FILE_MOST of bytes).
const TYPED_MOST = 64 * 1024;

/// The fields of a secret its owner typed in, as their app sent them: words only, its secret not empty, one secret's
/// size at most (which fields a kind has, plainOk says); undefined when they are not.
function typedFields(kind: Kind, v: unknown): Record<string, string> | undefined {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return undefined;
  const fields = Object.entries(v as Record<string, unknown>);
  if (!fields.every(([, x]) => typeof x === "string")) return undefined;
  const all = Object.fromEntries(fields) as Record<string, string>;
  const size = fields.reduce((n, [k, x]) => n + k.length + (x as string).length, 0);
  return (all[SECRET_FIELD[kind]] ?? "").trim() !== "" && (kind === "file" || size <= TYPED_MOST) ? all : undefined;
}

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
  /// Another station of the workspace by its name or id: its id and name; null for this station. Throws why not.
  peer?(given: string): { id: string; name: string } | null;
  /// A request to another station of the workspace (the station transport, mesh/bus.ts).
  ask?(station: string, request: Json): Promise<Json>;
  /// The directory a source session's tasks share here (jobs/remote.ts `work`), made and noted as used.
  workOf?(workspace: string, peer: string, session: string): string;
};

/// A command sent to another station to run, or one it sent here, waiting for how it ended.
type Away = { station: string; done(result: Json): void };

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
  /// The secrets agents asked to keep, by request, until decided: only in memory (a restart forgets them). The plain
  /// library's is written from here once approved; a vault's is sealed to its owner's devices set up later.
  readonly #unsaved = new Map<string, Record<string, string>>();
  /// Commands sent to other stations, by the id they say how they ended under (`vault.done`).
  readonly #away = new Map<string, Away>();

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
      const still = grant.exp > now && !ended(request.session) && this.#d.lock(row.ws) === null && l !== undefined && !item!.deleted && l.modes.includes(grant.mode)
        && allows(l.lasts ?? this.#d.plain.lasts(row.ws, item!.owner)?.lasts, grant.scope)
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
    if (r.vault === PLAIN || r.save) return r.owner === viewer.email.toLowerCase();
    return lock !== null && this.#d.vaults.vault(lock.ws, r.vault)?.members.includes(viewer.sub) === true;
  }

  /// Whom request `r`'s changes are told to (the event streams, api/events.ts `To`): in its workspace, its owner for the
  /// plain library or a secret to keep (none without one: null), else the members of its vault as each is told
  /// (`inVault`).
  tells(r: Request): To | null {
    if (r.vault !== PLAIN && !r.save) return { workspace: r.ws, vault: r.vault };
    return r.owner === undefined ? null : { workspace: r.ws, email: r.owner };
  }

  /// Whether `viewer` is a member of that vault of their workspace now: whom its requests are told to (`tells`).
  inVault(viewer: { sub: string; workspace: string }, vault: string): boolean {
    return this.#d.vaults.vault(viewer.workspace, vault)?.members.includes(viewer.sub) === true;
  }

  /// The requests `viewer` may decide in workspace `ws`, still waiting.
  pending(ws: string, lock: LockState | null, viewer: { sub: string; email: string }): Request[] {
    const now = Math.floor(this.#d.now() / 1000);
    const rows = this.#d.db.prepare("SELECT body FROM vault_requests WHERE ws = ? AND status = 'pending'").all(ws) as { body: string }[];
    return rows
      .map((r) => JSON.parse(r.body) as Request)
      .filter((r) => {
        // A vault's request whose box this station no longer holds (it restarted) can never be granted: let go. So is a
        // secret to keep that is gone with a restart (the plain library's) and sealed to no device; one the person types
        // in is held nowhere until then.
        const live = r.save ? r.save.typed === true || this.#unsaved.has(r.id) || (r.vault !== PLAIN && (r.sealed?.length ?? 0) > 0) : r.vault === PLAIN || this.keeper.waiting(r.id);
        if (r.at + PENDING_SECS > now && live) return true;
        this.#settle(r, "expired");
        return false;
      })
      .filter((r) => this.#decides(r, viewer, lock));
  }

  /// The uses of a vault's (or the plain library's) secrets `viewer` may see, the latest first: the requests decided.
  uses(ws: string, lock: LockState | null, vault: string, viewer: { sub: string; email: string }, limit = 500): Use[] {
    if (vault !== PLAIN && (lock === null || this.#d.vaults.vault(ws, vault)?.members.includes(viewer.sub) !== true)) return [];
    const rows = this.#d.db
      .prepare("SELECT body FROM vault_requests WHERE ws = ? AND status IN ('granted', 'denied') AND json_extract(body, '$.vault') = ? AND json_extract(body, '$.save') IS NULL ORDER BY json_extract(body, '$.at') DESC LIMIT ?")
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

  /// The longest grant a request's item (listed as `l`) is given for: its own, else its vault's or (the plain library)
  /// its owner's; null: any.
  #lastsOf(r: Request, l: Listing): Scope | null {
    if (l.lasts) return l.lasts;
    return (r.vault === PLAIN ? (r.owner ? this.#d.plain.lasts(r.ws, r.owner)?.lasts : undefined) : this.#d.vaults.vault(r.ws, r.vault)?.lasts) ?? null;
  }

  /// The listing of a request's item, where it still is.
  #listingOf(r: Request): Listing | undefined {
    return r.vault === PLAIN ? this.#d.plain.item(r.ws, r.item)?.listing : this.#d.vaults.item(r.ws, r.vault, r.item)?.listing;
  }

  /// secret_use: a request for `itemName` (its id or listed name) from `session`; waits a while for its decision.
  async ask(session: string, a: { item: string; mode?: string; reason: string; command?: string; hosts?: string[]; station?: string }): Promise<string> {
    const { ws } = this.#placeOf(session);
    const runOn = a.station ? this.#peer(a.station) : null;
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
      ...(a.command ? { command: a.command } : {}), ...(hosts.length ? { hosts } : {}), ...(runOn ? { runOn } : {}),
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
          : held.grant.mode === "file"
            ? `The file is written out for each command alone (removed when it ends) and its path is in ${l.env ?? "the variable you name in env"} and ${SECRET_VAR} (e.g. kubectl --kubeconfig "$${SECRET_VAR}"); its output comes back with the file's content hidden.`
            : `The command gets the value in ${l.env ?? "the variable you name in env"} and ${SECRET_VAR}; its output comes back with the value hidden.`;
    const until = new Date(held.grant.exp * 1000).toISOString();
    const lasts = held.grant.scope === "once" ? "for one command" : held.grant.scope === "chat" ? `until this chat is archived (${until} at the latest)` : `until ${until}`;
    const where = r.runOn ? ` Its commands run on ${r.runOn.name}, in this chat's directory there (where station_task runs); the value is sent there only for each command.` : "";
    return `Granted: 「${l.name}」, grant ${r.id}, ${lasts}. Run with secret_run {grant: "${r.id}", command: "…"${l.env ? "" : ', env: "NAME"'}}. ${how}${accountSaid(held)}${where} You never get the value itself.`;
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
    const how = howWords(r.mode, r.hosts ?? l.hosts);
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    // In a still.fail chat the card says where it is approved; Slack has no card, so the words say it.
    const where = stillfail ? [] : ["请在 still.fail 客户端的「密钥」中批准。"];
    const text = [
      `申请使用「${l.name}」：${r.reason}`, ...(r.command ? [`命令：\`${r.command.replace(/`/g, "'")}\``] : []), `方式：${how}`,
      ...(r.runOn ? [`运行在：${r.runOn.name}`] : []), ...where,
    ].join("\n\n");
    // The scopes the item allows, the longest recommended.
    const lasts = this.#lastsOf(r, l);
    const scopes = SCOPES.filter((s) => allows(lasts, s));
    const card = stillfail
      ? {
          type: "options",
          options: [
            ...scopes.map((s, i) => ({ ...SCOPE_WORDS[s], ...(i === scopes.length - 1 ? { recommended: true } : {}) })),
            { label: "拒绝", detail: "通知 agent 已拒绝" },
          ],
          ...(owner ? { assignee: owner.toLowerCase() } : {}),
          // The request as the app draws it (VaultAsk.tsx); its outcome added once decided (#settle).
          vault: { request: r.id, name: l.name, reason: r.reason, ...(r.command ? { command: r.command } : {}), mode: r.mode, hosts: r.mode === "proxy" ? (r.hosts ?? l.hosts) : [], ...(r.runOn ? { station: r.runOn.name } : {}) },
        }
      : null;
    return this.#postCard(session, thread, text, card);
  }

  /// A request's post in the session's chat, with its card where the chat shows cards; the card's ts, if it has one.
  async #postCard(session: string, thread: SessionThread, text: string, card: Record<string, unknown> | null): Promise<string | null> {
    const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
    const posted = await this.#d.hub.chat(thread.connect).post(here, text, []);
    const [n] = this.#d.hub.store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: session, text, attachments: [], declared: null, card });
    this.#d.hub.shared(thread.thread.id, n, session, text);
    return card !== null ? posted : null;
  }

  // ── secrets agents ask to keep (secret_save, docs/vault.md agent 存入) ──

  /// The person a session works for, as the lock has them (their sub), where security mode is on.
  #memberOf(lock: LockState, email: string): string | null {
    return [...lock.members.values()].find((m) => m.email.toLowerCase() === email)?.sub ?? null;
  }

  /// `sub`'s devices set up for the vault: their box certificates, checked against the lock.
  #certsOf(lock: LockState, sub: string): BoxCert[] {
    return this.#d.vaults.boxes(lock.ws).filter((c) => certOk(lock, c) === null && lock.devices.get(c.device)?.sub === sub);
  }

  /// The vault a secret kept for `sub` is meant for: one of theirs keyed to a device of theirs, their own first; empty
  /// while they have none (the app that approves makes one).
  #vaultFor(lock: LockState, sub: string): string {
    const devices = new Set(this.#certsOf(lock, sub).map((c) => c.device));
    const theirs = this.#d.vaults.vaults(lock.ws).filter((v) => v.members.includes(sub) && v.keys.some((k) => devices.has(k.cert.device)));
    return (theirs.find((v) => v.owner === sub) ?? theirs[0])?.id ?? "";
  }

  #sealTo(cert: BoxCert, ws: string, request: string, fields: Record<string, string>) {
    return { device: cert.device, box: cert.box, secret: seal(cert.box, Buffer.from(JSON.stringify(fields)), saveContext(ws, request)) };
  }

  /// Whether the person a session works for can keep a secret: `plain` (no security mode: the plain library here),
  /// `on` (a vault of theirs, keyed to a device of theirs set up), `off` (security mode on, their vault not turned on:
  /// a secret to keep waits on its card until they turn it on there), `none` (no one to keep it for).
  status(session: string): "plain" | "on" | "off" | "none" {
    const { lock } = this.#placeOf(session);
    const email = this.#starter(session);
    if (email === null) return "none";
    if (lock === null) return "plain";
    const sub = this.#memberOf(lock, email);
    if (sub === null) return "none";
    return this.#vaultFor(lock, sub) !== "" ? "on" : "off";
  }

  /// secret_save: a request from `session` to keep a secret in the vault of whoever started its chat, given as `value`,
  /// printed by `command` (run here in `cwd`; what it prints is never shown) or, given neither, typed in by that person
  /// on its card (`save.typed`: nothing of it held or sealed here); waits a while for its decision.
  async save(
    session: string,
    a: {
      name: string; kind: string; reason: string; value?: string; command?: string; path?: string; username?: string; public_key?: string; filename?: string; modes?: string[]; hosts?: string[]; env?: string;
      cwd: string; station?: string;
    },
  ): Promise<string> {
    const { ws, lock } = this.#placeOf(session);
    const kind = a.kind as Kind;
    if (a.path !== undefined && kind !== "file") throw new Refused("path is a file's: give kind file");
    if (a.path !== undefined && (a.command !== undefined || a.value !== undefined)) throw new Refused("Give a file as path, command or value, one of them.");
    // A file given by its path: read as a command printing it would (here or on the station named), ~/ its home there.
    const quoted = (p: string) => `'${p.replace(/'/g, "'\\''")}'`;
    const command = a.path === undefined ? a.command : `cat -- ${a.path.startsWith("~/") ? `"$HOME"/${quoted(a.path.slice(2))}` : quoted(a.path)}`;
    const filename = kind === "file" ? (a.filename ?? (a.path !== undefined ? basename(a.path) : "")).trim() : "";
    const from = a.station ? this.#peer(a.station) : null;
    if (from !== null && command === undefined) throw new Refused("station says where command runs: give command (or path)");
    const email = this.#starter(session);
    if (email === null) throw new Refused("No one started this chat: there is no one to keep a secret for.");
    if (!KINDS.includes(kind)) throw new Refused("kind is token, login, ssh_key or file");
    const name = a.name.trim();
    if (name === "" || name.length > 200) throw new Refused("name is required (at most 200 characters): what the person and agents will know it by");
    if (a.reason.trim() === "") throw new Refused("reason is required: why it is worth keeping, for the person deciding");
    if (a.value !== undefined && command !== undefined) throw new Refused("Give the secret as value or as a command that prints it (command), not both; neither, and the card asks the person to type it in.");
    const typed = a.value === undefined && command === undefined;
    const hosts = [...new Set((a.hosts ?? []).map((h) => h.trim().toLowerCase()).filter((h) => h !== ""))];
    const modes = (a.modes?.length ? [...new Set(a.modes)] : kind === "ssh_key" ? ["ssh"] : kind === "file" ? ["file"] : hosts.length > 0 ? ["proxy"] : ["env"]) as Mode[];
    if (!modes.every((m) => MODES.includes(m))) throw new Refused("modes are proxy, ssh, env or file");
    if (modes.includes("ssh") !== (kind === "ssh_key")) throw new Refused("an SSH key is given by ssh (or env), and only an SSH key is");
    if (kind === "file" && (modes.length !== 1 || modes[0] !== "file")) throw new Refused("a file is given as a file (modes: [\"file\"])");
    const sub = lock === null ? null : this.#memberOf(lock, email);
    if (lock !== null && sub === null) throw new Refused(`${email} is not in the workspace's security mode: there is no vault of theirs to keep it in.`);
    const listing: Listing = { name, kind, modes, hosts, ...(a.env ? { env: a.env } : {}) };
    const now = this.#d.now();
    const item = `i_${ulid(now)}`;
    // What is not secret checked before anything is run.
    const draft = (fields: Record<string, string>): PlainItem => ({ ws, id: item, owner: email, version: 0, kind, name, fields, notes: "", listing, at: Math.floor(now / 1000) });
    // (a file's value: its bytes in base64; given as value, its text)
    const fieldsOf = (value: string): Record<string, string> =>
      kind === "token" ? { value } : kind === "login" ? { ...(a.username ? { username: a.username } : {}), password: value }
      : kind === "file" ? { content: value, ...(filename ? { filename } : {}) } : { private_key: value, ...(a.public_key ? { public_key: a.public_key } : {}) };
    const why = plainOk(null, draft(fieldsOf("eA==")), email);
    if (why !== null) throw new Refused(why);
    let value = kind === "file" && a.value !== undefined ? Buffer.from(a.value, "utf8").toString("base64") : (a.value ?? "");
    if (command !== undefined) {
      const got = from === null ? await capture(command, a.cwd, baseEnv(), CAPTURE_MS) : await this.#captureOn(from, session, ws, command);
      const end = got.timedOut ? "it ran too long" : got.code !== null ? `exit code ${got.code}` : `ended by ${got.signal}`;
      const what = a.path !== undefined ? `The file could not be read (${end}); nothing was kept.` : `The command did not print the secret (${end}); nothing was kept.`;
      if (got.timedOut || got.code !== 0) throw new Refused(`${what} What it said on stderr:\n${got.err.slice(-2000)}`);
      if (got.tooLong) throw new Refused(`${a.path !== undefined ? "The file is" : "The command printed"} more than 64 KB: that is not one secret; nothing was kept.`);
      if (kind === "file" && got.raw === undefined) throw new Refused(`${from?.name ?? "That station"} cannot read a file as its bytes yet: update it.`);
      value = kind === "file" ? got.raw! : got.out;
    }
    if (kind === "file" && Buffer.byteLength(value, "base64") > FILE_MOST) throw new Refused(`The file is more than ${FILE_MOST / 1024} KB; nothing was kept.`);
    if (value === "" && !typed) throw new Refused("The secret is empty; nothing was kept.");
    const fields = typed ? null : fieldsOf(value);
    const id = `r_${ulid(now)}`;
    const save: Save = {
      kind, name, modes, hosts, ...(a.env ? { env: a.env } : {}), ...(a.username ? { username: a.username } : {}), ...(a.public_key ? { public_key: a.public_key } : {}), ...(filename ? { filename } : {}),
      ...(typed ? { typed: true as const } : {}),
    };
    const request: Request = {
      id, ws, vault: lock === null ? PLAIN : this.#vaultFor(lock, sub!), item, session, chat: "", mode: modes[0]!, reason: a.reason.trim(),
      ...(command !== undefined ? { command } : {}), ...(hosts.length ? { hosts } : {}),
      // A vault's: a box for the grant to this chat that comes with keeping it (the app seals the secret to it too).
      box: lock === null ? "" : this.keeper.open(id), at: Math.floor(now / 1000), status: "pending", owner: email, save, ...(from ? { runOn: from } : {}),
      ...(lock !== null && fields !== null ? { sealed: this.#certsOf(lock, sub!).map((c) => this.#sealTo(c, ws, id, fields)) } : {}),
    };
    if (fields !== null) this.#unsaved.set(id, fields);
    const kept: Kept = { request, thread: null, cardTs: null };
    const thread = this.#d.hub.store.latestThread(session);
    if (thread !== null) {
      request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
      kept.cardTs = await this.#postSave(session, thread, request);
      kept.thread = thread.thread.id;
    }
    this.#save(kept);
    this.#audit(request, "save-request", [modes.join(" "), hosts.join(" "), from ? `${from.name}: ${command}` : (command ?? ""), typed ? "typed" : ""].filter((x) => x !== "").join(" · "));
    this.#told(request);
    const decided = await this.#decision(id, WAIT_MS);
    return this.#saidSave(decided ?? request);
  }

  /// The card of a request to keep a secret: what it is, whose, why (the app draws it from `vault.save`, offering to
  /// turn the vault on first where it is not).
  async #postSave(session: string, thread: SessionThread, r: Request): Promise<string | null> {
    const s = r.save!;
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const kind = `（${KIND_WORDS[s.kind]}${s.username ? ` · ${s.username}` : s.filename ? ` · ${s.filename}` : ""}）`;
    const text = [
      s.typed ? `请填入「${s.name}」${kind}并存入密钥库：${r.reason}` : `申请将「${s.name}」存入密钥库${kind}：${r.reason}`,
      ...(stillfail ? [] : [s.typed ? "请在 still.fail 客户端的「密钥」中填写并存入。" : "请在 still.fail 客户端的「密钥」中批准。"]),
    ].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ ...SAVE_WORDS.save, recommended: true }, SAVE_WORDS.deny],
          assignee: r.owner,
          // The request as the app draws it (VaultAsk.tsx): `save` says it is one to keep; its outcome added once decided.
          vault: {
            request: r.id, name: s.name, reason: r.reason, ...(r.command ? { command: r.command } : {}), mode: s.modes[0], hosts: s.modes[0] === "proxy" ? s.hosts : [],
            ...(r.runOn ? { station: r.runOn.name } : {}),
            save: { kind: s.kind, ...(s.username ? { username: s.username } : {}), ...(s.filename ? { filename: s.filename } : {}), ...(s.typed ? { typed: true } : {}) },
          },
        }
      : null;
    return this.#postCard(session, thread, text, card);
  }

  /// What an agent is told of a request to keep a secret, waiting or decided.
  #saidSave(r: Request): string {
    const s = r.save!;
    const whose = r.owner ?? "the person";
    if (r.status === "granted") {
      const held = this.keeper.usable(r.session, r.id);
      const use = typeof held === "string"
        ? `When you need it, ask with secret_use {item: "${s.name}"}, then secret_run.`
        : `This chat may use it now: secret_run {grant: "${r.id}", command: "…"${s.env ? "" : ', env: "NAME"'}} (${held.grant.mode === "proxy" ? `through the proxy to ${held.grant.hosts.join(", ")}` : held.grant.mode === "ssh" ? "by ssh-agent" : held.grant.mode === "file" ? "as a file, its path in the variable" : "in the environment"}); other chats ask with secret_use.`;
      return `Kept: 「${s.name}」 is in ${whose}'s vault now (item ${r.item}). ${use}${typeof held === "string" ? "" : accountSaid(held)}`;
    }
    if (r.status === "denied") return `${whose} chose not to keep 「${s.name}」 (request ${r.id}).`;
    if (r.status === "expired") return `The request to keep 「${s.name}」 (${r.id}) was let go.`;
    const off = r.vault === "" && !s.typed ? " Their vault is not turned on yet: the card lets them turn it on in the still.fail app, and then keep it." : "";
    const asked = s.typed
      ? `Asked ${whose} to type 「${s.name}」 in (request ${r.id}): its card has a field for it, and what they type goes into their vault as they approve it in the still.fail app (turning their vault on first where it is not), never to you.`
      : `Asked to keep 「${s.name}」 (request ${r.id}); the card is in your chat for ${whose}, who approves it in the still.fail app.${off}`;
    return `${asked} Not decided yet: end your turn need_human (about the card), and you are told when it is decided. Only their approval in the app keeps it: a reply in the chat saying yes does not.`;
  }

  /// A device's box key published (PUT vault/boxes, checked): the secrets waiting to be kept for its person sealed to
  /// it too, so that they may approve them from it.
  boxed(lock: LockState, cert: BoxCert) {
    const sub = lock.devices.get(cert.device)?.sub;
    const email = sub === undefined ? undefined : lock.members.get(sub)?.email.toLowerCase();
    if (sub === undefined || email === undefined) return;
    const rows = this.#d.db.prepare("SELECT body FROM vault_requests WHERE ws = ? AND status = 'pending'").all(lock.ws) as { body: string }[];
    for (const row of rows) {
      const r = JSON.parse(row.body) as Request;
      const fields = this.#unsaved.get(r.id);
      if (!r.save || r.vault === PLAIN || r.owner !== email || fields === undefined || r.sealed?.some((x) => x.box === cert.box)) continue;
      const k = this.#kept(r.ws, r.id)!;
      k.request.sealed = [...(r.sealed ?? []).filter((x) => x.device !== cert.device), this.#sealTo(cert, r.ws, r.id, fields)];
      if (k.request.vault === "") k.request.vault = this.#vaultFor(lock, sub);
      this.#save(k);
      this.#told(k.request);
    }
  }

  /// POST vault/saves: a secret asked to be kept, written by `sub`'s app into their vault `vault` (under the request's
  /// item id; its copy brought here first); why it is refused, or null.
  saved(lock: LockState, sub: string, d: { request?: unknown; vault?: unknown; grant?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(lock.ws, d.request) : null;
    if (k === null || !k.request.save || k.request.vault === PLAIN) return "no such request to keep a secret in a vault";
    if (lock.members.get(sub)?.email.toLowerCase() !== k.request.owner) return "only the person it is kept for decides it";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const vault = typeof d.vault === "string" ? this.#d.vaults.vault(lock.ws, d.vault) : null;
    if (vault === null || !vault.members.includes(sub)) return "no such vault of theirs here";
    const item = this.#d.vaults.item(lock.ws, vault.id, k.request.item);
    if (item === null || item.deleted || item.listing?.name !== k.request.save.name) return "the item is not in that vault here: bring its copy first";
    // Keeping it lets the chat that asked use it (its app's grant, sealed to this request's box): kept all the same if
    // that grant does not hold.
    const why = d.grant === undefined ? "none sent" : this.keeper.accept(lock, vault, item, { ...k.request, vault: vault.id }, d.grant as Grant);
    if (why !== null) {
      log.warn("vault", "a kept secret's grant to its chat not taken", { why });
      // Its box is of no more use.
      if (this.keeper.waiting(k.request.id)) this.keeper.drop(k.request.id);
    }
    this.#settle(k.request, "granted", undefined, vault.id);
    return null;
  }

  /// POST vault/plain/saves: a secret asked to be kept, approved by whoever it is for (no security mode): written into
  /// the plain library here; one they type in, with its `fields` as their app sent them. The item as written, or why not.
  savedPlain(ws: string, lock: LockState | null, email: string, d: { request?: unknown; fields?: unknown }): PlainItem | string {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || !k.request.save || k.request.vault !== PLAIN) return "no such request to keep a secret";
    if (k.request.owner !== email.toLowerCase()) return "only the person it is kept for decides it";
    if (lock !== null) return "security mode is on: secrets go into the vault, encrypted";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const s = k.request.save;
    const fields = s.typed ? typedFields(s.kind, d.fields) : this.#unsaved.get(k.request.id);
    if (fields === undefined) return s.typed ? "this secret is typed in on its card, and sent with its fields (an app from before that cannot: update it)" : "the secret is gone (the station restarted): the agent asks again";
    const next: PlainItem = {
      ws, id: k.request.item, owner: k.request.owner!, version: 0, kind: s.kind, name: s.name, fields, notes: "",
      listing: { name: s.name, kind: s.kind, modes: s.modes, hosts: s.hosts, ...(s.env ? { env: s.env } : {}) }, at: Math.floor(this.#d.now() / 1000),
    };
    if (this.#d.plain.item(ws, next.id) !== null) return "the item is there already";
    const why = plainOk(null, next, next.owner);
    if (why !== null) return why;
    this.#d.plain.put(next);
    // Keeping it lets the chat that asked use it, for as long as the person's items are given.
    const lasts = this.#d.plain.lasts(ws, next.owner)?.lasts ?? null;
    const scope = SCOPES.filter((x) => allows(lasts, x)).at(-1)!;
    const held = this.keeper.hold(k.request, { scope, hosts: s.modes[0] === "proxy" ? s.hosts : [], listing: next.listing!, lasts }, { kind: s.kind, name: s.name, fields });
    if (held !== null) log.warn("vault", "a kept secret's grant to its chat not held", { why: held });
    this.#settle(k.request, "granted");
    return this.#d.plain.item(ws, next.id)!;
  }

  /// A request decided otherwise than granted, or granted (`grant` checked by the keeper first); `into`: the vault a
  /// secret to keep went into.
  #settle(r: Request, status: Request["status"], scope?: Scope, into?: string) {
    const k = this.#kept(r.ws, r.id);
    if (k === null || k.request.status !== "pending") return;
    k.request.status = status;
    if (into !== undefined) k.request.vault = into;
    this.#save(k);
    this.#unsaved.delete(r.id);
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
        this.#d.hub.notify(r.session, k.request.save ? this.#saidSave(k.request) : l ? this.#said(k.request, l) : `The request ${r.id} was ${status}.`);
      } catch {
        // The session is gone: nobody to tell.
      }
    }
  }

  /// POST vault/grants: `grant`, sent by `sub`'s app; why it is refused, or null.
  grant(lock: LockState, sub: string, grant: Grant): string | null {
    const k = typeof grant?.request === "string" ? this.#kept(lock.ws, grant.request) : null;
    if (k === null) return "no such request";
    if (k.request.save) return "a secret to keep is approved by POST vault/saves";
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
    if (k.request.save) return "a secret to keep is approved by POST vault/plain/saves";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (lock !== null) return "security mode is on: the plain library's secrets are moved into the vault, not given out";
    const item = this.#d.plain.item(ws, k.request.item);
    if (item === null || item.deleted || item.listing === undefined) return "the item is gone, or not one agents may ask for";
    const hosts = k.request.mode === "proxy" ? (k.request.hosts ?? item.listing.hosts) : [];
    const why = this.keeper.hold(k.request, { scope: d.scope as Scope, hosts, listing: item.listing, lasts: this.#lastsOf(k.request, item.listing) }, { kind: item.kind, name: item.name, fields: item.fields });
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
    const by = typeof d.sig?.key === "string" ? signerOf(lock, d.sig.key) : null;
    if (k.request.save) {
      // A secret to keep: its owner's to turn down, from one of their devices.
      if (lock.members.get(sub)?.email.toLowerCase() !== k.request.owner) return "only the person it is kept for decides it";
      if (by === null || by.sub !== sub) return "a refusal is signed by one of their devices in the lock";
    } else {
      const vault = this.#d.vaults.vault(lock.ws, k.request.vault);
      if (vault === null || !vault.members.includes(sub)) return "only the vault's members decide its requests";
      if (by === null || !vault.members.includes(by.sub)) return "a refusal is signed by a vault member's device in the lock";
    }
    if (!signedOk(d, TAG.deny)) return "the refusal's signature is invalid";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    this.#settle(k.request, "denied");
    return null;
  }

  /// secret_run: `command` with grant `id`, in the session's workspace (or `cwd` under it).
  /// `under`: `cwd` as given, under the session's directory (the one used on another station).
  async run(session: string, a: { grant: string; command: string; env?: string; cwd: string; under?: string; timeoutMs?: number; station?: string }): Promise<string> {
    const held = this.keeper.usable(session, a.grant);
    if (typeof held === "string") throw new Refused(held);
    if (a.env !== undefined && !/^[A-Za-z_][A-Za-z0-9_]*$/.test(a.env)) throw new Refused("env must be a variable name");
    // Where it was granted for, and nowhere else.
    const on = held.request.runOn ?? null;
    if (a.station !== undefined && a.station.trim() !== "") {
      const asked = this.#peer(a.station);
      if ((asked?.id ?? null) !== (on?.id ?? null)) {
        throw new Refused(on ? `This grant is for commands on ${on.name}: run them there (station "${on.name}", or none), or ask again.` : `This grant is for commands on this station: to run them on ${asked!.name}, ask again with secret_use {station: "${asked!.name}"}.`);
      }
    }
    const listing = this.#listingOf(held.request);
    this.keeper.spend(held.request.id);
    const env = a.env ?? listing?.env;
    const timeoutMs = Math.min(a.timeoutMs ?? RUN_MS, 3600_000);
    if (on !== null) {
      const ran = await this.#runOn(on, session, held, { command: a.command, under: a.under ?? "", timeoutMs, ...(env ? { env } : {}) });
      this.#audit(held.request, "run", `${on.name}: ${a.command}`.slice(0, 500));
      return said(ran);
    }
    // The station does not update itself meanwhile: the proxy or ssh-agent the command uses is this process's.
    const letGo = hold();
    const ran = await runWith(held, { command: a.command, cwd: a.cwd, ...(env ? { env } : {}), timeoutMs }, this.proxy, baseEnv(), (detail) =>
      this.#audit(held.request, "use", detail),
    ).finally(letGo);
    this.#audit(held.request, "run", a.command.slice(0, 500));
    return said(ran);
  }

  // ── commands on another station of the workspace (docs/vault.md 在另一台 station 上用) ──

  /// Station `given` (its name or id): another of the workspace, or null for this one.
  #peer(given: string): { id: string; name: string } | null {
    if (!this.#d.peer) throw new Refused("this station does not reach the workspace's other stations");
    try {
      return this.#d.peer(given.trim());
    } catch (e) {
      throw new Refused((e as Error).message);
    }
  }

  /// `request` sent to station `on`, which answers at once that it started and says how it ended later (`vault.done`):
  /// that, or a refusal when it would not start or said nothing within `ms` and a while.
  #elsewhere(on: { id: string; name: string }, request: Record<string, Json>, ms: number): Promise<Json> {
    const ask = this.#d.ask;
    if (!ask) return Promise.reject(new Refused("this station does not reach the workspace's other stations"));
    const id = `x_${ulid(this.#d.now())}`;
    return new Promise<Json>((resolve, reject) => {
      // How long its end is waited for: the machine's time, as the command's own is on that station.
      const stop = wall.after(ms + 120_000, () => {
        if (this.#away.delete(id)) reject(new Refused(`${on.name} did not say how the command ended; it may still have run`));
      });
      this.#away.set(id, { station: on.id, done: (result) => (stop(), resolve(result)) });
      ask(on.id, { ...request, id }).then(
        (answer) => {
          if ((answer as { started?: unknown } | null)?.started === true || !this.#away.delete(id)) return;
          stop();
          reject(new Refused(`${on.name} did not start it (a station from before this cannot: update it)`));
        },
        (e) => {
          if (!this.#away.delete(id)) return;
          stop();
          const why = (e as Error).message;
          // A station from before this answers what it does not know as one of its remote tasks.
          const old = /unknown method|task key are required|unknown task/.test(why) ? " (a station from before this cannot: update it)" : "";
          reject(new Refused(`${on.name} did not start it: ${why}${old}`));
        },
      );
    });
  }

  /// A command run with grant `held` on station `on`, in the session's directory there (`under` it).
  async #runOn(on: { id: string; name: string }, session: string, held: Held, a: { command: string; under: string; timeoutMs: number; env?: string }): Promise<Ran> {
    const { ws } = this.#placeOf(session);
    const result = (await this.#elsewhere(on, {
      method: "vault.run", workspace: ws, session, grant: held.request.id, command: a.command, under: a.under, timeoutMs: a.timeoutMs,
      ...(a.env ? { env: a.env } : {}), mode: held.grant.mode, hosts: held.grant.hosts, secret: held.secret as unknown as Json,
    }, a.timeoutMs)) as Partial<Ran> | null;
    if (result === null || typeof result.output !== "string") throw new Refused(`${on.name} said nothing of how the command ended`);
    return { code: typeof result.code === "number" ? result.code : null, signal: typeof result.signal === "string" ? result.signal : null, output: result.output, cut: result.cut === true, timedOut: result.timedOut === true };
  }

  /// What a command printed on station `on`, run in the session's directory there, taken as a secret to keep.
  async #captureOn(on: { id: string; name: string }, session: string, ws: string, command: string): Promise<Captured> {
    const got = (await this.#elsewhere(on, { method: "vault.capture", workspace: ws, session, command, under: "", timeoutMs: CAPTURE_MS }, CAPTURE_MS)) as Partial<Captured> | null;
    if (got === null || typeof got.out !== "string" || typeof got.err !== "string") throw new Refused(`${on.name} said nothing of what the command printed`);
    return {
      code: typeof got.code === "number" ? got.code : null, signal: typeof got.signal === "string" ? got.signal : null, out: got.out, ...(typeof got.raw === "string" ? { raw: got.raw } : {}), err: got.err,
      timedOut: got.timedOut === true, tooLong: got.tooLong === true,
    };
  }

  /// A request of another station of the workspace (`vault.`): a command to run here with a secret it holds a grant
  /// for, or one whose output it takes as a secret to keep, each in its session's directory here, answered at once and
  /// ended by asking that station back (`vault.done`); or how one sent from here ended.
  async heard(peer: string, ws: string, request: Json): Promise<Json> {
    const r = (request ?? {}) as Record<string, unknown>;
    const method = typeof r.method === "string" ? r.method : "";
    const id = typeof r.id === "string" ? r.id : "";
    if (method === "vault.done") {
      const away = this.#away.get(id);
      if (away === undefined || away.station !== peer) throw new Error("no such command sent to that station");
      this.#away.delete(id);
      away.done((r.result ?? null) as Json);
      return { ok: true };
    }
    if (method !== "vault.run" && method !== "vault.capture") throw new Error(`unknown method ${method}`);
    const session = typeof r.session === "string" ? r.session : "";
    const command = typeof r.command === "string" ? r.command : "";
    const under = typeof r.under === "string" ? r.under : "";
    const timeoutMs = Number.isSafeInteger(r.timeoutMs) ? Math.min(Math.max(1, r.timeoutMs as number), 3600_000) : RUN_MS;
    if (!/^x_[0-9A-Z]{26}$/.test(id) || session === "" || session.length > 256 || command.trim() === "") throw new Error("id, session and command are required");
    if (under.startsWith("/") || under.split(/[\\/]/).includes("..")) throw new Error("under is a path inside the session's directory");
    if (!this.#d.workOf || !this.#d.ask) throw new Error("this station runs no commands for others");
    const ask = this.#d.ask;
    const cwd = joinUnder(this.#d.workOf(ws, peer, session), under);
    const tell = (result: Json) =>
      ask(peer, { method: "vault.done", workspace: ws, id, result }).catch((e) => log.warn("vault", "a command's end not told to its station", { error: (e as Error).message }));
    // The station does not update itself meanwhile: the proxy or ssh-agent the command uses is this process's.
    const letGo = hold();
    if (method === "vault.capture") {
      void capture(command, cwd, baseEnv(), Math.min(timeoutMs, CAPTURE_MS))
        .then((got) => tell(got as unknown as Json), (e) => tell({ code: null, signal: null, out: "", err: `could not run it: ${(e as Error).message}`, timedOut: false, tooLong: false }))
        .finally(letGo);
      return { started: true };
    }
    const mode = MODES.includes(r.mode as Mode) ? (r.mode as Mode) : null;
    const secret = r.secret as { kind?: unknown; name?: unknown; fields?: unknown } | null;
    const hosts = Array.isArray(r.hosts) ? r.hosts.filter((h): h is string => typeof h === "string") : [];
    const env = typeof r.env === "string" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(r.env) ? r.env : undefined;
    const grant = typeof r.grant === "string" ? r.grant : "";
    if (mode === null || grant === "" || secret === null || typeof secret !== "object" || typeof secret.fields !== "object" || secret.fields === null) {
      letGo();
      throw new Error("mode, grant and secret are required");
    }
    const fields = Object.fromEntries(Object.entries(secret.fields as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === "string"));
    const held = { request: { id: grant }, grant: { mode, hosts }, secret: { kind: String(secret.kind ?? ""), name: String(secret.name ?? ""), fields }, uses: 0 } as unknown as Held;
    if (valueOf(held.secret) === null) {
      letGo();
      throw new Error("the secret holds no value");
    }
    void runWith(held, { command, cwd, timeoutMs, ...(env ? { env } : {}) }, this.proxy, baseEnv(), () => {})
      .then((ran) => tell(ran as unknown as Json), (e) => tell({ code: null, signal: null, output: `could not run it: ${(e as Error).message}`, cut: false, timedOut: false }))
      .finally(letGo);
    return { started: true };
  }

  /// The grants a session holds that may still be used.
  held(session: string): Held[] {
    return this.keeper.held(session);
  }
}

/// `dir`/`under`, made if need be.
/// What an agent is told of a login's account: not secret, so said, and in the variable each command gets it in.
function accountSaid(held: Held): string {
  const account = accountOf(held.secret);
  return account === null ? "" : ` The login's account is ${JSON.stringify(account)}, in ${ACCOUNT_VAR} too.`;
}

function joinUnder(dir: string, under: string): string {
  const at = under === "" ? dir : `${dir}/${under}`;
  mkdirSync(at, { recursive: true });
  return at;
}

/// The station's environment, without what would let a command act as the station or its agents' accounts.
const baseEnv = (): Record<string, string> =>
  Object.fromEntries(Object.entries(process.env).filter((e): e is [string, string] => e[1] !== undefined && !/^(STILLFAIL_|EMBER_|ANTHROPIC_|CLAUDE_|OPENAI_|CODEX_)/.test(e[0])));

function said(r: Ran): string {
  const end = r.timedOut ? "stopped: it ran too long" : r.code !== null ? `exit code ${r.code}` : `ended by ${r.signal}`;
  return `${end}${r.cut ? " (output cut in the middle)" : ""}\n${r.output}`;
}

export { Refused };
