import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { after, test } from "node:test";
import { CodebuddyDriver, classifyFailure, codebuddyEnv, configDir } from "../src/agents/codebuddy.ts";
import type { OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { profileRuntimes } from "../src/agents/profiles.ts";
import { accessKinds } from "../src/accounts/profiles.ts";
import { transcriptPath, readTimeline, isPosting } from "../src/read/transcript.ts";
import { callsOf } from "../src/usage/counter.ts";
import { CHAT_CREATE } from "../src/tools/chat.ts";
import { kindPackage } from "../src/updates/runtimes.ts";

const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "codebuddy-") : "/tmp/codebuddy-");
const drivers: CodebuddyDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});
const fake = `${fileURLToPath(new URL("./fake", import.meta.url))}${delimiter}${process.env.PATH}`;
let n = 0;
function setup(env: Record<string, string> = { CODEBUDDY_API_KEY: "cb-key", CODEBUDDY_INTERNET_ENVIRONMENT: "internal" }) {
  const id = ++n;
  const dump = join(data, `dump-${id}`);
  const options: OpenOptions = {
    key: `codebuddy-test-${id}`,
    profile: { id: "cb", runtime: "codebuddy", home: join(data, `home-${id}`), access: { kind: "env" }, env: { PATH: fake, FAKE_DUMP: dump, ...env } },
    cwd: data, instructions: "Use chat_post to answer.", mcpToken: "test-token", mcpUrl: "http://127.0.0.1:12345/mcp", route: "test",
  };
  const events: RuntimeEvent[] = [];
  const driver = new CodebuddyDriver({ data });
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

test("its own variables run CodeBuddy Code in its profile's files, with the station's tools and instructions", async () => {
  const { options, events, driver, dump } = setup();
  const session = await driver.open({ ...options, model: "deepseek-v4.1-flash", effort: "high" }, (e) => events.push(e));
  const started = JSON.parse(readFileSync(dump, "utf8").trim().split("\n")[0]!);
  assert.deepEqual(started.args, ["--acp", "--permission-mode", "bypassPermissions", "--append-system-prompt", "Use chat_post to answer.", "--effort", "high"]);
  assert.deepEqual([started.key, started.site, started.config, started.updates], ["cb-key", "internal", configDir(options.profile.home), "1"]);
  const opened = rpc(dump).find((m) => m.method === "session/new").params;
  assert.equal(opened.mcpServers[0].headers[0].value, "Bearer test-token");
  assert.equal(opened._meta["codebuddy.ai/suppressReplay"], true);
  assert.equal(rpc(dump).find((m) => m.method === "session/set_model").params.modelId, "deepseek-v4.1-flash");
  await session.prompt("hello");
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "completed" } });
  // What the person said goes as it is: the instructions are the system prompt's.
  assert.equal(rpc(dump).find((m) => m.method === "session/prompt").params.prompt[0].text, "hello");
  const path = transcriptPath("codebuddy", options.profile.home, session.id());
  assert.ok(path);
  const lines = readFileSync(path, "utf8").trim().split("\n").map((s) => JSON.parse(s));
  assert.equal(lines.find((m) => m.type === "assistant").text, "first hello");
  assert.equal(lines.find((m) => m.type === "tool").result, "file contents");
  assert.ok(isPosting(lines.filter((m) => m.type === "tool").at(-1).name));
  assert.ok(readTimeline("codebuddy", path).length > 0);
  // The turn's counts, input apart from the cache's, thoughts with the output; the context it ended with.
  const calls = callsOf("codebuddy", readFileSync(path, "utf8"), false, { model: null, codexId: null });
  assert.equal(calls.length, 1);
  assert.deepEqual([calls[0]!.input, calls[0]!.cacheRead, calls[0]!.output, calls[0]!.model, calls[0]!.context, calls[0]!.window], [1000, 200, 400, "deepseek-v4.1-flash", 5000, 200000]);
  const id = session.id();
  await session.dispose();
  events.length = 0;
  const resumed = await driver.open({ ...options, resume: id }, (e) => events.push(e));
  assert.equal(resumed.id(), id);
  assert.equal(events.length, 0);
  assert.equal(rpc(dump).filter((m) => m.method === "session/load").at(-1).params._meta["codebuddy.ai/suppressReplay"], true);
  await resumed.prompt("again");
  await until(() => ended(events).length === 1);
  assert.doesNotMatch(readFileSync(path, "utf8"), /past replay/);
  await resumed.dispose();
});

