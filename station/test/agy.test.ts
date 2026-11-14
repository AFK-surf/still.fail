import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { after, test } from "node:test";
import { AGY_FILE_TOKENS, AgyDriver, SESSIONS, agyAccountFile, agyKeychain, goKeyringValue, agyBaseModel, agyCatalog, agyConversations, agyEnv, agyHome, agyToken, agyVariant, classifyFailure, geminiDir } from "../src/agents/agy.ts";
import type { OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { profileRuntimes } from "../src/agents/profiles.ts";
import { Accounts, accountEmail, accountEmailSoon } from "../src/accounts/index.ts";
import { uncheckOutdated } from "../src/accounts/models.ts";
import { accessKinds, checkProfile, loginCommand } from "../src/accounts/profiles.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { checkQuota } from "../src/accounts/quota.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Accounts as SessionAccounts } from "../src/sessions/accounts.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Store } from "../src/store/store.ts";
import { tr } from "../src/ops/i18n.ts";
import { platform } from "../src/platform/index.ts";
import { transcriptPath, readTimeline, isPosting } from "../src/read/transcript.ts";
import { callsOf } from "../src/usage/counter.ts";
import { CHAT_CREATE } from "../src/tools/chat.ts";

const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "agy-") : "/tmp/agy-");
const drivers: AgyDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});
const fake = `${fileURLToPath(new URL("./fake", import.meta.url))}${delimiter}${process.env.PATH}`;
let n = 0;
function setup(env: Record<string, string> = {}) {
  const id = ++n;
  const dump = join(data, `dump-${id}`);
  const options: OpenOptions = {
    key: `agy-test-${id}`,
    profile: { id: "ag", runtime: "agy", home: join(data, `home-${id}`), access: { kind: "api-provider", provider: "google", key: "gemini-key" }, env: { PATH: fake, FAKE_DUMP: dump, ...env } },
    cwd: data, instructions: "Use chat_post to answer.", mcpToken: "test-token", mcpUrl: "http://127.0.0.1:12345/mcp", route: "test",
  };
  const events: RuntimeEvent[] = [];
  const driver = new AgyDriver({ data });
  drivers.push(driver);
  return { options, events, driver, dump };
}
async function until(f: () => boolean) {
  const end = Date.now() + 10_000;
  while (!f()) {
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 20));
  }
}
const ended = (events: RuntimeEvent[]) => events.filter((e) => e.type === "turnEnded");
const rpc = (dump: string) => readFileSync(dump + ".rpc", "utf8").trim().split("\n").map((s) => JSON.parse(s));

test("a Gemini key runs the Antigravity CLI in its profile's files, with the station's tools and instructions", async () => {
  const { options, events, driver, dump } = setup();
  const session = await driver.open({ ...options, model: "gemini-3.1-pro" }, (e) => events.push(e));
  const started = JSON.parse(readFileSync(dump, "utf8").trim().split("\n")[0]!);
  assert.deepEqual(started.args, ["acp", "--gemini-dir", geminiDir(options.profile.home), "--dangerously-skip-permissions", "--disable-telemetry"]);
  assert.equal(started.key, "gemini-key");
  assert.equal(started.updates, "1");
  const opened = rpc(dump).find((m) => m.method === "session/new").params;
  assert.equal(opened.mcpServers[0].headers[0].value, "Bearer test-token");
  assert.equal(opened._meta.antigravity.systemPrompt.append, "Use chat_post to answer.");
  assert.equal(rpc(dump).find((m) => m.method === "session/set_model").params.modelId, "gemini-3.1-pro");
  await session.prompt("hello");
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "completed" } });
  // What the person said goes as it is: the instructions are the system prompt's.
  assert.equal(rpc(dump).find((m) => m.method === "session/prompt").params.prompt[0].text, "hello");
  const path = transcriptPath("agy", options.profile.home, session.id());
  assert.ok(path);
  const lines = readFileSync(path, "utf8").trim().split("\n").map((s) => JSON.parse(s));
  assert.equal(lines.find((m) => m.type === "assistant").text, "first hello");
  assert.equal(lines.find((m) => m.type === "tool").result, "file contents");
  // The station's tool named as the others name it, from the title the CLI gives an MCP tool's call.
  assert.ok(isPosting(lines.filter((m) => m.type === "tool").at(-1).name));
  assert.ok(readTimeline("agy", path).length > 0);
  // The turn's counts, input apart from the cache's, thoughts with the output; the context it ended with.
  const calls = callsOf("agy", readFileSync(path, "utf8"), false, { model: null, codexId: null });
  assert.equal(calls.length, 1);
  assert.deepEqual([calls[0]!.input, calls[0]!.cacheRead, calls[0]!.output, calls[0]!.model, calls[0]!.context, calls[0]!.window], [1000, 200, 400, "gemini-3.1-pro", 5000, 1048576]);
  const id = session.id();
  await session.dispose();
  events.length = 0;
  const resumed = await driver.open({ ...options, resume: id }, (e) => events.push(e));
  assert.equal(resumed.id(), id);
  assert.equal(events.length, 0);
  assert.equal(rpc(dump).filter((m) => m.method === "session/load").at(-1).params._meta.antigravity.systemPrompt.append, "Use chat_post to answer.");
  await resumed.prompt("again");
  await until(() => ended(events).length === 1);
  assert.doesNotMatch(readFileSync(path, "utf8"), /past replay/);
  await resumed.dispose();
});

