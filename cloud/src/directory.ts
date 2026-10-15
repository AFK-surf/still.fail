// Who belongs where: users, workspaces, memberships, invitations and
// stations, in one SQLite-backed object so every change is a single
// transaction. Callers have already verified the account's access token;
// methods here check what that account may do in a workspace.
//
// It also holds the sockets that make this live (hibernatable, so idle ones
// cost nothing): each device's `/v1/events` socket, tagged `sub:<account>`,
// to which every change is pushed as the accounts it affects; and each
// station's socket, tagged `station:<id>`: what still.fail cloud tells the station
// (its name and workspace, the credential keys, what is revoked). Whether a
// station is up is not decided here: each device finds it out, reaching the
// station over the mesh.
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import { CODE_TTL_DAYS, isAdmin, newCode, normalizeCode } from "./admin";
import { digest, nowSeconds, randomSecret, type Identity } from "./auth";
import { header } from "./compat";
import type { Env } from "./env";
import { grantKeys } from "./grants";
import { langOf, type Lang } from "./i18n.ts";
import { MAX_RELAYS, parseRelays, relays, relayUrls, sameUrl } from "./relays";
import type { Part } from "./changelog";
import type { FeedbackInput } from "./feedback";
import type { AccountEvent, AddedView, Admission, AdminFeedback, AdminUser, AdminWorkspace, DeviceView, FeedbackStatus, InvitationView, InviteCodeView, LockHead, LockRequestView, MeView, MemberView, PendingInvitation, Role, StationView, UserView, WorkspaceSummary, WorkspaceView } from "./types";
import { asEntry, entryHash, shortCode, type LockEntry } from "./lock";
export type { Role };

export const ROLES: readonly Role[] = ["owner", "admin", "member"];
const MANAGERS: readonly Role[] = ["owner", "admin"];

export const INVITATION_TTL_SEC = 7 * 24 * 60 * 60;
export const ENROLLMENT_TTL_SEC = 60 * 60;
const LIMITS = { openInvitations: 50, pushPerUser: 32 };
/**
 * What an account may create, and what each workspace it created may hold (its creator counted among the people). Every
 * account is on the free plan: one workspace, just its creator, two stations. A code or the admin's say makes it
 * standard (#standard); the admin's own go up to the old bounds.
 */
export const PLANS = {
  free: { workspaces: 1, members: 1, stations: 2 },
  standard: { workspaces: 5, members: 6, stations: 64 },
  admin: { workspaces: 32, members: 200, stations: 64 },
} as const;
export type Plan = keyof typeof PLANS;

/** The events socket's subprotocols (api.ts socketToken), the new one first: clients from before the rename say "ember-events". */
export const EVENTS_PROTOCOLS = ["stillfail-events", "ember-events"] as const;
/** How long a revocation is kept and told: a day more than a credential lasts (grants.ts). */
const REVOCATION_DAYS = 31;

/** How often a station sends "ping" on its presence socket (the runtime answers "pong" without waking this object). */
export const PING_SEC = 30;
/** A station socket unanswered this long is taken for dead. */
export const SILENT_MS = 3 * PING_SEC * 1000;
/** Close codes a station acts on. */
export const CLOSE = { replaced: 4000, removed: 4004, silent: 4008 } as const;

/** Reports one sender may send in a day, and how many the console lists. */
const FEEDBACK_PER_DAY = 20;
const FEEDBACK_LISTED = 500;

const LIST: AccountEvent = { type: "workspaces" };
type Attachment = { station: string; at: number; dropped?: boolean } | { sub: string };

export class DirectoryError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}
const fail = (status: number, code: string): never => {
  throw new DirectoryError(status, code);
};

type Row = Record<string, SqlStorageValue>;

/** A device to push to, as registered (POST /v1/push). */
export type PushDevice = { kind: "web"; endpoint: string; p256dh: string; auth: string } | { kind: "fcm"; token: string };
/** A device registered, with the language its notifications are said in (Chinese for one registered before languages). */
export type PushRegistration = PushDevice & { id: string; lang: Lang };

