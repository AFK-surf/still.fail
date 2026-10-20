// An OpenCode Go profile signed in to the OpenCode Console (accounts/console.ts): the device sign-in, the profile it
// makes, its token renewed and refused, against a stand-in Console and Go gateway at a local address.
import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Accounts } from "../src/accounts/index.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { CONSOLE_FILE, readConsole } from "../src/accounts/console.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { URLS } from "../src/accounts/profiles.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { fingerprint } from "../src/sessions/decision.ts";
import { Store } from "../src/store/store.ts";
import { type Asked, provider, temp, upon } from "./accounts-fakes.ts";

const owner = { sub: "sub-owner", email: "owner@example.com", name: "", role: "owner", workspace: "ws", device: "d" };

/// The Console and the Go gateway: a code approved once `approve` is called, tokens st_<n> renewed by rt_<n> (each
/// spent when used, the token before it ending then), `signOut` ending all of them.
async function opencode() {
  const s = { approved: false, denied: false, signedOut: false, n: 0, valid: "", refresh: "" };
  const issue = () => {
    s.n += 1;
    s.valid = `st_${s.n}`;
    s.refresh = `rt_${s.n}`;
    return { status: 200, body: { access_token: s.valid, refresh_token: s.refresh, expires_in: 2_592_000, org_id: "wrk_1", token_type: "bearer" } };
  };
  const p = await provider((a: Asked) => {
    if (a.url === "/console/auth/device/code") return { status: 200, body: { device_code: "dc", user_code: "WXYZ-1234", verification_uri_complete: "/console/device?user_code=WXYZ-1234", expires_in: 600, interval: 0 } };
    if (a.url === "/console/auth/device/token" && a.form.grant_type === "refresh_token") {
      if (s.signedOut || a.form.refresh_token !== s.refresh) return { status: 400, body: { error: "invalid_grant" } };
      return issue();
    }
    if (a.url === "/console/auth/device/token") {
      if (a.form.device_code !== "dc") return { status: 400, body: { error: "invalid_grant" } };
      if (s.denied) return { status: 400, body: { error: "access_denied" } };
      return s.approved ? issue() : { status: 400, body: { error: "authorization_pending" } };
    }
    const bearer = a.headers.authorization === `Bearer ${s.valid}` && !s.signedOut;
    if (a.url === "/console/api/user") return bearer ? { status: 200, body: { id: "u1", email: "go@example.com" } } : { status: 401, body: {} };
    if (a.url === "/console/api/orgs") return bearer ? { status: 200, body: [{ id: "wrk_1", name: "Personal" }] } : { status: 401, body: {} };
    if (a.url === "/zen/go/v1/usage") return bearer ? { status: 200, body: { usage: {} } } : { status: 401, body: { error: "Invalid credential" } };
    if (a.url === "/zen/go/v1/models") return { status: 200, body: { data: [{ id: "kimi-k3" }, { id: "glm-5.2" }] } };
    return { status: 404, body: {} };
  });
  return { ...p, s, urls: { ...URLS, console: `${p.base}/console`, opencode: `${p.base}/zen/go` } };
}

test("a sign-in to the OpenCode Console relays its code and leaves the tokens in the home", async () => {
  const oc = await opencode();
  const dir = temp("console-login");
  const logins = new LoginManager(dir, undefined, undefined, undefined, oc.urls.console);
  const wait = (state: LoginState) => upon((wake) => logins.changes(wake), () => (logins.get("go")?.state === state ? logins.get("go") : undefined), state);
  try {
    const home = join(dir, "homes", "go");
    await logins.startConsole({ id: "go", home }, "zh");
    const asking = await wait("needs_approval");
    assert.deepEqual([asking.url, asking.userCode, asking.provider], [`${oc.base}/console/device?user_code=WXYZ-1234`, "WXYZ-1234", "opencode"]);
    oc.s.approved = true;
    await wait("done");
    assert.deepEqual({ ...readConsole(home)!, expiresAt: 0 }, { access: "st_1", refresh: "rt_1", expiresAt: 0, org: "wrk_1", email: "go@example.com", workspace: "Personal" });
    assert.ok(readConsole(home)!.expiresAt > Date.now() + 29 * 86_400_000);
    // The Console asked as the OAuth device grant has it.
    const polled = oc.asked.find((a) => a.url === "/console/auth/device/token")!;
    assert.deepEqual([polled.form.grant_type, polled.form.client_id], ["urn:ietf:params:oauth:grant-type:device_code", "still.fail"]);

    // Turned down on the Console's page: failed, saying so.
    oc.s.approved = false;
    oc.s.denied = true;
    await logins.startConsole({ id: "go", home }, "zh");
    assert.equal((await wait("failed")).error, "授权已被拒绝");
    // Cancelled while waiting: cancelled it stays, whatever the Console says next.
    oc.s.denied = false;
    await logins.startConsole({ id: "go", home }, "zh");
    await wait("needs_approval");
    logins.cancel("go");
    oc.s.approved = true;
    assert.equal(logins.get("go")!.state, "cancelled");
  } finally {
    await logins.close();
    await oc.close();
  }
});

