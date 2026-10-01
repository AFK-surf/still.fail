// still.fail cloud's API (the Worker ember-cloud): accounts and sign-in, workspaces and their stations, the operator's
// console API, and installing a station. It answers only the paths routed to it (wrangler.jsonc) on PUBLIC_ORIGIN's
// and ADMIN_ORIGIN's hosts; the web apps are static Workers of their own on those hosts' Custom Domains (routes take
// precedence over them), and the relay is a Worker of its own (relay-worker.ts), so deploying this one drops no relay
// connection and serves no page. Each host has an old name too (ember.3720.org, admin.ember.3720.org: the
// *_ORIGIN_ALIASES, compat.ts), answered the same; links, and signing in with Google, use the new ones.
import { installScript, releaseType } from "./install.ts";
import { latestDownload, serveRelease } from "./releases.ts";
import { authConfigured, bearerToken, denied, digest, readJson, reply, validId, validSecret, verifyToken } from "./auth";
import { devicePage, googleStart, consumeLoginRate } from "./login";
import { adminOrigins, betaOrigin, header, publicOrigins } from "./compat";
import type { Env } from "./env";
import { adminApi, api, socketToken } from "./api";
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

// The test channel is for the accounts the admin let in (Directory `beta`): the web app on BETA_ORIGIN
// (app.youdid.wtf), with the API on its paths as on PUBLIC_ORIGIN, and the beta apps (fail.still.android.beta,
// fail.still.desktop.beta), whose core says `x-stillfail-channel: beta` on every call. Signing in works for anyone
// (on the test channel's host it starts on PUBLIC_ORIGIN, as from the console, and comes back to its /auth/callback);
// any other call carrying an account's token answers 403 not_beta for an account not let in, which the page takes for
// "go to the stable one" and an app for "this account cannot use the test build".
const notBetaReply = (env: Env) => reply({ error: "not_beta", message: "这个账号还没有开通测试版", stable: env.PUBLIC_ORIGIN }, 403);

/** Whether a call of the test channel comes from an account not let in: one with a valid token, not beta. */
async function notBeta(request: Request, env: Env): Promise<boolean> {
  const token = bearerToken(request) ?? socketToken(request)?.token ?? null;
  const claims = token ? await verifyToken(env, token, "access") : null;
  // No token, or not a valid one: the call answers as it would anywhere (401 for an account's call).
  if (!claims) return false;
  return !(await env.DIRECTORY.getByName("primary").isBeta(claims.sub));
}

/** The same request on PUBLIC_ORIGIN: where a browser's sign-in goes, so its cookie is on the host Google calls back. */
const toPublic = (env: Env, url: URL) => new Response(null, { status: 302, headers: { location: `${env.PUBLIC_ORIGIN}${url.pathname}${url.search}`, "cache-control": "no-store" } });

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
    // The Worker's name, which it keeps (Cloudflare knows it by it).
    return Response.json({ service: "ember-cloud", google_login: authConfigured(env) });
  }
  const onPublic = publicOrigins(env).includes(url.origin);
  const onBeta = url.origin === betaOrigin(env);
  // Installing a station: the installer, and the releases it gets; the apps' builds, for their updaters. The installer
  // gets the test channel's release with ?channel=beta (or STILLFAIL_CHANNEL=beta where it runs), and by default when
  // fetched from the test channel's host; either way the station joins PUBLIC_ORIGIN.
  if ((onPublic || onBeta) && request.method === "GET") {
    const channel = url.searchParams.get("channel") === "beta" || (onBeta && url.searchParams.get("channel") !== "stable") ? "beta" : "stable";
    if (path === "/install.sh") return new Response(installScript(env.PUBLIC_ORIGIN, channel), { headers: { "content-type": "text/x-shellscript; charset=utf-8", "cache-control": "no-store" } });
    const release = /^\/releases\/(.+)$/.exec(path)?.[1];
    const type = release ? releaseType(release) : null;
    if (release && type) {
      return serveRelease(request, env.RELEASES, release, type);
    }
    // The apps' latest builds at links that stay (the site's download buttons; under /releases/, which cloud's routes send here).
    const app = /^\/releases\/latest\/(mac|android|mac-beta|android-beta)$/.exec(path)?.[1];
    if (app) {
      const file = await latestDownload(env.RELEASES, app);
      if (!file || !releaseType(file)) return notFound();
      return new Response(null, { status: 302, headers: { location: `/releases/${file}`, "cache-control": "no-store" } });
    }
  }
  const onConsole = adminOrigins(env).includes(url.origin);
  if (path.startsWith("/v1/")) {
    if (!onPublic && !onConsole && !onBeta) return reply({ error: "invalid_origin" }, 421);
    if (path.startsWith("/v1/auth/") && !authConfigured(env)) return reply({ error: "login_not_configured" }, 503);
    // Signing in, refreshing and signing out stay open to it, so a login completes and the page or app can be told.
    const ofBeta = onBeta || header(request, "channel") === "beta";
    if (ofBeta && !path.startsWith("/v1/auth/") && (await notBeta(request, env))) return notBetaReply(env);
  }
  if (onConsole) {
    if (path === "/v1/auth/google/start" && request.method === "GET") return toPublic(env, url);
    if (path.startsWith("/v1/admin/")) return adminApi(request, env, path);
    if (!CONSOLE_CALLS.has(path)) return notFound();
  }
  // A browser signing in on an old host, or on the test channel's, goes on to the new one, which Google calls back.
  if (url.origin !== env.PUBLIC_ORIGIN && request.method === "GET" && (path === "/v1/auth/google/start" || /^\/v1\/auth\/device\/[A-Za-z0-9_-]{43}$/.test(path))) return toPublic(env, url);
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

/**
 * Android App Links: the app, signed with this certificate, opens https://<its host>/o/… itself. Both the app from
 * before the rename (dev.ember.android) and the new one (fail.still.android), on every host: each says in its
 * manifest which hosts it opens.
 */
const ASSET_LINKS = ["fail.still.android", "dev.ember.android"].map((package_name) => ({
  relation: ["delegate_permission/common.handle_all_urls"],
  target: {
    namespace: "android_app",
    package_name,
    sha256_cert_fingerprints: ["A0:1A:48:B5:E1:A6:D2:AB:FB:EA:34:57:B6:C7:1D:12:57:BC:42:97:93:BD:8B:3E:BE:F6:BE:8E:E1:55:B5:6A"],
  },
}));