test("another model between turns is set in the running process; one it does not offer starts it again", async () => {
  const { options, events, driver, dump } = setup();
  const session = await driver.open(options, (e) => events.push(e));
  assert.equal(session.model, "gemini-3.5-flash");
  assert.equal(session.retune!({ ...options, model: "gemini-3.1-pro" }), true);
  assert.equal(session.retune!({ ...options, model: "not-offered" }), false);
  await session.prompt("hi");
  await until(() => ended(events).length === 1);
  assert.deepEqual(rpc(dump).filter((m) => m.method === "session/set_model").map((m) => m.params.modelId), ["gemini-3.1-pro"]);
  await session.dispose();
});

test("cancel, a signed-out account, an expired sign-in and a spent quota", async () => {
  const { options, events, driver } = setup();
  const s = await driver.open(options, (e) => events.push(e));
  assert.equal(await s.steer("idle"), false);
  await s.prompt("hold");
  assert.equal(await s.steer("hold-steer"), true);
  await s.abort();
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "aborted" } });
  assert.equal(await s.steer("idle"), false);
  await s.prompt("expired");
  await until(() => ended(events).length === 2);
  assert.equal((ended(events)[1] as any).outcome.reason, "auth");
  await s.prompt("quota");
  await until(() => ended(events).length === 3);
  assert.equal((ended(events)[2] as any).outcome.reason, "rate_limit");
  await s.dispose();
  const signedOut = setup({ FAKE_AGY_SIGNED_OUT: "1" });
  await assert.rejects(signedOut.driver.open(signedOut.options, () => {}), /Authentication required/);
  assert.equal(classifyFailure("Authentication required"), "auth");
});

test("steering mid-turn injects a prompt, completes once on the steered prompt, and keeps both prompts' usage", async () => {
  const { options, events, driver } = setup();
  const s = await driver.open({ ...options, model: "gemini-3.1-pro" }, (e) => events.push(e));
  await s.prompt("hold");
  await until(() => events.some((e) => e.type === "live" && e.event.kind === "delta" && e.event.text === "first "));
  assert.equal(await s.steer("follow up"), true);
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "completed" } });
  const path = transcriptPath("agy", options.profile.home, s.id())!;
  const entries = readFileSync(path, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(entries.filter((e) => e.type === "assistant").at(-1)?.text, "first follow up");
  assert.equal(entries.some((e) => e.type === "user" && e.text === "follow up"), true);
  const calls = callsOf("agy", readFileSync(path, "utf8"), false, { model: null, codexId: null });
  assert.equal(calls.length, 2);
  assert.deepEqual([calls[0]!.input, calls[0]!.output, calls[0]!.model], [500, 10, "gemini-3.1-pro"]);
  assert.deepEqual([calls[1]!.input, calls[1]!.cacheRead, calls[1]!.output, calls[1]!.model], [1000, 200, 400, "gemini-3.1-pro"]);
  await s.dispose();
});

