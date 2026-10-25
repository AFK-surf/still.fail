// A Kimi Code profile signed in to Kimi (accounts/kimi.ts): the device sign-in, the profile it makes, its token renewed
// in its home (never config.json) and refused, and what Claude Code is given, against a stand-in Kimi at a local address.
import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Accounts, type CheckRequest } from "../src/accounts/index.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { KIMI_TOKEN_FILE, readKimi, writeKimi } from "../src/accounts/kimi.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { URLS } from "../src/accounts/profiles.ts";
import { checkQuota, kimiWindows } from "../src/accounts/quota.ts";
import { keyFile, profileEnv, profileRuntimes } from "../src/agents/profiles.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { fingerprint } from "../src/sessions/decision.ts";
import { Store } from "../src/store/store.ts";
import { type Asked, provider, temp, upon } from "./accounts-fakes.ts";

const owner = { sub: "sub-owner", email: "owner@example.com", name: "", role: "owner", workspace: "ws", device: "d" };

/// Kimi's sign-in server: a code approved once `approve` is called, tokens kt_<n> renewed by kr_<n> (each spent when
/// used) for the device the sign-in was made on only, `signOut` ending them.
async function kimi() {
  const s = { approved: false, denied: false, signedOut: false, n: 0, refresh: "", device: "" };
  const issue = () => {
    s.n += 1;
    s.refresh = `kr_${s.n}`;
    return { status: 200, body: { access_token: `kt_${s.n}`, refresh_token: s.refresh, expires_in: 900, token_type: "Bearer", scope: "kimi-code" } };
  };
  const p = await provider((a: Asked) => {
    const device = a.headers["x-msh-device-id"] ?? "";
    if (a.form.client_id !== "17e5f671-d194-4dfb-9706-5516cb48c098") return { status: 400, body: { error: "invalid_client" } };
    if (a.url === "/api/oauth/device_authorization") {
      s.device = device;
      return { status: 200, body: { device_code: "dc", user_code: "ABCD-1234", verification_uri: "https://www.kimi.com/code/authorize_device", verification_uri_complete: "https://www.kimi.com/code/authorize_device?user_code=ABCD-1234", expires_in: 1800, interval: 0 } };
    }
    if (a.url === "/api/oauth/token" && a.form.grant_type === "refresh_token") {
      if (s.signedOut || a.form.refresh_token !== s.refresh || device !== s.device) return { status: 401, body: { error: "invalid_grant" } };
      return issue();
    }
    if (a.url === "/api/oauth/token") {
      if (a.form.device_code !== "dc" || device !== s.device) return { status: 400, body: { error: "invalid_grant" } };
      if (s.denied) return { status: 400, body: { error: "access_denied" } };
      return s.approved ? issue() : { status: 400, body: { error: "authorization_pending" } };
    }
    return { status: 404, body: {} };
  });
  return { ...p, s, urls: { ...URLS, kimi: p.base } };
}

test("a sign-in to Kimi relays its code and leaves the tokens in the home, for one device", async () => {
  const k = await kimi();
  const dir = temp("kimi-login");
  const logins = new LoginManager(dir, undefined, undefined, undefined, undefined, undefined, undefined, k.urls.kimi);
  const wait = (state: LoginState) => upon((wake) => logins.changes(wake), () => (logins.get("kc")?.state === state ? logins.get("kc") : undefined), state);
  try {
    const home = join(dir, "homes", "kc");
    await logins.startKimi({ id: "kc", home }, "zh");
    const asking = await wait("needs_approval");
    assert.deepEqual([asking.url, asking.userCode, asking.provider], ["https://www.kimi.com/code/authorize_device?user_code=ABCD-1234", "ABCD-1234", "kimi"]);
    k.s.approved = true;
    await wait("done");
    const login = readKimi(home)!;
    assert.deepEqual([login.access, login.refresh, login.lifeMs, login.deviceId], ["kt_1", "kr_1", 900_000, k.s.device]);
    assert.match(login.deviceId, /^[0-9a-f]{32}$/);
    // Claude Code's key: the access token alone.
    assert.equal(readFileSync(join(home, KIMI_TOKEN_FILE), "utf8"), "kt_1");
    const polled = k.asked.find((a) => a.url === "/api/oauth/token")!;
    assert.deepEqual([polled.form.grant_type, polled.headers["x-msh-platform"]], ["urn:ietf:params:oauth:grant-type:device_code", "still.fail"]);

    // Signed in again: on the same device.
    k.s.approved = false;
    await logins.startKimi({ id: "kc", home }, "zh");
    await wait("needs_approval");
    assert.equal(k.s.device, login.deviceId);
    // Turned down on Kimi's page: failed, saying so.
    k.s.denied = true;
    assert.equal((await wait("failed")).error, "授权已被拒绝");
  } finally {
    await logins.close();
    await k.close();
  }
});

