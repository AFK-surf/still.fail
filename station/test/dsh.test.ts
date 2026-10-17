// The DeepSeek Harness driver (src/agents/dsh.ts) against a fake dsh (test/fake/dsh: what the station's driver plugin in
// it says) under the real runner: turns and their steps, what it is started with (its patch, environment, the station's
// tools), failures and how they are told apart, a steer in the running turn, cancel, the process exiting, resuming, the
// transcript read as a timeline, and a session taken up by a next driver (with a snapshot, and after a crash) with its
// turn's end told once.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { BRIDGE, DshDriver, classifyFailure, dshSetup } from "../src/agents/dsh.ts";
import { dshRoute, profileEnv, profileRuntimes } from "../src/agents/profiles.ts";
import type { AgentSession, OpenOptions, Profile, RuntimeEvent } from "../src/agents/runtime.ts";
import { readTimeline, transcriptPath } from "../src/read/transcript.ts";

const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
process.env.PATH = `${fake}${delimiter}${process.env.PATH}`;
// Inherited, and not to reach the agent.
process.env.DEEPSEEK_API_KEY = "leaked";
process.env.DSH_HOME = "/elsewhere";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "ds-") : "/tmp/ds-");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline.
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
/// The fifos a `gate:<name>` turn waits at (test/fake/dsh.mjs): `open(part)` lets it go on.
function gates(dump: string, name: string) {
  const at = `${dump}.${name}`;
  if (process.platform !== "win32") for (const part of ["a", "b"]) execFileSync("/usr/bin/mkfifo", [`${at}.${part}`]);
  return { open: (part: "a" | "b") => writeFile(`${at}.${part}`, "go"), said: () => existsSync(`${at}.said`) };
}
const drivers: DshDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver() {
  const d = new DshDriver({ data });
  drivers.push(d);
  return d;
}

let n = 0;
function options(extra: Partial<OpenOptions> = {}, access: Record<string, unknown> = { kind: "opencode-go", key: "k1" }): OpenOptions & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  mkdirSync(home, { recursive: true });
  const dump = join(data, `dump${i}`);
  return {
    key: `slack:T1:C${i}:1700000000.000${i}`,
    profile: { id: "ds", runtime: "dsh", home, access, env: { FAKE_DUMP: dump } },
    cwd: data,
    model: "m1",
    instructions: "be brief; {{not a variable}}",
    mcpToken: "tok",
    mcpUrl: "http://127.0.0.1:4750/mcp",
    route: `route${i}`,
    dump,
    ...extra,
  };
}

function listen() {
  const events: RuntimeEvent[] = [];
  const push = (e: RuntimeEvent) => void events.push(e);
  const until = (what: (events: RuntimeEvent[]) => boolean) => eventually(() => what(events));
  return { events, push, until };
}

