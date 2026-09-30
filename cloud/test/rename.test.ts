import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { SignJWT } from "jose";
import { harness } from "./harness.ts";
import { previewFiles } from "../src/preview.ts";

// still.fail was called ember (docs/rename-still-fail.md). What was installed and opened before the rename keeps
// working: the hosts' old names, the old request headers, subprotocols and signed messages, the old paths.

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
    assert.deepEqual(await text(await h.fetchOld("preview", "/_ember/frame")), [200, "<title>still.fail preview (old path)</title>"]);
    assert.equal(((await (await h.fetchOld("main", "/healthz")).json()) as { service: string }).service, "ember-cloud");
    assert.equal(((await (await h.fetchOld("main", "/ping")).json()) as { service: string }).service, "ember-relay");
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
    const enrollment = await (await alice("POST", `/v1/workspaces/${w}/enrollments`, { name: "studio" })).json() as { install: string; command: string };
    assert.ok(enrollment.install.startsWith(`curl -fsSL ${h.origin}/install.sh | sh -s -- `));

    // Both apps' App Links, on both hosts.
    for (const fetch of [h.fetch, (path: string) => h.fetchOld("main", path)]) {
      const links = (await (await fetch("/.well-known/assetlinks.json")).json()) as { target: { package_name: string } }[];
      assert.deepEqual(links.map((l) => l.target.package_name), ["fail.still.android", "dev.ember.android"]);
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
    // The Android app from before the rename.
    const flow = await h.begin("google-android-user", undefined, "ember://auth/callback");
    const { code } = await h.complete(flow);
    assert.equal((await h.exchange(flow, code)).status, 200);
  } finally {
    await h.close();
  }
});

test("tokens issued for the old origin stay good", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const now = Math.floor(Date.now() / 1000);
    const old = await new SignJWT({ sub: tokens.subject, sid: tokens.session_id, email: tokens.email, type: "access" })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" }).setIssuer("ember-cloud").setAudience(h.oldOrigin).setIssuedAt(now - 1).setExpirationTime(now + 240)
      .sign(new TextEncoder().encode(h.signingKey));
    for (const fetch of [h.fetch, (path: string, init?: RequestInit) => h.fetchOld("main", path, init)]) {
      assert.equal((await fetch("/v1/me", { headers: { authorization: `Bearer ${old}` } })).status, 200);
    }
    const other = await new SignJWT({ sub: tokens.subject, sid: tokens.session_id, email: tokens.email, type: "access" })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" }).setIssuer("ember-cloud").setAudience("https://elsewhere.example").setIssuedAt(now - 1).setExpirationTime(now + 240)
      .sign(new TextEncoder().encode(h.signingKey));
    assert.equal((await h.fetch("/v1/me", { headers: { authorization: `Bearer ${other}` } })).status, 401);
  } finally {
    await h.close();
  }
});

/** Enrolls a station as one from before the rename would, or as a new one. */
async function enroll(h: Harness, fetch: Harness["fetch"], origin: string, prefix: "ember" | "stillfail") {
  const alice = h.as(await h.login("alice"));
  const w = ((await (await alice("POST", "/v1/workspaces", { name: `Home ${prefix} ${origin}` })).json()) as { id: string }).id;
  const enrollment = (await (await alice("POST", `/v1/workspaces/${w}/enrollments`, { name: "studio" })).json()) as { token: string };
  const station = await key();
  const response = await fetch("/v1/stations/enroll", {
    method: "POST",
    headers: json,
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`${prefix}-station-enroll-v1:${origin}:${enrollment.token}:${station.id}`) }),
  });
  return { alice, w, station, status: response.status };
}

