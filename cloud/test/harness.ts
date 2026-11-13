import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions, Response as MFResponse, Log, LogLevel } from "miniflare";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { ulid } from "ulid";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";
import type { MailMessage } from "../src/mail.ts";
import { createRequire } from "node:module";
import { brotliCompressSync } from "node:zlib";

// workerd keeps a WebSocket's TCP connection open some ten seconds after a close the Worker began (Cloudflare does
// not), and the ws client miniflare hands sockets through says "close" only once it ends: a test waiting on a close
// code waited those ten seconds (events.test.ts, 30 of the cloud tests' 35). The client ends it itself once both
// close frames have passed: ws then ends its side, and once that is written (not after a guess at how long that
// takes, which under load dropped its close frame), the connection goes.
const WS = createRequire(createRequire(import.meta.url).resolve("miniflare"))("ws");
const wsClose = WS.prototype.close;
WS.prototype.close = function (this: any, ...args: unknown[]) {
  wsClose.apply(this, args);
  const socket = this._socket;
  if (!this._closeFrameReceived || !socket) return;
  if (socket.writableFinished) socket.destroy();
  else socket.once("finish", () => socket.destroy());
};

/**
 * still.fail cloud's time in the tests (src/auth.ts `clock`), in ms: one fixed moment, so what a test sees never
 * depends on the hour it runs at (a minute's budget turning over halfway, say). Ahead of any real one, so the alarms
 * set from it (a login limit's day, a session's end) never go off during a test.
 */
export const NOW_MS = Date.UTC(2030, 0, 1, 12, 0, 30);

/** A request the Worker made to somewhere outside (a push service, say), as a stand-in sees it. */
export interface OutboundRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: Uint8Array;
}

/** The Cloudflare Access team the harness's `access` puts in front of the console. */
const ACCESS_TEAM = "https://team.cloudflareaccess.example";

