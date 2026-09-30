import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions, Response as MFResponse, Log, LogLevel } from "miniflare";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { ulid } from "ulid";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";

/** A request the Worker made to somewhere outside (a push service, say), as a stand-in sees it. */
export interface OutboundRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: Uint8Array;
}

export async function harness(
  options: {
    relay?: string;
    origin?: string;
    persist?: string;
    port?: number;
    signingKey?: string;
    noGoogle?: boolean;
    relayUrl?: string;
    /** The console's admin (alice unless said otherwise). */
    adminEmail?: string;
    /** The console's host. */
    adminOrigin?: string;
    previewOrigin?: string;
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
    /** Push services, FCM and its token endpoint: a stand-in answering every other outbound request. */
    push?: (request: OutboundRequest) => Promise<{ status: number; body?: string }> | { status: number; body?: string };
  } = {},
) {
  const origin = options.origin ?? "https://relay.example";
  const adminOrigin = options.adminOrigin ?? "https://admin.relay.example";
  const previewOrigin = options.previewOrigin ?? "https://preview.relay.example";
  const oldOrigin = options.oldOrigin ?? "https://old.relay.example";
  const oldAdminOrigin = options.oldAdminOrigin ?? "https://admin.old.relay.example";
  const oldPreviewOrigin = options.oldPreviewOrigin ?? "https://preview.old.relay.example";
  const signingKey = options.signingKey ?? randomSecret(),
    adminToken = randomSecret();
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const publicJwk = {
    ...(await exportJWK(publicKey)),
    kid: "test-google",
    alg: "RS256",
    use: "sig",
  };
  const codes = new Map<string, { nonce: string; challenge: string; sub: string; invalid?: string }>();
  const grantPair = await generateKeyPair("EdDSA", { crv: "Ed25519", extractable: true });
  const grantJwk = { ...(await exportJWK(grantPair.privateKey)), kid: "test-grant" };
  const grantPublicJwk = { ...(await exportJWK(grantPair.publicKey)), kid: "test-grant" };
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
    conditions: ["workerd", "worker", "browser"],
  })).outputFiles[0].text;
  // still.fail cloud's Workers as Cloudflare runs them: the static sites on their hosts, and routes (which take
  // precedence) sending the API's and the relay's paths to theirs (cloud/wrangler*.jsonc); on each host's new name
  // and its old one.
  const hosts = [origin, oldOrigin].map((o) => new URL(o).host), adminHosts = [adminOrigin, oldAdminOrigin].map((o) => new URL(o).host);
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
        bindings: { PUBLIC_ORIGIN: origin, ADMIN_ORIGIN: adminOrigin, PREVIEW_ORIGIN: previewOrigin, PUBLIC_ORIGIN_ALIASES: oldOrigin, ADMIN_ORIGIN_ALIASES: oldAdminOrigin, PREVIEW_ORIGIN_ALIASES: oldPreviewOrigin },
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
        routes: [...hosts.flatMap((host) => [`${host}/v1/*`, `${host}/healthz*`, `${host}/install.sh*`, `${host}/releases/*`, `${host}/.well-known/*`, `${host}/__test/*`]), ...adminHosts.map((host) => `${host}/v1/*`)],
        bindings: {
        PUBLIC_ORIGIN: origin,
        PUBLIC_ORIGIN_ALIASES: oldOrigin,
        ADMIN_ORIGIN: adminOrigin,
        ADMIN_ORIGIN_ALIASES: oldAdminOrigin,
        GOOGLE_CLIENT_ID: options.noGoogle ? "" : "test-google-client",
        GOOGLE_CLIENT_SECRET: randomSecret(),
        AUTH_SIGNING_KEY: signingKey,
        ADMIN_TOKEN: adminToken,
        ADMIN_EMAIL: options.adminEmail ?? "alice@example.test",
        GRANT_SIGNING_JWK: JSON.stringify(grantJwk),
        ...(options.relayUrl ? { RELAY_URL: options.relayUrl } : {}),
        ...(options.vapid ? { VAPID_PUBLIC_KEY: options.vapid.publicKey, VAPID_PRIVATE_KEY: options.vapid.privateKey, VAPID_SUBJECT: "mailto:ops@example.test" } : {}),
        ...(options.fcm ? { FCM_SERVICE_ACCOUNT: options.fcm } : {}),
        ...(options.axiom ? { AXIOM_TOKEN: options.axiom === "real" ? process.env.AXIOM_TOKEN! : "test-axiom-token", AXIOM_DATASET: options.axiom === "real" ? process.env.AXIOM_DATASET ?? "ember" : "ember-test" } : {}),
      },
      r2Buckets: ["RELEASES"],
      durableObjects: Object.fromEntries(["Account", "LoginAttempt", "LoginLimiter", "Directory", "TelemetryLimiter"].map((className, i) => [["ACCOUNTS", "LOGINS", "LOGIN_LIMITS", "DIRECTORY", "TELEMETRY_LIMITS"][i], { className, useSQLite: true }])),
      outboundService: async (request) => {
        const url = new URL(request.url);
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
            .setIssuedAt()
            .setExpirationTime("5m")
            .setIssuer("https://accounts.google.com")
            .setAudience(code.invalid === "aud" ? "wrong" : "test-google-client")
            .sign(privateKey);
          return MFResponse.json({ id_token: idToken });
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
  /** A request to a host's old name (before the rename): "main", "admin" or "preview". */
  const fetchOld = (on: "main" | "admin" | "preview", path: string, init?: RequestInit) => mf.dispatchFetch({ main: oldOrigin, admin: oldAdminOrigin, preview: oldPreviewOrigin }[on] + path, init as any);
  /** A request straight to one of the Workers ("api", "relay", "static"), whatever the routes say. */
  const fetchWorker = async (name: string, url: string, init?: RequestInit) => ((await mf.getWorker(name)) as unknown as { fetch(url: string, init?: RequestInit): Promise<Response> }).fetch(url, init);
  async function begin(sub = "google-test-user", invalid?: string, callback = "http://127.0.0.1:32145/oauth/callback") {
    const verifier = randomSecret(),
      state = randomSecret();
    const start = new URLSearchParams({
      state,
      redirect_uri: callback,
      code_challenge: await digest(verifier),
      code_challenge_method: "S256",
    });
    const response = await fetch("/v1/auth/google/start?" + start, { redirect: "manual" });
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
  /** Calls the API as a logged-in account (on the console's host with `on: "admin"`). */
  const as = (tokens: Tokens, on: "main" | "admin" = "main") => (method: string, path: string, value?: unknown) =>
    (on === "admin" ? fetchAdmin : fetch)(path, {
      method,
      headers: { authorization: `Bearer ${tokens.access_token}`, ...(value === undefined ? {} : { "content-type": "application/json" }) },
      ...(value === undefined ? {} : { body: JSON.stringify(value) }),
    });
  return {
    mf,
    origin,
    adminOrigin,
    oldOrigin,
    oldAdminOrigin,
    as,
    grantPublicJwk,
    adminToken,
    signingKey,
    codes,
    fetch,
    fetchAdmin,
    fetchPreview,
    fetchOld,
    fetchWorker,
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
  "/web/assets/app.js": "// the web app",
  "/admin/index.html": "<title>still.fail 管理后台</title>",
  "/admin/assets/console.js": "// the console",
  "/preview/_stillfail/frame.html": "<title>still.fail preview</title>",
  "/preview/_stillfail/sw.js": "// the preview's service worker",
  "/preview/_ember/frame.html": "<title>still.fail preview (old path)</title>",
  "/preview/_ember/sw.js": "// the preview's service worker (old path)",
  "/preview/404.html": "这是 still.fail 的预览地址",
};

function standInAssets(request: Request): Response {
  const body = STAND_IN_FILES[new URL(request.url).pathname];
  return body === undefined ? new MFResponse("Not found", { status: 404 }) as unknown as Response : new MFResponse(body) as unknown as Response;
}
