import assert from "node:assert/strict";
import test from "node:test";
import { build } from "esbuild";
import { Miniflare, convertV4MiniflareOptions, Log, LogLevel } from "miniflare";
import { randomSecret } from "../src/auth.ts";

// Uses only isolated synthetic Miniflare storage. No live worker/config or operator data.
test("Apple canonical mapping is stable, colon-free, metadata-preserving and never autojoins by nonunique email", async () => {
  const script = (await build({ entryPoints: ["test/apple-account-worker.ts"], bundle: true, write: false, format: "esm", platform: "node", external: ["cloudflare:workers", "cloudflare:sockets", "node:*"], conditions: ["workerd", "worker", "browser"], banner: { js: 'import { createRequire } from "node:module"; const require = createRequire("file:///worker.js");' } })).outputFiles[0].text;
  const mf = new Miniflare(convertV4MiniflareOptions({ log: new Log(LogLevel.ERROR), workers: [{ name: "apple-account-test", modules: true, script, compatibilityDate: "2026-09-08", compatibilityFlags: ["nodejs_compat"],
    bindings: { PUBLIC_ORIGIN: "https://apple-account.test", ADMIN_ORIGIN: "https://admin.test", AUTH_SIGNING_KEY: randomSecret(), GOOGLE_CLIENT_ID: "synthetic-google", GOOGLE_CLIENT_SECRET: randomSecret(), APPLE_CLIENT_ID: "synthetic-native", APPLE_CLIENT_SECRET: "synthetic-client-secret", APPLE_GRANT_KEY: randomSecret(), GRANT_SIGNING_JWK: "", ADMIN_EMAIL: "same@example.test" },
    durableObjects: Object.fromEntries(["Account", "LoginAttempt", "LoginLimiter", "Directory", "TelemetryLimiter"].map((className, i) => [["ACCOUNTS", "LOGINS", "LOGIN_LIMITS", "DIRECTORY", "TELEMETRY_LIMITS"][i], { className, useSQLite: true }])),
  }] }));
  const post = async (path: string, body: unknown) => (await mf.dispatchFetch(`https://apple-account.test${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })).json() as Promise<any>;
  try {
    const google = await post("/test/login", { sub: "unchanged-google-sub", email: "same@example.test", name: "Google name" });
    assert.equal(google.subject, "unchanged-google-sub");
    const workspace = await post("/test/workspace", { sub: google.subject });
    // Pre-added email existed before Apple was authorized: must not become Apple membership.
    await post("/test/add", { sub: google.subject, workspace: workspace.id, email: "first@example.test" });
    const apple = await post("/test/login", { apple: true, sub: "001.apple", email: "same@example.test", name: "Apple name" });
    const preadded = await post("/test/login", { apple: true, sub: "002.apple", email: "first@example.test" });
    assert.match(apple.subject, /^a_[A-Za-z0-9_-]{43}$/);
    assert.notEqual(apple.subject, google.subject);
    assert.deepEqual((await post("/test/me", { sub: apple.subject })).workspaces, []);
    assert.deepEqual((await post("/test/me", { sub: preadded.subject })).workspaces, []);
    const returning = await post("/test/login", { apple: true, sub: "001.apple" });
    assert.equal(returning.subject, apple.subject);
    assert.equal(returning.email, "same@example.test");
    assert.equal(returning.name, "Apple name");
    assert.equal((await post("/test/me", { sub: google.subject })).user.name, "Google name");
    const googleAdded = await post("/test/login", { sub: "old-google-first", email: "first@example.test", name: "Google first" });
    assert.equal((await post("/test/me", { sub: googleAdded.subject })).workspaces.length, 1, "Google pre-added path unchanged");
    const relay = await post("/test/login", { apple: true, sub: "003.apple", email: "relay@privaterelay.appleid.com" });
    assert.deepEqual((await post("/test/me", { sub: relay.subject })).workspaces, []);
    const attempt = await post("/v1/auth/apple/challenge", {});
    assert.equal(attempt.nonce.length, 43);
    assert.notEqual(attempt.nonce, attempt.state);
    // Invalid native token consumes the attempt before provider I/O; subsequent completion cannot replay it.
    const complete = (state: string) => post("/v1/auth/apple/token", { attempt: attempt.attempt, state, identityToken: "synthetic-invalid-token", authorizationCode: "synthetic-code" });
    assert.equal((await complete("x".repeat(43))).error, "invalid_login_state");
    assert.equal((await complete(attempt.state)).error, "apple_login_failed");
    assert.equal((await complete(attempt.state)).error, "invalid_login_state");
    const appleRequest = (path: string, body: unknown) => mf.dispatchFetch(`https://apple-account.test${path}`, { method: "POST", headers: { authorization: `Bearer ${apple.access_token}`, "content-type": "application/json" }, body: JSON.stringify(body) });
    const response = await appleRequest("/v1/workspaces", { name: "Apple free workspace" });
    assert.equal(response.status, 200, "Apple keeps the free workspace available to every account");
    const appleWorkspace = await response.json() as any;
    const extra = await appleRequest("/v1/workspaces", { name: "Should not inherit admin" });
    assert.equal(extra.status, 403, "same-email Apple does not inherit Google administrator capability");
    assert.equal((await extra.json() as any).error, "invite_code_required");
    assert.equal((await appleRequest(`/v1/workspaces/${appleWorkspace.id}/members`, { role: "member", emails: ["first@example.test"] })).status, 429, "Apple workspace keeps the free-plan member cap");
    const adminHeaders = { authorization: `Bearer ${google.access_token}` };
    const plans = await (await mf.dispatchFetch("https://admin.test/v1/admin/workspaces", { headers: adminHeaders })).json() as any;
    assert.deepEqual(plans.workspaces.filter((w: any) => w.id === appleWorkspace.id).map((w: any) => [w.plan, w.seats]), [["free", 1]]);
    const users = await (await mf.dispatchFetch("https://admin.test/v1/admin/users", { headers: adminHeaders })).json() as any;
    assert.deepEqual(users.users.filter((u: any) => u.sub === apple.subject).map((u: any) => [u.plan, u.admission, u.may_create]), [["free", "free", false]]);
    assert.equal((await mf.dispatchFetch("https://admin.test/v1/admin/users", { headers: { authorization: `Bearer ${apple.access_token}` } })).status, 404, "Apple cannot access the Google administrator console");
  } finally { await mf.dispose(); }
});
