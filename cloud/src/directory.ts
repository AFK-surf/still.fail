// Who belongs where: users, workspaces, memberships, invitations and
// stations, in one SQLite-backed object so every change is a single
// transaction. Callers have already verified the account's access token;
// methods here check what that account may do in a workspace.
//
// The sockets that make this live are not here: each device's `/v1/events` socket is on its account's object
// (account.ts), each station's presence socket on the station's own (station.ts). What a change affects is told to
// those objects after its transaction (#deliver: each account the events it gets, each station that its state changed,
// which it then reads here), at least once (the outbox). What scales with devices, stations and requests stays off this
// object; what scales with changes to who belongs where is here. Whether a station is up is not decided here: each
// device finds it out, reaching the station over the mesh.
//
// Sockets held here are those of before (`sub:<account>`, `station:<id>`), and, with DIRECTORY_SOCKETS "primary",
// those opened while the cloud is rolled back to them (`sockets`): told as they were, beside the objects.
import { DurableObject } from "cloudflare:workers";
import { ulid } from "ulid";
import { STATIONS_PER_WORKSPACE } from "../../client/limits.ts";
import { CODE_TTL_DAYS, isAdmin, newCode, normalizeCode } from "./admin";
import { digest, nowSeconds, randomSecret, type Identity } from "./auth";
import { header, publicOrigins } from "./compat";
import type { Env } from "./env";
import { grantKeys } from "./grants";
import { langOf, setCloud, type Lang } from "./i18n.ts";
import { isIconUrl } from "./icons";
import { showsOf, type Shows } from "./noticeText";
import { MAX_RELAYS, parseRelays, relays, relayUrls, sameUrl, waysOf } from "./relays";
import type { Part } from "./changelog";
import type { FeedbackInput } from "./feedback";
import type { AccountEvent, StationEvent, AddedView, Admission, AdminFeedback, FeedbackReply, WorkspaceFeedback, AdminPending, AdminUser, AdminWorkspace, DeviceView, FeedbackStatus, InvitationView, InviteCodeView, LockHead, LockRequestView, MeView, MemberView, PendingInvitation, RigView, Role, StationView, UserView, WorkspaceSummary, WorkspaceView } from "./types";
import { apply, asEntry, entryHash, genesis, keepLockAt, LockAppendRefused, shortCode, type Entry, type LockEntry, type LockState } from "./lock";
export type { Role };

export const ROLES: readonly Role[] = ["owner", "admin", "member"];
const MANAGERS: readonly Role[] = ["owner", "admin"];

export const INVITATION_TTL_SEC = 7 * 24 * 60 * 60;
/** How often one email is told by mail that it was added to one workspace, at most (`#toMail`). */
export const ADDED_MAIL_EVERY_SEC = 24 * 60 * 60;
/** Who `addMembers` tells by mail, by whom and to which workspace (api.ts sends them, mail.ts `sendAdded`). */
export type AddedMail = { to: { email: string; joined: boolean }[]; inviter: string; workspace: string };
export const ENROLLMENT_TTL_SEC = 60 * 60;
/** How long a device's request to be confirmed into the lock waits before it is dropped (one long gone, a browser profile thrown away). */
export const LOCK_REQUEST_TTL_SEC = 7 * 24 * 60 * 60;
const LIMITS = { openInvitations: 50, pushPerUser: 32 };
/**
 * What an account may create and how many people each workspace it created may hold (its creator among them). A code
 * or the admin's say makes an account standard (#standard); the admin's own go up to the old bounds.
 */
export const PLANS = {
  free: { workspaces: 1, members: 1 },
  standard: { workspaces: 5, members: 6 },
  admin: { workspaces: 32, members: 200 },
} as const;
export type Plan = keyof typeof PLANS;

/** The events socket's subprotocols (api.ts socketToken). */
export const EVENTS_PROTOCOLS = ["stillfail-events"] as const;
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
/** How many replies a station's agents may write on its reports a day. */
const FEEDBACK_REPLIES_PER_DAY = 100;
/** How many reports with replies a member's device is given of a workspace (feedbackOf). */
const FEEDBACK_SHOWN = 200;

const LIST: AccountEvent = { type: "workspaces" };
/** The picture an account is shown with, of its row in users: the one it put up for itself (setOwnPicture), else its sign-in's. */
const SHOWN_PICTURE = "COALESCE(own_picture, picture)";
type Attachment = { station: string; at: number; dropped?: boolean } | { sub: string };

/**
 * Where devices' events sockets and stations' presence sockets open, and who says whether a station is enrolled: their
 * own objects (account.ts, station.ts), or, with DIRECTORY_SOCKETS "primary" (env.ts), this one, as before them: the
 * way back while nothing else depends on those objects. Told either way (an account's object keeps whether it is let
 * into the test channel in both). A test sets `where` to move them.
 */
export const sockets = { where: (env: Env): "objects" | "primary" => (env.DIRECTORY_SOCKETS === "primary" ? "primary" : "objects") };

/**
 * What an account's or a station's object is told (#deliver): frames to send on its sockets (events, revocations, what
 * goes to all); `beta`, its account's test channel now; `state`, the station's state changed: `frame`, its state frame
 * as it is as this is sent, null in no workspace now (it lets its socket go). It answers whether it holds a socket
 * (`live`).
 */
export type Delivery = { frames?: string[]; beta?: boolean; state?: true; frame?: string | null };
/** The longest wait before a delivery that failed is tried again (from 2 s, doubling). */
const OUTBOX_MAX_DELAY = 600;
/** How many hours of its requests the directory keeps counted (adminLoad): a week, as the console's longest chart. */
const HOURS_KEPT = 7 * 24;

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
export type PushDevice =
  | { kind: "web"; endpoint: string; p256dh: string; auth: string }
  | { kind: "fcm"; token: string; app?: string }
  | { kind: "apns"; token: string; sandbox: boolean; app?: string };
/** A device registered, with the language its notifications are said in (Chinese for one registered before languages). */
export type PushRegistration = PushDevice & { id: string; lang: Lang; shows: Shows | null };

