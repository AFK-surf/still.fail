// The Devin driver (src/agents/devin.ts) against a fake devin (test/fake/devin: ACP as the Devin CLI speaks it) under the
// real runner: turns and their steps, what it is started with (its configuration, environment, the profile's key, the
// station's tools and the instructions' folder), a message put into the running turn (and one that came as it ended),
// failures and how they are told apart, cancel, a permission asked, the process exiting, resuming with the past Devin
// says again left out, the transcript it keeps read as a timeline and its usage counted, another model between turns,
// and a session taken up by a next driver (with a snapshot, and after a crash) with its turn's end told once; then what a
// profile runs it on, its sign-in in a terminal, its check and its allowance.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { CONFIG, DevinDriver, callOf, classifyFailure, devinArgs, devinCatalog, devinData, devinKey, outcomeOf, rulesFolder, variant } from "../src/agents/devin.ts";
import { profileEnv, profileRuntimes } from "../src/agents/profiles.ts";
import type { AgentSession, OpenOptions, Profile, RuntimeEvent } from "../src/agents/runtime.ts";
import { allLeft } from "../src/agents/runner.ts";
import { accessKinds, checkProfile, devinEmail, devinEmailIn, loginCommand } from "../src/accounts/profiles.ts";
import { LoginManager, type LoginState } from "../src/accounts/login.ts";
import { checkQuota } from "../src/accounts/quota.ts";
import { tr } from "../src/ops/i18n.ts";
import { platform } from "../src/platform/index.ts";
import { callsOf } from "../src/usage/counter.ts";
import { readTimeline, transcriptPath } from "../src/read/transcript.ts";

const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
process.env.PATH = `${fake}${delimiter}${process.env.PATH}`;
// Inherited, and not to reach the agent.
process.env.WINDSURF_API_KEY = "leaked";
process.env.DEVIN_MODEL = "leaked-model";
process.env.DEVIN_SESSIONS_DIR = "/elsewhere";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = mkdtempSync(process.platform === "win32" ? join(tmpdir(), "dv-") : "/tmp/dv-");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline.
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
const drivers: DevinDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver() {
  const d = new DevinDriver({ data });
  drivers.push(d);
  return d;
}

/// The sign-in page the fake's login prints (test/fake/devin.mjs).
const LOGIN_URL = "https://app.devin.ai/auth/cli/continue?state=6f1d2c3b-9a8e-4f70-b1c2-d3e4f5a6b7c8&prompt=select_account&code_challenge=q2W8x_Lm-3kZpRt7Yv0bNcJ4hUeSfAgD1iO5lK9wQyE&code_challenge_method=S256&cli_pkce_marker=1";
/// What `devin models list --format json` says (the fake's).
const LISTED = {
  families: [
    { slug: "swe-2", variants: [{ model_uid: "swe-2-high" }, { model_uid: "swe-2-medium" }, { model_uid: "swe-2-max" }, { model_uid: "swe-2-medium-lightning" }] },
    { slug: "claude-opus-5.5", variants: [{ model_uid: "claude-opus-5-5-medium" }, { model_uid: "claude-opus-5-5-low" }, { model_uid: "claude-opus-5-5-high-fast" }] },
    { slug: "kimi-k2.6", variants: [{ model_uid: "kimi-k2-6" }] },
    { slug: "glm-5.2", variants: [{ model_uid: "glm-5-2" }, { model_uid: "glm-5-2-max" }, { model_uid: "glm-5-2-1m" }] },
    {
      slug: "fusion",
      variants: [{ model_uid: "fusion-gpt-6-sol-low-sidekick-gpt-5-6-luna-high" }, { model_uid: "fusion-gpt-6-sol-max-sidekick-swe-2-medium" }, { model_uid: "fusion-gpt-6-sol-low-fast-sidekick-gpt-5-6-luna-high-priority" }],
    },
  ],
};
const MODELS = ["swe-2", "claude-opus-5-5", "kimi-k2-6", "glm-5-2"];
const EFFORTS = { "swe-2": ["medium", "high", "max"], "claude-opus-5-5": ["low", "medium"], "glm-5-2": ["max"] };

