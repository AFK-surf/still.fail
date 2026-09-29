import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { exportPKCS8, generateKeyPair } from "jose";
import { harness, type OutboundRequest } from "./harness.ts";
import { line, noticeBody } from "../src/noticeText.ts";
import { encrypt, fromB64url, senderKeys, toB64url, vapidAuthorization } from "../src/webpush.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");
const encoder = new TextEncoder();

// ── Web Push encryption (RFC 8291) ────────────────────────────────────────

/** RFC 8291's example (section 5 and appendix A). */
const RFC = {
  plaintext: "When I grow up, I want to be a watermelon",
  asPublic: "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8",
  asPrivate: "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw",
  uaPublic: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
  uaPrivate: "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94",
  auth: "BTBZMqHH6r4Tts7J_aSIgg",
  salt: "DGv6ra1nlYgDCS1FRnbzlw",
  result: "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN",
};

/** A browser's subscription keys: the private key it decrypts with, and what it gives the application. */
async function browser() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"])) as CryptoKeyPair;
  return { privateKey: pair.privateKey, p256dh: toB64url(new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer)), auth: toB64url(crypto.getRandomValues(new Uint8Array(16))) };
}

async function hkdf(salt: Uint8Array, ikm: BufferSource, info: string | Uint8Array, bytes: number) {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info: typeof info === "string" ? encoder.encode(info) : info }, key, bytes * 8));
}

/** What a browser does with a push's body (RFC 8291 and RFC 8188, one record). */
async function decrypt(body: Uint8Array, ua: { privateKey: CryptoKey; p256dh: string; auth: string }): Promise<string> {
  const salt = body.slice(0, 16);
  assert.equal(new DataView(body.buffer, body.byteOffset).getUint32(16), 4096);
  const idLength = body[20]!;
  const asPublic = body.slice(21, 21 + idLength);
  const sealed = body.slice(21 + idLength);
  const asKey = await crypto.subtle.importKey("raw", asPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdh = { name: "ECDH", public: asKey };
  const secret = await crypto.subtle.deriveBits(ecdh, ua.privateKey, 256);
  const info = new Uint8Array([...encoder.encode("WebPush: info\0"), ...fromB64url(ua.p256dh), ...asPublic]);
  const ikm = await hkdf(fromB64url(ua.auth), secret, info, 32);
  const cek = await crypto.subtle.importKey("raw", await hkdf(salt, ikm, "Content-Encoding: aes128gcm\0", 16), "AES-GCM", false, ["decrypt"]);
  const plain = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: await hkdf(salt, ikm, "Content-Encoding: nonce\0", 12) }, cek, sealed));
  let end = plain.length - 1;
  while (end >= 0 && plain[end] === 0) end--;
  assert.equal(plain[end], 2, "the last record's delimiter");
  return new TextDecoder().decode(plain.slice(0, end));
}

test("Web Push encryption gives RFC 8291's example, byte for byte", async () => {
  const keys = await senderKeys(RFC.asPublic, RFC.asPrivate);
  const body = await encrypt(encoder.encode(RFC.plaintext), RFC.uaPublic, RFC.auth, { keys, salt: fromB64url(RFC.salt) });
  assert.equal(toB64url(body), RFC.result);
  // And the RFC's user agent reads it.
  const point = fromB64url(RFC.uaPublic);
  const privateKey = await crypto.subtle.importKey("jwk", { kty: "EC", crv: "P-256", x: toB64url(point.slice(1, 33)), y: toB64url(point.slice(33)), d: RFC.uaPrivate }, { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  assert.equal(await decrypt(body, { privateKey, p256dh: RFC.uaPublic, auth: RFC.auth }), RFC.plaintext);
});

test("a pushed message decrypts with the subscription's keys, and not with another's", async () => {
  const ua = await browser();
  const message = JSON.stringify({ type: "notice", body: "需要处理 · 看一下 🔥" });
  const body = await encrypt(encoder.encode(message), ua.p256dh, ua.auth);
  assert.equal(await decrypt(body, ua), message);
  assert.notEqual(toB64url(await encrypt(encoder.encode(message), ua.p256dh, ua.auth)), toB64url(body), "a fresh key and salt each time");
  const other = await browser();
  await assert.rejects(decrypt(body, { ...other, p256dh: ua.p256dh }));
});

/** A VAPID key pair as the secrets hold it. */
async function vapidKeys() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.privateKey)) as JsonWebKey;
  return { publicKey: toB64url(new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer)), privateKey: jwk.d! };
}

