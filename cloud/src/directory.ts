// Who belongs where: users, workspaces, memberships, invitations and
// stations, in one SQLite-backed object so every change is a single
// transaction. Callers have already verified the account's access token;
// methods here check what that account may do in a workspace.
//
// It also holds the sockets that make this live (hibernatable, so idle ones
// cost nothing): each device's `/v1/events` socket, tagged `sub:<account>`,
// to which every change is pushed as the accounts it affects; and each
// station's presence socket, tagged `station:<id>` — open is online.
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import { CODE_TTL_DAYS, isAdmin, newCode, normalizeCode } from "./admin";
import { digest, nowSeconds, randomSecret, type Identity } from "./auth";
import type { Env } from "./env";
import { grantKeys } from "./grants";
import type { AccountEvent, Admission, AdminUser, AdminWorkspace, InvitationView, InviteCodeView, MemberView, PendingInvitation, Role, StationView, UserView, WorkspaceSummary, WorkspaceView } from "./types";
export type { Role };

export const ROLES: readonly Role[] = ["owner", "admin", "member"];
const MANAGERS: readonly Role[] = ["owner", "admin"];

export const INVITATION_TTL_SEC = 7 * 24 * 60 * 60;
export const ENROLLMENT_TTL_SEC = 60 * 60;
const LIMITS = { workspacesPerUser: 32, membersPerWorkspace: 200, stationsPerWorkspace: 64, openInvitations: 50 };

export const EVENTS_PROTOCOL = "ember-events";
/** How often a station sends "ping" on its presence socket (the runtime answers "pong" without waking this object). */
export const PING_SEC = 30;
/** A station socket unanswered this long is taken for dead. */
export const SILENT_MS = 3 * PING_SEC * 1000;
/** Close codes a station acts on. */
export const CLOSE = { replaced: 4000, removed: 4004, silent: 4008 } as const;

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

