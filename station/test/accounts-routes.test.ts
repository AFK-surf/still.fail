// The accounts' admin routes (admin/tests.rs: profiles, sign-ins, allowances, machine profiles, automatic decisions),
// on a station of the test's own: a config.json in a temp directory, a store, stand-in checks, allowances and login
// commands. Nothing reaches a provider, a keychain or a real login.
import type { Clock } from "effect";
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { Accounts, LOGIN_BROWSER_FILE, type AccountsDeps } from "../src/accounts/index.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { MachineLogins } from "../src/accounts/machine.ts";
import { learn } from "../src/accounts/catalog.ts";
import { routes } from "../src/api/routes/accounts.ts";
import { overview } from "../src/api/overview.ts";
import type { Request } from "../src/api/request.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { tr } from "../src/ops/i18n.ts";
import { profileEnv } from "../src/agents/profiles.ts";
import { fingerprint } from "../src/sessions/decision.ts";
import { DEFAULT_POLICY } from "../src/sessions/archive-policy.ts";
import { Store } from "../src/store/store.ts";
import { SessionChatPreparation, sessionChatReady } from "../src/store/session-chat-index.ts";
import { approval, exe, fakeBrowser, fakeLogin, machine as fakeMachine, provider, script, temp, until, upon } from "./accounts-fakes.ts";
import { URLS } from "../src/accounts/profiles.ts";
import { settle, testClock } from "./hub-fakes.ts";

const viewer = (email: string, role: string) => ({ sub: `sub-${email}`, email, name: "", role, workspace: "ws", device: "d" });
const owner = viewer("owner@example.com", "owner");
const member = viewer("dev@example.com", "member");

type Rig = Awaited<ReturnType<typeof rig>>;

async function rig(o: { approval?: string; data?: string; store?: Store; quota?: { n: number }; readQuota?: AccountsDeps["quota"]; resetQuota?: AccountsDeps["resetQuota"]; codex?: AccountsDeps["codex"]; hub?: AccountsDeps["hub"]; hermes?: AccountsDeps["hermes"]; machine?: MachineLogins; check?: AccountsDeps["check"]; discover?: AccountsDeps["discover"]; review?: AccountsDeps["reviewUndecided"]; clock?: Clock.Clock; workspaces?: string[]; shared?: AccountsDeps["shared"]; urls?: AccountsDeps["urls"]; claudeVersion?: string; ownReset?: boolean } = {}) {
  const data = o.data ?? temp("routes");
  const path = join(data, "config.json");
  if (!existsSync(path)) {
    writeFileSync(
      path,
      JSON.stringify({
        profiles: [
          { id: "cc", runtime: "claude", home: "homes/cc", env: { ANTHROPIC_API_KEY: "sk-very-secret-value", ANTHROPIC_BASE_URL: "https://example" } },
          { id: "cx", runtime: "codex", home: "homes/cx" },
        ],
        connects: [{ id: "ds", kind: "slack", mode: "multi-session", bind: { runtime: "claude" }, slack: { appToken: "xapp-1-aaaaaaaaaaaa", botToken: "xoxb-bbbbbbbbbbbb", appId: "A0DS", team: { id: "T0", name: "Acme" }, botName: "ember" } }],
      }),
    );
  }
  const config = new ConfigFile(data);
  config.check = checkConfig;
  const store = o.store ?? Store.open(":memory:", null);
  const fake = join(data, "fake-login");
  script(fake, fakeLogin(o.approval));
  const quota = o.quota;
  const accounts = new Accounts({
    data,
    store,
    config,
    loginCommands: { claude: exe(fake), codex: exe(fake) },
    machine: o.machine ?? null,
    checkOnStart: false,
    check: o.check ?? (async () => ({ state: "ok", detail: "fake", models: [], checkedAt: Date.now() })),
    quota:
      o.readQuota ??
      (quota
        ? async () => {
            quota.n++;
            return { state: "ok", windows: [{ label: "5 小时", usedPercent: 12, resetsAt: null }], detail: null, checkedAt: Date.now() };
          }
        : null),
    // (ownReset: the station's own way of resetting, a Claude subscription's here)
    ...(o.ownReset ? {} : { resetQuota: o.resetQuota ?? null }),
    codex: o.codex,
    hub: o.hub,
    reviewUndecided: o.review,
    hermes: o.hermes,
    discover: o.discover ?? (async (profile) => ({ state: "unsupported", detail: "", model: null, provider: null, models: [], fingerprint: fingerprint(profile) })),
    clock: o.clock,
    workspaces: () => o.workspaces ?? [],
    shared: o.shared,
    urls: o.urls,
    ...(o.claudeVersion !== undefined ? { claudeVersion: () => o.claudeVersion! } : {}),
  });
  accounts.start();
  const table = routes({
    accounts,
    overview: (r) => ({ profiles: accounts.profilesView(), logins: accounts.loginsView(), apiProviders: accounts.apiProviders(), automaticDecisions: accounts.automaticDecisionsView(r.viewer) }),
  });
  const call = async (method: string, path: string, body?: unknown, as = owner, headers: Record<string, string> = {}): Promise<[number, any]> => {
    const r: Request = { method, path, query: [], headers, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: as, lang: "zh" };
    for (const route of table) {
      const found = route.method === method ? route.pattern.exec(path) : null;
      if (found) {
        const a = await route.handle(r, found.slice(1));
        return [a.status, JSON.parse(String(a.body))];
      }
    }
    return [404, { error: `no route ${method} ${path}` }];
  };
  const profile = (id: string) => accounts.profiles().find((p) => p.id === id);
  const view = (id: string) => accounts.profilesView().find((p) => p.id === id);
  return { data, path, config, store, accounts, call, profile, view, close: () => accounts.close() };
}