/** Checks a push's `Authorization: vapid t=…, k=…` (RFC 8292) and gives its claims. */
async function vapidClaims(authorization: string, publicKey: string) {
  const match = /^vapid t=([^,]+), k=([A-Za-z0-9_-]+)$/.exec(authorization);
  assert.ok(match, authorization);
  assert.equal(match[2], publicKey);
  const [header, claims, signature] = match[1]!.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(fromB64url(header!))), { typ: "JWT", alg: "ES256" });
  const key = await crypto.subtle.importKey("raw", fromB64url(publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  assert.ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, fromB64url(signature!), encoder.encode(`${header}.${claims}`)), "signed with the VAPID key");
  return JSON.parse(new TextDecoder().decode(fromB64url(claims!))) as { aud: string; exp: number; sub: string };
}

test("the VAPID token is ES256 for the endpoint's origin, for at most 12 hours", async () => {
  const keys = await vapidKeys();
  const now = Math.floor(Date.now() / 1000);
  const claims = await vapidClaims(await vapidAuthorization({ ...keys, subject: "mailto:ops@example.test" }, "https://push.example:8443/send/abc?x=1", now), keys.publicKey);
  assert.equal(claims.aud, "https://push.example:8443");
  assert.equal(claims.sub, "mailto:ops@example.test");
  assert.ok(claims.exp > now && claims.exp <= now + 12 * 3600);
});

test("a notification's text is one line of at most 140 characters, made by its kind", () => {
  assert.equal(noticeBody("done", "修好了\n\n  部署  完成", "Claude"), "Claude: 修好了 部署 完成");
  assert.equal(noticeBody("message", "hi", "Bob"), "Bob: hi");
  assert.equal(noticeBody("block", "要你确认", "Claude"), "需要处理 · 要你确认");
  assert.equal(noticeBody("failed", "token runs out"), "出错了 · token runs out");
  assert.equal(noticeBody("done", "no one said it"), "no one said it");
  const long = line("字".repeat(200));
  assert.equal(Array.from(long).length, 140);
  assert.ok(long.endsWith("…"));
  assert.equal(Array.from(line("🔥".repeat(141))).length, 140, "cut by character, not UTF-16 unit");
  assert.equal(line("x".repeat(140)), "x".repeat(140));
});

// ── still.fail cloud ──────────────────────────────────────────────────────

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Station = Awaited<ReturnType<typeof key>>;

/** Alice's workspace with a station in it, and Bob a member of it. */
async function workspace(h: Harness) {
  const aliceTokens = await h.login("alice");
  const bobTokens = await h.login("bob");
  const alice = h.as(aliceTokens);
  const id = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
  assert.equal((await alice("POST", `/v1/workspaces/${id}/members`, { role: "member", emails: ["bob@example.test"] })).status, 200);
  const enrollment = (await (await alice("POST", `/v1/workspaces/${id}/enrollments`, { name: "studio" })).json()) as any;
  const station = await key();
  const response = await h.fetch("/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`) }),
  });
  assert.equal(response.status, 200);
  return { id, station, aliceTokens, bobTokens };
}

