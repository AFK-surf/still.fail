import assert from "node:assert/strict";
import test from "node:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { appleConfigured, appleIdentity, encryptAppleGrant, revokeAppleGrant, type AppleEnv } from "../src/apple.ts";
import { authConfigured, nowSeconds, randomSecret, signToken, verifyToken } from "../src/auth.ts";
import { ulid } from "ulid";

// Synthetic provider responses only. No real Apple credentials, network or production data.
test("Apple verifies issuer/audience/expiry/nonce, binds exchanged code identity, encrypts and really revokes grants", async () => {
  const original = globalThis.fetch;
  const pair = await generateKeyPair("RS256");
  const jwk = { ...await exportJWK(pair.publicKey), kid: "apple-test", alg: "RS256", use: "sig" };
  const env = { PUBLIC_ORIGIN: "https://example.test", AUTH_SIGNING_KEY: randomSecret(), APPLE_CLIENT_ID: "native.test", APPLE_CLIENT_SECRET: "synthetic-client-secret", APPLE_GRANT_KEY: randomSecret() } as AppleEnv;
  const nonce = randomSecret();
  const signed = (claims: Record<string, unknown> = {}, issuer = "https://appleid.apple.com", audience = "native.test", expiry = nowSeconds() + 60) =>
    new SignJWT({ nonce, sub: "001.apple-sub", email: "private@privaterelay.appleid.com", email_verified: "true", ...claims })
      .setProtectedHeader({ alg: "RS256", kid: jwk.kid }).setIssuer(issuer).setAudience(audience).setIssuedAt().setExpirationTime(expiry).sign(pair.privateKey);
  let exchanged = await signed();
  let revoked = false;
  let revokeStatus = 200;
  let exchanges = 0;
  const used = new Set<string>();
  globalThis.fetch = async (input, init) => {
    const url = String(input);
    if (url.endsWith("/auth/keys")) return Response.json({ keys: [jwk] });
    const form = new URLSearchParams(init?.body as URLSearchParams);
    if (url.endsWith("/auth/token")) {
      exchanges++;
      const code = form.get("code")!;
      if (used.has(code)) return Response.json({ error: "invalid_grant" }, { status: 400 });
      used.add(code);
      return Response.json({ id_token: exchanged, refresh_token: "synthetic-apple-grant" });
    }
    if (url.endsWith("/auth/revoke")) {
      assert.equal(form.get("token"), "synthetic-apple-grant");
      assert.equal(form.get("token_type_hint"), "refresh_token");
      revoked = true;
      return new Response(null, { status: revokeStatus });
    }
    throw new Error("unexpected outbound endpoint");
  };
  try {
    for (const bad of [await signed({}, "https://evil.test"), await signed({}, undefined, "other.app"), await signed({ nonce: "wrong" }), await signed({}, undefined, undefined, nowSeconds() - 1)]) {
      await assert.rejects(appleIdentity(env, bad, "not-exchanged", nonce));
    }
    assert.equal(exchanges, 0, "bad native tokens cannot exchange a code");
    const profile = await appleIdentity(env, await signed(), "once", nonce, " 首次名称 ");
    assert.equal(profile.name, "首次名称");
    assert.equal(profile.email, "private@privaterelay.appleid.com");
    assert.notEqual(profile.grant, "synthetic-apple-grant");
    assert.equal(profile.grant.includes("synthetic-apple-grant"), false);
    await assert.rejects(appleIdentity(env, await signed(), "once", nonce), /apple_exchange_failed/);
    exchanged = await signed({ sub: "another-sub" });
    await assert.rejects(appleIdentity(env, await signed(), "different", nonce), /apple_identity_mismatch/);
    // Returning provider tokens may omit first-consent metadata, without inventing Google/relay metadata.
    exchanged = await signed({ email: undefined, email_verified: undefined });
    const returning = await appleIdentity(env, await signed({ email: undefined, email_verified: undefined }), "returning", nonce);
    assert.equal(returning.email, "");
    assert.equal(returning.name, "");
    revokeStatus = 503;
    await assert.rejects(revokeAppleGrant(env, profile.grant), /apple_revocation_failed/);
    revokeStatus = 200;
    await revokeAppleGrant(env, profile.grant);
    assert.equal(revoked, true);
    await assert.rejects(revokeAppleGrant({ ...env, APPLE_GRANT_KEY: randomSecret() }, profile.grant));
    assert.notEqual(await encryptAppleGrant(env, "synthetic-apple-grant"), profile.grant, "randomized encryption");
  } finally { globalThis.fetch = original; }
});

test("Apple readiness is provider-specific and Google old-origin subject/session tokens remain compatible", async () => {
  const env = { PUBLIC_ORIGIN: "https://new.test", PUBLIC_ORIGIN_ALIASES: "https://old.test", GOOGLE_CLIENT_ID: "test-google", GOOGLE_CLIENT_SECRET: "synthetic", AUTH_SIGNING_KEY: randomSecret() } as AppleEnv;
  assert.equal(authConfigured(env), true);
  assert.equal(appleConfigured(env), false);
  const token = await signToken({ ...env, PUBLIC_ORIGIN: "https://old.test" }, "access", { sub: "original-google-sub", email: "same@example.test", sid: ulid() }, nowSeconds() + 300);
  assert.equal((await verifyToken(env, token, "access"))?.sub, "original-google-sub");
  assert.equal((await verifyToken({ ...env, APPLE_CLIENT_ID: "app" }, token, "access"))?.sub, "original-google-sub");
});