describe("the accounts routes", { concurrency: true }, () => {
  test("an API key can be disabled and re-enabled without losing the key or its settings", async () => {
    const moved: string[] = [];
    let checks = 0;
    const t = await rig({
      hub: { accounts: { setHealth: () => {}, healthOf: () => ({}) }, profileGone: async (id) => { moved.push(id); } },
      check: async () => { checks++; return { state: "ok", detail: "fake", models: [], checkedAt: 0 }; },
    });
    try {
      assert.equal((await t.call("PUT", "/profiles/key", { runtime: "claude", access: { kind: "anthropic-api", key: "sk-my-secret" }, models: ["opus"] }))[0], 200);
      await settle();
      assert.equal(t.view("key")!.enabled, true);
      assert.equal((await t.call("PUT", "/profiles/key", { enabled: "no" }))[0], 400);
      const disabled = await t.call("PUT", "/profiles/key", { enabled: false });
      assert.equal(disabled[0], 200);
      assert.equal(t.view("key")!.enabled, false);
      assert.deepEqual(moved, ["key"]);
      assert.equal((t.profile("key")!.access as any).key, "sk-my-secret");
      assert.deepEqual(t.profile("key")!.models, ["opus"]);
      await settle();
      const before = checks;
      assert.equal((await t.call("POST", "/profiles/key/check"))[0], 409);
      await t.accounts.refreshQuota("key");
      assert.equal(checks, before, "a disabled key is not checked in the background or by hand");
      assert.equal((await t.call("PUT", "/profiles/key", { name: "Backup" }))[0], 200);
      assert.equal(t.profile("key")!.enabled, false, "other edits retain the disabled state");
      assert.equal((await t.call("PUT", "/profiles/key", { enabled: true }))[0], 200);
      assert.equal(t.view("key")!.enabled, true);
      assert.equal((t.profile("key")!.access as any).key, "sk-my-secret");
      assert.deepEqual(t.profile("key")!.models, ["opus"]);
    } finally { await t.close(); }
  });

  test("a profile serves every workspace the station joined but those withheld from it; a joined workspace's members do all its own do", async () => {
    const t = await rig({ workspaces: ["W1", "W2", "W3"] });
    const joined = { ...viewer("guest@example.com", "admin"), workspace: "W2", home: false };
    // By default, all of them.
    assert.deepEqual(t.view("cc")?.workspaces, ["W2", "W3"]);
    assert.equal((await t.call("PUT", "/profiles/cc", { workspaces: ["W3"] }, member))[0], 403);
    assert.equal((await t.call("PUT", "/profiles/cc", { workspaces: ["../x"] }))[0], 400);
    // A joined workspace's admin sets it as the home one's do.
    assert.equal((await t.call("PUT", "/profiles/cc", { workspaces: ["W3", "W3"] }, joined))[0], 200);
    assert.deepEqual(t.profile("cc")?.withheld, ["W2"]);
    // Kept through other edits, theirs too; all given back takes it back.
    assert.equal((await t.call("PUT", "/profiles/cc", { name: "Claude" }, { ...joined, role: "member" }))[0], 200);
    assert.deepEqual(JSON.parse(readFileSync(t.path, "utf8")).profiles[0].withheld, ["W2"]);
    assert.deepEqual(t.view("cc")?.workspaces, ["W3"]);
    // They see every profile, as the home one's do, with what each serves.
    const seen = t.accounts.profilesView(joined);
    assert.deepEqual(seen.map((p) => [p.id, p.workspaces]), [["cc", ["W3"]], ["cx", ["W2", "W3"]]]);
    assert.equal(seen[0].access.key, t.accounts.profilesView(owner)[0].access.key);
    assert.notEqual(seen[0].home, "");
    assert.equal((await t.call("POST", "/profiles/cc/check", {}, joined))[0], 200);
    assert.equal((await t.call("POST", "/profiles/cx/quota", {}, joined))[0], 200);
    assert.equal((await t.call("PUT", "/profiles/cc", { workspaces: ["W2", "W3"] }))[0], 200);
    assert.equal(JSON.parse(readFileSync(t.path, "utf8")).profiles[0].withheld, undefined);
    // null: the home workspace's only.
    assert.equal((await t.call("PUT", "/profiles/cc", { workspaces: null }))[0], 200);
    assert.deepEqual(t.profile("cc")?.withheld, ["W2", "W3"]);
    assert.equal((await t.call("DELETE", "/profiles/cx", undefined, joined))[0], 200);
    await t.close();
  });

  test("invalid edits are refused and leave the config unchanged", async () => {
    const t = await rig();
    const before = readFileSync(t.path, "utf8");
    assert.deepEqual(await t.call("DELETE", "/profiles/nope"), [400, { error: "unknown profile nope" }]);
    assert.equal(readFileSync(t.path, "utf8"), before);
    await t.close();
  });

  test("a profile in use is deleted all the same, even the last of its runtime a connect runs", async () => {
    const t = await rig();
    assert.equal((await t.call("DELETE", "/profiles/cc"))[0], 200);
    assert.equal(t.profile("cc"), undefined);
    await t.close();
  });

  test("profile env: strings set, null removes, omitted keys stay", async () => {
    const t = await rig();
    await t.call("PUT", "/profiles/cc", { env: { ANTHROPIC_BASE_URL: null, EXTRA: "1" } });
    assert.deepEqual(profileEnv(t.profile("cc")!, "claude"), { ANTHROPIC_API_KEY: "sk-very-secret-value", EXTRA: "1" });
    assert.equal((await t.call("PUT", "/profiles/cc", { env: { "BAD NAME": "x" } }))[0], 400);
    await t.call("PUT", "/profiles/new-one", { runtime: "codex" });
    assert.equal(t.accounts.profiles().at(-1)!.home, join(t.data, "homes/new-one"));
    // Secrets are masked for the pages.
    const env = t.view("cc")!.env;
    assert.deepEqual(env, [
      { key: "ANTHROPIC_API_KEY", secret: true, value: "sk-ve…alue" },
      { key: "EXTRA", secret: false, value: "1" },
    ]);
    await t.close();
  });

  test("editing a profile's access keeps a blank key but never carries it to another kind", async () => {
    const t = await rig();
    assert.equal((await t.call("PUT", "/profiles/cx", { access: { kind: "opencode-go", key: "ocg-key-123456" } }))[0], 200);
    assert.equal(profileEnv(t.profile("cx")!, "codex").OPENCODE_GO_KEY, "ocg-key-123456");
    await t.call("PUT", "/profiles/cx", { name: "Codex OCG", access: { kind: "opencode-go", key: "" } });
    assert.deepEqual([(t.profile("cx")!.access as any).key, t.profile("cx")!.name], ["ocg-key-123456", "Codex OCG"]);
    assert.equal((await t.call("PUT", "/profiles/cx", { access: { kind: "subscription", key: "" } }))[0], 200);
    assert.equal((t.profile("cx")!.access as any).key, undefined);
    assert.equal(t.view("cx")!.loginCommand, `CODEX_HOME=${join(t.data, "homes/cx")} codex login`);
    await t.close();
  });

  test("a key that runs Codex says the levels Codex offers on it once made", async () => {
    const levels = ["low", "medium", "high", "xhigh", "max", "ultra"];
    const t = await rig({
      codex: () => ({ models: async () => ({ models: ["gpt-6.1-terra"], efforts: new Map([["gpt-6.1-terra", levels]]), defaults: new Map([["gpt-6.1-terra", "low"]]) }) }) as any,
    });
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "openai", key: "sk-123456" } }))[0], 200);
    await until(() => t.accounts.health("openai").check?.modelEfforts !== undefined, "its levels read");
    const check = t.accounts.health("openai").check!;
    assert.deepEqual(check.modelEfforts, { codex: { "gpt-6.1-terra": levels } }, "without them it would hold other accounts of the model to the usual levels");
    assert.deepEqual(check.modelEffortDefaults, { codex: { "gpt-6.1-terra": "low" } });
    await t.close();
  });

  test("a key on a listed provider makes a profile that runs what its endpoints speak", async () => {
    const t = await rig();
    // Chat completions only: DeepSeek Harness alone runs it.
    const [status, body] = await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "groq", key: "gsk-123456" } });
    assert.equal(status, 200, JSON.stringify(body));
    assert.equal(body.id, "groq");
    const groq = t.profile("groq")!;
    assert.deepEqual([(groq.access as any).kind, (groq.access as any).provider, groq.runtimes, groq.name], ["api-provider", "groq", ["dsh"], "Groq"]);
    assert.equal(profileEnv(groq, "dsh").STILLFAIL_DSH_KEY, "gsk-123456");
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "jev", key: "jev-key-1" } }))[0], 200);
    assert.deepEqual(t.profile("jev")!.runtimes, []);
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "opencode", key: "oc-key-1" } }))[0], 200);
    const zen = t.profile("opencode")!;
    assert.deepEqual(zen.runtimes, ["claude", "codex", "dsh"]);
    assert.equal(profileEnv(zen, "claude").ANTHROPIC_BASE_URL, "https://opencode.ai/zen");
    assert.equal(profileEnv(zen, "claude").ANTHROPIC_CUSTOM_HEADERS, "x-opencode-session: {route}");
    assert.equal(profileEnv(zen, "codex").STILLFAIL_API_KEY, "oc-key-1");
    // A second key on the same provider is a profile of its own.
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "groq", key: "gsk-other" } }))[0], 200);
    assert.equal(t.accounts.profiles().filter((p) => (p.access as any)?.provider === "groq").length, 2);
    // The address is the person's where the provider has none; a key is optional only for a server of one's own.
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "azure-openai", key: "k" } }))[0], 400);
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "custom", endpoint: "http://127.0.0.1:4000/v1", protocol: "anthropic" } }))[0], 200);
    const custom = t.profile("custom")!;
    assert.deepEqual([(custom.access as any).key, (custom.access as any).endpoint, custom.runtimes], [undefined, "http://127.0.0.1:4000/v1", ["claude", "dsh"]]);
    // Claude Code adds /v1/messages itself: the address is taken at the root above the /v1 given.
    assert.equal(profileEnv(custom, "claude").ANTHROPIC_BASE_URL, "http://127.0.0.1:4000");
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "groq" } }))[0], 400, "a key is needed");
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "nope", key: "k" } }))[0], 400);
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "anthropic", key: "k" } }))[0], 400, "Anthropic is its own kind");
    assert.deepEqual(await t.call("POST", "/profiles", { access: { kind: "subscription" } }), [400, { error: "订阅账号需通过登录添加" }]);
    assert.deepEqual(await t.call("POST", "/profiles", { access: { kind: "nope" } }), [400, { error: 'unknown access "nope"' }]);
    // What an older core is shown: `env`, with the provider beside it; the list leaves out the two kinds from before.
    const view = t.view("groq")!;
    assert.deepEqual([view.access.kind, view.access.provider, view.access.key.includes("123456")], ["env", "groq", false]);
    const listed = t.accounts.apiProviders().map((p) => p.id);
    assert.ok(listed.includes("deepseek") && listed.includes("opencode") && !listed.includes("anthropic") && !listed.includes("opencode-go"));
    // Its address can be changed, its key kept; it can be deleted.
    assert.equal((await t.call("PUT", "/profiles/custom", { access: { kind: "api-provider", endpoint: "http://127.0.0.1:5000/v1" } }))[0], 200);
    assert.equal((t.profile("custom")!.access as any).endpoint, "http://127.0.0.1:5000/v1");
    assert.equal((await t.call("DELETE", "/profiles/groq"))[0], 200);
    // The trial homes became the profiles' own.
    assert.ok(existsSync(join(t.data, "homes", "opencode")));
    await t.close();
  });

  test("a subscription sign-in runs on the station's machine and relays the link, the code and the result", async () => {
    const dir = temp("routes");
    const approved = approval(dir);
    const reloaded: string[] = [];
    const codex = () => ({ rateLimits: async () => ({}), resetQuota: async () => ({}), models: async () => ({ models: [], efforts: new Map() }), loginChanged: async (id: string) => { reloaded.push(id); } });
    const t = await rig({ data: dir, approval: approved.path, codex });
    const wait = (id: string, state: string) => waitFor(t, id, state);
    await t.call("PUT", "/profiles/sub", { runtime: "claude", access: { kind: "subscription" } });
    assert.equal((await t.call("POST", "/profiles/cc/login"))[0], 400, "keyed profiles do not sign in");
    assert.deepEqual(await t.call("GET", "/profiles/nope/login"), [404, { error: "unknown profile nope" }]);
    await t.call("POST", "/profiles/sub/login");
    const job = await wait("sub", "needs_code");
    assert.ok(job.url.startsWith("https://claude.com/cai/oauth/authorize?"));
    await t.call("POST", "/profiles/sub/login-code", { code: "wrong" });
    assert.ok((await wait("sub", "failed")).error.includes("invalid code"));
    assert.equal((await t.call("POST", "/profiles/sub/login-code", { code: "again" }))[0], 400);
    await t.call("POST", "/profiles/sub/login");
    await wait("sub", "needs_code");
    await t.call("POST", "/profiles/sub/login-code", { code: " good-code " });
    await wait("sub", "done");

    await t.call("PUT", "/profiles/cxs", { runtime: "codex", access: { kind: "subscription" } });
    await t.call("POST", "/profiles/cxs/login");
    const device = await wait("cxs", "needs_approval");
    assert.deepEqual([device.url, device.userCode], ["https://auth.openai.com/codex/device", "ABCD-12345"]);
    await approved.approve();
    await wait("cxs", "done");
    assert.equal(t.view("cxs")!.login.state, "done");
    await until(() => reloaded.includes("cxs"), "Codex told that the login changed");
    // Cancelled from the page.
    await t.call("POST", "/profiles/sub/login");
    await wait("sub", "needs_code");
    assert.equal((await t.call("DELETE", "/profiles/sub/login"))[1].job.state, "cancelled");
    await t.close();
  });

  /// The sign-in as its page reads it, once in `state`: read again each time the accounts say something changed.
  async function waitFor(t: Rig, id: string, state: string): Promise<any> {
    let last: any;
    try {
      return await upon(
        (wake) => t.accounts.onChange(wake),
        async () => {
          [, last] = await t.call("GET", `/profiles/${id}/login`);
          return last.job?.state === state ? last.job : undefined;
        },
        `${id} ${state}`,
      );
    } catch {
      throw new Error(`login of ${id} never reached ${state}: ${JSON.stringify(last)}`);
    }
  }

  test("a sign-in after its profile was deleted makes a profile beside the home left behind", async () => {
    const t = await rig();
    const signedIn = async () => {
      const [status, body] = await t.call("POST", "/logins", { runtime: "codex" });
      assert.equal(status, 200, JSON.stringify(body));
      const id = body.id;
      return upon(
        (wake) => t.accounts.onChange(wake),
        () => {
          const login = t.accounts.loginsView().find((l) => l.id === id);
          assert.equal(login?.error, null, JSON.stringify(login));
          return login?.created as string | undefined;
        },
        `the sign-in ${id} made a profile`,
      );
    };
    const first = await signedIn();
    assert.equal(t.profile(first)!.name, "ChatGPT 订阅");
    assert.equal((await t.call("DELETE", `/profiles/${first}`))[0], 200);
    assert.ok(existsSync(join(t.data, "homes", first)), "a deleted profile's home stays");
    const second = await signedIn();
    assert.notEqual(second, first);
    assert.ok(t.profile(second));
    // A sign-in is dropped from its page; another id is no route.
    const [, made] = await t.call("POST", "/logins", { runtime: "claude" });
    assert.deepEqual(await t.call("DELETE", `/logins/${made.id}`), [200, { ok: true }]);
    assert.equal((await t.call("DELETE", `/logins/${made.id}`))[0], 404);
    assert.deepEqual(await t.call("POST", "/logins", { runtime: "nope" }), [400, { error: "unknown runtime nope" }]);
    await t.close();
  });

  test("Claude sign-ins prefill --email when known and bind their browser state file across profile creation and cancellation", async () => {
    const dir = temp("claude-login-email-state");
    const argsLog = join(dir, "args.log");
    const t = await rig({ data: dir });
    script(
      join(dir, "fake-login"),
      `#!/bin/sh\necho "$*" >> '${argsLog}'\n` + fakeLogin().replace("#!/bin/sh\n", ""),
    );
    const b = fakeBrowser();
    t.accounts.logins.attach(b.pages);
    try {
      // 1. Email read from .claude.json in the profile's home, and browser state file in homes/<id>.
      await t.call("PUT", "/profiles/sub1", { name: "Claude 1", runtime: "claude", access: { kind: "subscription" } });
      mkdirSync(join(dir, "homes/sub1"), { recursive: true });
      writeFileSync(join(dir, "homes/sub1/.claude.json"), JSON.stringify({ oauthAccount: { emailAddress: "cuesurf1@proton.me" } }));
      await t.call("POST", "/profiles/sub1/login");
      await waitFor(t, "sub1", "needs_code");
      assert.equal(await t.accounts.logins.openPage("sub1", "zh"), "browser:T1");
      assert.equal(b.options.get("T1")?.stateFile?.(), join(dir, "homes/sub1", LOGIN_BROWSER_FILE));
      await t.call("DELETE", "/profiles/sub1/login");
      assert.equal(b.options.get("T1")?.stateFile?.(), join(dir, "homes/sub1", LOGIN_BROWSER_FILE), "an existing profile keeps its browser state across restarted sign-ins");

      // 2. Fallback to email-shaped profile name when .claude.json has none.
      await t.call("PUT", "/profiles/sub2", { name: "cuesurf2@proton.me", runtime: "claude", access: { kind: "subscription" } });
      await t.call("POST", "/profiles/sub2/login");
      await waitFor(t, "sub2", "needs_code");
      await t.call("DELETE", "/profiles/sub2/login");

      // 3. Non-email name without .claude.json omits --email.
      await t.call("PUT", "/profiles/sub3", { name: "Claude 主账号", runtime: "claude", access: { kind: "subscription" } });
      await t.call("POST", "/profiles/sub3/login");
      await waitFor(t, "sub3", "needs_code");
      await t.call("DELETE", "/profiles/sub3/login");

      const lines = readFileSync(argsLog, "utf8").trim().split("\n");
      assert.deepEqual(lines, [
        "auth login --claudeai --email cuesurf1@proton.me",
        "auth login --claudeai --email cuesurf2@proton.me",
        "auth login --claudeai",
      ]);

      // 4. New subscription login: stateFile follows homes/login-<hex> -> homes/<created> once finished, and becomes null when dropped.
      const [, started] = await t.call("POST", "/logins", { runtime: "claude" });
      await upon((wake) => t.accounts.onChange(wake), () => t.accounts.logins.get(started.id)?.state === "needs_code", "newLogin needs_code");
      assert.equal(await t.accounts.logins.openPage(started.id, "zh"), "browser:T2");
      const stateForNew = b.options.get("T2")!.stateFile!;
      assert.equal(stateForNew(), join(dir, "homes", started.id, LOGIN_BROWSER_FILE));
      await t.call("POST", `/logins/${started.id}/code`, { code: "good-code" });
      const created = await upon(
        (wake) => t.accounts.onChange(wake),
        () => t.accounts.loginsView().find((l) => l.id === started.id)?.created as string | undefined,
        "newLogin created profile",
      );
      assert.equal(stateForNew(), join(dir, "homes", created, LOGIN_BROWSER_FILE));

      const [, dropped] = await t.call("POST", "/logins", { runtime: "claude" });
      await upon((wake) => t.accounts.onChange(wake), () => t.accounts.logins.get(dropped.id)?.state === "needs_code", "dropped needs_code");
      assert.equal(await t.accounts.logins.openPage(dropped.id, "zh"), "browser:T3");
      const stateForDropped = b.options.get("T3")!.stateFile!;
      assert.equal(stateForDropped(), join(dir, "homes", dropped.id, LOGIN_BROWSER_FILE));
      await t.call("DELETE", `/logins/${dropped.id}`);
      assert.equal(stateForDropped(), null);
      assert.equal(existsSync(join(dir, "homes", dropped.id)), false);
    } finally {
      await t.close();
    }
  });

  test("a profile runs every model its check found, besides those config.json names, and names none of them there", async () => {
    const data = temp("found");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [] }));
    const offered = ["gpt-6-astra", "gpt-6-luna"];
    const t = await rig({ data, check: async (request) => ({ state: "ok", detail: "fake", models: request.kind === "subscription" ? offered : [], checkedAt: Date.now() }) });
    const [status, body] = await t.call("POST", "/logins", { runtime: "codex" });
    assert.equal(status, 200, JSON.stringify(body));
    const made = await upon((wake) => t.accounts.onChange(wake), () => t.accounts.loginsView().find((l) => l.id === body.id)?.created as string | undefined, `the sign-in ${body.id} made a profile`);
    const runs = await upon((wake) => t.accounts.onChange(wake), () => (t.profile(made)?.models.length ? t.profile(made)!.models : undefined), `${made} runs what its check found`);
    assert.deepEqual(runs, offered);
    assert.deepEqual(t.profile(made)!.named, [], "config.json names none of them");
    const raw = JSON.parse(readFileSync(join(data, "config.json"), "utf8"));
    assert.equal(raw.profiles.find((p: { id: string }) => p.id === made).models, undefined);
    await t.close();
  });

  test("a check that cannot read the models this time keeps those it read last", async () => {
    let listed: string[] | null = ["claude-opus-5-5", "claude-sonnet-5-5"];
    let state = "ok";
    const t = await rig({ check: async () => ({ state, detail: "fake", models: listed, checkedAt: Date.now() }) });
    await t.call("POST", "/profiles/cc/check");
    assert.deepEqual(t.profile("cc")!.models, ["claude-opus-5-5", "claude-sonnet-5-5"]);
    // Its model list not answered (a timeout, a 5xx), or the whole check failing a moment: still the models it runs.
    listed = null;
    await t.call("POST", "/profiles/cc/check");
    assert.deepEqual(t.profile("cc")!.models, ["claude-opus-5-5", "claude-sonnet-5-5"]);
    state = "failed";
    await t.call("POST", "/profiles/cc/check");
    assert.deepEqual(t.profile("cc")!.models, ["claude-opus-5-5", "claude-sonnet-5-5"]);
    // A list read again replaces it.
    state = "ok";
    listed = ["claude-opus-5-5"];
    await t.call("POST", "/profiles/cc/check");
    assert.deepEqual(t.profile("cc")!.models, ["claude-opus-5-5"]);
    await t.close();
  });

  test("outdated models are unchecked once when the station starts; one checked again by hand stays", async () => {
    const data = temp("outdated");
    writeFileSync(
      join(data, "config.json"),
      JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", access: { kind: "subscription" }, home: "homes/cc", models: ["claude-opus-4-6", "claude-sonnet-5-5"] }] }),
    );
    const db = join(data, "stillfail.db");
    const store = Store.open(db, null);
    store.setProfileCheck("cc", { state: "ok", detail: "", models: ["claude-opus-4-6", "claude-opus-5-5", "claude-sonnet-5-5"], checkedAt: 1 });
    const first = await rig({ data, store });
    assert.deepEqual(first.profile("cc")!.named, ["claude-sonnet-5-5", "claude-opus-5-5"]);
    assert.deepEqual(JSON.parse(readFileSync(first.path, "utf8")).outdatedUnchecked, ["claude-opus-4-6"]);
    assert.equal((await first.call("PUT", "/profiles/cc", { models: ["claude-opus-4-6", "claude-opus-5-5"] }))[0], 200);
    await first.close();
    const again = await rig({ data, store: Store.open(db, null) });
    assert.deepEqual(again.profile("cc")!.named, ["claude-opus-4-6", "claude-opus-5-5"]);
    await again.close();
  });

  test("a model new in the catalog has its maker's profiles checked again, and replaces the one before it", async () => {
    const data = temp("new-model");
    writeFileSync(
      join(data, "config.json"),
      JSON.stringify({
        profiles: [
          { id: "cc", runtime: "claude", access: { kind: "subscription" }, home: "homes/cc", models: ["claude-fable-5-1", "claude-opus-5-5"] },
          { id: "cx", runtime: "codex", access: { kind: "subscription" }, home: "homes/cx", models: ["gpt-6.1-sol"] },
        ],
      }),
    );
    const store = Store.open(join(data, "stillfail.db"), null);
    store.setProfileCheck("cc", { state: "ok", detail: "", models: ["claude-fable-5-1", "claude-opus-5-5"], checkedAt: 1 });
    store.setProfileCheck("cx", { state: "ok", detail: "", models: ["gpt-6.1-sol"], checkedAt: 1 });
    const checked: string[] = [];
    const t = await rig({
      data,
      store,
      check: async (o) => {
        checked.push(o.runtime);
        return { state: "ok", detail: "fake", models: o.runtime === "claude" ? ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5"] : ["gpt-6.1-sol"], checkedAt: 0 };
      },
    });
    try {
      learn({ "claude-fable-5-2": { maker: "anthropic" }, "claude-fable-5-1": { maker: "anthropic" }, "claude-opus-5-5": { maker: "anthropic" }, "gpt-6.1-sol": { maker: "openai" } });
      // A maker none of its profiles has a model of: nothing checked.
      t.accounts.newModels(["glm-9"]);
      t.accounts.newModels(["claude-fable-5-2"]);
      await until(() => t.profile("cc")!.named.includes("claude-fable-5-2"), "checked again");
      await settle();
      assert.deepEqual(checked, ["claude"]);
      assert.deepEqual(t.profile("cc")!.named, ["claude-opus-5-5", "claude-fable-5-2"]);
      assert.deepEqual(JSON.parse(readFileSync(t.path, "utf8")).outdatedUnchecked, ["claude-fable-5-1"]);
    } finally {
      learn(null);
      await t.close();
    }
  });

  test("a login its allowance's reading finds over is checked again, once, and the check says to sign in", async () => {
    let over = false;
    let checks = 0;
    const t = await rig({
      check: async () => {
        checks++;
        return over ? { state: "login", detail: "over", models: null, checkedAt: Date.now() } : { state: "ok", detail: "fake", models: [], checkedAt: Date.now() };
      },
      readQuota: async () => (over ? { state: "unavailable", windows: [], detail: "over", checkedAt: 0, signedOut: true } : { state: "ok", windows: [], detail: null, checkedAt: 0 }),
    });
    await t.call("POST", "/profiles/cc/check");
    await t.call("POST", "/profiles/cc/quota");
    assert.equal(checks, 1);
    over = true;
    await t.call("POST", "/profiles/cc/quota");
    await until(() => t.accounts.health("cc").check?.state === "login", "checked again");
    assert.equal(checks, 2);
    assert.ok(!("signedOut" in t.view("cc")!.quota), "not kept");
    // Said already: reading it again does not check it again.
    await t.call("POST", "/profiles/cc/quota");
    await settle();
    assert.equal(checks, 2);
    await t.close();
  });

  test("profile checks and quotas are kept so a restart shows them at once", async () => {
    const data = temp("restart");
    const db = join(data, "stillfail.db");
    const first = await rig({ data, store: Store.open(db, null), quota: { n: 0 } });
    await first.call("POST", "/profiles/cc/check");
    await first.call("POST", "/profiles/cc/quota");
    await first.close();
    const again = await rig({ data, store: Store.open(db, null) });
    assert.equal(again.view("cc")!.check.detail, "fake");
    assert.equal(again.view("cc")!.quota.windows[0].usedPercent, 12);
    assert.deepEqual(again.accounts.health("cc").quota.windows[0].usedPercent, 12);
    await again.close();
  });

  test("a revoked Codex login stays in the account check until the provider accepts it again", async () => {
    const data = temp("codex-revoked");
    const db = join(data, "stillfail.db");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cx", runtime: "codex", home: "homes/cx", access: { kind: "subscription" } }], connects: [] }));
    let outcome: "ok" | "revoked" | "offline" = "ok";
    const readQuota = async () => outcome === "ok"
      ? { state: "ok", windows: [{ label: "5h", usedPercent: 12, resetsAt: null }], detail: null, checkedAt: 0 }
      : { state: "unavailable", windows: [], detail: outcome, checkedAt: 0, ...(outcome === "revoked" ? { signedOut: true } : {}) };
    const check = async () => ({ state: "ok", detail: "Logged in using ChatGPT", models: ["gpt-x"], checkedAt: 0 });
    const first = await rig({ data, store: Store.open(db, null), readQuota, check });
    await first.call("POST", "/profiles/cx/quota");
    await first.call("POST", "/profiles/cx/check");
    outcome = "revoked";
    const quota = (await first.call("POST", "/profiles/cx/quota"))[1];
    assert.equal(quota.state, "unavailable");
    assert.equal(quota.signedOut, undefined, "the internal signal is not kept on quota");
    assert.deepEqual([first.accounts.health("cx").check.state, first.accounts.health("cx").check.models], ["login", ["gpt-x"]]);
    assert.equal((await first.call("POST", "/profiles/cx/check"))[1].state, "login", "the CLI's local status is insufficient");
    await first.close();
    first.store.close();

    const again = await rig({ data, store: Store.open(db, null), readQuota, check });
    assert.equal((await again.call("POST", "/profiles/cx/check"))[1].state, "login", "the refusal survives a station restart");
    outcome = "offline";
    await again.call("POST", "/profiles/cx/quota");
    assert.equal(again.accounts.health("cx").check.state, "login", "a network failure does not clear the refusal");
    outcome = "ok";
    await again.call("POST", "/profiles/cx/quota");
    assert.equal(again.accounts.health("cx").check.state, "ok");
    assert.equal(again.accounts.health("cx").check.codexRevoked, undefined);
    await again.close();
    again.store.close();
  });

  test("a completed Codex sign-in clears the old refusal even when the allowance is offline", async () => {
    const data = temp("codex-relogin-offline");
    const approved = approval(data);
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cx", runtime: "codex", home: "homes/cx", access: { kind: "subscription" } }], connects: [] }));
    let phase: "revoked" | "pending" | "offline" = "revoked";
    let startedOld!: () => void;
    let releaseOld!: () => void;
    const oldStarted = new Promise<void>((resolve) => { startedOld = resolve; });
    const oldFinished = new Promise<void>((resolve) => { releaseOld = resolve; });
    const readQuota = async () => {
      const started = phase;
      if (started === "pending") { startedOld(); await oldFinished; }
      return { state: "unavailable", windows: [], detail: started === "offline" ? "offline" : "revoked", checkedAt: 0, ...(started !== "offline" ? { signedOut: true } : {}) };
    };
    const t = await rig({ data, approval: approved.path, readQuota });
    await t.call("POST", "/profiles/cx/quota");
    assert.equal(t.accounts.health("cx").check.state, "login");
    await settle();
    phase = "pending";
    const old = t.call("POST", "/profiles/cx/quota");
    await oldStarted;
    await t.call("POST", "/profiles/cx/login");
    await waitFor(t, "cx", "needs_approval");
    await t.call("DELETE", "/profiles/cx/login");
    assert.equal(t.accounts.health("cx").check.state, "login", "a cancelled sign-in does not clear the refusal");
    await t.call("POST", "/profiles/cx/login");
    await waitFor(t, "cx", "needs_approval");
    phase = "offline";
    await approved.approve();
    await waitFor(t, "cx", "done");
    assert.equal(t.accounts.health("cx").check.state, "ok");
    releaseOld();
    await old;
    await until(() => t.accounts.health("cx").quota?.detail === "offline", "the post-login allowance read");
    assert.equal(t.accounts.health("cx").check.state, "ok");
    assert.equal(t.accounts.health("cx").check.codexRevoked, undefined);
    await settle();
    phase = "revoked";
    await t.call("POST", "/profiles/cx/quota");
    assert.equal(t.accounts.health("cx").check.state, "login", "a later refusal is still recorded");
    await t.close();
  });

  test("a profile on the machine's own login: made from a login kept in a file, its models chosen, never renamed or signed in, stopped", async () => {
    const m = fakeMachine({ claude: `echo '{"loggedIn": true, "email": "b@x.com", "subscriptionType": "pro"}'`, codex: "echo 'Logged in using ChatGPT'" });
    const { mkdirSync } = await import("node:fs");
    mkdirSync(join(m.home, ".claude"));
    writeFileSync(join(m.home, ".claude/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "fake-access", expiresAt: Date.now() + 3_600_000 } }));
    const s = await rig({ machine: new MachineLogins(m.env, undefined, () => "zh") });
    // Kept elsewhere than a file: not one to use.
    const keychain = await s.call("POST", "/profiles/machine", { runtime: "codex" });
    assert.equal(keychain[0], 400);
    assert.ok(keychain[1].error.includes("钥匙串"), keychain[1].error);
    const made = await s.call("POST", "/profiles/machine", { runtime: "claude" });
    assert.equal(made[0], 200, JSON.stringify(made[1]));
    assert.equal(made[1].id, "machine-claude");
    const profile = () => s.profile("machine-claude")!;
    assert.equal(profile().machine, true);
    assert.equal(profile().name, "b@x.com");
    assert.equal((profile().access as any).kind, "subscription");
    assert.equal((await s.call("POST", "/profiles/machine", { runtime: "claude" }))[0], 409);
    // Only its models are chosen here.
    assert.equal((await s.call("PUT", "/profiles/machine-claude", { name: "renamed", models: ["claude-x"], access: { kind: "opencode-go", key: "k" } }))[0], 200);
    assert.deepEqual([profile().name, profile().models, (profile().access as any).kind, profile().machine], ["b@x.com", ["claude-x"], "subscription", true]);
    assert.equal(s.view("machine-claude")!.machine, true);
    await s.call("POST", "/profiles/machine-claude/check");
    assert.equal(s.view("machine-claude")!.check.plan, "pro", "the machine's login supplies a tier missing from the check");
    // Its account, as the same one signed in on another station is: the workspace's list makes them one row.
    assert.equal(s.view("machine-claude")!.email, "b@x.com");
    // And how it runs: on by default, turned off and on here; other edits keep it.
    assert.equal(profile().backgroundOnMessage, true);
    assert.equal((await s.call("PUT", "/profiles/machine-claude", { backgroundOnMessage: false }))[0], 200);
    assert.equal(profile().backgroundOnMessage, false);
    assert.equal((await s.call("PUT", "/profiles/machine-claude", { models: ["claude-y"] }))[0], 200);
    assert.equal(s.view("machine-claude")!.backgroundOnMessage, false);
    assert.equal((await s.call("PUT", "/profiles/machine-claude", { backgroundOnMessage: true }))[0], 200);
    assert.equal(profile().backgroundOnMessage, true);
    assert.equal((await s.call("POST", "/profiles/machine-claude/login"))[0], 400);
    // Stopped: the profile goes; it can be made again from the machine's login.
    assert.equal((await s.call("DELETE", "/profiles/machine-claude"))[0], 200);
    assert.equal(s.profile("machine-claude"), undefined);
    assert.equal((await s.call("POST", "/profiles/machine", { runtime: "claude" }))[0], 200);
    await s.close();
  });

  test("a profile on the machine's login is signed in where the machine's is, and checked again when that login changes", async () => {
    const m = fakeMachine({ claude: `echo '{"loggedIn": true, "email": "b@x.com", "subscriptionType": "pro"}'` });
    mkdirSync(join(m.home, ".claude"));
    writeFileSync(join(m.home, ".claude/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "fake-access", expiresAt: Date.now() + 3_600_000 } }));
    const machine = new MachineLogins(m.env, undefined, () => "zh");
    const checked: string[] = [];
    const s = await rig({ machine, check: async (o) => (checked.push(o.home), { state: "ok", detail: "fake", models: [], plan: "max", checkedAt: Date.now() }) });
    assert.equal((await s.call("POST", "/profiles/machine", { runtime: "claude" }))[0], 200);
    // Its home holds no login: the command is the machine's own.
    assert.equal(s.view("machine-claude")!.loginCommand, "claude auth login");
    await until(() => checked.length >= 1, "checked once made");
    const made = checked.length;
    // Read again with nothing changed: not checked again.
    await machine.refresh();
    assert.equal(checked.length, made);
    // The account stayed the same but its tier changed: its profile must be checked again too.
    script(join(m.bin, "claude"), `#!/bin/sh\necho '{"loggedIn": true, "email": "b@x.com", "subscriptionType": "max"}'\n`);
    await machine.refresh();
    await until(() => s.view("machine-claude")?.check?.plan === "max", "the changed tier is shown");
    // The token-only check still says max; the machine's own login can identify the former 20x as Ultra.
    writeFileSync(join(m.home, ".claude/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "fake-access", expiresAt: Date.now() + 3_600_000, rateLimitTier: "default_claude_max_20x" } }));
    await machine.refresh();
    await until(() => s.view("machine-claude")?.check?.plan === "ultra", "the Ultra tier is shown");
    const afterPlan = checked.length;
    // Signed out in a terminal: checked again.
    script(join(m.bin, "claude"), `#!/bin/sh\necho '{"loggedIn": false}'\nexit 1\n`);
    await machine.refresh();
    await until(() => checked.length > afterPlan, "checked again");
    await s.close();
  });

  test("machine login identity readings tell sharing, including the first and a later sign-in", async () => {
    const m = fakeMachine({ claude: `echo '{"loggedIn": true, "email": "first@x.test"}'` });
    mkdirSync(join(m.home, ".claude"));
    writeFileSync(join(m.home, ".claude/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "fake", expiresAt: Date.now() + 3_600_000 } }));
    const machine = new MachineLogins(m.env, undefined, () => "zh");
    const identities: (string | null)[] = [];
    const s = await rig({ machine, shared: {
      status: async () => ({ check: null, quota: null }), view: () => null,
      loginUpdated: () => identities.push(machine.get().find((l) => l.runtime === "claude")?.email ?? null),
    } });
    await until(() => identities.includes("first@x.test"), "the first reading tells sharing");
    const count = identities.length;
    await machine.refresh();
    assert.equal(identities.length, count, "an unchanged reading does not refresh sharing");
    script(join(m.bin, "claude"), `#!/bin/sh\necho '{"loggedIn": true, "email": "second@x.test"}'\n`);
    await machine.refresh();
    assert.equal(identities.at(-1), "second@x.test");
    await s.close();
  });

  test("the first machine login reading updates a profile checked before its tier was known", async () => {
    const m = fakeMachine({ claude: `echo '{"loggedIn":true,"subscriptionType":"max"}'` });
    mkdirSync(join(m.home, ".claude"));
    writeFileSync(join(m.home, ".claude/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "fake", expiresAt: Date.now() + 3_600_000, rateLimitTier: "default_claude_max_20x" } }));
    const data = temp("machine-tier-first");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "machine-claude", name: "Claude", runtime: "claude", home: "homes/machine-claude", access: { kind: "subscription" }, machine: true }], connects: [] }));
    const entered = Promise.withResolvers<void>();
    const release = Promise.withResolvers<void>();
    const machine = new MachineLogins(m.env, async (runtime) => {
      if (runtime === "claude") { entered.resolve(); await release.promise; }
      return null;
    }, () => "zh");
    const s = await rig({ data, machine, check: async () => ({ state: "ok", detail: "已登录，max", models: [], plan: "max", checkedAt: 0 }) });
    await entered.promise;
    await s.call("POST", "/profiles/machine-claude/check");
    assert.equal(s.view("machine-claude")!.check.plan, "max");
    const updated = upon((wake) => s.accounts.onChange(wake), () => s.view("machine-claude")?.check?.plan === "ultra", "the machine's first tier reading");
    release.resolve();
    assert.equal(await updated, true);
    await s.close();
  });

  test("a profile's home is read on the thread for its first view alone; what changes in it shows once read again off the thread, ten seconds on", async () => {
    // Its time moves only as the test says.
    const time = testClock();
    const data = temp("homes-read");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "sx", runtime: "codex", home: "homes/sx", access: { kind: "subscription" } }], connects: [] }));
    const t = await rig({ data, clock: time.clock });
    assert.deepEqual([t.view("sx")!.homeExists, t.view("sx")!.email], [false, null]);
    // Signed in from a terminal: nothing told the station.
    const home = join(data, "homes", "sx");
    mkdirSync(home, { recursive: true });
    const claims = Buffer.from(JSON.stringify({ email: "b@x.com" })).toString("base64url");
    writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { id_token: `h.${claims}.s` } }));
    assert.deepEqual([t.view("sx")!.homeExists, t.view("sx")!.email], [false, null], "as last read: not read on the thread again");
    await time.adjust(10_000);
    const seen = await upon((wake) => t.accounts.onChange(wake), () => {
      const v = t.view("sx")!;
      return v.email === "b@x.com" && v.homeExists;
    }, "the home read again");
    assert.ok(seen);
    await t.close();
  });

  test("a profile just made has its allowance read at once, without waiting for a round", async () => {
    const quota = { n: 0 };
    // Its time never moves: no round comes.
    const t = await rig({ quota, clock: testClock().clock });
    const made = await t.call("PUT", "/profiles/linked", { name: "Linked", runtime: "codex", access: { kind: "subscription" }, home: "homes/linked" });
    assert.equal(made[0], 200);
    await until(() => quota.n > 0, "the allowance read");
    await settle();
    assert.equal(quota.n, 1);
    assert.equal(t.view("linked")!.quota.windows[0].usedPercent, 12);
    await t.close();
  });

  test("a station borrowing a profile is told its allowance asked again when older than a round, though no one follows it", async () => {
    const quota = { n: 0 };
    const time = testClock();
    const t = await rig({ quota, clock: time.clock });
    assert.equal((await t.accounts.lentHealth("cx")).quota!.windows[0]!.usedPercent, 12);
    assert.equal(quota.n, 1);
    await t.accounts.lentHealth("cx");
    assert.equal(quota.n, 1, "a fresh one is told as it is");
    await time.adjust(5 * 60_000);
    await t.accounts.lentHealth("cx");
    assert.equal(quota.n, 2);
    await t.close();
  });

  test("an allowance read stands while its provider gives no answer, half an hour at most; a person who asks it again is told it was not answered", async () => {
    // One round's question not reaching Anthropic took every Claude account's allowance and resets off their pages
    // until the next round (ccvm, 2026-11-11).
    const time = testClock();
    const ok = (used: number) => ({ state: "ok", windows: [{ label: "每周", usedPercent: used, resetsAt: null }], resetCount: 1, detail: null, checkedAt: 0 });
    const none = { state: "unavailable", windows: [], detail: "无法连接服务商", checkedAt: 0, unanswered: true };
    let answer: any = ok(40);
    let asked = 0;
    const t = await rig({ clock: time.clock, readQuota: async () => { asked++; return answer; }, resetQuota: async () => ({ outcome: "reset" }) });
    try {
      assert.equal((await t.call("POST", "/profiles/cc/quota"))[0], 200);
      const read = t.view("cc")!.quota;
      assert.deepEqual([read.state, read.windows[0].usedPercent, read.resetCount], ["ok", 40, 1]);
      // No answer: what was read stands, with when it was read.
      answer = none;
      await time.adjust(5 * 60_000);
      await t.accounts.refreshQuota("cc");
      assert.deepEqual(t.view("cc")!.quota, read);
      // Told to a station borrowing it the same; not asked again before the next round.
      const before = asked;
      assert.deepEqual((await t.accounts.lentHealth("cc")).quota, read);
      assert.equal(asked, before);
      // Asked by a person: told it was not answered, what stands left as it is.
      assert.deepEqual(await t.call("POST", "/profiles/cc/quota"), [502, { error: "无法连接服务商" }]);
      assert.deepEqual(t.view("cc")!.quota, read);
      // An answer again: the allowance as it is now, and a person asking is answered.
      answer = ok(55);
      await time.adjust(5 * 60_000);
      await t.accounts.refreshQuota("cc");
      assert.equal(t.view("cc")!.quota.windows[0].usedPercent, 55);
      assert.equal((await t.call("POST", "/profiles/cc/quota"))[0], 200);
      // None for half an hour since it was read: the failure is said, the marker not kept in it.
      answer = none;
      await time.adjust(25 * 60_000);
      await t.accounts.refreshQuota("cc");
      assert.equal(t.view("cc")!.quota.windows[0].usedPercent, 55);
      await time.adjust(5 * 60_000);
      await t.accounts.refreshQuota("cc");
      const failed = t.view("cc")!.quota;
      assert.deepEqual([failed.state, failed.windows.length, failed.detail, "unanswered" in failed], ["unavailable", 0, "无法连接服务商", false]);
      // What the provider says of the account itself (its sign-in over) is said at once, an allowance read or not.
      answer = ok(60);
      await t.accounts.refreshQuota("cc");
      answer = { state: "unavailable", windows: [], detail: "登录已过期或失效", checkedAt: 0 };
      await time.adjust(5 * 60_000);
      await t.accounts.refreshQuota("cc");
      assert.deepEqual([t.view("cc")!.quota.state, t.view("cc")!.quota.detail], ["unavailable", "登录已过期或失效"]);
      // Asked because it changed (a reset used): what was read before the reset does not stand through no answer.
      await t.call("PUT", "/profiles/cx", { access: { kind: "subscription" } });
      await settle();
      answer = ok(100);
      await t.accounts.refreshQuota("cx");
      assert.equal(t.view("cx")!.quota.windows[0].usedPercent, 100);
      answer = none;
      assert.equal((await t.call("POST", "/profiles/cx/reset-quota", undefined, owner, { "Idempotency-Key": "k1" }))[0], 200);
      assert.equal(t.view("cx")!.quota.state, "unavailable");
    } finally { await t.close(); }
  });

  test("a borrowed Codex subscription's allowance is read with the login its host lent while that is good, else its host's", async () => {
    const data = temp("borrowed-quota");
    const home = join(data, "homes", "bx");
    mkdirSync(home, { recursive: true });
    writeFileSync(
      join(data, "config.json"),
      JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }),
    );
    const jwt = (exp: number) => ["{}", JSON.stringify({ exp: Math.floor(exp / 1000) }), "s"].map((x) => Buffer.from(x).toString("base64url")).join(".");
    const lend = (exp: number) => writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: jwt(exp), account_id: "acct", refresh_token: "lent-by-another-station" } }));
    const chatgpt = await provider(() => ({ status: 200, body: { rate_limit: { primary_window: { used_percent: 40, limit_window_seconds: 604_800, reset_at: 1_900_000_000 } } } }));
    // The host's, as old as the last time anyone followed it.
    const hosts = { n: 0, at: 1 };
    const shared = {
      status: async () => {
        hosts.n++;
        return { check: { state: "ok", detail: "host", models: null, checkedAt: 1, plan: "pro" }, quota: { state: "ok", windows: [{ label: "每周", usedPercent: 96, resetsAt: null }], detail: null, checkedAt: hosts.at } };
      },
      view: () => null,
    };
    const t = await rig({ data, shared, urls: { ...URLS, chatgpt: chatgpt.base } });
    lend(Date.now() + 86_400_000);
    assert.equal((await t.call("POST", "/profiles/bx/quota"))[1].windows[0].usedPercent, 40);
    assert.equal(hosts.n, 0);
    assert.equal(chatgpt.asked[0]!.headers["chatgpt-account-id"], "acct");
    // The host's check does not put its older allowance back.
    assert.equal((await t.call("POST", "/profiles/bx/check"))[0], 200);
    assert.equal(hosts.n, 1);
    assert.equal(t.view("bx")!.check.plan, "pro", "the borrowed profile carries the host's tier");
    assert.equal(t.view("bx")!.quota.windows[0].usedPercent, 40);
    // Run out: the host's, once it is newer than the one read here.
    lend(Date.now() - 1000);
    assert.equal((await t.call("POST", "/profiles/bx/quota"))[1].windows[0].usedPercent, 40);
    hosts.at = Date.now() + 1000;
    assert.equal((await t.call("POST", "/profiles/bx/quota"))[1].windows[0].usedPercent, 96);
    assert.equal(hosts.n, 3);
    assert.equal(chatgpt.asked.length, 1);
    await chatgpt.close();
    await t.close();
  });

  test("a revoked borrowed login is replaced from its host, or remains unusable if the host cannot lend", async () => {
    const data = temp("borrowed-revoked");
    const home = join(data, "homes", "bx");
    mkdirSync(home, { recursive: true });
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
    const jwt = (name: string) => ["{}", JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 86400, name }), "s"].map((x) => Buffer.from(x).toString("base64url")).join(".");
    const old = jwt("old");
    const fresh = jwt("fresh");
    const write = (token: string) => writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: token } }));
    write(old);
    const chatgpt = await provider((asked) => asked.headers.authorization === `Bearer ${fresh}`
      ? { status: 200, body: { rate_limit: { primary_window: { used_percent: 20 } } } }
      : { status: 401, body: { error: { code: "token_revoked" } } });
    let online = false;
    let hostUp = true;
    let replaced = 0;
    const shared = {
      status: async () => {
        if (!hostUp) throw new Error("offline");
        return { check: { state: "ok", detail: "host", models: null, checkedAt: 9 }, quota: { state: "ok", windows: [], detail: null, checkedAt: Date.now() + 1000 } };
      },
      lendCodex: async (_profile: any, rejected: boolean) => { assert.equal(rejected, true); if (!online) throw new Error("offline"); write(fresh); return Date.now() + 86400_000; },
      view: () => null,
    };
    const codex = () => ({ rateLimits: async () => ({}), resetQuota: async () => ({}), models: async () => ({ models: [], efforts: new Map() }), loginChanged: async () => { replaced++; } });
    const t = await rig({ data, shared, codex, urls: { ...URLS, chatgpt: chatgpt.base } });
    assert.equal((await t.call("POST", "/profiles/bx/quota"))[1].state, "unavailable");
    assert.equal(t.accounts.health("bx").check.state, "login");
    await t.call("POST", "/profiles/bx/check");
    assert.equal(t.accounts.health("bx").check.state, "login", "a host's success cannot hide this station's refusal");
    hostUp = false;
    await t.call("POST", "/profiles/bx/check");
    assert.equal(t.accounts.health("bx").check.state, "failed");
    hostUp = true;
    await t.call("POST", "/profiles/bx/check");
    assert.equal(t.accounts.health("bx").check.state, "login", "the refusal survives the host going away and coming back");
    online = true;
    const recovered = (await t.call("POST", "/profiles/bx/quota"))[1];
    assert.equal(recovered.state, "ok");
    assert.equal(recovered.windows[0].usedPercent, 20);
    assert.equal(t.accounts.health("bx").check.state, "ok");
    assert.equal(replaced, 1, "the running app-server loads the new login");
    await chatgpt.close();
    await t.close();
  });

  test("a valid new local login replaces an app-server still using the revoked one", async () => {
    const data = temp("local-revoked");
    const home = join(data, "homes", "cx");
    mkdirSync(home, { recursive: true });
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cx", runtime: "codex", home: "homes/cx", access: { kind: "subscription" } }], connects: [] }));
    writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: "fresh" } }));
    const chatgpt = await provider(() => ({ status: 200, body: { rate_limit: { primary_window: { used_percent: 25 } } } }));
    let replaced = 0;
    const codex = () => ({ rateLimits: async () => ({}), resetQuota: async () => ({}), models: async () => ({ models: [], efforts: new Map() }), loginChanged: async () => { replaced++; } });
    const t = await rig({ data, codex, urls: { ...URLS, chatgpt: chatgpt.base }, readQuota: async () => ({ state: "unavailable", signedOut: true, windows: [], detail: "revoked", checkedAt: 0 }) });
    const recovered = (await t.call("POST", "/profiles/cx/quota"))[1];
    assert.equal(recovered.state, "ok");
    assert.equal(recovered.windows[0].usedPercent, 25);
    assert.equal(replaced, 1);
    await chatgpt.close();
    await t.close();
  });

  test("a turn's authentication refusal marks the check even if the allowance endpoint is unreachable", async () => {
    const data = temp("codex-turn-refused");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cx", runtime: "codex", home: "homes/cx", access: { kind: "subscription" } }], connects: [] }));
    const signals: { recheck?: (id: string) => Promise<unknown> } = {};
    const hub: NonNullable<AccountsDeps["hub"]> = { accounts: { setHealth: () => {}, healthOf: () => ({}), setRecheck: (f) => { signals.recheck = f; } } };
    let online = false;
    const t = await rig({ data, hub, readQuota: async () => online
      ? { state: "ok", windows: [], detail: null, checkedAt: 0 }
      : { state: "unavailable", windows: [], detail: "network", checkedAt: 0 } });
    assert.ok(signals.recheck);
    await signals.recheck("cx");
    assert.equal(t.accounts.health("cx").check.state, "login");
    assert.equal(t.accounts.health("cx").quota.detail, "network", "the real allowance error is preserved");
    online = true;
    await t.call("POST", "/profiles/cx/quota");
    assert.equal(t.accounts.health("cx").check.state, "ok");
    await t.close();
  });

  test("an authentication recheck started before sign-in cannot reject the new login", async () => {
    const data = temp("codex-recheck-relogin");
    const approved = approval(data);
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cx", runtime: "codex", home: "homes/cx", access: { kind: "subscription" } }], connects: [] }));
    const signals: { recheck?: (id: string) => Promise<unknown> } = {};
    const hub: NonNullable<AccountsDeps["hub"]> = { accounts: { setHealth: () => {}, healthOf: () => ({}), setRecheck: (f) => { signals.recheck = f; } } };
    let phase: "revoked" | "pending" | "offline" = "revoked";
    let startedOld!: () => void;
    let releaseOld!: () => void;
    const oldStarted = new Promise<void>((resolve) => { startedOld = resolve; });
    const oldFinished = new Promise<void>((resolve) => { releaseOld = resolve; });
    const readQuota = async () => {
      const started = phase;
      if (started === "pending") { startedOld(); await oldFinished; }
      return { state: "unavailable", windows: [], detail: started === "offline" ? "offline" : "revoked", checkedAt: 0, ...(started !== "offline" ? { signedOut: true } : {}) };
    };
    const t = await rig({ data, hub, approval: approved.path, readQuota });
    await t.call("POST", "/profiles/cx/quota");
    await settle();
    assert.ok(signals.recheck);
    phase = "pending";
    const old = signals.recheck("cx");
    await oldStarted;
    await t.call("POST", "/profiles/cx/login");
    await waitFor(t, "cx", "needs_approval");
    phase = "offline";
    await approved.approve();
    await waitFor(t, "cx", "done");
    releaseOld();
    await old;
    await until(() => t.accounts.health("cx").quota?.detail === "offline", "the new login's allowance read");
    assert.equal(t.accounts.health("cx").check.state, "ok");
    await t.close();
  });

  test("an OpenAI reset keeps its redemption key and reads the allowance again even without a reset", async () => {
    const keys: string[] = [];
    const quota = { n: 0 };
    const t = await rig({
      quota,
      resetQuota: async (p, key) => {
        assert.equal(p.id, "cx");
        keys.push(key);
        return { outcome: ({ empty: "noCredit", unused: "nothingToReset", again: "alreadyRedeemed", odd: "what" } as Record<string, string>)[key] ?? "reset" };
      },
    });
    await t.call("PUT", "/profiles/cx", { access: { kind: "subscription" } });
    const redeem = async (id: string, key: string) => (await t.call("POST", `/profiles/${id}/reset-quota`, undefined, owner, { "Idempotency-Key": key }))[0];
    assert.deepEqual(await t.call("POST", "/profiles/cx/reset-quota"), [400, { error: "reset requires an idempotency key" }]);
    assert.equal(await redeem("cc", "wrong-provider"), 400);
    assert.equal(await redeem("cx", "one"), 200);
    assert.deepEqual(keys, ["one"]);
    assert.equal(await redeem("cx", "again"), 200);
    assert.equal(await redeem("cx", "empty"), 409);
    assert.equal(await redeem("cx", "unused"), 409);
    assert.equal(await redeem("cx", "odd"), 502);
    assert.equal(await redeem("nope", "x"), 404);
    assert.ok(quota.n >= 4);
    await t.close();
  });

  test("a Claude subscription's limit reset is used as the installed Claude Code uses it, and wakes its account", async () => {
    const woke: string[] = [];
    let grantLeft = 1;
    const p = await provider((asked) => {
      if (asked.url.startsWith("/api/oauth/usage")) {
        return { status: 200, body: {
          seven_day: { utilization: 100, resets_at: null },
          juniper_tide: { eligible: false, ineligible_reason: "not_at_wall", arm: null, available: false },
          cedar_ember: { eligible: true, grants: [{ id: "launch-fable", resets_total: 1, resets_left: grantLeft, ends_at: "2027-03-09T07:59:00+00:00", paused: false, usable_now: true }], next_grant_id: grantLeft > 0 ? "launch-fable" : null },
        } };
      }
      if (asked.url === "/api/oauth/profile") return { status: 200, body: { organization: { uuid: "0f0e-org" } } };
      if (asked.url === "/api/organizations/0f0e-org/reset_rate_limits") {
        const result = grantLeft > 0 ? "reset" : "already_used";
        grantLeft = 0;
        return { status: 200, body: { result, resets_left: 0 } };
      }
      return { status: 404, body: {} };
    });
    const t = await rig({
      urls: { ...URLS, anthropic: p.base },
      claudeVersion: "2.1.321",
      ownReset: true,
      hub: { accounts: { setHealth: () => {}, healthOf: () => ({}) }, allowanceReset: async (id) => { woke.push(id); } },
      readQuota: async () => ({ state: "ok", windows: [{ label: "每周", usedPercent: grantLeft > 0 ? 100 : 3, resetsAt: null }], detail: null, checkedAt: 0 }),
    });
    await t.call("PUT", "/profiles/cc", { access: { kind: "subscription" } });
    mkdirSync(join(t.data, "homes/cc"), { recursive: true });
    writeFileSync(join(t.data, "homes/cc/.credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "claude-token", refreshToken: "r", expiresAt: Date.now() + 86_400_000 } }));
    const redeem = (key: string, reset?: string) => t.call("POST", "/profiles/cc/reset-quota", reset !== undefined ? { reset } : undefined, owner, { "Idempotency-Key": key });
    // A kind it holds none of: nothing claimed.
    assert.equal((await redeem("weekly", "weekly"))[0], 409);
    assert.equal(p.asked.filter((a) => a.method === "POST").length, 0);
    assert.deepEqual(await redeem("first", "full"), [200, { outcome: "reset" }]);
    const claim = p.asked.find((a) => a.method === "POST")!;
    assert.deepEqual(claim.body, { program: "cedar_ember", grant_id: "launch-fable", request_id: createHash("sha256").update("first").digest("hex") });
    assert.equal(claim.headers.authorization, "Bearer claude-token");
    assert.equal(claim.headers["user-agent"], "claude-cli/2.1.321 (external, cli)");
    assert.deepEqual(woke, ["cc"]);
    // None left now: said so, nothing claimed.
    const claims = p.asked.filter((a) => a.method === "POST").length;
    assert.equal((await redeem("second"))[0], 409);
    assert.equal(p.asked.filter((a) => a.method === "POST").length, claims);
    await t.close();
    await p.close();
  });

  test("without an installed Claude Code a Claude subscription's reset is not asked", async () => {
    const p = await provider(() => ({ status: 500, body: {} }));
    const t = await rig({ urls: { ...URLS, anthropic: p.base }, ownReset: true, readQuota: async () => ({ state: "ok", windows: [], detail: null, checkedAt: 0 }) });
    await t.call("PUT", "/profiles/cc", { access: { kind: "subscription" } });
    assert.equal((await t.call("POST", "/profiles/cc/reset-quota", undefined, owner, { "Idempotency-Key": "k" }))[0], 503);
    assert.equal(p.asked.length, 0);
    await t.close();
    await p.close();
  });

  test("a successful reset wakes its account and informs its share; an old redemption with no allowance does neither", async () => {
    const woke: string[] = [];
    const sent: string[] = [];
    let used = 100;
    const hub: NonNullable<AccountsDeps["hub"]> = {
      accounts: { setHealth: () => {}, healthOf: () => ({}) },
      allowanceReset: async (id) => { woke.push(id); },
    };
    const t = await rig({
      hub,
      readQuota: async () => ({ state: "ok", windows: [{ label: "week", usedPercent: used, resetsAt: null }], detail: null, checkedAt: 0 }),
      resetQuota: async (_p, key) => {
        if (key === "new") { used = 5; return { outcome: "reset" }; }
        return { outcome: key === "old" ? "alreadyRedeemed" : "noCredit" };
      },
      shared: { status: async () => ({ check: null, quota: null }), view: () => null, quotaReset: async (p, key) => { sent.push(`${p.id}:${key}`); } },
    });
    await t.call("PUT", "/profiles/cx", { access: { kind: "subscription" } });
    const redeem = (key: string) => t.call("POST", "/profiles/cx/reset-quota", undefined, owner, { "Idempotency-Key": key });
    assert.equal((await redeem("empty"))[0], 409);
    assert.equal((await redeem("old"))[0], 200);
    assert.deepEqual(woke, []);
    assert.equal((await redeem("new"))[0], 200);
    await until(() => sent.length === 1, "the reset is shared");
    assert.deepEqual(woke, ["cx"]);
    assert.deepEqual(sent, ["cx:new"]);
    await t.close();
  });

  test("a changed shared Codex login is fetched and loaded even when the old token has not expired", async () => {
    const data = temp("borrowed-changed");
    const home = join(data, "homes", "bx");
    mkdirSync(home, { recursive: true });
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
    const jwt = (name: string) => ["{}", JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 86400, name }), "s"].map((x) => Buffer.from(x).toString("base64url")).join(".");
    const old = jwt("old"), fresh = jwt("fresh");
    const write = (token: string) => writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: token, account_id: "acct" } }));
    write(old);
    const chatgpt = await provider((asked) => asked.headers.authorization === `Bearer ${fresh}`
      ? { status: 200, body: { rate_limit: { primary_window: { used_percent: 20 } } } }
      : { status: 401, body: { error: { code: "token_revoked" } } });
    const woke: string[] = [];
    let replaced = 0;
    let failReload = true;
    const hub: NonNullable<AccountsDeps["hub"]> = { accounts: { setHealth: () => {}, healthOf: () => ({}) }, allowanceReset: async (id) => { woke.push(id); } };
    const shared = {
      status: async () => ({ check: { state: "ok", detail: "host", models: null, checkedAt: 1 }, quota: null }),
      lendCodex: async (_profile: any, noFallback: boolean) => { assert.equal(noFallback, true); write(fresh); return Date.now() + 86400_000; },
      view: () => null,
    };
    const codex = () => ({ rateLimits: async () => ({}), resetQuota: async () => ({}), models: async () => ({ models: [], efforts: new Map() }), loginChanged: async () => { replaced++; if (failReload) { failReload = false; throw new Error("reload failed"); } } });
    const t = await rig({ data, shared, codex, hub, urls: { ...URLS, chatgpt: chatgpt.base } });
    await assert.rejects(t.accounts.sharedChanged("bx", true), /reload failed/);
    await t.accounts.sharedChanged("bx", true);
    assert.equal(JSON.parse(readFileSync(join(home, "auth.json"), "utf8")).tokens.access_token, fresh);
    assert.equal(replaced, 2, "a failed reload is retried even though the new file was already written");
    assert.equal(t.accounts.health("bx").quota.windows[0].usedPercent, 20);
    assert.deepEqual(woke, ["bx"]);
    await t.accounts.sharedChanged("bx", false);
    assert.equal(replaced, 2, "a quota or profile update with the same login does not restart a running app-server");
    await chatgpt.close();
    await t.close();
  });

  test("a copy of another station's profile is paused and used again here, nothing else of it edited here", async () => {
    const data = temp("borrowed-paused");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
    const moved: string[] = [];
    const shared = { status: async () => ({ check: { state: "ok", detail: "host", models: null, checkedAt: 1 }, quota: null }), view: () => ({ id: "s1", role: "user", host: "H", allow: null, reachable: true, pausable: true as const }) };
    const t = await rig({ data, shared, hub: { accounts: { setHealth: () => {}, healthOf: () => ({}) }, profileGone: async (id) => { moved.push(id); } } });
    try {
      assert.equal(t.view("bx")!.enabled, true);
      assert.equal((await t.call("PUT", "/profiles/bx", { name: "Mine" }))[0], 409, "a copy is edited on its host");
      assert.equal((await t.call("PUT", "/profiles/bx", { enabled: false, name: "Mine" }))[0], 409);
      assert.equal((await t.call("PUT", "/profiles/bx", { enabled: false }))[0], 200);
      assert.equal(t.view("bx")!.enabled, false);
      assert.deepEqual(moved, ["bx"], "its sessions here move off it");
      assert.equal((t.profile("bx") as any).share.paused, true);
      assert.equal((await t.call("PUT", "/profiles/bx", { enabled: false }))[0], 200);
      assert.deepEqual(moved, ["bx"], "paused already: nothing moves again");
      assert.equal((await t.call("PUT", "/profiles/bx", { enabled: true }))[0], 200);
      assert.equal(t.view("bx")!.enabled, true);
      assert.equal((t.profile("bx") as any).share.paused, undefined);
      assert.notEqual(t.profile("bx")!.enabled, false);
    } finally { await t.close(); }
  });

  test("a copy its host disabled stays disabled as it is used again here, said so or placed before that was said", async () => {
    // (`hostOff` is written as a copy is placed; one placed before it was, disabled, its host disabled: nothing else did)
    for (const share of [{ id: "s1", borrowed: true, host: "H", hostOff: true }, { id: "s1", borrowed: true, host: "H" }]) {
      const data = temp("borrowed-host-off");
      writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, enabled: false, share }], connects: [] }));
      const shared = { status: async () => ({ check: { state: "ok", detail: "host", models: null, checkedAt: 1 }, quota: null }), view: () => null };
      const t = await rig({ data, shared });
      try {
        assert.equal((await t.call("PUT", "/profiles/bx", { enabled: true }))[0], 200);
        assert.equal(t.view("bx")!.enabled, false, `its host disabled it (${JSON.stringify(share)}): using it again is the host's to say`);
        assert.equal((await t.call("PUT", "/profiles/bx", { enabled: false }))[0], 200);
        assert.equal((t.profile("bx") as any).share.paused, true);
        assert.equal(t.view("bx")!.enabled, false);
        assert.equal((await t.call("PUT", "/profiles/bx", { enabled: true }))[0], 200);
        assert.equal(t.view("bx")!.enabled, false, "paused here and ended: still its host's disabling");
      } finally { await t.close(); }
    }
  });

  test("a shared Codex host signing out updates the borrowed check even when there is no login to lend", async () => {
    const data = temp("borrowed-signed-out");
    writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
    const shared = {
      status: async () => ({ check: { state: "login", detail: "signed out", models: null, checkedAt: 1 }, quota: null }),
      lendCodex: async () => { throw new Error("no login to lend"); },
      view: () => null,
    };
    const t = await rig({ data, shared });
    await assert.rejects(t.accounts.sharedChanged("bx", false), /no login to lend/);
    assert.equal(t.accounts.health("bx").check.state, "login");
    await t.close();
  });

  test("OpenAI fast defaults off, survives other edits and can be turned off", async () => {
    const t = await rig();
    assert.equal(t.profile("cx")!.fast, undefined);
    assert.equal(t.view("cx")!.fast, null, "only a ChatGPT subscription has it");
    assert.equal((await t.call("PUT", "/profiles/cx", { fast: true, access: { kind: "subscription" } }))[0], 200);
    assert.equal(t.profile("cx")!.fast, true);
    await t.call("PUT", "/profiles/cx", { name: "OpenAI" });
    assert.equal(t.view("cx")!.fast, true);
    await t.call("PUT", "/profiles/cx", { fast: false });
    assert.equal(t.view("cx")!.fast, false);
    assert.deepEqual(await t.call("PUT", "/profiles/cx", { fast: "yes" }), [400, { error: "fast must be a boolean" }]);
    await t.close();
  });

  test("an Anthropic key on Claude Code has a Fast default too; a Claude Code profile on its own variables does not", async () => {
    const t = await rig();
    assert.equal(t.view("cc")!.fast, null);
    assert.equal((await t.call("PUT", "/profiles/cc", { fast: true, access: { kind: "anthropic-api", key: "sk-ant-1" } }))[0], 200);
    assert.equal(t.view("cc")!.fast, true);
    await t.call("PUT", "/profiles/cc", { fast: false });
    assert.equal(t.view("cc")!.fast, false);
    await t.close();
  });

  test("a Claude subscription has a Fast default only while its allowance says its usage credits are on", async () => {
    let extraUsage: boolean | undefined;
    const t = await rig({ readQuota: async () => ({ state: "ok", windows: [], detail: null, checkedAt: 0, ...(extraUsage === undefined ? {} : { extraUsage }) }) });
    assert.equal((await t.call("PUT", "/profiles/cc", { fast: true, access: { kind: "subscription" } }))[0], 200);
    assert.equal(t.view("cc")!.fast, null, "not known yet");
    extraUsage = false;
    await t.call("POST", "/profiles/cc/quota");
    assert.equal(t.view("cc")!.fast, null, "credits off");
    extraUsage = true;
    await t.call("POST", "/profiles/cc/quota");
    assert.equal(t.view("cc")!.fast, true);
    await t.close();
  });

  test("the automatic decisions use a model a profile verified, set by a workspace manager", async () => {
    const t = await rig({
      discover: async (profile) =>
        (profile.access as any)?.provider === "groq"
          ? { state: "ready", detail: "", model: "qwen3.8-flash", provider: "chat_logprobs", models: ["qwen3.8-flash"], fingerprint: fingerprint(profile) }
          : { state: "unsupported", detail: "", model: null, provider: null, models: [], fingerprint: fingerprint(profile) },
    });
    assert.deepEqual(await t.call("PUT", "/automatic-decisions", { completion: { enabled: true, model: "qwen3.8-flash" } }, member), [403, { error: "只有 workspace 管理员能配置自动决策" }]);
    assert.deepEqual(await t.call("POST", "/automatic-decisions/refresh", undefined, member), [403, { error: "只有 workspace 管理员能刷新决策模型" }]);
    assert.deepEqual(await t.call("PUT", "/automatic-decisions", { completion: { enabled: true, model: "qwen3.8-flash" } }), [400, { error: "请选择现有 Profile 中已验证可用的决策模型" }]);
    assert.deepEqual(await t.call("PUT", "/automatic-decisions", { completion: { enabled: "yes" } }), [400, { error: "自动决策配置格式不正确" }]);
    assert.equal((await t.call("POST", "/profiles", { access: { kind: "api-provider", provider: "groq", key: "gsk-123456" } }))[0], 200);
    // What the decisions can use is found after the profile is made.
    await until(() => t.accounts.decisionModels().length > 0, "the decision model found");
    assert.deepEqual(t.accounts.decisionModels(), [{ id: "qwen3.8-flash", name: "Qwen3.8 Flash", profiles: ["Groq"] }]);
    const [status, overview] = await t.call("PUT", "/automatic-decisions", { completion: { enabled: true, model: "qwen3.8-flash" } });
    assert.equal(status, 200);
    assert.deepEqual(overview.automaticDecisions.settings, { completion: { enabled: true, model: "qwen3.8-flash" } });
    assert.deepEqual(t.config.raw().automaticDecisions, { completion: { enabled: true, model: "qwen3.8-flash" } });
    assert.deepEqual(t.accounts.automaticDecisionsView(member), { canEdit: false, settings: {}, models: [], recent: [] });
    // The view hides what the capability was found for; an edited profile waits for its next check.
    assert.equal(t.view("groq")!.check.decision.fingerprint, undefined);
    await t.call("PUT", "/profiles/groq", { models: ["other"] });
    const decision = t.view("groq")!.check.decision;
    assert.ok(decision.state === "pending" || decision.state === "ready", JSON.stringify(decision));
    assert.equal((await t.call("POST", "/automatic-decisions/refresh"))[0], 200);
    assert.equal((await t.call("PUT", "/profiles/groq", { enabled: false }))[0], 200);
    assert.deepEqual(t.accounts.decisionModels(), [], "a disabled key is not offered for automatic decisions");
    assert.equal((await t.call("POST", "/automatic-decisions/refresh"))[0], 200, "refresh skips it");
    assert.equal((await t.call("PUT", "/profiles/groq", { enabled: true }))[0], 200);
    await until(() => t.accounts.decisionModels().length > 0, "the re-enabled key can decide again");
    await t.close();
  });

  test("a review request reports when its rule was turned off while old checks were being prepared", async () => {
    const entered = Promise.withResolvers<void>(), ready = Promise.withResolvers<number | null>();
    const t = await rig({ review: () => { entered.resolve(); return ready.promise; } });
    try {
      t.config.update((raw) => { raw.automaticDecisions = { completion: { enabled: true, model: null } }; });
      const response = t.call("POST", "/automatic-decisions/review");
      await entered.promise;
      t.config.update((raw) => { raw.automaticDecisions.completion.enabled = false; });
      ready.resolve(null);
      assert.deepEqual(await response, [409, { error: tr("zh", "station.decisions.enableFirst") }]);
    } finally { ready.resolve(null); await t.close(); }
  });

  test("automatic archiving is for a workspace manager to change", async () => {
    const t = await rig();
    assert.deepEqual(await t.call("PUT", "/archiving", { days: 2, slackDays: 3, reviewed: true }, member), [403, { error: "只有 workspace 管理员能修改自动归档" }]);
    assert.deepEqual(await t.call("PUT", "/archiving", { days: -1, slackDays: 3, reviewed: true }), [400, { error: "自动归档的设置不正确：天数要在 0 到 365 之间" }]);
    assert.deepEqual(await t.call("PUT", "/archiving", { days: 2, slackDays: 3 }), [400, { error: "自动归档的设置不正确：天数要在 0 到 365 之间" }]);
    assert.equal((await t.call("PUT", "/archiving", { days: 2, slackDays: 5, reviewed: true }))[0], 200);
    assert.deepEqual([t.config.raw().autoArchiveDays, t.config.raw().slackArchiveDays, t.config.raw().autoArchiveReviewed], [2, 5, true]);
    await t.close();
  });

  test("the archive policy page: its options with the chats last put there, who changed it, and edits by managers", async () => {
    const store = Store.open(":memory:", null);
    store.insertSession({ key: "titled", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/a", token: "t", createdAt: 1, lastActiveAt: 1 });
    store.insertSession({ key: "loose", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/b", token: "t2", createdAt: 1, lastActiveAt: 1 });
    store.insertSession({ key: "old", connect: "ds", runtime: "claude", profile: "cc", workspace: "/w/c", token: "t3", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
    store.joinThread(thread.id, "titled", "ds");
    store.setThreadTitle(thread.id, "修登录页");
    const result = (selected: string) => ({ selected, probabilities: { [selected]: 1 }, model: "m", source: "native", retainedMass: 1 });
    const base = { purpose: "archive", version: 3, model: "m", threshold: 0.9, elapsedMs: 1 };
    store.recordDecision("titled", { ...base, accepted: false, option: { id: "awaiting_review", name: "等人看结果", archive: false }, result: result("awaiting_review") });
    store.recordDecision("titled", { ...base, accepted: true, option: { id: "landed", name: "已落地", archive: true }, result: result("landed") });
    store.recordDecision("loose", { ...base, accepted: false, result: null, error: "timeout" });
    store.recordDecision("old", { ...base, version: 2, accepted: true, result: result("complete") });
    const t = await rig({ store });
    const view = t.accounts.automaticDecisionsView(owner);
    // Pages from before the policy list the checks one by one.
    assert.deepEqual(view.recent.map((r: any) => [r.title, r.label]), [["old", "已做完 · 推荐归档"], ["loose", "检查失败"], ["修登录页", "已落地 · 推荐归档"], ["修登录页", "等人看结果 · 不推荐"]]);
    const policy = view.policy;
    assert.equal(policy.text, DEFAULT_POLICY.policy);
    assert.equal(policy.edited, false);
    assert.equal(policy.change, null);
    assert.deepEqual([policy.checked, policy.failed], [3, 1]);
    // Each chat counted once, by its latest check.
    const landed = policy.options.find((o: any) => o.id === "landed");
    assert.equal(landed.count, 1);
    assert.deepEqual(landed.chats.map((c: any) => [c.title, c.recommended]), [["修登录页", true]]);
    assert.equal(policy.options.find((o: any) => o.id === "awaiting_review").count, 0);
    // Changed by a manager: kept by who, with what changed; a member is refused, and so is a policy that cannot be.
    const options = DEFAULT_POLICY.options.filter((o) => o.id !== "uncertain");
    assert.deepEqual(await t.call("PUT", "/automatic-decisions/policy", { policy: "x", options }, member), [403, { error: "只有 workspace 管理员能改归档策略" }]);
    assert.deepEqual(await t.call("PUT", "/automatic-decisions/policy", { policy: "x", options: options.map((o) => ({ ...o, archive: true })) }), [400, { error: "至少要有一个不推荐的选项" }]);
    const [status, overview] = await t.call("PUT", "/automatic-decisions/policy", { policy: "只看用户最初要的东西", options });
    assert.equal(status, 200);
    const after = overview.automaticDecisions.policy;
    assert.equal(after.text, "只看用户最初要的东西");
    assert.equal(after.options.length, DEFAULT_POLICY.options.length - 1);
    assert.deepEqual(after.change.by, { kind: "person", email: "owner@example.com", name: null });
    assert.equal(after.change.summary, "改了策略，删了「看不出来」");
    await t.close();
  });
});

// These await a local provider. Start them after the concurrent route rigs have finished opening their stores,
// so synchronous fixture setup cannot consume their timeout before the provider can answer.
test("an older host's fresh reset count gets its missing expiry details through the borrowed login", { timeout: 10_000 }, async () => {
  const data = temp("borrowed-reset-expiries");
  const home = join(data, "homes", "bx");
  mkdirSync(home, { recursive: true });
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
  const jwt = ["{}", JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 86400 }), "s"].map((x) => Buffer.from(x).toString("base64url")).join(".");
  let lent = 0;
  const expiries = ["2030-03-17T00:00:00Z", "2030-03-19T00:00:00Z"];
  let count = 2;
  const chatgpt = await provider((request) => request.url.endsWith("/usage")
    ? { status: 200, body: { rate_limit_reset_credits: { available_count: count }, rate_limit: { primary_window: { used_percent: 40 } } } }
    : { status: 200, body: { available_count: count, credits: expiries.slice(0, count).map((expires_at) => ({ status: "available", expires_at })) } });
  const shared = {
    status: async () => ({ check: { state: "ok", detail: "host", models: null, checkedAt: 1 }, quota: { state: "ok", windows: [], resetCount: count, detail: null, checkedAt: Date.now() + 60_000 } }),
    lendCodex: async () => {
      lent++;
      writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: jwt, account_id: "acct" } }));
      return Date.now() + 86_400_000;
    },
    view: () => null,
  };
  const t = await rig({ data, shared, readQuota: async () => ({ state: "unavailable", windows: [], detail: null, checkedAt: 0 }), urls: { ...URLS, chatgpt: chatgpt.base } });
  await t.call("POST", "/profiles/bx/check");
  await upon((wake) => t.accounts.onChange(wake), () => t.view("bx")?.quota?.resetExpiries?.length === 2, "both reset expiries read");
  assert.deepEqual(t.view("bx")!.quota.resetExpiries, expiries.map(Date.parse));
  assert.equal(lent, 1, "a login is borrowed when one is not yet here");
  assert.equal(chatgpt.asked[1]!.headers["chatgpt-account-id"], "acct");
  // A newer-looking summary from the older host must not erase the recent detailed reading.
  await t.call("POST", "/profiles/bx/check");
  assert.deepEqual(t.view("bx")!.quota.resetExpiries, expiries.map(Date.parse));
  // A changed count is a new set of credits; fetch its own details rather than reuse the old ones.
  count = 1;
  await t.call("POST", "/profiles/bx/check");
  await upon((wake) => t.accounts.onChange(wake), () => t.view("bx")?.quota?.resetExpiries?.length === 1, "the changed reset count read");
  assert.deepEqual(t.view("bx")!.quota.resetExpiries, [Date.parse(expiries[0]!)]);
  await chatgpt.close();
  await t.close();
});