test("a message for the running turn goes into it; none when nothing runs", async () => {
  const { options, events, driver } = setup();
  const s = await driver.open(options, (e) => events.push(e));
  assert.equal(await s.steer("idle"), false);
  await s.prompt("hold");
  await until(() => events.some((e) => e.type === "live" && e.event.kind === "delta" && e.event.text === "first "));
  assert.equal(await s.steer("also this"), true);
  await until(() => events.some((e) => e.type === "live" && e.event.kind === "delta" && e.event.text === " (heard also this)"));
  await s.abort();
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "aborted" } });
  const lines = readFileSync(transcriptPath("codebuddy", options.profile.home, s.id())!, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(lines.filter((l) => l.type === "user").map((l) => [l.text, l.steered ?? false]), [["hold", false], ["also this", true]]);
  await s.dispose();
});

test("another model between turns is set in the running process; one it does not offer, or another effort, starts it again", async () => {
  const { options, events, driver, dump } = setup();
  const session = await driver.open(options, (e) => events.push(e));
  assert.equal(session.model, "default-model");
  assert.equal(session.retune!({ ...options, model: "deepseek-v4.1-flash" }), true);
  assert.equal(session.retune!({ ...options, model: "not-offered" }), false);
  assert.equal(session.retune!({ ...options, model: "deepseek-v4.1-flash", effort: "low" }), false);
  await session.prompt("hi");
  await until(() => ended(events).length === 1);
  assert.deepEqual(rpc(dump).filter((m) => m.method === "session/set_model").map((m) => m.params.modelId), ["deepseek-v4.1-flash"]);
  await session.dispose();
});

test("a signed-out account, a refused sign-in mid-session and spent credits", async () => {
  const { options, events, driver } = setup();
  const s = await driver.open(options, (e) => events.push(e));
  await s.prompt("expired");
  await until(() => ended(events).length === 1);
  assert.equal((ended(events)[0] as any).outcome.reason, "auth");
  await s.prompt("credits");
  await until(() => ended(events).length === 2);
  assert.equal((ended(events)[1] as any).outcome.reason, "rate_limit");
  await s.dispose();
  const signedOut = setup({});
  await assert.rejects(signedOut.driver.open(signedOut.options, () => {}), /Authentication required/);
  assert.equal(classifyFailure("Authentication required"), "auth");
});

test("models are read without a turn, the station's tools, its instructions or a transcript", async () => {
  const { options, driver, dump } = setup();
  assert.deepEqual(await driver.models(options.profile), ["default-model", "deepseek-v4.1-flash"]);
  const calls = rpc(dump);
  assert.deepEqual(calls.find((c) => c.method === "session/new").params.mcpServers, []);
  assert.equal(calls.some((c) => c.method === "session/prompt" || c.method === "session/set_model"), false);
  assert.deepEqual(JSON.parse(readFileSync(dump, "utf8").trim().split("\n")[0]!).args, ["--acp", "--permission-mode", "bypassPermissions"]);
  assert.equal(readFileSync(dump, "utf8").includes(options.mcpToken), false);
});

test("a handover keeps the running turn, ended once by the next station", async () => {
  const { options, events, driver } = setup();
  const s = await driver.open(options, (e) => events.push(e));
  await s.prompt("hold");
  await until(() => events.some((e) => e.type === "live" && e.event.kind === "delta" && e.event.text === "first "));
  const snapshot = s.snapshot();
  s.detach();
  await allLeft();
  const next = new CodebuddyDriver({ data });
  drivers.push(next);
  const later: RuntimeEvent[] = [];
  const adopted = await next.adopt(options, snapshot, (e) => later.push(e));
  await adopted.abort();
  await until(() => ended(later).length === 1);
  assert.equal(ended(events).length, 0);
  await adopted.dispose();
});

test("which profiles run it, and none of the machine's CodeBuddy keys", (t) => {
  const { options } = setup();
  assert.deepEqual(accessKinds("codebuddy"), ["env"]);
  assert.deepEqual(profileRuntimes(options.profile), ["codebuddy"]);
  assert.ok(CHAT_CREATE.inputSchema.properties.runtime.enum.includes("codebuddy"));
  assert.equal(kindPackage("codebuddy"), "@tencent-ai/codebuddy-code");
  const saved = { CODEBUDDY_API_KEY: process.env.CODEBUDDY_API_KEY, CODEBUDDY_AUTH_TOKEN: process.env.CODEBUDDY_AUTH_TOKEN };
  process.env.CODEBUDDY_API_KEY = "machine-key";
  process.env.CODEBUDDY_AUTH_TOKEN = "machine-token";
  t.after(() => {
    for (const [k, v] of Object.entries(saved)) if (v === undefined) delete process.env[k]; else process.env[k] = v;
  });
  const env = codebuddyEnv(options);
  assert.equal(env.CODEBUDDY_API_KEY, "cb-key");
  assert.equal(env.CODEBUDDY_AUTH_TOKEN, undefined);
  const own = codebuddyEnv({ ...options, profile: { ...options.profile, env: {} } });
  assert.equal(own.CODEBUDDY_API_KEY, undefined);
});
