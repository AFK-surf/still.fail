// Only the test bundler imports this entry. Production exports no fixture routes.
import worker, { Account as ProductionAccount, Directory as ProductionDirectory, LoginAttempt, LoginLimiter, TelemetryLimiter } from "../src/index";
import { signToken, nowSeconds, reply, readJson } from "../src/auth";
import type { Env } from "../src/env";
export { LoginAttempt, LoginLimiter, TelemetryLimiter };

export class Directory extends ProductionDirectory {
  /** The presence alarm's check, as if it ran at `ms`. */
  sweepAt(ms: number) {
    return this.sweep(ms);
  }
  /** A code whose time is up. */
  expireInviteCode(code: string) {
    this.ctx.storage.sql.exec("UPDATE invite_codes SET expires_at = ? WHERE code = ?", nowSeconds(), code);
  }
  /** An account as members were before invite codes: in a workspace, admitted by nothing on record. */
  forgetAdmission(sub: string) {
    this.ctx.storage.sql.exec("UPDATE users SET admitted = NULL WHERE sub = ?", sub);
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
