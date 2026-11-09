import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

// still.fail cloud's Workers on its hosts: the static sites (the web app, the admin's console, the preview host) on each
// host's Custom Domain, and the API's and the relay's paths routed to their Workers ahead of them.

test("each host serves its own static site, the API and the relay on their paths ahead of it", async () => {
  const h = await harness();
  try {
    const text = async (response: { status: number; text(): Promise<string> }) => [response.status, await response.text()];
    assert.deepEqual(await text(await h.fetch("/")), [200, "<title>still.fail</title>"]);
    assert.deepEqual(await text(await h.fetch("/w/some-workspace/chats")), [200, "<title>still.fail</title>"]);
    assert.deepEqual(await text(await h.fetch("/assets/app.js")), [200, "// the web app"]);
    // The app's page answers every page but the few the web's own pages have (src/web.ts WEB_PAGES).
    for (const page of ["/login", "/login?return_to=%2F", "/auth/callback?code=x&state=y", "/slack/installed?code=x", "/w/ws1/s/st1/services/job1"]) assert.deepEqual(await text(await h.fetch(page)), [200, "<title>still.fail · web</title>"], page);
    // What another app shares in is the app's too (web/src/mbui/share.ts).
    for (const page of ["/mbui", "/share?text=hi", "/o/ws1/st1/s1", "/w/ws1/s/st1/chats/c1", "/invite", "/auth/callbacks", "/w/ws1/s/st1/services"]) assert.deepEqual(await text(await h.fetch(page)), [200, "<title>still.fail</title>"], page);
    // The app's pages are kept by nothing, its files as their host says (src/web.ts unkept).
    for (const page of ["/", "/w/some-workspace/chats", "/auth/callback?code=x&state=y"]) assert.equal((await h.fetch(page)).headers.get("cache-control"), "no-store", page);
    assert.notEqual((await h.fetch("/assets/app.js")).headers.get("cache-control"), "no-store");
    assert.deepEqual(await text(await h.fetchAdmin("/")), [200, "<title>still.fail 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/codes")), [200, "<title>still.fail 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/auth/callback?code=x&state=y")), [200, "<title>still.fail 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/assets/console.js")), [200, "// the console"]);
    // Each site's files are its own.
    assert.deepEqual(await text(await h.fetchAdmin("/assets/app.js")), [200, "<title>still.fail 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetch("/assets/console.js")), [200, "<title>still.fail</title>"]);
    assert.deepEqual(await text(await h.fetchPreview("/_stillfail/frame")), [200, "<title>still.fail preview</title>"]);
    assert.equal((await h.fetchPreview("/_stillfail/sw.js")).headers.get("service-worker-allowed"), "/");
    assert.equal((await h.fetchPreview("/anything")).status, 404);
    // The API's and the relay's paths are theirs on the main host.
    assert.equal(((await (await h.fetch("/healthz")).json()) as { service: string }).service, "stillfail-cloud");
    const ping = await h.fetch("/ping");
    assert.equal(((await ping.json()) as { service: string }).service, "stillfail-relay");
    assert.equal(ping.headers.get("access-control-allow-origin"), "*", "a browser times it to pick the nearest relay");
    assert.equal((await h.fetch("/generate_204", { headers: { "x-iroh-challenge": "abc" } })).headers.get("x-iroh-response"), "response abc");
    assert.equal((await h.fetch("/v1/nothing-here")).status, 404);
    assert.match((await h.fetch("/install.sh")).headers.get("content-type") ?? "", /shellscript/);
    // The static sites take no writes.
    assert.equal((await h.fetch("/", { method: "POST" })).status, 405);
  } finally {
    await h.close();
  }
});

// src/web.ts `hardened`: the app's answers carry the headers that keep a page from being framed, keep its addresses
// out of other sites' logs, and stop a browser reading a file as something else.
test("the app's host answers with what a page there may do; the test channel's too", async () => {
  const h = await harness();
  try {
    const fetch = async (path: string, beta = false) => (beta ? h.fetchBeta(path) : h.fetch(path));
    for (const [path, beta] of [["/", false], ["/assets/app.js", false], ["/auth/callback?code=x&state=y", false], ["/", true], ["/assets/app.js", true]] as const) {
      const answer = await fetch(path, beta);
      const at = `${path}${beta ? " (test channel)" : ""}`;
      assert.equal(answer.headers.get("referrer-policy"), "no-referrer", at);
      assert.equal(answer.headers.get("x-content-type-options"), "nosniff", at);
      const csp = answer.headers.get("content-security-policy") ?? "";
      for (const said of ["object-src 'none'", "base-uri 'none'", "form-action 'self' https://accounts.google.com", "frame-ancestors 'none'"]) assert.ok(csp.split("; ").includes(said), `${at}: ${said}`);
    }
    // A page asked for on an old host is a redirect first: it says where it went, not what a page may do.
    const old = await h.fetchOld("main", "/w/ws1/chats", { redirect: "manual" });
    assert.equal(old.status, 302);
    assert.equal(old.headers.get("location"), `${h.origin}/w/ws1/chats`);
  } finally {
    await h.close();
  }
});

