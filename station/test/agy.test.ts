import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { after, test } from "node:test";
import { AgyDriver, agyEnv, classifyFailure, geminiDir } from "../src/agents/agy.ts";
import type { OpenOptions, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { profileRuntimes } from "../src/agents/profiles.ts";
import { accessKinds } from "../src/accounts/profiles.ts";
import { transcriptPath, readTimeline } from "../src/read/transcript.ts";
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
  await s.prompt("hold");
  assert.equal(await s.steer("later"), false);
  await s.abort();
  await until(() => ended(events).length === 1);
  assert.deepEqual(ended(events)[0], { type: "turnEnded", outcome: { kind: "aborted" } });
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

test("models are read without a turn, the station's tools or a transcript", async () => {
  const { options, driver, dump } = setup();
  assert.deepEqual(await driver.models(options.profile), ["gemini-3.5-flash", "gemini-3.1-pro"]);
  const calls = rpc(dump);
  assert.deepEqual(calls.find((c) => c.method === "session/new").params.mcpServers, []);
  assert.equal(calls.some((c) => c.method === "session/prompt" || c.method === "session/set_model"), false);
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
  const next = new AgyDriver({ data });
  drivers.push(next);
  const later: RuntimeEvent[] = [];
  const adopted = await next.adopt(options, snapshot, (e) => later.push(e));
  await adopted.abort();
  await until(() => ended(later).length === 1);
  assert.equal(ended(events).length, 0);
  await adopted.dispose();
});

test("which profiles run it, and none of the machine's Google accounts", (t) => {
  const { options } = setup();
  assert.deepEqual(accessKinds("agy"), ["api-provider", "env"]);
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
  assert.equal(env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
  const own = agyEnv({ ...options, profile: { ...options.profile, access: { kind: "env" }, env: {} } });
  assert.equal(own.GEMINI_API_KEY, undefined);
});