test("models are read without a turn, the station's tools or a transcript", async () => {
  const { options, driver, dump } = setup();
  assert.deepEqual(await driver.models(options.profile), ["gemini-3.5-flash", "gemini-3.1-pro"]);
  const calls = rpc(dump);
  assert.deepEqual(calls.find((c) => c.method === "session/new").params.mcpServers, []);
  assert.equal(calls.some((c) => c.method === "session/prompt" || c.method === "session/set_model"), false);
  assert.equal(readFileSync(dump, "utf8").includes(options.mcpToken), false);
});

test("tiered subscription models normalize to base model + thinking levels, map (model, effort) to ACP modelId, and match legacy spellings", async () => {
  const { options, events, driver, dump } = setup({ FAKE_AGY_SUBSCRIPTION: "1" });
  const cat = await driver.catalog(options.profile);
  assert.deepEqual(cat, {
    models: ["gemini-4-carbon", "claude-opus-5-5", "gpt-oss-120b", "gemini-pro-orchestrator"],
    efforts: {
      "gemini-4-carbon": ["low", "medium", "high"],
      "claude-opus-5-5": ["low", "medium", "high"],
      "gpt-oss-120b": [],
      "gemini-pro-orchestrator": [],
    },
    defaults: { "gemini-4-carbon": "high", "claude-opus-5-5": "high" },
  });
  const medCat = agyCatalog(
    ["gemini-4-carbon-low", "gemini-4-carbon-medium", "gemini-4-carbon-high", "claude-opus-5-5-low", "claude-opus-5-5-high"],
    "gemini-4-carbon-medium",
  );
  assert.deepEqual(medCat.defaults, { "gemini-4-carbon": "medium", "claude-opus-5-5": "high" });
  assert.equal(agyVariant("gemini-4-carbon", undefined, ["gemini-4-carbon-low", "gemini-4-carbon-medium", "gemini-4-carbon-high"], "gemini-4-carbon-medium"), "gemini-4-carbon-medium");
  assert.equal(agyVariant("claude-opus-5-5", undefined, ["claude-opus-5-5-low", "claude-opus-5-5-high"], "gemini-4-carbon-medium"), "claude-opus-5-5-high");
  assert.deepEqual(agyBaseModel("claude-opus-5-5-medium"), { model: "claude-opus-5-5", effort: "medium" });
  assert.equal(agyVariant("gpt-oss-120b", undefined, ["gpt-oss-120b-medium"]), "gpt-oss-120b-medium");

  const session = await driver.open({ ...options, model: "gemini-4-carbon", effort: "medium" }, (e) => events.push(e));
  assert.equal(session.model, "gemini-4-carbon");
  assert.equal(session.currentModelId, "gemini-4-carbon-medium");
  assert.equal(session.retune!({ ...options, model: "gemini-4-carbon" }), true, "default effort returns to the CLI's defaultModelId");
  assert.equal(session.currentModelId, "gemini-4-carbon-high");
  assert.equal(session.retune!({ ...options, model: "gpt-oss-120b" }), true);
  await session.prompt("hi");
  await until(() => ended(events).length === 1);
  assert.deepEqual(
    rpc(dump).filter((m) => m.method === "session/set_model").map((m) => m.params.modelId),
    ["gemini-4-carbon-medium", "gemini-4-carbon-high", "gpt-oss-120b-medium"],
  );
  await session.dispose();

  const cfg = hubConfig(
    { profiles: [{ id: "ag", name: "AGY", runtime: "agy", home: "/h", access: { kind: "subscription" } }] },
    "/x",
    () => cat.models,
  );
  const p = cfg.profiles[0]!;
  assert.equal(p.models.includes("gemini-4-carbon"), true);
  const { spelling } = await import("../src/sessions/config.ts");
  assert.equal(spelling(p, "gemini-4-carbon-high"), "gemini-4-carbon");
  const { availableEfforts } = await import("../src/sessions/pool.ts");
  assert.deepEqual(availableEfforts("agy", "gemini-4-carbon-high", { agy: cat.efforts }), ["low", "medium", "high"]);
  const legacySessions = new Map<string, any>([
    ["s-legacy", { key: "s-legacy", runtime: "agy", profile: "ag", profilePinned: false, model: "gemini-4-carbon-high", effort: null }],
  ]);
  const legacyPool = new SessionAccounts({
    config: () => cfg,
    store: {
      getSession: (k: string) => legacySessions.get(k),
      setSessionProfile: () => {},
      lastTurn: () => ({ endedAt: 1000 }),
      recentlyCompacted: () => false,
      compactionsReady: () => false,
      lastContexts: () => [],
      compactionPoints: () => new Map(),
    } as never,
    running: () => [],
    clock: { currentTimeMillisUnsafe: () => 2000 } as never,
  });
  legacyPool.setHealth(() => ({
    check: { state: "ok", detail: "ok", models: cat.models, modelEfforts: { agy: cat.efforts }, checkedAt: 1500 },
  }));
  const patched = legacyPool.change("s-legacy", { effort: "low" }, "en");
  assert.equal(patched.effort, "low");
});