/** Sends notices as the station, signed (with another tag or prefix, or over another body, when a test says). */
async function notify(h: Harness, station: Station, notices: unknown[], sign: { tag?: string; body?: string } = {}) {
  const body = JSON.stringify({ notices });
  const ts = Math.floor(Date.now() / 1000);
  const digest = createHash("sha256").update(sign.body ?? body).digest("hex");
  const headers = { "content-type": "application/json", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": await station.sign(`${sign.tag ?? "stillfail-station-notify-v1"}:${h.origin}:${station.id}:${ts}:${digest}`) };
  return h.fetch("/v1/stations/notify", { method: "POST", headers, body });
}

const notice = (to: string[], extra: Record<string, unknown> = {}) => ({ to, kind: "done", session: "ember:c-1/x y", thread: 7, title: "部署挂了", by: "Claude", text: "修好了", at: 1790000000000, ...extra });

/** Push services as the tests see them: what each endpoint got; an endpoint listed in `gone` answers 410. */
function pushServices() {
  const got: OutboundRequest[] = [];
  const gone = new Set<string>();
  const answer = (request: OutboundRequest) => {
    got.push(request);
    return { status: gone.has(request.url) ? 410 : 201 };
  };
  return { got, gone, answer, to: (endpoint: string) => got.filter((r) => r.url === endpoint) };
}

const register = (h: Harness, tokens: { access_token: string }, method: "POST" | "DELETE", value: unknown) =>
  h.fetch("/v1/push", { method, headers: { authorization: `Bearer ${tokens.access_token}`, "content-type": "application/json" }, body: JSON.stringify(value) });

test("without a VAPID key there is no key to subscribe with, and browsers are not registered", async () => {
  const h = await harness();
  try {
    assert.equal((await h.fetch("/v1/push/key")).status, 404);
    const tokens = await h.login("alice");
    const ua = await browser();
    assert.equal((await register(h, tokens, "POST", { kind: "web", endpoint: "https://push.example/a", keys: { p256dh: ua.p256dh, auth: ua.auth } })).status, 503);
    // FCM tokens are kept all the same (sent once the service account is there).
    assert.equal((await register(h, tokens, "POST", { kind: "fcm", token: "device-token-1" })).status, 204);
  } finally {
    await h.close();
  }
});

test("a browser registers, gets its notices encrypted and signed for, and unregisters", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: services.answer });
  try {
    assert.deepEqual(await (await h.fetch("/v1/push/key")).json(), { vapid: vapid.publicKey });
    const { id, station, aliceTokens } = await workspace(h);
    const ua = await browser();
    const endpoint = "https://push.example/send/alice-1";
    // Not signed in, or not a subscription: refused.
    assert.equal((await h.fetch("/v1/push", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" })).status, 401);
    for (const bad of [{ kind: "web", endpoint: "http://push.example/x", keys: ua }, { kind: "web", endpoint, keys: { p256dh: "abc", auth: ua.auth } }, { kind: "web", endpoint, keys: { p256dh: ua.p256dh } }, { kind: "fcm", token: "" }, { kind: "apns", token: "x" }]) {
      assert.equal((await register(h, aliceTokens, "POST", bad)).status, 400, JSON.stringify(bad));
    }
    assert.equal((await register(h, aliceTokens, "POST", { kind: "web", endpoint, keys: { p256dh: ua.p256dh, auth: ua.auth + "==" } })).status, 204);

    const response = await notify(h, station, [notice(["Alice@Example.test"])]);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { sent: 1 });
    const [push] = services.to(endpoint);
    assert.ok(push);
    assert.equal(push.method, "POST");
    assert.equal(push.headers["content-encoding"], "aes128gcm");
    assert.equal(push.headers.ttl, "86400");
    assert.equal(push.headers.urgency, "high");
    assert.match(push.headers.topic!, /^[A-Za-z0-9_-]{32}$/);
    const claims = await vapidClaims(push.headers.authorization!, vapid.publicKey);
    assert.equal(claims.aud, "https://push.example");
    assert.equal(claims.sub, "mailto:ops@example.test");
    assert.deepEqual(JSON.parse(await decrypt(push.body, ua)), {
      type: "notice", kind: "done", title: "部署挂了", body: "Claude: 修好了",
      tag: `${id}/${station.id}/ember:c-1/x y`, url: `/o/${id}/${station.id}/${encodeURIComponent("ember:c-1/x y")}`,
      workspace: id, station: station.id, session: "ember:c-1/x y", at: "1790000000000",
    });

    // Registered again: still one registration, one push.
    assert.equal((await register(h, aliceTokens, "POST", { kind: "web", endpoint, keys: { p256dh: ua.p256dh, auth: ua.auth } })).status, 204);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 1 });
    assert.equal(services.to(endpoint).length, 2);

    assert.equal((await register(h, aliceTokens, "DELETE", { endpoint })).status, 204);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 0 });
    assert.equal(services.to(endpoint).length, 2);
  } finally {
    await h.close();
  }
});

test("a station's notices reach only members of its workspace, those they name", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: services.answer });
  try {
    const { station, aliceTokens, bobTokens } = await workspace(h);
    // Carol is signed in, but not in Alice's workspace.
    const carolTokens = await h.login("carol");
    const endpoints = { alice: "https://push.example/alice", bob: "https://push.example/bob", carol: "https://push.example/carol" };
    for (const [who, tokens] of [["alice", aliceTokens], ["bob", bobTokens], ["carol", carolTokens]] as const) {
      const ua = await browser();
      assert.equal((await register(h, tokens, "POST", { kind: "web", endpoint: endpoints[who], keys: { p256dh: ua.p256dh, auth: ua.auth } })).status, 204);
    }
    const response = await notify(h, station, [
      notice(["bob@example.test", "carol@example.test", "nobody@example.test"]),
      notice(["alice@example.test", "bob@example.test"], { kind: "block", session: "s2" }),
      { to: ["alice@example.test"], kind: "done" }, // not a notice: skipped
    ]);
    assert.deepEqual(await response.json(), { sent: 3 });
    assert.equal(services.to(endpoints.alice).length, 1);
    assert.equal(services.to(endpoints.bob).length, 2);
    assert.equal(services.to(endpoints.carol).length, 0, "not a member of the station's workspace");
  } finally {
    await h.close();
  }
});

