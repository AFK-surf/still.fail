// Only the test bundler imports this entry. Production exports no fixture routes.
import worker, { Account as ProductionAccount, Directory as ProductionDirectory, LoginAttempt, LoginLimiter, TelemetryLimiter } from "../src/index";
import { clock, signToken, nowSeconds, reply, readJson } from "../src/auth";
import type { Env } from "../src/env";
export { LoginAttempt, LoginLimiter, TelemetryLimiter };

// The moment the tests run at (harness.ts NOW_MS), unless they run on the machine's time (dev.ts). The Worker and its
// objects share this isolate, and so the clock.
declare const TEST_NOW_MS: number | null;
if (TEST_NOW_MS !== null) clock.now = () => TEST_NOW_MS;

export class Directory extends ProductionDirectory {
  /** The presence alarm's check, as if it ran at `ms`. */
  sweepAt(ms: number) {
    return this.sweep(ms);
  }
  #leaving = new Map<string, () => void>();
  override async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    await super.webSocketClose(ws, code);
    const { station } = ws.deserializeAttachment() as { station?: string };
    if (!station) return;
    this.ctx.storage.kv.put(`left:${station}`, true);
    this.#leaving.get(station)?.();
  }
  /** Once a socket of the station has closed and its close been handled (since the last time this said so). */
  async left(station: string) {
    if (!this.ctx.storage.kv.get(`left:${station}`)) await new Promise<void>((resolve) => this.#leaving.set(station, resolve));
    this.ctx.storage.kv.delete(`left:${station}`);
  }
  /** A code whose time is up. */
  expireInviteCode(code: string) {
    this.ctx.storage.sql.exec("UPDATE invite_codes SET expires_at = ? WHERE code = ?", nowSeconds(), code);
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
          sql.exec("INSERT INTO stations (id, workspace, name, enrolled_at, enrolled_by, last_seen, version) VALUES (?, ?, ?, ?, ?, ?, ?)",
            `${"0".repeat(56)}${String(i * 4 + k).padStart(8, "0")}`, id, `${pick(["mac-mini", "studio", "dev-box", "nas", "mbp"])}${k > 1 ? `-${k}` : ""}`, created, owner.sub, seen,
            pick(["0.1.1212", "0.1.1212", "0.1.1212", "0.1.1190", "0.1.1104"]));
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

export class Account extends ProductionAccount {
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
    const path = new URL(request.url).pathname;
    if (path === "/__test/devices") return reply(deviceRequests);
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
};
let offline = false;
let loseRefreshResponse = false;

const deviceRequests: string[] = [];