export async function harness(
  options: {
    relay?: string;
    origin?: string;
    persist?: string;
    port?: number;
    signingKey?: string;
    noGoogle?: boolean;
    /** REVIEW_ACCOUNTS: who signs in with a password (password.ts). */
    reviewAccounts?: string;
    relayUrl?: string;
    /** RELAY_URLS and RELAY_NAMES: relays beside it, and what they are called (the console's 中继 page). */
    relayUrls?: string;
    relayNames?: Record<string, string>;
    /** STATUS_PAGES: the pages the cron checks for still.fail/status; answered by `push` (they are outside). */
    statusPages?: Record<string, string>;
    /** STATUS_REPO_ID: the id of the repository whose issues labelled `incident` it shows; answered by `push`. */
    statusRepoId?: string;
    /** The console's admin (alice unless said otherwise). */
    adminEmail?: string;
    /** The console's host. */
    adminOrigin?: string;
    previewOrigin?: string;
    /** The test channel's host (BETA_ORIGIN): the web app and the API, for accounts let in. */
    betaOrigin?: string;
    /** The hosts' old names (before the rename to still.fail), bound to the same Workers: PUBLIC_ORIGIN_ALIASES and so on. */
    oldOrigin?: string;
    oldAdminOrigin?: string;
    oldPreviewOrigin?: string;
    /** The static sites' files (`/web/…`, `/admin/…`, `/preview/…`): a few stand-ins unless given. */
    assets?: (request: Request) => Promise<Response> | Response;
    /** Axiom: a stand-in answering its requests, or "real" to reach it (with AXIOM_TOKEN from the environment). */
    axiom?: ((request: Request) => Promise<Response> | Response) | "real";
    /** Push notifications: the VAPID key (base64url point and scalar), the FCM service account's JSON. */
    vapid?: { publicKey: string; privateKey: string };
    fcm?: string;
    /** FCM_SERVICE_ACCOUNT_MORE: the other product's projects' accounts. */
    fcmMore?: string;
    apns?: string;
    /** "real": the machine's time instead of NOW_MS (dev.ts, which real stations sign in to). */
    clock?: "real";
    /** The grant key (its private JWK, kid "test-grant"): one made now unless given (dev.ts's RESUME keeps it). */
    grantJwk?: JsonWebKey & { kid?: string };
    /** Signing in with an email: the codes sent are kept in `mails` (and handed to this, if it is one: false, or an
     * error code, and the binding throws as Cloudflare's would). */
    mail?: true | ((message: MailMessage) => boolean | string);
    /** Cloudflare Access in front of the console's host (ACCESS_TEAM_DOMAIN, ACCESS_AUD): `accessToken` makes its tokens. */
    access?: true;
    /** Another cloud's releases its own bucket lacks some of (RELEASES_UPSTREAM, https://upstream.test/releases): its answer to each file asked there. */
    upstream?: (file: string, request: OutboundRequest) => { status: number; body?: string; headers?: Record<string, string> };
    /** The other product's origins answered as that product (GUESTS, guests.ts), and the secret forwarded requests carry. */
    guests?: unknown[];
    forwardSecret?: string;
    /** Moved into another cloud (FORWARD_TO): where its requests go, answered by `push` as every other outbound one. */
    forwardTo?: string;
    /** MOVING: accounts moving between clouds (move.ts). */
    moving?: true;
    /** Push services, FCM and its token endpoint: a stand-in answering every other outbound request. */
    push?: (request: OutboundRequest) => Promise<{ status: number; body?: string }> | { status: number; body?: string };
  } = {},
) {
  const origin = options.origin ?? "https://relay.example";
  const adminOrigin = options.adminOrigin ?? "https://admin.relay.example";
  const previewOrigin = options.previewOrigin ?? "https://preview.relay.example";
  const betaOrigin = options.betaOrigin ?? "https://app.beta-domain.example";
  const oldOrigin = options.oldOrigin ?? "https://old.relay.example";
  const oldAdminOrigin = options.oldAdminOrigin ?? "https://admin.old.relay.example";
  const oldPreviewOrigin = options.oldPreviewOrigin ?? "https://preview.old.relay.example";
  /** still.fail cloud's time, in seconds: what a station signs with, say. */
  const now = () => Math.floor((options.clock === "real" ? Date.now() : NOW_MS) / 1000);
  const signingKey = options.signingKey ?? randomSecret(),
    adminToken = randomSecret(),
    feedbackToken = randomSecret();
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const publicJwk = {
    ...(await exportJWK(publicKey)),
    kid: "test-google",
    alg: "RS256",
    use: "sig",
  };
  const codes = new Map<string, { nonce: string; challenge: string; sub: string; invalid?: string }>();
  const mails: MailMessage[] = [];
  const grantPair = options.grantJwk ? null : await generateKeyPair("EdDSA", { crv: "Ed25519", extractable: true });
  const grantJwk = options.grantJwk ? { ...options.grantJwk, kid: "test-grant" } : { ...(await exportJWK(grantPair!.privateKey)), kid: "test-grant" };
  const { d: _d, ...grantPublicFields } = grantJwk as JsonWebKey & { kid: string };
  const grantPublicJwk = options.grantJwk ? { ...grantPublicFields, kid: "test-grant" } : { ...(await exportJWK(grantPair!.publicKey)), kid: "test-grant" };
  const bundle = async (entry: string) => (await build({
    entryPoints: [entry],
    bundle: true,
    write: false,
    format: "esm",
    platform: "node",
    banner: {
      js: 'import { createRequire } from "node:module"; const require = createRequire("file:///worker.js");',
    },
    external: ["cloudflare:workers", "cloudflare:sockets", "node:*"],
    define: { TEST_NOW_MS: options.clock === "real" ? "null" : String(NOW_MS) },
    conditions: ["workerd", "worker", "browser"],
  })).outputFiles[0].text;
  // still.fail cloud's Workers as Cloudflare runs them: the static sites on their hosts, and routes (which take
  // precedence) sending the API's and the relay's paths to theirs (cloud/wrangler*.jsonc); on each host's new name
  // and its old one.
  const hosts = [origin, oldOrigin].map((o) => new URL(o).host), adminHosts = [adminOrigin, oldAdminOrigin].map((o) => new URL(o).host), betaHost = new URL(betaOrigin).host;
  const common = { modules: true, compatibilityDate: "2026-09-08", compatibilityFlags: ["nodejs_compat"] };
  const mf = new Miniflare(
    convertV4MiniflareOptions({
      host: "127.0.0.1",
      ...(options.port ? { port: options.port } : {}),
      log: new Log(LogLevel.ERROR),
      ...(options.persist ? { resourcePersistencePath: options.persist } : {}),
      workers: [{
        ...common,
        name: "static",
        script: await bundle("test/static-worker.ts"),
        bindings: { PUBLIC_ORIGIN: origin, ADMIN_ORIGIN: adminOrigin, PREVIEW_ORIGIN: previewOrigin, PUBLIC_ORIGIN_ALIASES: oldOrigin, ADMIN_ORIGIN_ALIASES: oldAdminOrigin, PREVIEW_ORIGIN_ALIASES: oldPreviewOrigin, BETA_ORIGIN: betaOrigin },
        serviceBindings: { ASSETS: (options.assets ?? standInAssets) as any },
      }, {
        ...common,
        name: "relay",
        script: await bundle("test/relay-worker.ts"),
        routes: hosts.flatMap((host) => [`${host}/relay*`, `${host}/ping*`, `${host}/generate_204*`, `${host}/v1/admin/relay/*`]),
        bindings: { PUBLIC_ORIGIN: origin, PUBLIC_ORIGIN_ALIASES: oldOrigin, ADMIN_TOKEN: adminToken },
        serviceBindings: options.relay ? { TEST_RELAY: { external: { address: new URL(options.relay).host, http: {} } } } : {},
        durableObjects: { RELAY: { className: "Relay", useSQLite: true }, RELAY_BUDGET: { className: "RelayBudget", useSQLite: true } },
      }, {
        ...common,
        name: "api",
        script: await bundle("test/worker.ts"),
        routes: [...[...hosts, betaHost].flatMap((host) => [`${host}/v1/*`, `${host}/healthz*`, `${host}/install.sh*`, `${host}/install.ps1*`, `${host}/releases/*`, `${host}/.well-known/*`, `${host}/__test/*`]), ...adminHosts.map((host) => `${host}/v1/*`)],
        bindings: {
        PUBLIC_ORIGIN: origin,
        PUBLIC_ORIGIN_ALIASES: oldOrigin,
        ADMIN_ORIGIN: adminOrigin,
        ADMIN_ORIGIN_ALIASES: oldAdminOrigin,
        BETA_ORIGIN: betaOrigin,
        GOOGLE_CLIENT_ID: options.noGoogle ? "" : "test-google-client",
        GOOGLE_CLIENT_SECRET: randomSecret(),
        AUTH_SIGNING_KEY: signingKey,
        ADMIN_TOKEN: adminToken,
        FEEDBACK_TOKEN: feedbackToken,
        ADMIN_EMAIL: options.adminEmail ?? "alice@example.test",
        ...(options.access ? { ACCESS_TEAM_DOMAIN: ACCESS_TEAM, ACCESS_AUD: "test-access-aud" } : {}),
        ...(options.upstream ? { RELEASES_UPSTREAM: "https://upstream.test/releases" } : {}),
        GRANT_SIGNING_JWK: JSON.stringify(grantJwk),
        ...(options.relayUrl ? { RELAY_URL: options.relayUrl } : {}),
        ...(options.relayUrls ? { RELAY_URLS: options.relayUrls } : {}),
        ...(options.relayNames ? { RELAY_NAMES: options.relayNames } : {}),
        ...(options.statusPages ? { STATUS_PAGES: options.statusPages } : {}),
        ...(options.statusRepoId ? { STATUS_REPO_ID: options.statusRepoId } : {}),
        ...(options.vapid ? { VAPID_PUBLIC_KEY: options.vapid.publicKey, VAPID_PRIVATE_KEY: options.vapid.privateKey, VAPID_SUBJECT: "mailto:ops@example.test" } : {}),
        ...(options.fcm ? { FCM_SERVICE_ACCOUNT: options.fcm } : {}),
        ...(options.fcmMore ? { FCM_SERVICE_ACCOUNT_MORE: options.fcmMore } : {}),
        ...(options.apns ? { APNS_KEY: options.apns } : {}),
        ...(options.guests ? { GUESTS: JSON.stringify(options.guests) } : {}),
        ...(options.forwardSecret ? { FORWARD_SECRET: options.forwardSecret } : {}),
        ...(options.forwardTo ? { FORWARD_TO: options.forwardTo } : {}),
        ...(options.moving ? { MOVING: "1" } : {}),
        ...(options.reviewAccounts ? { REVIEW_ACCOUNTS: options.reviewAccounts } : {}),
        ...(options.mail ? { TEST_MAIL: "1" } : {}),
        ...(options.axiom ? { AXIOM_TOKEN: options.axiom === "real" ? process.env.AXIOM_TOKEN! : "test-axiom-token", AXIOM_DATASET: options.axiom === "real" ? process.env.AXIOM_DATASET ?? "ember" : "ember-test" } : {}),
      },
      r2Buckets: ["RELEASES"],
      durableObjects: {
        ...Object.fromEntries(["Account", "LoginAttempt", "LoginLimiter", "Directory", "TelemetryLimiter", "RelayLoad", "ServiceStatus", "Station"].map((className, i) => [["ACCOUNTS", "LOGINS", "LOGIN_LIMITS", "DIRECTORY", "TELEMETRY_LIMITS", "RELAY_LOAD", "SERVICE_STATUS", "STATIONS"][i], { className, useSQLite: true }])),
        RELAY: { className: "Relay", scriptName: "relay", useSQLite: true },
      },
      outboundService: async (request) => {
        const url = new URL(request.url);
        if (options.access && url.href === `${ACCESS_TEAM}/cdn-cgi/access/certs`) {
          return MFResponse.json({ keys: [{ ...publicJwk, kid: "test-access" }] });
        }
        if (options.upstream && url.href.startsWith("https://upstream.test/releases/")) {
          const answer = options.upstream(url.pathname.slice("/releases/".length), { url: url.href, method: request.method, headers: Object.fromEntries(request.headers), body: new Uint8Array() });
          return new MFResponse(answer.body ?? null, { status: answer.status, headers: answer.headers ?? {} });
        }
        if (url.href === "https://www.googleapis.com/oauth2/v3/certs") {
          return MFResponse.json({ keys: [publicJwk] }, { headers: { "cache-control": "max-age=3600" } });
        }
        if (url.href === "https://oauth2.googleapis.com/token") {
          const body = new URLSearchParams(await request.text());
          const code = codes.get(body.get("code") ?? "");
          codes.delete(body.get("code") ?? "");
          if (!code || (await digest(body.get("code_verifier") ?? "")) !== code.challenge || ![origin, oldOrigin].some((o) => body.get("redirect_uri") === o + "/v1/auth/google/callback")) return new MFResponse(null, { status: 401 });
          const idToken = await new SignJWT({
            nonce: code.invalid === "nonce" ? "incorrect" : code.nonce,
            sub: code.sub,
            email: code.sub === "google-test-user" ? "test@example.test" : `${code.sub}@example.test`,
            email_verified: code.invalid !== "email",
            name: `Name of ${code.sub}`,
            picture: "https://example.test/p.png",
          })
            .setProtectedHeader({ alg: "RS256", kid: "test-google" })
            .setIssuedAt(now())
            .setExpirationTime(now() + 300)
            .setIssuer("https://accounts.google.com")
            .setAudience(code.invalid === "aud" ? "wrong" : "test-google-client")
            .sign(privateKey);
          return MFResponse.json({ id_token: idToken });
        }
        if (url.href === "https://mail.test/send" && options.mail) {
          const message = JSON.parse(await request.text()) as MailMessage;
          const sent = options.mail === true ? true : options.mail(message);
          if (sent !== true) return new MFResponse(sent || "E_INTERNAL_SERVER_ERROR", { status: 500 });
          mails.push(message);
          return new MFResponse(null, { status: 200 });
        }
        if (url.origin === "https://api.axiom.co" && options.axiom) {
          if (options.axiom !== "real") return options.axiom(request as unknown as Request) as any;
          const answer = await globalThis.fetch(url, { method: request.method, headers: Object.fromEntries(request.headers), body: await request.arrayBuffer() });
          return new MFResponse(await answer.arrayBuffer(), { status: answer.status });
        }
        if (options.relay && url.origin === options.relay) {
          // Workerd networking to the real local relay uses a separate service
          // binding in the native harness; JS fetch does not proxy WebSockets.
          throw new Error("native relay requires network binding");
        }
        if (options.push) {
          const answer = await options.push({ url: url.href, method: request.method, headers: Object.fromEntries(request.headers), body: new Uint8Array(await request.arrayBuffer()) });
          return new MFResponse(answer.body ?? null, { status: answer.status, headers: answer.body ? { "content-type": "application/json" } : {} });
        }
        throw new Error("unexpected outbound request: " + url.origin + url.pathname);
      },
      }],
    }),
  );
  try {
    await mf.ready;
  } catch (error) {
    await mf.dispose();
    throw error;
  }
  const fetch = (path: string, init?: RequestInit) => mf.dispatchFetch(origin + path, init as any);
  /** A request to the console's host. */
  const fetchAdmin = (path: string, init?: RequestInit) => mf.dispatchFetch(adminOrigin + path, init as any);
  const fetchPreview = (path: string, init?: RequestInit) => mf.dispatchFetch(previewOrigin + path, init as any);
  /** A request to the test channel's host. */
  const fetchBeta = (path: string, init?: RequestInit) => mf.dispatchFetch(betaOrigin + path, init as any);
  /** A request to a host's old name (before the rename): "main", "admin" or "preview". */
  const fetchOld = (on: "main" | "admin" | "preview", path: string, init?: RequestInit) => mf.dispatchFetch({ main: oldOrigin, admin: oldAdminOrigin, preview: oldPreviewOrigin }[on] + path, init as any);
  /** A request straight to one of the Workers ("api", "relay", "static"), whatever the routes say. */
  const fetchWorker = async (name: string, url: string, init?: RequestInit) => ((await mf.getWorker(name)) as unknown as { fetch(url: string, init?: RequestInit): Promise<Response> }).fetch(url, init);
  /** One of the API's Durable Objects, by its binding and name, with the test hooks test/worker.ts gives it. */
  // deno-lint-ignore no-explicit-any
  const object = async (binding: "DIRECTORY" | "ACCOUNTS" | "STATIONS", name: string): Promise<any> => {
    const namespace: any = await mf.getDurableObjectNamespace(binding, "api");
    return namespace.get(namespace.idFromName(name));
  };
  /**
   * Once what still.fail cloud tells devices' and stations' objects after a change has got there (the Directory's
   * deliveries go out as the change answers): the barrier a test waits at instead of waiting a while.
   */
  const settled = async () => (await object("DIRECTORY", "primary")).settled();
  /**
   * Once everything still.fail cloud sends on a socket for what was done or said before now has arrived: where a test
   * reads a socket. The runtime answers "ping" itself, in the socket's order. By the first pong, what the socket said
   * before has reached its object; `settled` then waits for that to be answered and for what the Directory tells; the
   * second pong comes after everything those sent.
   */
  const heard = async (ws: { send(data: string): void; addEventListener(type: "message", on: (event: { data: unknown }) => void): void; removeEventListener(type: "message", on: (event: { data: unknown }) => void): void }) => {
    const pong = () =>
      new Promise<void>((resolve) => {
        const on = (event: { data: unknown }) => {
          if (event.data !== "pong") return;
          ws.removeEventListener("message", on);
          resolve();
        };
        ws.addEventListener("message", on);
        ws.send("ping");
      });
    await pong();
    await settled();
    await pong();
  };
  async function begin(sub = "google-test-user", invalid?: string, callback = "http://127.0.0.1:32145/oauth/callback") {
    const verifier = randomSecret(),
      state = randomSecret();
    const start = new URLSearchParams({
      state,
      redirect_uri: callback,
      code_challenge: await digest(verifier),
      code_challenge_method: "S256",
    });
    let response = await fetch("/v1/auth/google/start?" + start, { redirect: "manual" });
    // With signing in by email offered (`mail`), the page that asks how comes first: Google, as a browser chooses it.
    if (response.status === 200 && options.mail) {
      const id = /action="\/v1\/auth\/login\/([A-Za-z0-9_-]{43})"/.exec(await response.text())?.[1];
      const cookie = response.headers.get("set-cookie")?.split(";")[0] ?? "";
      response = await fetch(`/v1/auth/login/${id}`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", origin, cookie }, body: new URLSearchParams({ csrf: cookie.split("=")[1] ?? "", via: "google" }).toString() });
    }
    if (response.status !== 302) throw new Error("login start: " + response.status);
    const google = new URL(response.headers.get("location")!);
    const googleCode = ulid();
    codes.set(googleCode, {
      nonce: google.searchParams.get("nonce")!,
      challenge: google.searchParams.get("code_challenge")!,
      sub,
      invalid,
    });
    return {
      verifier,
      state,
      callback,
      google,
      googleCode,
      cookie: response.headers.get("set-cookie")!.split(";")[0],
    };
  }
  async function complete(flow: Awaited<ReturnType<typeof begin>>) {
    const callback = await fetch(
      "/v1/auth/google/callback?" +
        new URLSearchParams({
          state: flow.google.searchParams.get("state")!,
          code: flow.googleCode,
        }),
      { headers: { cookie: flow.cookie }, redirect: "manual" },
    );
    if (callback.status !== 302) throw new Error("callback: " + callback.status);
    const redirect = new URL(callback.headers.get("location")!);
    return { response: callback, redirect, code: redirect.searchParams.get("code")! };
  }
  async function exchange(flow: Awaited<ReturnType<typeof begin>>, code: string, verifier = flow.verifier) {
    return fetch("/v1/auth/token", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code, code_verifier: verifier, redirect_uri: flow.callback }),
    });
  }
  async function login(sub?: string) {
    const flow = await begin(sub);
    const result = await complete(flow);
    const response = await exchange(flow, result.code);
    if (response.status !== 200) throw new Error("exchange: " + response.status);
    return (await response.json()) as Tokens;
  }
  /** Calls the API as a logged-in account (on the console's host with `on: "admin"`, the test channel's with "beta"). */
  /** A token Cloudflare Access would add for `email` (Cf-Access-Jwt-Assertion); `aud` another application's, `expired`. */
  const accessToken = (email: string, made: { aud?: string; expired?: boolean; issuer?: string } = {}) =>
    new SignJWT({ email, type: "app" })
      .setProtectedHeader({ alg: "RS256", kid: "test-access" })
      .setIssuedAt(now() - 600)
      .setExpirationTime(made.expired ? now() - 60 : now() + 300)
      .setIssuer(made.issuer ?? ACCESS_TEAM)
      .setAudience(made.aud ?? "test-access-aud")
      .sign(privateKey);
  const as = (tokens: Tokens, on: "main" | "admin" | "beta" = "main") => (method: string, path: string, value?: unknown) =>
    ({ main: fetch, admin: fetchAdmin, beta: fetchBeta })[on](path, {
      method,
      headers: { authorization: `Bearer ${tokens.access_token}`, ...(value === undefined ? {} : { "content-type": "application/json" }) },
      ...(value === undefined ? {} : { body: JSON.stringify(value) }),
    });
  return {
    mf,
    now,
    accessToken,
    origin,
    adminOrigin,
    betaOrigin,
    oldOrigin,
    oldAdminOrigin,
    as,
    grantJwk,
    grantPublicJwk,
    adminToken,
    feedbackToken,
    signingKey,
    codes,
    mails,
    fetch,
    fetchAdmin,
    fetchPreview,
    fetchBeta,
    fetchOld,
    fetchWorker,
    object,
    settled,
    heard,
    begin,
    complete,
    exchange,
    login,
    close: () => mf.dispose(),
  };
}

