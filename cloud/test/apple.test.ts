import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { generateKeyPair } from "jose";
import { harness } from "./harness.ts";
import type { Tokens } from "../src/auth.ts";

const APPLE_SUB = "001234.0123456789abcdef0123456789abcdef.1234";
const hex = (value: string) => createHash("sha256").update(value).digest("hex");

test("signing in with Apple in the browser: Apple's cross-site post, the callback's GET with the cookie, a session", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    assert.deepEqual(await (await h.fetch("/healthz")).json(), { service: "stillfail-cloud", google_login: true, apple_login: true });
    const first = await h.appleLogin(APPLE_SUB, { email: "person@example.test", name: { firstName: "Ada", lastName: "Lovelace" } });
    assert.equal(first.authorize.origin + first.authorize.pathname, "https://appleid.apple.com/auth/authorize");
    assert.equal(first.authorize.searchParams.get("client_id"), "test-apple-services");
    assert.equal(first.authorize.searchParams.get("redirect_uri"), `${h.origin}/v1/auth/apple/callback`);
    assert.equal(first.authorize.searchParams.get("response_mode"), "form_post");
    assert.equal(first.authorize.searchParams.get("scope"), "name email");
    assert.equal(first.posted.status, 303, "Apple's post goes on to a GET");
    assert.equal(first.again!.searchParams.has("code"), false, "the code stays out of the URL");
    assert.equal(first.redirect!.origin + first.redirect!.pathname, first.callback);
    assert.equal(first.redirect!.searchParams.get("state"), first.state);
    const exchange = await h.fetch("/v1/auth/token", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: first.redirect!.searchParams.get("code"), code_verifier: first.verifier, redirect_uri: first.callback }),
    });
    assert.equal(exchange.status, 200);
    const tokens = (await exchange.json()) as Tokens;
    assert.equal(tokens.subject, "apple_001234_0123456789abcdef0123456789abcdef_1234");
    assert.equal(tokens.email, "person@example.test");
    assert.equal(tokens.name, "Ada Lovelace");
    assert.equal((await h.fetch("/v1/auth/session", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 200);

    // Apple gives the name once: the next sign-in keeps it.
    const again = await h.appleLogin(APPLE_SUB, { email: "person@example.test" });
    const second = (await (await h.fetch("/v1/auth/token", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: again.redirect!.searchParams.get("code"), code_verifier: again.verifier, redirect_uri: again.callback }),
    })).json()) as Tokens;
    assert.equal(second.subject, tokens.subject);
    assert.equal(second.name, "Ada Lovelace");
    const me = (await (await h.as(second)("GET", "/v1/me")).json()) as { user: { name: string } };
    assert.equal(me.user.name, "Ada Lovelace", "the Directory keeps it too");

    // The same email with Google is another account.
    const google = await h.login("person");
    assert.equal(google.email, "person@example.test");
    assert.notEqual(google.subject, tokens.subject);
  } finally {
    await h.close();
  }
});

test("Apple's browser sign-in needs the login's cookie, is posted once, and fails on a wrong or cancelled answer", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const stolen = await h.appleLogin(APPLE_SUB, { cookie: false });
    assert.equal(stolen.back!.status, 400, "the GET needs the browser that started it");

    const flow = await h.appleLogin(APPLE_SUB);
    const replayed = await h.fetch("/v1/auth/apple/callback", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ state: flow.authorize.searchParams.get("state")!, code: "another" }),
      redirect: "manual",
    });
    assert.equal(replayed.status, 400, "a second post is not taken");

    const cancelled = await h.appleLogin(APPLE_SUB, { invalid: "cancel" });
    assert.equal(cancelled.redirect!.searchParams.get("error"), "login_cancelled");
    for (const invalid of ["nonce", "aud", "email", "noEmail"]) {
      const wrong = await h.appleLogin(APPLE_SUB, { invalid });
      assert.equal(wrong.redirect!.searchParams.get("error"), "apple_login_failed", invalid);
      assert.equal(wrong.redirect!.searchParams.has("code"), false, invalid);
    }

    // From the console's host it starts on PUBLIC_ORIGIN, whose callback Apple knows.
    const moved = await h.fetchAdmin("/v1/auth/apple/start?state=x", { redirect: "manual" });
    assert.equal(moved.headers.get("location"), `${h.origin}/v1/auth/apple/start?state=x`);
  } finally {
    await h.close();
  }
});