for (const crashed of [false, true]) {
  test(`taking up a running session ${crashed ? "after a crash" : "from a handover"} keeps its turn, configured model and catalog`, async () => {
    const { options, events, driver } = setup();
    const configured = { ...options, model: "gemini-3.1-pro" };
    const s = await driver.open(configured, (e) => events.push(e));
    await s.prompt("hold");
    await until(() => events.some((e) => e.type === "live" && e.event.kind === "delta" && e.event.text === "first "));
    const snapshot = crashed ? null : s.snapshot();
    s.detach();
    await allLeft();
    const next = new AgyDriver({ data });
    drivers.push(next);
    const later: RuntimeEvent[] = [];
    const adopted = await next.adopt(configured, snapshot, (e) => later.push(e));
    assert.equal(adopted.model, "gemini-3.1-pro");
    await adopted.abort();
    await until(() => ended(later).length === 1);
    assert.equal(ended(events).length, 0);
    await adopted.prompt("after");
    await until(() => ended(later).length === 2);
    const path = transcriptPath("agy", options.profile.home, adopted.id())!;
    const calls = callsOf("agy", readFileSync(path, "utf8"), false, { model: null, codexId: null });
    assert.equal(calls.at(-1)?.model, "gemini-3.1-pro");
    assert.equal(adopted.retune!({ ...options, model: "not-offered" }), false);
    assert.equal(adopted.retune!({ ...options, model: "gemini-3.5-flash" }), true);
    await adopted.dispose();
  });
}