test("a profile signed in to Kimi runs Claude Code on a token renewed in its home, and asks to sign in again once refused", async () => {
  const k = await kimi();
  const data = temp("kimi-accounts");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [] }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  // The check is asked with the profile's current token (Kimi's own model list is not reached from a test).
  const asked: CheckRequest[] = [];
  const accounts = new Accounts({
    data,
    store: Store.open(":memory:", null),
    config,
    urls: k.urls,
    machine: null,
    checkOnStart: false,
    quota: null,
    resetQuota: null,
    check: async (request) => {
      asked.push(request);
      return request.key === "" ? { state: "login", detail: "Kimi 登录已失效", models: null, checkedAt: 0 } : { state: "ok", detail: "", models: ["kimi-for-coding"], checkedAt: 0 };
    },
    discover: async (profile) => ({ state: "unsupported", detail: "", model: null, provider: null, models: [], fingerprint: fingerprint(profile) }),
  });
  accounts.start();
  const raw = (id: string) => JSON.parse(readFileSync(join(data, "config.json"), "utf8")).profiles.find((p: any) => p.id === id);
  const view = (id: string) => accounts.profilesView().find((p) => p.id === id);
  try {
    const { id: login } = await accounts.newLogin({ access: "kimi-code" }, owner, "zh");
    await upon((wake) => accounts.onChange(wake), () => accounts.loginsView().find((l) => l.id === login)?.job?.state === "needs_approval", "code");
    k.s.approved = true;
    const made = await upon((wake) => accounts.onChange(wake), () => accounts.loginsView().find((l) => l.id === login)?.created, "profile");
    assert.equal(made, "kimi-code");
    // No token in config.json: it is in the profile's home.
    assert.deepEqual(raw(made), { id: made, name: "Kimi Code", access: { kind: "api-provider", provider: "kimi-code", login: true }, home: "homes/kimi-code", env: {} });
    const profile = accounts.profiles().find((p) => p.id === made)!;
    assert.deepEqual(profileRuntimes(profile), ["claude"]);
    assert.deepEqual([view(made)!.access.login, view(made)!.loginCommand], [true, ""]);
    const home = join(data, "homes", made);
    assert.equal((await accounts.check(made, "zh")).state, "ok");
    assert.equal(asked.at(-1)!.key, "kt_1");

    // Claude Code: Kimi's address, no key of its own (it reads the file), so the key helper's is used.
    const env = profileEnv(profile, "claude");
    assert.equal(env.ANTHROPIC_BASE_URL, "https://api.kimi.com/coding");
    assert.deepEqual([env.ANTHROPIC_AUTH_TOKEN, env.ANTHROPIC_API_KEY], [undefined, undefined]);
    assert.equal(keyFile(profile), join(home, KIMI_TOKEN_FILE));

    // Not due yet: left as it is.
    await accounts.renewKimi(made);
    assert.equal(readKimi(home)!.access, "kt_1");
    // Due (less than half its life left): renewed for its device, the refresh token spent replaced.
    writeKimi(home, { ...readKimi(home)!, expiresAt: Date.now() + 60_000 });
    await accounts.renewKimi(made);
    assert.deepEqual([readKimi(home)!.access, readKimi(home)!.refresh], ["kt_2", "kr_2"]);
    assert.equal(readFileSync(join(home, KIMI_TOKEN_FILE), "utf8"), "kt_2");
    assert.equal(raw(made).access.key, undefined);
    // An edit keeps the sign-in.
    accounts.putProfile(made, { name: "Kimi" }, owner, "zh");
    assert.deepEqual(raw(made).access, { kind: "api-provider", provider: "kimi-code", login: true });

    // Signed out on Kimi: renewing is refused, and the check asks for a sign-in.
    k.s.signedOut = true;
    writeKimi(home, { ...readKimi(home)!, expiresAt: Date.now() + 60_000 });
    await accounts.renewKimi(made);
    assert.equal(readKimi(home)!.refresh, "");
    assert.equal(asked.at(-1)!.key, "");
    assert.equal((await accounts.check(made, "zh")).state, "login");

    // Signed in again from its page: renewed from then on.
    k.s.signedOut = false;
    k.s.approved = false;
    await accounts.startLogin(made, owner, "zh");
    k.s.approved = true;
    await upon((wake) => accounts.onChange(wake), () => (readKimi(home)?.refresh ?? "") !== "", "signed in");
    assert.equal(readFileSync(join(home, KIMI_TOKEN_FILE), "utf8"), `kt_${k.s.n}`);
  } finally {
    await accounts.close();
    await k.close();
  }
});

test("Kimi Code's usage answer is its windows: the shorter ones, then the week", () => {
  const body = {
    usage: { limit: "100", remaining: "80", resetTime: "2026-10-28T00:00:00Z" },
    limits: [{ window: { duration: 300, timeUnit: "TIME_UNIT_MINUTE" }, detail: { limit: "100", remaining: "40", resetTime: "2026-10-21T18:00:00Z" } }],
  };
  assert.deepEqual(kimiWindows(body), [
    { label: "5 小时", usedPercent: 60, resetsAt: Date.parse("2026-10-21T18:00:00Z"), minutes: 300 },
    { label: "每周", usedPercent: 20, resetsAt: Date.parse("2026-10-28T00:00:00Z"), minutes: 7 * 24 * 60 },
  ]);
  assert.deepEqual(kimiWindows({ usage: { used: 5, limit: 0 } }), []);
});

test("Kimi Code saying no allowance at all has none to show; one it says and cannot be read is unavailable", async () => {
  let body: unknown = {};
  const p = await provider(() => ({ status: 200, body }));
  const kc = { id: "kc", home: "/h", access: { kind: "api-provider", provider: "kimi-code", key: "sk-kimi" } } as never;
  const ask = async () => {
    const q = await checkQuota(kc, {}, undefined, { ...URLS, kimiApi: p.base }, "zh");
    return [q.state, q.detail];
  };
  try {
    // (an account it tells nothing of, as it answers one today: `{}`)
    assert.deepEqual(await ask(), ["unsupported", "Kimi Code 未提供此账号的额度信息"]);
    body = { usage: { used: "a lot" } };
    assert.deepEqual(await ask(), ["unavailable", "Kimi Code 没有返回额度信息"]);
    body = { usage: { limit: "100", remaining: "80" } };
    assert.deepEqual(await ask(), ["ok", null]);
  } finally {
    await p.close();
  }
});
