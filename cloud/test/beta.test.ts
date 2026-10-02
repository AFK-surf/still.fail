import assert from "node:assert/strict";
import test from "node:test";
import { Response as MFResponse } from "miniflare";
import { betaOrigin } from "../src/compat.ts";
import { installScript, releaseType } from "../src/install.ts";
import { harness } from "./harness.ts";

// The test channel (BETA_ORIGIN, beta.still.fail): the web app's files on a host of their own, the API on its paths
// there for the accounts the admin let in. alice is the admin in every harness.

test("the admin lets an account into the test channel and out; /v1/me says beta only when it is on", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const admin = h.as(aliceTokens, "admin");
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    const users = async () => ((await (await admin("GET", "/v1/admin/users")).json()) as { users: { sub: string; beta: boolean }[] }).users;
    assert.deepEqual((await users()).map((u) => u.beta), [false, false]);
    const me = async () => ((await (await bob("GET", "/v1/me")).json()) as { user: Record<string, unknown> }).user;
    assert.equal("beta" in (await me()), false, "not said when off: a client from before it sees what it always saw");

    const on = await admin("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: true });
    assert.equal(on.status, 200);
    assert.deepEqual(await on.json(), { sub: bobTokens.subject, beta: true });
    assert.equal((await users()).find((u) => u.sub === bobTokens.subject)?.beta, true);
    assert.equal((await me()).beta, true);

    assert.equal((await admin("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: false })).status, 200);
    assert.equal("beta" in (await me()), false);

    assert.equal((await admin("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: "yes" })).status, 400);
    assert.equal((await admin("POST", "/v1/admin/users/nobody/beta", { on: true })).status, 404);
    // Only the admin, only on the console's host.
    assert.equal((await h.as(bobTokens, "admin")("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: true })).status, 404);
    assert.equal((await h.as(aliceTokens)("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: true })).status, 404);
    assert.equal("beta" in (await me()), false);
  } finally {
    await h.close();
  }
});

test("on the test channel's host an account not let in is told not_beta; signing in, refreshing and signing out stay open", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const bobTokens = await h.login("bob");
    const bobBeta = h.as(bobTokens, "beta");
    const refused = await bobBeta("GET", "/v1/me");
    assert.equal(refused.status, 403);
    assert.equal(((await refused.json()) as { error: string; stable: string }).error, "not_beta");
    assert.equal((await bobBeta("POST", "/v1/workspaces", { name: "W" })).status, 403);
    const socket = await h.fetchBeta("/v1/events", { headers: { upgrade: "websocket", "sec-websocket-protocol": `stillfail-events, stillfail-token.${bobTokens.access_token}` } });
    assert.equal(socket.status, 403);
    // The same account on the stable host is as before.
    assert.equal((await h.as(bobTokens)("GET", "/v1/me")).status, 200);
    // No token, or a bad one: what any host answers.
    assert.equal((await h.fetchBeta("/v1/me")).status, 401);
    assert.equal((await h.fetchBeta("/v1/me", { headers: { authorization: "Bearer nonsense" } })).status, 401);
    // Its session works there, so the page can be told and sign out.
    const refreshed = await h.fetchBeta("/v1/auth/refresh", { method: "POST", headers: { authorization: `Bearer ${bobTokens.refresh_token}`, "content-type": "application/json" }, body: JSON.stringify({ request_id: "01J0000000000000000000000B" }) });
    assert.equal(refreshed.status, 200);

    // Let in, it is served there like on the stable host.
    await h.as(aliceTokens, "admin")("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: true });
    const me = await bobBeta("GET", "/v1/me");
    assert.equal(me.status, 200);
    assert.equal(((await me.json()) as { user: { beta?: boolean } }).user.beta, true);
    // What the stable host would answer (bob's free workspace), not the test channel's refusal.
    const made = await bobBeta("POST", "/v1/workspaces", { name: "W" });
    assert.equal(made.status, 200);
    assert.equal((await h.fetchBeta("/healthz")).status, 200);
  } finally {
    await h.close();
  }
});

test("the beta apps say x-stillfail-channel: beta on the stable host, and are gated the same way", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const bobTokens = await h.login("bob");
    const call = (path: string, channel?: string) => h.fetch(path, { headers: { authorization: `Bearer ${bobTokens.access_token}`, ...(channel ? { "x-stillfail-channel": channel } : {}) } });
    const refused = await call("/v1/me", "beta");
    assert.equal(refused.status, 403);
    assert.equal(((await refused.json()) as { error: string }).error, "not_beta");
    assert.equal((await call("/v1/me")).status, 200);
    assert.equal((await call("/v1/me", "stable")).status, 200);
    // Signing in and staying signed in go on, so the app can say why.
    const refreshed = await h.fetch("/v1/auth/refresh", { method: "POST", headers: { authorization: `Bearer ${bobTokens.refresh_token}`, "content-type": "application/json", "x-stillfail-channel": "beta" }, body: JSON.stringify({ request_id: "01J0000000000000000000000C" }) });
    assert.equal(refreshed.status, 200);
    await h.as(aliceTokens, "admin")("POST", `/v1/admin/users/${bobTokens.subject}/beta`, { on: true });
    assert.equal((await call("/v1/me", "beta")).status, 200);
  } finally {
    await h.close();
  }
});

test("signing in on the test channel starts on the main host, where Google returns, and comes back to the test channel", async () => {
  const h = await harness();
  try {
    const callback = `${h.betaOrigin}/auth/callback`;
    const start = new URLSearchParams({ state: "s".repeat(43), redirect_uri: callback, code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    const moved = await h.fetchBeta(`/v1/auth/google/start?${start}`, { redirect: "manual" });
    assert.equal(moved.status, 302);
    assert.equal(moved.headers.get("location"), `${h.origin}/v1/auth/google/start?${start}`);
    assert.equal(moved.headers.get("set-cookie"), null);

    const flow = await h.begin("carol", undefined, callback);
    assert.equal(flow.google.searchParams.get("redirect_uri"), `${h.origin}/v1/auth/google/callback`, "no new redirect URI at Google");
    const { redirect, code } = await h.complete(flow);
    assert.equal(`${redirect.origin}${redirect.pathname}`, callback);
    const exchanged = await h.fetchBeta("/v1/auth/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ code, code_verifier: flow.verifier, redirect_uri: callback }) });
    assert.equal(exchanged.status, 200);
    const tokens = (await exchanged.json()) as { access_token: string };
    // Signed in, and told it is not let in yet.
    const me = await h.fetchBeta("/v1/me", { headers: { authorization: `Bearer ${tokens.access_token}` } });
    assert.equal(me.status, 403);
    // Only its callback: no other page of the host.
    const elsewhere = new URLSearchParams({ state: "s".repeat(43), redirect_uri: `${h.betaOrigin}/w/x`, code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    assert.equal((await h.fetch(`/v1/auth/google/start?${elsewhere}`, { redirect: "manual" })).status, 400);
  } finally {
    await h.close();
  }
});

test("the test channel's pages are the web app's, not to be indexed, and say they are the test channel's", async () => {
  const INDEX = '<!doctype html><html><head><title>still.fail</title><meta property="og:title" content="still.fail — 编码 agent"><meta property="og:image" content="https://app.still.fail/og-image.png"></head><body></body></html>';
  const MANIFEST = '{"name":"still.fail","short_name":"still.fail","start_url":"./"}';
  const assets = (request: Request) => {
    const path = new URL(request.url).pathname;
    if (path === "/web/index.html") return new MFResponse(INDEX, { headers: { "content-type": "text/html; charset=utf-8" } });
    if (path === "/web/site.webmanifest") return new MFResponse(MANIFEST, { headers: { "content-type": "application/manifest+json" } });
    if (path === "/web/assets/app.js") return new MFResponse("// the web app", { headers: { "content-type": "text/javascript" } });
    if (path === "/web/favicon.svg" || path === "/web/favicon-beta.svg") return new MFResponse(path, { headers: { "content-type": "image/svg+xml" } });
    return new MFResponse("Not found", { status: 404 });
  };
  const h = await harness({ assets: assets as unknown as (request: Request) => Response });
  try {
    for (const path of ["/", "/w/some-workspace/chats"]) {
      const page = await h.fetchBeta(path);
      assert.equal(page.status, 200);
      assert.equal(page.headers.get("x-robots-tag"), "noindex, nofollow");
      // Named the test channel's before any script runs: the title and the link previews' tags, not the URLs.
      const named = INDEX.replace("<title>still.fail", "<title>youdid.wtf").replace('content="still.fail —', 'content="youdid.wtf —');
      assert.equal(await page.text(), named.replace("<head>", `<head><meta name="stillfail-beta" content="${h.origin}">`), path);
    }
    const manifest = await h.fetchBeta("/site.webmanifest");
    assert.equal(await manifest.text(), '{"name":"youdid.wtf","short_name":"youdid.wtf","start_url":"./"}');
    assert.equal(manifest.headers.get("x-robots-tag"), "noindex, nofollow");
    assert.equal(await (await h.fetch("/site.webmanifest")).text(), MANIFEST);
    const file = await h.fetchBeta("/assets/app.js");
    assert.equal(await file.text(), "// the web app");
    assert.equal(file.headers.get("x-robots-tag"), "noindex, nofollow");
    // Its icons are the beta apps' face, at the same paths.
    assert.equal(await (await h.fetchBeta("/favicon.svg")).text(), "/web/favicon-beta.svg");
    assert.equal(await (await h.fetch("/favicon.svg")).text(), "/web/favicon.svg");
    const robots = await h.fetchBeta("/robots.txt");
    assert.equal(robots.headers.get("x-robots-tag"), "noindex, nofollow");
    assert.equal(await robots.text(), "User-agent: *\nDisallow: /\n");
    // The stable host is as it was.
    const stable = await h.fetch("/");
    assert.equal(stable.headers.get("x-robots-tag"), null);
    assert.equal(await stable.text(), INDEX);
  } finally {
    await h.close();
  }
});

test("the test channel's releases: served by name, installed with ?channel=beta, from its host, or STILLFAIL_CHANNEL", async () => {
  for (const file of ["station-beta.json", "android/beta/latest.json", "beta/stillfail-station-darwin-arm64.tar.gz", "beta/stillfail-station-linux-x64.tar.gz"]) assert.notEqual(releaseType(file), null, file);
  assert.equal(releaseType("desktop/stillfail-beta-mac.yml"), "text/yaml; charset=utf-8");
  // The beta apps' builds, apps of their own.
  assert.equal(releaseType("android/stillfail-beta-1300.apk"), "application/vnd.android.package-archive");
  assert.equal(releaseType("desktop/stillfail-beta-0.1.1300-arm64-mac.zip"), "application/zip");
  assert.equal(releaseType("desktop/stillfail-beta-0.1.1300-arm64-mac.zip.blockmap"), "application/octet-stream");
  assert.equal(releaseType("android/beta/stillfail-beta-1300.apk"), null);
  for (const file of ["beta/ember-station-linux-x64.tar.gz", "beta/station.json", "android/beta/stillfail-1.apk", "desktop/beta/stillfail-mac.yml", "beta/../station.json"]) assert.equal(releaseType(file), null, file);

  assert.match(installScript("https://ember.test"), /channel="\$\{STILLFAIL_CHANNEL:-stable\}"/);
  assert.match(installScript("https://ember.test", "beta"), /channel="\$\{STILLFAIL_CHANNEL:-beta\}"/);
  assert.match(installScript("https://ember.test"), /beta\) release="beta\/stillfail-station-\$platform\.tar\.gz"/);
  assert.doesNotMatch(installScript("https://ember.test"), /__CHANNEL__/);

  const h = await harness();
  try {
    const script = async (get: Promise<{ text(): Promise<string> }>) => (await get).text();
    assert.match(await script(h.fetch("/install.sh")), /STILLFAIL_CHANNEL:-stable/);
    assert.match(await script(h.fetch("/install.sh?channel=beta")), /STILLFAIL_CHANNEL:-beta/);
    const fromBeta = await script(h.fetchBeta("/install.sh"));
    assert.match(fromBeta, /STILLFAIL_CHANNEL:-beta/);
    assert.match(fromBeta, new RegExp(`origin="${h.origin}"`), "the station joins the stable host all the same");
    assert.match(await script(h.fetchBeta("/install.sh?channel=stable")), /STILLFAIL_CHANNEL:-stable/);

    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    await bucket.put("station-beta.json", '{"version":"0.1.2"}');
    await bucket.put("station.json", '{"version":"0.1.1"}');
    await bucket.put("android/latest.json", JSON.stringify({ versionCode: 1, file: "android/stillfail-1.apk" }));
    await bucket.put("android/beta/latest.json", JSON.stringify({ versionCode: 2, file: "android/stillfail-2.apk" }));
    assert.equal(await script(h.fetch("/releases/station-beta.json")), '{"version":"0.1.2"}');
    assert.equal(await script(h.fetchBeta("/releases/station.json")), '{"version":"0.1.1"}');
    // The links that stay follow the stable channel; the beta apps' have links of their own.
    const latest = async (app: string) => (await h.fetch(`/releases/latest/${app}`, { redirect: "manual" })).headers.get("location");
    assert.equal(await latest("android"), "/releases/android/stillfail-1.apk");
    await bucket.put("android/beta/latest.json", JSON.stringify({ versionCode: 2, file: "android/stillfail-beta-2.apk" }));
    assert.equal(await latest("android-beta"), "/releases/android/stillfail-beta-2.apk");
    await bucket.put("desktop/stillfail-mac.yml", "version: 0.1.1\npath: stillfail-0.1.1-arm64-mac.zip\n");
    await bucket.put("desktop/stillfail-beta-mac.yml", "version: 0.1.2\npath: stillfail-beta-0.1.2-arm64-mac.zip\n");
    assert.equal(await latest("mac"), "/releases/desktop/stillfail-0.1.1-arm64-mac.zip");
    assert.equal(await latest("mac-beta"), "/releases/desktop/stillfail-beta-0.1.2-arm64-mac.zip");
  } finally {
    await h.close();
  }
});

test("without BETA_ORIGIN there is no test channel", () => {
  assert.equal(betaOrigin({}), null);
  assert.equal(betaOrigin({ BETA_ORIGIN: " " }), null);
  assert.equal(betaOrigin({ BETA_ORIGIN: "https://beta.still.fail" }), "https://beta.still.fail");
});
