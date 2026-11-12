// A self-hosted cloud (selfhost/): its workerd config as the wrangler files make it, its router and static sites, and
// signing in without Google: with an email alone, and through an OpenID provider of the operator's.
import assert from "node:assert/strict";
import test from "node:test";
import { digest, randomSecret, type Tokens } from "../src/auth.ts";
import { routes, workerdConfig } from "../selfhost/config.ts";
import { routeOf } from "../selfhost/router.ts";
import { parseHeaders, serveFiles, typeOf, type StaticEnv } from "../selfhost/static.ts";
import { harness, OIDC_ISSUER } from "./harness.ts";

type H = Awaited<ReturnType<typeof harness>>;
type Answer = Awaited<ReturnType<H["fetch"]>>;

test("the config names none of still.fail's hosts: every name and key is read from the environment", () => {
  const config = workerdConfig();
  assert.doesNotMatch(config, /still\.fail|monoid\.build|youdid\.wtf|3720\.org|39\.105|cloudflareaccess/);
  for (const name of ["PUBLIC_ORIGIN", "ADMIN_ORIGIN", "RELAY_URL", "AUTH_SIGNING_KEY", "GRANT_SIGNING_JWK", "OIDC_ISSUER", "EMAIL_FROM"]) {
    assert.match(config, new RegExp(`\\(name = "${name}", fromEnvironment = "${name}"\\)`), name);
  }
  // Each of the API's Durable Objects, SQLite where its migration says so; the relay's own is not there (it is iroh-relay).
  for (const cls of ["Account", "Directory", "Station", "LoginAttempt", "LoginLimiter", "TelemetryLimiter", "RelayLoad", "ServiceStatus"]) {
    assert.match(config, new RegExp(`className = "${cls}", uniqueKey = "stillfail-cloud-${cls}", enableSql = true`), cls);
  }
  assert.doesNotMatch(config, /className = "Relay"/);
  assert.match(config, /\(name = "RELEASES", service = \(name = "releases", entrypoint = "Releases"\)\)/);
  assert.match(config, /\(name = "EMAIL", service = \(name = "mail", entrypoint = "Mail"\)\)/);
});

test("the routes are the wrangler files' on the cloud's own hosts: the API's paths first, each site's host for the rest", () => {
  const env = { PUBLIC_ORIGIN: "https://cloud.example", ADMIN_ORIGIN: "https://admin.cloud.example", PREVIEW_ORIGIN: "https://preview.cloud.example", ROUTES: routes() };
  const to = (url: string) => routeOf(env, new URL(url));
  assert.equal(to("https://cloud.example/v1/me"), "api");
  assert.equal(to("https://cloud.example/healthz"), "api");
  assert.equal(to("https://cloud.example/install.sh"), "api");
  assert.equal(to("https://cloud.example/releases/station.json"), "api");
  assert.equal(to("https://cloud.example/"), "web");
  assert.equal(to("https://cloud.example/w/1/s/2"), "web");
  assert.equal(to("https://admin.cloud.example/v1/admin/users"), "api");
  assert.equal(to("https://admin.cloud.example/users"), "admin");
  assert.equal(to("https://preview.cloud.example/_stillfail/frame"), "preview");
  assert.equal(to("https://preview.cloud.example/v1/me"), "preview", "the preview host has no API");
  assert.equal(to("https://elsewhere.example/v1/me"), null);
  assert.equal(to("http://cloud.example/v1/me"), null, "the origin is the scheme's too");
});

/** A site's files, as the disk service answers for them. */
function site(files: Record<string, string>, handling: StaticEnv["HANDLING"]): StaticEnv {
  const FILES = { fetch: async (request: Request) => {
    const body = files[new URL(request.url).pathname];
    return body === undefined ? new Response(null, { status: 404 }) : new Response(request.method === "HEAD" ? null : body, { headers: { "content-type": "application/octet-stream" } });
  } } as unknown as Fetcher;
  return { FILES, SITE: "admin", HANDLING: handling, PUBLIC_ORIGIN: "https://cloud.example" };
}

test("a site's files are served as Cloudflare's assets are: pages without .html, a directory's index, its _headers, what is missing as its wrangler file says", async () => {
  const files = { "/index.html": "<p>app", "/terms.html": "<p>terms", "/docs/index.html": "<p>docs", "/a.js": "1", "/404.html": "gone", "/_headers": "/a.js\n  Cache-Control: no-cache\n/x/*\n  X-Test: yes\n" };
  const spa = site(files, { html: "auto-trailing-slash", notFound: "single-page-application" });
  const get = async (env: StaticEnv, path: string) => {
    const answer = await serveFiles(new Request(`https://cloud.example${path}`), env);
    return { status: answer.status, type: answer.headers.get("content-type"), cache: answer.headers.get("cache-control"), body: await answer.text() };
  };
  assert.deepEqual(await get(spa, "/"), { status: 200, type: "text/html; charset=utf-8", cache: null, body: "<p>app" });
  assert.equal((await get(spa, "/terms")).body, "<p>terms");
  assert.equal((await get(spa, "/docs/")).body, "<p>docs");
  assert.deepEqual(await get(spa, "/a.js"), { status: 200, type: "text/javascript; charset=utf-8", cache: "no-cache", body: "1" });
  assert.equal((await get(spa, "/chats/1")).body, "<p>app", "the app's own routes");
  assert.equal((await get(spa, "/../index.html")).status, 200, "(normalized by the URL)");
  assert.equal((await get(spa, "/.env")).body, "<p>app", "no dot file is a file");
  const pages = site(files, { html: "auto-trailing-slash", notFound: "404-page" });
  assert.deepEqual(await get(pages, "/nothing"), { status: 404, type: "text/html; charset=utf-8", cache: null, body: "gone" });
  assert.equal((await serveFiles(new Request("https://cloud.example/", { method: "POST" }), spa)).status, 405);
  assert.deepEqual(parseHeaders("# a comment\n/a\n  A: 1\n  B: two: 2\n"), [{ path: "/a", headers: [["A", "1"], ["B", "two: 2"]] }]);
  assert.equal(typeOf("/x.wasm"), "application/wasm");
  assert.equal(typeOf("/x.unknown"), "application/octet-stream");
});