export class Directory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // (its pushes' words name its product)
    setCloud(env.PUBLIC_ORIGIN);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS users (sub TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', picture TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, last_seen INTEGER, admitted TEXT, beta INTEGER);
      CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS members (workspace TEXT NOT NULL, sub TEXT NOT NULL, role TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, sub));
      CREATE INDEX IF NOT EXISTS members_by_user ON members (sub);
      CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, role TEXT NOT NULL, email TEXT, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS stations (id TEXT PRIMARY KEY, last_seen INTEGER, version TEXT);
      CREATE TABLE IF NOT EXISTS station_members (workspace TEXT NOT NULL, station TEXT NOT NULL, name TEXT NOT NULL, emoji TEXT, icon TEXT, enrolled_at INTEGER NOT NULL, enrolled_by TEXT NOT NULL, PRIMARY KEY (workspace, station));
      CREATE INDEX IF NOT EXISTS station_members_by_station ON station_members (station, enrolled_at);
      CREATE TABLE IF NOT EXISTS enrollments (token_hash TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, created_by TEXT NOT NULL, expires_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS revocations (workspace TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (workspace, kind, id));
      CREATE TABLE IF NOT EXISTS added (workspace TEXT NOT NULL, email TEXT NOT NULL, role TEXT NOT NULL, added_by TEXT NOT NULL, added_at INTEGER NOT NULL, PRIMARY KEY (workspace, email));
      CREATE INDEX IF NOT EXISTS added_by_email ON added (email);
      CREATE TABLE IF NOT EXISTS added_mails (workspace TEXT NOT NULL, email TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (workspace, email));
      CREATE TABLE IF NOT EXISTS pending (email TEXT PRIMARY KEY, beta INTEGER, may_create INTEGER, added_by TEXT NOT NULL, added_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS invite_codes (code TEXT PRIMARY KEY, note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, revoked_at INTEGER, used_by TEXT, used_at INTEGER, workspace TEXT);
      CREATE TABLE IF NOT EXISTS push (id TEXT PRIMARY KEY, sub TEXT NOT NULL, sid TEXT NOT NULL, kind TEXT NOT NULL, endpoint TEXT, p256dh TEXT, auth TEXT, token TEXT, created INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS push_by_endpoint ON push (sub, endpoint);
      CREATE UNIQUE INDEX IF NOT EXISTS push_by_token ON push (sub, token);
      CREATE INDEX IF NOT EXISTS push_by_user ON push (sub, sid);
      CREATE TABLE IF NOT EXISTS feedback (id TEXT PRIMARY KEY, number INTEGER NOT NULL UNIQUE, key TEXT NOT NULL, channel TEXT NOT NULL, sender TEXT NOT NULL, station TEXT, workspace TEXT, account TEXT, title TEXT NOT NULL, body TEXT NOT NULL, area TEXT NOT NULL, reporter TEXT NOT NULL DEFAULT '', context TEXT, logs TEXT, status TEXT NOT NULL DEFAULT 'new', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS feedback_by_key ON feedback (sender, key);
      CREATE INDEX IF NOT EXISTS feedback_by_sender ON feedback (sender, created_at);
      CREATE TABLE IF NOT EXISTS feedback_replies (id TEXT PRIMARY KEY, feedback TEXT NOT NULL, author TEXT NOT NULL, by TEXT NOT NULL DEFAULT '', text TEXT NOT NULL, created_at INTEGER NOT NULL, delivered_at INTEGER);
      CREATE INDEX IF NOT EXISTS feedback_replies_by_feedback ON feedback_replies (feedback, created_at);
      CREATE TABLE IF NOT EXISTS migrations (name TEXT PRIMARY KEY, at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS lock_entries (workspace TEXT NOT NULL, seq INTEGER NOT NULL, hash TEXT NOT NULL, entry TEXT NOT NULL, PRIMARY KEY (workspace, seq));
      CREATE TABLE IF NOT EXISTS devices (workspace TEXT NOT NULL, sub TEXT NOT NULL, device TEXT NOT NULL, base TEXT, kind TEXT, label TEXT, first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL, PRIMARY KEY (workspace, sub, device));
      CREATE TABLE IF NOT EXISTS lock_aside (workspace TEXT NOT NULL, hash TEXT NOT NULL, entry TEXT NOT NULL, PRIMARY KEY (workspace, hash));
      CREATE TABLE IF NOT EXISTS lock_turned_off (workspace TEXT NOT NULL, genesis TEXT NOT NULL, seq INTEGER NOT NULL, entry TEXT NOT NULL, PRIMARY KEY (workspace, genesis, seq));
      CREATE TABLE IF NOT EXISTS lock_requests (workspace TEXT NOT NULL, base TEXT NOT NULL, sub TEXT NOT NULL, request TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (workspace, base));
      CREATE INDEX IF NOT EXISTS users_by_email ON users (lower(email));
      CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, key TEXT NOT NULL, body TEXT NOT NULL, tries INTEGER NOT NULL DEFAULT 0, next_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS live (kind TEXT NOT NULL, key TEXT NOT NULL, gen INTEGER NOT NULL, PRIMARY KEY (kind, key));
      CREATE TABLE IF NOT EXISTS hits (hour INTEGER NOT NULL, family TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (hour, family));
    `);
    // users had neither column before invite codes, nor beta (1: let into the test channel) before it, nor blocked (1:
    // the admin blocked the account; the account's own object is what keeps it out) before the console could block,
    // nor own_picture (the picture the account put up for itself: setOwnPicture) before it could; the table in
    // production gains them here.
    const columns = new Set(this.#rows("PRAGMA table_info(users)").map((r) => r.name as string));
    for (const column of ["last_seen INTEGER", "admitted TEXT", "beta INTEGER", "blocked INTEGER", "own_picture TEXT"]) {
      if (!columns.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE users ADD COLUMN ${column}`);
    }
    // Nor had feedback where it was fixed (the changelog's version and parts, changelog.ts) and when its station was
    // told, before the changelog.
    const reported = new Set(this.#rows("PRAGMA table_info(feedback)").map((r) => r.name as string));
    for (const column of ["fixed_in INTEGER", "fixed_parts TEXT", "told_at INTEGER"]) {
      if (!reported.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE feedback ADD COLUMN ${column}`);
    }
    // Nor had invite codes the test channel to give with them (1), before they could.
    if (!this.#rows("PRAGMA table_info(invite_codes)").some((r) => r.name === "beta")) this.#run("ALTER TABLE invite_codes ADD COLUMN beta INTEGER");
    // Nor had workspaces relays of their own (a JSON array of URLs, null for none), before they could have.
    if (!this.#rows("PRAGMA table_info(workspaces)").some((r) => r.name === "relays")) this.#run("ALTER TABLE workspaces ADD COLUMN relays TEXT");
    // Nor ways turned off (a JSON array of relay URLs and kinds of way, null for none: setWay), before they could be.
    if (!this.#rows("PRAGMA table_info(workspaces)").some((r) => r.name === "ways_off")) this.#run("ALTER TABLE workspaces ADD COLUMN ways_off TEXT");
    // Nor did push keep a device's language, before there were languages.
    if (!this.#rows("PRAGMA table_info(push)").some((r) => r.name === "lang")) this.#run("ALTER TABLE push ADD COLUMN lang TEXT");
    // Nor what a device shows of notices (JSON: noticeText.ts Shows; null all, in full), before a device said.
    if (!this.#rows("PRAGMA table_info(push)").some((r) => r.name === "shows")) this.#run("ALTER TABLE push ADD COLUMN shows TEXT");
    // Nor whether an APNs token is a development build's (1) or not, before there was APNs.
    if (!this.#rows("PRAGMA table_info(push)").some((r) => r.name === "sandbox")) this.#run("ALTER TABLE push ADD COLUMN sandbox INTEGER");
    // The credential that last took an app's token (its Firebase project, its APNs topic: push.ts), tried first.
    if (!this.#rows("PRAGMA table_info(push)").some((r) => r.name === "app")) this.#run("ALTER TABLE push ADD COLUMN app TEXT");
    // Nor had workspaces a mark of their own (an emoji, an icon, as a station's), before they could; their first letter till then.
    const marked = new Set(this.#rows("PRAGMA table_info(workspaces)").map((r) => r.name as string));
    for (const column of ["emoji TEXT", "icon TEXT"]) {
      if (!marked.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE workspaces ADD COLUMN ${column}`);
    }
    // Nor had workspaces limits of their own (people, stations; both or neither), before the admin could make one for
    // a company. max_stations stays for old clients and records; the current cap is shared by all workspaces.
    for (const column of ["max_members INTEGER", "max_stations INTEGER"]) {
      if (!marked.has(column.split(" ")[0]!)) this.#run(`ALTER TABLE workspaces ADD COLUMN ${column}`);
    }
    this.migrateFreePlan();
    this.migrateStationMembers();
    // A rig (a station that only runs tasks, 2026-11-10): a machine that only runs what the workspace's stations send it, its person's (the one
    // who added it: `enrolled_by`). `rig` is 1 on its row and on the enrollment that makes one; absent before them.
    for (const table of ["station_members", "enrollments"]) {
      if (!this.#rows(`PRAGMA table_info(${table})`).some((r) => r.name === "rig")) this.#run(`ALTER TABLE ${table} ADD COLUMN rig INTEGER`);
    }
    if (sockets.where(env) === "objects") this.handOff();
    // What deliveries a restart cut short still owe.
    if (this.#one("SELECT 1 AS x FROM outbox LIMIT 1")) void ctx.blockConcurrencyWhile(() => this.#arm());
  }

  /**
   * Sockets held here while devices' and stations' open on their own objects (those from before the deploy that moved
   * them, or from before the way back was left): closed as a restarting service's (1012), so each reconnects onto its
   * own object, reading everything again as it does after any reconnect.
   */
  protected handOff(): void {
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as Attachment;
      if ("station" in attachment) this.#drop(ws, 1012, "moved");
      else {
        try {
          ws.close(1012, "moved");
        } catch {
          // Closed already.
        }
      }
    }
  }

  /**
   * A station was in one workspace, its row in `stations` saying which and what it is called there (with an emoji and
   * an icon, which it gained later: absent from a table older than them). It may be in several now: `stations` keeps
   * the machine, `station_members` each workspace it is in, named there. An old table is
   * split here, each row into one of each; one already split has no `workspace` and is left alone.
   */
  protected migrateStationMembers(): void {
    const columns = new Set(this.#rows("PRAGMA table_info(stations)").map((r) => r.name as string));
    if (!columns.has("workspace")) return;
    const kept = (column: string) => (columns.has(column) ? column : "NULL");
    this.ctx.storage.transactionSync(() => {
      this.#run(`INSERT OR IGNORE INTO station_members (workspace, station, name, emoji, icon, enrolled_at, enrolled_by)
        SELECT workspace, id, name, ${kept("emoji")}, ${kept("icon")}, enrolled_at, enrolled_by FROM stations ORDER BY enrolled_at, rowid`);
      this.#run("CREATE TABLE stations_split (id TEXT PRIMARY KEY, last_seen INTEGER, version TEXT)");
      this.#run("INSERT INTO stations_split (id, last_seen, version) SELECT id, last_seen, version FROM stations");
      this.#run("DROP TABLE stations");
      this.#run("ALTER TABLE stations_split RENAME TO stations");
    });
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

  /** Pushes events to every events socket of these accounts: on their objects, and any held here. */
  #tell(subs: Iterable<string>, ...events: AccountEvent[]): void {
    const frames = events.map((event) => JSON.stringify(event));
    for (const sub of new Set(subs)) {
      this.#deliver("account", sub, { frames });
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

  // ── deliveries to the objects that hold the sockets ─────────────────────
  // Written in the same step as the change that makes them (nothing awaits between them, so the runtime keeps them
  // together), and sent as that step ends, each object's together in one call and one call at a time, so an object hears
  // its changes in order. One that fails is tried again with a backoff until it gets there (the alarm); one that is late
  // costs a device or a station told late, which reads everything again as it reconnects anyway. What keeps someone's
  // access (a revocation, a station leaving a workspace) is awaited before the change answers (#delivered); the rest
  // goes out as it answers, so no answer waits on a member's object across the world. Frames are only for sockets: an
  // object holding none (not in `live`) is not called for them, and reads all of it as one opens.

  /** Each object's sending now (`kind key`): what is written for it meanwhile goes next, in the same run. */
  readonly #sending = new Map<string, Promise<void>>();
  /** Objects the step being run must have reached before its request answers (#delivered). */
  #urgent: string[] = [];
  #soon: Promise<void> | null = null;

  /** `always`: whether or not it holds a socket (what its object keeps: an account's test channel, a station let go). */
  #deliver(kind: "account" | "station", key: string, body: Delivery, how: { urgent?: boolean; always?: boolean } = {}): void {
    if (!how.always && !this.#one("SELECT 1 AS x FROM live WHERE kind = ? AND key = ?", kind, key)) return;
    this.#run("INSERT INTO outbox (kind, key, body) VALUES (?, ?, ?)", kind, key, JSON.stringify(body));
    this.#soon ??= Promise.resolve().then(() => {
      this.#soon = null;
      this.#flush();
    });
    if (how.urgent) this.#urgent.push(`${kind} ${key}`);
  }

  /**
   * Waits until the deliveries the step that just ran made urgent got there or failed once (then they are tried again
   * after). Called in that same step, before anything is awaited: what another request's step makes is its own.
   */
  async #delivered(): Promise<void> {
    const keys = this.#urgent.splice(0);
    await this.#soon;
    await Promise.all(keys.map((k) => this.#sending.get(k)));
  }

  /** Sends what is due, to each object not being sent to already. */
  #flush(): void {
    for (const r of this.#rows("SELECT DISTINCT kind, key FROM outbox WHERE next_at <= ?", nowSeconds())) {
      const kind = r.kind as "account" | "station", key = r.key as string, k = `${kind} ${key}`;
      if (this.#sending.has(k)) continue;
      this.#sending.set(k, this.#sendAll(kind, key).finally(() => {
        this.#sending.delete(k);
        // Written between its last read and now.
        if (this.#one("SELECT 1 AS x FROM outbox WHERE kind = ? AND key = ? AND next_at <= ?", kind, key, nowSeconds())) this.#flush();
      }));
    }
  }

  async #sendAll(kind: "account" | "station", key: string): Promise<void> {
    for (;;) {
      // All that waits for it, what failed before with what is new, so it never hears a later change before an earlier one.
      const group = this.#rows("SELECT id, body, tries FROM outbox WHERE kind = ? AND key = ? ORDER BY id", kind, key);
      if (group.length === 0) return;
      const bodies = group.map((r) => JSON.parse(r.body as string) as Delivery);
      const tried = group.some((r) => (r.tries as number) > 0);
      const beta = [...bodies].reverse().find((b) => b.beta !== undefined)?.beta;
      const body: Delivery = {
        frames: bodies.flatMap((b) => b.frames ?? []),
        ...(beta === undefined ? {} : { beta }),
        // Tried again, a station is told its state too: what was told late is then followed by all of it as it is.
        // Made as it is sent, so the station need not ask for it.
        ...(bodies.some((b) => b.state) || (kind === "station" && tried) ? { state: true as const, frame: this.#frame(key) } : {}),
      };
      const ids = group.map((r) => r.id as number);
      const marks = ids.map(() => "?").join(", ");
      const gen = this.#one("SELECT gen FROM live WHERE kind = ? AND key = ?", kind, key)?.gen as number | undefined;
      try {
        const said = await this.send(kind, key, body);
        this.#run(`DELETE FROM outbox WHERE id IN (${marks})`, ...ids);
        // It holds no socket: out of `live`, unless one opened since (a newer gen).
        if (!said.live && gen !== undefined) this.#run("DELETE FROM live WHERE kind = ? AND key = ? AND gen <= ?", kind, key, gen);
      } catch (error) {
        const tries = Math.max(...group.map((r) => r.tries as number)) + 1;
        if (tries % 8 === 0) console.warn(`directory: ${kind} ${key} not told after ${tries} tries: ${(error as Error).message}`);
        this.#run(`UPDATE outbox SET tries = ?, next_at = ? WHERE id IN (${marks})`, tries, nowSeconds() + Math.min(2 ** tries, OUTBOX_MAX_DELAY), ...ids);
        await this.#arm();
        return;
      }
    }
  }

  /** One delivery to an object (a test makes it fail). */
  protected send(kind: "account" | "station", key: string, body: Delivery): Promise<{ live: boolean }> {
    return kind === "account" ? this.env.ACCOUNTS.getByName(key).deliver(key, body) : this.env.STATIONS.getByName(key).deliver(key, body);
  }

  /** The alarm at the next delivery due again, unless it is set sooner. */
  async #arm(): Promise<void> {
    const next = this.#one("SELECT MIN(next_at) AS at FROM outbox")?.at as number | null | undefined;
    if (next === null || next === undefined) return;
    const at = Math.max(next * 1000, Date.now());
    const set = await this.ctx.storage.getAlarm();
    if (set === null || at < set) await this.ctx.storage.setAlarm(at); // timer: a retry after a failure, with a backoff
  }

  /** Every delivery under way has got there or failed (the tests' barrier, instead of waiting a while). */
  protected async settled(): Promise<void> {
    while (this.#soon !== null || this.#sending.size > 0) await Promise.all([this.#soon, ...this.#sending.values()]);
  }

  /**
   * An object holding a socket now (an account's events socket, a station's presence socket): told what is for its
   * sockets, and what goes to all, until it says it holds none (closed, or a delivery's answer). Its `gen` tells a
   * close from before a later open.
   */
  #opened(kind: "account" | "station", key: string): number {
    // Never one given before: a close or an answer from before a later open must not take the later one's row.
    const gen = (this.ctx.storage.kv.get<number>("opened") ?? 0) + 1;
    this.ctx.storage.kv.put("opened", gen);
    this.#run("INSERT INTO live (kind, key, gen) VALUES (?, ?, ?) ON CONFLICT (kind, key) DO UPDATE SET gen = excluded.gen", kind, key, gen);
    return gen;
  }

  /** An account's object opened an events socket (account.ts): seen now (the console's last seen), and live. */
  seen(sub: string): number {
    this.#run("UPDATE users SET last_seen = ? WHERE sub = ?", nowSeconds(), sub);
    return this.#opened("account", sub);
  }

  /** An account's object closed its last events socket, opened as `gen`. */
  closed(sub: string, gen: number): void {
    this.#run("DELETE FROM live WHERE kind = 'account' AND key = ? AND gen = ?", sub, gen);
  }

  /** Tells every connected device of every account `event`, and every connected station `station` (a release out). */
  tellAll(event: AccountEvent, station: StationEvent | null): void {
    const frames = [JSON.stringify(event), station === null ? null : JSON.stringify(station)];
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as Attachment;
      const frame = "station" in attachment ? frames[1] : frames[0];
      if (frame === null || ws.readyState !== WebSocket.OPEN) continue;
      try {
        ws.send(frame);
      } catch {
        // Closing already; it reads what it needs as it connects again.
      }
    }
    for (const r of this.#rows("SELECT kind, key FROM live")) {
      const frame = r.kind === "station" ? frames[1] : frames[0];
      if (frame !== null) this.#deliver(r.kind as "account" | "station", r.key as string, { frames: [frame] });
    }
  }

  /** Tells every connected station `event` (the models' catalog changed). */
  tellStations(event: StationEvent): void {
    const frame = JSON.stringify(event);
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as Attachment;
      if (!("station" in attachment) || attachment.dropped || ws.readyState !== WebSocket.OPEN) continue;
      try {
        ws.send(frame);
      } catch {}
    }
    for (const r of this.#rows("SELECT key FROM live WHERE kind = 'station'")) this.#deliver("station", r.key as string, { frames: [frame] });
  }

  /** The models' catalog the cron made (models.ts `checkModels`): told to every connected station when it changed. */
  async modelsMade(etag: string): Promise<void> {
    const before = await this.ctx.storage.get<string>("models-etag");
    if (before === etag) return;
    await this.ctx.storage.put("models-etag", etag);
    this.tellStations({ type: "models", etag });
  }

  /**
   * Tells the operator's connected devices `event` (their console reads it again): its accounts, found by their email.
   * The cron's, every minute: what this object counted of its requests is kept then too (#keepCounts).
   */
  tellAdmins(event: AccountEvent): void {
    this.#keepCounts();
    if (!this.env.ADMIN_EMAIL) return;
    this.#tell(this.#byEmail(this.env.ADMIN_EMAIL), event);
  }

  #members(workspace: string): string[] {
    return this.#rows("SELECT sub FROM members WHERE workspace = ?", workspace).map((r) => r.sub as string);
  }

  /** The stations in a workspace, its rigs among them (each holds a presence socket and is told its state). */
  #stationsIn(workspace: string): string[] {
    return this.#rows("SELECT station FROM station_members WHERE workspace = ?", workspace).map((r) => r.station as string);
  }

  /** The workspaces a station is in, its home first: the one it joined first (the earliest row of the earliest second). */
  #memberships(station: string): string[] {
    return this.#rows("SELECT workspace FROM station_members WHERE station = ? ORDER BY enrolled_at, rowid", station).map((r) => r.workspace as string);
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
  #changed(workspace: string, list: boolean, also: Iterable<string> = [], lockOnly = false): void {
    for (const station of this.#stationsIn(workspace)) this.#sendState(station);
    const subs = [...this.#members(workspace), ...also];
    const lock = lockOnly ? { lock: { head: this.#lockHead(workspace), locked: this.#locked(workspace) } } : {};
    this.#tell(subs, ...(list ? [LIST] : []), { type: "workspace", id: workspace, ...lock });
  }

  /**
   * The account a sign-in that proved it holds `email` (Google's, or a code sent to it: login.ts) is, with the name and
   * picture it has: the one `sub` already is, else the first signed in with that email, so whoever signed up one way and
   * signs in the other is the same account, with its workspaces; null for a new one. App Store review's (`pw-`,
   * password.ts) is nobody's but its own.
   */
  accountFor(sub: string, email: string): { sub: string; name: string; picture: string } | null {
    const row = this.#one("SELECT sub, name, picture FROM users WHERE sub = ?", sub) ?? this.#one("SELECT sub, name, picture FROM users WHERE lower(email) = lower(?) AND sub NOT LIKE 'pw-%' ORDER BY created_at, rowid LIMIT 1", email);
    return row ? { sub: row.sub as string, name: row.name as string, picture: row.picture as string } : null;
  }

  upsertUser(identity: Identity): void {
    const old = this.#one("SELECT email, name, picture FROM users WHERE sub = ?", identity.sub);
    this.#run(
      `INSERT INTO users (sub, email, name, picture, created_at, last_seen) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (sub) DO UPDATE SET email = excluded.email, name = excluded.name, picture = excluded.picture, last_seen = excluded.last_seen`,
      identity.sub, identity.email, identity.name, identity.picture, nowSeconds(), nowSeconds(),
    );
    this.#joinAdded(identity.sub, identity.email);
    this.#takePending(identity.sub, identity.email);
    if (!old || (old.email === identity.email && old.name === identity.name && old.picture === identity.picture)) return;
    // Members lists show them; invitations they sent show their name; a new email has other invitations.
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", identity.sub)) this.#changed(row.workspace as string, false);
    const invited = this.#rows("SELECT i.email FROM invitations i WHERE i.created_by = ? AND i.expires_at > ?", identity.sub, nowSeconds()).flatMap((r) => this.#byEmail(r.email as string));
    this.#tell([...invited, ...(old.email === identity.email ? [] : [identity.sub])], LIST);
  }

  /**
   * The picture the account put up for itself (kept here: api.ts puts one sent in the bucket), shown instead of its
   * sign-in's wherever that was (`/v1/me`, members lists, the console); signing in again leaves it, as upsertUser
   * changes only the sign-in's. null takes it away, the sign-in's shown again. Its own devices and its workspaces'
   * members hear of it.
   */
  setOwnPicture(sub: string, picture: unknown): { picture: string } {
    const own = picture === null ? null : cleanPicture(picture, publicOrigins(this.env)) ?? fail(400, "invalid_icon");
    this.#run("UPDATE users SET own_picture = ? WHERE sub = ?", own, sub);
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", sub)) this.#changed(row.workspace as string, false);
    this.#tell([sub], LIST);
    return { picture: own ?? (this.#one("SELECT picture FROM users WHERE sub = ?", sub)?.picture as string | undefined) ?? "" };
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

  /** An account signing in with an email the admin gave rights to before it had one: they are its from now on. */
  #takePending(sub: string, email: string): void {
    const row = this.#one("SELECT beta, may_create FROM pending WHERE email = ?", email.toLowerCase());
    if (!row) return;
    this.ctx.storage.transactionSync(() => {
      if (row.beta) {
        this.#run("UPDATE users SET beta = 1 WHERE sub = ?", sub);
        this.#betaTold(sub);
      }
      if (row.may_create) this.#run("UPDATE users SET admitted = 'granted' WHERE sub = ? AND (admitted IS NULL OR admitted IN ('invitation', 'free'))", sub);
      this.#run("DELETE FROM pending WHERE email = ?", email.toLowerCase());
    });
  }

  /**
   * Adds people by email, no invitation to accept: those with an account are members at once, the others as soon as they
   * first sign in with that email. What each became: joined, added (waiting for a first sign-in), or already a member.
   */
  addMembers(sub: string, workspace: string, role: Role, emails: unknown): { joined: string[]; added: string[]; already: string[]; view: WorkspaceView; mail: AddedMail } {
    const mine = this.#role(sub, workspace, MANAGERS);
    if (!ROLES.includes(role)) fail(400, "invalid_role");
    if (role === "owner" && mine !== "owner") fail(403, "forbidden");
    const { joined, added, already } = this.#addEmails(sub, workspace, role, emailsOf(emails));
    return { joined, added, already, view: this.#view(sub, workspace), mail: this.#toMail(sub, workspace, joined, added) };
  }

  /**
   * Who of those just added is told so by mail (api.ts sends it): each email once a day in a workspace at most, so
   * taking someone out and adding them again cannot send the cloud's address to anyone over and over. Noted as sent
   * here; one that could not be sent is let go of again (`mailFailed`), so adding them again tries again.
   */
  #toMail(by: string, workspace: string, joined: string[], added: string[]): AddedMail {
    const now = nowSeconds();
    this.#run("DELETE FROM added_mails WHERE at <= ?", now - ADDED_MAIL_EVERY_SEC);
    const to: { email: string; joined: boolean }[] = [];
    for (const [emails, isJoined] of [[joined, true], [added, false]] as const) {
      for (const email of emails) {
        if (this.#one("SELECT 1 AS x FROM added_mails WHERE workspace = ? AND email = ?", workspace, email)) continue;
        this.#run("INSERT INTO added_mails (workspace, email, at) VALUES (?, ?, ?)", workspace, email, now);
        to.push({ email, joined: isJoined });
      }
    }
    const inviter = this.#one("SELECT COALESCE(NULLIF(name, ''), email) AS n FROM users WHERE sub = ?", by)?.n as string | undefined;
    const name = this.#one("SELECT name FROM workspaces WHERE id = ?", workspace)?.name as string | undefined;
    return { to, inviter: inviter ?? "", workspace: name ?? "" };
  }

  /** Mails of `addMembers` that could not be sent: not counted as sent, so adding them again sends again. */
  mailFailed(workspace: string, emails: string[]): void {
    for (const email of emails) this.#run("DELETE FROM added_mails WHERE workspace = ? AND email = ?", workspace, email);
  }

  /** addMembers once allowed: each email a member now, or as soon as it first signs in. */
  #addEmails(by: string, workspace: string, role: Role, wanted: string[]): { joined: string[]; added: string[]; already: string[] } {
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
            ON CONFLICT (workspace, email) DO UPDATE SET role = excluded.role, added_by = excluded.added_by`, workspace, email, role, by, nowSeconds());
          added.push(email);
        }
      }
    });
    this.#changed(workspace, true, joined.flatMap((e) => this.#byEmail(e)));
    return { joined, added, already };
  }

  /** Takes back an email added but not signed in yet. */
  removeAdded(sub: string, workspace: string, email: string): WorkspaceView {
    this.#role(sub, workspace, MANAGERS);
    this.#run("DELETE FROM added WHERE workspace = ? AND email = ?", workspace, email.trim().toLowerCase());
    this.#changed(workspace, true);
    return this.#view(sub, workspace);
  }

  me(sub: string): { user: MeView | null; workspaces: WorkspaceSummary[] } {
    const row = this.#one(`SELECT sub, email, name, ${SHOWN_PICTURE} AS picture, own_picture, beta FROM users WHERE sub = ?`, sub);
    // beta and own_picture only when set: clients from before them know no such field, and an account without them says
    // nothing.
    const user = row ? { sub: row.sub as string, email: row.email as string, name: row.name as string, picture: row.picture as string, ...(row.own_picture ? { own_picture: true as const } : {}), ...(row.beta ? { beta: true as const } : {}) } : undefined;
    const workspaces = this.#rows(`
      SELECT w.id, w.name, m.role, w.created_at,
        (SELECT COUNT(*) FROM station_members s WHERE s.workspace = w.id AND s.rig IS NULL) AS stations,
        (SELECT COUNT(*) FROM members x WHERE x.workspace = w.id) AS members, w.relays, w.ways_off, w.emoji, w.icon
      FROM members m JOIN workspaces w ON w.id = m.workspace WHERE m.sub = ? ORDER BY w.created_at`, sub)
      .map(({ relays, ways_off, emoji, icon, ...w }) => ({ ...w, relays: parseRelays(relays), ...offOf(ways_off), ...marks(emoji, icon) })) as unknown as WorkspaceSummary[];
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
    // Those the admin made for others (with limits of their own) are not the admin's to count.
    const made = this.#one("SELECT COUNT(*) AS n FROM workspaces WHERE created_by = ? AND max_members IS NULL", sub)!.n as number;
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
        // A code made with the test channel lets its account in too.
        this.#run("UPDATE users SET beta = 1 WHERE sub = ? AND (SELECT beta FROM invite_codes WHERE code = ?) = 1", sub, redeem);
        this.#betaTold(sub);
        this.#run("UPDATE users SET admitted = 'code' WHERE sub = ? AND (admitted IS NULL OR admitted IN ('invitation', 'free'))", sub);
      } else if (!standard) {
        // In a workspace, but not from before codes (#standard).
        this.#run("UPDATE users SET admitted = 'free' WHERE sub = ? AND (admitted IS NULL OR admitted = 'invitation')", sub);
      }
    });
    this.#tell([sub], LIST);
    return this.#view(sub, id);
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

  /** How many people a workspace may hold: its own limit, or its creator's plan's. */
  #memberCap(workspace: string): number {
    const own = this.#one("SELECT max_members, max_stations FROM workspaces WHERE id = ?", workspace);
    if (own && own.max_members !== null && own.max_stations !== null) return own.max_members as number;
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
    return this.#view(sub, id);
  }

  /** A workspace as the caller sees it (what its changes answer with: called within them, it is not counted again). */
  #view(sub: string, id: string): WorkspaceView {
    const role = this.#role(sub, id);
    const w = this.#one("SELECT id, name, created_at, relays, ways_off, emoji, icon FROM workspaces WHERE id = ?", id)!;
    const members = this.#rows(`
      SELECT m.sub, COALESCE(u.email, '') AS email, COALESCE(u.name, '') AS name, COALESCE(${SHOWN_PICTURE}, '') AS picture, m.role, m.added_at
      FROM members m LEFT JOIN users u ON u.sub = m.sub WHERE m.workspace = ? ORDER BY m.added_at`, id) as unknown as MemberView[];
    const stations = this.#stationViews(id).map(({ workspace: _, ...station }) => station);
    const rigs = this.#rigViews(id);
    const invitations = MANAGERS.includes(role)
      ? this.#rows("SELECT id, role, email, created_by, expires_at FROM invitations WHERE workspace = ? AND expires_at > ? ORDER BY expires_at", id, nowSeconds()) as unknown as InvitationView[]
      : [];
    const added = MANAGERS.includes(role)
      ? this.#rows("SELECT email, role, added_by, added_at FROM added WHERE workspace = ? ORDER BY added_at", id) as unknown as AddedView[]
      : [];
    return { id, name: w.name as string, ...marks(w.emoji, w.icon), role, created_at: w.created_at as number, members, stations, ...(rigs.length ? { rigs } : {}), invitations, added, relays: parseRelays(w.relays), ...offOf(w.ways_off), ways: waysOf(this.env, parseRelays(w.relays), parseRelays(w.ways_off)), lock: this.#lockHead(id), ...(this.#locked(id) ? { locked: true } : {}), lock_requests: this.#lockRequestCount(id, sub, role) };
  }

  /**
   * The stations of a workspace (of every workspace, grouped by the caller, without one), as its views list them: named
   * there, `joined` where it is not the station's home (a station in one workspace says nothing of it).
   */
  #stationViews(workspace: string | null): (StationView & { workspace: string })[] {
    return this.#rows(`SELECT m.workspace, m.station AS id, m.name, m.emoji, m.icon, m.enrolled_at, m.enrolled_by, s.last_seen, s.version,
        EXISTS (SELECT 1 FROM station_members o WHERE o.station = m.station AND (o.enrolled_at < m.enrolled_at OR (o.enrolled_at = m.enrolled_at AND o.rowid < m.rowid))) AS joined
      FROM station_members m LEFT JOIN stations s ON s.id = m.station WHERE (? IS NULL OR m.workspace = ?) AND m.rig IS NULL ORDER BY m.enrolled_at, m.rowid`, workspace, workspace)
      .map(({ joined, ...row }) => ({ ...row, ...(joined ? { joined: true } : {}) })) as unknown as (StationView & { workspace: string })[];
  }

  /** A workspace's rigs as its stations are told them (`rigs`); nothing said with none, as before there were any. */
  #rigsTold(workspace: string): { rigs?: Pick<RigView, "id" | "name" | "owner" | "owner_email" | "owner_name" | "version">[] } {
    const rigs = this.#rigViews(workspace).map(({ id, name, owner, owner_email, owner_name, version }) => ({ id, name, owner, owner_email, owner_name, version }));
    return rigs.length ? { rigs } : {};
  }

  /** The rigs of a workspace, each with its person (who added it). */
  #rigViews(workspace: string): RigView[] {
    return this.#rows(`SELECT m.station AS id, m.name, m.enrolled_at, m.enrolled_by AS owner, COALESCE(u.email, '') AS owner_email, COALESCE(u.name, '') AS owner_name, s.last_seen, s.version
      FROM station_members m LEFT JOIN stations s ON s.id = m.station LEFT JOIN users u ON u.sub = m.enrolled_by WHERE m.workspace = ? AND m.rig = 1 ORDER BY m.enrolled_at, m.rowid`, workspace) as unknown as RigView[];
  }

  // ── the workspace lock (lock.ts): kept and carried, not trusted ─────────────────────────

  /** Workspaces whose kept chain was checked while this object lives (#lockChecked). */
  protected readonly lockSeen = new Set<string>();

  /** The kept chain checked once a workspace while this object lives (#lockState): what it reads after is what checks out. */
  #lockChecked(workspace: string): void {
    if (this.lockSeen.has(workspace)) return;
    this.lockSeen.add(workspace);
    this.#lockState(workspace);
  }

  /**
   * The kept chain's state as a station takes it (null: none), what does not check out cut off with everything after
   * it: entries kept before the cloud checked them (until 2026-10-29), which every station refused, and every entry
   * after them with them (a workspace's new devices turned away for days). Its stations and members are told.
   */
  #lockState(workspace: string): LockState | null {
    let state: LockState | null = null;
    for (const r of this.#rows("SELECT seq, entry FROM lock_entries WHERE workspace = ? ORDER BY seq", workspace)) {
      try {
        const e = JSON.parse(r.entry as string) as Entry;
        state = state === null ? genesis(e) : apply(state, e, null);
      } catch (error) {
        this.#run("DELETE FROM lock_entries WHERE workspace = ? AND seq >= ?", workspace, r.seq);
        console.warn(`lock: ${workspace}'s kept lock cut back before entry ${String(r.seq)}, which no station takes: ${(error as Error).message}`);
        // Not from inside what is being told (a state frame reads the head).
        queueMicrotask(() => this.#changed(workspace, false));
        break;
      }
    }
    return state;
  }

  #lockHead(workspace: string): LockHead | null {
    this.#lockChecked(workspace);
    const last = this.#one("SELECT seq, hash FROM lock_entries WHERE workspace = ? ORDER BY seq DESC LIMIT 1", workspace);
    if (!last) return null;
    const first = this.#one("SELECT hash FROM lock_entries WHERE workspace = ? AND seq = 0", workspace);
    return { seq: last.seq as number, hash: last.hash as string, genesis: (first?.hash as string) ?? "" };
  }

  /** How many devices wait to be confirmed, of those the caller sees (all for owners and admins, their own for others). */
  #lockRequestCount(workspace: string, sub: string, role: Role): number {
    return this.#lockRequestRows(workspace, sub, role).length;
  }

  /**
   * The devices waiting to be confirmed that the caller sees, oldest first: not past their time, and of one person's
   * devices with the same kind and name (the same browser on the same computer, its storage cleared; an app installed
   * again) only the latest.
   */
  #lockRequestRows(workspace: string, sub: string, role: Role): Record<string, unknown>[] {
    const rows = this.#rows(
      `SELECT r.base, r.sub, COALESCE(u.email, '') AS email, r.request, r.created_at FROM lock_requests r LEFT JOIN users u ON u.sub = r.sub
        WHERE r.workspace = ? AND (? OR r.sub = ?) AND r.created_at > ? ORDER BY r.created_at DESC, r.rowid DESC`,
      workspace, MANAGERS.includes(role) ? 1 : 0, sub, nowSeconds() - LOCK_REQUEST_TTL_SEC,
    );
    const seen = new Set<string>();
    return rows.filter((r) => {
      const { kind, label } = JSON.parse(r.request as string) as { kind: string; label: string };
      if (!label) return true;
      const same = JSON.stringify([r.sub, kind, label]);
      if (seen.has(same)) return false;
      seen.add(same);
      return true;
    }).reverse();
  }

  /** Whether a workspace is locked: it has a chain, not turned off. */
  #locked(workspace: string): boolean {
    this.#lockChecked(workspace);
    const last = this.#one("SELECT entry FROM lock_entries WHERE workspace = ? ORDER BY seq DESC LIMIT 1", workspace);
    return last !== undefined && (JSON.parse(last.entry as string) as LockEntry).kind !== "disable";
  }

  /** Whether a workspace's chain moved to its people's logs (`moved {root}`, its last entry for good): whether it is on
   * is said there, never here, and `#locked` stays true. */
  #moved(workspace: string): boolean {
    this.#lockChecked(workspace);
    const last = this.#one("SELECT entry FROM lock_entries WHERE workspace = ? ORDER BY seq DESC LIMIT 1", workspace);
    return last !== undefined && (JSON.parse(last.entry as string) as LockEntry).kind === "moved";
  }

  /** The entries after `after` of a chain of the workspace's turned off (its genesis' hash), none if none is kept. */
  #lockTurnedOff(workspace: string, genesis: string, after: number): unknown[] {
    return this.#rows("SELECT entry FROM lock_turned_off WHERE workspace = ? AND genesis = ? AND seq > ? ORDER BY seq", workspace, genesis, after).map((r) => JSON.parse(r.entry as string));
  }

  #lockAfter(workspace: string, after: number): unknown[] {
    this.#lockChecked(workspace);
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
   * bring them; each is checked as a station checks it (signed by whom it may be), and one a station would refuse is
   * refused here, with the rest: kept, it would leave every entry after it refused at the stations. `fork`: what
   * another keeper took (a station of the lock, a device saying `keep`), kept by the rules' fork choice among all kept
   * (lock.ts `keepLockAt`): the chain gone by (`lock_entries`, what every reader reads) is their active chain, the rest
   * kept beside it (`lock_aside`, none in a record from before).
   */
  async #appendLock(workspace: string, raw: unknown, fork = false): Promise<LockHead | null> {
    const entries = (Array.isArray(raw) ? raw : []).map(asEntry);
    if (entries.length === 0 || entries.length > 256 || entries.some((e) => e === null || e.ws !== workspace)) fail(400, "invalid_lock_entries");
    // Nothing else runs on this object between the reads and the writes below (no await between them), so they are
    // one step. What is refused throws before anything is written.
    this.#lockChecked(workspace);
    const parse = (r: Record<string, unknown>) => JSON.parse(r.entry as string) as LockEntry;
    const kept = {
      entries: this.#rows("SELECT entry FROM lock_entries WHERE workspace = ? ORDER BY seq", workspace).map(parse),
      aside: this.#rows("SELECT entry FROM lock_aside WHERE workspace = ? ORDER BY rowid", workspace).map(parse),
    };
    let plan: ReturnType<typeof keepLockAt>;
    try {
      plan = keepLockAt(kept, entries as LockEntry[], nowSeconds(), fork);
    } catch (e) {
      if (e instanceof LockAppendRefused) fail(e.status, e.code);
      throw e;
    }
    const { restart, changed, moved, kept: now } = plan!;
    if (changed) {
      this.ctx.storage.transactionSync(() => {
        if (restart) {
          // A chain turned off, kept for the stations that missed its end (lockTurnedOff).
          const genesisHash = this.#one("SELECT hash FROM lock_entries WHERE workspace = ? AND seq = 0", workspace)?.hash;
          if (typeof genesisHash === "string") this.#run("INSERT OR IGNORE INTO lock_turned_off (workspace, genesis, seq, entry) SELECT workspace, ?, seq, entry FROM lock_entries WHERE workspace = ?", genesisHash, workspace);
        }
        // (from where the chain now parts from the one kept: a branch that won replaces it from there)
        const hashes = kept.entries.map(entryHash);
        let from = 0;
        while (!restart && from < now.entries.length && from < hashes.length && entryHash(now.entries[from]!) === hashes[from]) from++;
        this.#run("DELETE FROM lock_entries WHERE workspace = ? AND seq >= ?", workspace, from);
        for (const e of now.entries.slice(from)) this.#run("INSERT INTO lock_entries (workspace, seq, hash, entry) VALUES (?, ?, ?, ?)", workspace, e.seq, entryHash(e), JSON.stringify(e));
        const aside = new Set(now.aside.map(entryHash));
        const had = new Set(kept.aside.map(entryHash));
        for (const h of had) if (!aside.has(h)) this.#run("DELETE FROM lock_aside WHERE workspace = ? AND hash = ?", workspace, h);
        for (const e of now.aside) if (!had.has(entryHash(e))) this.#run("INSERT INTO lock_aside (workspace, hash, entry) VALUES (?, ?, ?)", workspace, entryHash(e), JSON.stringify(e));
      });
      // (its lock alone moved on: said in the event, so the members' devices need not ask for the workspace again)
      if (moved) this.#changed(workspace, false, [], true);
    }
    return this.#lockHead(workspace);
  }

  /** A member's device brings entries (its own signer's, or what a station had more: `keep`, what a station took). */
  async appendLock(sub: string, workspace: string, entries: unknown, keep = false): Promise<{ head: LockHead | null }> {
    this.#role(sub, workspace);
    return { head: await this.#appendLock(workspace, entries, keep) };
  }

  /** The owner lets the kept lock go (its signers lost: each station is reset on its own machine). */
  clearLock(sub: string, workspace: string): void {
    this.#role(sub, workspace, ["owner"]);
    this.#run("DELETE FROM lock_entries WHERE workspace = ?", workspace);
    this.#run("DELETE FROM lock_aside WHERE workspace = ?", workspace);
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

  /** The devices that asked for credentials in the workspace in the last 31 days: its owners and admins see everyone's
   * (what turning the lock on lists, when each was last used), a member their own. */
  devices(sub: string, workspace: string): { devices: DeviceView[] } {
    const manages = MANAGERS.includes(this.#role(sub, workspace));
    const devices = this.#rows(
      `SELECT d.sub, COALESCE(u.email, '') AS email, d.device, d.base, d.kind, d.label, d.first_seen, d.last_seen FROM devices d LEFT JOIN users u ON u.sub = d.sub
        WHERE d.workspace = ? AND d.last_seen >= ? AND d.sub IN (SELECT sub FROM members WHERE workspace = ?) AND (? OR d.sub = ?) ORDER BY d.sub, d.last_seen DESC`,
      workspace, nowSeconds() - 31 * 86400, workspace, manages ? 1 : 0, sub,
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
    // Asked again, it waits anew; those past their time, and the person's others it now stands for (the same kind and
    // name: see #lockRequestRows), go.
    this.#run("DELETE FROM lock_requests WHERE workspace = ? AND created_at <= ?", workspace, nowSeconds() - LOCK_REQUEST_TTL_SEC);
    if (label) {
      this.#run("DELETE FROM lock_requests WHERE workspace = ? AND sub = ? AND base != ? AND json_extract(request, '$.kind') = ? AND json_extract(request, '$.label') = ?", workspace, sub, base, kind, label);
    }
    this.#run(
      "INSERT INTO lock_requests (workspace, base, sub, request, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (workspace, base) DO UPDATE SET sub = excluded.sub, request = excluded.request, created_at = excluded.created_at",
      workspace, base, sub, JSON.stringify(request), nowSeconds(),
    );
    this.#changed(workspace, false);
    return { base, sub, email: (this.#one("SELECT email FROM users WHERE sub = ?", sub)?.email as string) ?? "", ...request, code, created_at: nowSeconds() };
  }

  /** Devices waiting to be confirmed: all of them for owners and admins, a member's own for a member. */
  async lockRequests(sub: string, workspace: string): Promise<{ requests: LockRequestView[] }> {
    const rows = this.#lockRequestRows(workspace, sub, this.#role(sub, workspace));
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
    // A relay of its own taken away is no longer among those turned off either.
    const off = parseRelays(this.#one("SELECT ways_off FROM workspaces WHERE id = ?", id)?.ways_off);
    const ways = waysOf(this.env, list, []).map((w) => sameUrl(w.id));
    const kept = off.filter((o) => ways.includes(sameUrl(o)));
    this.ctx.storage.transactionSync(() => {
      this.#run("UPDATE workspaces SET relays = ? WHERE id = ?", list.length ? JSON.stringify(list) : null, id);
      this.#run("UPDATE workspaces SET ways_off = ? WHERE id = ?", kept.length ? JSON.stringify(kept) : null, id);
    });
    this.#changed(id, true);
    return this.#view(sub, id);
  }

  /**
   * One way the workspace's devices reach its stations turned on or off (`ways` of its view: a relay, still.fail's or
   * its own, or a kind of way that is no relay): those off are told to its members in `/v1/me` as `ways_off`, and their
   * devices do not go that way to its stations (client/core-ts mesh.ts). A relay stays on: the web app goes through
   * relays alone, and a device that never reached a station yet knows of no other way there.
   */
  setWay(sub: string, id: string, way: unknown, on: unknown): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    if (typeof way !== "string" || typeof on !== "boolean") fail(400, "invalid_way");
    const row = this.#one("SELECT relays, ways_off FROM workspaces WHERE id = ?", id)!;
    const ways = waysOf(this.env, parseRelays(row.relays), parseRelays(row.ways_off));
    const target = ways.find((w) => sameUrl(w.id) === sameUrl(way as string)) ?? fail(400, "invalid_way");
    const off = ways.filter((w) => (w === target ? !on : !w.on)).map((w) => w.id);
    if (!ways.some((w) => w.kind === "relay" && !off.includes(w.id))) fail(409, "last_relay");
    this.#run("UPDATE workspaces SET ways_off = ? WHERE id = ?", off.length ? JSON.stringify(off) : null, id);
    this.#changed(id, true);
    return this.#view(sub, id);
  }

  /** Fails unless the caller manages the workspace (before a picture it sends is kept: api.ts). */
  manages(sub: string, id: string): void {
    this.#role(sub, id, MANAGERS);
  }

  /** A new name, a new emoji, a new icon (null or "" takes either away; a station's, cleanIcon), or several; what is not given stays. */
  updateWorkspace(sub: string, id: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    this.#role(sub, id, MANAGERS);
    const name = input.name === undefined ? undefined : cleanName(input.name) ?? fail(400, "invalid_name");
    const emoji = input.emoji === undefined ? undefined : input.emoji === null || input.emoji === "" ? null : cleanEmoji(input.emoji) ?? fail(400, "invalid_emoji");
    const icon = input.icon === undefined ? undefined : input.icon === null || input.icon === "" ? null : cleanIcon(input.icon, publicOrigins(this.env)) ?? fail(400, "invalid_icon");
    if (name === undefined && emoji === undefined && icon === undefined) fail(400, "invalid_name");
    if (name !== undefined) this.#run("UPDATE workspaces SET name = ? WHERE id = ?", name, id);
    if (emoji !== undefined) this.#run("UPDATE workspaces SET emoji = ? WHERE id = ?", emoji, id);
    if (icon !== undefined) this.#run("UPDATE workspaces SET icon = ? WHERE id = ?", icon, id);
    // Invitations show the name; the switchers, the mark.
    this.#changed(id, true, name !== undefined ? this.#invitees(id) : []);
    return this.#view(sub, id);
  }

  async deleteWorkspace(sub: string, id: string): Promise<void> {
    this.#role(sub, id, ["owner"]);
    this.#remove(id);
    await this.#delivered();
  }

  /** A workspace gone: its people told, its stations let go. */
  #remove(id: string): void {
    const told = [...this.#members(id), ...this.#invitees(id)];
    const stations = this.#stationsIn(id).map((station) => ({ station, home: this.#memberships(station)[0] }));
    this.ctx.storage.transactionSync(() => {
      for (const table of ["members", "invitations", "added", "station_members", "enrollments", "lock_entries", "lock_aside", "devices", "lock_requests"]) this.#run(`DELETE FROM ${table} WHERE workspace = ?`, id);
      this.#run("DELETE FROM workspaces WHERE id = ?", id);
    });
    this.#tell(told, LIST, { type: "workspace", id });
    // Its stations leave it; those in no other workspace are let go as before.
    for (const { station, home } of stations) this.#left(station, home!);
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
    return this.#view(sub, workspace);
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
    return this.#view(sub, workspace);
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

  async setRole(sub: string, workspace: string, target: string, role: Role): Promise<WorkspaceView> {
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
    const view = this.#view(sub, workspace);
    await this.#delivered();
    return view;
  }

  /** Removes a member; anyone may remove themselves (leave). */
  async removeMember(sub: string, workspace: string, target: string): Promise<void> {
    const mine = this.#role(sub, workspace);
    const row = this.#one("SELECT role FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    if (!row) fail(404, "member_not_found");
    if (target !== sub) {
      if (!MANAGERS.includes(mine)) fail(403, "forbidden");
      if (row!.role === "owner" && mine !== "owner") fail(403, "forbidden");
    }
    if (row!.role === "owner") this.#keepAnOwner(workspace);
    this.#run("DELETE FROM members WHERE workspace = ? AND sub = ?", workspace, target);
    this.#rigsGone(workspace, target);
    this.#revoke(workspace, "sub", target);
    this.#changed(workspace, true, [target]);
    await this.#delivered();
  }

  /** A person no longer in a workspace: the rigs they added there leave it with them. */
  #rigsGone(workspace: string, sub: string): void {
    for (const r of this.#rows("SELECT station FROM station_members WHERE workspace = ? AND rig = 1 AND enrolled_by = ?", workspace, sub)) {
      const station = r.station as string;
      const home = this.#memberships(station)[0]!;
      this.#run("DELETE FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
      this.#left(station, home);
    }
  }

  /**
   * The account deletes itself (DELETE /v1/me; its sessions end in its own object): the workspaces only it is in go as
   * deleteWorkspace takes them, it leaves the others, and what is kept of it goes: its row, push registrations, devices,
   * lock requests, bug reports, and what waits for its email (pending, added, invitations). Refused (409 sole_owner)
   * while it is the only owner of a workspace others are in: they would be left with no one to manage it.
   */
  async deleteAccount(sub: string): Promise<void> {
    const email = this.#one("SELECT email FROM users WHERE sub = ?", sub)?.email as string | undefined;
    const memberships = this.#rows("SELECT workspace, role FROM members WHERE sub = ?", sub).map((r) => ({ workspace: r.workspace as string, role: r.role as Role }));
    const alone = memberships.filter((m) => this.#members(m.workspace).length === 1).map((m) => m.workspace);
    for (const m of memberships) {
      if (m.role !== "owner" || alone.includes(m.workspace)) continue;
      if ((this.#one("SELECT COUNT(*) AS n FROM members WHERE workspace = ? AND role = 'owner'", m.workspace)!.n as number) <= 1) fail(409, "sole_owner");
    }
    for (const workspace of alone) {
      this.#role(sub, workspace, ["owner"]);
      this.#remove(workspace);
    }
    for (const { workspace } of memberships.filter((m) => !alone.includes(m.workspace))) {
      this.#run("DELETE FROM members WHERE workspace = ? AND sub = ?", workspace, sub);
      this.#rigsGone(workspace, sub);
      this.#revoke(workspace, "sub", sub);
      this.#changed(workspace, true);
    }
    this.ctx.storage.transactionSync(() => {
      for (const table of ["push", "devices", "lock_requests"]) this.#run(`DELETE FROM ${table} WHERE sub = ?`, sub);
      this.#run("DELETE FROM feedback_replies WHERE feedback IN (SELECT id FROM feedback WHERE account = ?)", sub);
      this.#run("DELETE FROM feedback WHERE account = ?", sub);
      if (email) {
        this.#run("DELETE FROM pending WHERE lower(email) = lower(?)", email);
        this.#run("DELETE FROM added WHERE lower(email) = lower(?)", email);
        this.#run("DELETE FROM invitations WHERE lower(email) = lower(?)", email);
      }
      this.#run("DELETE FROM users WHERE sub = ?", sub);
    });
    this.#tell([sub], LIST);
    await this.#delivered();
  }

  #keepAnOwner(workspace: string): void {
    const owners = this.#one("SELECT COUNT(*) AS n FROM members WHERE workspace = ? AND role = 'owner'", workspace)!.n as number;
    if (owners <= 1) fail(409, "last_owner");
  }

  // ── stations ────────────────────────────────────────────────────────────

  async createEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    this.#role(sub, workspace, MANAGERS);
    return this.#enrollment(sub, workspace, name);
  }

  /**
   * A rig's enrollment: any member adds one, which is theirs (a rig holds nothing of the workspace and asks nothing
   * of its stations; what runs on it is its person's to grant). A station is its managers' to add.
   */
  async createRigEnrollment(sub: string, workspace: string, name: string): Promise<{ token: string; expires_at: number }> {
    this.#role(sub, workspace);
    return this.#enrollment(sub, workspace, name, true);
  }

  async #enrollment(sub: string, workspace: string, name: unknown, rig = false): Promise<{ token: string; expires_at: number }> {
    const clean = cleanName(name) ?? fail(400, "invalid_name");
    if (this.#stationsFull(workspace)) fail(429, "too_many_stations");
    const token = randomSecret();
    const expires = nowSeconds() + ENROLLMENT_TTL_SEC;
    this.#run("DELETE FROM enrollments WHERE expires_at <= ?", nowSeconds());
    this.#run("INSERT INTO enrollments (token_hash, workspace, name, created_by, expires_at, rig) VALUES (?, ?, ?, ?, ?, ?)", await digest(token), workspace, clean, sub, expires, rig ? 1 : null);
    return { token, expires_at: expires };
  }

  #stationsFull(workspace: string): boolean {
    const stations = this.#one("SELECT COUNT(*) AS n FROM station_members WHERE workspace = ?", workspace)!.n as number;
    return stations >= STATIONS_PER_WORKSPACE;
  }

  /**
   * A station redeems an enrollment token. The caller has checked that the station holds the key for `station`.
   * Re-enrolling moves the station: it leaves every other workspace it is in. Joining (`join`, POST /v1/stations/join)
   * it stays in them and joins this one too; a station whose home is locked joins locked
   * workspaces only (an unlocked one's members are this cloud's word, which the home's lock took away). It pins each
   * locked workspace's lock there. `home` is the workspace it joined first, whose say goes for the machine.
   * `rig`: the machine enrolls as a rig, which a rig's token alone makes (a station's program from before rigs would
   * serve the workspace as a station under a rig's name) and no other does; a rig is in one workspace, so it never
   * joins. Its answer names its person (`rig`).
   */
  async enroll(token: string, station: string, version: string | null, join = false, locks = false, rig = false): Promise<{ workspace: string; workspace_name: string; name: string; home: string; rig?: { owner: string; owner_email: string; owner_name: string } }> {
    const hash = await digest(token);
    const row = this.#one("SELECT workspace, name, created_by, rig FROM enrollments WHERE token_hash = ? AND expires_at > ?", hash, nowSeconds());
    if (!row) fail(404, "enrollment_not_found");
    if ((row!.rig === 1) !== rig) fail(409, row!.rig === 1 ? "rig_enrollment" : "station_enrollment");
    if (rig && join) fail(409, "rig_enrollment");
    const workspace = row!.workspace as string;
    const was = this.#memberships(station);
    // A rig stays one, a station a station, where it is: its kind changes only by removing it first.
    if (join && this.#one("SELECT 1 AS x FROM station_members WHERE station = ? AND rig = 1", station)) fail(409, "rig_enrollment");
    const member = was.includes(workspace);
    // Across a lock: a locked home into an unlocked workspace; or into a locked one, by a station that would not pin it.
    // A chain moved is on or off by its root's log, which this cloud never reads: into one as into a locked one; out
    // of one as the home, no refusal on a guess (the asker's own check comes first, the station's own after: it takes
    // no members of a workspace that is off while its home is on, station/src/cloud/state.ts `leftOut`).
    const homeOn = was.length > 0 && this.#locked(was[0]!) && !this.#moved(was[0]!);
    if (join && !member && was.length > 0 && (homeOn ? !this.#locked(workspace) : this.#locked(workspace) && !locks)) fail(409, "locked_workspace");
    // Several tokens may be out at once: the last free place goes to the first redeemed.
    if (!member && this.#stationsFull(workspace)) fail(429, "too_many_stations");
    const left = join ? [] : was.filter((w) => w !== workspace);
    this.ctx.storage.transactionSync(() => {
      this.#run("DELETE FROM enrollments WHERE token_hash = ?", hash);
      this.#run("INSERT INTO stations (id, last_seen, version) VALUES (?, ?, ?) ON CONFLICT (id) DO UPDATE SET last_seen = excluded.last_seen, version = excluded.version", station, nowSeconds(), version);
      for (const other of left) this.#run("DELETE FROM station_members WHERE workspace = ? AND station = ?", other, station);
      if (join && member) this.#run("UPDATE station_members SET name = ? WHERE workspace = ? AND station = ?", row!.name, workspace, station);
      else {
        // Enrolled again where it is (moving), it keeps its emoji and icon there.
        this.#run(`INSERT INTO station_members (workspace, station, name, enrolled_at, enrolled_by, rig) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT (workspace, station) DO UPDATE SET name = excluded.name, enrolled_at = excluded.enrolled_at, enrolled_by = excluded.enrolled_by, rig = excluded.rig`,
          workspace, station, row!.name, nowSeconds(), row!.created_by, rig ? 1 : null);
      }
    });
    const w = this.#one("SELECT name FROM workspaces WHERE id = ?", workspace)!;
    this.#changed(workspace, true);
    for (const other of left) this.#changed(other, true);
    // Already connected (re-enrolled while running): it learns where it is now, before the answer when it left some.
    this.#sendState(station, left.length > 0);
    const home = this.#memberships(station)[0]!;
    const owner = rig ? this.#one("SELECT email, name FROM users WHERE sub = ?", row!.created_by) : undefined;
    await this.#delivered();
    return {
      workspace, workspace_name: w.name as string, name: row!.name as string, home,
      ...(rig ? { rig: { owner: row!.created_by as string, owner_email: (owner?.email as string | undefined) ?? "", owner_name: (owner?.name as string | undefined) ?? "" } } : {}),
    };
  }

  /** A new name, a new emoji, a new icon (null or "" takes either away), or several; what is not given stays. */
  updateStation(sub: string, workspace: string, station: string, input: { name?: unknown; emoji?: unknown; icon?: unknown }): WorkspaceView {
    if (!MANAGERS.includes(this.#role(sub, workspace)) && !this.#one("SELECT 1 AS x FROM station_members WHERE station = ? AND workspace = ? AND rig = 1 AND enrolled_by = ?", station, workspace, sub)) fail(403, "forbidden");
    const name = input.name === undefined ? undefined : cleanName(input.name) ?? fail(400, "invalid_name");
    const emoji = input.emoji === undefined ? undefined : input.emoji === null || input.emoji === "" ? null : cleanEmoji(input.emoji) ?? fail(400, "invalid_emoji");
    const icon = input.icon === undefined ? undefined : input.icon === null || input.icon === "" ? null : cleanIcon(input.icon, publicOrigins(this.env)) ?? fail(400, "invalid_icon");
    if (name === undefined && emoji === undefined && icon === undefined) fail(400, "invalid_name");
    if (name !== undefined) this.#run("UPDATE station_members SET name = ? WHERE station = ? AND workspace = ?", name, station, workspace);
    if (emoji !== undefined) this.#run("UPDATE station_members SET emoji = ? WHERE station = ? AND workspace = ?", emoji, station, workspace);
    if (icon !== undefined) this.#run("UPDATE station_members SET icon = ? WHERE station = ? AND workspace = ?", icon, station, workspace);
    this.#changed(workspace, false);
    if (name !== undefined) this.#sendState(station);
    return this.#view(sub, workspace);
  }

  /**
   * What a station is here: a whole one (`full`), or one that only runs tasks (`tasks`: a rig). It stays whose it is,
   * the member who added it (`enrolled_by`), and only they change its mode, either way (the user, 2026-11-10); whole
   * again only where they manage the workspace, as a member adds no whole station. One no member added (its adder
   * left, or the operator enrolled it) a workspace owner may make one that runs tasks, and it is theirs then. The
   * machine itself becomes it only by what that person's device asked of it (tasks) or they signed (full), which the
   * app brings it first: this lists it so. A station in several workspaces stays whole (a rig is in one), and a
   * workspace keeps one whole station at least.
   */
  async setStationMode(sub: string, workspace: string, station: string, mode: unknown): Promise<WorkspaceView> {
    const role = this.#role(sub, workspace);
    if (mode !== "full" && mode !== "tasks") fail(400, "invalid_name");
    const row = this.#one("SELECT rig, enrolled_by FROM station_members WHERE station = ? AND workspace = ?", station, workspace) ?? fail(404, "station_not_found");
    if ((row.rig === 1) !== (mode === "tasks")) {
      const mine = row.enrolled_by === sub;
      if (mode === "tasks") {
        const nobodys = !mine && !this.#one("SELECT 1 AS x FROM members WHERE workspace = ? AND sub = ?", workspace, row.enrolled_by ?? "");
        if (!mine && !(nobodys && role === "owner")) fail(403, "forbidden");
        if (this.#memberships(station).length !== 1) fail(409, "station_in_others");
        if (!this.#one("SELECT 1 AS x FROM station_members WHERE workspace = ? AND rig IS NULL AND station != ?", workspace, station)) fail(409, "last_station");
        // Theirs already, or (no member's) theirs now.
        this.#run("UPDATE station_members SET rig = 1, enrolled_by = ? WHERE station = ? AND workspace = ?", sub, station, workspace);
      } else {
        if (!mine || !MANAGERS.includes(role)) fail(403, "forbidden");
        this.#run("UPDATE station_members SET rig = NULL WHERE station = ? AND workspace = ?", station, workspace);
      }
      this.#changed(workspace, true);
      this.#sendState(station, true);
      await this.#delivered();
    }
    return this.#view(sub, workspace);
  }

  /** Takes a station out of this workspace only; it stays in the others it is in. A rig: its person may too. */
  async removeStation(sub: string, workspace: string, station: string): Promise<void> {
    const mine = this.#role(sub, workspace);
    const row = this.#one("SELECT rig, enrolled_by FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
    if (!MANAGERS.includes(mine) && !(row?.rig === 1 && row.enrolled_by === sub)) fail(403, "forbidden");
    const home = this.#memberships(station)[0];
    if (!row) return;
    this.#run("DELETE FROM station_members WHERE station = ? AND workspace = ?", station, workspace);
    this.#changed(workspace, true);
    this.#left(station, home!);
    await this.#delivered();
  }

  /**
   * A station has left a workspace (its row gone already; `home` its home before): in none now, it is let go (4004, as
   * when a station was in one); else it hears where it is now, and, its home gone, the workspace taking over (whose
   * views now name it home) is changed too.
   */
  #left(station: string, home: string): void {
    const now = this.#memberships(station);
    if (now.length === 0) {
      this.#run("DELETE FROM stations WHERE id = ?", station);
      this.#disconnect(station);
      return;
    }
    if (now[0] !== home) this.#changed(now[0]!, true);
    // Until it hears it, it takes that workspace's members still.
    this.#sendState(station, true);
  }

  /** Whether a station is enrolled (in some workspace). */
  isStation(station: string): boolean {
    return this.#one("SELECT 1 AS found FROM station_members WHERE station = ?", station) !== undefined;
  }

  // ── what a station's own object asks (station.ts) ──────────────────────

  /**
   * A station's presence socket opens on its object: when it was here noted, it is live, and what to tell it (`frame`,
   * null for one in no workspace, which is turned away).
   */
  stationConnected(station: string, version: string | null): { frame: string | null; gen: number } {
    if (this.#memberships(station).length === 0) return { frame: null, gen: 0 };
    this.#run("UPDATE stations SET last_seen = ?, version = COALESCE(?, version) WHERE id = ?", nowSeconds(), version, station);
    return { frame: this.#frame(station), gen: this.#opened("station", station) };
  }

  /** What a station is told as it changed: its state frame, null in no workspace now (it is let go). */
  stationState(station: string): string | null {
    return this.#frame(station);
  }

  /** A station's presence socket, opened as `gen`, closed or went silent on its object: when it was here. */
  stationLeft(station: string, gen: number): void {
    this.#run("UPDATE stations SET last_seen = ? WHERE id = ?", nowSeconds(), station);
    this.#run("DELETE FROM live WHERE kind = 'station' AND key = ? AND gen = ?", station, gen);
  }

  /** What a station said on its socket (on its object), and the frames that answer it. */
  async stationSaid(station: string, message: string): Promise<string[]> {
    const out: string[] = [];
    await this.#said(station, message, (frame) => out.push(frame));
    return out;
  }

  /** A mstill.fail's role, which its credential names (grants.ts). */
  memberRole(sub: string, workspace: string): Role {
    return this.#role(sub, workspace);
  }

  // ── revocations ─────────────────────────────────────────────────────────
  // A mstill.fail's credential lasts 30 days and stations check it offline, so what takes one back is told to them: every
  // credential of an account (`sub`) or of a sign-in session (`sid`) issued up to `at` is refused from then on. Each
  // station hears it at once if connected, and all of its workspaces' (of the last 31 days) when it connects.

  /** Takes back an account's credentials in a workspace, or one session's. */
  #revoke(workspace: string, kind: "sub" | "sid", id: string): void {
    const at = nowSeconds();
    this.#run("INSERT INTO revocations (workspace, kind, id, at) VALUES (?, ?, ?, ?) ON CONFLICT (workspace, kind, id) DO UPDATE SET at = excluded.at", workspace, kind, id, at);
    this.#run("DELETE FROM revocations WHERE at < ?", at - REVOCATION_DAYS * 86400);
    // Which workspace's: a station in several takes it back there alone (one from before them reads no such field).
    const frame = JSON.stringify({ type: "revoke", kind, id, at, workspace });
    for (const station of this.#stationsIn(workspace)) {
      this.#deliver("station", station, { frames: [frame] }, { urgent: true });
      for (const ws of this.#presence(station)) {
        try {
          ws.send(frame);
        } catch {
          // Closing already: it hears all of them when it connects again.
        }
      }
    }
  }

  /** Sessions signed out (all of an account's with none named): their credentials go, in every workspace of the account. */
  async revokeSessions(sub: string, sids: string[] | null): Promise<void> {
    if (sids === null) this.#run("DELETE FROM push WHERE sub = ?", sub);
    else for (const sid of sids) this.#run("DELETE FROM push WHERE sub = ? AND sid = ?", sub, sid);
    for (const row of this.#rows("SELECT workspace FROM members WHERE sub = ?", sub)) {
      const workspace = row.workspace as string;
      if (sids === null) this.#revoke(workspace, "sub", sub);
      else for (const sid of sids) this.#revoke(workspace, "sid", sid);
    }
    await this.#delivered();
  }

  // ── push registrations ──────────────────────────
  // A device's push subscription (Web Push) or token (FCM, APNs) is registered with each account signed in on it, one row
  // each, which belongs to the sign-in session that registered it last; signing that session out takes it
  // (revokeSessions).

  /** Registers a device's push subscription or token to an account's session (moving it there from the account's other). */
  registerPush(sub: string, sid: string, device: PushDevice, lang: Lang = "zh", shows: Shows | null = null): void {
    const [column, value] = device.kind === "web" ? ["endpoint", device.endpoint] : ["token", device.token];
    this.#run(`DELETE FROM push WHERE sub = ? AND ${column} = ?`, sub, value);
    const said = shows ? JSON.stringify(shows) : null;
    if (device.kind === "web") {
      this.#run("INSERT INTO push (id, sub, sid, kind, endpoint, p256dh, auth, created, lang, shows) VALUES (?, ?, ?, 'web', ?, ?, ?, ?, ?, ?)", ulid(), sub, sid, device.endpoint, device.p256dh, device.auth, nowSeconds(), lang, said);
    } else if (device.kind === "apns") {
      this.#run("INSERT INTO push (id, sub, sid, kind, token, sandbox, created, lang, shows) VALUES (?, ?, ?, 'apns', ?, ?, ?, ?, ?)", ulid(), sub, sid, device.token, device.sandbox ? 1 : 0, nowSeconds(), lang, said);
    } else {
      this.#run("INSERT INTO push (id, sub, sid, kind, token, created, lang, shows) VALUES (?, ?, ?, 'fcm', ?, ?, ?, ?)", ulid(), sub, sid, device.token, nowSeconds(), lang, said);
    }
    // An account's oldest go past a few dozen devices.
    this.#run("DELETE FROM push WHERE sub = ? AND id NOT IN (SELECT id FROM push WHERE sub = ? ORDER BY id DESC LIMIT ?)", sub, sub, LIMITS.pushPerUser);
  }

  /** Takes a device's registration off an account (another account's is left alone). */
  unregisterPush(sub: string, device: { endpoint: string } | { token: string }): void {
    if ("endpoint" in device) this.#run("DELETE FROM push WHERE sub = ? AND endpoint = ?", sub, device.endpoint);
    else this.#run("DELETE FROM push WHERE sub = ? AND token = ?", sub, device.token);
  }

  /** The credential that took each of these tokens (push.ts), kept with their registrations. */
  pushApps(took: { token: string; app: string }[]): void {
    for (const { token, app } of took) this.#run("UPDATE push SET app = ? WHERE token = ?", app, token);
  }

  /** Devices whose push service said they are gone: their registrations with every account. */
  dropPush(devices: PushDevice[]): void {
    for (const device of devices) {
      if (device.kind === "web") this.#run("DELETE FROM push WHERE endpoint = ?", device.endpoint);
      else this.#run("DELETE FROM push WHERE token = ?", device.token);
    }
  }

  /**
   * Where a station's notices go: the workspace they are of (`wanted`, else the station's home), and for each email
   * (lowercased) the registrations of the workspace's members signed in with it. Null for a station not in it.
   */
  pushTargets(station: string, emails: string[], wanted: string | null = null): { workspace: string; devices: Record<string, PushRegistration[]> } | null {
    const memberships = this.#memberships(station);
    const workspace = wanted ?? memberships[0];
    if (!workspace || !memberships.includes(workspace)) return null;
    const devices: Record<string, PushRegistration[]> = {};
    for (const email of new Set(emails.map((e) => e.toLowerCase()))) {
      devices[email] = this.#rows(
        `SELECT p.id, p.kind, p.endpoint, p.p256dh, p.auth, p.token, p.sandbox, p.lang, p.shows, p.app FROM push p JOIN users u ON u.sub = p.sub JOIN members m ON m.sub = p.sub AND m.workspace = ?
         WHERE lower(u.email) = ? ORDER BY p.id LIMIT ?`,
        workspace, email, LIMITS.pushPerUser,
      ).map((r): PushRegistration => {
        const lang = langOf(r.lang as string | null);
        const shows = typeof r.shows === "string" ? showsOf(JSON.parse(r.shows) as Record<string, unknown>) : null;
        const id = r.id as string;
        if (r.kind === "web") return { id, lang, shows, kind: "web", endpoint: r.endpoint as string, p256dh: r.p256dh as string, auth: r.auth as string };
        const app = typeof r.app === "string" ? { app: r.app } : {};
        if (r.kind === "apns") return { id, lang, shows, kind: "apns", token: r.token as string, sandbox: r.sandbox === 1, ...app };
        return { id, lang, shows, kind: "fcm", token: r.token as string, ...app };
      });
    }
    return { workspace, devices };
  }

  // ── moving into another cloud (move.ts) ─────────────────────────────────

  /** Every table but what is of this object's own sockets and counts (MOVE_SKIPPED), row by row. */
  moveExport(): Record<string, Row[]> {
    const tables = this.#rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '\\_%' ESCAPE '\\' AND name NOT LIKE 'sqlite_%'").map((r) => r.name as string);
    return Object.fromEntries(tables.filter((t) => !MOVE_SKIPPED.has(t)).map((t) => [t, this.#rows(`SELECT * FROM "${t}"`)]));
  }

  /** Each of `tables` made what another cloud's moveExport said, in one transaction (its rows taken out first); what
   * a table here does not have of a row's columns refuses the whole. How many rows each now has. */
  moveImport(tables: Record<string, Row[]>): Record<string, number> {
    const here = new Set(this.#rows("SELECT name FROM sqlite_master WHERE type = 'table'").map((r) => r.name as string));
    return this.ctx.storage.transactionSync(() => {
      const counts: Record<string, number> = {};
      for (const [table, rows] of Object.entries(tables)) {
        if (MOVE_SKIPPED.has(table) || !here.has(table) || !/^[a-z_]+$/.test(table)) throw new Error(`move: no table ${table}`);
        const columns = new Set(this.#rows(`PRAGMA table_info("${table}")`).map((r) => r.name as string));
        this.#run(`DELETE FROM "${table}"`);
        for (const row of rows) {
          const names = Object.keys(row);
          if (names.some((n) => !columns.has(n))) throw new Error(`move: ${table} has no column of ${names.join(",")}`);
          this.#run(`INSERT INTO "${table}" (${names.map((n) => `"${n}"`).join(", ")}) VALUES (${names.map(() => "?").join(", ")})`, ...names.map((n) => row[n] as SqlStorageValue));
        }
        counts[table] = rows.length;
      }
      return counts;
    });
  }

  /** The accounts there are (moving each one's object: move.ts). */
  moveAccounts(): string[] {
    return this.#rows("SELECT sub FROM users ORDER BY sub").map((r) => r.sub as string);
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
    return this.#rows(`SELECT sub, email, name, ${SHOWN_PICTURE} AS picture, created_at, last_seen, admitted, beta, blocked FROM users ORDER BY created_at DESC`).map((row) => {
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

  /** The emails the admin gave rights to that nobody has signed in with yet, the latest first. */
  adminPending(): AdminPending[] {
    return this.#rows("SELECT email, beta, may_create, added_at FROM pending ORDER BY added_at DESC").map((row) => ({
      email: row.email as string, beta: Boolean(row.beta), may_create: Boolean(row.may_create), added_at: row.added_at as number,
    }));
  }

  /**
   * The admin gives rights to an email, which needs no one to have signed in with it: the test channel, the standard plan
   * (`beta`, `may_create`; one not given, or null, stays as it was). An account already signed in with it has them at once (`sub`,
   * the first such); otherwise the account that first signs in with it does (#takePending; `sub` null).
   */
  setPending(by: string, email: unknown, beta: boolean | null | undefined, mayCreate: boolean | null | undefined): { email: string; sub: string | null } {
    const address = typeof email === "string" ? email.trim().toLowerCase() : "";
    if (!/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(address)) fail(400, "invalid_email");
    const accounts = this.#byEmail(address);
    if (accounts.length > 0) {
      for (const sub of accounts) {
        if (typeof beta === "boolean") this.setBeta(sub, beta);
        if (typeof mayCreate === "boolean") this.setMayCreate(sub, mayCreate);
      }
      return { email: address, sub: accounts[0]! };
    }
    const on = (v: boolean | null | undefined) => (typeof v === "boolean" ? (v ? 1 : 0) : null);
    this.#run(`INSERT INTO pending (email, beta, may_create, added_by, added_at) VALUES (?, COALESCE(?, 0), COALESCE(?, 0), ?, ?)
      ON CONFLICT (email) DO UPDATE SET beta = COALESCE(?, beta), may_create = COALESCE(?, may_create)`,
      address, on(beta), on(mayCreate), by, nowSeconds(), on(beta), on(mayCreate));
    return { email: address, sub: null };
  }

  /** Takes back the rights given to an email nobody has signed in with yet. */
  removePending(email: unknown): { ok: true } {
    this.#run("DELETE FROM pending WHERE email = ?", typeof email === "string" ? email.trim().toLowerCase() : "");
    return { ok: true };
  }

  /** Notes that the admin blocked the account or let it back (the account's own object is what keeps it out). */
  setBlocked(sub: string, on: boolean): void {
    this.#run("UPDATE users SET blocked = ? WHERE sub = ?", on ? 1 : null, sub);
  }

  /** Lets an account into the test channel (BETA_ORIGIN), or out of it. */
  setBeta(sub: string, on: boolean): { sub: string; beta: boolean } {
    if (!this.#one("SELECT 1 AS x FROM users WHERE sub = ?", sub)) fail(404, "user_not_found");
    this.#run("UPDATE users SET beta = ? WHERE sub = ?", on ? 1 : null, sub);
    this.#betaTold(sub);
    // Its `/v1/me` says so: its devices read it again (the 测试版 switch of its stations comes or goes at once).
    this.#tell([sub], LIST);
    return { sub, beta: on };
  }

  /** Whether the account may use the test channel (its object asks once, then is told: #betaTold). */
  isBeta(sub: string): boolean {
    return Boolean(this.#one("SELECT beta FROM users WHERE sub = ?", sub)?.beta);
  }

  /** The account's object keeps whether it is let into the test channel (account.ts `live`): it is told it now. */
  #betaTold(sub: string): void {
    this.#deliver("account", sub, { beta: Boolean(this.#one("SELECT beta FROM users WHERE sub = ?", sub)?.beta) }, { always: true });
  }

  /** The operator removes a workspace as its owner would; one made for a company may have no owner signed in yet. */
  async adminDeleteWorkspace(id: string): Promise<void> {
    if (!this.#one("SELECT 1 AS x FROM workspaces WHERE id = ?", id)) fail(404, "workspace_not_found");
    this.#remove(id);
    await this.#delivered();
  }

  /**
   * The admin makes a workspace for a company (「企业 workspace」): its owners by email, members at once or
   * when they first sign in, and limits of its own, the creator's plan aside. The admin is its creator but not in it.
   */
  adminCreateWorkspace(by: string, input: { name?: unknown; owners?: unknown; members?: unknown; stations?: unknown }): { id: string; joined: string[]; added: string[] } {
    const name = cleanName(input.name) ?? fail(400, "invalid_name");
    const owners = emailsOf(input.owners);
    const limits = limitsOf(input);
    if (owners.length > limits.members) fail(429, "too_many_members");
    const id = ulid();
    this.#run("INSERT INTO workspaces (id, name, created_by, created_at, max_members, max_stations) VALUES (?, ?, ?, ?, ?, ?)", id, name, by, nowSeconds(), limits.members, limits.stations);
    const { joined, added } = this.#addEmails(by, id, "owner", owners);
    return { id, joined, added };
  }

  /** The admin sets how many people a workspace may hold; stations have the shared limit. */
  adminSetLimits(workspace: string, input: { members?: unknown; stations?: unknown }): { members: number; stations: number } {
    if (!this.#one("SELECT 1 AS x FROM workspaces WHERE id = ?", workspace)) fail(404, "workspace_not_found");
    const limits = limitsOf(input);
    this.#run("UPDATE workspaces SET max_members = ?, max_stations = ? WHERE id = ?", limits.members, limits.stations, workspace);
    return limits;
  }

  /**
   * An enrollment the admin makes without being in the workspace: a station installed for a company, before it is
   * theirs. Only a workspace made for a company (with its own member limit) none of whose owners has signed in yet; from then
   * on its stations are its owners' to add.
   */
  async adminEnrollment(by: string, workspace: string, name: unknown): Promise<{ token: string; expires_at: number }> {
    const w = this.#one("SELECT max_members FROM workspaces WHERE id = ?", workspace);
    if (!w) fail(404, "workspace_not_found");
    if (w!.max_members === null || this.#hasOwner(workspace)) fail(409, "not_before_owner");
    return this.#enrollment(by, workspace, name);
  }

  #hasOwner(workspace: string): boolean {
    return Boolean(this.#one("SELECT 1 AS x FROM members WHERE workspace = ? AND role = 'owner' LIMIT 1", workspace));
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
      COALESCE(${SHOWN_PICTURE}, '') AS picture, m.role, m.added_at, u.last_seen FROM members m LEFT JOIN users u ON u.sub = m.sub ORDER BY m.added_at`));
    const stations = group<StationView>(this.#stationViews(null) as unknown as Row[]);
    const invitations = group<AdminWorkspace["invitations"][number]>(this.#rows(`SELECT i.workspace, i.id, i.role, i.email, i.created_by, i.expires_at,
      COALESCE(NULLIF(u.name, ''), u.email, '') AS inviter FROM invitations i LEFT JOIN users u ON u.sub = i.created_by WHERE i.expires_at > ? ORDER BY i.expires_at`, now));
    const added = group<AddedView>(this.#rows("SELECT workspace, email, role, added_by, added_at FROM added ORDER BY added_at"));
    // As #plan has it, in the same read.
    const plan = (w: Row): Plan => w.sub === null ? "free" : isAdmin(this.env, w.email as string) ? "admin"
      : w.admitted === "code" || w.admitted === "granted" || (w.admitted === null && w.member) ? "standard" : "free";
    return this.#rows(`SELECT w.id, w.name, w.created_at, w.max_members, w.max_stations, u.sub, u.email, u.name AS user_name, ${SHOWN_PICTURE} AS picture, u.admitted,
      EXISTS (SELECT 1 FROM members m WHERE m.sub = u.sub) AS member FROM workspaces w
      LEFT JOIN users u ON u.sub = w.created_by ORDER BY w.created_at DESC`).map((w) => ({
      id: w.id as string,
      name: w.name as string,
      created_at: w.created_at as number,
      created_by: w.sub === null ? null : { sub: w.sub as string, email: w.email as string, name: w.user_name as string, picture: w.picture as string },
      members: members.get(w.id as string) ?? [],
      stations: stations.get(w.id as string) ?? [],
      invitations: invitations.get(w.id as string) ?? [],
      added: added.get(w.id as string) ?? [],
      // As adminEnrollment has it: one made for a company, none of its owners signed in yet.
      enrollable: w.max_members !== null && !(members.get(w.id as string) ?? []).some((m) => m.role === "owner"),
      // As #memberCap has it: its own, or its creator's plan's. Stations use the same cap for all workspaces.
      station_seats: STATIONS_PER_WORKSPACE,
      ...(w.max_members !== null && w.max_stations !== null
        ? { seats: w.max_members as number, plan: "enterprise" as const }
        : { seats: PLANS[plan(w)].members, plan: plan(w) }),
    }));
  }

  /**
   * How loaded this object is, for the console (its 中继 page, relay-load.ts): its calls an hour by what they serve (the
   * last HOURS_KEPT hours, oldest first), the sockets it still holds (those of before their objects, which leave as
   * they reconnect), the objects told what is for their sockets, deliveries waiting to be tried again, and its storage.
   */
  adminLoad(): DirectoryLoad {
    this.#keepCounts();
    const now = nowSeconds();
    const first = Math.floor(now / 3600) - HOURS_KEPT + 1;
    const families: Record<string, number[]> = {};
    for (const r of this.#rows("SELECT hour, family, n FROM hits WHERE hour >= ? ORDER BY hour", first)) {
      (families[r.family as string] ??= new Array<number>(HOURS_KEPT).fill(0))[(r.hour as number) - first] = r.n as number;
    }
    const held = this.ctx.getWebSockets().map((ws) => ws.deserializeAttachment() as Attachment);
    const live = (kind: string) => this.#one("SELECT COUNT(*) AS n FROM live WHERE kind = ?", kind)!.n as number;
    return {
      at: now,
      calls: { start: first * 3600, step: 3600, families },
      held: { devices: held.filter((a) => "sub" in a).length, stations: held.filter((a) => "station" in a && !a.dropped).length },
      live: { accounts: live("account"), stations: live("station") },
      waiting: this.#one("SELECT COUNT(*) AS n FROM outbox")!.n as number,
      bytes: this.ctx.storage.sql.databaseSize,
    };
  }

  /** The calls counted since it last ran, kept (the cron's minute: tellAdmins; adminLoad), and the hours past HOURS_KEPT gone. */
  #keepCounts(): void {
    const counts = counted.get(this);
    if (!counts?.size) return;
    this.ctx.storage.transactionSync(() => {
      for (const [k, n] of counts) {
        const [hour, family] = k.split(" ");
        this.#run("INSERT INTO hits (hour, family, n) VALUES (?, ?, ?) ON CONFLICT (hour, family) DO UPDATE SET n = n + excluded.n", Number(hour), family!, n);
      }
      this.#run("DELETE FROM hits WHERE hour <= ?", Math.floor(nowSeconds() / 3600) - HOURS_KEPT);
    });
    counts.clear();
  }

  inviteCodes(): InviteCodeView[] {
    return this.#rows(`SELECT c.code, c.note, c.beta, c.created_at, c.expires_at, c.revoked_at, c.used_at, u.sub, u.email, u.name, ${SHOWN_PICTURE} AS picture, w.id, w.name AS workspace_name
      FROM invite_codes c LEFT JOIN users u ON u.sub = c.used_by LEFT JOIN workspaces w ON w.id = c.workspace ORDER BY c.created_at DESC, c.code`).map((row) => ({
      code: row.code as string,
      note: row.note as string,
      beta: Boolean(row.beta),
      created_at: row.created_at as number,
      expires_at: row.expires_at as number,
      revoked_at: row.revoked_at as number | null,
      used_at: row.used_at as number | null,
      used_by: row.sub === null ? null : { sub: row.sub as string, email: row.email as string, name: row.name as string, picture: row.picture as string },
      workspace: row.id === null ? null : { id: row.id as string, name: row.workspace_name as string },
    }));
  }

  /** A code; with `beta`, the account that redeems it is let into the test channel too. */
  createInviteCode(sub: string, note: unknown, days: unknown, beta = false): InviteCodeView {
    const clean = typeof note === "string" ? note.trim().replace(/\s+/g, " ") : "";
    if (clean.length > 200) fail(400, "invalid_note");
    const ttl = days === undefined ? CODE_TTL_DAYS : Number.isInteger(days) && (days as number) >= 1 && (days as number) <= 365 ? (days as number) : fail(400, "invalid_expiry");
    const code = newCode();
    const now = nowSeconds();
    this.#run("INSERT INTO invite_codes (code, note, created_by, created_at, expires_at, beta) VALUES (?, ?, ?, ?, ?, ?)", code, clean, sub, now, now + ttl * 24 * 60 * 60, beta ? 1 : null);
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
    // A station's report is of the workspace it names (one it is in), else of its home.
    const memberships = input.station ? this.#memberships(input.station) : [];
    if (input.workspace && !memberships.includes(input.workspace)) fail(403, "not_in_workspace");
    const workspace = input.station ? (input.workspace ?? memberships[0] ?? null) : null;
    const number = ((this.#one("SELECT MAX(number) AS n FROM feedback")?.n as number | null) ?? 0) + 1;
    const id = ulid();
    this.#run(
      `INSERT INTO feedback (id, number, key, channel, sender, station, workspace, account, title, body, area, reporter, context, logs, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?, ?)`,
      id, number, input.key, input.channel, input.sender, input.station, workspace, input.account, input.title, input.body, input.area, input.reporter, input.context, input.logs, now, now,
    );
    return { id, number, duplicate: false };
  }

  /** The reports, newest first, with the station, workspace and account they came from, and their replies. */
  adminFeedback(): AdminFeedback[] {
    const replies = new Map<string, FeedbackReply[]>();
    for (const r of this.#rows(`SELECT * FROM feedback_replies WHERE feedback IN (SELECT id FROM feedback ORDER BY number DESC LIMIT ${FEEDBACK_LISTED}) ORDER BY created_at, rowid`)) {
      const team = r.author === "team";
      const reply: FeedbackReply = {
        id: r.id as string,
        from: team ? "team" : "reporter",
        by: r.by as string,
        text: r.text as string,
        created_at: r.created_at as number,
        delivery: !team ? null : r.delivered_at !== null ? "delivered" : "pending",
        delivered_at: (r.delivered_at as number | null) ?? null,
      };
      const list = replies.get(r.feedback as string) ?? [];
      list.push(reply);
      replies.set(r.feedback as string, list);
    }
    const rows = this.#rows(`SELECT f.*, s.name AS station_name, w.name AS workspace_name, u.email AS account_email, u.name AS account_name
      FROM feedback f LEFT JOIN station_members s ON s.station = f.station AND s.workspace = f.workspace LEFT JOIN workspaces w ON w.id = f.workspace LEFT JOIN users u ON u.sub = f.account
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
        replies: replies.get(r.id as string) ?? [],
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

  /**
   * The workspace a station's report came from a chat of: the one the station said (context.workspace, from stations
   * that say it), else the one its link names (context.link, `/o/<workspace>/…`); only while the station is in it.
   * Not the report's `workspace`, which is the station's home where it said none. null: none to show it in.
   */
  #chatWorkspace(station: string | null, context: string | null): string | null {
    if (!station) return null;
    const said = contextOf(context);
    const named = typeof said.workspace === "string" ? said.workspace : typeof said.link === "string" ? (/\/o\/([0-9A-HJKMNP-TV-Z]{26})\//.exec(said.link)?.[1] ?? null) : null;
    return named && this.#memberships(station).includes(named) ? named : null;
  }

  /**
   * The team's reply on a report (`by`: the admin's email or the feedback monitor), shown to the people of the chat it
   * was reported from, in its workspace's members' apps (feedbackOf), never given to a station or its agents: each of
   * them is told on its events socket. One with no such chat (an account's report, or one whose chat cannot be found)
   * reaches no one: answered why (`undeliverable`), not kept.
   */
  replyToFeedback(id: string, by: string, text: string): { id: string; delivery: "pending" } | { undeliverable: "no_station" | "no_chat" } {
    const report = this.#one("SELECT station, context FROM feedback WHERE id = ?", id);
    if (!report) fail(404, "feedback_not_found");
    if (!report!.station) return { undeliverable: "no_station" };
    const workspace = this.#chatWorkspace(report!.station as string, report!.context as string | null);
    if (!workspace || !sessionOf(report!.context as string | null)) return { undeliverable: "no_chat" };
    const reply = ulid();
    const now = nowSeconds();
    this.#run("INSERT INTO feedback_replies (id, feedback, author, by, text, created_at) VALUES (?, ?, 'team', ?, ?, ?)", reply, id, by, text, now);
    this.#run("UPDATE feedback SET updated_at = ? WHERE id = ?", now, id);
    this.#tell(this.#members(workspace), { type: "feedback", workspace });
    return { id: reply, delivery: "pending" };
  }

  /** The reporter's agent answers one of its station's reports (FB-`number`): kept with the team's replies. null: too many today. */
  reporterReply(station: string, number: number, text: string, session: string | null): { id: string } | null {
    const report = this.#one("SELECT id, context FROM feedback WHERE number = ? AND station = ?", number, station);
    if (!report) fail(404, "feedback_not_found");
    const now = nowSeconds();
    const today = this.#one("SELECT COUNT(*) AS n FROM feedback_replies r JOIN feedback f ON f.id = r.feedback WHERE f.station = ? AND r.author = 'reporter' AND r.created_at > ?", station, now - 24 * 60 * 60);
    if ((today?.n as number) >= FEEDBACK_REPLIES_PER_DAY) return null;
    return { id: this.#reporterSaid(report!.id as string, session ? `session:${session}` : "", text, report!.context as string | null, station) };
  }

  /** A reply from the reporter's side (`by`: `session:<key>`, its agent's; `account:<sub>`, a person's in the app), told to the chat's people. */
  #reporterSaid(id: string, by: string, text: string, context: string | null, station: string): string {
    const reply = ulid();
    const now = nowSeconds();
    this.#run("INSERT INTO feedback_replies (id, feedback, author, by, text, created_at) VALUES (?, ?, 'reporter', ?, ?, ?)", reply, id, by, text, now);
    this.#run("UPDATE feedback SET updated_at = ? WHERE id = ?", now, id);
    const workspace = this.#chatWorkspace(station, context);
    if (workspace) this.#tell(this.#members(workspace), { type: "feedback", workspace });
    return reply;
  }

  /**
   * The reports with a reply of the team's from chats of a workspace, for a member's device to show in each chat (by
   * its station and session), newest first; the team's replies given are marked delivered. Who may read them is who
   * may read those chats: the workspace's members.
   */
  feedbackOf(sub: string, workspace: string): { feedback: WorkspaceFeedback[] } {
    this.#role(sub, workspace);
    const rows = this.#rows(`SELECT f.id, f.number, f.title, f.station, f.context FROM feedback f JOIN station_members s ON s.station = f.station AND s.workspace = ?
      WHERE EXISTS (SELECT 1 FROM feedback_replies r WHERE r.feedback = f.id AND r.author = 'team') ORDER BY f.number DESC LIMIT ${FEEDBACK_SHOWN}`, workspace)
      .filter((r) => this.#chatWorkspace(r.station as string, r.context as string | null) === workspace);
    const names = new Map<string, string>();
    const nameOf = (by: string): string => {
      if (!by.startsWith("account:")) return "";
      if (!names.has(by)) {
        const u = this.#one("SELECT name, email FROM users WHERE sub = ?", by.slice("account:".length));
        names.set(by, u ? ((u.name as string) || (u.email as string)) : "");
      }
      return names.get(by)!;
    };
    const now = nowSeconds();
    const feedback = rows.map((r): WorkspaceFeedback => {
      const replies = this.#rows("SELECT id, author, by, text, created_at, delivered_at FROM feedback_replies WHERE feedback = ? ORDER BY created_at, rowid", r.id);
      for (const reply of replies) if (reply.author === "team" && reply.delivered_at === null) this.#run("UPDATE feedback_replies SET delivered_at = ? WHERE id = ?", now, reply.id);
      const context = contextOf(r.context as string | null);
      return {
        id: r.id as string,
        number: r.number as number,
        title: r.title as string,
        station: r.station as string,
        session: sessionOf(r.context as string | null) ?? "",
        thread: typeof context.thread === "string" ? context.thread : null,
        replies: replies.map((reply) => {
          const by = reply.by as string;
          const from = reply.author === "team" ? "team" : by.startsWith("account:") ? "person" : "agent";
          return { id: reply.id as string, from, name: from === "person" ? nameOf(by) : "", text: reply.text as string, created_at: reply.created_at as number };
        }),
      };
    });
    return { feedback };
  }

  /** A member answers, in the app, a report shown in a chat of the workspace: kept as theirs. */
  memberFeedbackReply(sub: string, workspace: string, id: string, text: string): { id: string } {
    this.#role(sub, workspace);
    const report = this.#one("SELECT station, context FROM feedback WHERE id = ?", id);
    if (!report || this.#chatWorkspace(report.station as string | null, report.context as string | null) !== workspace) fail(404, "feedback_not_found");
    return { id: this.#reporterSaid(id, `account:${sub}`, text, report!.context as string | null, report!.station as string) };
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
   * station (whose signature it checked) in `x-stillfail-station`.
   */
  async fetch(request: Request): Promise<Response> {
    // Only while the sockets are rolled back here (sockets.where). An old Worker's, in flight as it is replaced, is
    // turned away as a restarting service: the device or station tries again, through the new one, onto its object.
    if (sockets.where(this.env) === "objects") return Response.json({ error: "moved" }, { status: 503 });
    const path = new URL(request.url).pathname;
    const pair = new WebSocketPair();
    if (path === "/events") {
      const sub = header(request, "sub")!;
      // Every device opens this when it starts: the nearest thing to "last seen" that costs no write per request.
      this.#run("UPDATE users SET last_seen = ? WHERE sub = ?", nowSeconds(), sub);
      this.ctx.acceptWebSocket(pair[1], [`sub:${sub}`]);
      pair[1].serializeAttachment({ sub } satisfies Attachment);
      return new Response(null, { status: 101, webSocket: pair[0], headers: { "sec-websocket-protocol": header(request, "protocol") ?? EVENTS_PROTOCOLS[0] } });
    }
    const station = header(request, "station")!;
    if (!this.isStation(station)) return Response.json({ error: "station_removed" }, { status: 404 });
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

  /** A station in no workspace now: its object hears it (and lets its socket go, 4004), and any socket held here goes. */
  #disconnect(station: string): void {
    this.#deliver("station", station, { state: true }, { urgent: true, always: true });
    for (const ws of this.#presence(station)) this.#drop(ws, CLOSE.removed, "station_removed");
  }

  /**
   * Where a station is and what it is called, and the cloud's own addresses as it has them now (a station enrolled
   * under an old host follows them: its links then use the new one); sent on connect and when that changes. What it
   * says at the top is of the station's home, as it was when a station was in one workspace (all a station from before
   * several knows); `workspaces`, each other one it is in, with its own peers, revocations and lock head.
   */
  #sendState(station: string, urgent = false): void {
    this.#deliver("station", station, { state: true }, { urgent });
    const sockets = this.#presence(station);
    if (!sockets.length) return;
    const frame = this.#frame(station);
    if (frame !== null) for (const ws of sockets) ws.send(frame);
  }

  /** A station's state frame (#sendState); null for one in no workspace. */
  #frame(station: string): string | null {
    const found = this.#rows(`SELECT m.workspace, w.name AS workspace_name, m.name, w.relays, w.ways_off, m.rig, m.enrolled_by FROM station_members m JOIN workspaces w ON w.id = m.workspace
      WHERE m.station = ? ORDER BY m.enrolled_at, m.rowid`, station);
    if (!found.length) return null;
    const since = nowSeconds() - REVOCATION_DAYS * 86400;
    // The rigs apart from the stations (`rigs`): a station from before them reads no such field and so takes no rig
    // for a station (which it would let ask anything of it). A rig is told the stations (they alone ask of it), not
    // the other rigs, and whose it is (`rig`).
    // (`ways`: the workspace's own relays and the ways it turned off, as kept here before its stations kept them: what a
    // station takes as its first of them, station/src/mesh/ways.ts)
    const [home, ...joined] = found.map(({ relays, ways_off, rig, enrolled_by, ...row }) => ({
      ...(row as { workspace: string; workspace_name: string; name: string }),
      ways: { relays: parseRelays(relays), off: parseRelays(ways_off) },
      peers: this.#rows("SELECT m.station AS id, m.name, s.version FROM station_members m LEFT JOIN stations s ON s.id = m.station WHERE m.workspace = ? AND m.rig IS NULL ORDER BY m.enrolled_at, m.rowid", row.workspace),
      ...(rig === 1 ? { rig: { owner: enrolled_by as string } } : this.#rigsTold(row.workspace as string)),
      revocations: this.#rows("SELECT kind, id, at FROM revocations WHERE workspace = ? AND at >= ?", row.workspace, since),
      lock: this.#lockHead(row.workspace as string),
      ...(this.#locked(row.workspace as string) ? { locked: true } : {}),
    }));
    const { peers, revocations, lock: _, locked: __, ...row } = home! as typeof home & { locked?: true };
    // Every workspace's own relays after still.fail's (one endpoint, homed on any of them): a station from before them
    // keeps one more relay as it keeps the rest.
    const told = relays(this.env);
    const relay_urls = [...told.relay_urls];
    for (const url of found.flatMap((w) => parseRelays(w.relays))) if (!relay_urls.map(sameUrl).includes(sameUrl(url))) relay_urls.push(url);
    const lock = this.#lockHead(row.workspace);
    return JSON.stringify({ type: "state", peers, ...row, origin: this.env.PUBLIC_ORIGIN, ...told, relay_urls, grant_keys: grantKeys(this.env), revocations, lock, workspaces: joined });
  }

  #offline(station: string): void {
    if (this.#presence(station).length) return;
    this.#run("UPDATE stations SET last_seen = ? WHERE id = ?", nowSeconds(), station);
  }

  /** "ping" is answered by the runtime; a station speaks otherwise only of the workspace locks: it asks for entries it
   * lacks (`lock.get {after}`, answered `{type: "lock", entries}`) or brings ones the cloud lacks (`lock.put`), of its
   * home's lock, or of another workspace's it is in that it names (`workspace`, said back with the entries). */
  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = ws.deserializeAttachment() as Attachment;
    if (typeof message !== "string" || !("station" in attachment)) return;
    await this.#said(attachment.station, message, (frame) => ws.send(frame));
  }

  /** What a station said (here or on its object), answered with `send`. */
  async #said(station: string, message: string, send: (frame: string) => void): Promise<void> {
    let body: { type?: unknown; after?: unknown; entries?: unknown; workspace?: unknown; genesis?: unknown; keep?: unknown };
    try {
      body = JSON.parse(message);
    } catch {
      return;
    }
    const all = this.#memberships(station);
    const named = typeof body.workspace === "string" ? body.workspace : null;
    const workspace = named === null ? all[0] : all.includes(named) ? named : undefined;
    if (!workspace) return;
    if (body.type === "lock.get") {
      const after = Number.isSafeInteger(body.after) ? (body.after as number) : -1;
      // A station that holds a chain turned off since (it was offline then, and the lock was turned on again after):
      // the rest of that chain, its `disable` with it, so it lets that chain go by itself (it checks each entry).
      const off = typeof body.genesis === "string" ? this.#lockTurnedOff(workspace, body.genesis, after) : [];
      send(JSON.stringify({ type: "lock", entries: off.length > 0 ? off : this.#lockAfter(workspace, after), ...(named === null ? {} : { workspace }) }));
    } else if (body.type === "lock.put") {
      // Refused when it does not follow: the station hears the cloud's head in the state frame and asks again. `keep`:
      // what the station keeps of the lock that the cloud's chain parted from (its head an entry that lost), kept by
      // the fork choice (a station from before says none, and is answered as before).
      await this.#appendLock(workspace, body.entries, body.keep === true).catch(() => this.#sendState(station));
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
  // (Only while the sockets are rolled back here: on their objects, each station's does the same.) The same alarm
  // tries again the deliveries that failed (#arm); one that fails again sets it for its next try.
  async alarm(): Promise<void> {
    if (this.sweep(Date.now())) await this.ctx.storage.setAlarm(Date.now() + SILENT_MS); // timer: a heartbeat's check, the stations' pings
    this.#flush();
    await Promise.all(this.#sending.values());
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

/** What the console shows of the directory's own load (adminLoad). */
export type DirectoryLoad = {
  at: number;
  /** Calls an hour from `start` (seconds), `step` apart, by family. */
  calls: { start: number; step: number; families: Record<string, number[]> };
  held: { devices: number; stations: number };
  live: { accounts: number; stations: number };
  waiting: number;
  bytes: number;
};

/** What each of the directory's calls serves, as its load is counted (adminLoad); "other" for one not listed. */
const FAMILIES: Record<string, string> = {
  accountFor: "signin", upsertUser: "signin",
  me: "me", invitationsFor: "me", setOwnPicture: "me", deleteAccount: "me", revokeSessions: "me",
  isBeta: "beta",
  seen: "sockets", closed: "sockets", stationConnected: "sockets", stationState: "sockets", stationLeft: "sockets", stationSaid: "sockets",
  fetch: "sockets", webSocketMessage: "sockets", webSocketClose: "sockets", webSocketError: "sockets",
  enroll: "stations", isStation: "stations", pushTargets: "stations", addFeedback: "stations", fixedUntold: "stations", reporterReply: "stations", toldFixed: "stations", markFixed: "stations",
  registerPush: "push", unregisterPush: "push", dropPush: "push", pushApps: "push",
  tellAll: "broadcast", tellStations: "broadcast", modelsMade: "broadcast", tellAdmins: "broadcast", alarm: "broadcast",
};
for (const name of ["workspace", "createWorkspace", "updateWorkspace", "deleteWorkspace", "invite", "previewInvitation", "acceptInvitation", "acceptById", "declineById", "revokeInvitation",
  "feedbackOf", "memberFeedbackReply", "setRole", "removeMember", "addMembers", "mailFailed", "removeAdded", "setRelays", "setWay", "manages", "createEnrollment", "createRigEnrollment", "updateStation", "setStationMode", "removeStation", "memberRole", "recordDevice", "devices",
  "lock", "appendLock", "clearLock", "requestLock", "lockRequests", "dropLockRequest"]) FAMILIES[name] = "workspaces";
for (const name of ["adminUsers", "setMayCreate", "adminPending", "setPending", "removePending", "setBlocked", "setBeta", "adminDeleteWorkspace", "adminCreateWorkspace", "adminSetLimits",
  "adminEnrollment", "adminWorkspaces", "inviteCodes", "createInviteCode", "revokeInviteCode", "adminFeedback", "setFeedbackStatus", "replyToFeedback", "adminLoad"]) FAMILIES[name] = "admin";
/** The tables that are this object's own, not moved into another cloud: its sockets' generations, the outbox to the
 * objects (made again as things change), its counts. */
const MOVE_SKIPPED = new Set(["outbox", "live", "hits"]);
for (const name of ["moveExport", "moveImport", "moveAccounts"]) FAMILIES[name] = "admin";
/** What it runs for itself rather than being called for. */
const UNCOUNTED = new Set(["constructor", "handOff", "migrateStationMembers", "migrateFreePlan", "send", "settled", "sweep"]);

/** Each directory's calls since they were last kept, by `hour family`: counted in memory, so a call that only reads writes nothing. */
const counted = new WeakMap<Directory, Map<string, number>>();
for (const name of Object.getOwnPropertyNames(Directory.prototype)) {
  const prototype = Directory.prototype as unknown as Record<string, unknown>;
  const method = prototype[name];
  if (UNCOUNTED.has(name) || typeof method !== "function") continue;
  const family = FAMILIES[name] ?? "other";
  prototype[name] = function (this: Directory, ...args: unknown[]) {
    const counts = counted.get(this) ?? counted.set(this, new Map()).get(this)!;
    const k = `${Math.floor(nowSeconds() / 3600)} ${family}`;
    counts.set(k, (counts.get(k) ?? 0) + 1);
    return (method as (...a: unknown[]) => unknown).apply(this, args);
  };
}

function cleanName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const clean = value.trim().replace(/\s+/g, " ");
  return clean && clean.length <= 80 ? clean : null;
}

/** Emails as addMembers takes them: lowercased, each once, at least one; fails when one is no email. */
function emailsOf(value: unknown): string[] {
  const given = Array.isArray(value) ? value : [];
  const wanted = [...new Set(given.map((e) => String(e).trim().toLowerCase()).filter(Boolean))];
  if (wanted.length === 0 || wanted.some((e) => !/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(e))) fail(400, "invalid_email");
  return wanted;
}

/** The largest member limit and the largest legacy station argument accepted from older clients. */
export const LIMITS_MAX = { members: 1000, stations: 256 } as const;

/** A workspace's member limit; accept the older station argument but use the shared cap. */
function limitsOf(input: { members?: unknown; stations?: unknown }): { members: number; stations: number } {
  const whole = (v: unknown, max: number) => (typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= max ? v : fail(400, "invalid_limits"));
  const members = whole(input.members, LIMITS_MAX.members);
  whole(input.stations, LIMITS_MAX.stations);
  return { members, stations: STATIONS_PER_WORKSPACE };
}

/**
 * A station's icon: one of still.fail's by its name (`glyph:rocket`, design/station-icons; a name a client does not know
 * falls back to the emoji), which may be given a colour (`glyph:rocket:blue`; the clients know which), or a picture put
 * up: kept in the bucket, by its address on one of `origins` (icons.ts keptIcon; any size up to ICON_FILE_BYTES, a GIF moving),
 * else (no bucket, or one put up before) a small data URL the clients made (96px, a few KB); else null.
 */
function cleanIcon(value: unknown, origins: string[]): string | null {
  if (typeof value !== "string") return null;
  if (/^glyph:[a-z0-9-]{1,40}(:[a-z]{1,16})?$/.test(value)) return value;
  if (origins.some((origin) => isIconUrl(origin, value))) return value;
  return value.length <= ICON_BYTES && /^data:image\/(png|webp|jpeg|gif);base64,[A-Za-z0-9+/]+={0,2}$/.test(value) ? value : null;
}
/** A picture an account puts up for itself: one kept here, by its address on one of `origins` (this cloud's and its
 * guests': the clients fetch a person's by its address); else null. */
function cleanPicture(value: unknown, origins: string[]): string | null {
  return typeof value === "string" && origins.some((origin) => isIconUrl(origin, value)) ? value : null;
}
/** A workspace's emoji and icon as its views carry them: each only when set (clients from before them know neither). */
function marks(emoji: unknown, icon: unknown): { emoji?: string; icon?: string } {
  return { ...(emoji ? { emoji: emoji as string } : {}), ...(icon ? { icon: icon as string } : {}) };
}
/** The ways a workspace turned off as its views carry them: only when some are (clients from before them know none). */
function offOf(kept: unknown): { ways_off?: string[] } {
  const off = parseRelays(kept);
  return off.length > 0 ? { ways_off: off } : {};
}
/** How long a picture's data URL kept in the workspace may be: it goes to every member with the workspace. */
const ICON_BYTES = 48_000;

/** One emoji, as a person sees one (a flag, a family, a skin tone are one): the first, else null. */
function cleanEmoji(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const first = [...new Intl.Segmenter().segment(value.trim())][0]?.segment;
  return first && first.length <= 32 && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(first) ? first : null;
}

/** A report's context as the station sent it; empty when it was cut at its limit. */
function contextOf(text: string | null): Record<string, unknown> {
  try {
    const value = JSON.parse(text ?? "{}") as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** The session a report came from, which a reply goes to. */
const sessionOf = (text: string | null): string | null => {
  const session = contextOf(text).session;
  return typeof session === "string" && session ? session : null;
};