/** The static sites' files, by site (`/web/…`, `/admin/…`, `/preview/…`: see test/static-worker.ts). */
export const STAND_IN_FILES: Record<string, string> = {
  "/web/index.html": "<title>still.fail</title>",
  "/web/web.html": "<title>still.fail · web</title>",
  "/web/assets/app.js": "// the web app",
  "/web/sw.js": "// the notifications' worker",
  "/web/mbui/app.js": "// the app, as mbui-web built it",
  "/web/mbui/host.js": "// mbui's web host",
  "/admin/index.html": "<title>still.fail 管理后台</title>",
  "/admin/assets/console.js": "// the console",
  "/preview/_stillfail/frame.html": "<title>still.fail preview</title>",
  "/preview/_stillfail/sw.js": "// the preview's service worker",
  "/preview/404.html": "这是 still.fail 的预览地址",
};

/** The files the build brotlis beside them (apps/mbui/scripts/web-app.sh): app.js's, not host.js's (a build without one). */
const STAND_IN_PACKED: Record<string, string> = { "/web/mbui/app.js.br": "/web/mbui/app.js" };

function standInAssets(request: Request): Response {
  const path = new URL(request.url).pathname;
  const packed = STAND_IN_PACKED[path];
  if (packed) return new MFResponse(brotliCompressSync(STAND_IN_FILES[packed]!)) as unknown as Response;
  const body = STAND_IN_FILES[path];
  const headers = path.endsWith(".html") ? { "content-type": "text/html; charset=utf-8" } : {};
  return body === undefined ? new MFResponse("Not found", { status: 404 }) as unknown as Response : new MFResponse(body, { headers }) as unknown as Response;
}