test("a device signed in with several accounts is registered with each, and gets a notice for both once", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: services.answer });
  try {
    const { station, aliceTokens, bobTokens } = await workspace(h);
    const ua = await browser();
    const shared = "https://push.example/shared";
    for (const tokens of [aliceTokens, bobTokens]) assert.equal((await register(h, tokens, "POST", { kind: "web", endpoint: shared, keys: { p256dh: ua.p256dh, auth: ua.auth } })).status, 204);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test", "bob@example.test"])])).json(), { sent: 1 });
    assert.deepEqual(await (await notify(h, station, [notice(["bob@example.test"])])).json(), { sent: 1 }, "bob's registration is still there");
    // Bob takes his off; Alice's stays.
    assert.equal((await register(h, bobTokens, "DELETE", { endpoint: shared })).status, 204);
    assert.deepEqual(await (await notify(h, station, [notice(["bob@example.test"])])).json(), { sent: 0 });
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 1 });
    // Registered with both again: once its push service says it is gone, it is gone for both.
    assert.equal((await register(h, bobTokens, "POST", { kind: "web", endpoint: shared, keys: { p256dh: ua.p256dh, auth: ua.auth } })).status, 204);
    services.gone.add(shared);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 0 });
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"]), notice(["bob@example.test"])])).json(), { sent: 0 });
    assert.equal(services.to(shared).length, 4, "not pushed to again once gone");
  } finally {
    await h.close();
  }
});

test("notices signed wrong, or by a station not enrolled, are refused", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: services.answer });
  try {
    const { station, aliceTokens } = await workspace(h);
    const ua = await browser();
    await register(h, aliceTokens, "POST", { kind: "web", endpoint: "https://push.example/a", keys: { p256dh: ua.p256dh, auth: ua.auth } });
    const to = [notice(["alice@example.test"])];
    assert.equal((await notify(h, station, to, { body: "{}" })).status, 401, "another body");
    assert.equal((await notify(h, station, to, { tag: "stillfail-station-telemetry-v1" })).status, 401, "a trace's signature");
    assert.equal((await notify(h, await key(), to)).status, 401, "not enrolled");
    assert.equal((await h.fetch("/v1/stations/notify", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ notices: to }) })).status, 401, "not signed");
    assert.equal(services.got.length, 0);
    // Stations from before the rename sign with the old prefix.
    assert.deepEqual(await (await notify(h, station, to, { tag: "ember-station-notify-v1" })).json(), { sent: 1 });
    assert.equal((await notify(h, station, [], {})).status, 200);
  } finally {
    await h.close();
  }
});

test("a registration its push service says is gone is dropped; other failures are not", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: (request) => (request.url.endsWith("/broken") ? (services.got.push(request), { status: 500 }) : services.answer(request)) });
  try {
    const { station, aliceTokens } = await workspace(h);
    const live = "https://push.example/live", gone = "https://push.example/gone", broken = "https://push.example/broken";
    for (const endpoint of [live, gone, broken]) {
      const ua = await browser();
      await register(h, aliceTokens, "POST", { kind: "web", endpoint, keys: { p256dh: ua.p256dh, auth: ua.auth } });
    }
    services.gone.add(gone);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 1 });
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test"])])).json(), { sent: 1 });
    assert.equal(services.to(live).length, 2);
    assert.equal(services.to(gone).length, 1, "dropped after its 410");
    assert.equal(services.to(broken).length, 2, "kept after its 500");
  } finally {
    await h.close();
  }
});

