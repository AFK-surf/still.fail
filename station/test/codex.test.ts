// The Codex driver (src/agents/codex.ts) against a fake app-server (test/fake/codex: JSON-RPC as codex speaks it) under
// the real runner: turns, failures by their code, abort, steer, a turn of its own, the app-server exiting, one
// app-server per profile and its restart once a profile edit leaves it idle, what it is started with, and threads taken
// up by a next driver (with a snapshot, and after a crash) with the turn's end told once and no live event twice.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import fs from "node:fs";
import { writeFile } from "node:fs/promises";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { CodexDriver, classifyCodexError, type CodexDriverOptions } from "../src/agents/codex.ts";
import { REPO_RULES_COMMAND } from "../src/agents/repo-rules.ts";
import { ackedOffset, outFile, runnerId } from "../src/agents/process.ts";
import { allLeft, existingRunners, type RunnerInfo } from "../src/agents/runner.ts";
import type { OpenOptions, Profile, RuntimeEvent } from "../src/agents/runtime.ts";
import { readAgentEnvFrom } from "../src/ops/agent-env.ts";
import { transcriptPaths } from "../src/read/transcript.ts";
import { tempDir } from "./temp-dir.ts";

const fake = join(dirname(fileURLToPath(import.meta.url)), "fake");
process.env.PATH = `${fake}${delimiter}${process.env.PATH}`;
// Inherited, and not to reach the agent.
process.env.OPENAI_API_KEY = "leaked";
process.env.CODEX_HOME = "/nowhere";
// Short: the runners' sockets live under it (104 bytes at most on macOS).
const data = tempDir(process.platform === "win32" ? join(tmpdir(), "cx-") : "/tmp/cx-");
const skills = join(data, "skills");
mkdirSync(join(skills, "mine"), { recursive: true });
writeFileSync(join(skills, "mine", "SKILL.md"), "");
const bundle = join(data, "cert.pem");
writeFileSync(bundle, "");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/// Looks every 20 ms until `done` holds: what real processes do has no event here. No deadline (it comes, however
/// slow the machine, or the test hangs).
async function eventually(done: () => boolean) {
  while (!done()) await sleep(20);
}
/// The fifos a `gate:<n>:<k>:<name>` turn waits at (test/fake/codex.mjs): `open(part)` lets it go on.
function gates(dump: string, name: string) {
  const at = `${dump}.${name}`;
  if (process.platform !== "win32") for (const part of ["a", "b"]) execFileSync("/usr/bin/mkfifo", [`${at}.${part}`]);
  return { open: (part: "a" | "b") => writeFile(`${at}.${part}`, "go"), said: () => existsSync(`${at}.said`) };
}
const drivers: CodexDriver[] = [];
after(async () => {
  await Promise.all(drivers.map((d) => d.shutdown()));
  rmSync(data, { recursive: true, force: true });
});

function driver(more: Partial<CodexDriverOptions> = {}) {
  const d = new CodexDriver({ data, hostSkills: skills, caBundle: bundle, ...more });
  drivers.push(d);
  return d;
}

let n = 0;
/// A profile of its own (so an app-server of its own), its starts and stdin dumped.
function profile(extra: Record<string, unknown> = {}): Profile & { dump: string } {
  const i = ++n;
  const home = join(data, `h${i}`);
  const dump = join(data, `dump${i}`);
  return { id: `cx${i}`, runtime: "codex", home, access: { kind: "opencode-go", key: "k2" }, env: { FAKE_DUMP: dump }, dump, ...extra };
}

function options(p: Profile, extra: Partial<OpenOptions> = {}): OpenOptions {
  return { key: `chat:${p.id}:${++n}`, profile: p, cwd: data, instructions: "be brief", mcpToken: "tok", mcpUrl: "http://127.0.0.1:4750/mcp", route: "r", ...extra };
}

function listen() {
  const events: RuntimeEvent[] = [];
  const push = (e: RuntimeEvent) => void events.push(e);
  const until = (what: (events: RuntimeEvent[]) => boolean) => eventually(() => what(events));
  return { events, push, until };
}