const ends = (events: RuntimeEvent[]) => events.filter((e) => e.type === "turnEnded");
const ended = (k: number) => (events: RuntimeEvent[]) => ends(events).length >= k;
const live = (events: RuntimeEvent[]) => events.flatMap((e) => (e.type === "live" ? [e.event] : []));
const deltas = (events: RuntimeEvent[]) => live(events).flatMap((e) => (e.kind === "delta" ? [e.text] : []));
const outcome = (events: RuntimeEvent[], k = 0) => (ends(events)[k] as Extract<RuntimeEvent, { type: "turnEnded" }>).outcome;
const stdin = (dump: string) => readFileSync(`${dump}.stdin`, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const started = (dump: string) => JSON.parse(readFileSync(dump, "utf8").trim().split("\n")[0]!);

describe("the DeepSeek Harness driver", { concurrency: true }, () => {
  test("a turn completes, from a process started with its patch, environment and the station's tools", async () => {
    const d = driver();
    const o = options({ effort: "max" });
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.match(session.id(), /^[0-9a-f-]{36}$/);
    await session.prompt("say:hello");
    assert.equal(session.busy(), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(session.busy(), false);
    assert.ok(!events.some((e) => e.type === "turnStarted"), "our own prompt's turn is not one started without us");
    assert.deepEqual(live(events).filter((e) => e.kind !== "phase").map((e) => e.kind), ["start", "delta", "end", "start", "delta", "end"]);
    assert.deepEqual(live(events).filter((e) => e.kind === "start").map((e) => (e as { step: string }).step), ["thinking", "text"]);
    assert.deepEqual(deltas(events), ["thinking it over", "hello"]);

    const run = started(o.dump);
    assert.deepEqual(run.argv.slice(0, 3), ["--profile", "acp", "--patch"]);
    const env = run.env;
    assert.equal(env.DSH_HOME, o.profile.home);
    assert.equal(env.DSH_AGENTS_HOME, join(o.profile.home, "agents"));
    assert.equal(env.DSH_PERMISSION_MODE, "danger-full-access");
    assert.equal(env.DSH_TELEMETRY_MODE, "DISABLED");
    assert.equal(env.DEEPSEEK_API_KEY, undefined, "not the station's own");
    assert.equal(env.STILLFAIL_DSH_KEY, "k1");
    // OpenCode Go through dsh's pi-ai routes, its session header the session's route.
    const byId = Object.fromEntries(run.patch.map((p: { id: string }) => [p.id, p]));
    // dsh's ACP server off, the station's driver in, by its path.
    assert.deepEqual(byId.acp, { id: "acp", disabled: true });
    // The station's tools by dsh's own MCP client, the session's token read from the environment (not in the file).
    assert.deepEqual(run.patch.find((p: { insert?: unknown }) => p.insert).insert, [
      { id: "stillfail-bridge", name: BRIDGE },
      {
        id: "stillfail-tools", name: "@deepseek-ai/dsh-mcp-client",
        config: { transport: "streamable-http", serverName: "stillfail", url: o.mcpUrl, headers: { Authorization: "!!js 'Bearer ' + process.env.STILLFAIL_MCP_TOKEN" }, failOnStartupError: true },
      },
    ]);
    assert.equal(env.STILLFAIL_MCP_TOKEN, "tok");
    assert.ok(existsSync(BRIDGE));
    assert.deepEqual(byId["llm-pi-ai"].config.providers.stillfail, {
      displayName: "OpenCode Go", api: "openai-completions", baseURL: "https://opencode.ai/zen/go/v1", apiKeyEnv: "STILLFAIL_DSH_KEY",
      models: [{ id: "m1", reasoningEfforts: { off: null, max: "max" } }], headers: { "x-opencode-session": `ember-${o.route}` }, reasoning: "max",
    });
    assert.deepEqual(byId["agent-default-model"].config, { provider: "stillfail", model: "m1" });
    assert.deepEqual(byId["system-prompt"].config, { personaPrefix: "", personaSuffix: "be brief; {\u200b{not a variable}}" }, "no prompt variables: the instructions' braces broken");
    assert.deepEqual(byId["session-persistence-jsonl"].config, { root: join(o.profile.home, "dsh-sessions"), compression: "none" });

    // Opened with the route its agent asks for.
    const sent = stdin(o.dump);
    assert.deepEqual(sent[0], { id: "open", op: "open", cwd: o.cwd, provider: "stillfail", model: "m1" });
    assert.ok(!readFileSync(run.argv[3], "utf8").includes("tok"));
    assert.equal(sent[1].op, "prompt");
    assert.equal(sent[1].text, "say:hello");
    await assert.rejects(session.prompt("x").then(() => session.prompt("y")), /a turn is already running/);
    await until(ended(2));
    assert.equal(await session.steer("more"), false, "nothing running to steer");

    // What it wrote is read as a timeline: what the station said, the thoughts and replies; not the context dsh adds.
    const path = transcriptPath("dsh", o.profile.home, session.id());
    assert.ok(path !== null);
    const timeline = readTimeline("dsh", path);
    assert.deepEqual(timeline.map((e) => [e.kind, e.text]), [
      ["user", "say:hello"], ["thinking", "thinking it over"], ["assistant", "hello"],
      ["user", "x"], ["thinking", "thinking it over"], ["assistant", "x"],
    ]);
    assert.match(timeline[0]!.at ?? "", /^\d{4}-\d\d-\d\dT/);
    await session.dispose();
    await until((e) => e.some((x) => x.type === "closed"));
  });

  test("a tool call is a step with its input and output; the transcript has it as call and result", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("cmd");
    await until(ended(1));
    const tool = live(events).find((e) => e.kind === "start" && e.step === "tool");
    assert.deepEqual(tool, { kind: "start", id: "call_3", step: "tool", tool: "bash", input: "" });
    // Its input as it streams, its output with its result, and its end only then.
    const of = live(events).filter((e) => "id" in e && e.id === "call_3").map((e) => (e.kind === "delta" ? `${e.field}:${e.text}` : e.kind));
    assert.deepEqual(of, ["start", 'input:{"command":"ls"}', "output:a\n", "end"]);
    const phases = live(events).flatMap((e) => (e.kind === "phase" ? [e.phase] : []));
    assert.deepEqual(phases.slice(0, 4), ["requesting", "responding", "working", "requesting"]);
    const timeline = readTimeline("dsh", transcriptPath("dsh", o.profile.home, session.id())!);
    const call = timeline.find((e) => e.kind === "tool_call");
    const result = timeline.find((e) => e.kind === "tool_result");
    assert.equal(call?.tool, "bash");
    assert.equal(call?.callId, result?.callId);
    assert.equal(result?.ok, true);
    assert.equal(result?.text, "a\n");
    await session.dispose();
  });

  test("a failed prompt is told apart by what dsh said", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    for (const [k, [said, reason]] of ([["fail:auth", "auth"], ["fail:rate", "rate_limit"], ["fail:model", "model"]] as const).entries()) {
      await session.prompt(said);
      await until(ended(k + 1));
      const o = outcome(events, k);
      assert.equal(o.kind, "failed");
      assert.equal((o as { reason: string }).reason, reason);
    }
    assert.equal(classifyFailure("UNKNOWN", 'turn failed: 401: {"message":"Upstream request failed: Invalid credential"}'), "auth");
    assert.equal(classifyFailure("MISSING_CREDENTIAL", "the route's key resolves to nothing"), "auth");
    assert.equal(classifyFailure("QUOTA", "insufficient balance"), "rate_limit");
    // A prompt dsh refuses starts no turn: it ends at once.
    await session.prompt("refuse");
    await until(ended(4));
    assert.equal(outcome(events, 3).kind, "failed");
    assert.equal(session.busy(), false);
    await session.dispose();
  });

  test("abort cancels the turn; its end comes as aborted, and the session goes on", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("hold");
    await until((e) => deltas(e).includes("holding"));
    await session.abort();
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "aborted" });
    assert.ok(stdin(o.dump).some((m) => m.op === "cancel"));
    await session.prompt("say:again");
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "completed" });
    await session.dispose();
  });

  test("a steer goes into the running turn, which reads it and goes on", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("hold");
    await until((e) => deltas(e).includes("holding"));
    assert.equal(await session.steer("more"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(deltas(events).includes("steer:more"), "read in the same turn");
    assert.equal(ends(events).length, 1);
    assert.ok(!events.some((e) => e.type === "turnStarted"));
    assert.ok(stdin(o.dump).some((m) => m.op === "steer" && m.text === "more"));
    await session.dispose();
  });

  test("a call to the station's tools failing as unreachable is told as toolsLost", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("tools");
    await until(ended(1));
    assert.ok(events.some((e) => e.type === "toolsLost" && /ECONNREFUSED/.test(e.why)));
    await session.dispose();
  });

  test("the process exiting during a turn fails it as exited, then closes the session", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("exit");
    await until((e) => e.some((x) => x.type === "closed"));
    const o = outcome(events);
    assert.equal(o.kind, "failed");
    assert.equal((o as { reason: string }).reason, "exited");
    await assert.rejects(session.prompt("x"), /closed/);
  });

  test("a session is resumed by its id in a new process; one dsh does not have is refused before it starts", async () => {
    const d = driver();
    const o = options();
    const a = listen();
    const first = await d.open(o, a.push);
    await first.prompt("say:one");
    await a.until(ended(1));
    const id = first.id();
    await first.dispose();
    const b = listen();
    const again = await d.open({ ...o, resume: id }, b.push);
    assert.equal(again.id(), id);
    await again.prompt("say:two");
    await b.until(ended(1));
    const resumed = stdin(o.dump).filter((m) => m.op === "open" && m.resume !== undefined);
    assert.equal(resumed.length, 1);
    assert.equal(resumed[0].resume, id);
    assert.deepEqual(readTimeline("dsh", transcriptPath("dsh", o.profile.home, id)!).filter((e) => e.kind === "assistant").map((e) => e.text), ["one", "two"]);
    await again.dispose();
    await assert.rejects(d.open({ ...o, resume: "11111111-1111-4111-8111-111111111111" }, () => {}), /no dsh session/);
  });

  for (const crashed of [false, true]) {
    test(`a next driver takes the session up ${crashed ? "after a crash (no snapshot)" : "from its snapshot"}: the turn ends once, no live event twice`, async () => {
      const first = driver();
      const o = options();
      const a = listen();
      const session = await first.open(o, a.push);
      const gate = gates(o.dump, "g");
      await session.prompt("gate:g");
      await a.until((e) => deltas(e).includes("first "));
      let snapshot: unknown = null;
      if (!crashed) snapshot = JSON.parse(JSON.stringify(session.snapshot()));
      // Stops: the process goes on under its runner, saying the rest with nobody reading.
      first.detach();
      await gate.open("a");
      await eventually(gate.said);
      const next = driver();
      const b = listen();
      const taken: AgentSession = await next.adopt(o, snapshot, b.push);
      assert.equal(taken.id(), session.id());
      assert.equal(taken.busy(), true);
      await gate.open("b");
      await b.until(ended(1));
      const all = [...a.events, ...b.events];
      assert.equal(ends(all).length, 1, "the turn's end, once");
      assert.deepEqual(outcome(b.events), { kind: "completed" });
      assert.deepEqual(deltas(all), ["first ", "second"], "every delta once, in order");
      const starts = live(all).filter((e) => e.kind === "start").length;
      assert.equal(starts, 2);
      assert.equal(live(all).filter((e) => e.kind === "end").length, starts, "every step started ends");
      assert.equal(b.events.filter((e) => e.type === "turnStarted").length, crashed ? 1 : 0);
      await taken.prompt("say:after");
      await b.until(ended(2));
      assert.deepEqual(outcome(b.events, 1), { kind: "completed" });
      await taken.dispose();
      await b.until((e) => e.some((x) => x.type === "closed"));
      assert.ok(!a.events.some((e) => e.type === "closed"), "the first driver hears nothing after letting go");
    });
  }
});

