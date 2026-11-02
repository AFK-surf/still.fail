// The Grok Build driver (src/agents/grok.ts) against a fake grok (test/fake/grok: ACP as Grok Build speaks it) under the
// real runner: turns and their steps, what it is started with (its flags, environment, the station's tools and
// instructions), a message put into the running turn, failures and how they are told apart, cancel, a permission asked,
// the process exiting, resuming, the transcript read as a timeline and its usage kept, and a session taken up by a next
// driver (with a snapshot, and after a crash) with its turn's end told once; then what a profile runs it on, its sign-in
// and its check.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { GrokDriver, classifyFailure, grokArgs, sessionDir, usageLine, USAGE } from "../src/agents/grok.ts";
import { profileEnv, profileRuntimes } from "../src/agents/profiles.ts";
import type { AgentSession, OpenOptions, Profile, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { checkProfile, grokModels, loginCommand } from "../src/accounts/profiles.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { grokQuotaOf } from "../src/accounts/quota.ts";
import { callsOf } from "../src/usage/counter.ts";
import { readTimeline, transcriptPath } from "../src/read/transcript.ts";

const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
process.env.PATH = `${fake}${delimiter}${process.env.PATH}`;
// Inherited, and not to reach the agent.
process.env.XAI_API_KEY = "leaked";
process.env.GROK_HOME = "/elsewhere";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "gk-") : "/tmp/gk-");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline.
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
const drivers: GrokDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver() {
  const d = new GrokDriver({ data });
  drivers.push(d);
  return d;
}