test("the iOS app signs in with Apple natively: a nonce, then the identity token for it, once", { timeout: 30000 }, async () => {
  const h = await harness();
  try {
    const post = (path: string, body: unknown) => h.fetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const begin = async () => (await (await post("/v1/auth/apple/native", { name: "iPhone" })).json()) as { id: string; nonce: string };
    const attempt = await begin();
    const token = await h.appleToken({ sub: APPLE_SUB, email: "person@example.test", nonce: hex(attempt.nonce) }, "fail.still.ios");
    const signed = await post("/v1/auth/apple/native/token", { id: attempt.id, identity_token: token, user: { name: { firstName: "Ada", lastName: "Lovelace" } } });
    assert.equal(signed.status, 200);
    const tokens = (await signed.json()) as Tokens;
    assert.equal(tokens.subject, "apple_001234_0123456789abcdef0123456789abcdef_1234", "the same account as the browser's");
    assert.equal(tokens.name, "Ada Lovelace");
    assert.equal((await h.fetch("/v1/auth/sessions", { headers: { authorization: `Bearer ${tokens.access_token}` } })).status, 200);
    assert.equal((await post("/v1/auth/apple/native/token", { id: attempt.id, identity_token: token })).status, 401, "an attempt is used once");

    // The console stays Google's: an Apple account with ADMIN_EMAIL is not the admin.
    const admin = await begin();
    const adminToken = await h.appleToken({ sub: "000999.abc.0001", email: "alice@example.test", nonce: hex(admin.nonce) }, "fail.still.ios");
    const apple = (await (await post("/v1/auth/apple/native/token", { id: admin.id, identity_token: adminToken })).json()) as Tokens;
    assert.equal(apple.email, "alice@example.test");
    assert.equal((await h.as(apple, "admin")("GET", "/v1/admin/me")).status, 404);
    assert.equal((await h.as(await h.login("alice"), "admin")("GET", "/v1/admin/me")).status, 200, "Google's alice still is");

    const other = await generateKeyPair("RS256");
    for (const [why, claims, aud, key] of [
      ["raw nonce", (n: string) => ({ sub: APPLE_SUB, email: "p@example.test", nonce: n }), "fail.still.ios", undefined],
      ["another app", (n: string) => ({ sub: APPLE_SUB, email: "p@example.test", nonce: hex(n) }), "com.example.other", undefined],
      ["not Apple's key", (n: string) => ({ sub: APPLE_SUB, email: "p@example.test", nonce: hex(n) }), "fail.still.ios", other.privateKey],
      ["no email", (n: string) => ({ sub: APPLE_SUB, nonce: hex(n) }), "fail.still.ios.beta", undefined],
    ] as const) {
      const next = await begin();
      const response = await post("/v1/auth/apple/native/token", { id: next.id, identity_token: await h.appleToken(claims(next.nonce), aud, key) });
      assert.equal(response.status, 401, why);
    }
  } finally {
    await h.close();
  }
});

test("without Apple's configuration its sign-in says so", { timeout: 20000 }, async () => {
  const h = await harness({ noApple: true });
  try {
    assert.equal(((await (await h.fetch("/healthz")).json()) as { apple_login: boolean }).apple_login, false);
    assert.equal((await h.fetch("/v1/auth/apple/start?state=x")).status, 503);
    assert.equal((await h.fetch("/v1/auth/apple/native", { method: "POST", headers: { "content-type": "application/json" }, body: '{"name":"iPhone"}' })).status, 503);
    assert.equal((await h.login()).email, "test@example.test", "Google's is unaffected");
  } finally {
    await h.close();
  }
});
