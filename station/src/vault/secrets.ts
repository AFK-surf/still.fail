// Agents asking for the vault's secrets (agent 用密钥): a request from a session, its card in the
// session's chat for the vault's owner, the grant or refusal the owner's app sends back (checked by the keeper, which
// alone ever holds the secret), and the commands run with a grant. Without security mode, the secrets are the plain
// library's (plain.ts): the same request and card, decided by the item's owner, the value read from the station. An
// agent may also ask to keep a secret in its owner's vault (secret_save): sealed to their devices, written by the app
// that approves it (or, without security mode, into the plain library here); or one only they hold, typed in on its card
// by them, written by their app as it is approved (`save.typed`). A grant may be for commands on another
// station of the workspace (`runOn`): the secret is sent there over the station transport for each command, run in the
// session's directory there, and only the outcome comes back. The requests and what was done with them are kept
// in the station's database (`vault_requests`, `vault_audit`), never a secret; the vaults' grants only in memory (carried
// over to the next process at a handover, `carried`), the plain library's written down without their value (`vault_grants`) and taken up again after a restart. A grant ends
// with its chat: archived or deleted, its session's grants are dropped.
import { createHash, randomBytes } from "node:crypto";
import { basename } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import { devicesFor, memberWithEmail, membersWithEmail, type LockState } from "../cloud/lock.ts";
import type { To } from "../api/events.ts";
import { UNDECIDED, threadAddress } from "../agents/instructions.ts";
import { Fibers, wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { foreground } from "../store/backfill.ts";
import type { CardOutcomeSaver } from "../store/card-outbox.ts";
import { type Json, STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";
import { CARD_OCCUPIED, cardPlace, recordPostedCard } from "../sessions/card-place.ts";
import type { Hub } from "../sessions/hub.ts";
import { hold } from "../updates/holds.ts";
import { stateOf } from "../browser/signins.ts";
import { ABOUT_MOST, type BoxCert, type Deny, type Grant, type Item, type Kind, type Listing, type Mode, type Request, type Save, type Scope, type Sealed, type Vault, SCOPES, TAG, allows, certOk, saveContext, seal, signedOk, signerOf } from "./crypto.ts";
import { type Carried, type Held, Keeper, accountOf, hostAllowed, valueOf } from "./keeper.ts";
import { FILE_MOST, KINDS, MODES, PLAIN, type PlainItem, type PlainStore, plainOk } from "./plain.ts";
import { Proxy, placeholder } from "./proxy.ts";
import { CAPTURE_MS, Incoming, RUN_MS, baseEnv } from "./incoming.ts";
import { ACCOUNT_VAR, type Captured, type Ran, SECRET_VAR, capture, runWith } from "./run.ts";
import type { VaultStore } from "./store.ts";
import { UseIndex } from "./use-index.ts";
import { hasVaultMembers, initializePendingIndex, pendingAuditComplete, pendingIndexComplete, pendingIndexStarted, PENDING_BODIES, PENDING_DUE, PENDING_DUPLICATES, PENDING_MEMBER, PENDING_NO_TIME, PENDING_NUL_FIELDS, PENDING_OTHER_TIME, PENDING_OWN, PENDING_SEED, PENDING_SEED_FIRST } from "./pending-index.ts";
import { hasInvalidVaultMembers, vaultMembersComplete, vaultMembersStarted } from "./member-index.ts";
import { reboxIndexComplete, REBOX_LEGACY, REBOX_READY } from "./rebox-index.ts";

export const CARRIED_SAVE_PENDING = "SELECT body FROM vault_requests WHERE ws = ? AND id = ? AND status = 'pending'";
const LISTING_PREFIX = 32;
const EXPIRED_GRANT_BATCH = 32;
type SavedGrant = { request: Request; grant: Omit<Grant, "secret">; uses: number; until?: number };
type RestoreRow = { ws: string; id: string; body: string };
type ExpiredGrant = { row: RestoreRow; saved: SavedGrant; now: number };

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
CREATE TABLE IF NOT EXISTS vault_renewals (
  ws TEXT NOT NULL,
  item TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, item)
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

/// A request no one decided is let go after a day.
const PENDING_SECS = 86400;

/// The words on the card of a request to delete an item.
const REMOVE_WORDS = {
  yes: { label: "删除", detail: "从密钥库删除这条密钥" },
  no: { label: "保留", detail: "不删除，通知 agent" },
};
/// The words on the card of a request to keep a secret.
const SAVE_WORDS = {
  save: { label: "存入密钥库", detail: "agent 之后每次使用仍需你批准" },
  deny: { label: "拒绝", detail: "不保存，通知 agent" },
};
/// The words on the card of a request to rename an item or say what it is.
const DESCRIBE_WORDS = {
  yes: { label: "确认修改", detail: "按以上内容修改名称与说明" },
  no: { label: "保持不变", detail: "不作修改，通知 agent" },
};
const KIND_WORDS: Record<Kind, string> = { token: "Token", login: "登录", ssh_key: "SSH 密钥", file: "文件", browser: "登录态" };
const howWords = (mode: Mode, hosts: string[]): string =>
  mode === "proxy" ? `代理（限 ${hosts.join(", ")}）` : mode === "ssh" ? "ssh-agent（私钥不出 station）" : mode === "file" ? "文件（命令运行时临时写出，可读取内容）"
  : mode === "browser" ? `放进这个对话的浏览器（限 ${hosts.join(", ")}，到期取出）` : "环境变量（命令可读取明文）";
/// Whether a request in `mode` names the hosts it goes to (on its card, in its grant).
const hosted = (mode: Mode): boolean => mode === "proxy" || mode === "browser";

/// The field of each kind that holds its secret.
const SECRET_FIELD: Record<Kind, string> = { token: "value", login: "password", ssh_key: "private_key", file: "content", browser: "cookies" };
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

/// What a sign-in's cookies are known by where they are not kept (a renewal's, `#renewalGranted`).
const digestOf = (cookies: string): string => createHash("sha256").update(cookies, "utf8").digest("hex");

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
  cardOutcomes?: CardOutcomeSaver;
  vaults: VaultStore;
  plain: PlainStore;
  /// The station's home workspace (a session of it has none of its own).
  home(): string | null;
  /// A chat's title, for the uses of a secret.
  title?(session: string): string | null;
  /// Its title without an old-order fallback; undefined means its order needs preparation.
  titleIfReady?(session: string): string | null | undefined;
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
  /// Whether what the process before this one held may still come (a handover under way, `carry`): until then a
  /// request whose box is not here yet is not let go.
  coming?(): boolean;
  /// Background use-index work waits for the previous process and gives foreground database writes priority.
  backfill?: { previousGone?: Promise<void>; priority?: SharedArrayBuffer };
  /// The chats' browsers (browser/browsers.ts), for sign-ins (kind browser); none: no sign-in is kept or given.
  browsers?: SignIns;
};

/// What the vault asks of the chats' browsers for sign-ins (browser/browsers.ts Browsers).
export type SignIns = {
  /// The cookies of `sites` (each with its subdomains) in `session`'s chat's browser, or in the station's own
  /// (`station`: where sign-ins were made before chats had browsers of their own), as JSON; the browser started if need be.
  cookies(session: string, sites: string[], station: boolean): Promise<string>;
  /// The passkeys of a sign-in still granted put into `session`'s chat's browser again (passkeysAgain).
  passkeysIn?(session: string, d: { sites: string[]; cookies: string }): Promise<void>;
  /// Grant `request`'s sign-in put into `session`'s chat's browser until `until` (unix seconds): its cookies of `sites`
  /// set now, taken out again then.
  signIn(session: string, d: { request: string; workspace?: string; sites: string[]; cookies: string; until: number }): Promise<void>;
  extendSignIn?(session: string, request: string, until: number): void;
};

/// What goes over to the next station process at a handover, from memory to memory (never written down): the keeper's
/// boxes and grants, and the secrets agents asked to keep, until decided.
type SaveScope = { ws: string; owner: string };
export type SecretsCarried = { keeper: Carried; unsaved: [string, Record<string, string>, SaveScope[]?][] };

/// A command sent to another station to run, or one it sent here, waiting for how it ended.
type Away = { station: string; session?: string; workspace?: string; done(result: Json): void; used?(): number | null };

/// A request as the station keeps it: the contract's, and where its card is.
type Kept = { request: Request; thread: number | null; cardTs: string | null; raw?: string };

/// What a tool or a route is told when it cannot go on.
class Refused extends Error {}
class DecisionChanged extends Error {}
class DecisionCardMoved extends Error {}

/// An item an agent may ask for: of a vault (its id) or of the plain library (`plain`), whose owner (email) decides.
export type Listed = { vault: string; item: string; owner: string | null; listing: Listing };

/// A use of a secret, as the pages list them: a request decided, in the chat that asked.
export type Use = { item: string; at: number; session: string; chatTitle: string | null; mode: Mode; command: string | null; hosts: string[]; denied: boolean };

export class Secrets {
  readonly keeper: Keeper;
  readonly proxy: Proxy;
  /// The plain library's items ( 不加锁的库).
  readonly plain: PlainStore;
  readonly #d: SecretsDeps;
  readonly #uses: UseIndex;
  readonly #listeners: ((r: Request) => void)[] = [];
  /// Who hears of an item of the plain library written here (a sign-in's new cookies).
  #plainWritten: (i: PlainItem) => void = () => {};
  /// The secrets agents asked to keep, by request, until decided: only in memory (a restart forgets them). The plain
  /// library's is written from here once approved; a vault's is sealed to its owner's devices set up later.
  readonly #unsaved = new Map<string, Record<string, string>>();
  /// The held saves by workspace and owner. The fields remain only in `#unsaved`.
  readonly #savesByOwner = new Map<string, Map<string, Set<string>>>();
  readonly #saveScopes = new Map<string, SaveScope[]>();
  /// Older handovers have fields but no scope; reboxed discovers those already written by the earlier process.
  readonly #unscopedSaves = new Set<string>();
  /// A save whose card is being posted has not been written yet; a device published meanwhile must get it too.
  readonly #postingSaves = new Map<string, Request>();
  /// Saves whose fields have gone and which have no sealed copy, by workspace; built once after the previous process exits.
  readonly #lostSaves = new Map<string, { ids: Set<string>; ready: boolean }>();
  /// The same lost ids in reverse, so taking a carried save does not traverse unrelated workspaces.
  readonly #lostScopes = new Map<string, Set<string>>();
  /// A held id can also name a pending save outside the scopes that came with it.
  readonly #heldLostScopes = new Map<string, Set<string>>();
  readonly #preparingPending = new Map<string, Promise<void>>();
  readonly #memberAudits = new Map<string, Promise<void>>();
  readonly #pendingAudits = new Map<string, Promise<void>>();
  #previousExited = false;
  /// Grants whose startup cleanup raced repeatedly with another writer, retried after handover.
  readonly #restorePending = new Map<string, { ws: string; id: string }>();
  #restoreWaiting = false;
  #restoreClosed = false;
  #restoreFibers: Fibers | null = null;
  #restoreRemove: ReturnType<DatabaseSync["prepare"]> | undefined;
  #restoreRemoveItem: ReturnType<DatabaseSync["prepare"]> | undefined;
  #restoreRead: ReturnType<DatabaseSync["prepare"]> | undefined;
  #restoreConfirm: ReturnType<DatabaseSync["prepare"]> | undefined;
  /// Saves to reconcile after the old process can no longer write requests or device certificates.
  readonly #carriedSaves = new Set<string>();
  #carriedSavesWaiting = false;
  /// Certificate writes can succeed even if a competing request write delays reboxing. Retry while the fields live here.
  readonly #reboxPending = new Map<string, { ws: string; device: string; delay: number }>();
  #reboxFibers: Fibers | null = null;
  #reboxScheduled = false;
  /// Commands sent to other stations, by the id they say how they ended under (`vault.done`).
  readonly #away = new Map<string, Away>();
  /// The commands other stations send to run here (vault/incoming.ts).
  readonly #runs: Incoming;

  constructor(d: SecretsDeps) {
    this.#d = d;
    this.#previousExited = d.backfill?.previousGone === undefined;
    if (d.backfill?.previousGone !== undefined) void d.backfill.previousGone.then(() => { this.#previousExited = true; }, () => {});
    d.db.exec(SCHEMA);
    initializePendingIndex(d.db);
    this.#uses = new UseIndex(d.db, d.backfill);
    const ended = (session: string) => {
      const row = d.hub.store.getSession(session);
      return row === null || row.archivedAt != null;
    };
    // Other connections can use, renew, or remove the same plain grant. A use or renewal must never recreate an
    // already removed record, and concurrent uses of a reusable grant must not overwrite each other's counts.
    const updateRepeated = (h: Held, until?: number): { uses: number; until?: number } | false | null => {
      if (h.request.vault !== PLAIN) return null;
      const { secret: _, ...grant } = h.grant;
      for (let attempt = 0; attempt < 3; attempt++) {
        const row = d.db.prepare("SELECT body FROM vault_grants WHERE ws = ? AND id = ?").get(h.request.ws, h.request.id) as { body: string } | undefined;
        if (row === undefined) return false;
        const stored = JSON.parse(row.body) as { request: Request; grant: Omit<Grant, "secret">; uses: number; until?: number };
        if (!Number.isSafeInteger(stored.uses) || stored.uses < 0 || (stored.until ?? stored.grant.exp) <= Math.floor(d.now() / 1000)
          || JSON.stringify(stored.request) !== JSON.stringify(h.request) || JSON.stringify(stored.grant) !== JSON.stringify(grant)) return false;
        const nextUntil = until === undefined ? stored.until : Math.max(stored.until ?? stored.grant.exp, until);
        const uses = stored.uses + (until === undefined ? 1 : 0);
        const body = JSON.stringify({ ...stored, uses, ...(nextUntil === undefined ? {} : { until: nextUntil }) });
        if (Number(d.db.prepare("UPDATE vault_grants SET body = ? WHERE ws = ? AND id = ? AND body = ?")
          .run(body, h.request.ws, h.request.id, row.body).changes) !== 0) {
          return { uses, ...(nextUntil === undefined ? {} : { until: nextUntil }) };
        }
      }
      return false;
    };
    this.keeper = new Keeper(() => Math.floor(d.now() / 1000), {
      ended,
      kept: {
        // The plain library's only: a vault's secret is never written down, and its grant is gone with the process.
        save: (h) => {
          if (h.request.vault !== PLAIN) return;
          const { secret: _, ...grant } = h.grant;
          d.db.prepare("INSERT INTO vault_grants (ws, id, session, body) VALUES (?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET body = excluded.body")
            .run(h.request.ws, h.request.id, h.request.session, JSON.stringify({ request: h.request, grant, uses: h.uses, ...(h.until === undefined ? {} : { until: h.until }) }));
        },
        current: (h) => {
          if (h.request.vault !== PLAIN) return null;
          const row = d.db.prepare("SELECT body FROM vault_grants WHERE ws = ? AND id = ?").get(h.request.ws, h.request.id) as { body: string } | undefined;
          if (row === undefined) return false;
          const stored = JSON.parse(row.body) as { request: Request; grant: Omit<Grant, "secret">; uses: number; until?: number };
          const { secret: _, ...grant } = h.grant;
          if (!Number.isSafeInteger(stored.uses) || stored.uses < 0
            || (stored.until !== undefined && !Number.isSafeInteger(stored.until))
            || JSON.stringify(stored.request) !== JSON.stringify(h.request) || JSON.stringify(stored.grant) !== JSON.stringify(grant)) return false;
          return { uses: stored.uses, ...(stored.until === undefined ? {} : { until: stored.until }) };
        },
        // Claim a persisted one-use grant with one conditional write: the previous station may still be running.
        spendOnce: (h) => {
          if (h.request.vault !== PLAIN) return null;
          const row = d.db.prepare("SELECT body FROM vault_grants WHERE ws = ? AND id = ?").get(h.request.ws, h.request.id) as { body: string } | undefined;
          if (row === undefined) return false;
          const stored = JSON.parse(row.body) as { request: Request; grant: Omit<Grant, "secret">; uses: number; until?: number };
          const { secret: _, ...grant } = h.grant;
          if (stored.uses !== 0 || (stored.until ?? stored.grant.exp) <= Math.floor(d.now() / 1000)
            || JSON.stringify(stored.request) !== JSON.stringify(h.request) || JSON.stringify(stored.grant) !== JSON.stringify(grant)) return false;
          const body = JSON.stringify({ ...stored, uses: 1 });
          return d.db.prepare("UPDATE vault_grants SET body = ? WHERE ws = ? AND id = ? AND body = ?")
            .run(body, h.request.ws, h.request.id, row.body).changes !== 0;
        },
        spendAgain: (h) => {
          const result = updateRepeated(h);
          if (result === false || result === null) return result;
          h.uses = result.uses - 1;
          if (result.until === undefined) delete h.until;
          else h.until = result.until;
          return true;
        },
        renew: (h, until) => {
          const result = updateRepeated(h, until);
          if (result === false || result === null) return result;
          h.uses = result.uses;
          return result.until!;
        },
        expire: (h, now) => {
          if (h.request.vault !== PLAIN) return null;
          const row = d.db.prepare("SELECT body FROM vault_grants WHERE ws = ? AND id = ?").get(h.request.ws, h.request.id) as { body: string } | undefined;
          if (row === undefined) return false;
          const stored = JSON.parse(row.body) as { request: Request; grant: Omit<Grant, "secret">; until?: number };
          const { secret: _, ...grant } = h.grant;
          if (JSON.stringify(stored.request) !== JSON.stringify(h.request) || JSON.stringify(stored.grant) !== JSON.stringify(grant)
            || (stored.until ?? stored.grant.exp) > now) return false;
          return Number(d.db.prepare("DELETE FROM vault_grants WHERE ws = ? AND id = ? AND body = ?")
            .run(h.request.ws, h.request.id, row.body).changes) !== 0;
        },
        forget: (h) => {
          if (h.request.vault === PLAIN) d.db.prepare("DELETE FROM vault_grants WHERE ws = ? AND id = ?").run(h.request.ws, h.request.id);
        },
      },
    });
    this.plain = d.plain;
    this.proxy = d.proxy ?? new Proxy(`${d.data}/vault`, d.now);
    this.#runs = new Incoming({ proxy: this.proxy, now: d.now, ...(d.workOf ? { workOf: d.workOf } : {}), ...(d.ask ? { ask: d.ask } : {}) });
    this.#restore(ended);
    d.hub.store.subscribe((c) => {
      if ((c.type === "sessionRemoved" || c.type === "session") && ended(c.key)) {
        for (const [id, away] of this.#away) if (away.session === c.key && away.workspace) void this.#d.ask?.(away.station, { method: "vault.revoke", workspace: away.workspace, id }).catch(() => {});
        if (this.keeper.holds(c.key)) this.keeper.end(c.key);
      }
    });
  }

  /// The plain library's grants written down before a restart, held again: those not run out, whose chat goes on and
  /// whose item is still given as granted, its value read again from the store.
  #restore(ended: (session: string) => boolean) {
    const rows = this.#d.db.prepare("SELECT ws, id, body FROM vault_grants").all() as RestoreRow[];
    const expired: ExpiredGrant[] = [];
    const restore = ({ row, saved, now }: ExpiredGrant, useNow = true) => {
      if (!this.#restoreRow(row, ended, saved, useNow ? now : undefined))
        this.#restorePending.set(JSON.stringify([row.ws, row.id]), { ws: row.ws, id: row.id });
    };
    const flush = () => {
      if (expired.length === 0) return;
      const batch = expired.splice(0);
      if (batch.length === 1) { restore(batch[0]!); return; }
      // The old process may have renewed a row since the list was read. Delete only the exact bodies we saw, and
      // recover any that changed using the same retry path as an individual grant.
      this.#restoreRemove ??= this.#d.db.prepare("DELETE FROM vault_grants WHERE ws = ? AND id = ? AND body = ?");
      const pending: ExpiredGrant[] = [];
      const priority = this.#d.backfill?.priority;
      foreground(priority === undefined ? null : new Int32Array(priority), () => {
        this.#d.db.exec("SAVEPOINT vault_restore_expired");
        try {
          for (const entry of batch) {
            const { row } = entry;
            if (Number(this.#restoreRemove!.run(row.ws, row.id, row.body).changes) === 0) pending.push(entry);
          }
          this.#d.db.exec("RELEASE vault_restore_expired");
        } catch (error) {
          try { this.#d.db.exec("ROLLBACK TO vault_restore_expired; RELEASE vault_restore_expired"); } catch {}
          throw error;
        }
      });
      for (const entry of pending) restore(entry, false);
    };
    for (const original of rows) {
      let saved: SavedGrant, now: number, due: boolean;
      try {
        now = Math.floor(this.#d.now() / 1000);
        saved = JSON.parse(original.body) as SavedGrant;
        due = (saved.until ?? saved.grant.exp) <= now;
      } catch (error) { flush(); throw error; }
      const entry = { row: original, saved, now };
      if (due) {
        expired.push(entry);
        if (expired.length === EXPIRED_GRANT_BATCH) flush();
      } else {
        const waiting = expired.length !== 0;
        flush();
        restore(entry, !waiting);
      }
    }
    flush();
    this.#resumeRestore(ended);
  }

  #restoreRow(original: RestoreRow, ended: (session: string) => boolean, first?: SavedGrant, firstNow?: number): boolean {
    let row: typeof original | undefined = original;
    // A previous station can renew or use a grant while this station is starting. Do not delete its newer version.
    for (let attempt = 0; row !== undefined && attempt < 3; attempt++) {
      const now = attempt === 0 && firstNow !== undefined ? firstNow : Math.floor(this.#d.now() / 1000);
      const { request, grant, uses, until } = attempt === 0 && first !== undefined ? first : JSON.parse(row.body) as SavedGrant;
      let checked: { body: string | null; owner: string; limit: { lasts: Scope; at: number } | null | undefined } | undefined;
      if ((until ?? grant.exp) > now && !ended(request.session) && this.#d.lock(row.ws) === null) {
        const snapshot = this.#d.plain.itemSnapshot(row.ws, request.item);
        const item = snapshot?.value ?? null;
        const l = item?.listing;
        const secret = item ? { kind: item.kind, name: item.name, fields: item.fields } : null;
        const limit = item && l?.lasts === undefined ? this.#d.plain.lasts(row.ws, item.owner) : undefined;
        checked = { body: snapshot?.body ?? null, owner: item?.owner ?? "", limit };
        const still = l !== undefined && !item!.deleted && l.modes.includes(grant.mode)
          && allows(l.lasts ?? limit?.lasts, grant.scope)
          && grant.hosts.every((h) => l.hosts.includes(h) || (!h.startsWith("*.") && hostAllowed(h, l.hosts))) && secret !== null && valueOf(secret) !== null;
        if (still) {
          // The initial list and the item's read may have raced with a deletion, renewal, or item change.
          // Check all three rows in one SQLite snapshot before accepting the saved grant.
          this.#restoreConfirm ??= this.#d.db.prepare(`SELECT g.body, p.body AS item_body, l.lasts, l.at
            FROM vault_grants g LEFT JOIN vault_plain p ON p.ws = g.ws AND p.id = ?
            LEFT JOIN vault_plain_lasts l ON l.ws = g.ws AND l.owner = ?
            WHERE g.ws = ? AND g.id = ?`);
          const current = this.#restoreConfirm.get(request.item, checked.owner, row.ws, row.id) as
            { body: string; item_body: string | null; lasts: Scope | null; at: number | null } | undefined;
          if (current === undefined) return true;
          if (current.body !== row.body || current.item_body !== checked.body
            || (limit !== undefined && (current.lasts !== (limit?.lasts ?? null) || current.at !== (limit?.at ?? null)))
            || (until ?? grant.exp) <= Math.floor(this.#d.now() / 1000) || ended(request.session) || this.#d.lock(row.ws) !== null) {
            row = { ...row, body: current.body };
            continue;
          }
          this.keeper.restore({ request, grant: { ...grant, secret: "" } as Grant, secret: secret!, uses, ...(until === undefined ? {} : { until }) });
          return true;
        }
      }
      let removed: number | bigint;
      if (checked === undefined) {
        this.#restoreRemove ??= this.#d.db.prepare("DELETE FROM vault_grants WHERE ws = ? AND id = ? AND body = ?");
        removed = this.#restoreRemove.run(row.ws, row.id, row.body).changes;
      } else {
        this.#restoreRemoveItem ??= this.#d.db.prepare(`DELETE FROM vault_grants WHERE ws = ? AND id = ? AND body = ?
          AND (SELECT body FROM vault_plain WHERE ws = ? AND id = ?) IS ?
          AND (? = 0 OR ((SELECT lasts FROM vault_plain_lasts WHERE ws = ? AND owner = ?) IS ?
            AND (SELECT at FROM vault_plain_lasts WHERE ws = ? AND owner = ?) IS ?))`);
        removed = this.#restoreRemoveItem.run(row.ws, row.id, row.body, row.ws, request.item, checked.body,
          checked.limit === undefined ? 0 : 1, row.ws, checked.owner, checked.limit?.lasts ?? null, row.ws, checked.owner, checked.limit?.at ?? null).changes;
      }
      if (Number(removed) !== 0) return true;
      this.#restoreRead ??= this.#d.db.prepare("SELECT ws, id, body FROM vault_grants WHERE ws = ? AND id = ?");
      row = this.#restoreRead.get(row.ws, row.id) as typeof original | undefined;
    }
    return row === undefined;
  }

  #resumeRestore(ended: (session: string) => boolean) {
    if (this.#restoreClosed || this.#restoreWaiting || this.#restorePending.size === 0) return;
    this.#restoreWaiting = true;
    void (this.#d.backfill?.previousGone ?? Promise.resolve()).then(() => {
      this.#restoreWaiting = false;
      if (!this.#restoreClosed) this.#retryRestore(ended);
    }, (error) => {
      this.#restoreWaiting = false;
      log.warn("vault", "the previous station did not finish for grant recovery", { error: (error as Error).message });
    });
  }

  #retryRestore(ended: (session: string) => boolean) {
    if (this.#restoreClosed) return;
    const first = this.#restorePending.entries().next().value;
    if (first === undefined) return;
    const [key, target] = first;
    this.#restorePending.delete(key);
    let delayed = false;
    try {
      if (!this.keeper.hasGrant(target.id)) {
        this.#restoreRead ??= this.#d.db.prepare("SELECT ws, id, body FROM vault_grants WHERE ws = ? AND id = ?");
        const row = this.#restoreRead.get(target.ws, target.id) as { ws: string; id: string; body: string } | undefined;
        if (row !== undefined && !this.#restoreRow(row, ended)) delayed = true;
      }
    } catch (error) {
      delayed = true;
      log.warn("vault", "a grant could not be recovered after handover", { error: (error as Error).message });
    }
    if (delayed) this.#restorePending.set(key, target);
    if (this.#restorePending.size > 0) {
      this.#restoreFibers ??= new Fibers("vault grant recovery");
      this.#restoreFibers.after(delayed ? 250 : 0, () => this.#retryRestore(ended));
    }
  }

  async close(): Promise<void> {
    this.#restoreClosed = true;
    this.#restorePending.clear();
    this.#reboxPending.clear();
    await Promise.all([this.#uses.close(), this.#restoreFibers?.close(), this.#reboxFibers?.close()]);
  }

  #scopeSave(id: string, ws: string, owner: string) {
    const scopes = this.#saveScopes.get(id) ?? [];
    if (scopes.some((s) => s.ws === ws && s.owner === owner)) return;
    scopes.push({ ws, owner });
    this.#saveScopes.set(id, scopes);
    const owners = this.#savesByOwner.get(ws) ?? new Map<string, Set<string>>();
    const requests = owners.get(owner) ?? new Set<string>();
    requests.add(id);
    owners.set(owner, requests);
    this.#savesByOwner.set(ws, owners);
  }

  #markLost(ws: string, id: string, lost: boolean) {
    const state = this.#lostSaves.get(ws);
    if (state === undefined) return;
    if (lost) {
      state.ids.add(id);
      const scopes = this.#lostScopes.get(id) ?? new Set<string>();
      scopes.add(ws);
      this.#lostScopes.set(id, scopes);
    } else {
      state.ids.delete(id);
      const scopes = this.#lostScopes.get(id);
      scopes?.delete(ws);
      if (scopes?.size === 0) this.#lostScopes.delete(id);
    }
  }

  #trackPending(ws: string, id: string, r: Request, pending: boolean) {
    if (pending && this.#unsaved.has(r.id) && this.#needsHeld(r)
      && !(this.#saveScopes.get(r.id) ?? []).some((scope) => scope.ws === ws)) {
      const scopes = this.#heldLostScopes.get(r.id) ?? new Set<string>();
      scopes.add(ws);
      this.#heldLostScopes.set(r.id, scopes);
    } else {
      const scopes = this.#heldLostScopes.get(r.id);
      scopes?.delete(ws);
      if (scopes?.size === 0) this.#heldLostScopes.delete(r.id);
    }
    this.#markLost(ws, id, pending && !this.#recoverable(r));
  }

  #forgetSave(id: string, settledWs?: string) {
    const recheck = new Set((this.#saveScopes.get(id) ?? []).map((s) => s.ws));
    for (const ws of this.#heldLostScopes.get(id) ?? []) recheck.add(ws);
    this.#unsaved.delete(id);
    for (const ws of recheck) {
      if (!this.#lostSaves.has(ws)) continue;
      const kept = ws === settledWs ? null : this.#kept(ws, id);
      this.#markLost(ws, id, kept?.request.status === "pending" && !this.#recoverable(kept.request));
    }
    this.#heldLostScopes.delete(id);
    this.#unscopedSaves.delete(id);
    this.#carriedSaves.delete(id);
    for (const { ws, owner } of this.#saveScopes.get(id) ?? []) {
      const owners = this.#savesByOwner.get(ws);
      const requests = owners?.get(owner);
      requests?.delete(id);
      if (requests?.size === 0) owners!.delete(owner);
      if (owners?.size === 0) this.#savesByOwner.delete(ws);
    }
    this.#saveScopes.delete(id);
  }

  /// What this process holds only in memory, for the next one (a handover).
  carried(): SecretsCarried {
    return { keeper: this.keeper.carried(), unsaved: [...this.#unsaved].map(([id, fields]): SecretsCarried["unsaved"][number] => {
      const scopes = this.#saveScopes.get(id);
      return scopes ? [id, fields, scopes.map((s) => ({ ...s }))] : [id, fields];
    }) };
  }

  /// What the process before this one held (`carried`), held here too.
  carry(c: SecretsCarried) {
    this.keeper.carry(c.keeper);
    for (const [id, fields, scopes] of c.unsaved ?? []) {
      if (this.#unsaved.has(id)) continue;
      this.#unsaved.set(id, fields);
      const wasLost = this.#lostScopes.get(id);
      if (wasLost !== undefined) {
        const carried = this.#heldLostScopes.get(id) ?? new Set<string>();
        for (const ws of [...wasLost]) { carried.add(ws); this.#markLost(ws, id, false); }
        this.#heldLostScopes.set(id, carried);
      }
      for (const scope of scopes ?? []) if (typeof scope.ws === "string" && typeof scope.owner === "string") this.#scopeSave(id, scope.ws, scope.owner);
      if (!this.#saveScopes.has(id)) this.#unscopedSaves.add(id);
      this.#carriedSaves.add(id);
    }
    if (this.#carriedSaves.size > 0) this.#waitForCarriedSaves();
  }

  /// Once the old process cannot write any more, reconcile each waiting save with its owner's current certificates.
  /// A device may have registered before the carry arrived, and a request may not have been written at that point.
  #waitForCarriedSaves() {
    if (this.#carriedSavesWaiting) return;
    this.#carriedSavesWaiting = true;
    const previous = this.#d.backfill?.previousGone ?? Promise.resolve();
    void previous.then(() => {
      this.#carriedSavesWaiting = false;
      if (this.#restoreClosed) return;
      // Older handovers did not carry a workspace or owner; one compatibility scan recovers those scopes.
      if (this.#unscopedSaves.size > 0) {
        const rows = this.#pendingForRecovery();
        for (const { ws, id } of rows) {
          if (!this.#unscopedSaves.has(id)) continue;
          const request = this.#kept(ws, id)?.request;
          if (request?.save && request.owner !== undefined) this.#scopeSave(id, ws, request.owner);
        }
      }
      // Match the order of the original device publication, even if the handover lists requests in another order.
      for (const id of [...this.#carriedSaves].sort()) {
        if (!this.#carriedSaves.delete(id)) continue;
        this.#unscopedSaves.delete(id);
        try {
          this.#reconcileCarriedSave(id);
        } catch (error) {
          log.warn("vault", "a carried save could not be taken up", { error: (error as Error).message });
        }
      }
    }).catch((error) => {
      this.#carriedSavesWaiting = false;
      log.warn("vault", "carried saves could not be taken up", { error: (error as Error).message });
    });
  }

  #sealCurrentSave(request: Request): boolean {
    if (request.owner === undefined) return false;
    const lock = this.#d.lock(request.ws);
    if (lock === null || lock.ws !== request.ws) return false;
    const certs = membersWithEmail(lock, request.owner).flatMap(({ sub }) => this.#certsOf(lock, sub).map((cert) => ({ cert, sub })));
    certs.sort((a, b) => a.cert.device < b.cert.device ? -1 : a.cert.device > b.cert.device ? 1 : 0);
    let changed = false;
    for (const { cert, sub } of certs) changed = this.#sealSave(request, lock, cert, sub, request.owner) || changed;
    return changed;
  }

  #reconcileCarriedSave(id: string) {
    let found = false;
    for (const { ws, owner } of this.#saveScopes.get(id) ?? []) {
      const kept = this.#kept(ws, id);
      if (kept?.request.status !== "pending" || !kept.request.save || kept.request.owner !== owner) continue;
      found = true;
      if (this.#sealCurrentSave(kept.request)) {
        this.#save(kept);
        this.#told(kept.request);
      }
    }
    if (!found && !this.#postingSaves.has(id)) {
      this.#forgetSave(id);
      this.keeper.discardBox(id);
    }
  }

  /// Requests to recover, in the old query's rowid order. While an old database is being indexed, retain its original
  /// scan so recovery is available immediately, including while the earlier process can still write.
  #pendingForRecovery(): { ws: string; id: string }[] {
    const sql = reboxIndexComplete(this.#d.db) ? REBOX_READY : REBOX_LEGACY;
    return this.#d.db.prepare(sql).all() as { ws: string; id: string }[];
  }

  /// Nothing more comes from the process before (it handed over, or there was none: a restart): each request still
  /// waiting whose box is not here gets a new one, told to its deciders, so that it may still be granted (the box holds
  /// no secret: only what is sealed to it once granted).
  reboxed() {
    const rows = this.#pendingForRecovery();
    const resolved = new Set<string>();
    for (const { ws, id } of rows) {
      const k = this.#kept(ws, id)!;
      if (this.#unsaved.has(id) && k.request.save && k.request.owner !== undefined) {
        this.#scopeSave(id, ws, k.request.owner);
        resolved.add(id);
      }
      if (k.request.box === "" || this.keeper.waiting(id)) continue;
      k.request.box = this.keeper.open(id);
      this.#save(k);
      this.#told(k.request);
    }
    for (const id of resolved) this.#unscopedSaves.delete(id);
  }

  /// Tells `f` of each request made or decided (the members' event streams).
  listen(f: (r: Request) => void) {
    this.#listeners.push(f);
  }

  /// Tells `f` of each item of the plain library this writes itself (`renewed`).
  onPlainWritten(f: (i: PlainItem) => void) {
    this.#plainWritten = f;
  }

  #told(r: Request) {
    for (const f of this.#listeners) f(r);
  }

  #kept(ws: string, id: string): Kept | null {
    const row = this.#d.db.prepare("SELECT body, thread, card_ts FROM vault_requests WHERE ws = ? AND id = ?").get(ws, id) as any;
    return row ? { request: JSON.parse(row.body), thread: row.thread ?? null, cardTs: row.card_ts ?? null, raw: row.body } : null;
  }

  #write(k: Kept) {
    const r = k.request;
    this.#d.db
      .prepare("INSERT INTO vault_requests (ws, id, session, status, body, thread, card_ts) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET status = excluded.status, body = excluded.body, thread = excluded.thread, card_ts = excluded.card_ts")
      .run(r.ws, r.id, r.session, r.status, JSON.stringify(r), k.thread, k.cardTs);
  }

  #trackSaved(k: Kept) {
    const r = k.request;
    const lost = this.#lostSaves.get(r.ws);
    if (lost !== undefined) this.#trackPending(r.ws, r.id, r, r.status === "pending");
  }

  #save(k: Kept) { this.#write(k); this.#trackSaved(k); }

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
    return this.#d.hub.store.starter(session);
  }

  /// The person a request is for: `person` (an email) when the agent names one, someone who wrote in this chat (a
  /// chat started in Slack has its people there, but they can write in it from the still.fail app too); else whoever
  /// started it.
  #personFor(session: string, person: string | undefined): string | null {
    const starter = this.#starter(session);
    const named = person?.trim().toLowerCase() ?? "";
    if (named === "" || named === starter) return starter;
    const people = (this.#d.hub.store.participants(session).get(session) ?? []).filter((p) => p.includes("@") && !p.includes(":"));
    if (people.includes(named)) return named;
    const who = people.length > 0 ? `the people who wrote in it from still.fail: ${people.join(", ")}` : "no one has written in it from still.fail yet: ask them to write in this chat in the still.fail app, then name them";
    throw new Refused(`${person} has not written in this chat: name one of ${who}; or leave person out for whoever started it.`);
  }

  /// A ready answer, or undefined while the existing worker prepares an old multi-chat session.
  #latestThreadReady(session: string): SessionThread | null | undefined {
    return this.#d.hub.prepareLatestThreads
      ? this.#d.hub.store.latestThreadIfReady(session)
      : this.#d.hub.store.latestThread(session);
  }

  /// The items a session may ask for: those with a listing of whoever started its chat, in their vaults (security
  /// mode on) or their plain library (off).
  listings(session: string, person?: string): Listed[] {
    const { ws, lock } = this.#placeOf(session);
    const email = this.#personFor(session, person);
    if (email === null) return [];
    return this.#listingsAt(ws, lock, email);
  }

  #plainListings(items: PlainItem[]): Listed[] {
    return items.flatMap((i) => (!i.deleted && i.listing ? [{ vault: PLAIN, item: i.id, owner: i.owner, listing: i.listing }] : []));
  }

  #vaultListings(lock: LockState, vault: Vault, items: Item[]): Listed[] {
    return items.flatMap((item) => !item.deleted && item.listing !== undefined && item.epoch === vault.epoch
      ? [{ vault: vault.id, item: item.id, owner: lock.members.get(vault.owner)?.email ?? null, listing: item.listing }] : []);
  }

  #listingsAt(ws: string, lock: LockState | null, email: string): Listed[] {
    if (lock === null) {
      return this.#plainListings(this.#d.plain.items(ws, email));
    }
    const sub = memberWithEmail(lock, email)?.sub;
    if (sub === undefined) return [];
    return this.#d.vaults
      .vaults(lock.ws)
      .filter((v) => v.members.includes(sub))
      .flatMap((vault) => this.#vaultListings(lock, vault, this.#d.vaults.items(lock.ws, vault.id)));
  }

  /// A use needs only the first matching listing. Names can equal another item's id, so retain the list's order.
  #findListing(session: string, wanted: string, person: string | undefined): Listed | undefined {
    const { ws, lock } = this.#placeOf(session);
    const email = this.#personFor(session, person);
    if (email === null) return undefined;
    const matches = (l: Listed) => l.item.toLowerCase() === wanted || l.listing.name.toLowerCase() === wanted;
    // Keep the prefix and any remaining reads in one snapshot: another connection may change an earlier item between them.
    this.#d.db.exec("SAVEPOINT vault_find_listing");
    try {
      if (lock === null) {
        const prefix = this.#d.plain.firstItems(ws, email, LISTING_PREFIX);
        const found = this.#plainListings(prefix.map((entry) => entry.value)).find(matches);
        if (found !== undefined || prefix.length < LISTING_PREFIX) return found;
        return this.#plainListings(this.#d.plain.itemsAfter(ws, email, prefix.at(-1)!.id)).find(matches);
      }
      const sub = memberWithEmail(lock, email)?.sub;
      if (sub === undefined) return undefined;
      const inVault = (vault: Vault, short: boolean): Listed | undefined => {
        if (!vault.members.includes(sub)) return undefined;
        const listings = (items: Item[]) => this.#vaultListings(lock, vault, items);
        // After the short vault prefix, use the original full item read: a miss across many vaults should not pay a
        // prefix probe for every vault.
        if (!short) return listings(this.#d.vaults.items(lock.ws, vault.id)).find(matches);
        const prefix = this.#d.vaults.firstItems(lock.ws, vault.id, LISTING_PREFIX);
        const found = listings(prefix.map((entry) => entry.value)).find(matches);
        if (found !== undefined || prefix.length < LISTING_PREFIX) return found;
        return listings(this.#d.vaults.itemsAfter(lock.ws, vault.id, prefix.at(-1)!.id)).find(matches);
      };
      const prefix = this.#d.vaults.firstVaults(lock.ws, LISTING_PREFIX);
      for (const entry of prefix) {
        const found = inVault(entry.value, true);
        if (found !== undefined) return found;
      }
      if (prefix.length < LISTING_PREFIX) return undefined;
      for (const vault of this.#d.vaults.vaultsAfter(lock.ws, prefix.at(-1)!.id)) {
        const found = inVault(vault, false);
        if (found !== undefined) return found;
      }
      return undefined;
    } finally { this.#d.db.exec("RELEASE vault_find_listing"); }
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

  /// Fill this workspace's old pending lookup before its request list is read.
  async preparePending(ws: string, members = this.#d.lock(ws) !== null): Promise<void> {
    // Do not make a request wait for an earlier process that is still running: the original query remains available.
    if (!this.#previousExited) return;
    // An older pending index can be used for the full pending scan immediately while its decision fields are
    // checked in the worker. Fresh indexes perform this check with their first backfill instead.
    if (pendingIndexStarted(this.#d.db, ws) && !pendingAuditComplete(this.#d.db, ws) && !this.#pendingAudits.has(ws)) {
      const audit = this.#uses.preparePending(ws, false, true);
      this.#pendingAudits.set(ws, audit);
      void audit.then(() => { this.#pendingAudits.delete(ws); }, (error) => {
        this.#pendingAudits.delete(ws);
        if (!this.#restoreClosed) log.warn("vault", "the pending index audit could not finish", { error: (error as Error).message });
      });
    }
    // An index begun by an older station may need a second bounded audit. Keep its list available via the original
    // scan while that happens, and share the audit between concurrent readers.
    if (members && hasVaultMembers(this.#d.db) && vaultMembersStarted(this.#d.db, ws) && !vaultMembersComplete(this.#d.db, ws)) {
      if (!this.#memberAudits.has(ws)) {
        const audit = this.#uses.preparePending(ws, true);
        this.#memberAudits.set(ws, audit);
        void audit.then(() => { this.#memberAudits.delete(ws); }, (error) => {
          this.#memberAudits.delete(ws);
          if (!this.#restoreClosed) log.warn("vault", "the member index audit could not finish", { error: (error as Error).message });
        });
      }
      await this.#uses.preparePending(ws, false);
    } else await this.#uses.preparePending(ws, members);
    if (this.#lostSaves.get(ws)?.ready === true) return;
    const already = this.#preparingPending.get(ws);
    if (already !== undefined) return already;
    const prepare = (async () => {
      // Once the earlier process has exited, writes to requests are made here and update this set in #save.
      const state = { ids: new Set<string>(), ready: false };
      this.#lostSaves.set(ws, state);
      try {
        let after: string | null = null;
        for (;;) {
          const rows = (after === null ? this.#d.db.prepare(PENDING_SEED_FIRST).all(ws, 32)
            : this.#d.db.prepare(PENDING_SEED).all(ws, after, 32)) as { id: string; body: string }[];
          for (const row of rows) {
            const request = JSON.parse(row.body) as Request;
            this.#trackPending(ws, row.id, request, true);
          }
          if (rows.length < 32) break;
          after = rows.at(-1)!.id;
          await new Promise<void>((resolve) => setImmediate(resolve));
        }
        state.ready = true;
      } catch (error) {
        if (this.#lostSaves.get(ws) === state) {
          for (const id of state.ids) this.#markLost(ws, id, false);
          this.#lostSaves.delete(ws);
        }
        throw error;
      }
    })();
    this.#preparingPending.set(ws, prepare);
    try { await prepare; }
    finally { if (this.#preparingPending.get(ws) === prepare) this.#preparingPending.delete(ws); }
  }

  /// The requests `viewer` may decide in workspace `ws`, still waiting.
  pending(ws: string, lock: LockState | null, viewer: { sub: string; email: string }): Request[] {
    const now = Math.floor(this.#d.now() / 1000);
    const lost = this.#lostSaves.get(ws);
    let rows: { body: string }[];
    // The readiness and anomaly checks must describe the same snapshot as the indexed candidates. A writer on
    // another connection can change a vault, its markers and its lookup between any two statements.
    this.#d.db.exec("SAVEPOINT vault_pending_read");
    try {
      // JSON-extracted SQL text and a bound JavaScript string do not compare alike for isolated surrogate code units.
      const ready = viewer.email.isWellFormed() && (lock === null || viewer.sub.isWellFormed())
        && lost?.ready === true && pendingIndexComplete(this.#d.db, ws) && pendingAuditComplete(this.#d.db, ws)
        && (lock === null || (lock.ws === ws && hasVaultMembers(this.#d.db) && vaultMembersComplete(this.#d.db, ws) && !hasInvalidVaultMembers(this.#d.db, ws)));
      if (!ready) {
        const sql = pendingIndexComplete(this.#d.db, ws) ? PENDING_BODIES : "SELECT body FROM vault_requests WHERE ws = ? AND status = 'pending'";
        rows = this.#d.db.prepare(sql).all(ws) as { body: string }[];
      } else {
        const selected = new Map<string, string>();
        const add = (found: unknown[]) => { for (const row of found as { id: string; body: string }[]) selected.set(row.id, row.body); };
        add(this.#d.db.prepare(PENDING_OWN).all(ws, viewer.email.toLowerCase()));
        if (lock !== null) add(this.#d.db.prepare(PENDING_MEMBER).all(ws, viewer.sub));
        add(this.#d.db.prepare(PENDING_DUE).all(ws, now - PENDING_SECS));
        add(this.#d.db.prepare(PENDING_NO_TIME).all(ws));
        add(this.#d.db.prepare(PENDING_OTHER_TIME).all(ws));
        add(this.#d.db.prepare(PENDING_DUPLICATES).all(ws));
        add(this.#d.db.prepare(PENDING_NUL_FIELDS).all(ws));
        if (this.#d.coming?.() !== true) for (const id of lost!.ids) {
          const kept = this.#kept(ws, id);
          if (kept?.request.status === "pending") selected.set(id, JSON.stringify(kept.request));
          else this.#markLost(ws, id, false);
        }
        rows = [...selected].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([, body]) => ({ body }));
      }
    } finally { this.#d.db.exec("RELEASE vault_pending_read"); }
    const vaultDecisions = new Map<string, boolean>();
    return rows
      .map((r) => JSON.parse(r.body) as Request)
      .flatMap((r) => {
        // A secret to keep that is gone with a restart (the plain library's) and sealed to no device can never be kept:
        // let go; one the person types in is held nowhere until then. A request to use one lives on (`reboxed`).
        if (this.#requestLive(r, now)) return [r];
        if (this.#settle(r, "expired")) return [];
        // Another connection may have changed the request before its expiration could be recorded.
        const current = this.#kept(r.ws, r.id)?.request;
        return current?.status === "pending" && this.#requestLive(current, now) ? [current] : [];
      })
      .filter((r) => {
        if (r.vault === PLAIN || r.save || lock === null) return this.#decides(r, viewer, lock);
        const checked = vaultDecisions.get(r.vault);
        if (checked !== undefined) return checked;
        const mayDecide = this.#decides(r, viewer, lock);
        vaultDecisions.set(r.vault, mayDecide);
        return mayDecide;
      });
  }

  #requestLive(r: Request, now: number): boolean {
    const live = this.#d.coming?.() === true || this.#recoverable(r);
    return r.at + PENDING_SECS > now && live;
  }

  #recoverable(r: Request): boolean {
    return !this.#needsHeld(r) || this.#unsaved.has(r.id);
  }

  #needsHeld(r: Request): boolean {
    return !!r.save && r.save.typed !== true && !(r.vault !== PLAIN && (r.sealed?.length ?? 0) > 0);
  }

  /// The uses of a vault's (or the plain library's) secrets `viewer` may see, the latest first: the requests decided.
  async uses(ws: string, lock: LockState | null, vault: string, viewer: { sub: string; email: string }, limit = 500): Promise<Use[]> {
    if (vault !== PLAIN && (lock === null || this.#d.vaults.vault(ws, vault)?.members.includes(viewer.sub) !== true)) return [];
    const bodies = await this.#uses.read(ws, vault, vault === PLAIN ? viewer.email.toLowerCase() : null, limit);
    // A large old database may still have been filling its index: access can change while that read waits.
    if (vault !== PLAIN && (this.#d.lock(ws) === null || this.#d.vaults.vault(ws, vault)?.members.includes(viewer.sub) !== true)) return [];
    // SQLite's JSON paths may select a different field than JSON.parse when an old body has duplicate keys or a
    // NUL in a key. Never expose a use whose parsed vault or plain-library owner differs from the authorized scope.
    const email = viewer.email.toLowerCase();
    const requests = bodies.map((body) => JSON.parse(body) as Request)
      .filter((r) => r.vault === vault && (vault !== PLAIN || r.owner === email) && r.save == null && r.describe == null && r.remove == null);
    const names = new Map<string, string | null>();
    const prepare = this.#d.hub.prepareLatestThreads;
    const titleIfReady = this.#d.titleIfReady;
    if (titleIfReady && prepare) {
      const sessions = new Set(requests.map((r) => r.session));
      for (;;) {
        // The vault may have changed while the worker prepared old sessions.
        if (vault !== PLAIN && (this.#d.lock(ws) === null || this.#d.vaults.vault(ws, vault)?.members.includes(viewer.sub) !== true)) return [];
        const missing: string[] = [];
        names.clear();
        // Read readiness and the name in one snapshot. Release it before waiting for the worker.
        this.#d.db.exec("SAVEPOINT vault_use_titles");
        try {
          for (const session of sessions) {
            try {
              const name = titleIfReady(session);
              if (name === undefined) missing.push(session);
              else names.set(session, name);
            } catch {
              names.set(session, null);
            }
          }
        } finally {
          this.#d.db.exec("RELEASE vault_use_titles");
        }
        if (missing.length === 0) break;
        await prepare(missing);
      }
    } else {
      for (const session of new Set(requests.map((r) => r.session))) names.set(session, this.#title(session));
    }
    return requests.map((r) => ({ item: r.item, at: r.at, session: r.session, chatTitle: names.get(r.session) ?? null, mode: r.mode, command: r.command ?? null, hosts: r.hosts ?? [], denied: r.status === "denied" }));
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

  /// secret_use: a request for `itemName` (its id or listed name) from `session`, its card posted; decided, the session
  /// is told (#settle).
  async ask(session: string, a: { item: string; mode?: string; reason: string; command?: string; hosts?: string[]; station?: string; timeout?: { kind: "idle" | "fixed"; seconds: number }; person?: string }): Promise<string> {
    const { ws } = this.#placeOf(session);
    const runOn = a.station ? this.#peer(a.station) : null;
    const wanted = a.item.trim().toLowerCase();
    const found = this.#findListing(session, wanted, a.person);
    // Named, the card is theirs to decide (a member of the vault it is in); else the vault's owner's.
    const decider = a.person?.trim() ? this.#personFor(session, a.person) : found?.owner ?? null;
    if (found === undefined) throw new Refused(`No secret named ${JSON.stringify(a.item)} may be asked for here: secret_list lists those that may.`);
    const { listing } = found;
    const plain = found.vault === PLAIN;
    const mode = (a.mode ?? listing.modes[0]) as Mode;
    if (!listing.modes.includes(mode)) throw new Refused(`「${listing.name}」 is given only by ${listing.modes.join(", ")}.`);
    if (a.reason.trim() === "") throw new Refused("reason is required: why you need it, for the person deciding");
    if (a.timeout && (!["idle", "fixed"].includes(a.timeout.kind) || !Number.isSafeInteger(a.timeout.seconds) || a.timeout.seconds < 60 || a.timeout.seconds > 30 * 86400 || a.timeout.seconds % 60 !== 0)) throw new Refused("timeout must be idle or fixed, in whole minutes from 1 minute to 30 days");
    const hosts = a.hosts?.length ? a.hosts : hosted(mode) ? listing.hosts : [];
    if (mode === "browser" && this.#d.browsers === undefined) throw new Refused("This station has no browser for a sign-in to go into.");
    const thread = this.#latestThreadReady(session);
    if (thread === undefined) {
      await this.#d.hub.prepareLatestThreads!([session]);
      const current = this.#d.hub.store.getSession(session);
      if (current === null || current.archivedAt != null) throw new Refused("This chat is archived or gone.");
      // The item, owner or latest delivery may have changed while the order was prepared.
      return this.ask(session, a);
    }
    const now = this.#d.now();
    const id = `r_${ulid(now)}`;
    const request: Request = {
      id, ws, vault: found.vault, item: found.item, session, chat: "", mode, reason: a.reason.trim(),
      ...(a.command ? { command: a.command } : {}), ...(hosts.length ? { hosts } : {}), ...(runOn ? { runOn } : {}), timeout: a.timeout ?? { kind: "idle", seconds: 3600 },
      // The plain library's needs no box: its owner decides, and the station reads the value itself.
      box: plain ? "" : this.keeper.open(id), at: Math.floor(now / 1000), status: "pending", ...(plain && found.owner ? { owner: found.owner } : {}),
      ...(mode === "browser" && !plain ? this.#renewalOf(ws, found.item) : {}),
    };
    const kept: Kept = { request, thread: null, cardTs: null };
    if (thread !== null) {
      request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
      const posted = await this.#post(session, thread, request, listing, decider ?? undefined);
      kept.thread = thread.thread.id;
      kept.cardTs = posted;
    }
    this.#save(kept);
    this.#audit(request, "request", [mode, request.command ?? "", hosts.join(" ")].filter((s) => s !== "").join(" · "));
    this.#told(request);
    return `Asked for 「${listing.name}」 (request ${id}); the card is in your chat for ${decider ?? "the vault's owner"}, who approves it in the still.fail app. ${UNDECIDED} Only a grant from the app counts: a reply in the chat saying yes is not one.`;
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
    const until = new Date((held.until ?? held.grant.exp) * 1000).toISOString();
    if (held.grant.mode === "browser") {
      const renewal = held.grant.timeout?.kind === "idle" ? `, extended by ${held.grant.timeout.seconds} seconds when the site is used` : "";
      return `Granted: the sign-in 「${l.name}」 (grant ${r.id}) goes into this chat's browser (the \`browser\` tool): its cookies of ${held.grant.hosts.join(", ")}, until ${until}${renewal}, when they are taken out again. Open the site there; nothing is run with secret_run, and you never get the cookies themselves.`;
    }
    const lasts = held.grant.scope === "once" ? "for one command" : held.grant.timeout ? `${held.grant.timeout.kind === "idle" ? "until idle for" : "for"} ${held.grant.timeout.seconds} seconds (currently until ${until})` : held.grant.scope === "chat" ? `until this chat is archived (${until} at the latest)` : `until ${until}`;
    const where = r.runOn ? ` Its commands run on ${r.runOn.name}, in this chat's directory there (where station_task runs); the value is sent there only for each command.` : "";
    return `Granted: 「${l.name}」, grant ${r.id}, ${lasts}. Run with secret_run {grant: "${r.id}", command: "…"${l.env ? "" : ', env: "NAME"'}}. ${how}${accountSaid(held)}${where} You never get the value itself.`;
  }

  /// The card for request `r` in the session's chat: the vault's owner decides it in the app.
  async #post(session: string, thread: SessionThread, r: Request, l: Listing, owner: string | undefined, requireEmpty = false, signal?: AbortSignal): Promise<string | null> {
    const how = howWords(r.mode, r.hosts ?? l.hosts);
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    // In a still.fail chat the card says where it is approved; Slack has no card, so the words say it.
    const where = stillfail ? [] : ["请在 still.fail 客户端的「密钥」中批准。"];
    const text = [
      `申请使用「${l.name}」：${r.reason}`, ...(r.command ? [`命令：\`${r.command.replace(/`/g, "'")}\``] : []), `方式：${how}`,
      ...(r.runOn ? [`运行在：${r.runOn.name}`] : []), ...(r.timeout ? [`申请时限：${r.timeout.kind === "idle" ? "闲置" : "固定"} ${r.timeout.seconds / 60} 分钟`] : []), ...where,
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
          // The request as the app draws it; its outcome added once decided (#settle).
          vault: { request: r.id, name: l.name, reason: r.reason, ...(r.command ? { command: r.command } : {}), mode: r.mode, hosts: hosted(r.mode) ? (r.hosts ?? l.hosts) : [], ...(r.runOn ? { station: r.runOn.name } : {}), ...(r.timeout ? { timeout: r.timeout } : {}) },
        }
      : null;
    return this.#postCard(session, thread, text, card, requireEmpty, r, signal);
  }

  /// A request's post in the session's chat, with its card where the chat shows cards; the card's ts, if it has one.
  async #postCard(session: string, thread: SessionThread, text: string, card: Record<string, unknown> | null, requireEmpty = false, request?: Request, signal?: AbortSignal): Promise<string | null> {
    const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
    signal?.throwIfAborted();
    const posted = await this.#d.hub.chat(thread.connect).post(here, text, []);
    const needed = request ? () => {
      const current = this.#kept(request.ws, request.id)?.request;
      return current?.status === "pending" && this.#requestLive(current, Math.floor(this.#d.now() / 1000));
    } : undefined;
    // A non-card surface has already delivered the message; finish recording it even if the caller leaves.
    return recordPostedCard(this.#d.hub, session, thread, text, card, posted, requireEmpty ? (why) => new Refused(why) : null, needed, undefined, card === null ? undefined : signal);
  }

  /// Reissue the card for the very same pending request, without recapturing or revealing a secret. A message can end
  /// the card's wait without deciding the underlying request; a later, unrelated card must never be displaced here.
  async reask(session: string, id: string, signal?: AbortSignal): Promise<string> {
    signal?.throwIfAborted();
    const { ws } = this.#placeOf(session);
    const kept = this.#kept(ws, id);
    if (kept === null || kept.request.session !== session) throw new Refused("No such request in this chat.");
    const r = kept.request;
    if (r.status !== "pending") throw new Refused(`Request ${id} is no longer pending (${r.status}).`);
    if (!this.#requestLive(r, Math.floor(this.#d.now() / 1000))) {
      if (!this.#settle(r, "expired")) throw new Refused(`Request ${id} changed while it was checked; try again.`);
      throw new Refused(`Request ${id} is no longer pending (expired).`);
    }
    const place = cardPlace(this.#d.hub.store, session, kept.thread, kept.cardTs);
    if (place === undefined) {
      if (!this.#d.hub.prepareCardPosts || kept.thread == null) throw new Refused("card lookup is not ready");
      await this.#d.hub.prepareCardPosts([kept.thread], signal);
      signal?.throwIfAborted();
      return this.reask(session, id, signal);
    }
    if (place === null) throw new Refused("This request has no card in the chat to ask again.");
    if (place.state === "same") return `The card for request ${id} is already pending in the chat.`;
    if (place.state === "other") throw new Refused(CARD_OCCUPIED);
    const listing = r.save ? null : this.#listingOf(r);
    if (!r.save && !listing) throw new Refused("The secret is no longer available to request.");
    const posted = r.save
      ? await this.#postSave(session, place.thread, r, true, signal)
      : r.describe
        ? await this.#postDescribe(session, place.thread, r, this.#deciderOf(r), true, signal)
        : r.remove
          ? await this.#postRemove(session, place.thread, r, this.#deciderOf(r), true, signal)
          : await this.#post(session, place.thread, r, listing!, r.owner, true, signal);
    const current = this.#kept(ws, id);
    if (current?.request.status === "pending" && !this.#requestLive(current.request, Math.floor(this.#d.now() / 1000))) this.#settle(current.request, "expired");
    // The original request may have been decided while the new message was being posted.
    const latest = this.#kept(ws, id);
    if (latest === null || latest.request.status !== "pending") {
      if (posted !== null) this.#d.hub.store.withdrawCard(session, place.thread.thread.id, posted);
      throw new Refused(`Request ${id} is no longer pending.`);
    }
    if (!this.#requestLive(latest.request, Math.floor(this.#d.now() / 1000))) {
      if (posted !== null) this.#d.hub.store.withdrawCard(session, place.thread.thread.id, posted);
      throw new Refused(`Request ${id} changed while it was checked; try again.`);
    }
    try {
      // The decision and the card location can change on another connection after the last read above.
      const changed = this.#d.db.prepare(`UPDATE vault_requests SET thread=?,card_ts=?
        WHERE ws=? AND id=? AND status='pending' AND body=? AND thread IS ? AND card_ts IS ?`)
        .run(place.thread.thread.id, posted, ws, id, latest.raw!, latest.thread, latest.cardTs).changes;
      if (changed === 0) throw new Refused(`Request ${id} changed while the card was posted; try again.`);
      this.#trackSaved(latest);
    } catch (error) {
      if (posted !== null) this.#d.hub.store.withdrawCard(session, place.thread.thread.id, posted);
      throw error;
    }
    return `The card for request ${id} is in the chat again. It is the same request; no secret was read again. ${UNDECIDED}`;
  }

  // ── an item renamed, or said what it is (secret_describe 改名和说明) ──

  /// secret_describe: a request from `session` to give item `a.item` (its id or listed name) a new name or about, its card
  /// posted for the item's owner (or the person named). Granted, the item says so: a vault's written by the app that
  /// approves it (its device signs the item), the plain library's here (`describedPlain`). It grants nothing.
  async describe(session: string, a: { item: string; name?: string; about?: string; reason: string; person?: string }): Promise<string> {
    const { ws } = this.#placeOf(session);
    const found = this.#findListing(session, a.item.trim().toLowerCase(), a.person);
    if (found === undefined) throw new Refused(`No secret named ${JSON.stringify(a.item)} is listed here: secret_list lists those that are.`);
    const decider = a.person?.trim() ? this.#personFor(session, a.person) : found.owner;
    const { listing } = found;
    const was = { name: listing.name, about: listing.about ?? "" };
    const name = (a.name ?? was.name).trim();
    const about = (a.about ?? was.about).trim();
    if (name === "" || name.length > 200) throw new Refused("name is at most 200 characters, and not empty: what the person and agents will know it by");
    if (about.length > ABOUT_MOST) throw new Refused(`about is at most ${ABOUT_MOST} characters`);
    if (name === was.name && about === was.about) throw new Refused(`「${was.name}」 is named and described so already: nothing to change.`);
    if (a.reason.trim() === "") throw new Refused("reason is required: why, for the person deciding");
    const thread = this.#latestThreadReady(session);
    if (thread === undefined) {
      await this.#d.hub.prepareLatestThreads!([session]);
      const current = this.#d.hub.store.getSession(session);
      if (current === null || current.archivedAt != null) throw new Refused("This chat is archived or gone.");
      return this.describe(session, a);
    }
    const plain = found.vault === PLAIN;
    const now = this.#d.now();
    const id = `r_${ulid(now)}`;
    const request: Request = {
      id, ws, vault: found.vault, item: found.item, session, chat: "", mode: listing.modes[0]!, reason: a.reason.trim(),
      box: "", at: Math.floor(now / 1000), status: "pending", ...(plain && found.owner ? { owner: found.owner } : {}),
      describe: { name, about, was },
    };
    const kept: Kept = { request, thread: null, cardTs: null };
    if (thread !== null) {
      request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
      kept.cardTs = await this.#postDescribe(session, thread, request, decider ?? undefined);
      kept.thread = thread.thread.id;
    }
    this.#save(kept);
    this.#audit(request, "describe-request", name === was.name ? "about" : `name ${name}`);
    this.#told(request);
    return this.#saidDescribe(request) + (decider ? ` It is for ${decider} to decide.` : "");
  }

  /// Who decides request `r` as its card says: the plain library's item's owner, else its vault's owner.
  #deciderOf(r: Request): string | undefined {
    if (r.owner) return r.owner;
    const lock = this.#d.lock(r.ws);
    const vault = this.#d.vaults.vault(r.ws, r.vault);
    return lock !== null && vault !== null ? lock.members.get(vault.owner)?.email.toLowerCase() : undefined;
  }

  /// The card of a request to rename an item or say what it is: its name and about as they were and are to be.
  async #postDescribe(session: string, thread: SessionThread, r: Request, decider: string | undefined, requireEmpty = false, signal?: AbortSignal): Promise<string | null> {
    const d = r.describe!;
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const text = [
      `申请修改密钥「${d.was.name}」的${d.name !== d.was.name && d.about !== d.was.about ? "名称与说明" : d.name !== d.was.name ? "名称" : "说明"}：${r.reason}`,
      ...(d.name !== d.was.name ? [`名称改为：${d.name}`] : []),
      ...(d.about !== d.was.about ? [d.about === "" ? "清除说明" : `说明改为：${d.about}`] : []),
      ...(stillfail ? [] : ["请在 still.fail 客户端的「密钥」中批准。"]),
    ].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ ...DESCRIBE_WORDS.yes, recommended: true }, DESCRIBE_WORDS.no],
          ...(decider ? { assignee: decider.toLowerCase() } : {}),
          // The request as the app draws it: `describe` says it is one to rename; its outcome added once decided.
          vault: { request: r.id, name: d.was.name, reason: r.reason, mode: r.mode, hosts: [], describe: { name: d.name, about: d.about, wasAbout: d.was.about } },
        }
      : null;
    return this.#postCard(session, thread, text, card, requireEmpty, r, signal);
  }

  /// What an agent is told of a request to rename an item, waiting (secret_describe's answer) or decided (a notice).
  #saidDescribe(r: Request): string {
    const d = r.describe!;
    if (r.status === "granted") return `Changed: the item ${r.item} is 「${d.name}」 now${d.about ? `, described as: ${d.about}` : ", with no description"}.`;
    if (r.status === "denied") return `The person chose not to change 「${d.was.name}」 (request ${r.id}): it stays as it was.`;
    if (r.status === "expired") return `The request to change 「${d.was.name}」 (${r.id}) was let go.`;
    return `Asked to change 「${d.was.name}」 (request ${r.id}); the card is in your chat, approved in the still.fail app. ${UNDECIDED} Only their approval in the app changes it: a reply in the chat saying yes does not.`;
  }

  /// POST vault/described `{request}`: a request to rename an item of a vault, approved by a member of it whose app wrote
  /// the item's next version (and brought it here): taken once the item here says what was asked. Why not, or null.
  described(lock: LockState, sub: string, d: { request?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(lock.ws, d.request) : null;
    if (k === null || !k.request.describe || k.request.vault === PLAIN) return "no such request to rename an item of a vault";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const vault = this.#d.vaults.vault(lock.ws, k.request.vault);
    if (vault === null || !vault.members.includes(sub)) return "only the vault's members decide its requests";
    const item = this.#d.vaults.item(lock.ws, vault.id, k.request.item);
    const want = k.request.describe;
    if (item === null || item.deleted || item.listing?.name !== want.name || (item.listing.about ?? "") !== want.about) return "the item does not say so here: bring its copy first";
    if (!this.#settle(k.request, "granted")) return this.#decisionChanged(k.request);
    return null;
  }

  /// POST vault/plain/described `{request}`: a request to rename an item of the plain library, approved by its owner:
  /// its next version written here. The item as written, or why not.
  describedPlain(ws: string, lock: LockState | null, email: string, d: { request?: unknown }): PlainItem | string {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || !k.request.describe || k.request.vault !== PLAIN) return "no such request to rename an item of the plain library";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (lock !== null) return "security mode is on: the item is in the vault, changed by the app";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const snapshot = this.#d.plain.itemSnapshot(ws, k.request.item);
    const prev = snapshot?.value ?? null;
    if (prev === null || prev.deleted || prev.listing === undefined) return "the item is gone, or not one agents may ask for";
    const want = k.request.describe;
    const { about: _, ...listing } = prev.listing;
    const next: PlainItem = { ...prev, version: prev.version + 1, name: want.name, notes: want.about, listing: { ...listing, name: want.name, ...(want.about ? { about: want.about } : {}) }, at: Math.floor(this.#d.now() / 1000) };
    const why = plainOk(prev, next, prev.owner);
    if (why !== null) return why;
    try {
      const settled = this.#settle(k.request, "granted", undefined, undefined, () => {
        if (this.#d.db.prepare("SELECT 1 FROM vault_plain WHERE ws=? AND id=? AND body=?").get(ws, prev.id, snapshot!.body) === undefined) throw new Refused("the item changed; try again");
        this.#d.plain.put(next);
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    return this.#d.plain.item(ws, next.id)!;
  }

  // ── an item deleted (secret_delete 删除) ──

  /// secret_delete: a request from `session` to delete item `a.item` (its id or listed name), its card posted for the
  /// item's owner (or the person named). Granted, the item is gone: a vault's deleted by the app that approves it (its
  /// device signs the deleted version), the plain library's here (`removedPlain`). It grants nothing.
  async remove(session: string, a: { item: string; reason: string; person?: string }): Promise<string> {
    const { ws } = this.#placeOf(session);
    const found = this.#findListing(session, a.item.trim().toLowerCase(), a.person);
    if (found === undefined) throw new Refused(`No secret named ${JSON.stringify(a.item)} is listed here: secret_list lists those that are.`);
    if (a.reason.trim() === "") throw new Refused("reason is required: why, for the person deciding");
    const decider = a.person?.trim() ? this.#personFor(session, a.person) : found.owner;
    const thread = this.#latestThreadReady(session);
    if (thread === undefined) {
      await this.#d.hub.prepareLatestThreads!([session]);
      const current = this.#d.hub.store.getSession(session);
      if (current === null || current.archivedAt != null) throw new Refused("This chat is archived or gone.");
      return this.remove(session, a);
    }
    const plain = found.vault === PLAIN;
    const now = this.#d.now();
    const id = `r_${ulid(now)}`;
    const request: Request = {
      id, ws, vault: found.vault, item: found.item, session, chat: "", mode: found.listing.modes[0]!, reason: a.reason.trim(),
      box: "", at: Math.floor(now / 1000), status: "pending", ...(plain && found.owner ? { owner: found.owner } : {}),
      remove: { name: found.listing.name },
    };
    const kept: Kept = { request, thread: null, cardTs: null };
    if (thread !== null) {
      request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
      kept.cardTs = await this.#postRemove(session, thread, request, decider ?? undefined);
      kept.thread = thread.thread.id;
    }
    this.#save(kept);
    this.#audit(request, "remove-request", "");
    this.#told(request);
    return this.#saidRemove(request) + (decider ? ` It is for ${decider} to decide.` : "");
  }

  /// The card of a request to delete an item: its name and why.
  async #postRemove(session: string, thread: SessionThread, r: Request, decider: string | undefined, requireEmpty = false, signal?: AbortSignal): Promise<string | null> {
    const name = r.remove!.name;
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const text = [
      `申请删除密钥「${name}」：${r.reason}`,
      ...(stillfail ? [] : ["请在 still.fail 客户端的「密钥」中批准。"]),
    ].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ ...REMOVE_WORDS.yes, recommended: true }, REMOVE_WORDS.no],
          ...(decider ? { assignee: decider.toLowerCase() } : {}),
          // The request as the app draws it: `remove` says it is one to delete; its outcome added once decided.
          vault: { request: r.id, name, reason: r.reason, mode: r.mode, hosts: [], remove: { name } },
        }
      : null;
    return this.#postCard(session, thread, text, card, requireEmpty, r, signal);
  }

  /// What an agent is told of a request to delete an item, waiting (secret_delete's answer) or decided (a notice).
  #saidRemove(r: Request): string {
    const name = r.remove!.name;
    if (r.status === "granted") return `Deleted: 「${name}」 (${r.item}) is no longer in the vault.`;
    if (r.status === "denied") return `The person chose to keep 「${name}」 (request ${r.id}): it stays in the vault.`;
    if (r.status === "expired") return `The request to delete 「${name}」 (${r.id}) was let go.`;
    if (r.status === "withdrawn") return `You withdrew the request to delete 「${name}」 (${r.id}).`;
    return `Asked to delete 「${name}」 (request ${r.id}); the card is in your chat, approved in the still.fail app. ${UNDECIDED} Only their approval in the app deletes it: a reply in the chat saying yes does not.`;
  }

  /// POST vault/removed `{request}`: a request to delete an item of a vault, approved by a member of it whose app wrote
  /// the item's deleted version (and brought it here): taken once the item here is deleted. Why not, or null.
  removed(lock: LockState, sub: string, d: { request?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(lock.ws, d.request) : null;
    if (k === null || !k.request.remove || k.request.vault === PLAIN) return "no such request to delete an item of a vault";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const vault = this.#d.vaults.vault(lock.ws, k.request.vault);
    if (vault === null || !vault.members.includes(sub)) return "only the vault's members decide its requests";
    const item = this.#d.vaults.item(lock.ws, vault.id, k.request.item);
    if (item !== null && !item.deleted) return "the item is not deleted here: bring its copy first";
    if (!this.#settle(k.request, "granted")) return this.#decisionChanged(k.request);
    return null;
  }

  /// POST vault/plain/removed `{request}`: a request to delete an item of the plain library, approved by its owner:
  /// its deleted version written here. The item as written, or why not.
  removedPlain(ws: string, email: string, d: { request?: unknown }): PlainItem | string {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || !k.request.remove || k.request.vault !== PLAIN) return "no such request to delete an item of the plain library";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const snapshot = this.#d.plain.itemSnapshot(ws, k.request.item);
    const prev = snapshot?.value ?? null;
    if (prev === null || prev.deleted) return "the item is gone already";
    const next: PlainItem = { ws, id: prev.id, owner: prev.owner, version: prev.version + 1, kind: prev.kind, name: "", fields: {}, notes: "", at: Math.floor(this.#d.now() / 1000), deleted: true };
    const why = plainOk(prev, next, prev.owner);
    if (why !== null) return why;
    try {
      const settled = this.#settle(k.request, "granted", undefined, undefined, () => {
        if (this.#d.db.prepare("SELECT 1 FROM vault_plain WHERE ws=? AND id=? AND body=?").get(ws, prev.id, snapshot!.body) === undefined) throw new Refused("the item changed; try again");
        this.#d.plain.put(next);
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    return this.#d.plain.item(ws, next.id)!;
  }

  // ── a request taken back by the agent that asked (secret_cancel 撤回) ──

  /// secret_cancel: `session` takes back request `id` of its own (secret_use, secret_save, secret_describe,
  /// secret_delete) that nobody decided yet: its card closed and saying so, gone from its owner's waiting requests.
  cancel(session: string, id: string): string {
    const { ws } = this.#placeOf(session);
    const kept = this.#kept(ws, id.trim());
    if (kept === null || kept.request.session !== session) throw new Refused("No such request in this chat: give the id (r_…) secret_use, secret_save, secret_describe or secret_delete answered.");
    const r = kept.request;
    if (r.status !== "pending") throw new Refused(`Request ${r.id} is no longer pending (${r.status}): nothing to withdraw.`);
    if (!this.#settle(r, "withdrawn")) {
      const now = this.#kept(ws, r.id)?.request.status;
      throw new Refused(now && now !== "pending" ? `Request ${r.id} was ${now} meanwhile: nothing to withdraw.` : `Request ${r.id} changed while it was withdrawn; try again.`);
    }
    return `Withdrew request ${r.id}: its card is closed and its owner no longer sees it waiting.`;
  }

  // ── secrets agents ask to keep (secret_save agent 存入) ──

  /// The person a session works for, as the lock has them (their sub), where security mode is on.
  #memberOf(lock: LockState, email: string): string | null {
    return memberWithEmail(lock, email)?.sub ?? null;
  }

  /// `sub`'s devices set up for the vault: their box certificates, checked against the lock.
  #certsOf(lock: LockState, sub: string): BoxCert[] {
    // Keep the store's device order, but read certificates only for this person's lock devices.
    return [...devicesFor(lock, sub)].sort().flatMap((id) => {
      const cert = this.#d.vaults.box(lock.ws, id);
      return cert !== null && certOk(lock, cert) === null && lock.devices.get(cert.device)?.sub === sub ? [cert] : [];
    });
  }

  /// The vault a secret kept for `sub` is meant for: one of theirs keyed to a device of theirs, their own first; empty
  /// while they have none (the app that approves makes one).
  #vaultFor(lock: LockState, sub: string): string {
    const devices = new Set(this.#certsOf(lock, sub).map((c) => c.device));
    // Without a certificate there cannot be a vault keyed to one of this person's devices.
    if (devices.size === 0) return "";
    // A personal vault wins over an earlier shared one. Keep both portions in one snapshot and use the stored key as
    // the boundary: older data can have a different id in the body.
    this.#d.db.exec("SAVEPOINT vault_choose_owner");
    try {
      let first: Vault | undefined;
      const personal = (vaults: Vault[]) => {
        for (const vault of vaults) {
          if (!vault.members.includes(sub) || !vault.keys.some((k) => devices.has(k.cert.device))) continue;
          first ??= vault;
          if (vault.owner === sub) return vault;
        }
        return undefined;
      };
      const prefix = this.#d.vaults.firstVaults(lock.ws, LISTING_PREFIX);
      let owned = personal(prefix.map((entry) => entry.value));
      if (owned !== undefined) return owned.id ?? "";
      if (prefix.length === LISTING_PREFIX) owned = personal(this.#d.vaults.vaultsAfter(lock.ws, prefix.at(-1)!.id));
      return (owned ?? first)?.id ?? "";
    } finally { this.#d.db.exec("RELEASE vault_choose_owner"); }
  }

  #sealTo(cert: BoxCert, ws: string, request: string, fields: Record<string, string>) {
    return { device: cert.device, box: cert.box, secret: seal(cert.box, Buffer.from(JSON.stringify(fields)), saveContext(ws, request)) };
  }

  /// Whether the person a session works for can keep a secret: `plain` (no security mode: the plain library here),
  /// `on` (a vault of theirs, keyed to a device of theirs set up), `off` (security mode on, their vault not turned on:
  /// a secret to keep waits on its card until they turn it on there), `none` (no one to keep it for).
  status(session: string, person?: string): "plain" | "on" | "off" | "none" {
    const { lock } = this.#placeOf(session);
    const email = this.#personFor(session, person);
    if (email === null) return "none";
    if (lock === null) return "plain";
    const sub = this.#memberOf(lock, email);
    if (sub === null) return "none";
    return this.#vaultFor(lock, sub) !== "" ? "on" : "off";
  }

  /// secret_save: a request from `session` to keep a secret in the vault of whoever started its chat, given as `value`,
  /// printed by `command` (run here in `cwd`; what it prints is never shown) or, given neither, typed in by that person
  /// on its card (`save.typed`: nothing of it held or sealed here); its card posted, decided, the session is told (#settle).
  async save(
    session: string,
    a: {
      name: string; kind: string; reason: string; value?: string; command?: string; path?: string; username?: string; public_key?: string; filename?: string; modes?: string[]; hosts?: string[]; env?: string;
      cwd: string; station?: string; browser?: "chat" | "station"; person?: string;
      /// What it is and how it is used (its listing's `about`, the item's notes): shown to agents with its name.
      about?: string;
      /// Kept from a sign-in's card (signin.ts), the person having chosen there to keep it: no card of its own, its
      /// request told to `made` (the app that signed in approves it in place).
      quiet?: (request: string) => void;
    },
  ): Promise<string> {
    const place = this.#placeOf(session);
    const ws = place.ws;
    let lock = place.lock;
    const kind = a.kind as Kind;
    // A sign-in is read from a browser, never given, printed or typed in.
    if (kind === "browser" && (a.value !== undefined || a.command !== undefined || a.path !== undefined || a.station !== undefined)) throw new Refused("A sign-in (kind browser) is read from this chat's browser (or the station's: browser \"station\"), its cookies of hosts: give no value, command, path or station.");
    if (kind === "browser" && this.#d.browsers === undefined) throw new Refused("This station has no browser to read a sign-in from.");
    if (kind !== "browser" && a.browser !== undefined) throw new Refused("browser says where a sign-in is read from: give kind browser");
    if (a.path !== undefined && kind !== "file") throw new Refused("path is a file's: give kind file");
    if (a.path !== undefined && (a.command !== undefined || a.value !== undefined)) throw new Refused("Give a file as path, command or value, one of them.");
    // A file given by its path: read as a command printing it would (here or on the station named), ~/ its home there.
    const quoted = (p: string) => `'${p.replace(/'/g, "'\\''")}'`;
    const command = a.path === undefined ? a.command : `cat -- ${a.path.startsWith("~/") ? `"$HOME"/${quoted(a.path.slice(2))}` : quoted(a.path)}`;
    const filename = kind === "file" ? (a.filename ?? (a.path !== undefined ? basename(a.path) : "")).trim() : "";
    const from = a.station ? this.#peer(a.station) : null;
    if (from !== null && command === undefined) throw new Refused("station says where command runs: give command (or path)");
    const email = this.#personFor(session, a.person);
    if (email === null) throw new Refused("No one started this chat: there is no one to keep a secret for; name the person it is for (person).");
    if (!KINDS.includes(kind)) throw new Refused("kind is token, login, ssh_key, file or browser");
    const name = a.name.trim();
    if (name === "" || name.length > 200) throw new Refused("name is required (at most 200 characters): what the person and agents will know it by");
    if (a.reason.trim() === "") throw new Refused("reason is required: why it is worth keeping, for the person deciding");
    const about = (a.about ?? "").trim();
    if (about.length > ABOUT_MOST) throw new Refused(`about is at most ${ABOUT_MOST} characters`);
    if (a.value !== undefined && command !== undefined) throw new Refused("Give the secret as value or as a command that prints it (command), not both; neither, and the card asks the person to type it in.");
    const typed = kind !== "browser" && a.value === undefined && command === undefined;
    const hosts = [...new Set((a.hosts ?? []).map((h) => h.trim().toLowerCase()).filter((h) => h !== ""))];
    const modes = (a.modes?.length ? [...new Set(a.modes)] : kind === "ssh_key" ? ["ssh"] : kind === "file" ? ["file"] : kind === "browser" ? ["browser"] : hosts.length > 0 ? ["proxy"] : ["env"]) as Mode[];
    if (!modes.every((m) => MODES.includes(m))) throw new Refused("modes are proxy, ssh, env, file or browser");
    if (modes.includes("ssh") !== (kind === "ssh_key")) throw new Refused("an SSH key is given by ssh (or env), and only an SSH key is");
    if (kind === "file" && (modes.length !== 1 || modes[0] !== "file")) throw new Refused("a file is given as a file (modes: [\"file\"])");
    let sub = lock === null ? null : this.#memberOf(lock, email);
    if (lock !== null && sub === null) throw new Refused(`${email} is not in the workspace's security mode: there is no vault of theirs to keep it in.`);
    const listing: Listing = { name, kind, modes, hosts, ...(a.env ? { env: a.env } : {}), ...(about ? { about } : {}) };
    const now = this.#d.now();
    const item = `i_${ulid(now)}`;
    // What is not secret checked before anything is run.
    const draft = (fields: Record<string, string>): PlainItem => ({ ws, id: item, owner: email, version: 0, kind, name, fields, notes: about, listing, at: Math.floor(now / 1000) });
    // (a file's value: its bytes in base64; given as value, its text)
    const fieldsOf = (value: string): Record<string, string> =>
      kind === "token" ? { value } : kind === "browser" ? { cookies: value } : kind === "login" ? { ...(a.username ? { username: a.username } : {}), password: value }
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
    if (kind === "browser") {
      value = await this.#d.browsers!.cookies(session, hosts, a.browser === "station");
      const found = stateOf(value);
      if (found.cookies.length === 0 && found.passkeys.length === 0) throw new Refused(`${a.browser === "station" ? "The station's browser" : "This chat's browser"} holds no cookies or passkeys of ${hosts.join(", ")}: sign in there first (a person, in the tab you give them with the \`screen\` tool; a passkey: added on the site's account page there); nothing was kept.`);
      if (value.length > TYPED_MOST) throw new Refused(`The cookies of ${hosts.join(", ")} are more than ${TYPED_MOST / 1024} KB: name the sites the sign-in is for, not more; nothing was kept.`);
    }
    if (kind === "file" && Buffer.byteLength(value, "base64") > FILE_MOST) throw new Refused(`The file is more than ${FILE_MOST / 1024} KB; nothing was kept.`);
    if (value === "" && !typed) throw new Refused("The secret is empty; nothing was kept.");
    // A command or browser read must happen only once. Keep its result in this call while an old order is prepared,
    // and recheck who may keep it before making a box or saving anything.
    const currentLock = () => {
      const current = this.#d.hub.store.getSession(session);
      if (current === null || current.archivedAt != null) throw new Refused("This chat is archived or gone; nothing was kept.");
      if ((current.ws ?? this.#d.home()) !== ws || this.#personFor(session, a.person) !== email) throw new Refused("This chat's owner or workspace changed; nothing was kept.");
      return this.#d.lock(current.ws ?? null);
    };
    currentLock();
    let thread = this.#latestThreadReady(session);
    while (thread === undefined) {
      await this.#d.hub.prepareLatestThreads!([session]);
      currentLock();
      thread = this.#latestThreadReady(session);
    }
    lock = currentLock();
    sub = lock === null ? null : this.#memberOf(lock, email);
    if (lock !== null && sub === null) throw new Refused(`${email} is not in the workspace's security mode: there is no vault of theirs to keep it in.`);
    const fields = typed ? null : fieldsOf(value);
    const requestedAt = this.#d.now();
    const id = `r_${ulid(requestedAt)}`;
    const save: Save = {
      kind, name, modes, hosts, ...(a.env ? { env: a.env } : {}), ...(a.username ? { username: a.username } : {}), ...(a.public_key ? { public_key: a.public_key } : {}), ...(filename ? { filename } : {}),
      ...(typed ? { typed: true as const } : {}), ...(about ? { about } : {}),
    };
    const request: Request = {
      id, ws, vault: lock === null ? PLAIN : this.#vaultFor(lock, sub!), item, session, chat: "", mode: modes[0]!, reason: a.reason.trim(),
      ...(command !== undefined ? { command } : {}), ...(hosts.length ? { hosts } : {}),
      // A vault's: a box for the grant to this chat that comes with keeping it (the app seals the secret to it too).
      box: lock === null ? "" : this.keeper.open(id), at: Math.floor(requestedAt / 1000), status: "pending", owner: email, save, ...(from ? { runOn: from } : {}),
      ...(lock !== null && fields !== null ? { sealed: this.#certsOf(lock, sub!).map((c) => this.#sealTo(c, ws, id, fields)) } : {}),
    };
    const duringHandover = lock !== null && fields !== null && !this.#previousExited;
    if (fields !== null) {
      this.#unsaved.set(id, fields);
      this.#scopeSave(id, ws, email);
      this.#postingSaves.set(id, request);
      // The previous process cannot rebox a save whose fields exist only in this process.
      if (duringHandover) { this.#carriedSaves.add(id); this.#waitForCarriedSaves(); }
    }
    const kept: Kept = { request, thread: null, cardTs: null };
    try {
      if (thread !== null) {
        request.chat = threadAddress(thread.thread.channel, thread.thread.threadTs);
        kept.cardTs = a.quiet ? null : await this.#postSave(session, thread, request);
        kept.thread = thread.thread.id;
      }
      // If the predecessor exited while the card was being posted, its last certificate must be included before this
      // request is written. The exit callback may already have observed the still-unwritten posting above.
      if (duringHandover && this.#previousExited) this.#sealCurrentSave(request);
      this.#save(kept);
    } catch (error) {
      this.#forgetSave(id);
      this.keeper.drop(id);
      throw error;
    } finally {
      this.#postingSaves.delete(id);
    }
    a.quiet?.(id);
    this.#audit(request, "save-request", [modes.join(" "), hosts.join(" "), from ? `${from.name}: ${command}` : (command ?? ""), typed ? "typed" : ""].filter((x) => x !== "").join(" · "));
    this.#told(request);
    return this.#saidSave(request);
  }

  /// The card of a request to keep a secret: what it is, whose, why (the app draws it from `vault.save`, offering to
  /// turn the vault on first where it is not).
  async #postSave(session: string, thread: SessionThread, r: Request, requireEmpty = false, signal?: AbortSignal): Promise<string | null> {
    const s = r.save!;
    const stillfail = thread.thread.surface === STILLFAIL_SURFACE;
    const kind = `（${KIND_WORDS[s.kind]}${s.username ? ` · ${s.username}` : s.filename ? ` · ${s.filename}` : ""}）`;
    const text = [
      s.typed ? `请填入「${s.name}」${kind}并存入密钥库：${r.reason}` : `申请将「${s.name}」存入密钥库${kind}：${r.reason}`,
      ...(s.about ? [`说明：${s.about}`] : []),
      ...(stillfail ? [] : [s.typed ? "请在 still.fail 客户端的「密钥」中填写并存入。" : "请在 still.fail 客户端的「密钥」中批准。"]),
    ].join("\n\n");
    const card = stillfail
      ? {
          type: "options",
          options: [{ ...SAVE_WORDS.save, recommended: true }, SAVE_WORDS.deny],
          assignee: r.owner,
          // The request as the app draws it: `save` says it is one to keep; its outcome added once decided.
          vault: {
            request: r.id, name: s.name, reason: r.reason, ...(r.command ? { command: r.command } : {}), mode: s.modes[0], hosts: hosted(s.modes[0]!) ? s.hosts : [],
            ...(s.about ? { about: s.about } : {}),
            ...(r.runOn ? { station: r.runOn.name } : {}),
            save: { kind: s.kind, ...(s.username ? { username: s.username } : {}), ...(s.filename ? { filename: s.filename } : {}), ...(s.typed ? { typed: true } : {}) },
          },
        }
      : null;
    return this.#postCard(session, thread, text, card, requireEmpty, r, signal);
  }

  /// What an agent is told of a request to keep a secret, waiting (secret_save's answer) or decided (a notice).
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
    return `${asked} ${UNDECIDED} Only their approval in the app keeps it: a reply in the chat saying yes does not.`;
  }

  #sealSave(r: Request, lock: LockState, cert: BoxCert, sub: string, email: string): boolean {
    const fields = this.#unsaved.get(r.id);
    if (r.ws !== lock.ws || !r.save || r.vault === PLAIN || r.owner !== email || fields === undefined || r.sealed?.some((x) => x.box === cert.box)) return false;
    r.sealed = [...(r.sealed ?? []).filter((x) => x.device !== cert.device), this.#sealTo(cert, r.ws, r.id, fields)];
    if (r.vault === "") r.vault = this.#vaultFor(lock, sub);
    return true;
  }

  /// A device's box key published (PUT vault/boxes, checked): the secrets waiting to be kept for its person sealed to
  /// it too, so that they may approve them from it.
  boxed(lock: LockState, cert: BoxCert): boolean {
    try {
      const complete = this.#boxed(lock, cert);
      if (!complete) this.#queueRebox(lock.ws, cert.device);
      return complete;
    } catch (error) {
      this.#queueRebox(lock.ws, cert.device);
      throw error;
    }
  }

  #queueRebox(ws: string, device: string) {
    if (this.#restoreClosed) return;
    const key = `${ws}\0${device}`;
    if (!this.#reboxPending.has(key)) this.#reboxPending.set(key, { ws, device, delay: 250 });
    this.#scheduleRebox(0);
  }

  #scheduleRebox(delay: number) {
    if (this.#restoreClosed || this.#reboxScheduled || this.#reboxPending.size === 0) return;
    this.#reboxScheduled = true;
    this.#reboxFibers ??= new Fibers("vault reboxing");
    this.#reboxFibers.after(delay, () => this.#retryRebox());
  }

  #retryRebox() {
    this.#reboxScheduled = false;
    if (this.#restoreClosed) return;
    const next = this.#reboxPending.entries().next().value;
    if (next === undefined) return;
    const [key, pending] = next;
    const { ws, device } = pending;
    this.#reboxPending.delete(key);
    let retry = false, delay = pending.delay;
    try {
      const lock = this.#d.lock(ws);
      if (lock === null) { retry = true; delay = Math.max(delay, 5_000); }
      else {
        const cert = this.#d.vaults.box(ws, device);
        if (cert !== null && cert.ws === ws && cert.device === device && certOk(lock, cert) === null) retry = !this.#boxed(lock, cert);
      }
    } catch (error) {
      retry = true;
      log.warn("vault", "a certificate could not rebox its pending saves", { error: (error as Error).message });
    }
    if (retry && !this.#reboxPending.has(key)) this.#reboxPending.set(key, { ws, device, delay: Math.min(delay * 2, 30_000) });
    this.#scheduleRebox(retry ? delay : 0);
  }

  #boxed(lock: LockState, cert: BoxCert): boolean {
    const sub = lock.devices.get(cert.device)?.sub;
    const email = sub === undefined ? undefined : lock.members.get(sub)?.email.toLowerCase();
    if (sub === undefined || email === undefined) return true;
    // A handover from an older station may contain a save not written yet. Recheck those known ids in this workspace;
    // reboxed has already scoped those it could find. New saves and handovers carry their own scope.
    if (this.#unscopedSaves.size > 0) {
      const lookup = this.#d.db.prepare(CARRIED_SAVE_PENDING);
      for (const id of this.#unscopedSaves) {
        const row = lookup.get(lock.ws, id) as { body: string } | undefined;
        if (row === undefined) continue;
        const r = JSON.parse(row.body) as Request;
        if (this.#unscopedSaves.has(r.id) && r.save && r.owner !== undefined) this.#scopeSave(r.id, r.ws, r.owner);
      }
    }
    // Request ids are ASCII ULIDs: retain the old workspace scan's primary-key order for notifications.
    const requests = [...(this.#savesByOwner.get(lock.ws)?.get(email) ?? [])].sort();
    if (requests.length === 0) return true;
    const read = this.#d.db.prepare("SELECT body, thread, card_ts FROM vault_requests WHERE ws = ? AND id = ? AND status = 'pending'");
    const write = this.#d.db.prepare(`UPDATE vault_requests SET body = ?
      WHERE ws = ? AND id = ? AND status = 'pending' AND body = ? AND thread IS ? AND card_ts IS ?
        AND EXISTS (SELECT 1 FROM vault_boxes WHERE ws = ? AND device = ? AND body = ?)`);
    let checked = JSON.stringify(cert), complete = true;
    for (const id of requests) {
      let settled = false;
      for (let attempt = 0; attempt < 3; attempt++) {
        // Another connection may have published a certificate after this callback was scheduled. Only trust that
        // replacement after checking it against the lock, and write a request only while both records are unchanged.
        const held = this.#d.vaults.boxSnapshot(lock.ws, cert.device);
        if (held === null) break;
        if (held.body !== checked) {
          if (held.value === null || typeof held.value !== "object" || held.value.ws !== lock.ws || held.value.device !== cert.device || certOk(lock, held.value) !== null) break;
          checked = held.body;
        }
        const posting = this.#postingSaves.get(id);
        if (posting !== undefined) this.#sealSave(posting, lock, held.value, sub, email);
        const row = read.get(lock.ws, id) as { body: string; thread: number | null; card_ts: string | null } | undefined;
        if (row === undefined) { settled = true; break; }
        const k: Kept = { request: JSON.parse(row.body), thread: row.thread ?? null, cardTs: row.card_ts ?? null };
        if (!this.#sealSave(k.request, lock, held.value, sub, email)) { settled = true; break; }
        if (write.run(JSON.stringify(k.request), lock.ws, id, row.body, k.thread, k.cardTs, lock.ws, cert.device, held.body).changes === 0) continue;
        this.#trackSaved(k);
        this.#told(k.request);
        settled = true;
        break;
      }
      if (!settled) complete = false;
    }
    return complete;
  }

  /// POST vault/saves: a secret asked to be kept, written by `sub`'s app into their vault `vault` (under the request's
  /// item id; its copy brought here first); why it is refused, or null.
  saved(lock: LockState, sub: string, d: { request?: unknown; vault?: unknown; grant?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(lock.ws, d.request) : null;
    if (k === null || !k.request.save || k.request.vault === PLAIN) return "no such request to keep a secret in a vault";
    if (lock.members.get(sub)?.email.toLowerCase() !== k.request.owner) return "only the person it is kept for decides it";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const vaultSnapshot = typeof d.vault === "string" ? this.#d.vaults.vaultSnapshot(lock.ws, d.vault) : null;
    const vault = vaultSnapshot?.value ?? null;
    if (vault === null || !vault.members.includes(sub)) return "no such vault of theirs here";
    const itemSnapshot = this.#d.vaults.itemSnapshot(lock.ws, vault.id, k.request.item);
    const item = itemSnapshot?.value ?? null;
    if (item === null || item.deleted || item.listing?.name !== k.request.save.name) return "the item is not in that vault here: bring its copy first";
    // Keeping it lets the chat that asked use it (its app's grant, sealed to this request's box): kept all the same if
    // that grant does not hold.
    const prepared = d.grant === undefined ? "none sent" : this.keeper.prepareAccept(lock, vault, item, { ...k.request, vault: vault.id }, d.grant as Grant);
    let why: string | null = null;
    try {
      const settled = this.#settle(k.request, "granted", undefined, vault.id, (current) => {
        this.#checkVaultSnapshot(lock.ws, vault.id, item.id, vaultSnapshot!.body, itemSnapshot!.body);
        why = typeof prepared === "string" ? prepared : prepared();
        if (why !== null && this.keeper.waiting(current.id)) this.keeper.drop(current.id);
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    if (why !== null) log.warn("vault", "a kept secret's grant to its chat not taken", { why });
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
      ws, id: k.request.item, owner: k.request.owner!, version: 0, kind: s.kind, name: s.name, fields, notes: s.about ?? "",
      listing: { name: s.name, kind: s.kind, modes: s.modes, hosts: s.hosts, ...(s.env ? { env: s.env } : {}), ...(s.about ? { about: s.about } : {}) }, at: Math.floor(this.#d.now() / 1000),
    };
    if (this.#d.plain.item(ws, next.id) !== null) return "the item is there already";
    const why = plainOk(null, next, next.owner);
    if (why !== null) return why;
    let held: string | null = null;
    try {
      const settled = this.#settle(k.request, "granted", undefined, undefined, (current) => {
        if (this.#d.plain.item(ws, next.id) !== null) throw new Refused("the item is there already");
        this.#d.plain.put(next);
        // Keeping it lets the chat that asked use it, for as long as the person's items are given.
        const lasts = this.#d.plain.lasts(ws, next.owner)?.lasts ?? null;
        const scope: Scope = allows(lasts, "hour") ? "hour" : "once";
        held = this.keeper.hold(current, { scope, hosts: hosted(s.modes[0]!) ? s.hosts : [], listing: next.listing!, lasts, ...(scope === "hour" ? { timeout: { kind: "idle" as const, seconds: 3600 } } : {}) }, { kind: s.kind, name: s.name, fields });
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    if (held !== null) log.warn("vault", "a kept secret's grant to its chat not held", { why: held });
    return this.#d.plain.item(ws, next.id)!;
  }

  /// A request decided otherwise than granted, or granted (`grant` checked by the keeper first); `into`: the vault a
  /// secret to keep went into.
  #settle(r: Request, status: Request["status"], scope?: Scope, into?: string, prepare?: (current: Request) => void): boolean {
    let settled: { k: Kept; outcome: Record<string, unknown>; queued: boolean } | undefined;
    const requested = JSON.stringify(r);
    for (let attempt = 0; attempt < 3; attempt++) {
      const k = this.#kept(r.ws, r.id);
      if (k === null || k.request.status !== "pending" || JSON.stringify(k.request) !== requested) return false;
      const expected = k;
      const outcome: Record<string, unknown> = { status, ...(status === "granted" && scope ? { scope } : {}) };
      const save = () => {
        // The writer is held here: a decision or reissued card committed after our first read must be seen.
        const current = this.#d.db.prepare("SELECT thread,card_ts FROM vault_requests WHERE ws=? AND id=? AND status='pending' AND body=?")
          .get(r.ws, r.id, expected.raw!) as { thread: number | null; card_ts: string | null } | undefined;
        if (current === undefined) throw new DecisionChanged();
        if (current.thread !== expected.thread || current.card_ts !== expected.cardTs) throw new DecisionCardMoved();
        prepare?.(k.request);
        k.request.status = status;
        if (into !== undefined) k.request.vault = into;
        const held = status === "granted" ? this.keeper.usable(r.session, r.id) : null;
        if (typeof held === "object" && held !== null && held.grant.timeout) outcome.timeout = held.grant.timeout;
        this.#write(k);
      };
      const queue = k.thread !== null && k.cardTs !== null ? this.#d.cardOutcomes : undefined;
      try {
        this.keeper.rollbackOnError(r.id, () => {
          if (queue) queue.save({ thread: expected.thread!, ts: expected.cardTs!, agent: r.session, field: "vault", close: true, outcome }, save);
          else {
            const nested = this.#d.db.isTransaction;
            this.#d.db.exec(nested ? "SAVEPOINT vault_settle" : "BEGIN IMMEDIATE");
            try { save(); this.#d.db.exec(nested ? "RELEASE vault_settle" : "COMMIT"); }
            catch (error) { try { this.#d.db.exec(nested ? "ROLLBACK TO vault_settle; RELEASE vault_settle" : "ROLLBACK"); } catch {} throw error; }
          }
        });
      } catch (error) {
        if (error instanceof DecisionChanged) return false;
        if (error instanceof DecisionCardMoved) continue;
        throw error;
      }
      settled = { k, outcome, queued: queue !== undefined };
      break;
    }
    if (settled === undefined) return false;
    const { k, outcome, queued } = settled;
    this.#trackSaved(k);
    if (!queued && k.thread !== null && k.cardTs !== null) {
      this.#d.hub.store.withdrawCard(r.session, k.thread, k.cardTs);
      this.#d.hub.store.restateCard(r.session, k.thread, k.cardTs, (card) => ({ ...card, vault: { ...card?.vault, outcome } }));
    }
    this.#forgetSave(r.id, r.ws);
    if (status !== "granted") this.keeper.drop(r.id);
    this.#audit(k.request, status, "");
    this.#told(k.request);
    if (status === "granted" && k.request.mode === "browser" && !k.request.describe && !k.request.remove) {
      this.#renewalGranted(k.request);
      this.#signIn(k.request);
    }
    // The agent is told in its session: no tool call waits for it.
    // (one the agent withdrew itself: it knows, from secret_cancel's answer)
    if (status !== "expired" && status !== "withdrawn") {
      const l = this.#listingOf(r);
      try {
        this.#d.hub.notify(r.session, k.request.save ? this.#saidSave(k.request) : k.request.describe ? this.#saidDescribe(k.request) : k.request.remove ? this.#saidRemove(k.request) : l ? this.#said(k.request, l) : `The request ${r.id} was ${status}.`);
      } catch {
        // The session is gone: nobody to tell.
      }
    }
    return true;
  }

  #decisionChanged(r: Request): string {
    const current = this.#kept(r.ws, r.id);
    return current === null ? "no such request" : current.request.status === "pending" ? "the request changed; try again" : `the request is ${current.request.status}`;
  }

  #checkVaultSnapshot(ws: string, vault: string, item: string, vaultBody: string, itemBody: string): void {
    const currentVault = this.#d.db.prepare("SELECT 1 FROM vaults WHERE ws=? AND id=? AND body=?").get(ws, vault, vaultBody);
    const currentItem = this.#d.db.prepare("SELECT 1 FROM vault_items WHERE ws=? AND vault=? AND id=? AND body=?").get(ws, vault, item, itemBody);
    if (currentVault === undefined || currentItem === undefined) throw new Refused("the request's vault or item changed; try again");
  }

  /// A sign-in granted: put into the chat's browser while the grant lasts.
  #signIn(r: Request) {
    const held = this.keeper.usable(r.session, r.id);
    const cookies = typeof held === "string" ? null : valueOf(held.secret);
    if (typeof held === "string" || cookies === null || this.#d.browsers === undefined) return;
    if (held.request.vault === PLAIN && held.grant.scope === "once" && !this.#previousExited) {
      // An older process may still use its in-memory copy without the conditional claim. Wait for its real exit.
      void this.#d.backfill!.previousGone!.then(() => this.#signIn(r)).catch((error) =>
        log.warn("vault", "a sign-in could not wait for the previous station", { request: r.id, error: (error as Error).message }));
      return;
    }
    if (!this.keeper.spend(r.id)) {
      log.warn("vault", "a one-use sign-in grant was already used or changed", { request: r.id });
      return;
    }
    this.#audit(r, "use", `browser ${held.grant.hosts.join(" ")}`);
    void this.#d.browsers.signIn(r.session, { request: r.id, workspace: r.ws, sites: held.grant.hosts, cookies, until: held.grant.exp }).catch((e) =>
      log.warn("vault", "a sign-in could not be put into its chat's browser", { request: r.id, error: (e as Error).message }));
  }

  /// `session`'s chat has a new context in the browser (Chrome started again): its sign-ins still granted put in again.
  signInAgain(session: string) {
    for (const h of this.keeper.held(session)) {
      const cookies = h.grant.mode === "browser" ? valueOf(h.secret) : null;
      if (cookies === null || this.#d.browsers === undefined) continue;
      if (h.request.vault === PLAIN && h.grant.scope === "once") {
        this.#signIn(h.request);
        continue;
      }
      void this.#d.browsers.signIn(session, { request: h.request.id, workspace: h.request.ws, sites: h.grant.hosts, cookies, until: h.until ?? h.grant.exp }).catch((e) =>
        log.warn("vault", "a sign-in could not be put into its chat's browser again", { request: h.request.id, error: (e as Error).message }));
    }
  }

  /// A deliberate browser action on a granted site extends that sign-in's idle time.
  browserUsed(session: string, host: string) {
    for (const h of this.keeper.held(session)) {
      if (h.grant.mode !== "browser" || h.grant.timeout?.kind !== "idle" || !h.grant.hosts.some((site) => host === site || host.endsWith(`.${site}`))) continue;
      this.keeper.renew(session, h.request.id);
      if (h.until !== undefined) this.#d.browsers?.extendSignIn?.(session, h.request.id, h.until);
    }
  }

  /// `session`'s chat's context taken up from the station process before: the passkeys of its sign-ins still granted put
  /// in again (they went with that process's connection to the browser; its cookies are there still).
  passkeysAgain(session: string) {
    for (const h of this.keeper.held(session)) {
      const cookies = h.grant.mode === "browser" ? valueOf(h.secret) : null;
      if (cookies === null || this.#d.browsers?.passkeysIn === undefined) continue;
      if (h.request.vault === PLAIN && h.grant.scope === "once") {
        this.#signIn(h.request);
        continue;
      }
      void this.#d.browsers.passkeysIn(session, { sites: h.grant.hosts, cookies }).catch((e) =>
        log.warn("vault", "a sign-in's passkeys could not be put into its chat's browser again", { request: h.request.id, error: (e as Error).message }));
    }
  }

  /// A sign-in taken out of its chat's browser as its grant ended, with its cookies as they were then: kept as the
  /// item's new version where the station keeps it (the plain library), so the next chat given it has the site's latest.
  /// A vault's item is written only by its members' apps: not here.
  renewed(session: string, request: string, cookies: string, workspace?: string) {
    // Contexts made before the workspace was kept still need their original lookup: the session may have moved.
    let r: Request | undefined;
    if (workspace === undefined) {
      const row = this.#d.db.prepare("SELECT ws FROM vault_requests WHERE id = ? AND session = ?").get(request, session) as { ws: string } | undefined;
      r = row === undefined ? undefined : this.#kept(row.ws, request)?.request;
    } else {
      const row = this.#d.db.prepare("SELECT body FROM vault_requests WHERE ws = ? AND id = ? AND session = ?").get(workspace, request, session) as { body: string } | undefined;
      r = row === undefined ? undefined : JSON.parse(row.body) as Request;
    }
    if (r === undefined) return;
    if (r.vault !== PLAIN) return this.#renewSealed(r, cookies);
    const item = this.#d.plain.item(r.ws, r.item);
    if (item === null || item.deleted || item.kind !== "browser" || item.fields.cookies === cookies) return;
    const next: PlainItem = { ...item, version: item.version + 1, fields: { ...item.fields, cookies }, at: Math.floor(this.#d.now() / 1000) };
    const why = plainOk(item, next, item.owner);
    if (why !== null) return log.warn("vault", "a sign-in's new cookies not kept", { request, why });
    this.#d.plain.put(next);
    this.#audit(r, "renewed", "");
    this.#plainWritten(next);
  }

  /// A vault's sign-in's newer cookies: the station cannot write its item (only its members' apps can), so they are
  /// sealed to its members' devices set up and kept (the latest only) until a grant of it carries them: the app that
  /// grants the next request for it writes them as the item's next version ( 登录态 写回).
  #renewSealed(r: Request, cookies: string) {
    const lock = this.#d.lock(r.ws);
    const vault = lock === null ? null : this.#d.vaults.vault(lock.ws, r.vault);
    if (lock === null || vault === null) return;
    const certs = vault.members.flatMap((sub) => this.#certsOf(lock, sub));
    if (certs.length === 0) return;
    const id = `n_${ulid(this.#d.now())}`;
    const body = { id, sealed: certs.map((c) => this.#sealTo(c, r.ws, id, { cookies })), digest: digestOf(cookies) };
    this.#d.db.prepare("INSERT INTO vault_renewals (ws, item, body) VALUES (?, ?, ?) ON CONFLICT (ws, item) DO UPDATE SET body = excluded.body").run(r.ws, r.item, JSON.stringify(body));
    this.#audit(r, "renewal", "");
  }

  /// The newer cookies kept for sign-in `item`, for a request of it to carry.
  #renewalOf(ws: string, item: string): { renewal?: Request["renewal"] } {
    const row = this.#d.db.prepare("SELECT body FROM vault_renewals WHERE ws = ? AND item = ?").get(ws, item) as { body: string } | undefined;
    if (row === undefined) return {};
    const { id, sealed } = JSON.parse(row.body) as { id: string; sealed: Sealed[] };
    return { renewal: { id, sealed } };
  }

  /// A sign-in granted with the newer cookies its request carried (its grant's are those): they are written now, kept
  /// no longer. A grant with others (an app from before renewals) leaves them for the next.
  #renewalGranted(r: Request) {
    if (r.renewal === undefined) return;
    const held = this.keeper.usable(r.session, r.id);
    const cookies = typeof held === "string" ? null : valueOf(held.secret);
    const row = this.#d.db.prepare("SELECT body FROM vault_renewals WHERE ws = ? AND item = ?").get(r.ws, r.item) as { body: string } | undefined;
    const kept = row === undefined ? null : (JSON.parse(row.body) as { id: string; digest: string });
    if (kept === null || kept.id !== r.renewal.id || cookies === null || digestOf(cookies) !== kept.digest) return;
    this.#d.db.prepare("DELETE FROM vault_renewals WHERE ws = ? AND item = ?").run(r.ws, r.item);
  }

  /// POST vault/grants: `grant`, sent by `sub`'s app; why it is refused, or null.
  grant(lock: LockState, sub: string, grant: Grant): string | null {
    const k = typeof grant?.request === "string" ? this.#kept(lock.ws, grant.request) : null;
    if (k === null) return "no such request";
    if (k.request.save) return "a secret to keep is approved by POST vault/saves";
    if (k.request.describe) return "a request to rename an item grants nothing: it is approved by POST vault/described";
    if (k.request.remove) return "a request to delete an item grants nothing: it is approved by POST vault/removed";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    const vaultSnapshot = this.#d.vaults.vaultSnapshot(lock.ws, k.request.vault);
    const itemSnapshot = this.#d.vaults.itemSnapshot(lock.ws, k.request.vault, k.request.item);
    const vault = vaultSnapshot?.value ?? null, item = itemSnapshot?.value ?? null;
    if (vault === null || item === null) return "the request's vault or item is gone";
    if (!vault.members.includes(sub)) return "only the vault's members decide its requests";
    const prepared = this.keeper.prepareAccept(lock, vault, item, k.request, grant);
    if (typeof prepared === "string") return prepared;
    try {
      const settled = this.#settle(k.request, "granted", grant.scope, undefined, () => {
        this.#checkVaultSnapshot(lock.ws, vault.id, item.id, vaultSnapshot!.body, itemSnapshot!.body);
        const why = prepared();
        if (why !== null) throw new Refused(why);
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    return null;
  }

  /// POST vault/plain/grants: the plain library's request `request` granted by `email` (its item's owner) for `scope`;
  /// why it is refused, or null. Security mode on, nothing of the plain library is given out (it is moved into a vault).
  grantPlain(ws: string, lock: LockState | null, email: string, d: { request?: unknown; scope?: unknown; timeout?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || k.request.vault !== PLAIN) return "no such request of the plain library";
    if (k.request.save) return "a secret to keep is approved by POST vault/plain/saves";
    if (k.request.describe) return "a request to rename an item grants nothing: it is approved by POST vault/plain/described";
    if (k.request.remove) return "a request to delete an item grants nothing: it is approved by POST vault/plain/removed";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (lock !== null) return "security mode is on: the plain library's secrets are moved into the vault, not given out";
    const itemSnapshot = this.#d.plain.itemSnapshot(ws, k.request.item);
    const item = itemSnapshot?.value ?? null;
    if (item === null || item.deleted || item.listing === undefined) return "the item is gone, or not one agents may ask for";
    const hosts = hosted(k.request.mode) ? (k.request.hosts ?? item.listing.hosts) : [];
    const timeout = d.timeout as { kind: "idle" | "fixed"; seconds: number } | undefined;
    try {
      const settled = this.#settle(k.request, "granted", d.scope as Scope, undefined, (current) => {
        if (this.#d.db.prepare("SELECT 1 FROM vault_plain WHERE ws=? AND id=? AND body=?").get(ws, item.id, itemSnapshot!.body) === undefined)
          throw new Refused("the item changed; try again");
        const why = this.keeper.hold(current, { scope: d.scope as Scope, hosts, listing: item.listing!, lasts: this.#lastsOf(current, item.listing!), ...(timeout === undefined ? {} : { timeout }) }, { kind: item.kind, name: item.name, fields: item.fields });
        if (why !== null) throw new Refused(why);
      });
      if (!settled) return this.#decisionChanged(k.request);
    } catch (error) { if (error instanceof Refused) return error.message; throw error; }
    return null;
  }

  /// POST vault/plain/denials: the plain library's request turned down by its item's owner.
  denyPlain(ws: string, email: string, d: { request?: unknown }): string | null {
    const k = typeof d?.request === "string" ? this.#kept(ws, d.request) : null;
    if (k === null || k.request.vault !== PLAIN) return "no such request of the plain library";
    if (k.request.owner !== email.toLowerCase()) return "only the item's owner decides its requests";
    if (k.request.status !== "pending") return `the request is ${k.request.status}`;
    if (!this.#settle(k.request, "denied")) return this.#decisionChanged(k.request);
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
    if (!this.#settle(k.request, "denied")) return this.#decisionChanged(k.request);
    return null;
  }

  /// secret_run: `command` with grant `id`, in the session's workspace (or `cwd` under it).
  /// `under`: `cwd` as given, under the session's directory (the one used on another station).
  async run(session: string, a: { grant: string; command: string; env?: string; cwd: string; under?: string; timeoutMs?: number; station?: string }): Promise<string> {
    let held = this.keeper.usable(session, a.grant);
    if (typeof held === "string") throw new Refused(held);
    if (held.request.vault === PLAIN && held.grant.scope === "once" && !this.#previousExited) {
      // The previous binary may still spend an in-memory copy without a conditional database claim.
      await this.#d.backfill!.previousGone;
      held = this.keeper.usable(session, a.grant);
      if (typeof held === "string") throw new Refused(held);
    }
    if (held.grant.mode === "browser") throw new Refused("A sign-in is not run with: it is in this chat's browser (the `browser` tool) while its grant lasts.");
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
    if (!this.keeper.spend(held.request.id)) throw new Refused("this grant was already used or changed: ask again");
    const env = a.env ?? listing?.env;
    const timeoutMs = Math.min(a.timeoutMs ?? RUN_MS, 3600_000);
    if (on !== null) {
      const ran = await this.#runOn(on, session, held, { command: a.command, under: a.under ?? "", timeoutMs, ...(env ? { env } : {}) });
      this.#audit(held.request, "run", `${on.name}: ${a.command}`.slice(0, 500));
      return said(ran);
    }
    // The station does not update itself meanwhile: the proxy or ssh-agent the command uses is this process's.
    const letGo = hold();
    const ran = await runWith(held, { command: a.command, cwd: a.cwd, ...(env ? { env } : {}), timeoutMs }, this.proxy, baseEnv(), (detail) => {
      this.keeper.renew(session, held.request.id);
      this.#audit(held.request, "use", detail);
    }, () => this.keeper.active(session, held.request.id)).finally(letGo);
    this.#audit(held.request, "run", a.command.slice(0, 500));
    return said(ran);
  }

  // ── commands on another station of the workspace ( 在另一台 station 上用) ──

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
  #elsewhere(on: { id: string; name: string }, request: Record<string, Json>, ms: number, used?: () => number | null): Promise<Json> {
    const ask = this.#d.ask;
    if (!ask) return Promise.reject(new Refused("this station does not reach the workspace's other stations"));
    const id = `x_${ulid(this.#d.now())}`;
    return new Promise<Json>((resolve, reject) => {
      // How long its end is waited for: the machine's time, as the command's own is on that station.
      const stop = wall.after(ms + 120_000, () => {
        if (this.#away.delete(id)) reject(new Refused(`${on.name} did not say how the command ended; it may still have run`));
      });
      this.#away.set(id, { station: on.id, done: (result) => (stop(), resolve(result)), ...(used ? { used } : {}), ...(typeof request.session === "string" ? { session: request.session } : {}), ...(typeof request.workspace === "string" ? { workspace: request.workspace } : {}) });
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
    if (held.grant.timeout) {
      const answer = await this.#d.ask?.(on.id, { method: "vault.capabilities", workspace: ws }).catch(() => null) as { timeouts?: unknown } | null | undefined;
      if (answer?.timeouts !== true) throw new Refused(`${on.name} needs an update before a timed grant can run there`);
    }
    const result = (await this.#elsewhere(on, {
      method: "vault.run", workspace: ws, session, grant: held.request.id, command: a.command, under: a.under, timeoutMs: a.timeoutMs,
      ...(a.env ? { env: a.env } : {}), mode: held.grant.mode, hosts: held.grant.hosts, secret: held.secret as unknown as Json,
      expires: held.until ?? held.grant.exp, ...(held.grant.timeout ? { grantTimeout: held.grant.timeout } : {}),
    }, a.timeoutMs, () => {
      if (!this.keeper.active(session, held.request.id)) return null;
      this.keeper.renew(session, held.request.id);
      return held.until ?? held.grant.exp;
    })) as Partial<Ran> | null;
    if (result === null || typeof result.output !== "string") throw new Refused(`${on.name} said nothing of how the command ended`);
    return { code: typeof result.code === "number" ? result.code : null, signal: typeof result.signal === "string" ? result.signal : null, output: result.output, cut: result.cut === true, timedOut: result.timedOut === true, used: result.used === true };
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
    if (method === "vault.used") {
      const away = this.#away.get(id);
      if (away === undefined || away.station !== peer || away.used === undefined) throw new Error("no such command sent to that station");
      return { until: away.used() };
    }
    if (method === "vault.done") {
      const away = this.#away.get(id);
      if (away === undefined || away.station !== peer) throw new Error("no such command sent to that station");
      this.#away.delete(id);
      away.done((r.result ?? null) as Json);
      return { ok: true };
    }
    // A command another station sends to run here: vault/incoming.ts (a rig runs those too, with no vault of its own).
    return this.#runs.heard(peer, ws, request);
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

function said(r: Ran): string {
  const end = r.timedOut ? "stopped: it ran too long" : r.code !== null ? `exit code ${r.code}` : `ended by ${r.signal}`;
  return `${end}${r.cut ? " (output cut in the middle)" : ""}\n${r.output}`;
}

export { Refused };