test("missing reset details are retried on a later quota round, not in a loop", { timeout: 10_000 }, async () => {
  const data = temp("borrowed-reset-retry");
  const home = join(data, "homes", "bx");
  mkdirSync(home, { recursive: true });
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "bx", runtime: "codex", home: "homes/bx", access: { kind: "subscription" }, share: { id: "s1", borrowed: true, host: "H" } }], connects: [] }));
  const jwt = ["{}", JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 86400 }), "s"].map((x) => Buffer.from(x).toString("base64url")).join(".");
  writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { access_token: jwt } }));
  let detailsAvailable = false;
  const chatgpt = await provider((request) => request.url.endsWith("/usage")
    ? { status: 200, body: { rate_limit_reset_credits: { available_count: 1 } } }
    : detailsAvailable ? { status: 200, body: { credits: [{ status: "available", expires_at: "2030-03-17T00:00:00Z" }] } } : { status: 503, body: {} });
  const time = testClock();
  const shared = {
    status: async () => ({ check: { state: "ok", detail: "host", models: null, checkedAt: 1 }, quota: { state: "ok", windows: [], resetCount: 1, detail: null, checkedAt: 1 } }),
    view: () => null,
  };
  const t = await rig({ data, shared, clock: time.clock, readQuota: async () => ({ state: "unavailable", windows: [], detail: null, checkedAt: 0 }), urls: { ...URLS, chatgpt: chatgpt.base } });
  await t.call("POST", "/profiles/bx/check");
  await upon((wake) => t.accounts.onChange(wake), () => chatgpt.asked.length === 2 && t.view("bx")?.quota?.checkedAt !== 1, "the first detail request finished");
  assert.equal(t.view("bx")!.quota.resetCount, 1);
  assert.equal(t.view("bx")!.quota.resetExpiries, undefined);
  await t.call("POST", "/profiles/bx/check");
  await settle();
  assert.equal(chatgpt.asked.length, 2, "another check does not immediately retry the unavailable details");
  detailsAvailable = true;
  await time.adjust(5 * 60_000);
  t.accounts.followed();
  await upon((wake) => t.accounts.onChange(wake), () => t.view("bx")?.quota?.resetExpiries?.length === 1, "the next quota round read the expiry");
  assert.deepEqual(t.view("bx")!.quota.resetExpiries, [Date.parse("2030-03-17T00:00:00Z")]);
  await chatgpt.close();
  await t.close();
});