/** The cloud's sign-in page for a browser, from its start. */
async function start(h: H) {
  const verifier = randomSecret(), callback = "http://127.0.0.1:32145/oauth/callback";
  const query = new URLSearchParams({ state: randomSecret(), redirect_uri: callback, code_challenge: await digest(verifier), code_challenge_method: "S256" });
  const answer = await h.fetch("/v1/auth/google/start?" + query, { redirect: "manual" });
  const page = answer.status === 200 ? await answer.text() : "";
  const cookie = answer.headers.get("set-cookie")?.split(";")[0] ?? "";
  const id = /action="\/v1\/auth\/login\/([A-Za-z0-9_-]{43})"/.exec(page)?.[1];
  const post = (fields: Record<string, string>) => h.fetch(`/v1/auth/login/${id}`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", origin: h.origin, cookie }, body: new URLSearchParams({ csrf: cookie.split("=")[1] ?? "", ...fields }).toString() });
  const exchange = async (finished: Answer) => {
    const code = new URL(finished.headers.get("location")!).searchParams.get("code");
    const tokens = await h.fetch("/v1/auth/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ code, code_verifier: verifier, redirect_uri: callback }) });
    assert.equal(tokens.status, 200);
    return (await tokens.json()) as Tokens;
  };
  return { answer, page, cookie, post, exchange };
}

test("without Google, a cloud with mail signs in with an email alone: no Google on its page, and none to be asked for", async () => {
  const h = await harness({ noGoogle: true, mail: true });
  try {
    assert.equal((await (await h.fetch("/healthz")).json() as { google_login: boolean }).google_login, true, "signing in is set up");
    const b = await start(h);
    assert.equal(b.answer.status, 200);
    assert.match(b.page, /type="email"/);
    assert.doesNotMatch(b.page, /value="google"|accounts\.google\.com|Google/);
    assert.equal((await b.post({ via: "google" })).status, 200, "the page again, not Google");
    assert.equal((await b.post({ via: "email", email: "owner@example.test" })).status, 200);
    const code = /\b(\d{6})\b/.exec(h.mails.at(-1)!.text)![1]!;
    const tokens = await b.exchange(await b.post({ via: "code", code }));
    assert.equal(tokens.email, "owner@example.test");
  } finally {
    await h.close();
  }
});

test("without Google and without mail nobody signs in", async () => {
  const h = await harness({ noGoogle: true });
  try {
    assert.equal((await h.fetch("/v1/auth/google/start?state=x")).status, 503);
  } finally {
    await h.close();
  }
});

test("through the operator's OpenID provider: its page, its endpoints from its discovery, its accounts named apart from Google's", async () => {
  const h = await harness({ oidc: true, mail: true });
  try {
    const b = await start(h);
    assert.match(b.page, /Continue with Example SSO|使用 Example SSO 账号继续/);
    assert.doesNotMatch(b.page, /Google/);
    const gone = await b.post({ via: "google" });
    assert.equal(gone.status, 302);
    const at = new URL(gone.headers.get("location")!);
    assert.equal(`${at.origin}${at.pathname}`, `${OIDC_ISSUER}/authorize`);
    assert.equal(at.searchParams.get("redirect_uri"), `${h.origin}/v1/auth/google/callback`);
    const code = randomSecret();
    h.codes.set(code, { nonce: at.searchParams.get("nonce")!, challenge: at.searchParams.get("code_challenge")!, sub: "user|42" });
    const callback = await h.fetch("/v1/auth/google/callback?" + new URLSearchParams({ state: at.searchParams.get("state")!, code }), { headers: { cookie: gone.headers.get("set-cookie")!.split(";")[0]! }, redirect: "manual" });
    const tokens = await b.exchange(callback);
    assert.equal(tokens.email, "user42@sso.example.test");
    assert.match(tokens.subject, /^oi-[A-Za-z0-9_-]{32}$/, "its sub is the provider's alone");
    assert.equal(tokens.subject, `oi-${(await digest(`${OIDC_ISSUER}\0user|42`)).slice(0, 32)}`);
  } finally {
    await h.close();
  }
});
