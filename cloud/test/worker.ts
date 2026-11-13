// Only the test bundler imports this entry. Production exports no fixture routes.
import worker, { Account as ProductionAccount, Directory as ProductionDirectory, LoginAttempt as ProductionLoginAttempt, LoginLimiter, RelayLoad, ServiceStatus, Station as ProductionStation, TelemetryLimiter } from "../src/index";
import { clock, signToken, nowSeconds, reply, readJson } from "../src/auth";
import { sockets, type Delivery } from "../src/directory";
import type { Env } from "../src/env";
import type { MailMessage } from "../src/mail";
export { LoginLimiter, RelayLoad, ServiceStatus, TelemetryLimiter };

// The moment the tests run at (harness.ts NOW_MS), unless they run on the machine's time (dev.ts). The Worker and its
// objects share this isolate, and so the clock.
declare const TEST_NOW_MS: number | null;
if (TEST_NOW_MS !== null) clock.now = () => TEST_NOW_MS;

/**
 * With TEST_MAIL (harness.ts `mail`), signing in with an email is offered, its codes (and the API's mails to people
 * added to a workspace) sent to https://mail.test/send,
 * where the harness keeps them, instead of through Cloudflare Email Service; an answer other than 200 is the error the
 * binding throws, its body the error's code.
 */
const withTestMail = <E extends Env & { TEST_MAIL?: string }>(env: E): E => {
  if (!env.TEST_MAIL) return env;
  const send = async (message: MailMessage) => {
    const answer = await fetch("https://mail.test/send", { method: "POST", body: JSON.stringify(message) });
    if (!answer.ok) throw Object.assign(new Error("not sent"), { code: await answer.text() });
    return { messageId: crypto.randomUUID() };
  };
  return { ...env, EMAIL: { send }, EMAIL_FROM: "noreply@relay.example" };
};
export class LoginAttempt extends ProductionLoginAttempt {
  constructor(ctx: DurableObjectState, env: Env & { TEST_MAIL?: string }) {
    super(ctx, withTestMail(env));
  }
}

