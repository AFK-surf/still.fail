import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

// ember cloud's Workers on its hosts: the static sites (the web app, the admin's console, the preview host) on each
// host's Custom Domain, and the API's and the relay's paths routed to their Workers ahead of them.

test("each host serves its own static site, the API and the relay on their paths ahead of it", async () => {
  const h = await harness();
  try {
    const text = async (response: { status: number; text(): Promise<string> }) => [response.status, await response.text()];
    assert.deepEqual(await text(await h.fetch("/")), [200, "<title>ember</title>"]);
    assert.deepEqual(await text(await h.fetch("/w/some-workspace/chats")), [200, "<title>ember</title>"]);
    assert.deepEqual(await text(await h.fetch("/assets/app.js")), [200, "// the web app"]);
    assert.deepEqual(await text(await h.fetchAdmin("/")), [200, "<title>ember 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/codes")), [200, "<title>ember 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/auth/callback?code=x&state=y")), [200, "<title>ember 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchAdmin("/assets/console.js")), [200, "// the console"]);
    // Each site's files are its own.
    assert.deepEqual(await text(await h.fetchAdmin("/assets/app.js")), [200, "<title>ember 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetch("/assets/console.js")), [200, "<title>ember</title>"]);
    assert.deepEqual(await text(await h.fetchPreview("/_ember/frame")), [200, "<title>ember preview</title>"]);
    assert.equal((await h.fetchPreview("/_ember/sw.js")).headers.get("service-worker-allowed"), "/");
    assert.equal((await h.fetchPreview("/anything")).status, 404);
    // The API's and the relay's paths are theirs on the main host.
    assert.equal(((await (await h.fetch("/healthz")).json()) as { service: string }).service, "ember-cloud");
    assert.equal(((await (await h.fetch("/ping")).json()) as { service: string }).service, "ember-relay");
    assert.equal((await h.fetch("/generate_204", { headers: { "x-iroh-challenge": "abc" } })).headers.get("x-iroh-response"), "response abc");
    assert.equal((await h.fetch("/v1/nothing-here")).status, 404);
    assert.match((await h.fetch("/install.sh")).headers.get("content-type") ?? "", /shellscript/);
    // The static sites take no writes.
    assert.equal((await h.fetch("/", { method: "POST" })).status, 405);
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
    const api = await h.mf.getWorker("api");
    for (const origin of ["https://other.relay.example", "https://admin.relay.example.evil"]) {
      const response = await api.fetch(`${origin}/v1/me`, { headers: { authorization: `Bearer ${tokens.access_token}` } });
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
