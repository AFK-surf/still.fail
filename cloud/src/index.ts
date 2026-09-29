// ember cloud's API (the Worker ember-cloud): accounts and sign-in, workspaces and their stations, the operator's
// console API, and installing a station. It answers only the paths routed to it (wrangler.jsonc) on PUBLIC_ORIGIN's
// and ADMIN_ORIGIN's hosts; the web apps are static Workers of their own on those hosts' Custom Domains (routes take
// precedence over them), and the relay is a Worker of its own (relay-worker.ts), so deploying this one drops no relay
// connection and serves no page.
import { installScript, releaseType } from "./install.ts";
import { authConfigured, bearerToken, denied, digest, readJson, reply, validId, validSecret, verifyToken } from "./auth";
import { devicePage, googleStart, consumeLoginRate } from "./login";
import type { Env } from "./env";
import { adminApi, api } from "./api";
import { parseTraceparent, recordCall } from "./tracing";
export { TelemetryLimiter } from "./tracing";
export { Account } from "./account";
export { Directory } from "./directory";
export { LoginAttempt, LoginLimiter } from "./login";

// The admin's console has a host of its own, ADMIN_ORIGIN: its /v1/ calls come here too — the calls its client core
// makes to sign in and stay signed in (the core talks to the page's origin), and the console's API; nothing else. A
// sign-in starts on PUBLIC_ORIGIN all the same: the login's cookie belongs to the host that starts it, and Google
// calls back to PUBLIC_ORIGIN, which then sends the browser on to the console's /auth/callback.
const CONSOLE_CALLS = new Set(["/v1/auth/token", "/v1/auth/refresh", "/v1/auth/logout", "/v1/me"]);

const notFound = () => new Response("Not found", { status: 404 });

