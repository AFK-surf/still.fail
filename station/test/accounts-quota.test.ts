// Allowances and renewing a Claude login (quota.rs, claude_oauth.rs tests): against local providers, in temp homes.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { existsSync, mkdirSync, readFileSync, realpathSync, rmdirSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { claudeOAuthToken, RefreshLock } from "../src/accounts/oauth.ts";
import { readClaudeCredentials } from "../src/agents/machine-logins.ts";
import { URLS } from "../src/accounts/profiles.ts";
import { at, checkQuota, claudeUsage, claudeWithRefresh, codexQuota, codexUsage, codexWindows, machineUsage, windowLabel } from "../src/accounts/quota.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { machine, provider, script, temp, until } from "./accounts-fakes.ts";

describe("allowances and renewing", { concurrency: true }, () => {
  test("an account its provider refuses is blocked, a sign-in no longer good is not", async () => {
    let p = await provider(() => ({ status: 403, body: { error: { message: "This organization has been disabled." } } }));
    const blocked = await claudeUsage(p.base, "t", "zh");
    assert.equal(blocked.state, "blocked");
    assert.ok(blocked.detail!.includes("This organization has been disabled"));
    await p.close();
    p = await provider(() => ({ status: 401, body: { error: { message: "OAuth token has expired" } } }));
    const expired = await claudeUsage(p.base, "t", "zh");
    assert.deepEqual([expired.state, expired.detail], ["unavailable", "登录已过期或失效"]);
    await p.close();
    p = await provider(() => ({ status: 401, body: { detail: "Your account has been deactivated" } }));
    assert.equal((await claudeUsage(p.base, "t", "zh")).state, "blocked");
    await p.close();
  });

  test("a codex login's allowance is read with its auth.json's tokens", async () => {
    const dir = temp("codex-usage");
    const file = join(dir, "auth.json");
    writeFileSync(file, JSON.stringify({ tokens: { access_token: "at", account_id: "acc" } }));
    const body = {
      plan_type: "pro",
      rate_limit: {
        primary_window: { used_percent: 30, limit_window_seconds: 18_000, reset_at: 1_900_000_000 },
        secondary_window: { used_percent: 80, limit_window_seconds: 604_800, reset_at: 1_900_500_000 },
      },
    };
    const p = await provider(() => ({ status: 200, body }));
    const quota = await codexUsage(file, { ...URLS, chatgpt: p.base });
    assert.equal(quota!.plan, "pro");
    assert.deepEqual(quota!.windows, [
      { label: "5 小时", usedPercent: 30, resetsAt: 1_900_000_000_000, minutes: 300 },
      { label: "每周", usedPercent: 80, resetsAt: 1_900_500_000_000, minutes: 10080 },
    ]);
    assert.equal(p.asked[0]!.headers.authorization, "Bearer at");
    assert.equal(p.asked[0]!.headers["chatgpt-account-id"], "acc");
    assert.equal(p.asked[0]!.url, "/backend-api/wham/usage");
    // No file (the keychain keeps it): nothing to read.
    assert.equal(await codexUsage(join(dir, "none", "auth.json"), { ...URLS, chatgpt: p.base }), null);
    await p.close();
  });

  test("a provider the station cannot reach is said so, not as Node says it", async () => {
    const dir = temp("codex-unreached");
    writeFileSync(join(dir, "auth.json"), JSON.stringify({ tokens: { access_token: "at" } }));
    // (a port nothing listens on any more: the connection is refused)
    const p = await provider(() => ({ status: 200, body: {} }));
    await p.close();
    const quota = await machineUsage("codex", { CODEX_HOME: dir }, { ...URLS, chatgpt: p.base }, "zh");
    assert.deepEqual([quota!.state, quota!.detail], ["unavailable", "无法连接服务商，请检查此 station 的网络或代理"]);
  });

  test("codex credits and resets are independent of windows and preserve unknowns", () => {
    const q = codexQuota({ rateLimits: { credits: { hasCredits: true, unlimited: false, balance: "123.45" } }, rateLimitResetCredits: { availableCount: 2, credits: [] } });
    assert.equal(q.state, "ok");
    assert.deepEqual(q.windows, []);
    assert.equal(q.credits!.balance, "123.45");
    assert.equal(q.resetCount, 2);
    const old = codexQuota({ rateLimits: { primary: { usedPercent: 10 } } });
    assert.equal(old.credits, undefined);
    assert.equal(old.resetCount, undefined);
    assert.ok(codexQuota({ rateLimits: { credits: { hasCredits: true, unlimited: true, balance: null } } }).credits!.unlimited);
    const zero = codexQuota({ rateLimits: { credits: { hasCredits: false, unlimited: false, balance: "0" } }, rateLimitResetCredits: { availableCount: 0 } });
    assert.equal(zero.resetCount, 0);
    assert.equal(zero.credits!.balance, "0");
  });

  test("codex app-server limits and window names", () => {
    const limits = { rateLimits: { primary: { usedPercent: 12.4, windowDurationMins: 300, resetsAt: 1_900_000_000 }, secondary: null } };
    assert.deepEqual(codexWindows(limits), [{ label: "5 小时", usedPercent: 12, resetsAt: 1_900_000_000_000, minutes: 300 }]);
    assert.equal(codexQuota({ rateLimits: { ...limits.rateLimits, planType: "ultra" } }).plan, "ultra");
    assert.equal(codexQuota(limits).plan, undefined);
    assert.equal(windowLabel(10080, "x"), "每周");
    assert.equal(windowLabel(43200, "x"), "每月");
    assert.equal(windowLabel(2880, "x"), "2 天");
    assert.equal(windowLabel(null, "每周"), "每周");
    assert.equal(at("2026-09-27T00:00:02.500Z"), Date.parse("2026-09-27T00:00:02.500Z"));
  });

  // ── renewing (claude_oauth.rs) ──

  const credentials = (expires: number) => ({
    otherCredential: { keep: true },
    claudeAiOauth: { accessToken: "old", refreshToken: "refresh-old", expiresAt: expires, scopes: ["user:profile", "user:inference"], subscriptionType: "max", clientId: "test-client" },
  });

  /// The token endpoint (POST) answers `status` with new tokens; usage (GET) answers the new token 42%, others 401.
  const oauthProvider = (status: number) =>
    provider((asked) => {
      if (asked.method === "POST") {
        return { status, delayMs: 50, body: { access_token: "new", refresh_token: "refresh-new", expires_in: 28800, refresh_token_expires_in: 86400, scope: "user:profile user:inference" } };
      }
      if (asked.headers.authorization === "Bearer new") return { status: 200, body: { five_hour: { utilization: 42 } } };
      return { status: 401, body: { error: { message: "expired" } } };
    });

  test("an abandoned lock is taken over, and its old owner cannot remove the one that replaced it", async () => {
    const dir = temp("lock");
    const path = join(dir, ".oauth_refresh.lock");
    mkdirSync(path);
    const old = (Date.now() - 61_000) / 1000;
    utimesSync(path, old, old);
    const owner = await RefreshLock.acquire(path);
    rmdirSync(path);
    mkdirSync(path);
    owner.release();
    assert.ok(existsSync(path));
  });

  test("parallel quota reads renew once without a claude process and keep what else the login holds", async () => {
    const home = temp("renew");
    const path = join(home, ".credentials.json");
    writeFileSync(path, JSON.stringify(credentials(1)));
    const p = await oauthProvider(200);
    const urls = { ...URLS, anthropic: p.base, claudeToken: p.base };
    const [a, b] = await Promise.all([claudeWithRefresh({}, home, urls), claudeWithRefresh({}, home, urls)]);
    for (const q of [a, b]) assert.equal(q.windows[0]!.usedPercent, 42);
    const posts = p.asked.filter((r) => r.method === "POST");
    assert.equal(posts.length, 1);
    assert.equal(posts[0]!.body.refresh_token, "refresh-old");
    assert.equal(posts[0]!.body.client_id, "test-client");
    assert.equal(posts[0]!.body.scope, "user:profile user:inference");
    const stored = JSON.parse(readFileSync(path, "utf8"));
    assert.equal(stored.claudeAiOauth.refreshToken, "refresh-new");
    assert.equal(stored.claudeAiOauth.subscriptionType, "max");
    assert.equal(stored.otherCredential.keep, true);
    if (process.platform !== "win32") assert.equal(statSync(path).mode & 0o777, 0o600);
    assert.ok(!existsSync(join(home, ".oauth_refresh.lock")));
    await p.close();
  });

  test("an early 401 renews and asks the allowance once more", async () => {
    const home = temp("early");
    writeFileSync(join(home, ".credentials.json"), JSON.stringify(credentials(Date.now() + 3_600_000)));
    const p = await oauthProvider(200);
    const got = await claudeWithRefresh({}, home, { ...URLS, anthropic: p.base, claudeToken: p.base });
    assert.equal(got.state, "ok");
    assert.deepEqual(p.asked.map((r) => r.method), ["GET", "POST", "GET"]);
    await p.close();
  });

  test("a failed renewal keeps the login as it was, and the next try renews", async () => {
    const home = temp("failed");
    const path = join(home, ".credentials.json");
    const original = JSON.stringify(credentials(1));
    writeFileSync(path, original);
    let p = await oauthProvider(503);
    const error = await claudeOAuthToken({}, home, null, p.base).then(
      () => "renewed",
      (e) => (e as Error).message,
    );
    assert.ok(error.includes("503") && !error.includes("refresh-old"), error);
    assert.equal(readFileSync(path, "utf8"), original);
    await p.close();
    p = await oauthProvider(200);
    assert.equal((await claudeOAuthToken({}, home, null, p.base))[0], "new");
    await p.close();
  });

  test("a login that can no longer be renewed is over: its allowance says so, for its profile to be checked again", async () => {
    const home = temp("over");
    const path = join(home, ".credentials.json");
    const profile = { ...hubConfig({ profiles: [{ id: "cc", home: "homes/cc", runtime: "claude", access: { kind: "subscription" } }] }, "/x").profiles[0]!, home };
    let p = await oauthProvider(400);
    const urls = { ...URLS, anthropic: p.base, claudeToken: p.base };
    // Run out with nothing to renew it with, or its refresh token refused.
    writeFileSync(path, JSON.stringify({ claudeAiOauth: { accessToken: "old", expiresAt: 1 } }));
    const none = await checkQuota(profile, {}, undefined, urls, "zh");
    assert.deepEqual([none.state, none.detail, none.signedOut], ["unavailable", "Claude 登录已过期且无法续期，请重新登录", true]);
    writeFileSync(path, JSON.stringify(credentials(1)));
    const refused = await checkQuota(profile, {}, undefined, urls, "zh");
    assert.deepEqual([refused.state, refused.signedOut], ["unavailable", true]);
    await p.close();
    // Not renewed for now: nothing is said of the login.
    p = await oauthProvider(503);
    const later = await checkQuota(profile, {}, undefined, { ...urls, anthropic: p.base, claudeToken: p.base }, "zh");
    assert.deepEqual([later.state, later.signedOut], ["unavailable", undefined]);
    await p.close();
  });

  test("a token handed out is renewed while it still lasts the usual margin, and given as it is when that fails", async () => {
    const home = temp("handed");
    const path = join(home, ".credentials.json");
    writeFileSync(path, JSON.stringify(credentials(Date.now() + 1_800_000)));
    let p = await oauthProvider(503);
    const [kept] = await claudeOAuthToken({}, home, null, p.base, "en", 3_600_000);
    assert.notEqual(kept, "new", "renewing failed: the token lasting half an hour is given");
    assert.ok(p.asked.some((r) => r.method === "POST"), "it was renewed first");
    await p.close();
    p = await oauthProvider(200);
    assert.equal((await claudeOAuthToken({}, home, null, p.base, "en", 3_600_000))[0], "new");
    await p.close();
  });

  test("the CLI's legacy lock is waited for, and the token it saved is read again", async () => {
    const home = temp("legacy");
    const path = join(home, ".credentials.json");
    writeFileSync(path, JSON.stringify(credentials(1)));
    const lock = `${realpathSync(home)}.lock`;
    mkdirSync(lock);
    const renewed = claudeOAuthToken({}, home, null, "http://127.0.0.1:1");
    // Its own lock taken, it is waiting on the legacy one (taken in the same run of microtasks): the CLI saves and leaves.
    await until(() => existsSync(join(home, ".oauth_refresh.lock")), "its own lock taken");
    const data = credentials(Date.now() + 3_600_000);
    data.claudeAiOauth.accessToken = "cli-won";
    writeFileSync(path, JSON.stringify(data));
    rmdirSync(lock);
    const [token] = await renewed;
    assert.equal(token, "cli-won");
  });

  test("a keychain read failure never replays a stale file's refresh token", { skip: process.platform !== "darwin" }, async () => {
    const m = machine({ security: "exit 36" }); // errSecInteractionNotAllowed, not errSecItemNotFound (44)
    mkdirSync(join(m.home, ".claude"));
    const file = join(m.home, ".claude", ".credentials.json");
    const stale = JSON.stringify(credentials(1));
    writeFileSync(file, stale);
    const p = await oauthProvider(200);
    try {
      await assert.rejects(claudeOAuthToken(m.env, null, null, p.base, "en"), /keychain/i);
      assert.equal(p.asked.length, 0, "no stale refresh token leaves the machine");
      assert.equal(readFileSync(file, "utf8"), stale);
    } finally {
      await p.close();
    }
  });

  test("a keychain failure on the locked reread cannot switch to the file", { skip: process.platform !== "darwin" }, async () => {
    const m = machine({ security: `if [ -f "$HOME/read-once" ]; then exit 36; fi
: > "$HOME/read-once"
/bin/cat "$HOME/keychain"` });
    mkdirSync(join(m.home, ".claude"));
    const original = JSON.stringify(credentials(1));
    writeFileSync(join(m.home, "keychain"), original);
    const file = join(m.home, ".claude", ".credentials.json");
    writeFileSync(file, original);
    const p = await oauthProvider(200);
    try {
      await assert.rejects(claudeOAuthToken(m.env, null, null, p.base, "en"), /keychain/i);
      assert.equal(p.asked.length, 0);
      assert.equal(readFileSync(file, "utf8"), original);
      assert.equal(readFileSync(join(m.home, "keychain"), "utf8"), original);
      assert.equal(existsSync(join(m.home, ".claude", ".oauth_refresh.lock")), false);
      assert.equal(existsSync(`${realpathSync(join(m.home, ".claude"))}.lock`), false);
    } finally {
      await p.close();
    }
  });

  test("machine credential discovery does not fall back on keychain errors or malformed entries", { skip: process.platform !== "darwin" }, async () => {
    for (const security of ["exit 36", "printf 'not-json'", "printf '{}'", "kill -TERM $$", "missing-executable"]) {
      const m = machine({ security });
      if (security === "missing-executable") m.env.PATH = join(m.home, "missing-bin");
      mkdirSync(join(m.home, ".claude"));
      writeFileSync(join(m.home, ".claude", ".credentials.json"), JSON.stringify(credentials(Date.now() + 3_600_000)));
      assert.equal(await readClaudeCredentials(m.env), undefined, security);
    }
  });

  test("a missing keychain item still permits a file-only machine login", { skip: process.platform !== "darwin" }, async () => {
    const m = machine(); // security exits 44: item not found
    mkdirSync(join(m.home, ".claude"));
    const data = credentials(Date.now() + 3_600_000);
    writeFileSync(join(m.home, ".claude", ".credentials.json"), JSON.stringify(data));
    assert.equal((await readClaudeCredentials(m.env))?.token, "old");
    assert.equal((await claudeOAuthToken(m.env, null, null, "http://127.0.0.1:1"))[0], "old");
  });

  test("the machine's login renews in the keychain and never uses the stale file", { skip: process.platform !== "darwin" }, async () => {
    const home = temp("keychain");
    mkdirSync(join(home, ".claude"));
    const file = join(home, ".claude", ".credentials.json");
    writeFileSync(file, "stale file must not be read or replaced");
    const keychain = join(home, "keychain");
    writeFileSync(keychain, JSON.stringify(credentials(1)));
    // A stand-in `security` keeping its item in a file of the test's own (never the real keychain). Its PATH is only the
    // home: what it runs is named whole.
    script(
      join(home, "security"),
      `#!/bin/sh
p="$HOME/keychain"
if [ "$1" = "-i" ]; then
  command=$(/bin/cat)
  hex=\${command#* -X \\"}
  hex=\${hex%%\\"*}
  printf '%s' "$hex" | /usr/bin/xxd -r -p > "$p"
else
  /bin/cat "$p"
  echo
fi
`,
    );
    const p = await oauthProvider(200);
    const [token] = await claudeOAuthToken({ HOME: home, PATH: home }, null, null, p.base);
    assert.equal(token, "new");
    // What it was handed to keep is the whole login, as JSON.
    assert.equal(JSON.parse(readFileSync(keychain, "utf8")).claudeAiOauth.refreshToken, "refresh-new");
    assert.equal(readFileSync(file, "utf8"), "stale file must not be read or replaced");
    await p.close();
  });
});