/** Once a socket's close has been handled (since the last time this said so), on whichever object held it. */
class Leaving {
  #waiting = new Map<string, () => void>();
  #done = new Set<string>();
  closed(key: string) {
    this.#done.add(key);
    this.#waiting.get(key)?.();
  }
  async left(key: string) {
    if (!this.#done.has(key)) await new Promise<void>((resolve) => this.#waiting.set(key, resolve));
    this.#done.delete(key);
  }
}

/**
 * What a socket said that is not answered yet, on the object that holds it. The runtime starts a message's handler
 * before it reads the socket's next one, so one said before a ping is counted here by the ping's pong.
 */
class Saying {
  #open = new Set<Promise<void>>();
  through(handled: Promise<void>): Promise<void> {
    this.#open.add(handled);
    const over = () => void this.#open.delete(handled);
    handled.then(over, over);
    return handled;
  }
  async answered(): Promise<void> {
    while (this.#open.size > 0) await Promise.allSettled([...this.#open]);
  }
}

export class Directory extends ProductionDirectory {
  /** The presence alarm's check, as if it ran at `ms` (the sockets held here, while rolled back). */
  sweepAt(ms: number) {
    return this.sweep(ms);
  }
  #saying = new Saying();
  override webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    return this.#saying.through(super.webSocketMessage(ws, message));
  }
  #leaving = new Leaving();
  override async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    await super.webSocketClose(ws, code);
    const { station } = ws.deserializeAttachment() as { station?: string };
    if (station) this.#leaving.closed(station);
  }
  /** Once a socket of the station held here has closed and its close been handled. */
  left(station: string) {
    return this.#leaving.left(station);
  }
  /**
   * Everything a station said on its socket, here or on its object, is answered (an answer takes its object a call
   * to the Directory, and may be a change the Directory then tells), and every delivery under way has got there or
   * failed.
   */
  override async settled() {
    await this.#saying.answered();
    const holding = this.ctx.storage.sql.exec("SELECT key FROM live WHERE kind = 'station'").toArray();
    await Promise.all(holding.map((row) => (this.env.STATIONS.getByName(row.key as string) as unknown as { answered(): Promise<void> }).answered()));
    return super.settled();
  }
  /** Deliveries to these objects (`kind key`) fail, as if the network between them broke; none given, none do. */
  #failing = new Set<string>();
  failTo(...targets: string[]) {
    this.#failing = new Set(targets);
  }
  override send(kind: "account" | "station", key: string, body: Delivery) {
    if (this.#failing.has(`${kind} ${key}`)) return Promise.reject(new Error("network down (test)"));
    return super.send(kind, key, body);
  }
  /** What waits to be tried again: how many deliveries, to whom. */
  waiting() {
    return this.ctx.storage.sql.exec("SELECT kind, key, tries FROM outbox ORDER BY id").toArray();
  }
  /** The alarm the retries set, gone off now (the test's clock is far ahead of the machine's, so it never goes off by itself). */
  async retry() {
    this.ctx.storage.sql.exec("UPDATE outbox SET next_at = 0");
    await this.alarm();
    await this.settled();
  }
  /** What the constructor does as a deploy that moves the sockets to their objects starts it. */
  handOffNow() {
    this.handOff();
  }
  /** A code whose time is up. */
  expireInviteCode(code: string) {
    this.ctx.storage.sql.exec("UPDATE invite_codes SET expires_at = ? WHERE code = ?", nowSeconds(), code);
  }
  /** A device's request to be confirmed into a workspace's lock, made `secs` ago. */
  ageLockRequest(workspace: string, base: string, secs: number) {
    this.ctx.storage.sql.exec("UPDATE lock_requests SET created_at = ? WHERE workspace = ? AND base = ?", nowSeconds() - secs, workspace, base);
  }
  /** A workspace's lock kept as `entries`, unchecked, as the cloud kept them before it checked them (none read yet). */
  keepLockUnchecked(workspace: string, entries: { seq: number; entry: unknown; hash: string }[]) {
    this.ctx.storage.sql.exec("DELETE FROM lock_entries WHERE workspace = ?", workspace);
    for (const e of entries) this.ctx.storage.sql.exec("INSERT INTO lock_entries (workspace, seq, hash, entry) VALUES (?, ?, ?, ?)", workspace, e.seq, e.hash, JSON.stringify(e.entry));
    this.lockSeen.delete(workspace);
  }
  /** The hashes of the entries kept off a workspace lock's chain (lock_aside), in the order kept. */
  lockAside(workspace: string): string[] {
    return this.ctx.storage.sql.exec("SELECT hash FROM lock_aside WHERE workspace = ? ORDER BY rowid", workspace).toArray().map((r) => r.hash as string);
  }
  /** An account as members were before invite codes: in a workspace, admitted by nothing on record. */
  forgetAdmission(sub: string) {
    this.ctx.storage.sql.exec("UPDATE users SET admitted = NULL WHERE sub = ?", sub);
  }
  /** An account that created its workspaces before the free plan, admitted as `admitted` then; the plan's change runs again. */
  beforeFreePlan(sub: string, admitted: string | null) {
    this.ctx.storage.sql.exec("UPDATE users SET admitted = ? WHERE sub = ?", admitted, sub);
    this.ctx.storage.sql.exec("DELETE FROM migrations WHERE name = 'free-plan'");
    this.migrateFreePlan();
  }
  /** A station limit from before the shared cap, kept as an existing workspace's setting. */
  legacyStationLimit(workspace: string, limit: number) {
    this.ctx.storage.sql.exec("UPDATE workspaces SET max_stations = ? WHERE id = ?", limit, workspace);
  }
  /** A station already enrolled before the shared cap was introduced. */
  previouslyEnrolledStation(workspace: string, station: string, by: string) {
    this.ctx.storage.sql.exec("INSERT INTO stations (id, last_seen, version) VALUES (?, ?, ?)", station, nowSeconds(), "0.3.1");
    this.ctx.storage.sql.exec("INSERT INTO station_members (workspace, station, name, enrolled_at, enrolled_by) VALUES (?, ?, ?, ?, ?)", workspace, station, "earlier", nowSeconds(), by);
  }
  /**
   * The stations as they were kept before a station could be in several workspaces: one table, a row each (with
   * `marks`, the emoji and icon it gained later; without, as a table older than them), each station in the one
   * workspace it is in now. The split runs again, twice (the second time finds nothing to do). What `stations` holds
   * after it.
   */
  unsplitStations(marks = true): string[] {
    const sql = this.ctx.storage.sql;
    const rows = sql.exec("SELECT m.workspace, m.station AS id, m.name, m.emoji, m.icon, m.enrolled_at, m.enrolled_by, s.last_seen, s.version FROM station_members m JOIN stations s ON s.id = m.station ORDER BY m.enrolled_at, m.rowid").toArray();
    this.ctx.storage.transactionSync(() => {
      sql.exec("DROP TABLE stations");
      sql.exec("DELETE FROM station_members");
      sql.exec(`CREATE TABLE stations (id TEXT PRIMARY KEY, workspace TEXT NOT NULL, name TEXT NOT NULL, enrolled_at INTEGER NOT NULL, enrolled_by TEXT NOT NULL, last_seen INTEGER, version TEXT${marks ? ", emoji TEXT, icon TEXT" : ""})`);
      for (const r of rows) {
        sql.exec(`INSERT INTO stations (id, workspace, name, enrolled_at, enrolled_by, last_seen, version${marks ? ", emoji, icon" : ""}) VALUES (?, ?, ?, ?, ?, ?, ?${marks ? ", ?, ?" : ""})`,
          r.id, r.workspace, r.name, r.enrolled_at, r.enrolled_by, r.last_seen, r.version, ...(marks ? [r.emoji, r.icon] : []));
      }
    });
    this.migrateStationMembers();
    this.migrateStationMembers();
    return sql.exec("PRAGMA table_info(stations)").toArray().map((r) => r.name as string);
  }
  /**
   * `users` made-up accounts over the last four months, about one in three with a workspace of up to five people and
   * up to three stations (none ever connects), some invitations and codes: what the admin's console looks like once
   * many people use still.fail (dev.ts, SEED). Seeded by `seed`, so each run makes the same.
   */
  seedPeople(users: number, seed = 7) {
    const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    const pick = <T>(list: T[]) => list[Math.floor(random() * list.length)]!;
    const now = nowSeconds();
    const day = 86400;
    const names = ["王一凡", "Alice Chen", "陈晨", "Bob Lee", "李雷", "Mia Zhang", "张伟", "Leo Park", "刘洋", "Nina Wu", "赵敏", "Omar Ali", "周杰", "Ivy Lin", "吴昊", "Sam Ho", "韩梅梅", "Tom Xu", "孙悦", "Zoe Ma"];
    const domains = ["gmail.com", "acme.io", "qq.com", "proton.me", "163.com"];
    const teams = ["产品", "设计", "增长", "研发", "运营", "Infra", "Data", "AI Lab", "客服", "市场"];
    const sql = this.ctx.storage.sql;
    const subs: { sub: string; created: number }[] = [];
    this.ctx.storage.transactionSync(() => {
      for (let i = 0; i < users; i++) {
        const sub = `seed-${i}`;
        const name = names[i % names.length]!;
        // More people lately than at first.
        const created = now - Math.floor(random() * random() * 120 * day);
        const seen = random() < 0.06 ? null : Math.min(now, created + Math.floor(random() * (now - created)));
        const local = /[a-z]/i.test(name) ? name.toLowerCase().replace(" ", ".") : "user";
        sql.exec("INSERT OR IGNORE INTO users (sub, email, name, picture, created_at, last_seen, beta) VALUES (?, ?, ?, '', ?, ?, ?)",
          sub, `${local}${i}@${pick(domains)}`, name, created, seen, random() < 0.04 ? 1 : null);
        subs.push({ sub, created });
      }
      for (let i = 0; i < Math.floor(users / 3); i++) {
        const owner = pick(subs);
        const id = `seedws${String(i).padStart(4, "0")}`;
        const created = owner.created + Math.floor(random() * 3 * day);
        sql.exec("INSERT INTO workspaces (id, name, created_by, created_at) VALUES (?, ?, ?, ?)", id, `${teams[i % teams.length]}${i >= teams.length ? ` ${Math.floor(i / teams.length)}` : ""}`, owner.sub, created);
        sql.exec("INSERT INTO members (workspace, sub, role, added_at) VALUES (?, ?, 'owner', ?)", id, owner.sub, created);
        sql.exec("UPDATE users SET admitted = ? WHERE sub = ? AND admitted IS NULL", pick(["code", "code", "granted"]), owner.sub);
        for (let k = Math.floor(random() * 5); k > 0; k--) {
          const member = pick(subs).sub;
          sql.exec("INSERT OR IGNORE INTO members (workspace, sub, role, added_at) VALUES (?, ?, ?, ?)", id, member, random() < 0.2 ? "admin" : "member", created + day);
          sql.exec("UPDATE users SET admitted = 'invitation' WHERE sub = ? AND admitted IS NULL", member);
        }
        for (let k = Math.floor(random() * 4); k > 0; k--) {
          const seen = random() < 0.12 ? null : now - Math.floor(random() * random() * random() * 40 * day);
          const station = `${"0".repeat(56)}${String(i * 4 + k).padStart(8, "0")}`;
          sql.exec("INSERT INTO stations (id, last_seen, version) VALUES (?, ?, ?)", station, seen, pick(["0.1.1212", "0.1.1212", "0.1.1212", "0.1.1190", "0.1.1104"]));
          sql.exec("INSERT INTO station_members (workspace, station, name, enrolled_at, enrolled_by) VALUES (?, ?, ?, ?, ?)",
            id, station, `${pick(["cedar", "willow", "dev-box", "nas", "mbp"])}${k > 1 ? `-${k}` : ""}`, created, owner.sub);
        }
        if (random() < 0.15) {
          sql.exec("INSERT INTO invitations (id, workspace, token_hash, role, email, created_by, expires_at) VALUES (?, ?, ?, 'member', ?, ?, ?)",
            `seedinv${i}`, id, `seed-hash-${i}`, `friend${i}@gmail.com`, owner.sub, now + 3 * day);
        }
      }
      for (let i = 0; i < Math.floor(users / 20); i++) {
        const created = now - Math.floor(random() * 60 * day);
        sql.exec("INSERT INTO invite_codes (code, note, created_by, created_at, expires_at, revoked_at) VALUES (?, ?, 'seed', ?, ?, ?)",
          `SEED-${String(1000 + i).slice(-4)}-${pick(["ABCD", "EFGH", "JKMN", "PQRS"])}`, pick(["", "", "内测群", "朋友", "展会", "Twitter 抽奖"]), created, created + pick([7, 14, 30]) * day, random() < 0.1 ? created + day : null);
      }
    });
  }
}

/**
 * A socket's opening whose answer from the Directory is late: the Directory has counted it, the object has not heard
 * so yet. `hold` before it opens, `held` once the answer waits here, `go` lets it through.
 */
class LateOpening {
  #gate: Promise<void> | null = null;
  #go: (() => void) | null = null;
  #arrived: (() => void) | null = null;
  #here = new Promise<void>((resolve) => (this.#arrived = resolve));
  hold() {
    this.#gate = new Promise<void>((resolve) => (this.#go = resolve));
  }
  held() {
    return this.#here;
  }
  go() {
    this.#go?.();
    this.#gate = null;
  }
  async through<T>(answer: Promise<T>): Promise<T> {
    const value = await answer;
    if (this.#gate) {
      this.#arrived?.();
      await this.#gate;
    }
    return value;
  }
}

/** Where the sockets open (directory.ts `sockets`), as a deploy of DIRECTORY_SOCKETS sets it, for the whole isolate. */
function socketsAt(where: "objects" | "primary") {
  sockets.where = () => where;
}

export class Station extends ProductionStation {
  /** The presence alarm's check, as if it ran at `ms`. */
  sweepAt(ms: number) {
    return this.sweep(ms);
  }
  #leaving = new Leaving();
  override async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    await super.webSocketClose(ws, code);
    this.#leaving.closed("socket");
  }
  /** Once its socket has closed and its close been handled. */
  left() {
    return this.#leaving.left("socket");
  }
  #saying = new Saying();
  override webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    return this.#saying.through(super.webSocketMessage(ws, message));
  }
  /** Once everything its socket said, that got here, is answered (the Directory's `settled` asks). */
  answered() {
    return this.#saying.answered();
  }
  /** What the constructor does as a deploy that rolls the sockets back starts it. */
  handBackNow() {
    this.handBack();
  }
  #late = new LateOpening();
  holdOpening() {
    this.#late.hold();
  }
  openingHeld() {
    return this.#late.held();
  }
  letOpen() {
    this.#late.go();
  }
  protected override connected(station: string, version: string | null) {
    return this.#late.through(super.connected(station, version));
  }
}