test("an overview names only the visible chats once when it makes the archive policy", async () => {
  const t = await rig();
  try {
    for (const [key, ws] of [["b1", "B"], ["b2", "B"], ["w", "W"]] as const) {
      t.store.insertSession({ key, ws, connect: "ds", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
      const older = t.store.openThread("slack", "C", `${key}-older`, null, null);
      t.store.joinThread(older.id, key, "ds");
      const thread = t.store.openThread(`chat:${key}`, key, key, null, null);
      t.store.joinThread(thread.id, key, "ds");
      t.store.setThreadTitle(thread.id, `title-${key}`);
    }
    const decision = { purpose: "archive", accepted: true, result: { selected: "landed" } };
    t.store.recordDecision("b1", decision);
    for (let i = 0; i < 30; i++) t.store.recordDecision("w", decision);
    t.store.recordDecision("b2", decision);
    t.store.setArchivePolicy(DEFAULT_POLICY, { kind: "agent", session: "b2" }, "edit", "B");

    const named: string[] = [];
    let policies = 0;
    let policyReads = 0;
    const sessionChat = t.store.sessionChat.bind(t.store);
    const latest = t.store.latestDecisionsSince.bind(t.store);
    const archivePolicy = t.store.archivePolicy.bind(t.store);
    t.store.sessionChat = (session) => {
      assert.equal(sessionChatReady(t.store.db, session), true, "the name is read only after preparation");
      named.push(session);
      return sessionChat(session);
    };
    t.store.latestDecisionsSince = (since) => { policies++; return latest(since); };
    t.store.archivePolicy = (ws) => { policyReads++; return archivePolicy(ws); };
    const prepared: string[][] = [];
    const hub: any = { processes: () => new Map(), config: () => ({ dataDir: t.data }),
      prepareSessionChatNames: async (sessions: string[]) => {
        prepared.push([...sessions]);
        const work = new SessionChatPreparation();
        for (const session of sessions) while (!work.step(t.store.db, session).done) {}
      } };
    const cloud: any = { state: null };
    const of = async (as: typeof joined) => (await overview({ store: t.store, hub, cloud, config: () => t.config.raw(), accounts: t.accounts }, as, "en") as any).automaticDecisions;
    const joined = { ...owner, workspace: "B", home: false };
    const view = await of(joined);
    assert.deepEqual(view.recent.map((r: any) => [r.session, r.title]), [["b2", "title-b2"]], "the global latest 30 checks are filtered to this workspace");
    assert.deepEqual([view.policy.checked, view.policy.failed, view.canEditPolicy], [2, 0, true]);
    assert.deepEqual(view.policy.options.find((o: any) => o.id === "landed").chats.map((c: any) => c.title).sort(), ["title-b1", "title-b2"]);
    assert.equal(view.policy.change.by.title, "title-b2");
    assert.equal(policies, 1, "only the policy being returned is read");
    assert.equal(policyReads, 1, "the policy and its change come from one read");
    assert.deepEqual(named.sort(), ["b1", "b2"], "invisible chats are not named, and each visible chat is named once");
    assert.deepEqual(prepared.map((sessions) => sessions.sort()), [["b1", "b2"]]);
    named.length = 0;
    policies = 0;
    policyReads = 0;
    const again = await of(joined);
    assert.deepEqual(again, view);
    assert.deepEqual([policies, named], [0, []], "a repeated overview reuses its view");
    assert.equal(policyReads, 0);
    const homeView = await of({ ...joined, workspace: "W", home: true });
    assert.equal(homeView.recent.length, 29);
    assert.ok(homeView.recent.every((r: any) => r.session === "w" && r.title === "title-w"));
    assert.deepEqual([homeView.policy.checked, homeView.policy.failed], [1, 0]);
    assert.deepEqual([policies, named], [1, ["w"]], "the home workspace's checks use their own policy and names");
    assert.deepEqual(prepared.map((sessions) => sessions.sort()), [["b1", "b2"], ["w"]]);
    assert.equal(policyReads, 1);
    named.length = 0;
    policies = 0;
    const memberView = await of({ ...joined, role: "member" });
    assert.deepEqual(memberView, { canEdit: false, settings: {}, models: [], recent: [] });
    assert.deepEqual([policies, named], [0, []]);
  } finally {
    await t.close();
    t.store.close();
  }
});

test("a Hermes profile offers discovered models and keeps a manual selection when discovery fails", async () => {
  let fail = false;
  const r = await rig({ hermes: () => ({ models: async () => { if (fail) throw new Error("provider unavailable"); return ["openrouter:model-a", "custom:model-b"]; } }) });
  try {
    const [status, created] = await r.call("POST", "/profiles", {runtime:"hermes",access:{kind:"env"}});
    assert.equal(status,200);
    const id = created.id;
    await r.accounts.check(id);
    assert.deepEqual(r.view(id).check.models,["openrouter:model-a","custom:model-b"]);
    // every one discovered runs, the one named by hand first
    await r.accounts.putProfile(id,{addModel:"custom:model-b"},owner);
    assert.deepEqual(r.profile(id)?.named,["custom:model-b"]);
    assert.deepEqual(r.profile(id)?.models,["custom:model-b","openrouter:model-a"]);
    fail = true;
    const check = await r.accounts.check(id);
    assert.deepEqual(check.models,["openrouter:model-a","custom:model-b"]);
    assert.deepEqual(r.profile(id)?.models,["custom:model-b","openrouter:model-a"]);
    assert.match(check.detail,/provider unavailable/);
  } finally {await r.close();}
});
