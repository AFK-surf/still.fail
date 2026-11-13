// still.fail cloud's API (the Worker stillfail-cloud): accounts and sign-in, workspaces and their stations, the operator's
// console API, and installing a station. It answers only the paths routed to it (wrangler.jsonc) on PUBLIC_ORIGIN's
// and ADMIN_ORIGIN's hosts; the web apps are static Workers of their own on those hosts' Custom Domains (routes take
// precedence over them), and the relay is a Worker of its own (relay-worker.ts), so deploying this one drops no relay
// connection and serves no page. Each host has an old name too (ember.3720.org, admin.ember.3720.org: the
// *_ORIGIN_ALIASES, compat.ts), answered the same; links, and signing in with Google, use the new ones.
import { installScript, releaseType, sharedRelease } from "./install.ts";
import { windowsInstallScript } from "./install-windows.ts";
import { cloudProduct, requestLang, setCloud, tr } from "./i18n.ts";
import { latestDownload, serveRelease, upstreamRelease } from "./releases.ts";
import { authConfigured, bearerToken, denied, digest, readJson, reply, validId, validSecret, verifyToken } from "./auth";
import { devicePage, googleStart, consumeLoginRate, signedInPage } from "./login";
import { passwordSignIn } from "./password";
import { adminOrigins, betaOrigin, header, publicOrigins } from "./compat";
import { asOrigin, forward, served } from "./guests";
import { isMoveCall, moveApi, moving } from "./move";
import { asProductOf } from "./here";
import type { Env } from "./env";
import { adminApi, api, blockAccount, FEEDBACK_REPLY_PATH, FEEDBACK_STATUS_PATH, feedbackList, liveOf, notBetaReply, onTestChannel, replyToFeedback, setFeedbackStatus } from "./api";
import { noted, parseTraceparent, recordCall, relayToTelemetry, takeNotes, unverifiedNotes } from "./tracing";
export { TelemetryLimiter } from "./tracing";
export { Account } from "./account";
export { Directory } from "./directory";
export { LoginAttempt, LoginLimiter } from "./login";
export { RelayLoad } from "./relay-load";
export { ServiceStatus } from "./status";
export { Station } from "./station";
import { sampleOwnRelay } from "./relay-load";
import { checkServices } from "./status";
import { checkModels } from "./models";
import { PROBE_EVERY_MIN, probeRelays } from "./probes";
import { relayUrls } from "./relays";

/** The minute of each hour the models' catalog is made afresh (`scheduled`). */
const MODELS_MINUTE = 7;

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
// any other call carrying an account's token answers 403 not_beta for an account not let in (api.ts notBetaReply).

/**
 * Whether a call of the test channel comes from an account not let in: one with a valid token, not beta, as its
 * account's object says with whether the token's session is live (asked once: api.ts liveOf). A device's events socket
 * is its account's object's to refuse (api.ts).
 */
async function notBeta(request: Request, env: Env): Promise<boolean> {
  onTestChannel.add(request);
  const token = bearerToken(request);
  const claims = token ? await verifyToken(env, token, "access") : null;
  // No token, or not a valid one: the call answers as it would anywhere (401 for an account's call).
  if (!claims || new URL(request.url).pathname === "/v1/events") return false;
  return (await liveOf(request, env, claims)) === "not_beta";
}

/** The same request on PUBLIC_ORIGIN: where a browser's sign-in goes, so its cookie is on the host Google calls back. */
const toPublic = (env: Env, url: URL) => new Response(null, { status: 302, headers: { location: `${env.PUBLIC_ORIGIN}${url.pathname}${url.search}`, "cache-control": "no-store" } });

export default {
  // A /v1/* call in a recorded trace (a client core's) is a span of it, sent once the answer is out.
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    setCloud(env.PUBLIC_ORIGIN);
    // A cloud that moved into another (guests.ts): what reaches it goes there, but for its releases, which stay here.
    if (env.FORWARD_TO && !new URL(request.url).pathname.startsWith("/releases/")) return forward(request, env);
    // A request a guest forwarded is answered as made on its origin, as its product (guests.ts).
    request = served(request, env);
    const origin = new URL(request.url).origin;
    env = asOrigin(env, origin);
    return asProductOf(env.PUBLIC_ORIGIN === origin || betaOrigin(env) === origin ? origin : env.PUBLIC_ORIGIN, () => answer(request, env, ctx));
  },
  // Every minute (wrangler.jsonc triggers): still.fail's own relay's counters, for the console (relay-load.ts; the
  // operator's devices told they were sampled), then the services checked for still.fail/status (status.ts); every
  // PROBE_EVERY_MIN, the relays probed from China's networks (probes.ts), where RELAY_PROBES says so; hourly, the
  // models' catalog made afresh from models.dev, the stations told when it changed (models.ts). A cloud that moved
  // into another (FORWARD_TO) has no stations of its own to tell.
  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    return scheduled(controller, env, ctx);
  },
} satisfies ExportedHandler<Env>;