test("which profiles run it, and none of the machine's Google accounts", (t) => {
  const { options } = setup();
  assert.deepEqual(accessKinds("agy"), ["subscription", "api-provider", "env"]);
  assert.ok(profileRuntimes({ id: "g", runtime: "dsh", home: "", access: { kind: "api-provider", provider: "google", key: "k" } }).includes("agy"));
  assert.ok(!profileRuntimes({ id: "x", runtime: "dsh", home: "", access: { kind: "api-provider", provider: "xai", key: "k" } }).includes("agy"));
  assert.ok(CHAT_CREATE.inputSchema.properties.runtime.enum.includes("agy"));
  const saved = { GEMINI_API_KEY: process.env.GEMINI_API_KEY, GOOGLE_APPLICATION_CREDENTIALS: process.env.GOOGLE_APPLICATION_CREDENTIALS };
  process.env.GEMINI_API_KEY = "machine-key";
  process.env.GOOGLE_APPLICATION_CREDENTIALS = "/machine/adc.json";
  t.after(() => {
    for (const [k, v] of Object.entries(saved)) if (v === undefined) delete process.env[k]; else process.env[k] = v;
  });
  const env = agyEnv(options);
  assert.equal(env.GEMINI_API_KEY, "gemini-key");
  assert.equal(env.ANTIGRAVITY_GEMINI_DIR, geminiDir(options.profile.home));
  assert.equal(env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
  const own = agyEnv({ ...options, profile: { ...options.profile, access: { kind: "env" }, env: {} } });
  assert.equal(own.GEMINI_API_KEY, undefined);
});

test("a Google account: signed in in its terminal interface (the way chosen, Google's page relayed, the code pasted back), in the profile's files; then checked, and its sessions run on it", { skip: process.platform === "win32" && "no terminal to sign in in" }, async () => {
  const home = join(data, "google");
  const dump = join(data, "google-dump");
  const env = { ...process.env, PATH: fake, FAKE_DUMP: dump, GEMINI_API_KEY: "machine-key", SSH_CONNECTION: "10.0.0.1 22 10.0.0.2 22" } as Record<string, string>;
  const logins = new LoginManager(data, { claude: "claude", codex: "codex", agy: "agy" }, () => env);
  const wait = async (state: LoginState) => until(() => logins.get("g")?.state === state);
  const check = () => checkProfile({ runtime: "agy", kind: "subscription", key: "", via: {}, home, env, machine: false, lang: "en" });
  try {
    assert.equal((await check()).state, "login");
    await logins.start({ id: "g", runtime: "agy", home }, "en");
    await wait("needs_code");
    assert.match(logins.get("g")!.url ?? "", /^https:\/\/accounts\.google\.com\/o\/oauth2\/auth\?.*redirect_uri=https%3A%2F%2Fantigravity\.google%2Foauth-callback/);
    const run = JSON.parse(readFileSync(dump, "utf8").trim().split("\n").at(-1)!);
    // Its HOME the profile's agy/ (so the sign-in lands in the ACP server's --gemini-dir), not a remote session's, none of
    // the machine's keys.
    assert.deepEqual([run.args, run.home, run.remote, run.key], [[], agyHome(home), null, null]);
    await logins.submitCode("g", " 4/0Ab-code ", "en");
    await wait("done");
    assert.equal(JSON.parse(readFileSync(agyToken(home), "utf8")).token.access_token, "ya29.4/0Ab-code");
    assert.equal(JSON.parse(readFileSync(agyAccountFile(home), "utf8")).email, "someone@gmail.com");
    assert.equal(agyToken(home), join(geminiDir(home), "antigravity-cli", "antigravity-oauth-token"));
    const signedIn = await check();
    assert.equal(signedIn.state, "ok");
    assert.match(signedIn.detail ?? "", /someone@gmail\.com/);
  } finally {
    await logins.close();
  }
  // A subscription profile's sessions are given no key: the sign-in in its files is what they run on.
  const { options, driver } = setup();
  const signed = { ...options, profile: { ...options.profile, home, access: { kind: "subscription" } } };
  assert.equal(agyEnv(signed).GEMINI_API_KEY, undefined);
  const s = await driver.open(signed, () => {});
  await s.dispose();
});

test("a Google account's sign-in: refused at once where there is no terminal; without a sign-in its allowance says signed out; its login command", async () => {
  const terminal = platform.terminal;
  platform.terminal = () => null;
  const logins = new LoginManager(data, { claude: "claude", codex: "codex", agy: "agy" });
  try {
    const job = await logins.start({ id: "nt", runtime: "agy", home: join(data, "no-terminal") }, "en");
    assert.deepEqual([job.state, job.error], ["failed", tr("en", "station.login.agyNoTerminal")]);
  } finally {
    platform.terminal = terminal;
    await logins.close();
  }
  const q = await checkQuota({ id: "p", runtime: "agy", home: join(data, "no-signin"), access: { kind: "subscription" } } as never, {}, undefined, undefined, "en");
  assert.deepEqual([q.state, q.detail], ["unavailable", tr("en", "station.quota.signInExpired")]);
  assert.equal(loginCommand("agy", "/h"), "HOME=/h/agy agy");
});

test("an Antigravity CLI account's Gemini and Claude / GPT windows weigh only on their own models in the pool", () => {
  const cfg = hubConfig(
    {
      profiles: [
        { id: "ag1", name: "AG1", runtime: "agy", home: "/h1", access: { kind: "subscription" }, model: "gemini-4-carbon-medium", models: ["gemini-4-carbon-medium", "claude-opus-5-5-medium"] },
        { id: "ag2", name: "AG2", runtime: "agy", home: "/h2", access: { kind: "subscription" }, model: "gemini-4-carbon-medium", models: ["gemini-4-carbon-medium", "claude-opus-5-5-medium"] },
      ],
    },
    "/x",
  );
  const sessions = new Map<string, any>([
    ["s-gemini", { key: "s-gemini", runtime: "agy", profile: "ag1", profilePinned: false, model: "gemini-4-carbon-medium", effort: null }],
    ["s-claude", { key: "s-claude", runtime: "agy", profile: "ag1", profilePinned: false, model: "claude-opus-5-5-medium", effort: null }],
  ]);
  const pool = new SessionAccounts({
    config: () => cfg,
    store: {
      getSession: (k: string) => sessions.get(k),
      setSessionProfile: (k: string, id: string, pinned: boolean) => {
        const s = sessions.get(k);
        if (s) {
          s.profile = id;
          s.profilePinned = pinned;
        }
      },
      lastTurn: () => ({ endedAt: 1000 }),
      recentlyCompacted: () => false,
      compactionsReady: () => false,
      lastContexts: () => [],
      compactionPoints: () => new Map(),
    } as never,
    running: () => [],
    clock: { currentTimeMillisUnsafe: () => 2000 } as never,
  });
  const ag1Quota = {
    state: "ok",
    checkedAt: 1500,
    windows: [
      { label: "5 小时 · Gemini", usedPercent: 15, resetsAt: 5000, scope: "gemini" },
      { label: "每周 · Gemini", usedPercent: 25, resetsAt: 9000, scope: "gemini" },
      { label: "5 小时 · Claude / GPT", usedPercent: 100, resetsAt: 6000, scope: "3p" },
      { label: "每周 · Claude / GPT", usedPercent: 40, resetsAt: 9000, scope: "3p" },
    ],
  };
  const ag2Quota = {
    state: "ok",
    checkedAt: 1500,
    windows: [
      { label: "5 小时 · Gemini", usedPercent: 100, resetsAt: 7000, scope: "gemini" },
      { label: "每周 · Gemini", usedPercent: 100, resetsAt: 8000, scope: "gemini" },
      { label: "5 小时 · Claude / GPT", usedPercent: 100, resetsAt: 8500, scope: "3p" },
      { label: "每周 · Claude / GPT", usedPercent: 50, resetsAt: 9000, scope: "3p" },
    ],
  };
  pool.setHealth((id) => ({
    check: { state: "ok", detail: "ok", models: ["gemini-4-carbon-medium", "claude-opus-5-5-medium"], checkedAt: 1500 },
    quota: id === "ag1" ? ag1Quota : ag2Quota,
  }));
  // Gemini on ag1 is still healthy even though ag1's Claude / GPT 5h window is at 100%.
  assert.equal(pool.runOn("s-gemini").id, "ag1");
  // Claude on ag1 sees only the 3P window (refills at 6000), while ag2's 3P window is also full (8500): stays on ag1 and refills at 6000.
  assert.equal(pool.refillsAt("s-claude"), 6000);
});

test("macOS keychain: `agy` is kept to the profile's file, and a sign-in it had moved into the machine's one keychain item is taken back only by the profile whose account it is", async () => {
  const dir = join(data, "keychain-accounts");
  mkdirSync(dir, { recursive: true });
  const unsignedHome = join(dir, "homes", "unsigned");
  const preExistingHome = join(dir, "homes", "preexisting");
  const notedHome = join(dir, "homes", "noted");
  const otherHome = join(dir, "homes", "other");
  const envHome = join(dir, "homes", "env");
  const apiHome = join(dir, "homes", "api");
  // `linkTranscripts` creates `agy/sessions` even before a profile has ever signed in.
  mkdirSync(join(agyHome(unsignedHome), SESSIONS), { recursive: true });
  mkdirSync(join(geminiDir(unsignedHome), "antigravity-cli"), { recursive: true });
  // A profile signed in before `account.json` existed, whose token file `agy acp` moved into the keychain: whose
  // account the item is cannot be told, so it signs in again.
  mkdirSync(agyConversations(preExistingHome), { recursive: true });
  writeFileSync(join(agyConversations(preExistingHome), "c1.db"), "db");
  // A profile signed in via station (noted email), then its token file moved into the keychain by `agy`.
  const token = JSON.stringify({ token: { access_token: "ya29.x" }, auth_method: "consumer", id_token_email: "someone@gmail.com" });
  mkdirSync(join(geminiDir(notedHome), "antigravity-cli"), { recursive: true });
  writeFileSync(agyToken(notedHome), token);
  // Another account's profile, its file moved too: the one item holds the account signed in last, not this one.
  mkdirSync(agyHome(otherHome), { recursive: true });
  writeFileSync(agyAccountFile(otherHome), JSON.stringify({ email: "other@gmail.com" }));

  const hadKeychain = platform.hasKeychain;
  const read = agyKeychain.read;
  platform.hasKeychain = true;
  let item: string | null = null;
  let reads = 0;
  agyKeychain.read = async () => {
    reads++;
    return item;
  };
  const store = Store.open(":memory:", null);
  const config = new ConfigFile(dir);
  config.update((raw) => {
    raw.profiles = [
      { id: "ag-u", name: "Unsigned", runtime: "agy", home: unsignedHome, access: { kind: "subscription" } },
      { id: "ag-p", name: "PreExisting", runtime: "agy", home: preExistingHome, access: { kind: "subscription" } },
      { id: "ag-n", name: "Noted", runtime: "agy", home: notedHome, access: { kind: "subscription" } },
      { id: "ag-o", name: "Other", runtime: "agy", home: otherHome, access: { kind: "subscription" } },
      { id: "ag-env", name: "Env", runtime: "agy", home: envHome, access: { kind: "env" } },
      { id: "ag-api", name: "Api", runtime: "agy", home: apiHome, access: { kind: "api-provider", provider: "google", key: "bad-key" } },
    ];
  });
  let driverMode: "ok" | "auth" | "crash" = "ok";
  let driverCalls = 0;
  const accounts = new Accounts({
    data: dir,
    store,
    config,
    machine: null,
    checkOnStart: false,
    check: (req, lang) =>
      req.kind === "api-provider"
        ? Promise.resolve({ state: "failed", detail: "Google refused the key (401)", models: null, checkedAt: 0 })
        : checkProfile({ ...req, env: {}, machine: false, lang }),
    quota: async () => ({ state: "ok", windows: [], detail: null, checkedAt: 0 }),
    agy: () =>
      ({
        models: async () => {
          driverCalls++;
          if (driverMode === "auth") throw new Error("Authentication required");
          if (driverMode === "crash") throw new Error("spawn agy ENOENT");
          return ["gemini-3.5-flash", "gemini-3.1-pro"];
        },
      }) as never,
  });
  try {
    // Its processes keep the sign-in in the file alone: never the keychain's one item for every profile.
    const { options } = setup();
    assert.equal(agyEnv(options).SSH_CLIENT, AGY_FILE_TOKENS.SSH_CLIENT);

    // 1. The first check notes the email; then `agy` (before) moved the file into the keychain, as go-keyring writes it.
    const first = await checkProfile({ runtime: "agy", kind: "subscription", key: "", via: {}, home: notedHome, env: {}, machine: false, lang: "en" });
    assert.equal(first.state, "ok");
    assert.match(first.detail, /someone@gmail\.com/);
    assert.equal(reads, 0, "a profile with its file reads no keychain");
    rmSync(agyToken(notedHome));
    item = `go-keyring-base64:${Buffer.from(token).toString("base64")}`;
    assert.equal(accountEmail("agy", notedHome), "someone@gmail.com");

    // 2. The item is this profile's account: taken back into its file, and it is signed in on it.
    const back = await checkProfile({ runtime: "agy", kind: "subscription", key: "", via: {}, home: notedHome, env: {}, machine: false, lang: "en" });
    assert.equal(back.state, "ok");
    assert.match(back.detail, /someone@gmail\.com/);
    assert.equal(readFileSync(agyToken(notedHome), "utf8"), token);

    // 3. The item is another account's: not taken, signed out (it ran on someone@'s quota before).
    const other = await checkProfile({ runtime: "agy", kind: "subscription", key: "", via: {}, home: otherHome, env: {}, machine: false, lang: "en" });
    assert.equal(other.state, "login");
    assert.equal(existsSync(agyToken(otherHome)), false);

    // 4. Unsigned and pre-existing profiles (no noted account) stay `login` without probing `agy acp`.
    assert.equal((await accounts.check("ag-u", "en")).state, "login");
    assert.equal((await accounts.check("ag-p", "en")).state, "login");
    assert.equal(driverCalls, 0);

    // 5. The taken-back profile probes `agy acp` and reports `ok` with models.
    const nCheck = await accounts.check("ag-n", "en");
    assert.equal(nCheck.state, "ok");
    assert.deepEqual(nCheck.models, ["gemini-3.5-flash", "gemini-3.1-pro"]);

    // 6. A revoked sign-in (`Authentication required`) flips a subscription check back to `login` while preserving known models.
    driverMode = "auth";
    const revoked = await accounts.check("ag-n", "en");
    assert.equal(revoked.state, "login");
    assert.equal(revoked.detail, tr("en", "station.profile.signedOut"));
    assert.deepEqual(revoked.models, ["gemini-3.5-flash", "gemini-3.1-pro"]);

    // 7. Non-subscription `agy` profiles (`env` and `api-provider`) never get mapped to `login`:
    //    `env` reports `failed` (`agyFailed`), and an already-failed `api-provider` key check preserves its `keyRefused` error without spawning `agy acp`.
    const callsBeforeEnv = driverCalls;
    const envFailed = await accounts.check("ag-env", "en");
    assert.equal(envFailed.state, "failed");
    assert.match(envFailed.detail, /Authentication required/);
    assert.equal(driverCalls, callsBeforeEnv + 1);

    const apiFailed = await accounts.check("ag-api", "en");
    assert.equal(apiFailed.state, "failed");
    assert.equal(apiFailed.detail, "Google refused the key (401)");
    assert.equal(driverCalls, callsBeforeEnv + 1, "already-failed api-provider check does not spawn agy acp");

    // 8. Non-auth launch error still reports `failed`.
    driverMode = "crash";
    const crashed = await accounts.check("ag-n", "en");
    assert.equal(crashed.state, "failed");
    assert.match(crashed.detail, /ENOENT/);
  } finally {
    platform.hasKeychain = hadKeychain;
    agyKeychain.read = read;
    await accounts.close();
    store.close();
  }
});

test("go-keyring's stored values, as `agy` left them in the keychain", () => {
  const text = JSON.stringify({ id_token_email: "a@b.c" });
  assert.equal(goKeyringValue(`go-keyring-base64:${Buffer.from(text).toString("base64")}`), text);
  assert.equal(goKeyringValue(`go-keyring-encoded:${Buffer.from(text).toString("hex")}`), text);
  assert.equal(goKeyringValue(text), text);
});

test("uncheckOutdated migrates legacy tiered agy model IDs in config.json to base models", () => {
  const raw: any = {
    profiles: [
      {
        id: "ag",
        runtime: "agy",
        access: { kind: "subscription" },
        model: "gemini-4-carbon-high",
        models: ["gemini-4-carbon-high", "claude-opus-5-5-medium"],
      },
    ],
    connects: [{ id: "sl", bind: { runtime: "agy", model: "gemini-4-carbon-high" } }],
  };
  const { changes } = uncheckOutdated(raw, () => ["gemini-4-carbon", "claude-opus-5-5", "gpt-oss-120b"], new Set());
  assert.equal(changes.length, 1);
  assert.deepEqual(raw.profiles[0].models, ["gemini-4-carbon", "claude-opus-5-5"]);
  assert.equal(raw.profiles[0].model, "gemini-4-carbon");
  assert.equal(raw.connects[0].bind.model, "gemini-4-carbon");
});