const ends = (events: RuntimeEvent[]) => events.filter((e) => e.type === "turnEnded");
const ended = (k: number) => (events: RuntimeEvent[]) => ends(events).length >= k;
const deltas = (events: RuntimeEvent[]) => events.flatMap((e) => (e.type === "live" && e.event.kind === "delta" ? [e.event.text] : []));
const outcome = (events: RuntimeEvent[], k = 0) => (ends(events)[k] as Extract<RuntimeEvent, { type: "turnEnded" }>).outcome;
const starts = (dump: string) => readFileSync(dump, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const stdin = (dump: string) => readFileSync(`${dump}.stdin`, "utf8").trim().split("\n").map((l) => JSON.parse(l));

// Each test has its own driver, profile and runners: they run side by side.
describe("the Codex driver", { concurrency: true }, () => {
  test("the software page only updates the installation this profile actually runs", { skip: process.platform === "win32" }, async () => {
    const p = profile();
    const stationBin = join(data, `station-bin-${p.id}`), otherBin = join(data, `profile-bin-${p.id}`);
    mkdirSync(stationBin);
    mkdirSync(otherBin);
    for (const bin of [stationBin, otherBin]) writeFileSync(join(bin, "codex"), "#!/bin/sh\necho codex-cli\n", { mode: 0o755 });
    const d = driver({ env: { PATH: stationBin } });
    assert.equal(await d.updateMatchesStation({ ...p, env: { PATH: stationBin } }), true);
    assert.equal(await d.updateMatchesStation({ ...p, env: { PATH: otherBin } }), false);
  });

  for (const resumed of [false, true]) test(`a ${resumed ? "resumed" : "new"} thread uses the transcript path Codex gave, before and after the file appears`, async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_ROLLOUT: "1" };
    const other = join(data, `unrelated-${p.id}`, "transcripts", "codex");
    for (let i = 0; i < 100; i++) mkdirSync(join(other, String(i)), { recursive: true });
    const session = await d.open(options(p, resumed ? { resume: "th-existing" } : {}), listen().push);
    const path = join(p.home, "sessions", "2026", "11", "03", `rollout-${session.id()}.jsonl`);
    const listed: string[] = [];
    const real = fs.readdirSync;
    fs.readdirSync = ((dir: fs.PathLike, ...args: unknown[]) => (listed.push(String(dir)), (real as (...xs: unknown[]) => unknown)(dir, ...args))) as typeof real;
    syncBuiltinESMExports();
    try {
      assert.deepEqual(transcriptPaths("codex", join(data, `unrelated-${p.id}`), [p.home], [session.id()], [], { anywhere: false }), { paths: [], current: false });
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, "");
      assert.deepEqual(transcriptPaths("codex", join(data, `unrelated-${p.id}`), [p.home], [session.id()], [], { anywhere: false }), { paths: [path], current: true });
      assert.deepEqual(listed, [], "unrelated rollout directories are not read");
    } finally {
      fs.readdirSync = real;
      syncBuiltinESMExports();
      await session.dispose();
    }
  });

  test("a thread taken up from an older station learns its transcript path", async () => {
    const first = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_ROLLOUT_ON_READ: "1" };
    const dataDir = join(data, `old-station-${p.id}`);
    const other = join(dataDir, "transcripts", "codex");
    for (let i = 0; i < 100; i++) mkdirSync(join(other, String(i)), { recursive: true });
    const one = await first.open(options(p), () => {});
    const path = join(p.home, "sessions", "2026", "11", "03", `rollout-${one.id()}.jsonl`);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "");
    const snapshot = JSON.parse(JSON.stringify(one.snapshot()));
    assert.equal(snapshot.transcriptPath, undefined);
    first.detach();
    await allLeft();
    const next = driver();
    const events = listen();
    const taken = await next.adopt(options(p, { resume: one.id() }), snapshot, events.push);
    await taken.prompt("say:after");
    await events.until(ended(1));
    const listed: string[] = [];
    const real = fs.readdirSync;
    fs.readdirSync = ((dir: fs.PathLike, ...args: unknown[]) => (listed.push(String(dir)), (real as (...xs: unknown[]) => unknown)(dir, ...args))) as typeof real;
    syncBuiltinESMExports();
    try {
      assert.deepEqual(transcriptPaths("codex", dataDir, [p.home], [one.id()], [], { anywhere: false }), { paths: [path], current: true });
      assert.deepEqual(listed, [], "taking up an existing thread does not scan unrelated rollouts");
    } finally {
      fs.readdirSync = real;
      syncBuiltinESMExports();
      await taken.dispose();
    }
  });

  test("a text-only request has no shell, MCP server or writable environment", async () => {
    const d = driver();
    const p = profile();
    const session = await d.open(options(p, { textOnly: true }), listen().push);
    const start = stdin(p.dump).find((m) => m.method === "thread/start");
    assert.equal(start.params.sandbox, "read-only");
    assert.equal(start.params.ephemeral, true);
    assert.deepEqual(start.params.environments, []);
    assert.equal(start.params.config["features.shell_tool"], false);
    assert.equal(start.params.config["features.unified_exec"], false);
    assert.equal(start.params.config["features.view_image"], false);
    assert.equal(start.params.config["features.goals"], false);
    assert.deepEqual(start.params.config.mcp_servers, {});
    assert.equal(start.params.config.hooks, undefined, "no tools, no rules to tell");
    assert.ok(stdin(p.dump).some((m) => m.method === "mcpServerStatus/list"));
    assert.ok(!stdin(p.dump).some((m) => m.method === "config/read"), "MCP credentials are not read into the runner log");
    await session.dispose();
  });

  test("a text-only request refuses a server that still exposes MCP tools", async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_MCP_UNAVOIDABLE: "1" };
    await assert.rejects(d.open(options(p, { textOnly: true }), listen().push), /cannot open a text-only Codex session/);
    assert.ok(!stdin(p.dump).some((m) => m.method === "turn/start"));
  });

  test("a text-only request disables configured MCP servers for its own thread", async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_MCP_CONFIGURED: "1" };
    const session = await d.open(options(p, { textOnly: true }), listen().push);
    const start = stdin(p.dump).find((m) => m.method === "thread/start");
    assert.deepEqual(start.params.config.mcp_servers, { configured: { enabled: false } });
    await session.dispose();
  });

  test("a text-only request disables servers added by the working directory before sending any text", async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_MCP_PROJECT: "1" };
    const session = await d.open(options(p, { textOnly: true }), listen().push);
    const requests = stdin(p.dump);
    const starts = requests.filter((m) => m.method === "thread/start");
    assert.equal(starts.length, 2);
    assert.deepEqual(starts[1].params.config.mcp_servers, { configured: { enabled: false } });
    assert.ok(requests.some((m) => m.method === "thread/unsubscribe"));
    assert.ok(!requests.some((m) => m.method === "turn/start" || m.method === "config/read"));
    await session.dispose();
  });

  test("an incomplete Codex is reported before it starts a turn and its status is refreshed", async () => {
    let refreshed = 0;
    const d = driver({
      missingHost: async () => ({ binary: "/codex", helper: "/codex-code-mode-host" }),
      incompleteInstallation: () => { refreshed++; },
    });
    const p = profile();
    await assert.rejects(d.open(options(p), () => {}), /Codex.*缺少执行组件/);
    assert.equal(refreshed, 1);
    assert.equal(existsSync(p.dump), false, "the broken app-server is not started");
  });

  test("a text-only request does not need the code-mode host", async () => {
    let probed = false;
    const d = driver({ missingHost: async () => { probed = true; return { binary: "/codex", helper: "/codex-code-mode-host" }; } });
    const session = await d.open(options(profile(), { textOnly: true }), listen().push);
    assert.equal(probed, false);
    await session.dispose();
  });

  test("a new sign-in replaces the app-server after its running turn, and new requests wait for it", async () => {
    const d = driver();
    const p = profile();
    const { events, push, until } = listen();
    const session = await d.open(options(p), push);
    await session.prompt("hold:1");
    await until((e) => deltas(e).length > 0);
    await d.loginChanged(p.id);
    let answered = false;
    const limits = d.rateLimits(p).then((value) => { answered = true; return value; });
    await sleep(100);
    assert.equal(answered, false, "a request does not use the old process while its turn runs");
    assert.equal(starts(p.dump).length, 1);
    assert.equal(await session.steer("finish"), true);
    await until(ended(1));
    assert.equal(outcome(events).kind, "completed");
    assert.deepEqual(await limits, { rateLimits: { primary: { usedPercent: 5 } } });
    assert.equal(starts(p.dump).length, 2, "the next request uses a new process");
    await session.dispose();
  });

  test("a borrowed login about to run out is lent again under the running app-server, not by starting another", async () => {
    let until = Date.now() + 3600_000;
    const writes: number[] = [];
    const d = driver({ lent: { borrowed: () => true, write: async () => (writes.push(until), until) } });
    const p = profile();
    const { events, push, until: wait } = listen();
    const session = await d.open(options(p), push);
    assert.equal(writes.length, 1, "lent as it starts");
    await session.prompt("cmd");
    await wait(ended(1));
    assert.equal(writes.length, 2, "lent again before a turn, as it runs out within hours");
    until = Date.now() + 48 * 3600_000;
    const other = await d.open(options(p), () => {});
    assert.equal(writes.length, 3, "and as another session opens on it");
    await session.prompt("cmd");
    await wait(ended(2));
    assert.equal(writes.length, 3, "lasting long enough, it is not lent again");
    assert.equal(starts(p.dump).length, 1, "one app-server all along");
    await Promise.all([session.dispose(), other.dispose()]);
  });

  test("a turn completes, on an app-server started with the flags and environment of codex.rs", async () => {
    const d = driver();
    const p = profile();
    const { events, push, until } = listen();
    const session = await d.open(options(p, { model: "gpt-x", effort: "high" }), push);
    assert.match(session.id(), /^th-/);
    await session.prompt("cmd");
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(!events.some((e) => e.type === "turnStarted"));
    const live = events.flatMap((e) => (e.type === "live" ? [e.event] : []));
    const steps = live.filter((e) => e.kind !== "phase");
    const command = (steps[0] as { id: string }).id;
    assert.deepEqual(steps.slice(0, 3), [
      { kind: "start", id: command, step: "tool", tool: "shell", input: "ls" },
      { kind: "delta", id: command, field: "output", text: "a\n" },
      { kind: "end", id: command },
    ]);
    assert.deepEqual(steps.slice(3).map((e) => e.kind), ["start", "delta", "end"]);
    assert.deepEqual(live.filter((e) => e.kind === "phase").map((e) => (e as { phase: string }).phase), ["requesting", "working", "requesting", "responding"]);

    const [started] = starts(p.dump);
    assert.deepEqual(started.argv, [
      "app-server",
      "-c", "features.apps=false",
      "-c", "features.recommended_plugins=false",
      "-c", 'model_provider="opencode-go"',
      "-c", 'model_providers.opencode-go.base_url="https://opencode.ai/zen/go/v1"',
      "-c", 'model_providers.opencode-go.env_http_headers={"x-opencode-session"="OPENCODE_SESSION"}',
      "-c", 'model_providers.opencode-go.env_key="OPENCODE_GO_KEY"',
      "-c", 'model_providers.opencode-go.name="OpenCode Go"',
      "-c", 'model_providers.opencode-go.wire_api="responses"',
      "--listen", "stdio://",
    ]);
    assert.equal(started.env.CODEX_HOME, p.home);
    assert.equal(started.env.OPENAI_API_KEY, undefined);
    assert.equal(started.env.SSL_CERT_FILE, bundle);
    assert.equal(started.env.OPENCODE_GO_KEY, "k2");
    assert.equal(started.env.OPENCODE_SESSION, `stillfail-${p.id}`, "a codex route is its profile");

    const sent = stdin(p.dump);
    assert.deepEqual(sent[0], { id: 1, method: "initialize", params: { clientInfo: { name: "stillfail", version: "0" }, capabilities: { experimentalApi: true } } });
    assert.deepEqual(sent[1], { method: "initialized", params: {} });
    assert.deepEqual(sent[2], {
      id: 2,
      method: "thread/start",
      params: {
        cwd: data,
        approvalPolicy: "never",
        sandbox: "danger-full-access",
        developerInstructions: "be brief",
        config: {
          "mcp_servers.stillfail.url": "http://127.0.0.1:4750/mcp",
          "mcp_servers.stillfail.http_headers": { Authorization: "Bearer tok" },
          // A repository's rules told as its tools first touch it (test/repo-rules-hook.test.ts), trusted as given.
          hooks: {
            PostToolUse: [{ matcher: "*", hooks: [{ type: "command", command: REPO_RULES_COMMAND }] }],
            PostCompact: [{ hooks: [{ type: "command", command: REPO_RULES_COMMAND }] }],
          },
          bypass_hook_trust: true,
          model_reasoning_effort: "high",
          "skills.config": [{ path: join(skills, "mine", "SKILL.md"), enabled: false }],
        },
        model: "gpt-x",
      },
    });
    // Its connection to the station's tools asked after first.
    assert.deepEqual(sent[3], { id: 3, method: "mcpServerStatus/list", params: { threadId: session.id(), serverName: "stillfail", detail: "toolsAndAuthOnly" } });
    // Not a subscription: no service tier.
    assert.deepEqual(sent[4], { id: 4, method: "turn/start", params: { threadId: session.id(), input: [{ type: "text", text: "cmd" }] } });
    await session.dispose();
    assert.equal(stdin(p.dump).at(-1).method, "thread/unsubscribe");
  });

  test("a session kept to less context starts its thread compacting at it", async () => {
    const d = driver();
    const p = profile();
    const session = await d.open(options(p, { model: "gpt-x", context: 300_000 }), listen().push);
    const start = stdin(p.dump).find((m) => m.method === "thread/start");
    assert.equal(start.params.config.model_auto_compact_token_limit, 300_000);
    await session.dispose();
  });

  test("another model and effort go with the next turn/start; back to a default takes a new start", async () => {
    const d = driver();
    const p = profile();
    const { push, until } = listen();
    const session = await d.open(options(p, { model: "gpt-x", effort: "high" }), push);
    assert.ok(session.retune!(options(p, { model: "gpt-x", effort: "high" })), "as it runs: nothing to do");
    await session.prompt("cmd");
    await until(ended(1));
    assert.ok(session.retune!(options(p, { model: "gpt-y", effort: "low" })));
    await session.prompt("cmd");
    await until(ended(2));
    const turns = stdin(p.dump).filter((m) => m.method === "turn/start").map((m) => [m.params.model, m.params.effort]);
    assert.deepEqual(turns, [[undefined, undefined], ["gpt-y", "low"]]);
    assert.ok(!session.retune!(options(p, { model: "gpt-y" })), "no effort named: the thread's would stay");
    await session.dispose();
  });

  test("a failed turn is told apart by its codexErrorInfo", async () => {
    const d = driver();
    const { events, push, until } = listen();
    const session = await d.open(options(profile()), push);
    for (const [i, prompt] of ["fail:auth", "fail:rate", "fail:model"].entries()) {
      await session.prompt(prompt);
      await until(ended(i + 1));
    }
    assert.deepEqual(outcome(events, 0), { kind: "failed", reason: "auth", message: "unauthorized: token expired" });
    assert.deepEqual(outcome(events, 1), { kind: "failed", reason: "rate_limit", message: "usage limit reached" });
    assert.deepEqual(outcome(events, 2), { kind: "failed", reason: "model", message: "model not supported" });
    assert.equal(classifyCodexError(null), "model");
    assert.equal(classifyCodexError({ serverOverloaded: null }), "overloaded");
    assert.equal(classifyCodexError({ usageLimitExceeded: null }), "rate_limit");
    assert.equal(classifyCodexError(null, "auth error: 401, auth error code: token_revoked"), "auth");
    assert.equal(classifyCodexError(null, "model not supported"), "model");
    // Turned away with nothing said (2026-11-02, "unexpected status 403 Forbidden: "): refused, why not known; not the
    // model's error. Its region said, or Cloudflare's page for a blocked address: where it comes from.
    assert.equal(classifyCodexError({ responseStreamConnectionFailed: { httpStatusCode: 403 } }, "unexpected status 403 Forbidden: Unknown error"), "denied");
    assert.equal(classifyCodexError("other", "unexpected status 403 Forbidden: "), "denied");
    assert.equal(classifyCodexError({ responseStreamConnectionFailed: { httpStatusCode: 403 } }, "unexpected status 403 Forbidden: <!DOCTYPE html><title>Just a moment...</title>"), "blocked");
    assert.equal(classifyCodexError({ responseStreamConnectionFailed: { httpStatusCode: 401 } }, "unexpected status 401 Unauthorized: "), "auth");
    assert.equal(classifyCodexError({ responseStreamDisconnected: { httpStatusCode: null } }, "stream disconnected before completion"), "network");
    assert.equal(classifyCodexError(null, "stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses)"), "network");
    assert.equal(classifyCodexError("contextWindowExceeded", "Codex ran out of room in the model's context window"), "context");
  });

  test("abort interrupts the running turn by its id; steer adds to it, and is refused with nothing running", async () => {
    const d = driver();
    const p = profile();
    const { events, push, until } = listen();
    const session = await d.open(options(p), push);
    assert.equal(await session.steer("early"), false);
    await session.prompt("hold:1");
    await until((e) => deltas(e).length >= 1);
    assert.equal(await session.steer("more"), true);
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "completed" });
    assert.ok(deltas(events).includes("steer:more"));
    const steer = stdin(p.dump).find((m) => m.method === "turn/steer");
    assert.deepEqual(steer.params, { threadId: session.id(), input: [{ type: "text", text: "more" }], expectedTurnId: steer.params.expectedTurnId });
    assert.match(steer.params.expectedTurnId, /^tu-/);

    assert.deepEqual(deltas(events), ["d0 ", "steer:more"]);
    await session.prompt("hold:3");
    await until((e) => deltas(e).length >= 5);
    await session.abort();
    await until(ended(2));
    assert.deepEqual(outcome(events, 1), { kind: "aborted" });
    assert.deepEqual(deltas(events).slice(2), ["d0 ", "d1 ", "d2 "]);
    const interrupt = stdin(p.dump).find((m) => m.method === "turn/interrupt");
    assert.equal(interrupt.params.threadId, session.id());
    assert.match(interrupt.params.turnId, /^tu-/);
    await session.backgroundTools(); // nothing for codex
  });

  test("an interrupt rejected by the app-server is reported and can be retried", async () => {
    const d = driver();
    const p = profile({ env: { FAKE_INTERRUPT_FAIL_ONCE: "1" } });
    const { events, push, until } = listen();
    const session = await d.open(options(p), push);
    await session.prompt("hold:1");
    await until((e) => deltas(e).length >= 1);
    await assert.rejects(session.abort(), /interrupt failed/);
    assert.equal(session.busy(), true);
    await session.abort();
    await until(ended(1));
    assert.deepEqual(outcome(events), { kind: "aborted" });
  });

  test("a turn that starts without a prompt of ours is told as turnStarted; codex's own questions are refused", async () => {
    const d = driver();
    const p = profile();
    const { events, push, until } = listen();
    const session = await d.open(options(p), push);
    await session.prompt("again");
    await until(ended(2));
    assert.deepEqual(events.filter((e) => e.type !== "live").map((e) => e.type), ["turnEnded", "turnStarted", "turnEnded"]);
    await session.prompt("ask");
    await until(ended(3));
    assert.ok(stdin(p.dump).some((m) => m.id === "srv-1" && m.error?.code === -32601));
  });

  test("a thread resumed while loaded with its station tools failed is loaded again, with them", async () => {
    const d = driver();
    const p = profile();
    // Loaded while the station's door was closed: its MCP connection failed, and it stays loaded.
    const first = options(p, { mcpUrl: "http://127.0.0.1:1/mcp" });
    const before = await d.open(first, () => {});
    const { events, push, until } = listen();
    const session = await d.open(options(p, { key: first.key, resume: before.id() }), push);
    assert.equal(session.id(), before.id());
    await session.prompt("mcp");
    await until(ended(1));
    assert.deepEqual(deltas(events), ["connected"]);
    // Both times without the thread's history, which the reply would otherwise carry whole.
    assert.deepEqual(stdin(p.dump).filter((m) => m.method === "thread/resume").map((m) => m.params.excludeTurns), [true, true]);
  });

  test("a thread whose station tools failed starts no turn: opened again, resuming, it has them", async () => {
    const d = driver();
    const p = profile();
    // Opened while the station's door was closed: its MCP connection failed, so its turns would have no station tools.
    const first = options(p, { mcpUrl: "http://127.0.0.1:1/mcp" });
    const { events, push, until } = listen();
    const failed = await d.open(first, push);
    await assert.rejects(failed.prompt("mcp"), /station's tools failed/);
    assert.equal(failed.busy(), false);
    await failed.dispose();
    const session = await d.open(options(p, { key: first.key, resume: failed.id() }), push);
    await session.prompt("mcp");
    await until(ended(1));
    assert.deepEqual(deltas(events), ["connected"]);
  });

  test("the app-server exiting fails the thread's turn as exited and closes every thread on it", async () => {
    const d = driver();
    const p = profile();
    const a = listen();
    const b = listen();
    const one = await d.open(options(p), a.push);
    const two = await d.open(options(p), b.push);
    assert.equal(starts(p.dump).length, 1, "one app-server for the profile's threads");
    await one.prompt("exit");
    await a.until((e) => e.some((x) => x.type === "closed"));
    await b.until((e) => e.some((x) => x.type === "closed"));
    assert.deepEqual(a.events.filter((e) => e.type !== "live"), [
      { type: "turnEnded", outcome: { kind: "failed", reason: "exited", message: "codex app-server exited (4)" } },
      { type: "closed", why: "codex app-server exited (4)" },
    ]);
    assert.deepEqual(b.events, [{ type: "closed", why: "codex app-server exited (4)" }]);
    await assert.rejects(two.prompt("x"), /closed/);
    // The next session starts it again.
    const c = listen();
    const three = await d.open(options(p), c.push);
    await three.prompt("say:back");
    await c.until(ended(1));
    assert.equal(starts(p.dump).length, 2);
  });

  test("a profile edit restarts its app-server once no turn runs on it, its other threads opened again", async () => {
    const d = driver();
    const p = profile();
    const a = listen();
    const one = await d.open(options(p), a.push);
    await one.prompt("hold:1");
    await a.until((e) => deltas(e).length >= 1);
    const edited = { ...p, env: { ...(p.env as object), EXTRA: "1" } };
    const two = await d.open(options(edited), () => {});
    assert.equal(starts(p.dump).length, 1, "a turn runs on it: it keeps serving");
    await one.abort();
    await a.until(ended(1));
    // A thread opened on it meanwhile does not keep it: its next turn is refused, to be opened again on a new one.
    await assert.rejects(two.prompt("say:x"), /profile changed/);
    await two.dispose();
    const { push, until } = listen();
    const three = await d.open(options(edited), push);
    assert.equal(starts(p.dump).length, 2);
    assert.equal(starts(p.dump)[1].env.EXTRA, "1");
    await a.until((e) => e.some((x) => x.type === "closed"));
    await three.prompt("say:x");
    await until(ended(1));
  });

  test("codex updated under its app-server: replaced once no turn runs on it, its sessions opened again", async () => {
    let installed = "1.0.0";
    const d = driver({ installedVersion: async () => installed });
    const p = profile();
    writeFileSync(`${p.dump}.version`, "1.0.0");
    const a = listen();
    const b = listen();
    const one = await d.open(options(p), a.push);
    const two = await d.open(options(p), b.push);
    await one.prompt("hold:1");
    await a.until((e) => deltas(e).length >= 1);
    // Updated: the files of the one running are gone (its version is not the one installed now).
    installed = "2.0.0";
    writeFileSync(`${p.dump}.version`, "2.0.0");
    await d.runtimeChanged(false, true);
    assert.equal(starts(p.dump).length, 1, "a turn runs on it: it keeps serving");
    const c = listen();
    const three = await d.open(options(p), c.push);
    assert.equal(starts(p.dump).length, 2, "new threads use the updated host while the old turn finishes");
    await three.prompt("say:back");
    await c.until(ended(1));
    await one.abort();
    await a.until(ended(1));
    // The turn over, it is replaced: its threads closed, to be opened again with their next turn.
    await a.until((e) => e.some((x) => x.type === "closed"));
    await b.until((e) => e.some((x) => x.type === "closed"));
    assert.equal(starts(p.dump).length, 2);
  });

  test("a same-version replacement waits for its turn and starts a new app-server", async () => {
    const d = driver({ installedVersion: async () => "1.0.0" });
    const p = profile();
    writeFileSync(`${p.dump}.version`, "1.0.0");
    const a = listen();
    const one = await d.open(options(p), a.push);
    await one.prompt("hold:1");
    await a.until((e) => deltas(e).length >= 1);

    // A repaired installation can have the same version while its executable and helpers have changed.
    await d.runtimeChanged(true);
    const b = listen();
    const next = d.open(options(p), b.push);
    assert.equal(starts(p.dump).length, 1, "the running turn is not interrupted");
    assert.equal(await one.steer("finish"), true);
    await a.until(ended(1));
    assert.equal(outcome(a.events).kind, "completed");
    const two = await next;
    assert.equal(starts(p.dump).length, 2);
    await two.prompt("say:back");
    await b.until(ended(1));
    assert.equal(outcome(b.events).kind, "completed");
  });

  test("an app-server whose output has grown long is replaced once its turn ends, its sessions opened again", async () => {
    // Every app-server has written more than this by its first turn's end.
    const d = driver({ outputLimit: 1 });
    const p = profile();
    const a = listen();
    const one = await d.open(options(p), a.push);
    await one.prompt("say:x");
    await a.until(ended(1));
    await a.until((e) => e.some((x) => x.type === "closed"));
    const b = listen();
    const two = await d.open(options(p), b.push);
    assert.equal(starts(p.dump).length, 2);
    await two.prompt("say:back");
    await b.until(ended(1));
  });

  test("a turn asked of an app-server Codex was updated under is refused, so it is opened again on a new one", async () => {
    // Codex updated from outside the station, while the app-server started: it runs the old one.
    const d = driver({ installedVersion: async () => "2.0.0" });
    const p = profile();
    writeFileSync(`${p.dump}.version`, "1.0.0");
    const one = await d.open(options(p), () => {});
    writeFileSync(`${p.dump}.version`, "2.0.0");
    await assert.rejects(one.prompt("say:x"), /updated/);
    await one.dispose();
    const { push, until } = listen();
    const two = await d.open(options(p), push);
    assert.equal(starts(p.dump).length, 2);
    await two.prompt("say:x");
    await until(ended(1));
  });

  test("a subscription's turns say their service tier; models and rate limits come from the app-server", async () => {
    let fast: boolean | undefined = true;
    const d = driver({ fast: () => fast });
    const p = profile({ access: { kind: "subscription" } });
    const { push, until } = listen();
    const session = await d.open(options(p), push);
    await session.prompt("say:a");
    await until(ended(1));
    fast = undefined;
    await session.prompt("say:b");
    await until(ended(2));
    const tiers = stdin(p.dump).filter((m) => m.method === "turn/start").map((m) => m.params.serviceTier);
    assert.deepEqual(tiers, ["fast", null], "an explicit null clears a tier chosen before");
    const started = starts(p.dump)[0];
    assert.deepEqual(started.argv, ["app-server", "-c", "features.apps=false", "-c", "features.recommended_plugins=false", "--listen", "stdio://"]);
    const catalog = await d.models(p);
    assert.deepEqual(catalog.models, ["gpt-a", "legacy"]);
    assert.deepEqual(catalog.efforts.get("gpt-a"), ["low", "high"]);
    assert.deepEqual(await d.rateLimits(p), { rateLimits: { primary: { usedPercent: 5 } } });
    // Its login renewed by the app-server that runs on it (it holds the refresh token); none on another profile.
    assert.equal(await d.renewLogin(p.id), true);
    assert.deepEqual(stdin(p.dump).filter((m) => m.method === "account/read").map((m) => m.params), [{ refreshToken: true }]);
    assert.equal(await d.renewLogin("none-runs-on-it"), false);
  });

  for (const crashed of [false, true]) {
    test(`a next driver takes the threads up ${crashed ? "after a crash (no snapshot)" : "from their snapshots"}: each turn ends once, no live event twice`, async () => {
      const first = driver();
      const p = profile();
      p.env = { ...(p.env as Record<string, string>), FAKE_ROLLOUT: "1" };
      const a = listen();
      const a2 = listen();
      const one = await first.open(options(p), a.push);
      const two = await first.open(options(p), a2.push);
      const [gateOne, gateTwo] = [gates(p.dump, "one"), gates(p.dump, "two")];
      await one.prompt("gate:12:4:one");
      await two.prompt("gate:14:4:two");
      await a.until((e) => deltas(e).length >= 4);
      await a2.until((e) => deltas(e).length >= 4);
      // A request in flight as it lets go: its reply goes to the next driver, which drops it.
      const steering = one.steer("late");
      let snapshots: unknown[] = [null, null];
      if (!crashed) {
        snapshots = JSON.parse(JSON.stringify([one.snapshot(), two.snapshot()]));
        assert.equal((snapshots[0] as { transcriptPath: string }).transcriptPath, join(p.home, "sessions", "2026", "11", "03", `rollout-${one.id()}.jsonl`));
      }
      first.detach();
      // (the station let go before the next takes up, as the hub waits: every line handled acknowledged)
      await allLeft();
      assert.equal(await steering, false, "its reply is the next station's");
      // The app-server has the steer; the first turn says the rest of its reply with nobody reading.
      await eventually(() => stdin(p.dump).some((m) => m.method === "turn/steer"));
      await gateOne.open("a");
      await eventually(gateOne.said);
      const next = driver();
      const b = listen();
      const b2 = listen();
      const takenOne = await next.adopt(options(p, { resume: one.id() }), snapshots[0], b.push);
      // The second is taken up later: what came for it meanwhile (the rest of its reply) waits for it.
      await gateTwo.open("a");
      await eventually(gateTwo.said);
      const takenTwo = await next.adopt(options(p, { resume: two.id() }), snapshots[1], b2.push);
      assert.equal(takenOne.id(), one.id());
      await Promise.all([gateOne.open("b"), gateTwo.open("b")]);
      await b.until(ended(1));
      await b2.until(ended(1));
      for (const [before, now, count] of [[a, b, 12], [a2, b2, 14]] as const) {
        const all = [...before.events, ...now.events];
        assert.equal(ends(all).length, 1, "the turn's end, once");
        assert.deepEqual(outcome(now.events), { kind: "completed" });
        const said = deltas(all).filter((t) => !t.startsWith("steer:"));
        assert.deepEqual(said, Array.from({ length: count }, (_, i) => `d${i} `), "every delta once, in order");
        assert.equal(all.filter((e) => e.type === "live" && e.event.kind === "start").length, 1);
        assert.equal(all.filter((e) => e.type === "live" && e.event.kind === "end").length, 1);
        assert.equal(now.events.filter((e) => e.type === "turnStarted").length, crashed ? 1 : 0);
      }
      assert.ok(deltas([...a.events, ...b.events]).includes("steer:late"), "the steer itself reached the turn");
      assert.equal(starts(p.dump).length, 1, "the same app-server");
      // It goes on: new requests on the app-server taken up.
      await takenOne.prompt("say:after");
      await b.until(ended(2));
      assert.deepEqual(outcome(b.events, 1), { kind: "completed" });
      assert.ok(!a.events.some((e) => e.type === "closed"));
    });
  }

  // On ccvm (2026-11-04) a profile's app-server, shared by its chats, went 19 hours without a moment no turn ran on it:
  // replaced only once idle, it never was, its output 4.9 GB.
  for (const after of ["", "handed over", "a crash"] as const) {
    test(`an app-server outgrown with a turn running all the while is replaced: new turns go to a new one, its own ends there${after ? `, ${after} meanwhile` : ""}`, async () => {
      const d = driver();
      const p = profile();
      const a = listen();
      const b = listen();
      const long = await d.open(options(p), a.push);
      const idle = await d.open(options(p), b.push);
      const gate = gates(p.dump, `drain${after.length}`);
      await long.prompt(`gate:6:3:drain${after.length}`);
      await a.until((e) => deltas(e).length >= 3);
      // Its output past the limit from now on (every app-server has written more than this by now).
      (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
      // Another's turn ends while that one runs: the app-server is replaced now, the one with no turn let go of.
      await idle.prompt("say:x");
      await b.until((e) => e.some((x) => x.type === "closed"));
      const old = existingRunners(data).find((r) => r.id === runnerId("codex", p.id))!;
      const c = listen();
      const fresh = await d.open(options(p), c.push);
      assert.equal(starts(p.dump).length, 2, "a new app-server for new turns");
      const now = existingRunners(data).find((r) => r.id.startsWith(`${old.id}.`));
      assert.ok(now, "under a runner of its own, the one being replaced keeping its");
      let x = a;
      let ending = long;
      if (after !== "") {
        const snapshots = after === "handed over" ? JSON.parse(JSON.stringify([long.snapshot(), fresh.snapshot()])) : [null, null];
        d.detach();
        await allLeft();
        const next = driver({ outputLimit: 1 });
        x = listen();
        ending = await next.adopt(options(p, { resume: long.id() }), snapshots[0], x.push);
        await next.adopt(options(p, { resume: fresh.id() }), snapshots[1], () => {});
      }
      await gate.open("a");
      await eventually(gate.said);
      await gate.open("b");
      await x.until(ended(1));
      assert.deepEqual(deltas([...a.events, ...(x === a ? [] : x.events)]), Array.from({ length: 6 }, (_, i) => `d${i} `), "its turn to the end, once, on the one being replaced");
      assert.deepEqual(outcome(x.events), { kind: "completed" });
      // Its last turn over: it is let go of, and ends with its runner (its output gone with it).
      await x.until((e) => e.some((y) => y.type === "closed"));
      await eventually(() => !existingRunners(data).some((r) => r.id === old.id));
      assert.equal(starts(p.dump).length, 2, "none started for its turn");
      void ending;
      if (after === "") {
        await fresh.prompt("say:y");
        await c.until(ended(1));
      }
    });
  }

  for (const after of ["", "handed over", "a crash"] as const) {
    test(`a thread let go of by an app-server being replaced takes its next turn on the new one, once that one let go of it${after ? `, ${after} meanwhile` : ""}`, async () => {
      const d = driver();
      const p = profile();
      const a = listen();
      const b = listen();
      const long = await d.open(options(p), a.push);
      const idle = await d.open(options(p), b.push);
      const gate = gates(p.dump, `held${after.length}`);
      const unsub = gates(p.dump, "unsub");
      await long.prompt(`gate:6:3:held${after.length}`);
      await a.until((e) => deltas(e).length >= 3);
      (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
      await idle.prompt("say:x");
      await b.until((e) => e.some((x) => x.type === "closed"));
      // Its unsubscribe held: a turn asked of it now is refused (as the session does, it is opened again)...
      await assert.rejects(idle.prompt("say:again"), /closed|being replaced/);
      let now = d;
      let x = a;
      if (after !== "") {
        const snapshot = after === "handed over" ? JSON.parse(JSON.stringify(long.snapshot())) : null;
        d.detach();
        await allLeft();
        now = driver();
        x = listen();
        await now.adopt(options(p, { resume: long.id() }), snapshot, x.push);
      }
      let opened = false;
      const c = listen();
      const reopening = now.open(options(p, { resume: idle.id() }), c.push).then((s) => ((opened = true), s));
      // After a crash nothing says it was being replaced: taken up as the key's app-server, the thread resumes on it
      // (the same process: nothing to let go of), and it is replaced at its next turn's end.
      if (after !== "a crash") {
        await sleep(300);
        assert.equal(opened, false, "resumed elsewhere only once the one being replaced let go of it");
      }
      await unsub.open("a");
      const again = await reopening;
      await again.prompt("say:again");
      await c.until(ended(1));
      assert.deepEqual(outcome(c.events), { kind: "completed" });
      if (after !== "a crash") assert.ok((again as unknown as { host: { proc: { info: { id: string } } } }).host.proc.info.id.includes("."), "on the new app-server");
      // ...and the turn running all the while ends there, uninterrupted.
      await gate.open("a");
      await eventually(gate.said);
      await gate.open("b");
      await x.until(ended(1));
      assert.deepEqual(outcome(x.events), { kind: "completed" });
      assert.deepEqual(deltas([...a.events, ...(x === a ? [] : x.events)]), Array.from({ length: 6 }, (_, i) => `d${i} `));
    });
  }

  test("handed over with no session on the app-server being replaced, its threads still being let go of: one is resumed elsewhere only once it is", async () => {
    const d = driver();
    const p = profile();
    const a = listen();
    const b = listen();
    const long = await d.open(options(p), a.push);
    const idle = await d.open(options(p), b.push);
    const gate = gates(p.dump, "none");
    const unsub = gates(p.dump, "unsub");
    await long.prompt("gate:4:2:none");
    await a.until((e) => deltas(e).length >= 2);
    (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
    await idle.prompt("say:x");
    await b.until((e) => e.some((x) => x.type === "closed"));
    const fresh = await d.open(options(p), () => {});
    await gate.open("a");
    await eventually(gate.said);
    await gate.open("b");
    await a.until((e) => e.some((x) => x.type === "closed"));
    // Every session off it, its unsubscribes held: handed over, only the new one's session says where it runs.
    const old = existingRunners(data).find((r) => r.id === runnerId("codex", p.id))!;
    const snapshot = JSON.parse(JSON.stringify(fresh.snapshot()));
    d.detach();
    await allLeft();
    // Its output not to be read again (held only: none of its turns runs on): it cannot be opened now, its runner
    // writing on through the descriptor it holds.
    const out = join(data, "run", "runners", `${old.id}.out`);
    fs.chmodSync(out, 0);
    const next = driver();
    await next.adopt(options(p, { resume: fresh.id() }), snapshot, () => {});
    let opened = false;
    const c = listen();
    const reopening = next.open(options(p, { resume: idle.id() }), c.push).then((s) => ((opened = true), s));
    await sleep(300);
    assert.equal(opened, false, "the one left being replaced found and asked first");
    await unsub.open("a");
    const again = await reopening;
    fs.chmodSync(out, 0o600);
    await again.prompt("say:again");
    await c.until(ended(1));
    assert.deepEqual(outcome(c.events), { kind: "completed" });
  });

  test("a thread the app-server being replaced will not let go of is not resumed elsewhere", async () => {
    const d = driver();
    const p = profile();
    const a = listen();
    const b = listen();
    const long = await d.open(options(p), a.push);
    const idle = await d.open(options(p), b.push);
    const gate = gates(p.dump, "refuse");
    await long.prompt("gate:4:2:refuse");
    await a.until((e) => deltas(e).length >= 2);
    writeFileSync(`${p.dump}.unsub.fail`, "");
    (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
    await idle.prompt("say:x");
    await b.until((e) => e.some((x) => x.type === "closed"));
    await assert.rejects(d.open(options(p, { resume: idle.id() }), () => {}), /did not let go of its thread/);
    rmSync(`${p.dump}.unsub.fail`);
    const c = listen();
    const again = await d.open(options(p, { resume: idle.id() }), c.push);
    await again.prompt("say:again");
    await c.until(ended(1));
    await gate.open("a");
    await eventually(gate.said);
    await gate.open("b");
    await a.until(ended(1));
  });

  test("an app-server being replaced, slow to go once its last turn ends, is not taken up again by a host asked for meanwhile", async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_TERM_MS: "1500" };
    const a = listen();
    const b = listen();
    const long = await d.open(options(p), a.push);
    const idle = await d.open(options(p), b.push);
    const gate = gates(p.dump, "slow");
    await long.prompt("gate:4:2:slow");
    await a.until((e) => deltas(e).length >= 2);
    (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
    await idle.prompt("say:x");
    await b.until((e) => e.some((x) => x.type === "closed"));
    // Being replaced now; the new one within the limit (else it too is replaced, once idle).
    (d as unknown as { options: CodexDriverOptions }).options.outputLimit = undefined;
    const old = existingRunners(data).find((r) => r.id === runnerId("codex", p.id))!;
    await gate.open("a");
    await eventually(gate.said);
    await gate.open("b");
    await a.until(ended(1));
    // Its last turn over, it is going (slowly): a session opened now goes to an app-server of its own.
    const c = listen();
    const fresh = await d.open(options(p), c.push);
    assert.notEqual((fresh as unknown as { host: { proc: { info: RunnerInfo } } }).host.proc.info.runner, old.runner, "not the one going");
    await fresh.prompt("say:y");
    await c.until(ended(1));
    assert.deepEqual(outcome(c.events), { kind: "completed" });
    // (the new one may have its runner id now that the old one is gone: told apart by the runner's pid)
    await eventually(() => !existingRunners(data).some((r) => r.runner === old.runner));
    assert.ok(!c.events.some((e) => e.type === "closed"), "not killed under it");
  });

  test("a turn asked as an idle app-server is being replaced does not begin on it: opened again elsewhere", async () => {
    const d = driver();
    const p = profile();
    p.env = { ...(p.env as Record<string, string>), FAKE_TERM_MS: "1500" };
    const a = listen();
    const b = listen();
    const one = await d.open(options(p), a.push);
    const two = await d.open(options(p), b.push);
    const gate = gates(p.dump, "last");
    await one.prompt("gate:2:1:last");
    await a.until((e) => deltas(e).length >= 1);
    // The other's turn asked, held where it looks at its thread's tools (its last await)...
    const mcp = gates(p.dump, "mcp");
    const asked = two.prompt("say:b").then(() => "began", (e: Error) => e.message);
    await sleep(200);
    // ...while the last turn ends, the app-server outgrown: idle, it is replaced (slow to go).
    (d as unknown as { options: CodexDriverOptions }).options.outputLimit = 1;
    await gate.open("a");
    await eventually(gate.said);
    await gate.open("b");
    await a.until(ended(1));
    await sleep(200);
    await mcp.open("a");
    assert.match(await asked, /being replaced|closed/, "refused, to be opened again on a new one");
    assert.ok(!b.events.some((e) => e.type === "turnEnded"), "no turn begun there to be cut short");
  });

  // On ccvm (2026-11-04) a station that crashed left two app-servers; the next read each one's output again from its
  // start (157 MB, the station's thread held 10 s; the other's was 4.9 GB), though only the turns running said anything
  // that still stood.
  test("after a crash an app-server's output is read again from where the earliest turn running began, not from its start", async () => {
    const first = driver();
    const p = profile();
    const a = listen();
    const a2 = listen();
    const one = await first.open(options(p), a.push);
    const two = await first.open(options(p), a2.push);
    await one.prompt("say:before");
    await a.until(ended(1));
    const info = existingRunners(data).find((r) => r.id === runnerId("codex", p.id))!;
    // Where the last turn of a thread began in the output as it is now.
    const began = (thread: string) => {
      const out = readFileSync(join(data, "run", "runners", `${info.id}.out`));
      let at = 0;
      let found = -1;
      for (let i = out.indexOf(10); i >= 0; at = i + 1, i = out.indexOf(10, at)) {
        if (out[at] !== 0x7b || out.subarray(at, i).indexOf("turn/started") < 0) continue;
        const msg = JSON.parse(out.toString("utf8", at, i));
        if (msg?.params?.threadId === thread) found = at;
      }
      return found;
    };
    const gate = gates(p.dump, "kept");
    await two.prompt("gate:6:3:kept");
    await a2.until((e) => deltas(e).length >= 3);
    // Another turn ends while that one runs, saying more than the runner gives back at once (32 MiB, native/runner
    // `punch`): reading again still begins where that one began, and the runner keeps it.
    await one.prompt(`say:${"x".repeat(34 * 1024 * 1024)}`);
    await a.until(ended(2));
    assert.ok(began(two.id()) > 0);
    assert.equal(info.keeps, true, "the runner says it keeps what the station keeps");
    first.detach();
    await allLeft();
    // The runner says what was acknowledged and kept, both from the last ack: from where the turn running began.
    const out = join(data, "run", "runners", `${info.id}.out`);
    assert.equal((await ackedOffset(info, out)).keep, began(two.id()), "from where the turn running began");
    await gate.open("a");
    await eventually(gate.said);
    const next = driver();
    const b = listen();
    const b2 = listen();
    await next.adopt(options(p, { resume: one.id() }), null, b.push);
    const takenTwo = await next.adopt(options(p, { resume: two.id() }), null, b2.push);
    await gate.open("b");
    await b2.until(ended(1));
    const all = [...a2.events, ...b2.events];
    assert.equal(ends(all).length, 1, "its end, once");
    assert.deepEqual(deltas(all), Array.from({ length: 6 }, (_, i) => `d${i} `), "every delta once, in order");
    assert.equal(b2.events.filter((e) => e.type === "turnStarted").length, 1, "read again as running");
    assert.equal(b.events.filter((e) => e.type === "turnStarted").length, 0, "the one whose turns had ended, idle");
    // None running now: reading again begins past it.
    const twoBegan = began(two.id());
    await takenTwo.prompt("say:after");
    await b2.until(ended(2));
    next.detach();
    await allLeft();
    const now = await ackedOffset(info, out);
    assert.ok(now.keep !== null && now.keep > twoBegan && now.keep <= now.at, `${twoBegan} < ${now.keep} <= ${now.at}`);
    // Taken up once more, so the driver's shutdown ends it.
    await driver().adopt(options(p, { resume: two.id() }), null, () => {});
  });

  // On a station (2026-11-02) a next station asked a profile's quota as it started: it took the app-server up as after a
  // crash, from the station still handing over, which let go of the turn running on it.
  test("a next driver takes no app-server up before the station before it is taken up: that one hears its turn to the end", { timeout: 60_000 }, async () => {
    const first = driver();
    const p = profile();
    const a = listen();
    const one = await first.open(options(p), a.push);
    const gate = gates(p.dump, "early");
    await one.prompt("gate:6:3:early");
    await a.until((e) => deltas(e).length >= 3);
    // The next station asks the profile's quota as it starts, before what the one before left is taken up: it does not
    // so much as look for an app-server yet.
    const taken = Promise.withResolvers<void>();
    let looked = false;
    const next = driver({ takenUp: taken.promise, installedVersion: async () => ((looked = true), null) });
    const quota = next.rateLimits(p);
    await new Promise((r) => setImmediate(r));
    assert.equal(looked, false, "no app-server looked for before the station before is taken up");
    await gate.open("a");
    await eventually(gate.said);
    await gate.open("b");
    await a.until(ended(1));
    assert.deepEqual(deltas(a.events), Array.from({ length: 6 }, (_, i) => `d${i} `), "all of its turn, to the station before");
    // That one hands over: its snapshot, its runner let go; the next takes the session up from it, then the rest.
    const snapshot = JSON.parse(JSON.stringify(one.snapshot()));
    first.detach();
    await allLeft();
    const b = listen();
    const again = await next.adopt(options(p, { resume: one.id() }), snapshot, b.push);
    taken.resolve();
    assert.deepEqual(await quota, { rateLimits: { primary: { usedPercent: 5 } } });
    await again.prompt("say:after");
    await b.until(ended(1));
    assert.deepEqual(outcome(b.events), { kind: "completed" });
    assert.equal(starts(p.dump).length, 1, "the same app-server");
  });

  test("an app-server's output read again after a crash lets the main thread go and says it gets on with it", async () => {
    const said: number[] = [];
    let turns = 0;
    const d = driver({ taking: () => { said.push(turns); setImmediate(() => turns++); } });
    const p = profile();
    const id = "codex-reread";
    mkdirSync(dirname(outFile(data, id)), { recursive: true });
    writeFileSync(outFile(data, id), '{"method":"item/started","params":{"threadId":"t"}}\n'.repeat(10_000));
    try {
      // No runner behind it: all the file is read, then taking it up goes no further, which is not this test's.
      await (d as any).takeUp(p, { id, socket: join(data, "no-such.sock"), args: [] }).catch(() => {});
    } finally {
      await d.shutdown();
    }
    assert.deepEqual(said, [0, 1], "once per 4096 lines, the main thread let go after each");
  });

  test("an app-server's output of long lines read again after a crash says it gets on with it by the bytes gone by", async () => {
    let said = 0;
    const d = driver({ taking: () => void said++, takeUpBytes: 2 << 20 });
    const p = profile();
    const id = "codex-reread-long";
    mkdirSync(dirname(outFile(data, id)), { recursive: true });
    // Four lines of 2 MB each, what a station passes over: far fewer than 4096 lines, four times the step.
    const line = `{"method":"turn/diff/updated","params":{"threadId":"t","diff":"${"x".repeat((2 << 20) - 64)}"}}\n`;
    writeFileSync(outFile(data, id), line.repeat(4));
    try {
      await (d as any).takeUp(p, { id, socket: join(data, "no-such.sock"), args: [] }).catch(() => {});
    } finally {
      await d.shutdown();
    }
    assert.ok(said >= 2, `told ${said} times over ${line.length * 4} bytes`);
  });

  test("shutdown ends the app-servers and their runners", async () => {
    const d = new CodexDriver({ data, hostSkills: skills, caBundle: bundle });
    const p = profile();
    await d.open(options(p), () => {});
    const pid = starts(p.dump)[0].pid;
    await d.shutdown();
    const alive = () => {
      try {
        process.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    };
    await eventually(() => !alive() && !existingRunners(data).some((r) => r.pid === pid));
    assert.throws(() => process.kill(pid, 0));
    assert.ok(!existingRunners(data).some((r) => r.pid === pid));
  });
});

// Alone: the station's variables are the whole process's, and every app-server above would be out of date under them.
describe("the Codex driver under the station's variables", () => {
  test("the station's variables for its agents: an app-server starts with them, again once idle when they change; a profile's own win", async (t) => {
    t.after(() => readAgentEnvFrom(() => null));
    let raw: any = {};
    readAgentEnvFrom(() => raw);
    const d = driver();
    const p = profile({ env: { FAKE_DUMP: "", MINE: "profile's" } });
    (p.env as Record<string, string>).FAKE_DUMP = p.dump;
    const one = await d.open(options(p), () => {});
    await one.dispose();
    assert.equal(starts(p.dump)[0].env.HTTPS_PROXY, undefined);
    raw = { agentEnv: { HTTPS_PROXY: "http://127.0.0.1:7890", MINE: "station's" } };
    const { push, until } = listen();
    const two = await d.open(options(p), push);
    assert.equal(starts(p.dump).length, 2);
    const env = starts(p.dump)[1].env;
    assert.equal(env.HTTPS_PROXY, "http://127.0.0.1:7890");
    assert.match(env.NO_PROXY, /(^|,)127\.0\.0\.1(,|$)/);
    assert.equal(env.MINE, "profile's");
    await two.prompt("say:x");
    await until(ended(1));
  });
});
