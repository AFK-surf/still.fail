// What the operator's own machine asks of a self-hosted cloud, on a socket only it reaches (config.ts `setup`,
// 127.0.0.1), each call with ADMIN_TOKEN:
//   POST /v1/setup      { admin, workspace, station }: the admin's account (as a code sent to its email would sign it
//                       in), its workspace of that name (made once), and, while the workspace has no station, an
//                       enrollment for one named `station`: { cloud, relays, workspace, workspace_name, stations, enrollment? }. The
//                       calls are the API's own, made as the admin, in a session ended once they are done.
//   POST /v1/scheduled  what Cloudflare's cron does (wrangler.jsonc triggers): the API's scheduled handler, now.
import type { Account } from "../src/account.ts";
import type { Directory } from "../src/directory.ts";
import { digest, type Tokens } from "../src/auth.ts";
import type { WorkspaceSummary } from "../src/types.ts";
import { ulid } from "ulid";

/** A service binding as workerd has it, with its Worker's scheduled handler (what Cloudflare's cron calls). */
type Scheduling = Fetcher & { scheduled(options: { scheduledTime?: Date; cron?: string }): Promise<{ outcome: string } | undefined> };

export type SetupEnv = { PUBLIC_ORIGIN: string; ADMIN_TOKEN?: string | null; API: Scheduling; ACCOUNTS: DurableObjectNamespace<Account>; DIRECTORY: DurableObjectNamespace<Directory> };

const json = (body: unknown, status = 200) => Response.json(body, { status, headers: { "cache-control": "no-store" } });

async function setup(env: SetupEnv, input: { admin?: unknown; workspace?: unknown; station?: unknown }): Promise<Response> {
  const email = typeof input.admin === "string" ? input.admin.trim().toLowerCase() : "";
  const name = typeof input.workspace === "string" ? input.workspace : "";
  const station = typeof input.station === "string" ? input.station : "station";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !name) return json({ error: "invalid_request" }, 400);
  // The account a code to that email signs in to (login.ts emailIdentity): one with the email, else its own.
  const own = `em-${(await digest(email)).slice(0, 32)}`;
  const found = await env.DIRECTORY.getByName("primary").accountFor(own, email);
  const identity = { sub: found?.sub ?? own, email, name: found?.name ?? "", picture: found?.picture ?? "" };
  const made = await env.ACCOUNTS.getByName(identity.sub).create(identity, ulid(), "setup");
  if (!made.ok) return json({ error: "no_session", status: made.status }, 502);
  const tokens = (await made.json()) as Tokens;
  const call = async (method: string, path: string, body?: unknown, token = tokens.access_token) => {
    const answer = await env.API.fetch(new Request(`${env.PUBLIC_ORIGIN}${path}`, {
      method,
      headers: { authorization: `Bearer ${token}`, "cf-connecting-ip": "127.0.0.1", ...(body === undefined ? {} : { "content-type": "application/json" }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }));
    const said = (await answer.json().catch(() => ({}))) as Record<string, unknown>;
    if (!answer.ok) throw Object.assign(new Error(`${method} ${path}: ${answer.status} ${JSON.stringify(said)}`), { said });
    return said;
  };
  try {
    const me = (await call("GET", "/v1/me")) as { workspaces: WorkspaceSummary[]; relay_urls: string[] };
    const workspace = me.workspaces.find((w) => w.name === name && w.role === "owner") ?? ((await call("POST", "/v1/workspaces", { name })) as unknown as WorkspaceSummary);
    const stations = workspace.stations ?? 0;
    const enrollment = stations > 0 ? undefined : await call("POST", `/v1/workspaces/${workspace.id}/enrollments`, { name: station });
    return json({ cloud: env.PUBLIC_ORIGIN, relays: me.relay_urls, workspace: workspace.id, workspace_name: workspace.name, stations: typeof stations === "number" ? stations : 0, ...(enrollment ? { enrollment: { name: station, token: enrollment.token, expires_at: enrollment.expires_at, command: enrollment.command } } : {}) });
  } catch (error) {
    return json({ error: "setup_failed", detail: String((error as Error).message) }, 502);
  } finally {
    await call("POST", "/v1/auth/logout", { all: false }, tokens.refresh_token).catch(() => undefined);
  }
}

export default {
  async fetch(request: Request, env: SetupEnv): Promise<Response> {
    const path = new URL(request.url).pathname;
    const token = /^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "")?.[1];
    if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 43 || !token || (await digest(token)) !== (await digest(env.ADMIN_TOKEN))) return json({ error: "invalid_session" }, 401);
    if (request.method !== "POST") return json({ error: "not_found" }, 404);
    if (path === "/v1/setup") return setup(env, (await request.json().catch(() => ({}))) as Record<string, unknown>);
    if (path === "/v1/scheduled") {
      const ran = await env.API.scheduled({ scheduledTime: new Date(), cron: "* * * * *" });
      return json({ outcome: ran?.outcome ?? "ok" });
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<SetupEnv>;
