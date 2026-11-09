import assert from "node:assert/strict";
import test from "node:test";
import { decodeJwt, SignJWT } from "jose";
import { harness } from "./harness.ts";
import { previewFiles } from "../src/preview.ts";

// still.fail was called ember. Its hosts' old names still answer (stations enrolled then
// may have one in their settings); the old request headers, subprotocols and signed messages no longer do.

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}

const json = { "content-type": "application/json" };

test("each host's old name serves the same: static sites, the API, the relay, the installer; the web app's pages move", async () => {
  const h = await harness();
  try {
    const text = async (response: { status: number; text(): Promise<string> }) => [response.status, await response.text()];
    // The web app's pages on its old host go to the same path and query on the new one; its notifications' worker stays.
    for (const path of ["/", "/w/some-workspace/chats?service=job-1", "/assets/app.js", "/invite"]) {
      const page = await h.fetchOld("main", path, { redirect: "manual" });
      assert.deepEqual([page.status, page.headers.get("location")], [302, `${h.origin}${path}`], path);
    }
    assert.deepEqual(await text(await h.fetchOld("main", "/sw.js")), [200, "// the notifications' worker"]);
    assert.deepEqual(await text(await h.fetchOld("admin", "/codes")), [200, "<title>still.fail 管理后台</title>"]);
    assert.deepEqual(await text(await h.fetchOld("preview", "/_stillfail/frame")), [200, "<title>still.fail preview</title>"]);
    assert.equal(((await (await h.fetchOld("main", "/healthz")).json()) as { service: string }).service, "stillfail-cloud");
    assert.equal(((await (await h.fetchOld("main", "/ping")).json()) as { service: string }).service, "stillfail-relay");
    assert.match((await h.fetchOld("main", "/install.sh")).headers.get("content-type") ?? "", /shellscript/);

    // A signed-in account's calls, on the old host and the old console host.
    const tokens = await h.login("alice");
    const me = await h.fetchOld("main", "/v1/me", { headers: { authorization: `Bearer ${tokens.access_token}` } });
    assert.equal(me.status, 200);
    assert.equal(((await me.json()) as { relay_url: string }).relay_url, h.origin, "what the cloud hands out is on the new host");
    assert.equal((await h.fetchOld("admin", "/v1/admin/me", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 200);
    assert.equal((await h.fetchOld("admin", "/v1/workspaces", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 404, "the old console host is a console host");
    // Links made on either host are on the new one.
    const alice = h.as(tokens);
    const w = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as { id: string }).id;
    const invite = await (await h.fetchOld("main", `/v1/workspaces/${w}/invitations`, { method: "POST", headers: { ...json, authorization: `Bearer ${tokens.access_token}` }, body: JSON.stringify({ role: "member", email: "bob@example.test" }) })).json() as { url: string };
    assert.ok(invite.url?.startsWith(`${h.origin}/invite#`), JSON.stringify(invite));
    const enrollment = await (await alice("POST", `/v1/workspaces/${w}/enrollments`, { name: "willow" })).json() as { install: string; command: string };
    assert.ok(enrollment.install.startsWith(`curl -fsSL ${h.origin}/install.sh | sh -s -- `));

    // Both apps' App Links, on both hosts.
    for (const fetch of [h.fetch, (path: string) => h.fetchOld("main", path)]) {
      const links = (await (await fetch("/.well-known/assetlinks.json")).json()) as { target: { package_name: string } }[];
      assert.deepEqual(links.map((l) => l.target.package_name), ["fail.still.android"]);
    }
    // Still no wildcard.
    assert.equal((await h.fetchWorker("api", "https://other.relay.example/v1/me", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 421);
    assert.equal((await h.fetchWorker("relay", "https://other.relay.example/ping")).status, 421);
  } finally {
    await h.close();
  }
});

test("signing in on an old host goes on to the new one, which Google calls back, and returns where it started", async () => {
  const h = await harness();
  try {
    const callback = `${h.oldOrigin}/auth/callback`;
    const start = new URLSearchParams({ state: "s".repeat(43), redirect_uri: callback, code_challenge: "c".repeat(43), code_challenge_method: "S256" });
    for (const on of ["main", "admin"] as const) {
      const moved = await h.fetchOld(on, `/v1/auth/google/start?${start}`, { redirect: "manual" });
      assert.equal(moved.status, 302, on);
      assert.equal(moved.headers.get("location"), `${h.origin}/v1/auth/google/start?${start}`, on);
      assert.equal(moved.headers.get("set-cookie"), null, on);
    }
    // A device's sign-in page, as a device from before the move linked to it.
    const device = "d".repeat(43);
    const page = await h.fetchOld("main", `/v1/auth/device/${device}`, { redirect: "manual" });
    assert.deepEqual([page.status, page.headers.get("location")], [302, `${h.origin}/v1/auth/device/${device}`]);

    // The whole way, for the web app on the old host and for the old console.
    for (const back of [callback, `${h.oldAdminOrigin}/auth/callback`]) {
      const flow = await h.begin("alice", undefined, back);
      assert.equal(flow.google.searchParams.get("redirect_uri"), `${h.origin}/v1/auth/google/callback`);
      const { redirect, code } = await h.complete(flow);
      assert.equal(`${redirect.origin}${redirect.pathname}`, back);
      const exchanged = await h.fetchOld(back.startsWith(h.oldAdminOrigin) ? "admin" : "main", "/v1/auth/token", { method: "POST", headers: json, body: JSON.stringify({ code, code_verifier: flow.verifier, redirect_uri: back }) });
      assert.equal(exchanged.status, 200, back);
    }
  } finally {
    await h.close();
  }
});

test("tokens are stillfail's: one issued under the old name is refused", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    assert.equal(decodeJwt(tokens.access_token).iss, "stillfail-cloud");
    assert.equal((await h.fetch("/v1/me", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 200);
    const now = h.now();
    const old = await new SignJWT({ sub: tokens.subject, sid: tokens.session_id, email: tokens.email, type: "access" })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" }).setIssuer("ember-cloud").setAudience(h.oldOrigin).setIssuedAt(now - 1).setExpirationTime(now + 240)
      .sign(new TextEncoder().encode(h.signingKey));
    assert.equal((await h.fetch("/v1/me", { headers: { authorization: `Bearer ${old}` } })).status, 401);
  } finally {
    await h.close();
  }
});

/** Enrolls a station signing under `prefix` over `origin`. */
async function enroll(h: Harness, fetch: Harness["fetch"], origin: string, prefix: "ember" | "stillfail") {
  const alice = h.as(await h.login("alice"));
  const w = ((await (await alice("POST", "/v1/workspaces", { name: `Home ${prefix} ${origin}` })).json()) as { id: string }).id;
  const enrollment = (await (await alice("POST", `/v1/workspaces/${w}/enrollments`, { name: "willow" })).json()) as { token: string };
  const station = await key();
  const response = await fetch("/v1/stations/enroll", {
    method: "POST",
    headers: json,
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`${prefix}-station-enroll-v1:${origin}:${enrollment.token}:${station.id}`) }),
  });
  return { alice, w, station, status: response.status };
}

test("a station signs under stillfail, over either host's origin; the old name's signatures and headers are refused", async () => {
  const h = await harness();
  try {
    const old = (path: string, init?: RequestInit) => h.fetchOld("main", path, init);
    for (const [fetch, origin, prefix, status] of [[h.fetch, h.origin, "stillfail", 200], [old, h.oldOrigin, "stillfail", 200], [h.fetch, h.origin, "ember", 401]] as const) {
      assert.equal((await enroll(h, fetch, origin, prefix)).status, status, `${prefix} ${origin}`);
    }
    const { station } = await enroll(h, h.fetch, h.origin, "stillfail");
    const ts = h.now();
    const before = await old("/v1/stations/connect", {
      headers: { upgrade: "websocket", "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await station.sign(`ember-station-connect-v1:${h.oldOrigin}:${station.id}:${ts}`) },
    });
    assert.equal(before.status, 400);
    const now = await old("/v1/stations/connect", {
      headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.oldOrigin}:${station.id}:${ts}`) },
    });
    assert.equal(now.status, 101);
    now.webSocket!.accept();
    now.webSocket!.close();
    assert.equal((await h.fetch("/.well-known/stillfail-grant-keys")).status, 200);
    assert.notEqual((await h.fetch("/.well-known/ember-grant-keys")).status, 200);
  } finally {
    await h.close();
  }
});

test("a device's events socket takes only the stillfail subprotocols", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const events = (protocols: string) => h.fetchOld("main", "/v1/events", { headers: { upgrade: "websocket", "sec-websocket-protocol": protocols } });
    const response = await events(`stillfail-events, stillfail-token.${tokens.access_token}`);
    assert.equal(response.status, 101);
    assert.equal(response.headers.get("sec-websocket-protocol"), "stillfail-events");
    response.webSocket!.accept();
    response.webSocket!.close();
    assert.equal((await events(`ember-events, ember-token.${tokens.access_token}`)).status, 401);
  } finally {
    await h.close();
  }
});

test("the preview host's files are under /_stillfail/ alone, on either host", async () => {
  const files = previewFiles("// annotate");
  assert.equal(files["_stillfail/annotate.js"], "// annotate");
  assert.match(files["_stillfail/frame.html"]!, /<script src="annotate\.js"><\/script>/);
  assert.match(files["_stillfail/frame.html"]!, /register\("sw\.js", \{ scope: "\/" \}\)/);
  assert.match(files._headers!, /\/_stillfail\/sw\.js\n  Service-Worker-Allowed: \/\n/);
  assert.match(files["_stillfail/sw.js"]!, /const FRAMES = \["\/_stillfail\/frame"\];/);
  assert.equal(files["_ember/frame.html"], undefined);
  // The service worker leaves the host's own files alone.
  const own = new Function(`${/const OWN = .*;/.exec(files["_stillfail/sw.js"]!)![0]} return OWN;`)() as RegExp;
  assert.deepEqual(["/_stillfail/frame", "/_ember/sw.js", "/app/_stillfail/x", "/"].map((p) => own.test(p)), [true, false, false, false]);

  const h = await harness();
  try {
    for (const fetch of [h.fetchPreview, (path: string) => h.fetchOld("preview", path)]) {
      assert.equal((await fetch("/_stillfail/frame")).status, 200);
      assert.equal((await fetch("/_stillfail/sw.js")).headers.get("service-worker-allowed"), "/");
    }
  } finally {
    await h.close();
  }
});
