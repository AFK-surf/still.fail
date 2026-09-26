import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions, Response as MFResponse, Log, LogLevel } from "miniflare";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { ulid } from "ulid";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";

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
    /** The ASSETS binding: a few stand-in files of both web apps unless given. */
    assets?: (request: Request) => Promise<Response> | Response;
    /** Axiom: a stand-in answering its requests, or "real" to reach it (with AXIOM_TOKEN from the environment). */
    axiom?: ((request: Request) => Promise<Response> | Response) | "real";
  } = {},
) {
  const origin = options.origin ?? "https://relay.example";
  const adminOrigin = options.adminOrigin ?? "https://admin.relay.example";
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
  const bundled = await build({
    entryPoints: ["test/worker.ts"],
    bundle: true,
    write: false,
    format: "esm",
    platform: "node",
    banner: {
      js: 'import { createRequire } from "node:module"; const require = createRequire("file:///worker.js");',
    },
    external: ["cloudflare:workers", "cloudflare:sockets", "node:*"],
    conditions: ["workerd", "worker", "browser"],
  });
  const mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: bundled.outputFiles[0].text,
      compatibilityDate: "2026-09-08",
      host: "127.0.0.1",
      ...(options.port ? { port: options.port } : {}),
      compatibilityFlags: ["nodejs_compat"],
      log: new Log(LogLevel.ERROR),
      ...(options.persist ? { resourcePersistencePath: options.persist } : {}),
      bindings: {
        PUBLIC_ORIGIN: origin,
        ADMIN_ORIGIN: adminOrigin,
        GOOGLE_CLIENT_ID: options.noGoogle ? "" : "test-google-client",
        GOOGLE_CLIENT_SECRET: randomSecret(),
        AUTH_SIGNING_KEY: signingKey,
        ADMIN_TOKEN: adminToken,
        ADMIN_EMAIL: options.adminEmail ?? "alice@example.test",
        GRANT_SIGNING_JWK: JSON.stringify(grantJwk),
        ...(options.relayUrl ? { RELAY_URL: options.relayUrl } : {}),
        ...(options.axiom ? { AXIOM_TOKEN: options.axiom === "real" ? process.env.AXIOM_TOKEN! : "test-axiom-token", AXIOM_DATASET: options.axiom === "real" ? process.env.AXIOM_DATASET ?? "ember" : "ember-test" } : {}),
      },
      serviceBindings: {
        ...(options.relay ? { TEST_RELAY: { external: { address: new URL(options.relay).host, http: {} } } } : {}),
        ASSETS: (options.assets ?? standInAssets) as any,
      },
      durableObjects: Object.fromEntries(["Account", "LoginAttempt", "LoginLimiter", "Relay", "DiscoveryRecord", "RelayBudget", "Directory", "TelemetryLimiter"].map((className, i) => [["ACCOUNTS", "LOGINS", "LOGIN_LIMITS", "RELAY", "RECORDS", "RELAY_BUDGET", "DIRECTORY", "TELEMETRY_LIMITS"][i], { className, useSQLite: true }])),
      outboundService: async (request) => {
        const url = new URL(request.url);
        if (url.href === "https://www.googleapis.com/oauth2/v3/certs") {
          return MFResponse.json({ keys: [publicJwk] }, { headers: { "cache-control": "max-age=3600" } });
        }
        if (url.href === "https://oauth2.googleapis.com/token") {
          const body = new URLSearchParams(await request.text());
          const code = codes.get(body.get("code") ?? "");
          codes.delete(body.get("code") ?? "");
          if (!code || (await digest(body.get("code_verifier") ?? "")) !== code.challenge || body.get("redirect_uri") !== origin + "/v1/auth/google/callback") return new MFResponse(null, { status: 401 });
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
        throw new Error("unexpected outbound request: " + url.origin + url.pathname);
      },
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
    as,
    grantPublicJwk,
    adminToken,
    signingKey,
    codes,
    fetch,
    fetchAdmin,
    begin,
    complete,
    exchange,
    login,
    close: () => mf.dispose(),
  };
}

/** Files like Cloudflare's assets binding serves them: a directory's index.html for its path with a slash, 404 for anything else. */
export const STAND_IN_FILES: Record<string, string> = {
  "/index.html": "<title>ember</title>",
  "/assets/app.js": "// the web app",
  "/admin-app/index.html": "<title>ember 管理后台</title>",
  "/admin-app/assets/console.js": "// the console",
};

function standInAssets(request: Request): Response {
  const path = new URL(request.url).pathname;
  const body = STAND_IN_FILES[path.endsWith("/") ? `${path}index.html` : path];
  return body === undefined ? new MFResponse("Not found", { status: 404 }) as unknown as Response : new MFResponse(body) as unknown as Response;
}