export class Directory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS users (sub TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', picture TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, last_seen INTEGER, admitted TEXT);
      CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS members (workspace TEXT NOT NULL, sub TEXT NOT NULL, role TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, sub));
      CREATE INDEX IF NOT EXISTS members_by_user ON members (sub);
      CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, role TEXT NOT NULL, email TEXT, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS stations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, enrolled_at INTEGER NOT NULL, enrolled_by TEXT NOT NULL, last_seen INTEGER, version TEXT);
      CREATE TABLE IF NOT EXISTS enrollments (token_hash TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS invite_codes (code TEXT PRIMARY KEY, note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, revoked_at INTEGER, used_by TEXT, used_at INTEGER, workspace TEXT);
    `);
    // users had neither column before invite codes; the table in production gains them here.
    const columns = new Set(this.#rows("PRAGMA table_info(users)").map((r) => r.name as string));
    for (const column of ["last_seen INTEGER", "admitted TEXT"]) {
      if (!columns.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE users ADD COLUMN ${column}`);
    }
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
    if (!old || (old.email === identity.email && old.name === identity.name && old.picture === identity.picture)) return;
    // Members lists show them; invitations they sent show their name; a new email has other invitations.
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", identity.sub)) this.#changed(row.workspace as string, false);
    const invited = this.#rows("SELECT i.email FROM invitations i WHERE i.created_by = ? AND i.expires_at > ?", identity.sub, nowSeconds()).flatMap((r) => this.#byEmail(r.email as string));
    this.#tell([...invited, ...(old.email === identity.email ? [] : [identity.sub])], LIST);
  }

  me(sub: string): { user: UserView | null; workspaces: WorkspaceSummary[] } {
    const user = this.#one("SELECT sub, email, name, picture FROM users WHERE sub = ?", sub) as unknown as UserView | undefined;
    const workspaces = this.#rows(`
      SELECT w.id, w.name, m.role, w.created_at,
        (SELECT COUNT(*) FROM stations s WHERE s.workspace = w.id) AS stations,
        (SELECT COUNT(*) FROM members x WHERE x.workspace = w.id) AS members
      FROM members m JOIN workspaces w ON w.id = m.workspace WHERE m.sub = ? ORDER BY w.created_at`, sub) as unknown as WorkspaceSummary[];
    return { user: user ?? null, workspaces };
  }

  /**
   * ember is invite-only: the admin may create workspaces, and so may anyone
   * let in before — through an invitation they accepted or a code they
   * redeemed (or, from before codes existed, by being a member somewhere).
   * Anyone else redeems a code, which is used up by this workspace. Nothing
   * here awaits, so two creations with one code cannot both see it unused.
   */
  createWorkspace(sub: string, name: string, admin: boolean, code: unknown): WorkspaceView {
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    const owned = this.#one("SELECT COUNT(*) AS n FROM members WHERE sub = ? AND role = 'owner'", sub)!.n as number;
    if (owned >= LIMITS.workspacesPerUser) fail(429, "too_many_workspaces");
    const redeem = admin || this.#admitted(sub) ? null : this.#redeemable(code);
    const id = ulid();
    const now = nowSeconds();
    this.ctx.storage.transactionSync(() => {
      this.#run("INSERT INTO workspaces (id, name, created_by, created_at) VALUES (?, ?, ?, ?)", id, clean, sub, now);
      this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, 'owner', ?)", id, sub, now);
      if (redeem) {
        this.#run("UPDATE invite_codes SET used_by = ?, used_at = ?, workspace = ? WHERE code = ?", sub, now, id, redeem);
        this.#run("UPDATE users SET admitted = 'code' WHERE sub = ? AND admitted IS NULL", sub);
      }
    });
    this.#tell([sub], LIST);
    return this.workspace(sub, id);
  }

  #admitted(sub: string): boolean {
    return Boolean(this.#one("SELECT 1 AS x FROM users WHERE sub = ? AND admitted IS NOT NULL UNION ALL SELECT 1 FROM members WHERE sub = ? LIMIT 1", sub, sub));
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
    const w = this.#one("SELECT id, name, created_at FROM workspaces WHERE id = ?", id)!;
    const members = this.#rows(`
      SELECT m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name, COALESCE(u.picture, '') AS picture, m.role, m.added_at
      FROM members m LEFT JOIN users u ON u.sub = m.sub WHERE m.workspace = ? ORDER BY m.added_at`, id) as unknown as MemberView[];
    const stations = this.#rows("SELECT id, name, enrolled_at, enrolled_by, last_seen, version FROM stations WHERE workspace = ? ORDER BY enrolled_at", id)
      .map((row) => ({ ...row, online: this.#presence(row.id as string).length > 0 })) as unknown as StationView[];
    const invitations = MANAGERS.includes(role)
      ? this.#rows("SELECT id, role, email, created_by, expires_at FROM invitations WHERE workspace = ? AND expires_at > ? ORDER BY expires_at", id, nowSeconds()) as unknown as InvitationView[]
      : [];
    return { id, name: w.name as string, role, created_at: w.created_at as number, members, stations, invitations };
  }

  renameWorkspace(sub: string, id: string, name: string): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    this.#run("UPDATE workspaces SET name = ? WHERE id = ?", cleanName(name) ?? fail(400, "invalid_name"), id);
    this.#changed(id, true, this.#invitees(id));
    for (const row of this.#rows("SELECT id FROM stations WHERE workspace = ?", id)) this.#sendState(row.id as string);
    return this.workspace(sub, id);
  }

  deleteWorkspace(sub: string, id: string): void {
    this.#role(sub, id, ["owner"]);
    const told = [...this.#members(id), ...this.#invitees(id)];
    const stations = this.#rows("SELECT id FROM stations WHERE workspace = ?", id).map((r) => r.id as string);
    this.ctx.storage.transactionSync(() => {
      for (const table of ["members", "invitations", "stations", "enrollments"]) this.#run(`DELETE FROM ${table} WHERE workspace = ?`, id);
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
    const count = this.#one("SELECT COUNT(*) AS n FROM members WHERE workspace = ?", workspace)!.n as number;
    const existing = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, sub);
    if (!existing && count >= LIMITS.membersPerWorkspace) fail(429, "too_many_members");
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
    const count = this.#one("SELECT COUNT(*) AS n FROM members WHERE workspace = ?", workspace)!.n as number;
    if (!existing && count >= LIMITS.membersPerWorkspace) fail(429, "too_many_members");
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
    const stations = this.#one("SELECT COUNT(*) AS n FROM stations WHERE workspace = ?", workspace)!.n as number;
    if (stations >= LIMITS.stationsPerWorkspace) fail(429, "too_many_stations");
    const token = randomSecret();
    const expires = nowSeconds() + ENROLLMENT_TTL_SEC;
    this.#run("DELETE FROM enrollments WHERE expires_at <= ?", nowSeconds());
    this.#run("INSERT INTO enrollments (token_hash, workspace, name, created_by, expires_at) VALUES (?, ?, ?, ?, ?)", await digest(token), workspace, clean, sub, expires);
    return { token, expires_at: expires };
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

  renameStation(sub: string, workspace: string, station: string, name: string): WorkspaceView {
    this.#role(sub, workspace, MANAGERS);
    this.#run("UPDATE stations SET name = ? WHERE id = ? AND workspace = ?", cleanName(name) ?? fail(400, "invalid_name"), station, workspace);
    this.#changed(workspace, false);
    this.#sendState(station);
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

  access(sub: string, workspace: string, station: string): { role: Role; station_name: string } {
    const role = this.#role(sub, workspace);
    const row = this.#one("SELECT name FROM stations WHERE id = ? AND workspace = ?", station, workspace);
    if (!row) fail(404, "station_not_found");
    return { role, station_name: row!.name as string };
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
    return this.#rows("SELECT sub, email, name, picture, created_at, last_seen, admitted FROM users ORDER BY created_at DESC").map((row) => {
      const workspaces = memberships.get(row.sub as string) ?? [];
      const admission: Admission | null = isAdmin(this.env, row.email as string) ? "admin" : (row.admitted as Admission | null) ?? (workspaces.length ? "early" : null);
      return {
        sub: row.sub as string, email: row.email as string, name: row.name as string, picture: row.picture as string,
        created_at: row.created_at as number, last_seen: row.last_seen as number | null, admission, workspaces,
      };
    });
  }

  /** The operator removes a workspace as its owner would (the admin token's route). */
  adminDeleteWorkspace(id: string): void {
    const owner = this.#one("SELECT sub FROM members WHERE workspace = ? AND role = 'owner' LIMIT 1", id);
    if (!owner) fail(404, "workspace_not_found");
    this.deleteWorkspace(owner!.sub as string, id);
  }

  adminWorkspaces(): AdminWorkspace[] {
    const now = nowSeconds();
    return this.#rows(`SELECT w.id, w.name, w.created_at, u.sub, u.email, u.name AS user_name, u.picture FROM workspaces w
      LEFT JOIN users u ON u.sub = w.created_by ORDER BY w.created_at DESC`).map((w) => ({
      id: w.id as string,
      name: w.name as string,
      created_at: w.created_at as number,
      created_by: w.sub === null ? null : { sub: w.sub as string, email: w.email as string, name: w.user_name as string, picture: w.picture as string },
      members: this.#rows(`SELECT m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name, COALESCE(u.picture, '') AS picture, m.role, m.added_at
        FROM members m LEFT JOIN users u ON u.sub = m.sub WHERE m.workspace = ? ORDER BY m.added_at`, w.id) as unknown as MemberView[],
      stations: this.#rows("SELECT id, name, enrolled_at, enrolled_by, last_seen, version FROM stations WHERE workspace = ? ORDER BY enrolled_at", w.id)
        .map((row) => ({ ...row, online: this.#presence(row.id as string).length > 0 })) as unknown as StationView[],
      invitations: this.#rows(`SELECT i.id, i.role, i.email, i.created_by, i.expires_at, COALESCE(NULLIF(u.name, ''), u.email, '') AS inviter
        FROM invitations i LEFT JOIN users u ON u.sub = i.created_by WHERE i.workspace = ? AND i.expires_at > ? ORDER BY i.expires_at`, w.id, now) as unknown as AdminWorkspace["invitations"],
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

  // ── sockets ─────────────────────────────────────────────────────────────

  /**
   * Upgrades reach here only through the Worker, which has authenticated
   * them: `/events` names the account in `x-ember-sub`, `/stations/connect`
   * the station (whose signature it checked) in `x-ember-station`.
   */
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    const pair = new WebSocketPair();
    if (path === "/events") {
      const sub = request.headers.get("x-ember-sub")!;
      // Every device opens this when it starts: the nearest thing to "last seen" that costs no write per request.
      this.#run("UPDATE users SET last_seen = ? WHERE sub = ?", nowSeconds(), sub);
      this.ctx.acceptWebSocket(pair[1], [`sub:${sub}`]);
      pair[1].serializeAttachment({ sub } satisfies Attachment);
      return new Response(null, { status: 101, webSocket: pair[0], headers: { "sec-websocket-protocol": EVENTS_PROTOCOL } });
    }
    const station = request.headers.get("x-ember-station")!;
    const row = this.#one("SELECT workspace FROM stations WHERE id = ?", station);
    if (!row) return Response.json({ error: "station_removed" }, { status: 404 });
    // One socket per station: a reconnect replaces the one it gave up on, without an offline in between.
    const wasOnline = this.#presence(station).length > 0;
    for (const old of this.#presence(station)) this.#drop(old, CLOSE.replaced, "replaced");
    this.#run("UPDATE stations SET last_seen = ?, version = COALESCE(?, version) WHERE id = ?", nowSeconds(), request.headers.get("x-ember-version"), station);
    this.ctx.acceptWebSocket(pair[1], [`station:${station}`]);
    pair[1].serializeAttachment({ station, at: Date.now() } satisfies Attachment);
    this.#sendState(station);
    if (!wasOnline) this.#tell(this.#members(row.workspace as string), { type: "station", workspace: row.workspace as string, id: station, online: true });
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

  /** Where a station is and what it is called; sent on connect and when that changes. */
  #sendState(station: string): void {
    const sockets = this.#presence(station);
    if (!sockets.length) return;
    const row = this.#one("SELECT s.workspace, w.name AS workspace_name, s.name FROM stations s JOIN workspaces w ON w.id = s.workspace WHERE s.id = ?", station);
    if (!row) return;
    const frame = JSON.stringify({ type: "state", ...row, grant_keys: grantKeys(this.env) });
    for (const ws of sockets) ws.send(frame);
  }

  #offline(station: string): void {
    if (this.#presence(station).length) return;
    const row = this.#one("SELECT workspace FROM stations WHERE id = ?", station);
    if (!row) return;
    this.#run("UPDATE stations SET last_seen = ? WHERE id = ?", nowSeconds(), station);
    this.#tell(this.#members(row.workspace as string), { type: "station", workspace: row.workspace as string, id: station, online: false });
  }

  async webSocketMessage(): Promise<void> {
    // Nothing is read from sockets; "ping" is answered by the runtime.
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