let n = 0;
function options(extra: Partial<OpenOptions> = {}, access: Record<string, unknown> = { kind: "subscription" }): OpenOptions & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  mkdirSync(home, { recursive: true });
  const dump = join(data, `dump${i}`);
  return {
    key: `slack:T1:C${i}:1700000000.000${i}`,
    profile: { id: "gk", runtime: "grok", home, access, env: { FAKE_DUMP: dump } },
    cwd: data,
    model: "grok-4.7",
    instructions: "be brief",
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

describe("the Grok Build driver", { concurrency: true }, () => {
  test("a turn completes, from a process started with its flags, environment, instructions and the station's tools", async () => {
    const d = driver();
    const o = options({ effort: "xhigh" });
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.match(session.id(), /^01a151b0-/);
    await session.prompt("say:hello");
    assert.equal(session.busy(), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(session.busy(), false);
    assert.ok(!events.some((e) => e.type === "turnStarted"), "our own prompt's turn is not one started without us");
    // A thought, then the reply in two chunks: one step each.
    assert.deepEqual(live(events).filter((e) => e.kind !== "phase").map((e) => e.kind), ["start", "delta", "end", "start", "delta", "delta", "end"]);
    assert.deepEqual(deltas(events), ["thinking it over", "hel", "lo"]);

    const run = started(o.dump);
    assert.deepEqual(run.argv, ["agent", "--always-approve", "--no-leader", "--model", "grok-4.7", "--reasoning-effort", "xhigh", "stdio"]);
    const env = run.env;
    assert.equal(env.GROK_HOME, join(o.profile.home, "grok"));
    assert.equal(env.GROK_DISABLE_AUTOUPDATER, "1");
    assert.equal(env.GROK_TELEMETRY_ENABLED, "0");
    assert.equal(env.XAI_API_KEY, undefined, "not the station's own");
    assert.equal(env.GROK_CLAUDE_HOOKS_ENABLED, "false", "not the person's Claude Code hooks");
    assert.equal(env.GROK_CLAUDE_MCPS_ENABLED, "false");

    // The station's tools, with the session's token, and its instructions.
    const sent = stdin(o.dump);
    assert.equal(sent[0].method, "initialize");
    assert.equal(sent[1].method, "session/new");
    assert.deepEqual(sent[1].params.mcpServers, [{ type: "http", name: "stillfail", url: o.mcpUrl, headers: [{ name: "Authorization", value: "Bearer tok" }] }]);
    assert.equal(sent[1].params.cwd, o.cwd);
    assert.match(sent[1].params._meta.rules, /^be brief\n\n.*use_tool.*stillfail__chat_post/s);
    assert.deepEqual(sent[2].params.prompt, [{ type: "text", text: "say:hello" }]);
    await assert.rejects(session.prompt("x").then(() => session.prompt("y")), /a turn is already running/);
    await until(ended(2));
    assert.equal(await session.steer("more"), false, "nothing to put it into: the station starts a turn of its own");

    // What it wrote is read as a timeline: what the station said, the thoughts and replies; not the context it adds.
    const path = transcriptPath("grok", o.profile.home, session.id());
    assert.ok(path !== null);
    const timeline = readTimeline("grok", path);
    assert.deepEqual(timeline.map((e) => [e.kind, e.text]), [
      ["user", "say:hello"], ["thinking", "thinking it over"], ["assistant", "hello"],
      ["user", "x"], ["thinking", "thinking it over"], ["assistant", "x"],
    ]);
    // Each turn's usage kept beside it, its input less what the cache read and wrote.
    const usage = readFileSync(join(sessionDir(o.profile.home, session.id())!, USAGE), "utf8").trim().split("\n").map((l) => JSON.parse(l));
    assert.equal(usage.length, 2);
    assert.deepEqual([usage[0].usage, usage[0].context, usage[0].window], [{ input: 30, cacheRead: 60, cacheWrite: 10, output: 7, calls: 2 }, 1234, 256000]);
    // Between turns, another model and effort are set in the process, not by starting another.
    assert.equal(session.retune?.({ ...o, model: "grok-4.6", effort: "low" }), true);
    await eventually(() => stdin(o.dump).filter((m) => m.method === "session/set_config_option").length === 2);
    assert.deepEqual(stdin(o.dump).filter((m) => m.method === "session/set_config_option").map((m) => [m.params.configId, m.params.value]), [["model", "grok-4.6"], ["reasoning_effort", "low"]]);
    const calls = callsOf("grok", readFileSync(join(sessionDir(o.profile.home, session.id())!, USAGE), "utf8"), false, { model: null, codexId: null });
    assert.deepEqual(calls.map((c) => [c.model, c.input, c.cacheRead, c.cacheWrite, c.output]), [["grok-4.7", 30, 60, 10, 7], ["grok-4.7", 30, 60, 10, 7]]);
    // Each turn's calls, and the context it ended with, of the model's window: what a chat says of them.
    assert.deepEqual(calls.map((c) => [c.calls, c.context, c.window]), [[2, 1234, 256000], [2, 1234, 256000]]);
    await session.dispose();
    await until((e) => e.some((x) => x.type === "closed"));
  });

  test("a message for the running turn goes into it", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("hold");
    await until((e) => deltas(e).join("").includes("holding"));
    assert.equal(await session.steer("and this"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(deltas(events).join("").includes("heard: and this"));
    const interject = stdin(o.dump).find((m) => m.method === "_x.ai/interject");
    assert.deepEqual(interject.params, { sessionId: session.id(), text: "and this" });
    // Its own steering is not what the station said.
    const timeline = readTimeline("grok", transcriptPath("grok", o.profile.home, session.id())!);
    assert.deepEqual(timeline.filter((e) => e.kind === "user").map((e) => e.text), ["hold"]);
    await session.dispose();
  });

  test("a tool call is a step with its input and output; the transcript has it as call and result", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("cmd");
    await until(ended(1));
    const tool = live(events).find((e) => e.kind === "start" && e.step === "tool");
    assert.deepEqual(tool, { kind: "start", id: tool && "id" in tool ? tool.id : "", step: "tool", tool: "run_terminal_command", input: '{\n  "command": "ls"\n}' });
    assert.ok(live(events).some((e) => e.kind === "delta" && e.field === "output" && e.text === "a\n"));
    const timeline = readTimeline("grok", transcriptPath("grok", o.profile.home, session.id())!);
    const call = timeline.find((e) => e.kind === "tool_call");
    const result = timeline.find((e) => e.kind === "tool_result");
    assert.equal(call?.tool, "run_terminal_command");
    assert.equal(call?.callId, result?.callId);
    assert.equal(result?.ok, true);
    assert.equal(result?.text, "exit: 0\na\n");
    await session.dispose();
  });

  test("a call to one of the station's tools, reached through use_tool, is named and given as that tool", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("post");
    await until(ended(1));
    const tool = live(events).find((e) => e.kind === "start" && e.step === "tool");
    assert.deepEqual(tool && "tool" in tool ? [tool.tool, tool.input] : null, ["mcp__stillfail__chat_post", '{\n  "text": "posted words"\n}']);
    const call = readTimeline("grok", transcriptPath("grok", o.profile.home, session.id())!).find((e) => e.kind === "tool_call");
    assert.deepEqual([call?.tool, call?.text], ["mcp__stillfail__chat_post", '{\n  "text": "posted words"\n}']);
    await session.dispose();
  });

  test("a subagent's steps are shown under the call that spawned it, marked a subagent's, and end with it", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("sub");
    await until(ended(1));
    const starts = live(events).filter((e) => e.kind === "start");
    const spawn = starts.find((e) => e.kind === "start" && e.tool === "spawn_subagent");
    const inner = starts.filter((e) => e.kind === "start" && e.subagent === true);
    assert.ok(spawn);
    assert.deepEqual(inner.map((e) => (e.kind === "start" ? [e.step, e.tool ?? null, e.parent] : null)), [["tool", "read_file", spawn.id], ["text", null, spawn.id]]);
    assert.equal(live(events).filter((e) => e.kind === "end").length, starts.length, "every step started ends");
    await session.dispose();
  });

  test("a failed prompt is told apart by what Grok Build said", async () => {
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
    assert.equal(classifyFailure("You are not authenticated. Run grok login"), "auth");
    assert.equal(classifyFailure("RESOURCE_EXHAUSTED: usage limit reached"), "rate_limit");
    // SuperGrok's free usage running out names the subscription, but it is a limit, not the account.
    assert.equal(
      classifyFailure(
        "Rate limited: API error (status 429 Too Many Requests): subscription:free-usage-exhausted: You've used all the included free usage for model grok-4.7 for now. Upgrade to a Grok subscription for higher limits",
      ),
      "rate_limit",
    );
    await session.dispose();
  });

  test("abort cancels the turn; its end comes as aborted, and the session goes on", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("hold");
    await until((e) => deltas(e).join("").includes("holding"));
    await session.abort();
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "aborted" });
    assert.ok(stdin(o.dump).some((m) => m.method === "session/cancel"));
    await session.prompt("say:again");
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "completed" });
    await session.dispose();
  });

  test("a permission it asks is allowed", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("ask");
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    const answer = stdin(o.dump).find((m) => m.id === "perm-1");
    assert.deepEqual(answer.result, { outcome: { outcome: "selected", optionId: "allow-once" } });
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

  test("a session is loaded by its id in a new process; one Grok Build does not have is refused before it starts", async () => {
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
    const loaded = stdin(o.dump).filter((m) => m.method === "session/load");
    assert.equal(loaded.length, 1);
    assert.equal(loaded[0].params.sessionId, id);
    assert.match(loaded[0].params._meta.rules, /^be brief/);
    assert.deepEqual(readTimeline("grok", transcriptPath("grok", o.profile.home, id)!).filter((e) => e.kind === "assistant").map((e) => e.text), ["one", "two"]);
    await again.dispose();
    await assert.rejects(d.open({ ...o, resume: "11111111-1111-4111-8111-111111111111" }, () => {}), /no Grok Build session/);
  });

  for (const crashed of [false, true]) {
    test(`a next driver takes the session up ${crashed ? "after a crash (no snapshot)" : "from its snapshot"}: the turn ends once, no live event twice`, async () => {
      const first = driver();
      const o = options();
      const a = listen();
      const session = await first.open(o, a.push);
      await session.prompt("hold");
      await a.until((e) => deltas(e).join("").includes("holding"));
      let snapshot: unknown = null;
      if (!crashed) snapshot = JSON.parse(JSON.stringify(session.snapshot()));
      // Stops: the process goes on under its runner with nobody reading.
      first.detach();
      // (the station let go before the next takes up, as the hub waits: every line handled acknowledged)
      await allLeft();
      const next = driver();
      const b = listen();
      const taken: AgentSession = await next.adopt(o, snapshot, b.push);
      assert.equal(taken.id(), session.id());
      assert.equal(taken.busy(), true);
      assert.equal(await taken.steer("go on"), true);
      await b.until(ended(1));
      const all = [...a.events, ...b.events];
      assert.equal(ends(all).length, 1, "the turn's end, once");
      assert.deepEqual(outcome(b.events), { kind: "completed" });
      assert.equal(deltas(all).join("").split("holding").length - 1, 1, "every delta once");
      const starts = live(all).filter((e) => e.kind === "start").length;
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

describe("what a profile runs Grok Build on", () => {
  const profile = (access: Record<string, unknown>, more: Partial<Profile> = {}): Profile => ({ id: "p", runtime: "grok", home: "/h", access, ...more });

  test("SuperGrok signs in in its home; an xAI key runs it too and is given to it; no other provider's", () => {
    assert.deepEqual(profileRuntimes(profile({ kind: "subscription" })), ["grok"]);
    assert.deepEqual(profileEnv(profile({ kind: "subscription" }), "grok"), {});
    const xai = profile({ kind: "api-provider", provider: "xai", key: "xai-k" });
    assert.deepEqual(profileRuntimes(xai), ["codex", "dsh", "grok"]);
    assert.deepEqual(profileEnv(xai, "grok"), { XAI_API_KEY: "xai-k" });
    assert.ok(!profileRuntimes(profile({ kind: "api-provider", provider: "openai", key: "k" })).includes("grok"));
    assert.deepEqual(profileRuntimes(profile({ kind: "env" })), ["grok"]);
    assert.equal(loginCommand("grok", "/h"), "GROK_HOME=/h/grok grok login --device-auth");
    assert.deepEqual(grokArgs(undefined, "max"), ["agent", "--always-approve", "--no-leader", "--reasoning-effort", "max", "stdio"]);
    assert.deepEqual(grokArgs("grok-4.6", "minimal"), ["agent", "--always-approve", "--no-leader", "--model", "grok-4.6", "stdio"], "an effort it has not is left to it");
  });

  test("a turn's usage line from the prompt's answer; none without its usage", () => {
    const line = usageLine({ result: { stopReason: "end_turn", _meta: { promptId: "p1", modelId: "grok-4.7", totalTokens: 22751, usage: { inputTokens: 22533, outputTokens: 211, cachedReadTokens: 22400, cacheCreationTokens: 0, modelCalls: 1 } } } }, 5, 256000);
    assert.deepEqual(JSON.parse(line!), { type: "stillfail/usage", time: 5, id: "p1", model: "grok-4.7", usage: { input: 133, cacheRead: 22400, cacheWrite: 0, output: 211, calls: 1 }, context: 22751, window: 256000 });
    assert.equal(usageLine({ result: { stopReason: "cancelled" } }, 5), null);
  });

  test("its sign-in relays the device code and ends signed in; its check says so with the account's models", async () => {
    const home = join(data, "login");
    const dump = join(data, "login-dump");
    const logins = new LoginManager(data, { claude: "claude", codex: "codex", grok: "grok" }, () => ({ ...process.env, FAKE_DUMP: dump }) as Record<string, string>);
    const wait = (state: LoginState) => eventually(() => logins.get("g")?.state === state);
    try {
      const signedOut = await checkProfile({ runtime: "grok", kind: "subscription", key: "", via: {}, home, env: { ...process.env, FAKE_DUMP: dump } as Record<string, string>, machine: false, lang: "zh" });
      assert.equal(signedOut.state, "login");
      await logins.start({ id: "g", runtime: "grok", home }, "zh");
      await wait("needs_approval");
      const job = logins.get("g")!;
      assert.deepEqual([job.url, job.userCode], ["https://accounts.x.ai/oauth2/device?user_code=ABCD-1234", "ABCD-1234"]);
      assert.equal(started(dump).env.GROK_HOME, join(home, "grok"));
      writeFileSync(`${dump}.approve`, "");
      await wait("done");
      assert.ok(existsSync(join(home, "grok", "auth.json")));
      const check = await checkProfile({ runtime: "grok", kind: "subscription", key: "", via: {}, home, env: { ...process.env, FAKE_DUMP: dump } as Record<string, string>, machine: false, lang: "zh" });
      assert.equal(check.state, "ok");
      assert.deepEqual(check.models, ["grok-4.7", "grok-4.6"]);
      assert.match(check.detail ?? "", /grok@example\.com/);
    } finally {
      await logins.close();
    }
    assert.deepEqual(grokModels("Available models:\n  * grok-4.7 (default)\n  - grok-4.7-build-fast\n"), ["grok-4.7", "grok-4.7-build-fast"]);
  });

  test("its allowance is the included credits used of the current period", () => {
    const q = grokQuotaOf({ config: { creditUsagePercent: 37.4, currentPeriod: { type: "USAGE_PERIOD_TYPE_WEEKLY", start: "2026-10-13T00:00:00Z", end: "2026-10-20T00:00:00Z" } }, subscription_tier: "SuperGrok" }, "zh");
    assert.equal(q.state, "ok");
    assert.equal(q.plan, "SuperGrok");
    assert.deepEqual(q.windows, [{ label: "每周", usedPercent: 37, resetsAt: Date.parse("2026-10-20T00:00:00Z"), minutes: 7 * 24 * 60 }]);
    assert.equal(grokQuotaOf({ config: {} }, "zh").state, "unavailable");
    assert.equal(grokQuotaOf({ config: {}, subscription_tier: "SuperGrok Heavy" }, "zh").plan, "SuperGrok Heavy");
    // Nothing used yet: Grok Build's answer leaves the zero out.
    const fresh = grokQuotaOf({ config: { currentPeriod: { type: "USAGE_PERIOD_TYPE_WEEKLY", start: "2026-10-17T12:19:48.162200+00:00", end: "2026-10-24T12:19:48.162200+00:00" } }, subscription_tier: "SuperGrok Heavy" }, "zh");
    assert.deepEqual([fresh.state, fresh.windows[0]?.usedPercent, fresh.windows[0]?.label, fresh.detail], ["ok", 0, "每周", "SuperGrok Heavy"]);
  });
});
