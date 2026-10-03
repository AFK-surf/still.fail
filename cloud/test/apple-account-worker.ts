// Test-only RPC fixture entry; never imported by production worker or deployment configuration.
import worker, { Account, Directory, LoginAttempt, LoginLimiter, TelemetryLimiter } from "../src/index";
import { encryptAppleGrant, type AppleEnv } from "../src/apple";
import { reply } from "../src/auth";
import { ulid } from "ulid";
export { Account, Directory, LoginAttempt, LoginLimiter, TelemetryLimiter };
export default {
  async fetch(request: Request, env: AppleEnv, ctx: ExecutionContext) {
    const path = new URL(request.url).pathname;
    if (!path.startsWith("/test/")) return worker.fetch(request, env, ctx);
    const body = await request.json() as any;
    const dir = env.DIRECTORY.getByName("primary");
    if (path === "/test/login") {
      const sub = body.apple ? await dir.appleSubject(body.sub) : body.sub;
      return env.ACCOUNTS.getByName(sub).create({ sub, email: body.email ?? "", name: body.name ?? "", picture: "", ...(body.apple ? { provider: "apple" as const } : {}) }, ulid(), "Test device", body.apple ? await encryptAppleGrant(env, "synthetic-grant") : undefined);
    }
    if (path === "/test/workspace") return reply(await dir.createWorkspace(body.sub, "Shared test workspace", true, null));
    if (path === "/test/add") return reply(await dir.addMembers(body.sub, body.workspace, "member", [body.email]));
    if (path === "/test/me") return reply(await dir.me(body.sub));
    return reply({ error: "fixture_not_found" }, 404);
  },
};