let n = 0;
/// A Devin account signed in (its key in the profile's devin/data, as `devin auth login` leaves it), with a workspace's
/// skills.
function options(extra: Partial<OpenOptions> = {}, signedIn = true): OpenOptions & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  mkdirSync(home, { recursive: true });
  if (signedIn) {
    mkdirSync(join(devinData(home), "devin"), { recursive: true });
    writeFileSync(join(devinData(home), "devin", "credentials.toml"), `windsurf_api_key = "devin-k${i}"\napi_server_url = "https://server.codeium.com"\n`);
  }
  // A workspace's skills (not the profile home's: agent-home.ts).
  const skills = join(data, `skills${i}`);
  mkdirSync(join(skills, "s1"), { recursive: true });
  const dump = join(data, `dump${i}`);
  return {
    key: `slack:T1:C${i}:1700000000.000${i}`,
    profile: { id: "dv", runtime: "devin", home, access: { kind: "subscription" }, env: { FAKE_DUMP: dump } },
    cwd: data,
    model: "swe-2",
    effort: "high",
    instructions: "be brief",
    skills,
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
const lines = (file: string) => readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const stdin = (dump: string) => lines(`${dump}.stdin`);
const said = (dump: string) => lines(`${dump}.out`);
const started = (dump: string) => lines(dump)[0]!;
const pretty = (v: unknown) => JSON.stringify(v, null, 2);
/// The timeline as the history shows it: each entry's kind, text, tool and whether it went well.
const timelineOf = (home: string, id: string) =>
  readTimeline("devin", transcriptPath("devin", home, id)!).map(({ kind, text, tool, ok }) => ({ kind, text, ...(tool ? { tool } : {}), ...(ok !== undefined ? { ok } : {}) }));

describe("the Devin driver", { concurrency: true }, () => {
  test("a turn completes with its steps live, from a process started with its configuration, environment, key, instructions and the station's tools", async () => {
    const d = driver();
    const o = options();
    const home = o.profile.home;
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    assert.match(session.id(), /^[a-z]+-[a-z]+$/, "Devin names it");
    await session.prompt("work");
    assert.equal(session.busy(), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.equal(session.busy(), false);
    assert.ok(!events.some((e) => e.type === "turnStarted"), "our own prompt's turn is not one started without us");
    // A thought, words, a command, a post through the station's tools (named as Claude Code names it), the reply.
    const starts = live(events).flatMap((e) => (e.kind === "start" ? [[e.step, e.tool ?? null, e.input ?? null]] : []));
    assert.deepEqual(starts, [
      ["thinking", null, null], ["text", null, null], ["tool", "exec", pretty({ command: "sleep 1; echo done" })],
      ["tool", "mcp__stillfail__chat_post", pretty({ to: "here", text: "posted words" })], ["text", null, null],
    ]);
    assert.deepEqual(deltas(events), ["thinking it over", "Running.", "done", "Posted.", "do", "ne"]);
    assert.equal(live(events).filter((e) => e.kind === "end").length, starts.length, "every step started ends");

    // Its configuration (not the person's other tools', no updating itself), its model at its level.
    const run = started(o.dump);
    const config = join(home, "devin", "config.json");
    assert.deepEqual(run.argv, ["--config", config, "acp", "--model", "swe-2-high"]);
    assert.deepEqual(JSON.parse(run.config), CONFIG);
    assert.ok(Object.values(CONFIG.read_config_from).every((v) => v === false));
    assert.equal(CONFIG.auto_update, false);
    // Its store in the shared sessions; nobody else's key or model.
    assert.equal(run.env.DEVIN_SESSIONS_DIR, join(home, "devin", "sessions", "store"));
    assert.equal(run.env.WINDSURF_API_KEY, undefined, "not the station's own");
    assert.equal(run.env.DEVIN_MODEL, undefined);
    assert.equal(run.env.FAKE_DUMP, o.dump, "the profile's own variables");

    // Signed in with the profile's key; the station's tools with the session's token; its instructions a folder of the
    // session's own given beside the working directory; no approvals.
    const sent = stdin(o.dump);
    assert.deepEqual(sent.map((m) => m.method), ["initialize", "authenticate", "session/new", "session/set_config_option", "session/prompt"]);
    assert.match(devinKey(home) ?? "", /^devin-k\d+$/);
    assert.deepEqual(sent[1].params, { methodId: "devin-browser", _meta: { api_key: devinKey(home) } });
    assert.equal(sent[2].params.cwd, o.cwd);
    assert.deepEqual(sent[2].params.mcpServers, [{ type: "http", name: "stillfail", url: o.mcpUrl, headers: [{ name: "Authorization", value: "Bearer tok" }] }]);
    const [rules] = sent[2].params.additionalDirectories;
    assert.deepEqual(sent[2].params.additionalDirectories, [rules]);
    assert.match(readFileSync(join(rules, ".devin", "rules", "stillfail.md"), "utf8"), /^---\ndescription: still\.fail station\ntrigger: always_on\n---\nbe brief\n\n.*mcp__stillfail__chat_post.*\n$/s);
    assert.ok(!existsSync(join(rules, "AGENTS.md")), "no memory but the one with the instructions");
    assert.ok(existsSync(join(rules, ".devin", "skills", "s1")), "the workspace's skills linked in");
    assert.deepEqual(sent[3].params, { sessionId: session.id(), configId: "mode", value: "bypass" });
    assert.deepEqual(sent[4].params, { sessionId: session.id(), prompt: [{ type: "text", text: "work" }] });
    assert.ok(said(o.dump).some((m) => m.id === sent[3].id && m.result !== undefined), "bypass taken");

    await assert.rejects(session.prompt("x").then(() => session.prompt("y")), /a turn is already running/);
    await until(ended(2));
    assert.equal(await session.steer("more"), false, "nothing to put it into: the station starts a turn of its own");

    // The transcript it keeps (Cursor's lines) is read as a timeline: what the station said, the thoughts, the words,
    // each call with its input and result.
    const path = transcriptPath("devin", home, session.id());
    assert.equal(path, join(home, "devin", "sessions", `${session.id()}.jsonl`));
    assert.deepEqual(timelineOf(home, session.id()), [
      { kind: "user", text: "work" },
      { kind: "thinking", text: "thinking it over" },
      { kind: "assistant", text: "Running." },
      { kind: "tool_call", text: pretty({ command: "sleep 1; echo done" }), tool: "exec" },
      { kind: "tool_result", text: "done", ok: true },
      { kind: "tool_call", text: pretty({ to: "here", text: "posted words" }), tool: "mcp__stillfail__chat_post" },
      { kind: "tool_result", text: "Posted.", ok: true },
      { kind: "assistant", text: "done" },
      { kind: "user", text: "x" },
      { kind: "thinking", text: "thinking it over" },
      { kind: "assistant", text: "x" },
    ]);
    // Each turn's counts: its calls' (each said twice, counted once), input less what the cache read; the context its
    // last call had, of the model's window; then its end.
    const kept = lines(path!);
    const usage = kept.filter((l) => l.type === "usage");
    assert.deepEqual(usage.map(({ model, usage, calls, context, window }) => ({ model, usage, calls, context, window })), [
      { model: "swe-2", usage: { inputTokens: 2100, cacheReadTokens: 1200, cacheWriteTokens: 0, outputTokens: 153 }, calls: 3, context: 1252, window: 262000 },
      { model: "swe-2", usage: { inputTokens: 600, cacheReadTokens: 400, cacheWriteTokens: 0, outputTokens: 50 }, calls: 1, context: 1050, window: 262000 },
    ]);
    const prompts = sent.filter((m) => m.method === "session/prompt").map((m) => m.id.slice("prompt:".length));
    assert.equal(usage[0].run, prompts[0], "a turn's counts named by its prompt");
    assert.deepEqual(kept.filter((l) => l.type === "end").map((l) => l.status), ["finished", "finished"]);
    assert.deepEqual(kept[0], { time: kept[0].time, type: "session", id: session.id(), cwd: o.cwd });
    const calls = callsOf("devin", readFileSync(path!, "utf8"), false, { model: null, codexId: null });
    assert.deepEqual(calls.map(({ id, model, input, cacheRead, cacheWrite, output }) => ({ id, model, input, cacheRead, cacheWrite, output })), [
      { id: `devin:${usage[0].run}`, model: "swe-2", input: 2100, cacheRead: 1200, cacheWrite: 0, output: 153 },
      { id: `devin:${usage[1].run}`, model: "swe-2", input: 600, cacheRead: 400, cacheWrite: 0, output: 50 },
    ]);
    // Each turn's calls (3 and 1), and the context it ended with, of the model's window: what a chat says of them.
    assert.deepEqual(calls.map(({ calls, context, window }) => [calls, context, window]), [[3, 1252, 262000], [1, 1050, 262000]]);

    // Between turns, another model (its family's option) and level are set in the process; one it has not, not.
    assert.equal(session.retune?.({ ...o, model: "claude-opus-5-5", effort: "low" }), true);
    assert.equal(session.retune?.({ ...o, model: "gpt-9" }), false);
    const configs = () => stdin(o.dump).filter((m) => m.method === "session/set_config_option").slice(1);
    await eventually(() => configs().length === 2);
    assert.deepEqual(configs().map((m) => [m.params.configId, m.params.value]), [["model", "claude-opus-5-5-medium"], ["thought_level", "low"]]);
    await eventually(() => configs().every((m) => said(o.dump).some((a) => a.id === m.id)));
    assert.ok(configs().every((m) => said(o.dump).find((a) => a.id === m.id)?.error === undefined), "Devin took both");
    await session.prompt("say:three");
    await until(ended(3));
    assert.equal(lines(path!).filter((l) => l.type === "usage").at(-1).model, "claude-opus-5-5", "the next turn's counts are the model's");
    await session.dispose();
    await until((e) => e.some((x) => x.type === "closed"));
  });

  test("a message for the running turn goes into it, answered with it: the turn ends once", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("hold");
    await until((e) => deltas(e).join("").includes("holding"));
    assert.equal(session.retune?.({ ...o, model: "kimi-k2-6" }), false, "not while a turn runs");
    assert.equal(await session.steer("and this"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(deltas(events).join("").includes("heard: and this"));
    const prompts = stdin(o.dump).filter((m) => m.method === "session/prompt");
    assert.deepEqual(prompts.map((m) => [m.id.split(":")[0], m.params.prompt[0].text]), [["prompt", "hold"], ["steer", "and this"]]);
    // Both prompts are answered at the turn's end (the message's after the turn's own): the next turn is the next.
    await session.prompt("say:after");
    await until(ended(2));
    assert.equal(ends(events).length, 2);
    assert.ok(!events.some((e) => e.type === "turnStarted"));
    assert.deepEqual(outcome(events, 1), { kind: "completed" });
    // The message put in is the history's, in its place.
    assert.deepEqual(timelineOf(o.profile.home, session.id()).filter((e) => e.kind === "user" || e.kind === "assistant").map((e) => [e.kind, e.text]), [
      ["user", "hold"], ["assistant", "holding"], ["user", "and this"], ["assistant", "heard: and this"], ["user", "say:after"], ["assistant", "after"],
    ]);
    await session.dispose();
  });

  test("a message that comes as the turn ends is a turn of its own: started when its steps come, ended by its answer", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("late");
    await until((e) => deltas(e).join("").includes("first"));
    assert.equal(await session.steer("then this"), true);
    await until(ended(2));
    assert.deepEqual(events.filter((e) => e.type === "turnStarted" || e.type === "turnEnded").map((e) => e.type), ["turnEnded", "turnStarted", "turnEnded"]);
    assert.deepEqual([outcome(events, 0), outcome(events, 1)], [{ kind: "completed" }, { kind: "completed" }]);
    assert.ok(deltas(events).join("").includes("late then this"));
    assert.equal(session.busy(), false);
    const usage = lines(transcriptPath("devin", o.profile.home, session.id())!).filter((l) => l.type === "usage");
    const steer = stdin(o.dump).find((m) => m.method === "session/prompt" && m.id.startsWith("steer:"));
    assert.deepEqual(usage.map((u) => u.calls), [1, 1], "each turn its own counts");
    assert.equal(usage[1].run, steer.id.slice("steer:".length));
    await session.prompt("say:next");
    await until(ended(3));
    assert.deepEqual(outcome(events, 2), { kind: "completed" });
    await session.dispose();
  });

  test("a failed prompt is told apart by what Devin said; not signed in is the sign-in's", async () => {
    assert.equal(classifyFailure("ACP host has not authenticated"), "auth");
    assert.equal(classifyFailure("Monthly ACU limit reached"), "rate_limit");
    assert.equal(classifyFailure("Your usage quota has been exhausted"), "rate_limit");
    assert.equal(classifyFailure("the model failed"), "model");
    assert.deepEqual(outcomeOf({ result: { stopReason: "end_turn" } }), { kind: "completed" });
    assert.deepEqual(outcomeOf({ result: { stopReason: "cancelled" } }), { kind: "aborted" });
    assert.deepEqual(outcomeOf({ result: { stopReason: "refusal" } }), { kind: "failed", reason: "model", message: "the model refused" });
    assert.deepEqual(outcomeOf({ error: { code: -32602, message: "Invalid params", data: "Invalid value 'x' for config option 'model'" } }), {
      kind: "failed", reason: "model", message: "Invalid params: Invalid value 'x' for config option 'model'",
    });
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    const cases = [["fail:auth", "auth"], ["fail:acu", "rate_limit"], ["fail:quota", "rate_limit"], ["fail:model", "model"]] as const;
    for (const [k, [text, reason]] of cases.entries()) {
      await session.prompt(text);
      await until(ended(k + 1));
      const o = outcome(events, k);
      assert.equal(o.kind, "failed", text);
      assert.equal((o as { reason: string }).reason, reason, text);
    }
    assert.deepEqual(outcome(events, 3), { kind: "failed", reason: "model", message: "model glm-9 is not available" });
    assert.equal((outcome(events, 2) as { message: string }).message, "Internal error: Your usage quota has been exhausted");
    assert.equal(session.busy(), false);
    await session.dispose();
    // No sign-in in the profile: nothing to authenticate with (the inherited key is not its), and the prompt fails so.
    const o = options({}, false);
    const b = listen();
    const signedOut = await driver().open(o, b.push);
    assert.ok(!stdin(o.dump).some((m) => m.method === "authenticate"));
    await signedOut.prompt("say:hi");
    await b.until(ended(1));
    assert.equal((outcome(b.events) as { reason: string }).reason, "auth");
    assert.match((outcome(b.events) as { message: string }).message, /has not authenticated/);
    const end = lines(transcriptPath("devin", o.profile.home, signedOut.id())!).at(-1);
    assert.deepEqual([end.type, end.status], ["end", "error"]);
    await signedOut.dispose();
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
    assert.deepEqual(stdin(o.dump).find((m) => m.method === "session/cancel")?.params, { sessionId: session.id() });
    assert.equal(await session.steer("too late"), false);
    await session.prompt("say:again");
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "completed" });
    assert.deepEqual(lines(transcriptPath("devin", o.profile.home, session.id())!).filter((l) => l.type === "end").map((l) => l.status), ["cancelled", "finished"]);
    await session.dispose();
  });

  test("a permission it asks is allowed for that call only; a question of its own is answered as not supported", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("ask");
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    const sent = stdin(o.dump);
    assert.deepEqual(sent.find((m) => m.id === "perm-1")?.result, { outcome: { outcome: "selected", optionId: "allow-once" } });
    assert.equal(sent.find((m) => m.id === "question-1")?.error?.code, -32601);
    await session.dispose();
  });

  test("a call to the station's tools failing as its server unreachable is told as toolsLost", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(), push);
    await session.prompt("tools");
    await until(ended(1));
    assert.ok(events.some((e) => e.type === "toolsLost" && /Failed to connect to MCP server 'stillfail'/.test(e.why)));
    assert.deepEqual(outcome(events), { kind: "completed" });
    await session.dispose();
  });

  test("the process exiting during a turn fails it as exited, then closes the session", async () => {
    const d = driver();
    const o = options();
    const { events, push, until } = listen();
    const session = await d.open(o, push);
    await session.prompt("exit");
    await until((e) => e.some((x) => x.type === "closed"));
    const out = outcome(events);
    assert.equal(out.kind, "failed");
    assert.equal((out as { reason: string }).reason, "exited");
    assert.equal(ends(events).length, 1);
    await assert.rejects(session.prompt("x"), /closed/);
    const kept = lines(transcriptPath("devin", o.profile.home, session.id())!);
    assert.deepEqual(kept.slice(-2).map((l) => [l.type, l.text ?? l.status]), [["assistant", "partial"], ["end", "error"]]);
  });

  test("a session is loaded by its id in a new process, the past Devin says again not a turn nor kept again; one the station has not is refused before it starts", async () => {
    const o = options();
    const a = listen();
    const first = await driver().open(o, a.push);
    await first.prompt("work");
    await a.until(ended(1));
    const id = first.id();
    await first.dispose();
    const b = listen();
    const again = await driver().open({ ...o, resume: id }, b.push);
    assert.equal(again.id(), id);
    const loaded = stdin(o.dump).filter((m) => m.method === "session/load");
    assert.equal(loaded.length, 1);
    assert.deepEqual(Object.keys(loaded[0].params).sort(), ["additionalDirectories", "cwd", "mcpServers", "sessionId"]);
    assert.equal(loaded[0].params.sessionId, id);
    assert.equal(loaded[0].params.mcpServers[0].headers[0].value, "Bearer tok");
    // Devin said the session's past before answering: none of it is the station's.
    assert.ok(said(o.dump).filter((m) => m.method === "session/update" && m.params.update.sessionUpdate === "agent_message_chunk").length > 4, "the past was said again");
    assert.equal(b.events.length, 0, "nothing live of the past");
    assert.equal(again.busy(), false);
    assert.equal(stdin(o.dump).filter((m) => m.method === "session/new").length, 1, "not a new one");
    await again.prompt("say:two");
    await b.until(ended(1));
    assert.ok(!b.events.some((e) => e.type === "turnStarted"));
    assert.deepEqual(deltas(b.events), ["thinking it over", "tw", "o"]);
    const timeline = timelineOf(o.profile.home, id);
    assert.deepEqual(timeline.filter((e) => e.kind === "user").map((e) => e.text), ["work", "say:two"]);
    assert.deepEqual(timeline.filter((e) => e.kind === "assistant").map((e) => e.text), ["Running.", "done", "two"]);
    assert.equal(timeline.filter((e) => e.kind === "tool_call").length, 2);
    assert.equal(lines(transcriptPath("devin", o.profile.home, id)!).filter((l) => l.type === "session").length, 1);
    await again.dispose();
    await assert.rejects(driver().open({ ...o, resume: "gone-away" }, () => {}), /no Devin session gone-away/);
  });

  test("the instructions' folder is the session's own, written again with its instructions", () => {
    const home = join(data, "rules-home");
    mkdirSync(home, { recursive: true });
    const a = rulesFolder(home, "k1", "first");
    assert.equal(rulesFolder(home, "k1", "second"), a);
    assert.notEqual(rulesFolder(home, "k2", "other"), a);
    assert.match(readFileSync(join(a, ".devin", "rules", "stillfail.md"), "utf8"), /\n---\nsecond\n\nThe station's tools/);
    assert.ok(a.startsWith(join(home, "devin", "station")));
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
      assert.deepEqual(outcome(b.events), { kind: "completed" });
      assert.ok(deltas(b.events).join("").includes("heard: go on"));
      // The message's answer comes after the turn's: not another end.
      await taken.prompt("say:after");
      await b.until(ended(2));
      assert.deepEqual(outcome(b.events, 1), { kind: "completed" });
      const all = [...a.events, ...b.events];
      assert.equal(ends(all).length, 2, "each turn's end, once");
      assert.equal(deltas(all).join("").split("holding").length - 1, 1, "every delta once");
      const starts = live(all).filter((e) => e.kind === "start").length;
      assert.equal(live(all).filter((e) => e.kind === "end").length, starts, "every step started ends");
      assert.equal(b.events.filter((e) => e.type === "turnStarted").length, crashed ? 1 : 0);
      await taken.dispose();
      await b.until((e) => e.some((x) => x.type === "closed"));
      assert.ok(!a.events.some((e) => e.type === "closed"), "the first driver hears nothing after letting go");
    });
  }
});