test("signing a session out takes its registrations; the account's other sessions keep theirs", async () => {
  const vapid = await vapidKeys();
  const services = pushServices();
  const h = await harness({ vapid, push: services.answer });
  try {
    const { station, bobTokens } = await workspace(h);
    const laptop = await h.login("bob");
    const phone = "https://push.example/bob-phone", desk = "https://push.example/bob-laptop";
    for (const [endpoint, tokens] of [[phone, bobTokens], [desk, laptop]] as const) {
      const ua = await browser();
      await register(h, tokens, "POST", { kind: "web", endpoint, keys: { p256dh: ua.p256dh, auth: ua.auth } });
    }
    const out = await h.fetch("/v1/auth/logout", { method: "POST", headers: { authorization: `Bearer ${bobTokens.refresh_token}`, "content-type": "application/json" }, body: '{"all":false}' });
    assert.equal(out.status, 200);
    assert.deepEqual(await (await notify(h, station, [notice(["bob@example.test"])])).json(), { sent: 1 });
    assert.deepEqual([services.to(phone).length, services.to(desk).length], [0, 1]);
    // All of them.
    await h.fetch("/v1/auth/logout", { method: "POST", headers: { authorization: `Bearer ${laptop.refresh_token}`, "content-type": "application/json" }, body: '{"all":true}' });
    assert.deepEqual(await (await notify(h, station, [notice(["bob@example.test"])])).json(), { sent: 0 });
  } finally {
    await h.close();
  }
});

test("Android devices get a high-priority FCM data message; an unregistered token is dropped", async () => {
  const { privateKey } = await generateKeyPair("RS256", { extractable: true });
  const account = { type: "service_account", project_id: "stillfail-test", client_email: "push@stillfail-test.iam.gserviceaccount.com", private_key: await exportPKCS8(privateKey), token_uri: "https://oauth.example/token" };
  const got: OutboundRequest[] = [];
  const h = await harness({
    fcm: JSON.stringify(account),
    push: (request) => {
      got.push(request);
      if (request.url === account.token_uri) return { status: 200, body: JSON.stringify({ access_token: "fcm-access", expires_in: 3600, token_type: "Bearer" }) };
      const message = JSON.parse(new TextDecoder().decode(request.body)).message;
      if (message.token === "gone-token") return { status: 404, body: JSON.stringify({ error: { code: 404, status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }) };
      return { status: 200, body: JSON.stringify({ name: "projects/stillfail-test/messages/1" }) };
    },
  });
  try {
    const { id, station, aliceTokens, bobTokens } = await workspace(h);
    assert.equal((await register(h, aliceTokens, "POST", { kind: "fcm", token: "alice-token" })).status, 204);
    assert.equal((await register(h, bobTokens, "POST", { kind: "fcm", token: "gone-token" })).status, 204);
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test", "bob@example.test"], { kind: "failed", text: "token runs out" })])).json(), { sent: 1 });

    const token = got.filter((r) => r.url === account.token_uri);
    assert.equal(token.length, 1, "one access token for all the pushes");
    const form = new URLSearchParams(new TextDecoder().decode(token[0]!.body));
    assert.equal(form.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
    const assertion = JSON.parse(Buffer.from(form.get("assertion")!.split(".")[1]!, "base64url").toString());
    assert.equal(assertion.scope, "https://www.googleapis.com/auth/firebase.messaging");
    assert.equal(assertion.iss, account.client_email);

    const sends = got.filter((r) => r.url === "https://fcm.googleapis.com/v1/projects/stillfail-test/messages:send");
    assert.equal(sends.length, 2);
    const toAlice = sends.map((r) => ({ headers: r.headers, message: JSON.parse(new TextDecoder().decode(r.body)).message })).find((r) => r.message.token === "alice-token")!;
    assert.equal(toAlice.headers.authorization, "Bearer fcm-access");
    const tag = `${id}/${station.id}/ember:c-1/x y`;
    assert.deepEqual(toAlice.message.android, { priority: "HIGH" }, "no collapse key: the app replaces a chat's notification by its tag");
    assert.equal(toAlice.message.data.body, "出错了 · token runs out");
    assert.equal(toAlice.message.data.tag, tag);
    assert.ok(Object.values(toAlice.message.data).every((v) => typeof v === "string"), "every value a string");

    // The unregistered token is gone; the access token is kept.
    assert.deepEqual(await (await notify(h, station, [notice(["alice@example.test", "bob@example.test"])])).json(), { sent: 1 });
    assert.equal(got.filter((r) => r.url === account.token_uri).length, 1);
    assert.equal(got.filter((r) => r.url.endsWith("messages:send")).length, 3);
  } finally {
    await h.close();
  }
});