// src/web.ts `packed` and `built`: the app's script goes as its build brotlied it to a browser that takes brotli, the
// file as it is to one that does not or where the build made none; a file named by its build is kept for good.
test("the app's scripts go as their build brotlied them, and what a build names is kept for good", async () => {
  const h = await harness();
  try {
    for (const beta of [false, true]) {
      const fetch = (path: string, init?: RequestInit) => (beta ? h.fetchBeta(path, init) : h.fetch(path, init));
      const at = beta ? " (test channel)" : "";
      const br = await fetch("/mbui/app.js?b=123", { headers: { "accept-encoding": "gzip, br" } });
      assert.equal(br.status, 200, at);
      assert.match(br.headers.get("vary") ?? "", /accept-encoding/i, at);
      // (brotlied once, by the build and not again by the Worker: the client undoes it once and has the file; what the
      // answer says of its encoding Miniflare keeps to itself, test/web.test.ts reads it)
      assert.equal(await br.text(), "// the app, as mbui-web built it", at);
      assert.equal(br.headers.get("cache-control"), "public, max-age=31536000, immutable", at);
      assert.equal(br.headers.get("x-content-type-options"), "nosniff", at);
      const plain = await fetch("/mbui/app.js?b=123", { headers: { "accept-encoding": "gzip" } });
      assert.notEqual(plain.headers.get("content-encoding"), "br", at);
      assert.equal(await plain.text(), "// the app, as mbui-web built it", at);
      const host = await fetch("/mbui/host.js?b=123", { headers: { "accept-encoding": "br" } });
      assert.notEqual(host.headers.get("content-encoding"), "br", `host.js has no .br${at}`);
      assert.equal(await host.text(), "// mbui's web host", at);
      // without its build's name it is asked after as before; the page itself is kept by nothing
      assert.notEqual((await fetch("/mbui/app.js")).headers.get("cache-control"), "public, max-age=31536000, immutable", at);
      assert.equal((await fetch("/mbui/missing.js?b=123")).headers.get("cache-control"), "no-store", `a missing file is the page${at}`);
    }
  } finally {
    await h.close();
  }
});

test("the console's host answers only the calls its core makes; other API paths are 404 there, and other hosts 421", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const admin = h.as(tokens, "admin");
    assert.equal((await admin("GET", "/v1/me")).status, 200);
    assert.equal((await admin("GET", "/v1/admin/users")).status, 200);
    for (const path of ["/v1/workspaces", "/v1/auth/sessions", "/v1/nothing-here"]) assert.equal((await admin("GET", path)).status, 404, path);
    assert.equal((await admin("POST", "/v1/workspaces", { name: "W" })).status, 404);
    assert.equal((await h.fetchAdmin("/v1/events", { headers: { upgrade: "websocket" } })).status, 404);
    assert.equal((await h.fetchAdmin("/v1/stations/enroll", { method: "POST" })).status, 404);
    // Refreshing and signing out work there, as the core does them.
    const refreshed = await h.fetchAdmin("/v1/auth/refresh", { method: "POST", headers: { authorization: `Bearer ${tokens.refresh_token}`, "content-type": "application/json" }, body: JSON.stringify({ request_id: "01J0000000000000000000000A" }) });
    assert.equal(refreshed.status, 200);
    const next = (await refreshed.json()) as { refresh_token: string };
    const out = await h.fetchAdmin("/v1/auth/logout", { method: "POST", headers: { authorization: `Bearer ${next.refresh_token}`, "content-type": "application/json" }, body: JSON.stringify({ all: false }) });
    assert.equal(out.status, 200);
    // Neither origin is a wildcard: the API turns away a host it is not routed on.
    for (const origin of ["https://other.relay.example", "https://admin.relay.example.evil"]) {
      const response = await h.fetchWorker("api", `${origin}/v1/me`, { headers: { authorization: `Bearer ${tokens.access_token}` } });
      assert.equal(response.status, 421, origin);
    }
  } finally {
    await h.close();
  }
});

test("signing in to the console starts on the main host, where Google returns, and comes back to the console", async () => {
  const h = await harness();
  try {
    const callback = `${h.adminOrigin}/auth/callback`;
    const start = new URLSearchParams({ state: "s".repeat(43), redirect_uri: callback, code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    const moved = await h.fetchAdmin(`/v1/auth/google/start?${start}`, { redirect: "manual" });
    assert.equal(moved.status, 302);
    assert.equal(moved.headers.get("location"), `${h.origin}/v1/auth/google/start?${start}`);
    assert.equal(moved.headers.get("set-cookie"), null, "the login's cookie is set by the host Google calls back");

    const flow = await h.begin("alice", undefined, callback);
    assert.equal(flow.google.searchParams.get("redirect_uri"), `${h.origin}/v1/auth/google/callback`, "Google's redirect is the main origin's, as registered");
    const { redirect, code } = await h.complete(flow);
    assert.equal(`${redirect.origin}${redirect.pathname}`, callback);
    const exchanged = await h.fetchAdmin("/v1/auth/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ code, code_verifier: flow.verifier, redirect_uri: callback }) });
    assert.equal(exchanged.status, 200);
    const tokens = (await exchanged.json()) as { access_token: string };
    assert.equal((await h.fetchAdmin("/v1/admin/me", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 200);

    // Any other page on the console's host is no place to come back to.
    const elsewhere = new URLSearchParams({ state: "s".repeat(43), redirect_uri: `${h.adminOrigin}/users`, code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    assert.equal((await h.fetch(`/v1/auth/google/start?${elsewhere}`, { redirect: "manual" })).status, 400);
  } finally {
    await h.close();
  }
});