describe("what a profile runs DeepSeek Harness on", () => {
  const profile = (access: Record<string, unknown>, more: Partial<Profile> = {}): Profile => ({ id: "p", runtime: "dsh", home: "/h", access, ...more });

  test("a provider's key: DeepSeek on its own route, the rest on the protocol they speak, chat completions first", () => {
    const deepseek = profile({ kind: "api-provider", provider: "deepseek", key: "sk" });
    assert.deepEqual(profileRuntimes(deepseek), ["dsh"], "DeepSeek speaks chat completions only: dsh alone runs it");
    assert.deepEqual(dshRoute(deepseek), { kind: "deepseek" });
    assert.deepEqual(profileEnv(deepseek, "dsh"), { DEEPSEEK_API_KEY: "sk" });
    const setup = dshSetup(dshRoute(deepseek), "deepseek-v4-pro", "medium", "", "/h", "r", "http://127.0.0.1:1/mcp");
    const byId = Object.fromEntries(setup.patch.map((p) => [p.id, p]));
    assert.deepEqual(byId["llm-deepseek"].config, { apiKeyEnv: "DEEPSEEK_API_KEY", models: [{ id: "deepseek-v4-pro" }], reasoningEffort: "high" });
    assert.deepEqual([setup.provider, setup.model], ["deepseek-official", "deepseek-v4-pro"]);

    assert.deepEqual(dshRoute(profile({ kind: "api-provider", provider: "moonshotai", key: "k" })), { kind: "pi", name: "Kimi", api: "openai-completions", baseURL: "https://api.moonshot.ai/v1" });
    assert.deepEqual(dshRoute(profile({ kind: "api-provider", provider: "minimax", key: "k" })), { kind: "pi", name: "MiniMax", api: "anthropic-messages", baseURL: "https://api.minimax.io/anthropic" });
    assert.deepEqual(dshRoute(profile({ kind: "api-provider", provider: "openai", key: "k" })), { kind: "pi", name: "OpenAI", api: "openai-responses", baseURL: "https://api.openai.com/v1" });
    assert.deepEqual(profileRuntimes(profile({ kind: "api-provider", provider: "openai", key: "k" })), ["codex", "dsh"]);
    assert.deepEqual(profileEnv(profile({ kind: "api-provider", provider: "openai", key: "k" }), "dsh"), { STILLFAIL_DSH_KEY: "k" });
    // A decision-only provider runs no runtime.
    assert.deepEqual(profileRuntimes(profile({ kind: "api-provider", provider: "jev", key: "k" })), []);
  });

  test("a model is needed on a provider's route; custom variables keep dsh's own configuration", () => {
    assert.throws(() => dshSetup(dshRoute(profile({ kind: "opencode-go", key: "k" })), undefined, undefined, "", "/h", "r", "http://127.0.0.1:1/mcp"), /names no model/);
    const own = dshSetup(dshRoute(profile({ kind: "env" })), undefined, undefined, "", "/h", "r", "http://127.0.0.1:1/mcp");
    assert.deepEqual(own.patch.map((p) => p.id ?? "insert"), ["acp", "insert", "system-prompt", "session-persistence-jsonl"]);
    assert.equal(own.provider, undefined, "dsh's own default route");
    assert.deepEqual(profileRuntimes(profile({ kind: "env" })), ["dsh"]);
    assert.deepEqual(profileRuntimes(profile({ kind: "subscription" })), [], "no subscription to sign in to");
    assert.deepEqual(profileRuntimes(profile({ kind: "opencode-go", key: "k" }, { runtime: "claude" })), ["claude", "codex", "dsh"]);
    assert.deepEqual(profileRuntimes(profile({ kind: "anthropic-api", key: "k" }, { runtime: "claude" })), ["claude", "dsh"]);
  });
});