async function answer(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const parent = new URL(request.url).pathname.startsWith("/v1/") && request.headers.get("upgrade") === null ? parseTraceparent(request.headers.get("traceparent")) : null;
  const started = Date.now();
  // What the handler noted for the span never goes out with the answer.
  const { response, notes } = takeNotes(await handle(request, env));
  if (parent?.sampled) ctx.waitUntil(recordCall(env, parent, request, response, started, Date.now(), notes));
  return response;
}

async function scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
  const minute = Math.floor(controller.scheduledTime / 60_000);
  ctx.waitUntil(
    sampleOwnRelay(env)
      .catch(() => [])
      .then(async (full) => {
        await env.DIRECTORY.getByName("primary").tellAdmins({ type: "relays" }).catch(() => undefined);
        await checkServices(env, full);
      }),
  );
  if (minute % 60 === MODELS_MINUTE && !env.FORWARD_TO) ctx.waitUntil(checkModels(env).catch(() => undefined));
  if (env.RELAY_PROBES === "globalping" && minute % PROBE_EVERY_MIN === 0) ctx.waitUntil(probeAndSay(env));
}

/** Whether the request carries FEEDBACK_TOKEN, the team's feedback monitor's (unset or short: nobody's). */
async function feedbackMonitor(env: Env, request: Request): Promise<boolean> {
  const supplied = bearerToken(request);
  return !!env.FEEDBACK_TOKEN && env.FEEDBACK_TOKEN.length >= 43 && !!supplied && (await digest(supplied)) === (await digest(env.FEEDBACK_TOKEN));
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === "/healthz" && request.method === "GET") {
    // The Worker's name, which it keeps (Cloudflare knows it by it).
    return Response.json({ service: "stillfail-cloud", google_login: authConfigured(env) });
  }
  const onPublic = publicOrigins(env).includes(url.origin);
  const onBeta = url.origin === betaOrigin(env);
  // Installing a station: the installer, and the releases it gets; the apps' builds, for their updaters. The installer
  // gets the test channel's release with ?channel=beta (or STILLFAIL_CHANNEL=beta where it runs), and by default when
  // fetched from the test channel's host; either way the station joins PUBLIC_ORIGIN.
  if ((onPublic || onBeta) && request.method === "GET") {
    const channel = url.searchParams.get("channel") === "beta" || (onBeta && url.searchParams.get("channel") !== "stable") ? "beta" : "stable";
    if (path === "/install.sh") return new Response(installScript(env.PUBLIC_ORIGIN, channel, requestLang(request)), { headers: { "content-type": "text/x-shellscript; charset=utf-8", "cache-control": "no-store" } });
    if (path === "/install.ps1") return new Response(windowsInstallScript(env.PUBLIC_ORIGIN, channel, requestLang(request)), { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
    // The beta Android apps built from #1194 (4608) until #1263 ask their feed's beta twice (their feed android/beta,
    // to which a beta's core adds /beta): theirs is the beta feed, for them to update to a build that asks it right.
    const asked = /^\/releases\/(.+)$/.exec(path)?.[1];
    const release = asked === "android/beta/beta/latest.json" ? "android/beta/latest.json" : asked;
    const type = release ? releaseType(release) : null;
    if (release && type) {
      const own = await serveRelease(request, env.RELEASES, release, type);
      // (a cloud whose bucket holds its own apps' alone: the station's from still.fail's, install.ts sharedRelease)
      if (own.status !== 404 || !env.RELEASES_UPSTREAM || !sharedRelease(release)) return own;
      return upstreamRelease(request, env.RELEASES_UPSTREAM, release);
    }
    // The apps' latest builds at links that stay (the site's download buttons; under /releases/, which cloud's routes send here).
    const app = /^\/releases\/latest\/(mac|android|win|mac-beta|android-beta|win-beta|android-mbui|mac-mbui|win-mbui|linux-mbui|linux-arm64-mbui)$/.exec(path)?.[1];
    if (app) {
      const file = await latestDownload(env.RELEASES, app);
      if (!file || !releaseType(file)) return notFound();
      return new Response(null, { status: 302, headers: { location: `/releases/${file}`, "cache-control": "no-store" } });
    }
  }
  const onConsole = adminOrigins(env).includes(url.origin);
  if (path.startsWith("/v1/")) {
    if (!onPublic && !onConsole && !onBeta) return reply({ error: "invalid_origin" }, 421);
    // Moving into another cloud (move.ts): only the move's own calls and the icons it copies, the rest asked to wait.
    if (isMoveCall(path)) return moveApi(request, env, path);
    if (env.MOVING && !path.startsWith("/v1/icons/")) return moving();
    if (path.startsWith("/v1/auth/") && !authConfigured(env)) return reply({ error: "login_not_configured" }, 503);
    // Signing in, refreshing and signing out stay open to it, so a login completes and the page or app can be told.
    const ofBeta = onBeta || header(request, "channel") === "beta";
    if (ofBeta && !path.startsWith("/v1/auth/") && (await notBeta(request, env))) return notBetaReply(env, request);
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
    const lang = requestLang(request);
    return devicePage(lang, tr(lang, "cloud.login.complete.title"), `<p>${tr(lang, "cloud.login.complete.body")}</p>`);
  }
  // Where an app's browser sign-in ends once the browser has come back to it (mbui's browser_login `done`): it is
  // signed in, the page can be closed; on Android, `app` its package, a link back to it should it not come forward.
  if (path === "/v1/auth/done" && request.method === "GET") return signedInPage(requestLang(request), url.searchParams.get("app"));
  // The sign-in page's forms (Google, or a code sent to an email: login.ts `choose`).
  const choice = /^\/v1\/auth\/login\/([A-Za-z0-9_-]{43})$/.exec(path);
  if (choice && request.method === "POST") return env.LOGINS.getByName(choice[1]!).choose(choice[1]!, request);
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
      return env.LOGINS.getByName(body.id).startDevice(body.id, body.code_challenge, body.name, env.PUBLIC_ORIGIN);
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
  if (path === "/v1/auth/password" && request.method === "POST") return passwordSignIn(env, request);
  if ((path === "/v1/auth/refresh" || path === "/v1/auth/logout") && request.method === "POST") {
    try {
      const token = bearerToken(request);
      const claims = token ? await verifyToken(env, token, "refresh") : null;
      if (!claims || !token) return path.endsWith("/refresh") ? noted(denied(), { "stillfail.auth.outcome": "invalid_token", ...unverifiedNotes(token) }) : denied();
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
      return blockAccount(env, admin![1]!, body.blocked);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
  }
  // The console's bug reports for the team's feedback monitor: FEEDBACK_TOKEN reads them, marks their status and replies
  // to them, and nothing else. A status marked or a reply with another token is the console's admin's, signed in (adminApi).
  if (path === "/v1/admin/feedback/list" && request.method === "POST") {
    if (!(await feedbackMonitor(env, request))) return denied();
    return reply({ feedback: await feedbackList(env) });
  }
  const feedbackStatus = FEEDBACK_STATUS_PATH.exec(path);
  if (feedbackStatus && request.method === "POST" && (await feedbackMonitor(env, request))) {
    let body: Record<string, unknown>;
    try {
      body = await readJson(request);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
    return setFeedbackStatus(env, feedbackStatus[1]!, body.status);
  }
  const feedbackReply = FEEDBACK_REPLY_PATH.exec(path);
  if (feedbackReply && request.method === "POST" && (await feedbackMonitor(env, request))) {
    let body: Record<string, unknown>;
    try {
      body = await readJson(request);
    } catch {
      return reply({ error: "invalid_request" }, 400);
    }
    return replyToFeedback(env, feedbackReply[1]!, "feedback-monitor", body.text);
  }
  // The Android app opens an item's link (/o/…) itself: this says the domain is its (App Links).
  if (path === "/.well-known/assetlinks.json") {
    return new Response(JSON.stringify(assetLinks()), { headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } });
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
 * Android App Links: the app, signed with this certificate, opens https://<its host>/o/… itself, on every host: its
 * manifest says which hosts it opens. Another product's cloud its own apps' (monoid's: build.monoid.android and .beta).
 */
const assetLinks = () => (cloudProduct().id === "stillfail" ? ["fail.still.android"] : [`${cloudProduct().reverse}.android`, `${cloudProduct().reverse}.android.beta`]).map((package_name) => ({
  relation: ["delegate_permission/common.handle_all_urls"],
  target: {
    namespace: "android_app",
    package_name,
    sha256_cert_fingerprints: ["A0:1A:48:B5:E1:A6:D2:AB:FB:EA:34:57:B6:C7:1D:12:57:BC:42:97:93:BD:8B:3E:BE:F6:BE:8E:E1:55:B5:6A"],
  },
}));

/** The relays probed (probes.ts), each probe's result a `relay probe` line of that relay in Cloud Logging. */
async function probeAndSay(env: Env): Promise<void> {
  const found = await probeRelays(relayUrls(env), (input, init) => fetch(input, init), (ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  for (const [relay, lines] of found) await relayToTelemetry(env, relay, null, lines.map((fields) => ({ what: "relay probe", fields })));
}