export class Account extends ProductionAccount {
  /** What the constructor does as a deploy that rolls the sockets back starts it. */
  handBackNow() {
    this.handBack();
  }
  #late = new LateOpening();
  holdOpening() {
    this.#late.hold();
  }
  openingHeld() {
    return this.#late.held();
  }
  letOpen() {
    this.#late.go();
  }
  protected override opened(sub: string) {
    return this.#late.through(super.opened(sub));
  }
  expire(id: string, kind: "idle" | "absolute") {
    const account = this.ctx.storage.kv.get<any>("account");
    const session = account.sessions.find((s: any) => s.id === id);
    if (kind === "idle") session.idle = nowSeconds();
    else session.expires = nowSeconds();
    this.ctx.storage.kv.put("account", account);
  }
  /** Moves the session's last rotation `seconds` into the past (past its retry window, say). */
  age(id: string, seconds: number) {
    const account = this.ctx.storage.kv.get<any>("account");
    const session = account.sessions.find((s: any) => s.id === id);
    if (session.retry) session.retry.until -= seconds;
    if (session.rotated !== undefined) session.rotated -= seconds;
    this.ctx.storage.kv.put("account", account);
  }
  /** As if the session was signed in `seconds` earlier than it was. */
  signedInEarlier(id: string, seconds: number) {
    const account = this.ctx.storage.kv.get<any>("account");
    const session = account.sessions.find((s: any) => s.id === id);
    session.created -= seconds;
    session.expires -= seconds;
    this.ctx.storage.kv.put("account", account);
  }
  statistics() {
    return {
      quota: this.ctx.storage.kv.get("quota"),
      account: this.ctx.storage.kv.get<any>("account")?.sessions.map((s: any) => ({
        id: s.id,
        generation: s.generation,
        expires: s.expires,
        idle: s.idle,
      })),
    };
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    env = withTestMail(env);
    const path = new URL(request.url).pathname;
    if (path === "/__test/devices") return reply(deviceRequests);
    if (path === "/__test/sockets") {
      const { where } = (await readJson(request)) as { where: "objects" | "primary" };
      socketsAt(where);
      return reply({ where });
    }
    if (path === "/__test/offline") {
      offline = !offline;
      return reply({ offline });
    }
    if (path === "/__test/lose-refresh-response") {
      loseRefreshResponse = true;
      return reply({ armed: true });
    }
    if (path === "/v1/auth/refresh" && loseRefreshResponse) {
      loseRefreshResponse = false;
      const response = await worker.fetch(request, env, ctx);
      return response.ok ? reply({ error: "lost_response" }, 503) : response;
    }
    if (offline && path.startsWith("/v1/auth/")) return reply({ error: "unavailable" }, 503);
    if (path === "/__test/access") {
      const body = await readJson(request);
      return reply({
        token: await signToken(
          env,
          "access",
          {
            sub: body.sub,
            sid: body.sid,
            email: "test@example.test",
          },
          nowSeconds() + Number(body.seconds),
        ),
      });
    }
    if (path === "/v1/auth/device" && request.method === "POST") {
      const response = await worker.fetch(request, env, ctx);
      if (response.ok) {
        deviceRequests.push(((await response.clone().json()) as { verification_uri: string }).verification_uri);
        if (deviceRequests.length > 8) deviceRequests.shift();
      }
      return response;
    }
    return worker.fetch(request, env, ctx);
  },
  scheduled: worker.scheduled,
};
let offline = false;
let loseRefreshResponse = false;

const deviceRequests: string[] = [];