export default {
  // A /v1/* call in a recorded trace (a client core's) is a span of it, sent once the answer is out.
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const parent = new URL(request.url).pathname.startsWith("/v1/") && request.headers.get("upgrade") === null ? parseTraceparent(request.headers.get("traceparent")) : null;
    if (!parent?.sampled) return handle(request, env);
    const started = Date.now();
    const response = await handle(request, env);
    ctx.waitUntil(recordCall(env, parent, request, response, started, Date.now()));
    return response;
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === "/healthz" && request.method === "GET") {
    return Response.json({ service: "ember-cloud", google_login: authConfigured(env) });
  }
  // Installing a station: the installer, and the releases it gets; the apps' builds, for their updaters.
  if (url.origin === env.PUBLIC_ORIGIN && request.method === "GET") {
    if (path === "/install.sh") return new Response(installScript(env.PUBLIC_ORIGIN), { headers: { "content-type": "text/x-shellscript; charset=utf-8", "cache-control": "no-store" } });
    const release = /^\/releases\/(.+)$/.exec(path)?.[1];
    const type = release ? releaseType(release) : null;
    if (release && type) {
      const object = await env.RELEASES?.get(release);
      if (!object) return reply({ error: "release_not_found" }, 404);
      return new Response(object.body, { headers: { "content-type": type, "content-length": String(object.size), "cache-control": "no-store" } });
    }
  }
  const onConsole = url.origin === env.ADMIN_ORIGIN;
  if (path.startsWith("/v1/")) {
    if (url.origin !== env.PUBLIC_ORIGIN && !onConsole) return reply({ error: "invalid_origin" }, 421);
    if (path.startsWith("/v1/auth/") && !authConfigured(env)) return reply({ error: "login_not_configured" }, 503);
  }
  if (onConsole) {
    if (path === "/v1/auth/google/start" && request.method === "GET") {
      return new Response(null, { status: 302, headers: { location: `${env.PUBLIC_ORIGIN}${path}${url.search}`, "cache-control": "no-store" } });
    }
    if (path.startsWith("/v1/admin/")) return adminApi(request, env, path);
    if (!CONSOLE_CALLS.has(path)) return notFound();
  }
  if (path === "/v1/auth/google/start" && request.method === "GET") {
    return googleStart(env, request);
  }
  if (path === "/v1/auth/device/complete" && request.method === "GET") {
    return devicePage("请返回 still.fail", "<p>登录结果会在发起登录的地方显示，现在可以关闭此页。</p>");
  }
  const device = /^\/v1\/auth\/device\/([A-Za-z0-9_-]{43})$/.exec(path);
  if (device && (request.method === "GET" || request.method === "POST")) {
    return env.LOGINS.getByName(device[1]).authorizeDevice(device[1], request);
  }
  if ((path === "/v1/auth/device" || path === "/v1/auth/device/token" || path === "/v1/auth/device/cancel") && request.method === "POST") {
    try {
      const body = await readJson(request);
      if (!validSecret(body.id)) return reply({ error: "invalid_login" }, 400);
      if (path.endsWith("/token") || path.endsWith("/cancel")) {
        if (!validSecret(body.code_verifier)) return reply({ error: "invalid_grant" }, 401);
        return path.endsWith("/cancel") ? env.LOGINS.getByName(body.id).cancelDevice(body.code_verifier) : env.LOGINS.getByName(body.id).pollDevice(body.code_verifier);
      }
      if (!validSecret(body.code_challenge) || typeof body.name !== "string") return reply({ error: "invalid_login" }, 400);
      if (!(await consumeLoginRate(env, request))) return reply({ error: "rate_limited" }, 429, { "retry-after": "60" });
      return env.LOGINS.getByName(body.id).startDevice(body.id, body.code_challenge, body.name);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
  }
  if (path === "/v1/auth/google/callback" && request.method === "GET") {
    const state = url.searchParams.get("state");
    if (!validSecret(state)) return reply({ error: "invalid_login_state" }, 400);
    return env.LOGINS.getByName(state).callback(state, request);
  }
  if (path === "/v1/auth/token" && request.method === "POST") {
    try {
      const body = await readJson(request);
      if (typeof body.code !== "string") return denied();
      const [id, secret, extra] = body.code.split(".");
      if (!validSecret(id) || !validSecret(secret) || extra !== undefined || !validSecret(body.code_verifier) || typeof body.redirect_uri !== "string") return denied();
      return env.LOGINS.getByName(id).exchange(secret, body.code_verifier, body.redirect_uri);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
  }
  if ((path === "/v1/auth/refresh" || path === "/v1/auth/logout") && request.method === "POST") {
    try {
      const token = bearerToken(request);
      const claims = token ? await verifyToken(env, token, "refresh") : null;
      if (!claims || !token) return denied();
      const body = await readJson(request);
      const account = env.ACCOUNTS.getByName(claims.sub);
      if (path.endsWith("/refresh")) {
        if (!validId(body.request_id)) return reply({ error: "invalid_request" }, 400);
        return account.refresh(token, body.request_id);
      }
      if (typeof body.all !== "boolean") return reply({ error: "invalid_request" }, 400);
      return account.logout(token, body.all);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
  }
  const admin = /^\/v1\/admin\/accounts\/([A-Za-z0-9_-]{1,128})$/.exec(path);
  const deleteWorkspace = /^\/v1\/admin\/workspaces\/([A-Za-z0-9_-]{1,64})\/delete$/.exec(path);
  const listWorkspaces = path === "/v1/admin/workspaces/list";
  if ((admin || deleteWorkspace || listWorkspaces) && request.method === "POST") {
    const supplied = bearerToken(request);
    if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 43 || !supplied || (await digest(supplied)) !== (await digest(env.ADMIN_TOKEN))) return denied();
    try {
      if (listWorkspaces) return reply({ workspaces: await env.DIRECTORY.getByName("primary").adminWorkspaces() });
      if (deleteWorkspace) {
        await env.DIRECTORY.getByName("primary").adminDeleteWorkspace(deleteWorkspace[1]!);
        return reply({ deleted: true });
      }
      const body = await readJson(request);
      if (typeof body.blocked !== "boolean") return reply({ error: "invalid_request" }, 400);
      return env.ACCOUNTS.getByName(admin![1]).administer(body.blocked);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
  }
  // The Android app opens an item's link (/o/…) itself: this says the domain is its (App Links).
  if (path === "/.well-known/assetlinks.json") {
    return new Response(JSON.stringify(ASSET_LINKS), { headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } });
  }
  const handled = await api(request, env, url);
  if (handled) return handled;
  if (path === "/v1/auth/session" || path === "/v1/auth/sessions" || /^\/v1\/auth\/sessions\/[^/]+$/.test(path)) {
    const token = bearerToken(request);
    const claims = token ? await verifyToken(env, token, "access") : null;
    if (!claims) return denied();
    return env.ACCOUNTS.getByName(claims.sub).fetch(request);
  }
  return notFound();
}

/** Android App Links: dev.ember.android, signed with this certificate, opens https://ember.3720.org/o/… itself. */
const ASSET_LINKS = [{
  relation: ["delegate_permission/common.handle_all_urls"],
  target: {
    namespace: "android_app",
    package_name: "dev.ember.android",
    sha256_cert_fingerprints: ["A0:1A:48:B5:E1:A6:D2:AB:FB:EA:34:57:B6:C7:1D:12:57:BC:42:97:93:BD:8B:3E:BE:F6:BE:8E:E1:55:B5:6A"],
  },
}];