test("stations from before the rename: old host, old headers, old signed messages, old grant keys path", async () => {
  const h = await harness();
  try {
    const old = (path: string, init?: RequestInit) => h.fetchOld("main", path, init);
    // Enrolling: the old name signed over the old origin on the old host, and each mix (a station moved over).
    for (const [fetch, origin, prefix] of [[old, h.oldOrigin, "ember"], [h.fetch, h.origin, "ember"], [h.fetch, h.oldOrigin, "stillfail"], [old, h.origin, "stillfail"]] as const) {
      assert.equal((await enroll(h, fetch, origin, prefix)).status, 200, `${prefix} ${origin}`);
    }
    const { alice, w, station } = await enroll(h, old, h.oldOrigin, "ember");
    const forged = await key();
    assert.equal((await enroll(h, old, "https://elsewhere.example", "ember")).status, 401, "another cloud's");

    // Its presence socket with the x-ember-* headers and message.
    const ts = Math.floor(Date.now() / 1000);
    const connect = async (signer: Awaited<ReturnType<typeof key>>) => old("/v1/stations/connect", {
      headers: { upgrade: "websocket", "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await signer.sign(`ember-station-connect-v1:${h.oldOrigin}:${station.id}:${ts}`), "x-ember-version": "0.1.900" },
    });
    assert.equal((await connect(forged)).status, 401);
    const presence = await connect(station);
    assert.equal(presence.status, 101);
    presence.webSocket!.accept();
    const view = (await (await alice("GET", `/v1/workspaces/${w}`)).json()) as { stations: { id: string; version: string | null }[] };
    assert.equal(view.stations.find((s) => s.id === station.id)?.version, "0.1.900", "x-ember-version is read");
    presence.webSocket!.close();

    // The new headers win over old ones when both are there.
    const both = await h.fetch("/v1/stations/connect", {
      headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-ember-station": forged.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`) },
    });
    assert.equal(both.status, 101);
    both.webSocket!.accept();
    both.webSocket!.close();

    // The grant keys, where old stations fetch them and where new ones do.
    const keys = await Promise.all(["/.well-known/ember-grant-keys", "/.well-known/stillfail-grant-keys"].map(async (path) => (await (await old(path)).json()) as { keys: unknown[] }));
    assert.deepEqual(keys[0], keys[1]);
    assert.equal(keys[0]!.keys.length, 1);
  } finally {
    await h.close();
  }
});

test("a station's traces with the old headers and message", async () => {
  const got: unknown[] = [];
  const h = await harness({ axiom: async (request) => (got.push(await request.text()), new Response("{}")) });
  try {
    const { station } = await enroll(h, h.fetch, h.origin, "stillfail");
    const body = JSON.stringify({ resourceSpans: [{ scopeSpans: [{ spans: [{ name: "x" }] }] }] });
    const digest = createHash("sha256").update(body).digest("hex");
    const ts = Math.floor(Date.now() / 1000);
    const post = async (headers: Record<string, string>) => h.fetchOld("main", "/v1/telemetry/traces", { method: "POST", headers: { ...json, ...headers }, body });
    assert.equal((await post({ "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await station.sign(`ember-station-telemetry-v1:${h.oldOrigin}:${station.id}:${ts}:${digest}`) })).status, 202);
    assert.equal((await post({ "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`stillfail-station-telemetry-v1:${h.origin}:${station.id}:${ts}:${digest}`) })).status, 202);
    assert.equal((await post({ "x-ember-station": station.id, "x-ember-ts": String(ts), "x-ember-signature": await station.sign(`ember-station-telemetry-v1:https://elsewhere.example:${station.id}:${ts}:${digest}`) })).status, 401);
    assert.equal(got.length, 2);
  } finally {
    await h.close();
  }
});

test("a device's events socket: the old subprotocols are answered with the old one, the new with the new", async () => {
  const h = await harness();
  try {
    const tokens = await h.login("alice");
    const events = (protocols: string) => h.fetchOld("main", "/v1/events", { headers: { upgrade: "websocket", "sec-websocket-protocol": protocols } });
    for (const [offered, selected] of [
      [`ember-events, ember-token.${tokens.access_token}`, "ember-events"],
      [`stillfail-events, stillfail-token.${tokens.access_token}`, "stillfail-events"],
      [`stillfail-events, ember-events, stillfail-token.${tokens.access_token}`, "stillfail-events"],
    ]) {
      const response = await events(offered!);
      assert.equal(response.status, 101, offered);
      assert.equal(response.headers.get("sec-websocket-protocol"), selected, offered);
      response.webSocket!.accept();
      response.webSocket!.close();
    }
    assert.equal((await events(`ember-token.${tokens.access_token}`)).status, 401, "must ask for the events protocol");
    assert.equal((await events(`other-events, stillfail-token.${tokens.access_token}`)).status, 401);
  } finally {
    await h.close();
  }
});

test("the preview host's files are under /_stillfail/ and, for clients from before the rename, /_ember/", async () => {
  const files = previewFiles("// annotate");
  for (const prefix of ["_stillfail", "_ember"]) {
    assert.equal(files[`${prefix}/annotate.js`], "// annotate");
    // The frame loads its script and service worker from beside itself: each stays under the prefix it was opened with.
    assert.match(files[`${prefix}/frame.html`]!, /<script src="annotate\.js"><\/script>/);
    assert.match(files[`${prefix}/frame.html`]!, /register\("sw\.js", \{ scope: "\/" \}\)/);
    assert.match(files._headers!, new RegExp(`/${prefix}/sw\\.js\\n  Service-Worker-Allowed: /\\n`));
    assert.match(files[`${prefix}/sw.js`]!, /const FRAMES = \["\/_stillfail\/frame", "\/_ember\/frame"\];/);
  }
  // The service worker leaves the host's own files alone, under either prefix.
  const own = new Function(`${/const OWN = .*;/.exec(files["_stillfail/sw.js"]!)![0]} return OWN;`)() as RegExp;
  assert.deepEqual(["/_stillfail/frame", "/_ember/sw.js", "/app/_ember/x", "/_embers/x", "/"].map((p) => own.test(p)), [true, true, false, false, false]);

  const h = await harness();
  try {
    for (const fetch of [h.fetchPreview, (path: string) => h.fetchOld("preview", path)]) {
      assert.equal((await fetch("/_stillfail/frame")).status, 200);
      assert.equal((await fetch("/_ember/frame")).status, 200);
      assert.equal((await fetch("/_ember/sw.js")).headers.get("service-worker-allowed"), "/");
      assert.equal((await fetch("/_stillfail/sw.js")).headers.get("service-worker-allowed"), "/");
    }
  } finally {
    await h.close();
  }
});