describe("what a profile runs Devin on", () => {
  const profile = (access: Record<string, unknown>, more: Partial<Profile> = {}): Profile => ({ id: "p", runtime: "devin", home: "/h", access, ...more });

  test("a Devin account signs in in its home, or its own variables run it; its model a family at a thinking level", () => {
    assert.deepEqual(accessKinds("devin"), ["subscription", "env"]);
    assert.deepEqual(profileRuntimes(profile({ kind: "subscription" })), ["devin"]);
    assert.deepEqual(profileEnv(profile({ kind: "subscription" }), "devin"), {});
    assert.deepEqual(profileRuntimes(profile({ kind: "env" })), ["devin"]);
    assert.equal(loginCommand("devin", "/h"), `XDG_DATA_HOME=${join("/h", "devin", "data")} devin auth login --force-manual-token-flow`);
    assert.deepEqual(devinArgs("/c.json", undefined, "high"), ["--config", "/c.json", "acp"]);
    assert.deepEqual(devinArgs("/c.json", "glm-5-2", undefined), ["--config", "/c.json", "acp", "--model", "glm-5-2"]);
    assert.deepEqual(devinArgs("/c.json", "swe-2", "max"), ["--config", "/c.json", "acp", "--model", "swe-2-max"]);
    assert.equal(variant("swe-2", "fast"), "swe-2", "not a level: the family at its own");
  });

  test("the account's models are the families at their levels, not the faster ones; a call's counts its input less the cache's", () => {
    assert.deepEqual(devinCatalog(LISTED), { models: MODELS, efforts: EFFORTS });
    assert.deepEqual(devinCatalog({}), { models: [], efforts: {} });
    assert.deepEqual(callOf({ sessionUpdate: "usage_update", used: 11193, size: 262000, _meta: { "cognition.ai/inputTokens": 11125, "cognition.ai/outputTokens": 68, "cognition.ai/cachedReadTokens": 128 } }), {
      inputTokens: 10997, cacheReadTokens: 128, cacheWriteTokens: 0, outputTokens: 68,
    });
    assert.equal(devinEmailIn("User:\n  Name:              Someone\n  Email:             someone@example.com\n"), "someone@example.com");
    assert.equal(devinEmailIn("Not logged in."), null);
  });

  test("its allowance is not said to the station", async () => {
    const q = await checkQuota({ id: "p", runtime: "devin", home: "/h", access: { kind: "subscription" } } as never, {}, undefined, undefined, "en");
    assert.equal(q.state, "unsupported");
    assert.equal(q.detail, tr("en", "station.quota.devinUnsupported"));
  });

  test("its sign-in, in a terminal, relays the page and the code pasted back; its check then says the account and its models", { skip: process.platform === "win32" && "no terminal to sign in in" }, async () => {
    const home = join(data, "login");
    const dump = join(data, "login-dump");
    const env = { ...process.env, FAKE_DUMP: dump } as Record<string, string>;
    const logins = new LoginManager(data, { claude: "claude", codex: "codex", devin: "devin" }, () => env);
    const wait = (state: LoginState) => eventually(() => logins.get("d")?.state === state);
    const check = () => checkProfile({ runtime: "devin", kind: "subscription", key: "", via: {}, home, env, machine: false, lang: "en" });
    try {
      const signedOut = await check();
      assert.equal(signedOut.state, "login");
      assert.equal(devinEmail(home), null);
      // A code refused: the sign-in fails with what Devin said.
      await logins.start({ id: "d", runtime: "devin", home }, "en");
      await wait("needs_code");
      await logins.submitCode("d", "bad", "en");
      await wait("failed");
      assert.match(logins.get("d")!.error ?? "", /Invalid code/);
      await logins.start({ id: "d", runtime: "devin", home }, "en");
      await wait("needs_code");
      // The page's link once (its OSC 8 target and its text are the same), whole.
      assert.equal(logins.get("d")!.url, LOGIN_URL);
      const run = lines(dump).at(-1);
      assert.deepEqual(run.argv, ["auth", "login", "--force-manual-token-flow"]);
      assert.equal(run.env.XDG_DATA_HOME, devinData(home));
      assert.equal(run.env.WINDSURF_API_KEY, undefined);
      await logins.submitCode("d", " abc123 ", "en");
      await wait("done");
      assert.equal(devinKey(home), "devin-abc123");
      const signedIn = await check();
      assert.equal(signedIn.state, "ok");
      assert.deepEqual(signedIn.models, MODELS);
      assert.deepEqual(signedIn.modelEfforts, { devin: EFFORTS });
      assert.match(signedIn.detail ?? "", /someone@example\.com/);
      assert.equal(devinEmail(home), "someone@example.com", "noted for naming the account");
      assert.equal(lines(dump).filter((l) => l.argv[0] === "auth" && l.argv[1] === "status").every((l) => l.env.XDG_DATA_HOME === devinData(home)), true);
    } finally {
      await logins.close();
    }
  });

  test("where there is no terminal to sign in in, the sign-in fails at once and says so", async () => {
    const terminal = platform.terminal;
    platform.terminal = () => null;
    const logins = new LoginManager(data, { claude: "claude", codex: "codex", devin: "devin" });
    try {
      const job = await logins.start({ id: "nt", runtime: "devin", home: join(data, "no-terminal") }, "en");
      assert.deepEqual([job.state, job.error], ["failed", tr("en", "station.login.devinNoTerminal")]);
      assert.equal(logins.get("nt")?.state, "failed");
    } finally {
      platform.terminal = terminal;
      await logins.close();
    }
  });
});