export class Directory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS users (sub TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', picture TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, last_seen INTEGER, admitted TEXT, beta INTEGER);
      CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS members (workspace TEXT NOT NULL, sub TEXT NOT NULL, role TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, sub));
      CREATE INDEX IF NOT EXISTS members_by_user ON members (sub);
      CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, role TEXT NOT NULL, email TEXT, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS stations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, enrolled_at INTEGER NOT NULL, enrolled_by TEXT NOT NULL, last_seen INTEGER, version TEXT);
      CREATE TABLE IF NOT EXISTS enrollments (token_hash TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS revocations (workspace TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (workspace, kind, id));
      CREATE TABLE IF NOT EXISTS added (workspace TEXT NOT NULL, email TEXT NOT NULL, role TEXT NOT NULL, added_by TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, email));
      CREATE INDEX IF NOT EXISTS added_by_email ON added (email);
      CREATE TABLE IF NOT EXISTS invite_codes (code TEXT PRIMARY KEY, note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, revoked_at INTEGER, used_by TEXT, used_at INTEGER, workspace TEXT);
      CREATE TABLE IF NOT EXISTS push (id TEXT PRIMARY KEY, sub TEXT NOT NULL, sid TEXT NOT NULL, kind TEXT NOT NULL, endpoint TEXT, p256dh TEXT, auth TEXT, token TEXT, created INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS push_by_endpoint ON push (sub, endpoint);
      CREATE UNIQUE INDEX IF NOT EXISTS push_by_token ON push (sub, token);
      CREATE INDEX IF NOT EXISTS push_by_user ON push (sub, sid);
      CREATE TABLE IF NOT EXISTS feedback (id TEXT PRIMARY KEY, number INTEGER NOT NULL UNIQUE, key TEXT NOT NULL, channel TEXT NOT NULL, sender TEXT NOT NULL, station TEXT, workspace TEXT, account TEXT, title TEXT NOT NULL, body TEXT NOT NULL, area TEXT NOT NULL, reporter TEXT NOT NULL DEFAULT '', context TEXT, logs TEXT, status TEXT NOT NULL DEFAULT 'new', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS feedback_by_key ON feedback (sender, key);
      CREATE INDEX IF NOT EXISTS feedback_by_sender ON feedback (sender, created_at);
      CREATE TABLE IF NOT EXISTS migrations (name TEXT PRIMARY KEY, at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS lock_entries (workspace TEXT NOT NULL, seq INTEGER NOT NULL, hash TEXT NOT NULL, entry TEXT NOT NULL, PRIMARY KEY (workspace, seq));
      CREATE TABLE IF NOT EXISTS devices (workspace TEXT NOT NULL, sub TEXT NOT NULL, device TEXT NOT NULL, base TEXT, kind TEXT, label TEXT, first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL, PRIMARY KEY (workspace, sub, device));
      CREATE TABLE IF NOT EXISTS lock_requests (workspace TEXT NOT NULL, base TEXT NOT NULL, sub TEXT NOT NULL, request TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (workspace, base));
    `);
    // users had neither column before invite codes, nor beta (1: let into the test channel) before it, nor blocked (1:
    // the admin blocked the account; the account's own object is what keeps it out) before the console could block;
    // the table in production gains them here.
    const columns = new Set(this.#rows("PRAGMA table_info(users)").map((r) => r.name as string));
    for (const column of ["last_seen INTEGER", "admitted TEXT", "beta INTEGER", "blocked INTEGER"]) {
      if (!columns.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE users ADD COLUMN ${column}`);
    }
    // Nor had feedback where it was fixed (the changelog's version and parts, changelog.ts) and when its station was
    // told, before the changelog.
    const reported = new Set(this.#rows("PRAGMA table_info(feedback)").map((r) => r.name as string));
    for (const column of ["fixed_in INTEGER", "fixed_parts TEXT", "told_at INTEGER"]) {
      if (!reported.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE feedback ADD COLUMN ${column}`);
    }
    // Nor had workspaces relays of their own (a JSON array of URLs, null for none), before they could have.
    if (!this.#rows("PRAGMA table_info(workspaces)").some((r) => r.name === "relays")) this.#run("ALTER TABLE workspaces ADD COLUMN relays TEXT");
    // Nor did push keep a device's language, before there were languages.
    if (!this.#rows("PRAGMA table_info(push)").some((r) => r.name === "lang")) this.#run("ALTER TABLE push ADD COLUMN lang TEXT");
    // Nor had stations an emoji (one, picked in the settings; null for none), before they could have.
    if (!this.#rows("PRAGMA table_info(stations)").some((r) => r.name === "emoji")) this.#run("ALTER TABLE stations ADD COLUMN emoji TEXT");
    // Nor an icon (one of still.fail's, or a picture put up; shown before the emoji where it is known), before they could.
    if (!this.#rows("PRAGMA table_info(stations)").some((r) => r.name === "icon")) this.#run("ALTER TABLE stations ADD COLUMN icon TEXT");
    // Nor had workspaces a mark of their own (an emoji, an icon, as a station's), before they could; their first letter till then.
    const marked = new Set(this.#rows("PRAGMA table_info(workspaces)").map((r) => r.name as string));
    for (const column of ["emoji TEXT", "icon TEXT"]) {
      if (!marked.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE workspaces ADD COLUMN ${column}`);
    }
    this.migrateFreePlan();
  }

  /**
   * Before the free plan, having created a workspace was itself the right to create more; it is the standard plan's
   * now, so those who created one keep it as if the admin had said so. Once: creating on the free plan says 'free'.
   */
  protected migrateFreePlan(): void {
    if (this.#one("SELECT 1 AS x FROM migrations WHERE name = 'free-plan'")) return;
    this.ctx.storage.transactionSync(() => {
      this.#run(`UPDATE users SET admitted = 'granted' WHERE sub IN (SELECT created_by FROM workspaces)
        AND (admitted IS NULL OR admitted NOT IN ('code', 'granted')) AND NOT (admitted IS NULL AND sub IN (SELECT sub FROM members))`);
      this.#run("INSERT INTO migrations (name, at) VALUES ('free-plan', ?)", nowSeconds());
    });
  }

  #rows(query: string, ...args: SqlStorageValue[]): Row[] {
    return this.ctx.storage.sql.exec(query, ...args).toArray() as Row[];
  }
  #one(query: string, ...args: SqlStorageValue[]): Row | undefined {
    return this.#rows(query, ...args)[0];
  }
  #run(query: string, ...args: SqlStorageValue[]): void {
    this.ctx.storage.sql.exec(query, ...args);
  }

  /** The caller's role in a workspace; fails unless it has one of `allowed`. */
  #role(sub: string, workspace: string, allowed: readonly Role[] = ROLES): Role {
    const row = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, sub);
    if (!row) fail(404, "workspace_not_found");
    const role = row!.role as Role;
    if (!allowed.includes(role)) fail(403, "forbidden");
    return role;
  }

  // ── notifications ───────────────────────────────────────────────────────

  /** Pushes events to every open events socket of these accounts. */
  #tell(subs: Iterable<string>, ...events: AccountEvent[]): void {
    const frames = events.map((event) => JSON.stringify(event));
    for (const sub of new Set(subs)) {
      for (const ws of this.ctx.getWebSockets(`sub:${sub}`)) {
        for (const frame of frames) {
          try {
            ws.send(frame);
          } catch {
            // Closing already; its device reconnects and refetches.
          }
        }
      }
    }
  }

  #members(workspace: string): string[] {
    return this.#rows("SELECT sub FROM members WHERE workspace = ?", workspace).map((r) => r.sub as string);
  }

  /** Accounts signed in with this email (invitations are addressed by email). */
  #byEmail(email: string | null): string[] {
    return email ? this.#rows("SELECT sub FROM users WHERE lower(email) = lower(?)", email).map((r) => r.sub as string) : [];
  }

  /** Accounts with an open invitation to this workspace; they see its name. */
  #invitees(workspace: string): string[] {
    return this.#rows("SELECT u.sub FROM invitations i JOIN users u ON lower(u.email) = i.email WHERE i.workspace = ? AND i.expires_at > ?", workspace, nowSeconds()).map((r) => r.sub as string);
  }

  /**
   * A workspace changed: its members (and `also`) are told, with `workspaces`
   * too when what their lists show changed (a name, a role, a count).
   */
  #changed(workspace: string, list: boolean, also: Iterable<string> = []): void {
    for (const row of this.#rows("SELECT id FROM stations WHERE workspace = ?", workspace)) this.#sendState(row.id as string);
    const subs = [...this.#members(workspace), ...also];
    this.#tell(subs, ...(list ? [LIST] : []), { type: "workspace", id: workspace });
  }

  upsertUser(identity: Identity): void {
    const old = this.#one("SELECT email, name, picture FROM users WHERE sub = ?", identity.sub);
    this.#run(
      `INSERT INTO users (sub, email, name, picture, created_at, last_seen) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (sub) DO UPDATE SET email = excluded.email, name = excluded.name, picture = excluded.picture, last_seen = excluded.last_seen`,
      identity.sub, identity.email, identity.name, identity.picture, nowSeconds(), nowSeconds(),
    );
    this.#joinAdded(identity.sub, identity.email);
    if (!old || (old.email === identity.email && old.name === identity.name && old.picture === identity.picture)) return;
    // Members lists show them; invitations they sent show their name; a new email has other invitations.
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", identity.sub)) this.#changed(row.workspace as string, false);
    const invited = this.#rows("SELECT i.email FROM invitations i WHERE i.created_by = ? AND i.expires_at > ?", identity.sub, nowSeconds()).flatMap((r) => this.#byEmail(r.email as string));
    this.#tell([...invited, ...(old.email === identity.email ? [] : [identity.sub])], LIST);
  }

  /** An account whose email was added to workspaces: a member of each from now on. */
  #joinAdded(sub: string, email: string): void {
    const rows = this.#rows("SELECT workspace, role FROM added WHERE email = ?", email.toLowerCase());
    if (rows.length === 0) return;
    this.ctx.storage.transactionSync(() => {
      for (const row of rows) {
        this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?) ON CONFLICT (workspace, sub) DO NOTHING", row.workspace, sub, row.role, nowSeconds());
      }
      this.#run("DELETE FROM added WHERE email = ?", email.toLowerCase());
      this.#run("UPDATE users SET admitted = 'invitation' WHERE sub = ? AND admitted IS NULL", sub);
    });
    for (const row of rows) this.#changed(row.workspace as string, true);
  }

  /**
   * Adds people by email, no invitation to accept: those with an account are members at once, the others as soon as they
   * first sign in with that email. What each became: joined, added (waiting for a first sign-in), or already a member.
   */
  addMembers(sub: string, workspace: string, role: Role, emails: unknown): { joined: string[]; added: string[]; already: string[]; view: WorkspaceView } {
    const mine = this.#role(sub, workspace, MANAGERS);
    if (!ROLES.includes(role)) fail(400, "invalid_role");
    if (role === "owner" && mine !== "owner") fail(403, "forbidden");
    const given = Array.isArray(emails) ? emails : [];
    const wanted = [...new Set(given.map((e) => String(e).trim().toLowerCase()).filter(Boolean))];
    if (wanted.length === 0 || wanted.some((e) => !/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(e))) fail(400, "invalid_email");
    const joined: string[] = [];
    const added: string[] = [];
    const already: string[] = [];
    const cap = this.#memberCap(workspace);
    this.ctx.storage.transactionSync(() => {
      for (const email of wanted) {
        if (this.#one("SELECT 1 AS x FROM members m JOIN users u ON u.sub = m.sub WHERE m.workspace = ? AND lower(u.email) = ?", workspace, email)) {
          already.push(email);
          continue;
        }
        // An open invitation to this email, or its being added already, is replaced: its seat is this one.
        const replaces = this.#one(`SELECT (SELECT COUNT(*) FROM invitations WHERE workspace = ? AND email = ? AND expires_at > ?)
          + (SELECT COUNT(*) FROM added WHERE workspace = ? AND email = ?) AS n`, workspace, email, nowSeconds(), workspace, email)!.n as number;
        if (this.#seats(workspace, true) - replaces >= cap) fail(429, "too_many_members");
        // An invitation to the same email is replaced by being added.
        this.#run("DELETE FROM invitations WHERE workspace = ? AND email = ?", workspace, email);
        const accounts = this.#byEmail(email);
        if (accounts.length > 0) {
          for (const account of accounts) {
            this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?) ON CONFLICT (workspace, sub) DO NOTHING", workspace, account, role, nowSeconds());
            this.#run("UPDATE users SET admitted = 'invitation' WHERE sub = ? AND admitted IS NULL", account);
          }
          joined.push(email);
        } else {
          this.#run(`INSERT INTO added (workspace, email, role, added_by, added_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (workspace, email) DO UPDATE SET role = excluded.role, added_by = excluded.added_by`, workspace, email, role, sub, nowSeconds());
          added.push(email);
        }
      }
    });
    this.#changed(workspace, true, joined.flatMap((e) => this.#byEmail(e)));
    return { joined, added, already, view: this.workspace(sub, workspace) };
  }

  /** Takes back an email added but not signed in yet. */
  removeAdded(sub: string, workspace: string, email: string): WorkspaceView {
    this.#role(sub, workspace, MANAGERS);
    this.#run("DELETE FROM added WHERE workspace = ? AND email = ?", workspace, email.trim().toLowerCase());
    this.#changed(workspace, true);
    return this.workspace(sub, workspace);
  }

  me(sub: string): { user: MeView | null; workspaces: WorkspaceSummary[] } {
    const row = this.#one("SELECT sub, email, name, picture, beta FROM users WHERE sub = ?", sub);
    // beta only when set: clients from before it know no such field, and an account without it says nothing.
    const user = row ? { sub: row.sub as string, email: row.email as string, name: row.name as string, picture: row.picture as string, ...(row.beta ? { beta: true as const } : {}) } : undefined;
    const workspaces = this.#rows(`
      SELECT w.id, w.name, m.role, w.created_at,
        (SELECT COUNT(*) FROM stations s WHERE s.workspace = w.id) AS stations,
        (SELECT COUNT(*) FROM members x WHERE x.workspace = w.id) AS members, w.relays, w.emoji, w.icon
      FROM members m JOIN workspaces w ON w.id = m.workspace WHERE m.sub = ? ORDER BY w.created_at`, sub)
      .map(({ relays, emoji, icon, ...w }) => ({ ...w, relays: parseRelays(relays), ...marks(emoji, icon) })) as unknown as WorkspaceSummary[];
    return { user: user ?? null, workspaces };
  }

  /**
   * Anyone signed in may create a workspace on the free plan (PLANS.free.workspaces of them). The standard plan's are
   * the account's to earn: the admin's say, or a code (used up by the workspace it is redeemed with), or having been in
   * a workspace before codes existed. An account on the free plan that has used its free ones is asked for a code, and
   * redeeming it makes the account, and so every workspace it created, standard. Nothing here awaits, so two creations
   * with one code cannot both see it unused.
   */
  createWorkspace(sub: string, name: string, admin: boolean, code: unknown): WorkspaceView {
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    const made = this.#one("SELECT COUNT(*) AS n FROM workspaces WHERE created_by = ?", sub)!.n as number;
    const standard = admin || this.#standard(sub);
    const given = typeof code === "string" && code.trim() !== "";
    // A code given on the free plan is redeemed even while a free workspace is left: it is what the person asked for.
    const redeem = standard || (!given && made < PLANS.free.workspaces) ? null : this.#redeemable(code);
    if (made >= PLANS[admin ? "admin" : "standard"].workspaces) fail(429, "too_many_workspaces");
    const id = ulid();
    const now = nowSeconds();
    this.ctx.storage.transactionSync(() => {
      this.#run("INSERT INTO workspaces (id, name, created_by, created_at) VALUES (?, ?, ?, ?)", id, clean, sub, now);
      this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, 'owner', ?)", id, sub, now);
      if (redeem) {
        this.#run("UPDATE invite_codes SET used_by = ?, used_at = ?, workspace = ? WHERE code = ?", sub, now, id, redeem);
        this.#run("UPDATE users SET admitted = 'code' WHERE sub = ? AND (admitted IS NULL OR admitted IN ('invitation', 'free'))", sub);
      } else if (!standard) {
        // In a workspace, but not from before codes (#standard).
        this.#run("UPDATE users SET admitted = 'free' WHERE sub = ? AND (admitted IS NULL OR admitted = 'invitation')", sub);
      }
    });
    this.#tell([sub], LIST);
    return this.workspace(sub, id);
  }

  /** Whether an account is on the standard plan (the admin aside): see createWorkspace. */
  #standard(sub: string): boolean {
    return Boolean(this.#one(`SELECT 1 AS x FROM users WHERE sub = ? AND admitted IN ('code', 'granted')
      UNION ALL SELECT 1 FROM users u JOIN members m ON m.sub = u.sub WHERE u.sub = ? AND u.admitted IS NULL LIMIT 1`, sub, sub));
  }

  /** The plan a workspace is on: its creator's. */
  #plan(workspace: string): Plan {
    const creator = this.#one("SELECT u.sub, u.email FROM workspaces w JOIN users u ON u.sub = w.created_by WHERE w.id = ?", workspace);
    if (!creator) return "free";
    return isAdmin(this.env, creator.email as string) ? "admin" : this.#standard(creator.sub as string) ? "standard" : "free";
  }

  /** How many people a workspace may hold, its creator among them. */
  #memberCap(workspace: string): number {
    return PLANS[this.#plan(workspace)].members;
  }

  /** Who a workspace holds or has let in: members, emails added but not signed in yet, and, with `invited`, open invitations. */
  #seats(workspace: string, invited = false): number {
    return this.#one(`SELECT (SELECT COUNT(*) FROM members WHERE workspace = ?) + (SELECT COUNT(*) FROM added WHERE workspace = ?)
      + (CASE WHEN ? THEN (SELECT COUNT(*) FROM invitations WHERE workspace = ? AND expires_at > ?) ELSE 0 END) AS n`,
      workspace, workspace, invited ? 1 : 0, workspace, nowSeconds())!.n as number;
  }

  /** The stored form of a code that may be redeemed now; fails with why not. */
  #redeemable(value: unknown): string {
    if (typeof value !== "string" || !value.trim()) fail(403, "invite_code_required");
    const code = normalizeCode(value) ?? fail(404, "invite_code_invalid");
    const row = this.#one("SELECT expires_at, revoked_at, used_by FROM invite_codes WHERE code = ?", code);
    if (!row || row.revoked_at !== null) fail(404, "invite_code_invalid");
    if (row!.used_by !== null) fail(409, "invite_code_used");
    if ((row!.expires_at as number) <= nowSeconds()) fail(410, "invite_code_expired");
    return code;
  }

  workspace(sub: string, id: string): WorkspaceView {
    const role = this.#role(sub, id);
    const w = this.#one("SELECT id, name, created_at, relays, emoji, icon FROM workspaces WHERE id = ?", id)!;
    const members = this.#rows(`
      SELECT m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name, COALESCE(u.picture, '') AS picture, m.role, m.added_at
      FROM members m LEFT JOIN users u ON u.sub = m.sub WHERE m.workspace = ? ORDER BY m.added_at`, id) as unknown as MemberView[];
    const stations = this.#rows("SELECT id, name, emoji, icon, enrolled_at, enrolled_by, last_seen, version FROM stations WHERE workspace = ? ORDER BY enrolled_at", id) as unknown as StationView[];
    const invitations = MANAGERS.includes(role)
      ? this.#rows("SELECT id, role, email, created_by, expires_at FROM invitations WHERE workspace = ? AND expires_at > ? ORDER BY expires_at", id, nowSeconds()) as unknown as InvitationView[]
      : [];
    const added = MANAGERS.includes(role)
      ? this.#rows("SELECT email, role, added_by, added_at FROM added WHERE workspace = ? ORDER BY added_at", id) as unknown as AddedView[]
      : [];
    return { id, name: w.name as string, ...marks(w.emoji, w.icon), role, created_at: w.created_at as number, members, stations, invitations, added, relays: parseRelays(w.relays), lock: this.#lockHead(id), lock_requests: this.#lockRequestCount(id, sub, role) };
  }

  // ── the workspace lock (docs/workspace-lock.md, lock.ts): kept and carried, not trusted ─────────────────────────

  #lockHead(workspace: string): LockHead | null {
    const last = this.#one("SELECT seq, hash FROM lock_entries WHERE workspace = ? ORDER BY seq DESC LIMIT 1", workspace);
    if (!last) return null;
    const first = this.#one("SELECT hash FROM lock_entries WHERE workspace = ? AND seq = 0", workspace);
    return { seq: last.seq as number, hash: last.hash as string, genesis: (first?.hash as string) ?? "" };
  }

  /** How many devices wait to be confirmed, of those the caller sees (all for owners and admins, their own for others). */
  #lockRequestCount(workspace: string, sub: string, role: Role): number {
    return this.#one("SELECT COUNT(*) AS n FROM lock_requests WHERE workspace = ? AND (? OR sub = ?)", workspace, MANAGERS.includes(role) ? 1 : 0, sub)!.n as number;
  }

  #lockAfter(workspace: string, after: number): unknown[] {
    return this.#rows("SELECT entry FROM lock_entries WHERE workspace = ? AND seq > ? ORDER BY seq", workspace, after).map((r) => JSON.parse(r.entry as string));
  }

  /** The lock's head and its entries after `after`, for any member. */
  lock(sub: string, workspace: string, after: number): { head: LockHead | null; entries: unknown[] } {
    this.#role(sub, workspace);
    return { head: this.#lockHead(workspace), entries: this.#lockAfter(workspace, after) };
  }

  /**
   * Entries that follow the kept chain (those it has are skipped; one that disagrees is refused, with the rest). A
   * genesis starts a chain where there is none, or where the last one was turned off. Stations and members' devices
   * bring them; whether one is signed by whom it may be is not checked here: a station checks every entry itself.
   */
  async #appendLock(workspace: string, raw: unknown): Promise<LockHead | null> {
    const entries = (Array.isArray(raw) ? raw : []).map(asEntry);
    if (entries.length === 0 || entries.length > 256 || entries.some((e) => e === null || e.ws !== workspace)) fail(400, "invalid_lock_entries");
    // Hashed before anything is read: nothing else runs on this object between the reads and the writes below (no
    // await between them), so they are one step. What is refused throws before anything is written.
    const hashed = await Promise.all((entries as LockEntry[]).map(async (e) => ({ e, hash: await entryHash(e) })));
    let head = this.#lockHead(workspace);
    let lastKind = head ? (JSON.parse(this.#one("SELECT entry FROM lock_entries WHERE workspace = ? AND seq = ?", workspace, head.seq)!.entry as string) as LockEntry).kind : null;
    let restart = false;
    const adding: { e: LockEntry; hash: string }[] = [];
    for (const { e, hash } of hashed) {
      if (e.kind === "genesis" && e.seq === 0 && e.prev === null) {
        if (head?.genesis === hash) continue;
        if (head && lastKind !== "disable") fail(409, "lock_exists");
        restart = true;
        adding.length = 0;
      } else if (head && e.seq <= head.seq) {
        const had = adding.find((a) => a.e.seq === e.seq)?.hash ?? (restart ? undefined : (this.#one("SELECT hash FROM lock_entries WHERE workspace = ? AND seq = ?", workspace, e.seq)?.hash as string | undefined));
        if (had !== hash) fail(409, "lock_fork");
        continue;
      } else if (!head || e.seq !== head.seq + 1 || e.prev !== head.hash) fail(409, "lock_does_not_follow");
      adding.push({ e, hash });
      head = { seq: e.seq, hash, genesis: e.seq === 0 ? hash : head!.genesis };
      lastKind = e.kind;
    }
    if (adding.length > 0) {
      this.ctx.storage.transactionSync(() => {
        if (restart) this.#run("DELETE FROM lock_entries WHERE workspace = ?", workspace);
        for (const { e, hash } of adding) this.#run("INSERT INTO lock_entries (workspace, seq, hash, entry) VALUES (?, ?, ?, ?)", workspace, e.seq, hash, JSON.stringify(e));
      });
      this.#changed(workspace, false);
    }
    return this.#lockHead(workspace);
  }

  /** A member's device brings entries (its own signer's, or what a station had more). */
  async appendLock(sub: string, workspace: string, entries: unknown): Promise<{ head: LockHead | null }> {
    this.#role(sub, workspace);
    return { head: await this.#appendLock(workspace, entries) };
  }

  /** The owner lets the kept lock go (its signers lost: each station is reset on its own machine). */
  clearLock(sub: string, workspace: string): void {
    this.#role(sub, workspace, ["owner"]);
    this.#run("DELETE FROM lock_entries WHERE workspace = ?", workspace);
    this.#changed(workspace, false);
  }

  /** A device asked for a credential: kept for the owner to check when the lock is turned on. */
  recordDevice(sub: string, workspace: string, device: string, said: { base?: string; kind?: string; label?: string }): void {
    const now = nowSeconds();
    this.#run(
      `INSERT INTO devices (workspace, sub, device, base, kind, label, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (workspace, sub, device) DO UPDATE SET base = COALESCE(excluded.base, base), kind = COALESCE(excluded.kind, kind), label = COALESCE(excluded.label, label), last_seen = excluded.last_seen`,
      workspace, sub, device, said.base ?? null, said.kind ?? null, said.label ?? null, now, now,
    );
  }

  /** The devices that asked for credentials in the workspace in the last 31 days (its owners and admins). */
  devices(sub: string, workspace: string): { devices: DeviceView[] } {
    this.#role(sub, workspace, MANAGERS);
    const devices = this.#rows(
      `SELECT d.sub, COALESCE(u.email, '') AS email, d.device, d.base, d.kind, d.label, d.first_seen, d.last_seen FROM devices d LEFT JOIN users u ON u.sub = d.sub
        WHERE d.workspace = ? AND d.last_seen >= ? AND d.sub IN (SELECT sub FROM members WHERE workspace = ?) ORDER BY d.sub, d.last_seen DESC`,
      workspace, nowSeconds() - 31 * 86400, workspace,
    ) as unknown as DeviceView[];
    return { devices };
  }

  /** A member's new device asks to be confirmed into the lock: its owners and admins, and the member's other devices, are told. */
  async requestLock(sub: string, workspace: string, input: Record<string, unknown>): Promise<LockRequestView> {
    this.#role(sub, workspace);
    const base = typeof input.base === "string" && /^[0-9a-f]{64}$/.test(input.base) ? input.base : fail(400, "invalid_device");
    const kind = input.kind === "app" || input.kind === "web" ? input.kind : fail(400, "invalid_kind");
    const label = typeof input.label === "string" ? input.label.slice(0, 120) : "";
    const sign_key = typeof input.sign_key === "string" && input.sign_key.length <= 200 ? input.sign_key : null;
    const endpoints = Array.isArray(input.endpoints) ? input.endpoints.filter((e): e is string => typeof e === "string" && /^[0-9a-f]{64}$/.test(e)).slice(0, 16) : [];
    const code = await shortCode(base);
    const request = { kind, label, sign_key, endpoints };
    this.#run(
      "INSERT INTO lock_requests (workspace, base, sub, request, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (workspace, base) DO UPDATE SET sub = excluded.sub, request = excluded.request",
      workspace, base, sub, JSON.stringify(request), nowSeconds(),
    );
    this.#changed(workspace, false);
    return { base, sub, email: (this.#one("SELECT email FROM users WHERE sub = ?", sub)?.email as string) ?? "", ...request, code, created_at: nowSeconds() };
  }

  /** Devices waiting to be confirmed: all of them for owners and admins, a member's own for a member. */
  async lockRequests(sub: string, workspace: string): Promise<{ requests: LockRequestView[] }> {
    const role = this.#role(sub, workspace);
    const rows = this.#rows(
      `SELECT r.base, r.sub, COALESCE(u.email, '') AS email, r.request, r.created_at FROM lock_requests r LEFT JOIN users u ON u.sub = r.sub
        WHERE r.workspace = ? AND (? OR r.sub = ?) ORDER BY r.created_at`,
      workspace, MANAGERS.includes(role) ? 1 : 0, sub,
    );
    const requests = await Promise.all(rows.map(async (r) => ({ base: r.base as string, sub: r.sub as string, email: r.email as string, ...(JSON.parse(r.request as string) as { kind: string; label: string; sign_key: string | null; endpoints: string[] }), code: await shortCode(r.base as string), created_at: r.created_at as number })));
    return { requests };
  }

  /** A request answered (confirmed or turned down): gone from the list. Its member's own, or an owner's or admin's. */
  dropLockRequest(sub: string, workspace: string, base: string): void {
    const role = this.#role(sub, workspace);
    const row = this.#one("SELECT sub FROM lock_requests WHERE workspace = ? AND base = ?", workspace, base);
    if (!row) return;
    if (row.sub !== sub && !MANAGERS.includes(role)) fail(403, "forbidden");
    this.#run("DELETE FROM lock_requests WHERE workspace = ? AND base = ?", workspace, base);
    this.#changed(workspace, false);
  }

  /**
   * The workspace's own relays, used besides still.fail's by its stations (told in their state) and by its members'
   * devices (in `/v1/me`): https URLs (http too when the cloud itself is on http: a local setup), at most MAX_RELAYS,
   * still.fail's own left out. Whether one answers is not asked here: the cloud may be where it cannot be reached from
   * (one inside mainland China), and one that does not answer is passed over where it is measured.
   */
  setRelays(sub: string, id: string, input: unknown): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    if (!Array.isArray(input) || input.length > MAX_RELAYS) fail(400, "invalid_relays");
    const ours = relayUrls(this.env).map(sameUrl);
    const insecure = this.env.PUBLIC_ORIGIN.startsWith("http:");
    const list: string[] = [];
    for (const raw of input as unknown[]) {
      const url = typeof raw === "string" && URL.canParse(raw.trim()) ? new URL(raw.trim()) : null;
      if (!url || !(url.protocol === "https:" || (insecure && url.protocol === "http:")) || url.username || url.password || url.search || url.hash) fail(400, "invalid_relay");
      const clean = url!.href.replace(/\/+$/, "");
      if (!ours.includes(sameUrl(clean)) && !list.some((u) => sameUrl(u) === sameUrl(clean))) list.push(clean);
    }
    this.#run("UPDATE workspaces SET relays = ? WHERE id = ?", list.length ? JSON.stringify(list) : null, id);
    this.#changed(id, true);
    return this.workspace(sub, id);
  }

  /** A new name, a new emoji, a new icon (null or "" takes either away; a station's, cleanIcon), or several; what is not given stays. */
  updateWorkspace(sub: string, id: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    const name = input.name === undefined ? undefined : cleanName(input.name) ?? fail(400, "invalid_name");
    const emoji = input.emoji === undefined ? undefined : input.emoji === null || input.emoji === "" ? null : cleanEmoji(input.emoji) ?? fail(400, "invalid_emoji");
    const icon = input.icon === undefined ? undefined : input.icon === null || input.icon === "" ? null : cleanIcon(input.icon) ?? fail(400, "invalid_icon");
    if (name === undefined && emoji === undefined && icon === undefined) fail(400, "invalid_name");
    if (name !== undefined) this.#run("UPDATE workspaces SET name = ? WHERE id = ?", name, id);
    if (emoji !== undefined) this.#run("UPDATE workspaces SET emoji = ? WHERE id = ?", emoji, id);
    if (icon !== undefined) this.#run("UPDATE workspaces SET icon = ? WHERE id = ?", icon, id);
    // Invitations show the name; the switchers, the mark.
    this.#changed(id, true, name !== undefined ? this.#invitees(id) : []);
    return this.workspace(sub, id);
  }

  deleteWorkspace(sub: string, id: string): void {
    this.#role(sub, id, ["owner"]);
    const told = [...this.#members(id), ...this.#invitees(id)];
    const stations = this.#rows("SELECT id FROM stations WHERE workspace = ?", id).map((r) => r.id as string);
    this.ctx.storage.transactionSync(() => {
      for (const table of ["members", "invitations", "added", "stations", "enrollments", "lock_entries", "devices", "lock_requests"]) this.#run(`DELETE FROM ${table} WHERE workspace = ?`, id);
      this.#run("DELETE FROM workspaces WHERE id = ?", id);
    });
    this.#tell(told, LIST, { type: "workspace", id });
    for (const station of stations) this.#disconnect(station, CLOSE.removed, "station_removed");
  }

  // ── people ──────────────────────────────────────────────────────────────

  async invite(sub: string, workspace: string, role: Role, email: string | null): Promise<{ token: string; id: string; expires_at: number }> {
    const mine = this.#role(sub, workspace, MANAGERS);
    if (!ROLES.includes(role)) fail(400, "invalid_role");
    if (role === "owner" && mine !== "owner") fail(403, "forbidden");
    if (email === null || !/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(email)) fail(400, "invalid_email");
    if (this.#one("SELECT 1 AS x FROM members m JOIN users u ON u.sub = m.sub WHERE m.workspace = ? AND lower(u.email) = lower(?)", workspace, email!)) fail(409, "already_member");
    const open = this.#one("SELECT COUNT(*) AS n FROM invitations WHERE workspace = ? AND expires_at > ?", workspace, nowSeconds())!.n as number;
    if (open >= LIMITS.openInvitations) fail(429, "too_many_invitations");
    // Every open invitation holds a seat, but a newer one to the same email takes the older one's.
    const replaces = this.#one("SELECT 1 AS x FROM invitations WHERE workspace = ? AND email = ? AND expires_at > ?", workspace, email!.toLowerCase(), nowSeconds()) ? 1 : 0;
    if (this.#seats(workspace, true) - replaces >= this.#memberCap(workspace)) fail(429, "too_many_members");
    const token = randomSecret();
    const id = ulid();
    const expires = nowSeconds() + INVITATION_TTL_SEC;
    // A newer invitation for the same email replaces the older one.
    this.#run("DELETE FROM invitations WHERE workspace = ? AND email = ?", workspace, email!.toLowerCase());
    this.#run("INSERT INTO invitations (id, workspace, token_hash, role, email, created_by, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      id, workspace, await digest(token), role, email!.toLowerCase(), sub, expires);
    this.#changed(workspace, false);
    this.#tell(this.#byEmail(email), LIST);
    return { token, id, expires_at: expires };
  }

  /** What an invitation leads to, for the page that asks to accept it. */
  async previewInvitation(token: string): Promise<{ workspace: string; name: string; role: Role; inviter: string; email: string | null }> {
    const row = this.#one(`SELECT i.workspace, w.name, i.role, i.email, COALESCE(u.name, u.email, '') AS inviter FROM invitations i
      JOIN workspaces w ON w.id = i.workspace LEFT JOIN users u ON u.sub = i.created_by WHERE i.token_hash = ? AND i.expires_at > ?`, await digest(token), nowSeconds());
    if (!row) fail(404, "invitation_not_found");
    return { workspace: row!.workspace as string, name: row!.name as string, role: row!.role as Role, inviter: row!.inviter as string, email: (row!.email as string | null) ?? null };
  }

  async acceptInvitation(sub: string, email: string, token: string): Promise<WorkspaceView> {
    const hash = await digest(token);
    const row = this.#one("SELECT id, workspace, role, email FROM invitations WHERE token_hash = ? AND expires_at > ?", hash, nowSeconds());
    if (!row) fail(404, "invitation_not_found");
    if (row!.email && (row!.email as string) !== email.toLowerCase()) fail(403, "invitation_for_other_email");
    const workspace = row!.workspace as string;
    const existing = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, sub);
    if (!existing && this.#seats(workspace) >= this.#memberCap(workspace)) fail(429, "too_many_members");
    this.ctx.storage.transactionSync(() => {
      this.#run("DELETE FROM invitations WHERE id = ?", row!.id);
      // Accepting never lowers a role someone already has.
      this.#run("UPDATE users SET admitted = 'invitation' WHERE sub = ? AND admitted IS NULL", sub);
      if (!existing) this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?)", workspace, sub, row!.role, nowSeconds());
      else if (ROLES.indexOf(row!.role as Role) < ROLES.indexOf(existing.role as Role)) this.#run("UPDATE members SET role = ? WHERE workspace = ? AND sub = ?", row!.role, workspace, sub);
    });
    this.#changed(workspace, true);
    return this.workspace(sub, workspace);
  }

  /** Invitations waiting for this email: what someone sees right after signing in. */
  invitationsFor(email: string): PendingInvitation[] {
    return this.#rows(`SELECT i.id, i.workspace, w.name, i.role, COALESCE(NULLIF(u.name, ''), u.email, '') AS inviter, i.expires_at FROM invitations i
      JOIN workspaces w ON w.id = i.workspace LEFT JOIN users u ON u.sub = i.created_by
      WHERE i.email = ? AND i.expires_at > ? ORDER BY i.expires_at`, email.toLowerCase(), nowSeconds()) as unknown as PendingInvitation[];
  }

  /** Accepts an invitation addressed to this account's email, by id (no link needed). */
  acceptById(sub: string, email: string, id: string): WorkspaceView {
    const row = this.#one("SELECT id, workspace, role, email FROM invitations WHERE id = ? AND expires_at > ?", id, nowSeconds());
    if (!row) fail(404, "invitation_not_found");
    if ((row!.email as string | null) !== email.toLowerCase()) fail(403, "invitation_for_other_email");
    const workspace = row!.workspace as string;
    const existing = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, sub);
    if (!existing && this.#seats(workspace) >= this.#memberCap(workspace)) fail(429, "too_many_members");
    this.ctx.storage.transactionSync(() => {
      this.#run("DELETE FROM invitations WHERE id = ?", id);
      this.#run("UPDATE users SET admitted = 'invitation' WHERE sub = ? AND admitted IS NULL", sub);
      if (!existing) this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?)", workspace, sub, row!.role, nowSeconds());
    });
    this.#changed(workspace, true);
    return this.workspace(sub, workspace);
  }

  declineById(email: string, id: string): void {
    const row = this.#one("SELECT workspace FROM invitations WHERE id = ? AND email = ?", id, email.toLowerCase());
    if (!row) return;
    this.#run("DELETE FROM invitations WHERE id = ?", id);
    this.#changed(row.workspace as string, false);
    this.#tell(this.#byEmail(email), LIST);
  }

  revokeInvitation(sub: string, workspace: string, id: string): void {
    this.#role(sub, workspace, MANAGERS);
    const row = this.#one("SELECT email FROM invitations WHERE id = ? AND workspace = ?", id, workspace);
    if (!row) return;
    this.#run("DELETE FROM invitations WHERE id = ?", id);
    this.#changed(workspace, false);
    this.#tell(this.#byEmail(row.email as string | null), LIST);
  }

  setRole(sub: string, workspace: string, target: string, role: Role): WorkspaceView {
    this.#role(sub, workspace, ["owner"]);
    if (!ROLES.includes(role)) fail(400, "invalid_role");
    const current = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    if (!current) fail(404, "member_not_found");
    if (current!.role === "owner" && role !== "owner") this.#keepAnOwner(workspace);
    this.#run("UPDATE members SET role = ? WHERE workspace = ? AND sub = ?", role, workspace, target);
    // The credentials it holds name its old role: its stations take none of them from now on (it gets a new one).
    this.#revoke(workspace, "sub", target);
    this.#changed(workspace, false);
    this.#tell([target], LIST);
    return this.workspace(sub, workspace);
  }

  /** Removes a member; anyone may remove themselves (leave). */
  removeMember(sub: string, workspace: string, target: string): void {
    const mine = this.#role(sub, workspace);
    const row = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    if (!row) fail(404, "member_not_found");
    if (target !== sub) {
      if (!MANAGERS.includes(mine)) fail(403, "forbidden");
      if (row!.role === "owner" && mine !== "owner") fail(403, "forbidden");
    }
    if (row!.role === "owner") this.#keepAnOwner(workspace);
    this.#run("DELETE FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    this.#revoke(workspace, "sub", target);
    this.#changed(workspace, true, [target]);
  }

  #keepAnOwner(workspace: string): void {
    const owners = this.#one("SELECT COUNT(*) AS n FROM members WHERE workspace = ? AND role = 'owner'", workspace)!.n as number;
    if (owners <= 1) fail(409, "last_owner");
  }

  // ── stations ────────────────────────────────────────────────────────────

  async createEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    this.#role(sub, workspace, MANAGERS);
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    if (this.#stationsFull(workspace)) fail(429, "too_many_stations");
    const token = randomSecret();
    const expires = nowSeconds() + ENROLLMENT_TTL_SEC;
    this.#run("DELETE FROM enrollments WHERE expires_at <= ?", nowSeconds());
    this.#run("INSERT INTO enrollments (token_hash, workspace, name, created_by, expires_at) VALUES (?, ?, ?, ?, ?)", await digest(token), workspace, clean, sub, expires);
    return { token, expires_at: expires };
  }

  #stationsFull(workspace: string): boolean {
    const stations = this.#one("SELECT COUNT(*) AS n FROM stations WHERE workspace = ?", workspace)!.n as number;
    return stations >= PLANS[this.#plan(workspace)].stations;
  }

  /**
   * A station redeems an enrollment token. The caller has checked that the
   * station holds the key for `station`. Re-enrolling moves the station.
   */
  async enroll(token: string, station: string, version: string | null): Promise<{ workspace: string; workspace_name: string; name: string }> {
    const hash = await digest(token);
    const row = this.#one("SELECT workspace, name, created_by FROM enrollments WHERE token_hash = ? AND expires_at > ?", hash, nowSeconds());
    if (!row) fail(404, "enrollment_not_found");
    const moved = this.#one("SELECT workspace FROM stations WHERE id = ?", station)?.workspace as string | undefined;
    // Several tokens may be out at once: the last free place goes to the first redeemed.
    if (moved !== row!.workspace && this.#stationsFull(row!.workspace as string)) fail(429, "too_many_stations");
    this.ctx.storage.transactionSync(() => {
      this.#run("DELETE FROM enrollments WHERE token_hash = ?", hash);
      this.#run(`INSERT INTO stations (id, workspace, name, enrolled_at, enrolled_by, last_seen, version) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET workspace = excluded.workspace, name = excluded.name, enrolled_at = excluded.enrolled_at, enrolled_by = excluded.enrolled_by, last_seen = excluded.last_seen, version = excluded.version`,
        station, row!.workspace, row!.name, nowSeconds(), row!.created_by, nowSeconds(), version);
    });
    const w = this.#one("SELECT name FROM workspaces WHERE id = ?", row!.workspace)!;
    this.#changed(row!.workspace as string, true);
    if (moved && moved !== row!.workspace) this.#changed(moved, true);
    // Already connected (re-enrolled while running): it learns where it is now.
    this.#sendState(station);
    return { workspace: row!.workspace as string, workspace_name: w.name as string, name: row!.name as string };
  }

  /** A new name, a new emoji, a new icon (null or "" takes either away), or several; what is not given stays. */
  updateStation(sub: string, workspace: string, station: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    this.#role(sub, workspace, MANAGERS);
    const name = input.name === undefined ? undefined : cleanName(input.name) ?? fail(400, "invalid_name");
    const emoji = input.emoji === undefined ? undefined : input.emoji === null || input.emoji === "" ? null : cleanEmoji(input.emoji) ?? fail(400, "invalid_emoji");
    const icon = input.icon === undefined ? undefined : input.icon === null || input.icon === "" ? null : cleanIcon(input.icon) ?? fail(400, "invalid_icon");
    if (name === undefined && emoji === undefined && icon === undefined) fail(400, "invalid_name");
    if (name !== undefined) this.#run("UPDATE stations SET name = ? WHERE id = ? AND workspace = ?", name, station, workspace);
    if (emoji !== undefined) this.#run("UPDATE stations SET emoji = ? WHERE id = ? AND workspace = ?", emoji, station, workspace);
    if (icon !== undefined) this.#run("UPDATE stations SET icon = ? WHERE id = ? AND workspace = ?", icon, station, workspace);
    this.#changed(workspace, false);
    if (name !== undefined) this.#sendState(station);
    return this.workspace(sub, workspace);
  }

  removeStation(sub: string, workspace: string, station: string): void {
    this.#role(sub, workspace, MANAGERS);
    if (!this.#one("SELECT 1 AS x FROM stations WHERE id = ? AND workspace = ?", station, workspace)) return;
    this.#run("DELETE FROM stations WHERE id = ?", station);
    this.#changed(workspace, true);
    this.#disconnect(station, CLOSE.removed, "station_removed");
  }

  /** What a grant to reach `station` should say about the caller, if it may. */
  /** Whether a station is enrolled (in some workspace). */
  isStation(station: string): boolean {
    return this.#one("SELECT 1 AS found FROM stations WHERE id = ?", station) !== undefined;
  }

  /** A mstill.fail's role, which its credential names (grants.ts). */
  memberRole(sub: string, workspace: string): Role {
    return this.#role(sub, workspace);
  }

  // ── revocations ─────────────────────────────────────────────────────────
  // A mstill.fail's credential lasts 30 days and stations check it offline, so what takes one back is told to them: every
  // credential of an account (`sub`) or of a sign-in session (`sid`) issued up to `at` is refused from then on. Each
  // station hears it at once if connected, and all of its workspace's (of the last 31 days) when it connects.

  /** Takes back an account's credentials in a workspace, or one session's. */
  #revoke(workspace: string, kind: "sub" | "sid", id: string): void {
    const at = nowSeconds();
    this.#run("INSERT INTO revocations (workspace, kind, id, at) VALUES (?, ?, ?, ?) ON CONFLICT (workspace, kind, id) DO UPDATE SET at = excluded.at", workspace, kind, id, at);
    this.#run("DELETE FROM revocations WHERE at < ?", at - REVOCATION_DAYS * 86400);
    const frame = JSON.stringify({ type: "revoke", kind, id, at });
    for (const row of this.#rows("SELECT id FROM stations WHERE workspace = ?", workspace)) {
      for (const ws of this.#presence(row.id as string)) {
        try {
          ws.send(frame);
        } catch {
          // Closing already: it hears all of them when it connects again.
        }
      }
    }
  }

  /** Sessions signed out (all of an account's with none named): their credentials go, in every workspace of the account. */
  revokeSessions(sub: string, sids: string[] | null): void {
    if (sids === null) this.#run("DELETE FROM push WHERE sub = ?", sub);
    else for (const sid of sids) this.#run("DELETE FROM push WHERE sub = ? AND sid = ?", sub, sid);
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", sub)) {
      const workspace = row.workspace as string;
      if (sids === null) this.#revoke(workspace, "sub", sub);
      else for (const sid of sids) this.#revoke(workspace, "sid", sid);
    }
  }

  // ── push registrations (docs/notifications.md) ──────────────────────────
  // A device's push subscription (Web Push) or token (FCM) is registered with each account signed in on it, one row
  // each, which belongs to the sign-in session that registered it last; signing that session out takes it
  // (revokeSessions).

  /** Registers a device's push subscription or token to an account's session (moving it there from the account's other). */
  registerPush(sub: string, sid: string, device: PushDevice, lang: Lang = "zh"): void {
    const [column, value] = device.kind === "web" ? ["endpoint", device.endpoint] : ["token", device.token];
    this.#run(`DELETE FROM push WHERE sub = ? AND ${column} = ?`, sub, value);
    if (device.kind === "web") {
      this.#run("INSERT INTO push (id, sub, sid, kind, endpoint, p256dh, auth, created, lang) VALUES (?, ?, ?, 'web', ?, ?, ?, ?, ?)", ulid(), sub, sid, device.endpoint, device.p256dh, device.auth, nowSeconds(), lang);
    } else {
      this.#run("INSERT INTO push (id, sub, sid, kind, token, created, lang) VALUES (?, ?, ?, 'fcm', ?, ?, ?)", ulid(), sub, sid, device.token, nowSeconds(), lang);
    }
    // An account's oldest go past a few dozen devices.
    this.#run("DELETE FROM push WHERE sub = ? AND id NOT IN (SELECT id FROM push WHERE sub = ? ORDER BY id DESC LIMIT ?)", sub, sub, LIMITS.pushPerUser);
  }

  /** Takes a device's registration off an account (another account's is left alone). */
  unregisterPush(sub: string, device: { endpoint: string } | { token: string }): void {
    if ("endpoint" in device) this.#run("DELETE FROM push WHERE sub = ? AND endpoint = ?", sub, device.endpoint);
    else this.#run("DELETE FROM push WHERE sub = ? AND token = ?", sub, device.token);
  }

  /** Devices whose push service said they are gone: their registrations with every account. */
  dropPush(devices: PushDevice[]): void {
    for (const device of devices) {
      if (device.kind === "web") this.#run("DELETE FROM push WHERE endpoint = ?", device.endpoint);
      else this.#run("DELETE FROM push WHERE token = ?", device.token);
    }
  }

  /**
   * Where a station's notices go: its workspace, and for each email (lowercased) the registrations of the workspace's
   * members signed in with it. Null for a station not enrolled.
   */
  pushTargets(station: string, emails: string[]): { workspace: string; devices: Record<string, PushRegistration[]> } | null {
    const row = this.#one("SELECT workspace FROM stations WHERE id = ?", station);
    if (!row) return null;
    const workspace = row.workspace as string;
    const devices: Record<string, PushRegistration[]> = {};
    for (const email of new Set(emails.map((e) => e.toLowerCase()))) {
      devices[email] = this.#rows(
        `SELECT p.id, p.kind, p.endpoint, p.p256dh, p.auth, p.token, p.lang FROM push p JOIN users u ON u.sub = p.sub JOIN members m ON m.sub = p.sub AND m.workspace = ?
         WHERE lower(u.email) = ? ORDER BY p.id LIMIT ?`,
        workspace, email, LIMITS.pushPerUser,
      ).map((r): PushRegistration => {
        const lang = langOf(r.lang as string | null);
        return r.kind === "web" ? { id: r.id as string, lang, kind: "web", endpoint: r.endpoint as string, p256dh: r.p256dh as string, auth: r.auth as string } : { id: r.id as string, lang, kind: "fcm", token: r.token as string };
      });
    }
    return { workspace, devices };
  }

  // ── the admin's console ─────────────────────────────────────────────────
  // The caller has checked that the account is the admin's (admin.ts).

  adminUsers(): AdminUser[] {
    const memberships = new Map<string, AdminUser["workspaces"]>();
    for (const row of this.#rows("SELECT m.sub, w.id, w.name, m.role FROM members m JOIN workspaces w ON w.id = m.workspace ORDER BY w.created_at")) {
      const list = memberships.get(row.sub as string) ?? [];
      list.push({ id: row.id as string, name: row.name as string, role: row.role as Role });
      memberships.set(row.sub as string, list);
    }
    return this.#rows("SELECT sub, email, name, picture, created_at, last_seen, admitted, beta, blocked FROM users ORDER BY created_at DESC").map((row) => {
      const sub = row.sub as string;
      const workspaces = memberships.get(sub) ?? [];
      const admin = isAdmin(this.env, row.email as string);
      const admission: Admission | null = admin ? "admin" : (row.admitted as Admission | null) ?? (workspaces.length ? "early" : null);
      // As #standard has it, without a query per account.
      const mayCreate = admin || row.admitted === "code" || row.admitted === "granted" || (row.admitted === null && workspaces.length > 0);
      return {
        sub, email: row.email as string, name: row.name as string, picture: row.picture as string,
        created_at: row.created_at as number, last_seen: row.last_seen as number | null, admission, workspaces, beta: Boolean(row.beta),
        // creator: no longer keeps the standard plan by itself (#standard); false so the console lets it be taken back.
        may_create: mayCreate, plan: admin ? "admin" : mayCreate ? "standard" : "free", creator: false, blocked: Boolean(row.blocked),
      };
    });
  }

  /**
   * The admin puts an account on the standard plan, as a code would (`granted`), or back on the free one: `free` if it
   * created a workspace, `invitation` if it is only in others', or, in none, nothing. Its workspaces go with it (#plan);
   * what they hold beyond the free plan stays, only nothing more is let in.
   */
  setMayCreate(sub: string, on: boolean): { sub: string; may_create: boolean } {
    const row = this.#one("SELECT email FROM users WHERE sub = ?", sub);
    if (!row) fail(404, "user_not_found");
    if (on) this.#run("UPDATE users SET admitted = 'granted' WHERE sub = ? AND (admitted IS NULL OR admitted IN ('invitation', 'free'))", sub);
    else {
      const creator = this.#one("SELECT 1 AS x FROM workspaces WHERE created_by = ? LIMIT 1", sub);
      const member = this.#one("SELECT 1 AS x FROM members WHERE sub = ? LIMIT 1", sub);
      this.#run("UPDATE users SET admitted = ? WHERE sub = ?", creator ? "free" : member ? "invitation" : null, sub);
    }
    return { sub, may_create: isAdmin(this.env, row!.email as string) || this.#standard(sub) };
  }

  /** Notes that the admin blocked the account or let it back (the account's own object is what keeps it out). */
  setBlocked(sub: string, on: boolean): void {
    this.#run("UPDATE users SET blocked = ? WHERE sub = ?", on ? 1 : null, sub);
  }

  /** Lets an account into the test channel (BETA_ORIGIN), or out of it. */
  setBeta(sub: string, on: boolean): { sub: string; beta: boolean } {
    if (!this.#one("SELECT 1 AS x FROM users WHERE sub = ?", sub)) fail(404, "user_not_found");
    this.#run("UPDATE users SET beta = ? WHERE sub = ?", on ? 1 : null, sub);
    // Its `/v1/me` says so: its devices read it again (the 测试版 switch of its stations comes or goes at once).
    this.#tell([sub], LIST);
    return { sub, beta: on };
  }

  /** Whether the account may use the test channel. */
  isBeta(sub: string): boolean {
    return Boolean(this.#one("SELECT beta FROM users WHERE sub = ?", sub)?.beta);
  }

  /** The operator removes a workspace as its owner would (the admin token's route). */
  adminDeleteWorkspace(id: string): void {
    const owner = this.#one("SELECT sub FROM members WHERE workspace = ? AND role = 'owner' LIMIT 1", id);
    if (!owner) fail(404, "workspace_not_found");
    this.deleteWorkspace(owner!.sub as string, id);
  }

  adminWorkspaces(): AdminWorkspace[] {
    const now = nowSeconds();
    // Three reads for all of them, grouped here: a query per workspace grows with every one made.
    const group = <T>(rows: Row[]): Map<string, T[]> => {
      const by = new Map<string, T[]>();
      for (const { workspace, ...rest } of rows) {
        const list = by.get(workspace as string) ?? [];
        list.push(rest as T);
        by.set(workspace as string, list);
      }
      return by;
    };
    const members = group<AdminWorkspace["members"][number]>(this.#rows(`SELECT m.workspace, m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name,
      COALESCE(u.picture, '') AS picture, m.role, m.added_at, u.last_seen FROM members m LEFT JOIN users u ON u.sub = m.sub ORDER BY m.added_at`));
    const stations = group<StationView>(this.#rows("SELECT workspace, id, name, emoji, icon, enrolled_at, enrolled_by, last_seen, version FROM stations ORDER BY enrolled_at"));
    const invitations = group<AdminWorkspace["invitations"][number]>(this.#rows(`SELECT i.workspace, i.id, i.role, i.email, i.created_by, i.expires_at,
      COALESCE(NULLIF(u.name, ''), u.email, '') AS inviter FROM invitations i LEFT JOIN users u ON u.sub = i.created_by WHERE i.expires_at > ? ORDER BY i.expires_at`, now));
    // As #plan has it, in the same read.
    const plan = (w: Row): Plan => w.sub === null ? "free" : isAdmin(this.env, w.email as string) ? "admin"
      : w.admitted === "code" || w.admitted === "granted" || (w.admitted === null && w.member) ? "standard" : "free";
    return this.#rows(`SELECT w.id, w.name, w.created_at, u.sub, u.email, u.name AS user_name, u.picture, u.admitted,
      EXISTS (SELECT 1 FROM members m WHERE m.sub = u.sub) AS member FROM workspaces w
      LEFT JOIN users u ON u.sub = w.created_by ORDER BY w.created_at DESC`).map((w) => ({
      id: w.id as string,
      name: w.name as string,
      created_at: w.created_at as number,
      created_by: w.sub === null ? null : { sub: w.sub as string, email: w.email as string, name: w.user_name as string, picture: w.picture as string },
      members: members.get(w.id as string) ?? [],
      stations: stations.get(w.id as string) ?? [],
      invitations: invitations.get(w.id as string) ?? [],
      seats: PLANS[plan(w)].members,
      plan: plan(w),
    }));
  }

  inviteCodes(): InviteCodeView[] {
    return this.#rows(`SELECT c.code, c.note, c.created_at, c.expires_at, c.revoked_at, c.used_at, u.sub, u.email, u.name, u.picture, w.id, w.name AS workspace_name
      FROM invite_codes c LEFT JOIN users u ON u.sub = c.used_by LEFT JOIN workspaces w ON w.id = c.workspace ORDER BY c.created_at DESC, c.code`).map((row) => ({
      code: row.code as string,
      note: row.note as string,
      created_at: row.created_at as number,
      expires_at: row.expires_at as number,
      revoked_at: row.revoked_at as number | null,
      used_at: row.used_at as number | null,
      used_by: row.sub === null ? null : { sub: row.sub as string, email: row.email as string, name: row.name as string, picture: row.picture as string },
      workspace: row.id === null ? null : { id: row.id as string, name: row.workspace_name as string },
    }));
  }

  createInviteCode(sub: string, note: unknown, days: unknown): InviteCodeView {
    const clean = typeof note === "string" ? note.trim().replace(/\s+/g, " ") : "";
    if (clean.length > 200) fail(400, "invalid_note");
    const ttl = days === undefined ? CODE_TTL_DAYS : Number.isInteger(days) && (days as number) >= 1 && (days as number) <= 365 ? (days as number) : fail(400, "invalid_expiry");
    const code = newCode();
    const now = nowSeconds();
    this.#run("INSERT INTO invite_codes (code, note, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?)", code, clean, sub, now, now + ttl * 24 * 60 * 60);
    return this.inviteCodes().find((c) => c.code === code)!;
  }

  /** Stops an unused code from being redeemed; a used one has done its work and stays as it is. */
  revokeInviteCode(value: string): void {
    const code = normalizeCode(value) ?? fail(404, "invite_code_invalid");
    const row = this.#one("SELECT used_by FROM invite_codes WHERE code = ?", code);
    if (!row) fail(404, "invite_code_invalid");
    if (row!.used_by !== null) fail(409, "invite_code_used");
    this.#run("UPDATE invite_codes SET revoked_at = COALESCE(revoked_at, ?) WHERE code = ?", nowSeconds(), code);
  }

  // ── bug reports (feedback.ts) ───────────────────────────────────────────

  /** Keeps a report; the same sender's same key again is the one kept. null: the sender sent too many today. */
  addFeedback(input: FeedbackInput): { id: string; number: number; duplicate: boolean } | null {
    const kept = this.#one("SELECT id, number FROM feedback WHERE sender = ? AND key = ?", input.sender, input.key);
    if (kept) return { id: kept.id as string, number: kept.number as number, duplicate: true };
    const now = nowSeconds();
    const today = this.#one("SELECT COUNT(*) AS n FROM feedback WHERE sender = ? AND created_at > ?", input.sender, now - 24 * 60 * 60);
    if ((today?.n as number) >= FEEDBACK_PER_DAY) return null;
    const workspace = input.station ? ((this.#one("SELECT workspace FROM stations WHERE id = ?", input.station)?.workspace as string | undefined) ?? null) : null;
    const number = ((this.#one("SELECT MAX(number) AS n FROM feedback")?.n as number | null) ?? 0) + 1;
    const id = ulid();
    this.#run(
      `INSERT INTO feedback (id, number, key, channel, sender, station, workspace, account, title, body, area, reporter, context, logs, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?, ?)`,
      id, number, input.key, input.channel, input.sender, input.station, workspace, input.account, input.title, input.body, input.area, input.reporter, input.context, input.logs, now, now,
    );
    return { id, number, duplicate: false };
  }

  /** The reports, newest first, with the station, workspace and account they came from. */
  adminFeedback(): AdminFeedback[] {
    const rows = this.#rows(`SELECT f.*, s.name AS station_name, w.name AS workspace_name, u.email AS account_email, u.name AS account_name
      FROM feedback f LEFT JOIN stations s ON s.id = f.station LEFT JOIN workspaces w ON w.id = f.workspace LEFT JOIN users u ON u.sub = f.account
      ORDER BY f.number DESC LIMIT ${FEEDBACK_LISTED}`);
    return rows.map((r) => {
      let context: Record<string, unknown> | null = null;
      try {
        context = r.context ? (JSON.parse(r.context as string) as Record<string, unknown>) : null;
      } catch {
        // Cut at its limit: shown as it came.
        context = { text: r.context };
      }
      return {
        id: r.id as string,
        number: r.number as number,
        channel: r.channel === "beta" ? "beta" : "stable",
        station: r.station ? { id: r.station as string, name: (r.station_name as string | null) ?? "" } : null,
        workspace: r.workspace ? { id: r.workspace as string, name: (r.workspace_name as string | null) ?? "" } : null,
        account: r.account ? { sub: r.account as string, email: (r.account_email as string | null) ?? "", name: (r.account_name as string | null) ?? "" } : null,
        title: r.title as string,
        body: r.body as string,
        area: r.area as AdminFeedback["area"],
        reporter: r.reporter as string,
        context,
        logs: (r.logs as string | null) ?? null,
        status: r.status as FeedbackStatus,
        fixed_in: (r.fixed_in as number | null) ?? null,
        told_at: (r.told_at as number | null) ?? null,
        created_at: r.created_at as number,
        updated_at: r.updated_at as number,
      };
    });
  }

  setFeedbackStatus(id: string, status: FeedbackStatus): void {
    if (!this.#one("SELECT 1 AS found FROM feedback WHERE id = ?", id)) fail(404, "feedback_not_found");
    this.#run("UPDATE feedback SET status = ?, updated_at = ? WHERE id = ?", status, nowSeconds(), id);
  }

  /**
   * Marks the reports the changelog says are fixed (newest entry first): the version and parts of the latest fix of
   * each, until its station is told; one the team marked won't fix stays so.
   */
  markFixed(fixes: { number: number; version: number; parts: string[] }[]): void {
    const now = nowSeconds();
    for (const { number, version, parts } of fixes) {
      this.#run(
        `UPDATE feedback SET fixed_in = ?, fixed_parts = ?, status = CASE WHEN status = 'wontfix' THEN status ELSE 'fixed' END, updated_at = ?
         WHERE number = ? AND told_at IS NULL AND (fixed_in IS NULL OR fixed_in < ?)`,
        version, JSON.stringify(parts), now, number, version,
      );
    }
  }

  /** A station's reports that are fixed and it has not told of yet, with where it reported each. */
  fixedUntold(station: string): { id: string; number: number; title: string; channel: "stable" | "beta"; version: number; parts: Part[]; session: string | null; thread: string | null }[] {
    return this.#rows("SELECT id, number, title, channel, fixed_in, fixed_parts, context FROM feedback WHERE station = ? AND fixed_in IS NOT NULL AND told_at IS NULL AND status = 'fixed' ORDER BY number", station).map((r) => {
      let context: Record<string, unknown> = {};
      let parts: Part[] = [];
      try {
        context = JSON.parse((r.context as string | null) ?? "{}") as Record<string, unknown>;
      } catch {
        // Cut at its limit: no session to tell.
      }
      try {
        parts = JSON.parse((r.fixed_parts as string | null) ?? "[]") as Part[];
      } catch {
        parts = [];
      }
      const said = (v: unknown) => (typeof v === "string" && v ? v : null);
      return { id: r.id as string, number: r.number as number, title: r.title as string, channel: r.channel === "beta" ? "beta" : "stable", version: r.fixed_in as number, parts, session: said(context.session), thread: said(context.thread) };
    });
  }

  /** The station has told these of its reports' fixes. */
  toldFixed(station: string, ids: string[]): void {
    const now = nowSeconds();
    for (const id of ids) this.#run("UPDATE feedback SET told_at = ? WHERE id = ? AND station = ? AND fixed_in IS NOT NULL AND told_at IS NULL", now, id, station);
  }

  // ── sockets ─────────────────────────────────────────────────────────────

  /**
   * Upgrades reach here only through the Worker, which has authenticated
   * them: `/events` names the account in `x-stillfail-sub` (and the
   * subprotocol to select in `x-stillfail-protocol`), `/stations/connect` the
   * station (whose signature it checked) in `x-stillfail-station`. (The
   * x-ember-* ones are read too: a Worker from before the rename may still be
   * passing a request on while this object already runs the new code.)
   */
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    const pair = new WebSocketPair();
    if (path === "/events") {
      const sub = header(request, "sub")!;
      // Every device opens this when it starts: the nearest thing to "last seen" that costs no write per request.
      this.#run("UPDATE users SET last_seen = ? WHERE sub = ?", nowSeconds(), sub);
      this.ctx.acceptWebSocket(pair[1], [`sub:${sub}`]);
      pair[1].serializeAttachment({ sub } satisfies Attachment);
      return new Response(null, { status: 101, webSocket: pair[0], headers: { "sec-websocket-protocol": header(request, "protocol") ?? EVENTS_PROTOCOLS[1] } });
    }
    const station = header(request, "station")!;
    const row = this.#one("SELECT workspace FROM stations WHERE id = ?", station);
    if (!row) return Response.json({ error: "station_removed" }, { status: 404 });
    // One socket per station: a reconnect replaces the one it gave up on.
    for (const old of this.#presence(station)) this.#drop(old, CLOSE.replaced, "replaced");
    this.#run("UPDATE stations SET last_seen = ?, version = COALESCE(?, version) WHERE id = ?", nowSeconds(), header(request, "version"), station);
    this.ctx.acceptWebSocket(pair[1], [`station:${station}`]);
    pair[1].serializeAttachment({ station, at: Date.now() } satisfies Attachment);
    this.#sendState(station);
    if ((await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + SILENT_MS);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  /** The open presence sockets of a station (at most one, but a replaced one may linger). */
  #presence(station: string): WebSocket[] {
    return this.ctx.getWebSockets(`station:${station}`).filter((ws) => ws.readyState === WebSocket.OPEN && !(ws.deserializeAttachment() as { dropped?: boolean }).dropped);
  }

  /** Closes a socket from this side; its close event then changes nothing. */
  #drop(ws: WebSocket, code: number, reason: string): void {
    ws.serializeAttachment({ ...(ws.deserializeAttachment() as Attachment), dropped: true });
    try {
      ws.close(code, reason);
    } catch {
      // Already closed.
    }
  }

  #disconnect(station: string, code: number, reason: string): void {
    for (const ws of this.#presence(station)) this.#drop(ws, code, reason);
  }

  /** Where a station is and what it is called, and the cloud's own addresses as it has them now (a station enrolled
   * under an old host follows them: its links then use the new one); sent on connect and when that changes. */
  #sendState(station: string): void {
    const sockets = this.#presence(station);
    if (!sockets.length) return;
    const found = this.#one("SELECT s.workspace, w.name AS workspace_name, s.name, w.relays FROM stations s JOIN workspaces w ON w.id = s.workspace WHERE s.id = ?", station);
    if (!found) return;
    const { relays: own, ...row } = found;
    const revocations = this.#rows("SELECT kind, id, at FROM revocations WHERE workspace = ? AND at >= ?", row.workspace as string, nowSeconds() - REVOCATION_DAYS * 86400);
    const peers = this.#rows("SELECT id, name, version FROM stations WHERE workspace = ? ORDER BY enrolled_at", row.workspace as string);
    // The workspace's own relays after still.fail's: a station from before them keeps one more relay as it keeps the rest.
    const told = relays(this.env);
    const relay_urls = [...told.relay_urls, ...parseRelays(own).filter((u) => !told.relay_urls.map(sameUrl).includes(sameUrl(u)))];
    const lock = this.#lockHead(row.workspace as string);
    const frame = JSON.stringify({ type: "state", peers, ...row, origin: this.env.PUBLIC_ORIGIN, ...told, relay_urls, grant_keys: grantKeys(this.env), revocations, lock });
    for (const ws of sockets) ws.send(frame);
  }

  #offline(station: string): void {
    if (this.#presence(station).length) return;
    this.#run("UPDATE stations SET last_seen = ? WHERE id = ?", nowSeconds(), station);
  }

  /** "ping" is answered by the runtime; a station speaks otherwise only of the workspace lock: it asks for entries it
   * lacks (`lock.get {after}`, answered `{type: "lock", entries}`) or brings ones the cloud lacks (`lock.put`). */
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = ws.deserializeAttachment() as Attachment;
    if (typeof message !== "string" || !("station" in attachment)) return;
    let body: { type?: unknown; after?: unknown; entries?: unknown };
    try {
      body = JSON.parse(message);
    } catch {
      return;
    }
    const workspace = this.#one("SELECT workspace FROM stations WHERE id = ?", attachment.station)?.workspace as string | undefined;
    if (!workspace) return;
    if (body.type === "lock.get") {
      ws.send(JSON.stringify({ type: "lock", entries: this.#lockAfter(workspace, Number.isSafeInteger(body.after) ? (body.after as number) : -1) }));
    } else if (body.type === "lock.put") {
      // Refused when it does not follow: the station hears the cloud's head in the state frame and asks again.
      await this.#appendLock(workspace, body.entries).catch(() => this.#sendState(attachment.station));
    }
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    const attachment = ws.deserializeAttachment() as Attachment;
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code);
    } catch {
      // The runtime completed the close.
    }
    if ("station" in attachment && !attachment.dropped) this.#offline(attachment.station);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    const attachment = ws.deserializeAttachment() as Attachment;
    if ("station" in attachment && !attachment.dropped) this.#offline(attachment.station);
  }

  // A station that vanishes without closing (power cut, network gone) can
  // leave a socket the runtime keeps for a long time. Stations send "ping"
  // every PING_SEC and the runtime answers without waking this object,
  // recording when; while any station is connected an alarm looks at those
  // times every SILENT_MS and drops the silent ones. That is one wake-up per
  // interval however many stations there are — pinging from here would wake
  // the object for every ping, and without the check a vanished station would
  // show online until the runtime happened to notice.
  async alarm(): Promise<void> {
    if (this.sweep(Date.now())) await this.ctx.storage.setAlarm(Date.now() + SILENT_MS);
  }

  /** Drops station sockets silent at `now`; says whether any station is still connected. */
  protected sweep(now: number): boolean {
    let connected = false;
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as Attachment;
      if (!("station" in attachment) || attachment.dropped || ws.readyState !== WebSocket.OPEN) continue;
      const answered = this.ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? 0;
      if (now - Math.max(attachment.at, answered) > SILENT_MS) {
        this.#drop(ws, CLOSE.silent, "silent");
        this.#offline(attachment.station);
      } else connected = true;
    }
    return connected;
  }
}

function cleanName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim().replace(/\s+/g, " ");
  return clean && clean.length <= 80 ? clean : null;
}

/**
 * A station's icon: one of still.fail's by its name (`glyph:rocket`, design/station-icons; a name a client does not know
 * falls back to the emoji), which may be given a colour (`glyph:rocket:blue`; the clients know which), or a small picture
 * put up, as a data URL the clients made (96px, a few KB); else null.
 */
function cleanIcon(value: unknown): string | null {
  if (typeof value !== "string") return null;
  if (/^glyph:[a-z0-9-]{1,40}(:[a-z]{1,16})?$/.test(value)) return value;
  return value.length <= ICON_BYTES && /^data:image\/(png|webp|jpeg);base64,[A-Za-z0-9+/]+={0,2}$/.test(value) ? value : null;
}
/** A workspace's emoji and icon as its views carry them: each only when set (clients from before them know neither). */
function marks(emoji: unknown, icon: unknown): { emoji?: string; icon?: string } {
  return { ...(emoji ? { emoji: emoji as string } : {}), ...(icon ? { icon: icon as string } : {}) };
}
/** How long a picture's data URL may be: it goes to every member with the workspace. */
const ICON_BYTES = 48_000;

/** One emoji, as a person sees one (a flag, a family, a skin tone are one): the first, else null. */
function cleanEmoji(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const first = [...new Intl.Segmenter().segment(value.trim())][0]?.segment;
  return first && first.length <= 32 && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(first) ? first : null;
}
