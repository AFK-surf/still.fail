// Who belongs where: users, workspaces, memberships, invitations and
// stations, in one SQLite-backed object so every change is a single
// transaction. Callers have already verified the account's access token;
// methods here check what that account may do in a workspace.
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import { digest, nowSeconds, randomSecret, type Identity } from "./auth";
import type { Env } from "./env";
import type { InvitationView, MemberView, PendingInvitation, Role, StationView, UserView, WorkspaceSummary, WorkspaceView } from "./types";
export type { Role };

export const ROLES: readonly Role[] = ["owner", "admin", "member"];
const MANAGERS: readonly Role[] = ["owner", "admin"];

export const INVITATION_TTL_SEC = 7 * 24 * 60 * 60;
export const ENROLLMENT_TTL_SEC = 60 * 60;
const LIMITS = { workspacesPerUser: 32, membersPerWorkspace: 200, stationsPerWorkspace: 64, openInvitations: 50 };

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
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS users (sub TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', picture TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS members (workspace TEXT NOT NULL, sub TEXT NOT NULL, role TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, sub));
      CREATE INDEX IF NOT EXISTS members_by_user ON members (sub);
      CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, role TEXT NOT NULL, email TEXT, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS stations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, enrolled_at INTEGER NOT NULL, enrolled_by TEXT NOT NULL, last_seen INTEGER, version TEXT);
      CREATE TABLE IF NOT EXISTS enrollments (token_hash TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
    `);
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

  upsertUser(identity: Identity): void {
    this.#run(
      `INSERT INTO users (sub, email, name, picture, created_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (sub) DO UPDATE SET email = excluded.email, name = excluded.name, picture = excluded.picture`,
      identity.sub, identity.email, identity.name, identity.picture, nowSeconds(),
    );
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

  createWorkspace(sub: string, name: string): WorkspaceView {
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    const owned = this.#one("SELECT COUNT(*) AS n FROM members WHERE sub = ? AND role = 'owner'", sub)!.n as number;
    if (owned >= LIMITS.workspacesPerUser) fail(429, "too_many_workspaces");
    const id = ulid();
    const now = nowSeconds();
    this.ctx.storage.transactionSync(() => {
      this.#run("INSERT INTO workspaces (id, name, created_by, created_at) VALUES (?, ?, ?, ?)", id, clean, sub, now);
      this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, 'owner', ?)", id, sub, now);
    });
    return this.workspace(sub, id);
  }

  workspace(sub: string, id: string): WorkspaceView {
    const role = this.#role(sub, id);
    const w = this.#one("SELECT id, name, created_at FROM workspaces WHERE id = ?", id)!;
    const members = this.#rows(`
      SELECT m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name, COALESCE(u.picture, '') AS picture, m.role, m.added_at
      FROM members m LEFT JOIN users u ON u.sub = m.sub WHERE m.workspace = ? ORDER BY m.added_at`, id) as unknown as MemberView[];
    const stations = this.#rows("SELECT id, name, enrolled_at, enrolled_by, last_seen, version FROM stations WHERE workspace = ? ORDER BY enrolled_at", id) as unknown as StationView[];
    const invitations = MANAGERS.includes(role)
      ? this.#rows("SELECT id, role, email, created_by, expires_at FROM invitations WHERE workspace = ? AND expires_at > ? ORDER BY expires_at", id, nowSeconds()) as unknown as InvitationView[]
      : [];
    return { id, name: w.name as string, role, created_at: w.created_at as number, members, stations, invitations };
  }

  renameWorkspace(sub: string, id: string, name: string): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    this.#run("UPDATE workspaces SET name = ? WHERE id = ?", cleanName(name) ?? fail(400, "invalid_name"), id);
    return this.workspace(sub, id);
  }

  deleteWorkspace(sub: string, id: string): void {
    this.#role(sub, id, ["owner"]);
    this.ctx.storage.transactionSync(() => {
      for (const table of ["members", "invitations", "stations", "enrollments"]) this.#run(`DELETE FROM ${table} WHERE workspace = ?`, id);
      this.#run("DELETE FROM workspaces WHERE id = ?", id);
    });
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
      if (!existing) this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?)", workspace, sub, row!.role, nowSeconds());
      else if (ROLES.indexOf(row!.role as Role) < ROLES.indexOf(existing.role as Role)) this.#run("UPDATE members SET role = ? WHERE workspace = ? AND sub = ?", row!.role, workspace, sub);
    });
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
      if (!existing) this.#run("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?)", workspace, sub, row!.role, nowSeconds());
    });
    return this.workspace(sub, workspace);
  }

  declineById(email: string, id: string): void {
    this.#run("DELETE FROM invitations WHERE id = ? AND email = ?", id, email.toLowerCase());
  }

  revokeInvitation(sub: string, workspace: string, id: string): void {
    this.#role(sub, workspace, MANAGERS);
    this.#run("DELETE FROM invitations WHERE id = ? AND workspace = ?", id, workspace);
  }

  setRole(sub: string, workspace: string, target: string, role: Role): WorkspaceView {
    this.#role(sub, workspace, ["owner"]);
    if (!ROLES.includes(role)) fail(400, "invalid_role");
    const current = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    if (!current) fail(404, "member_not_found");
    if (current!.role === "owner" && role !== "owner") this.#keepAnOwner(workspace);
    this.#run("UPDATE members SET role = ? WHERE workspace = ? AND sub = ?", role, workspace, target);
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
    this.ctx.storage.transactionSync(() => {
      this.#run("DELETE FROM enrollments WHERE token_hash = ?", hash);
      this.#run(`INSERT INTO stations (id, workspace, name, enrolled_at, enrolled_by, last_seen, version) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET workspace = excluded.workspace, name = excluded.name, enrolled_at = excluded.enrolled_at, enrolled_by = excluded.enrolled_by, last_seen = excluded.last_seen, version = excluded.version`,
        station, row!.workspace, row!.name, nowSeconds(), row!.created_by, nowSeconds(), version);
    });
    const w = this.#one("SELECT name FROM workspaces WHERE id = ?", row!.workspace)!;
    return { workspace: row!.workspace as string, workspace_name: w.name as string, name: row!.name as string };
  }

  /** A station reports in; returns its workspace, or null once it was removed. */
  heartbeat(station: string, version: string | null): { workspace: string; name: string } | null {
    const row = this.#one("SELECT workspace, name FROM stations WHERE id = ?", station);
    if (!row) return null;
    this.#run("UPDATE stations SET last_seen = ?, version = COALESCE(?, version) WHERE id = ?", nowSeconds(), version, station);
    return { workspace: row.workspace as string, name: row.name as string };
  }

  renameStation(sub: string, workspace: string, station: string, name: string): WorkspaceView {
    this.#role(sub, workspace, MANAGERS);
    this.#run("UPDATE stations SET name = ? WHERE id = ? AND workspace = ?", cleanName(name) ?? fail(400, "invalid_name"), station, workspace);
    return this.workspace(sub, workspace);
  }

  removeStation(sub: string, workspace: string, station: string): void {
    this.#role(sub, workspace, MANAGERS);
    this.#run("DELETE FROM stations WHERE id = ? AND workspace = ?", station, workspace);
  }

  /** What a grant to reach `station` should say about the caller, if it may. */
  access(sub: string, workspace: string, station: string): { role: Role; station_name: string } {
    const role = this.#role(sub, workspace);
    const row = this.#one("SELECT name FROM stations WHERE id = ? AND workspace = ?", station, workspace);
    if (!row) fail(404, "station_not_found");
    return { role, station_name: row!.name as string };
  }
}

function cleanName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim().replace(/\s+/g, " ");
  return clean && clean.length <= 80 ? clean : null;
}