test("a profile signed in to OpenCode runs on its token, renewed, kept through edits, and asks to sign in again once refused", async () => {
  const oc = await opencode();
  const data = temp("console-accounts");
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "key", home: "homes/key", access: { kind: "opencode-go", key: "sk-own" } }] }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  const accounts = new Accounts({
    data,
    store: Store.open(":memory:", null),
    config,
    urls: oc.urls,
    machine: null,
    checkOnStart: false,
    quota: null,
    resetQuota: null,
    discover: async (profile) => ({ state: "unsupported", detail: "", model: null, provider: null, models: [], fingerprint: fingerprint(profile) }),
  });
  accounts.start();
  const raw = (id: string) => JSON.parse(readFileSync(join(data, "config.json"), "utf8")).profiles.find((p: any) => p.id === id);
  const view = (id: string) => accounts.profilesView().find((p) => p.id === id);
  try {
    // A new profile from a sign-in: named by the account, its key the token, every runtime of OpenCode Go.
    const { id: login } = await accounts.newLogin({ access: "opencode-go" }, owner, "zh");
    await upon((wake) => accounts.onChange(wake), () => accounts.loginsView().find((l) => l.id === login)?.job?.state === "needs_approval", "code");
    oc.s.approved = true;
    const made = await upon((wake) => accounts.onChange(wake), () => accounts.loginsView().find((l) => l.id === login)?.created, "profile");
    assert.equal(made, "opencode-go");
    assert.deepEqual(raw(made), { id: made, name: "go@example.com", access: { kind: "opencode-go", key: "st_1", login: true }, home: "homes/opencode-go", env: {} });
    assert.deepEqual(accounts.profiles().find((p) => p.id === made)!.runtimes, ["claude", "codex", "dsh"]);
    assert.deepEqual([view(made)!.access.login, view(made)!.email, view(made)!.loginCommand], [true, "go@example.com", ""]);
    assert.equal((await accounts.check(made, "zh")).state, "ok");

    // Renewed: the new token is its key, the refresh token spent replaced in its home.
    await accounts.renewConsole(made);
    assert.equal(raw(made).access.key, "st_2");
    assert.equal(readConsole(join(data, "homes", made))!.refresh, "rt_2");
    assert.equal((await accounts.check(made, "zh")).state, "ok");
    // An edit keeps the sign-in; a key given in its place ends it.
    accounts.putProfile(made, { name: "Go" }, owner, "zh");
    assert.deepEqual(raw(made).access, { kind: "opencode-go", key: "st_2", login: true });

    // Signed out on the Console: renewing is refused, and the check asks for a sign-in rather than a key.
    oc.s.signedOut = true;
    await accounts.renewConsole(made);
    assert.equal(raw(made).access.key, "st_2");
    const out = await accounts.check(made, "zh");
    assert.deepEqual([out.state, out.detail], ["login", "OpenCode 登录已失效"]);
    accounts.putProfile(made, { access: { kind: "opencode-go", key: "sk-instead" } }, owner, "zh");
    assert.deepEqual(raw(made).access, { kind: "opencode-go", key: "sk-instead" });

    // A profile on a key signs in from its page: the token takes the key's place.
    oc.s.signedOut = false;
    oc.s.approved = false;
    await accounts.startLogin("key", owner, "zh");
    oc.s.approved = true;
    await upon((wake) => accounts.onChange(wake), () => raw("key").access.login === true, "signed in");
    assert.deepEqual(raw("key").access, { kind: "opencode-go", key: `st_${oc.s.n}`, login: true });
    assert.ok(readFileSync(join(data, "homes", "key", CONSOLE_FILE), "utf8").includes(`rt_${oc.s.n}`));
  } finally {
    await accounts.close();
    await oc.close();
  }
});
